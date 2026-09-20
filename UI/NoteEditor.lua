-- Field Journal: the margin-note editor and the quest-link picker.
-- Both widgets are built as children of FieldJournal.UI.window by
-- FieldJournal.UI.createWindow().

local FieldJournal = select(2, ...)
FieldJournal.UI = FieldJournal.UI or {}

local clean = FieldJournal.clean

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
            and entry.questID and not FieldJournal.QuestLog.isPlaceholder(entry) and not seen[entry.questID] then
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

local function createNoteEditor()
    local window = FieldJournal.UI.window
    local noteEditor = CreateFrame("Frame", nil, window)
    FieldJournal.UI.noteEditor = noteEditor
    noteEditor:SetSize(306, 265)
    noteEditor:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -21, 60)
    noteEditor:SetFrameLevel(window:GetFrameLevel() + 20)
    FieldJournal.UI.coloredRectangle(noteEditor, "BACKGROUND", 0.28, 0.17, 0.09, 1, 0, 0, 0, 0)
    local editorPaper = noteEditor:CreateTexture(nil, "BORDER")
    editorPaper:SetTexture("Interface\\AddOns\\FieldJournal\\art\\parchment.tga")
    editorPaper:SetPoint("TOPLEFT", 4, -4)
    editorPaper:SetPoint("BOTTOMRIGHT", -4, 4)
    noteEditor.title = FieldJournal.UI.makeLabel(noteEditor, 14, {0.27, 0.15, 0.07})
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
    local saveNote = FieldJournal.UI.makeButton(noteEditor, 130, 25, "Save note")
    saveNote:SetPoint("BOTTOMLEFT", 14, 12)
    saveNote:SetScript("OnClick", function()
        local body = clean(noteEditBox:GetText())
        if body ~= "" and noteEditor.questID then
            FieldJournal.QuestLog.addEntry("margin", noteEditor.questID, "My note", FieldJournal.QuestLog.questTitle(noteEditor.questID), body, "")
            FieldJournal.UI.selectedKey = "quest:" .. noteEditor.questID
        end
        noteEditor:Hide()
        FieldJournal.UI.Refresh()
    end)
    local cancelNote = FieldJournal.UI.makeButton(noteEditor, 130, 25, "Cancel")
    cancelNote:SetPoint("BOTTOMRIGHT", -14, 12)
    cancelNote:SetScript("OnClick", function() noteEditor:Hide() end)
    noteEditor:Hide()
end

local function createQuestPicker()
    local window = FieldJournal.UI.window
    local questPicker = CreateFrame("Frame", nil, window)
    FieldJournal.UI.questPicker = questPicker
    questPicker:SetSize(306, 300)
    questPicker:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -21, 60)
    questPicker:SetFrameLevel(window:GetFrameLevel() + 20)
    FieldJournal.UI.coloredRectangle(questPicker, "BACKGROUND", 0.28, 0.17, 0.09, 1, 0, 0, 0, 0)
    local pickerPaper = questPicker:CreateTexture(nil, "BORDER")
    pickerPaper:SetTexture("Interface\\AddOns\\FieldJournal\\art\\parchment.tga")
    pickerPaper:SetPoint("TOPLEFT", 4, -4)
    pickerPaper:SetPoint("BOTTOMRIGHT", -4, 4)
    local pickerTitle = FieldJournal.UI.makeLabel(questPicker, 15, {0.27, 0.15, 0.07})
    pickerTitle:SetPoint("TOPLEFT", 13, -12)
    pickerTitle:SetText("Link to a quest")
    local pickerClose = FieldJournal.UI.makeButton(questPicker, 22, 22, "X")
    pickerClose:SetPoint("TOPRIGHT", -8, -8)
    pickerClose:SetScript("OnClick", function() questPicker:Hide() end)
    questPicker.rows = {}
    for index = 1, 7 do
        local row = FieldJournal.UI.makeButton(questPicker, 278, 27, "")
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
    questPicker.count = FieldJournal.UI.makeLabel(questPicker, 11, {0.42, 0.31, 0.20})
    questPicker.count:SetPoint("BOTTOMLEFT", 15, 14)
    questPicker:EnableMouseWheel(true)
    questPicker:SetScript("OnMouseWheel", function(_, delta)
        questPicker.offset = math.max(0, math.min(math.max(0, #questPicker.options - #questPicker.rows), questPicker.offset - delta * 3))
        refreshQuestPicker()
    end)
    questPicker:Hide()
end

FieldJournal.UI.questOptions = questOptions
FieldJournal.UI.refreshQuestPicker = refreshQuestPicker
FieldJournal.UI.openQuestPicker = openQuestPicker
FieldJournal.UI.createNoteEditor = createNoteEditor
FieldJournal.UI.createQuestPicker = createQuestPicker
