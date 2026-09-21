-- Field Journal: /fj export and /fj import -- the manual safety valve.
--
-- WHY THIS EXISTS. Plan 3b gave every install a rotating ring of five
-- snapshots, but that ring lives INSIDE FieldJournalDB -- the same account
-- saved-variables file whose loss motivated this whole phase. It defends
-- against in-file damage and not against the file disappearing. This file
-- produces the first copy of a journal that can leave the game entirely: a
-- printable string the player pastes into a text file, a chat message, or
-- another machine.
--
-- THE PIPELINE, AND WHO OWNS IT. Export is
--     Backup.snapshotData(charData) -> envelope -> AceSerializer:Serialize
--       -> LibDeflate:CompressDeflate -> LibDeflate:EncodeForPrint
-- and import is exactly that reversed. This file owns every one of those steps
-- and the shape of the envelope in between. No other shipped file may call
-- Serialize/Deserialize/CompressDeflate/DecompressDeflate/EncodeForPrint/
-- DecodeForPrint or read a field out of a decoded payload -- Core/SlashCommands.lua
-- goes through Export.encode / Export.importString / Export.describePayload /
-- Export.message instead, and tests/fj_export_spec.lua enforces that against the
-- real .toc. One owner means one place where a format change has to be thought
-- about, and one place a validation hole could hide.
--
-- WHY THE SNAPSHOT HELPER AND NOT db.char. FieldJournal.Backup.snapshotData
-- already deep-copies db.char minus its own `backups` ring, and db.char.backups
-- is owned exclusively by Core/Backup.lua. Exporting the ring would multiply the
-- string's size by six for no benefit -- the receiving character builds its own
-- ring -- and re-deriving that exclusion here would be a second copy of a rule
-- that then has to stay in step with Core/Backup.lua forever.
--
-- WHY AN ENVELOPE RATHER THAN THE BARE TABLE. A bare serialized db.char is
-- indistinguishable from any other AceSerializer string, so a WeakAuras or
-- Details string pasted by mistake would decode to *a table* and reach the merge
-- with nothing but guesswork standing in the way. The envelope carries an addon
-- tag, its own format version and the journal schema version, so a foreign or
-- incompatible string is rejected by identity rather than by inspection. It also
-- lets /fj import tell the player whose journal, from when, they are about to
-- merge.
--
-- VALIDATION HAPPENS BEFORE THE MERGE, NEVER DURING IT. This is the one code
-- path in the addon where data of unknown provenance reaches the journal.
--
-- Nothing in this file may throw. Every entry point runs from a slash command or
-- a UI button; each catches its own errors, prints, and degrades.

local FieldJournal = select(2, ...)

local Export = {}
FieldJournal.Export = Export

-- ADDON_TAG identifies a string as ours. PAYLOAD_VERSION versions the envelope
-- itself and is deliberately separate from Database.SCHEMA_VERSION, which
-- versions the journal data carried inside it: the two can change independently.
Export.ADDON_TAG = "FieldJournal"
Export.PAYLOAD_VERSION = 1

-- The seven collections FieldJournal.Migrations.mergeIntoCharacter reads. A
-- valid export carries at least one of them, and every one it does carry must be
-- a table.
local COLLECTIONS = {
    "entries", "encounters", "diaryEvents", "craftEvents",
    "bestiary", "objectiveState", "questBookmarks",
}

-- The five counted collections, paired with the wording /fj import uses when it
-- reports what arrived. Deliberately the same wording Migrations.countText and
-- Core/Backup.lua use, so one journal is described identically everywhere.
local COUNTED = {
    {field = "entries", label = "entries"},
    {field = "encounters", label = "encounters"},
    {field = "diaryEvents", label = "diary events"},
    {field = "craftEvents", label = "craft events"},
    {field = "bestiary", label = "bestiary species"},
}

local MESSAGES = {
    unavailable = "the database or one of the export libraries is not available, so nothing can be exported or imported.",
    empty = "this character's journal is empty, so there is nothing to export.",
    error = "the export failed unexpectedly. Nothing was changed.",
    importerror = "the import failed unexpectedly. Run /fj status and report this.",
    notstring = "no import string was supplied. Use /fj import with no argument to open the paste box.",
    blank = "the import string was blank.",
    decode = "that is not a Field Journal export string (it could not be decoded). Check that you copied all of it.",
    decompress = "that import string is damaged (it could not be decompressed). Check that you copied all of it.",
    deserialize = "that import string is damaged (it could not be read). Check that you copied all of it.",
    foreign = "that string is not a Field Journal export.",
    payloadversion = "that export was made with a different Field Journal export format.",
    schema = "that export uses a journal schema this version of Field Journal does not recognise.",
    shape = "that export does not contain a readable Field Journal journal.",
    nothing = "that export contained nothing this character was missing; nothing changed.",
}

