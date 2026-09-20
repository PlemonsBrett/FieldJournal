-- Field Journal: creature observation, encounter recording, loot attribution
-- and the species index the Bestiary tab renders.

local FieldJournal = select(2, ...)
FieldJournal.Bestiary = FieldJournal.Bestiary or {}

local clean = FieldJournal.clean
local accessible = FieldJournal.accessible
local currentZone = FieldJournal.currentZone
local currentPlace = FieldJournal.currentPlace
local currentMapPosition = FieldJournal.currentMapPosition
local creatureIDFromGUID = FieldJournal.creatureIDFromGUID

local recentDeaths = {}
local observedUnits = {}
local observedUnitCount = 0
local lootSlots = {}

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
    if not name:find("^Unidentified creature") then questID = FieldJournal.QuestLog.findUniqueQuestMention(name) end
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
        FieldJournal.QuestLog.addEntry("kill", nil, "Encounter", name,
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
    local questID = tonumber(loot.questID) or FieldJournal.QuestLog.findUniqueQuestMention(loot.name)
    if questID and loot.questItem then
        local body = "I picked up " .. loot.name
            .. (sourceName and (" from " .. sourceName) or (" near " .. currentPlace())) .. "."
        FieldJournal.QuestLog.addEntry("pickup", nil, "Found", loot.name, body, "", questID)
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

local function clearLootSlots()
    wipe(lootSlots)
end

local function partyKill(sourceGUID, targetGUID)
    if targetGUID and accessible(targetGUID)
        and type(targetGUID) == "string"
        and (targetGUID:find("^Creature%-") or targetGUID:find("^Vehicle%-")) then
        observeUnit("target")
        local personal = false
        if sourceGUID and accessible(sourceGUID) then
            personal = sourceGUID == UnitGUID("player") or sourceGUID == UnitGUID("pet")
        end
        recordEncounter(targetGUID, observedName(targetGUID), personal and "personal" or "party")
    end
end

local function unitDied(guid)
    if guid and accessible(guid) and type(guid) == "string" then
        local observed = observedUnits[guid]
        if observed and observed.engaged and GetTime() - observed.at < 90 then
            recordEncounter(guid, observed.name, "observed")
        end
    end
end

FieldJournal.Bestiary.observeUnit = observeUnit
FieldJournal.Bestiary.observedName = observedName
FieldJournal.Bestiary.recordEncounter = recordEncounter
FieldJournal.Bestiary.captureLootSlots = captureLootSlots
FieldJournal.Bestiary.commitLootSlot = commitLootSlot
FieldJournal.Bestiary.clearLootSlots = clearLootSlots
FieldJournal.Bestiary.partyKill = partyKill
FieldJournal.Bestiary.unitDied = unitDied
FieldJournal.Bestiary.buildBestiaryViews = buildBestiaryViews
