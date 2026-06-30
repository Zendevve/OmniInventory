-- =============================================================================
-- OmniInventory Consolidated Small Features
-- =============================================================================
-- Implements the small-effort gap-analysis items in one module so the
-- Core/Frame files stay focused:
--   * Configurable Auto-Display (A12)
--   * Junk Include/Exclude Lists (A6)
--   * CacheWarmer (A28)
--   * AutoLoot (A29)
--   * Money Tracker (A27)
--   * Global Lock (C5)
--   * Interacting Window Tracking (C6)
--   * Bag Type Tags/Icons (A34)
--   * Bound Item Indicator (A42)
--   * Theme System (A46)
--   * TidyBags / Auto-Tidy (A38)
--   * Resort Button (C9)
--   * Item Fixes Database (A30)
--   * LDB Data Source/Launcher (A10)
-- =============================================================================

local addonName, Omni = ...

Omni.Features = {}
local Features = Omni.Features

-- =============================================================================
-- Interacting Window Tracking (C6)
-- =============================================================================
-- Tracks which "interacting" window is currently open so other systems
-- (auto-display, virtual stacking, junk filter) can be context-aware.

Features.interactingWindow = nil  -- "bank" | "vendor" | "mail" | "ah" | "trade" | "guildbank" | "craft" | nil

function Features:GetInteractingWindow()
    return Features.interactingWindow
end

function Features:SetInteractingWindow(window)
    Features.interactingWindow = window
end

function Features:IsAtBank()
    return Features.interactingWindow == "bank"
end

function Features:IsAtVendor()
    return Features.interactingWindow == "vendor"
end

-- =============================================================================
-- Global Lock (C5)
-- =============================================================================
-- When true, all layout updates are paused. Mirrors AdiBags SetGlobalLock.

function Features:SetGlobalLock(locked)
    local on = locked == true
    if Omni.Data then
        Omni.Data:Set("globalLock", on)
    end
    Omni._globalLock = on
end

function Features:IsGlobalLocked()
    if Omni._globalLock ~= nil then
        return Omni._globalLock
    end
    return Omni.Data and Omni.Data:Get("globalLock") == true or false
end

-- =============================================================================
-- Configurable Auto-Display (A12)
-- =============================================================================
-- Per-event open/close of the main inventory frame based on user settings.

function Features:IsAutoDisplayEnabled(event)
    if not Omni.Data then return false end
    local ad = Omni.Data:Get("autoDisplay") or {}
    return ad[event] == true
end

function Features:ApplyAutoDisplay(event, isShow)
    if not event then return end
    if isShow and Features:IsAutoDisplayEnabled(event) then
        if Omni.Frame and not Omni.Frame:IsShown() then
            Omni.Frame:Show()
        end
    end
end

-- =============================================================================
-- Junk Include/Exclude Lists (A6)
-- =============================================================================

function Features:IsJunkItem(itemInfo)
    if not itemInfo then return false end
    local itemID = itemInfo.itemID
    if not itemID then return false end

    if Omni.Data then
        local exclude = Omni.Data:Get("junkExclude") or {}
        if exclude[itemID] then
            return false
        end
        local include = Omni.Data:Get("junkInclude") or {}
        if include[itemID] then
            return true
        end
    end

    -- Default: quality 0 (poor/grey) is junk
    return (itemInfo.quality or 1) == 0
end

function Features:AddJunkInclude(itemID)
    if not itemID then return end
    if Omni.Data then
        local inc = Omni.Data:Get("junkInclude") or {}
        inc[itemID] = true
        Omni.Data:Set("junkInclude", inc)
    end
end

function Features:RemoveJunkInclude(itemID)
    if not itemID then return end
    if Omni.Data then
        local inc = Omni.Data:Get("junkInclude") or {}
        inc[itemID] = nil
        Omni.Data:Set("junkInclude", inc)
    end
end

function Features:AddJunkExclude(itemID)
    if not itemID then return end
    if Omni.Data then
        local exc = Omni.Data:Get("junkExclude") or {}
        exc[itemID] = true
        Omni.Data:Set("junkExclude", exc)
    end
