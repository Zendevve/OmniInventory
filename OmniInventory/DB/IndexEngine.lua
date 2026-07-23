-- =============================================================================
-- OmniInventory DB/IndexEngine.lua
-- Account-wide In-Memory O(1) Inverted Item Index & Aggregate Inventory Store
-- =============================================================================
-- Maintains an instant inverted lookup index:
--   ItemIndex[itemID][realmName][charName] = { bags = X, bank = Y, equip = Z }
-- Enables O(1) slot mutations and instant aggregate cross-character queries
-- without iterating container slot tables on mouseover tooltips.
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or _G.Omni or _G.OmniInventory or {}
_G.OmniInventory = Omni
_G.Omni = Omni

local IndexEngine = {
    ItemIndex = {},  -- [itemID][realmName][charName] = { bags = N, bank = N, equip = N }
    SlotCache = {}   -- [realmName][charName][indexKey] = { itemID = ID, count = C, loc = category }
}
Omni.IndexEngine = IndexEngine
Omni.DB = Omni.DB or {}
Omni.DB.IndexEngine = IndexEngine

-- Internal helper: classify bagID into location category ("bags", "bank", "equip")
local function GetLocationCategory(bagID)
    if bagID == "equip" or bagID == -3 then
        return "equip"
    end
    bagID = tonumber(bagID) or 0
    if bagID == -1 or (bagID >= 5 and bagID <= 11) then
        return "bank"
    else
        return "bags"
    end
end

--- Instant O(1) mutation method updating in-memory index when a slot changes.
-- @param realmName string Realm name
-- @param charName string Character name
-- @param bagID number|string Container bag ID or "equip"
-- @param slotID number Container slot ID
-- @param newItemID number|nil New item ID in slot (nil if emptied)
-- @param newCount number|nil New stack count (defaults to 1 if newItemID set)
-- @param oldItemID number|nil (Optional) Explicit old item ID override
-- @param oldCount number|nil (Optional) Explicit old count override
function IndexEngine:UpdateSlot(realmName, charName, bagID, slotID, newItemID, newCount, oldItemID, oldCount)
    if not realmName or not charName or not bagID or not slotID then return end

    local Schema = Omni.Schema or (Omni.DB and Omni.DB.Schema)
    local indexKey = Schema and Schema.ToIndex and Schema.ToIndex(bagID, slotID) or ((tonumber(bagID) or 0) * 100 + (tonumber(slotID) or 0))
    local locCategory = GetLocationCategory(bagID)

    -- Initialize character slot cache
    self.SlotCache[realmName] = self.SlotCache[realmName] or {}
    self.SlotCache[realmName][charName] = self.SlotCache[realmName][charName] or {}
    local charSlots = self.SlotCache[realmName][charName]

    local cachedSlot = charSlots[indexKey]

    -- Determine old item details to decrement
    local prevItemID = oldItemID or (cachedSlot and cachedSlot.itemID)
    local prevCount = oldCount or (cachedSlot and cachedSlot.count) or 0

    newItemID = tonumber(newItemID)
    newCount = newItemID and (tonumber(newCount) or 1) or 0

    -- 1. Decrement old item count from index if present
    if prevItemID and prevItemID > 0 and prevCount > 0 then
        local realmIdx = self.ItemIndex[prevItemID] and self.ItemIndex[prevItemID][realmName]
        local charCounts = realmIdx and realmIdx[charName]
        if charCounts and charCounts[locCategory] then
            charCounts[locCategory] = math.max(0, charCounts[locCategory] - prevCount)
            -- Clean up zeroed sub-tables to conserve memory
            if charCounts.bags == 0 and charCounts.bank == 0 and charCounts.equip == 0 then
                realmIdx[charName] = nil
                if not next(realmIdx) then
                    self.ItemIndex[prevItemID][realmName] = nil
                    if not next(self.ItemIndex[prevItemID]) then
                        self.ItemIndex[prevItemID] = nil
                    end
                end
            end
        end
    end

    -- 2. Increment new item count in index if present
    if newItemID and newItemID > 0 and newCount > 0 then
        self.ItemIndex[newItemID] = self.ItemIndex[newItemID] or {}
        self.ItemIndex[newItemID][realmName] = self.ItemIndex[newItemID][realmName] or {}
        local charCounts = self.ItemIndex[newItemID][realmName][charName]
        if not charCounts then
            charCounts = { bags = 0, bank = 0, equip = 0 }
            self.ItemIndex[newItemID][realmName][charName] = charCounts
        end
        charCounts[locCategory] = (charCounts[locCategory] or 0) + newCount

        -- Update slot cache record
        charSlots[indexKey] = { itemID = newItemID, count = newCount, loc = locCategory }
    else
        -- Slot emptied
        charSlots[indexKey] = nil
    end
end

