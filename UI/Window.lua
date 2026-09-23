-- Field Journal: the journal window - tabs, the entry list, and the detail pane.

local FieldJournal = select(2, ...)
FieldJournal.UI = FieldJournal.UI or {}

local clean = FieldJournal.clean

local rows = {}
local visibleKeys = {}
local detailBlocks = {}
local relatedKeys = {}
local relatedIndex = 0
local currentTab = "quests"
local tabButtons = {}
local ALL_TABS = {{"quests", "Quests"}, {"diary", "Daily diary"},
    {"bestiary", "Bestiary"}, {"craft", "Crafting & gathering"}}

-- Pure: no frame calls, so this is the one piece of this file's tab logic
-- that can run under tests/wow_env.lua. Quests is never hideable -- it is
-- the addon's core feature, not an optional collection like the other three.
local function visibleTabs()
    local profile = FieldJournal.db and FieldJournal.db.profile
    local result = {}
    for _, tab in ipairs(ALL_TABS) do
        local key = tab[1]
        local show = key == "quests"
            or (key == "diary" and (not profile or profile.showDiary ~= false))
            or (key == "bestiary" and (not profile or profile.showBestiary ~= false))
            or (key == "craft" and (not profile or profile.showCrafting ~= false))
        if show then result[#result + 1] = tab end
    end
    return result
end
local zoneButton
local detailText
local detailScrollChild
local bookmarkButton
local linkButton
local writeButton
local countText
local historyButton

local function matchingEntries()
    if currentTab == "diary" then return FieldJournal.Diary.buildLifeViews(FieldJournal.diaryEvents, "diary") end
    if currentTab == "bestiary" then return FieldJournal.Bestiary.buildBestiaryViews() end
    if currentTab == "craft" then return FieldJournal.Diary.buildLifeViews(FieldJournal.craftEvents, "craft") end
    return FieldJournal.QuestLog.buildQuestViews()
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
                font = FieldJournal.UI.makeLabel(detailScrollChild, 15, {0.25, 0.15, 0.08}),
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
        local activities = entry.activities or FieldJournal.Diary.groupLifeEvents(entry.items)
        local blocks = {{text = entry.title, size = 20, gap = 5},
            {text = #activities .. " activities from " .. #entry.items .. " records",
                size = 12, color = {0.45, 0.30, 0.18}, gap = 18}}
        local order = entry.tab == "craft" and {"GATHERING", "CRAFTING", "SKILLS", "OTHER MEMORIES"}
            or {"TRAINING", "TRADE", "COMPANY", "OTHER MEMORIES"}
        for _, section in ipairs(order) do
            local sectionHasItems = false
            for _, batch in ipairs(activities) do
                if FieldJournal.Diary.batchSection(batch) == section then
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
                    blocks[#blocks + 1] = {text = FieldJournal.Diary.batchDescription(batch), size = 14, gap = 17}
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
            if encounter.linkedQuestID then line = line .. "\nFiled with " .. FieldJournal.QuestLog.questTitle(encounter.linkedQuestID) end
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
        if entry.linkedQuestID then heading = heading .. "\nLinked quest: " .. FieldJournal.QuestLog.questTitle(entry.linkedQuestID) end
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

-- Repositions the tab row so a hidden tab leaves no gap, and falls back to
-- "quests" if the tab currently being viewed just became hidden. Called once
-- at window creation and again by Task 8's settings-panel checkboxes whenever
-- a visibility setting changes.
local function layoutTabs()
    local shown = {}
    for _, tab in ipairs(visibleTabs()) do shown[tab[1]] = true end
    local index = 0
    for _, tab in ipairs(ALL_TABS) do
        local button = tabButtons[tab[1]]
        if button then
            if shown[tab[1]] then
                index = index + 1
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", 28 + (index - 1) * 168, -49)
                button:Show()
            else
                button:Hide()
            end
        end
    end
    if not shown[currentTab] then
        currentTab = "quests"
        if FieldJournal.db and FieldJournal.db.profile then FieldJournal.db.profile.lastTab = "quests" end
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

-- Captures the window's current on-screen position into the account-wide
-- profile (shared across characters that opt into the same AceDB profile).
-- Nil-guarded: FieldJournal.db can be nil if the database failed to open.
local function saveWindowPosition(window)
    if not FieldJournal.db or not FieldJournal.db.profile then return end
    local point, _, relativePoint, x, y = window:GetPoint()
    if not point then return end
    FieldJournal.db.profile.windowPoint = {point = point, relativePoint = relativePoint, x = x, y = y}
end

-- Restores a previously saved position, falling back to the original default
-- (screen center) when there is nothing saved yet or the database is nil.
local function restoreWindowPosition(window)
    local saved = FieldJournal.db and FieldJournal.db.profile and FieldJournal.db.profile.windowPoint
    if not saved then
        window:SetPoint("CENTER")
        return
    end
    window:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
end

local function createWindow()
    local window = CreateFrame("Frame", "FieldJournalWindow", UIParent)
    FieldJournal.UI.window = window
    window:SetSize(730, 530)
    restoreWindowPosition(window)
    if FieldJournal.db and FieldJournal.db.profile and FieldJournal.db.profile.lastTab then
        currentTab = FieldJournal.db.profile.lastTab
    end
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveWindowPosition(self)
    end)
    window:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "FieldJournalWindow")

    -- Two parchment pages bound in a dark leather cover.
    FieldJournal.UI.coloredRectangle(window, "BACKGROUND", 0.16, 0.095, 0.055, 0.98, 0, 0, 0, 0)
    FieldJournal.UI.coloredRectangle(window, "BACKGROUND", 0.48, 0.31, 0.15, 1, 7, -7, -7, 7)
    local leftPaper = window:CreateTexture(nil, "BORDER")
    leftPaper:SetTexture("Interface\\AddOns\\FieldJournal\\art\\parchment.tga")
    leftPaper:SetPoint("TOPLEFT", 13, -47)
    leftPaper:SetPoint("BOTTOMRIGHT", -370, 15)
    local rightPaper = window:CreateTexture(nil, "BORDER")
    rightPaper:SetTexture("Interface\\AddOns\\FieldJournal\\art\\parchment.tga")
    rightPaper:SetPoint("TOPLEFT", 366, -47)
    rightPaper:SetPoint("BOTTOMRIGHT", -13, 15)
    FieldJournal.UI.coloredRectangle(window, "ARTWORK", 0.20, 0.12, 0.07, 0.9, 358, -358, -44, 14)
    local title = FieldJournal.UI.makeLabel(window, 25, {0.98, 0.81, 0.47})
    title:SetFont("Fonts\\MORPHEUS.TTF", 25, "")
    title:SetPoint("TOPLEFT", 21, -9)
    title:SetText("Field Journal")
    local subtitle = FieldJournal.UI.makeLabel(window, 11, {0.76, 0.63, 0.43})
    subtitle:SetPoint("TOPRIGHT", -48, -20)
    subtitle:SetText("YOUR STORY IN AZEROTH")
    local close = FieldJournal.UI.makeButton(window, 22, 22, "X")
    close:SetPoint("TOPRIGHT", -7, -8)
    close:SetScript("OnClick", function() window:Hide() end)
    local settingsButton = FieldJournal.UI.makeButton(window, 22, 22, "*")
    settingsButton:SetPoint("TOPRIGHT", close, "TOPLEFT", -4, 0)
    settingsButton:SetScript("OnClick", function()
        if FieldJournal.UI.settingsPanel then FieldJournal.UI.settingsPanel:Show() end
    end)
    window:Hide()

    -- All four buttons are always created (toggling a setting must not require
    -- rebuilding the window), and layoutTabs() decides which are shown and
    -- where, every time visibility can have changed.
    for index, tab in ipairs(ALL_TABS) do
        local button = FieldJournal.UI.makeButton(window, 163, 25, tab[2])
        button:SetPoint("TOPLEFT", 28 + (index - 1) * 168, -49)
        button:SetScript("OnClick", function()
            currentTab = tab[1]
            if FieldJournal.db and FieldJournal.db.profile then FieldJournal.db.profile.lastTab = tab[1] end
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

    FieldJournal.UI.coloredRectangle(window, "ARTWORK", 0.64, 0.54, 0.38, 1, 27, -389, -83, 423)
    local search = CreateFrame("EditBox", nil, window)
    window.search = search
    search:SetSize(310, 24)
    search:SetPoint("TOPLEFT", 28, -83)
    search:SetAutoFocus(false)
    search:SetFont(STANDARD_TEXT_FONT, 13, "")
    search:SetTextColor(0.22, 0.14, 0.08)
    search:SetTextInsets(8, 8, 0, 0)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local searchHint = FieldJournal.UI.makeLabel(window, 12, {0.45, 0.35, 0.23})
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

    zoneButton = FieldJournal.UI.makeButton(window, 310, 23, "All zones")
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

    countText = FieldJournal.UI.makeLabel(window, 11, {0.42, 0.31, 0.20})
    countText:SetPoint("TOPLEFT", zoneButton, "BOTTOMLEFT", 5, -9)

    historyButton = FieldJournal.UI.makeButton(window, 310, 23, "Recover earlier stories")
    historyButton:SetPoint("BOTTOMLEFT", 28, 27)
    historyButton:SetScript("OnClick", function() FieldJournal.QuestLog.importCompletedQuests(false) end)

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
        row.title = FieldJournal.UI.makeLabel(row, 13, {0.27, 0.15, 0.07})
        row.title:SetPoint("TOPLEFT", 3, -2)
        row.title:SetWidth(285)
        row.title:SetMaxLines(1)
        row.subtitle = FieldJournal.UI.makeLabel(row, 11, {0.47, 0.37, 0.24})
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
    detailText = FieldJournal.UI.makeLabel(detailScrollChild, 15, {0.25, 0.15, 0.08})
    detailText:SetPoint("TOPLEFT", 0, 0)
    detailText:SetWidth(292)
    detailText:SetSpacing(4)

    bookmarkButton = FieldJournal.UI.makeButton(window, 150, 25, "Bookmark")
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
    linkButton = FieldJournal.UI.makeButton(window, 150, 25, "Link to quest")
    linkButton:SetPoint("BOTTOMLEFT", 546, 28)
    linkButton:SetScript("OnClick", function()
        local entry = FieldJournal.UI.selectedKey and FieldJournal.UI.viewItems[FieldJournal.UI.selectedKey]
        if not entry then return end
        if entry.kind == "note" or entry.kind == "speech" or entry.kind == "gossip" or entry.kind == "kill" or entry.kind == "pickup" then
            FieldJournal.UI.openQuestPicker()
        elseif relatedKeys[1] then
            relatedIndex = (relatedIndex % #relatedKeys) + 1
            FieldJournal.UI.selectedKey = relatedKeys[relatedIndex]
            scroll:SetVerticalScroll(0)
            FieldJournal.UI.Refresh()
        end
    end)

    writeButton = FieldJournal.UI.makeButton(window, 306, 25, "Write in the margin")
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

    layoutTabs()
    FieldJournal.UI.createNoteEditor()
    FieldJournal.UI.createQuestPicker()
    FieldJournal.UI.createSettingsPanel()
    window:SetScript("OnShow", function()
        if FieldJournal.initializeCharacter then FieldJournal.initializeCharacter() end
        FieldJournal.QuestLog.syncActiveQuestLog()
        FieldJournal.UI.Refresh()
    end)
end

FieldJournal.UI.visibleTabs = visibleTabs
FieldJournal.UI.layoutTabs = layoutTabs
FieldJournal.UI.matchingEntries = matchingEntries
FieldJournal.UI.zones = zones
FieldJournal.UI.renderDetailBlocks = renderDetailBlocks
FieldJournal.UI.rememberedWhen = rememberedWhen
FieldJournal.UI.rememberedPlace = rememberedPlace
FieldJournal.UI.questStageStory = questStageStory
FieldJournal.UI.marginStory = marginStory
FieldJournal.UI.showDetail = showDetail
FieldJournal.UI.saveWindowPosition = saveWindowPosition
FieldJournal.UI.restoreWindowPosition = restoreWindowPosition
FieldJournal.UI.createWindow = createWindow
