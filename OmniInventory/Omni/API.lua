-- =============================================================================
-- OmniInventory API Abstraction Layer (The Shim)
-- =============================================================================
-- Purpose: Bridge legacy 3.3.5a APIs to modern Retail-style table returns.
-- This allows the entire codebase to use modern syntax while remaining
-- compatible with WotLK 3.3.5a client.
--
-- This module mimics the Retail `C_Container` namespace.
-- =============================================================================

local addonName, Omni = ...

Omni.API = {}
local API = Omni.API

-- =============================================================================
-- Client Detection
-- =============================================================================

local clientVersion = select(4, GetBuildInfo()) or 30300
API.isWotLK = clientVersion < 40000
API.isRetail = clientVersion >= 100000

-- =============================================================================
-- ᵔᴥᵔ Polyfill: Tooltip Scanner ᵔᴥᵔ
-- =============================================================================

local scanningTooltip = CreateFrame("GameTooltip", "OmniScanningTooltip", nil, "GameTooltipTemplate")
scanningTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local bindScanCache = {}

function API:ClearContainerBindScanCache()
    wipe(bindScanCache)
end

local SOULBOUND_TEXT = ITEM_SOULBOUND or "Soulbound"
local BOE_TEXT = ITEM_BIND_ON_EQUIP or "Binds when equipped"
local BOP_TEXT = ITEM_BIND_ON_PICKUP or "Binds when picked up"
local BOA_TEXT = ITEM_BIND_TO_ACCOUNT or "Binds to account"
local BOA_BNET_TEXT = ITEM_BIND_TO_BNETACCOUNT or "Binds to Battle.net account"

local function ScanTooltipForBinding(bag, slot, resolvedLink)
    local link = resolvedLink or GetContainerItemLink(bag, slot)
    local cacheKey = link and (tostring(bag) .. "\031" .. tostring(slot) .. "\031" .. link)
    if cacheKey then
        local cached = bindScanCache[cacheKey]
        if cached then
            return cached[1], cached[2]
        end
    end

    local boundResult, typeResult = false, "BoE"
    if link then
        local _, _, quality = GetItemInfo(link)
        if quality == 7 then
            boundResult, typeResult = true, "BoA"
            if cacheKey then
                bindScanCache[cacheKey] = { boundResult, typeResult }
            end
            return boundResult, typeResult
        end
    end

    scanningTooltip:ClearLines()
    scanningTooltip:SetBagItem(bag, slot)

    for i = 2, math.min(5, scanningTooltip:NumLines()) do
        local textFrame = _G["OmniScanningTooltipTextLeft" .. i]
        if textFrame then
            local line = textFrame:GetText()
            if line then
                if line == SOULBOUND_TEXT or line == BOP_TEXT then
                    boundResult, typeResult = true, "BoP"
                    break
                elseif line == BOA_TEXT or line == BOA_BNET_TEXT then
                    boundResult, typeResult = true, "BoA"
                    break
                elseif line == BOE_TEXT then
                    boundResult, typeResult = false, "BoE"
                    break
                end
            end
        end
    end

    if cacheKey then
        bindScanCache[cacheKey] = { boundResult, typeResult }
    end
    return boundResult, typeResult
end

--- Tooltip scan on an item hyperlink (guild bank, inspect, etc.).
---@param itemLink string
---@return boolean isBound
---@return string bindType "BoP" | "BoE"
function API:GetBindingFromHyperlink(itemLink)
    if not itemLink then return true, "BoP" end

    local _, _, quality = GetItemInfo(itemLink)
    if quality == 7 then
        return true, "BoA"
    end

    scanningTooltip:ClearLines()
    scanningTooltip:SetHyperlink(itemLink)

    for i = 2, math.min(8, scanningTooltip:NumLines()) do
        local textFrame = _G["OmniScanningTooltipTextLeft" .. i]
        if textFrame then
            local line = textFrame:GetText()
            if line then
                if line == SOULBOUND_TEXT or line == BOP_TEXT then
                    return true, "BoP"
                elseif line == BOA_TEXT or line == BOA_BNET_TEXT then
                    return true, "BoA"
                elseif line == BOE_TEXT then
                    return false, "BoE"
                end
            end
        end
    end

    return false, "BoE"
end

-- =============================================================================
-- ＼ʕ •ᴥ•ʔ／ API Wrappers ＼ʕ •ᴥ•ʔ／
-- =============================================================================

--- Check whether the item in (bagID, slotID) is Soulbound.
---@param bagID number
---@param slotID number
---@return boolean isBound
function API:IsItemSoulbound(bagID, slotID)
    local bound = ScanTooltipForBinding(bagID, slotID)
    return bound
end

--- Check whether the item in (bagID, slotID) is referenced by any equipment
--- manager set. Returns nil so the caller can fall back to the slow GetEquipmentSetItemIDs iteration.
---@param bagID number
---@param slotID number
---@return boolean|nil inSet
function API:IsItemInEquipmentSet(bagID, slotID)
    return nil
end

--- Replacement for GetContainerItemLink.
---@param bagID number
---@param slotID number
---@return string|nil link
function API:GetItemLinkBySlot(bagID, slotID)
    return GetContainerItemLink(bagID, slotID)
end

