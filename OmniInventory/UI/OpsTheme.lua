-- =============================================================================
-- OmniInventory Design System
-- =============================================================================
-- Purpose: Shared palette tokens + widget factories matching the bag interface
--          visual language (Frame.lua DIM palette). Used by Options.lua and
--          available for future adoption by BankFrame, GuildBankFrame, etc.
-- WoTLK 3.3.5a Compatible - Uses only native APIs
-- =============================================================================

local addonName, Omni = ...

Omni.OpsTheme = {}
local OpsTheme = Omni.OpsTheme

-- =============================================================================
-- Palette
-- =============================================================================

OpsTheme.PAL = {
    -- Frame
    BG               = { 0.08, 0.08, 0.08, 0.95 },
    BG_HEADER        = { 0.15, 0.15, 0.15, 1.00 },
    BG_CONTROL       = { 0.12, 0.12, 0.12, 1.00 },
    BG_CONTROL_HOVER = { 0.22, 0.22, 0.22, 1.00 },
    BG_CONTROL_PRESSED = { 0.06, 0.06, 0.06, 1.00 },
    BG_DISABLED      = { 0.10, 0.10, 0.10, 0.55 },

    -- Borders
    BORDER           = { 0.35, 0.35, 0.35, 1.00 },
    BORDER_HOVER     = { 0.60, 0.60, 0.60, 1.00 },
    BORDER_PRESSED   = { 0.80, 0.80, 0.80, 1.00 },
    BORDER_FRAME     = { 0.40, 0.40, 0.40, 1.00 },
    BORDER_GOLD      = { 0.45, 0.38, 0.15, 1.00 },

    -- Accents
    ACCENT_GREEN     = { 0.20, 0.80, 0.20, 1.00 },
    ACCENT_CYAN      = { 0.45, 0.80, 1.00, 1.00 },
    ACCENT_GOLD      = { 1.00, 0.82, 0.00, 1.00 },

    -- Text
    TEXT             = { 1.00, 1.00, 1.00, 1.00 },
    TEXT_DIM         = { 0.55, 0.55, 0.55, 1.00 },
    TEXT_LABEL       = { 0.90, 0.90, 0.90, 1.00 },
    TEXT_DISABLED    = { 0.50, 0.50, 0.50, 1.00 },

    -- Section header tints (carried from original SECTION_COLORS)
    SECTION = {
        view   = { 0.85, 0.90, 1.00 },
        sort   = { 0.85, 0.90, 1.00 },
        misc   = { 0.78, 0.88, 1.00 },
        colors = { 1.00, 0.60, 0.20 },
        footer = { 0.40, 1.00, 0.55 },
        addon  = { 0.45, 0.80, 1.00 },
        feat   = { 0.85, 0.70, 1.00 },
    },

    -- Layout
    PADDING       = 8,
    EDGE_SIZE     = 14,
    EDGE_INSETS   = { left = 3, right = 3, top = 3, bottom = 3 },

    -- Widgets
    CHECKBOX_SIZE = 16,
    SLIDER_HEIGHT = 16,
    SLIDER_WIDTH  = 200,
    SLIDER_THUMB_W = 12,
    SLIDER_THUMB_H = 14,
    BTN_HEIGHT    = 22,
    BTN_MIN_WIDTH = 80,
    SCROLL_BAR_W  = 6,
    SCROLL_THUMB_H = 20,
    ICON_SIZE     = 18,
}

-- =============================================================================
-- Theme (rounded / square)
-- =============================================================================

local function GetTheme()
    if Omni.Features and Omni.Features.GetTheme then
        return Omni.Features:GetTheme()
    end
    return "rounded"
end

local function GetBorderFile()
    local theme = GetTheme()
    if theme == "square" then
        return "Interface\\Buttons\\WHITE8X8"
    end
    return "Interface\\Tooltips\\UI-Tooltip-Border"
end

local function GetEdgeSize()
    local theme = GetTheme()
    if theme == "square" then
        return 1
    end
    return OpsTheme.PAL.EDGE_SIZE
end

local function GetInsets()
    local theme = GetTheme()
    if theme == "square" then
        return { left = 1, right = 1, top = 1, bottom = 1 }
    end
    return OpsTheme.PAL.EDGE_INSETS
