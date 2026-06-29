-- =============================================================================
-- OmniInventory Item Button Widget
-- =============================================================================
-- Purpose: Reusable item slot button with icon, count, quality border,
-- tooltip, and click handling. Uses object pooling for efficiency.
-- =============================================================================

local addonName, Omni = ...

Omni.ItemButton = {}
local ItemButton = Omni.ItemButton

-- =============================================================================
-- Constants
-- =============================================================================

local BUTTON_SIZE = 37
local ICON_SIZE = 32
local BORDER_SIZE = 2

local TEXTURE_QUEST_AVAILABLE = "Interface\\GossipFrame\\AvailableQuestIcon"
local TEXTURE_QUEST_DAILY = "Interface\\GossipFrame\\DailyQuestIcon"
local QUEST_STARTER_ICON_SIZE = 20
local ConfigureSecureItemUse

local function GetSpecialtyBagColor(bagID)
    if not bagID or bagID < 1 or bagID > 11 then
        return nil
    end
    local _, family = GetContainerNumFreeSlots(bagID)
    family = family or 0
    if family == 0 then
        return nil
    end

    if bit.band(family, 1) > 0 or bit.band(family, 2) > 0 then
        return 0.9, 0.8, 0.2  -- Ammo / Quiver (Yellow-gold)
    elseif bit.band(family, 4) > 0 then
        return 0.6, 0.2, 0.85  -- Soul Bag (Purple)
    elseif bit.band(family, 8) > 0 then
        return 0.6, 0.4, 0.25  -- Leatherworking (Brown)
    elseif bit.band(family, 16) > 0 then
        return 0.4, 0.6, 1.0   -- Inscription (Light Blue)
    elseif bit.band(family, 32) > 0 then
        return 0.12, 0.85, 0.12 -- Herbs (Green)
    elseif bit.band(family, 64) > 0 then
        return 0.9, 0.45, 0.1  -- Mining (Copper)
    elseif bit.band(family, 128) > 0 then
        return 0.12, 0.64, 1.0 -- Engineering (Cyan)
    elseif bit.band(family, 512) > 0 then
        return 0.0, 0.8, 0.7   -- Gems (Teal)
    elseif bit.band(family, 1024) > 0 then
        return 0.0, 0.5, 0.9   -- Tackle Box (Deep Blue)
    end
    return nil
end

local function isTextColorRed(textTable)
    if not textTable then return false end
    local text = textTable:GetText()
    if not text or text == "" or string.find(text, "^0 / %d+$") then return false end
    local r, g, b = textTable:GetTextColor()
    return r > 0.95 and g < 0.2 and b < 0.2
end

local function CheckIfItemUnusable(bag, slot, itemID)
    if not bag or not slot or not itemID then return false end

    -- Fast pre-check by level
    local _, _, _, _, minLevel = GetItemInfo(itemID)
    if minLevel and minLevel > 0 then
        if minLevel > UnitLevel("player") then
            return true
        end
    end

    -- Tooltip check
    local scanningTooltip = _G["OmniScanningTooltip"]
    if not scanningTooltip then return false end

    scanningTooltip:ClearLines()
    scanningTooltip:SetBagItem(bag, slot)

    for i = 2, scanningTooltip:NumLines() do
        local leftFrame = _G["OmniScanningTooltipTextLeft" .. i]
        if leftFrame and isTextColorRed(leftFrame) then
            return true
        end
        local rightFrame = _G["OmniScanningTooltipTextRight" .. i]
        if rightFrame and isTextColorRed(rightFrame) then
            return true
        end
    end

    return false
end

local function NormalizeMouseButton(mouseButton)
    if mouseButton == "LeftButtonUp" or mouseButton == "LeftButtonDown" then
        return "LeftButton"
    end
    if mouseButton == "RightButtonUp" or mouseButton == "RightButtonDown" then
        return "RightButton"
    end
    if mouseButton == "MiddleButtonUp" or mouseButton == "MiddleButtonDown" then
        return "MiddleButton"
    end
    return mouseButton
end

local function IsSendMailComposeOpen()
    return SendMailFrame and SendMailFrame:IsShown()
end

local function PerformBlizzardContainerRightClick(bagID, slotID)
    if not bagID or not slotID or bagID < 0 or slotID < 1 then
        return false
    end
    local clickFn = _G.ContainerFrameItemButton_OnClick
    if not clickFn or not Omni.Utils or not Omni.Utils.EnsureBlizzardContainerItemButtons or not Omni.Utils.GetBlizzardBagSlotButton then
        return false
    end
    Omni.Utils:EnsureBlizzardContainerItemButtons()
    local proxy = Omni.Utils:GetBlizzardBagSlotButton(bagID, slotID)
    if not proxy then
        return false
    end
    clickFn(proxy, "RightButton")
    return true
end

function ItemButton:HandleBagSlotRightClickInventory(bagID, slotID, secureUseConfigured)
    if not bagID or not slotID or bagID < 0 or slotID < 1 then
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        return false
    end
    if IsSendMailComposeOpen() then
        if not PerformBlizzardContainerRightClick(bagID, slotID) then
            UseContainerItem(bagID, slotID)
        end
        return true
    end
    if not secureUseConfigured then
        UseContainerItem(bagID, slotID)
        return true
    end
    return false
