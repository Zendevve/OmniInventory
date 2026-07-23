-- =============================================================================
-- OmniInventory DB/Schema.lua
-- SavedVariables Schema & Short-Link Serialization Format
-- =============================================================================
-- Architected for WoW 3.3.5a (Wrath of the Lich King - Build 30300)
-- Provides short-link item record serialization ("itemID:suffix:enchant,count"),
-- realm/character slot hierarchy mapping, and fast pack/unpack utilities.
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or _G.Omni or _G.OmniInventory or {}
_G.OmniInventory = Omni
_G.Omni = Omni

local Schema = {}
Omni.Schema = Schema
Omni.DB = Omni.DB or {}
Omni.DB.Schema = Schema

-- Schema Version Identifier
Schema.VERSION = "1.0.0"

--- Initialise the global SavedVariables table structure
-- @return table Reference to OmniInventoryDB
function Schema:InitDB()
    _G.OmniInventoryDB = _G.OmniInventoryDB or {}
    local db = _G.OmniInventoryDB
    db.version = db.version or Schema.VERSION
    db.realms = db.realms or {}

    -- Ensure backwards compatibility migration from legacy 'realm' structure
    if db.realm and type(db.realm) == "table" then
        for rName, rData in pairs(db.realm) do
            if type(rData) == "table" then
                db.realms[rName] = db.realms[rName] or { characters = {} }
                local chars = db.realms[rName].characters
                for cName, cData in pairs(rData) do
                    if type(cData) == "table" and cName ~= "guilds" then
                        chars[cName] = chars[cName] or cData
                    end
                end
            end
        end
    end

    return db
end

--- Get or create character data table within OmniInventoryDB.realms
-- @param realmName string Realm name
-- @param charName string Character name
-- @return table Character record table
function Schema:GetCharacterRecord(realmName, charName)
    local db = self:InitDB()
    if not realmName or not charName then return nil end

    db.realms[realmName] = db.realms[realmName] or { characters = {} }
    local realm = db.realms[realmName]
    realm.characters = realm.characters or {}

    if not realm.characters[charName] then
        realm.characters[charName] = {
            class = "UNKNOWN",
            level = 1,
            money = 0,
            bags = {},
            slots = {}
        }
    end

    return realm.characters[charName]
end

--- Encodes container bagID and slotID into a single integer index key.
-- Non-negative bagIDs (0..11): (bagID * 100) + slotID
-- Negative bagIDs (-1 Bank, -2 Keyring): (bagID * 100) - slotID
-- @param bagID number Container bag ID
-- @param slotID number Container slot ID
-- @return number Unique integer index key
function Schema.ToIndex(bagID, slotID)
    bagID = tonumber(bagID) or 0
    slotID = tonumber(slotID) or 0
    if bagID >= 0 then
        return (bagID * 100) + slotID
    else
        return (bagID * 100) - slotID
    end
end

--- Decodes a single integer index key back into container bagID and slotID.
-- @param index number Unique integer index key
-- @return number bagID, number slotID
function Schema.FromIndex(index)
    index = tonumber(index) or 0
    if index >= 0 then
        local bagID = math.floor(index / 100)
        local slotID = index % 100
        return bagID, slotID
    else
        local absIdx = math.abs(index)
        local bagID = -math.floor(absIdx / 100)
        local slotID = absIdx % 100
        return bagID, slotID
    end
end

--- Extracts itemID, suffixID, and enchantID from a full WoW item link or item string.
-- Supported link formats:
--   |cff9d9d9d|Hitem:7005:0:0:0:0:0:0:0:80:0|h[Skinning Knife]|h|r
--   item:40554:3831:0:0:0:0:-3831:0:80:0
--   40554
-- @param itemLink string|number Full item link, item string, or item ID
-- @return number|nil itemID, number suffixID, number enchantID
function Schema.CompressLink(itemLink)
    if not itemLink then return nil, 0, 0 end

    if type(itemLink) == "number" then
        return itemLink, 0, 0
    end

    -- Match 3.3.5a item link pattern: item:itemID:enchant:gem1:gem2:gem3:gem4:suffix:...
    local itemID, enchant, suffix = string.match(itemLink, "item:(%d+):(%-?%d+):%d+:%d+:%d+:%d+:(%-?%d+)")
    if itemID then
        return tonumber(itemID), tonumber(suffix) or 0, tonumber(enchant) or 0
    end

    -- Match simple item:itemID pattern
    itemID = string.match(itemLink, "item:(%d+)")
    if itemID then
        return tonumber(itemID), 0, 0
    end

    -- Numeric string fallback
    local num = tonumber(itemLink)
    if num then
        return num, 0, 0
    end

    return nil, 0, 0
end

--- Serializes item information into short-link string format to minimize storage size.
-- Formats:
--   "itemID,count"                  (suffix = 0, enchant = 0)
--   "itemID:suffix,count"           (suffix ~= 0, enchant = 0)
--   "itemID:suffix:enchant,count"   (enchant ~= 0)
-- @param itemID number Item ID
-- @param suffix number|nil Random suffix ID (optional)
-- @param enchant number|nil Permanent enchant ID (optional)
-- @param count number|nil Stack count (defaults to 1)
-- @return string Serialized short-link string
function Schema.PackItemRecord(itemID, suffix, enchant, count)
    itemID = tonumber(itemID)
    if not itemID then return nil end

    count = tonumber(count) or 1
    suffix = tonumber(suffix) or 0
    enchant = tonumber(enchant) or 0

    if suffix == 0 and enchant == 0 then
        return itemID .. "," .. count
    elseif enchant == 0 then
        return itemID .. ":" .. suffix .. "," .. count
    else
        return itemID .. ":" .. suffix .. ":" .. enchant .. "," .. count
    end
end

--- Deserializes a short-link string back into individual item components.
-- @param packedStr string Serialized short-link string
-- @return number|nil itemID, number suffix, number enchant, number count
function Schema.UnpackItemRecord(packedStr)
    if not packedStr or packedStr == "" then return nil, 0, 0, 0 end

    local linkPart, countStr = string.match(packedStr, "^([^,]+),(%d+)$")
    if not linkPart then
        linkPart = packedStr
        countStr = "1"
    end
    local count = tonumber(countStr) or 1

    local itemID, suffix, enchant = string.match(linkPart, "^(%d+):(%-?%d+):(%-?%d+)$")
    if itemID then
        return tonumber(itemID), tonumber(suffix) or 0, tonumber(enchant) or 0, count
    end

    itemID, suffix = string.match(linkPart, "^(%d+):(%-?%d+)$")
    if itemID then
        return tonumber(itemID), tonumber(suffix) or 0, 0, count
    end

    itemID = string.match(linkPart, "^(%d+)$")
    if itemID then
        return tonumber(itemID), 0, 0, count
    end

    return nil, 0, 0, 0
end

--- Reconstructs a standard WoW 3.3.5a item link string from itemID, suffix, and enchant.
-- @param itemID number Item ID
-- @param suffix number|nil Random suffix ID
-- @param enchant number|nil Enchant ID
-- @return string Reconstructed item link string
function Schema.DecompressLink(itemID, suffix, enchant)
    itemID = tonumber(itemID)
    if not itemID then return nil end

    suffix = tonumber(suffix) or 0
    enchant = tonumber(enchant) or 0

    return string.format("item:%d:%d:0:0:0:0:%d:0:80:0", itemID, enchant, suffix)
end

-- Module Initialization hook
function Schema:OnInitialize()
    self:InitDB()
end

if Omni.RegisterModule then
    Omni:RegisterModule("Schema", Schema)
end

return Schema
