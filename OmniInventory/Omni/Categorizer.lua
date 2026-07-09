-- =============================================================================
-- OmniInventory Smart Categorization Engine
-- =============================================================================
-- Purpose: Automatically assign items to logical categories using a
-- priority-based pipeline (Quest > Equipment > Consumables > etc.)
-- =============================================================================

local addonName, Omni = ...

Omni.Categorizer = {}
local Categorizer = Omni.Categorizer

local CATEGORY_COLORS = {
    ["Perishable"]       = { r = 0.90, g = 0.35, b = 0.20 },  -- Orange-red
    ["Quest Items"]      = { r = 0.95, g = 0.85, b = 0.15 },  -- Gold/yellow
    ["Equipment Sets"]   = { r = 0.35, g = 0.70, b = 0.95 },  -- Steel blue
    ["BoE"]              = { r = 0.30, g = 0.85, b = 0.45 },  -- Green
    ["New Items"]        = { r = 0.85, g = 0.30, b = 0.85 },  -- Magenta
    ["Soulbound"]        = { r = 0.50, g = 0.65, b = 0.85 },  -- Muted blue-grey
    ["Account Bound"]    = { r = 0.00, g = 0.85, b = 0.95 },  -- Cyan/Heirloom
    ["Equipment"]        = { r = 0.65, g = 0.65, b = 0.70 },  -- Muted grey
    ["Consumables"]      = { r = 0.90, g = 0.65, b = 0.25 },  -- Amber
    ["Trade Goods"]      = { r = 0.75, g = 0.50, b = 0.90 },  -- Purple
    ["Reagents"]         = { r = 0.55, g = 0.75, b = 0.55 },  -- Sage green
    ["Tools"]            = { r = 0.50, g = 0.50, b = 0.55 },  -- Slate
    ["Keys"]             = { r = 0.85, g = 0.65, b = 0.45 },  -- Copper
    ["Bags"]             = { r = 0.60, g = 0.45, b = 0.30 },  -- Brown
    ["Ammo"]             = { r = 0.75, g = 0.60, b = 0.40 },  -- Leather
    ["Glyphs"]           = { r = 0.45, g = 0.80, b = 0.80 },  -- Teal
    ["Junk"]             = { r = 0.45, g = 0.45, b = 0.45 },  -- Dark grey
    ["Mounts"]           = { r = 0.95, g = 0.75, b = 0.25 },  -- Amber/gold
    ["Companions"]       = { r = 0.85, g = 0.50, b = 0.75 },  -- Magenta/pink
    ["Holiday"]          = { r = 0.95, g = 0.60, b = 0.60 },  -- Warm rose
    -- Detailed-mode buckets (hidden unless OmniInventoryDB.global.detailedCategories == true)
    ["Soul Shards"]      = { r = 0.55, g = 0.20, b = 0.65 },  -- Deep violet (ArkInventory + GudaBags)
    ["Hearthstone"]      = { r = 0.95, g = 0.50, b = 0.20 },  -- Orange (GudaBags itemID 6948 carveout)
    ["Recipes"]          = { r = 0.75, g = 0.55, b = 0.30 },  -- Tan/copper (Recipe own bucket, Ark/Adi/Guda)
    ["Gems"]             = { r = 0.30, g = 0.45, b = 0.85 },  -- Cobalt (Gem own bucket, Ark/Adi)
    ["Trinkets"]         = { r = 0.95, g = 0.80, b = 0.20 },  -- Gold (INVTYPE_TRINKET own bucket, GudaBags)
    ["Food"]             = { r = 0.35, g = 0.75, b = 0.40 },  -- Forest green (Food vs Drink split, Ark/Guda)
    ["Drink"]            = { r = 0.40, g = 0.65, b = 0.95 },  -- Sky blue (Drink vs Food split, Ark/Guda)
    ["Miscellaneous"]    = { r = 0.55, g = 0.55, b = 0.55 },  -- Medium grey
}

-- =============================================================================
-- Category Registry
-- =============================================================================

