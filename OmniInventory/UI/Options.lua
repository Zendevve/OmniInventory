-- =============================================================================
-- OmniInventory Configuration Panel
-- =============================================================================
-- Purpose: Simple standalone options frame called via /oi config
-- Features: Scale slider, Sort mode, View mode, Reset position
-- =============================================================================

local addonName, Omni = ...

Omni.Settings = {}
local Settings = Omni.Settings
local optionsFrame = nil

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

-- ʕ •ᴥ•ʔ✿ Keep in sync with ItemButton.FinalizeOmniItemTooltipLayout clamp ✿ ʕ •ᴥ•ʔ
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



-- ʕ •ᴥ•ʔ✿ Section header palette — distinct tints so categories read at a glance ✿ ʕ •ᴥ•ʔ
local SECTION_COLORS = {
    view   = { 0.85, 0.90, 1.00 },
    sort   = { 0.85, 0.90, 1.00 },
    misc   = { 0.78, 0.88, 1.00 },
    colors = { 1.00, 0.60, 0.20 },
    footer = { 0.40, 1.00, 0.55 },
    addon  = { 0.45, 0.80, 1.00 },
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

    -- Backdrop
    optionsFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    -- Draggable header
    optionsFrame:RegisterForDrag("LeftButton")
    optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving)
    optionsFrame:SetScript("OnDragStop", optionsFrame.StopMovingOrSizing)

    -- Title
    local title = optionsFrame:CreateTexture(nil, "ARTWORK")
    title:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    title:SetSize(320, 64)
    title:SetPoint("TOP", 0, 12)

    local titleText = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", title, "TOP", 0, -14)
    titleText:SetText("OmniInventory Settings")

    local closeBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function()
        optionsFrame:Hide()
    end)

    -- ʕ •ᴥ•ʔ✿ Scrollable content viewport so we never outgrow the frame ✿ ʕ •ᴥ•ʔ
    local scrollFrame = CreateFrame("ScrollFrame", "OmniOptionsScroll", optionsFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -34, 16)

    -- Frame is 320 wide minus 16 (left inset) + 34 (right inset for scrollbar) = 270
    local SCROLL_CHILD_WIDTH = 270
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(SCROLL_CHILD_WIDTH, 1)
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local bar = _G[self:GetName() .. "ScrollBar"]
        if not bar then return end
        local step = 28
        bar:SetValue(bar:GetValue() - (delta * step))
    end)

    self.scrollFrame = scrollFrame
    self.content = scrollChild
    self:CreateControls(scrollChild)

    local requiredHeight = self._contentHeight or 700
    scrollChild:SetHeight(requiredHeight)

    optionsFrame:Hide()
    return optionsFrame
end

local function CreateSectionHeader(parent, text, y, color)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOP", 0, y)
    label:SetText(text)
    if color then
        label:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
    return label
end