end

local QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 },
    [1] = { 1.00, 1.00, 1.00 },
    [2] = { 0.12, 1.00, 0.00 },
    [3] = { 0.00, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 },
    [5] = { 1.00, 0.50, 0.00 },
    [6] = { 0.90, 0.80, 0.50 },
    [7] = { 0.00, 0.80, 1.00 },
}

-- ʕ •ᴥ•ʔ✿ Hidden, ID-less limbo parent for buttons that are not currently
-- assigned to any (bag, slot). Buttons must always have a real parent so
-- their secure OnClick path doesn't dereference nil; we only reparent
-- to the bag-keyed ItemContainer at acquire time. ✿ ʕ •ᴥ•ʔ
local buttonLimbo
local function GetButtonLimbo()
    if not buttonLimbo then
        buttonLimbo = CreateFrame("Frame", "OmniItemButtonLimbo", UIParent)
        buttonLimbo:Hide()
    end
    return buttonLimbo
end

local VALID_ITEM_TOOLTIP_PLACEMENT = {
    right = true,
    left = true,
    fixed = true,
    fixed_br = true,
    fixed_bl = true,
    fixed_tl = true,
    fixed_tr = true,
}

local function NormalizeTooltipPlacement(p)
    if p == "fixed" then
        return "fixed_br"
    end
    return p
end

local function IsFixedScreenTooltipPlacement(p)
    p = NormalizeTooltipPlacement(p)
    return p == "fixed_br" or p == "fixed_bl" or p == "fixed_tl" or p == "fixed_tr"
end

local function GetResolvedItemTooltipPlacement()
    if Omni and Omni.Data and Omni.Data.Get then
        local p = Omni.Data:Get("itemTooltipPlacement")
        if type(p) == "string" and VALID_ITEM_TOOLTIP_PLACEMENT[p] then
            return NormalizeTooltipPlacement(p)
        end
    end
    return "right"
end

-- ʕ •ᴥ•ʔ✿ Real container slots (bags, bank, bank bags, keyring); main bank is bagID -1. ✿ ʕ •ᴥ•ʔ
local function IsLiveContainerFrameSlot(bagID, slotID)
    if bagID == nil or slotID == nil then
        return false
    end
    if bagID == -2 or bagID == -1 then
        return true
    end
    if bagID >= 0 and bagID <= 11 then
        return true
    end
    return false
end

local questScanTooltip
local function GetQuestScanTooltip()
    if not questScanTooltip then
        questScanTooltip = CreateFrame("GameTooltip", "OmniItemQuestScanTooltip", nil, "GameTooltipTemplate")
        questScanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return questScanTooltip
end
local function GetItemStartsQuestTooltipMarker()
    return ITEM_STARTS_QUEST
end

local function BagSlotTooltipMentionsStartsQuest(bagID, slotID)
    local marker = GetItemStartsQuestTooltipMarker()
    if not marker or not bagID or not slotID then
        return false
    end
    if not IsLiveContainerFrameSlot(bagID, slotID) then
        return false
    end
    local tip = GetQuestScanTooltip()
    tip:ClearLines()
    tip:SetBagItem(bagID, slotID)
    local prefix = "OmniItemQuestScanTooltipTextLeft"
    for i = 1, tip:NumLines() do
        local left = _G[prefix .. i]
        if left then
            local text = left:GetText()
            if text and string.find(text, marker, 1, true) then
                return true
            end
        end
    end
    return false
end

-- ʕ •ᴥ•ʔ✿ nil = hide; "available" / "daily" after ITEMS_STARTS_QUEST line + quest id ✿ ʕ •ᴥ•ʔ
local function GetQuestStarterOverlayKind(bagID, slotID)
    if not BagSlotTooltipMentionsStartsQuest(bagID, slotID) then
        return nil
    end
    local questId
    if GetContainerItemQuestInfo then
        local _, qId = GetContainerItemQuestInfo(bagID, slotID)
        questId = qId
    end
    if questId and questId > 0 and type(IsDailyQuest) == "function" and IsDailyQuest(questId) then
        return "daily"
    end
    return "available"
end

local function LayoutQuestStarterIcon(button)
    local icon = button.questStarterIcon
    if not icon or not icon:IsShown() then
        return
    end
    icon:ClearAllPoints()
    if button.accountIcon and button.accountIcon:IsShown() then
        icon:SetPoint("TOPLEFT", button.accountIcon, "TOPRIGHT", 2, 0)
    else
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", -3, -2)
    end
end

local function UpdateQuestStarterIcon(button, itemInfo)
    if not button or not button.questStarterIcon then
        return
    end
    local icon = button.questStarterIcon
    if not itemInfo or itemInfo.__empty or not itemInfo.bagID or not itemInfo.slotID then
        icon:Hide()
        return
    end
    local kind = GetQuestStarterOverlayKind(itemInfo.bagID, itemInfo.slotID)
    if not kind then
        icon:Hide()
        return
    end
    if kind == "daily" then
        icon:SetTexture(TEXTURE_QUEST_DAILY)
    else
        icon:SetTexture(TEXTURE_QUEST_AVAILABLE)
    end
    icon:Show()
    LayoutQuestStarterIcon(button)
