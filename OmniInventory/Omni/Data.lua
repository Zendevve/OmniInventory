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
        dbVersion = 4,
        viewMode = "flow",      -- "grid", "flow", "list"
        sortMode = "category",  -- "category", "quality", "name", "ilvl", "usage"
        columns = 10,
        itemSize = 37,
        scale = 1.0,
        opacity = 0.95,
        highlightNewItems = true,
        showItemLevel = true,
        -- right | left | fixed_br | fixed_bl | fixed_tl | fixed_tr (ItemButton)
        itemTooltipPlacement = "right",
        -- x = pixels inset from bottom-right; y = up from bottom
        itemTooltipFixed = {
            x = 24,
            y = 140,
        },
        enableBoundCategories = true,
        enableUnusableOverlay = true,
        autoSellJunk = true,
        vendorDoubleRightClick = true,
        vendorCtrlRightClick = true,
        collapseEmptySlots = false,
        autoRepair = false,
        autoRepairGuild = false,
        -- Footer: larger outlined gold + slot count; slots tint blue→red by fill
        footerMoneyEmphasis = true,
        -- Footer money: render gold/silver/copper as coin icons instead of text
        footerMoneyIcons = false,
        -- Custom footer launcher buttons (mini-mode themed)
        footerButtons = {
            clearGlow       = true,   -- Mark All Read
            resetInstances  = false,
            hearthstone     = true,
            openables       = true,   -- Clam/container opener
            disenchant      = true,   -- Only shows for enchanters
            picklock        = true,    -- Only shows for rogues
        },
        -- Detailed categories: opt-in extra buckets (Soul Shards,
        -- Hearthstone, Recipes, Gems, Trinkets, Food vs Drink split).
        detailedCategories = false,
        -- Configurable auto-display: per-event open/close of the
        -- main inventory frame. Mirrors Bagnon's per-frame/per-event model
        -- but scoped to the single Omni main bag window.
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
        -- Junk filter include/exclude lists (AdiBags-style).
        junkInclude = {},     -- itemIDs always treated as junk
        junkExclude = { [6948] = true }, -- itemIDs never treated as junk (Hearthstone default)
        -- Global lock: when true, all layout updates are paused
        -- (sort/swap/equipment changes). Mirrors AdiBags SetGlobalLock.
        globalLock = false,
        -- Theme: "rounded" (default WoW borders) or "square"
        -- (pfUI-compatible, cropped icons, hidden rounded borders).
        theme = "rounded",
        -- Auto-tidy: compact layout on close (AdiBags TidyBags).
        autoTidyOnClose = false,
        -- Auto-loot: automatically loot loot frames when opened.
        autoLoot = false,
        -- Cache warmer: pre-load GetItemInfo for known item IDs
        -- on PLAYER_ENTERING_WORLD to avoid tooltip delays.
        cacheWarmer = true,
        -- Money tracker: record gold history per character over
        -- time for trend display.
        moneyTracker = false,
        -- Bound item indicator: show a small chain icon on
        -- soulbound items in the bag.
        showBoundIndicator = false,
        -- Bag type tags: show family tag text on specialty
        -- bag slot icons in the header.
        showBagTypeTags = false,
        -- Resort button: show a button when a dry-run detects
        -- the layout could be reorganized (Bagshui-style).
        showResortButton = false,
        -- Category stripe: show a small vertical stripe on the left
        -- edge of each item slot matching its category color.
        showCategoryStripe = false,
    },
    char = {
        position = nil,         -- { point, x, y }
        customRules = {},
        collapsedCategories = {},
        -- Per-character UI settings (view mode, scale, bag filter, etc.)
        settings = {
            viewMode = "flow",  -- "grid", "flow", "list", "bag"
            scale = 1.0,
            itemScale = 1.0,
            itemGap = 4,
            selectedBagID = nil,
            selectedBankBagID = nil,
            bankViewMode = "flow",
        },
        -- Per-character guild bank settings
        guildBank = {
            viewMode = "flow",  -- "grid" or "flow"
            tabMappings = {},
        },
        -- Per-frame layout settings (bag/bank/keys)
        frameSettings = {},
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
-- Database Migrations
-- =============================================================================

local migrations = {
    [2] = function(db)
        if db.global then
            local pl = db.global.itemTooltipPlacement
            if pl == "addon" then
                db.global.itemTooltipPlacement = "right"
            elseif pl == "fixed" then
                db.global.itemTooltipPlacement = "fixed_br"
            end
            db.global.tooltipAddonCompatibility = nil
        end
    end,
    -- v3: Ensure char.settings and char.guildBank sub-tables exist so
    -- MergeDefaults can recursively populate their keys. Also ensures
    -- detailedCategories has an explicit default for existing users.
    [3] = function(db)
        if db.char then
            db.char.settings   = db.char.settings   or {}
            db.char.guildBank  = db.char.guildBank  or { tabMappings = {} }
            db.char.frameSettings = db.char.frameSettings or {}
        end
        if db.global then
            db.global.detailedCategories = db.global.detailedCategories or false
        end
    end,
    [4] = function(db)
        if db.realm then
            for realmName, realmData in pairs(db.realm) do
                realmData.guilds = realmData.guilds or {}
            end
        end
    end,
}

local function MigrateDB()
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.global = OmniInventoryDB.global or {}

    local currentVersion = OmniInventoryDB.global.dbVersion or 1
    local targetVersion = defaults.global.dbVersion or 2

    if currentVersion < targetVersion then
        for v = currentVersion + 1, targetVersion do
            if migrations[v] then
                local ok, err = pcall(migrations[v], OmniInventoryDB)
                if not ok then
                    print("|cFF00FF00OmniInventory|r: DB migration to version " .. v .. " failed: " .. tostring(err))
                else
                    print("|cFF00FF00OmniInventory|r: DB migrated to version " .. v)
                end
            end
        end
        OmniInventoryDB.global.dbVersion = targetVersion
    end
end

-- =============================================================================
-- Initialization
-- =============================================================================

function Data:Init()
    -- Run database migrations
    MigrateDB()

    -- Ensure all default keys exist
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    OmniInventoryDB.char = OmniInventoryDB.char or {}
    OmniInventoryDB.realm = OmniInventoryDB.realm or {}

    MergeDefaults(OmniInventoryDB.global, defaults.global)
    MergeDefaults(OmniInventoryDB.char, defaults.char)
    MergeDefaults(OmniInventoryDB.realm, defaults.realm)




    -- Store current character info
    local realmName = GetRealmName()
    local playerName = UnitName("player")
    local charKey = realmName .. "-" .. playerName

    OmniInventoryDB.realm[realmName] = OmniInventoryDB.realm[realmName] or {}
    OmniInventoryDB.realm[realmName].guilds = OmniInventoryDB.realm[realmName].guilds or {}
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
-- Per-Frame Settings (A13)
-- =============================================================================
-- Each frame ("bag", "bank", "keys") has independent visual/layout settings.
-- Mirrors Bagnon's per-frame SavedFrameSettings model.

local FRAME_DEFAULTS = {
    bag = {
        scale = 1.0,
        opacity = 0.95,
        columns = 10,
        itemSize = 37,
        itemScale = 1.0,
        itemGap = 4,
        position = nil,       -- { point, x, y }
        color = { r = 0.08, g = 0.08, b = 0.08, a = 0.95 },
        borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1.0 },
        strata = "HIGH",
        viewMode = "flow",
        reverseSlotOrder = false,
    },
    bank = {
        scale = 1.0,
        opacity = 0.95,
        columns = 10,
        itemSize = 37,
        itemScale = 1.0,
        itemGap = 4,
        position = nil,
        color = { r = 0.08, g = 0.08, b = 0.08, a = 0.95 },
        borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1.0 },
        strata = "HIGH",
        viewMode = "flow",
        reverseSlotOrder = false,
    },
    keys = {
        scale = 1.0,
        opacity = 0.95,
        columns = 8,
        itemSize = 30,
        itemScale = 1.0,
        itemGap = 2,
        position = nil,
        color = { r = 0.08, g = 0.08, b = 0.08, a = 0.95 },
        borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1.0 },
        strata = "HIGH",
        viewMode = "grid",
        reverseSlotOrder = false,
    },
}

