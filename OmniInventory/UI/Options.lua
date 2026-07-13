-- =============================================================================
-- OmniInventory Configuration Panel
-- =============================================================================
-- Purpose: Standalone options frame called via /oi config
-- Style: Sidebar tabs + scrollable content panel, matching the bag interface
--        visual language defined by OpsTheme. Inspired by the CartoMapper
--        options layout but re-skinned with Omni's flat dark motif.
-- WoTLK 3.3.5a Compatible - Uses only native APIs
-- =============================================================================

local addonName, Omni = ...

Omni.Settings = {}
local Settings = Omni.Settings
local optionsFrame = nil
local OpsTheme = Omni.OpsTheme

local function RefreshAllInventory()
    if Omni.Frame then
        if Omni.Frame.InvalidateRenderCaches then
            Omni.Frame:InvalidateRenderCaches()
        end
        Omni.Frame:UpdateLayout()
    end
    if Omni.BankFrame and Omni.BankFrame.UpdateLayout then
        Omni.BankFrame:UpdateLayout()
    end
    if Omni.GuildBankFrame and Omni.GuildBankFrame.UpdateLayout then
        Omni.GuildBankFrame:UpdateLayout()
    end
end

local TOOLTIP_PLACEMENT_CYCLE = {
    "right",
    "left",
    "fixed_br",
    "fixed_bl",
    "fixed_tl",
    "fixed_tr",
}

local TOOLTIP_PLACEMENT_LABEL = {
    right = "Right of slot",
    left = "Left of slot",
    fixed_br = "Fixed (bottom-right)",
    fixed_bl = "Fixed (bottom-left)",
    fixed_tl = "Fixed (top-left)",
    fixed_tr = "Fixed (top-right)",
    fixed = "Fixed (bottom-right)",
}

local function IsFixedTooltipPlacementMode(mode)
    return mode == "fixed_br" or mode == "fixed_bl" or mode == "fixed_tl" or mode == "fixed_tr"
        or mode == "fixed"
end

local TOOLTIP_FIXED_X_MAX = 400
local TOOLTIP_FIXED_Y_MAX = 400
local TOOLTIP_PLACEMENT_TO_FIXED_SLIDER_GAP = 72

local function GetTooltipPlacementButtonLabel(mode)
    return TOOLTIP_PLACEMENT_LABEL[mode] or mode
end

local function CycleTooltipPlacementSetting()
    local cur = Omni.ItemButton and Omni.ItemButton.GetResolvedTooltipPlacement
        and Omni.ItemButton.GetResolvedTooltipPlacement() or "right"
    local idx = 1
    for i, v in ipairs(TOOLTIP_PLACEMENT_CYCLE) do
        if v == cur then
            idx = i
            break
        end
    end
    local nextPl = TOOLTIP_PLACEMENT_CYCLE[(idx % #TOOLTIP_PLACEMENT_CYCLE) + 1]
    if Omni.Data then
        Omni.Data:Set("itemTooltipPlacement", nextPl)
    end
end

local function FormatScalePercent(value)
    return string.format("%d%%", math.floor((value or 1) * 100 + 0.5))
end

local function FormatGapPixels(value)
    return string.format("%d px", math.floor((value or 0) + 0.5))
end

local function IsSettingEditLocked()
    return InCombatLockdown and InCombatLockdown()
end

local colorPickerCloseRefreshPending = false

local function RegisterColorPickerCloseRefresh()
    if not ColorPickerFrame or ColorPickerFrame.__OmniInvColorPickerHide then return end
    ColorPickerFrame.__OmniInvColorPickerHide = true
    ColorPickerFrame:HookScript("OnHide", function()
        if colorPickerCloseRefreshPending then
            colorPickerCloseRefreshPending = false
            RefreshAllInventory()
        end
    end)
end

local SECTION_COLORS = {
    -- OpenCode rule: marketing chrome stays monochrome. Headers use the ink
    -- ladder. Semantic tints (success/accent/warning) are reserved for TUI
    -- mockup panels only.
    view   = OpsTheme.PAL.TEXT,                -- ink
    sort   = OpsTheme.PAL.TEXT,                -- ink
    misc   = OpsTheme.PAL.TEXT_SECONDARY,      -- charcoal
    colors = OpsTheme.PAL.TEXT_SECONDARY,      -- charcoal
    footer = OpsTheme.PAL.TEXT,                -- ink
    addon  = OpsTheme.PAL.TEXT,                -- ink
    feat   = OpsTheme.PAL.TEXT_SECONDARY,      -- charcoal
}

local FOOTER_BUTTON_OPTIONS = {
    { key = "clearGlow",      label = "Mark All Read",   tipTitle = "Mark All Read",   tipSub = "Marks all new items in your bags as read/seen." },
    { key = "resetInstances", label = "Reset Instances", tipTitle = "Reset Instances", tipSub = "Resets all your dungeons and raid instances." },
    { key = "hearthstone",    label = "Hearthstone",    tipTitle = "Hearthstone",    tipSub = "Uses your Hearthstone if it is in your bags." },
    { key = "openables",      label = "Clam Opener",      tipTitle = "Clam Opener",      tipSub = "Automatically opens clams, lockboxes, or other containers in your bags." },
    { key = "disenchant",     label = "Disenchant",     tipTitle = "Disenchant",     tipSub = "Casts Disenchant (requires Enchanting profession)." },
    { key = "picklock",       label = "Pick Lock",       tipTitle = "Pick Lock",       tipSub = "Casts Pick Lock (requires Rogue class)." },
}


local function GetFooterButtonsDB()
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    OmniInventoryDB.global.footerButtons = OmniInventoryDB.global.footerButtons or {}
    return OmniInventoryDB.global.footerButtons
end

local function IsFooterButtonEnabled(key)
    local db = GetFooterButtonsDB()
    if db[key] == nil then db[key] = true end
    return db[key] == true
end

-- =============================================================================
-- Layout Constants
-- =============================================================================

local FRAME_W   = 540
local FRAME_H   = 480
local SIDEBAR_W = 130
local CONTENT_W = 360
local TAB_H     = 32
local TAB_GAP   = 2
local SPACING   = 54
local SECTION_GAP = 18
local HEADER_GAP   = 22
local COL_LEFT  = 14
local COL_RIGHT = 180
local ROW_H     = 22

-- Tab catalogue ---------------------------------------------------------------------------
-- Each entry: { label, builderKey }. builders stored on Settings keyed by
-- _builder_<key> and assembled in CreateControls (below) into per-tab panels.

local TAB_CATALOG = {
    { label = "General",            key = "general" },
    { label = "Scales & Layout",    key = "scales"  },
    { label = "View & Sort",        key = "viewsort" },
    { label = "Tooltips",           key = "tooltip" },
    { label = "Footer Buttons",     key = "footer"  },
    { label = "Auto-Display",       key = "autodisplay" },
    { label = "Features",           key = "features" },
    { label = "Rules",              key = "rules"   },
}

local activeTab = 1

-- =============================================================================
-- Creation
-- =============================================================================

function Settings:CreateOptionsFrame()
    if optionsFrame then return optionsFrame end

    optionsFrame = CreateFrame("Frame", "OmniOptionsFrame", UIParent)
    optionsFrame:SetSize(FRAME_W, FRAME_H)
    optionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    optionsFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    optionsFrame:SetFrameLevel(20)
    optionsFrame:SetClampedToScreen(true)
    optionsFrame:EnableMouse(true)
    optionsFrame:SetMovable(true)
    optionsFrame:RegisterForDrag("LeftButton")
    optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving)
    optionsFrame:SetScript("OnDragStop", optionsFrame.StopMovingOrSizing)
    optionsFrame:EnableKeyboard(true)
    optionsFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    optionsFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    optionsFrame:SetScript("OnEvent", function()
        if optionsFrame:IsShown() then
            self:UpdateValues()
        end
    end)

    -- Backdrop: flat dark motif matching bag interface
    OpsTheme:ApplyFrameBackdrop(optionsFrame)

    -- Register for ESC-close like the main bag frame
    if UISpecialFrames then
        local already = false
        for _, n in ipairs(UISpecialFrames) do
            if n == "OmniOptionsFrame" then already = true break end
        end
        if not already then
            tinsert(UISpecialFrames, "OmniOptionsFrame")
        end
    end

    -- Drag header strip (top 24px)
    local dragStrip = CreateFrame("Frame", nil, optionsFrame)
    dragStrip:SetHeight(24)
    dragStrip:SetPoint("TOPLEFT", OpsTheme.PAL.PADDING, -OpsTheme.PAL.PADDING)
    dragStrip:SetPoint("TOPRIGHT", -OpsTheme.PAL.PADDING, -OpsTheme.PAL.PADDING)
    dragStrip.bg = dragStrip:CreateTexture(nil, "BACKGROUND")
    dragStrip.bg:SetAllPoints()
    dragStrip.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    dragStrip.bg:SetVertexColor(unpack(OpsTheme.PAL.BG_HEADER))
    dragStrip:EnableMouse(true)
    dragStrip:RegisterForDrag("LeftButton")
    dragStrip:SetScript("OnDragStart", function() optionsFrame:StartMoving() end)
    dragStrip:SetScript("OnDragStop", function() optionsFrame:StopMovingOrSizing() end)

    -- Title: ASCII wordmark + caption (OpenCode nav-style)
    -- The brand identity is its own ASCII art. Single-line wordmark
    -- keeps it lightweight inside the nav header.
    local titleText = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", dragStrip, "TOPLEFT", 8, -5)
    titleText:SetText("|cfff1eee9 _/_/_/  |r|cffa8a39c OmniInventory Settings|r")

    -- Close button
    local closeBtn = OpsTheme.CreateButton(dragStrip, "X", 20, function()
        optionsFrame:Hide()
    end)
    closeBtn:SetHeight(20)
    closeBtn:SetPoint("RIGHT", dragStrip, "RIGHT", 0, 0)

    -- Bag/Bank target toggle placed at top-right of header beside close
    -- (Mirrors the previous dual-tab behavior but compact.)
    local targetBtn = OpsTheme.CreateButton(dragStrip, "Target: Bag", 100, function()
        local target = Settings.activeConfigTarget or "bag"
        local nextTarget = target == "bag" and "bank" or "bag"
        Settings.activeConfigTarget = nextTarget
        self:RefreshTargetLabel()
        Settings:UpdateValues()
    end)
    targetBtn:SetSize(100, 20)
    targetBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    self.targetBtn = targetBtn

    -- =============================================================================
    -- Sidebar (vertical tab list)
    -- =============================================================================

    local sidebar = CreateFrame("Frame", nil, optionsFrame)
    sidebar:SetSize(SIDEBAR_W, FRAME_H - 24 - OpsTheme.PAL.PADDING * 2 - 10)
    sidebar:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", OpsTheme.PAL.PADDING, -34)
    OpsTheme:ApplyControlBackdrop(sidebar)
    sidebar:SetBackdropColor(0, 0, 0, 0.45)

    -- Scrollable content area
    local contentArea = OpsTheme.CreateScrollFrame(optionsFrame, CONTENT_W, 0)
    contentArea:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, 0)
    contentArea:SetPoint("BOTTOMRIGHT", optionsFrame, "BOTTOMRIGHT", -OpsTheme.PAL.PADDING - 6, OpsTheme.PAL.PADDING + 6)
    self.contentArea = contentArea

    local scrollChild = CreateFrame("Frame", nil, contentArea)
    scrollChild:SetSize(CONTENT_W, 1)
    contentArea:SetScrollChild(scrollChild)
    self.content = scrollChild

    -- Tab buttons + per-tab panels
    self.tabButtons = {}
    self.tabPanels  = {}
    self._syncingScaleControls = false

    for i, def in ipairs(TAB_CATALOG) do
        local btn = OpsTheme.CreateSidebarTab(sidebar, def.label, SIDEBAR_W - 10, TAB_H,
            i == activeTab, function()
                self:SelectTab(i)
            end)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 5, -5 - (i - 1) * (TAB_H + TAB_GAP))
        self.tabButtons[i] = btn

        local panel = CreateFrame("Frame", nil, scrollChild)
        panel:SetAllPoints()
        panel:Hide()
        self.tabPanels[i] = panel
    end

    -- Build the widgets into each panel
    self:CreateControls()

    -- Keyboard: ESC closes
    optionsFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
        end
    end)

    self:RefreshTargetLabel()
    self:SelectTab(activeTab, true)
    optionsFrame:Hide()
    return optionsFrame