end

-- =============================================================================
-- Backdrop Helpers
-- =============================================================================

function OpsTheme:ApplyFrameBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = GetBorderFile(),
        edgeSize = GetEdgeSize(),
        insets = GetInsets(),
    })
    frame:SetBackdropColor(unpack(self.PAL.BG))
    frame:SetBackdropBorderColor(unpack(self.PAL.BORDER_FRAME))
end

function OpsTheme:ApplyControlBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(self.PAL.BG_CONTROL))
    frame:SetBackdropBorderColor(unpack(self.PAL.BORDER))
end

-- =============================================================================
-- Factory: Tab Button (ribbon style)
-- =============================================================================

function OpsTheme.CreateTabButton(parent, label, isActive, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(110, OpsTheme.PAL.BTN_HEIGHT)
    OpsTheme:ApplyControlBackdrop(btn)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(label)

    local function ApplyState(active)
        if active then
            btn:SetBackdropColor(0.18, 0.18, 0.18, 1)
            btn:SetBackdropBorderColor(unpack(OpsTheme.PAL.ACCENT_GREEN))
            btn.text:SetTextColor(unpack(OpsTheme.PAL.ACCENT_GREEN))
            btn:Disable()
        else
            btn:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL))
            btn:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER))
            btn.text:SetTextColor(unpack(OpsTheme.PAL.TEXT_LABEL))
            btn:Enable()
        end
    end

    ApplyState(isActive)
    btn._ApplyState = ApplyState

    btn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_HOVER))
            self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_HOVER))
        end
    end)
    btn:SetScript("OnLeave", function(self)
        ApplyState(self._isActive)
    end)

    btn:SetScript("OnClick", function(self)
        self._isActive = true
        ApplyState(true)
        if onClick then onClick(self) end
    end)

    btn._isActive = isActive
    return btn
end

-- =============================================================================
-- Factory: Flat Button (ribbon style)
-- =============================================================================

function OpsTheme.CreateButton(parent, label, width, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or OpsTheme.PAL.BTN_MIN_WIDTH, OpsTheme.PAL.BTN_HEIGHT)
    OpsTheme:ApplyControlBackdrop(btn)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(label)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_HOVER))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_HOVER))
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER))
    end)
    btn:SetScript("OnMouseDown", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_PRESSED))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_PRESSED))
    end)
    btn:SetScript("OnMouseUp", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_HOVER))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_HOVER))
    end)

    btn:SetScript("OnClick", function(self)
        if onClick then onClick(self) end
    end)

    return btn
end

-- =============================================================================
-- Factory: Icon Button (ribbon style)
-- =============================================================================

function OpsTheme.CreateIconButton(parent, iconTexture, width, height, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or OpsTheme.PAL.ICON_SIZE, height or OpsTheme.PAL.ICON_SIZE)
    OpsTheme:ApplyControlBackdrop(btn)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 2, -2)
    btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.icon:SetTexture(iconTexture)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_HOVER))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_HOVER))
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER))
    end)
    btn:SetScript("OnMouseDown", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_PRESSED))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_PRESSED))
    end)
    btn:SetScript("OnMouseUp", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_HOVER))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_HOVER))
    end)
    btn:SetScript("OnClick", function(self)
        if onClick then onClick(self) end
    end)

    return btn
end

-- =============================================================================
-- Factory: Check Button (custom 16x16, no UICheckButtonTemplate)
-- =============================================================================

