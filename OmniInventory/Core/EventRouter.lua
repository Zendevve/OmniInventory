-- =============================================================================
-- OmniInventory Core/EventRouter.lua
-- Event Subscription, Slot State Diffing Engine & 100ms Throttling Buckets
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or _G.OmniInventory or _G.Omni

local EventRouter = {
    slotCache = {},
    dirtySlots = {},
    callbacks = {},
}
Omni.EventRouter = EventRouter

local BUCKET_DELAY = 0.100 -- 100ms throttling bucket
local accumulator = 0
local isThrottling = false

-- Create event listener frame
local eventFrame = CreateFrame("Frame", "OmniInventoryEventFrame", UIParent)
EventRouter.frame = eventFrame

-- Create batch updater frame for OnUpdate throttling
local updaterFrame = CreateFrame("Frame", "OmniInventoryBatchUpdater", UIParent)
updaterFrame:Hide()

-- Callback Bus
function EventRouter:RegisterCallback(eventName, handler)
    if not eventName or type(handler) ~= "function" then return end
    if not self.callbacks[eventName] then
        self.callbacks[eventName] = {}
    end
    table.insert(self.callbacks[eventName], handler)
end

function EventRouter:UnregisterCallback(eventName, handler)
    if not self.callbacks[eventName] then return end
    for i, h in ipairs(self.callbacks[eventName]) do
        if h == handler then
            table.remove(self.callbacks[eventName], i)
            break
        end
    end
end

function EventRouter:TriggerCallbacks(eventName, ...)
    local list = self.callbacks[eventName]
    if list then
        for _, handler in ipairs(list) do
            handler(eventName, ...)
        end
    end
end

-- Slot key calculation supporting negative bag IDs (e.g. bank -1, keyring -2)
local function GetSlotKey(bagID, slotID)
    if bagID >= 0 then
        return (bagID * 1000) + slotID
    else
        return (math.abs(bagID) * 100000) + slotID
    end
end
EventRouter.GetSlotKey = GetSlotKey

-- Throttled Batch Update Handler
local function BatchUpdateHandler(self, elapsed)
    accumulator = accumulator + elapsed
    if accumulator >= BUCKET_DELAY then
        accumulator = 0
        self:Hide()
        isThrottling = false
        
        if next(EventRouter.dirtySlots) then
            if Omni.LayoutEngine and type(Omni.LayoutEngine.UpdateDirtySlots) == "function" then
                Omni.LayoutEngine:UpdateDirtySlots(EventRouter.dirtySlots)
            end
            EventRouter:TriggerCallbacks("ON_SLOTS_UPDATED", EventRouter.dirtySlots)
            table.wipe(EventRouter.dirtySlots)
        end
    end
end

updaterFrame:SetScript("OnUpdate", BatchUpdateHandler)

-- Process BAG_UPDATE event with slot diffing
function EventRouter:OnBagUpdate(bagID)
    if not bagID then return end
    local GetNumSlots = (Omni.Compat and Omni.Compat.GetContainerNumSlots) or GetContainerNumSlots or function() return 0 end
    local GetItemInfo = (Omni.Compat and Omni.Compat.GetContainerItemInfo) or GetContainerItemInfo or function() return nil end

    local numSlots = GetNumSlots(bagID)
    local hasChanges = false
    local diffedCount = 0

    for slotID = 1, numSlots do
        local slotKey = GetSlotKey(bagID, slotID)
        local texture, count, locked, quality, readable, lootable, link = GetItemInfo(bagID, slotID)
        
        local cached = self.slotCache[slotKey]
        if not cached or cached.link ~= link or cached.count ~= count or cached.locked ~= locked then
            self.slotCache[slotKey] = {
                link = link,
                count = count,
                locked = locked,
                texture = texture,
                quality = quality,
            }
            self.dirtySlots[slotKey] = true
            hasChanges = true
            diffedCount = diffedCount + 1
        end
    end

    if Omni.Perf and type(Omni.Perf.RecordSlotDiff) == "function" then
        Omni.Perf:RecordSlotDiff(numSlots, diffedCount)
    end

    if hasChanges then
        if not isThrottling then
            isThrottling = true
            accumulator = 0
            updaterFrame:Show()
        end
    end
end


-- Direct Event Handler Switchboard
local function OnEvent(self, event, arg1, arg2, ...)
    if event == "BAG_UPDATE" then
        EventRouter:OnBagUpdate(arg1)
    elseif event == "ITEM_LOCK_CHANGED" then
        local bagID, slotID = arg1, arg2
        if bagID and slotID then
            local slotKey = GetSlotKey(bagID, slotID)
            EventRouter.dirtySlots[slotKey] = true
            EventRouter:TriggerCallbacks("ITEM_LOCK_CHANGED", bagID, slotID)
        end
    elseif event == "BANKFRAME_OPENED" then
        EventRouter:TriggerCallbacks("BANKFRAME_OPENED")
    elseif event == "BANKFRAME_CLOSED" then
        EventRouter:TriggerCallbacks("BANKFRAME_CLOSED")
    elseif event == "MERCHANT_SHOW" then
        EventRouter:TriggerCallbacks("MERCHANT_SHOW")
    elseif event == "EQUIPMENT_SETS_CHANGED" then
        EventRouter:TriggerCallbacks("EQUIPMENT_SETS_CHANGED")
    end
end

-- Register target events
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("ITEM_LOCK_CHANGED")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("BANKFRAME_CLOSED")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
eventFrame:SetScript("OnEvent", OnEvent)
