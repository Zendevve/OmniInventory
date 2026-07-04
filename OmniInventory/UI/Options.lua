-- =============================================================================
-- OmniInventory Configuration Panel
-- =============================================================================
-- Purpose: Standalone options frame called via /oi config
-- Style: Flat dark motif matching bag interface (via OpsTheme)
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
    view   = { 0.85, 0.90, 1.00 },
    sort   = { 0.85, 0.90, 1.00 },
    misc   = { 0.78, 0.88, 1.00 },
    colors = { 1.00, 0.60, 0.20 },
    footer = { 0.40, 1.00, 0.55 },
    addon  = { 0.45, 0.80, 1.00 },
    feat   = { 0.85, 0.70, 1.00 },
}

local FOOTER_BUTTON_OPTIONS = {
    { key = "resetInstances", label = "Reset Instances" },
    { key = "hearthstone",    label = "Hearthstone" },
    { key = "openables",      label = "Clam Opener" },
    { key = "disenchant",     label = "Disenchant" },
    { key = "picklock",       label = "Pick Lock" },
}

local ADDON_BUTTON_OPTIONS = {
    { key = "atlasLoot",   label = "AtlasLoot"   },
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

local function GetAddonButtonsDB()
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    OmniInventoryDB.global.addonButtons = OmniInventoryDB.global.addonButtons or {}
    return OmniInventoryDB.global.addonButtons
end

local function IsAddonButtonEnabled(key)
    local db = GetAddonButtonsDB()
    if db[key] == nil then db[key] = true end
    return db[key] == true
end

-- =============================================================================
-- Creation
-- =============================================================================

function Settings:CreateOptionsFrame()
    if optionsFrame then return optionsFrame end

    optionsFrame = CreateFrame("Frame", "OmniOptionsFrame", UIParent)
    optionsFrame:SetSize(320, 520)
    optionsFrame:SetPoint("CENTER")
    optionsFrame:SetFrameStrata("DIALOG")
    optionsFrame:EnableMouse(true)
    optionsFrame:SetMovable(true)
    optionsFrame:SetClampedToScreen(true)
    optionsFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    optionsFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    optionsFrame:SetScript("OnEvent", function()
        if optionsFrame:IsShown() then
            self:UpdateValues()
        end
    end)

    -- Backdrop: flat dark motif matching bag interface
    OpsTheme:ApplyFrameBackdrop(optionsFrame)

    -- Draggable header area (top 24px strip)
    local dragStrip = CreateFrame("Frame", nil, optionsFrame)
    dragStrip:SetHeight(24)
    dragStrip:SetPoint("TOPLEFT", OpsTheme.PAL.PADDING, -OpsTheme.PAL.PADDING)
    dragStrip:SetPoint("TOPRIGHT", -OpsTheme.PAL.PADDING, -OpsTheme.PAL.PADDING)
    dragStrip.bg = dragStrip:CreateTexture(nil, "BACKGROUND")
    dragStrip.bg:SetAllPoints()
    dragStrip.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    dragStrip.bg:SetVertexColor(unpack(OpsTheme.PAL.BG_HEADER))

    optionsFrame:EnableKeyboard(true)

    -- Title text
    local titleText = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", dragStrip, "TOPLEFT", 8, -5)
    titleText:SetText("|cFF00FF00Omni|rInventory Settings")

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

    -- Close button (flat style matching bag header)
    local closeBtn = OpsTheme.CreateButton(optionsFrame, "X", 20, function()
        optionsFrame:Hide()
    end)
    closeBtn:SetHeight(20)
    closeBtn:SetPoint("TOPRIGHT", -OpsTheme.PAL.PADDING, -OpsTheme.PAL.PADDING)

    -- Drag
    dragStrip:EnableMouse(true)
    dragStrip:RegisterForDrag("LeftButton")
    dragStrip:SetScript("OnDragStart", function() optionsFrame:StartMoving() end)
    dragStrip:SetScript("OnDragStop", function() optionsFrame:StopMovingOrSizing() end)

    -- Scrollable content
    local scrollChildW = 280
    local scrollFrame = OpsTheme.CreateScrollFrame(optionsFrame, 290, 0)
    scrollFrame:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 10, -32)
    scrollFrame:SetPoint("BOTTOMRIGHT", optionsFrame, "BOTTOMRIGHT", -18, 10)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(scrollChildW, 1)
    scrollFrame:SetScrollChild(scrollChild)

    self.scrollFrame = scrollFrame
    self.content = scrollChild
    self:CreateControls(scrollChild)

    local requiredHeight = self._contentHeight or 700
    scrollChild:SetHeight(requiredHeight)

    -- Keyboard: ESC closes, Tab cycles focus
    optionsFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
        end
    end)

    optionsFrame:Hide()
    return optionsFrame
