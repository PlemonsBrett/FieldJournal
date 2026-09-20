-- Field Journal: shared namespace and root helpers.
-- WoW passes (addonName, addonTable) as the vararg of every file in an addon;
-- that addonTable is the single namespace every Field Journal module shares.

local addonName, FieldJournal = ...

FieldJournal.QuestLog = FieldJournal.QuestLog or {}
FieldJournal.Bestiary = FieldJournal.Bestiary or {}
FieldJournal.Diary = FieldJournal.Diary or {}
FieldJournal.Crafting = FieldJournal.Crafting or {}
FieldJournal.UI = FieldJournal.UI or {}

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