function Settings:CreateControls(parent)
    local yOffset = -20
    local SPACING = 40
    -- ʕ •ᴥ•ʔ✿ Vertical rhythm — SECTION_GAP lives above every category header, HEADER_GAP under it ✿ ʕ •ᴥ•ʔ
    local SECTION_GAP = 18
    local HEADER_GAP = 22
    self.colorSwatches = {}
    self._syncingScaleControls = false

    -- 1. Frame Scale Slider
    local scaleSlider = CreateFrame("Slider", "OmniScaleSlider", parent, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOP", 0, yOffset)
    scaleSlider:SetMinMaxValues(0.5, 2.0)
    scaleSlider:SetValueStep(0.1)
    -- Note: SetObeyStepOnDrag not available in WotLK 3.3.5a
    scaleSlider:SetWidth(200)

    _G[scaleSlider:GetName() .. "Low"]:SetText("50%")
    _G[scaleSlider:GetName() .. "High"]:SetText("200%")
    _G[scaleSlider:GetName() .. "Text"]:SetText("Frame Scale")
    local scaleValueText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleValueText:SetPoint("TOP", scaleSlider, "BOTTOM", 0, 2)
    scaleValueText:SetText("Current: 100%")

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        if Settings._syncingScaleControls then return end
        -- Round to 1 decimal
        value = math.floor(value * 10 + 0.5) / 10
        if IsSettingEditLocked() then
            Settings:UpdateValues()
            print("|cFFFF4040OmniInventory|r: Scale settings can only be changed out of combat.")
            return
        end
        scaleValueText:SetText("Current: " .. FormatScalePercent(value))
        if Omni.Frame then
            Omni.Frame:SetScale(value)
        end
    end)
    self.scaleSlider = scaleSlider
    self.scaleValueText = scaleValueText

    yOffset = yOffset - SPACING

    -- 2. Item Scale Slider
    local itemScaleSlider = CreateFrame("Slider", "OmniItemScaleSlider", parent, "OptionsSliderTemplate")
    itemScaleSlider:SetPoint("TOP", 0, yOffset)
    itemScaleSlider:SetMinMaxValues(0.5, 2.0)
    itemScaleSlider:SetValueStep(0.1)
    itemScaleSlider:SetWidth(200)

    _G[itemScaleSlider:GetName() .. "Low"]:SetText("50%")
    _G[itemScaleSlider:GetName() .. "High"]:SetText("200%")
    _G[itemScaleSlider:GetName() .. "Text"]:SetText("Item Scale")
    local itemScaleValueText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    itemScaleValueText:SetPoint("TOP", itemScaleSlider, "BOTTOM", 0, 2)
    itemScaleValueText:SetText("Current: 100%")

    itemScaleSlider:SetScript("OnValueChanged", function(self, value)
        if Settings._syncingScaleControls then return end
        value = math.floor(value * 10 + 0.5) / 10
        if IsSettingEditLocked() then
            Settings:UpdateValues()
            print("|cFFFF4040OmniInventory|r: Scale settings can only be changed out of combat.")
            return
        end
        itemScaleValueText:SetText("Current: " .. FormatScalePercent(value))
        if Omni.Frame and Omni.Frame.SetItemScale then
            Omni.Frame:SetItemScale(value)
        end
    end)
    self.itemScaleSlider = itemScaleSlider
    self.itemScaleValueText = itemScaleValueText

    yOffset = yOffset - SPACING

    local itemGapSlider = CreateFrame("Slider", "OmniItemGapSlider", parent, "OptionsSliderTemplate")
    itemGapSlider:SetPoint("TOP", 0, yOffset)
    itemGapSlider:SetMinMaxValues(0, 20)
    itemGapSlider:SetValueStep(1)
    itemGapSlider:SetWidth(200)

    _G[itemGapSlider:GetName() .. "Low"]:SetText("0px")
    _G[itemGapSlider:GetName() .. "High"]:SetText("20px")
    _G[itemGapSlider:GetName() .. "Text"]:SetText("Item Gap")
    local itemGapValueText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    itemGapValueText:SetPoint("TOP", itemGapSlider, "BOTTOM", 0, 2)
    itemGapValueText:SetText("Current: 4 px")

    itemGapSlider:SetScript("OnValueChanged", function(self, value)
        if Settings._syncingScaleControls then return end
        value = math.floor(value + 0.5)
        if IsSettingEditLocked() then
            Settings:UpdateValues()
            print("|cFFFF4040OmniInventory|r: Scale settings can only be changed out of combat.")
            return
        end
        itemGapValueText:SetText("Current: " .. FormatGapPixels(value))
        if Omni.Frame and Omni.Frame.SetItemGap then
            Omni.Frame:SetItemGap(value)
        end
    end)
    self.itemGapSlider = itemGapSlider
    self.itemGapValueText = itemGapValueText

    yOffset = yOffset - SPACING - 20

    -- 3. View Mode (Grid, Flow, List)
    CreateSectionHeader(parent, "View Mode", yOffset, SECTION_COLORS.view)
    yOffset = yOffset - 20

    local viewBtn = CreateFrame("Button", "OmniViewToggle", parent, "UIPanelButtonTemplate")
    viewBtn:SetSize(140, 24)
    viewBtn:SetPoint("TOP", 0, yOffset)
    viewBtn:SetText("Cycle View")
    viewBtn:SetScript("OnClick", function()
        if Omni.Frame then Omni.Frame:CycleView() end
    end)
    self.viewBtn = viewBtn

    yOffset = yOffset - SPACING

    -- 4. Sort Mode
    CreateSectionHeader(parent, "Sort Mode (Default)", yOffset, SECTION_COLORS.sort)
    yOffset = yOffset - 20

    local sortBtn = CreateFrame("Button", "OmniSortToggle", parent, "UIPanelButtonTemplate")
    sortBtn:SetSize(140, 24)
    sortBtn:SetPoint("TOP", 0, yOffset)
    sortBtn:SetText("Cycle Sort")
    sortBtn:SetScript("OnClick", function()
        if Omni.Frame then Omni.Frame:CycleSort() end
    end)
    self.sortBtn = sortBtn

    yOffset = yOffset - SPACING - 20

    -- ʕ ● ᴥ ●ʔ Category Editor intentionally hidden — custom-rule engine is disabled pending rewrite

    yOffset = yOffset - SECTION_GAP
    CreateSectionHeader(parent, "Misc Options", yOffset, SECTION_COLORS.misc)
    yOffset = yOffset - HEADER_GAP

    local highlightCb = CreateFrame("CheckButton", "OmniHighlightNewItems", parent, "UICheckButtonTemplate")
    highlightCb:SetSize(24, 24)
    highlightCb:SetPoint("TOPLEFT", 14, yOffset)
    local highlightLabel = highlightCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    highlightLabel:SetPoint("LEFT", highlightCb, "RIGHT", 2, 1)
    highlightLabel:SetText("New items")
    highlightCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Highlight new items", 1, 0.82, 0)
        GameTooltip:AddLine("Visually emphasize items that count as new in your bags.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    highlightCb:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    highlightCb:SetScript("OnClick", function(self)
        if Omni.Data then
            Omni.Data:Set("highlightNewItems", self:GetChecked() and true or false)
            RefreshAllInventory()
        end
    end)
    self.highlightNewItemsCb = highlightCb

    local footerMoneyCb = CreateFrame("CheckButton", "OmniFooterMoneyEmphasis", parent, "UICheckButtonTemplate")
    footerMoneyCb:SetSize(24, 24)
    footerMoneyCb:SetPoint("TOPLEFT", 160, yOffset)
    local footerMoneyLabel = footerMoneyCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    footerMoneyLabel:SetPoint("LEFT", footerMoneyCb, "RIGHT", 2, 1)
    footerMoneyLabel:SetText("Bold footer")
    footerMoneyCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Bold footer", 1, 0.82, 0)
        GameTooltip:AddLine("Larger outlined gold and bag count. Slot text shifts from light blue to red as bags fill.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    footerMoneyCb:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    footerMoneyCb:SetScript("OnClick", function(self)
        if Omni.Data then
            Omni.Data:Set("footerMoneyEmphasis", self:GetChecked() and true or false)
        end
        if Omni.Frame and Omni.Frame.RefreshFooterMoneyStyle then
            Omni.Frame:RefreshFooterMoneyStyle()
        end
        RefreshAllInventory()
    end)
    self.footerMoneyEmphasisCb = footerMoneyCb

    yOffset = yOffset - 22

    local boundCatsCb = CreateFrame("CheckButton", "OmniEnableBoundCategories", parent, "UICheckButtonTemplate")
    boundCatsCb:SetSize(24, 24)
    boundCatsCb:SetPoint("TOPLEFT", 14, yOffset)
    local boundCatsLabel = boundCatsCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    boundCatsLabel:SetPoint("LEFT", boundCatsCb, "RIGHT", 2, 1)
    boundCatsLabel:SetText("Bound lanes")
    boundCatsCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Categorize bound items", 1, 0.82, 0)
        GameTooltip:AddLine("Separate Soulbound (BoP) equipment and Account Bound (BoA/Heirlooms) into their own lanes.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    boundCatsCb:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    boundCatsCb:SetScript("OnClick", function(self)
        if Omni.Data then
            Omni.Data:Set("enableBoundCategories", self:GetChecked() and true or false)
            RefreshAllInventory()
        end
    end)
    self.enableBoundCategoriesCb = boundCatsCb

    local unusableCb = CreateFrame("CheckButton", "OmniEnableUnusableOverlay", parent, "UICheckButtonTemplate")
    unusableCb:SetSize(24, 24)
    unusableCb:SetPoint("TOPLEFT", 160, yOffset)
    local unusableLabel = unusableCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    unusableLabel:SetPoint("LEFT", unusableCb, "RIGHT", 2, 1)
    unusableLabel:SetText("Red overlays")
    unusableCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Unusable red overlay", 1, 0.82, 0)
        GameTooltip:AddLine("Tints unusable gear (level/class locks) and unlearned recipes red.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    unusableCb:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    unusableCb:SetScript("OnClick", function(self)
        if Omni.Data then
            Omni.Data:Set("enableUnusableOverlay", self:GetChecked() and true or false)
            RefreshAllInventory()
        end
    end)
    self.enableUnusableOverlayCb = unusableCb

    yOffset = yOffset - 22

    local autoSellCb = CreateFrame("CheckButton", "OmniAutoSellJunk", parent, "UICheckButtonTemplate")
    autoSellCb:SetSize(24, 24)
    autoSellCb:SetPoint("TOPLEFT", 14, yOffset)
    local autoSellLabel = autoSellCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    autoSellLabel:SetPoint("LEFT", autoSellCb, "RIGHT", 2, 1)
    autoSellLabel:SetText("Auto-sell junk")
    autoSellCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Auto-sell junk", 1, 0.82, 0)
        GameTooltip:AddLine("Automatically sells all grey quality items in your bags when visiting a merchant NPC.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    autoSellCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    autoSellCb:SetScript("OnClick", function(self)
        if Omni.Data then
            Omni.Data:Set("autoSellJunk", self:GetChecked() and true or false)
        end
    end)
    self.autoSellJunkCb = autoSellCb

    local autoRepairCb = CreateFrame("CheckButton", "OmniAutoRepair", parent, "UICheckButtonTemplate")
    autoRepairCb:SetSize(24, 24)
    autoRepairCb:SetPoint("TOPLEFT", 160, yOffset)
    local autoRepairLabel = autoRepairCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    autoRepairLabel:SetPoint("LEFT", autoRepairCb, "RIGHT", 2, 1)
    autoRepairLabel:SetText("Auto-repair")
    autoRepairCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Auto-repair gear", 1, 0.82, 0)
        GameTooltip:AddLine("Automatically repairs all equipped and inventory gear when visiting a repair merchant.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    autoRepairCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    autoRepairCb:SetScript("OnClick", function(self)
        if Omni.Data then
            local checked = self:GetChecked() and true or false
            Omni.Data:Set("autoRepair", checked)
            if self.guildFundsCb then
                if checked then
                    self.guildFundsCb:Enable()
                    self.guildFundsCb:SetAlpha(1.0)
                else
                    self.guildFundsCb:Disable()
                    self.guildFundsCb:SetAlpha(0.5)
                end
            end
        end
    end)
    self.autoRepairCb = autoRepairCb

    yOffset = yOffset - 22

    local guildFundsCb = CreateFrame("CheckButton", "OmniAutoRepairGuild", parent, "UICheckButtonTemplate")
    guildFundsCb:SetSize(24, 24)
    guildFundsCb:SetPoint("TOPLEFT", 160, yOffset)
    local guildFundsLabel = guildFundsCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    guildFundsLabel:SetPoint("LEFT", guildFundsCb, "RIGHT", 2, 1)
    guildFundsLabel:SetText("Use Guild funds")
    guildFundsCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Use Guild Funds", 1, 0.82, 0)
        GameTooltip:AddLine("Attempts to use guild bank funds for auto-repairs before using your own gold.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    guildFundsCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    guildFundsCb:SetScript("OnClick", function(self)
        if Omni.Data then
            Omni.Data:Set("autoRepairGuild", self:GetChecked() and true or false)
        end
    end)
    self.autoRepairGuildCb = guildFundsCb

    -- Link them
    autoRepairCb.guildFundsCb = guildFundsCb

    local showItemLevelCb = CreateFrame("CheckButton", "OmniShowItemLevel", parent, "UICheckButtonTemplate")
    showItemLevelCb:SetSize(24, 24)
    showItemLevelCb:SetPoint("TOPLEFT", 14, yOffset)
    local showItemLevelLabel = showItemLevelCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    showItemLevelLabel:SetPoint("LEFT", showItemLevelCb, "RIGHT", 2, 1)
    showItemLevelLabel:SetText("Item levels")
    showItemLevelCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Show Item Levels", 1, 0.82, 0)
        GameTooltip:AddLine("Displays the item level (iLevel) directly on weapons and armor in your bags and bank.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    showItemLevelCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    showItemLevelCb:SetScript("OnClick", function(self)
        if Omni.Data then
            Omni.Data:Set("showItemLevel", self:GetChecked() and true or false)
            RefreshAllInventory()
        end
    end)
    self.showItemLevelCb = showItemLevelCb

    yOffset = yOffset - 22

    local sellProtectionCb = CreateFrame("CheckButton", "OmniVendorDoubleRightClick", parent, "UICheckButtonTemplate")
    sellProtectionCb:SetSize(24, 24)
    sellProtectionCb:SetPoint("TOPLEFT", 14, yOffset)
    local sellProtectionLabel = sellProtectionCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sellProtectionLabel:SetPoint("LEFT", sellProtectionCb, "RIGHT", 2, 1)
    sellProtectionLabel:SetText("Double-click sell protection")
    sellProtectionCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Vendor Sell Protection", 1, 0.82, 0)
        GameTooltip:AddLine("Requires a double-right-click to sell valuable items (Soulbound gear, active quest items, rare/epic loot) at vendors.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    sellProtectionCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sellProtectionCb:SetScript("OnClick", function(self)
        if Omni.Data then
            Omni.Data:Set("vendorDoubleRightClick", self:GetChecked() and true or false)
        end
    end)
    self.vendorDoubleRightClickCb = sellProtectionCb

    yOffset = yOffset - 22

    local collapseEmptyCb = CreateFrame("CheckButton", "OmniCollapseEmptySlots", parent, "UICheckButtonTemplate")
    collapseEmptyCb:SetSize(24, 24)
    collapseEmptyCb:SetPoint("TOPLEFT", 14, yOffset)
    local collapseEmptyLabel = collapseEmptyCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    collapseEmptyLabel:SetPoint("LEFT", collapseEmptyCb, "RIGHT", 2, 1)
    collapseEmptyLabel:SetText("Collapse empty slots")
    collapseEmptyCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Collapse Empty Slots", 1, 0.82, 0)
        GameTooltip:AddLine("Collapses all empty slots in Grid and Flow views into a single slot button per bag type, displaying a count of the total empty spaces.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    collapseEmptyCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    collapseEmptyCb:SetScript("OnClick", function(self)
        if Omni.Data then
            Omni.Data:Set("collapseEmptySlots", self:GetChecked() and true or false)
            RefreshAllInventory()
        end
    end)
    self.collapseEmptySlotsCb = collapseEmptyCb

    yOffset = yOffset - SPACING - 4

    local tipPlacementHeader = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tipPlacementHeader:SetPoint("TOP", parent, "TOP", 0, yOffset)
    tipPlacementHeader:SetWidth(260)
    tipPlacementHeader:SetJustifyH("CENTER")
    tipPlacementHeader:SetText("Item tooltips (bags, bank, guild bank, offline)")

    local tipPlacementBtn = CreateFrame("Button", "OmniTooltipPlacementBtn", parent, "UIPanelButtonTemplate")
    tipPlacementBtn:SetSize(260, 22)
    tipPlacementBtn:SetPoint("TOP", parent, "TOP", 0, yOffset - 18)
    tipPlacementBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Tooltip placement", 1, 0.82, 0)
        GameTooltip:AddLine("Right / Left: anchor relative to the slot. Fixed modes: screen corner + X/Y insets (sliders below).", 0.75, 0.75, 0.75, true)
        GameTooltip:AddLine("Click the button to cycle modes.", 0.65, 0.65, 0.65, true)
        GameTooltip:Show()
    end)
    tipPlacementBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    tipPlacementBtn:SetScript("OnClick", function()
        CycleTooltipPlacementSetting()
        Settings:RefreshTooltipPlacementControls()
    end)
    self.tooltipPlacementBtn = tipPlacementBtn

    yOffset = yOffset - TOOLTIP_PLACEMENT_TO_FIXED_SLIDER_GAP

    local tipFixedXSlider = CreateFrame("Slider", "OmniTooltipFixedXSlider", parent, "OptionsSliderTemplate")
    tipFixedXSlider:SetPoint("TOP", parent, "TOP", 0, yOffset)
    tipFixedXSlider:SetMinMaxValues(0, TOOLTIP_FIXED_X_MAX)
    tipFixedXSlider:SetValueStep(1)
    tipFixedXSlider:SetWidth(200)
    _G[tipFixedXSlider:GetName() .. "Low"]:SetText("0")
    _G[tipFixedXSlider:GetName() .. "High"]:SetText(tostring(TOOLTIP_FIXED_X_MAX))
    _G[tipFixedXSlider:GetName() .. "Text"]:SetText("Fixed X (horizontal inset)")
    local tipFixedXValue = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tipFixedXValue:SetPoint("TOP", tipFixedXSlider, "BOTTOM", 0, 2)
    tipFixedXValue:SetText("24")
    tipFixedXSlider:SetScript("OnValueChanged", function(_, value)
        if Settings._syncingTooltipFixedSliders then
            return
        end
        value = math.floor(value + 0.5)
        tipFixedXValue:SetText(tostring(value))
        if OmniInventoryDB and OmniInventoryDB.global then
            OmniInventoryDB.global.itemTooltipFixed = OmniInventoryDB.global.itemTooltipFixed or {}
            OmniInventoryDB.global.itemTooltipFixed.x = value
        end
        if Omni.ItemButton and Omni.ItemButton.FinalizeOmniItemTooltipLayout then
            Omni.ItemButton.FinalizeOmniItemTooltipLayout()
        end
    end)
    self.tooltipFixedXSlider = tipFixedXSlider
    self.tooltipFixedXValue = tipFixedXValue

    yOffset = yOffset - 36

    local tipFixedYSlider = CreateFrame("Slider", "OmniTooltipFixedYSlider", parent, "OptionsSliderTemplate")
    tipFixedYSlider:SetPoint("TOP", parent, "TOP", 0, yOffset)
    tipFixedYSlider:SetMinMaxValues(0, TOOLTIP_FIXED_Y_MAX)
    tipFixedYSlider:SetValueStep(1)
    tipFixedYSlider:SetWidth(200)
    _G[tipFixedYSlider:GetName() .. "Low"]:SetText("0")
    _G[tipFixedYSlider:GetName() .. "High"]:SetText(tostring(TOOLTIP_FIXED_Y_MAX))
    _G[tipFixedYSlider:GetName() .. "Text"]:SetText("Fixed Y (vertical inset)")
    local tipFixedYValue = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tipFixedYValue:SetPoint("TOP", tipFixedYSlider, "BOTTOM", 0, 2)
    tipFixedYValue:SetText("140")
    tipFixedYSlider:SetScript("OnValueChanged", function(_, value)
        if Settings._syncingTooltipFixedSliders then
            return
        end
        value = math.floor(value + 0.5)
        tipFixedYValue:SetText(tostring(value))
        if OmniInventoryDB and OmniInventoryDB.global then
            OmniInventoryDB.global.itemTooltipFixed = OmniInventoryDB.global.itemTooltipFixed or {}
            OmniInventoryDB.global.itemTooltipFixed.y = value
        end
        if Omni.ItemButton and Omni.ItemButton.FinalizeOmniItemTooltipLayout then
            Omni.ItemButton.FinalizeOmniItemTooltipLayout()
        end
    end)
    self.tooltipFixedYSlider = tipFixedYSlider
    self.tooltipFixedYValue = tipFixedYValue

    yOffset = yOffset - 36

    self:RefreshTooltipPlacementControls()

    -- 6. Reset Button
    local resetBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, 24)
    resetBtn:SetPoint("TOP", 0, yOffset)
    resetBtn:SetText("Reset Position & Scale")
    resetBtn:SetScript("OnClick", function()
        if Omni.Frame then
            Omni.Frame:ResetPosition()
            if self.scaleSlider then self.scaleSlider:SetValue(1.0) end
            if self.itemScaleSlider then self.itemScaleSlider:SetValue(1.0) end
            if self.itemGapSlider then self.itemGapSlider:SetValue(4) end
        end
    end)

    yOffset = yOffset - SPACING - SECTION_GAP



    CreateSectionHeader(parent, "Footer Buttons", yOffset, SECTION_COLORS.footer)
    yOffset = yOffset - HEADER_GAP

    self.footerButtonCbs = self.footerButtonCbs or {}
    for i, def in ipairs(FOOTER_BUTTON_OPTIONS) do
        local column = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local xOffset = (column == 0) and 14 or 160
        local rowY = yOffset - (row * 22)

        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", xOffset, rowY)
        local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 1)
        lbl:SetText(def.label)
        cb:SetChecked(IsFooterButtonEnabled(def.key))
        cb.__fbKey = def.key
        cb:SetScript("OnClick", function(self)
            local db = GetFooterButtonsDB()
            db[self.__fbKey] = self:GetChecked() and true or false
            if Omni.Frame and Omni.Frame.UpdateFooterCustomButtons then
                Omni.Frame:UpdateFooterCustomButtons()
            end
        end)
        self.footerButtonCbs[def.key] = cb
    end
    local rowCount = math.ceil(#FOOTER_BUTTON_OPTIONS / 2)
    yOffset = yOffset - (rowCount * 22)

    yOffset = yOffset - SECTION_GAP

    CreateSectionHeader(parent, "Addon Buttons", yOffset, SECTION_COLORS.addon)
    yOffset = yOffset - HEADER_GAP

    self.addonButtonCbs = self.addonButtonCbs or {}
    for i, def in ipairs(ADDON_BUTTON_OPTIONS) do
        local column = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local xOffset = (column == 0) and 14 or 160
        local rowY = yOffset - (row * 22)

        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", xOffset, rowY)
        local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 1)
        lbl:SetText(def.label)
        cb:SetChecked(IsAddonButtonEnabled(def.key))
        cb.__abKey = def.key
        cb:SetScript("OnClick", function(self)
            local db = GetAddonButtonsDB()
            db[self.__abKey] = self:GetChecked() and true or false
            if Omni.Frame and Omni.Frame.UpdateFooterCustomButtons then
                Omni.Frame:UpdateFooterCustomButtons()
            end
        end)
        self.addonButtonCbs[def.key] = cb
    end
    local addonRowCount = math.ceil(#ADDON_BUTTON_OPTIONS / 2)
    yOffset = yOffset - (addonRowCount * 22)

    yOffset = yOffset - SECTION_GAP

    -- ʕ •ᴥ•ʔ✿ New Features section: auto-display, junk lists, cache warmer,
    -- auto-loot, money tracker, bound indicator, bag type tags, theme,
    -- auto-tidy, resort button, global lock. ✿ ʕ •ᴥ•ʔ
    CreateSectionHeader(parent, "Auto-Display & Features", yOffset, { 0.85, 0.70, 1.00 })
    yOffset = yOffset - HEADER_GAP

    local autoDisplayBankCb = CreateFrame("CheckButton", "OmniAutoDisplayBank", parent, "UICheckButtonTemplate")
    autoDisplayBankCb:SetSize(24, 24)
    autoDisplayBankCb:SetPoint("TOPLEFT", 14, yOffset)
    local autoDisplayBankLabel = autoDisplayBankCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    autoDisplayBankLabel:SetPoint("LEFT", autoDisplayBankCb, "RIGHT", 2, 1)
    autoDisplayBankLabel:SetText("Auto-open at Bank")
    autoDisplayBankCb:SetScript("OnClick", function(self)
        if Omni.Data then
            local ad = Omni.Data:Get("autoDisplay") or {}
            ad.bank = self:GetChecked() and true or false
            Omni.Data:Set("autoDisplay", ad)
        end
    end)
    self.autoDisplayBankCb = autoDisplayBankCb

    local autoDisplayVendorCb = CreateFrame("CheckButton", "OmniAutoDisplayVendor", parent, "UICheckButtonTemplate")
    autoDisplayVendorCb:SetSize(24, 24)
    autoDisplayVendorCb:SetPoint("TOPLEFT", 160, yOffset)
    local autoDisplayVendorLabel = autoDisplayVendorCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    autoDisplayVendorLabel:SetPoint("LEFT", autoDisplayVendorCb, "RIGHT", 2, 1)
    autoDisplayVendorLabel:SetText("Auto-open at Vendor")
    autoDisplayVendorCb:SetScript("OnClick", function(self)
        if Omni.Data then
            local ad = Omni.Data:Get("autoDisplay") or {}
            ad.vendor = self:GetChecked() and true or false
            Omni.Data:Set("autoDisplay", ad)
        end
    end)
    self.autoDisplayVendorCb = autoDisplayVendorCb

    yOffset = yOffset - 22

    local autoDisplayMailCb = CreateFrame("CheckButton", "OmniAutoDisplayMail", parent, "UICheckButtonTemplate")
    autoDisplayMailCb:SetSize(24, 24)
    autoDisplayMailCb:SetPoint("TOPLEFT", 14, yOffset)
    local autoDisplayMailLabel = autoDisplayMailCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    autoDisplayMailLabel:SetPoint("LEFT", autoDisplayMailCb, "RIGHT", 2, 1)
    autoDisplayMailLabel:SetText("Auto-open at Mail")
    autoDisplayMailCb:SetScript("OnClick", function(self)
        if Omni.Data then
            local ad = Omni.Data:Get("autoDisplay") or {}
            ad.mail = self:GetChecked() and true or false
            Omni.Data:Set("autoDisplay", ad)
        end
    end)
    self.autoDisplayMailCb = autoDisplayMailCb

    local autoDisplayAhCb = CreateFrame("CheckButton", "OmniAutoDisplayAh", parent, "UICheckButtonTemplate")
    autoDisplayAhCb:SetSize(24, 24)
    autoDisplayAhCb:SetPoint("TOPLEFT", 160, yOffset)
    local autoDisplayAhLabel = autoDisplayAhCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    autoDisplayAhLabel:SetPoint("LEFT", autoDisplayAhCb, "RIGHT", 2, 1)
    autoDisplayAhLabel:SetText("Auto-open at AH")
    autoDisplayAhCb:SetScript("OnClick", function(self)
        if Omni.Data then
            local ad = Omni.Data:Get("autoDisplay") or {}
            ad.ah = self:GetChecked() and true or false
            Omni.Data:Set("autoDisplay", ad)
        end
    end)
    self.autoDisplayAhCb = autoDisplayAhCb

    yOffset = yOffset - 22

    local autoDisplayTradeCb = CreateFrame("CheckButton", "OmniAutoDisplayTrade", parent, "UICheckButtonTemplate")
    autoDisplayTradeCb:SetSize(24, 24)
    autoDisplayTradeCb:SetPoint("TOPLEFT", 14, yOffset)
    local autoDisplayTradeLabel = autoDisplayTradeCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    autoDisplayTradeLabel:SetPoint("LEFT", autoDisplayTradeCb, "RIGHT", 2, 1)
    autoDisplayTradeLabel:SetText("Auto-open at Trade")
    autoDisplayTradeCb:SetScript("OnClick", function(self)
        if Omni.Data then
            local ad = Omni.Data:Get("autoDisplay") or {}
            ad.trade = self:GetChecked() and true or false
            Omni.Data:Set("autoDisplay", ad)
        end
    end)
    self.autoDisplayTradeCb = autoDisplayTradeCb

    local autoDisplayCraftCb = CreateFrame("CheckButton", "OmniAutoDisplayCraft", parent, "UICheckButtonTemplate")
    autoDisplayCraftCb:SetSize(24, 24)
    autoDisplayCraftCb:SetPoint("TOPLEFT", 160, yOffset)
    local autoDisplayCraftLabel = autoDisplayCraftCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    autoDisplayCraftLabel:SetPoint("LEFT", autoDisplayCraftCb, "RIGHT", 2, 1)
    autoDisplayCraftLabel:SetText("Auto-open at Craft")
    autoDisplayCraftCb:SetScript("OnClick", function(self)
        if Omni.Data then
            local ad = Omni.Data:Get("autoDisplay") or {}
            ad.craft = self:GetChecked() and true or false
            Omni.Data:Set("autoDisplay", ad)
        end
    end)
    self.autoDisplayCraftCb = autoDisplayCraftCb

    yOffset = yOffset - 22

    local cacheWarmerCb = CreateFrame("CheckButton", "OmniCacheWarmer", parent, "UICheckButtonTemplate")
    cacheWarmerCb:SetSize(24, 24)
    cacheWarmerCb:SetPoint("TOPLEFT", 14, yOffset)
    local cacheWarmerLabel = cacheWarmerCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cacheWarmerLabel:SetPoint("LEFT", cacheWarmerCb, "RIGHT", 2, 1)
    cacheWarmerLabel:SetText("Cache warmer")
    cacheWarmerCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Cache Warmer", 1, 0.82, 0)
        GameTooltip:AddLine("Pre-loads GetItemInfo for known item IDs on login to avoid tooltip delays.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    cacheWarmerCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cacheWarmerCb:SetScript("OnClick", function(self)
        if Omni.Data then
            Omni.Data:Set("cacheWarmer", self:GetChecked() and true or false)
        end
    end)
    self.cacheWarmerCb = cacheWarmerCb

    local autoLootCb = CreateFrame("CheckButton", "OmniAutoLoot", parent, "UICheckButtonTemplate")
    autoLootCb:SetSize(24, 24)
    autoLootCb:SetPoint("TOPLEFT", 160, yOffset)
    local autoLootLabel = autoLootCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    autoLootLabel:SetPoint("LEFT", autoLootCb, "RIGHT", 2, 1)
    autoLootLabel:SetText("Auto-loot")
    autoLootCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Auto-Loot", 1, 0.82, 0)
        GameTooltip:AddLine("Automatically loots all items when a loot frame opens.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    autoLootCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    autoLootCb:SetScript("OnClick", function(self)
        if Omni.Data then
            Omni.Data:Set("autoLoot", self:GetChecked() and true or false)
            if Omni.Features and Omni.Features.InitAutoLoot then
                Omni.Features:InitAutoLoot()
            end
        end
    end)
    self.autoLootCb = autoLootCb

    yOffset = yOffset - 22

    local moneyTrackerCb = CreateFrame("CheckButton", "OmniMoneyTracker", parent, "UICheckButtonTemplate")
    moneyTrackerCb:SetSize(24, 24)
    moneyTrackerCb:SetPoint("TOPLEFT", 14, yOffset)
    local moneyTrackerLabel = moneyTrackerCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    moneyTrackerLabel:SetPoint("LEFT", moneyTrackerCb, "RIGHT", 2, 1)
    moneyTrackerLabel:SetText("Money tracker")
    moneyTrackerCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Money Tracker", 1, 0.82, 0)
        GameTooltip:AddLine("Records gold history per character over time for trend display.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    moneyTrackerCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    moneyTrackerCb:SetScript("OnClick", function(self)
        if Omni.Data then
            Omni.Data:Set("moneyTracker", self:GetChecked() and true or false)
        end
    end)
    self.moneyTrackerCb = moneyTrackerCb

    local boundIndicatorCb = CreateFrame("CheckButton", "OmniBoundIndicator", parent, "UICheckButtonTemplate")
    boundIndicatorCb:SetSize(24, 24)
    boundIndicatorCb:SetPoint("TOPLEFT", 160, yOffset)
    local boundIndicatorLabel = boundIndicatorCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    boundIndicatorLabel:SetPoint("LEFT", boundIndicatorCb, "RIGHT", 2, 1)
    boundIndicatorLabel:SetText("Bound indicator")
    boundIndicatorCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Bound Item Indicator", 1, 0.82, 0)
        GameTooltip:AddLine("Shows a small chain icon on soulbound items in the bag.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    boundIndicatorCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    boundIndicatorCb:SetScript("OnClick", function(self)
        if Omni.Data then
            Omni.Data:Set("showBoundIndicator", self:GetChecked() and true or false)
            RefreshAllInventory()
        end
    end)
    self.boundIndicatorCb = boundIndicatorCb

    yOffset = yOffset - 22

    local bagTypeTagsCb = CreateFrame("CheckButton", "OmniBagTypeTags", parent, "UICheckButtonTemplate")
    bagTypeTagsCb:SetSize(24, 24)
    bagTypeTagsCb:SetPoint("TOPLEFT", 14, yOffset)
    local bagTypeTagsLabel = bagTypeTagsCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bagTypeTagsLabel:SetPoint("LEFT", bagTypeTagsCb, "RIGHT", 2, 1)
    bagTypeTagsLabel:SetText("Bag type tags")
    bagTypeTagsCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Bag Type Tags", 1, 0.82, 0)
        GameTooltip:AddLine("Shows family tag text (Ammo, Herb, Mining, etc.) on specialty bag tooltips.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    bagTypeTagsCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bagTypeTagsCb:SetScript("OnClick", function(self)
        if Omni.Data then
            Omni.Data:Set("showBagTypeTags", self:GetChecked() and true or false)
        end
    end)
    self.bagTypeTagsCb = bagTypeTagsCb

    local autoTidyCb = CreateFrame("CheckButton", "OmniAutoTidy", parent, "UICheckButtonTemplate")
    autoTidyCb:SetSize(24, 24)
    autoTidyCb:SetPoint("TOPLEFT", 160, yOffset)
    local autoTidyLabel = autoTidyCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    autoTidyLabel:SetPoint("LEFT", autoTidyCb, "RIGHT", 2, 1)
    autoTidyLabel:SetText("Auto-tidy on close")
    autoTidyCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Auto-Tidy on Close", 1, 0.82, 0)
        GameTooltip:AddLine("Compacts bag layout and sorts when the bag window is closed (AdiBags TidyBags).", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    autoTidyCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    autoTidyCb:SetScript("OnClick", function(self)
        if Omni.Data then
            Omni.Data:Set("autoTidyOnClose", self:GetChecked() and true or false)
        end
    end)
    self.autoTidyCb = autoTidyCb

    yOffset = yOffset - 22

    local resortButtonCb = CreateFrame("CheckButton", "OmniResortButton", parent, "UICheckButtonTemplate")
    resortButtonCb:SetSize(24, 24)
    resortButtonCb:SetPoint("TOPLEFT", 14, yOffset)
    local resortButtonLabel = resortButtonCb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    resortButtonLabel:SetPoint("LEFT", resortButtonCb, "RIGHT", 2, 1)
    resortButtonLabel:SetText("Resort button")
    resortButtonCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Resort Button", 1, 0.82, 0)
        GameTooltip:AddLine("Shows a resort button when a dry-run detects the layout could be reorganized.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    resortButtonCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    resortButtonCb:SetScript("OnClick", function(self)
        if Omni.Data then
            Omni.Data:Set("showResortButton", self:GetChecked() and true or false)
        end
    end)
    self.resortButtonCb = resortButtonCb

    -- Theme cycle button
    local themeBtn = CreateFrame("Button", "OmniThemeBtn", parent, "UIPanelButtonTemplate")
    themeBtn:SetSize(120, 22)
    themeBtn:SetPoint("TOPLEFT", 160, yOffset)
    themeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Theme", 1, 0.82, 0)
        GameTooltip:AddLine("Rounded: default WoW borders. Square: pfUI-compatible, cropped icons.", 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    themeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    themeBtn:SetScript("OnClick", function()
        if Omni.Features and Omni.Features.GetTheme then
            local cur = Omni.Features:GetTheme()
            local nextTheme = cur == "square" and "rounded" or "square"
            Omni.Features:SetTheme(nextTheme)
            Settings:RefreshThemeLabel()
            RefreshAllInventory()
        end
    end)
    self.themeBtn = themeBtn

    yOffset = yOffset - SPACING - SECTION_GAP

    -- ʕ •ᴥ•ʔ✿ yOffset grows negative as rows are added — flip and pad for the scroll child ✿ ʕ •ᴥ•ʔ
    self._contentHeight = math.abs(yOffset) + 40
end

function Settings:CreateLabel(parent, text, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOP", x, y)
    label:SetText(text)
    return label
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
    if self.tooltipPlacementBtn then
        self.tooltipPlacementBtn:SetText(GetTooltipPlacementButtonLabel(mode))
    end
    local fixedActive = IsFixedTooltipPlacementMode(mode)
    local inactiveAlpha = 0.48
    local function StyleFixedSlider(slider, enabled)
        if not slider then
            return
        end
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
                self.autoRepairGuildCb:Enable()
                self.autoRepairGuildCb:SetAlpha(1.0)
            else
                self.autoRepairGuildCb:Disable()
                self.autoRepairGuildCb:SetAlpha(0.5)
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
    -- ʕ •ᴥ•ʔ✿ New Features checkboxes ✿ ʕ •ᴥ•ʔ
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
        if self.tooltipFixedXValue then
            self.tooltipFixedXValue:SetText(tostring(math.floor(fx + 0.5)))
        end
        if self.tooltipFixedYValue then
            self.tooltipFixedYValue:SetText(tostring(math.floor(fy + 0.5)))
        end
    end
    self._syncingTooltipFixedSliders = false
    self:RefreshTooltipPlacementControls()
    if Omni.Frame and self.scaleSlider then
        local scale = Omni.Frame:GetScale()
        self.scaleSlider:SetValue(scale)
        if self.scaleValueText then
            self.scaleValueText:SetText("Current: " .. FormatScalePercent(scale))
        end
    end
    if Omni.Frame and self.itemScaleSlider and Omni.Frame.GetItemScale then
        local itemScale = Omni.Frame:GetItemScale()
        self.itemScaleSlider:SetValue(itemScale)
        if self.itemScaleValueText then
            self.itemScaleValueText:SetText("Current: " .. FormatScalePercent(itemScale))
        end
    end
    if Omni.Frame and self.itemGapSlider and Omni.Frame.GetItemGap then
        local itemGap = Omni.Frame:GetItemGap()
        self.itemGapSlider:SetValue(itemGap)
        if self.itemGapValueText then
            self.itemGapValueText:SetText("Current: " .. FormatGapPixels(itemGap))
        end
    end
    local scaleControlsEnabled = not IsSettingEditLocked()
    local function SetSliderInteractive(slider, enabled)
        if not slider then return end
        slider:EnableMouse(enabled)
        slider:SetAlpha(enabled and 1 or 0.55)
    end
    SetSliderInteractive(self.scaleSlider, scaleControlsEnabled)
    SetSliderInteractive(self.itemScaleSlider, scaleControlsEnabled)
    SetSliderInteractive(self.itemGapSlider, scaleControlsEnabled)


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
    self.themeBtn:SetText("Theme: " .. theme)
end

function Settings:Init()
    -- Initialized
end

print("|cFF00FF00OmniInventory|r: Settings module loaded")
