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
FieldJournal.frame = CreateFrame("Frame")
FieldJournal.UI.zoneFilter = "All zones"
FieldJournal.UI.searchText = ""
FieldJournal.UI.viewItems = {}
local recentDeaths = {}
local observedUnits = {}
local observedUnitCount = 0
local lootSlots = {}
local merchantContext
local trainerContext
local groupSnapshot
local recentCrafts = {}
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
FieldJournal.Diary.groupLifeEvents = groupLifeEvents

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
FieldJournal.Diary.batchSection = batchSection

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
FieldJournal.Diary.batchDescription = batchDescription

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
FieldJournal.Diary.buildLifeViews = buildLifeViews

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