function OpsTheme.CreateCheckButton(parent, label, tooltipTitle, tooltipSub, isChecked, onClick)
    local cbSize = OpsTheme.PAL.CHECKBOX_SIZE
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(cbSize, cbSize)

    -- Box
    btn.box = btn:CreateTexture(nil, "ARTWORK")
    btn.box:SetAllPoints()
    btn.box:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- Check mark texture (drawn as a small white square when checked)
    btn.check = btn:CreateTexture(nil, "OVERLAY")
    btn.check:SetPoint("TOPLEFT", 3, -3)
    btn.check:SetPoint("BOTTOMRIGHT", -3, 3)
    btn.check:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- Label
    btn.labelStr = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    btn.labelStr:SetPoint("LEFT", btn, "RIGHT", 4, 0)
    btn.labelStr:SetText(label)
    btn.labelStr:SetJustifyH("LEFT")

    -- State
    btn._checked = isChecked

    local function ApplyVisual(checked)
        if checked then
            btn.box:SetVertexColor(unpack(OpsTheme.PAL.ACCENT_GREEN))
            btn.box:SetVertexColor(0.18, 0.18, 0.18, 1)
            btn.check:SetVertexColor(unpack(OpsTheme.PAL.ACCENT_GREEN))
            btn.check:Show()
        else
            btn.box:SetVertexColor(unpack(OpsTheme.PAL.BG_CONTROL))
            btn.check:Hide()
        end
    end

    local function ApplyEnabled(enabled)
        if enabled then
            btn:SetAlpha(1)
            btn:EnableMouse(true)
        else
            btn:SetAlpha(0.45)
            btn:EnableMouse(false)
        end
    end

    ApplyVisual(isChecked)
    btn._ApplyVisual = ApplyVisual
    btn._ApplyEnabled = ApplyEnabled

    -- Border lines (1px chevron-lite like bag slot icons)
    local function SetBorderColor(r, g, b)
        if not btn.borderTop then return end
        btn.borderTop:SetVertexColor(r, g, b, 1)
        btn.borderBottom:SetVertexColor(r, g, b, 1)
        btn.borderLeft:SetVertexColor(r, g, b, 1)
        btn.borderRight:SetVertexColor(r, g, b, 1)
    end

    btn.borderTop = btn:CreateTexture(nil, "OVERLAY")
    btn.borderTop:SetTexture("Interface\\Buttons\\WHITE8X8")
    btn.borderTop:SetPoint("TOPLEFT", -1, 1)
    btn.borderTop:SetPoint("TOPRIGHT", 1, 1)
    btn.borderTop:SetHeight(1)

    btn.borderBottom = btn:CreateTexture(nil, "OVERLAY")
    btn.borderBottom:SetTexture("Interface\\Buttons\\WHITE8X8")
    btn.borderBottom:SetPoint("BOTTOMLEFT", -1, -1)
    btn.borderBottom:SetPoint("BOTTOMRIGHT", 1, -1)
    btn.borderBottom:SetHeight(1)

    btn.borderLeft = btn:CreateTexture(nil, "OVERLAY")
    btn.borderLeft:SetTexture("Interface\\Buttons\\WHITE8X8")
    btn.borderLeft:SetPoint("TOPLEFT", -1, 1)
    btn.borderLeft:SetPoint("BOTTOMLEFT", -1, -1)
    btn.borderLeft:SetWidth(1)

    btn.borderRight = btn:CreateTexture(nil, "OVERLAY")
    btn.borderRight:SetTexture("Interface\\Buttons\\WHITE8X8")
    btn.borderRight:SetPoint("TOPRIGHT", 1, 1)
    btn.borderRight:SetPoint("BOTTOMRIGHT", 1, -1)
    btn.borderRight:SetWidth(1)

    SetBorderColor(unpack(OpsTheme.PAL.BORDER))

    -- Hover
    btn:SetScript("OnEnter", function(self)
        SetBorderColor(unpack(OpsTheme.PAL.BORDER_HOVER))
        if tooltipTitle then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltipTitle, 1, 0.82, 0)
            if tooltipSub then
                GameTooltip:AddLine(tooltipSub, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        SetBorderColor(unpack(OpsTheme.PAL.BORDER))
        GameTooltip:Hide()
    end)

    -- Click
    btn:SetScript("OnClick", function(self)
        self._checked = not self._checked
        ApplyVisual(self._checked)
        if onClick then onClick(self, self._checked) end
    end)

    -- Public API
    btn.SetChecked = function(self, checked)
        self._checked = checked
        ApplyVisual(checked)
    end
    btn.GetChecked = function(self)
        return self._checked
    end
    btn.SetLabel = function(self, text)
        self.labelStr:SetText(text)
    end
    btn.SetTooltip = function(self, title, sub)
        tooltipTitle = title
        tooltipSub = sub
    end
    btn.SetEnabled = function(self, enabled)
        self._enabled = enabled and true or false
        ApplyEnabled(self._enabled)
    end
    btn.Enable = function(self)
        self:SetEnabled(true)
    end
    btn.Disable = function(self)
        self:SetEnabled(false)
    end
    btn.IsEnabled = function(self)
        return self._enabled ~= false
    end

    -- Gate clicks by enabled state (defensive: _ApplyEnabled already toggles
    -- EnableMouse, but OnClick can still fire from keyboard/code paths)
    local origOnClick = btn:GetScript("OnClick")
    btn:SetScript("OnClick", function(self)
        if self._enabled == false then return end
        if origOnClick then
            origOnClick(self)
        end
    end)

    return btn
