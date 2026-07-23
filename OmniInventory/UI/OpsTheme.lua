-- =============================================================================
-- OmniInventory Design System (OpenCode-flavored, dark mode)
-- =============================================================================
-- Purpose: Shared palette tokens + widget factories. Adapted from the
--          OpenCode marketing design system — Berkeley Mono typography
--          spirit (substituted to JetBrains Mono since WoW fonts are
--          limited to the .ttf files in the client), warm cream canvas
--          inverted to a deep warm-black, hairline 1px hairlines, and
--          the Apple HIG semantic ramp for the in-TUI mockup.
-- WoTLK 3.3.5a Compatible - Uses only native APIs
-- =============================================================================

local addonName, Omni = ...

Omni.OpsTheme = {}
local OpsTheme = Omni.OpsTheme

-- =============================================================================
-- Helpers
-- =============================================================================

-- Convert a hex string "#rrggbb" or "#rrggbbaa" to { r, g, b, a } in 0..1
local function Hex(h)
    if not h or h:sub(1, 1) ~= "#" then return { 0, 0, 0, 1 } end
    h = h:sub(2)
    if #h == 6 then
        return {
            tonumber(h:sub(1, 2), 16) / 255,
            tonumber(h:sub(3, 4), 16) / 255,
            tonumber(h:sub(5, 6), 16) / 255,
            1,
        }
    end
    if #h == 8 then
        return {
            tonumber(h:sub(1, 2), 16) / 255,
            tonumber(h:sub(3, 4), 16) / 255,
            tonumber(h:sub(5, 6), 16) / 255,
            tonumber(h:sub(7, 8), 16) / 255,
        }
    end
    return { 0, 0, 0, 1 }
end

-- =============================================================================
-- Palette — Dark mode (OpenCode inverse)
-- =============================================================================
-- Reference: refs/opencode-design-system.md (dark section)

-- Color Ramp (RGBA normalized 0.0 to 1.0)
OpsTheme.colors = {
    canvas              = { 0.086, 0.078, 0.075, 0.95 }, -- #161413 (Dark Canvas)
    surfaceSoft         = { 0.122, 0.110, 0.102, 1.00 }, -- #1f1c1a (Card Surface)
    surfaceDark         = { 0.039, 0.035, 0.031, 1.00 }, -- #0a0908 (Deep Background)
    hairline            = { 0.941, 0.910, 0.824, 0.10 }, -- Translucent Hairline Rule
    hairlineStrong      = { 0.353, 0.337, 0.329, 1.00 }, -- #5a5654
    
    -- Typography Ink Ladder
    ink                 = { 0.945, 0.933, 0.914, 1.00 }, -- #f1eee9 (Warm Off-White)
    charcoal            = { 0.812, 0.796, 0.769, 1.00 }, -- #cfcbc4
    body                = { 0.659, 0.639, 0.612, 1.00 }, -- #a8a39c
    mute                = { 0.478, 0.455, 0.431, 1.00 }, -- #7a746e
    ash                 = { 0.290, 0.275, 0.259, 1.00 }, -- #4a4642 (Disabled)
    
    -- Accents
    accent              = { 0.000, 0.478, 1.000, 1.00 }, -- Apple Blue #007aff
    danger              = { 1.000, 0.231, 0.188, 1.00 }, -- Red #ff3b30
    warning             = { 1.000, 0.624, 0.039, 1.00 }, -- Gold #ff9f0a
    success             = { 0.188, 0.820, 0.345, 1.00 }, -- Green #30d158
}

