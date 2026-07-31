-- =============================================================================
-- OmniInventory Omni/SlotLocks.lua
-- Per-character slot locking system for inventory protection
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or _G.OmniInventory or _G.Omni

local SlotLocks = {}
Omni.SlotLocks = SlotLocks

local lockedSlots = {}

function SlotLocks:Init()
    if _G.OmniInventoryDB and _G.OmniInventoryDB.char then
        _G.OmniInventoryDB.char.lockedSlots = _G.OmniInventoryDB.char.lockedSlots or {}
        lockedSlots = _G.OmniInventoryDB.char.lockedSlots
    else
        lockedSlots = {}
    end
end

function SlotLocks:MakeKey(bagID, slotID)
    if bagID == nil or slotID == nil then return nil end
    return bagID .. "_" .. slotID
end

function SlotLocks:IsLocked(bagID, slotID)
    local key = self:MakeKey(bagID, slotID)
    return key and lockedSlots[key] == true or false
end

function SlotLocks:ToggleLock(bagID, slotID)
    local key = self:MakeKey(bagID, slotID)
    if not key then return false end

    if lockedSlots[key] then
        lockedSlots[key] = nil
        if Omni.Frame and Omni.Frame.UpdateLayout then
            Omni.Frame:UpdateLayout()
        end
        return false
    else
        lockedSlots[key] = true
        if Omni.Frame and Omni.Frame.UpdateLayout then
            Omni.Frame:UpdateLayout()
        end
        return true
    end
end

function SlotLocks:SetLocked(bagID, slotID, isLocked)
    local key = self:MakeKey(bagID, slotID)
    if not key then return end

    if isLocked then
        lockedSlots[key] = true
    else
        lockedSlots[key] = nil
    end

    if Omni.Frame and Omni.Frame.UpdateLayout then
        Omni.Frame:UpdateLayout()
    end
end

function SlotLocks:ClearAll()
    for k in pairs(lockedSlots) do
        lockedSlots[k] = nil
    end
    if Omni.Frame and Omni.Frame.UpdateLayout then
        Omni.Frame:UpdateLayout()
    end
end

return SlotLocks
