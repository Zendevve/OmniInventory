local addonName, NS = ...

NS.FrameHelpers = {}
local FrameHelpers = NS.FrameHelpers

-- Theme constants
local COLORS = {
    BORDER  = {0.00, 0.00, 0.00, 1.00},
}

-- Helper to create a 1px border around a frame
function FrameHelpers:CreateBorder(f)
    if f.border then return end
    f.border = {}

    -- Top
    f.border.t = f:CreateTexture(nil, "BORDER")
    f.border.t:SetTexture(unpack(COLORS.BORDER))
    f.border.t:SetPoint("TOPLEFT", -1, 1)
    f.border.t:SetPoint("TOPRIGHT", 1, 1)
    f.border.t:SetHeight(1)

    -- Bottom
    f.border.b = f:CreateTexture(nil, "BORDER")
    f.border.b:SetTexture(unpack(COLORS.BORDER))
    f.border.b:SetPoint("BOTTOMLEFT", -1, -1)
    f.border.b:SetPoint("BOTTOMRIGHT", 1, -1)
    f.border.b:SetHeight(1)

    -- Left
    f.border.l = f:CreateTexture(nil, "BORDER")
    f.border.l:SetTexture(unpack(COLORS.BORDER))
    f.border.l:SetPoint("TOPLEFT", -1, 1)
    f.border.l:SetPoint("BOTTOMLEFT", -1, -1)
    f.border.l:SetWidth(1)

    -- Right
    f.border.r = f:CreateTexture(nil, "BORDER")
    f.border.r:SetTexture(unpack(COLORS.BORDER))
    f.border.r:SetPoint("TOPRIGHT", 1, 1)
    f.border.r:SetPoint("BOTTOMRIGHT", 1, -1)
    f.border.r:SetWidth(1)
end

-- Create tab UI elements
function FrameHelpers:CreateTabs(parentFrame)
    local tabs = {}

    parentFrame.numTabs = 2
    parentFrame.Tabs = {}

    -- Tab 1: Inventory
    tabs.inventoryTab = CreateFrame("Button", "ZenBagsInventoryTab", parentFrame)
    tabs.inventoryTab:SetSize(100, 25)
    tabs.inventoryTab:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", 20, -25)

    tabs.inventoryTab.bg = tabs.inventoryTab:CreateTexture(nil, "BACKGROUND")
    tabs.inventoryTab.bg:SetAllPoints()
    tabs.inventoryTab.bg:SetTexture(0.12, 0.12, 0.12, 1)

    tabs.inventoryTab.text = tabs.inventoryTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tabs.inventoryTab.text:SetPoint("CENTER")
    tabs.inventoryTab.text:SetText("Inventory")

    tabs.inventoryTab.activeBorder = tabs.inventoryTab:CreateTexture(nil, "OVERLAY")
    tabs.inventoryTab.activeBorder:SetHeight(2)
    tabs.inventoryTab.activeBorder:SetPoint("BOTTOMLEFT")
    tabs.inventoryTab.activeBorder:SetPoint("BOTTOMRIGHT")
    tabs.inventoryTab.activeBorder:SetTexture(0.4, 0.6, 1.0, 1)

    tabs.inventoryTab:SetScript("OnClick", function() NS.Frames:SwitchView("bags") end)
    table.insert(parentFrame.Tabs, tabs.inventoryTab)

    -- Tab 2: Bank
    tabs.bankTab = CreateFrame("Button", "ZenBagsBankTab", parentFrame)
    tabs.bankTab:SetSize(100, 25)
    tabs.bankTab:SetPoint("LEFT", tabs.inventoryTab, "RIGHT", 2, 0)

    tabs.bankTab.bg = tabs.bankTab:CreateTexture(nil, "BACKGROUND")
    tabs.bankTab.bg:SetAllPoints()
    tabs.bankTab.bg:SetTexture(0.12, 0.12, 0.12, 1)

    tabs.bankTab.text = tabs.bankTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tabs.bankTab.text:SetPoint("CENTER")
    tabs.bankTab.text:SetText("Bank")

    tabs.bankTab.activeBorder = tabs.bankTab:CreateTexture(nil, "OVERLAY")
    tabs.bankTab.activeBorder:SetHeight(2)
    tabs.bankTab.activeBorder:SetPoint("BOTTOMLEFT")
    tabs.bankTab.activeBorder:SetPoint("BOTTOMRIGHT")
    tabs.bankTab.activeBorder:SetTexture(0.4, 0.6, 1.0, 1)

    tabs.bankTab:SetScript("OnClick", function() NS.Frames:SwitchView("bank") end)
    table.insert(parentFrame.Tabs, tabs.bankTab)

    -- Set inventory as active by default
    self:SetActiveTab(parentFrame, 1)

    -- Show bank tab if we have cached data
    if NS.Data:HasCachedBankItems() then
        tabs.bankTab:Show()
    else
        tabs.bankTab:Hide()
    end

    return tabs
end

function FrameHelpers:SetActiveTab(parentFrame, tabIndex)
    for i, tab in ipairs(parentFrame.Tabs) do
        if i == tabIndex then
            tab.bg:SetTexture(0.18, 0.18, 0.18, 1)
            tab.activeBorder:Show()
        else
            tab.bg:SetTexture(0.12, 0.12, 0.12, 1)
            tab.activeBorder:Hide()
        end
    end
end

-- Create drop-anywhere button
function FrameHelpers:CreateDropButton(contentFrame)
    local dropButton = CreateFrame("Button", nil, contentFrame)
    dropButton:SetAllPoints(contentFrame)
    dropButton:EnableMouse(true)
    dropButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    dropButton:SetScript("OnReceiveDrag", function()
        if CursorHasItem() then
            for bagID = 0, 4 do
                local numSlots = GetContainerNumSlots(bagID)
                for slotID = 1, numSlots do
                    local itemInfo = GetContainerItemInfo(bagID, slotID)
                    if not itemInfo then
                        PickupContainerItem(bagID, slotID)
                        C_Timer.After(0.1, function()
                            NS.Frames:Update()
                        end)
                        return
                    end
                end
            end
        end
    end)

    dropButton:SetScript("OnClick", function()
        if CursorHasItem() then
            for bagID = 0, 4 do
                local numSlots = GetContainerNumSlots(bagID)
                for slotID = 1, numSlots do
                    local itemInfo = GetContainerItemInfo(bagID, slotID)
                    if not itemInfo then
                        PickupContainerItem(bagID, slotID)
                        C_Timer.After(0.1, function()
                            NS.Frames:Update()
                        end)
                        return
                    end
                end
            end
        end
    end)

    return dropButton
end

-- Create dummy bag frames for tooltips
function FrameHelpers:GetOrCreateDummyBag(parentFrame, bagID)
    if not NS.Frames.dummyBags then
        NS.Frames.dummyBags = {}
    end

    if not NS.Frames.dummyBags[bagID] then
        local dummy = CreateFrame("Frame", nil, parentFrame)
        dummy:SetID(bagID)
        NS.Frames.dummyBags[bagID] = dummy
    end

    return NS.Frames.dummyBags[bagID]
end
