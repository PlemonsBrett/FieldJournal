-- Field Journal: crafting, gathering and trade-skill milestone capture.
-- These all append to FieldJournal.craftEvents, which the Crafting tab renders.

local FieldJournal = select(2, ...)
FieldJournal.Crafting = FieldJournal.Crafting or {}

local clean = FieldJournal.clean
local accessible = FieldJournal.accessible
local currentPlace = FieldJournal.currentPlace
local itemName = FieldJournal.itemName

local recentCrafts = {}

local function recordCraft(itemID, name, count)
    local craftEvents = FieldJournal.craftEvents
    name = itemName(itemID, name)
    if name == "" then return end
    local key = tostring(itemID or name)
    if recentCrafts[key] and time() - recentCrafts[key] < 3 then return end
    recentCrafts[key] = time()
    FieldJournal.Diary.addLifeEvent(craftEvents, "craft", "Crafted " .. name,
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
        FieldJournal.Diary.addLifeEvent(craftEvents, "milestone", skill .. " reached " .. level,
            "At " .. currentPlace() .. ", my " .. skill .. " skill reached " .. level .. ".")
    end
end

local function recordGather(loot, count, guid)
    FieldJournal.Diary.addLifeEvent(FieldJournal.craftEvents, "gather", "Collected " .. loot.name,
        "Near " .. currentPlace() .. ", I collected " .. loot.name .. ".",
        {itemID = loot.itemID, count = count, sourceGUID = guid})
end

local function tradeskillMessage(message)
    if type(message) == "string" and accessible(message) then
        local id, item = message:match("|Hitem:(%d+).-|h%[(.-)%]|h")
        if id then recordCraft(tonumber(id), item, 1) end
    end
end

local function craftedResult(data)
    if type(data) == "table" then recordCraft(data.itemID, data.hyperlink, data.quantity or 1) end
end

FieldJournal.Crafting.recordCraft = recordCraft
FieldJournal.Crafting.recordSkillMessage = recordSkillMessage
FieldJournal.Crafting.recordGather = recordGather
FieldJournal.Crafting.tradeskillMessage = tradeskillMessage
FieldJournal.Crafting.craftedResult = craftedResult
