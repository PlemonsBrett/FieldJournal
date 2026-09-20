local addonName, FieldJournal = ...
local clean = FieldJournal.clean
local accessible = FieldJournal.accessible
local characterKey = FieldJournal.characterKey
local currentZone = FieldJournal.currentZone
local currentPlace = FieldJournal.currentPlace
local currentMapPosition = FieldJournal.currentMapPosition
local creatureIDFromGUID = FieldJournal.creatureIDFromGUID
local itemName = FieldJournal.itemName
local moneyText = FieldJournal.moneyText
local makeLabel = FieldJournal.UI.makeLabel
local coloredRectangle = FieldJournal.UI.coloredRectangle
local makeButton = FieldJournal.UI.makeButton
local openQuestPicker = FieldJournal.UI.openQuestPicker
local createWindow = FieldJournal.UI.createWindow
local addEntry = FieldJournal.QuestLog.addEntry
local beginNote = FieldJournal.QuestLog.beginNote
local captureGossip = FieldJournal.QuestLog.captureGossip
local captureNotePage = FieldJournal.QuestLog.captureNotePage
local captureQuest = FieldJournal.QuestLog.captureQuest
local captureSpeech = FieldJournal.QuestLog.captureSpeech
local closeNote = FieldJournal.QuestLog.closeNote
local findUniqueQuestMention = FieldJournal.QuestLog.findUniqueQuestMention
local flushPendingSpeech = FieldJournal.QuestLog.flushPendingSpeech
local questAccepted = FieldJournal.QuestLog.questAccepted
local questSpeaker = FieldJournal.QuestLog.questSpeaker
local questTitle = FieldJournal.QuestLog.questTitle
local recoveredBody = FieldJournal.QuestLog.recoveredBody
local syncActiveQuestLog = FieldJournal.QuestLog.syncActiveQuestLog
local addLifeEvent = FieldJournal.Diary.addLifeEvent
local learnedSpell = FieldJournal.Diary.learnedSpell
local merchantBagUpdate = FieldJournal.Diary.merchantBagUpdate
local merchantClosed = FieldJournal.Diary.merchantClosed
local merchantShown = FieldJournal.Diary.merchantShown
local resetGroupSnapshot = FieldJournal.Diary.resetGroupSnapshot
local trainerClosed = FieldJournal.Diary.trainerClosed
local trainerShown = FieldJournal.Diary.trainerShown
local updateGroup = FieldJournal.Diary.updateGroup
local craftedResult = FieldJournal.Crafting.craftedResult
local recordSkillMessage = FieldJournal.Crafting.recordSkillMessage
local tradeskillMessage = FieldJournal.Crafting.tradeskillMessage
FieldJournal.frame = CreateFrame("Frame")
FieldJournal.UI.zoneFilter = "All zones"
FieldJournal.UI.searchText = ""
FieldJournal.UI.viewItems = {}
local recentDeaths = {}
local observedUnits = {}
local observedUnitCount = 0
local lootSlots = {}
local initializeCharacter

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

local function observeUnit(unit)
    if not UnitGUID or not UnitName then return end
    local okGUID, guid = pcall(UnitGUID, unit)
    if not okGUID or not guid or not accessible(guid) then return end
    if type(guid) ~= "string" or not (guid:find("^Creature%-") or guid:find("^Vehicle%-")) then return end
    local okName, name = pcall(UnitName, unit)
    if not okName or not name or not accessible(name) then return end
    name = clean(name)
    if name == "" then return end
    if not observedUnits[guid] then observedUnitCount = observedUnitCount + 1 end
    if observedUnitCount > 500 then observedUnits = {}; observedUnitCount = 1 end
    local engaged = false
    if UnitAffectingCombat then
        local okCombat, inCombat = pcall(UnitAffectingCombat, "player")
        if okCombat and accessible(inCombat) then
            engaged = inCombat and true or false
        end
    end
    observedUnits[guid] = {
        name = name, at = GetTime(),
        engaged = engaged,
    }
end

