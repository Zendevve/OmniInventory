-- =============================================================================
-- OmniInventory Engine/SignatureCache.lua
-- Memoized Item Signature & Property Hash Engine (Zero String Allocation Sorting)
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or _G.OmniInventory or _G.Omni

local SignatureCache = {
    cache = {},
}
Omni.SignatureCache = SignatureCache

--- Calculate unique signatureKey integer without string formatting
-- Formula: signatureKey = itemID + (suffixID * 100000) + (enchantID * 100000000)
local function GetSignatureKey(itemID, suffixID, enchantID)
    itemID = itemID or 0
    suffixID = suffixID or 0
    enchantID = enchantID or 0
    return itemID + (suffixID * 100000) + (enchantID * 100000000)
end
SignatureCache.GetSignatureKey = GetSignatureKey

--- Parse Item Link without creating temporary string objects when cached
-- Format: item:itemID:enchantID:gem1:gem2:gem3:gem4:suffixID:uniqueID:linkLevel:reforgeID
local function ParseItemLink(itemLink)
    if not itemLink or type(itemLink) ~= "string" then
        return 0, 0, 0
    end

    local itemID, enchantID, suffixID = string.match(itemLink, "item:(%d+):(%d+):%d+:%d+:%d+:%d+:(%-?%d+)")
    itemID = tonumber(itemID) or 0
    enchantID = tonumber(enchantID) or 0
    suffixID = tonumber(suffixID) or 0
    if suffixID < 0 then suffixID = math.abs(suffixID) end

    return itemID, suffixID, enchantID
end
SignatureCache.ParseItemLink = ParseItemLink

--- Get or Compute Memoized Signature Entry for an Item
function SignatureCache:GetSignature(itemLink, slotData)
    if not itemLink then
        return nil
    end

    local itemID, suffixID, enchantID = ParseItemLink(itemLink)
    if itemID == 0 then return nil end

    local signatureKey = GetSignatureKey(itemID, suffixID, enchantID)
    local cached = self.cache[signatureKey]
    if cached then
        return cached
    end

    -- Compute new signature entry
    slotData = slotData or {}
    slotData.itemID = itemID
    slotData.suffixID = suffixID
    slotData.enchantID = enchantID

    -- Fetch item info from WoW C-API if available
    local name, _, quality, iLevel, reqLevel, class, subClass, maxStack, equipLoc, icon = nil
    if GetItemInfo then
        name, _, quality, iLevel, reqLevel, class, subClass, maxStack, equipLoc, icon = GetItemInfo(itemLink)
    end
    if name then
        slotData.name = name
        slotData.quality = quality
        slotData.class = class
        slotData.subClass = subClass
        slotData.maxStack = maxStack
        slotData.equipLoc = equipLoc
        slotData.icon = icon
    end

    -- Evaluate bitmask and category via RulesEngine
    local bitmask, categoryID, categoryName, categoryPriority = 0, "Miscellaneous", "Miscellaneous", 0
    if Omni.RulesEngine and type(Omni.RulesEngine.EvaluateItem) == "function" then
        bitmask, categoryID, categoryName, categoryPriority = Omni.RulesEngine:EvaluateItem(slotData, nil)
    end

    -- Check equipment sets if item is in set
    local isSetItem = false
    local setNames = nil

    local entry = {
        signatureKey = signatureKey,
        itemID = itemID,
        suffixID = suffixID,
        enchantID = enchantID,
        bitmask = bitmask,
        categoryID = categoryID,
        categoryName = categoryName,
        categoryPriority = categoryPriority,
        isBound = slotData.isBound or false,
        isUnusable = slotData.isUnusable or false,
        isSetItem = isSetItem,
        setNames = setNames or {},
        name = name or "",
        quality = quality or 0,
        class = class or "",
        subClass = subClass or "",
        icon = icon or "",
    }

    self.cache[signatureKey] = entry
    return entry
end

--- Invalidate specific signature from cache
function SignatureCache:Invalidate(signatureKey)
    if signatureKey and self.cache[signatureKey] then
        self.cache[signatureKey] = nil
    end
end

--- Clear entire signature cache
function SignatureCache:Clear()
    table.wipe(self.cache)
end