end

local function UpdateTooltipCompareState()
    if not GameTooltip or not GameTooltip:IsShown() then
        return
    end

    if IsShiftKeyDown() then
        if GameTooltip_ShowCompareItem then
            GameTooltip_ShowCompareItem(GameTooltip)
        end
    else
        if GameTooltip_HideShoppingTooltips then
            GameTooltip_HideShoppingTooltips(GameTooltip)
        else
            if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
            if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
        end
    end
    ItemButton.FinalizeOmniItemTooltipLayout()
end

local modifierTooltipFrame = CreateFrame("Frame")
modifierTooltipFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
modifierTooltipFrame:SetScript("OnEvent", function()
    UpdateTooltipCompareState()
end)

function ItemButton.GetResolvedTooltipPlacement()
    return GetResolvedItemTooltipPlacement()
end

function ItemButton.SetOmniItemTooltipOwner(owner)
    if not owner or not GameTooltip then
        return
    end
    local placement = GetResolvedItemTooltipPlacement()
    if IsFixedScreenTooltipPlacement(placement) then
        GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    elseif placement == "left" then
        GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    else
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    end
end

function ItemButton.HideTooltipIfOwnedBy(owner)
    if not owner or not GameTooltip or not GameTooltip.GetOwner then
        return false
    end
    if GameTooltip:GetOwner() ~= owner then
        return false
    end
    GameTooltip:Hide()
    if GameTooltip_HideShoppingTooltips then
        GameTooltip_HideShoppingTooltips(GameTooltip)
    else
        if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
        if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
    end
    return true
end

function ItemButton.FinalizeOmniItemTooltipLayout()
    local placement = GetResolvedItemTooltipPlacement()
    if not IsFixedScreenTooltipPlacement(placement) then
        return
    end
    if not GameTooltip or not GameTooltip:IsShown() then
        return
    end
    local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
    if not owner or owner.__omniUsesCustomTooltip ~= true then
        return
    end
    local fix = Omni.Data and Omni.Data.Get and Omni.Data:Get("itemTooltipFixed")
    -- ʕ •ᴥ•ʔ✿ X/Y = inset toward screen center from the anchored corner (caps match options sliders) ✿ ʕ •ᴥ•ʔ
    local FIXED_X_MAX, FIXED_Y_MAX = 400, 400
    local hInset = 24
    local vInset = 140
    if type(fix) == "table" then
        hInset = math.max(0, math.min(tonumber(fix.x) or hInset, FIXED_X_MAX))
        vInset = math.max(0, math.min(tonumber(fix.y) or vInset, FIXED_Y_MAX))
    end
    GameTooltip:ClearAllPoints()
    if placement == "fixed_br" then
        GameTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -hInset, vInset)
    elseif placement == "fixed_bl" then
        GameTooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", hInset, vInset)
    elseif placement == "fixed_tl" then
        GameTooltip:SetPoint("TOPLEFT", UIParent, "TOPLEFT", hInset, -vInset)
    elseif placement == "fixed_tr" then
        GameTooltip:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -hInset, -vInset)
    end
end



local function GetItemIDFromLink(itemLink)
    if not itemLink then
        return nil
    end
    if Omni.API then
        local id = Omni.API:GetIdFromLink(itemLink)
        if id then
            return id
        end
    end
    local itemIdStr = string.match(itemLink, "item:(%d+)")
    if itemIdStr then
        return tonumber(itemIdStr)
    end
    return nil
end



local function GetButtonRenderSize(button)
    if not button then
        return BUTTON_SIZE
    end
    local w = button.GetWidth and button:GetWidth() or BUTTON_SIZE
    local h = button.GetHeight and button:GetHeight() or BUTTON_SIZE
    local size = math.min(w or BUTTON_SIZE, h or BUTTON_SIZE)
    if not size or size <= 0 then
        size = BUTTON_SIZE
    end
    return size
end



local function HideItemCooldown(button)
    if button and button.cooldown then
        button.cooldown:Hide()
    end
end

local function ShouldShowEmptyDropHighlight(button)
    if not button or not button.itemInfo or not button.itemInfo.__empty then
        return false
    end
    return CursorHasItem and CursorHasItem() and true or false
end

local function UpdateEmptyDropHighlight(button)
    if not button or not button.emptyDropHighlight then
        return
    end

    if ShouldShowEmptyDropHighlight(button) then
        button.emptyDropHighlight:Show()
    else
        button.emptyDropHighlight:Hide()
    end
end

-- =============================================================================
-- Button Creation
-- =============================================================================

local buttonCount = 0

