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
        highlightNewItems = true,
        showItemLevel = true,
        -- ʕ •ᴥ•ʔ✿ right | left | fixed_br | fixed_bl | fixed_tl | fixed_tr (ItemButton) ✿ ʕ •ᴥ•ʔ
        itemTooltipPlacement = "right",
        -- ʕ •ᴥ•ʔ✿ x = pixels inset from bottom-right; y = up from bottom ✿ ʕ •ᴥ•ʔ
        itemTooltipFixed = {
            x = 24,
            y = 140,
        },
        enableBoundCategories = true,
        enableUnusableOverlay = true,
        autoSellJunk = true,
        vendorDoubleRightClick = true,
        collapseEmptySlots = false,
        autoRepair = false,
        autoRepairGuild = false,
        -- ʕ •ᴥ•ʔ✿ Footer: larger outlined gold + slot count; slots tint blue→red by fill ✿ ʕ •ᴥ•ʔ
        footerMoneyEmphasis = true,
        -- ʕ •ᴥ•ʔ✿ Custom footer launcher buttons (mini-mode themed) ✿ ʕ •ᴥ•ʔ
        footerButtons = {
            resetInstances = false,
        },
        -- ʕ •ᴥ•ʔ✿ Third-party addon launchers (auto-hidden when the addon isn't loaded) ✿ ʕ •ᴥ•ʔ
        addonButtons = {
            atlasLoot   = true,
        },
        -- ʕ •ᴥ•ʔ✿ Configurable auto-display: per-event open/close of the
        -- main inventory frame. Mirrors Bagnon's per-frame/per-event model
        -- but scoped to the single Omni main bag window. ✿ ʕ •ᴥ•ʔ
        autoDisplay = {
            bank    = true,   -- BANKFRAME_OPENED
            vendor  = false,  -- MERCHANT_SHOW
            mail    = false,  -- MAIL_SHOW
            ah      = false,  -- AUCTION_HOUSE_SHOW
            trade   = false,  -- TRADE_SHOW
            guildbank = true, -- GUILDBANKFRAME_OPENED
            craft   = false,  -- TRADE_SKILL_SHOW / CRAFT_SHOW
            player  = false,  -- PLAYER_FRAME_OPENED-ish (character frame)
        },
        -- ʕ •ᴥ•ʔ✿ Junk filter include/exclude lists (AdiBags-style). ✿ ʕ •ᴥ•ʔ
        junkInclude = {},     -- itemIDs always treated as junk
        junkExclude = { [6948] = true }, -- itemIDs never treated as junk (Hearthstone default)
        -- ʕ •ᴥ•ʔ✿ Global lock: when true, all layout updates are paused
        -- (sort/swap/equipment changes). Mirrors AdiBags SetGlobalLock. ✿ ʕ •ᴥ•ʔ
        globalLock = false,
        -- ʕ •ᴥ•ʔ✿ Theme: "rounded" (default WoW borders) or "square"
        -- (pfUI-compatible, cropped icons, hidden rounded borders). ✿ ʕ •ᴥ•ʔ
        theme = "rounded",
        -- ʕ •ᴥ•ʔ✿ Auto-tidy: compact layout on close (AdiBags TidyBags). ✿ ʕ •ᴥ•ʔ
        autoTidyOnClose = false,
        -- ʕ •ᴥ•ʔ✿ Auto-loot: automatically loot loot frames when opened. ✿ ʕ •ᴥ•ʔ
        autoLoot = false,
        -- ʕ •ᴥ•ʔ✿ Cache warmer: pre-load GetItemInfo for known item IDs
        -- on PLAYER_ENTERING_WORLD to avoid tooltip delays. ✿ ʕ •ᴥ•ʔ
        cacheWarmer = true,
        -- ʕ •ᴥ•ʔ✿ Money tracker: record gold history per character over
        -- time for trend display. ✿ ʕ •ᴥ•ʔ
        moneyTracker = false,
        -- ʕ •ᴥ•ʔ✿ Bound item indicator: show a small chain icon on
        -- soulbound items in the bag. ✿ ʕ •ᴥ•ʔ
        showBoundIndicator = false,
        -- ʕ •ᴥ•ʔ✿ Bag type tags: show family tag text on specialty
        -- bag slot icons in the header. ✿ ʕ •ᴥ•ʔ
        showBagTypeTags = false,
        -- ʕ •ᴥ•ʔ✿ Resort button: show a button when a dry-run detects
        -- the layout could be reorganized (Bagshui-style). ✿ ʕ •ᴥ•ʔ
        showResortButton = false,
    },
    char = {
        position = nil,         -- { point, x, y }
        customRules = {},
        collapsedCategories = {},
    },
    realm = {},  -- Cross-character data stored here
}

