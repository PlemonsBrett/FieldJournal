-- Field Journal: shared namespace and root helpers.
-- WoW passes (addonName, addonTable) as the vararg of every file in an addon;
-- that addonTable is the single namespace every Field Journal module shares.

local addonName, FieldJournal = ...

FieldJournal.QuestLog = FieldJournal.QuestLog or {}
FieldJournal.Bestiary = FieldJournal.Bestiary or {}
FieldJournal.Diary = FieldJournal.Diary or {}
FieldJournal.Crafting = FieldJournal.Crafting or {}
FieldJournal.UI = FieldJournal.UI or {}

FieldJournal.frame = CreateFrame("Frame")
FieldJournal.UI.zoneFilter = "All zones"
FieldJournal.UI.searchText = ""
FieldJournal.UI.viewItems = {}

local function characterKey()
    return (GetRealmName() or "Unknown realm") .. ":" .. (UnitName("player") or "Unknown character")
end

local function clean(value)
    if type(value) ~= "string" then return "" end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function accessible(value)
    if canaccessvalue then return canaccessvalue(value) end
    if issecretvalue then return not issecretvalue(value) end
    return true
end

local function currentZone()
    return clean(GetRealZoneText()) ~= "" and GetRealZoneText() or "Unknown zone"
end

local function currentPlace()
    local zone = currentZone()
    local subzone = GetSubZoneText and clean(GetSubZoneText()) or ""
    if subzone ~= "" and subzone ~= zone then return subzone .. ", " .. zone end
    return zone
end

local function currentMapPosition()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then return end
    local x, y = position.x, position.y
    if type(x) == "number" and type(y) == "number" then return mapID, x, y end
end

local function creatureIDFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    return guid:match("^[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)")
end

local function itemName(itemID, fallback)
    if itemID and GetItemInfo then
        local name = GetItemInfo(itemID)
        if clean(name) ~= "" then return name end
    end
    if itemID and C_Item and C_Item.GetItemNameByID then
        local name = C_Item.GetItemNameByID(itemID)
        if clean(name) ~= "" then return name end
    end
    return clean(fallback) ~= "" and fallback or ("Item #" .. tostring(itemID or "?"))
end