function ItemButton:Create(parent)
    buttonCount = buttonCount + 1
    local name = "OmniItemButton" .. buttonCount

    -- ʕ •ᴥ•ʔ✿ ContainerFrameItemButtonTemplate is THE template AdiBags / Bagnon
    -- use. It carries Blizzard's own secure OnClick (ContainerFrameItemButton_
    -- OnClick) which reads bag from self:GetParent():GetID() and slot from
    -- self:GetID(), and is whitelisted to call PickupContainerItem and
    -- UseContainerItem in combat. Crucially this template does NOT promote
    -- its parent to "protected by association" the way SecureActionButton
    -- Template does, so OmniInventoryFrame stays a plain Frame and Show /
    -- Hide work in combat. We park the button on the limbo parent here and
    -- let acquire-time logic reparent it to the bag-keyed ItemContainer. ✿ ʕ •ᴥ•ʔ
    local button = CreateFrame("Button", name, parent or GetButtonLimbo(), "ContainerFrameItemButtonTemplate")
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- ʕ •ᴥ•ʔ✿ Strip the Blizzard normal/pushed/highlight skin -- our quality
    -- border owns the look. The icon, count, and cooldown frames provided
    -- by the template are wired up below. ✿ ʕ •ᴥ•ʔ
    pcall(button.SetNormalTexture, button, nil)
    pcall(button.SetPushedTexture, button, nil)
    pcall(button.SetHighlightTexture, button, nil)
    pcall(button.SetDisabledTexture, button, nil)
    if button.SetNormalTexture and _G[name .. "NormalTexture"] then
        _G[name .. "NormalTexture"]:SetAlpha(0)
    end

    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.bg:SetVertexColor(0.1, 0.1, 0.1, 1)

    button.icon = _G[name .. "IconTexture"] or button:CreateTexture(nil, "ARTWORK")
    button.icon:ClearAllPoints()
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.cooldown = _G[name .. "Cooldown"]
    if not button.cooldown then
        button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    end
    button.cooldown:ClearAllPoints()
    button.cooldown:SetPoint("TOPLEFT", button.icon, "TOPLEFT", 0, 0)
    button.cooldown:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT", 0, 0)
    button.cooldown:Hide()

    local questIcon = _G[name .. "IconQuestTexture"]
    if questIcon then questIcon:Hide() end
    local stockTex = _G[name .. "Stock"]
    if stockTex then stockTex:Hide() end

    -- Quality border (our custom colored border)
    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetPoint("TOPLEFT", -1, 1)
    button.border:SetPoint("BOTTOMRIGHT", 1, -1)
    button.border:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.border:SetVertexColor(0.3, 0.3, 0.3, 1)
    button:CreateTexture(nil, "OVERLAY"):Hide()  -- Placeholder

    -- Create actual border using 4 edge textures for clean look
    button.borderTop = button:CreateTexture(nil, "OVERLAY")
    button.borderTop:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.borderTop:SetHeight(1)
    button.borderTop:SetPoint("TOPLEFT", 0, 0)
    button.borderTop:SetPoint("TOPRIGHT", 0, 0)
    button.borderTop:SetVertexColor(0.3, 0.3, 0.3, 1)

    button.borderBottom = button:CreateTexture(nil, "OVERLAY")
    button.borderBottom:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.borderBottom:SetHeight(1)
    button.borderBottom:SetPoint("BOTTOMLEFT", 0, 0)
    button.borderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
    button.borderBottom:SetVertexColor(0.3, 0.3, 0.3, 1)

    button.borderLeft = button:CreateTexture(nil, "OVERLAY")
    button.borderLeft:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.borderLeft:SetWidth(1)
    button.borderLeft:SetPoint("TOPLEFT", 0, 0)
    button.borderLeft:SetPoint("BOTTOMLEFT", 0, 0)
    button.borderLeft:SetVertexColor(0.3, 0.3, 0.3, 1)

    button.borderRight = button:CreateTexture(nil, "OVERLAY")
    button.borderRight:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.borderRight:SetWidth(1)
    button.borderRight:SetPoint("TOPRIGHT", 0, 0)
    button.borderRight:SetPoint("BOTTOMRIGHT", 0, 0)
    button.borderRight:SetVertexColor(0.3, 0.3, 0.3, 1)

    -- Hide the backdrop border texture we created earlier
    button.border:Hide()

    -- Search dim overlay
    button.dimOverlay = button:CreateTexture(nil, "OVERLAY", nil, 7)
    button.dimOverlay:SetAllPoints(button.icon)
    button.dimOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.dimOverlay:SetVertexColor(0, 0, 0, 0.7)
    button.dimOverlay:Hide()

    button.emptyDropHighlight = button:CreateTexture(nil, "OVERLAY", nil, 8)
    button.emptyDropHighlight:SetAllPoints(button.icon)
    button.emptyDropHighlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.emptyDropHighlight:SetVertexColor(0.25, 0.85, 1, 0.35)
    button.emptyDropHighlight:Hide()

    -- Pin/Favorite icon (star in top-right corner)
    button.pinIcon = button:CreateTexture(nil, "OVERLAY")
    button.pinIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1") -- Star icon
    button.pinIcon:SetSize(14, 14)
    button.pinIcon:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    button.pinIcon:Hide()

    button.questStarterIcon = button:CreateTexture(nil, "OVERLAY", nil, 3)
    button.questStarterIcon:SetSize(QUEST_STARTER_ICON_SIZE, QUEST_STARTER_ICON_SIZE)
    button.questStarterIcon:Hide()





    -- ʕ •ᴥ•ʔ✿ Template Count sits under our OVERLAY adornments; own string last ✿ ʕ •ᴥ•ʔ
    local templateCount = _G[name .. "Count"]
    if templateCount then
        templateCount:SetText("")
        templateCount:Hide()
    end
    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    button.count:SetJustifyH("RIGHT")
    pcall(button.count.SetDrawLayer, button.count, "OVERLAY", 127)

    button.itemInfo = nil

    -- ʕ •ᴥ•ʔ✿ HookScript after template: OnClick adds shift+rclick pin; OnEnter
    -- rebuilds GameTooltip (SetBagItem / hyperlink) so placement matches Omni settings. ✿ ʕ •ᴥ•ʔ
    button:HookScript("OnMouseDown", function(self)
        ItemButton:OnMouseDown(self)
    end)

    button:HookScript("OnClick", function(self, mouseButton)
        ItemButton:OnClick(self, mouseButton)
    end)

    button:HookScript("OnEnter", function(self)
        ItemButton:OnEnter(self)
    end)

    button:HookScript("OnLeave", function(self)
        ItemButton:OnLeave(self)
    end)

    button:HookScript("OnUpdate", function(self)
        if self.__emptyDropHighlightHovering then
            UpdateEmptyDropHighlight(self)
        end
    end)

    button:HookScript("OnDragStart", function(self)
        ItemButton:OnDragStart(self)
    end)

    button:HookScript("OnReceiveDrag", function(self)
        ItemButton:OnReceiveDrag(self)
    end)

    -- ʕ •ᴥ•ʔ✿ GameTooltip_OnUpdate calls owner:UpdateTooltip (~TOOLTIP_UPDATE_TIME).
    -- Default ContainerFrameItemButton_OnEnter uses GetParent():GetID() for the
    -- bag; BANK_CONTAINER (-1) can round-trip wrong from Frame:GetID on some
    -- builds, so the refresh clears the tip while hover continues. Rebuild from
    -- itemInfo like our OnEnter hook. ✿ ʕ •ᴥ•ʔ
    button.UpdateTooltip = function(self)
        if self.itemInfo then
            ItemButton:OnEnter(self)
        elseif _G.ContainerFrameItemButton_OnEnter then
            _G.ContainerFrameItemButton_OnEnter(self)
        end
    end

    return button