end

-- =============================================================================
-- Tab switching
-- =============================================================================

function Settings:SelectTab(index, skipScrollReset)
    activeTab = index
    if not skipScrollReset and self.contentArea then
        self.contentArea:SetVerticalScroll(0)
    end
    for i, panel in ipairs(self.tabPanels) do
        if i == index then
            panel:Show()
        else
            panel:Hide()
        end
    end
    for i, btn in ipairs(self.tabButtons) do
        btn:SetActive(i == index)
    end

    -- The scrollChild tracks the visible panel's height so the scrollbar
    -- reflects only the active tab's content length.
    local panel = self.tabPanels and self.tabPanels[index]
    if panel and panel.Refresh then
        panel:Refresh()
    end
    if panel and panel._contentHeight and self.content then
        self.content:SetHeight(panel._contentHeight)
    end
end

function Settings:RefreshTargetLabel()
    if not self.targetBtn then return end
    local target = Settings.activeConfigTarget or "bag"
    self.targetBtn.text:SetText("Target: " .. (target == "bank" and "Bank" or "Bag"))
end

-- =============================================================================
-- Widget assembly
-- =============================================================================

function Settings:CreateControls()
    self.colorSwatches = {}
    self:BuildGeneral(self.tabPanels[1])
    self:BuildScales(self.tabPanels[2])
    self:BuildViewSort(self.tabPanels[3])
    self:BuildTooltips(self.tabPanels[4])
    self:BuildFooterButtons(self.tabPanels[5])
    self:BuildAutoDisplay(self.tabPanels[6])
    self:BuildFeatures(self.tabPanels[7])
    if self.tabPanels[8] then
        self:BuildRules(self.tabPanels[8])
    end
end

-- Shared checkbox factory that wires to Omni.Data
local function MakeDataCheckbox(panel, x, y, label, tipTitle, tipSub, dataKey,
        defaultTrue, onChange, refreshAfter)
    local cb = OpsTheme.CreateCheckButton(panel, label, tipTitle, tipSub, false, function(self, checked)
        if Omni.Data then
            Omni.Data:Set(dataKey, checked)
            if onChange then onChange(checked) end
            if refreshAfter then RefreshAllInventory() end
        end
    end)
    cb:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    cb._dataKey = dataKey
    cb._defaultTrue = defaultTrue
    return cb
end

-- =============================================================================
-- Tab 1: General (key options + reset)
-- =============================================================================