local categories = {}  -- { name = { priority, icon, color, filter } }
local categoryOrder = {}  -- Sorted by priority

local TOOLS_ITEMS = {
    [7453] = true,
    [45120] = true,
    [6256] = true,
    [6366] = true,
    [6367] = true,
    [6365] = true,
    [25978] = true,
    [44050] = true,
    [45991] = true,
    [45858] = true,
    [15846] = true,
    [45992] = true,
    [19970] = true,
    [7005] = true,
    [2901] = true,
    [5956] = true,
    [6219] = true,
    [10498] = true,
    [20815] = true,
    [20824] = true,
    [39505] = true,
    [6218] = true,
    [6339] = true,
    [11130] = true,
    [11145] = true,
    [16207] = true,
    [22461] = true,
    [22462] = true,
    [22463] = true,
    [44452] = true,
    [40772] = true,
    [23821] = true,
    [9149] = true,
    [13503] = true,
    [35751] = true,
    [35748] = true,
    [35750] = true,
    [35749] = true,
    [44322] = true,
    [44323] = true,
    [44324] = true,
    [49040] = true,
    [6948] = true,
    [40768] = true,
    [6265] = true,
    [22057] = true,
    [12534] = true,
    [10818] = true,
    [19931] = true,
    [21986] = true,
    [49633] = true,
    [49634] = true,
    [60274] = true,
}

-- =============================================================================
-- New Items Tracking (Session-based)
-- =============================================================================

local sessionItems = {}  -- Items present at login
local newItems = {}      -- Items acquired this session

local function SnapshotInventory()
    sessionItems = {}
    local API = Omni.API
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slot = 1, numSlots do
            local link = API and API:GetItemLinkBySlot(bagID, slot) or GetContainerItemLink(bagID, slot)
            if link then
                local itemID = API and API:GetIdFromLink(link) or tonumber(string.match(link, "item:(%d+)"))
                if itemID then
                    sessionItems[itemID] = true
                end
            end
        end
    end
end

-- Public API for new item tracking
function Categorizer:IsNewItem(itemID)
    if not itemID then return false end
    return newItems[itemID] == true
end

function Categorizer:MarkAsNew(itemID)
    if itemID and not sessionItems[itemID] then
        newItems[itemID] = true
    end
end

function Categorizer:ClearNewItem(itemID)
    if itemID then
        newItems[itemID] = nil
    end
end

function Categorizer:ClearAllNewItems()
    newItems = {}
end

function Categorizer:SnapshotInventory()
    SnapshotInventory()
end

-- =============================================================================
-- Perishable Items Registry
-- =============================================================================
-- Time-limited items that must be turned in before they expire

local PERISHABLE_ITEMS = {
    [50289] = true,  -- Blacktip Shark (1 hour turn-in)
}

function Categorizer:IsPerishableItem(itemID)
    if not itemID then return false end
    if PERISHABLE_ITEMS[itemID] then return true end
    if OmniInventoryDB and OmniInventoryDB.perishableItems
        and OmniInventoryDB.perishableItems[itemID] then
        return true
    end
    return false
end

function Categorizer:AddPerishableItem(itemID)
    if not itemID then return end
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.perishableItems = OmniInventoryDB.perishableItems or {}
    OmniInventoryDB.perishableItems[itemID] = true
end

function Categorizer:RemovePerishableItem(itemID)
    if not itemID then return end
    if OmniInventoryDB and OmniInventoryDB.perishableItems then
        OmniInventoryDB.perishableItems[itemID] = nil
    end
end

-- =============================================================================
-- Category Filters
-- =============================================================================

-- Check if item is a quest item
local function IsQuestItem(itemInfo)
    if not itemInfo or not itemInfo.bagID or not itemInfo.slotID then
        return false
    end

    -- GetContainerItemQuestInfo was added in 3.3.3
    local isQuestItem, questId, isActive = GetContainerItemQuestInfo(itemInfo.bagID, itemInfo.slotID)
    return isQuestItem or false
end