end

function ItemButton:UpdateCooldown(button)
    if not button or not button.cooldown then return end

    local bagID = button.bagID
    local slotID = button.slotID
    if not bagID or not slotID or bagID < 0 then
        HideItemCooldown(button)
        return
    end

    local start, duration, enable = GetContainerItemCooldown(bagID, slotID)
    if not start or not duration or duration <= 0 or not enable or enable == 0 then
        HideItemCooldown(button)
        return
    end

    if button.cooldown.SetCooldown then
        button.cooldown:SetCooldown(start, duration)
        button.cooldown:Show()
    elseif CooldownFrame_SetTimer then
        CooldownFrame_SetTimer(button.cooldown, start, duration, enable)
        button.cooldown:Show()
    else
        HideItemCooldown(button)
    end
end

-- =============================================================================
-- Button Update
-- =============================================================================


function ItemButton:SetItem(button, itemInfo)
    if not button then return end

    button.itemInfo = itemInfo

    if itemInfo and itemInfo.__empty then
        local prevBagID = button.bagID
        local prevSlotID = button.slotID
        button.bagID = itemInfo.bagID
        button.slotID = itemInfo.slotID
        if itemInfo.slotID and button.SetID
                and (prevBagID ~= itemInfo.bagID or prevSlotID ~= itemInfo.slotID) then
            pcall(button.SetID, button, itemInfo.slotID)
        end

        button.icon:SetTexture(nil)
        button.count:SetText("")
        button.count:Hide()
        pcall(button.EnableMouse, button, true)
        local r, g, b = 0.3, 0.3, 0.3
        local sr, sg, sb = GetSpecialtyBagColor(itemInfo.bagID)
        if sr then
            r, g, b = sr, sg, sb
        end
        if button.borderTop then button.borderTop:SetVertexColor(r, g, b, 1) end
        if button.borderBottom then button.borderBottom:SetVertexColor(r, g, b, 1) end
        if button.borderLeft then button.borderLeft:SetVertexColor(r, g, b, 1) end
        if button.borderRight then button.borderRight:SetVertexColor(r, g, b, 1) end
        button.dimOverlay:Hide()
        UpdateEmptyDropHighlight(button)
        HideItemCooldown(button)
        if button.questStarterIcon then button.questStarterIcon:Hide() end
        button.__lastRenderKey = nil
        return
    end

    if not itemInfo then
        button.icon:SetTexture(nil)
        button.count:SetText("")
        button.count:Hide()
        pcall(button.EnableMouse, button, false)
        local grey = 0.3
        if button.borderTop then button.borderTop:SetVertexColor(grey, grey, grey, 1) end
        if button.borderBottom then button.borderBottom:SetVertexColor(grey, grey, grey, 1) end
        if button.borderLeft then button.borderLeft:SetVertexColor(grey, grey, grey, 1) end
        if button.borderRight then button.borderRight:SetVertexColor(grey, grey, grey, 1) end
        button.dimOverlay:Hide()
        UpdateEmptyDropHighlight(button)
        HideItemCooldown(button)
        if button.questStarterIcon then button.questStarterIcon:Hide() end
        button.__lastRenderKey = nil
        return
    end

    pcall(button.EnableMouse, button, true)

    local isPinned = itemInfo.itemID and Omni.Data and Omni.Data:IsPinned(itemInfo.itemID) or false
    local renderKey = button.__lastRenderKey
    local questOverlayKind
    if renderKey
            and renderKey.bagID == itemInfo.bagID
            and renderKey.slotID == itemInfo.slotID
            and renderKey.hyperlink == itemInfo.hyperlink
            and renderKey.iconFileID == itemInfo.iconFileID
            and renderKey.stackCount == itemInfo.stackCount
            and renderKey.quality == itemInfo.quality
            and renderKey.isNew == itemInfo.isNew
            and renderKey.isQuickFiltered == itemInfo.isQuickFiltered
            and renderKey.itemID == itemInfo.itemID then
        questOverlayKind = renderKey.questOverlayKind
    else
        questOverlayKind = GetQuestStarterOverlayKind(itemInfo.bagID, itemInfo.slotID)
    end
    if renderKey
            and renderKey.hyperlink == itemInfo.hyperlink
            and renderKey.iconFileID == itemInfo.iconFileID
            and renderKey.stackCount == itemInfo.stackCount
            and renderKey.quality == itemInfo.quality
            and renderKey.isNew == itemInfo.isNew
            and renderKey.isQuickFiltered == itemInfo.isQuickFiltered
            and renderKey.itemID == itemInfo.itemID
            and renderKey.bagID == itemInfo.bagID
            and renderKey.slotID == itemInfo.slotID
            and renderKey.isPinned == isPinned
            and renderKey.questOverlayKind == questOverlayKind then
        UpdateQuestStarterIcon(button, itemInfo)
        self:UpdateCooldown(button)
        return
    end

    -- Set icon
    local texture = itemInfo.iconFileID
    if texture then
        button.icon:SetTexture(texture)
    else
        button.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    local count = math.max(1, tonumber(itemInfo.stackCount) or 1)
    if count > 1 then
        button.count:SetText(tostring(count))
        button.count:Show()
    else
        button.count:SetText("")
        button.count:Hide()
    end

    -- Set quality border color
    local quality = itemInfo.quality or 1
    local r, g, b
    local sr, sg, sb = GetSpecialtyBagColor(itemInfo.bagID)
    if quality <= 1 and sr then
        r, g, b = sr, sg, sb
    else
        local color = QUALITY_COLORS[quality] or QUALITY_COLORS[1]
        r, g, b = color[1], color[2], color[3]
    end

    if button.borderTop then button.borderTop:SetVertexColor(r, g, b, 1) end
    if button.borderBottom then button.borderBottom:SetVertexColor(r, g, b, 1) end
    if button.borderLeft then button.borderLeft:SetVertexColor(r, g, b, 1) end
    if button.borderRight then button.borderRight:SetVertexColor(r, g, b, 1) end

    -- ʕ •ᴥ•ʔ✿ ContainerFrameItemButton_OnClick reads bag from
    -- self:GetParent():GetID() and slot from self:GetID(); the parenting
    -- to the bag-keyed ItemContainer (which carries SetID(bagID)) and the
    -- SetID below are what wire this button to the secure use / pickup
    -- pipeline. Both calls are protected on this client and therefore are
    -- only safe to issue out of combat -- the render path is combat-gated
    -- in UI/Frame.lua so we never reach SetItem during lockdown. ✿ ʕ •ᴥ•ʔ
    local prevBagID = button.bagID
    local prevSlotID = button.slotID
    button.bagID = itemInfo.bagID
    button.slotID = itemInfo.slotID
    -- ʕ •ᴥ•ʔ✿ SetID must track bag moves (same slot index, different bag). pcall in combat. ✿ ʕ •ᴥ•ʔ
    if itemInfo.slotID and button.SetID
            and (prevBagID ~= itemInfo.bagID or prevSlotID ~= itemInfo.slotID) then
        pcall(button.SetID, button, itemInfo.slotID)
    end

    -- Apply unusable item red overlay
    local isUnusable = false
    if not itemInfo.isQuickFiltered
            and OmniInventoryDB
            and OmniInventoryDB.global
            and OmniInventoryDB.global.enableUnusableOverlay ~= false
            and itemInfo.bagID
            and itemInfo.slotID then
        isUnusable = CheckIfItemUnusable(itemInfo.bagID, itemInfo.slotID, itemInfo.itemID)
    end

    -- Apply quick filter dimming or clear search dim
    if itemInfo.isQuickFiltered then
        button.dimOverlay:Show()
        button.icon:SetDesaturated(true)
        button.icon:SetAlpha(0.4)
        button.icon:SetVertexColor(1, 1, 1)
    else
        button.dimOverlay:Hide()
        button.icon:SetDesaturated(false)
        button.icon:SetAlpha(1)
        if isUnusable then
            button.icon:SetVertexColor(1, 0.1, 0.1)
        else
            button.icon:SetVertexColor(1, 1, 1)
        end
    end
    UpdateEmptyDropHighlight(button)

    -- Show pin icon if item is pinned
    if isPinned then
        button.pinIcon:Show()
    else
        button.pinIcon:Hide()
    end

    UpdateQuestStarterIcon(button, itemInfo)
    self:UpdateCooldown(button)

    button.__lastRenderKey = {
        hyperlink = itemInfo.hyperlink,
        iconFileID = itemInfo.iconFileID,
        stackCount = itemInfo.stackCount,
        quality = itemInfo.quality,
        isNew = itemInfo.isNew,
        isQuickFiltered = itemInfo.isQuickFiltered,
        itemID = itemInfo.itemID,
        bagID = itemInfo.bagID,
        slotID = itemInfo.slotID,
        isPinned = isPinned,
        questOverlayKind = questOverlayKind,
    }