--- The chat line for a reason token returned by any function in this file,
--  already prefixed. Published so no other file ever writes its own wording for
--  an export failure -- see the ownership rule in this plan's Global Constraints.
function Export.message(reason, detail)
    local text = MESSAGES[reason] or MESSAGES.error
    if type(detail) == "string" and detail ~= "" then text = text .. " " .. detail end
    return "Field Journal: " .. text
end

-- Everything this file borrows lives on the shared namespace or behind LibStub,
-- and is looked up at call time rather than captured at load time, so
-- Core/Export.lua stays loadable -- and every entry point stays non-throwing --
-- even if a library or another Core module failed to load.
local function helpers()
    local Backup, Database, Migrations = FieldJournal.Backup, FieldJournal.Database, FieldJournal.Migrations
    if type(Backup) ~= "table" or type(Database) ~= "table" or type(Migrations) ~= "table" then return nil end
    if type(Backup.snapshotData) ~= "function" then return nil end
    if type(Backup.dropSupersededPlaceholders) ~= "function" then return nil end
    if type(Database.deepCopy) ~= "function" then return nil end
    if type(Database.SCHEMA_VERSION) ~= "number" then return nil end
    if type(Migrations.counts) ~= "function" then return nil end
    if type(Migrations.countText) ~= "function" then return nil end
    if type(Migrations.mergeIntoCharacter) ~= "function" then return nil end
    if type(Migrations.highestOrder) ~= "function" then return nil end
    -- LibStub is a table with a __call metamethod; the second argument makes a
    -- missing library return nil instead of raising.
    if type(LibStub) ~= "table" then return nil end
    local serializer = LibStub("AceSerializer-3.0", true)
    local deflate = LibStub("LibDeflate", true)
    if type(serializer) ~= "table" or type(serializer.Serialize) ~= "function"
        or type(serializer.Deserialize) ~= "function" then return nil end
    if type(deflate) ~= "table" or type(deflate.CompressDeflate) ~= "function"
        or type(deflate.DecompressDeflate) ~= "function"
        or type(deflate.EncodeForPrint) ~= "function"
        or type(deflate.DecodeForPrint) ~= "function" then return nil end
    return {
        snapshotData = Backup.snapshotData,
        dropSupersededPlaceholders = Backup.dropSupersededPlaceholders,
        deepCopy = Database.deepCopy,
        schemaVersion = Database.SCHEMA_VERSION,
        counts = Migrations.counts,
        countText = Migrations.countText,
        mergeIntoCharacter = Migrations.mergeIntoCharacter,
        highestOrder = Migrations.highestOrder,
        serializer = serializer,
        deflate = deflate,
    }
end

local function totalRecords(tally)
    return tally.entries + tally.encounters + tally.diaryEvents + tally.craftEvents + tally.bestiary
end

--- The exact table this addon serialises. Returns payload, reason.
--  `data` is FieldJournal.Backup.snapshotData's output -- db.char minus its
--  backup ring -- which is already the flat shape
--  FieldJournal.Migrations.mergeIntoCharacter consumes, so an import needs no
--  reshaping at all.
function Export.buildPayload(charData)
    local h = helpers()
    if not h or type(charData) ~= "table" then return nil, "unavailable" end

    -- snapshotData is pcall-wrapped because Migrations.counts (which it does not
    -- call, but which runs next on its output) and a hand-edited collection can
    -- both raise, and this function must not.
    local ok, data = pcall(h.snapshotData, charData)
    if not ok or type(data) ~= "table" then return nil, "unavailable" end

    local tallied, tally = pcall(h.counts, data)
    if not tallied then return nil, "error" end
    if totalRecords(tally) == 0 then return nil, "empty" end

    local character = "Unknown character"
    if type(FieldJournal.characterKey) == "function" then
        local named, key = pcall(FieldJournal.characterKey)
        if named and type(key) == "string" and key ~= "" then character = key end
    end

    return {
        addon = Export.ADDON_TAG,
        payloadVersion = Export.PAYLOAD_VERSION,
        schemaVersion = type(data.schemaVersion) == "number" and data.schemaVersion or h.schemaVersion,
        character = character,
        at = time(),
        counts = tally,
        data = data,
    }, "built"
end

