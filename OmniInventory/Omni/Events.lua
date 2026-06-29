-- =============================================================================
-- OmniInventory Event Bucketing System
-- =============================================================================
-- Purpose: Coalesce rapid BAG_UPDATE events into single UI refresh
-- Prevents frame drops when looting multiple items at once
-- =============================================================================

local addonName, Omni = ...

Omni.Events = {}
local Events = Omni.Events

-- =============================================================================
-- Configuration
-- =============================================================================

local BUCKET_DELAY = 0.05  -- 50ms window for coalescing events
local BAG_UPDATE_CHUNK_SIZE = 2
local BAG_UPDATE_CHUNK_TICK = 0.02

-- =============================================================================
-- State
-- =============================================================================

local buckets = {}  -- { eventName = { timer, callback, payload } }
local eventFrame = CreateFrame("Frame")
local bagUpdateChunkFrame = nil
local bagUpdateChunkQueue = nil

local bagSlotContents = {}
local newItems = {}
local hasDoneInitialScan = false

Omni.NewItems = newItems

local function StopBagUpdateChunking()
    if bagUpdateChunkFrame then
        bagUpdateChunkFrame:SetScript("OnUpdate", nil)
    end
    bagUpdateChunkQueue = nil
end

local function StartBagUpdateChunking(modifiedBags)
    local bagIDs = {}
    for bagID in pairs(modifiedBags or {}) do
        if type(bagID) == "number" and bagID >= 0 and bagID <= 4 then
            bagIDs[#bagIDs + 1] = bagID
        end
    end
    if #bagIDs == 0 then
        return false
    end
    table.sort(bagIDs)
    bagUpdateChunkQueue = {
        bagIDs = bagIDs,
        idx = 1,
        elapsed = 0,
    }
    bagUpdateChunkFrame = bagUpdateChunkFrame or CreateFrame("Frame")
    bagUpdateChunkFrame:SetScript("OnUpdate", function(self, elapsed)
        if not bagUpdateChunkQueue then
            self:SetScript("OnUpdate", nil)
            return
        end
        bagUpdateChunkQueue.elapsed = (bagUpdateChunkQueue.elapsed or 0) + (elapsed or 0)
        if bagUpdateChunkQueue.elapsed < BAG_UPDATE_CHUNK_TICK then
            return
        end
        bagUpdateChunkQueue.elapsed = 0
        local chunk = {}
        local endIdx = math.min(
            bagUpdateChunkQueue.idx + BAG_UPDATE_CHUNK_SIZE - 1,
            #bagUpdateChunkQueue.bagIDs
        )
        for i = bagUpdateChunkQueue.idx, endIdx do
            chunk[bagUpdateChunkQueue.bagIDs[i]] = true
        end
        bagUpdateChunkQueue.idx = endIdx + 1
        if Omni.Frame and Omni.Frame.IsShown and Omni.Frame:IsShown() and Omni.Frame.UpdateLayout then
            Omni.Frame:UpdateLayout(chunk, { reason = "bag_update_chunk" })
        end
        if bagUpdateChunkQueue.idx > #bagUpdateChunkQueue.bagIDs then
            self:SetScript("OnUpdate", nil)
            bagUpdateChunkQueue = nil
        end
    end)
    return true
end

-- =============================================================================
-- Bucket Manager
-- =============================================================================

--- Register an event with bucketing
---@param eventName string The WoW event to listen for
---@param callback function Called when bucket fires, receives aggregated payload
function Events:RegisterBucketEvent(eventName, callback)
    if buckets[eventName] then
        return -- Already registered
    end

    buckets[eventName] = {
        timer = nil,
        callback = callback,
        payload = {},
        timerFrame = CreateFrame("Frame"),
    }

    local bucket = buckets[eventName]
    bucket.timerFrame:Hide()
    bucket.timerFrame.elapsed = 0

    bucket.timerFrame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + (elapsed or 0)
        if self.elapsed >= BUCKET_DELAY then
            self:Hide()
            -- Fire the callback with accumulated payload
            local payload = bucket.payload
            bucket.payload = {}  -- Reset for next batch
            if Omni._perfEnabled and Omni.Perf then
                Omni.Perf:CountBucket(eventName, true)
            end
            bucket.callback(payload)
        end
    end)

    eventFrame:RegisterEvent(eventName)
end

--- Unregister a bucketed event
---@param eventName string
function Events:UnregisterBucketEvent(eventName)
    if not buckets[eventName] then return end

    eventFrame:UnregisterEvent(eventName)
    buckets[eventName].timerFrame:Hide()
    buckets[eventName] = nil