end

-- =============================================================================
-- Search Highlighting
-- =============================================================================

function ItemButton:SetSearchMatch(button, isMatch)
    if not button then return end

    if isMatch then
        button.dimOverlay:Hide()
        button.icon:SetDesaturated(false)
        button.icon:SetAlpha(1)
    else
        button.dimOverlay:Show()
        button.icon:SetDesaturated(true)
        button.icon:SetAlpha(0.5)
    end
end

function ItemButton:ClearSearch(button)
    if not button then return end

    button.dimOverlay:Hide()
    button.icon:SetDesaturated(false)
    button.icon:SetAlpha(1)
end

-- =============================================================================
-- Event Handlers
-- =============================================================================

-- ʕ •ᴥ•ʔ✿ Kept as a no-op so any leftover callers (eg. saved-variables
-- migration paths, the bank renderer) don't blow up. The template's
-- built-in OnClick is the secure path now. ✿ ʕ •ᴥ•ʔ
ConfigureSecureItemUse = function(button)
    if not button then return end
    button.secureUseConfigured = true
end

local function QueueOptimisticFlowRefresh(button, waitForCursorClear)
    if not button or not Omni.Frame or not Omni.Frame.RequestOptimisticFlowRefresh then
        return
    end

    local bagID = button.bagID
    local slotID = button.slotID
    if not bagID or not slotID or bagID < 0 or bagID > 4 or slotID < 1 then
        button.__omniActionStateKey = nil
        return
    end

    Omni.Frame:RequestOptimisticFlowRefresh(bagID, slotID, {
        stateKey = button.__omniActionStateKey,
        waitForCursorClear = waitForCursorClear == true,
    })
    button.__omniActionStateKey = nil