-- OpenCode TUI RGBA Quality Colors for Item Buttons (0: Poor -> 7: Heirloom)
OpsTheme.qualityColors = {
    [0] = { 0.478, 0.455, 0.431, 1.00 }, -- Poor (Mute Grey)
    [1] = { 0.812, 0.796, 0.769, 1.00 }, -- Common (Charcoal Off-White)
    [2] = { 0.188, 0.820, 0.345, 1.00 }, -- Uncommon (OpenCode Green #30d158)
    [3] = { 0.000, 0.478, 1.000, 1.00 }, -- Rare (OpenCode Blue #007aff)
    [4] = { 0.635, 0.325, 0.871, 1.00 }, -- Epic (OpenCode Purple #a259ff)
    [5] = { 1.000, 0.624, 0.039, 1.00 }, -- Legendary (OpenCode Warning Gold #ff9f0a)
    [6] = { 0.900, 0.800, 0.500, 1.00 }, -- Artifact (OpenCode Gold)
    [7] = { 0.000, 0.800, 1.000, 1.00 }, -- Heirloom (OpenCode Heirloom Cyan)
}
OpsTheme.QUALITY_COLORS = OpsTheme.qualityColors

--- Returns RGBA quality colors for native OpenCode TUI quality glow borders
-- @param quality Item quality integer (0..7)
-- @return r, g, b, a values normalized (0..1)
function OpsTheme:GetQualityColor(quality)
    quality = tonumber(quality) or 1
    local color = self.qualityColors[quality] or self.qualityColors[1]
    return color[1], color[2], color[3], color[4] or 1
end

-- ASCII Formatting Markers
OpsTheme.ASCII = {
    EXPAND   = "[+]",
    COLLAPSE = "[-]",
    CLOSE    = "[x]",
    CHECKED  = "[X]",
    UNCHECKED= "[ ]",
    ARROW    = "->",
    OK       = "[OK]",
    WARN     = "[!]",
}

OpsTheme.PAL = {
    -- Canvas / surface
    BG                 = Hex("#161413ff"),  -- canvas (deep warm black, replaces #fdfcfc)
    BG_HEADER          = Hex("#1f1c1aff"),  -- surface-soft (nav bar fill, header strip)
    BG_CONTROL         = Hex("#262220ff"),  -- surface-card 2-tier (controls, inputs)
    BG_CONTROL_HOVER   = Hex("#332e2bff"),  -- surface-card hover
    BG_CONTROL_PRESSED = Hex("#0e0d0cff"),  -- ink-deep (#0f0000) inverted for dark
    BG_DISABLED        = Hex("#1a1715cc"),  -- disabled fill at lower alpha

    -- Borders (hairline / hairline-strong)
    BORDER             = Hex("#5a5654ff"),  -- hairline-strong (~ -40% from ink)
    BORDER_HOVER       = Hex("#8a857fff"),  -- mid-tone warm gray
    BORDER_PRESSED     = Hex("#f1eee9ff"),  -- ink (pressed border is bright)
    BORDER_FRAME       = Hex("#5a5654ff"),  -- outer frame hairline
    BORDER_GOLD        = Hex("#a9800aff"),  -- preserved gold tone for category accents

    -- Accents (Apple HIG ramp — used inside the TUI mockup)
    ACCENT_GREEN       = Hex("#30d158ff"),  -- success (replaces ANSI green)
    ACCENT_CYAN        = Hex("#007affff"),  -- accent (Apple Blue — replaces cyan)
    ACCENT_GOLD        = Hex("#ff9f0aff"),  -- warning

    -- Semantic ramp (kept per design system, available to TUI mockup)
    SEMANTIC = {
        accent        = Hex("#007affff"),
        accent_hover  = Hex("#0056b3ff"),
        accent_active = Hex("#004085ff"),
        danger        = Hex("#ff3b30ff"),
        danger_hover  = Hex("#d70015ff"),
        danger_active = Hex("#a50011ff"),
        warning       = Hex("#ff9f0aff"),
        warning_hover = Hex("#cc7f08ff"),
        warning_active= Hex("#995f06ff"),
        success       = Hex("#30d158ff"),
    },

    -- Text ladder (mapped from {ink, charcoal, body, mute, stone, ash})
    TEXT               = Hex("#f1eee9ff"),  -- ink (warm off-white)
    TEXT_SECONDARY     = Hex("#cfcbc4ff"),  -- charcoal
    TEXT_BODY          = Hex("#a8a39cff"),  -- body (default paragraph)
    TEXT_DIM           = Hex("#7a746eff"),  -- mute (metadata, tab labels default)
    TEXT_LABEL         = Hex("#605c58ff"),  -- stone (breadcrumb separators)
    TEXT_DISABLED      = Hex("#4a4642ff"),  -- ash
    TEXT_ON_DARK       = Hex("#f1eee9ff"),  -- on-dark (text on surface-dark = canvas)

    -- Hero TUI mockup surface (the ONE allowed dark surface)
    BG_HERO            = Hex("#0a0908ff"),  -- deeper than canvas, derived from ink-deep
    BG_HERO_ELEVATED   = Hex("#1a1715ff"),  -- prompt row inside the mockup

    -- Section header tints (sample tints; marketing pages keep mostly monochrome)
    SECTION = {
        view   = Hex("#007affff"),  -- accent-style
        sort   = Hex("#007affff"),
        misc   = Hex("#a8a39cff"),  -- body-tier
        colors = Hex("#ff9f0aff"),  -- warning (TUI mockup vibe)
        footer = Hex("#30d158ff"),  -- success
        addon  = Hex("#007affff"),
        feat   = Hex("#cfcbc4ff"),
    },

    -- Layout (OpenCode 8px base + finer)
    PADDING       = 8,
    EDGE_SIZE     = 1,                       -- 1px hairline, matches WoW flat dark
    EDGE_INSETS   = { left = 0, right = 0, top = 0, bottom = 0 },
    SPACING = {
        xxs = 1,
        xs  = 4,
        sm  = 8,
        md  = 12,
        lg  = 16,
        xl  = 24,
        xxl = 32,
        section = 96,
    },
    ROUNDED = {
        none = 0,
        sm   = 4,
        full = 9999,
    },

    -- Widget sizing
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
-- Type tokens (Berkeley Mono substitute -> available WoW fonts)
-- =============================================================================
-- WoW's available bodies include GameFontNormal, GameFontNormalSmall,
-- GameFontHighlight, GameFontHighlightSmall, etc. Sizes are tampered with
-- SetFont to approach the OpenCode scale (38 / 16 / 14).

OpsTheme.TYPE = {
    display_xl    = { font = "Fonts\\FRIZQT__.TTF", size = 38, weight = "OUTLINE" },
    heading_md    = { font = "Fonts\\FRIZQT__.TTF", size = 16 },
    body_md       = { font = "Fonts\\FRIZQT__.TTF", size = 16 },
    body_strong   = { font = "Fonts\\FRIZQT__.TTF", size = 16 },
    body_tight    = { font = "Fonts\\FRIZQT__.TTF", size = 16 },
    link_md       = { font = "Fonts\\FRIZQT__.TTF", size = 16 },
    button_md     = { font = "Fonts\\FRIZQT__.TTF", size = 16 },
    caption_md    = { font = "Fonts\\FRIZQT__.TTF", size = 14 },
}

-- Apply a type token to a FontString. Returns the FontString for chaining.
function OpsTheme:ApplyType(fs, tokenName, color)
    local t = self.TYPE[tokenName]
    if not t then return fs end
    fs:SetFont(t.font, t.size)
    if color then
        fs:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
    return fs
end


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
-- Factory: Sidebar Tab (vertical, list-oriented)
-- =============================================================================
-- Vertical button used in the left-hand sidebar of the options panel.
-- Active state is shown by an accent left bar + brightened background; the
-- button stays enabled so it can be re-clicked (unlike CreateTabButton).

function OpsTheme.CreateSidebarTab(parent, label, width, height, isActive, onClick)
    local PAL = OpsTheme.PAL
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 120, height or 30)
    OpsTheme:ApplyControlBackdrop(btn)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("LEFT", btn, "LEFT", 10, 0)
    btn.text:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    btn.text:SetJustifyH("LEFT")
    btn.text:SetText(label)

    -- Active accent bar (left edge)
    btn.accent = btn:CreateTexture(nil, "OVERLAY")
    btn.accent:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    btn.accent:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    btn.accent:SetWidth(3)
    btn.accent:SetTexture("Interface\\Buttons\\WHITE8X8")

    btn._isActive = isActive and true or false

    local function ApplyState(active)
        if active then
            btn:SetBackdropColor(unpack(PAL.BG_CONTROL_HOVER))
            btn:SetBackdropBorderColor(unpack(PAL.ACCENT_GREEN))
            btn.accent:SetVertexColor(unpack(PAL.ACCENT_GREEN))
            btn.accent:Show()
            btn.text:SetTextColor(unpack(PAL.ACCENT_GREEN))
        else
            btn:SetBackdropColor(unpack(PAL.BG_CONTROL))
            btn:SetBackdropBorderColor(unpack(PAL.BORDER))
            btn.accent:Hide()
            btn.text:SetTextColor(unpack(PAL.TEXT_LABEL))
        end
    end

    btn._ApplyState = ApplyState
    ApplyState(btn._isActive)

    btn:SetScript("OnEnter", function(self)
        if not self._isActive then
            self:SetBackdropColor(unpack(PAL.BG_CONTROL_HOVER))
            self:SetBackdropBorderColor(unpack(PAL.BORDER_HOVER))
        end
    end)
    btn:SetScript("OnLeave", function(self)
        ApplyState(self._isActive)
    end)
    btn:SetScript("OnClick", function(self)
        if onClick then onClick(self) end
    end)

    btn.SetActive = function(self, active)
        self._isActive = active and true or false
        ApplyState(self._isActive)
    end

    return btn
end

-- =============================================================================
-- Factory: Radio Button (flat circle, optional group)
-- =============================================================================

function OpsTheme.CreateRadioButton(parent, label, tooltipTitle, tooltipSub, group, onSelected)
    local PAL = OpsTheme.PAL
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(16, 16)

    -- Outer ring
    btn.ring = btn:CreateTexture(nil, "ARTWORK")
    btn.ring:SetAllPoints()
    btn.ring:SetTexture("Interface\\Buttons\\WHITE8X8")
    btn.ring:SetVertexColor(unpack(PAL.BORDER))

    -- Inner fill (to give a hollow look)
    btn.inner = btn:CreateTexture(nil, "OVERLAY")
    btn.inner:SetPoint("TOPLEFT", 2, -2)
    btn.inner:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.inner:SetTexture("Interface\\Buttons\\WHITE8X8")
    btn.inner:SetVertexColor(unpack(PAL.BG_CONTROL))

    -- Selection dot
    btn.dot = btn:CreateTexture(nil, "OVERLAY")
    btn.dot:SetPoint("TOPLEFT", 4, -4)
    btn.dot:SetPoint("BOTTOMRIGHT", -4, 4)
    btn.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
    btn.dot:SetVertexColor(unpack(PAL.ACCENT_GREEN))
    btn.dot:Hide()

    -- Label
    btn.labelStr = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    btn.labelStr:SetPoint("LEFT", btn, "RIGHT", 5, 0)
    btn.labelStr:SetText(label)
    btn.labelStr:SetJustifyH("LEFT")

    btn._checked = false
    btn._group = group
    btn._siblings = nil  -- set by parent code

    local function ApplyVisual(checked)
        if checked then
            btn.ring:SetVertexColor(unpack(PAL.ACCENT_GREEN))
            btn.dot:Show()
        else
            btn.ring:SetVertexColor(unpack(PAL.BORDER))
            btn.dot:Hide()
        end
    end

    btn._ApplyVisual = ApplyVisual
    btn._onSelected = onSelected

    -- 1px border around the dot/inner (chevron-lite, matches checkboxes)
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
    local function SetBorderColor(r, g, b)
        btn.borderTop:SetVertexColor(r, g, b, 1)
        btn.borderBottom:SetVertexColor(r, g, b, 1)
        btn.borderLeft:SetVertexColor(r, g, b, 1)
        btn.borderRight:SetVertexColor(r, g, b, 1)
    end
    SetBorderColor(unpack(PAL.BORDER))

    btn:SetScript("OnEnter", function(self)
        SetBorderColor(unpack(PAL.BORDER_HOVER))
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
        SetBorderColor(unpack(PAL.BORDER))
        GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function(self)
        self:_Select()
    end)

    function btn:_Select()
        if self._checked then return end
        -- Deselect siblings in the same group
        if self._siblings then
            for _, other in ipairs(self._siblings) do
                if other ~= self and other._group == self._group then
                    other._checked = false
                    other:_ApplyVisual(false)
                end
            end
        end
        self._checked = true
        ApplyVisual(true)
        if self._onSelected then self._onSelected(self) end
    end

    btn.SetChecked = function(self, checked)
        self._checked = checked and true or false
        ApplyVisual(self._checked)
        -- When selected externally, also deselect siblings
        if checked and self._siblings then
            for _, other in ipairs(self._siblings) do
                if other ~= self and other._group == self._group then
                    other._checked = false
                    other:_ApplyVisual(false)
                end
            end
        end
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

    return btn
end

-- =============================================================================
-- Factory: Group radios (links siblings so they deselect each other)
-- =============================================================================

function OpsTheme.GroupRadios(radios)
    for _, r in ipairs(radios) do
        r._siblings = radios
    end
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
            if btn:IsEnabled() then
                btn:Disable()
            end
        else
            btn:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL))
            btn:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER))
            btn.text:SetTextColor(unpack(OpsTheme.PAL.TEXT_LABEL))
            if not btn:IsEnabled() then
                btn:Enable()
            end
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

function OpsTheme.CreateSlider(parent, label, minVal, maxVal, stepVal, formatFn, onChange, tooltipTitle, tooltipSub)
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

    -- Hover Tooltips
    local function ShowTooltip(self)
        if tooltipTitle then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltipTitle, 1, 0.82, 0)
            if tooltipSub then
                GameTooltip:AddLine(tooltipSub, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
    end
    local function HideTooltip(self)
        GameTooltip:Hide()
    end

    container:EnableMouse(true)
    container:SetScript("OnEnter", ShowTooltip)
    container:SetScript("OnLeave", HideTooltip)
    container.thumb:SetScript("OnEnter", ShowTooltip)
    container.thumb:SetScript("OnLeave", HideTooltip)

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
    bar:EnableMouse(true)

    bar.track = bar:CreateTexture(nil, "ARTWORK")
    bar.track:SetAllPoints()
    bar.track:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.track:SetVertexColor(0.15, 0.15, 0.15, 1)

    bar.thumb = CreateFrame("Frame", nil, bar)
    bar.thumb:SetWidth(barW)
    bar.thumb:SetHeight(OpsTheme.PAL.SCROLL_THUMB_H)
    bar.thumb:SetPoint("TOP", 0, 0)
    bar.thumb:EnableMouse(true)

    bar.thumb.tex = bar.thumb:CreateTexture(nil, "ARTWORK")
    bar.thumb.tex:SetAllPoints()
    bar.thumb.tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.thumb.tex:SetVertexColor(0.40, 0.40, 0.40, 1)

    scrollFrame._bar = bar
    scrollFrame._barW = barW

    -- Mouse wheel scrolling
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local step = 28
        self:SetVerticalScroll(math.max(0, math.min(
            self:GetVerticalScrollRange(),
            self:GetVerticalScroll() - (delta * step)
        )))
    end)

    -- Handle scrollbar thumb dragging
    bar.thumb:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self._dragging = true
            local cursorY = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local top = self:GetTop()
            if top and scale and scale > 0 then
                self._clickOffset = top - (cursorY / scale)
            else
                self._clickOffset = 0
            end
        end
    end)
    bar.thumb:SetScript("OnMouseUp", function(self)
        self._dragging = false
    end)

    -- Handle track click (scroll to clicked position and start dragging)
    bar:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            local cursorY = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local barTop = self:GetTop()
            if barTop and scale and scale > 0 then
                local mouseVal = barTop - (cursorY / scale)
                local thumbH = bar.thumb:GetHeight()
                local usableRange = self:GetHeight() - thumbH
                local pct = 0
                if usableRange > 0 then
                    pct = (mouseVal - thumbH / 2) / usableRange
                    pct = math.max(0, math.min(1, pct))
                end
                scrollFrame:SetVerticalScroll(pct * scrollFrame:GetVerticalScrollRange())

                bar.thumb._dragging = true
                bar.thumb._clickOffset = thumbH / 2
            end
        end
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

        -- Process dragging if active
        if self._bar.thumb._dragging then
            if not IsMouseButtonDown("LeftButton") then
                self._bar.thumb._dragging = false
            else
                local thumb = self._bar.thumb
                local cursorY = GetCursorPosition()
                local scale = thumb:GetEffectiveScale()
                local barTop = self._bar:GetTop()
                if barTop and scale and scale > 0 then
                    local targetThumbTop = (cursorY / scale) + (thumb._clickOffset or 0)
                    local y = targetThumbTop - barTop
                    local barH = self._bar:GetHeight() - thumb:GetHeight()
                    local pct = 0
                    if barH > 0 then
                        pct = -y / barH
                        pct = math.max(0, math.min(1, pct))
                    end
                    self:SetVerticalScroll(pct * self:GetVerticalScrollRange())
                end
            end
        end

        local range = self:GetVerticalScrollRange()
        local cur = self:GetVerticalScroll()
        if range <= 0 then
            self._bar.thumb:ClearAllPoints()
            self._bar.thumb:SetPoint("TOP", self._bar, "TOP", 0, 0)
            return
        end
        local pct = cur / range
        local thumbH = self._bar.thumb:GetHeight()
        local barH = self._bar:GetHeight() - thumbH
        local y = -pct * barH
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