function Data:GetFrameSetting(frameID, key, default)
    if not frameID or not key then return default end
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.char = OmniInventoryDB.char or {}
    OmniInventoryDB.char.frameSettings = OmniInventoryDB.char.frameSettings or {}
    local frameData = OmniInventoryDB.char.frameSettings[frameID]
    if frameData and frameData[key] ~= nil then
        return frameData[key]
    end
    local frameDefault = FRAME_DEFAULTS[frameID]
    if frameDefault and frameDefault[key] ~= nil then
        return frameDefault[key]
    end
    return default
end

function Data:SetFrameSetting(frameID, key, value)
    if not frameID or not key then return end
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.char = OmniInventoryDB.char or {}
    OmniInventoryDB.char.frameSettings = OmniInventoryDB.char.frameSettings or {}
    if not OmniInventoryDB.char.frameSettings[frameID] then
        local fd = FRAME_DEFAULTS[frameID] or {}
        local copy = {}
        for k, v in pairs(fd) do
            if type(v) == "table" then
                copy[k] = {}
                for k2, v2 in pairs(v) do copy[k][k2] = v2 end
            else
                copy[k] = v
            end
        end
        OmniInventoryDB.char.frameSettings[frameID] = copy
    end
    OmniInventoryDB.char.frameSettings[frameID][key] = value
