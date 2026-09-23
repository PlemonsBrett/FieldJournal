-- Field Journal: shared parchment-styled frame helpers.

local FieldJournal = select(2, ...)
FieldJournal.UI = FieldJournal.UI or {}

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

-- The one shared string dialog behind /fj export and /fj import: a parchment
-- panel with a heading, a hint line, one multi-line EditBox and two buttons. It
-- is created on first use and reused afterwards, so repeated exports never leak
-- frames, and it is a child of UIParent rather than of the journal window so
-- /fj export works without the journal being open.
--
-- Deliberately minimal, with no scroll frame: an export string is thousands of
-- characters and nobody reads it -- it arrives already selected so the player
-- presses Ctrl-C at once, and a pasted one is acted on by a button rather than
-- proof-read. Adding a scroll frame is the only reason to revisit this.
local stringDialog

local function buildStringDialog()
    local frame = CreateFrame("Frame", "FieldJournalStringDialog", UIParent)
    frame:SetSize(470, 300)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "FieldJournalStringDialog")

    coloredRectangle(frame, "BACKGROUND", 0.16, 0.095, 0.055, 0.98, 0, 0, 0, 0)
    local paper = frame:CreateTexture(nil, "BORDER")
    paper:SetTexture("Interface\\AddOns\\FieldJournal\\art\\parchment.tga")
    paper:SetPoint("TOPLEFT", 7, -7)
    paper:SetPoint("BOTTOMRIGHT", -7, 7)

    frame.heading = makeLabel(frame, 16, {0.27, 0.15, 0.07})
    frame.heading:SetPoint("TOPLEFT", 16, -14)
    frame.heading:SetWidth(400)
    frame.heading:SetMaxLines(1)

    frame.hint = makeLabel(frame, 11, {0.45, 0.35, 0.23})
    frame.hint:SetPoint("TOPLEFT", 16, -36)
    frame.hint:SetWidth(436)
    frame.hint:SetMaxLines(3)

    local close = makeButton(frame, 22, 22, "X")
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() frame:Hide() end)

    coloredRectangle(frame, "ARTWORK", 0.64, 0.54, 0.38, 1, 15, -15, -78, 52)
    local box = CreateFrame("EditBox", nil, frame)
    frame.box = box
    box:SetPoint("TOPLEFT", 21, -83)
    box:SetPoint("BOTTOMRIGHT", -21, 57)
    box:SetAutoFocus(false)
    box:SetMultiLine(true)
    box:SetMaxLetters(0) -- 0 means no limit; an export runs to thousands of characters
    box:SetFont(STANDARD_TEXT_FONT, 12, "")
    box:SetTextColor(0.22, 0.14, 0.08)
    box:SetTextInsets(6, 6, 4, 4)
    box:SetScript("OnEscapePressed", function() frame:Hide() end)
    box:SetScript("OnEditFocusGained", function(self)
        if frame.readOnly then self:HighlightText() end
    end)
    -- Read-only without a read-only API: put the text straight back the moment
    -- the player types over it. The userInput flag is false when this file calls
    -- SetText, so restoring cannot recurse.
    box:SetScript("OnTextChanged", function(self, userInput)
        if frame.readOnly and userInput then
            self:SetText(frame.contents or "")
            self:HighlightText()
        end
    end)

    frame.accept = makeButton(frame, 130, 25, "Import")
    frame.accept:SetPoint("BOTTOMLEFT", 21, 18)
    frame.accept:SetScript("OnClick", function()
        -- Read the text and hide BEFORE running the handler: the handler prints
        -- its report, and a dialog still covering the chat frame while it does
        -- is the difference between a player seeing "imported 14 entries" and
        -- wondering whether anything happened.
        local handler, text = frame.onAccept, box:GetText()
        frame:Hide()
        if handler then handler(text) end
    end)

    frame.dismiss = makeButton(frame, 130, 25, "Close")
    frame.dismiss:SetPoint("BOTTOMRIGHT", -21, 18)
    frame.dismiss:SetScript("OnClick", function() frame:Hide() end)

    frame:Hide()
    return frame
end

local function stringDialogFrame()
    if not stringDialog then stringDialog = buildStringDialog() end
    return stringDialog
end

local function openCopyBox(title, hint, text)
    local frame = stringDialogFrame()
    frame.readOnly = true
    frame.contents = tostring(text or "")
    frame.onAccept = nil
    frame.heading:SetText(tostring(title or "Field Journal"))
    frame.hint:SetText(tostring(hint or ""))
    frame.accept:Hide()
    frame.dismiss:ClearAllPoints()
    frame.dismiss:SetPoint("BOTTOM", 0, 18)
    frame:Show()
    frame.box:SetText(frame.contents)
    frame.box:SetFocus()
    frame.box:HighlightText()
end

local function openPasteBox(title, hint, onAccept)
    local frame = stringDialogFrame()
    frame.readOnly = false
    frame.contents = ""
    frame.onAccept = type(onAccept) == "function" and onAccept or nil
    frame.heading:SetText(tostring(title or "Field Journal"))
    frame.hint:SetText(tostring(hint or ""))
    frame.accept:Show()
    frame.dismiss:ClearAllPoints()
    frame.dismiss:SetPoint("BOTTOMRIGHT", -21, 18)
    frame:Show()
    frame.box:SetText("")
    frame.box:SetFocus()
end

--- Shows `text` read-only, already selected so the player can press Ctrl-C
--  immediately. Returns true if the window opened. Never throws: this runs
--  inside a slash command, where a raise becomes a Lua error popup.
function FieldJournal.UI.showCopyBox(title, hint, text)
    local ok, err = pcall(openCopyBox, title, hint, text)
    if not ok then
        print("Field Journal: the export window could not be opened (" .. tostring(err) .. ").")
        return false
    end
    return true
end

--- Shows an empty, editable box; `onAccept(text)` is called with whatever the
--  player pasted when they choose Import. Returns true if the window opened.
--  Never throws, for the same reason as showCopyBox.
function FieldJournal.UI.showPasteBox(title, hint, onAccept)
    local ok, err = pcall(openPasteBox, title, hint, onAccept)
    if not ok then
        print("Field Journal: the import window could not be opened (" .. tostring(err) .. ").")
        return false
    end
    return true
end

FieldJournal.UI.makeLabel = makeLabel
FieldJournal.UI.coloredRectangle = coloredRectangle
FieldJournal.UI.makeButton = makeButton