-- Native-first equipment manager membership check
local function IsEquipmentSetItem(itemInfo)
    if not itemInfo then return false end

    -- Preferred path: ask the C extension about this exact slot instance.
    local API = Omni.API
    if API and itemInfo.bagID and itemInfo.slotID then
        local inSet = API:IsItemInEquipmentSet(itemInfo.bagID, itemInfo.slotID)
        if inSet ~= nil then
            return inSet
        end
    end

    -- Fallback: iterate saved sets by itemID (slower, misses specific instances).
    if not itemInfo.hyperlink then return false end

    local numSets = GetNumEquipmentSets and GetNumEquipmentSets() or 0
    for i = 1, numSets do
        local name = GetEquipmentSetInfo(i)
        if name then
            local itemIDs = GetEquipmentSetItemIDs(name)
            if itemIDs then
                for _, itemID in pairs(itemIDs) do
                    if itemID == itemInfo.itemID then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function GetItemID(itemInfo)
    if not itemInfo then
        return nil
    end
    if itemInfo.itemID then
        return itemInfo.itemID
    end
    if itemInfo.hyperlink then
        if Omni.API then
            return Omni.API:GetIdFromLink(itemInfo.hyperlink)
        end
        return tonumber(string.match(itemInfo.hyperlink, "item:(%d+)"))
    end
    return nil
end


-- Get item type fields from itemInfo or GetItemInfo fallback
local function GetItemTypeInfo(itemInfo)
    if not itemInfo then
        return nil, nil, nil
    end

    local itemType = itemInfo.itemType
    local itemSubType = itemInfo.itemSubType
    local equipSlot = itemInfo.equipSlot

    if itemType then
        return itemType, itemSubType, equipSlot
    end

    if not itemInfo.hyperlink then
        return nil, nil, nil
    end

    local _, _, _, _, _, resolvedType, resolvedSubType, _, resolvedEquipSlot = GetItemInfo(itemInfo.hyperlink)
    return resolvedType, resolvedSubType, resolvedEquipSlot
end

local function IsEquipmentItem(itemInfo)
    local itemType, _, equipSlot = GetItemTypeInfo(itemInfo)
    if equipSlot and equipSlot ~= "" and equipSlot ~= "INVTYPE_BAG" and equipSlot ~= "INVTYPE_QUIVER" then
        return true
    end

    -- Fallback for uncached equip slots
    return itemType == "Armor" or itemType == "Weapon"
end

local function IsBoEItem(itemInfo)
    if not itemInfo then
        return false
    end
    if itemInfo.bindType ~= "BoE" then
        return false
    end
    return IsEquipmentItem(itemInfo)
end

local function IsSoulboundItem(itemInfo)
    if not itemInfo then
        return false
    end
    if itemInfo.bindType ~= "BoP" and not itemInfo.isBound then
        return false
    end
    return IsEquipmentItem(itemInfo)
end

local function IsAccountBoundItem(itemInfo)
    if not itemInfo then
        return false
    end
    return itemInfo.bindType == "BoA" or itemInfo.quality == 7
end


local function IsToolsItem(itemInfo)
    local itemID = GetItemID(itemInfo)
    if not itemID then
        return false
    end
    return TOOLS_ITEMS[itemID] == true
end


-- =============================================================================
-- Heuristic Classification
-- =============================================================================

