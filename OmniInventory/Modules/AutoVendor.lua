-- =============================================================================
-- OmniInventory AutoVendor Module
-- =============================================================================
-- Purpose: Auto-sells gray/junk items with adaptive delay and undo buyback buffer
-- WoTLK 3.3.5a Compatible - Uses only native APIs
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or {}

local AutoVendor = {
    buybackBuffer = {}, -- 12-item undo buyback buffer
    sellQueue = {},
    isSelling = false,
    enabled = true,
    customJunk = {}, -- itemIDs of custom junk items
}
Omni.AutoVendor = AutoVendor

local frame = CreateFrame("Frame", "OmniAutoVendorFrame")

-- Merchant Header Undo Button
local undoButton = nil

local function CreateUndoButton()
    if undoButton then return undoButton end
    if not MerchantFrame then return nil end

    undoButton = CreateFrame("Button", "OmniVendorUndoButton", MerchantFrame, "UIPanelButtonTemplate")
    undoButton:SetSize(120, 20)
    undoButton:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -40, -38)
    undoButton:SetText("[Undo Buyback]")

    undoButton:SetScript("OnClick", function(self)
        AutoVendor:UndoBuyback()
    end)

    undoButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("OmniInventory Buyback Buffer")
        GameTooltip:AddLine("Click to re-purchase recent auto-sold items.", 1, 1, 1)
        if #AutoVendor.buybackBuffer > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format("Items in buffer: %d/12", #AutoVendor.buybackBuffer), 0.7, 0.7, 0.7)
            for i, item in ipairs(AutoVendor.buybackBuffer) do
                GameTooltip:AddLine(string.format("- %s (x%d)", item.link or item.name or "Item", item.count or 1), 1, 1, 1)
            end
        end
        GameTooltip:Show()
    end)

    undoButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    return undoButton
end

local function UpdateUndoButtonState()
    if not undoButton then
        CreateUndoButton()
    end
    if undoButton then
        local count = #AutoVendor.buybackBuffer
        local merchantBuybackCount = GetNumBuybackItems and GetNumBuybackItems() or 0
        if count > 0 and merchantBuybackCount > 0 then
            undoButton:Enable()
            undoButton:SetText(string.format("[Undo Buyback] (%d)", count))
        else
            undoButton:Disable()
            undoButton:SetText("[Undo Buyback]")
        end
    end
end

function AutoVendor:IsJunk(bag, slot, itemID, quality, price)
    if not itemID or (price and price <= 0) then return false end
    -- Check custom junk list
    if self.customJunk[itemID] then
        return true
    end
    -- Check Gray quality (0)
    if quality == 0 then
        return true
    end
    return false
end

function AutoVendor:BuildSellQueue()
    self.sellQueue = {}
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local texture, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bag, slot)
            if link and not locked then
                local itemID = tonumber(link:match("item:(%d+)"))
                local name, _, _, _, _, _, _, _, _, _, price = GetItemInfo(link)
                price = price or 0

                -- Check MerchantOverlay sell protection guard rails
                local isProtected = false
                if Omni.MerchantOverlay and Omni.MerchantOverlay.IsProtected then
                    isProtected = Omni.MerchantOverlay:IsProtected(bag, slot, link, quality)
                elseif quality and quality >= 3 then
                    -- Protection fallback for Rare/Epic
                    isProtected = true
                end

                if not isProtected and self:IsJunk(bag, slot, itemID, quality, price) then
                    table.insert(self.sellQueue, {
                        bag = bag,
                        slot = slot,
                        itemID = itemID,
                        name = name or "Junk Item",
                        link = link,
                        count = count or 1,
                        price = price,
                    })
                end
            end
        end
    end
end

function AutoVendor:ProcessNextSell()
    if not MerchantFrame or not MerchantFrame:IsShown() then
        self.isSelling = false
        self.sellQueue = {}
        return
    end

    if #self.sellQueue == 0 then
        self.isSelling = false
        UpdateUndoButtonState()
        return
    end

    local item = table.remove(self.sellQueue, 1)
    -- Re-verify slot content and lock state
    local _, count, locked, _, _, _, link = GetContainerItemInfo(item.bag, item.slot)
    if link and not locked then
        -- Record into buyback buffer before selling
        table.insert(self.buybackBuffer, {
            itemID = item.itemID,
            name = item.name,
            link = item.link,
            count = count or item.count,
            price = item.price,
            time = GetTime(),
        })
        -- Enforce 12-item buffer limit
        while #self.buybackBuffer > 12 do
            table.remove(self.buybackBuffer, 1)
        end

        UseContainerItem(item.bag, item.slot)
        self.isSelling = true
    else
        -- If slot was locked or empty, proceed to next
        self:ProcessNextSell()
    end
end

function AutoVendor:UndoBuyback()
    if #self.buybackBuffer == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("[!] OmniInventory: No items in buyback buffer.")
        return
    end

    local merchantBuybackCount = GetNumBuybackItems and GetNumBuybackItems() or 0
    if merchantBuybackCount <= 0 then
        DEFAULT_CHAT_FRAME:AddMessage("[!] OmniInventory: Merchant buyback window is empty.")
        self.buybackBuffer = {}
        UpdateUndoButtonState()
        return
    end

    -- Re-purchase last item in buyback buffer
    local lastItem = table.remove(self.buybackBuffer)
    -- Call WoW BuybackItem(index) - index merchantBuybackCount
    BuybackItem(merchantBuybackCount)

    local msg = string.format("[OK] Restored sold item from buyback: %s", lastItem.link or lastItem.name or "Item")
    DEFAULT_CHAT_FRAME:AddMessage(msg)
    UpdateUndoButtonState()
end

function AutoVendor:OnMerchantShow()
    if not self.enabled then return end
    CreateUndoButton()
    UpdateUndoButtonState()

    self:BuildSellQueue()
    if #self.sellQueue > 0 then
        self:ProcessNextSell()
    end
end

function AutoVendor:OnItemLockChanged()
    if self.isSelling then
        -- Adaptive delay synced with lock state change to prevent opcode drops
        self:ProcessNextSell()
    end
end

frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")
frame:RegisterEvent("ITEM_LOCK_CHANGED")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "MERCHANT_SHOW" then
        AutoVendor:OnMerchantShow()
    elseif event == "MERCHANT_CLOSED" then
        AutoVendor.isSelling = false
        AutoVendor.sellQueue = {}
    elseif event == "ITEM_LOCK_CHANGED" then
        AutoVendor:OnItemLockChanged()
    end
end)