end

function Features:RemoveJunkExclude(itemID)
    if not itemID then return end
    if Omni.Data then
        local exc = Omni.Data:Get("junkExclude") or {}
        exc[itemID] = nil
        Omni.Data:Set("junkExclude", exc)
    end
end

-- =============================================================================
-- CacheWarmer (A28)
-- =============================================================================
-- Pre-loads GetItemInfo for known item IDs on PLAYER_ENTERING_WORLD.

local cacheWarmerFrame
local cacheWarmerQueue
local cacheWarmerIndex

function Features:WarmCache()
    if not Omni.Data or Omni.Data:Get("cacheWarmer") ~= true then
        return
    end
    if cacheWarmerQueue then
        return -- already running
    end

    cacheWarmerQueue = {}
    cacheWarmerIndex = 1

    -- Collect all item IDs currently in bags + bank snapshot
    for bagID = 0, 4 do
        local n = GetContainerNumSlots(bagID) or 0
        for slot = 1, n do
            local link = GetContainerItemLink(bagID, slot)
            if link then
                local id = tonumber(string.match(link, "item:(%d+)"))
                if id then
                    cacheWarmerQueue[#cacheWarmerQueue + 1] = id
                end
            end
        end
    end

    -- Add pinned items
    if OmniInventoryDB and OmniInventoryDB.global and OmniInventoryDB.global.pinnedItems then
        for id in pairs(OmniInventoryDB.global.pinnedItems) do
            cacheWarmerQueue[#cacheWarmerQueue + 1] = id
        end
    end

    -- Add junk include/exclude lists
    if OmniInventoryDB and OmniInventoryDB.global then
        for id in pairs(OmniInventoryDB.global.junkInclude or {}) do
            cacheWarmerQueue[#cacheWarmerQueue + 1] = id
        end
        for id in pairs(OmniInventoryDB.global.junkExclude or {}) do
            cacheWarmerQueue[#cacheWarmerQueue + 1] = id
        end
    end

    if #cacheWarmerQueue == 0 then
        cacheWarmerQueue = nil
        return
    end

    if not cacheWarmerFrame then
        cacheWarmerFrame = CreateFrame("Frame")
    end

    local batchSize = 32
    cacheWarmerFrame:SetScript("OnUpdate", function(self, elapsed)
        local processed = 0
        while cacheWarmerIndex <= #cacheWarmerQueue and processed < batchSize do
            local id = cacheWarmerQueue[cacheWarmerIndex]
            GetItemInfo(id)
            cacheWarmerIndex = cacheWarmerIndex + 1
            processed = processed + 1
        end
        if cacheWarmerIndex > #cacheWarmerQueue then
            self:SetScript("OnUpdate", nil)
            cacheWarmerQueue = nil
            cacheWarmerIndex = nil
        end
    end)
end

-- =============================================================================
-- AutoLoot (A29)
-- =============================================================================

local autoLootFrame

function Features:InitAutoLoot()
    if not Omni.Data or Omni.Data:Get("autoLoot") ~= true then
        return
    end
    if autoLootFrame then return end

    autoLootFrame = CreateFrame("Frame")
    autoLootFrame:RegisterEvent("LOOT_OPENED")
    autoLootFrame:SetScript("OnEvent", function(_, event)
        if event ~= "LOOT_OPENED" then return end
        if not Omni.Data or Omni.Data:Get("autoLoot") ~= true then return end
        if GetNumLootItems and GetNumLootItems() > 0 then
            for i = GetNumLootItems(), 1, -1 do
                local _, _, isItem = GetLootSlotInfo(i)
                if isItem or true then
                    LootSlot(i)
                end
            end
        end
    end)
end

-- =============================================================================
-- Money Tracker (A27)
-- =============================================================================
-- Records gold history per character over time for trend display.

function Features:RecordMoney()
    if not Omni.Data or Omni.Data:Get("moneyTracker") ~= true then
        return
    end
    if not OmniInventoryDB or not OmniInventoryDB.realm then return end
    local realm = GetRealmName()
    local player = UnitName("player")
    local charData = OmniInventoryDB.realm[realm] and OmniInventoryDB.realm[realm][player]
    if not charData then return end

    charData.goldHistory = charData.goldHistory or {}
    local now = time()
    -- Record at most once per 5 minutes to avoid bloat
    local last = charData.goldHistory[#charData.goldHistory]
    if last and (now - last.t) < 300 then
        return
    end
    table.insert(charData.goldHistory, { t = now, gold = GetMoney() or 0 })
    -- Cap history at 288 entries (24h at 5-min intervals)
    while #charData.goldHistory > 288 do
        table.remove(charData.goldHistory, 1)
    end
end

-- =============================================================================
-- Bag Type Tags/Icons (A34)
-- =============================================================================
-- Maps bag family bitmasks to localized tags and icons.

Features.FAMILY_TAGS = {
    [1]    = { tag = "Ammo",     icon = "Interface\\Icons\\INV_Misc_Ammo_01" },
    [2]    = { tag = "Quiver",   icon = "Interface\\Icons\\INV_Misc_Quiver_01" },
    [4]    = { tag = "Soul",     icon = "Interface\\Icons\\INV_Misc_Gem_Soul_01" },
    [8]    = { tag = "Leather",  icon = "Interface\\Icons\\Trade_LeatherWorking" },
    [16]   = { tag = "Inscribe", icon = "Interface\\Icons\\INV_Inscription_Tradeskill01" },
    [32]   = { tag = "Herb",     icon = "Interface\\Icons\\Trade_Herbalism" },
    [64]   = { tag = "Mining",   icon = "Interface\\Icons\\Trade_Mining" },
    [128]  = { tag = "Eng",      icon = "Interface\\Icons\\Trade_Engineering" },
    [512]  = { tag = "Gem",      icon = "Interface\\Icons\\INV_Misc_Gem_Bloodstone_01" },
    [1024] = { tag = "Tackle",   icon = "Interface\\Icons\\INV_Misc_Fish_01" },
}

function Features:GetFamilyTag(family)
    if not family or family == 0 then return nil end
    for bit_mask, info in pairs(Features.FAMILY_TAGS) do
        local matches = false
        if bit and bit.band then
            matches = bit.band(family, bit_mask) > 0
        else
            -- ʕ •ᴥ•ʔ✿ Fallback when bit library is unavailable: integer
            -- modulo check (works for single-bit masks). ✿ ʕ •ᴥ•ʔ
            matches = (math.floor(family / bit_mask) % 2) == 1
        end
        if matches then
            return info.tag, info.icon
        end
    end
    return nil
end

function Features:GetBagFamilyTag(bagID)
    if not bagID or bagID < 1 or bagID > 11 then return nil end
    local _, family = GetContainerNumFreeSlots(bagID)
    return Features:GetFamilyTag(family or 0)
end

-- =============================================================================
-- Bound Item Indicator (A42)
-- =============================================================================
-- Returns true if the item should show a bound (chain) indicator.

function Features:ShouldShowBoundIndicator(itemInfo)
    if not itemInfo then return false end
    if not Omni.Data or Omni.Data:Get("showBoundIndicator") ~= true then
        return false
    end
    return itemInfo.isBound == true or itemInfo.bindType == "BoP" or itemInfo.bindType == "BoA"
end

-- =============================================================================
-- Theme System (A46)
-- =============================================================================
-- "rounded" (default WoW borders) or "square" (pfUI-compatible).

function Features:GetTheme()
    return (Omni.Data and Omni.Data:Get("theme")) or "rounded"
end

function Features:IsSquareTheme()
    return Features:GetTheme() == "square"
end

function Features:SetTheme(theme)
    if Omni.Data then
        Omni.Data:Set("theme", theme == "square" and "square" or "rounded")
    end
end

-- =============================================================================
-- TidyBags / Auto-Tidy (A38)
-- =============================================================================
-- Compacts layout on close.

function Features:ShouldAutoTidyOnClose()
    return Omni.Data and Omni.Data:Get("autoTidyOnClose") == true or false
end

function Features:RunTidy()
    -- Trigger a full layout refresh + native sort
    if Omni.Frame and Omni.Frame.UpdateLayout then
        Omni.Frame:UpdateLayout(nil, { forceFull = true, reason = "tidy" })
    end
    if SortBags then
        SortBags()
    end
end

-- =============================================================================
-- Resort Button (C9)
-- =============================================================================
-- Tracks whether a dry-run detected layout changes; the Frame can show
-- a resort button when this is true.

Features._resortPending = false

function Features:SetResortPending(pending)
    Features._resortPending = pending == true
end

function Features:IsResortPending()
    return Features._resortPending == true
end

function Features:ShouldShowResortButton()
    if not Omni.Data or Omni.Data:Get("showResortButton") ~= true then
        return false
    end
    return Features:IsResortPending()
end

-- =============================================================================
-- Item Fixes Database (A30)
-- =============================================================================
-- Corrections for Vanilla client quirks. Keyed by itemID.

Features.ITEM_FIXES = {
    -- Example entries; expand as needed for specific client quirks.
    -- [itemID] = { category = "Trade Goods", quality = 2 },
}

function Features:GetItemFix(itemID)
    if not itemID then return nil end
    return Features.ITEM_FIXES[itemID]
end

function Features:ApplyItemFixes(itemInfo)
    if not itemInfo or not itemInfo.itemID then return itemInfo end
    local fix = Features.ITEM_FIXES[itemInfo.itemID]
    if not fix then return itemInfo end
    if fix.category then itemInfo.category = fix.category end
    if fix.quality then itemInfo.quality = fix.quality end
    return itemInfo
end

-- =============================================================================
-- LDB Data Source/Launcher (A10)
-- =============================================================================
-- Registers a LibDataBroker data object if LibDataBroker is available.

function Features:InitLDB()
    if Features._ldbInitialized then return end
    Features._ldbInitialized = true

    local LibDataBroker
    if type(_G.LibStub) == "function" then
        local ok, lib = pcall(_G.LibStub, "LibDataBroker-1.1", true)
        if ok then
            LibDataBroker = lib
        end
    end

    if not LibDataBroker then
        return
    end

    local function getBagUsageText()
        local free, total = 0, 0
        for bagID = 0, 4 do
            total = total + (GetContainerNumSlots(bagID) or 0)
            free = free + (GetContainerNumFreeSlots(bagID) or 0)
        end
        local used = total - free
        return string.format("%d/%d slots", used, total)
    end

    local dataObject = LibDataBroker:NewDataObject("OmniInventory", {
        type = "data source",
        text = "OmniInventory",
        label = "OmniInventory",
        icon = "Interface\\Icons\\INV_Misc_Bag_07",
        OnClick = function(self, button)
            if button == "LeftButton" then
                if Omni.Frame then Omni.Frame:Toggle() end
            elseif button == "RightButton" then
                if Omni.Settings then Omni.Settings:Toggle() end
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:SetText("|cFF00FF00Omni|rInventory")
            tooltip:AddLine(getBagUsageText(), 1, 1, 1)
            tooltip:AddLine(" ")
            tooltip:AddLine("Left-click: Toggle Bags", 0.7, 0.7, 0.7)
            tooltip:AddLine("Right-click: Settings", 0.7, 0.7, 0.7)
        end,
    })

    Features._ldbObject = dataObject

    -- Update text periodically
    local updateFrame = CreateFrame("Frame")
    updateFrame:SetScript("OnEvent", function()
        if dataObject then
            dataObject.text = getBagUsageText()
        end
    end)
    updateFrame:RegisterEvent("BAG_UPDATE")
    updateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
end

-- =============================================================================
-- Initialization
-- =============================================================================

function Features:Init()
    self:InitLDB()
    self:InitAutoLoot()
end

print("|cFF00FF00OmniInventory|r: Features module loaded")