end

function ItemButton:OnMouseDown(button)
    if not button or not button.itemInfo or not Omni.Frame or not Omni.Frame.SnapshotBagSlotState then
        return
    end

    local bagID = button.bagID
    local slotID = button.slotID
    if not bagID or not slotID or bagID < 0 or bagID > 4 or slotID < 1 then
        button.__omniActionStateKey = nil
        return
    end

    button.__omniActionStateKey = Omni.Frame:SnapshotBagSlotState(bagID, slotID)
end

function ItemButton:OnPreClick() end

-- ʕ •ᴥ•ʔ✿ ContainerFrameItemButtonTemplate's XML OnClick already invokes
-- ContainerFrameItemButton_OnClick which handles use / pickup / equip /
-- shift-link / ctrl-dressup / split / right-click-use, all on Blizzard's
-- whitelisted secure path that works in combat. This hook only adds the
-- OmniInventory-specific extras: shift+rclick to toggle pin and the
-- isNew bookkeeping. We never PickupContainerItem ourselves so we don't
-- double-handle and don't trigger combat lockdown from insecure code. ✿ ʕ •ᴥ•ʔ
function ItemButton:OnClick(button, mouseButton)
    if not button then return end

    mouseButton = NormalizeMouseButton(mouseButton) or mouseButton

    if mouseButton == "RightButton" and IsShiftKeyDown()
            and button.itemInfo and button.itemInfo.itemID then
        local isPinned = Omni.Data and Omni.Data:TogglePin(button.itemInfo.itemID)
        if isPinned then
            if button.pinIcon then button.pinIcon:Show() end
            print("|cFF00FF00Omni|r: Item pinned!")
        else
            if button.pinIcon then button.pinIcon:Hide() end
            print("|cFF00FF00Omni|r: Item unpinned.")
        end
        if Omni.Frame and not (InCombatLockdown and InCombatLockdown()) then
            Omni.Frame:UpdateLayout()
        end
        if Omni.BankFrame and Omni.BankFrame.UpdateLayout
                and not (InCombatLockdown and InCombatLockdown()) then
            Omni.BankFrame:UpdateLayout()
        end
        button.__omniActionStateKey = nil
        return
    end

    if button.itemInfo and button.itemInfo.isNew then
        button.itemInfo.isNew = false
        if Omni.Categorizer and button.itemInfo.itemID then
            Omni.Categorizer:ClearNewItem(button.itemInfo.itemID)
        end
    end

    QueueOptimisticFlowRefresh(button, CursorHasItem and CursorHasItem())
    UpdateEmptyDropHighlight(button)