end

-- =============================================================================
-- Factory: Slider (custom, no OptionsSliderTemplate)
-- =============================================================================

function OpsTheme.CreateSlider(parent, label, minVal, maxVal, stepVal, formatFn, onChange)
    local PAL = OpsTheme.PAL
    local sliderW = PAL.SLIDER_WIDTH
    local thumbW = PAL.SLIDER_THUMB_W
    local thumbH = PAL.SLIDER_THUMB_H

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(sliderW, 44)

    -- Label
    container.labelStr = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    container.labelStr:SetPoint("TOP", 0, 0)
    container.labelStr:SetText(label)

    -- Track background
    container.track = container:CreateTexture(nil, "ARTWORK")
    container.track:SetPoint("TOPLEFT", 0, -14)
    container.track:SetPoint("TOPRIGHT", 0, -14)
    container.track:SetHeight(4)
    container.track:SetTexture("Interface\\Buttons\\WHITE8X8")
    container.track:SetVertexColor(0.20, 0.20, 0.20, 1)

    -- Track border
    container.trackBorder = container:CreateTexture(nil, "OVERLAY")
    container.trackBorder:SetPoint("TOPLEFT", 0, -13)
    container.trackBorder:SetPoint("TOPRIGHT", 0, -13)
    container.trackBorder:SetHeight(6)
    container.trackBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    container.trackBorder:SetVertexColor(0.35, 0.35, 0.35, 1)

    -- Filled portion
    container.fill = container:CreateTexture(nil, "ARTWORK")
    container.fill:SetPoint("TOPLEFT", 0, -14)
    container.fill:SetHeight(4)
    container.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    container.fill:SetVertexColor(unpack(PAL.ACCENT_GREEN))

    -- Thumb
    container.thumb = CreateFrame("Button", nil, container)
    container.thumb:SetSize(thumbW, thumbH)
    container.thumb.tex = container.thumb:CreateTexture(nil, "ARTWORK")
    container.thumb.tex:SetAllPoints()
    container.thumb.tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    container.thumb.tex:SetVertexColor(unpack(PAL.ACCENT_GREEN))

    container.thumb.borderTop = container.thumb:CreateTexture(nil, "OVERLAY")
    container.thumb.borderTop:SetTexture("Interface\\Buttons\\WHITE8X8")
    container.thumb.borderTop:SetPoint("TOPLEFT", -1, 1)
    container.thumb.borderTop:SetPoint("TOPRIGHT", 1, 1)
    container.thumb.borderTop:SetHeight(1)
    container.thumb.borderTop:SetVertexColor(1, 1, 1, 0.6)

    container.thumb.borderBottom = container.thumb:CreateTexture(nil, "OVERLAY")
    container.thumb.borderBottom:SetTexture("Interface\\Buttons\\WHITE8X8")
    container.thumb.borderBottom:SetPoint("BOTTOMLEFT", -1, -1)
    container.thumb.borderBottom:SetPoint("BOTTOMRIGHT", 1, -1)
    container.thumb.borderBottom:SetHeight(1)
    container.thumb.borderBottom:SetVertexColor(1, 1, 1, 0.6)

    -- Min/Max labels
    container.minLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    container.minLabel:SetPoint("TOPLEFT", 0, -28)
    container.minLabel:SetText(formatFn and formatFn(minVal) or tostring(minVal))

    container.maxLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    container.maxLabel:SetPoint("TOPRIGHT", 0, -28)
    container.maxLabel:SetText(formatFn and formatFn(maxVal) or tostring(maxVal))

    -- Value text
    container.valueText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    container.valueText:SetPoint("TOP", 0, -34)
    container.valueText:SetText("")

    -- State
    container._min = minVal
    container._max = maxVal
    container._step = stepVal
    container._value = minVal
    container._formatFn = formatFn
    container._onChange = onChange
    container._syncing = false

    local halfThumb = thumbW / 2

    local function UpdateThumbPosition(value)
        local pct = (value - minVal) / (maxVal - minVal)
        local x = halfThumb + pct * (sliderW - thumbW)
        container.thumb:ClearAllPoints()
        container.thumb:SetPoint("CENTER", container, "TOPLEFT", x, -16)
    end

    local function UpdateFill(value)
        local pct = (value - minVal) / (maxVal - minVal)
        local fillW = halfThumb + pct * (sliderW - thumbW)
        container.fill:SetWidth(math.max(1, fillW))
    end

    local function UpdateDisplay(value)
        local text = formatFn and formatFn(value) or string.format("%.2f", value)
        container.valueText:SetText("Current: " .. text)
        UpdateThumbPosition(value)
        UpdateFill(value)
    end

    -- Thumb dragging
    container.thumb:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self._dragging = true
        end
    end)
    container.thumb:SetScript("OnMouseUp", function(self)
        self._dragging = false
    end)

    -- Click on track to jump
    container:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            local cursorX = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local selfLeft = self:GetLeft()
            local relX = (cursorX / scale) - selfLeft
            local usableW = sliderW - thumbW
            local pct = math.max(0, math.min(1, (relX - halfThumb) / usableW))
            local raw = minVal + pct * (maxVal - minVal)
            local stepped = math.floor(raw / stepVal + 0.5) * stepVal
            stepped = math.max(minVal, math.min(maxVal, stepped))
            container._value = stepped
            UpdateDisplay(stepped)
            if not container._syncing and onChange then
                onChange(stepped)
            end
        end
    end)

    -- Thumb drag via OnUpdate
    local dragFrame = CreateFrame("Frame")
    dragFrame:SetScript("OnUpdate", function(self, elapsed)
        if container.thumb._dragging then
            local cursorX = GetCursorPosition()
            local scale = container:GetEffectiveScale()
            local selfLeft = container:GetLeft()
            local relX = (cursorX / scale) - selfLeft
            local usableW = sliderW - thumbW
            local pct = math.max(0, math.min(1, (relX - halfThumb) / usableW))
            local raw = minVal + pct * (maxVal - minVal)
            local stepped = math.floor(raw / stepVal + 0.5) * stepVal
            stepped = math.max(minVal, math.min(maxVal, stepped))
            if stepped ~= container._value then
                container._value = stepped
                UpdateDisplay(stepped)
                if not container._syncing and onChange then
                    onChange(stepped)
                end
            end
        end
    end)

    -- Public API
    container.SetValue = function(self, value)
        self._syncing = true
        value = math.max(self._min, math.min(self._max, value))
        self._value = value
        UpdateDisplay(value)
        self._syncing = false
    end

    container.GetValue = function(self)
        return self._value
    end

    container.SetEnabled = function(self, enabled)
        if enabled then
            self:SetAlpha(1)
            self:EnableMouse(true)
            self.thumb:EnableMouse(true)
        else
            self:SetAlpha(0.45)
            self:EnableMouse(false)
            self.thumb:EnableMouse(false)
        end
    end

    container.SetValueLabel = function(self, text)
        self.valueText:SetText(text)
    end

    -- Initial display
    UpdateDisplay(minVal)

    return container