local function observedName(guid)
    local known = observedUnits[guid]
    if known then return known.name end
    if UnitTokenFromGUID then
        local ok, unit = pcall(UnitTokenFromGUID, guid)
        if ok and unit and accessible(unit) then
            observeUnit(unit)
            if observedUnits[guid] then return observedUnits[guid].name end
        end
    end
    for _, unit in ipairs({"target", "mouseover", "softenemy"}) do
        observeUnit(unit)
        if observedUnits[guid] then return observedUnits[guid].name end
    end
    local creatureID = guid:match("^Creature%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)")
    return creatureID and ("Unidentified creature #" .. creatureID) or "Unidentified creature"
end

local function recordEncounter(guid, name, source)
    local db, encounters, bestiary = FieldJournal.db, FieldJournal.encounters, FieldJournal.bestiary
    if not encounters or not guid or recentDeaths[guid] then return end
    name = clean(name)
    if name == "" then return end
    recentDeaths[guid] = true
    local questID
    if not name:find("^Unidentified creature") then questID = findUniqueQuestMention(name) end
    local place = currentPlace()
    local mapID, mapX, mapY = currentMapPosition()
    encounters[#encounters + 1] = {
        guid = guid, name = name, zone = currentZone(), place = place,
        seenAt = time(), mapID = mapID, mapX = mapX, mapY = mapY,
        linkedQuestID = questID, source = source,
    }
    local creatureID = creatureIDFromGUID(guid)
    local beastKey = creatureID and ("creature:" .. creatureID) or ("name:" .. name)
    local beast = bestiary and bestiary[beastKey]
    if bestiary then
        if not beast then
            beast = {key = beastKey, name = name, kills = 0, places = {}, drops = {}, order = 0}
            bestiary[beastKey] = beast
        end
        if not name:find("^Unidentified creature") then beast.name = name end
        beast.kills = beast.kills + 1
        db.nextOrder = db.nextOrder + 1
        beast.order = db.nextOrder
        local location = beast.places[place] or {count = 0}
        location.count = location.count + 1
        location.mapID, location.mapX, location.mapY = mapID, mapX, mapY
        beast.places[place] = location
    end
    if #encounters > 2500 then table.remove(encounters, 1) end
    if questID then
        local story = source == "personal" and ("Near " .. place .. ", I fought " .. name .. " and saw " .. name .. " fall.")
            or ("Near " .. place .. ", I saw " .. name .. " fall during the fight.")
        addEntry("kill", nil, "Encounter", name,
            story, "", questID)
    end
    FieldJournal.UI.RefreshIfShown()
end