end

function ItemButton:OnEnter(button)
    if not button or not button.itemInfo then return end

    button.__omniUsesCustomTooltip = true
    local info = button.itemInfo
    local bagID, slotID = info.bagID, info.slotID

    ItemButton.SetOmniItemTooltipOwner(button)
    if GameTooltip.ClearLines then
        GameTooltip:ClearLines()
    end

    local shown = false
    if IsLiveContainerFrameSlot(bagID, slotID) and slotID then
        GameTooltip:SetBagItem(bagID, slotID)
        if GameTooltip.NumLines then
            shown = GameTooltip:NumLines() > 0
        else
            shown = true
        end
    end

    if not shown and info.hyperlink then
        GameTooltip:SetHyperlink(info.hyperlink)
        if not IsLiveContainerFrameSlot(bagID, slotID) then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Bank Item (Offline)", 0.5, 0.5, 0.5)
        end
    end

    GameTooltip:Show()
    ItemButton.FinalizeOmniItemTooltipLayout()
    UpdateTooltipCompareState()

    if Omni.Frame and Omni.Frame.HighlightItem then
        Omni.Frame:HighlightItem(info)
    end

    button.__emptyDropHighlightHovering = true
    UpdateEmptyDropHighlight(button)
end

function ItemButton:OnLeave(button)
    button.__emptyDropHighlightHovering = false
    if button.emptyDropHighlight then
        button.emptyDropHighlight:Hide()
    end

    button.__omniUsesCustomTooltip = false
    ItemButton.HideTooltipIfOwnedBy(button)
    if ResetCursor then
        ResetCursor()
    end
end

function ItemButton:RefreshCompareTooltips()
    UpdateTooltipCompareState()
end

-- ʕ •ᴥ•ʔ✿ ContainerFrameItemButtonTemplate already handles OnDragStart and
-- OnReceiveDrag through its built-in scripts (PickupContainerItem on the
-- template's own bag/slot resolution). Our hooks would double-pickup and
-- swap the item with whatever the cursor still carries -- so they no-op. ✿ ʕ •ᴥ•ʔ
function ItemButton:OnDragStart(button)
    QueueOptimisticFlowRefresh(button, true)
end
function ItemButton:OnReceiveDrag() end

-- =============================================================================
-- Reset (for pool release)
-- =============================================================================

function ItemButton:Reset(button)
    if not button then return end

    button.itemInfo = nil
    button.__lastRenderKey = nil
    button.__omniActionStateKey = nil
    button.__omniUsesCustomTooltip = nil
    button.__emptyDropHighlightHovering = false
    button.bagID = nil
    button.slotID = nil
    if button.icon then button.icon:SetTexture(nil) end
    if button.count then
        button.count:SetText("")
        button.count:Hide()
    end

    local grey = 0.3
    if button.borderTop then button.borderTop:SetVertexColor(grey, grey, grey, 1) end
    if button.borderBottom then button.borderBottom:SetVertexColor(grey, grey, grey, 1) end
    if button.borderLeft then button.borderLeft:SetVertexColor(grey, grey, grey, 1) end
    if button.borderRight then button.borderRight:SetVertexColor(grey, grey, grey, 1) end

    if button.dimOverlay then button.dimOverlay:Hide() end
    if button.pinIcon then button.pinIcon:Hide() end
    if button.emptyDropHighlight then button.emptyDropHighlight:Hide() end
    HideItemCooldown(button)
    if button.icon then
        button.icon:SetDesaturated(false)
        button.icon:SetAlpha(1)
        button.icon:SetVertexColor(1, 1, 1)
    end

    pcall(button.Hide, button)
end

-- ʕ •ᴥ•ʔ✿ Blizzard refreshes bag/guild/hyperlink tooltips on a timer and re-anchors;
-- post-hook re-applies fixed screen-corner UIParent offset without a per-frame loop. ✿ ʕ •ᴥ•ʔ
local function RegisterOmniFixedTooltipReanchorHooks()
    if Omni._omniFixedTooltipReanchorHooks then
        return
    end
    if not (GameTooltip and hooksecurefunc) then
        return
    end
    Omni._omniFixedTooltipReanchorHooks = true
    hooksecurefunc(GameTooltip, "SetBagItem", function()
        ItemButton.FinalizeOmniItemTooltipLayout()
    end)
    hooksecurefunc(GameTooltip, "SetHyperlink", function()
        ItemButton.FinalizeOmniItemTooltipLayout()
    end)
    hooksecurefunc(GameTooltip, "SetGuildBankItem", function()
        ItemButton.FinalizeOmniItemTooltipLayout()
    end)
end

RegisterOmniFixedTooltipReanchorHooks()

print("|cFF00FF00OmniInventory|r: ItemButton loaded")