function Settings:BuildGeneral(panel)
    local y = -15

    local header = OpsTheme.CreateSectionHeader(panel, "[+]  General Options", SECTION_COLORS.misc)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    y = y - HEADER_GAP

    local function MakeCb(col, row, label, tipTitle, tipSub, dataKey, defaultTrue, onChange, refreshAfter)
        local xoff = col == 0 and COL_LEFT or COL_RIGHT
        local cb = MakeDataCheckbox(panel, xoff, y - (row * ROW_H), label, tipTitle, tipSub,
            dataKey, defaultTrue, onChange, refreshAfter)
        return cb
    end

    -- Row 0
    local row = 0
    self.highlightNewItemsCb = MakeCb(0, row,
        "New items",
        "Highlight new items",
        "Visually emphasize items that count as new in your bags.",
        "highlightNewItems", true, nil, true)
    self.footerMoneyEmphasisCb = MakeCb(1, row,
        "Bold footer",
        "Bold footer",
        "Larger outlined gold and bag count. Slot text shifts from light blue to red as bags fill.",
        "footerMoneyEmphasis", true, function()
            if Omni.Frame and Omni.Frame.RefreshFooterMoneyStyle then
                Omni.Frame:RefreshFooterMoneyStyle()
            end
        end, true)

    -- Row 1
    row = 1
    self.enableBoundCategoriesCb = MakeCb(0, row,
        "Bound lanes",
        "Categorize bound items",
        "Separate Soulbound (BoP) equipment and Account Bound (BoA/Heirlooms) into their own lanes.",
        "enableBoundCategories", true, nil, true)
    self.enableUnusableOverlayCb = MakeCb(1, row,
        "Red overlays",
        "Unusable red overlay",
        "Tints unusable gear (level/class locks) and unlearned recipes red.",
        "enableUnusableOverlay", true, nil, true)

    -- Row 2
    row = 2
    self.showItemLevelCb = MakeCb(0, row,
        "Item levels",
        "Show Item Levels",
        "Displays the item level (iLevel) directly on weapons and armor in your bags and bank.",
        "showItemLevel", true, nil, true)
    self.vendorDoubleRightClickCb = MakeCb(1, row,
        "Double-click sell protection",
        "Vendor Sell Protection",
        "Requires a double-right-click to sell valuable items (Soulbound gear, active quest items, rare/epic loot) at vendors.",
        "vendorDoubleRightClick", true)

    -- Row 3
    row = 3
    self.enableKnownRecipeOverlayCb = MakeCb(0, row,
        "Green recipes",
        "Known Recipe Overlay",
        "Tints already-learned recipes green in bag, bank, mailbox, inbox, trade, loot, and merchant frames.",
        "enableKnownRecipeOverlay", true, nil, true)
    self.collapseEmptySlotsCb = MakeCb(1, row,
        "Collapse empty slots",
        "Collapse Empty Slots",
        "Collapses all empty slots in Grid and Flow views into a single slot button per bag type, displaying a count of the total empty spaces.",
        "collapseEmptySlots", false, nil, true)

    -- Row 4
    row = 4
    self.boundIndicatorCb = MakeCb(0, row,
        "Bound indicator",
        "Bound Item Indicator",
        "Shows a small chain icon on soulbound items in the bag.",
        "showBoundIndicator", false, nil, true)
    self.bagTypeTagsCb = MakeCb(1, row,
        "Bag type tags",
        "Bag Type Tags",
        "Shows family tag text (Ammo, Herb, Mining, etc.) on specialty bag tooltips.",
        "showBagTypeTags", false)
    self.showCategoryStripeCb = MakeCb(1, row,
        "Category stripe",
        "Category Color Stripe",
        "Displays a small vertical stripe on the left edge of each item slot matching its category color.",
        "showCategoryStripe", false, nil, true)

    -- Row 5
    row = 5
    self.footerMoneyIconsCb = MakeCb(0, row,
        "Money icons",
        "Coin Icons",
        "Show the footer money as gold, silver, and copper coin icons instead of text (e.g. 12g 34s 56c).",
        "footerMoneyIcons", false, function()
            if Omni.Frame then
                Omni.Frame:UpdateMoney()
                if Omni.Frame.UpdateFooterCustomButtons then
                    Omni.Frame:UpdateFooterCustomButtons()
                end
            end
        end, true)
    self.vendorCtrlRightClickCb = MakeCb(1, row,
        "Ctrl right-click bypass",
        "Ctrl+Right-Click Sell Bypass",
        "Allows holding the Ctrl key while right-clicking a protected item to instantly sell it, bypassing the double-click warning.",
        "vendorCtrlRightClick", true)

    y = y - (ROW_H * 6) - SECTION_GAP

    local resetHeader = OpsTheme.CreateSectionHeader(panel, "[+]  Frame Position", SECTION_COLORS.footer)
    resetHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    y = y - HEADER_GAP

    local resetBtn = OpsTheme.CreateButton(panel, "Reset Position & Scale", 220, function()
        local target = Settings.activeConfigTarget or "bag"
        if target == "bank" and Omni.BankFrame then
            local bFrame = Omni.BankFrame:GetFrame()
            if bFrame then
                bFrame:ClearAllPoints()
                bFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
            Omni.BankFrame:SetScale(1.0)
            Omni.BankFrame:SetItemScale(1.0)
            Omni.BankFrame:SetItemGap(4)
        elseif Omni.Frame then
            Omni.Frame:ResetPosition()
            Omni.Frame:SetScale(1.0)
            Omni.Frame:SetItemScale(1.0)
            Omni.Frame:SetItemGap(4)
        end
        Settings:UpdateValues()
    end)
    resetBtn:SetSize(220, OpsTheme.PAL.BTN_HEIGHT)
    resetBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    resetBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_HOVER))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_HOVER))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Reset Position & Scale", 1, 0.82, 0)
        GameTooltip:AddLine("Resets the selected target's (Bag or Bank) window position, scale, item size, and padding back to defaults.", 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER))
        GameTooltip:Hide()
    end)
    y = y - SPACING

    panel._contentHeight = math.abs(y) + 40
end

-- =============================================================================
-- Tab 2: Scales & Layout
-- =============================================================================

function Settings:BuildScales(panel)
    local y = -15

    local header = OpsTheme.CreateSectionHeader(panel, "[+]  Frame Scaling", SECTION_COLORS.misc)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    y = y - HEADER_GAP

    local scaleSlider = OpsTheme.CreateSlider(panel, "Frame Scale", 0.5, 2.0, 0.1, FormatScalePercent, function(value)
        if IsSettingEditLocked() then
            Settings:UpdateValues()
            print("|cFFFF4040OmniInventory|r: Scale settings can only be changed out of combat.")
            return
        end
        local target = Settings.activeConfigTarget or "bag"
        if target == "bank" and Omni.BankFrame then
            Omni.BankFrame:SetScale(value)
        elseif Omni.Frame then
            Omni.Frame:SetScale(value)
        end
    end, "Frame Scale", "Adjust the scale of the bag or bank frame (50% to 200%).")
    scaleSlider:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    self.scaleSlider = scaleSlider
    y = y - SPACING

    local itemScaleSlider = OpsTheme.CreateSlider(panel, "Item Scale", 0.5, 2.0, 0.1, FormatScalePercent, function(value)
        if IsSettingEditLocked() then
            Settings:UpdateValues()
            print("|cFFFF4040OmniInventory|r: Scale settings can only be changed out of combat.")
            return
        end
        local target = Settings.activeConfigTarget or "bag"
        if target == "bank" and Omni.BankFrame then
            Omni.BankFrame:SetItemScale(value)
        elseif Omni.Frame and Omni.Frame.SetItemScale then
            Omni.Frame:SetItemScale(value)
        end
    end, "Item Scale", "Adjust the size/scale of individual item buttons (50% to 200%).")
    itemScaleSlider:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    self.itemScaleSlider = itemScaleSlider
    y = y - SPACING

    local itemGapSlider = OpsTheme.CreateSlider(panel, "Item Gap", 0, 20, 1, FormatGapPixels, function(value)
        if IsSettingEditLocked() then
            Settings:UpdateValues()
            print("|cFFFF4040OmniInventory|r: Scale settings can only be changed out of combat.")
            return
        end
        local target = Settings.activeConfigTarget or "bag"
        if target == "bank" and Omni.BankFrame then
            Omni.BankFrame:SetItemGap(value)
        elseif Omni.Frame and Omni.Frame.SetItemGap then
            Omni.Frame:SetItemGap(value)
        end
    end, "Item Gap", "Adjust the spacing between item buttons (0 to 20 pixels).")
    itemGapSlider:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    self.itemGapSlider = itemGapSlider
    y = y - SPACING

    local combatNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    combatNote:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    combatNote:SetWidth(CONTENT_W - COL_LEFT * 2)
    combatNote:SetJustifyH("LEFT")
    combatNote:SetText("Note: scaling sliders are disabled in combat. Bag/Bank target is set in the header.")
    combatNote:SetTextColor(unpack(OpsTheme.PAL.TEXT_DIM))
    y = y - 32

    panel._contentHeight = math.abs(y) + 40