local TYPE_TO_CATEGORY = {
    -- Main types
    ["Armor"]         = "Equipment",
    ["Weapon"]        = "Equipment",
    ["Consumable"]    = "Consumables",
    ["Trade Goods"]   = "Trade Goods",
    ["Reagent"]       = "Reagents",
    ["Recipe"]        = "Trade Goods",
    ["Gem"]           = "Trade Goods",
    ["Quest"]         = "Quest Items",
    ["Key"]           = "Keys",
    ["Miscellaneous"] = "Miscellaneous",
    ["Container"]     = "Bags",
    ["Projectile"]    = "Ammo",
    ["Quiver"]        = "Bags",
    ["Glyph"]         = "Glyphs",

    -- Subtypes (for more specific matching)
    ["Potion"]              = "Consumables",
    ["Elixir"]              = "Consumables",
    ["Flask"]               = "Consumables",
    ["Food & Drink"]        = "Consumables",
    ["Food"]                = "Consumables",
    ["Drink"]               = "Consumables",
    ["Bandage"]             = "Consumables",
    ["Scroll"]              = "Consumables",
    ["Other"]               = "Consumables",  -- Consumable subtype
    ["Item Enhancement"]    = "Consumables",
    ["Item Enchantment"]    = "Consumables",
    ["Leather"]             = "Trade Goods",
    ["Metal & Stone"]       = "Trade Goods",
    ["Cloth"]               = "Trade Goods",
    ["Herb"]                = "Trade Goods",
    ["Elemental"]           = "Trade Goods",
    ["Enchanting"]          = "Trade Goods",
    ["Jewelcrafting"]       = "Trade Goods",
    ["Parts"]               = "Trade Goods",
    ["Devices"]             = "Trade Goods",
    ["Explosives"]          = "Trade Goods",
    ["Materials"]           = "Trade Goods",
    ["Meat"]                = "Trade Goods",
    -- Subclasses of "Miscellaneous" that lift out into their own categories
    -- (ArkInventory / AdiBags / GudaBags all do this).
    ["Mount"]               = "Mounts",
    ["Mounts"]              = "Mounts",
    ["Companion"]           = "Companions",
    ["Companion Pets"]      = "Companions",
    ["Pet"]                 = "Companions",
    ["Holiday"]             = "Holiday",
}

local function ClassifyByItemType(itemInfo)
    local itemType, itemSubType = GetItemTypeInfo(itemInfo)

    if not itemType then
        return "Miscellaneous"
    end

    -- Equipment must win over subtype names like "Cloth"/"Leather".
    if IsEquipmentItem(itemInfo) then
        return "Equipment"
    end

    -- These top-level types are unambiguous.
    if itemType == "Trade Goods" then return "Trade Goods" end
    if itemType == "Reagent" then return "Reagents" end
    if itemType == "Container" then return "Bags" end
    if itemType == "Projectile" then return "Ammo" end
    if itemType == "Glyph" then return "Glyphs" end
    if itemType == "Quest" then return "Quest Items" end
    if itemType == "Key" then return "Keys" end

    -- Check subtype first for more specific classification
    if itemSubType then
        local subCategory = TYPE_TO_CATEGORY[itemSubType]
        if subCategory then
            return subCategory
        end
    end

    -- Fallback to main type
    return TYPE_TO_CATEGORY[itemType] or "Miscellaneous"
end

-- =============================================================================
-- Detailed Categories Mode (opt-in)
-- =============================================================================
-- Each reference addon does something slightly different here. We borrow the
-- pieces that overlap and gate them behind a single DB toggle so the default
-- behavior stays unchanged for existing users.
--
--   * Soul Shards id 6265 + Hearthstone id 6948   -- ArkInventory / GudaBags
--     carve specific items out of generic buckets into their own.
--   * Recipes own bucket                          -- ArkInventory / AdiBags /
--     GudaBags all separate Recipe itemType from Trade Goods.
--   * Gems own bucket                            -- ArkInventory / AdiBags.
--   * Trinkets own bucket                        -- GudaBags' INVTYPE_TRINKET
--     carve-out (bound tiers such as Soulbound/BoA still take priority).
--   * Food vs Drink split                        -- ArkInventory / GudaBags
--     restoreTag + spell text heuristic.
--
-- Toggle lives in OmniInventoryDB.global.detailedCategories (bool).

local DETAILED_ITEM_OVERRIDES = {
    [6265] = "Soul Shards",
    [6948] = "Hearthstone",
}

local function IsDetailedCategoriesEnabled()
    if not OmniInventoryDB or not OmniInventoryDB.global then return false end
    return OmniInventoryDB.global.detailedCategories == true
end

local function IsEquipmentTrinket(itemInfo)
    local _, _, equipSlot = GetItemTypeInfo(itemInfo)
    return equipSlot == "INVTYPE_TRINKET"
end

