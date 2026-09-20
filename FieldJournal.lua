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
FieldJournal.frame = CreateFrame("Frame")
FieldJournal.UI.zoneFilter = "All zones"
FieldJournal.UI.searchText = ""
FieldJournal.UI.viewItems = {}
local rows = {}
local visibleKeys = {}
local zoneButton
local detailText
local detailScrollChild
local bookmarkButton
local linkButton
local writeButton
local relatedKeys = {}
local relatedIndex = 0
local countText
local historyButton
local activeNoteTitle
local activeNoteKey
local pendingSpeech = {}
local recentDeaths = {}
local observedUnits = {}
local observedUnitCount = 0
local detailBlocks = {}
local lootSlots = {}
local merchantContext
local trainerContext
local groupSnapshot
local recentCrafts = {}
local currentTab = "quests"
local tabButtons = {}
local recentQuestContexts = {}
local recentTraining = {}
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

local function addLifeEvent(collection, kind, title, body, extra)
    local db = FieldJournal.db
    if not collection or not db then return end
    db.nextOrder = db.nextOrder + 1
    local event = {
        key = kind .. ":" .. db.nextOrder, kind = kind, title = clean(title),
        body = clean(body), place = currentPlace(), zone = currentZone(),
        seenAt = time(), order = db.nextOrder,
    }
    event.mapID, event.mapX, event.mapY = currentMapPosition()
    if extra then for key, value in pairs(extra) do event[key] = value end end
    collection[#collection + 1] = event
    if #collection > 3000 then table.remove(collection, 1) end
    FieldJournal.UI.RefreshIfShown()
    return event
end

local function recoveredBody(questID)
    local recoveredQuestText = FieldJournal.recoveredQuestText
    local text = recoveredQuestText and recoveredQuestText[questID]
    if not text then return nil end
    local class = UnitClass("player") or "adventurer"
    return "Quest description\n\n" .. text:gsub("%$c", class)
end

local function addEntry(kind, id, stage, title, body, speaker, linkedQuestID)
    local db, entries = FieldJournal.db, FieldJournal.entries
    body = clean(body)
    if body == "" or not entries then return end
    title = clean(title)
    speaker = clean(speaker)
    local key = table.concat({kind, tostring(id or 0), stage or "", speaker, body}, "\031")
    local entry = entries[key]
    if not entry then
        if kind == "quest" and id then entries["past:" .. id] = nil end
        db.nextOrder = db.nextOrder + 1
        entry = {
            key = key,
            kind = kind,
            questID = id,
            stage = stage,
            title = title ~= "" and title or (speaker ~= "" and speaker or "Conversation"),
            speaker = speaker,
            body = body,
            zone = currentZone(),
            place = currentPlace(),
            seenAt = time(),
            order = db.nextOrder,
            bookmarked = false,
            linkedQuestID = linkedQuestID,
        }
        entries[key] = entry
        entry.mapID, entry.mapX, entry.mapY = currentMapPosition()
    FieldJournal.UI.RefreshIfShown()
    elseif linkedQuestID and not entry.linkedQuestID then
        entry.linkedQuestID = linkedQuestID
    end
    return entry
end

local function questTitle(questID)
    local entries = FieldJournal.entries
    for _, entry in pairs(entries or {}) do
        if (entry.kind == "quest" or entry.kind == "pastQuest") and entry.questID == questID then
            return entry.title
        end
    end
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local title = C_QuestLog.GetTitleForQuestID(questID)
        if clean(title) ~= "" then return title end
    end
    return "Quest #" .. tostring(questID)
end

local function findUniqueQuestMention(term)
    local entries = FieldJournal.entries
    term = clean(term):lower()
    if #term < 4 then return nil end
    local matches = {}
    local function consider(questID, title, body)
        if questID and ((title or "") .. " " .. (body or "")):lower():find(term, 1, true) then
            matches[questID] = true
        end
    end
    for _, entry in pairs(entries or {}) do
        if entry.kind == "quest" and entry.questID then
            consider(entry.questID, entry.title, entry.body)
        end
    end
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and GetQuestLogQuestText then
        local count = C_QuestLog.GetNumQuestLogEntries() or 0
        for index = 1, count do
            local info = C_QuestLog.GetInfo(index)
            if info and not info.isHeader and info.questID then
                local description, objective = GetQuestLogQuestText(index)
                local text = (description or "") .. " " .. (objective or "")
                if C_QuestLog.GetQuestObjectives then
                    for _, task in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                        text = text .. " " .. (task.text or "")
                    end
                end
                consider(info.questID, info.title, text)
            end
        end
    end
    local only
    for questID in pairs(matches) do
        if only then return nil end
        only = questID
    end
    return only
end

local function updateNoteBody(entry)
    local parts = {}
    local maxPage = 0
    for page in pairs(entry.pages) do
        if page > maxPage then maxPage = page end
    end
    for page = 1, maxPage do
        if entry.pages[page] then
            if maxPage > 1 then parts[#parts + 1] = "Page " .. page .. "\n" end
            parts[#parts + 1] = entry.pages[page]
            parts[#parts + 1] = "\n\n"
        end
    end
    entry.body = clean(table.concat(parts))
end

local function captureNotePage()
    local db, entries = FieldJournal.db, FieldJournal.entries
    if not entries or not ItemTextGetText then return end
    local body = clean(ItemTextGetText())
    if body == "" then return end
    local title = clean((ItemTextGetItem and ItemTextGetItem()) or activeNoteTitle)
    if title == "" then title = "Unmarked note" end
    local page = (ItemTextGetPage and ItemTextGetPage()) or 1
    if type(page) ~= "number" or page < 1 then page = 1 end
    if page == 1 or not activeNoteKey then
        -- The first page identifies a note when a book is reopened later.
        activeNoteKey = table.concat({"note", title, body}, "\031")
    end
    local entry = entries[activeNoteKey]
    if not entry then
        db.nextOrder = db.nextOrder + 1
        entry = {
            key = activeNoteKey,
            kind = "note",
            stage = "Note",
            title = title,
            speaker = "",
            body = "",
            pages = {},
            zone = currentZone(),
            place = currentPlace(),
            seenAt = time(),
            order = db.nextOrder,
            bookmarked = false,
            linkedQuestID = findUniqueQuestMention(title),
        }
        entries[activeNoteKey] = entry
        entry.mapID, entry.mapX, entry.mapY = currentMapPosition()
    end
    if not entry.linkedQuestID then entry.linkedQuestID = findUniqueQuestMention(title) end
    entry.pages = entry.pages or {}
    entry.pages[page] = body
    updateNoteBody(entry)
    FieldJournal.UI.RefreshIfShown()
end

local function captureSpeech(stage, message, speaker)
    if canaccessvalue and (not canaccessvalue(message) or not canaccessvalue(speaker)) then
        pendingSpeech[#pendingSpeech + 1] = {stage, message, speaker}
        return
    end
    if issecretvalue and (issecretvalue(message) or issecretvalue(speaker))
        and not canaccessvalue then return end
    speaker = clean(speaker)
    if speaker == "" then speaker = "Unknown voice" end
    local questID = findUniqueQuestMention(speaker)
    if not questID then
        local candidate, ambiguous
        for id, context in pairs(recentQuestContexts) do
            if context.speaker == speaker and time() - context.at <= 300
                and context.zone == currentZone() then
                if candidate and candidate ~= id then ambiguous = true break end
                candidate = id
            end
        end
        if not ambiguous then questID = candidate end
    end
    addEntry("speech", nil, stage, speaker, message, "", questID)
end

local function flushPendingSpeech()
    local remaining = {}
    for _, line in ipairs(pendingSpeech) do
        if canaccessvalue and (not canaccessvalue(line[2]) or not canaccessvalue(line[3])) then
            remaining[#remaining + 1] = line
        else
            captureSpeech(line[1], line[2], line[3])
        end
    end
    pendingSpeech = remaining
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

local function isPlaceholder(entry)
    if not entry or entry.kind ~= "pastQuest" then return false end
    local body = entry.body or ""
    return body:find("This quest was completed before Field Journal", 1, true) ~= nil
        or body:find("The original words have not been found", 1, true) ~= nil
end

local function importCompletedQuests(silent)
    local db, entries = FieldJournal.db, FieldJournal.entries
    if not entries or not C_QuestLog or not C_QuestLog.GetAllCompletedQuestIDs then
        if not silent then print("Field Journal: completed quest history is unavailable in this client.") end
        return
    end
    local ids = C_QuestLog.GetAllCompletedQuestIDs() or {}
    local recovered = 0
    local recorded = {}
    for _, entry in pairs(entries) do
        if entry.kind == "quest" and entry.questID then recorded[entry.questID] = true end
    end
    for _, id in ipairs(ids) do
        local key = "past:" .. id
        local recoveredText = recoveredBody(id)
        if recoveredText and not recorded[id] and entries[key] and
            (isPlaceholder(entries[key]) or entries[key].stage ~= "Recovered description") then
            entries[key].stage = "Recovered description"
            entries[key].body = recoveredText
            recovered = recovered + 1
        elseif recoveredText and not recorded[id] and not entries[key] then
            local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
            if clean(title) ~= "" then
                db.nextOrder = db.nextOrder + 1
                entries[key] = {
                    key = key,
                    kind = "pastQuest",
                    questID = id,
                    stage = "Recovered description",
                    title = title,
                    speaker = "",
                    body = recoveredText,
                    zone = "Earlier adventures",
                    seenAt = nil,
                    order = db.nextOrder,
                    bookmarked = false,
                }
                recovered = recovered + 1
            end
        end
    end
    if not silent then print("Field Journal: recovered " .. recovered .. " earlier quest descriptions. Unverified title-only entries are hidden.") end
    FieldJournal.UI.RefreshIfShown()
end

local function questSpeaker()
    return UnitName("npc") or UnitName("target") or ""
end

local function linkRecentConversation(questID, speaker)
    local entries = FieldJournal.entries
    if not questID or clean(speaker) == "" then return end
    local now = time()
    local changed = false
    for _, entry in pairs(entries or {}) do
        if entry.kind == "gossip" and not entry.linkedQuestID
            and entry.title == speaker and entry.seenAt
            and now - entry.seenAt <= 120 and entry.zone == currentZone() then
            entry.linkedQuestID = questID
            changed = true
        end
    end
    if changed then FieldJournal.UI.RefreshIfShown() end
end

local function captureQuest(stage)
    local id = GetQuestID and GetQuestID() or nil
    local title = GetTitleText and GetTitleText() or ""
    local speaker = questSpeaker()
    if id and clean(speaker) ~= "" then
        recentQuestContexts[id] = {speaker = speaker, at = time(), zone = currentZone()}
    end
    if stage == "Offered" then
        local description = GetQuestText and GetQuestText() or ""
        local objectives = GetObjectiveText and GetObjectiveText() or ""
        local body = clean(description)
        if clean(objectives) ~= "" and objectives ~= description then
            body = body .. "\n\nObjectives\n" .. objectives
        end
        addEntry("quest", id, stage, title, body, speaker)
    elseif stage == "In progress" then
        addEntry("quest", id, stage, title, GetProgressText and GetProgressText() or "", speaker)
    elseif stage == "Completed" then
        addEntry("quest", id, stage, title, GetRewardText and GetRewardText() or "", speaker)
    end
    linkRecentConversation(id, speaker)
end

local function activeQuests()
    local result = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local count = C_QuestLog.GetNumQuestLogEntries() or 0
        for index = 1, count do
            local info = C_QuestLog.GetInfo(index)
            if info and not info.isHeader and info.questID then result[info.questID] = info end
        end
    end
    return result
end

local function syncActiveQuestLog()
    local entries, objectiveState = FieldJournal.entries, FieldJournal.objectiveState
    if not entries or not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries or not C_QuestLog.GetInfo then return end
    local count = C_QuestLog.GetNumQuestLogEntries() or 0
    for index = 1, count do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID then
            local id = info.questID
            local captured = false
            for _, entry in pairs(entries) do
                if entry.questID == id and entry.kind == "quest" then captured = true break end
            end
            if not captured and GetQuestLogQuestText then
                local description, objectives = GetQuestLogQuestText(index)
                local body = clean(description)
                if clean(objectives) ~= "" then body = body .. "\n\nObjectives\n" .. objectives end
                addEntry("quest", id, "In log", info.title, body, "")
            end
            if C_QuestLog.GetQuestObjectives then
                local objectives = C_QuestLog.GetQuestObjectives(id)
                if objectives then
                    local states = objectiveState[id]
                    if not states then states = {}; objectiveState[id] = states end
                    for objectiveIndex, objective in ipairs(objectives) do
                        local objectiveText = clean(objective.text)
                        local previous = states[objectiveIndex]
                        if type(previous) == "table" and objectiveText ~= "" then
                            if not previous.finished and objective.finished then
                                addEntry("questStatus", id, "Objective finished", info.title, objectiveText, "")
                            elseif previous.text ~= objectiveText then
                                addEntry("questStatus", id, "Objective updated", info.title, objectiveText, "")
                            end
                        end
                        states[objectiveIndex] = {text = objectiveText, finished = objective.finished and true or false}
                    end
                end
            end
        end
    end
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
            addLifeEvent(craftEvents, "gather", "Collected " .. loot.name,
                "Near " .. currentPlace() .. ", I collected " .. loot.name .. ".",
                {itemID = loot.itemID, count = source.count, sourceGUID = guid})
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

local function spellName(spellID)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then return info.name end
    end
    return GetSpellInfo and GetSpellInfo(spellID)
end

local function learnedSpell(spellID)
    local diaryEvents = FieldJournal.diaryEvents
    if not diaryEvents or not spellID or not accessible(spellID) then return end
    local name = spellName(spellID)
    if clean(name) == "" or recentTraining[spellID] and time() - recentTraining[spellID] < 4 then return end
    recentTraining[spellID] = time()
    local teacher = trainerContext and time() - trainerContext.at < 90 and trainerContext.name
    local place = trainerContext and trainerContext.place or currentPlace()
    local body = teacher and ("At " .. place .. ", " .. teacher .. " taught me " .. name .. ".")
        or ("At " .. place .. ", I learned " .. name .. ".")
    addLifeEvent(diaryEvents, "training", "Learned " .. name, body, {spellID = spellID})
end

local function recordCraft(itemID, name, count)
    local craftEvents = FieldJournal.craftEvents
    name = itemName(itemID, name)
    if name == "" then return end
    local key = tostring(itemID or name)
    if recentCrafts[key] and time() - recentCrafts[key] < 3 then return end
    recentCrafts[key] = time()
    addLifeEvent(craftEvents, "craft", "Crafted " .. name,
        "At " .. currentPlace() .. ", I made " .. (count and count > 1 and (count .. " " .. name) or name) .. ".",
        {itemID = itemID, count = count or 1})
end

local function recordSkillMessage(message)
    local craftEvents = FieldJournal.craftEvents
    if type(message) ~= "string" or not accessible(message) then return end
    local skill, level = message:match("[Yy]our skill in (.-) has increased to (%d+)")
    level = tonumber(level)
    if not skill or not level then return end
    local milestone = level == 20 or level == 25 or level == 35 or level == 40 or level == 50
        or level == 75 or (level >= 100 and level % 25 == 0)
    if milestone then
        addLifeEvent(craftEvents, "milestone", skill .. " reached " .. level,
            "At " .. currentPlace() .. ", my " .. skill .. " skill reached " .. level .. ".")
    end
end

local function currentGroup()
    local result = {}
    if not GetNumGroupMembers then return result end
    local count = GetNumGroupMembers()
    if count <= 0 then return result end
    local raid = IsInRaid and IsInRaid()
    for index = 1, count do
        local unit = raid and ("raid" .. index) or ("party" .. index)
        local name = UnitName(unit)
        if name and name ~= UnitName("player") then result[name] = true end
    end
    return result
end

local function updateGroup()
    local diaryEvents = FieldJournal.diaryEvents
    local now = currentGroup()
    if groupSnapshot then
        for name in pairs(now) do
            if not groupSnapshot[name] then
                addLifeEvent(diaryEvents, "group", "Met " .. name,
                    "Near " .. currentPlace() .. ", I joined a group with " .. name .. ".")
            end
        end
    end
    groupSnapshot = now
end

local function bagSnapshot()
    local items, names = {}, {}
    local api = C_Container
    if not api or not api.GetContainerNumSlots or not api.GetContainerItemInfo then return items, names end
    for bag = 0, 4 do
        for slot = 1, api.GetContainerNumSlots(bag) or 0 do
            local info = api.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                items[info.itemID] = (items[info.itemID] or 0) + (info.stackCount or 1)
                local link = info.hyperlink or info.itemLink
                names[info.itemID] = type(link) == "string" and link:match("|h%[([^%]]+)%]|h")
                    or names[info.itemID]
            end
        end
    end
    return items, names
end

local function checkMerchant()
    local diaryEvents = FieldJournal.diaryEvents
    if not merchantContext or not diaryEvents then return end
    local newItems, newNames = bagSnapshot()
    local newMoney = GetMoney and GetMoney() or 0
    local gained, lost = {}, {}
    for id, count in pairs(newItems) do
        local delta = count - (merchantContext.items[id] or 0)
        if delta > 0 then gained[#gained + 1] = delta .. " " .. itemName(id, newNames[id]) end
    end
    for id, count in pairs(merchantContext.items) do
        local delta = count - (newItems[id] or 0)
        if delta > 0 then lost[#lost + 1] = delta .. " " .. itemName(id, merchantContext.names[id]) end
    end
    table.sort(gained)
    table.sort(lost)
    if #gained > 0 and newMoney < merchantContext.money then
        addLifeEvent(diaryEvents, "purchase", "A purchase from " .. merchantContext.name,
            "At " .. merchantContext.place .. ", I bought " .. table.concat(gained, ", ")
            .. " from " .. merchantContext.name .. " for " .. moneyText(merchantContext.money - newMoney) .. ".")
    elseif #lost > 0 and newMoney > merchantContext.money then
        addLifeEvent(diaryEvents, "sale", "Sold to " .. merchantContext.name,
            "At " .. merchantContext.place .. ", I sold " .. table.concat(lost, ", ")
            .. " to " .. merchantContext.name .. " for " .. moneyText(newMoney - merchantContext.money) .. ".")
    end
    merchantContext.items, merchantContext.names, merchantContext.money = newItems, newNames, newMoney
end

local function readableItemName(item)
    local fallback = item.title or ""
    local fromLink = fallback:match("|h%[([^%]]+)%]|h")
        or (item.body or ""):match("|h%[([^%]]+)%]|h")
    if fromLink then return fromLink end
    fallback = fallback:gsub("^Collected ", ""):gsub("^Crafted ", "")
    return itemName(item.itemID, fallback)
end

local function addBatchItem(batch, name, count)
    name = clean(name)
    if name == "" then return end
    local found = batch.items[name]
    batch.items[name] = (found or 0) + (tonumber(count) or 1)
end

local function merchantItems(batch, item)
    local buying = item.kind == "purchase"
    local list = buying and batch.bought or batch.sold
    local portion = buying and (item.body or ""):match("I bought (.-) from ")
        or (item.body or ""):match("I sold (.-) to ")
    if portion then
        for amount, name in portion:gmatch("(%d+) ([^,]+)") do
            name = clean(name)
            local id = name:match("^Item #(%d+)$")
            if id then name = itemName(tonumber(id), name) end
            list[name] = (list[name] or 0) + tonumber(amount)
        end
    end
    local price = (item.body or ""):match(" for (.-)%.$") or ""
    local copper = (tonumber(price:match("(%d+) gold")) or 0) * 10000
        + (tonumber(price:match("(%d+) silver")) or 0) * 100
        + (tonumber(price:match("(%d+) copper")) or 0)
    if buying then batch.spent = batch.spent + copper else batch.received = batch.received + copper end
end

local function groupLifeEvents(items)
    local sorted = {}
    for _, item in ipairs(items) do sorted[#sorted + 1] = item end
    table.sort(sorted, function(a, b)
        if (a.seenAt or 0) ~= (b.seenAt or 0) then return (a.seenAt or 0) < (b.seenAt or 0) end
        return (a.order or 0) < (b.order or 0)
    end)
    local batches, latest = {}, {}
    for _, item in ipairs(sorted) do
        local kind = item.kind or "other"
        local place = item.place or item.zone or "an unknown place"
        local vendor = (item.title or ""):match("^Sold to (.+)$")
            or (item.title or ""):match("^A purchase from (.+)$")
        local groupKind = (kind == "sale" or kind == "purchase") and "merchant" or kind
        local key
        if groupKind == "merchant" then key = "merchant:" .. (vendor or "merchant") .. ":" .. place
        elseif groupKind == "gather" then key = "gather:" .. tostring(item.sourceGUID or item.key)
        elseif groupKind == "craft" then key = "craft:" .. place
        else key = tostring(item.key) end
        local batch = latest[key]
        local limit = groupKind == "gather" and 300 or 180
        if not batch or (item.seenAt or 0) - (batch.lastAt or 0) > limit then
            batch = {kind = groupKind, place = place, vendor = vendor, firstAt = item.seenAt,
                lastAt = item.seenAt, items = {}, sold = {}, bought = {}, spent = 0,
                received = 0, raw = {}}
            batches[#batches + 1] = batch
            latest[key] = batch
        end
        batch.lastAt = item.seenAt or batch.lastAt
        batch.raw[#batch.raw + 1] = item
        if groupKind == "gather" or groupKind == "craft" then
            addBatchItem(batch, readableItemName(item), item.count)
        elseif groupKind == "merchant" then
            merchantItems(batch, item)
        end
    end
    return batches
end

local function itemSummary(items)
    local result = {}
    for name, count in pairs(items) do result[#result + 1] = count .. " × " .. name end
    table.sort(result)
    return table.concat(result, ", ")
end

local function batchSection(batch)
    if batch.kind == "merchant" then return "TRADE" end
    if batch.kind == "training" then return "TRAINING" end
    if batch.kind == "group" then return "COMPANY" end
    if batch.kind == "gather" then return "GATHERING" end
    if batch.kind == "craft" then return "CRAFTING" end
    if batch.kind == "skill" or batch.kind == "milestone" then return "SKILLS" end
    return "OTHER MEMORIES"
end

local function batchDescription(batch)
    if batch.kind == "gather" then
        return "Near " .. batch.place .. ", I gathered " .. itemSummary(batch.items) .. "."
    elseif batch.kind == "craft" then
        return "At " .. batch.place .. ", I made " .. itemSummary(batch.items) .. "."
    elseif batch.kind == "merchant" then
        local parts = {"At " .. batch.place .. ", I traded with " .. (batch.vendor or "a merchant") .. "."}
        if next(batch.sold) then parts[#parts + 1] = "Sold: " .. itemSummary(batch.sold) .. "." end
        if next(batch.bought) then parts[#parts + 1] = "Bought: " .. itemSummary(batch.bought) .. "." end
        if batch.received > 0 then parts[#parts + 1] = "Received " .. moneyText(batch.received) .. "." end
        if batch.spent > 0 then parts[#parts + 1] = "Spent " .. moneyText(batch.spent) .. "." end
        return table.concat(parts, "\n")
    end
    local parts = {}
    for _, item in ipairs(batch.raw) do parts[#parts + 1] = item.body or item.title end
    return table.concat(parts, "\n")
end

local function buildLifeViews(collection, kind)
    local searchText = FieldJournal.UI.searchText
    local result, days = {}, {}
    FieldJournal.UI.viewItems = {}
    local viewItems = FieldJournal.UI.viewItems
    for _, item in ipairs(collection or {}) do
        local day = date("%Y-%m-%d", item.seenAt or time())
        local group = days[day]
        if not group then
            group = {key = kind .. ":" .. day, kind = "lifeDay", title = date("%A, %d %B %Y", item.seenAt or time()),
                zone = "Daily pages", order = 0, items = {}, tab = kind}
            days[day] = group
            viewItems[group.key] = group
        end
        group.items[#group.items + 1] = item
        group.order = math.max(group.order, item.order or 0)
    end
    local query = searchText:lower()
    for _, group in pairs(days) do
        group.activities = groupLifeEvents(group.items)
        local haystack = group.title
        for _, item in ipairs(group.items) do haystack = haystack .. " " .. item.title .. " " .. item.body .. " " .. item.place end
        if query == "" or haystack:lower():find(query, 1, true) then result[#result + 1] = group.key end
    end
    table.sort(result, function(a, b) return viewItems[a].order > viewItems[b].order end)
    return result
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

local function matchingEntries()
    local entries, questBookmarks = FieldJournal.entries, FieldJournal.questBookmarks
    local searchText, zoneFilter = FieldJournal.UI.searchText, FieldJournal.UI.zoneFilter
    if currentTab == "diary" then return buildLifeViews(FieldJournal.diaryEvents, "diary") end
    if currentTab == "bestiary" then return buildBestiaryViews() end
    if currentTab == "craft" then return buildLifeViews(FieldJournal.craftEvents, "craft") end
    local result, groups, loose = {}, {}, {}
    local active = activeQuests()
    local captured = {}
    FieldJournal.UI.viewItems = {}
    local viewItems = FieldJournal.UI.viewItems
    for _, entry in pairs(entries or {}) do
        if entry.kind == "quest" and entry.questID then captured[entry.questID] = true end
    end
    local function groupFor(questID)
        local group = groups[questID]
        if not group then
            group = {
                key = "quest:" .. questID,
                kind = "questGroup",
                questID = questID,
                title = questTitle(questID),
                zone = "Earlier adventures",
                order = 0,
                active = active[questID] ~= nil,
                items = {},
                bookmarked = questBookmarks and questBookmarks[questID] or false,
            }
            groups[questID] = group
            viewItems[group.key] = group
        end
        return group
    end
    for questID, info in pairs(active) do
        local group = groupFor(questID)
        group.title = clean(info.title) ~= "" and info.title or group.title
        group.zone = currentZone()
    end
    for key, entry in pairs(entries or {}) do
        if entry.questID and (entry.kind == "quest" or entry.kind == "pastQuest" or entry.kind == "questStatus" or entry.kind == "margin")
            and not isPlaceholder(entry) and not (entry.kind == "pastQuest" and captured[entry.questID]) then
            local group = groupFor(entry.questID)
            group.items[#group.items + 1] = entry
            viewItems[key] = entry
            group.order = math.max(group.order, entry.order or 0)
            if entry.kind == "quest" or entry.kind == "pastQuest" then group.title = entry.title end
            if entry.zone and entry.zone ~= "Earlier adventures"
                and (entry.order or 0) >= (group.zoneOrder or 0) then
                group.zone = entry.zone
                group.zoneOrder = entry.order or 0
            end
        elseif entry.kind == "note" or entry.kind == "speech" or entry.kind == "gossip" or entry.kind == "kill" or entry.kind == "pickup" then
            viewItems[key] = entry
            if entry.linkedQuestID then
                local group = groupFor(entry.linkedQuestID)
                group.items[#group.items + 1] = entry
                group.order = math.max(group.order, entry.order or 0)
            else
                loose[#loose + 1] = entry
            end
        end
    end
    local query = searchText:lower()
    for _, group in pairs(groups) do
        local haystack = group.title .. " " .. group.zone
        for _, item in ipairs(group.items) do
            haystack = haystack .. " " .. (item.title or "") .. " " .. (item.speaker or "") .. " " .. (item.body or "")
        end
        if (zoneFilter == "All zones" or group.zone == zoneFilter)
            and (query == "" or haystack:lower():find(query, 1, true)) then
            result[#result + 1] = group.key
        end
    end
    for _, entry in ipairs(loose) do
        if (zoneFilter == "All zones" or entry.zone == zoneFilter)
            and (query == "" or (entry.title .. " " .. entry.body):lower():find(query, 1, true)) then
            result[#result + 1] = entry.key
        end
    end
    table.sort(result, function(a, b)
        local left, right = viewItems[a], viewItems[b]
        if left.bookmarked ~= right.bookmarked then return left.bookmarked end
        if (left.active or false) ~= (right.active or false) then return left.active end
        return (left.order or 0) > (right.order or 0)
    end)
    return result
end

local function zones()
    local viewItems = FieldJournal.UI.viewItems
    local result, seen = {"All zones"}, {}
    for _, entry in pairs(viewItems) do
        if entry.zone and not seen[entry.zone] then
            seen[entry.zone] = true
            result[#result + 1] = entry.zone
        end
    end
    table.sort(result, function(a, b)
        if a == "All zones" then return true end
        if b == "All zones" then return false end
        return a < b
    end)
    return result
end

local function makeLabel(parent, size, color)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetFont(STANDARD_TEXT_FONT, size, "")
    label:SetTextColor(unpack(color))
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    return label
end

local function coloredRectangle(parent, layer, r, g, b, a, left, right, top, bottom)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetColorTexture(r, g, b, a)
    texture:SetPoint("TOPLEFT", left, top)
    texture:SetPoint("BOTTOMRIGHT", right, bottom)
    return texture
end

local function makeButton(parent, width, height, label)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    coloredRectangle(button, "BACKGROUND", 0.43, 0.30, 0.17, 0.9, 0, 0, 0, 0)
    coloredRectangle(button, "BORDER", 0.83, 0.73, 0.53, 1, 1, -1, -1, 1)
    local font = makeLabel(button, 13, {0.24, 0.14, 0.08})
    font:SetJustifyH("CENTER")
    font:SetJustifyV("MIDDLE")
    font:SetAllPoints(button)
    font:SetMaxLines(1)
    button:SetFontString(font)
    button:SetText(label)
    button:SetScript("OnEnter", function(self) self:GetFontString():SetTextColor(0.55, 0.28, 0.10) end)
    button:SetScript("OnLeave", function(self) self:GetFontString():SetTextColor(0.24, 0.14, 0.08) end)
    return button
end

local function questOptions()
    local entries = FieldJournal.entries
    local options, seen, archive = {}, {}, {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local count = C_QuestLog.GetNumQuestLogEntries() or 0
        for index = 1, count do
            local info = C_QuestLog.GetInfo(index)
            if info and not info.isHeader and info.questID and clean(info.title) ~= "" and not seen[info.questID] then
                options[#options + 1] = {id = info.questID, title = info.title}
                seen[info.questID] = true
            end
        end
    end
    for _, entry in pairs(entries or {}) do
        if (entry.kind == "quest" or entry.kind == "pastQuest" or entry.kind == "questStatus" or entry.kind == "margin")
            and entry.questID and not isPlaceholder(entry) and not seen[entry.questID] then
            local old = archive[entry.questID]
            if not old or (entry.order or 0) > (old.order or 0) then archive[entry.questID] = entry end
        end
    end
    local older = {}
    for _, entry in pairs(archive) do older[#older + 1] = entry end
    table.sort(older, function(a, b)
        if a.kind ~= b.kind then return a.kind == "quest" end
        return (a.order or 0) > (b.order or 0)
    end)
    for _, entry in ipairs(older) do options[#options + 1] = {id = entry.questID, title = entry.title} end
    return options
end

local function refreshQuestPicker()
    local questPicker = FieldJournal.UI.questPicker
    if not questPicker then return end
    local options = questPicker.options or {}
    local offset = math.min(questPicker.offset or 0, math.max(0, #options - #questPicker.rows))
    questPicker.offset = offset
    for index, row in ipairs(questPicker.rows) do
        local option = options[offset + index]
        if option then
            row.option = option
            row:SetText(option.title)
            row:Show()
        else
            row.option = nil
            row:Hide()
        end
    end
    questPicker.count:SetText(#options == 0 and "No quests found" or ((offset + 1) .. "–" .. math.min(#options, offset + #questPicker.rows) .. " of " .. #options))
end

local function openQuestPicker()
    local questPicker, entries = FieldJournal.UI.questPicker, FieldJournal.entries
    if not questPicker then return end
    questPicker.options = questOptions()
    local entry = FieldJournal.UI.selectedKey and entries[FieldJournal.UI.selectedKey]
    if entry and entry.linkedQuestID then
        table.insert(questPicker.options, 1, {title = "Remove quest link", remove = true})
    end
    questPicker.offset = 0
    refreshQuestPicker()
    questPicker:Show()
end

local function renderDetailBlocks(blocks)
    detailText:Hide()
    for _, block in ipairs(detailBlocks) do
        block.font:Hide()
        block.line:Hide()
    end
    local y = 0
    for index, content in ipairs(blocks) do
        local block = detailBlocks[index]
        if not block then
            block = {
                font = makeLabel(detailScrollChild, 15, {0.25, 0.15, 0.08}),
                line = detailScrollChild:CreateTexture(nil, "OVERLAY"),
            }
            detailBlocks[index] = block
        end
        block.font:ClearAllPoints()
        block.font:SetPoint("TOPLEFT", 0, -y)
        block.font:SetWidth(292)
        block.font:SetFont(STANDARD_TEXT_FONT, content.size or 15, "")
        block.font:SetTextColor(unpack(content.color or {0.25, 0.15, 0.08}))
        block.font:SetText(content.text or "")
        block.font:Show()
        local height = math.max(content.size or 15, block.font:GetStringHeight())
        if content.strike then
            block.line:ClearAllPoints()
            block.line:SetPoint("TOPLEFT", block.font, "TOPLEFT", 1, -height * 0.52)
            block.line:SetSize(math.min(286, math.max(36, block.font:GetStringWidth() + 7)), 2)
            block.line:SetColorTexture(0.39, 0.19, 0.09, 0.65)
            block.line:Show()
        else
            block.line:Hide()
        end
        y = y + height + (content.gap or 9)
    end
    detailScrollChild:SetHeight(math.max(380, y + 20))
end

local function rememberedWhen(item)
    return item.seenAt and date("%d %b %Y, %H:%M", item.seenAt) or "Earlier; time unknown"
end

local function rememberedPlace(item)
    return clean(item.place) ~= "" and item.place or (item.zone or "an unknown place")
end

local function questStageStory(item)
    local place, speaker = rememberedPlace(item), clean(item.speaker)
    if item.kind == "pastQuest" then
        return "I recovered this quest's description later:\n" .. item.body
    elseif item.kind == "questStatus" then
        if item.stage == "Accepted" then
            return speaker ~= "" and ("At " .. place .. ", I agreed to help " .. speaker .. ".")
                or ("At " .. place .. ", I accepted this request.")
        end
        return speaker ~= "" and ("At " .. place .. ", I turned the quest in to " .. speaker .. ".")
            or ("At " .. place .. ", I closed this chapter.")
    elseif item.stage == "Offered" then
        local start = speaker ~= "" and ("At " .. place .. ", I heard " .. speaker .. "'s request.")
            or ("At " .. place .. ", I learned of a request.")
        return start .. "\n\n" .. item.body
    elseif item.stage == "In progress" then
        local start = speaker ~= "" and ("At " .. place .. ", I spoke with " .. speaker .. " again. They said:")
            or ("At " .. place .. ", I heard more about the task:")
        return start .. "\n\n“" .. item.body .. "”"
    elseif item.stage == "Completed" then
        local start = speaker ~= "" and ("At " .. place .. ", " .. speaker .. " said:")
            or ("At " .. place .. ", I heard:")
        return start .. "\n\n“" .. item.body .. "”"
    elseif item.stage == "In log" then
        return "I found this description in my quest log after I began keeping this journal:\n\n" .. item.body
    end
    return item.body or ""
end

local function marginStory(item)
    local place = rememberedPlace(item)
    if item.kind == "speech" then
        local verb = item.stage == "Yelled" and "yell" or item.stage == "Whispered" and "whisper" or "say"
        return "Near " .. place .. ", I heard " .. item.title .. " " .. verb .. ":\n“" .. item.body .. "”"
    elseif item.kind == "gossip" then
        return "At " .. place .. ", I spoke with " .. item.title .. ". They said:\n“" .. item.body .. "”"
    elseif item.kind == "note" then
        return "At " .. place .. ", I read " .. item.title .. ":\n" .. item.body
    elseif item.kind == "kill" or item.kind == "margin" or item.kind == "pickup" then
        return item.body
    elseif item.stage == "Objective finished" then
        return "I finished this part of the task: " .. item.body
    elseif item.stage == "Objective updated" then
        return "I made progress: " .. item.body
    end
    return item.body or ""
end

local function showDetail(entry)
    local entries, encounters = FieldJournal.entries, FieldJournal.encounters
    relatedKeys = {}
    if not entry then
        for _, block in ipairs(detailBlocks) do block.font:Hide(); block.line:Hide() end
        detailText:Show()
        local emptyText = currentTab == "quests" and "Your story begins when you speak to someone or open a quest."
            or currentTab == "diary" and "Daily memories will appear here as I learn, trade, and travel with others."
            or currentTab == "bestiary" and "Creatures I have seen fall will appear here."
            or "Gathered resources, crafted items, and skill milestones will appear here."
        detailText:SetText(emptyText)
        bookmarkButton:Hide()
        linkButton:Hide()
        writeButton:Hide()
    elseif entry.kind == "questGroup" then
        local blocks = {}
        local status = entry.active and "In progress" or "Recorded quest"
        if not entry.active and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
            and C_QuestLog.IsQuestFlaggedCompleted(entry.questID) then status = "Completed" end
        blocks[#blocks + 1] = {text = entry.title, size = 20, color = {0.23, 0.12, 0.06}, gap = 4}
        blocks[#blocks + 1] = {text = entry.zone .. "  •  " .. status, size = 12, color = {0.45, 0.30, 0.18}, gap = 18}
        blocks[#blocks + 1] = {text = "THE QUEST", size = 13, color = {0.35, 0.20, 0.10}, gap = 11}
        local stages, margins = {}, {}
        for _, item in ipairs(entry.items) do
            if item.kind == "quest" or item.kind == "pastQuest"
                or (item.kind == "questStatus" and (item.stage == "Accepted" or item.stage == "Turned in")) then
                stages[#stages + 1] = item
            else
                margins[#margins + 1] = item
                if item.kind == "note" or item.kind == "speech" or item.kind == "margin"
                    or item.kind == "gossip" or item.kind == "kill" or item.kind == "pickup" then
                    relatedKeys[#relatedKeys + 1] = item.key
                end
            end
        end
        table.sort(stages, function(a, b) return (a.order or 0) < (b.order or 0) end)
        table.sort(margins, function(a, b) return (a.order or 0) < (b.order or 0) end)
        if #stages == 0 then
            blocks[#blocks + 1] = {text = "This quest is in my log, but I did not record its earlier words.", gap = 16}
        end
        for index, item in ipairs(stages) do
            local old = index < #stages
            blocks[#blocks + 1] = {
                text = item.stage or "Quest text", size = 15, strike = old,
                color = old and {0.49, 0.39, 0.28} or {0.25, 0.13, 0.07}, gap = 3,
            }
            blocks[#blocks + 1] = {
                text = item.stage == "In log" and "Copied from my quest log; original meeting unknown"
                    or (rememberedWhen(item) .. "  •  " .. rememberedPlace(item)),
                size = 11, color = {0.49, 0.36, 0.22}, gap = 7,
            }
            blocks[#blocks + 1] = {
                text = questStageStory(item), size = 14,
                color = old and {0.39, 0.31, 0.23} or {0.25, 0.15, 0.08}, gap = 18,
            }
        end
        if entry.active and C_QuestLog and C_QuestLog.GetQuestObjectives then
            local objectives = C_QuestLog.GetQuestObjectives(entry.questID)
            if objectives and #objectives > 0 then
                blocks[#blocks + 1] = {text = "CURRENT OBJECTIVES", size = 13, color = {0.35, 0.20, 0.10}, gap = 10}
                for _, objective in ipairs(objectives) do
                    local description = clean(objective.text)
                    if description ~= "" then
                        blocks[#blocks + 1] = {
                            text = description, size = 14, strike = objective.finished,
                            color = objective.finished and {0.49, 0.39, 0.28} or {0.25, 0.15, 0.08}, gap = 8,
                        }
                    end
                end
            end
        end
        blocks[#blocks + 1] = {text = "IN THE MARGINS", size = 13, color = {0.35, 0.20, 0.10}, gap = 10}
        if #margins == 0 then
            blocks[#blocks + 1] = {text = "Nothing has been written in the margins yet.", size = 14}
        end
        for _, item in ipairs(margins) do
            blocks[#blocks + 1] = {
                text = rememberedWhen(item) .. "  •  " .. rememberedPlace(item),
                size = 11, color = {0.49, 0.36, 0.22}, gap = 5,
            }
            blocks[#blocks + 1] = {text = marginStory(item), size = 14, gap = 16}
        end
        renderDetailBlocks(blocks)
        bookmarkButton:Show()
        bookmarkButton:Enable()
        bookmarkButton:SetText(entry.bookmarked and "Remove bookmark" or "Bookmark")
        linkButton:SetText("Read related (" .. #relatedKeys .. ")")
        linkButton:SetShown(#relatedKeys > 0)
        writeButton:Show()
    elseif entry.kind == "lifeDay" then
        local activities = entry.activities or groupLifeEvents(entry.items)
        local blocks = {{text = entry.title, size = 20, gap = 5},
            {text = #activities .. " activities from " .. #entry.items .. " records",
                size = 12, color = {0.45, 0.30, 0.18}, gap = 18}}
        local order = entry.tab == "craft" and {"GATHERING", "CRAFTING", "SKILLS", "OTHER MEMORIES"}
            or {"TRAINING", "TRADE", "COMPANY", "OTHER MEMORIES"}
        for _, section in ipairs(order) do
            local sectionHasItems = false
            for _, batch in ipairs(activities) do
                if batchSection(batch) == section then
                    if not sectionHasItems then
                        blocks[#blocks + 1] = {text = section, size = 13,
                            color = {0.35, 0.20, 0.10}, gap = 10}
                        sectionHasItems = true
                    end
                    local label = batch.kind == "gather" and "Gathering near " .. batch.place
                        or batch.kind == "craft" and "Crafting at " .. batch.place
                        or batch.kind == "merchant" and "Trading with " .. (batch.vendor or "a merchant")
                        or (batch.raw[1] and batch.raw[1].title) or "A memory"
                    blocks[#blocks + 1] = {text = date("%H:%M", batch.firstAt or time()) .. "  •  " .. label,
                        size = 12, color = {0.45, 0.30, 0.18}, gap = 5}
                    blocks[#blocks + 1] = {text = batchDescription(batch), size = 14, gap = 17}
                end
            end
        end
        renderDetailBlocks(blocks)
        bookmarkButton:Hide()
        linkButton:Hide()
        writeButton:Hide()
    elseif entry.kind == "beast" then
        local beast = entry.beast
        local blocks = {{text = beast.name, size = 20, gap = 6},
            {text = (beast.kills or 0) > 0 and ("I have seen " .. beast.kills .. " fall.")
                or "I found loot linked to this creature, but did not record the fight.", size = 14, gap = 20},
            {text = "WHERE I FOUND THEM", size = 13, gap = 9}}
        local places = {}
        for place, info in pairs(beast.places or {}) do
            places[#places + 1] = place .. "  •  " .. info.count .. " encounter(s)"
        end
        table.sort(places)
        if #places == 0 then places[1] = "Place unknown" end
        for _, place in ipairs(places) do blocks[#blocks + 1] = {text = place, size = 14, gap = 7} end
        blocks[#blocks + 1] = {text = "WHAT I FOUND", size = 13, gap = 9}
        local drops = {}
        for _, drop in pairs(beast.drops or {}) do drops[#drops + 1] = drop.name .. "  ×" .. drop.count end
        table.sort(drops)
        if #drops == 0 then drops[1] = "No loot recorded yet." end
        for _, drop in ipairs(drops) do blocks[#blocks + 1] = {text = drop, size = 14, gap = 7} end
        renderDetailBlocks(blocks)
        bookmarkButton:Hide()
        linkButton:Hide()
        writeButton:Hide()
    elseif entry.kind == "encounterGroup" then
        for _, block in ipairs(detailBlocks) do block.font:Hide(); block.line:Hide() end
        detailText:Show()
        local lines = {"Encounters\nA record of creatures I fought and saw fall.\n"}
        for index = #encounters, math.max(1, #encounters - 49), -1 do
            local encounter = encounters[index]
            local when = encounter.seenAt and date("%d %b %Y, %H:%M", encounter.seenAt) or "Earlier"
            local line = when .. " • " .. encounter.name .. "\nNear " .. (encounter.place or encounter.zone or "an unknown place")
            if encounter.linkedQuestID then line = line .. "\nFiled with " .. questTitle(encounter.linkedQuestID) end
            lines[#lines + 1] = line .. "\n"
        end
        detailText:SetText(table.concat(lines, "\n"))
        bookmarkButton:Disable()
        linkButton:Hide()
        writeButton:Hide()
    else
        for _, block in ipairs(detailBlocks) do block.font:Hide(); block.line:Hide() end
        detailText:Show()
        writeButton:Hide()
        local dateText = entry.seenAt and date("%d %b %Y, %H:%M", entry.seenAt) or "Date unknown"
        local heading = entry.title .. "\n" .. rememberedPlace(entry) .. "  •  " .. dateText
        if entry.speaker ~= "" then heading = heading .. "\n" .. entry.speaker end
        if entry.kind == "quest" or entry.kind == "pastQuest" or entry.kind == "note" or entry.kind == "speech" then
            heading = heading .. "  •  " .. entry.stage
        end
        if entry.linkedQuestID then heading = heading .. "\nLinked quest: " .. questTitle(entry.linkedQuestID) end
        local body = entry.kind == "speech" and ("“" .. entry.body .. "”") or entry.body
        if (entry.kind == "quest" or entry.kind == "pastQuest") and entry.questID then
            for key, related in pairs(entries) do
                if related.linkedQuestID == entry.questID and (related.kind == "note" or related.kind == "speech") then
                    relatedKeys[#relatedKeys + 1] = key
                end
            end
            table.sort(relatedKeys, function(a, b) return (entries[a].order or 0) > (entries[b].order or 0) end)
            if #relatedKeys > 0 then
                body = body .. "\n\nFiled with this quest"
                for _, key in ipairs(relatedKeys) do
                    local related = entries[key]
                    body = body .. "\n• " .. related.title .. " (" .. related.stage .. ")"
                end
            end
            linkButton:SetText("Read related (" .. #relatedKeys .. ")")
            linkButton:SetShown(#relatedKeys > 0)
        elseif entry.kind == "note" or entry.kind == "speech" or entry.kind == "gossip" or entry.kind == "kill" or entry.kind == "pickup" then
            linkButton:SetText(entry.linkedQuestID and "Change quest link" or "Link to quest")
            linkButton:Show()
        else
            linkButton:Hide()
        end
        detailText:SetText(heading .. "\n\n" .. body)
        bookmarkButton:Enable()
        bookmarkButton:Show()
        bookmarkButton:SetText(entry.bookmarked and "Remove bookmark" or "Bookmark")
    end
    if not (entry and (entry.kind == "questGroup" or entry.kind == "lifeDay" or entry.kind == "beast")) then
        detailScrollChild:SetHeight(math.max(380, detailText:GetStringHeight() + 28))
    end
end

function FieldJournal.UI.Refresh()
    if not FieldJournal.UI.window then return end
    visibleKeys = matchingEntries()
    if not FieldJournal.UI.selectedKey and currentTab ~= "quests" and #visibleKeys > 0 then FieldJournal.UI.selectedKey = visibleKeys[1] end
    countText:SetText(#visibleKeys .. (currentTab == "bestiary" and " species"
        or currentTab == "quests" and " quests" or " days"))
    zoneButton:SetText(FieldJournal.UI.zoneFilter)
    zoneButton:SetShown(currentTab == "quests")
    historyButton:SetShown(currentTab == "quests")
    for id, button in pairs(tabButtons) do
        button:GetFontString():SetTextColor(id == currentTab and 0.95 or 0.24,
            id == currentTab and 0.82 or 0.14, id == currentTab and 0.51 or 0.08)
    end
    local offset = math.min(FieldJournal.UI.window.listScroll.offset or 0, math.max(0, #visibleKeys - #rows))
    FieldJournal.UI.window.listScroll.offset = offset
    for i, row in ipairs(rows) do
        local entry = FieldJournal.UI.viewItems[visibleKeys[offset + i]]
        if entry then
            row.key = entry.key
            row.title:SetText((entry.bookmarked and "★ " or "") .. entry.title)
            local stage = entry.kind == "questGroup" and (entry.active and "In progress" or "Quest")
                or entry.kind == "encounterGroup" and (#FieldJournal.encounters .. " remembered")
                or entry.kind == "note" and "Note" or entry.kind == "speech" and entry.stage
                or entry.kind == "gossip" and "Conversation" or entry.kind == "kill" and "Encounter"
                or entry.kind == "lifeDay" and (#(entry.activities or {}) .. " activities · " .. #entry.items .. " records")
                or entry.kind == "beast" and entry.zone or entry.stage or "Entry"
            row.subtitle:SetText((entry.kind == "beast" or entry.kind == "lifeDay")
                and stage or (stage .. " · " .. entry.zone))
            row.selected:SetShown(entry.key == FieldJournal.UI.selectedKey)
            row:Show()
        else
            row.key = nil
            row:Hide()
        end
    end
    if FieldJournal.UI.selectedKey and not FieldJournal.UI.viewItems[FieldJournal.UI.selectedKey] then FieldJournal.UI.selectedKey = nil end
    showDetail(FieldJournal.UI.selectedKey and FieldJournal.UI.viewItems[FieldJournal.UI.selectedKey] or nil)
end

function FieldJournal.UI.RefreshIfShown()
    if FieldJournal.UI.window and FieldJournal.UI.window:IsShown() then FieldJournal.UI.Refresh() end
end

local function createWindow()
    local window = CreateFrame("Frame", "FieldJournalWindow", UIParent)
    FieldJournal.UI.window = window
    window:SetSize(730, 530)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "FieldJournalWindow")

    -- Two parchment pages bound in a dark leather cover.
    coloredRectangle(window, "BACKGROUND", 0.16, 0.095, 0.055, 0.98, 0, 0, 0, 0)
    coloredRectangle(window, "BACKGROUND", 0.48, 0.31, 0.15, 1, 7, -7, -7, 7)
    local leftPaper = window:CreateTexture(nil, "BORDER")
    leftPaper:SetTexture("Interface\\AddOns\\FieldJournal\\art\\parchment.tga")
    leftPaper:SetPoint("TOPLEFT", 13, -47)
    leftPaper:SetPoint("BOTTOMRIGHT", -370, 15)
    local rightPaper = window:CreateTexture(nil, "BORDER")
    rightPaper:SetTexture("Interface\\AddOns\\FieldJournal\\art\\parchment.tga")
    rightPaper:SetPoint("TOPLEFT", 366, -47)
    rightPaper:SetPoint("BOTTOMRIGHT", -13, 15)
    coloredRectangle(window, "ARTWORK", 0.20, 0.12, 0.07, 0.9, 358, -358, -44, 14)
    local title = makeLabel(window, 25, {0.98, 0.81, 0.47})
    title:SetFont("Fonts\\MORPHEUS.TTF", 25, "")
    title:SetPoint("TOPLEFT", 21, -9)
    title:SetText("Field Journal")
    local subtitle = makeLabel(window, 11, {0.76, 0.63, 0.43})
    subtitle:SetPoint("TOPRIGHT", -48, -20)
    subtitle:SetText("YOUR STORY IN AZEROTH")
    local close = makeButton(window, 22, 22, "X")
    close:SetPoint("TOPRIGHT", -7, -8)
    close:SetScript("OnClick", function() window:Hide() end)
    window:Hide()

    local tabList = {{"quests", "Quests"}, {"diary", "Daily diary"},
        {"bestiary", "Bestiary"}, {"craft", "Crafting & gathering"}}
    for index, tab in ipairs(tabList) do
        local button = makeButton(window, 163, 25, tab[2])
        button:SetPoint("TOPLEFT", 28 + (index - 1) * 168, -49)
        button:SetScript("OnClick", function()
            currentTab = tab[1]
            FieldJournal.UI.selectedKey = nil
            FieldJournal.UI.searchText = ""
            FieldJournal.UI.zoneFilter = "All zones"
            if window.search then window.search:SetText("") end
            window.listScroll.offset = 0
            window.detailScroll:SetVerticalScroll(0)
            FieldJournal.UI.Refresh()
        end)
        tabButtons[tab[1]] = button
    end

    coloredRectangle(window, "ARTWORK", 0.64, 0.54, 0.38, 1, 27, -389, -83, 423)
    local search = CreateFrame("EditBox", nil, window)
    window.search = search
    search:SetSize(310, 24)
    search:SetPoint("TOPLEFT", 28, -83)
    search:SetAutoFocus(false)
    search:SetFont(STANDARD_TEXT_FONT, 13, "")
    search:SetTextColor(0.22, 0.14, 0.08)
    search:SetTextInsets(8, 8, 0, 0)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local searchHint = makeLabel(window, 12, {0.45, 0.35, 0.23})
    searchHint:SetPoint("TOPLEFT", search, "TOPLEFT", 8, -5)
    searchHint:SetText("Search your journal")
    search:SetScript("OnTextChanged", function(self)
        FieldJournal.UI.searchText = clean(self:GetText())
        searchHint:SetShown(FieldJournal.UI.searchText == "")
        if window.listScroll then
            window.listScroll.offset = 0
            FieldJournal.UI.Refresh()
        end
    end)

    zoneButton = makeButton(window, 310, 23, "All zones")
    zoneButton:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
    zoneButton:SetScript("OnClick", function()
        local list = zones()
        local nextIndex = 1
        for i, zone in ipairs(list) do
            if zone == FieldJournal.UI.zoneFilter then nextIndex = (i % #list) + 1 break end
        end
        FieldJournal.UI.zoneFilter = list[nextIndex]
        window.listScroll.offset = 0
        FieldJournal.UI.Refresh()
    end)

    countText = makeLabel(window, 11, {0.42, 0.31, 0.20})
    countText:SetPoint("TOPLEFT", zoneButton, "BOTTOMLEFT", 5, -9)

    historyButton = makeButton(window, 310, 23, "Recover earlier stories")
    historyButton:SetPoint("BOTTOMLEFT", 28, 27)
    historyButton:SetScript("OnClick", function() importCompletedQuests(false) end)

    window.listScroll = CreateFrame("Frame", nil, window)
    window.listScroll:SetPoint("TOPLEFT", 25, -166)
    window.listScroll:SetSize(315, 280)
    window.listScroll.offset = 0
    window.listScroll:EnableMouseWheel(true)
    window.listScroll:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, math.min(math.max(0, #visibleKeys - #rows), self.offset - delta * 3))
        FieldJournal.UI.Refresh()
    end)

    for i = 1, 8 do
        local row = CreateFrame("Button", nil, window)
        row:SetSize(305, 34)
        row:SetPoint("TOPLEFT", 27, -166 - (i - 1) * 34)
        row.selected = row:CreateTexture(nil, "ARTWORK")
        row.selected:SetAllPoints()
        row.selected:SetColorTexture(0.48, 0.32, 0.15, 0.22)
        row.title = makeLabel(row, 13, {0.27, 0.15, 0.07})
        row.title:SetPoint("TOPLEFT", 3, -2)
        row.title:SetWidth(285)
        row.title:SetMaxLines(1)
        row.subtitle = makeLabel(row, 11, {0.47, 0.37, 0.24})
        row.subtitle:SetPoint("TOPLEFT", 3, -18)
        row.subtitle:SetWidth(285)
        row.subtitle:SetMaxLines(1)
        row:SetScript("OnClick", function(self)
            FieldJournal.UI.selectedKey = self.key
            if FieldJournal.UI.questPicker then FieldJournal.UI.questPicker:Hide() end
            window.detailScroll:SetVerticalScroll(0)
            FieldJournal.UI.Refresh()
        end)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            window.listScroll.offset = math.max(0, math.min(math.max(0, #visibleKeys - #rows), window.listScroll.offset - delta * 3))
            FieldJournal.UI.Refresh()
        end)
        rows[i] = row
    end

    local scroll = CreateFrame("ScrollFrame", nil, window)
    window.detailScroll = scroll
    scroll:SetPoint("TOPLEFT", 390, -90)
    scroll:SetPoint("BOTTOMRIGHT", -36, 106)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 32)))
    end)
    detailScrollChild = CreateFrame("Frame", nil, scroll)
    detailScrollChild:SetWidth(295)
    detailScrollChild:SetHeight(380)
    scroll:SetScrollChild(detailScrollChild)
    detailText = makeLabel(detailScrollChild, 15, {0.25, 0.15, 0.08})
    detailText:SetPoint("TOPLEFT", 0, 0)
    detailText:SetWidth(292)
    detailText:SetSpacing(4)

    bookmarkButton = makeButton(window, 150, 25, "Bookmark")
    bookmarkButton:SetPoint("BOTTOMLEFT", 390, 28)
    bookmarkButton:SetScript("OnClick", function()
        local entry = FieldJournal.UI.selectedKey and FieldJournal.UI.viewItems[FieldJournal.UI.selectedKey]
        if entry then
            if entry.kind == "questGroup" then
                FieldJournal.questBookmarks[entry.questID] = not entry.bookmarked or nil
            else
                entry.bookmarked = not entry.bookmarked
            end
            FieldJournal.UI.Refresh()
        end
    end)
    linkButton = makeButton(window, 150, 25, "Link to quest")
    linkButton:SetPoint("BOTTOMLEFT", 546, 28)
    linkButton:SetScript("OnClick", function()
        local entry = FieldJournal.UI.selectedKey and FieldJournal.UI.viewItems[FieldJournal.UI.selectedKey]
        if not entry then return end
        if entry.kind == "note" or entry.kind == "speech" or entry.kind == "gossip" or entry.kind == "kill" or entry.kind == "pickup" then
            openQuestPicker()
        elseif relatedKeys[1] then
            relatedIndex = (relatedIndex % #relatedKeys) + 1
            FieldJournal.UI.selectedKey = relatedKeys[relatedIndex]
            scroll:SetVerticalScroll(0)
            FieldJournal.UI.Refresh()
        end
    end)

    writeButton = makeButton(window, 306, 25, "Write in the margin")
    writeButton:SetPoint("BOTTOMLEFT", 390, 60)
    writeButton:SetScript("OnClick", function()
        local entry = FieldJournal.UI.selectedKey and FieldJournal.UI.viewItems[FieldJournal.UI.selectedKey]
        if not entry or entry.kind ~= "questGroup" then return end
        FieldJournal.UI.noteEditor.questID = entry.questID
        FieldJournal.UI.noteEditor.title:SetText("A note on " .. entry.title)
        FieldJournal.UI.noteEditBox:SetText("")
        FieldJournal.UI.noteEditor:Show()
        FieldJournal.UI.noteEditBox:SetFocus()
    end)

    local noteEditor = CreateFrame("Frame", nil, window)
    FieldJournal.UI.noteEditor = noteEditor
    noteEditor:SetSize(306, 265)
    noteEditor:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -21, 60)
    noteEditor:SetFrameLevel(window:GetFrameLevel() + 20)
    coloredRectangle(noteEditor, "BACKGROUND", 0.28, 0.17, 0.09, 1, 0, 0, 0, 0)
    local editorPaper = noteEditor:CreateTexture(nil, "BORDER")
    editorPaper:SetTexture("Interface\\AddOns\\FieldJournal\\art\\parchment.tga")
    editorPaper:SetPoint("TOPLEFT", 4, -4)
    editorPaper:SetPoint("BOTTOMRIGHT", -4, 4)
    noteEditor.title = makeLabel(noteEditor, 14, {0.27, 0.15, 0.07})
    noteEditor.title:SetPoint("TOPLEFT", 13, -12)
    noteEditor.title:SetWidth(260)
    noteEditor.title:SetMaxLines(1)
    local noteEditBox = CreateFrame("EditBox", nil, noteEditor)
    FieldJournal.UI.noteEditBox = noteEditBox
    noteEditBox:SetSize(278, 172)
    noteEditBox:SetPoint("TOPLEFT", 14, -44)
    noteEditBox:SetAutoFocus(false)
    noteEditBox:SetMultiLine(true)
    noteEditBox:SetMaxLetters(1200)
    noteEditBox:SetFont(STANDARD_TEXT_FONT, 13, "")
    noteEditBox:SetTextColor(0.25, 0.15, 0.08)
    noteEditBox:SetScript("OnEscapePressed", function() noteEditor:Hide() end)
    local saveNote = makeButton(noteEditor, 130, 25, "Save note")
    saveNote:SetPoint("BOTTOMLEFT", 14, 12)
    saveNote:SetScript("OnClick", function()
        local body = clean(noteEditBox:GetText())
        if body ~= "" and noteEditor.questID then
            addEntry("margin", noteEditor.questID, "My note", questTitle(noteEditor.questID), body, "")
            FieldJournal.UI.selectedKey = "quest:" .. noteEditor.questID
        end
        noteEditor:Hide()
        FieldJournal.UI.Refresh()
    end)
    local cancelNote = makeButton(noteEditor, 130, 25, "Cancel")
    cancelNote:SetPoint("BOTTOMRIGHT", -14, 12)
    cancelNote:SetScript("OnClick", function() noteEditor:Hide() end)
    noteEditor:Hide()

    local questPicker = CreateFrame("Frame", nil, window)
    FieldJournal.UI.questPicker = questPicker
    questPicker:SetSize(306, 300)
    questPicker:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -21, 60)
    questPicker:SetFrameLevel(window:GetFrameLevel() + 20)
    coloredRectangle(questPicker, "BACKGROUND", 0.28, 0.17, 0.09, 1, 0, 0, 0, 0)
    local pickerPaper = questPicker:CreateTexture(nil, "BORDER")
    pickerPaper:SetTexture("Interface\\AddOns\\FieldJournal\\art\\parchment.tga")
    pickerPaper:SetPoint("TOPLEFT", 4, -4)
    pickerPaper:SetPoint("BOTTOMRIGHT", -4, 4)
    local pickerTitle = makeLabel(questPicker, 15, {0.27, 0.15, 0.07})
    pickerTitle:SetPoint("TOPLEFT", 13, -12)
    pickerTitle:SetText("Link to a quest")
    local pickerClose = makeButton(questPicker, 22, 22, "X")
    pickerClose:SetPoint("TOPRIGHT", -8, -8)
    pickerClose:SetScript("OnClick", function() questPicker:Hide() end)
    questPicker.rows = {}
    for index = 1, 7 do
        local row = makeButton(questPicker, 278, 27, "")
        row:SetPoint("TOPLEFT", 14, -45 - (index - 1) * 31)
        row:SetScript("OnClick", function(self)
            local option = self.option
            local entry = FieldJournal.UI.selectedKey and FieldJournal.entries[FieldJournal.UI.selectedKey]
            if not option or not entry then return end
            entry.linkedQuestID = option.remove and nil or option.id
            questPicker:Hide()
            FieldJournal.UI.Refresh()
        end)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            questPicker.offset = math.max(0, math.min(math.max(0, #questPicker.options - #questPicker.rows), questPicker.offset - delta * 3))
            refreshQuestPicker()
        end)
        questPicker.rows[index] = row
    end
    questPicker.count = makeLabel(questPicker, 11, {0.42, 0.31, 0.20})
    questPicker.count:SetPoint("BOTTOMLEFT", 15, 14)
    questPicker:EnableMouseWheel(true)
    questPicker:SetScript("OnMouseWheel", function(_, delta)
        questPicker.offset = math.max(0, math.min(math.max(0, #questPicker.options - #questPicker.rows), questPicker.offset - delta * 3))
        refreshQuestPicker()
    end)
    questPicker:Hide()
    window:SetScript("OnShow", function()
        if initializeCharacter then initializeCharacter() end
        syncActiveQuestLog()
        FieldJournal.UI.Refresh()
    end)
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
    groupSnapshot = currentGroup()

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
        if questID then
            local speaker = questSpeaker()
            if clean(speaker) ~= "" then recentQuestContexts[questID] = {speaker = speaker, at = time(), zone = currentZone()} end
            addEntry("questStatus", questID, "Accepted", questTitle(questID), "Added to my quest log.", questSpeaker())
            syncActiveQuestLog()
        end
    elseif event == "QUEST_TURNED_IN" then
        local questID = name
        if questID then
            addEntry("questStatus", questID, "Turned in", questTitle(questID), "I turned in this quest.", questSpeaker())
        end
    elseif event == "QUEST_LOG_UPDATE" then
        syncActiveQuestLog()
    elseif event == "GOSSIP_SHOW" then
        if C_GossipInfo and C_GossipInfo.GetText then
            local speaker = questSpeaker()
            local linked = findUniqueQuestMention(speaker)
            if not linked then
                for id, context in pairs(recentQuestContexts) do
                    if context.speaker == speaker and time() - context.at <= 300 then linked = id end
                end
            end
            addEntry("gossip", nil, "Conversation", speaker, C_GossipInfo.GetText(), speaker, linked)
        end
    elseif event == "ITEM_TEXT_BEGIN" then
        activeNoteTitle = clean((ItemTextGetItem and ItemTextGetItem()) or "")
        activeNoteKey = nil
    elseif event == "ITEM_TEXT_READY" then
        captureNotePage()
    elseif event == "ITEM_TEXT_CLOSED" then
        activeNoteTitle = nil
        activeNoteKey = nil
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
        trainerContext = {name = questSpeaker(), place = currentPlace(), at = time()}
    elseif event == "TRAINER_CLOSED" then
        if trainerContext then trainerContext.at = time() end
    elseif event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        learnedSpell(name)
    elseif event == "CHAT_MSG_SKILL" then
        recordSkillMessage(name)
    elseif event == "CHAT_MSG_TRADESKILLS" then
        if type(name) == "string" and accessible(name) then
            local id, item = name:match("|Hitem:(%d+).-|h%[(.-)%]|h")
            if id then recordCraft(tonumber(id), item, 1) end
        end
    elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
        local data = name
        if type(data) == "table" then recordCraft(data.itemID, data.hyperlink, data.quantity or 1) end
    elseif event == "GROUP_ROSTER_UPDATE" then
        updateGroup()
    elseif event == "MERCHANT_SHOW" then
        local items, names = bagSnapshot()
        merchantContext = {name = clean(questSpeaker()) ~= "" and questSpeaker() or "a merchant",
            place = currentPlace(), money = GetMoney and GetMoney() or 0,
            items = items, names = names}
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_MONEY" then
        if merchantContext and C_Timer and C_Timer.After then C_Timer.After(0.1, checkMerchant) end
    elseif event == "MERCHANT_CLOSED" then
        checkMerchant()
        merchantContext = nil
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