end

-- =============================================================================
-- Tab 3: View & Sort
-- =============================================================================

function Settings:BuildViewSort(panel)
    local y = -15

    local viewHeader = OpsTheme.CreateSectionHeader(panel, "[+]  View Mode", SECTION_COLORS.view)
    viewHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    y = y - HEADER_GAP

    local viewBtn = OpsTheme.CreateButton(panel, "View: Grid", 160, function()
        if Omni.Frame then
            Omni.Frame:CycleView()
            self:RefreshViewLabel()
        end
    end)
    viewBtn:SetSize(160, OpsTheme.PAL.BTN_HEIGHT)
    viewBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    viewBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_HOVER))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_HOVER))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("View Mode", 1, 0.82, 0)
        GameTooltip:AddLine("Choose how items are laid out: Grid, Flow (categorized grid), List, or Bag (classic view).", 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    viewBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER))
        GameTooltip:Hide()
    end)
    self.viewBtn = viewBtn
    y = y - SPACING

    local sortHeader = OpsTheme.CreateSectionHeader(panel, "[+]  Sort Mode (Default)", SECTION_COLORS.sort)
    sortHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    y = y - HEADER_GAP

    local sortBtn = OpsTheme.CreateButton(panel, "Sort: Category", 160, function()
        if Omni.Frame then
            Omni.Frame:CycleSort()
            self:RefreshSortLabel()
        end
    end)
    sortBtn:SetSize(160, OpsTheme.PAL.BTN_HEIGHT)
    sortBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    sortBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_HOVER))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_HOVER))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sort Mode", 1, 0.82, 0)
        GameTooltip:AddLine("Choose how items are sorted: Category, Quality, Name, Item Level, or Usage.", 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    sortBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER))
        GameTooltip:Hide()
    end)
    self.sortBtn = sortBtn
    y = y - SPACING

    local themeHeader = OpsTheme.CreateSectionHeader(panel, "[+]  Theme", SECTION_COLORS.colors)
    themeHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    y = y - HEADER_GAP

    local themeBtn = OpsTheme.CreateButton(panel, "Theme: Rounded", 160, function()
        if Omni.Features and Omni.Features.GetTheme then
            local cur = Omni.Features:GetTheme()
            local nextTheme = cur == "square" and "rounded" or "square"
            Omni.Features:SetTheme(nextTheme)
            Settings:RefreshThemeLabel()
            if Omni.Frame and Omni.Frame.ApplyTheme then
                Omni.Frame:ApplyTheme()
            end
            RefreshAllInventory()
        end
    end)
    themeBtn:SetSize(160, OpsTheme.PAL.BTN_HEIGHT)
    themeBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    themeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_HOVER))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_HOVER))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Theme", 1, 0.82, 0)
        GameTooltip:AddLine("Rounded: default WoW borders. Square: pfUI-compatible, cropped icons.", 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    themeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER))
        GameTooltip:Hide()
    end)
    self.themeBtn = themeBtn
    y = y - SPACING

    panel._contentHeight = math.abs(y) + 40
end

-- =============================================================================
-- Tab 4: Tooltips
-- =============================================================================

function Settings:BuildTooltips(panel)
    local y = -15

    local tipPlacementHeader = OpsTheme.CreateSectionHeader(panel, "[+]  Item Tooltips", SECTION_COLORS.addon)
    tipPlacementHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    y = y - HEADER_GAP

    local describe = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    describe:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    describe:SetWidth(CONTENT_W - COL_LEFT * 2 - 10)
    describe:SetJustifyH("LEFT")
    describe:SetText("Item tooltips (bags, bank, guild bank, offline)")
    describe:SetTextColor(unpack(OpsTheme.PAL.TEXT_LABEL))
    y = y - 20

    local tipPlacementBtn = OpsTheme.CreateButton(panel, "Right of slot", 240, function()
        CycleTooltipPlacementSetting()
        Settings:RefreshTooltipPlacementControls()
    end)
    tipPlacementBtn:SetSize(240, OpsTheme.PAL.BTN_HEIGHT)
    tipPlacementBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    tipPlacementBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_HOVER))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_HOVER))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Tooltip placement", 1, 0.82, 0)
        GameTooltip:AddLine("Right / Left: anchor relative to the slot. Fixed modes: screen corner + X/Y insets (sliders below).", 0.75, 0.75, 0.75, true)
        GameTooltip:AddLine("Click the button to cycle modes.", 0.65, 0.65, 0.65, true)
        GameTooltip:Show()
    end)
    tipPlacementBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL))
        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER))
        GameTooltip:Hide()
    end)
    self.tooltipPlacementBtn = tipPlacementBtn
    y = y - TOOLTIP_PLACEMENT_TO_FIXED_SLIDER_GAP

    local tipFixedXSlider = OpsTheme.CreateSlider(panel, "Fixed X (horizontal inset)", 0, TOOLTIP_FIXED_X_MAX, 1, nil, function(value)
        if Settings._syncingTooltipFixedSliders then return end
        if OmniInventoryDB and OmniInventoryDB.global then
            OmniInventoryDB.global.itemTooltipFixed = OmniInventoryDB.global.itemTooltipFixed or {}
            OmniInventoryDB.global.itemTooltipFixed.x = value
        end
        if Omni.ItemButton and Omni.ItemButton.FinalizeOmniItemTooltipLayout then
            Omni.ItemButton.FinalizeOmniItemTooltipLayout()
        end
    end, "Fixed X Offset", "Inset of the fixed tooltip from the left/right screen edge.")
    tipFixedXSlider:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    self.tooltipFixedXSlider = tipFixedXSlider
    y = y - SPACING

    local tipFixedYSlider = OpsTheme.CreateSlider(panel, "Fixed Y (vertical inset)", 0, TOOLTIP_FIXED_Y_MAX, 1, nil, function(value)
        if Settings._syncingTooltipFixedSliders then return end
        if OmniInventoryDB and OmniInventoryDB.global then
            OmniInventoryDB.global.itemTooltipFixed = OmniInventoryDB.global.itemTooltipFixed or {}
            OmniInventoryDB.global.itemTooltipFixed.y = value
        end
        if Omni.ItemButton and Omni.ItemButton.FinalizeOmniItemTooltipLayout then
            Omni.ItemButton.FinalizeOmniItemTooltipLayout()
        end
    end, "Fixed Y Offset", "Inset of the fixed tooltip from the top/bottom screen edge.")
    tipFixedYSlider:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    self.tooltipFixedYSlider = tipFixedYSlider
    y = y - SPACING

    self:RefreshTooltipPlacementControls()

    panel._contentHeight = math.abs(y) + 40
end

-- =============================================================================
-- Tab 5: Footer Buttons
-- =============================================================================