local function GetFoodOrDrinkCategory(itemInfo)
    if not IsDetailedCategoriesEnabled() then return nil end
    local itemType, itemSubType = GetItemTypeInfo(itemInfo)
    if itemType ~= "Consumable" then return nil end
    if itemSubType ~= "Food & Drink" and itemSubType ~= "Food" and itemSubType ~= "Drink" then
        return nil
    end
    if not itemInfo.hyperlink then return "Food & Drink" end
    local _, _, _, _, _, _, _, _, _, _, _, spellDesc = GetItemInfo(itemInfo.hyperlink)
    if not spellDesc then
        -- Item cache not warm yet; keep the umbrella bucket so a fresh item
        -- doesn't get misclassified on first open.
        return "Food & Drink"
    end
    local lower = string.lower(spellDesc)
    -- Drinks restore mana while drinking; foods restore health while eating.
    if string.find(lower, "mana") and string.find(lower, "drink") then return "Drink" end
    if string.find(lower, "health") and string.find(lower, "eat") then return "Food" end
    if string.find(lower, "drink") then return "Drink" end
    if string.find(lower, "eat") then return "Food" end
    return "Food & Drink"
end

local function ApplyDetailedOverrides(category, itemInfo)
    if not IsDetailedCategoriesEnabled() then return category end
    if not itemInfo then return category end

    -- itemID-specific carve-outs always win (Soul Shards, Hearthstone).
    local itemID = GetItemID(itemInfo)
    if itemID then
        local det = DETAILED_ITEM_OVERRIDES[itemID]
        if det then return det end
    end

    local itemType = itemInfo.itemType
    if itemType == "Recipe" then return "Recipes" end
    if itemType == "Gem" then return "Gems" end

    -- Promote Trinkets out of the generic "Equipment" bucket, but only when
    -- bound tiers (Soulbound / Account Bound / BoE) did not already win.
    if category == "Equipment" and IsEquipmentTrinket(itemInfo) then
        return "Trinkets"
    end

    -- Food vs Drink split operates within the Consumables bucket.
    if category == "Consumables" then
        local fd = GetFoodOrDrinkCategory(itemInfo)
        if fd then return fd end
    end

    return category
end

-- =============================================================================
-- Priority Pipeline
-- =============================================================================

local categoryCache = {}

function Categorizer:ClearCategoryCache()
    wipe(categoryCache)
end

function Categorizer:GetCategory(itemInfo)
    local perfToken = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("categorizer.GetCategory")
    if not itemInfo then
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("categorizer.GetCategory", perfToken)
        end
        return "Miscellaneous"
    end

    local itemID = itemInfo.itemID or (itemInfo.hyperlink and tonumber(string.match(itemInfo.hyperlink, "item:(%d+)")))
    if itemID then
        local cached = categoryCache[itemID]
        if cached then
            if Omni._perfEnabled and Omni.Perf then
                Omni.Perf:End("categorizer.GetCategory", perfToken)
            end
            return cached
        end
    end

    local category = self:GetCategoryInternal(itemInfo)
    if itemID and category then
        categoryCache[itemID] = category
    end

    if Omni._perfEnabled and Omni.Perf then
        Omni.Perf:End("categorizer.GetCategory", perfToken, { result = category })
    end
    return category
end