end

function Data:GetAllFrameSettings(frameID)
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.char = OmniInventoryDB.char or {}
    OmniInventoryDB.char.frameSettings = OmniInventoryDB.char.frameSettings or {}
    if not OmniInventoryDB.char.frameSettings[frameID] then
        local fd = FRAME_DEFAULTS[frameID] or {}
        local copy = {}
        for k, v in pairs(fd) do
            if type(v) == "table" then
                copy[k] = {}
                for k2, v2 in pairs(v) do copy[k][k2] = v2 end
            else
                copy[k] = v
            end
        end
        OmniInventoryDB.char.frameSettings[frameID] = copy
    end
    return OmniInventoryDB.char.frameSettings[frameID]
end

-- =============================================================================
-- Cross-Character Data
-- =============================================================================

-- Helper: native-first link fetch
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
    char.level = UnitLevel("player")

    char.bags = {}
    char.bagSizes = char.bagSizes or {}
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        char.bagSizes[tostring(bagID)] = numSlots
        for slot = 1, numSlots do
            local link = FetchLink(bagID, slot)
            if link then
                local _, count = GetContainerItemInfo(bagID, slot)
                local _, _, quality = GetItemInfo(link)
                table.insert(char.bags, {
                    bagID = bagID,
                    slotID = slot,
                    link = link,
                    count = count or 1,
                    quality = quality or 0
                })
            end
        end
    end

    -- Keyring
    local keyringSlots = GetContainerNumSlots(-2) or 0
    char.bagSizes["-2"] = keyringSlots
    for slot = 1, keyringSlots do
        local link = FetchLink(-2, slot)
        if link then
            local _, count = GetContainerItemInfo(-2, slot)
            table.insert(char.bags, {
                bagID = -2,
                slotID = slot,
                link = link,
                count = count or 1,
                quality = 0
            })
        end
    end
end

function Data:SaveBankItems()
    local realm = OmniInventoryDB.realm[self.realmName]
    local char = realm and realm[self.playerName]
    if not char then return end

    local numSlots = GetContainerNumSlots(-1) or 0
    if numSlots <= 0 then
        return -- Bank is closed/not available, don't wipe the cached data!
    end

    char.bank = {}
    char.bagSizes = char.bagSizes or {}

    char.bagSizes["-1"] = numSlots
    for slot = 1, numSlots do
        local link = FetchLink(-1, slot)
        if link then
            local _, count = GetContainerItemInfo(-1, slot)
            local _, _, quality = GetItemInfo(link)
            table.insert(char.bank, {
                bagID = -1,
                slotID = slot,
                link = link,
                count = count or 1,
                quality = quality or 0
            })
        end
    end

    for bagID = 5, 11 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        char.bagSizes[tostring(bagID)] = numSlots
        for slot = 1, numSlots do
            local link = FetchLink(bagID, slot)
            if link then
                local _, count = GetContainerItemInfo(bagID, slot)
                local _, _, quality = GetItemInfo(link)
                table.insert(char.bank, {
                    bagID = bagID,
                    slotID = slot,
                    link = link,
                    count = count or 1,
                    quality = quality or 0
                })
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
-- Offline Inventory DB (A11) — Equipment + Cross-Character Viewing
-- =============================================================================
-- Bagnon_Forever-style: store equipped items so any character can view
-- any other character's inventory. Also stores bank slot count.

function Data:SaveEquipment()
    local realm = OmniInventoryDB.realm[self.realmName]
    local char = realm and realm[self.playerName]
    if not char then return end

    char.equipment = {}
    -- WotLK equip slots: 1..19 (incl. bag, ranged, tabard, etc.)
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local texture = GetInventoryItemTexture("player", slot)
            local _, _, quality = GetItemInfo(link)
            table.insert(char.equipment, {
                slotID = slot,
                link = link,
                texture = texture,
                quality = quality or 0,
            })
        end
    end
end