end

function Settings:CreateControls(parent)
    local yOffset = -15
    local SPACING = 54
    local SECTION_GAP = 18
    local HEADER_GAP = 22
    self.colorSwatches = {}
    self._syncingScaleControls = false

    -- Frame Selector Tabs
    local activeTarget = Settings.activeConfigTarget or "bag"

    local bagTab = OpsTheme.CreateTabButton(parent, "Bag Frame", activeTarget == "bag", function()
        Settings.activeConfigTarget = "bag"
        self:RefreshTabs()
        Settings:UpdateValues()
    end)
    bagTab:SetPoint("TOPLEFT", 25, yOffset)

    local bankTab = OpsTheme.CreateTabButton(parent, "Bank Frame", activeTarget == "bank", function()
        Settings.activeConfigTarget = "bank"
        self:RefreshTabs()
        Settings:UpdateValues()
    end)
    bankTab:SetPoint("TOPRIGHT", -25, yOffset)

    self.configTabBag = bagTab
    self.configTabBank = bankTab

    yOffset = yOffset - 35

    -- 1. Frame Scale Slider
    local scaleSlider = OpsTheme.CreateSlider(parent, "Frame Scale", 0.5, 2.0, 0.1, FormatScalePercent, function(value)
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
    end)
    scaleSlider:SetPoint("TOP", 0, yOffset)
    self.scaleSlider = scaleSlider

    yOffset = yOffset - SPACING

    -- 2. Item Scale Slider
    local itemScaleSlider = OpsTheme.CreateSlider(parent, "Item Scale", 0.5, 2.0, 0.1, FormatScalePercent, function(value)
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
    end)
    itemScaleSlider:SetPoint("TOP", 0, yOffset)
    self.itemScaleSlider = itemScaleSlider

    yOffset = yOffset - SPACING

    -- 3. Item Gap Slider
    local itemGapSlider = OpsTheme.CreateSlider(parent, "Item Gap", 0, 20, 1, FormatGapPixels, function(value)
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
    end)
    itemGapSlider:SetPoint("TOP", 0, yOffset)
    self.itemGapSlider = itemGapSlider

    yOffset = yOffset - SPACING - 20

    -- 4. View Mode
    local viewHeader = OpsTheme.CreateSectionHeader(parent, "View Mode", SECTION_COLORS.view)
    viewHeader:SetPoint("TOP", 0, yOffset)
    yOffset = yOffset - 20

    local viewBtn = OpsTheme.CreateButton(parent, "Cycle View", 140, function()
        if Omni.Frame then Omni.Frame:CycleView() end
    end)
    viewBtn:SetPoint("TOP", 0, yOffset)
    self.viewBtn = viewBtn

    yOffset = yOffset - SPACING

    -- 5. Sort Mode
    local sortHeader = OpsTheme.CreateSectionHeader(parent, "Sort Mode (Default)", SECTION_COLORS.sort)
    sortHeader:SetPoint("TOP", 0, yOffset)
    yOffset = yOffset - 20

    local sortBtn = OpsTheme.CreateButton(parent, "Cycle Sort", 140, function()
        if Omni.Frame then Omni.Frame:CycleSort() end
    end)
    sortBtn:SetPoint("TOP", 0, yOffset)
    self.sortBtn = sortBtn

    yOffset = yOffset - SPACING - 20

    yOffset = yOffset - SECTION_GAP
    local miscHeader = OpsTheme.CreateSectionHeader(parent, "Misc Options", SECTION_COLORS.misc)
    miscHeader:SetPoint("TOP", 0, yOffset)
    yOffset = yOffset - HEADER_GAP

    -- Checkboxes: 2 columns, each row 22px apart
    local COL_LEFT = 14
    local COL_RIGHT = 160
    local ROW_H = 22

    local function MakeCb(col, row, label, tipTitle, tipSub, defaultChecked, onClick)
        local cb = OpsTheme.CreateCheckButton(parent, label, tipTitle, tipSub, defaultChecked, onClick)
        local xOff = (col == 0) and COL_LEFT or COL_RIGHT
        cb:SetPoint("TOPLEFT", xOff, yOffset - (row * ROW_H))
        return cb
    end

    -- Row 0
    local row = 0
    self.highlightNewItemsCb = MakeCb(0, row, "New items",
        "Highlight new items",
        "Visually emphasize items that count as new in your bags.",
        false,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("highlightNewItems", checked)
                RefreshAllInventory()
            end
        end)

    self.footerMoneyEmphasisCb = MakeCb(1, row, "Bold footer",
        "Bold footer",
        "Larger outlined gold and bag count. Slot text shifts from light blue to red as bags fill.",
        false,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("footerMoneyEmphasis", checked)
            end
            if Omni.Frame and Omni.Frame.RefreshFooterMoneyStyle then
                Omni.Frame:RefreshFooterMoneyStyle()
            end
            RefreshAllInventory()
        end)

    -- Row 1
    row = 1
    self.enableBoundCategoriesCb = MakeCb(0, row, "Bound lanes",
        "Categorize bound items",
        "Separate Soulbound (BoP) equipment and Account Bound (BoA/Heirlooms) into their own lanes.",
        true,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("enableBoundCategories", checked)
                RefreshAllInventory()
            end
        end)

    self.enableUnusableOverlayCb = MakeCb(1, row, "Red overlays",
        "Unusable red overlay",
        "Tints unusable gear (level/class locks) and unlearned recipes red.",
        true,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("enableUnusableOverlay", checked)
                RefreshAllInventory()
            end
        end)

    -- Row 2
    row = 2
    self.autoSellJunkCb = MakeCb(0, row, "Auto-sell junk",
        "Auto-sell junk",
        "Automatically sells all grey quality items in your bags when visiting a merchant NPC.",
        true,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("autoSellJunk", checked)
            end
        end)

    self.autoRepairCb = MakeCb(1, row, "Auto-repair",
        "Auto-repair gear",
        "Automatically repairs all equipped and inventory gear when visiting a repair merchant.",
        false,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("autoRepair", checked)
                if self._guildFundsCb then
                    if checked then
                        self._guildFundsCb:SetEnabled(true)
                    else
                        self._guildFundsCb:SetEnabled(false)
                    end
                end
            end
        end)

    -- Row 3
    row = 3
    self.autoRepairGuildCb = MakeCb(1, row, "Use Guild funds",
        "Use Guild Funds",
        "Attempts to use guild bank funds for auto-repairs before using your own gold.",
        false,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("autoRepairGuild", checked)
            end
        end)

    self.showItemLevelCb = MakeCb(0, row, "Item levels",
        "Show Item Levels",
        "Displays the item level (iLevel) directly on weapons and armor in your bags and bank.",
        true,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("showItemLevel", checked)
                RefreshAllInventory()
            end
        end)

    -- Link auto-repair → guild funds
    if self.autoRepairCb and self.autoRepairGuildCb then
        self.autoRepairCb._guildFundsCb = self.autoRepairGuildCb
    end

    -- Row 4
    row = 4
    self.vendorDoubleRightClickCb = MakeCb(0, row, "Double-click sell protection",
        "Vendor Sell Protection",
        "Requires a double-right-click to sell valuable items (Soulbound gear, active quest items, rare/epic loot) at vendors.",
        true,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("vendorDoubleRightClick", checked)
            end
        end)

    -- Row 5
    row = 5
    self.collapseEmptySlotsCb = MakeCb(0, row, "Collapse empty slots",
        "Collapse Empty Slots",
        "Collapses all empty slots in Grid and Flow views into a single slot button per bag type, displaying a count of the total empty spaces.",
        false,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("collapseEmptySlots", checked)
                RefreshAllInventory()
            end
        end)

    yOffset = yOffset - (ROW_H * 6) - SPACING - 4

    -- Tooltip placement
    local tipPlacementHeader = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tipPlacementHeader:SetPoint("TOP", parent, "TOP", 0, yOffset)
    tipPlacementHeader:SetWidth(260)
    tipPlacementHeader:SetJustifyH("CENTER")
    tipPlacementHeader:SetText("Item tooltips (bags, bank, guild bank, offline)")

    local tipPlacementBtn = OpsTheme.CreateButton(parent, "Right of slot", 260, function()
        CycleTooltipPlacementSetting()
        Settings:RefreshTooltipPlacementControls()
    end)
    tipPlacementBtn:SetPoint("TOP", parent, "TOP", 0, yOffset - 18)
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

    yOffset = yOffset - TOOLTIP_PLACEMENT_TO_FIXED_SLIDER_GAP

    local tipFixedXSlider = OpsTheme.CreateSlider(parent, "Fixed X (horizontal inset)", 0, TOOLTIP_FIXED_X_MAX, 1, nil, function(value)
        if Settings._syncingTooltipFixedSliders then return end
        if OmniInventoryDB and OmniInventoryDB.global then
            OmniInventoryDB.global.itemTooltipFixed = OmniInventoryDB.global.itemTooltipFixed or {}
            OmniInventoryDB.global.itemTooltipFixed.x = value
        end
        if Omni.ItemButton and Omni.ItemButton.FinalizeOmniItemTooltipLayout then
            Omni.ItemButton.FinalizeOmniItemTooltipLayout()
        end
    end)
    tipFixedXSlider:SetPoint("TOP", parent, "TOP", 0, yOffset)
    self.tooltipFixedXSlider = tipFixedXSlider

    yOffset = yOffset - 36

    local tipFixedYSlider = OpsTheme.CreateSlider(parent, "Fixed Y (vertical inset)", 0, TOOLTIP_FIXED_Y_MAX, 1, nil, function(value)
        if Settings._syncingTooltipFixedSliders then return end
        if OmniInventoryDB and OmniInventoryDB.global then
            OmniInventoryDB.global.itemTooltipFixed = OmniInventoryDB.global.itemTooltipFixed or {}
            OmniInventoryDB.global.itemTooltipFixed.y = value
        end
        if Omni.ItemButton and Omni.ItemButton.FinalizeOmniItemTooltipLayout then
            Omni.ItemButton.FinalizeOmniItemTooltipLayout()
        end
    end)
    tipFixedYSlider:SetPoint("TOP", parent, "TOP", 0, yOffset)
    self.tooltipFixedYSlider = tipFixedYSlider

    yOffset = yOffset - 36

    self:RefreshTooltipPlacementControls()

    -- Reset Button
    local resetBtn = OpsTheme.CreateButton(parent, "Reset Position & Scale", 200, function()
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
    resetBtn:SetPoint("TOP", 0, yOffset)

    yOffset = yOffset - SPACING - SECTION_GAP

    -- Footer Buttons
    local footerHeader = OpsTheme.CreateSectionHeader(parent, "Footer Buttons", SECTION_COLORS.footer)
    footerHeader:SetPoint("TOP", 0, yOffset)
    yOffset = yOffset - HEADER_GAP

    self.footerButtonCbs = self.footerButtonCbs or {}
    for i, def in ipairs(FOOTER_BUTTON_OPTIONS) do
        local column = (i - 1) % 2
        local rowIdx = math.floor((i - 1) / 2)
        local xOff = (column == 0) and COL_LEFT or COL_RIGHT
        local rowY = yOffset - (rowIdx * ROW_H)

        local cb = OpsTheme.CreateCheckButton(parent, def.label, nil, nil, IsFooterButtonEnabled(def.key), function(self, checked)
            local db = GetFooterButtonsDB()
            db[def.key] = checked
            if Omni.Frame and Omni.Frame.UpdateFooterCustomButtons then
                Omni.Frame:UpdateFooterCustomButtons()
            end
        end)
        cb:SetPoint("TOPLEFT", xOff, rowY)
        self.footerButtonCbs[def.key] = cb
    end
    local rowCount = math.ceil(#FOOTER_BUTTON_OPTIONS / 2)
    yOffset = yOffset - (rowCount * ROW_H)

    yOffset = yOffset - SECTION_GAP

    -- Addon Buttons
    local addonHeader = OpsTheme.CreateSectionHeader(parent, "Addon Buttons", SECTION_COLORS.addon)
    addonHeader:SetPoint("TOP", 0, yOffset)
    yOffset = yOffset - HEADER_GAP

    self.addonButtonCbs = self.addonButtonCbs or {}
    for i, def in ipairs(ADDON_BUTTON_OPTIONS) do
        local column = (i - 1) % 2
        local rowIdx = math.floor((i - 1) / 2)
        local xOff = (column == 0) and COL_LEFT or COL_RIGHT
        local rowY = yOffset - (rowIdx * ROW_H)

        local cb = OpsTheme.CreateCheckButton(parent, def.label, nil, nil, IsAddonButtonEnabled(def.key), function(self, checked)
            local db = GetAddonButtonsDB()
            db[def.key] = checked
            if Omni.Frame and Omni.Frame.UpdateFooterCustomButtons then
                Omni.Frame:UpdateFooterCustomButtons()
            end
        end)
        cb:SetPoint("TOPLEFT", xOff, rowY)
        self.addonButtonCbs[def.key] = cb
    end
    local addonRowCount = math.ceil(#ADDON_BUTTON_OPTIONS / 2)
    yOffset = yOffset - (addonRowCount * ROW_H)

    yOffset = yOffset - SECTION_GAP

    -- Auto-Display & Features
    local featHeader = OpsTheme.CreateSectionHeader(parent, "Auto-Display & Features", SECTION_COLORS.feat)
    featHeader:SetPoint("TOP", 0, yOffset)
    yOffset = yOffset - HEADER_GAP

    -- Row 0: Auto-display bank/vendor
    row = 0
    self.autoDisplayBankCb = MakeCb(0, row, "Auto-open at Bank", nil, nil, false, function(self, checked)
        if Omni.Data then
            local ad = Omni.Data:Get("autoDisplay") or {}
            ad.bank = checked
            Omni.Data:Set("autoDisplay", ad)
        end
    end)
    self.autoDisplayVendorCb = MakeCb(1, row, "Auto-open at Vendor", nil, nil, false, function(self, checked)
        if Omni.Data then
            local ad = Omni.Data:Get("autoDisplay") or {}
            ad.vendor = checked
            Omni.Data:Set("autoDisplay", ad)
        end
    end)

    -- Row 1: Mail / AH
    row = 1
    self.autoDisplayMailCb = MakeCb(0, row, "Auto-open at Mail", nil, nil, false, function(self, checked)
        if Omni.Data then
            local ad = Omni.Data:Get("autoDisplay") or {}
            ad.mail = checked
            Omni.Data:Set("autoDisplay", ad)
        end
    end)
    self.autoDisplayAhCb = MakeCb(1, row, "Auto-open at AH", nil, nil, false, function(self, checked)
        if Omni.Data then
            local ad = Omni.Data:Get("autoDisplay") or {}
            ad.ah = checked
            Omni.Data:Set("autoDisplay", ad)
        end
    end)

    -- Row 2: Trade / Craft
    row = 2
    self.autoDisplayTradeCb = MakeCb(0, row, "Auto-open at Trade", nil, nil, false, function(self, checked)
        if Omni.Data then
            local ad = Omni.Data:Get("autoDisplay") or {}
            ad.trade = checked
            Omni.Data:Set("autoDisplay", ad)
        end
    end)
    self.autoDisplayCraftCb = MakeCb(1, row, "Auto-open at Craft", nil, nil, false, function(self, checked)
        if Omni.Data then
            local ad = Omni.Data:Get("autoDisplay") or {}
            ad.craft = checked
            Omni.Data:Set("autoDisplay", ad)
        end
    end)

    -- Row 3: Cache warmer / Auto-loot
    row = 3
    self.cacheWarmerCb = MakeCb(0, row, "Cache warmer",
        "Cache Warmer",
        "Pre-loads GetItemInfo for known item IDs on login to avoid tooltip delays.",
        true,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("cacheWarmer", checked)
                if checked and Omni.Features and Omni.Features.WarmCache then
                    Omni.Features:WarmCache()
                end
            end
        end)
    self.autoLootCb = MakeCb(1, row, "Auto-loot",
        "Auto-Loot",
        "Automatically loots all items when a loot frame opens.",
        false,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("autoLoot", checked)
                if Omni.Features and Omni.Features.InitAutoLoot then
                    Omni.Features:InitAutoLoot()
                end
            end
        end)

    -- Row 4: Money tracker / Bound indicator
    row = 4
    self.moneyTrackerCb = MakeCb(0, row, "Money tracker",
        "Money Tracker",
        "Records gold history per character over time for trend display.",
        false,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("moneyTracker", checked)
            end
        end)
    self.boundIndicatorCb = MakeCb(1, row, "Bound indicator",
        "Bound Item Indicator",
        "Shows a small chain icon on soulbound items in the bag.",
        false,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("showBoundIndicator", checked)
                RefreshAllInventory()
            end
        end)

    -- Row 5: Bag type tags / Auto-tidy
    row = 5
    self.bagTypeTagsCb = MakeCb(0, row, "Bag type tags",
        "Bag Type Tags",
        "Shows family tag text (Ammo, Herb, Mining, etc.) on specialty bag tooltips.",
        false,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("showBagTypeTags", checked)
            end
        end)
    self.autoTidyCb = MakeCb(1, row, "Auto-tidy on close",
        "Auto-Tidy on Close",
        "Compacts bag layout and sorts when the bag window is closed (AdiBags TidyBags).",
        false,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("autoTidyOnClose", checked)
            end
        end)

    -- Row 6: Resort button / Theme
    row = 6
    self.resortButtonCb = MakeCb(0, row, "Resort button",
        "Resort Button",
        "Shows a resort button when a dry-run detects the layout could be reorganized.",
        false,
        function(self, checked)
            if Omni.Data then
                Omni.Data:Set("showResortButton", checked)
                if Omni.Frame and Omni.Frame.UpdateResortButtonVisibility then
                    Omni.Frame:UpdateResortButtonVisibility()
                end
            end
        end)

    local themeBtn = OpsTheme.CreateButton(parent, "Theme: Rounded", 120, function()
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
    themeBtn:SetPoint("TOPLEFT", COL_RIGHT, yOffset - (row * ROW_H))
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

    yOffset = yOffset - ((row + 1) * ROW_H) - SPACING - SECTION_GAP

    self._contentHeight = math.abs(yOffset) + 40
end

-- =============================================================================
-- Actions
-- =============================================================================

function Settings:RefreshTabs()
    local active = self.activeConfigTarget or "bag"
    if self.configTabBag then
        self.configTabBag._isActive = (active == "bag")
        self.configTabBag:_ApplyState(active == "bag")
    end
    if self.configTabBank then
        self.configTabBank._isActive = (active == "bank")
        self.configTabBank:_ApplyState(active == "bank")
    end
end

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
    if self.tooltipPlacementBtn then
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

    if self.highlightNewItemsCb and Omni.Data then
        self.highlightNewItemsCb:SetChecked(Omni.Data:Get("highlightNewItems") == true)
    end
    if self.footerMoneyEmphasisCb and Omni.Data then
        self.footerMoneyEmphasisCb:SetChecked(Omni.Data:Get("footerMoneyEmphasis") == true)
    end
    if self.enableBoundCategoriesCb and Omni.Data then
        self.enableBoundCategoriesCb:SetChecked(Omni.Data:Get("enableBoundCategories") ~= false)
    end
    if self.enableUnusableOverlayCb and Omni.Data then
        self.enableUnusableOverlayCb:SetChecked(Omni.Data:Get("enableUnusableOverlay") ~= false)
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
    if self.showItemLevelCb and Omni.Data then
        self.showItemLevelCb:SetChecked(Omni.Data:Get("showItemLevel") ~= false)
    end
    if self.vendorDoubleRightClickCb and Omni.Data then
        self.vendorDoubleRightClickCb:SetChecked(Omni.Data:Get("vendorDoubleRightClick") ~= false)
    end
    if self.collapseEmptySlotsCb and Omni.Data then
        self.collapseEmptySlotsCb:SetChecked(Omni.Data:Get("collapseEmptySlots") == true)
    end
    -- New Features checkboxes
    local ad = Omni.Data and Omni.Data:Get("autoDisplay") or {}
    if self.autoDisplayBankCb then self.autoDisplayBankCb:SetChecked(ad.bank == true) end
    if self.autoDisplayVendorCb then self.autoDisplayVendorCb:SetChecked(ad.vendor == true) end
    if self.autoDisplayMailCb then self.autoDisplayMailCb:SetChecked(ad.mail == true) end
    if self.autoDisplayAhCb then self.autoDisplayAhCb:SetChecked(ad.ah == true) end
    if self.autoDisplayTradeCb then self.autoDisplayTradeCb:SetChecked(ad.trade == true) end
    if self.autoDisplayCraftCb then self.autoDisplayCraftCb:SetChecked(ad.craft == true) end
    if self.cacheWarmerCb and Omni.Data then
        self.cacheWarmerCb:SetChecked(Omni.Data:Get("cacheWarmer") ~= false)
    end
    if self.autoLootCb and Omni.Data then
        self.autoLootCb:SetChecked(Omni.Data:Get("autoLoot") == true)
    end
    if self.moneyTrackerCb and Omni.Data then
        self.moneyTrackerCb:SetChecked(Omni.Data:Get("moneyTracker") == true)
    end
    if self.boundIndicatorCb and Omni.Data then
        self.boundIndicatorCb:SetChecked(Omni.Data:Get("showBoundIndicator") == true)
    end
    if self.bagTypeTagsCb and Omni.Data then
        self.bagTypeTagsCb:SetChecked(Omni.Data:Get("showBagTypeTags") == true)
    end
    if self.autoTidyCb and Omni.Data then
        self.autoTidyCb:SetChecked(Omni.Data:Get("autoTidyOnClose") == true)
    end
    if self.resortButtonCb and Omni.Data then
        self.resortButtonCb:SetChecked(Omni.Data:Get("showResortButton") == true)
    end
    self:RefreshThemeLabel()
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
    local target = Settings.activeConfigTarget or "bag"
    local scale, itemScale, itemGap

    if target == "bank" and Omni.BankFrame then
        scale = Omni.BankFrame:GetScale()
        itemScale = Omni.BankFrame:GetItemScale()
        itemGap = Omni.BankFrame:GetItemGap()
    else
        scale = Omni.Frame:GetScale()
        itemScale = Omni.Frame:GetItemScale()
        itemGap = Omni.Frame:GetItemGap()
    end

    if self.scaleSlider then
        self.scaleSlider:SetValue(scale)
    end
    if self.itemScaleSlider then
        self.itemScaleSlider:SetValue(itemScale)
    end
    if self.itemGapSlider then
        self.itemGapSlider:SetValue(itemGap)
    end
    local scaleControlsEnabled = not IsSettingEditLocked()
    if self.scaleSlider then self.scaleSlider:SetEnabled(scaleControlsEnabled) end
    if self.itemScaleSlider then self.itemScaleSlider:SetEnabled(scaleControlsEnabled) end
    if self.itemGapSlider then self.itemGapSlider:SetEnabled(scaleControlsEnabled) end

    if self.footerButtonCbs then
        for _, def in ipairs(FOOTER_BUTTON_OPTIONS) do
            local cb = self.footerButtonCbs[def.key]
            if cb then cb:SetChecked(IsFooterButtonEnabled(def.key)) end
        end
    end
    if self.addonButtonCbs then
        for _, def in ipairs(ADDON_BUTTON_OPTIONS) do
            local cb = self.addonButtonCbs[def.key]
            if cb then cb:SetChecked(IsAddonButtonEnabled(def.key)) end
        end
    end
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

function Settings:Init()
    Settings.activeConfigTarget = "bag"
end