function Settings:BuildFooterButtons(panel)
    local y = -15

    local footerHeader = OpsTheme.CreateSectionHeader(panel, "[+]  Footer Buttons", SECTION_COLORS.footer)
    footerHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    y = y - HEADER_GAP

    self.footerButtonCbs = {}
    for i, def in ipairs(FOOTER_BUTTON_OPTIONS) do
        local column = (i - 1) % 2
        local rowIdx = math.floor((i - 1) / 2)
        local xoff = column == 0 and COL_LEFT or COL_RIGHT
        local rowY = y - (rowIdx * ROW_H)

        local cb = OpsTheme.CreateCheckButton(panel, def.label, def.tipTitle, def.tipSub, IsFooterButtonEnabled(def.key), function(self, checked)
            local db = GetFooterButtonsDB()
            db[def.key] = checked
            if Omni.Frame and Omni.Frame.UpdateFooterCustomButtons then
                Omni.Frame:UpdateFooterCustomButtons()
            end
        end)
        cb:SetPoint("TOPLEFT", xoff, rowY)
        self.footerButtonCbs[def.key] = cb
    end
    local rowCount = math.ceil(#FOOTER_BUTTON_OPTIONS / 2)
    y = y - (rowCount * ROW_H) - SECTION_GAP

    panel._contentHeight = math.abs(y) + 40
end

-- =============================================================================
-- Tab 6: Auto-Display
-- =============================================================================

function Settings:BuildAutoDisplay(panel)
    local y = -15

    local adHeader = OpsTheme.CreateSectionHeader(panel, "[+]  Auto-Display", SECTION_COLORS.feat)
    adHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    y = y - HEADER_GAP

    local function MakeAd(row, col, label, tipTitle, tipSub, subKey)
        local xoff = col == 0 and COL_LEFT or COL_RIGHT
        local cb = OpsTheme.CreateCheckButton(panel, label, tipTitle, tipSub, false, function(self, checked)
            if Omni.Data then
                local ad = Omni.Data:Get("autoDisplay") or {}
                ad[subKey] = checked
                Omni.Data:Set("autoDisplay", ad)
            end
        end)
        cb:SetPoint("TOPLEFT", xoff, y - (row * ROW_H))
        cb._adSubKey = subKey
        return cb
    end

    -- Row 0
    self.autoDisplayBankCb   = MakeAd(0, 0, "Auto-open at Bank",   "Auto-open at Bank", "Automatically opens the bag window when you interact with a banker.", "bank")
    self.autoDisplayVendorCb = MakeAd(0, 1, "Auto-open at Vendor", "Auto-open at Vendor", "Automatically opens the bag window when you interact with a merchant.", "vendor")
    -- Row 1
    self.autoDisplayMailCb = MakeAd(1, 0, "Auto-open at Mail", "Auto-open at Mail", "Automatically opens the bag window when you open your mailbox.", "mail")
    self.autoDisplayAhCb   = MakeAd(1, 1, "Auto-open at AH",   "Auto-open at AH", "Automatically opens the bag window when you interact with an Auctioneer.", "ah")
    -- Row 2
    self.autoDisplayTradeCb = MakeAd(2, 0, "Auto-open at Trade", "Auto-open at Trade", "Automatically opens the bag window when trading with another player.", "trade")
    self.autoDisplayCraftCb = MakeAd(2, 1, "Auto-open at Craft", "Auto-open at Craft", "Automatically opens the bag window when viewing a profession/crafting pane.", "craft")

    y = y - (ROW_H * 3) - SECTION_GAP

    panel._contentHeight = math.abs(y) + 40
end

-- =============================================================================
-- Tab 8: Features (cache warmer, auto-loot, money tracker, etc.)
-- =============================================================================

function Settings:BuildFeatures(panel)
    local y = -15

    local header = OpsTheme.CreateSectionHeader(panel, "[+]  Inventory Features", SECTION_COLORS.feat)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y)
    y = y - HEADER_GAP

    local function MakeFe(row, col, label, tipTitle, tipSub, dataKey, defaultTrue, onChange, refreshAfter)
        local xoff = col == 0 and COL_LEFT or COL_RIGHT
        local cb = MakeDataCheckbox(panel, xoff, y - (row * ROW_H), label, tipTitle, tipSub,
            dataKey, defaultTrue, onChange, refreshAfter)
        return cb
    end

    -- Row 0
    local row = 0
    self.cacheWarmerCb = MakeFe(row, 0,
        "Cache warmer",
        "Cache Warmer",
        "Pre-loads GetItemInfo for known item IDs on login to avoid tooltip delays.",
        "cacheWarmer", true, function(checked)
            if checked and Omni.Features and Omni.Features.WarmCache then
                Omni.Features:WarmCache()
            end
        end)
    self.autoLootCb = MakeFe(row, 1,
        "Auto-loot",
        "Auto-Loot",
        "Automatically loots all items when a loot frame opens.",
        "autoLoot", false, function(checked)
            if Omni.Features and Omni.Features.InitAutoLoot then
                Omni.Features:InitAutoLoot()
            end
        end)

    -- Row 1
    row = 1
    self.moneyTrackerCb = MakeFe(row, 0,
        "Money tracker",
        "Money Tracker",
        "Records gold history per character over time for trend display.",
        "moneyTracker", false)
    self.autoSellJunkCb = MakeFe(row, 1,
        "Auto-sell junk",
        "Auto-sell junk",
        "Automatically sells all grey quality items in your bags when visiting a merchant NPC. Alt+Right-Click any item in your bags to toggle its junk/auto-sell status.",
        "autoSellJunk", true)

    -- Row 2 (auto-repair + guild funds)
    row = 2
    self.autoRepairCb = MakeFe(row, 0,
        "Auto-repair",
        "Auto-repair gear",
        "Automatically repairs all equipped and inventory gear when visiting a repair merchant.",
        "autoRepair", false, function(checked)
            if self.autoRepairGuildCb then
                self.autoRepairGuildCb:SetEnabled(checked)
            end
        end)
    self.autoRepairGuildCb = MakeFe(row, 1,
        "Use Guild funds",
        "Use Guild Funds",
        "Attempts to use guild bank funds for auto-repairs before using your own gold.",
        "autoRepairGuild", false)

    -- Link auto-repair → guild funds
    if self.autoRepairCb and self.autoRepairGuildCb then
        self.autoRepairCb._guildFundsCb = self.autoRepairGuildCb
    end

    -- Row 3
    row = 3
    self.autoTidyCb = MakeFe(row, 0,
        "Auto-tidy on close",
        "Auto-Tidy on Close",
        "Compacts bag layout and sorts when the bag window is closed (AdiBags TidyBags).",
        "autoTidyOnClose", false)
    self.resortButtonCb = MakeFe(row, 1,
        "Resort button",
        "Resort Button",
        "Shows a resort button when a dry-run detects the layout could be reorganized.",
        "showResortButton", false, function()
            if Omni.Frame and Omni.Frame.UpdateResortButtonVisibility then
                Omni.Frame:UpdateResortButtonVisibility()
            end
        end)

    row = 4
    -- Account-wide toggle -- separate from per-character Omni.Data so it
    -- can't reuse MakeDataCheckbox. Wired through the Categorizer setter
    -- which also invalidates the per-item cache.
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    OmniInventoryDB.global.detailedCategories = OmniInventoryDB.global.detailedCategories or false
    self.detailedCategoriesCb = OpsTheme.CreateCheckButton(panel,
        "Detailed categories",
        "Detailed Categories",
        "Opt-in extra buckets inspired by ArkInventory, AdiBags, and GudaBags: Soul Shards (id 6265), Hearthstone (id 6948), Recipes (itemType), Gems, Trinkets (INVTYPE_TRINKET), and Food vs Drink split. Toggling reclassifies items on next refresh.",
        OmniInventoryDB.global.detailedCategories == true,
        function(_, checked)
            if Omni.Categorizer and Omni.Categorizer.SetDetailedCategories then
                Omni.Categorizer:SetDetailedCategories(checked)
            else
                OmniInventoryDB.global.detailedCategories = checked and true or false
            end
            if Omni.Frame and Omni.Frame.InvalidateRenderCaches then
                Omni.Frame:InvalidateRenderCaches({ clearLayout = true })
                Omni.Frame:UpdateLayout()
            end
            if Omni.BankFrame and Omni.BankFrame.UpdateLayout then
                Omni.BankFrame:UpdateLayout()
            end
            if Omni.GuildBankFrame and Omni.GuildBankFrame.UpdateLayout then
                Omni.GuildBankFrame:UpdateLayout()
            end
        end)
    self.detailedCategoriesCb:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_LEFT, y - (row * ROW_H))

    y = y - (ROW_H * 5) - SECTION_GAP

    panel._contentHeight = math.abs(y) + 40
