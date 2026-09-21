-- Field Journal: the one-time migration from the pre-AceDB saved shape.
--
-- Before this plan the addon kept everything in an account-wide FieldJournalDB
-- with per-character sub-tables keyed "<realm>:<character>", mirrored into a
-- per-character FieldJournalCharacterDB, plus three hand-added recovery
-- globals (FieldJournalRecoveryDB / DB2 / DB3) that were merged in on every
-- single load. AceDB now owns FieldJournalDB and exposes only the logged-in
-- character's slot as db.char, so this file copies the old shape into db.char
-- once and then stops reading it (the legacyMigrated flag guards the pass).
--
-- Only the CURRENT character is migrated. That is safe because AceDB never
-- deletes top-level keys it does not own: initdb only adds to the saved table
-- and its PLAYER_LOGOUT handler only prunes inside the sections listed in
-- db.keys. The legacy characters/encounters/diaryEvents/craftEvents/bestiary/
-- objectiveStates/questBookmarks tables therefore stay on disk next to
-- AceDB's own shape, and every other character migrates itself the first time
-- it logs in after this update.
--
-- The merge rules below are the ones this addon has used in production since
-- 0.7.1 and they are deliberately unchanged: identity-keyed de-duplication,
-- an existing entry is never overwritten, and bestiary kills / order / place
-- counts / drop counts reconcile by taking the maximum. Only the destination
-- changed -- one flat per-character table instead of db.<collection>[key].
--
-- Nothing here may throw. A malformed legacy collection must be skipped with a
-- chat message, leaving that collection as it was, and must never break addon
-- load. The three recovery globals are read-only; we never write or clear them.

local FieldJournal = select(2, ...)

local Migrations = {}
FieldJournal.Migrations = Migrations