local function captureLootSlots()
    if not GetNumLootItems or not GetLootSlotInfo then return end
    for slot = 1, GetNumLootItems() do
        local _, name, quantity, _, _, _, isQuestItem, questID, _, isCoin = GetLootSlotInfo(slot)
        if name and accessible(name) and not isCoin then
            local link = GetLootSlotLink and GetLootSlotLink(slot)
            local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
            local sources = {}
            if GetLootSourceInfo then
                local info = {GetLootSourceInfo(slot)}
                for index = 1, #info, 2 do
                    local guid = info[index]
                    if type(guid) == "string" and accessible(guid) then
                        sources[#sources + 1] = {guid = guid, count = tonumber(info[index + 1]) or 1}
                    end
                end
            end
            lootSlots[slot] = {name = name, itemID = itemID, count = tonumber(quantity) or 1,
                sources = sources, questID = questID, questItem = isQuestItem}
        end
    end
end

local function commitLootSlot(slot)
    local db, bestiary, craftEvents = FieldJournal.db, FieldJournal.bestiary, FieldJournal.craftEvents
    local loot = lootSlots[slot]
    lootSlots[slot] = nil
    if not loot then return end
    local sourceName
    for _, source in ipairs(loot.sources) do
        local guid = source.guid
        if guid:find("^Creature%-") or guid:find("^Vehicle%-") then
            local name = observedName(guid)
            sourceName = sourceName or name
            local creatureID = creatureIDFromGUID(guid)
            local key = creatureID and ("creature:" .. creatureID) or ("name:" .. name)
            local beast = bestiary[key]
            if not beast then
                beast = {key = key, name = name, kills = 0, places = {}, drops = {}, order = 0}
                bestiary[key] = beast
            end
            if name and not name:find("^Unidentified creature") then beast.name = name end
            local dropKey = loot.itemID and tostring(loot.itemID) or loot.name
            local drop = beast.drops[dropKey] or {name = loot.name, count = 0}
            drop.count = drop.count + source.count
            beast.drops[dropKey] = drop
            db.nextOrder = db.nextOrder + 1
            beast.order = db.nextOrder
        elseif guid:find("^GameObject%-") then
            sourceName = sourceName or "something in " .. currentPlace()
            FieldJournal.Crafting.recordGather(loot, source.count, guid)
        end
    end
    local questID = tonumber(loot.questID) or findUniqueQuestMention(loot.name)
    if questID and loot.questItem then
        local body = "I picked up " .. loot.name
            .. (sourceName and (" from " .. sourceName) or (" near " .. currentPlace())) .. "."
        addEntry("pickup", nil, "Found", loot.name, body, "", questID)
    end
    FieldJournal.UI.RefreshIfShown()
end

local function buildBestiaryViews()
    local bestiary, searchText = FieldJournal.bestiary, FieldJournal.UI.searchText
    local result = {}
    FieldJournal.UI.viewItems = {}
    local viewItems = FieldJournal.UI.viewItems
    local query = searchText:lower()
    for key, beast in pairs(bestiary or {}) do
        local view = {key = "beast:" .. key, kind = "beast", title = beast.name,
            zone = (beast.kills or 0) > 0 and ("Encountered " .. beast.kills .. " time(s)")
                or "Loot observed", order = beast.order or 0, beast = beast}
        viewItems[view.key] = view
        if query == "" or beast.name:lower():find(query, 1, true) then result[#result + 1] = view.key end
    end
    table.sort(result, function(a, b) return viewItems[a].order > viewItems[b].order end)
    return result
end
FieldJournal.Bestiary.buildBestiaryViews = buildBestiaryViews

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

FieldJournal.mergeList = mergeList
FieldJournal.mergeCharacterCollections = mergeCharacterCollections
FieldJournal.mergeAccountRecovery = mergeAccountRecovery

initializeCharacter = function()
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
    resetGroupSnapshot()

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
        if entry.kind == "pastQuest" and entry.questID and recoveredBody(entry.questID)
            and entry.stage ~= "Recovered description" then
            entry.stage = "Recovered description"
            entry.body = recoveredBody(entry.questID)
        end
    end
    if not FieldJournal.UI.window then createWindow() end
    syncActiveQuestLog()
    observeUnit("target")
end
FieldJournal.initializeCharacter = initializeCharacter

SLASH_FIELDJOURNAL1 = "/fieldjournal"
SLASH_FIELDJOURNAL2 = "/fj"
SlashCmdList.FIELDJOURNAL = function(message)
    local command, remainder = (message or ""):match("^(%S+)%s*(.-)%s*$")
    if command == "repair" then
        FieldJournal.loadedCharacterKey = nil
        initializeCharacter()
    FieldJournal.UI.RefreshIfShown()
        print("Field Journal: restored the bestiary index from saved encounters where needed.")
        return
    end
    if command == "status" then
        initializeCharacter()
        local function listens(eventName)
            return FieldJournal.frame.IsEventRegistered and FieldJournal.frame:IsEventRegistered(eventName) and "on" or "off"
        end
        local species = 0
        for _ in pairs(FieldJournal.bestiary or {}) do species = species + 1 end
        local recoveries = (FieldJournalRecoveryDB and 1 or 0)
            + (FieldJournalRecoveryDB2 and 1 or 0) + (FieldJournalRecoveryDB3 and 1 or 0)
        print("Field Journal: PARTY_KILL " .. listens("PARTY_KILL")
            .. ", UNIT_DIED " .. listens("UNIT_DIED")
            .. ", encounters " .. tostring(FieldJournal.encounters and #FieldJournal.encounters or 0)
            .. ", bestiary species " .. species
            .. ", craft events " .. tostring(FieldJournal.craftEvents and #FieldJournal.craftEvents or 0)
            .. ", recovery snapshots " .. recoveries
            .. ", character " .. tostring(FieldJournal.loadedCharacterKey or "not loaded") .. ".")
        return
    end
    if command == "remember" or command == "note" then
        local title, body = (remainder or ""):match("^(.-)%s*|%s*(.+)$")
        if not title or clean(title) == "" or clean(body) == "" then
            print("Field Journal: use /fj " .. command .. " Name | Text")
            return
        end
        if command == "remember" then
            addEntry("speech", nil, "Remembered", title, body, "", findUniqueQuestMention(title))
        else
            addEntry("note", nil, "Note", title, body, "", findUniqueQuestMention(title))
        end
        print("Field Journal: recorded " .. clean(title) .. ".")
        return
    end
    if not FieldJournal.UI.window then createWindow() end
    if FieldJournal.UI.window:IsShown() then FieldJournal.UI.window:Hide() else FieldJournal.UI.window:Show() end
end

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
        captureQuest("Offered")
    elseif event == "QUEST_PROGRESS" then
        captureQuest("In progress")
    elseif event == "QUEST_COMPLETE" then
        captureQuest("Completed")
    elseif event == "QUEST_ACCEPTED" then
        local questID = select(2, ...) or (type(name) == "number" and name)
        questAccepted(questID)
    elseif event == "QUEST_TURNED_IN" then
        local questID = name
        if questID then
            addEntry("questStatus", questID, "Turned in", questTitle(questID), "I turned in this quest.", questSpeaker())
        end
    elseif event == "QUEST_LOG_UPDATE" then
        syncActiveQuestLog()
    elseif event == "GOSSIP_SHOW" then
        captureGossip()
    elseif event == "ITEM_TEXT_BEGIN" then
        beginNote()
    elseif event == "ITEM_TEXT_READY" then
        captureNotePage()
    elseif event == "ITEM_TEXT_CLOSED" then
        closeNote()
    elseif event == "CHAT_MSG_MONSTER_SAY" then
        captureSpeech("Said", name, select(2, ...))
    elseif event == "CHAT_MSG_MONSTER_YELL" then
        captureSpeech("Yelled", name, select(2, ...))
    elseif event == "CHAT_MSG_MONSTER_WHISPER" then
        captureSpeech("Whispered", name, select(2, ...))
    elseif event == "PLAYER_REGEN_ENABLED" then
        flushPendingSpeech()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_TARGET_CHANGED" then
        observeUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        observeUnit("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        observeUnit(name)
    elseif event == "LOOT_OPENED" or event == "LOOT_READY" then
        captureLootSlots()
    elseif event == "LOOT_SLOT_CLEARED" then
        commitLootSlot(name)
    elseif event == "LOOT_CLOSED" then
        wipe(lootSlots)
    elseif event == "TRAINER_SHOW" then
        trainerShown()
    elseif event == "TRAINER_CLOSED" then
        trainerClosed()
    elseif event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        learnedSpell(name)
    elseif event == "CHAT_MSG_SKILL" then
        recordSkillMessage(name)
    elseif event == "CHAT_MSG_TRADESKILLS" then
        tradeskillMessage(name)
    elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
        craftedResult(name)
    elseif event == "GROUP_ROSTER_UPDATE" then
        updateGroup()
    elseif event == "MERCHANT_SHOW" then
        merchantShown()
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_MONEY" then
        merchantBagUpdate()
    elseif event == "MERCHANT_CLOSED" then
        merchantClosed()
    elseif event == "PARTY_KILL" then
        local targetGUID = select(2, ...)
        if targetGUID and accessible(targetGUID)
            and type(targetGUID) == "string"
            and (targetGUID:find("^Creature%-") or targetGUID:find("^Vehicle%-")) then
            observeUnit("target")
            local personal = false
            if name and accessible(name) then
                personal = name == UnitGUID("player") or name == UnitGUID("pet")
            end
            recordEncounter(targetGUID, observedName(targetGUID), personal and "personal" or "party")
        end
    elseif event == "UNIT_DIED" then
        local guid = name
        if guid and accessible(guid) and type(guid) == "string" then
            local observed = observedUnits[guid]
            if observed and observed.engaged and GetTime() - observed.at < 90 then
                recordEncounter(guid, observed.name, "observed")
            end
        end
    end
end)
