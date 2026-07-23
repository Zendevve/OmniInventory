-- =============================================================================
-- OmniInventory Core/Compatibility.lua
-- WoW 3.3.5a C-API Fallback Wrappers & Taint Protection Safeguards
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or _G.OmniInventory or _G.Omni

local Compat = {}
Omni.Compat = Compat

-- 1. GetContainerNumSlots Wrapper
-- Returns total slots for container bagID (0-4 for bags, -1 for bank, 5-11 for bank bags, -2 for keyring)
Compat.GetContainerNumSlots = function(bagID)
    if GetContainerNumSlots then
        return GetContainerNumSlots(bagID) or 0
    end
    return 0
end
Compat.GetNumSlots = Compat.GetContainerNumSlots

-- 2. GetContainerItemInfo Wrapper
-- Returns texture, count, locked, quality, readable, lootable, link, isFiltered
Compat.GetContainerItemInfo = function(bagID, slotID)
    if GetContainerItemInfo then
        local texture, count, locked, quality, readable, lootable, link, isFiltered = GetContainerItemInfo(bagID, slotID)
        return texture, (count or 0), (locked or false), (quality or -1), (readable or false), (lootable or false), link, isFiltered
    end
    return nil, 0, false, -1, false, false, nil, false
end
Compat.GetItemInfo = Compat.GetContainerItemInfo

-- 3. InCombatLockdown Safeguard
-- Returns true if player is currently in combat lockdown
Compat.InCombatLockdown = function()
    if InCombatLockdown then
        return InCombatLockdown() or false
    end
    return false
end
Compat.IsCombat = Compat.InCombatLockdown

-- 4. GetEquipmentSetLocations Wrapper
-- Native to WoW 3.3.5a (Equipment Manager API)
Compat.GetEquipmentSetLocations = function(setName)
    if GetEquipmentSetLocations then
        return GetEquipmentSetLocations(setName)
    end
    return nil
end
Compat.GetEquipmentSets = Compat.GetEquipmentSetLocations

-- 5. Safe Item Info Retrieval
Compat.GetItemInfoInstant = function(item)
    if not item then return nil end
    if GetItemInfoInstant then
        return GetItemInfoInstant(item)
    elseif GetItemInfo then
        local itemID, itemType, itemSubType, itemEquipLoc, icon, itemClassID, itemSubClassID = GetItemInfo(item)
        return itemID, itemType, itemSubType, itemEquipLoc, icon, itemClassID, itemSubClassID
    end
    return nil
end

-- 6. Safe Container Free Slots Wrapper
Compat.GetContainerNumFreeSlots = function(bagID)
    if GetContainerNumFreeSlots then
        return GetContainerNumFreeSlots(bagID)
    end
    local numSlots = Compat.GetContainerNumSlots(bagID)
    if numSlots == 0 then return 0, 0 end
    local free = 0
    for slot = 1, numSlots do
        local texture = Compat.GetContainerItemInfo(bagID, slot)
        if not texture then
            free = free + 1
        end
    end
    return free, 0
end