function Data:SaveBankSlotCount()
    local realm = OmniInventoryDB.realm[self.realmName]
    local char = realm and realm[self.playerName]
    if not char then return end

    local mainSlots = GetContainerNumSlots(-1) or 0
    if mainSlots <= 0 then
        return -- Bank is not open
    end

    char.bankSlots = GetNumBankSlots and GetNumBankSlots() or 0
end

function Data:GetCharacterData(realmName, playerName)
    if not realmName or not playerName then return nil end
    local realm = OmniInventoryDB and OmniInventoryDB.realm and OmniInventoryDB.realm[realmName]
    return realm and realm[playerName]
end

function Data:SetViewedCharacter(playerName)
    self.currentViewedChar = playerName or self.playerName
end

function Data:ClearViewedCharacter()
    self.currentViewedChar = self.playerName
end

function Data:IsViewingOwnCharacter()
    return not self.currentViewedChar or self.currentViewedChar == self.playerName
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

-- =============================================================================
-- Guild Bank Caching System
-- =============================================================================

function Data:SaveGuildBank(guildName, tabIndex)
    if not guildName then
        guildName = GetGuildInfo("player")
    end
    if not guildName or guildName == "" then return end

    OmniInventoryDB.char = OmniInventoryDB.char or {}
    OmniInventoryDB.char.guildName = guildName

    local numTabs = GetNumGuildBankTabs() or 0
    if numTabs <= 0 then return end

    local realm = OmniInventoryDB.realm[self.realmName]
    if not realm then return end
    realm.guilds = realm.guilds or {}
    realm.guilds[guildName] = realm.guilds[guildName] or { tabs = {} }

    local tabs = realm.guilds[guildName].tabs

    local activeTab = tabIndex or (GetCurrentGuildBankTab and GetCurrentGuildBankTab()) or 1
    if activeTab < 1 or activeTab > numTabs then return end

    local name, icon, isViewable, canDeposit, numWithdrawals, remainingWithdrawals = GetGuildBankTabInfo(activeTab)
    if not name or name == "" then
        return
    end

    tabs[activeTab] = tabs[activeTab] or {}
    tabs[activeTab].name = name
    tabs[activeTab].icon = icon
    tabs[activeTab].isViewable = isViewable and true or false
    tabs[activeTab].canDeposit = canDeposit and true or false
    tabs[activeTab].numWithdrawals = numWithdrawals or 0
    tabs[activeTab].remainingWithdrawals = remainingWithdrawals or 0
    tabs[activeTab].items = {}

    if isViewable then
        -- 98 slots per tab in WotLK
        for slot = 1, 98 do
            local link = GetGuildBankItemLink(activeTab, slot)
            if link then
                local _, count = GetGuildBankItemInfo(activeTab, slot)
                local _, _, quality = GetItemInfo(link)
                table.insert(tabs[activeTab].items, {
                    slotID = slot,
                    link = link,
                    count = count or 1,
                    quality = quality or 0
                })
            end
        end
    end
end

function Data:SaveGuildBankHeaders(guildName)
    if not guildName then
        guildName = GetGuildInfo("player")
    end
    if not guildName or guildName == "" then return end

    OmniInventoryDB.char = OmniInventoryDB.char or {}
    OmniInventoryDB.char.guildName = guildName

    local numTabs = GetNumGuildBankTabs() or 0
    if numTabs <= 0 then return end

    local realm = OmniInventoryDB.realm[self.realmName]
    if not realm then return end
    realm.guilds = realm.guilds or {}
    realm.guilds[guildName] = realm.guilds[guildName] or { tabs = {} }
    realm.guilds[guildName].money = GetGuildBankMoney and GetGuildBankMoney() or 0

    local tabs = realm.guilds[guildName].tabs

    for i = 1, numTabs do
        local name, icon, isViewable, canDeposit, numWithdrawals, remainingWithdrawals = GetGuildBankTabInfo(i)
        if name and name ~= "" then
            tabs[i] = tabs[i] or {}
            tabs[i].name = name
            tabs[i].icon = icon
            tabs[i].isViewable = isViewable and true or false
            tabs[i].canDeposit = canDeposit and true or false
            tabs[i].numWithdrawals = numWithdrawals or 0
            tabs[i].remainingWithdrawals = remainingWithdrawals or 0
            tabs[i].items = tabs[i].items or {}
        end
    end
end

function Data:GetGuildBankCache(guildName)
    if not guildName then
        guildName = GetGuildInfo("player")
    end
    if not guildName or guildName == "" then return nil end
    local realm = OmniInventoryDB and OmniInventoryDB.realm and OmniInventoryDB.realm[self.realmName]
    return realm and realm.guilds and realm.guilds[guildName]
end
