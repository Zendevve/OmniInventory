local addonName, NS = ...

NS.Data = {}
local Data = NS.Data

-- Bag ID Constants
Data.BAGS = {0, 1, 2, 3, 4}
Data.BANK = {-1, 5, 6, 7, 8, 9, 10, 11}
Data.KEYRING = -2

-- State
Data.cache = {} -- Cached item data per character
Data.isBankOpen = false

-- =============================================================================
-- Initialization
-- =============================================================================

function Data:Init()
    -- Load cached data from SavedVariables
    if ZenBagsDB and ZenBagsDB.cache then
        self.cache = ZenBagsDB.cache
    end
end

-- =============================================================================
-- Core API: Item Info
-- =============================================================================

--- Get item information for a specific bag slot
-- @param bag number Bag ID
-- @param slot number Slot ID
-- @return link, count, texture, quality, isLocked, itemID
function Data:GetItemInfo(bag, slot)
    -- Determine if we should use cached data
    if self:IsCached(bag) then
        return self:GetCachedItemInfo(bag, slot)
    else
        return self:GetLiveItemInfo(bag, slot)
    end
end

--- Check if a bag is currently using cached data
-- @param bag number Bag ID
-- @return boolean
function Data:IsCached(bag)
    -- Bank bags are cached when bank is closed
    if self:IsBankBag(bag) then
        return not self.isBankOpen
    end
    
    -- Inventory bags are always live
    return false
end

--- Get live item info from WoW API
-- @param bag number
-- @param slot number
-- @return link, count, texture, quality, isLocked, itemID
function Data:GetLiveItemInfo(bag, slot)
    local texture, count, locked, quality, readable, lootable, link, isFiltered, noValue, itemID = GetContainerItemInfo(bag, slot)
    return link, count, texture, quality, locked, itemID
end

--- Get cached item info from SavedVariables
-- @param bag number
-- @param slot number
-- @return link, count, texture, quality, isLocked, itemID
function Data:GetCachedItemInfo(bag, slot)
    local charKey = self:GetCharacterKey()
    local bagData = self.cache[charKey] and self.cache[charKey][bag]
    
    if not bagData then
        return nil, nil, nil, nil, nil, nil
    end
    
    local itemData = bagData[slot]
    if not itemData then
        return nil, nil, nil, nil, nil, nil
    end
    
    return itemData.link, itemData.count, itemData.texture, itemData.quality, false, itemData.itemID
end

-- =============================================================================
-- Core API: Bag Info
-- =============================================================================

--- Get the size of a bag
-- @param bag number Bag ID
-- @return number
function Data:GetBagSize(bag)
    if self:IsCached(bag) then
        local charKey = self:GetCharacterKey()
        local bagData = self.cache[charKey] and self.cache[charKey][bag]
        if bagData then
            return bagData.size or 0
        end
        return 0
    else
        return GetContainerNumSlots(bag) or 0
    end
end

--- Check if a bag is a bank bag
-- @param bag number
-- @return boolean
function Data:IsBankBag(bag)
    for _, bankBag in ipairs(self.BANK) do
        if bag == bankBag then
            return true
        end
    end
    return false
end

--- Check if a bag is an inventory bag
-- @param bag number
-- @return boolean
function Data:IsInventoryBag(bag)
    for _, invBag in ipairs(self.BAGS) do
        if bag == invBag then
            return true
        end
    end
    return false
end

-- =============================================================================
-- Caching System
-- =============================================================================

--- Update the cache with current live data
-- This should be called whenever bags are scanned
function Data:UpdateCache()
    local charKey = self:GetCharacterKey()
    
    -- Initialize cache structure
    if not ZenBagsDB then
        ZenBagsDB = {}
    end
    ZenBagsDB.cache = ZenBagsDB.cache or {}
    ZenBagsDB.cache[charKey] = ZenBagsDB.cache[charKey] or {}
    
    -- Scan all bags
    local bagList = {}
    for _, bag in ipairs(self.BAGS) do
        table.insert(bagList, bag)
    end
    
    if self.isBankOpen then
        for _, bag in ipairs(self.BANK) do
            table.insert(bagList, bag)
        end
    end
    
    for _, bag in ipairs(bagList) do
        local numSlots = GetContainerNumSlots(bag)
        ZenBagsDB.cache[charKey][bag] = {size = numSlots}
        
        for slot = 1, numSlots do
            local texture, count, locked, quality, readable, lootable, link, isFiltered, noValue, itemID = GetContainerItemInfo(bag, slot)
            
            if link then
                ZenBagsDB.cache[charKey][bag][slot] = {
                    link = link,
                    count = count,
                    texture = texture,
                    quality = quality,
                    itemID = itemID
                }
            else
                ZenBagsDB.cache[charKey][bag][slot] = nil
            end
        end
    end
    
    -- Update in-memory cache reference
    self.cache = ZenBagsDB.cache
end

--- Get the character key for cache storage
-- @return string
function Data:GetCharacterKey()
    return UnitName("player") .. " - " .. GetRealmName()
end

-- =============================================================================
-- Bank State Management
-- =============================================================================

function Data:SetBankOpen(isOpen)
    self.isBankOpen = isOpen
    if isOpen then
        self:UpdateCache()
    end
end

function Data:IsBankOpen()
    return self.isBankOpen
end

--- Get cached bank items in Inventory-compatible format
-- @return table Array of item data
function Data:GetCachedBankItems()
    local charKey = self:GetCharacterKey()
    local items = {}
    
    if not self.cache[charKey] then
        return items
    end
    
    -- Iterate through all bank bags
    for _, bag in ipairs(self.BANK) do
        local bagData = self.cache[charKey][bag]
        if bagData then
            for slot = 1, (bagData.size or 0) do
                local itemData = bagData[slot]
                if itemData then
                    -- Build item in same format as Inventory.lua
                    table.insert(items, {
                        bagID = bag,
                        slotID = slot,
                        link = itemData.link,
                        texture = itemData.texture,
                        count = itemData.count,
                        quality = itemData.quality,
                        itemID = itemData.itemID,
                        location = "bank",
                        category = NS.Categories:GetCategory(itemData.link)
                    })
                end
            end
        end
    end
    
    return items
end

--- Check if there are cached bank items available
-- @return boolean
function Data:HasCachedBankItems()
    local charKey = self:GetCharacterKey()
    if not self.cache[charKey] then
        return false
    end
    
    -- Check if any bank bag has items
    for _, bag in ipairs(self.BANK) do
        local bagData = self.cache[charKey][bag]
        if bagData then
            for slot = 1, (bagData.size or 0) do
                if bagData[slot] then
                    return true
                end
            end
        end
    end
    
    return false
end