--- The whole outbound pipeline. Returns the printable string plus "exported",
--  or nil plus a reason token for Export.message. Never throws: Serialize
--  raises on an unserialisable value and both LibDeflate calls raise on a
--  non-string argument, so the chain runs inside a pcall.
function Export.encode(charData)
    local h = helpers()
    if not h then return nil, "unavailable" end

    local payload, reason = Export.buildPayload(charData)
    if not payload then return nil, reason end

    local ok, text = pcall(function()
        local serialized = h.serializer:Serialize(payload)
        local compressed = h.deflate:CompressDeflate(serialized)
        return h.deflate:EncodeForPrint(compressed)
    end)
    if not ok or type(text) ~= "string" or text == "" then return nil, "error" end
    return text, "exported"
end

--- The inbound pipeline, stopping before validation. Returns the decoded
--  payload plus "decoded", or nil plus a reason token. Never throws.
function Export.decode(text)
    local h = helpers()
    if not h then return nil, "unavailable" end
    if type(text) ~= "string" then return nil, "notstring" end

    local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then return nil, "blank" end

    -- DecodeForPrint returns nil for any character it cannot have produced;
    -- DecompressDeflate returns nil on a bad stream or a failed Adler-32 check;
    -- Deserialize returns false plus a message. All three are checked, and the
    -- whole chain runs inside a pcall because each still raises on a
    -- wrong-typed argument.
    local ok, result, reason = pcall(function()
        local compressed = h.deflate:DecodeForPrint(trimmed)
        if type(compressed) ~= "string" then return nil, "decode" end
        local serialized = h.deflate:DecompressDeflate(compressed)
        if type(serialized) ~= "string" then return nil, "decompress" end
        local read, payload = h.serializer:Deserialize(serialized)
        if not read or type(payload) ~= "table" then return nil, "deserialize" end
        return payload, "decoded"
    end)
    if not ok then return nil, "decode" end
    if not result then return nil, reason or "decode" end
    return result, "decoded"
end

--- Rejects anything that is not this addon's own export of a schema version this
--  build understands, BEFORE a single record is merged. Returns ok, reason,
--  detail -- detail is an extra sentence naming the mismatched numbers.
--
--  The schema check is deliberately exact rather than "anything at or below
--  ours". A lower version is an older shape this build has no migration path
--  for outside the one-time legacy import, and a higher one is a shape it has
--  never seen; merging either means merging records whose fields cannot be
--  reasoned about. Refusing with both numbers named is the honest answer.
function Export.validate(payload)
    local h = helpers()
    if not h then return false, "unavailable" end
    if type(payload) ~= "table" then return false, "foreign" end
    if payload.addon ~= Export.ADDON_TAG then return false, "foreign" end
    if payload.payloadVersion ~= Export.PAYLOAD_VERSION then
        return false, "payloadversion",
            "This build reads format " .. Export.PAYLOAD_VERSION .. "; that string is format "
                .. tostring(payload.payloadVersion) .. "."
    end
    if payload.schemaVersion ~= h.schemaVersion then
        return false, "schema",
            "This build reads schema v" .. h.schemaVersion .. "; that string is schema v"
                .. tostring(payload.schemaVersion) .. "."
    end
    if type(payload.data) ~= "table" then return false, "shape" end

    local present = 0
    for _, field in ipairs(COLLECTIONS) do
        local collection = payload.data[field]
        if collection ~= nil then
            if type(collection) ~= "table" then return false, "shape" end
            present = present + 1
        end
    end
    if present == 0 then return false, "shape" end
    return true, "valid"
end

--- One chat-ready sentence describing a payload: who exported it, when, and what
--  it holds. Published so /fj import's confirmation -- and any later report line
--  about an export -- never reads payload fields directly. Never throws.
function Export.describePayload(payload)
    local h = helpers()
    if not h or type(payload) ~= "table" then return "an unreadable export" end
    local tally = type(payload.counts) == "table" and payload.counts or nil
    if not tally and type(payload.data) == "table" then
        local ok, computed = pcall(h.counts, payload.data)
        if ok then tally = computed end
    end
    local described = "unreadable counts"
    if tally then
        local ok, text = pcall(h.countText, tally)
        if ok then described = text end
    end
    local at = tonumber(payload.at)
    return "exported by " .. tostring(payload.character or "an unknown character")
        .. " on " .. (at and date("%Y-%m-%d %H:%M", at) or "an unknown date")
        .. " (" .. described .. ")"
end

