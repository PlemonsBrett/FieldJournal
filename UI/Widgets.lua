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

FieldJournal.UI.makeLabel = makeLabel
FieldJournal.UI.coloredRectangle = coloredRectangle
FieldJournal.UI.makeButton = makeButton