end

-- =============================================================================
-- Factory: Section Header
-- =============================================================================

function OpsTheme.CreateSectionHeader(parent, text, color)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetText(text)
    if color then
        label:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    else
        label:SetTextColor(unpack(OpsTheme.PAL.TEXT))
    end
    return label
end

-- =============================================================================
-- Factory: Scroll Frame (custom thin bar)
-- =============================================================================

function OpsTheme.CreateScrollFrame(parent, width, height)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    scrollFrame:SetSize(width, height)
    scrollFrame:EnableMouseWheel(true)

    -- Scrollbar track
    local barW = OpsTheme.PAL.SCROLL_BAR_W
    local bar = CreateFrame("Frame", nil, scrollFrame)
    bar:SetWidth(barW)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", 0, 0)

    bar.track = bar:CreateTexture(nil, "ARTWORK")
    bar.track:SetAllPoints()
    bar.track:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.track:SetVertexColor(0.15, 0.15, 0.15, 1)

    bar.thumb = CreateFrame("Frame", nil, bar)
    bar.thumb:SetWidth(barW)
    bar.thumb:SetHeight(OpsTheme.PAL.SCROLL_THUMB_H)
    bar.thumb:SetPoint("TOP", 0, 0)

    bar.thumb.tex = bar.thumb:CreateTexture(nil, "ARTWORK")
    bar.thumb.tex:SetAllPoints()
    bar.thumb.tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.thumb.tex:SetVertexColor(0.40, 0.40, 0.40, 1)

    scrollFrame._bar = bar
    scrollFrame._barW = barW

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local step = 28
        self:SetVerticalScroll(math.max(0, math.min(
            self:GetVerticalScrollRange(),
            self:GetVerticalScroll() - (delta * step)
        )))
    end)

    scrollFrame:SetScript("OnScrollRangeChanged", function(self, range)
        if not self._bar then return end
        local viewH = self:GetHeight()
        if viewH <= 0 then return end
        local thumbH = math.max(20, viewH * (viewH / (viewH + range)))
        self._bar.thumb:SetHeight(thumbH)
    end)

    scrollFrame:SetScript("OnUpdate", function(self)
        if not self._bar then return end
        local range = self:GetVerticalScrollRange()
        local cur = self:GetVerticalScroll()
        local viewH = self:GetHeight()
        if range <= 0 then
            self._bar.thumb:SetPoint("TOP", 0, 0)
            return
        end
        local pct = cur / range
        local thumbH = self._bar.thumb:GetHeight()
        local barH = self._bar:GetHeight() - thumbH
        local y = -(pct * barH) - (thumbH / 2)
        self._bar.thumb:ClearAllPoints()
        self._bar.thumb:SetPoint("TOP", self._bar, "TOP", 0, y)
    end)

    return scrollFrame
