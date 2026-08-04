-- =============================================================================
-- OmniInventory Auto-Destroy Module
-- =============================================================================
-- Purpose: Semi-automated item destruction with keybind processing.
--   - Grey junk (quality 0) auto-sells at vendors via AutoVendor
--   - Non-junk destroy items queued for keybind processing
--   - Dry-run mode logs actions without executing
-- WoTLK 3.3.5a Compatible - Uses only native APIs
-- =============================================================================

local addonName, Omni = ...

local AutoDestroy = {
    queue = {},           -- { { bag, slot, itemLink, reason, action, timestamp } }
    isProcessing = false,
    undoLog = {},         -- circular buffer of last 12 destroyed items
    maxUndoLog = 12,
}
Omni.AutoDestroy = AutoDestroy

local frame = CreateFrame("Frame", "OmniAutoDestroyFrame")

-- =============================================================================
-- Queue Management
-- =============================================================================

--- Scan bags and populate destroy queue
function AutoDestroy:ScanBags()
    self.queue = {}
    
    if not Omni.DestroyRules or not Omni.DestroyRules.IsEnabled then
        return
    end
    
    if not Omni.DestroyRules:IsEnabled() then
        return
    end
    
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, numSlots do
            local slotData = Omni.DestroyRules:BuildSlotData(bagID, slotID)
            if slotData and not slotData.locked then
                local action, reason = Omni.DestroyRules:Evaluate(slotData)
                
                if action == "destroy" then
                    if Omni.DestroyRules:IsDryRun() then
                        DEFAULT_CHAT_FRAME:AddMessage(
                            string.format("|cFFFF8800[AutoDestroy DryRun]|r Would destroy: %s (reason: %s)",
                                slotData.hyperlink or slotData.name, reason or "unknown")
                        )
                    else
                        table.insert(self.queue, {
                            bag = bagID,
                            slot = slotID,
                            link = slotData.hyperlink,
                            name = slotData.name,
                            itemID = slotData.itemID,
                            reason = reason,
                            action = action,
                            timestamp = GetTime(),
                        })
                    end
                elseif action == "sell" then
                    -- Route grey junk to AutoVendor
                    if Omni.AutoVendor and Omni.AutoVendor.BuildSellQueue then
                        -- AutoVendor handles this on MERCHANT_SHOW
                    end
                end
            end
        end
    end
    
    if #self.queue > 0 and not Omni.DestroyRules:IsDryRun() then
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cFF00FF00OmniInventory|r: %d items queued for destruction. Press your destroy keybind to process.",
                #self.queue)
        )
    end
end

--- Process next item in destroy queue (requires hardware event)
function AutoDestroy:ProcessNext()
    if #self.queue == 0 then
        self.isProcessing = false
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00OmniInventory|r: Destroy queue empty.")
        return
    end
    
    -- Combat check
    if InCombatLockdown and InCombatLockdown() then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000OmniInventory|r: Cannot destroy items in combat. Queue deferred.")
        return
    end
    
    local item = table.remove(self.queue, 1)
    
    -- Re-verify slot content
    local link = GetContainerItemLink(item.bag, item.slot)
    if not link then
        -- Slot changed, skip
        self:ProcessNext()
        return
    end
    
    local _, count, locked = GetContainerItemInfo(item.bag, item.slot)
    if locked then
        -- Item locked, skip
        self:ProcessNext()
        return
    end
    
    -- Attempt destruction via PickupContainerItem + DeleteCursorItem
    PickupContainerItem(item.bag, item.slot)
    
    if CursorHasItem and CursorHasItem() then
        DeleteCursorItem()
        
        -- Log to undo buffer
        table.insert(self.undoLog, {
            itemID = item.itemID,
            name = item.name,
            link = item.link,
            count = count or 1,
            reason = item.reason,
            timestamp = GetTime(),
        })
        while #self.undoLog > self.maxUndoLog do
            table.remove(self.undoLog, 1)
        end
        
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cFFFF4040Destroyed:|r %s x%d (reason: %s)",
                item.link or item.name, count or 1, item.reason or "rule"))
    else
        -- DeleteCursorItem failed (item has no use effect) - try vendor sell fallback
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cFFFF8800[AutoDestroy]|r %s cannot be destroyed directly. Routing to vendor sell.",
                item.link or item.name))
        
        -- Add to AutoVendor sell queue for next merchant visit
        if Omni.AutoVendor then
            Omni.AutoVendor.customJunk = Omni.AutoVendor.customJunk or {}
            if item.itemID then
                Omni.AutoVendor.customJunk[item.itemID] = true
            end
        end
    end
    
    -- Process next with delay (adaptive throttle like AutoVendor)
    if #self.queue > 0 then
        self.isProcessing = true
    end
end

--- Process entire destroy queue (called by keybind)
function AutoDestroy:ProcessQueue()
    if self.isProcessing then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000OmniInventory|r: Destroy queue already processing.")
        return
    end
    
    if #self.queue == 0 then
        self:ScanBags()
    end
    
    if #self.queue == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00OmniInventory|r: No items to destroy.")
        return
    end
    
    self.isProcessing = true
    self:ProcessNext()
end

--- Undo last destruction (shows link for manual recovery)
function AutoDestroy:UndoLast()
    if #self.undoLog == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000OmniInventory|r: No destroyed items in undo log.")
        return
    end
    
    local last = self.undoLog[#self.undoLog]
    DEFAULT_CHAT_FRAME:AddMessage(
        string.format("|cFFFF8800[AutoDestroy]|r Last destroyed: %s x%d at %s. Cannot restore automatically.",
            last.link or last.name, last.count or 1,
            date("%H:%M:%S", last.timestamp)))
end

--- Show undo log
function AutoDestroy:ShowUndoLog()
    if #self.undoLog == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00OmniInventory|r: Undo log is empty.")
        return
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFCC00AutoDestroy Undo Log:|r")
    for i, entry in ipairs(self.undoLog) do
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("  %d. %s x%d (%s) at %s",
                i, entry.link or entry.name, entry.count or 1,
                entry.reason or "unknown", date("%H:%M:%S", entry.timestamp)))
    end
end

--- Dry-run scan (logs what would be destroyed without doing anything)
function AutoDestroy:DryRun()
    local wasDryRun = Omni.DestroyRules and Omni.DestroyRules:IsDryRun()
    
    -- Temporarily enable dry-run
    if Omni.Data then
        Omni.Data:Set("destroyDryRun", true)
    end
    
    self:ScanBags()
    
    -- Restore previous dry-run state
    if Omni.Data and wasDryRun ~= nil then
        Omni.Data:Set("destroyDryRun", wasDryRun)
    end
end

-- =============================================================================
-- Event Handlers
-- =============================================================================

local function OnEvent(self, event, ...)
    if event == "BAG_UPDATE" then
        -- Re-scan bags when inventory changes
        if Omni.DestroyRules and Omni.DestroyRules.IsEnabled and Omni.DestroyRules:IsEnabled() then
            AutoDestroy:ScanBags()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Resume processing after combat ends
        if AutoDestroy.isProcessing and #AutoDestroy.queue > 0 then
            AutoDestroy:ProcessNext()
        end
    end
end

frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", OnEvent)

-- =============================================================================
-- Slash Commands
-- =============================================================================

-- Register via Core/SlashCommands.lua integration
-- /oi destroy - process destroy queue
-- /oi destroy scan - scan and show what would be destroyed
-- /oi destroy undo - show undo log
-- /oi destroy dryrun - dry-run scan