function Categorizer:GetCategoryInternal(itemInfo)
    local perfToken = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("categorizer.GetCategory")
    if not itemInfo then
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("categorizer.GetCategory", perfToken)
        end
        return "Miscellaneous"
    end

    -- Priority 1: Manual Override
    if itemInfo.itemID and OmniInventoryDB and OmniInventoryDB.categoryOverrides then
        local override = OmniInventoryDB.categoryOverrides[itemInfo.itemID]
        if override then
            if Omni._perfEnabled and Omni.Perf then
                Omni.Perf:End("categorizer.GetCategory", perfToken)
            end
            return override
        end
    end

    -- User-defined categories (A18): evaluate in sequence order
    -- before the hardcoded pipeline. Each category has an optional item
    -- list and/or a compiled rule expression.
    if Omni.Categories then
        local userCats = Omni.Categories:GetAll()
        for _, cat in ipairs(userCats or {}) do
            if Omni.Categories:ItemMatchesCategory(itemInfo, cat.name) then
                if Omni._perfEnabled and Omni.Perf then
                    Omni.Perf:End("categorizer.GetCategory", perfToken)
                end
                return cat.name
            end
        end
    end

    -- Priority 1.75: Perishable / time-limited turn-in items
    if self:IsPerishableItem(GetItemID(itemInfo)) then
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("categorizer.GetCategory", perfToken)
        end
        return "Perishable"
    end



    -- Priority 2: Quest Items
    if IsQuestItem(itemInfo) then
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("categorizer.GetCategory", perfToken)
        end
        return "Quest Items"
    end


    -- Priority 4: Equipment Sets
    if IsEquipmentSetItem(itemInfo) then
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("categorizer.GetCategory", perfToken)
        end
        return "Equipment Sets"
    end

    -- Bound categories (Priority 4.1 & 4.2)
    if not OmniInventoryDB or not OmniInventoryDB.global or OmniInventoryDB.global.enableBoundCategories ~= false then
        if IsAccountBoundItem(itemInfo) then
            if Omni._perfEnabled and Omni.Perf then
                Omni.Perf:End("categorizer.GetCategory", perfToken)
            end
            return "Account Bound"
        end

        if IsSoulboundItem(itemInfo) then
            if Omni._perfEnabled and Omni.Perf then
                Omni.Perf:End("categorizer.GetCategory", perfToken)
            end
            return "Soulbound"
        end
    end


    -- Prio 5 : Tools
    if IsToolsItem(itemInfo) then
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("categorizer.GetCategory", perfToken)
        end
        return "Tools"
    end

    -- Priority 6: BoE equipment
    if IsBoEItem(itemInfo) then
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("categorizer.GetCategory", perfToken)
        end
        return "BoE"
    end


    -- Priority 88: Check quality/include lists for junk
    local isJunk = false
    if Omni.Features and Omni.Features.IsJunkItem then
        isJunk = Omni.Features:IsJunkItem(itemInfo)
    else
        isJunk = (itemInfo.quality == 0)
    end

    if isJunk then
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("categorizer.GetCategory", perfToken)
        end
        return "Junk"
    end

    

    -- Priority 10+: Heuristic classification
    local out = ClassifyByItemType(itemInfo)

    -- Detailed-mode reroutes (Soul Shards id 6265, Hearthstone id 6948,
    -- Recipe itemType, Gem itemType, Trinkets INVTYPE_TRINKET, Food/Drink
    -- split for Consumables). Bound tier labels (Soulbound/BoE/BoA) win
    -- over the Trinkets promotion since they take priority higher up the
    -- pipeline -- only untouched "Equipment" items get promoted.
    out = ApplyDetailedOverrides(out, itemInfo)

    if Omni._perfEnabled and Omni.Perf then
        Omni.Perf:End("categorizer.GetCategory", perfToken, { result = out })
    end
    return out
end

-- =============================================================================
-- Manual Override Management
-- =============================================================================

function Categorizer:SetManualOverride(itemID, categoryName)
    if not itemID or not categoryName then return end

    OmniInventoryDB.categoryOverrides = OmniInventoryDB.categoryOverrides or {}
    OmniInventoryDB.categoryOverrides[itemID] = categoryName
    self:ClearCategoryCache()
end

function Categorizer:ClearManualOverride(itemID)
    if not itemID then return end

    if OmniInventoryDB and OmniInventoryDB.categoryOverrides then
        OmniInventoryDB.categoryOverrides[itemID] = nil
    end
    self:ClearCategoryCache()
end

-- Detailed-categories toggle: flips OmniInventoryDB.global.detailedCategories
-- and invalidates the per-item cache so the new routing takes effect on the
-- next pass.
function Categorizer:SetDetailedCategories(enabled)
    if not OmniInventoryDB or not OmniInventoryDB.global then return end
    OmniInventoryDB.global.detailedCategories = enabled and true or false
    self:ClearCategoryCache()
