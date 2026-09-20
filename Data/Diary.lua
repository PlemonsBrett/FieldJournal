-- Field Journal: the daily diary - training, company and trade capture, plus the
-- batching and formatting helpers the diary and crafting day-pages both render with.

local FieldJournal = select(2, ...)
FieldJournal.Diary = FieldJournal.Diary or {}

local clean = FieldJournal.clean
local accessible = FieldJournal.accessible
local currentZone = FieldJournal.currentZone
local currentPlace = FieldJournal.currentPlace
local currentMapPosition = FieldJournal.currentMapPosition
local itemName = FieldJournal.itemName
local moneyText = FieldJournal.moneyText

local merchantContext
local trainerContext
local groupSnapshot
local recentTraining = {}

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

local function resetGroupSnapshot()
    groupSnapshot = currentGroup()
end

local function trainerShown()
    trainerContext = {name = FieldJournal.QuestLog.questSpeaker(), place = currentPlace(), at = time()}
end

local function trainerClosed()
    if trainerContext then trainerContext.at = time() end
end

local function merchantShown()
    local items, names = bagSnapshot()
    merchantContext = {name = clean(FieldJournal.QuestLog.questSpeaker()) ~= "" and FieldJournal.QuestLog.questSpeaker() or "a merchant",
        place = currentPlace(), money = GetMoney and GetMoney() or 0,
        items = items, names = names}
end

local function merchantBagUpdate()
    if merchantContext and C_Timer and C_Timer.After then C_Timer.After(0.1, checkMerchant) end
end

local function merchantClosed()
    checkMerchant()
    merchantContext = nil
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

FieldJournal.Diary.addLifeEvent = addLifeEvent
FieldJournal.Diary.spellName = spellName
FieldJournal.Diary.learnedSpell = learnedSpell
FieldJournal.Diary.currentGroup = currentGroup
FieldJournal.Diary.updateGroup = updateGroup
FieldJournal.Diary.resetGroupSnapshot = resetGroupSnapshot
FieldJournal.Diary.bagSnapshot = bagSnapshot
FieldJournal.Diary.checkMerchant = checkMerchant
FieldJournal.Diary.trainerShown = trainerShown
FieldJournal.Diary.trainerClosed = trainerClosed
FieldJournal.Diary.merchantShown = merchantShown
FieldJournal.Diary.merchantBagUpdate = merchantBagUpdate
FieldJournal.Diary.merchantClosed = merchantClosed
FieldJournal.Diary.readableItemName = readableItemName
FieldJournal.Diary.addBatchItem = addBatchItem
FieldJournal.Diary.merchantItems = merchantItems
FieldJournal.Diary.groupLifeEvents = groupLifeEvents
FieldJournal.Diary.itemSummary = itemSummary
FieldJournal.Diary.batchSection = batchSection
FieldJournal.Diary.batchDescription = batchDescription
FieldJournal.Diary.buildLifeViews = buildLifeViews
