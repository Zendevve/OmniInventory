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

local QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 },  -- Poor (Grey)
    [1] = { 1.00, 1.00, 1.00 },  -- Common (White)
    [2] = { 0.12, 1.00, 0.00 },  -- Uncommon (Green)
    [3] = { 0.00, 0.44, 0.87 },  -- Rare (Blue)
    [4] = { 0.64, 0.21, 0.93 },  -- Epic (Purple)
    [5] = { 1.00, 0.50, 0.00 },  -- Legendary (Orange)
    [6] = { 0.90, 0.80, 0.50 },  -- Artifact (Light Gold)
    [7] = { 0.00, 0.80, 1.00 },  -- Heirloom (Light Blue)
}

-- =============================================================================
-- Button Creation
-- =============================================================================

local buttonCount = 0

function ItemButton:Create(parent)
    buttonCount = buttonCount + 1
    local name = "OmniItemButton" .. buttonCount

    -- Create using ItemButtonTemplate for proper behavior
    local button = CreateFrame("Button", name, parent, "ItemButtonTemplate")
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)

    -- Get standard template elements
    button.icon = _G[name .. "IconTexture"] or button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("CENTER")
    button.icon:SetSize(ICON_SIZE, ICON_SIZE)

    button.count = _G[name .. "Count"] or button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)

    -- Quality border frame
    button.border = CreateFrame("Frame", nil, button)
    button.border:SetPoint("TOPLEFT", -BORDER_SIZE, BORDER_SIZE)
    button.border:SetPoint("BOTTOMRIGHT", BORDER_SIZE, -BORDER_SIZE)
    button.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = BORDER_SIZE,
    })
    button.border:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    button.border:SetFrameLevel(button:GetFrameLevel() + 1)

    -- New item glow
    button.glow = button:CreateTexture(nil, "OVERLAY")
    button.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    button.glow:SetBlendMode("ADD")
    button.glow:SetPoint("CENTER")
    button.glow:SetSize(BUTTON_SIZE * 1.5, BUTTON_SIZE * 1.5)
    button.glow:Hide()

    -- Search dim overlay
    button.dimOverlay = button:CreateTexture(nil, "OVERLAY")
    button.dimOverlay:SetAllPoints()
    button.dimOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.dimOverlay:SetVertexColor(0, 0, 0, 0.7)
    button.dimOverlay:Hide()

    -- Store item info reference
    button.itemInfo = nil

    -- Click handlers
    button:SetScript("OnClick", function(self, mouseButton)
        ItemButton:OnClick(self, mouseButton)
    end)

    button:SetScript("OnEnter", function(self)
        ItemButton:OnEnter(self)
    end)

    button:SetScript("OnLeave", function(self)
        ItemButton:OnLeave(self)
    end)

    -- Drag handlers
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        ItemButton:OnDragStart(self)
    end)

    button:SetScript("OnReceiveDrag", function(self)
        ItemButton:OnReceiveDrag(self)
    end)

    return button
end

-- =============================================================================
-- Button Update
-- =============================================================================

function ItemButton:SetItem(button, itemInfo)
    if not button then return end

    button.itemInfo = itemInfo

    if not itemInfo then
        -- Empty slot
        button.icon:SetTexture(nil)
        button.count:SetText("")
        button.border:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        button.glow:Hide()
        button.dimOverlay:Hide()
        button:SetID(0)
        return
    end

    -- Set icon
    local texture = itemInfo.iconFileID
    if texture then
        button.icon:SetTexture(texture)
    else
        button.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Set count
    local count = itemInfo.stackCount or 1
    if count > 1 then
        button.count:SetText(count)
    else
        button.count:SetText("")
    end

    -- Set quality border
    local quality = itemInfo.quality or 1
    local color = QUALITY_COLORS[quality] or QUALITY_COLORS[1]
    button.border:SetBackdropBorderColor(color[1], color[2], color[3], 1)

    -- Store bag/slot for container operations
    button:SetID(itemInfo.slotID or 0)
    button.bagID = itemInfo.bagID
    button.slotID = itemInfo.slotID

    -- New item glow (optional)
    if itemInfo.isNew then
        button.glow:Show()
    else
        button.glow:Hide()
    end

    -- Clear search dim
    button.dimOverlay:Hide()
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

function ItemButton:OnClick(button, mouseButton)
    if not button or not button.itemInfo then return end

    local bagID = button.bagID
    local slotID = button.slotID

    if not bagID or not slotID then return end

    if mouseButton == "LeftButton" then
        if IsModifiedClick("PICKUPACTION") then
            -- Pickup item
            PickupContainerItem(bagID, slotID)
        elseif IsModifiedClick("SPLITSTACK") then
            -- Split stack
            local _, count = GetContainerItemInfo(bagID, slotID)
            if count and count > 1 then
                OpenStackSplitFrame(count, button, "BOTTOMRIGHT", "TOPRIGHT")
            end
        else
            -- Use item
            UseContainerItem(bagID, slotID)
        end
    elseif mouseButton == "RightButton" then
        -- Use item (right-click)
        UseContainerItem(bagID, slotID)
    end
end

function ItemButton:OnEnter(button)
    if not button or not button.itemInfo then return end

    local bagID = button.bagID
    local slotID = button.slotID

    if bagID and slotID then
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(bagID, slotID)
        GameTooltip:Show()

        -- Highlight in search
        if Omni.Frame and Omni.Frame.HighlightItem then
            Omni.Frame:HighlightItem(button.itemInfo)
        end
    end
end

function ItemButton:OnLeave(button)
    GameTooltip:Hide()
end

function ItemButton:OnDragStart(button)
    if not button then return end

    local bagID = button.bagID
    local slotID = button.slotID

    if bagID and slotID then
        PickupContainerItem(bagID, slotID)
    end
end

function ItemButton:OnReceiveDrag(button)
    if not button then return end

    local bagID = button.bagID
    local slotID = button.slotID

    if bagID and slotID then
        PickupContainerItem(bagID, slotID)
    end
end

-- =============================================================================
-- Reset (for pool release)
-- =============================================================================

function ItemButton:Reset(button)
    if not button then return end

    button.itemInfo = nil
    button.bagID = nil
    button.slotID = nil
    button.icon:SetTexture(nil)
    button.count:SetText("")
    button.border:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    button.glow:Hide()
    button.dimOverlay:Hide()
    button.icon:SetDesaturated(false)
    button.icon:SetAlpha(1)
    button:Hide()
end

print("|cFF00FF00OmniInventory|r: ItemButton loaded")
