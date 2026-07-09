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
            -- Fallback when bit library is unavailable: integer
            -- modulo check (works for single-bit masks).
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
-- Currency Frame (A35)
-- =============================================================================
-- Dedicated currency display frame showing tracked currencies in the bag frame.
-- Reuses the existing TRACKED_TOOLTIP_CURRENCIES from Frame.lua via a standalone
-- popup so users can see their emblem/seal counts without hovering the footer.

local currencyFrame

function Features:GetCurrencyFrame()
    return currencyFrame
end

function Features:CreateCurrencyFrame()
    if currencyFrame then return currencyFrame end
    if not Omni.Frame then return nil end

    currencyFrame = CreateFrame("Frame", "OmniCurrencyFrame", UIParent)
    currencyFrame:SetSize(220, 180)
    currencyFrame:SetFrameStrata("DIALOG")
    currencyFrame:SetClampedToScreen(true)
    currencyFrame:EnableMouse(true)
    currencyFrame:SetMovable(true)
    currencyFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    currencyFrame:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    currencyFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    currencyFrame.title = currencyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    currencyFrame.title:SetPoint("TOPLEFT", 8, -6)
    currencyFrame.title:SetText("|cFFFFCC00Currencies|r")

    currencyFrame.closeBtn = CreateFrame("Button", nil, currencyFrame, "UIPanelCloseButton")
    currencyFrame.closeBtn:SetSize(18, 18)
    currencyFrame.closeBtn:SetPoint("TOPRIGHT", -2, -2)
    currencyFrame.closeBtn:SetScript("OnClick", function() currencyFrame:Hide() end)

    currencyFrame.rows = {}
    currencyFrame:Hide()

    tinsert(UISpecialFrames, "OmniCurrencyFrame")

    return currencyFrame
end

function Features:UpdateCurrencyFrame()
    if not currencyFrame or not currencyFrame:IsShown() then return end

    -- Reuse Frame.lua's currency collectors via the Omni namespace if available
    local rows = {}
    -- Honor + Arena
    if GetHonorCurrency then
        local honor = select(1, GetHonorCurrency())
        if type(honor) == "number" and honor > 0 then
            rows[#rows + 1] = { label = "Honor Points", value = honor, icon = "Interface\\Icons\\inv_bannerpvp_01" }
        end
    end
    if GetArenaCurrency then
        local a = GetArenaCurrency()
        if type(a) == "number" and a > 0 then
            rows[#rows + 1] = { label = "Arena Points", value = a, icon = "Interface\\Icons\\achievement_pvp_h_14" }
        end
    end
    -- Tracked item currencies (mirror Frame.lua DIM.TRACKED_TOOLTIP_CURRENCIES)
    local tracked = {
        { label = "Emblem of Frost",           itemID = 49426 },
        { label = "Emblem of Triumph",         itemID = 47241 },
        { label = "Emblem of Conquest",        itemID = 45624 },
        { label = "Emblem of Valor",           itemID = 40753 },
        { label = "Emblem of Heroism",         itemID = 40752 },
        { label = "Badge of Justice",          itemID = 29434 },
        { label = "Champion's Seal",           itemID = 24131 },
        { label = "Venture Coin",              itemID = 37836 },
        { label = "Wintergrasp Mark of Honor", itemID = 43589 },
        { label = "Stone Keeper's Shard",      itemID = 43228 },
    }
    for _, entry in ipairs(tracked) do
        if GetItemCount then
            local count = GetItemCount(entry.itemID, true) or 0
            if count > 0 then
                rows[#rows + 1] = { label = entry.label, value = count, itemID = entry.itemID }
            end
        end
    end

    -- Render rows
    for i = 1, #rows do
        local row = currencyFrame.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, currencyFrame)
            row:SetHeight(18)
            row:SetPoint("LEFT", 8, 0)
            row:SetPoint("RIGHT", -8, 0)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(14, 14)
            row.icon:SetPoint("LEFT", 0, 0)
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            row.label:SetJustifyH("LEFT")
            row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.value:SetPoint("RIGHT", 0, 0)
            row.value:SetJustifyH("RIGHT")
            row.value:SetTextColor(1, 0.85, 0.25)
            currencyFrame.rows[i] = row
        end
        local yOffset = -24 - ((i - 1) * 20)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", currencyFrame, "TOPLEFT", 8, yOffset)
        row:SetPoint("TOPRIGHT", currencyFrame, "TOPRIGHT", -8, yOffset)
        local icon = rows[i].icon
        if not icon and rows[i].itemID and GetItemIcon then
            icon = GetItemIcon(rows[i].itemID)
        end
        if icon then
            row.icon:SetTexture(icon)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.icon:Show()
        else
            row.icon:Hide()
        end
        row.label:SetText(rows[i].label)
        row.value:SetText(tostring(rows[i].value))
        row:Show()
    end
    for i = #rows + 1, #currencyFrame.rows do
        currencyFrame.rows[i]:Hide()
    end

    local height = 24 + (#rows * 20) + 12
    currencyFrame:SetHeight(math.max(height, 40))
end

function Features:ToggleCurrencyFrame()
    if not currencyFrame then
        self:CreateCurrencyFrame()
    end
    if not currencyFrame then return end
    if currencyFrame:IsShown() then
        currencyFrame:Hide()
    else
        self:UpdateCurrencyFrame()
        currencyFrame:Show()
    end
end

-- =============================================================================
-- Bank Switcher (A39)
-- =============================================================================
-- Switches between bank bag views. Provides a dropdown/cycle to view
-- individual bank bags (5-11) or the main bank (-1) or all.

function Features:CycleBankBagView()
    if not Omni.BankFrame then return end
    -- Cycle: all -> -1 -> 5 -> 6 -> ... -> 11 -> all
    local current = OmniInventoryDB and OmniInventoryDB.char
        and OmniInventoryDB.char.settings and OmniInventoryDB.char.settings.selectedBankBagID
    local sequence = { nil, -1, 5, 6, 7, 8, 9, 10, 11 }
    local idx = 1
    for i, v in ipairs(sequence) do
        if v == current then
            idx = i
            break
        end
    end
    local nextVal = sequence[(idx % #sequence) + 1]
    if Omni.BankFrame.SetBankBagFilter then
        Omni.BankFrame:SetBankBagFilter(nextVal)
    end
end

-- =============================================================================
-- Initialization
-- =============================================================================

function Features:Init()
    self:InitAutoLoot()
end