end

function Categorizer:IsDetailedCategoriesEnabled()
    return IsDetailedCategoriesEnabled()
end

-- =============================================================================
-- Category Registry
-- =============================================================================

function Categorizer:RegisterCategory(name, priority, icon, color, filterFunc)
    categories[name] = {
        name = name,
        priority = priority,
        icon = icon,
        color = color or CATEGORY_COLORS[name] or { r = 0.5, g = 0.5, b = 0.5 },
        filter = filterFunc,
    }

    -- Rebuild sorted order
    categoryOrder = {}
    for catName, catDef in pairs(categories) do
        table.insert(categoryOrder, catDef)
    end
    table.sort(categoryOrder, function(a, b)
        return a.priority < b.priority
    end)
end

function Categorizer:GetCategoryInfo(name)
    if name and (name == "Free Space" or string.match(name, "^Free Space")) then
        return {
            name = name,
            priority = 150,
            color = { r = 0.5, g = 0.5, b = 0.5 },
        }
    end
    return categories[name] or {
        name = name,
        priority = 99,
        color = CATEGORY_COLORS[name] or { r = 0.5, g = 0.5, b = 0.5 },
    }
end

function Categorizer:GetAllCategories()
    return categoryOrder
end

function Categorizer:GetCategoryColor(name)
    local info = self:GetCategoryInfo(name)
    return info.color.r, info.color.g, info.color.b
end

-- =============================================================================
-- Categorize All Items
-- =============================================================================

