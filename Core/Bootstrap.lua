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

local function initializeCharacter()
    local db = FieldJournal.db
    if not db then return end
    local charData = db.char
    if type(charData) ~= "table" then return end
    local key = characterKey()
    if FieldJournal.loadedCharacterKey == key and FieldJournal.entries and FieldJournal.bestiary then return end
    FieldJournal.loadedCharacterKey = key
    -- Point the namespace fields every Data/ and UI/ file already reads at this
    -- character's AceDB slot. The `or {}` guards are not paranoia about AceDB's
    -- defaults -- AceDB's PLAYER_LOGOUT pass deletes collections that are still
    -- empty, and copyDefaults recreates them at load, but a hand-edited or
    -- half-written SavedVariables file can still arrive with one missing.
    FieldJournal.charData = charData
    charData.nextOrder = charData.nextOrder or 0
    charData.entries = charData.entries or {}
    FieldJournal.entries = charData.entries
    charData.objectiveState = charData.objectiveState or {}
    FieldJournal.objectiveState = charData.objectiveState
    charData.questBookmarks = charData.questBookmarks or {}
    FieldJournal.questBookmarks = charData.questBookmarks
    charData.encounters = charData.encounters or {}
    FieldJournal.encounters = charData.encounters
    charData.diaryEvents = charData.diaryEvents or {}
    FieldJournal.diaryEvents = charData.diaryEvents
    charData.craftEvents = charData.craftEvents or {}
    FieldJournal.craftEvents = charData.craftEvents
    charData.bestiary = charData.bestiary or {}
    FieldJournal.bestiary = charData.bestiary
    -- The per-character mirror predates AceDB and is kept deliberately: it is a
    -- second, independently written copy of the same five collections, and this
    -- is precisely the release where a second copy is worth its disk space.
    -- It keeps the old "<realm>:<char>" key format so the legacy shape stays
    -- self-consistent. Core/Backup.lua (Plan 3b) supersedes it.
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
        FieldJournal.Database.initialize()
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