end

-- =============================================================================
-- Actions
-- =============================================================================

function Settings:Toggle()
    if not optionsFrame then
        self:CreateOptionsFrame()
    end

    if optionsFrame:IsShown() then
        optionsFrame:Hide()
    else
        self:UpdateValues()
        optionsFrame:Show()
    end
end

function Settings:RefreshTooltipPlacementControls()
    if not Omni.ItemButton or not Omni.ItemButton.GetResolvedTooltipPlacement then
        return
    end
    local mode = Omni.ItemButton.GetResolvedTooltipPlacement()
    if self.tooltipPlacementBtn and self.tooltipPlacementBtn.text then
        self.tooltipPlacementBtn.text:SetText(GetTooltipPlacementButtonLabel(mode))
    end
    local fixedActive = IsFixedTooltipPlacementMode(mode)
    local inactiveAlpha = 0.48
    local function StyleFixedSlider(slider, enabled)
        if not slider then return end
        slider:SetAlpha(enabled and 1 or inactiveAlpha)
        slider:EnableMouse(enabled)
    end
    StyleFixedSlider(self.tooltipFixedXSlider, fixedActive)
    StyleFixedSlider(self.tooltipFixedYSlider, fixedActive)
end

function Settings:UpdateValues()
    if not optionsFrame then return end

    self._syncingScaleControls = true
    RegisterColorPickerCloseRefresh()

    -- General checkboxes
    if self.highlightNewItemsCb and Omni.Data then
        self.highlightNewItemsCb:SetChecked(Omni.Data:Get("highlightNewItems") == true)
    end
    if self.footerMoneyEmphasisCb and Omni.Data then
        self.footerMoneyEmphasisCb:SetChecked(Omni.Data:Get("footerMoneyEmphasis") == true)
    end
    if self.footerMoneyIconsCb and Omni.Data then
        self.footerMoneyIconsCb:SetChecked(Omni.Data:Get("footerMoneyIcons") == true)
    end
    if self.enableBoundCategoriesCb and Omni.Data then
        self.enableBoundCategoriesCb:SetChecked(Omni.Data:Get("enableBoundCategories") ~= false)
    end
    if self.enableUnusableOverlayCb and Omni.Data then
        self.enableUnusableOverlayCb:SetChecked(Omni.Data:Get("enableUnusableOverlay") ~= false)
    end
    if self.showItemLevelCb and Omni.Data then
        self.showItemLevelCb:SetChecked(Omni.Data:Get("showItemLevel") ~= false)
    end
    if self.vendorDoubleRightClickCb and Omni.Data then
        self.vendorDoubleRightClickCb:SetChecked(Omni.Data:Get("vendorDoubleRightClick") ~= false)
    end
    if self.vendorCtrlRightClickCb and Omni.Data then
        self.vendorCtrlRightClickCb:SetChecked(Omni.Data:Get("vendorCtrlRightClick") ~= false)
    end
    if self.collapseEmptySlotsCb and Omni.Data then
        self.collapseEmptySlotsCb:SetChecked(Omni.Data:Get("collapseEmptySlots") == true)
    end
    if self.boundIndicatorCb and Omni.Data then
        self.boundIndicatorCb:SetChecked(Omni.Data:Get("showBoundIndicator") == true)
    end
    if self.bagTypeTagsCb and Omni.Data then
        self.bagTypeTagsCb:SetChecked(Omni.Data:Get("showBagTypeTags") == true)
    end
    if self.showCategoryStripeCb and Omni.Data then
        self.showCategoryStripeCb:SetChecked(Omni.Data:Get("showCategoryStripe") == true)
    end
    if self.enableKnownRecipeOverlayCb and Omni.Data then
        self.enableKnownRecipeOverlayCb:SetChecked(Omni.Data:Get("enableKnownRecipeOverlay") ~= false)
    end

    -- Scales sliders
    local target = Settings.activeConfigTarget or "bag"
    local scale, itemScale, itemGap
    if target == "bank" and Omni.BankFrame and Omni.BankFrame.GetScale then
        scale = Omni.BankFrame:GetScale()
        itemScale = Omni.BankFrame:GetItemScale()
        itemGap = Omni.BankFrame:GetItemGap()
    else
        scale = (Omni.Frame and Omni.Frame.GetScale and Omni.Frame:GetScale()) or 1.0
        itemScale = (Omni.Frame and Omni.Frame.GetItemScale and Omni.Frame:GetItemScale()) or 1.0
        itemGap = (Omni.Frame and Omni.Frame.GetItemGap and Omni.Frame:GetItemGap()) or 4
    end
    if self.scaleSlider then self.scaleSlider:SetValue(scale) end
    if self.itemScaleSlider then self.itemScaleSlider:SetValue(itemScale) end
    if self.itemGapSlider then self.itemGapSlider:SetValue(itemGap) end
    local scaleControlsEnabled = not IsSettingEditLocked()
    if self.scaleSlider then self.scaleSlider:SetEnabled(scaleControlsEnabled) end
    if self.itemScaleSlider then self.itemScaleSlider:SetEnabled(scaleControlsEnabled) end
    if self.itemGapSlider then self.itemGapSlider:SetEnabled(scaleControlsEnabled) end

    -- Tooltip fixed sliders + placement button
    self._syncingTooltipFixedSliders = true
    if Omni.Data and self.tooltipFixedXSlider and self.tooltipFixedYSlider then
        local fix = Omni.Data:Get("itemTooltipFixed") or {}
        local fx = math.max(0, math.min(tonumber(fix.x) or 24, TOOLTIP_FIXED_X_MAX))
        local fy = math.max(0, math.min(tonumber(fix.y) or 140, TOOLTIP_FIXED_Y_MAX))
        self.tooltipFixedXSlider:SetValue(fx)
        self.tooltipFixedYSlider:SetValue(fy)
    end
    self._syncingTooltipFixedSliders = false
    self:RefreshTooltipPlacementControls()

    -- Footer buttons
    if self.footerButtonCbs then
        for _, def in ipairs(FOOTER_BUTTON_OPTIONS) do
            local cb = self.footerButtonCbs[def.key]
            if cb then cb:SetChecked(IsFooterButtonEnabled(def.key)) end
        end
    end
    -- Auto-display checkboxes (Bank/Vendor/Mail/AH/Trade/Craft)
    local ad = Omni.Data and Omni.Data:Get("autoDisplay") or {}
    if self.autoDisplayBankCb then self.autoDisplayBankCb:SetChecked(ad.bank == true) end
    if self.autoDisplayVendorCb then self.autoDisplayVendorCb:SetChecked(ad.vendor == true) end
    if self.autoDisplayMailCb then self.autoDisplayMailCb:SetChecked(ad.mail == true) end
    if self.autoDisplayAhCb then self.autoDisplayAhCb:SetChecked(ad.ah == true) end
    if self.autoDisplayTradeCb then self.autoDisplayTradeCb:SetChecked(ad.trade == true) end
    if self.autoDisplayCraftCb then self.autoDisplayCraftCb:SetChecked(ad.craft == true) end

    -- Features checkboxes
    if self.cacheWarmerCb and Omni.Data then
        self.cacheWarmerCb:SetChecked(Omni.Data:Get("cacheWarmer") ~= false)
    end
    if self.autoLootCb and Omni.Data then
        self.autoLootCb:SetChecked(Omni.Data:Get("autoLoot") == true)
    end
    if self.moneyTrackerCb and Omni.Data then
        self.moneyTrackerCb:SetChecked(Omni.Data:Get("moneyTracker") == true)
    end
    if self.autoSellJunkCb and Omni.Data then
        self.autoSellJunkCb:SetChecked(Omni.Data:Get("autoSellJunk") ~= false)
    end
    if self.autoRepairCb and Omni.Data then
        local repairActive = Omni.Data:Get("autoRepair") == true
        self.autoRepairCb:SetChecked(repairActive)
        if self.autoRepairGuildCb then
            if repairActive then
                self.autoRepairGuildCb:SetEnabled(true)
            else
                self.autoRepairGuildCb:SetEnabled(false)
            end
        end
    end
    if self.autoRepairGuildCb and Omni.Data then
        self.autoRepairGuildCb:SetChecked(Omni.Data:Get("autoRepairGuild") == true)
    end
    if self.autoTidyCb and Omni.Data then
        self.autoTidyCb:SetChecked(Omni.Data:Get("autoTidyOnClose") == true)
    end
    if self.resortButtonCb and Omni.Data then
        self.resortButtonCb:SetChecked(Omni.Data:Get("showResortButton") == true)
    end
    if self.detailedCategoriesCb then
        self.detailedCategoriesCb:SetChecked(
            OmniInventoryDB and OmniInventoryDB.global
                and OmniInventoryDB.global.detailedCategories == true)
    end

    -- Theme + view + sort + target labels
    self:RefreshThemeLabel()
    self:RefreshViewLabel()
    self:RefreshSortLabel()
    self:RefreshTargetLabel()

    -- Make the visible panel the correct height
    local panel = self.tabPanels and self.tabPanels[activeTab]
    if panel and panel._contentHeight then
        self.content:SetHeight(panel._contentHeight)
    end

    -- Color swatches (retained for forward compat)
    if self.colorSwatches then
        for _, swatch in ipairs(self.colorSwatches) do
            local c = swatch.__color
            if c and swatch.tex then
                swatch.tex:SetVertexColor(c.r or 1, c.g or 1, c.b or 1, c.a or 1)
            end
        end
    end

    self._syncingScaleControls = false