-- The three things every merge of older data into a live journal must do, and
-- the reason each exists. All three are exactly what Core/Backup.lua's restore
-- does, because an export string is a snapshot taken at an earlier moment in
-- precisely the way a ring snapshot is.
local function performImport(charData, payload, h)
    local before = h.counts(charData)

    -- Snapshot which past:<questID> placeholders are already live BEFORE the
    -- merge. A merge can add the real kind == "quest" capture for a quest whose
    -- placeholder is already live (either because the import itself carries
    -- that capture, or because the target already had it) and
    -- dropSupersededPlaceholders below then removes that placeholder in the
    -- same call -- a +1/-1 to the entries count that nets to zero even though
    -- real data changed (a placeholder was replaced by real text). Only a
    -- placeholder that was ALREADY live before this call, and is gone
    -- afterwards, counts as a genuine, reportable drop.
    local preExistingPast = {}
    if type(charData.entries) == "table" then
        for key in pairs(charData.entries) do
            if type(key) == "string" and key:sub(1, 5) == "past:" then
                preExistingPast[key] = true
            end
        end
    end

    -- 1. The merge always gets a DEEP COPY. Migrations.mergeIntoCharacter
    --    inserts source record tables by reference (target[#target + 1] = record,
    --    target.entries[key] = entry, target.bestiary[key] = incoming), so
    --    merging payload.data itself would make live records and the decoded
    --    payload's records the same Lua tables -- a later edit to an imported
    --    record would rewrite the payload this session still holds, and WoW's
    --    saved-variables writer, which does not preserve shared references,
    --    would write each imported record twice.
    h.mergeIntoCharacter(charData, h.deepCopy(payload.data), "imported journal")

    -- 2. Re-apply Data/QuestLog.lua addEntry's own rule
    --        if kind == "quest" and id then entries["past:" .. id] = nil end
    --    mergeEntries fills in any entry key the target is missing, so an import
    --    otherwise resurrects every recovered-description placeholder the player
    --    has already replaced with a real capture, and the Quests tab lists the
    --    same quest twice with no error and no log line.
    h.dropSupersededPlaceholders(charData)

    -- dropSupersededPlaceholders removes every superseded placeholder, including
    -- ones the merge itself just introduced; only placeholders present in
    -- preExistingPast (i.e. genuinely live before this call) and now gone count
    -- toward the reported total.
    local dropped = 0
    for key in pairs(preExistingPast) do
        if charData.entries[key] == nil then
            dropped = dropped + 1
        end
    end

    -- 3. Lift nextOrder above everything just imported. All six capture paths in
    --    Data/ do nextOrder = nextOrder + 1, so without this the next new record
    --    can collide with an imported one and sort wrongly.
    local importedNextOrder = tonumber(payload.data.nextOrder) or 0
    charData.nextOrder = math.max(charData.nextOrder or 0, importedNextOrder, h.highestOrder(charData))

    return before, h.counts(charData), dropped
end

--- Decode, validate and merge one export string into this character. Returns
--  imported, reason. Prints its own report on every path. Never throws.
--
--  Nothing is merged until decode AND validate have both succeeded: a foreign,
--  truncated or schema-incompatible string leaves the journal byte-identical and
--  says why. This is the one code path where data of unknown provenance reaches
--  the journal, so the rejection is the feature.
function Export.importString(charData, text)
    local h = helpers()
    if not h or type(charData) ~= "table" then
        print(Export.message("unavailable"))
        return false, "unavailable"
    end

    local payload, reason = Export.decode(text)
    if not payload then
        print(Export.message(reason))
        return false, reason
    end

    local ok, invalidReason, detail = Export.validate(payload)
    if not ok then
        print(Export.message(invalidReason, detail))
        return false, invalidReason
    end

    print("Field Journal: importing a journal " .. Export.describePayload(payload) .. ".")

    local results = {pcall(performImport, charData, payload, h)}
    if not results[1] then
        print(Export.message("importerror", tostring(results[2])))
        return false, "error"
    end
    local before, after, dropped = results[2], results[3], results[4]

    local gained = {}
    for _, counted in ipairs(COUNTED) do
        local delta = after[counted.field] - before[counted.field]
        if delta > 0 then gained[#gained + 1] = delta .. " " .. counted.label end
    end

    if #gained == 0 and dropped == 0 then
        print(Export.message("nothing"))
        return false, "nothing"
    end

    if #gained > 0 then
        print("Field Journal: imported " .. table.concat(gained, ", ") .. ".")
    end
    if dropped > 0 then
        print("Field Journal: dropped " .. dropped
            .. " earlier-quest placeholder(s) this import already had a real capture for.")
    end
    return true, "imported"
end