function Categorizer:CategorizeItems(items)
    local perfToken = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("categorizer.CategorizeItems")
    local categorized = {}  -- { categoryName = { items } }

    for _, itemInfo in ipairs(items) do
        local category = self:GetCategory(itemInfo)

        if not categorized[category] then
            categorized[category] = {}
        end

        itemInfo.category = category
        table.insert(categorized[category], itemInfo)
    end

    if Omni._perfEnabled and Omni.Perf then
        Omni.Perf:End("categorizer.CategorizeItems", perfToken, { itemCount = items and #items or 0 })
    end
    return categorized
end

-- =============================================================================
-- Initialization
-- =============================================================================

function Categorizer:Init()
    self:RegisterCategory("Perishable", 1, nil, CATEGORY_COLORS["Perishable"])
    self:RegisterCategory("Quest Items", 2, nil, CATEGORY_COLORS["Quest Items"])
    self:RegisterCategory("Equipment Sets", 4, nil, CATEGORY_COLORS["Equipment Sets"])
    self:RegisterCategory("Soulbound", 4.1, nil, CATEGORY_COLORS["Soulbound"])
    self:RegisterCategory("Account Bound", 4.2, nil, CATEGORY_COLORS["Account Bound"])
    self:RegisterCategory("BoE", 5, nil, CATEGORY_COLORS["BoE"])
    self:RegisterCategory("New Items", 6, nil, CATEGORY_COLORS["New Items"])
    self:RegisterCategory("Equipment", 10, nil, CATEGORY_COLORS["Equipment"])
    self:RegisterCategory("Consumables", 11, nil, CATEGORY_COLORS["Consumables"])
    self:RegisterCategory("Trade Goods", 12, nil, CATEGORY_COLORS["Trade Goods"])
    self:RegisterCategory("Reagents", 13, nil, CATEGORY_COLORS["Reagents"])
    self:RegisterCategory("Tools", 14, nil, CATEGORY_COLORS["Tools"])
    self:RegisterCategory("Keys", 15, nil, CATEGORY_COLORS["Keys"])
    self:RegisterCategory("Bags", 16, nil, CATEGORY_COLORS["Bags"])
    self:RegisterCategory("Ammo", 17, nil, CATEGORY_COLORS["Ammo"])
    self:RegisterCategory("Glyphs", 18, nil, CATEGORY_COLORS["Glyphs"])
    self:RegisterCategory("Mounts", 19, nil, CATEGORY_COLORS["Mounts"])
    self:RegisterCategory("Companions", 20, nil, CATEGORY_COLORS["Companions"])
    self:RegisterCategory("Holiday", 21, nil, CATEGORY_COLORS["Holiday"])
    -- Detailed-mode buckets (only surface when detailedCategories is enabled).
    self:RegisterCategory("Soul Shards", 22, nil, CATEGORY_COLORS["Soul Shards"])
    self:RegisterCategory("Hearthstone", 23, nil, CATEGORY_COLORS["Hearthstone"])
    self:RegisterCategory("Recipes", 24, nil, CATEGORY_COLORS["Recipes"])
    self:RegisterCategory("Gems", 25, nil, CATEGORY_COLORS["Gems"])
    self:RegisterCategory("Trinkets", 26, nil, CATEGORY_COLORS["Trinkets"])
    self:RegisterCategory("Food", 27, nil, CATEGORY_COLORS["Food"])
    self:RegisterCategory("Drink", 28, nil, CATEGORY_COLORS["Drink"])
    self:RegisterCategory("Junk", 90, nil, CATEGORY_COLORS["Junk"])
    self:RegisterCategory("Miscellaneous", 99, nil, CATEGORY_COLORS["Miscellaneous"])
    self:RegisterCategory("Free Space", 150, nil, CATEGORY_COLORS["Free Space"] or { r = 0.5, g = 0.5, b = 0.5 })

    -- Initialize manual overrides
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.categoryOverrides = OmniInventoryDB.categoryOverrides or {}
    OmniInventoryDB.perishableItems = OmniInventoryDB.perishableItems or {}
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    OmniInventoryDB.global.categoryCustoms = OmniInventoryDB.global.categoryCustoms or {}
    OmniInventoryDB.global.categoryRenames = OmniInventoryDB.global.categoryRenames or {}
    OmniInventoryDB.global.detailedCategories = OmniInventoryDB.global.detailedCategories or false

    -- Invalidate cached item -> category lookups so this session's
    -- upgraded rules apply immediately instead of relying on stale
    -- entries from before new categories/Mount/Companion/Holiday
    -- mappings were wired up.
    self:ClearCategoryCache()
end

-- =============================================================================
-- Category Customization and Rename Support
-- =============================================================================

local function GetOriginalCategoryName(name)
    if OmniInventoryDB and OmniInventoryDB.global and OmniInventoryDB.global.categoryRenames then
        for orig, renamed in pairs(OmniInventoryDB.global.categoryRenames) do
            if renamed == name then
                return orig
            end
        end
    end
    return name
end
Omni.Categorizer.GetOriginalCategoryName = GetOriginalCategoryName

local orig_GetCategoryInfo = Categorizer.GetCategoryInfo
function Categorizer:GetCategoryInfo(name)
    if name and (name == "Free Space" or string.match(name, "^Free Space")) then
        return {
            name = name,
            priority = 150,
            color = { r = 0.5, g = 0.5, b = 0.5 },
        }
    end

    local origName = GetOriginalCategoryName(name)
    local defaultInfo = categories[origName] or {
        name = name,
        priority = 99,
        color = CATEGORY_COLORS[origName] or CATEGORY_COLORS[name] or { r = 0.5, g = 0.5, b = 0.5 },
    }

    local custom = OmniInventoryDB and OmniInventoryDB.global and OmniInventoryDB.global.categoryCustoms and OmniInventoryDB.global.categoryCustoms[name]
    if custom then
        return {
            name = name,
            priority = custom.priority or defaultInfo.priority,
            color = custom.color or defaultInfo.color,
            icon = defaultInfo.icon,
            filter = defaultInfo.filter,
        }
    end
    return defaultInfo
end

local orig_GetCategory = Categorizer.GetCategory
function Categorizer:GetCategory(itemInfo)
    local cat = orig_GetCategory(self, itemInfo)
    if cat and OmniInventoryDB and OmniInventoryDB.global and OmniInventoryDB.global.categoryRenames then
        local newName = OmniInventoryDB.global.categoryRenames[cat]
        if newName then
            return newName
        end
    end
    return cat
end