end

function Settings:RefreshThemeLabel()
    if not self.themeBtn then return end
    local theme = "Rounded"
    if Omni.Features and Omni.Features.GetTheme then
        theme = Omni.Features:GetTheme() == "square" and "Square" or "Rounded"
    end
    self.themeBtn.text:SetText("Theme: " .. theme)
end

function Settings:RefreshViewLabel()
    if not self.viewBtn then return end
    local view = "Grid"
    if Omni.Frame and Omni.Frame.GetView then
        view = Omni.Frame:GetView()
    elseif OmniInventoryDB and OmniInventoryDB.char and OmniInventoryDB.char.settings then
        view = OmniInventoryDB.char.settings.viewMode or "flow"
    end
    -- Capitalize first letter
    view = view:gsub("^%l", string.upper)
    self.viewBtn.text:SetText("View: " .. view)
end

function Settings:RefreshSortLabel()
    if not self.sortBtn then return end
    local sort = "Category"
    if Omni.Sorter and Omni.Sorter.GetDefaultMode then
        sort = Omni.Sorter:GetDefaultMode()
    end
    -- Capitalize first letter
    sort = sort:gsub("^%l", string.upper)
    self.sortBtn.text:SetText("Sort: " .. sort)
end

function Settings:BuildRules(panel)
    panel.editingCategoryName = nil  -- nil: list view, "": new category/rule, "name": edit rule

    local container = CreateFrame("Frame", nil, panel)
    container:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    container:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    panel.container = container

    local function RefreshPanel()
        -- Clean up existing widgets in container
        local children = { container:GetChildren() }
        for _, child in ipairs(children) do
            child:Hide()
            child:SetParent(nil)
        end
        local regions = { container:GetRegions() }
        for _, region in ipairs(regions) do
            region:Hide()
        end

        local y = -15
        local header = OpsTheme.CreateSectionHeader(container, "[+]  Custom Rules", SECTION_COLORS.colors)
        header:SetPoint("TOPLEFT", container, "TOPLEFT", COL_LEFT, y)
        y = y - HEADER_GAP

        if panel.editingCategoryName then
            -- =============================================================================
            -- EDITOR MODE
            -- =============================================================================
            local isNew = (panel.editingCategoryName == "")
            local catName = panel.editingCategoryName
            local catDef = not isNew and Omni.Categories and Omni.Categories:Get(catName)

            local ruleName = isNew and "" or catName
            local rulePrio = catDef and tostring(catDef.sequence or 50) or "50"
            local ruleFormula = catDef and tostring(catDef.rule or "") or ""

            -- Title for Editor
            local subHeader = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            subHeader:SetPoint("TOPLEFT", container, "TOPLEFT", COL_LEFT, y)
            subHeader:SetText(isNew and "CREATE NEW RULE" or "EDIT RULE: " .. catName)
            subHeader:SetTextColor(0.9, 0.9, 0.9)
            y = y - 16

            -- Input Helper Function
            local function CreateEditBox(width, height, defaultVal, isMultiLine)
                local f = CreateFrame("Frame", nil, container)
                f:SetSize(width, height)
                OpsTheme:ApplyControlBackdrop(f)
                f:SetBackdropColor(0.08, 0.08, 0.08, 1)

                local eb = CreateFrame("EditBox", nil, f)
                eb:SetSize(width - 12, height - 6)
                eb:SetPoint("TOPLEFT", 6, -3)
                eb:SetAutoFocus(false)
                eb:SetFontObject(ChatFontNormal)
                eb:SetTextColor(1, 1, 1, 1)
                eb:SetTextInsets(0, 0, 0, 0)
                eb:SetText(defaultVal)
                if isMultiLine then
                    eb:SetMultiLine(true)
                end
                eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

                f.editBox = eb
                return f
            end

            -- Rule Name Label
            local nameLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameLabel:SetPoint("TOPLEFT", container, "TOPLEFT", COL_LEFT, y)
            nameLabel:SetText("Rule / Category Name:")
            nameLabel:SetTextColor(0.7, 0.7, 0.7)
            y = y - 14

            -- Rule Name Input
            local nameFrame = CreateEditBox(200, 22, ruleName)
            nameFrame:SetPoint("TOPLEFT", container, "TOPLEFT", COL_LEFT, y)
            y = y - 30
            if not isNew then
                nameFrame.editBox:EnableMouse(false)
                nameFrame.editBox:SetTextColor(0.5, 0.5, 0.5)
            end

            -- Priority Label
            local prioLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            prioLabel:SetPoint("TOPLEFT", container, "TOPLEFT", COL_LEFT, y)
            prioLabel:SetText("Priority / Order (lower numbers run first):")
            prioLabel:SetTextColor(0.7, 0.7, 0.7)
            y = y - 14

            -- Priority Input
            local prioFrame = CreateEditBox(60, 22, rulePrio)
            prioFrame:SetPoint("TOPLEFT", container, "TOPLEFT", COL_LEFT, y)
            y = y - 30

            -- Formula Label
            local formulaLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            formulaLabel:SetPoint("TOPLEFT", container, "TOPLEFT", COL_LEFT, y)
            formulaLabel:SetText("Rule Formula:")
            formulaLabel:SetTextColor(0.7, 0.7, 0.7)
            y = y - 14

            -- Formula Input
            local formulaFrame = CreateEditBox(320, 60, ruleFormula, true)
            formulaFrame:SetPoint("TOPLEFT", container, "TOPLEFT", COL_LEFT, y)
            y = y - 70

            -- Status / Error text
            local errorLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            errorLabel:SetPoint("TOPLEFT", container, "TOPLEFT", COL_LEFT, y)
            errorLabel:SetWidth(320)
            errorLabel:SetJustifyH("LEFT")
            errorLabel:SetText("")
            errorLabel:SetTextColor(1, 0.2, 0.2)
            y = y - 30

            -- Buttons
            local saveBtn = OpsTheme.CreateButton(container, "Save", 80, function()
                local nameText = nameFrame.editBox:GetText() or ""
                nameText = nameText:match("^%s*(.-)%s*$") -- simple trim
                local prioNum = tonumber(prioFrame.editBox:GetText()) or 50
                local formulaText = formulaFrame.editBox:GetText() or ""

                if nameText == "" then
                    errorLabel:SetText("Error: Name is required.")
                    return
                end

                -- Check syntax by compiling the rule first
                local _, compileErr = Omni.Rules:Compile(formulaText)
                if compileErr then
                    errorLabel:SetText("Formula Error: " .. compileErr)
                    return
                end

                if Omni.Categories then
                    -- Save category
                    local success, err = Omni.Categories:Create(nameText, {
                        sequence = prioNum,
                        rule = formulaText,
                    })
                    if not success then
                        errorLabel:SetText("Error: " .. (err or "failed to create"))
                        return
                    end
                end

                -- Close editor
                panel.editingCategoryName = nil
                RefreshPanel()
                RefreshAllInventory()
            end)
            saveBtn:SetPoint("TOPLEFT", container, "TOPLEFT", COL_LEFT, y)
            saveBtn:SetScript("OnEnter", function(self)
                self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_HOVER))
                self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_HOVER))
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Save Rule", 1, 0.82, 0)
                GameTooltip:AddLine("Compile and save this custom rule.", 0.75, 0.75, 0.75, true)
                GameTooltip:Show()
            end)
            saveBtn:SetScript("OnLeave", function(self)
                self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL))
                self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER))
                GameTooltip:Hide()
            end)

            local cancelBtn = OpsTheme.CreateButton(container, "Cancel", 80, function()
                panel.editingCategoryName = nil
                RefreshPanel()
            end)
            cancelBtn:SetPoint("TOPLEFT", saveBtn, "TOPRIGHT", 10, 0)
            cancelBtn:SetScript("OnEnter", function(self)
                self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_HOVER))
                self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_HOVER))
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Cancel", 1, 0.82, 0)
                GameTooltip:AddLine("Discard changes and return to the list.", 0.75, 0.75, 0.75, true)
                GameTooltip:Show()
            end)
            cancelBtn:SetScript("OnLeave", function(self)
                self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL))
                self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER))
                GameTooltip:Hide()
            end)
            y = y - 30

        else
            -- =============================================================================
            -- LIST MODE
            -- =============================================================================
            local addBtn = OpsTheme.CreateButton(container, "+ Add New Rule", 120, function()
                panel.editingCategoryName = ""
                RefreshPanel()
            end)
            addBtn:SetPoint("TOPLEFT", container, "TOPLEFT", COL_LEFT, y)
            addBtn:SetScript("OnEnter", function(self)
                self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_HOVER))
                self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_HOVER))
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Add New Rule", 1, 0.82, 0)
                GameTooltip:AddLine("Create a new custom sorting rule.", 0.75, 0.75, 0.75, true)
                GameTooltip:Show()
            end)
            addBtn:SetScript("OnLeave", function(self)
                self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL))
                self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER))
                GameTooltip:Hide()
            end)
            y = y - 30

            local cats = Omni.Categories and Omni.Categories:GetAll() or {}
            if #cats == 0 then
                local noRulesText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                noRulesText:SetPoint("TOPLEFT", container, "TOPLEFT", COL_LEFT, y)
                noRulesText:SetText("No custom rules created yet.")
                noRulesText:SetTextColor(0.5, 0.5, 0.5)
                y = y - 20
            else
                for _, cat in ipairs(cats) do
                    local rowFrame = CreateFrame("Frame", nil, container)
                    rowFrame:SetSize(CONTENT_W - 24, 38)
                    rowFrame:SetPoint("TOPLEFT", container, "TOPLEFT", COL_LEFT, y)
                    OpsTheme:ApplyControlBackdrop(rowFrame)
                    rowFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.3)

                    -- Name & Prio
                    local nameText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    nameText:SetPoint("TOPLEFT", 6, -4)
                    nameText:SetText(cat.name)
                    nameText:SetTextColor(1, 0.82, 0)

                    local prioText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    prioText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
                    prioText:SetText("Prio: " .. (cat.sequence or 50))
                    prioText:SetTextColor(0.6, 0.6, 0.6)

                    -- Formula (truncated)
                    local formulaText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    formulaText:SetPoint("LEFT", 120, 0)
                    formulaText:SetWidth(120)
                    formulaText:SetJustifyH("LEFT")
                    local rawFormula = cat.rule or ""
                    if #rawFormula > 25 then
                        rawFormula = string.sub(rawFormula, 1, 22) .. "..."
                    end
                    formulaText:SetText(rawFormula)
                    formulaText:SetTextColor(0.8, 0.8, 0.8)

                    -- Action buttons
                    local editBtn = OpsTheme.CreateButton(rowFrame, "Edit", 40, function()
                        panel.editingCategoryName = cat.name
                        RefreshPanel()
                    end)
                    editBtn:SetPoint("RIGHT", -50, 0)
                    editBtn:SetHeight(18)
                    editBtn:SetScript("OnEnter", function(self)
                        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_HOVER))
                        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_HOVER))
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText("Edit Rule", 1, 0.82, 0)
                        GameTooltip:AddLine("Edit this custom rule's priority and formula.", 0.75, 0.75, 0.75, true)
                        GameTooltip:Show()
                    end)
                    editBtn:SetScript("OnLeave", function(self)
                        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL))
                        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER))
                        GameTooltip:Hide()
                    end)

                    local deleteBtn = OpsTheme.CreateButton(rowFrame, "Del", 36, function()
                        if Omni.Categories then
                            Omni.Categories:Delete(cat.name)
                        end
                        RefreshPanel()
                        RefreshAllInventory()
                    end)
                    deleteBtn:SetPoint("RIGHT", -8, 0)
                    deleteBtn:SetHeight(18)
                    deleteBtn:SetScript("OnEnter", function(self)
                        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL_HOVER))
                        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER_HOVER))
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText("Delete Rule", 1, 0.82, 0)
                        GameTooltip:AddLine("Delete this custom rule.", 0.75, 0.75, 0.75, true)
                        GameTooltip:Show()
                    end)
                    deleteBtn:SetScript("OnLeave", function(self)
                        self:SetBackdropColor(unpack(OpsTheme.PAL.BG_CONTROL))
                        self:SetBackdropBorderColor(unpack(OpsTheme.PAL.BORDER))
                        GameTooltip:Hide()
                    end)
                    deleteBtn.text:SetTextColor(1, 0.3, 0.3)

                    y = y - 42
                end
            end
        end

        panel._contentHeight = math.abs(y) + 40
        if Settings.content then
            Settings.content:SetHeight(panel._contentHeight)
        end
    end

    panel.Refresh = RefreshPanel
    RefreshPanel()
end

function Settings:Init()
    Settings.activeConfigTarget = "bag"
end