--- Rebuilds the account-wide inverted index from SavedVariables (OmniInventoryDB).
-- Performs a full pass over all realm and character records.
function IndexEngine:RebuildIndex()
    table.wipe(self.ItemIndex)
    table.wipe(self.SlotCache)

    local Schema = Omni.Schema or (Omni.DB and Omni.DB.Schema)
    local db = _G.OmniInventoryDB
    if not db then return end

    -- Helper function to scan character record tables
    local function ProcessCharacterData(realmName, charName, charData)
        if not charData or type(charData) ~= "table" then return end

        -- Process packed slots array if present (v1 compressed format)
        if charData.slots and type(charData.slots) == "table" then
            for indexKey, packedStr in pairs(charData.slots) do
                if Schema and Schema.FromIndex and Schema.UnpackItemRecord then
                    local bagID, slotID = Schema.FromIndex(indexKey)
                    local itemID, suffix, enchant, count = Schema.UnpackItemRecord(packedStr)
                    if itemID and count and count > 0 then
                        self:UpdateSlot(realmName, charName, bagID, slotID, itemID, count)
                    end
                end
            end
        end

        -- Process unpacked bags array (standard table format)
        if charData.bags and type(charData.bags) == "table" then
            for _, itemRecord in pairs(charData.bags) do
                if type(itemRecord) == "table" and itemRecord.link then
                    local itemID = Schema and Schema.CompressLink and Schema.CompressLink(itemRecord.link)
                        or tonumber(string.match(itemRecord.link, "item:(%d+)"))
                    local count = tonumber(itemRecord.count) or 1
                    local bagID = itemRecord.bagID or 0
                    local slotID = itemRecord.slotID or 1
                    if itemID and count > 0 then
                        self:UpdateSlot(realmName, charName, bagID, slotID, itemID, count)
                    end
                end
            end
        end

        -- Process unpacked bank array
        if charData.bank and type(charData.bank) == "table" then
            for _, itemRecord in pairs(charData.bank) do
                if type(itemRecord) == "table" and itemRecord.link then
                    local itemID = Schema and Schema.CompressLink and Schema.CompressLink(itemRecord.link)
                        or tonumber(string.match(itemRecord.link, "item:(%d+)"))
                    local count = tonumber(itemRecord.count) or 1
                    local bagID = itemRecord.bagID or -1
                    local slotID = itemRecord.slotID or 1
                    if itemID and count > 0 then
                        self:UpdateSlot(realmName, charName, bagID, slotID, itemID, count)
                    end
                end
            end
        end

        -- Process equipment array
        if charData.equipment and type(charData.equipment) == "table" then
            for _, equipRecord in pairs(charData.equipment) do
                if type(equipRecord) == "table" and equipRecord.link then
                    local itemID = Schema and Schema.CompressLink and Schema.CompressLink(equipRecord.link)
                        or tonumber(string.match(equipRecord.link, "item:(%d+)"))
                    local slotID = equipRecord.slotID or 1
                    if itemID then
                        self:UpdateSlot(realmName, charName, "equip", slotID, itemID, 1)
                    end
                end
            end
        end
    end

    -- Process OmniInventoryDB.realms
    if db.realms and type(db.realms) == "table" then
        for realmName, realmData in pairs(db.realms) do
            if realmData.characters and type(realmData.characters) == "table" then
                for charName, charData in pairs(realmData.characters) do
                    ProcessCharacterData(realmName, charName, charData)
                end
            end
        end
    end

    -- Process legacy OmniInventoryDB.realm if present
    if db.realm and type(db.realm) == "table" then
        for realmName, realmData in pairs(db.realm) do
            if type(realmData) == "table" then
                for charName, charData in pairs(realmData) do
                    if charName ~= "guilds" and type(charData) == "table" then
                        ProcessCharacterData(realmName, charName, charData)
                    end
                end
            end
        end
    end
end

--- Instant O(1) total count query for an item across all alts on a realm (or all realms if realmName is nil).
-- @param itemID number Item ID
-- @param realmName string|nil Optional realm name filter
-- @return number Total aggregate count of item
function IndexEngine:GetItemTotalCount(itemID, realmName)
    itemID = tonumber(itemID)
    if not itemID or not self.ItemIndex[itemID] then return 0 end

    local total = 0
    local itemRecord = self.ItemIndex[itemID]

    if realmName then
        local realmRecord = itemRecord[realmName]
        if realmRecord then
            for charName, counts in pairs(realmRecord) do
                total = total + (counts.bags or 0) + (counts.bank or 0) + (counts.equip or 0)
            end
        end
    else
        for rName, realmRecord in pairs(itemRecord) do
            for charName, counts in pairs(realmRecord) do
                total = total + (counts.bags or 0) + (counts.bank or 0) + (counts.equip or 0)
            end
        end
    end

    return total
end

--- Instant aggregate character breakdown query for an item across alts.
-- @param itemID number Item ID
-- @param realmName string|nil Optional realm name filter
-- @return table Table of character breakdown: { [charName] = { bags = N, bank = N, equip = N, total = N } }
function IndexEngine:GetItemLocationBreakdown(itemID, realmName)
    itemID = tonumber(itemID)
    local breakdown = {}
    if not itemID or not self.ItemIndex[itemID] then return breakdown end

    local itemRecord = self.ItemIndex[itemID]

    local function AppendRealm(rName, realmRecord)
        if not realmRecord then return end
        for charName, counts in pairs(realmRecord) do
            local bags = counts.bags or 0
            local bank = counts.bank or 0
            local equip = counts.equip or 0
            local charTotal = bags + bank + equip
            if charTotal > 0 then
                breakdown[charName] = {
                    realm = rName,
                    bags = bags,
                    bank = bank,
                    equip = equip,
                    total = charTotal
                }
            end
        end
    end

    if realmName then
        AppendRealm(realmName, itemRecord[realmName])
    else
        for rName, realmRecord in pairs(itemRecord) do
            AppendRealm(rName, realmRecord)
        end
    end

    return breakdown
end

-- Initialize and rebuild index on login/load
function IndexEngine:OnInitialize()
    self:RebuildIndex()
end

-- Event frame for automatic initialization
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and (arg1 == addonName or arg1 == "OmniInventory") then
        IndexEngine:RebuildIndex()
    elseif event == "PLAYER_LOGIN" then
        IndexEngine:RebuildIndex()
    end
end)

if Omni.RegisterModule then
    Omni:RegisterModule("IndexEngine", IndexEngine)
end

return IndexEngine
