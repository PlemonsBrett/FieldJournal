-- Field Journal: quest, speech, note and gossip capture, and the quest-grouped
-- view the Quests tab renders.

local FieldJournal = select(2, ...)
FieldJournal.QuestLog = FieldJournal.QuestLog or {}

local clean = FieldJournal.clean
local currentZone = FieldJournal.currentZone
local currentPlace = FieldJournal.currentPlace
local currentMapPosition = FieldJournal.currentMapPosition

local pendingSpeech = {}
local recentQuestContexts = {}
local activeNoteTitle
local activeNoteKey

local function recoveredBody(questID)
    local recoveredQuestText = FieldJournal.recoveredQuestText
    local text = recoveredQuestText and recoveredQuestText[questID]
    if not text then return nil end
    local class = UnitClass("player") or "adventurer"
    return "Quest description\n\n" .. text:gsub("%$c", class)
end

local function addEntry(kind, id, stage, title, body, speaker, linkedQuestID)
    local db, entries = FieldJournal.charData, FieldJournal.entries
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
    local db, entries = FieldJournal.charData, FieldJournal.entries
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

local function isPlaceholder(entry)
    if not entry or entry.kind ~= "pastQuest" then return false end
    local body = entry.body or ""
    return body:find("This quest was completed before Field Journal", 1, true) ~= nil
        or body:find("The original words have not been found", 1, true) ~= nil
end

local function importCompletedQuests(silent)
    local db, entries = FieldJournal.charData, FieldJournal.entries
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

local function buildQuestViews()
    local entries, questBookmarks = FieldJournal.entries, FieldJournal.questBookmarks
    local searchText, zoneFilter = FieldJournal.UI.searchText, FieldJournal.UI.zoneFilter
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

local function beginNote()
    activeNoteTitle = clean((ItemTextGetItem and ItemTextGetItem()) or "")
    activeNoteKey = nil
end

local function closeNote()
    activeNoteTitle = nil
    activeNoteKey = nil
end

local function questAccepted(questID)
    if questID then
        local speaker = questSpeaker()
        if clean(speaker) ~= "" then
            recentQuestContexts[questID] = {speaker = speaker, at = time(), zone = currentZone()}
        end
        addEntry("questStatus", questID, "Accepted", questTitle(questID), "Added to my quest log.", questSpeaker())
        syncActiveQuestLog()
    end
end

local function captureGossip()
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
end

FieldJournal.QuestLog.recoveredBody = recoveredBody
FieldJournal.QuestLog.addEntry = addEntry
FieldJournal.QuestLog.questTitle = questTitle
FieldJournal.QuestLog.findUniqueQuestMention = findUniqueQuestMention
FieldJournal.QuestLog.updateNoteBody = updateNoteBody
FieldJournal.QuestLog.captureNotePage = captureNotePage
FieldJournal.QuestLog.captureSpeech = captureSpeech
FieldJournal.QuestLog.flushPendingSpeech = flushPendingSpeech
FieldJournal.QuestLog.isPlaceholder = isPlaceholder
FieldJournal.QuestLog.importCompletedQuests = importCompletedQuests
FieldJournal.QuestLog.questSpeaker = questSpeaker
FieldJournal.QuestLog.linkRecentConversation = linkRecentConversation
FieldJournal.QuestLog.captureQuest = captureQuest
FieldJournal.QuestLog.activeQuests = activeQuests
FieldJournal.QuestLog.syncActiveQuestLog = syncActiveQuestLog
FieldJournal.QuestLog.buildQuestViews = buildQuestViews
FieldJournal.QuestLog.beginNote = beginNote
FieldJournal.QuestLog.closeNote = closeNote
FieldJournal.QuestLog.questAccepted = questAccepted
FieldJournal.QuestLog.captureGossip = captureGossip
