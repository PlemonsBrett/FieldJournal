-- Field Journal: the settings panel -- tab visibility toggles and the
-- export/import/backup/repair actions, reachable without a slash command.
-- Built the same way UI/NoteEditor.lua builds the note editor and quest
-- picker: a child of FieldJournal.UI.window, shown/hidden rather than
-- created and destroyed.

local FieldJournal = select(2, ...)
FieldJournal.UI = FieldJournal.UI or {}

local function makeToggle(parent, label, get, set)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    local text = FieldJournal.UI.makeLabel(parent, 13, {0.25, 0.15, 0.08})
    text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    text:SetText(label)
    check:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        if FieldJournal.UI.layoutTabs then FieldJournal.UI.layoutTabs() end
        if FieldJournal.UI.Refresh then FieldJournal.UI.Refresh() end
    end)
    check.refresh = function() check:SetChecked(get() and true or false) end
    return check
end

local function runCommand(command)
    return function()
        local ok, err = pcall(SlashCmdList.FIELDJOURNAL, command)
        if not ok then print("Field Journal: that action failed unexpectedly (" .. tostring(err) .. ").") end
    end
end

local function createSettingsPanel()
    local window = FieldJournal.UI.window
    local panel = CreateFrame("Frame", nil, window)
    FieldJournal.UI.settingsPanel = panel
    panel:SetSize(320, 300)
    panel:SetPoint("CENTER", window, "CENTER", 0, 0)
    panel:SetFrameLevel(window:GetFrameLevel() + 30)
    FieldJournal.UI.coloredRectangle(panel, "BACKGROUND", 0.28, 0.17, 0.09, 1, 0, 0, 0, 0)
    local paper = panel:CreateTexture(nil, "BORDER")
    paper:SetTexture("Interface\\AddOns\\FieldJournal\\art\\parchment.tga")
    paper:SetPoint("TOPLEFT", 4, -4)
    paper:SetPoint("BOTTOMRIGHT", -4, 4)

    local title = FieldJournal.UI.makeLabel(panel, 15, {0.27, 0.15, 0.07})
    title:SetPoint("TOPLEFT", 13, -12)
    title:SetText("Settings")
    local close = FieldJournal.UI.makeButton(panel, 22, 22, "X")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() panel:Hide() end)

    local sectionLabel = FieldJournal.UI.makeLabel(panel, 12, {0.35, 0.20, 0.10})
    sectionLabel:SetPoint("TOPLEFT", 16, -46)
    sectionLabel:SetText("SHOW THESE TABS (recording never stops)")

    local toggles = {}
    local toggleDefs = {
        {label = "Daily diary", get = function() return not FieldJournal.db or not FieldJournal.db.profile or FieldJournal.db.profile.showDiary ~= false end,
            set = function(value) if FieldJournal.db and FieldJournal.db.profile then FieldJournal.db.profile.showDiary = value end end},
        {label = "Bestiary", get = function() return not FieldJournal.db or not FieldJournal.db.profile or FieldJournal.db.profile.showBestiary ~= false end,
            set = function(value) if FieldJournal.db and FieldJournal.db.profile then FieldJournal.db.profile.showBestiary = value end end},
        {label = "Crafting & gathering", get = function() return not FieldJournal.db or not FieldJournal.db.profile or FieldJournal.db.profile.showCrafting ~= false end,
            set = function(value) if FieldJournal.db and FieldJournal.db.profile then FieldJournal.db.profile.showCrafting = value end end},
    }
    for index, def in ipairs(toggleDefs) do
        local check = makeToggle(panel, def.label, def.get, def.set)
        check:SetPoint("TOPLEFT", 18, -66 - (index - 1) * 28)
        toggles[index] = check
    end

    local actionsLabel = FieldJournal.UI.makeLabel(panel, 12, {0.35, 0.20, 0.10})
    actionsLabel:SetPoint("TOPLEFT", 16, -166)
    actionsLabel:SetText("JOURNAL ACTIONS")

    local exportButton = FieldJournal.UI.makeButton(panel, 138, 25, "Export")
    exportButton:SetPoint("TOPLEFT", 16, -186)
    exportButton:SetScript("OnClick", runCommand("export"))

    local importButton = FieldJournal.UI.makeButton(panel, 138, 25, "Import")
    importButton:SetPoint("TOPRIGHT", -16, -186)
    importButton:SetScript("OnClick", runCommand("import"))

    local backupButton = FieldJournal.UI.makeButton(panel, 138, 25, "Backup now")
    backupButton:SetPoint("TOPLEFT", 16, -218)
    backupButton:SetScript("OnClick", runCommand("backup now"))

    local repairButton = FieldJournal.UI.makeButton(panel, 138, 25, "Repair")
    repairButton:SetPoint("TOPRIGHT", -16, -218)
    repairButton:SetScript("OnClick", runCommand("repair"))

    panel:SetScript("OnShow", function()
        for _, check in ipairs(toggles) do check.refresh() end
    end)
    panel:Hide()
end

FieldJournal.UI.createSettingsPanel = createSettingsPanel