end

--- Direct event registration (no bucketing)
---@param eventName string
---@param callback function
function Events:RegisterEvent(eventName, callback)
    eventFrame:RegisterEvent(eventName)
    eventFrame[eventName] = callback
end

--- Unregister direct event
---@param eventName string
function Events:UnregisterEvent(eventName)
    eventFrame:UnregisterEvent(eventName)
    eventFrame[eventName] = nil
end

-- =============================================================================
-- Event Handler
-- =============================================================================

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if Omni._perfEnabled and Omni.Perf then
        Omni.Perf:CountBucket(event, false)
    end
    -- Check for bucketed events
    local bucket = buckets[event]
    if bucket then
        -- Add to payload
        local arg1 = ...
        if arg1 ~= nil then
            bucket.payload[arg1] = true  -- Use table as set for deduplication
        else
            bucket.payload["_trigger"] = true
        end

        -- Start/restart the timer
        bucket.timerFrame.elapsed = 0
        bucket.timerFrame:Show()
        return
    end

    -- Direct event handling
    if self[event] then
        self[event](...)
    end
end)

-- =============================================================================
-- Pre-registered Common Events
-- =============================================================================

--- Initialize with common bag events
function Events:Init()
    -- These are the primary events that can cause rapid updates
    -- The callback receives a table of modified bagIDs

    self:RegisterBucketEvent("BAG_UPDATE", function(modifiedBags)
        if Omni.API and Omni.API.ClearContainerBindScanCache then
            Omni.API:ClearContainerBindScanCache()
        end
        if Omni.Data and Omni.Data.SaveCharacterInventory then
            Omni.Data:SaveCharacterInventory()
        end

        -- New item detection scan
        if not hasDoneInitialScan then
            hasDoneInitialScan = true
            for bagID = 0, 4 do
                local numSlots = GetContainerNumSlots(bagID) or 0
                for slotID = 1, numSlots do
                    local link = GetContainerItemLink(bagID, slotID)
                    local itemID = link and tonumber(string.match(link, "item:(%d+)")) or nil
                    local slotKey = bagID .. "_" .. slotID
                    bagSlotContents[slotKey] = itemID
                end
            end
        else
            for bagID in pairs(modifiedBags or {}) do
                if type(bagID) == "number" and bagID >= 0 and bagID <= 4 then
                    local numSlots = GetContainerNumSlots(bagID) or 0
                    for slotID = 1, numSlots do
                        local link = GetContainerItemLink(bagID, slotID)
                        local itemID = link and tonumber(string.match(link, "item:(%d+)")) or nil
                        local slotKey = bagID .. "_" .. slotID
                        
                        local oldItemID = bagSlotContents[slotKey]
                        if itemID and oldItemID ~= nil and itemID ~= oldItemID then
                            newItems[slotKey] = true
                        elseif itemID and oldItemID == nil then
                            newItems[slotKey] = true
                        end
                        bagSlotContents[slotKey] = itemID
                    end
                end
            end
        end
        local perfToken = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("events.BAG_UPDATE.flush")
        local hasPlayerBagChange = false
        local hasBankBagChange = false
        local hasTrigger = modifiedBags and modifiedBags._trigger == true

        for bagID in pairs(modifiedBags or {}) do
            if type(bagID) == "number" then
                if bagID >= 0 and bagID <= 4 then
                    hasPlayerBagChange = true
                elseif bagID == -1 or (bagID >= 5 and bagID <= 11) then
                    hasBankBagChange = true
                end
            end
        end

        if hasTrigger then
            hasPlayerBagChange = true
            hasBankBagChange = true
        end

        -- Update the frame
        if Omni.Frame and Omni.Frame.IsShown and Omni.Frame:IsShown() and hasPlayerBagChange then
            local bagCount = 0
            for bagID in pairs(modifiedBags or {}) do
                if type(bagID) == "number" and bagID >= 0 and bagID <= 4 then
                    bagCount = bagCount + 1
                end
            end
            if bagCount > BAG_UPDATE_CHUNK_SIZE and not hasTrigger then
                StartBagUpdateChunking(modifiedBags)
            else
                StopBagUpdateChunking()
                Omni.Frame:UpdateLayout(modifiedBags, { reason = "bag_update" })
            end
        else
            StopBagUpdateChunking()
        end
        if Omni.BankFrame and Omni.BankFrame:IsShown() and hasBankBagChange then
            Omni.BankFrame:UpdateLayout()
        end
        if Omni._perfEnabled and Omni.Perf then
            local bagCount = 0
            for _ in pairs(modifiedBags or {}) do
                bagCount = bagCount + 1
            end
            Omni.Perf:End("events.BAG_UPDATE.flush", perfToken, { changedBags = bagCount })
        end
    end)

    -- ʕ •ᴥ•ʔ✿ Bank events drive the standalone BankFrame to the left ✿ ʕ •ᴥ•ʔ
    self:RegisterEvent("BANKFRAME_OPENED", function()
        if Omni.Data and Omni.Data.SaveBankItems then
            Omni.Data:SaveBankItems()
        end
        if Omni.Frame then
            Omni.Frame:Show()
        end
        if Omni.BankFrame then
            Omni.BankFrame:Show()
        end
    end)

    self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", function()
        if Omni.Data and Omni.Data.SaveBankItems then
            Omni.Data:SaveBankItems()
        end
        if Omni.BankFrame and Omni.BankFrame:IsShown() then
            Omni.BankFrame:UpdateLayout()
        end
    end)

    self:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED", function()
        if Omni.BankFrame and Omni.BankFrame:IsShown() then
            Omni.BankFrame:UpdateLayout()
        end
    end)

    self:RegisterEvent("BANKFRAME_CLOSED", function()
        if Omni.BankFrame then
            Omni.BankFrame:Hide()
        end
    end)

    -- ʕ •ᴥ•ʔ✿ Guild bank events drive the Omni.GuildBankFrame override ✿ ʕ •ᴥ•ʔ
    self:RegisterEvent("GUILDBANKFRAME_OPENED", function()
        if Omni.GuildBankFrame then
            Omni.GuildBankFrame:Show()
        end
    end)

    self:RegisterEvent("GUILDBANKFRAME_CLOSED", function()
        if Omni.GuildBankFrame then
            Omni.GuildBankFrame:Hide()
        end
    end)

    self:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED", function()
        if Omni.GuildBankFrame and Omni.GuildBankFrame:IsShown() then
            Omni.GuildBankFrame:UpdateLayout()
        end
    end)

    self:RegisterEvent("GUILDBANK_UPDATE_TABS", function()
        if Omni.GuildBankFrame and Omni.GuildBankFrame:IsShown() then
            if Omni.GuildBankFrame.QueryAllTabs then
                Omni.GuildBankFrame:QueryAllTabs()
            end
            Omni.GuildBankFrame:UpdateLayout()
        end
    end)

    self:RegisterEvent("GUILDBANK_UPDATE_MONEY", function()
        if Omni.GuildBankFrame and Omni.GuildBankFrame:IsShown() then
            Omni.GuildBankFrame:UpdateMoney()
        end
    end)

    self:RegisterEvent("GUILDBANK_UPDATE_WITHDRAWMONEY", function()
        if Omni.GuildBankFrame and Omni.GuildBankFrame:IsShown() then
            Omni.GuildBankFrame:UpdateMoney()
        end
    end)

    self:RegisterEvent("GUILDBANK_UPDATE_TEXT", function()
        if Omni.GuildBankFrame and Omni.GuildBankFrame:IsShown() then
            Omni.GuildBankFrame:UpdateInfoText()
        end
    end)

    self:RegisterEvent("GUILDBANK_ITEM_LOCK_CHANGED", function()
        if Omni.GuildBankFrame and Omni.GuildBankFrame:IsShown() then
            Omni.GuildBankFrame:UpdateLayout()
        end
    end)

    -- Player money changed
    self:RegisterEvent("PLAYER_MONEY", function()
        if Omni.Data and Omni.Data.SaveCharacterInventory then
            Omni.Data:SaveCharacterInventory()
        end
        if Omni.Frame then
            Omni.Frame:UpdateMoney()
        end
    end)

    self:RegisterEvent("MERCHANT_SHOW", function()
        if Omni.Frame and Omni.Frame.SetMerchantOpen then
            Omni.Frame:SetMerchantOpen(true)
            if Omni.Frame.IsShown and Omni.Frame:IsShown() then
                Omni.Frame:UpdateLayout(nil, { forceFull = true, reason = "vendor_transition" })
            end
        end

        -- Auto Sell Junk & Auto Repair
        local db = OmniInventoryDB and OmniInventoryDB.global
        if db then
            -- 1. Auto Sell Junk
            if db.autoSellJunk ~= false then
                local soldCount = 0
                local earnedMoney = 0
                for bagID = 0, 4 do
                    local numSlots = GetContainerNumSlots(bagID) or 0
                    for slotID = 1, numSlots do
                        local link = GetContainerItemLink(bagID, slotID)
                        if link then
                            local _, _, quality, _, _, _, _, _, _, _, price = GetItemInfo(link)
                            if quality == 0 and price and price > 0 then
                                local _, count = GetContainerItemInfo(bagID, slotID)
                                earnedMoney = earnedMoney + (price * (count or 1))
                                UseContainerItem(bagID, slotID)
                                soldCount = soldCount + 1
                            end
                        end
                    end
                end
                if soldCount > 0 and Omni.Utils and Omni.Utils.FormatMoney then
                    local formatted = Omni.Utils:FormatMoney(earnedMoney)
                    print("|cFF00FF00OmniInventory|r: Automatically sold " .. soldCount .. " junk items for " .. formatted .. ".")
                end
            end

            -- 2. Auto Repair
            if db.autoRepair == true and CanMerchantRepair() then
                local repairCost, canRepair = GetRepairAllCost()
                if canRepair and repairCost > 0 then
                    local useGuild = false
                    if db.autoRepairGuild == true and CanGuildBankRepair() then
                        local amount = GetGuildBankWithdrawMoney()
                        local guildMoney = GetGuildBankMoney()
                        if amount == -1 or amount >= repairCost then
                            if guildMoney >= repairCost then
                                useGuild = true
                            end
                        end
                    end

                    if useGuild then
                        RepairAllItems(true)
                        if Omni.Utils and Omni.Utils.FormatMoney then
                            print("|cFF00FF00OmniInventory|r: Automatically repaired items using Guild Funds for " .. Omni.Utils:FormatMoney(repairCost) .. ".")
                        end
                    elseif GetMoney() >= repairCost then
                        RepairAllItems(false)
                        if Omni.Utils and Omni.Utils.FormatMoney then
                            print("|cFF00FF00OmniInventory|r: Automatically repaired items for " .. Omni.Utils:FormatMoney(repairCost) .. ".")
                        end
                    else
                        print("|cFFFF4040OmniInventory|r: Insufficient funds for auto-repair.")
                    end
                end
            end
        end
    end)

    self:RegisterEvent("MERCHANT_CLOSED", function()
        if Omni.Frame and Omni.Frame.SetMerchantOpen then
            Omni.Frame:SetMerchantOpen(false)
            if Omni.Frame.IsShown and Omni.Frame:IsShown() then
                Omni.Frame:UpdateLayout(nil, { forceFull = true, reason = "vendor_transition" })
            end
        end
    end)

    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        -- ʕ •ᴥ•ʔ✿ Always re-render so secure attributes / positions / new
        -- items missed during combat are restored. UpdateLayout no longer
        -- requires IsShown(), so this is safe even when bags are hidden. ✿ ʕ •ᴥ•ʔ
        if Omni.Frame and Omni.Frame.UpdateLayout then
            pcall(Omni.Frame.UpdateLayout, Omni.Frame, nil, { reason = "player_regen" })
        end
        if Omni.BankFrame and Omni.BankFrame.UpdateLayout
                and Omni.BankFrame:IsShown() then
            pcall(Omni.BankFrame.UpdateLayout, Omni.BankFrame)
        end
        if Omni.GuildBankFrame and Omni.GuildBankFrame.UpdateLayout
                and Omni.GuildBankFrame:IsShown() then
            pcall(Omni.GuildBankFrame.UpdateLayout, Omni.GuildBankFrame)
        end
    end)

    -- Item info received (async data load)
    self:RegisterBucketEvent("GET_ITEM_INFO_RECEIVED", function()
        local perfToken = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("events.GET_ITEM_INFO_RECEIVED.flush")
        if Omni.Frame and Omni.Frame:IsShown() then
            -- Refresh layout to fix "Miscellaneous" items that now have data
            Omni.Frame:UpdateLayout(nil, { reason = "item_info_received" })
        end
        if Omni.BankFrame and Omni.BankFrame:IsShown() then
            Omni.BankFrame:UpdateLayout()
        end
        if Omni.GuildBankFrame and Omni.GuildBankFrame:IsShown() then
            Omni.GuildBankFrame:UpdateLayout()
        end
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("events.GET_ITEM_INFO_RECEIVED.flush", perfToken)
        end
    end)

    -- Save initial state on login
    if Omni.Data then
        if Omni.Data.SaveCharacterInventory then
            Omni.Data:SaveCharacterInventory()
        end
        if Omni.Data.SaveBankItems then
            Omni.Data:SaveBankItems()
        end
    end
end

print("|cFF00FF00OmniInventory|r: Event Bucketing system loaded")