end

-- =============================================================================
-- Helper: Set 1px border lines on a frame (matching bag slot icon style)
-- =============================================================================

function OpsTheme.Apply1pxBorder(frame, color)
    local r, g, b = color[1], color[2], color[3]

    frame._borderTop = frame:CreateTexture(nil, "OVERLAY")
    frame._borderTop:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame._borderTop:SetPoint("TOPLEFT", -1, 1)
    frame._borderTop:SetPoint("TOPRIGHT", 1, 1)
    frame._borderTop:SetHeight(1)
    frame._borderTop:SetVertexColor(r, g, b, 1)

    frame._borderBottom = frame:CreateTexture(nil, "OVERLAY")
    frame._borderBottom:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame._borderBottom:SetPoint("BOTTOMLEFT", -1, -1)
    frame._borderBottom:SetPoint("BOTTOMRIGHT", 1, -1)
    frame._borderBottom:SetHeight(1)
    frame._borderBottom:SetVertexColor(r, g, b, 1)

    frame._borderLeft = frame:CreateTexture(nil, "OVERLAY")
    frame._borderLeft:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame._borderLeft:SetPoint("TOPLEFT", -1, 1)
    frame._borderLeft:SetPoint("BOTTOMLEFT", -1, -1)
    frame._borderLeft:SetWidth(1)
    frame._borderLeft:SetVertexColor(r, g, b, 1)

    frame._borderRight = frame:CreateTexture(nil, "OVERLAY")
    frame._borderRight:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame._borderRight:SetPoint("TOPRIGHT", 1, 1)
    frame._borderRight:SetPoint("BOTTOMRIGHT", 1, -1)
    frame._borderRight:SetWidth(1)
    frame._borderRight:SetVertexColor(r, g, b, 1)

    frame.SetBorderColor = function(self, cr, cg, cb)
        self._borderTop:SetVertexColor(cr, cg, cb, 1)
        self._borderBottom:SetVertexColor(cr, cg, cb, 1)
        self._borderLeft:SetVertexColor(cr, cg, cb, 1)
        self._borderRight:SetVertexColor(cr, cg, cb, 1)
    end
end