--- Parse any WoW hyperlink (item, spell, achievement, etc.) into (id, typeID).
---@param link string
---@return number|nil id
---@return number|nil typeID  1 = item
function API:GetIdFromLink(link)
    if not link then return nil end
    local itemID = tonumber(string.match(link, "item:(%d+)"))
    if itemID then
        return itemID, 1
    end
    return nil
end

-- =============================================================================
-- Namespace: OmniC_Container (C_Container Polyfill)
-- =============================================================================
-- Provides a modern, table-based API for item data.

OmniC_Container = {}

--- Get container item info in modern table format.
--- Replaces `GetContainerItemInfo` (returns 9 values) with a single table.
---@param bagID number
---@param slotID number
---@return table|nil info Item info structure or nil if slot is empty
function OmniC_Container.GetContainerItemInfo(bagID, slotID)
    local texture, itemCount, locked, quality, readable, lootable, itemLink = GetContainerItemInfo(bagID, slotID)

    if not texture then
        return nil
    end

    if not itemLink then
        itemLink = API:GetItemLinkBySlot(bagID, slotID)
    end

    local itemID
    if itemLink then
        itemID = API:GetIdFromLink(itemLink)
    end

    local isBound, bindType = ScanTooltipForBinding(bagID, slotID, itemLink)

    -- GetContainerItemInfo often returns -1/nil for quality in 3.3.5a
    if (not quality or quality < 0) and itemLink then
        local _, _, itemQuality = GetItemInfo(itemLink)
        quality = itemQuality
    end

    -- Return modern table structure (Matches Retail C_Container.GetContainerItemInfo)
    return {
        -- Core Identification
        iconFileID = texture,
        itemID = itemID,
        hyperlink = itemLink,

        -- Stack Info
        stackCount = math.max(1, tonumber(itemCount) or 1),

        -- State Flags
        isLocked = locked or false,
        isReadable = readable or false,
        hasLoot = lootable or false,
        isBound = isBound,
        bindType = bindType,         -- "BoP" when soulbound, "BoE" otherwise

        -- Quality (default to 1/Common if still unknown to avoid Lua errors)
        quality = quality or 1,

        -- Location (Added convenience)
        bagID = bagID,
        slotID = slotID,
    }
end

--- Get total number of slots in a container.
---@param bagID number
---@return number numSlots
function OmniC_Container.GetContainerNumSlots(bagID)
    return GetContainerNumSlots(bagID) or 0
end

--- Get free slot count in a container.
---@param bagID number
---@return number freeSlots
---@return number bagType
function OmniC_Container.GetContainerFreeSlots(bagID)
    local numFreeSlots, bagType = GetContainerNumFreeSlots(bagID)
    return numFreeSlots or 0, bagType or 0
end

-- =============================================================================
-- Helper Functions (Extensions)
-- =============================================================================

--- Get all items in a specific bag container.
---@param bagID number
---@return table items Array of item info tables
function OmniC_Container.GetContainerItems(bagID)
    local items = {}
    local numSlots = OmniC_Container.GetContainerNumSlots(bagID)

    for slotID = 1, numSlots do
        local info = OmniC_Container.GetContainerItemInfo(bagID, slotID)
        if info then
            table.insert(items, info)
        end
    end

    return items
end

--- Get all items in player inventory (Bags 0-4).
---@return table items Array of item info tables
function OmniC_Container.GetAllBagItems()
    local items = {}

    for bagID = 0, 4 do
        local bagItems = OmniC_Container.GetContainerItems(bagID)
        for _, item in ipairs(bagItems) do
            table.insert(items, item)
        end
    end

    return items
end

--- Get all items in player bank (Main -1 + Bags 5-11).
---@return table items Array of item info tables
function OmniC_Container.GetAllBankItems()
    local items = {}

    -- Main bank (bagID = -1)
    local bankItems = OmniC_Container.GetContainerItems(-1)
    for _, item in ipairs(bankItems) do
        table.insert(items, item)
    end

    -- Bank bags (5-11)
    for bagID = 5, 11 do
        local bagItems = OmniC_Container.GetContainerItems(bagID)
        for _, item in ipairs(bagItems) do
            table.insert(items, item)
        end
    end

    return items
end

-- =============================================================================
-- Extended Item Info (GetItemInfo Wrapper)
-- =============================================================================

--- Get extended item info properly structured.
--- Wraps `GetItemInfo` to return a table instead of list of returns.
---@param itemLink string
---@return table|nil info Table with keys or nil not cached.
function API:GetExtendedItemInfo(itemLink)
    if not itemLink then return nil end

    local name, link, quality, iLevel, reqLevel, class, subclass,
          maxStack, equipSlot, texture, vendorPrice = GetItemInfo(itemLink)

    if not name then
        return nil -- Item info not in local cache yet
    end

    return {
        name = name,
        link = link,
        quality = quality or 0,
        itemLevel = iLevel or 0,
        requiredLevel = reqLevel or 0,
        itemType = class,
        itemSubType = subclass,
        maxStackSize = maxStack or 1,
        equipSlot = equipSlot,
        iconFileID = texture,
        vendorPrice = vendorPrice or 0,
    }
end

-- =============================================================================
-- Initialization
-- =============================================================================

do
    print("|cFF00FF00OmniInventory|r: API Shim loaded (" .. (API.isWotLK and "WotLK 3.3.5a" or "Retail") .. ")")
end