local function moneyText(copper)
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local coins = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. " gold" end
    if silver > 0 then parts[#parts + 1] = silver .. " silver" end
    if coins > 0 or #parts == 0 then parts[#parts + 1] = coins .. " copper" end
    return table.concat(parts, ", ")
end

FieldJournal.clean = clean
FieldJournal.accessible = accessible
FieldJournal.characterKey = characterKey
FieldJournal.currentZone = currentZone
FieldJournal.currentPlace = currentPlace
FieldJournal.currentMapPosition = currentMapPosition
FieldJournal.creatureIDFromGUID = creatureIDFromGUID
FieldJournal.itemName = itemName
FieldJournal.moneyText = moneyText

local function savedCharacterKey()
    local db = FieldJournal.db
    local key = characterKey()
    if not db or not db.characters or db.characters[key] then return key end
    local name = UnitName("player")
    if not name or name == "" then return key end
    local suffix = ":" .. name
    local found
    for oldKey in pairs(db.characters) do
        if oldKey:sub(-#suffix) == suffix then
            if found then return key end
            found = oldKey
        end
    end
    return found or key
end

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

local function mergeCharacterCollections(key, source)
    local db = FieldJournal.db
    if type(source) ~= "table" then return end
    db.characters[key] = db.characters[key] or {}
    for entryKey, entry in pairs(source.entries or {}) do
        if not db.characters[key][entryKey] then db.characters[key][entryKey] = entry end
    end
    db.encounters[key] = db.encounters[key] or {}
    mergeList(db.encounters[key], source.encounters, function(item) return item.guid end)
    local function eventIdentity(item)
        return table.concat({tostring(item.key), tostring(item.seenAt),
            tostring(item.sourceGUID), tostring(item.itemID)}, "\031")
    end
    db.diaryEvents[key] = db.diaryEvents[key] or {}
    mergeList(db.diaryEvents[key], source.diaryEvents, eventIdentity)
    db.craftEvents[key] = db.craftEvents[key] or {}
    mergeList(db.craftEvents[key], source.craftEvents, eventIdentity)
    db.bestiary[key] = db.bestiary[key] or {}
    for beastKey, incoming in pairs(source.bestiary or {}) do
        local beast = db.bestiary[key][beastKey]
        if not beast then
            db.bestiary[key][beastKey] = incoming
        else
            beast.kills = math.max(beast.kills or 0, incoming.kills or 0)
            beast.order = math.max(beast.order or 0, incoming.order or 0)
            if not beast.name or beast.name:find("^Unidentified creature") then beast.name = incoming.name end
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

local function mergeAccountRecovery(source)
    local db = FieldJournal.db
    if type(source) ~= "table" or type(source.characters) ~= "table" then return end
    for key, savedEntries in pairs(source.characters) do
        mergeCharacterCollections(key, {
            entries = savedEntries,
            encounters = source.encounters and source.encounters[key],
            diaryEvents = source.diaryEvents and source.diaryEvents[key],
            craftEvents = source.craftEvents and source.craftEvents[key],
            bestiary = source.bestiary and source.bestiary[key],
        })
    end
    db.nextOrder = math.max(db.nextOrder or 0, source.nextOrder or 0)
end

local function initializeCharacter()
    local db = FieldJournal.db
    if not db then return end
    local key = savedCharacterKey()
    if FieldJournal.loadedCharacterKey == key and FieldJournal.entries and FieldJournal.bestiary then return end
    if FieldJournalCharacterDB and (not FieldJournalCharacterDB.key or FieldJournalCharacterDB.key == key) then
        mergeCharacterCollections(key, FieldJournalCharacterDB)
    end
    FieldJournal.loadedCharacterKey = key
    db.characters[key] = db.characters[key] or {}
    FieldJournal.entries = db.characters[key]
    db.objectiveStates[key] = db.objectiveStates[key] or {}
    FieldJournal.objectiveState = db.objectiveStates[key]
    db.questBookmarks[key] = db.questBookmarks[key] or {}
    FieldJournal.questBookmarks = db.questBookmarks[key]
    db.encounters[key] = db.encounters[key] or {}
    FieldJournal.encounters = db.encounters[key]
    db.diaryEvents[key] = db.diaryEvents[key] or {}
    FieldJournal.diaryEvents = db.diaryEvents[key]
    db.craftEvents[key] = db.craftEvents[key] or {}
    FieldJournal.craftEvents = db.craftEvents[key]
    db.bestiary[key] = db.bestiary[key] or {}
    FieldJournal.bestiary = db.bestiary[key]
    FieldJournalCharacterDB = {
        key = key, entries = FieldJournal.entries, encounters = FieldJournal.encounters,
        diaryEvents = FieldJournal.diaryEvents, craftEvents = FieldJournal.craftEvents,
        bestiary = FieldJournal.bestiary,
    }
    local entries, encounters, bestiary, questBookmarks =
        FieldJournal.entries, FieldJournal.encounters, FieldJournal.bestiary, FieldJournal.questBookmarks
    FieldJournal.Diary.resetGroupSnapshot()

    -- Reconcile the derived index with the persistent encounter log on every load.
    -- Existing higher totals and item counts remain intact.
    local rebuilt = {}
    for _, encounter in ipairs(encounters) do
        if encounter.guid and encounter.name then
            local id = creatureIDFromGUID(encounter.guid)
            local beastKey = id and ("creature:" .. id) or ("name:" .. encounter.name)
            local record = rebuilt[beastKey]
            if not record then
                record = {name = encounter.name, kills = 0, places = {}, order = 0}
                rebuilt[beastKey] = record
            end
            record.kills = record.kills + 1
            local place = encounter.place or encounter.zone or "Unknown place"
            local location = record.places[place] or {count = 0}
            location.count = location.count + 1
            location.mapID, location.mapX, location.mapY = encounter.mapID, encounter.mapX, encounter.mapY
            record.places[place] = location
            record.order = math.max(record.order, encounter.seenAt or 0)
        end
    end
    for beastKey, record in pairs(rebuilt) do
        local beast = bestiary[beastKey]
        if not beast then
            beast = {key = beastKey, name = record.name, kills = 0, places = {}, drops = {}, order = 0}
            bestiary[beastKey] = beast
        end
        beast.kills = math.max(beast.kills or 0, record.kills)
        beast.places = beast.places or {}
        beast.drops = beast.drops or {}
        for place, location in pairs(record.places) do
            local existing = beast.places[place]
            if not existing or (existing.count or 0) < location.count then beast.places[place] = location end
        end
        if (beast.order or 0) == 0 then beast.order = record.order end
    end
    for _, entry in pairs(entries) do
        if (entry.kind == "quest" or entry.kind == "pastQuest") and entry.questID and entry.bookmarked then
            questBookmarks[entry.questID] = true
            entry.bookmarked = false
        end
        if entry.kind == "pastQuest" and entry.questID and FieldJournal.QuestLog.recoveredBody(entry.questID)
            and entry.stage ~= "Recovered description" then
            entry.stage = "Recovered description"
            entry.body = FieldJournal.QuestLog.recoveredBody(entry.questID)
        end
    end
    if not FieldJournal.UI.window then FieldJournal.UI.createWindow() end
    FieldJournal.QuestLog.syncActiveQuestLog()
    FieldJournal.Bestiary.observeUnit("target")
end

FieldJournal.savedCharacterKey = savedCharacterKey
FieldJournal.mergeList = mergeList
FieldJournal.mergeCharacterCollections = mergeCharacterCollections
FieldJournal.mergeAccountRecovery = mergeAccountRecovery
FieldJournal.initializeCharacter = initializeCharacter

FieldJournal.frame:RegisterEvent("ADDON_LOADED")
FieldJournal.frame:RegisterEvent("PLAYER_LOGIN")
FieldJournal.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
FieldJournal.frame:RegisterEvent("QUEST_DETAIL")
FieldJournal.frame:RegisterEvent("QUEST_PROGRESS")
FieldJournal.frame:RegisterEvent("QUEST_COMPLETE")
FieldJournal.frame:RegisterEvent("QUEST_ACCEPTED")
FieldJournal.frame:RegisterEvent("QUEST_TURNED_IN")
FieldJournal.frame:RegisterEvent("QUEST_LOG_UPDATE")
FieldJournal.frame:RegisterEvent("GOSSIP_SHOW")
FieldJournal.frame:RegisterEvent("ITEM_TEXT_BEGIN")
FieldJournal.frame:RegisterEvent("ITEM_TEXT_READY")
FieldJournal.frame:RegisterEvent("ITEM_TEXT_CLOSED")
FieldJournal.frame:RegisterEvent("CHAT_MSG_MONSTER_SAY")
FieldJournal.frame:RegisterEvent("CHAT_MSG_MONSTER_YELL")
FieldJournal.frame:RegisterEvent("CHAT_MSG_MONSTER_WHISPER")
FieldJournal.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
FieldJournal.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
FieldJournal.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
for _, event in ipairs({"LOOT_OPENED", "LOOT_READY", "LOOT_SLOT_CLEARED", "LOOT_CLOSED",
    "TRAINER_SHOW", "TRAINER_CLOSED", "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE",
    "CHAT_MSG_SKILL", "CHAT_MSG_TRADESKILLS", "TRADE_SKILL_ITEM_CRAFTED_RESULT",
    "GROUP_ROSTER_UPDATE", "MERCHANT_SHOW", "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED", "PLAYER_MONEY"}) do
    pcall(FieldJournal.frame.RegisterEvent, FieldJournal.frame, event)
end
local partyKillRegistered = pcall(FieldJournal.frame.RegisterEvent, FieldJournal.frame, "PARTY_KILL")
local unitDiedRegistered = pcall(FieldJournal.frame.RegisterEvent, FieldJournal.frame, "UNIT_DIED")
pcall(FieldJournal.frame.RegisterEvent, FieldJournal.frame, "UPDATE_MOUSEOVER_UNIT")
pcall(FieldJournal.frame.RegisterEvent, FieldJournal.frame, "NAME_PLATE_UNIT_ADDED")
FieldJournal.frame:SetScript("OnEvent", function(_, event, ...)
    local name = ...
    if event == "ADDON_LOADED" then
        if name ~= addonName then return end
        FieldJournalDB = FieldJournalDB or {version = 1, nextOrder = 0, characters = {}}
        FieldJournal.db = FieldJournalDB
        local db = FieldJournal.db
        db.nextOrder = db.nextOrder or 0
        db.characters = db.characters or {}
        db.objectiveStates = db.objectiveStates or {}
        db.questBookmarks = db.questBookmarks or {}
        db.encounters = db.encounters or {}
        db.diaryEvents = db.diaryEvents or {}
        db.craftEvents = db.craftEvents or {}
        db.bestiary = db.bestiary or {}
        db.bestiaryMigrated = db.bestiaryMigrated or {}
        mergeAccountRecovery(FieldJournalRecoveryDB)
        mergeAccountRecovery(FieldJournalRecoveryDB2)
        mergeAccountRecovery(FieldJournalRecoveryDB3)
        FieldJournal.recoveredQuestText = FieldJournalQuestText or {}
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        initializeCharacter()
        if event == "PLAYER_LOGIN" and not partyKillRegistered and not unitDiedRegistered then
            print("Field Journal: no kill event is available on this client; encounter recording is unavailable.")
        end
    elseif event == "QUEST_DETAIL" then
        FieldJournal.QuestLog.captureQuest("Offered")
    elseif event == "QUEST_PROGRESS" then
        FieldJournal.QuestLog.captureQuest("In progress")
    elseif event == "QUEST_COMPLETE" then
        FieldJournal.QuestLog.captureQuest("Completed")
    elseif event == "QUEST_ACCEPTED" then
        local questID = select(2, ...) or (type(name) == "number" and name)
        FieldJournal.QuestLog.questAccepted(questID)
    elseif event == "QUEST_TURNED_IN" then
        local questID = name
        if questID then
            FieldJournal.QuestLog.addEntry("questStatus", questID, "Turned in", FieldJournal.QuestLog.questTitle(questID), "I turned in this quest.", FieldJournal.QuestLog.questSpeaker())
        end
    elseif event == "QUEST_LOG_UPDATE" then
        FieldJournal.QuestLog.syncActiveQuestLog()
    elseif event == "GOSSIP_SHOW" then
        FieldJournal.QuestLog.captureGossip()
    elseif event == "ITEM_TEXT_BEGIN" then
        FieldJournal.QuestLog.beginNote()
    elseif event == "ITEM_TEXT_READY" then
        FieldJournal.QuestLog.captureNotePage()
    elseif event == "ITEM_TEXT_CLOSED" then
        FieldJournal.QuestLog.closeNote()
    elseif event == "CHAT_MSG_MONSTER_SAY" then
        FieldJournal.QuestLog.captureSpeech("Said", name, select(2, ...))
    elseif event == "CHAT_MSG_MONSTER_YELL" then
        FieldJournal.QuestLog.captureSpeech("Yelled", name, select(2, ...))
    elseif event == "CHAT_MSG_MONSTER_WHISPER" then
        FieldJournal.QuestLog.captureSpeech("Whispered", name, select(2, ...))
    elseif event == "PLAYER_REGEN_ENABLED" then
        FieldJournal.QuestLog.flushPendingSpeech()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_TARGET_CHANGED" then
        FieldJournal.Bestiary.observeUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        FieldJournal.Bestiary.observeUnit("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        FieldJournal.Bestiary.observeUnit(name)
    elseif event == "LOOT_OPENED" or event == "LOOT_READY" then
        FieldJournal.Bestiary.captureLootSlots()
    elseif event == "LOOT_SLOT_CLEARED" then
        FieldJournal.Bestiary.commitLootSlot(name)
    elseif event == "LOOT_CLOSED" then
        FieldJournal.Bestiary.clearLootSlots()
    elseif event == "TRAINER_SHOW" then
        FieldJournal.Diary.trainerShown()
    elseif event == "TRAINER_CLOSED" then
        FieldJournal.Diary.trainerClosed()
    elseif event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        FieldJournal.Diary.learnedSpell(name)
    elseif event == "CHAT_MSG_SKILL" then
        FieldJournal.Crafting.recordSkillMessage(name)
    elseif event == "CHAT_MSG_TRADESKILLS" then
        FieldJournal.Crafting.tradeskillMessage(name)
    elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
        FieldJournal.Crafting.craftedResult(name)
    elseif event == "GROUP_ROSTER_UPDATE" then
        FieldJournal.Diary.updateGroup()
    elseif event == "MERCHANT_SHOW" then
        FieldJournal.Diary.merchantShown()
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_MONEY" then
        FieldJournal.Diary.merchantBagUpdate()
    elseif event == "MERCHANT_CLOSED" then
        FieldJournal.Diary.merchantClosed()
    elseif event == "PARTY_KILL" then
        FieldJournal.Bestiary.partyKill(name, (select(2, ...)))
    elseif event == "UNIT_DIED" then
        FieldJournal.Bestiary.unitDied(name)
    end
end)
