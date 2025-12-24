-- =============================================================================
-- OmniInventory Data Persistence
-- =============================================================================
-- Manages SavedVariables and cross-character data
-- =============================================================================

local addonName, Omni = ...

Omni.Data = {}
local Data = Omni.Data

-- =============================================================================
-- Default Configuration
-- =============================================================================

local defaults = {
    global = {
        viewMode = "flow",      -- "grid", "flow", "list"
        sortMode = "category",  -- "category", "quality", "name", "ilvl", "usage"
        columns = 10,
        itemSize = 37,
        scale = 1.0,
        opacity = 0.95,
    },
    char = {
        position = nil,         -- { point, x, y }
        customRules = {},
        collapsedCategories = {},
    },
    realm = {},  -- Cross-character data stored here
}

-- =============================================================================
-- Initialization
-- =============================================================================

function Data:Init()
    OmniInventoryDB = OmniInventoryDB or {}

    -- Ensure all default keys exist
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    OmniInventoryDB.char = OmniInventoryDB.char or {}
    OmniInventoryDB.realm = OmniInventoryDB.realm or {}

    -- Merge defaults
    for k, v in pairs(defaults.global) do
        if OmniInventoryDB.global[k] == nil then
            OmniInventoryDB.global[k] = v
        end
    end

    -- Store current character info
    local realmName = GetRealmName()
    local playerName = UnitName("player")
    local charKey = realmName .. "-" .. playerName

    OmniInventoryDB.realm[realmName] = OmniInventoryDB.realm[realmName] or {}
    OmniInventoryDB.realm[realmName][playerName] = OmniInventoryDB.realm[realmName][playerName] or {
        class = select(2, UnitClass("player")),
        lastSeen = time(),
        gold = 0,
        bags = {},
        bank = {},
    }

    self.charKey = charKey
    self.realmName = realmName
    self.playerName = playerName
end

-- =============================================================================
-- Accessors
-- =============================================================================

function Data:Get(key)
    return OmniInventoryDB.global[key]
end

function Data:Set(key, value)
    OmniInventoryDB.global[key] = value
end

function Data:GetChar(key)
    return OmniInventoryDB.char[key]
end

function Data:SetChar(key, value)
    OmniInventoryDB.char[key] = value
end

function Data:GetPlayerMoney()
    return GetMoney() or 0
end

-- =============================================================================
-- Cross-Character Data
-- =============================================================================

function Data:SaveCharacterInventory()
    local realm = OmniInventoryDB.realm[self.realmName]
    local char = realm and realm[self.playerName]
    if not char then return end

    char.gold = GetMoney()
    char.lastSeen = time()

    -- Save bag item strings (compact format)
    char.bags = {}
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bagID, slot)
            if link then
                local _, count = GetContainerItemInfo(bagID, slot)
                table.insert(char.bags, { link = link, count = count or 1 })
            end
        end
    end
end

function Data:GetAllCharacters()
    local chars = {}
    for realmName, realmData in pairs(OmniInventoryDB.realm or {}) do
        for playerName, charData in pairs(realmData) do
            table.insert(chars, {
                realm = realmName,
                name = playerName,
                class = charData.class,
                gold = charData.gold,
                lastSeen = charData.lastSeen,
            })
        end
    end
    return chars
end

print("|cFF00FF00OmniInventory|r: Data module loaded")