local function CopyTable(src)
    if type(src) ~= "table" then
        return src
    end
    local dst = {}
    for key, value in pairs(src) do
        if type(value) == "table" then
            dst[key] = CopyTable(value)
        else
            dst[key] = value
        end
    end
    return dst
end

local function MergeDefaults(target, source)
    for key, value in pairs(source) do
        if target[key] == nil then
            target[key] = CopyTable(value)
        elseif type(value) == "table" and type(target[key]) == "table" then
            MergeDefaults(target[key], value)
        end
    end
end

-- =============================================================================
-- Initialization
-- =============================================================================

function Data:Init()
    OmniInventoryDB = OmniInventoryDB or {}

    -- Ensure all default keys exist
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    OmniInventoryDB.char = OmniInventoryDB.char or {}
    OmniInventoryDB.realm = OmniInventoryDB.realm or {}

    MergeDefaults(OmniInventoryDB.global, defaults.global)
    MergeDefaults(OmniInventoryDB.char, defaults.char)
    MergeDefaults(OmniInventoryDB.realm, defaults.realm)

    -- ʕ •ᴥ•ʔ✿ One-shot: retire addon-hook placement + legacy compat flag ✿ ʕ •ᴥ•ʔ
    do
        local g = OmniInventoryDB.global
        local pl = g.itemTooltipPlacement
        if pl == nil or pl == "addon" then
            g.itemTooltipPlacement = "right"
        elseif pl == "fixed" then
            g.itemTooltipPlacement = "fixed_br"
        end
        g.tooltipAddonCompatibility = nil
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

-- ʕ •ᴥ•ʔ✿ Helper: native-first link fetch ✿ ʕ •ᴥ•ʔ
local function FetchLink(bagID, slot)
    local API = Omni.API
    if API then
        return API:GetItemLinkBySlot(bagID, slot)
    end
    return GetContainerItemLink(bagID, slot)
end

function Data:SaveCharacterInventory()
    local realm = OmniInventoryDB.realm[self.realmName]
    local char = realm and realm[self.playerName]
    if not char then return end

    char.gold = GetMoney()
    char.lastSeen = time()

    char.bags = {}
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local link = FetchLink(bagID, slot)
            if link then
                local _, count = GetContainerItemInfo(bagID, slot)
                table.insert(char.bags, { link = link, count = count or 1 })
            end
        end
    end
end

function Data:SaveBankItems()
    local realm = OmniInventoryDB.realm[self.realmName]
    local char = realm and realm[self.playerName]
    if not char then return end

    char.bank = {}

    local numSlots = GetContainerNumSlots(-1)
    for slot = 1, numSlots do
        local link = FetchLink(-1, slot)
        if link then
            local _, count = GetContainerItemInfo(-1, slot)
            table.insert(char.bank, { link = link, count = count or 1 })
        end
    end

    for bagID = 5, 11 do
        local numSlots = GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local link = FetchLink(bagID, slot)
            if link then
                local _, count = GetContainerItemInfo(bagID, slot)
                table.insert(char.bank, { link = link, count = count or 1 })
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

-- =============================================================================
-- Favorites/Pin System
-- =============================================================================

function Data:PinItem(itemID)
    if not itemID then return end
    OmniInventoryDB.global.pinnedItems = OmniInventoryDB.global.pinnedItems or {}
    OmniInventoryDB.global.pinnedItems[itemID] = true
end

function Data:UnpinItem(itemID)
    if not itemID then return end
    if OmniInventoryDB.global.pinnedItems then
        OmniInventoryDB.global.pinnedItems[itemID] = nil
    end
end

function Data:IsPinned(itemID)
    if not itemID then return false end
    return OmniInventoryDB.global.pinnedItems and OmniInventoryDB.global.pinnedItems[itemID] == true
end

function Data:TogglePin(itemID)
    if self:IsPinned(itemID) then
        self:UnpinItem(itemID)
        return false
    else
        self:PinItem(itemID)
        return true
    end
end

print("|cFF00FF00OmniInventory|r: Data module loaded")