local function protect(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        print("Field Journal: skipped unreadable legacy " .. label .. " (" .. tostring(err) .. ").")
    end
    return ok
end

-- Ported byte-for-byte from Core/Bootstrap.lua.
local function mergeList(target, source, identity)
    if type(source) ~= "table" then return end
    local seen = {}
    for _, record in ipairs(target) do
        local id = identity(record)
        if id then seen[id] = true end
    end
    for _, record in ipairs(source) do
        local id = identity(record)
        if id and not seen[id] then
            target[#target + 1] = record
            seen[id] = true
        end
    end
    table.sort(target, function(a, b) return (a.order or a.seenAt or 0) < (b.order or b.seenAt or 0) end)
end

-- Ported byte-for-byte from the closure inside the old
-- mergeCharacterCollections; hoisted to file scope so both event collections
-- share the one definition.
local function eventIdentity(item)
    return table.concat({tostring(item.key), tostring(item.seenAt),
        tostring(item.sourceGUID), tostring(item.itemID)}, "\031")
end

-- guid alone is not a stable identity across migration sources: WoW creature
-- GUIDs get reused after a creature respawns at the same spawn point over
-- long timescales, and the addon's own in-session duplicate guard
-- (recentDeaths in Data/Bestiary.lua) is memory-only and never persisted. Two
-- genuinely distinct historical encounters (weeks apart, at a respawned
-- creature) can legitimately share a guid, so seenAt must be part of the
-- identity too -- this mirrors eventIdentity's reasoning above.
local function encounterIdentity(item)
    if item.guid == nil then return nil end
    return tostring(item.guid) .. "\031" .. tostring(item.seenAt)
end

local function mergeEntries(target, source)
    target.entries = target.entries or {}
    if type(source) ~= "table" then return end
    for entryKey, entry in pairs(source) do
        if not target.entries[entryKey] then target.entries[entryKey] = entry end
    end
end

local function mergeEncounters(target, source)
    target.encounters = target.encounters or {}
    mergeList(target.encounters, source, encounterIdentity)
end

local function mergeDiaryEvents(target, source)
    target.diaryEvents = target.diaryEvents or {}
    mergeList(target.diaryEvents, source, eventIdentity)
end

local function mergeCraftEvents(target, source)
    target.craftEvents = target.craftEvents or {}
    mergeList(target.craftEvents, source, eventIdentity)
end

local function mergeBestiary(target, source)
    target.bestiary = target.bestiary or {}
    if type(source) ~= "table" then return end
    for beastKey, incoming in pairs(source) do
        if type(incoming) == "table" then
            local beast = target.bestiary[beastKey]
            if not beast then
                target.bestiary[beastKey] = incoming
            else
                beast.kills = math.max(beast.kills or 0, incoming.kills or 0)
                beast.order = math.max(beast.order or 0, incoming.order or 0)
                if not beast.name or beast.name:find("^Unidentified creature") then
                    beast.name = incoming.name
                end
                beast.places = beast.places or {}
                for place, location in pairs(incoming.places or {}) do
                    local existing = beast.places[place]
                    if not existing or (existing.count or 0) < (location.count or 0) then
                        beast.places[place] = location
                    end
                end
                beast.drops = beast.drops or {}
                for itemKey, drop in pairs(incoming.drops or {}) do
                    local existing = beast.drops[itemKey]
                    if not existing or (existing.count or 0) < (drop.count or 0) then
                        beast.drops[itemKey] = drop
                    end
                end
            end
        end
    end
end

-- objectiveState and questBookmarks were never part of the old merge logic:
-- mergeCharacterCollections only handled the five collections above, because
-- the recovery snapshots it was written for only carried those five. The new
-- db.char owns both, and losing a player's quest bookmarks or their in-flight
-- objective progress on migration would be a real regression, so they get a
-- plain fill-only copy here. An existing value always wins.
local function mergeMap(target, field, source)
    target[field] = target[field] or {}
    if type(source) ~= "table" then return end
    for key, value in pairs(source) do
        if target[field][key] == nil then target[field][key] = value end
    end
end

-- A whole top-level source field (e.g. source.entries) being present but not
-- a table means that entire legacy collection is unreadable -- distinct from
-- an otherwise-valid collection containing one malformed record, which stays
-- silent (that would be noisier and is not what this warning covers).
local function warnIfMalformed(label, fieldName, value)
    if value ~= nil and type(value) ~= "table" then
        print("Field Journal: skipped malformed legacy " .. label .. " " .. fieldName
            .. " (expected a table, got " .. type(value) .. ").")
    end
end

--- Merges one flat source table into one flat per-character table.
--  Each collection is merged behind its own pcall, so one unreadable
--  collection cannot stop the other six.
--  @param target  the destination (db.char, or a plain table under test)
--  @param source  {entries, encounters, diaryEvents, craftEvents, bestiary,
--                  objectiveState, questBookmarks} -- any field may be absent
--  @param label   what to name this source in a chat warning
local function mergeIntoCharacter(target, source, label)
    if type(target) ~= "table" or type(source) ~= "table" then return end
    label = tostring(label or "saved data")
    warnIfMalformed(label, "characters", source.entries)
    warnIfMalformed(label, "encounters", source.encounters)
    warnIfMalformed(label, "diary events", source.diaryEvents)
    warnIfMalformed(label, "craft events", source.craftEvents)
    warnIfMalformed(label, "bestiary", source.bestiary)
    warnIfMalformed(label, "objectiveStates", source.objectiveState)
    warnIfMalformed(label, "quest bookmarks", source.questBookmarks)
    protect(label .. " entries", mergeEntries, target, source.entries)
    protect(label .. " encounters", mergeEncounters, target, source.encounters)
    protect(label .. " diary events", mergeDiaryEvents, target, source.diaryEvents)
    protect(label .. " craft events", mergeCraftEvents, target, source.craftEvents)
    protect(label .. " bestiary", mergeBestiary, target, source.bestiary)
    protect(label .. " objective state", mergeMap, target, "objectiveState", source.objectiveState)
    protect(label .. " quest bookmarks", mergeMap, target, "questBookmarks", source.questBookmarks)
end

--- Ported from Core/Bootstrap.lua's savedCharacterKey(), with the account
--  table passed in instead of read off FieldJournal.db (which is now the AceDB
--  object). The old saves are keyed "<realm>:<character>", and a realm rename
--  during this beta left some installs with a stale realm prefix. Prefer the
--  exact current key; otherwise accept a single old key ending in
--  ":<character>"; never guess when two or more match.
function Migrations.legacyCharacterKey(account)
    local key = FieldJournal.characterKey()
    if type(account) ~= "table" or type(account.characters) ~= "table" or account.characters[key] then
        return key
    end
    local name = UnitName("player")
    if not name or name == "" then return key end
    local suffix = ":" .. name
    local found
    for oldKey in pairs(account.characters) do
        if type(oldKey) == "string" and oldKey:sub(-#suffix) == suffix then
            if found then return key end
            found = oldKey
        end
    end
    return found or key
end

--- Reshapes an account-wide legacy table (FieldJournalDB or any of the three
--  recovery snapshots -- they all share the same shape) into the flat
--  per-character shape mergeIntoCharacter expects.
function Migrations.accountSlice(account, key)
    if type(account) ~= "table" then return nil end
    local function at(field)
        local collection = account[field]
        if type(collection) ~= "table" then return nil end
        return collection[key]
    end
    return {
        entries = at("characters"),
        encounters = at("encounters"),
        diaryEvents = at("diaryEvents"),
        craftEvents = at("craftEvents"),
        bestiary = at("bestiary"),
        objectiveState = at("objectiveStates"),
        questBookmarks = at("questBookmarks"),
    }
end

function Migrations.counts(charData)
    local entries, species = 0, 0
    if type(charData) == "table" then
        for _ in pairs(charData.entries or {}) do entries = entries + 1 end
        for _ in pairs(charData.bestiary or {}) do species = species + 1 end
        return {
            entries = entries,
            encounters = #(charData.encounters or {}),
            diaryEvents = #(charData.diaryEvents or {}),
            craftEvents = #(charData.craftEvents or {}),
            bestiary = species,
        }
    end
    return {entries = 0, encounters = 0, diaryEvents = 0, craftEvents = 0, bestiary = 0}
end

local function countText(tally)
    return tally.entries .. " entries, " .. tally.encounters .. " encounters, "
        .. tally.diaryEvents .. " diary events, " .. tally.craftEvents .. " craft events, "
        .. tally.bestiary .. " bestiary species"
end

-- The old account-wide nextOrder was a single shared counter. If it was lost
-- or never written, new records must still sort after migrated ones, so take
-- the highest order actually present as a floor.
local function highestOrder(charData)
    local highest = 0
    local function consider(value)
        if type(value) == "number" and value > highest then highest = value end
    end
    for _, entry in pairs(charData.entries or {}) do
        if type(entry) == "table" then consider(entry.order) end
    end
    for _, collection in ipairs({charData.encounters or {}, charData.diaryEvents or {},
                                 charData.craftEvents or {}}) do
        for _, record in ipairs(collection) do
            if type(record) == "table" then consider(record.order) end
        end
    end
    for _, beast in pairs(charData.bestiary or {}) do
        if type(beast) == "table" then consider(beast.order) end
    end
    return highest
end

--- The one-time pre-AceDB import. Returns true if it merged any source.
--  @param charData  db.char for the logged-in character
--  @param legacy    {account, character, recovery = {{name, data}, ...}} from
--                   Core/Database.lua's captureLegacy()
function Migrations.migrateLegacy(charData, legacy)
    if type(charData) ~= "table" then return false end
    legacy = type(legacy) == "table" and legacy or {}

    local legacyKey = Migrations.legacyCharacterKey(legacy.account)
    local sources = {}

    if type(legacy.account) == "table" then
        sources[#sources + 1] = {
            label = "FieldJournalDB",
            data = Migrations.accountSlice(legacy.account, legacyKey),
            nextOrder = legacy.account.nextOrder,
        }
    end

    -- The old mirror carried the key it was written for. Honour exactly the
    -- guard Core/Bootstrap.lua used, so another character's stale mirror is
    -- never folded into this character's journal.
    if type(legacy.character) == "table"
        and (not legacy.character.key or legacy.character.key == legacyKey) then
        sources[#sources + 1] = {label = "FieldJournalCharacterDB", data = legacy.character}
    end

    for _, snapshot in ipairs(legacy.recovery or {}) do
        if type(snapshot) == "table" and type(snapshot.data) == "table" then
            local key = Migrations.legacyCharacterKey(snapshot.data)
            sources[#sources + 1] = {
                label = tostring(snapshot.name or "recovery snapshot"),
                data = Migrations.accountSlice(snapshot.data, key),
                nextOrder = snapshot.data.nextOrder,
            }
        end
    end

    if #sources == 0 then
        print("Field Journal: no pre-AceDB saved data found; starting a fresh journal.")
        charData.legacyMigrated = true
        return false
    end

    local before = Migrations.counts(charData)
    print("Field Journal: migrating legacy saved data as " .. legacyKey
        .. " (" .. countText(before) .. " before).")

    local highestNextOrder = 0
    for _, source in ipairs(sources) do
        if type(source.nextOrder) == "number" and source.nextOrder > highestNextOrder then
            highestNextOrder = source.nextOrder
        end
        mergeIntoCharacter(charData, source.data, source.label)
    end

    charData.nextOrder = math.max(charData.nextOrder or 0, highestNextOrder, highestOrder(charData))
    charData.legacyMigrated = true

    print("Field Journal: migration complete (" .. countText(Migrations.counts(charData))
        .. " after, nextOrder " .. charData.nextOrder .. ").")
    return true
end

--- Called once from Core/Database.lua right after AceDB:New. Never throws.
function Migrations.run(charData, legacy)
    if type(charData) ~= "table" then return end

    if not charData.legacyMigrated then
        local ok, err = pcall(Migrations.migrateLegacy, charData, legacy)
        if not ok then
            FieldJournal.migrationError = tostring(err)
            print("Field Journal: the legacy migration failed (" .. tostring(err)
                .. "). Your old saved data was NOT changed. Run /fj status and report this.")
            -- Deliberately does not set legacyMigrated: a failed pass must be
            -- retried on the next load rather than silently skipped forever,
            -- and the chat line repeats until it is fixed.
        end
    end

    charData.schemaVersion = (FieldJournal.Database and FieldJournal.Database.SCHEMA_VERSION) or 2
end

Migrations.mergeList = mergeList
Migrations.mergeIntoCharacter = mergeIntoCharacter
-- Published for Core/Backup.lua. highestOrder lifts nextOrder above everything
-- a restore just put back, exactly as migrateLegacy uses it here; countText
-- keeps /fj backup's ring listing worded identically to the migration output.
Migrations.highestOrder = highestOrder
Migrations.countText = countText
