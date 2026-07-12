-- =============================================================================
-- OmniInventory Main Frame
-- =============================================================================
-- Purpose: Primary window container with header, search, content area,
-- footer, and window management (move, resize, position persistence).
-- =============================================================================

local Omni = select(2, ...)

-- Offline Character Wrapper Redirections
local GetContainerNumSlots = function(bagID)
    return OmniC_Container.GetContainerNumSlots(bagID)
end

local GetContainerNumFreeSlots = function(bagID)
    return OmniC_Container.GetContainerFreeSlots(bagID)
end

local orig_GetContainerItemInfo = GetContainerItemInfo
local GetContainerItemInfo = function(bagID, slotID)
    local viewedChar = Omni.Data and Omni.Data.currentViewedChar
    if viewedChar and viewedChar ~= Omni.Data.playerName then
        local info = OmniC_Container.GetContainerItemInfo(bagID, slotID)
        if info then
            return info.iconFileID, info.stackCount, false, info.quality, false, false, info.hyperlink
        end
        return nil
    end
    return orig_GetContainerItemInfo(bagID, slotID)
end

local orig_GetContainerItemLink = GetContainerItemLink
local GetContainerItemLink = function(bagID, slotID)
    local viewedChar = Omni.Data and Omni.Data.currentViewedChar
    if viewedChar and viewedChar ~= Omni.Data.playerName then
        local info = OmniC_Container.GetContainerItemInfo(bagID, slotID)
        return info and info.hyperlink
    end
    return orig_GetContainerItemLink(bagID, slotID)
end

Omni.Frame = {}
local Frame = Omni.Frame

-- Single table: WoW Lua allows only 200 chunk locals
local DIM = {
    FRAME_MIN_WIDTH = 350,
    FRAME_MIN_HEIGHT = 300,
    FRAME_DEFAULT_WIDTH = 450,
    FRAME_DEFAULT_HEIGHT = 400,
    HEADER_HEIGHT = 24,
    FOOTER_HEIGHT = 24,
    SEARCH_HEIGHT = 24,
    PADDING = 8,
    ITEM_SIZE = 37,
    ITEM_SPACING = 4,
    ITEM_SCALE_MIN = 0.5,
    ITEM_SCALE_MAX = 2.0,
    ITEM_GAP_MIN = 0,
    ITEM_GAP_MAX = 20,
    DEFAULT_VIEW_MODE = "flow",
    BAG_ICON_SIZE = 18,
    BAG_IDS = { 0, 1, 2, 3, 4 },
    FORCE_EMPTY_EVENT_TIMEOUT = 0.35,
    FORCE_EMPTY_MAX_LOCK_RETRIES = 20,
    FORCE_EMPTY_MAX_MOVE_RETRIES = 6,
    BURST_FULL_REFRESH_DELAY = 0.20,
    FORCED_FULL_REFRESH_COOLDOWN = 0.20,
    OPTIMISTIC_FLOW_REFRESH_TIMEOUT = 0.75,
    OPTIMISTIC_FLOW_REFRESH_SUPPRESS_WINDOW = 0.25,
    RIBBON_BTN_HEIGHT = 20,
    RIBBON_ICON_BTN_SIZE = 20,
    RIBBON_TEXT_BTN_WIDTH = 46,
    RIBBON_GAP = 3,
    RIBBON_SEP_GAP = 5,
    KEYRING_BAG_ID = -2,
    SETTINGS_ICON = "Interface\\Icons\\Trade_Engineering",
    KEYRING_ICON = "Interface\\Icons\\INV_Misc_Key_03",
    KEYRING_COLS = 8,
    KEYRING_CELL = 30,
    KEYRING_CELL_GAP = 2,
    KEYRING_PAD = 10,
    KEYRING_HEADER = 22,
    FILTER_HEIGHT = 22,
    FILTER_BUTTON_HEIGHT = 18,
    FILTER_BUTTON_SPACING = 2,
    FILTER_BUTTON_START_X = 4,
    FILTER_TEXT_PADDING_MAX = 10,
    FILTER_TEXT_PADDING_MIN = 3,
    FILTER_BUTTON_MIN_WIDTH = 22,
    FILTER_FONT_PATH = "Fonts\\FRIZQT__.TTF",
    FILTER_FONT_SIZES = { 10, 9, 8, 7 },
    FILTER_ROW_SPACING = 2,
    FILTER_ROW_TOP_PAD = 2,
    FILTER_ROW_BOTTOM_PAD = 2,
    FILTER_NEUTRAL_COLOR = { 0.75, 0.75, 0.75 },
    FOOTER_BTN_SIZE = 20,
    FOOTER_BTN_GAP = 3,
    FOOTER_SEP_GAP = 5,
    MONEY_SAFETY_GAP = 8,
    HONOR_PER_ARENA_POINT = 62,
    STONE_KEEPER_SHARDS_PER_100K_HONOR = 300,
    STONE_KEEPER_SHARD_ITEM_ID = 43228,
    WINTERGRASP_MARK_OF_HONOR_ITEM_ID = 43589,
}

DIM.SEP_SLOT_WIDTH = 1 + DIM.FOOTER_SEP_GAP * 2
DIM.OVERFLOW_SLOT_COST = DIM.FOOTER_BTN_SIZE + DIM.FOOTER_BTN_GAP

DIM.TRACKED_TOOLTIP_CURRENCIES = {
    { key = "frost",      label = "Emblem of Frost",            itemID = 49426, color = { 0.70, 0.95, 1.00 } },
    { key = "triumph",    label = "Emblem of Triumph",          itemID = 47241, color = { 1.00, 0.90, 0.45 } },
    { key = "conquest",   label = "Emblem of Conquest",         itemID = 45624, color = { 1.00, 0.78, 0.42 } },
    { key = "valor",      label = "Emblem of Valor",            itemID = 40753, color = { 1.00, 0.70, 0.30 } },
    { key = "heroism",    label = "Emblem of Heroism",          itemID = 40752, color = { 0.90, 0.85, 0.80 } },
    { key = "justice",    label = "Badge of Justice",           itemID = 29434, color = { 0.95, 0.95, 0.95 } },
    { key = "seal",       label = "Champion's Seal",            itemID = 24131, color = { 0.95, 0.82, 0.35 } },
    { key = "venture",    label = "Venture Coin",               itemID = 37836, color = { 0.40, 1.00, 0.70 } },
    { key = "wgMark",     label = "Wintergrasp Mark of Honor",  itemID = DIM.WINTERGRASP_MARK_OF_HONOR_ITEM_ID, color = { 0.65, 0.90, 1.00 } },
}

-- =============================================================================
-- Frame State
-- =============================================================================

local mainFrame = nil
-- Persistent slot-button map: slotButtons[bagID][slotID] = button.
-- Each button is created, parented to its bag's ItemContainer, and SetID
-- once out-of-combat. It is never reparented or renumbered again. During
-- combat we only mutate insecure state (alpha, icon, count), which keeps
-- every physical bag slot interactable even for items that appear while
-- PLAYER_REGEN_ENABLED is still pending.
local function GetFreeSpaceCategoryName(bagID)
    if bagID == 0 or bagID == -1 then
        return "Free Space"
    end
    local invID = ContainerIDToInventoryID(bagID)
    if invID then
        local link = GetInventoryItemLink("player", invID)
        if link then
            local _, _, _, _, _, _, _, _, _, _, _, itemClassID, itemSubClassID = GetItemInfo(link)
            if itemSubClassID and itemSubClassID > 0 then
                local bagName = GetItemInfo(link)
                if bagName then
                    return "Free Space (" .. bagName .. ")"
                end
            end
        end
    end
    return "Free Space"
end

local slotButtons = {}
local itemButtons = {}  -- Flat list of populated slot buttons (search / cooldown)
local offlineFlowButtons = {}  -- Track pool-acquired alt/offline buttons in RenderFlowView
local categoryHeaders = {}  -- Active category header FontStrings
local listRows = {}  -- Track list row frames
local currentView = DIM.DEFAULT_VIEW_MODE
local currentMode = "bags"
local isSearchActive = false
local searchText = ""
local selectedBagID = nil
local IsValidBagID
-- Remembers the view mode the user was on before clicking a
-- bag icon forced bag view. ToggleBagPreview uses it to restore the
-- prior view (flow/grid/list) when the bag is unselected.
local preBagViewMode = nil
local forceEmptyFrame = nil
local forceEmptyJob = nil

-- Combat-safety state
-- ContainerFrameItemButtonTemplate children may make OmniInventoryFrame
-- protected in 3.3.5a (IsProtected returns true). Show/Hide on a
-- protected frame are blocked from insecure/tainted code during combat.
-- If the player's key binding is CLEAN (set via Key Binding UI), the
-- binding's execution context is clean and Show/Hide work even in combat.
-- If the binding is TAINTED (from old SetBinding from addon code),
-- Show/Hide are blocked in combat.
-- The protected-child operations that ARE still forbidden in combat
-- are the structural ones on the ItemButtons themselves: SetParent,
-- SetID, SetPoint, ClearAllPoints. UpdateLayout is therefore combat-
-- gated end-to-end and PLAYER_REGEN_ENABLED replays the render once
-- combat ends. While combat is active the buttons keep whatever
-- (bag, slot, position) they were assigned before combat started, so
-- the user still sees their last known inventory and the template's
-- secure OnClick (use / pickup / equip / swap) still routes correctly.
local hasRenderedOnce = false
local pendingCombatRender = false

local burstRefreshFrame = nil
local burstRefreshElapsed = 0
local burstRefreshPending = false
local lastForcedFullRefreshAt = 0
local optimisticFlowRefreshFrame = nil
local optimisticFlowRefreshWatches = {}
local lastOptimisticFlowRefreshAt = 0
local flowLayoutCache = nil
local vendorFlowLayoutFreeze = nil
local wasMerchantOpen = false
local lastRenderedShowSignature = nil
local renderScratch = {
    categories = {},
    categoryOrder = {},
    touched = {},
    usedCategoryKeys = {},
    usedTouchedBags = {},
    headerByCategory = {},
}

local function ClearArray(t)
    for i = #t, 1, -1 do
        t[i] = nil
    end
end

local function ClearMap(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function IsMerchantOpen()
    return Omni and Omni._merchantOpen == true
end

local function HasBagChangeEntries(changedBags)
    if type(changedBags) ~= "table" then
        return false
    end
    for bagID in pairs(changedBags) do
        if type(bagID) == "number" then
            return true
        end
    end
    return false
end

local function StopBurstFullRefresh()
    burstRefreshPending = false
    burstRefreshElapsed = 0
    if burstRefreshFrame then
        burstRefreshFrame:SetScript("OnUpdate", nil)
    end
end

Frame._renderCacheEpoch = 0
Frame._layoutFlushState = Frame._layoutFlushState or {
    frame = nil,
    pending = false,
    changedBags = nil,
    opts = nil,
}

function Frame:_QueueLayoutUpdate(changedBags, opts)
    local layoutFlushState = self._layoutFlushState
    local incomingOpts = {}
    if type(opts) == "table" then
        for k, v in pairs(opts) do
            incomingOpts[k] = v
        end
    end
    layoutFlushState.opts = layoutFlushState.opts or {}

    if incomingOpts.forceFull then
        layoutFlushState.opts.forceFull = true
    end
    if incomingOpts.reason then
        layoutFlushState.opts.reason = incomingOpts.reason
    end

    if layoutFlushState.changedBags == nil then
        if type(changedBags) == "table" then
            layoutFlushState.changedBags = {}
            for bagID, changed in pairs(changedBags) do
                if type(bagID) == "number" and changed then
                    layoutFlushState.changedBags[bagID] = true
                elseif bagID == "_trigger" and changed then
                    layoutFlushState.changedBags._trigger = changed
                end
            end
        else
            layoutFlushState.changedBags = nil
        end
    elseif type(changedBags) == "table" then
        for bagID, changed in pairs(changedBags) do
            if type(bagID) == "number" and changed then
                layoutFlushState.changedBags[bagID] = true
            elseif bagID == "_trigger" and changed then
                layoutFlushState.changedBags._trigger = changed
            end
        end
    end

    if layoutFlushState.pending then
        return
    end

    layoutFlushState.pending = true
    if not layoutFlushState.frame then
        layoutFlushState.frame = CreateFrame("Frame")
    end

    layoutFlushState.frame:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        layoutFlushState.pending = false
        local flushChangedBags = layoutFlushState.changedBags
        local flushOpts = layoutFlushState.opts or {}
        layoutFlushState.changedBags = nil
        layoutFlushState.opts = nil
        flushOpts.__coalesced = true
        if Frame and Frame.UpdateLayout then
            Frame:UpdateLayout(flushChangedBags, flushOpts)
        end
    end)
end

local function TryForceFullRefresh(reason)
    local now = (GetTime and GetTime()) or 0
    if now > 0 and lastForcedFullRefreshAt > 0 and (now - lastForcedFullRefreshAt) < DIM.FORCED_FULL_REFRESH_COOLDOWN then
        return false
    end
    lastForcedFullRefreshAt = now
    if Omni.Frame and Omni.Frame.UpdateLayout then
        Omni.Frame:UpdateLayout(nil, { forceFull = true, reason = reason or "forced_full", immediate = true })
        return true
    end
    return false
end

local function RequestBurstFullRefresh()
    burstRefreshPending = true
    burstRefreshElapsed = 0

    if not burstRefreshFrame then
        burstRefreshFrame = CreateFrame("Frame")
    end

    burstRefreshFrame:SetScript("OnUpdate", function(self, elapsed)
        burstRefreshElapsed = burstRefreshElapsed + (elapsed or 0)
        if burstRefreshElapsed < DIM.BURST_FULL_REFRESH_DELAY then
            return
        end

        self:SetScript("OnUpdate", nil)
        burstRefreshPending = false
        burstRefreshElapsed = 0
        TryForceFullRefresh("burst_full")
    end)
end

local function BuildFlowItemContentSignature(items)
    local parts = {}
    for _, item in ipairs(items or {}) do
        if item and not item.__empty and item.bagID and item.slotID then
            parts[#parts + 1] = table.concat({
                tostring(item.bagID),
                tostring(item.slotID),
                tostring(item.itemID or 0),
                tostring(item.stackCount or 0),
                tostring(item.isBound and 1 or 0),
                tostring(item.bindType or 0),
                tostring(item.category or ""),
            }, "\031")
        end
    end
    table.sort(parts)
    return table.concat(parts, "\030")
end

local function GetScopedBagSlotsTotal(bagPreviewScopeSet)
    local n = 0
    for _, bagID in ipairs(DIM.BAG_IDS) do
        if not bagPreviewScopeSet or bagPreviewScopeSet[bagID] then
            n = n + (GetContainerNumSlots(bagID) or 0)
        end
    end
    return n
end

local function CountTouchedSlotsInScope(touched, bagPreviewScopeSet)
    if not touched then
        return 0
    end
    local n = 0
    for bagID, slots in pairs(touched) do
        if type(bagID) == "number" and (not bagPreviewScopeSet or bagPreviewScopeSet[bagID]) then
            for _ in pairs(slots) do
                n = n + 1
            end
        end
    end
    return n
end

local function BuildScopedSlotOccupancySignature(bagPreviewScopeSet)
    local parts = {}
    for _, bagID in ipairs(DIM.BAG_IDS) do
        if not bagPreviewScopeSet or bagPreviewScopeSet[bagID] then
            local numSlots = GetContainerNumSlots(bagID) or 0
            for slotID = 1, numSlots do
                local texture = GetContainerItemInfo(bagID, slotID)
                parts[#parts + 1] = texture and "1" or "0"
            end
        end
    end
    return table.concat(parts, "")
end

local function IsCategoryCollapsed(catName)
    if not OmniInventoryDB or not OmniInventoryDB.char or not OmniInventoryDB.char.collapsedCategories then
        return false
    end
    return OmniInventoryDB.char.collapsedCategories[catName] == true
end

local function BuildFlowCompositionSignature(categories, categoryOrder, usableWidth, itemStep, filterName)
    local parts = {
        tostring(math.floor((usableWidth or 0) + 0.5)),
        tostring(math.floor(((itemStep or 0) * 100) + 0.5)),
        tostring(filterName or "none"),
    }
    for _, catName in ipairs(categoryOrder or {}) do
        local count = categories and categories[catName] and #categories[catName] or 0
        local collapsed = IsCategoryCollapsed(catName)
        parts[#parts + 1] = tostring(catName) .. ":" .. tostring(count) .. ":" .. (collapsed and "c" or "e")
    end
    return table.concat(parts, "|")
end

function Frame:BuildFlowLaneSignature(categoryOrder, usableWidth, itemStep, filterName)
    local parts = {
        tostring(math.floor((usableWidth or 0) + 0.5)),
        tostring(math.floor(((itemStep or 0) * 100) + 0.5)),
        tostring(filterName or "none"),
    }
    for _, catName in ipairs(categoryOrder or {}) do
        local collapsed = IsCategoryCollapsed(catName)
        parts[#parts + 1] = tostring(catName) .. ":" .. (collapsed and "c" or "e")
    end
    return table.concat(parts, "|")
end

local function ItemRenderKey(itemInfo)
    if not itemInfo or itemInfo.__empty then
        return "empty:" .. tostring(Frame._renderCacheEpoch or 0)
    end
    return table.concat({
        tostring(Frame._renderCacheEpoch or 0),
        tostring(itemInfo.itemID or 0),
        tostring(itemInfo.bagID or -1),
        tostring(itemInfo.slotID or -1),
        tostring(itemInfo.hyperlink or ""),
        tostring(itemInfo.iconFileID or ""),
        tostring(itemInfo.stackCount or 1),
        tostring(itemInfo.quality or 0),
        tostring(itemInfo.category or "Miscellaneous"),
        tostring(itemInfo.isQuickFiltered == true),
    }, ":")
end

local function BuildBagSlotStateKey(info)
    if not info then
        return "EMPTY"
    end

    return table.concat({
        tostring(info.itemID or 0),
        tostring(info.hyperlink or ""),
        tostring(info.stackCount or 0),
        tostring(info.iconFileID or ""),
    }, "\031")
end

local function GetBagSlotStateKey(bagID, slotID)
    if not OmniC_Container or not bagID or not slotID or bagID < 0 or slotID < 1 then
        return nil
    end

    return BuildBagSlotStateKey(OmniC_Container.GetContainerItemInfo(bagID, slotID))
end

local function ComputeBagContentSignature()
    local parts = {}
    for _, bagID in ipairs(DIM.BAG_IDS) do
        local numSlots = GetContainerNumSlots(bagID) or 0
        parts[#parts + 1] = "b" .. tostring(bagID) .. ":" .. tostring(numSlots)
        for slotID = 1, numSlots do
            local texture, count = GetContainerItemInfo(bagID, slotID)
            if texture then
                parts[#parts + 1] = tostring(texture) .. ":" .. tostring(count or 1)
            end
        end
    end
    return table.concat(parts, "|")
end

local function RebuildPopulatedItemButtonList()
    ClearArray(itemButtons)
    IterateSlotButtons(function(_, _, btn)
        if btn and btn.itemInfo and not (btn.itemInfo and btn.itemInfo.__empty) then
            itemButtons[#itemButtons + 1] = btn
        end
    end)
end

local function DoesFlowSlotChangeRequireRelayout(previousInfo, nextInfo)
    if not previousInfo and not nextInfo then
        return false
    end

    if not previousInfo or not nextInfo then
        return true
    end

    if previousInfo.category ~= nextInfo.category then
        return true
    end

    if previousInfo.itemID ~= nextInfo.itemID then
        return true
    end

    if previousInfo.hyperlink ~= nextInfo.hyperlink then
        return true
    end

    if previousInfo.quality ~= nextInfo.quality then
        return true
    end

    if previousInfo.isBound ~= nextInfo.isBound or previousInfo.bindType ~= nextInfo.bindType then
        return true
    end

    return false
end

local function NarrowChangedBagsToSelectedScope(changedBags)
    if type(changedBags) ~= "table" then
        return changedBags
    end
    if currentView ~= "bag" then
        return changedBags
    end
    if not IsValidBagID(selectedBagID) then
        return changedBags
    end
    if changedBags._trigger then
        return changedBags
    end
    if changedBags[selectedBagID] then
        return { [selectedBagID] = true }
    end
    return {}
end

local function HasOptimisticFlowRefreshWatches()
    return next(optimisticFlowRefreshWatches) ~= nil
end

local function StopOptimisticFlowRefreshWatcher()
    optimisticFlowRefreshWatches = {}
    if optimisticFlowRefreshFrame then
        optimisticFlowRefreshFrame:SetScript("OnUpdate", nil)
    end
end

local function StartOptimisticFlowRefreshWatcher()
    if not optimisticFlowRefreshFrame then
        optimisticFlowRefreshFrame = CreateFrame("Frame")
    end

    optimisticFlowRefreshFrame:SetScript("OnUpdate", function(self, elapsed)
        if not mainFrame or not mainFrame:IsShown() or currentView ~= "flow" or InCombat() then
            StopOptimisticFlowRefreshWatcher()
            return
        end

        local slotChanged = false

        for watchKey, watch in pairs(optimisticFlowRefreshWatches) do
            watch.elapsed = (watch.elapsed or 0) + (elapsed or 0)
            if watch.elapsed >= DIM.OPTIMISTIC_FLOW_REFRESH_TIMEOUT then
                optimisticFlowRefreshWatches[watchKey] = nil
            else
                local waitingOnCursor = watch.waitForCursorClear
                    and CursorHasItem
                    and CursorHasItem()
                if not waitingOnCursor then
                    local currentKey = GetBagSlotStateKey(watch.bagID, watch.slotID)
                    if currentKey and currentKey ~= watch.stateKey then
                        slotChanged = true
                        break
                    end
                end
            end
        end

        if slotChanged then
            lastOptimisticFlowRefreshAt = (GetTime and GetTime()) or 0
            StopBurstFullRefresh()
            StopOptimisticFlowRefreshWatcher()
            TryForceFullRefresh("optimistic_flow")
            return
        end

        if not HasOptimisticFlowRefreshWatches() then
            self:SetScript("OnUpdate", nil)
        end
    end)
end

local function SetButtonItem(btn, itemInfo)
    if not btn then return end

    if btn.SetItem then
        btn:SetItem(itemInfo)
        return
    end

    if Omni.ItemButton and Omni.ItemButton.SetItem then
        Omni.ItemButton:SetItem(btn, itemInfo)
    end
end

function Frame:InvalidateRenderCaches(opts)
    opts = opts or {}
    self._renderCacheEpoch = (self._renderCacheEpoch or 0) + 1

    if not opts.clearLayout and not opts.clearSearchCache then
        return
    end

    if opts.clearLayout then
        flowLayoutCache = nil
    end

    for _, byBag in pairs(slotButtons) do
        for _, btn in pairs(byBag) do
            if btn then
                if opts.clearLayout then
                    btn._oiLayoutX = nil
                    btn._oiLayoutY = nil
                    btn._oiLayoutScale = nil
                end
                if opts.clearSearchCache then
                    btn._cachedSearchName = nil
                    btn._cachedSearchNameLower = nil
                end
            end
        end
    end
end

local function ApplyItemButtonMetrics(btn, itemScale)
    if not btn then return end
    local scale = math.max(DIM.ITEM_SCALE_MIN, math.min(itemScale or 1, DIM.ITEM_SCALE_MAX))
    local size = DIM.ITEM_SIZE * scale
    pcall(function()
        btn:SetScale(1)
        btn:SetSize(size, size)
        if btn.glow then
            btn.glow:SetSize(size * 1.5, size * 1.5)
        end
    end)
end

local function NormalizeViewMode(mode)
    if mode == "grid" or mode == "flow" or mode == "list" or mode == "bag" then
        return mode
    end
    return DIM.DEFAULT_VIEW_MODE
end

function Frame:_RefreshViewButtonLabel()
    if mainFrame and mainFrame.header and mainFrame.header.viewBtn then
        local labels = { grid = "Grid", flow = "Flow", list = "List", bag = "Bag" }
        mainFrame.header.viewBtn.text:SetText(labels[currentView] or "Grid")
    end
end

function Frame:_ActivateCombatGridFallback()
    if not self._combatGridFallbackActive then
        self._combatGridFallbackOriginalView = currentView
        self._combatGridFallbackActive = true
    end
    currentView = "grid"
    self:_RefreshViewButtonLabel()
    self:UpdateResortButtonVisibility()
    self:ApplyTheme()
end

function Frame:_RestoreCombatGridFallback()
    if not self._combatGridFallbackActive then
        return false
    end

    currentView = NormalizeViewMode(self._combatGridFallbackOriginalView)
    self._combatGridFallbackOriginalView = nil
    self._combatGridFallbackActive = false
    self:_RefreshViewButtonLabel()
    if Frame and Frame.InvalidateRenderCaches then
        Frame:InvalidateRenderCaches({ clearLayout = true })
    end
    return true
end



local function GetSavedViewMode()
    local settings = OmniInventoryDB and OmniInventoryDB.char and OmniInventoryDB.char.settings
    return NormalizeViewMode(settings and settings.viewMode)
end

local function GetSavedItemScale()
    if Omni.Data and Omni.Data.GetFrameSetting then
        return Omni.Data:GetFrameSetting("bag", "itemScale", 1.0)
    end
    local settings = OmniInventoryDB and OmniInventoryDB.char and OmniInventoryDB.char.settings
    local scale = settings and settings.itemScale
    if type(scale) ~= "number" then
        return 1
    end
    return math.max(DIM.ITEM_SCALE_MIN, math.min(scale, DIM.ITEM_SCALE_MAX))
end

local function GetSavedItemGap()
    if Omni.Data and Omni.Data.GetFrameSetting then
        return Omni.Data:GetFrameSetting("bag", "itemGap", DIM.ITEM_SPACING)
    end
    local settings = OmniInventoryDB and OmniInventoryDB.char and OmniInventoryDB.char.settings
    local gap = settings and settings.itemGap
    if type(gap) ~= "number" then
        return DIM.ITEM_SPACING
    end
    return math.max(DIM.ITEM_GAP_MIN, math.min(gap, DIM.ITEM_GAP_MAX))
end

local function ComputeShowSignature()
    local parts = {
        tostring(currentView or "flow"),
        tostring(activeFilter or "none"),
        tostring(selectedBagID or "all"),
    }
    if mainFrame then
        local w, h = mainFrame:GetSize()
        local s = mainFrame:GetScale() or 1
        parts[#parts + 1] = string.format("f:%.1f:%.1f:%.3f", w or 0, h or 0, s)
    end
    parts[#parts + 1] = ComputeBagContentSignature()
    local sortMode = "category"
    if Omni.Sorter and Omni.Sorter.GetDefaultMode then
        sortMode = Omni.Sorter:GetDefaultMode() or "category"
    end
    parts[#parts + 1] = "sort:" .. tostring(sortMode)
    parts[#parts + 1] = string.format("is:%.4f", GetSavedItemScale())
    parts[#parts + 1] = string.format("ig:%.4f", GetSavedItemGap())
    parts[#parts + 1] = "q:" .. tostring(searchText or "")
    parts[#parts + 1] = "e:" .. tostring(Frame._renderCacheEpoch or 0)
    return table.concat(parts, "|")
end

IsValidBagID = function(bagID)
    return type(bagID) == "number" and bagID >= 0 and bagID <= 4
end

local function GetSavedBagFilter()
    local settings = OmniInventoryDB and OmniInventoryDB.char and OmniInventoryDB.char.settings
    local bagID = settings and settings.selectedBagID
    if IsValidBagID(bagID) then
        return bagID
    end
    return nil
end

local function GetBagDisplayName(bagID)
    if bagID == 0 then
        return "Backpack"
    end
    local name = GetBagName and GetBagName(bagID)
    if name and name ~= "" then
        return name
    end
    return "Bag " .. tostring(bagID)
end

local function GetBagIconTexture(bagID)
    if bagID == 0 then
        return "Interface\\Buttons\\Button-Backpack-Up"
    end
    local inventorySlot = ContainerIDToInventoryID and ContainerIDToInventoryID(bagID)
    local texture = inventorySlot and GetInventoryItemTexture("player", inventorySlot)
    return texture or "Interface\\Icons\\INV_Misc_Bag_10_Blue"
end

-- =============================================================================
-- Frame Creation
-- =============================================================================

function Frame:CreateMainFrame()
    if mainFrame then return mainFrame end

    -- Main window
    mainFrame = CreateFrame("Frame", "OmniInventoryFrame", UIParent)
    mainFrame:SetSize(DIM.FRAME_DEFAULT_WIDTH, DIM.FRAME_DEFAULT_HEIGHT)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetFrameLevel(100)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:SetResizable(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetMinResize(DIM.FRAME_MIN_WIDTH, DIM.FRAME_MIN_HEIGHT)

    -- CRITICAL: secure-template anchor for combat-safe bag frame.
    --
    -- The four SecureActionButtonTemplate footer buttons (hearthstone,
    -- openables, disenchant, picklock) MUST NOT be descendants of
    -- OmniInventoryFrame.  In WoW 3.3.5a, a SecureActionButtonTemplate
    -- descendant promotes its parent chain to "protected by association",
    -- which blocks Show/Hide/SetPoint on OmniInventoryFrame from addon
    -- code during combat lockdown.  This is the same isolation pattern
    -- GudaBags uses for its Guda_HearthstoneAnchor (parented to UIParent,
    -- not to Guda_BagFrame) -- see refs/GudaBags/UI/BagFrame.lua
    -- lines 1962-1979 for the original rationale.
    --
    -- We parent the four secure buttons to this plain Frame on UIParent
    -- instead of to mainFrame.footer.  The buttons are still positioned
    -- visually over the footer via SetPoint -- SetPoint works across any
    -- parent/child boundary.  An OnShow / move / resize watcher keeps the
    -- anchor's screen coordinates aligned with mainFrame so the buttons
    -- track when the player drags the bag.
    --
    -- NOTE: ContainerFrameItemButtonTemplate (item-button) descendants do
    -- NOT promote their parent in 3.3.5a (per UI/ItemButton.lua comment
    -- at the CreateFrame call), so those are safe under mainFrame.  Only
    -- SecureActionButtonTemplate needs this isolation.
    local secureAnchor = CreateFrame("Frame", "OmniInventorySecureAnchor", UIParent)
    secureAnchor:SetSize(1, 1)
    -- Park it at a placeholder; node repositions to match the footer
    -- via the watcher installed at the end of CreateMainFrame.
    secureAnchor:SetPoint("CENTER", UIParent, "CENTER", -12000, -12000)
    secureAnchor:SetAlpha(0)
    if secureAnchor.EnableMouse then secureAnchor:EnableMouse(false) end
    secureAnchor:Hide()
    mainFrame.secureAnchor = secureAnchor
    -- Frames layered ABOVE the bag so the secure buttons visually sit on
    -- top of the footer (HIGH strata + high frame level covers this
    -- without inheriting any registered-for-input events).
    secureAnchor:SetFrameStrata("HIGH")
    secureAnchor:SetFrameLevel(200)

    -- Backdrop
    mainFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    mainFrame:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    mainFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Apply saved scale
    local scale = OmniInventoryDB and OmniInventoryDB.char and OmniInventoryDB.char.settings and OmniInventoryDB.char.settings.scale
    mainFrame:SetScale(scale or 1)

    -- Create components
    self:CreateHeader()
    self:CreateSearchBar()
    self:CreateFilterBar()
    self:CreateContentArea()
    self:CreateFooter()
    self:RefreshFooterMoneyStyle()
    self:CreateResizeHandle()

    -- Combat hint: only surfaces on the rare "opened during combat
    -- with no prior render" path. Width-constrained + word-wrapped so the
    -- message can never punch out of the frame like the old banner did.
    mainFrame.combatHint = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mainFrame.combatHint:ClearAllPoints()
    mainFrame.combatHint:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, DIM.FOOTER_HEIGHT + DIM.PADDING + 6)
    mainFrame.combatHint:SetWidth(220)
    mainFrame.combatHint:SetJustifyH("CENTER")
    mainFrame.combatHint:SetJustifyV("MIDDLE")
    mainFrame.combatHint:SetTextColor(1, 0.82, 0, 1)
    mainFrame.combatHint:SetText("")
    mainFrame.combatHint:Hide()

    self:RegisterEvents()

    -- Make ESC close the bag, like every other inventory addon.
    if UISpecialFrames then
        local already = false
        for _, n in ipairs(UISpecialFrames) do
            if n == "OmniInventoryFrame" then already = true break end
        end
        if not already then
            tinsert(UISpecialFrames, "OmniInventoryFrame")
        end
    end

    -- Focus button for Ctrl-F keybind (combat-safe keybinding override)
    local focusButton = CreateFrame("Button", "OmniSearchFocusButton", mainFrame)
    focusButton:SetScript("OnClick", function()
        if mainFrame.searchBox and mainFrame.searchBox:IsShown() then
            mainFrame.searchBox:SetFocus()
        end
    end)
    SetOverrideBinding(mainFrame, true, "CTRL-F", "CLICK OmniSearchFocusButton:LeftButton")

    -- Secure-anchor watcher: keep OmniInventorySecureAnchor offset
    -- synchronized with the footer's screen-space position so the
    -- secure footer buttons always render over the footer even after
    -- the player drags the bag. Layout chains down through hooks so
    -- any move/resize/show path keeps them aligned.
    local anchorRepositionFrame = CreateFrame("Frame")
    anchorRepositionFrame.elapsed = 0
    anchorRepositionFrame.waiting = false
    anchorRepositionFrame.debounce = 0.05
    local function RepositionSecureAnchor()
        if not (mainFrame and mainFrame.secureAnchor and mainFrame.footer) then return end
        if InCombatLockdown and InCombatLockdown() then return end
        local footer = mainFrame.footer
        -- Set scale to match mainFrame so secure buttons scale correctly and cross-parent anchoring works reliably
        local bagScale = mainFrame:GetScale() or 1
        mainFrame.secureAnchor:SetScale(bagScale)

        local x = footer:GetLeft() or 0
        local y = footer:GetBottom() or 0
        local w = footer:GetWidth() or 1
        local h = footer:GetHeight() or 1

        mainFrame.secureAnchor:ClearAllPoints()
        mainFrame.secureAnchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
        mainFrame.secureAnchor:SetSize(w, h)
    end
    anchorRepositionFrame:SetScript("OnUpdate", function(self, elapsed)
        if mainFrame and mainFrame.isMoving then
            RepositionSecureAnchor()
        elseif self.waiting then
            self.elapsed = self.elapsed + elapsed
            if self.elapsed < self.debounce then return end
            self.elapsed = 0
            self.waiting = false
            RepositionSecureAnchor()
        end
    end)
    local function requestSecureAnchorReposition()
        anchorRepositionFrame.elapsed = 0
        anchorRepositionFrame.waiting = true
    end
    local lastDonateMessageTime = nil
    local DONATE_MESSAGE_COOLDOWN = 900 -- 15 minutes

    -- Hook OnShow / drag-end events so the secure anchor follows.
    mainFrame:HookScript("OnShow", function()
        if mainFrame.secureAnchor then
            mainFrame.secureAnchor:SetAlpha(1)
            mainFrame.secureAnchor:Show()
        end
        requestSecureAnchorReposition()

        -- Donation reminder with 15-minute rate limit
        local now = GetTime()
        if not lastDonateMessageTime or (now - lastDonateMessageTime) >= DONATE_MESSAGE_COOLDOWN then
            lastDonateMessageTime = now
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[OmniInventory]|r: Like this addon? Support development at |cFF00FFFFbuymeacoffee.com/zendevve|r ☕")
            end
        end
    end)
    mainFrame:HookScript("OnHide", function()
        if Omni.Events and Omni.Events.FlushDeferredSaves then
            Omni.Events:FlushDeferredSaves()
        end
        if mainFrame.secureAnchor then
            -- Use SetAlpha(0) where allowed: Show/Hide on a frame with
            -- secure descendants is a protected op in combat, but SetAlpha
            -- is not. We are in OnHide which is itself called from a
            -- HandleShow/Hide call -- defensive SetAlpha(0) + clear-points
            -- prevents any flashed-on secure buttons when the bag closes
            -- mid-combat.  We still call Hide() out of combat to fully
            -- tear down layout.
            if InCombatLockdown and InCombatLockdown() then
                mainFrame.secureAnchor:SetAlpha(0)
            else
                mainFrame.secureAnchor:Hide()
            end
        end
    end)
    mainFrame:HookScript("OnSizeChanged", requestSecureAnchorReposition)
    if mainFrame.SetResizeBounds then
        -- SetResizeBounds doesn't always fire OnSizeChanged in 3.3.5a; add
        -- a passive monitor so screen-snap / clipped resize stays aligned.
        mainFrame.secureAnchorResizeFrame = CreateFrame("Frame")
        mainFrame.secureAnchorResizeFrame.elapsed = 0
        mainFrame.secureAnchorResizeFrame:Hide()
        mainFrame.secureAnchorResizeFrame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = self.elapsed + elapsed
            if self.elapsed < 0.2 then return end
            self.elapsed = 0
            requestSecureAnchorReposition()
        end)
        mainFrame.secureAnchorResizeFrame:Show()
    end
    mainFrame._requestSecureAnchorReposition = requestSecureAnchorReposition

    mainFrame:Hide()

    return mainFrame
end

-- =============================================================================
-- Header (power ribbon)
-- =============================================================================

local function StyleRibbonButton(btn)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.12, 0.12, 0.12, 1)
    btn:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    btn:HookScript("OnEnter", function(self)
        self:SetBackdropColor(0.22, 0.22, 0.22, 1)
        self:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        if self._tooltipTitle then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(self._tooltipTitle, 1, 1, 1)
            if self._tooltipSub then
                GameTooltip:AddLine(self._tooltipSub, 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end
    end)
    btn:HookScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.12, 0.12, 1)
        self:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        GameTooltip:Hide()
    end)
end

local function CreateRibbonTextButton(parent, label, tooltipTitle, tooltipSub, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(DIM.RIBBON_TEXT_BTN_WIDTH, DIM.RIBBON_BTN_HEIGHT)
    StyleRibbonButton(btn)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(label)

    btn._tooltipTitle = tooltipTitle
    btn._tooltipSub = tooltipSub
    btn:SetScript("OnClick", onClick)
    return btn
end

local function CreateRibbonIconButton(parent, iconTexture, tooltipTitle, tooltipSub, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(DIM.RIBBON_ICON_BTN_SIZE, DIM.RIBBON_ICON_BTN_SIZE)
    StyleRibbonButton(btn)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 2, -2)
    btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.icon:SetTexture(iconTexture)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn._tooltipTitle = tooltipTitle
    btn._tooltipSub = tooltipSub
    btn:SetScript("OnClick", onClick)
    return btn
end

-- Drag-drop landing zone for bag-slot icons in the ribbon
function Frame:EquipBagFromCursor(bagID)
    if not IsValidBagID(bagID) then return end
    if bagID == 0 then
        print("|cFF00FF00OmniInventory|r: Backpack slot cannot be swapped.")
        if ClearCursor then ClearCursor() end
        return
    end
    if InCombat() then
        print("|cFF00FF00OmniInventory|r: Cannot change bags during combat.")
        return
    end
    if not (CursorHasItem and CursorHasItem()) then return end

    local inventoryID = ContainerIDToInventoryID and ContainerIDToInventoryID(bagID)
    if not inventoryID then return end

    local targetHasBag = (GetContainerNumSlots(bagID) or 0) > 0
    if not targetHasBag then
        if PutItemInBag then
            PutItemInBag(inventoryID)
        end
        return
    end

    local tempBagID, tempSlotID
    for _, bID in ipairs(DIM.BAG_IDS) do
        if bID ~= bagID then
            local slots = GetContainerNumSlots(bID) or 0
            for slotID = 1, slots do
                local texture = GetContainerItemInfo(bID, slotID)
                if not texture then
                    tempBagID = bID
                    tempSlotID = slotID
                    break
                end
            end
        end
        if tempBagID then break end
    end

    if not tempBagID or not tempSlotID then
        print("|cFF00FF00OmniInventory|r: No free slot available to perform bag swap.")
        return
    end

    PickupContainerItem(tempBagID, tempSlotID)
    Frame:StartBagSwap(tempBagID, tempSlotID, bagID)
end

function Frame:CreateHeader()
    local header = CreateFrame("Frame", nil, mainFrame)
    header:SetHeight(DIM.HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", DIM.PADDING, -DIM.PADDING)
    header:SetPoint("TOPRIGHT", -DIM.PADDING, -DIM.PADDING)

    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    header.bg:SetVertexColor(0.15, 0.15, 0.15, 1)

    local titleBtn = CreateFrame("Button", nil, header)
    titleBtn:SetHeight(16)
    titleBtn:SetPoint("LEFT", 6, 0)

    local titleText = titleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", 0, 0)
    titleText:SetText("|cFF00FF00Omni|rInventory")
    titleBtn:SetFontString(titleText)
    titleBtn.text = titleText

    titleBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("OmniInventory Characters", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click to select another character's bags to view offline.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    titleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    titleBtn:SetScript("OnClick", function(self)
        if Omni.Frame and Omni.Frame.OpenCharacterSelectMenu then
            Omni.Frame.OpenCharacterSelectMenu(self)
        end
    end)

    header.title = titleBtn

    header.closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    header.closeBtn:SetSize(20, 20)
    header.closeBtn:SetPoint("RIGHT", -2, 0)
    header.closeBtn:SetScript("OnClick", function() Frame:Hide() end)

    -- Ribbon: rightmost wins, everything else chains leftward
    header.viewBtn = CreateRibbonTextButton(header, "Flow",
        "View Mode", "Click to cycle Grid / Flow / List / Bag",
        function() Frame:CycleView() end)
    header.viewBtn:SetPoint("RIGHT", header.closeBtn, "LEFT", -DIM.RIBBON_GAP, 0)

    header.sortBtn = CreateRibbonTextButton(header, "Sort",
        "Sort Mode", "Click to cycle the active sort",
        function() Frame:CycleSort() end)
    header.sortBtn:SetPoint("RIGHT", header.viewBtn, "LEFT", -DIM.RIBBON_GAP, 0)

    header.sortBtn:HookScript("OnEnter", function(self)
        local mode = Omni.Sorter and Omni.Sorter:GetDefaultMode() or "category"
        self._tooltipSub = "Current: " .. mode
    end)

    -- Resort button: physically sorts and consolidates the bags
    header.resortBtn = CreateRibbonIconButton(header, "Interface\\AddOns\\OmniInventory\\Textures\\Broom",
        "Resort", "Physically sort and consolidate your bags",
        function()
            if Omni.PhysicalSort then
                Omni.PhysicalSort:Sort({ consolidateStacks = true, routeSpecialized = true })
            else
                Frame:UpdateLayout(nil, { forceFull = true, reason = "resort_button" })
            end
        end)
    header.resortBtn.icon:SetTexCoord(0, 1, 0, 1) -- Keep full broom texture uncropped
    header.resortBtn:SetPoint("RIGHT", header.sortBtn, "LEFT", -DIM.RIBBON_GAP, 0)
    header.resortBtn:Hide()

    header.optBtn = CreateRibbonIconButton(header, DIM.SETTINGS_ICON,
        "Settings", "Open the OmniInventory settings panel",
        function()
            if Omni.Settings then
                Omni.Settings:Toggle()
            else
                print("|cFF00FF00OmniInventory|r: Settings not loaded")
            end
        end)
    header.optBtn:SetPoint("RIGHT", header.resortBtn, "LEFT", -DIM.RIBBON_GAP, 0)

    header.keyBtn = CreateRibbonIconButton(header, DIM.KEYRING_ICON,
        "Keyring", "Open keyring popup",
        function() Frame:ToggleKeyring() end)
    header.keyBtn:SetPoint("RIGHT", header.optBtn, "LEFT", -DIM.RIBBON_GAP, 0)

    header.bankBtn = CreateRibbonIconButton(header, "Interface\\Icons\\INV_Misc_Bag_10_Blue",
        "Bank", "Open bank window (offline/cached)",
        function()
            if Omni.BankFrame then
                Omni.BankFrame:Toggle()
            end
        end)
    header.bankBtn:SetPoint("RIGHT", header.keyBtn, "LEFT", -DIM.RIBBON_GAP, 0)

    -- Separator line between ribbon actions and bag slot icons
    header.ribbonSep = header:CreateTexture(nil, "OVERLAY")
    header.ribbonSep:SetTexture("Interface\\Buttons\\WHITE8X8")
    header.ribbonSep:SetVertexColor(0.35, 0.35, 0.35, 1)
    header.ribbonSep:SetSize(1, 14)
    header.ribbonSep:SetPoint("RIGHT", header.bankBtn, "LEFT", -DIM.RIBBON_SEP_GAP, 0)

    header.bagButtons = {}
    header.bagBar = CreateFrame("Frame", nil, header)
    header.bagBar:SetSize((DIM.BAG_ICON_SIZE + 2) * #DIM.BAG_IDS, DIM.BAG_ICON_SIZE)
    header.bagBar:SetPoint("RIGHT", header.ribbonSep, "LEFT", -DIM.RIBBON_SEP_GAP, 0)

    header.title:SetPoint("RIGHT", header.bagBar, "LEFT", -8, 0)

    for index, bagID in ipairs(DIM.BAG_IDS) do
        local bagBtn = CreateFrame("Button", nil, header.bagBar)
        bagBtn:SetSize(DIM.BAG_ICON_SIZE, DIM.BAG_ICON_SIZE)
        bagBtn:SetPoint("LEFT", (index - 1) * (DIM.BAG_ICON_SIZE + 2), 0)
        bagBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        bagBtn:RegisterForDrag("LeftButton")
        bagBtn.bagID = bagID

        bagBtn.icon = bagBtn:CreateTexture(nil, "ARTWORK")
        bagBtn.icon:SetAllPoints()
        bagBtn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        bagBtn.borderTop = bagBtn:CreateTexture(nil, "OVERLAY")
        bagBtn.borderTop:SetTexture("Interface\\Buttons\\WHITE8X8")
        bagBtn.borderTop:SetPoint("TOPLEFT", -1, 1)
        bagBtn.borderTop:SetPoint("TOPRIGHT", 1, 1)
        bagBtn.borderTop:SetHeight(1)

        bagBtn.borderBottom = bagBtn:CreateTexture(nil, "OVERLAY")
        bagBtn.borderBottom:SetTexture("Interface\\Buttons\\WHITE8X8")
        bagBtn.borderBottom:SetPoint("BOTTOMLEFT", -1, -1)
        bagBtn.borderBottom:SetPoint("BOTTOMRIGHT", 1, -1)
        bagBtn.borderBottom:SetHeight(1)

        bagBtn.borderLeft = bagBtn:CreateTexture(nil, "OVERLAY")
        bagBtn.borderLeft:SetTexture("Interface\\Buttons\\WHITE8X8")
        bagBtn.borderLeft:SetPoint("TOPLEFT", -1, 1)
        bagBtn.borderLeft:SetPoint("BOTTOMLEFT", -1, -1)
        bagBtn.borderLeft:SetWidth(1)

        bagBtn.borderRight = bagBtn:CreateTexture(nil, "OVERLAY")
        bagBtn.borderRight:SetTexture("Interface\\Buttons\\WHITE8X8")
        bagBtn.borderRight:SetPoint("TOPRIGHT", 1, 1)
        bagBtn.borderRight:SetPoint("BOTTOMRIGHT", 1, -1)
        bagBtn.borderRight:SetWidth(1)

        bagBtn:SetScript("OnClick", function(self, mouseButton)
            if mouseButton == "LeftButton" then
                -- Cursor holds a bag → swap; otherwise preview filter.
                if CursorHasItem and CursorHasItem() then
                    Frame:EquipBagFromCursor(self.bagID)
                    return
                end
                Frame:ToggleBagPreview(self.bagID)
            elseif mouseButton == "RightButton" then
                Frame:ForceEmptyBag(self.bagID)
            end
        end)

        bagBtn:SetScript("OnReceiveDrag", function(self)
            Frame:EquipBagFromCursor(self.bagID)
        end)

        bagBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(GetBagDisplayName(self.bagID), 1, 1, 1)
            -- Bag type tag (AdiBags FAMILY_TAGS) — gated by showBagTypeTags setting.
            if Omni.Features and Omni.Features.GetBagFamilyTag then
                local showTags = not Omni.Data
                    or (Omni.Data:Get("showBagTypeTags") == true)
                if showTags then
                    local tag = Omni.Features:GetBagFamilyTag(self.bagID)
                    if tag then
                        GameTooltip:AddLine("Type: " .. tag, 0.7, 0.85, 1.0)
                    end
                end
            end
            GameTooltip:AddLine("Left-click: Preview this bag", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Right-click: Force-empty bag", 0.8, 0.8, 0.8)
            if self.bagID ~= 0 then
                GameTooltip:AddLine("Drag a bag here to equip it", 0.6, 0.9, 0.6)
            end
            GameTooltip:Show()
        end)
        bagBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        header.bagButtons[bagID] = bagBtn
    end

    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        mainFrame:StartMoving()
        mainFrame.isMoving = true
    end)
    header:SetScript("OnDragStop", function()
        mainFrame:StopMovingOrSizing()
        mainFrame.isMoving = false
        Frame:SavePosition()
        if mainFrame._requestSecureAnchorReposition then
            mainFrame._requestSecureAnchorReposition()
        end
    end)

    mainFrame.header = header
end

function Frame:UpdateBagIconTextures()
    if not mainFrame or not mainFrame.header or not mainFrame.header.bagButtons then return end

    for _, bagID in ipairs(DIM.BAG_IDS) do
        local bagBtn = mainFrame.header.bagButtons[bagID]
        if bagBtn and bagBtn.icon then
            bagBtn.icon:SetTexture(GetBagIconTexture(bagID))
        end
    end
end

function Frame:UpdateResortButtonVisibility()
    if not mainFrame or not mainFrame.header then return end
    local resortBtn = mainFrame.header.resortBtn
    if not resortBtn then return end
    local showResort = Omni.Data and Omni.Data:Get("showResortButton") == true or false
    if showResort then
        resortBtn:Show()
    else
        resortBtn:Hide()
    end
end

function Frame:UpdateBagIconVisuals()
    if not mainFrame or not mainFrame.header or not mainFrame.header.bagButtons then return end

    if mainFrame.header.bagBar then
        mainFrame.header.bagBar:Show()
    end

    for _, bagID in ipairs(DIM.BAG_IDS) do
        local bagBtn = mainFrame.header.bagButtons[bagID]
        if bagBtn then
            local r, g, b = 0.4, 0.4, 0.4
            if selectedBagID == bagID then
                r, g, b = 0.2, 0.8, 0.2
            end
            if bagBtn.borderTop then bagBtn.borderTop:SetVertexColor(r, g, b, 1) end
            if bagBtn.borderBottom then bagBtn.borderBottom:SetVertexColor(r, g, b, 1) end
            if bagBtn.borderLeft then bagBtn.borderLeft:SetVertexColor(r, g, b, 1) end
            if bagBtn.borderRight then bagBtn.borderRight:SetVertexColor(r, g, b, 1) end
            bagBtn:SetAlpha(1)
        end
    end
end

-- =============================================================================
-- =============================================================================
-- Keyring Popup (bagID -2)
-- =============================================================================



function Frame:CreateKeyringPopup()
    if not mainFrame then return nil end
    if mainFrame.keyringPopup then return mainFrame.keyringPopup end

    local popup = CreateFrame("Frame", "OmniKeyringPopup", mainFrame)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(mainFrame:GetFrameLevel() + 10)
    -- Anchor above the main frame so the popup is always on-screen
    -- even when the bag is docked near the bottom of the display.
    popup:SetPoint("BOTTOMLEFT", mainFrame, "TOPLEFT", 0, 4)
    popup:SetSize(
        DIM.KEYRING_PAD * 2 + DIM.KEYRING_COLS * (DIM.KEYRING_CELL + DIM.KEYRING_CELL_GAP) - DIM.KEYRING_CELL_GAP,
        DIM.KEYRING_HEADER + DIM.KEYRING_PAD + DIM.KEYRING_CELL + DIM.KEYRING_CELL_GAP
    )
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    popup:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    popup:SetBackdropBorderColor(0.45, 0.38, 0.15, 1)

    popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    popup.title:SetPoint("TOPLEFT", DIM.KEYRING_PAD, -6)
    popup.title:SetText("|cFFFFCC00Keyring|r")

    popup.empty = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    popup.empty:SetPoint("CENTER", 0, -4)
    popup.empty:SetText("Keyring is empty.")
    popup.empty:Hide()

    popup.closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    popup.closeBtn:SetSize(18, 18)
    popup.closeBtn:SetPoint("TOPRIGHT", -2, -2)
    popup.closeBtn:SetScript("OnClick", function() popup:Hide() end)

    -- Container carries SetID(-2) so the secure template resolves
    -- to the keyring bag when a key is clicked. An explicit size keeps the
    -- child item buttons inside a non-zero hit region.
    popup.container = CreateFrame("Frame", nil, popup)
    popup.container:SetPoint("TOPLEFT", DIM.KEYRING_PAD, -(DIM.KEYRING_HEADER + 2))
    popup.container:SetPoint("BOTTOMRIGHT", -DIM.KEYRING_PAD, DIM.KEYRING_PAD)
    popup.container:SetID(DIM.KEYRING_BAG_ID)

    popup.buttons = {}
    popup:Hide()
    mainFrame.keyringPopup = popup

    popup:SetScript("OnShow", function() Frame:UpdateKeyring() end)

    tinsert(UISpecialFrames, "OmniKeyringPopup")

    if Omni.Events then
        Omni.Events:RegisterEvent("BAG_UPDATE_KEYRING", function()
            if popup:IsShown() then Frame:UpdateKeyring() end
        end)
    end

    return popup
end

function Frame:UpdateKeyring()
    if not mainFrame or not mainFrame.keyringPopup then return end
    local popup = mainFrame.keyringPopup
    if InCombat() then
        popup.empty:SetText("Keyring update deferred during combat.")
        popup.empty:Show()
        return
    end

    local slots = GetContainerNumSlots(DIM.KEYRING_BAG_ID) or 0

    if slots <= 0 then
        popup.empty:SetText("You have no keyring.")
        popup.empty:Show()
        for _, btn in ipairs(popup.buttons) do pcall(btn.Hide, btn) end
        popup:SetSize(240, DIM.KEYRING_HEADER + DIM.KEYRING_PAD * 2 + 40)
        return
    end

    popup.empty:Hide()

    for slotID = 1, slots do
        local btn = popup.buttons[slotID]
        if not btn then
            btn = Omni.ItemButton and Omni.ItemButton:Create(popup.container)
                or CreateFrame("Button", nil, popup.container, "ContainerFrameItemButtonTemplate")
            btn:SetSize(DIM.KEYRING_CELL, DIM.KEYRING_CELL)
            if btn.SetID then pcall(btn.SetID, btn, slotID) end
            popup.buttons[slotID] = btn
        end

        local col = (slotID - 1) % DIM.KEYRING_COLS
        local row = math.floor((slotID - 1) / DIM.KEYRING_COLS)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", popup.container, "TOPLEFT",
            col * (DIM.KEYRING_CELL + DIM.KEYRING_CELL_GAP),
            -row * (DIM.KEYRING_CELL + DIM.KEYRING_CELL_GAP))

        local info
        if OmniC_Container then
            info = OmniC_Container.GetContainerItemInfo(DIM.KEYRING_BAG_ID, slotID)
        end
        if info then
            if Omni.Categorizer then
                info.category = info.category or Omni.Categorizer:GetCategory(info)
            end
            SetButtonItem(btn, info)
        else
            SetButtonItem(btn, nil)
        end
        pcall(btn.Show, btn)
    end

    -- Hide any stale buttons left over from a previous larger keyring
    for slotID = slots + 1, #popup.buttons do
        local btn = popup.buttons[slotID]
        if btn then pcall(btn.Hide, btn) end
    end

    local rows = math.ceil(slots / DIM.KEYRING_COLS)
    local width = DIM.KEYRING_PAD * 2 + DIM.KEYRING_COLS * (DIM.KEYRING_CELL + DIM.KEYRING_CELL_GAP) - DIM.KEYRING_CELL_GAP
    local height = DIM.KEYRING_HEADER + DIM.KEYRING_PAD + rows * (DIM.KEYRING_CELL + DIM.KEYRING_CELL_GAP)
    popup:SetSize(width, height)
end

function Frame:ToggleKeyring()
    if InCombat() then
        print("|cFF00FF00OmniInventory|r: Keyring unavailable during combat.")
        return
    end
    local popup = mainFrame and mainFrame.keyringPopup or self:CreateKeyringPopup()
    if not popup then return end
    if popup:IsShown() then
        popup:Hide()
    else
        popup:Show()
    end
end

-- =============================================================================
-- Search Bar
-- =============================================================================

function Frame:CreateSearchBar()
    local searchBar = CreateFrame("Frame", nil, mainFrame)
    searchBar:SetHeight(DIM.SEARCH_HEIGHT)
    searchBar:SetPoint("TOPLEFT", mainFrame.header, "BOTTOMLEFT", 0, -4)
    searchBar:SetPoint("TOPRIGHT", mainFrame.header, "BOTTOMRIGHT", 0, -4)

    -- Background
    searchBar.bg = searchBar:CreateTexture(nil, "BACKGROUND")
    searchBar.bg:SetAllPoints()
    searchBar.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    searchBar.bg:SetVertexColor(0.1, 0.1, 0.1, 1)

    -- Search icon
    searchBar.icon = searchBar:CreateTexture(nil, "ARTWORK")
    searchBar.icon:SetSize(14, 14)
    searchBar.icon:SetPoint("LEFT", 6, 0)
    searchBar.icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")

    -- Help button (?)
    local helpBtn = CreateFrame("Button", nil, searchBar)
    helpBtn:SetSize(14, 14)
    helpBtn:SetPoint("RIGHT", -6, 0)
    helpBtn:SetNormalTexture("Interface\\Common\\Help-i")
    helpBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilit")
    helpBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("OmniInventory Search Query Help", 1, 0.82, 0)
        GameTooltip:AddLine("Type text to match item names (e.g. 'silk').", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Prefix-based Search:", 1, 0.82, 0)
        GameTooltip:AddLine("~t:text / tooltip:text - Search inside tooltips", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("~q:quality / quality:quality - Search by rarity (e.g. 'epic', '4')", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("~e / ~equip / equipment - Equippable items only", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Rule Engine Expressions (MyBags / Bagshui):", 1, 0.82, 0)
        GameTooltip:AddLine("Quality('epic') - Match Epic items", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Type('Armor') - Match Armor items", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Name('shadow') - Match name containing 'shadow'", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Binds('BoP') - Match soulbound items", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Id(6948) - Match Hearthstone", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Combine expressions using 'and', 'or', 'not'.", 1, 1, 1, true)
        GameTooltip:AddLine("Example: Quality('epic') and Type('Armor')", 0.6, 0.85, 1.0, true)
        GameTooltip:Show()
    end)
    helpBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Clear button (red X)
    local clearBtn = CreateFrame("Button", nil, searchBar)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", helpBtn, "LEFT", -4, 0)
    clearBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    clearBtn:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
    clearBtn:Hide()

    -- Search editbox (plain EditBox, no template to avoid white borders)
    searchBar.editBox = CreateFrame("EditBox", "OmniSearchBox", searchBar)
    searchBar.editBox:SetPoint("LEFT", searchBar.icon, "RIGHT", 4, 0)
    searchBar.editBox:SetHeight(18)
    searchBar.editBox:SetAutoFocus(false)
    searchBar.editBox:SetFontObject(ChatFontNormal)
    searchBar.editBox:SetTextColor(1, 1, 1, 1)
    searchBar.editBox:SetTextInsets(2, 2, 0, 0)
    searchBar.editBox:SetPoint("RIGHT", clearBtn, "LEFT", -4, 0)

    clearBtn:SetScript("OnClick", function()
        searchBar.editBox:SetText("")
        searchBar.editBox:ClearFocus()
    end)

    searchBar.editBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText() or ""
        isSearchActive = (searchText ~= "")
        if Frame and Frame.UpdateLayout then
            Frame:UpdateLayout(nil, { reason = "search_change" })
        end
        if searchText ~= "" then
            clearBtn:Show()
        else
            clearBtn:Hide()
        end
    end)

    searchBar.editBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    searchBar.editBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText() or ""
        if text ~= "" then
            if OmniInventoryDB and OmniInventoryDB.global then
                OmniInventoryDB.global.searchHistory = OmniInventoryDB.global.searchHistory or {}
                local history = OmniInventoryDB.global.searchHistory
                for i = #history, 1, -1 do
                    if history[i] == text then
                        table.remove(history, i)
                    end
                end
                table.insert(history, text)
                while #history > 10 do
                    table.remove(history, 1)
                end
            end
        end
        self:ClearFocus()
    end)

    local historyIndex = nil
    searchBar.editBox:SetScript("OnEditFocusGained", function(self)
        historyIndex = nil
    end)

    searchBar.editBox:SetScript("OnKeyDown", function(self, key)
        if key == "UP" or key == "DOWN" then
            if not OmniInventoryDB or not OmniInventoryDB.global or not OmniInventoryDB.global.searchHistory then return end
            local history = OmniInventoryDB.global.searchHistory
            if #history == 0 then return end

            if key == "UP" then
                if not historyIndex then
                    historyIndex = #history
                else
                    historyIndex = math.max(1, historyIndex - 1)
                end
                self:SetText(history[historyIndex])
                self:HighlightText()
            elseif key == "DOWN" then
                if historyIndex then
                    if historyIndex < #history then
                        historyIndex = historyIndex + 1
                        self:SetText(history[historyIndex])
                        self:HighlightText()
                    else
                        historyIndex = nil
                        self:SetText("")
                    end
                end
            end
        end
    end)

    mainFrame.searchBar = searchBar
    mainFrame.searchBox = searchBar.editBox
    mainFrame.searchClearBtn = clearBtn
    searchBar.clearBtn = clearBtn
    searchBar.helpBtn = helpBtn
end

-- =============================================================================
-- Quick Filter Bar
-- =============================================================================

local activeFilter = nil  -- Current active filter
local activeFilterMissingState = {
    since = nil,
    count = 0,
    clearDelay = 0.75,
    clearEvents = 4,
}

-- Static specials always rendered first. "All" clears the
-- filter, "New" matches the session-acquired flag, and everything
-- after them is generated dynamically from the categories currently
-- present in the inventory (see RebuildFilterTabs).
local SPECIAL_FILTERS = {
    { name = "All", filter = nil, color = DIM.FILTER_NEUTRAL_COLOR },
}

local function ApplyFilterButtonVisual(btn, hovered)
    local c = btn.colorTuple or DIM.FILTER_NEUTRAL_COLOR
    local r, g, b = c[1], c[2], c[3]
    local isActive = (activeFilter == btn.filterName)
    local bgIntensity
    if isActive then
        bgIntensity = 0.45
    elseif hovered then
        bgIntensity = 0.28
    else
        bgIntensity = 0.14
    end
    btn:SetBackdropColor(r * bgIntensity, g * bgIntensity, b * bgIntensity, 1)
    local borderAlpha = isActive and 1.0 or (hovered and 0.75 or 0.45)
    btn:SetBackdropBorderColor(r, g, b, borderAlpha)
    if btn.text then
        btn.text:SetTextColor(r, g, b, 1)
    end
end

local function CreateFilterButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(DIM.FILTER_BUTTON_HEIGHT)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("CENTER")
    btn:SetScript("OnClick", function(self)
        Frame:SetQuickFilter(self.filterName)
    end)
    btn:SetScript("OnEnter", function(self) ApplyFilterButtonVisual(self, true) end)
    btn:SetScript("OnLeave", function(self) ApplyFilterButtonVisual(self, false) end)
    return btn
end

local function ResolveCategoryColor(name)
    if Omni.Categorizer and name then
        local r, g, b = Omni.Categorizer:GetCategoryColor(name)
        if r and g and b then
            return { r, g, b }
        end
    end
    return DIM.FILTER_NEUTRAL_COLOR
end

function Frame:CreateFilterBar()
    local filterBar = CreateFrame("Frame", nil, mainFrame)
    filterBar:SetHeight(DIM.FILTER_HEIGHT)
    filterBar:SetPoint("TOPLEFT", mainFrame.searchBar, "BOTTOMLEFT", 0, -2)
    filterBar:SetPoint("TOPRIGHT", mainFrame.searchBar, "BOTTOMRIGHT", 0, -2)

    filterBar.bg = filterBar:CreateTexture(nil, "BACKGROUND")
    filterBar.bg:SetAllPoints()
    filterBar.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    filterBar.bg:SetVertexColor(0.08, 0.08, 0.08, 1)

    -- Button pool: buttons are created lazily as the inventory
    -- grows into new categories, then reused across refreshes. Each
    -- refresh repositions, re-labels, and re-colors them based on the
    -- categories currently in the bag.
    filterBar.buttons = {}

    mainFrame.filterBar = filterBar
end

function Frame:RebuildFilterTabs(presentCategories)
    local filterBar = mainFrame and mainFrame.filterBar
    if not filterBar then return end

    -- Assemble the ordered tab definition list: specials first,
    -- then every category that currently holds an item (sorted by the
    -- Categorizer's priority so tabs read left-to-right in the same
    -- order the sections render).
    local defs = {}
    for _, spec in ipairs(SPECIAL_FILTERS) do
        local color = spec.color or ResolveCategoryColor(spec.categoryColorFor)
        table.insert(defs, {
            name = spec.name,
            filter = spec.filter,
            color = color,
            isSpecial = spec.isSpecial,
        })
    end

    local categoryNames = {}
    if presentCategories then
        for name in pairs(presentCategories) do
            table.insert(categoryNames, name)
        end
    end
    table.sort(categoryNames, function(a, b)
        local ia = Omni.Categorizer and Omni.Categorizer:GetCategoryInfo(a) or { priority = 99 }
        local ib = Omni.Categorizer and Omni.Categorizer:GetCategoryInfo(b) or { priority = 99 }
        if (ia.priority or 99) ~= (ib.priority or 99) then
            return (ia.priority or 99) < (ib.priority or 99)
        end
        return a < b
    end)

    for _, name in ipairs(categoryNames) do
        table.insert(defs, {
            name = name,
            filter = name,
            color = ResolveCategoryColor(name),
        })
    end

    -- Single-row shrink-to-fit. We first try every tab at the
    -- default font and max padding. If the labels overflow the bar,
    -- we progressively compress: reduce padding, then step the font
    -- size down (10→9→8→7). We keep the existing wrap path as a last-
    -- resort fallback so oddly-wide labels on a tiny frame still land
    -- somewhere visible.
    local barWidth = filterBar:GetWidth()
    if not barWidth or barWidth <= 0 then
        barWidth = mainFrame:GetWidth() - 16
    end
    local rowMaxX = barWidth - DIM.FILTER_BUTTON_START_X
    local availableWidth = barWidth - DIM.FILTER_BUTTON_START_X * 2

    -- Pre-create buttons so we can measure
    for i, def in ipairs(defs) do
        local btn = filterBar.buttons[i]
        if not btn then
            btn = CreateFilterButton(filterBar)
            filterBar.buttons[i] = btn
        end
        btn.text:SetText(def.name)
    end

    local function measureForFontAndPadding(fontSize, padding)
        local widths = {}
        local total = 0
        for i, def in ipairs(defs) do
            local btn = filterBar.buttons[i]
            btn.text:SetFont(DIM.FILTER_FONT_PATH, fontSize)
            local w = math.max(btn.text:GetStringWidth() + padding * 2, DIM.FILTER_BUTTON_MIN_WIDTH)
            widths[i] = w
            total = total + w
        end
        total = total + DIM.FILTER_BUTTON_SPACING * math.max(#defs - 1, 0)
        return widths, total
    end

    -- Walk (fontSize, padding) combinations from most generous to
    -- tightest; stop at the first combo where everything fits.
    local chosenWidths = nil
    for _, fontSize in ipairs(DIM.FILTER_FONT_SIZES) do
        for padding = DIM.FILTER_TEXT_PADDING_MAX, DIM.FILTER_TEXT_PADDING_MIN, -1 do
            local widths, total = measureForFontAndPadding(fontSize, padding)
            if total <= availableWidth then
                chosenWidths = widths
                break
            end
        end
        if chosenWidths then break end
    end

    -- Fallback: use the tightest combo even if it still overflows, and
    -- allow the wrap logic below to push the leftovers onto row 2.
    if not chosenWidths then
        chosenWidths = measureForFontAndPadding(
            DIM.FILTER_FONT_SIZES[#DIM.FILTER_FONT_SIZES],
            DIM.FILTER_TEXT_PADDING_MIN
        )
    end

    local x = DIM.FILTER_BUTTON_START_X
    local row = 0
    for i, def in ipairs(defs) do
        local btn = filterBar.buttons[i]
        local finalWidth = chosenWidths[i]

        -- Wrap only if we couldn't shrink enough to fit on one row.
        if x > DIM.FILTER_BUTTON_START_X and (x + finalWidth) > rowMaxX then
            row = row + 1
            x = DIM.FILTER_BUTTON_START_X
        end

        local y = -(DIM.FILTER_ROW_TOP_PAD + row * (DIM.FILTER_BUTTON_HEIGHT + DIM.FILTER_ROW_SPACING))

        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", filterBar, "TOPLEFT", x, y)
        btn:SetSize(finalWidth, DIM.FILTER_BUTTON_HEIGHT)

        btn.filterName = def.filter
        btn.colorTuple = def.color
        btn:Show()
        ApplyFilterButtonVisual(btn, false)

        x = x + finalWidth + DIM.FILTER_BUTTON_SPACING
    end

    for i = #defs + 1, #filterBar.buttons do
        filterBar.buttons[i]:Hide()
    end

    local rowCount = (#defs > 0) and (row + 1) or 1
    local barHeight = DIM.FILTER_ROW_TOP_PAD
        + rowCount * DIM.FILTER_BUTTON_HEIGHT
        + math.max(rowCount - 1, 0) * DIM.FILTER_ROW_SPACING
        + DIM.FILTER_ROW_BOTTOM_PAD
    filterBar:SetHeight(math.max(barHeight, DIM.FILTER_HEIGHT))

    -- If the active filter's category vanished from the bag
    -- (e.g. vendored every Junk item), fall back to "All" so the user
    -- isn't stuck looking at an empty filtered view. Re-apply visuals
    -- afterward so the previously-active tab no longer reads active.
    if activeFilter then
        local stillPresent = false
        for _, def in ipairs(defs) do
            if def.filter == activeFilter then
                stillPresent = true
                break
            end
        end
        if stillPresent then
            activeFilterMissingState.since = nil
            activeFilterMissingState.count = 0
        else
            activeFilterMissingState.count = (activeFilterMissingState.count or 0) + 1
            if not activeFilterMissingState.since then
                activeFilterMissingState.since = (GetTime and GetTime()) or 0
            end
            local now = (GetTime and GetTime()) or 0
            local elapsed = now - (activeFilterMissingState.since or now)
            local shouldClear = activeFilterMissingState.count >= activeFilterMissingState.clearEvents
                and elapsed >= activeFilterMissingState.clearDelay
            if shouldClear then
                activeFilter = nil
                activeFilterMissingState.since = nil
                activeFilterMissingState.count = 0
                for i = 1, #defs do
                    ApplyFilterButtonVisual(filterBar.buttons[i], false)
                end
            end
        end
    else
        activeFilterMissingState.since = nil
        activeFilterMissingState.count = 0
    end
end

function Frame:SetQuickFilter(filterName)
    -- Toggle semantics: clicking the active tab a second time
    -- clears the filter so the bag "sorts back" to its normal LPT
    -- layout without needing a separate "All" click.
    if activeFilter ~= nil and activeFilter == filterName then
        filterName = nil
    end
    activeFilter = filterName
    activeFilterMissingState.since = nil
    activeFilterMissingState.count = 0
    self:InvalidateRenderCaches()

    if mainFrame.filterBar and mainFrame.filterBar.buttons then
        for _, btn in ipairs(mainFrame.filterBar.buttons) do
            if btn:IsShown() then
                ApplyFilterButtonVisual(btn, false)
            end
        end
    end

    self:UpdateLayout(nil, { reason = "filter_change" })
end

function Frame:GetActiveFilter()
    return activeFilter
end

-- =============================================================================
-- Content Area (ScrollFrame)
-- =============================================================================



function Frame:CreateContentArea()
    local content = CreateFrame("ScrollFrame", "OmniContentScroll", mainFrame, "UIPanelScrollFrameTemplate")
    content:SetPoint("TOPLEFT", mainFrame.filterBar, "BOTTOMLEFT", 0, -4)
    content:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -DIM.PADDING, DIM.PADDING + DIM.FOOTER_HEIGHT + 4)

    -- Scroll child
    local scrollChild = CreateFrame("Frame", "OmniContentChild", content)
    scrollChild:SetSize(content:GetWidth(), 1)  -- Height set dynamically
    content:SetScrollChild(scrollChild)

    local scrollBar = _G["OmniContentScrollScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -16)
        scrollBar:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 16)
        scrollBar:SetAlpha(0)
        scrollBar:SetWidth(1)
        scrollBar:EnableMouse(false)
        local up = _G["OmniContentScrollScrollBarScrollUpButton"]
        local down = _G["OmniContentScrollScrollBarScrollDownButton"]
        if up then
            up:SetAlpha(0)
            up:EnableMouse(false)
        end
        if down then
            down:SetAlpha(0)
            down:EnableMouse(false)
        end
        local thumb = scrollBar:GetThumbTexture()
        if thumb then thumb:SetAlpha(0) end
    end

    -- Per-bag ItemContainer frames. ContainerFrameItemButton_OnClick
    -- reads the bag from self:GetParent():GetID(), so every item button
    -- must live under a parent whose SetID matches its bag. We create
    -- one zero-size insecure Frame per bag (and a -1 slot for stray
    -- buttons), pin them at scrollChild origin, and reparent buttons
    -- into them at acquire time. The bag IDs themselves are insecure so
    -- SetID here is allowed even in combat, but we only ever hand out
    -- the table OOC so it doesn't matter.
    mainFrame.itemContainers = {}
    local function MakeItemContainer(bagID)
        local f = CreateFrame("Frame", nil, scrollChild)
        f:SetSize(1, 1)
        f:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        f:SetID(bagID)
        f:Show()
        mainFrame.itemContainers[bagID] = f
        return f
    end
    for _, bagID in ipairs(DIM.BAG_IDS) do
        MakeItemContainer(bagID)
    end
    MakeItemContainer(-1)
    mainFrame._makeItemContainer = MakeItemContainer

    mainFrame.content = content
    mainFrame.scrollChild = scrollChild
end

-- Lazy-fetch (or create OOC) the per-bag ItemContainer for `bagID`.
-- Hot path called from RenderFlowView for every item, so cheap. Returns
-- nil when called in combat for a bag we have not seen before -- callers
-- treat that as "no container, skip this button".
local function GetItemContainer(bagID)
    if not mainFrame or not mainFrame.itemContainers then return nil end
    local container = mainFrame.itemContainers[bagID]
    if container then return container end
    if InCombat() and not Frame._combatGridBootstrap then return nil end
    if mainFrame._makeItemContainer then
        return mainFrame._makeItemContainer(bagID)
    end
    return nil
end
Frame._GetItemContainer = GetItemContainer

-- =============================================================================
-- Persistent Slot-Button Map
-- =============================================================================
-- Why this exists
-- ContainerFrameItemButtonTemplate is a protected frame. Structural ops
-- (SetParent, SetPoint, ClearAllPoints, SetID, Show, Hide) are forbidden
-- during combat. The ONLY way to guarantee a new item arriving mid-combat
-- is still clickable is to pre-allocate a button for every physical bag
-- slot out-of-combat, then touch ONLY insecure state (SetAlpha, icon,
-- count) when combat fills or empties it.

local OVERFLOW_ROW_GAP = 4
local EMPTY_SLOT_ALPHA = 1
-- show_open: sync-paint first N flow cells; defer SetItem for the rest
local FLOW_SHOW_OPEN_DEFER_AFTER = 36

local deferredFlowPaintQueue = {}
local deferredFlowPaintFrame

local function GetSlotButton(bagID, slotID)
    local byBag = slotButtons[bagID]
    if not byBag then return nil end
    return byBag[slotID]
end
Frame._GetSlotButton = GetSlotButton

local function CreateSlotButton(bagID, slotID)
    if InCombat() and not Frame._combatGridBootstrap then return nil end

    local container = GetItemContainer(bagID)
    if not container then return nil end

    local btn
    local fromPool = false
    if Frame._combatGridBootstrap and Omni.ItemButton then
        local createdOK, created = pcall(Omni.ItemButton.Create, Omni.ItemButton, container)
        if createdOK then
            btn = created
        end
    end
    if not btn and Omni.Pool then
        local acquiredOK, acquired = pcall(Omni.Pool.Acquire, Omni.Pool, "ItemButton")
        if acquiredOK then
            btn = acquired
            fromPool = btn ~= nil
        end
    end
    if not btn and Omni.ItemButton then
        local createdOK, created = pcall(Omni.ItemButton.Create, Omni.ItemButton, container)
        if createdOK then
            btn = created
        end
    end
    if not btn then return nil end

    local ok = pcall(function()
        if btn:GetParent() ~= container then
            btn:SetParent(container)
        end
        if btn.SetID then btn:SetID(slotID) end
        ApplyItemButtonMetrics(btn, GetSavedItemScale())
        btn:ClearAllPoints()
        btn:SetAlpha(0)
        btn:Show()
    end)

    local parentOK = btn.GetParent and btn:GetParent() == container
    local idOK = (not btn.GetID) or btn:GetID() == slotID
    if not ok and not (parentOK and idOK) then
        if fromPool and Omni.Pool then
            Omni.Pool:Release("ItemButton", btn)
        else
            pcall(btn.Hide, btn)
        end
        return nil
    end

    btn.bagID = bagID
    btn.slotID = slotID

    return btn
end

-- Ensure every physical bag slot has a persistent button. Called
-- OOC from RenderFlowView. Grows on bag upgrades and releases surplus
-- buttons back to the pool when a bag is swapped for something smaller.
local function EnsureSlotButtons()
    if InCombat() and not Frame._combatGridBootstrap then return end

    for _, bagID in ipairs(DIM.BAG_IDS) do
        slotButtons[bagID] = slotButtons[bagID] or {}
        local byBag = slotButtons[bagID]
        local numSlots = GetContainerNumSlots(bagID) or 0

        for slotID = 1, numSlots do
            if not byBag[slotID] then
                byBag[slotID] = CreateSlotButton(bagID, slotID)
            end
        end

        for slotID, btn in pairs(byBag) do
            if slotID > numSlots then
                if Omni.Pool then
                    Omni.Pool:Release("ItemButton", btn)
                end
                pcall(btn.Hide, btn)
                byBag[slotID] = nil
            end
        end
    end
end
Frame._EnsureSlotButtons = EnsureSlotButtons

local function IterateSlotButtons(callback)
    for _, bagID in ipairs(DIM.BAG_IDS) do
        local byBag = slotButtons[bagID]
        if byBag then
            local numSlots = GetContainerNumSlots(bagID) or 0
            for slotID = 1, numSlots do
                local btn = byBag[slotID]
                if btn then
                    callback(bagID, slotID, btn)
                end
            end
        end
    end
end
Frame._IterateSlotButtons = IterateSlotButtons

-- Live slot query after AH embed / fast-show — layout often ran first
local function RefreshSlotButtonFromLiveContainer(bagID, slotID, btn)
    if not btn or not OmniC_Container or not bagID or not slotID then
        return
    end
    local info = OmniC_Container.GetContainerItemInfo(bagID, slotID)
    if not info then
        return
    end
    if Omni.Categorizer then
        info.category = Omni.Categorizer:GetCategory(info)
    end
    if btn.itemInfo then
        info.isQuickFiltered = btn.itemInfo.isQuickFiltered
    end
    SetButtonItem(btn, info)
end



local function CancelDeferredFlowItemPaint()
    if deferredFlowPaintFrame then
        deferredFlowPaintFrame:SetScript("OnUpdate", nil)
    end
    ClearArray(deferredFlowPaintQueue)
end

local function ScheduleDeferredFlowItemPaint()
    if #deferredFlowPaintQueue == 0 then
        return
    end
    if not deferredFlowPaintFrame then
        deferredFlowPaintFrame = CreateFrame("Frame")
    end
    deferredFlowPaintFrame:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        if not mainFrame or not mainFrame:IsShown() then
            ClearArray(deferredFlowPaintQueue)
            return
        end
        for i = 1, #deferredFlowPaintQueue do
            local pair = deferredFlowPaintQueue[i]
            local btn = pair[1]
            local slotItem = pair[2]
            deferredFlowPaintQueue[i] = nil
            if btn and slotItem then
                local ok = pcall(function()
                    SetButtonItem(btn, slotItem)
                    btn._oiRenderKey = ItemRenderKey(slotItem)
                    btn:Show()
                    local a = slotItem.__empty and EMPTY_SLOT_ALPHA or 1
                    btn:SetAlpha(a)
                end)
                if not ok then
                    pcall(SetButtonItem, btn, nil)
                    if btn.icon then btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
                    pcall(btn.Show, btn)
                    btn._oiRenderKey = "error"
                end
            end
        end
        ClearArray(deferredFlowPaintQueue)
    end)
end

function Frame:_HasAnySlotButtons()
    for _, byBag in pairs(slotButtons) do
        if byBag and next(byBag) ~= nil then
            return true
        end
    end
    return false
end

function Frame:RenderCombatGridFallback()
    if not mainFrame or not mainFrame.scrollChild then
        return false
    end

    self:_ActivateCombatGridFallback()
    self._combatGridBootstrap = true

    local ok = pcall(function()
        local items = {}
        if OmniC_Container then
            items = OmniC_Container.GetAllBagItems()
        end

        self:RenderFlowView(items)
        self:UpdateBagIconTextures()
        self:UpdateBagIconVisuals()
        self:UpdateSlotCount()
        self:UpdateMoney()

        if searchText and searchText ~= "" then
            self:ApplySearch(searchText)
        end
    end)

    self._combatGridBootstrap = false

    if ok and self:_HasAnySlotButtons() then
        hasRenderedOnce = true
        lastRenderedShowSignature = ComputeShowSignature()
        return true
    end

    return false
end

-- =============================================================================
-- Footer
-- =============================================================================

-- Footer custom launcher buttons
local function FindHearthstone()
    for bagID = 0, 4 do
        local slots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, slots do
            local link = GetContainerItemLink(bagID, slotID)
            if link then
                local itemID = tonumber(string.match(link, "item:(%d+)"))
                if itemID == 6948 then
                    return bagID, slotID
                end
            end
        end
    end
    return nil, nil
end

local function FindFirstOpenableContainer()
    for bagID = 0, 4 do
        local slots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, slots do
            local info = OmniC_Container.GetContainerItemInfo(bagID, slotID)
            if info and info.hasLoot and info.hyperlink then
                return bagID, slotID, info.hyperlink
            end
        end
    end
    return nil, nil, nil
end

local function HasSpell(spellName)
    local i = 1
    while true do
        local sName = GetSpellName(i, BOOKTYPE_SPELL)
        if not sName then break end
        if sName == spellName then
            return true
        end
        i = i + 1
    end
    return false
end

-- Footer custom launcher buttons
local FOOTER_CUSTOM_BUTTONS = {
    {
        key     = "clearGlow",
        icon    = "Interface\\Icons\\Spell_Holy_Purify",
        title   = "Mark All Read",
        sub     = "Clears the golden new item glow from all items in your bags.",
        onClick = function()
            if Omni.NewItems then
                wipe(Omni.NewItems)
            end
            if Omni.Categorizer and Omni.Categorizer.ClearAllNewItems then
                Omni.Categorizer:ClearAllNewItems()
            end
            for _, byBag in pairs(slotButtons) do
                for _, btn in pairs(byBag) do
                    if btn and btn.newGlow then
                        if btn.newGlow.pulse then btn.newGlow.pulse:Stop() end
                        btn.newGlow:Hide()
                    end
                end
            end
            if Omni.Frame and Omni.Frame.UpdateLayout then
                Omni.Frame:InvalidateRenderCaches({ clearLayout = true })
                Omni.Frame:UpdateLayout()
            end
            if Omni.BankFrame and Omni.BankFrame.UpdateLayout then
                Omni.BankFrame:UpdateLayout()
            end
            print("|cFF00FF00Omni|r: All new items marked as read.")
        end,
    },
    {
        key     = "resetInstances",
        icon    = "Interface\\Icons\\Achievement_Boss_Murmur",
        title   = "Reset Instances",
        sub     = "Teleports out of the current LFG dungeon (if any) and resets all instances.",
        onClick = function()
            if type(_G.LFGTeleport) == "function" and type(_G.IsInLFGDungeon) == "function" then
                LFGTeleport(IsInLFGDungeon())
            end
            if type(_G.ResetInstances) == "function" then
                _G.ResetInstances()
            end
        end,
    },
    {
        key     = "hearthstone",
        icon    = "Interface\\Icons\\INV_Misc_Rune_01",
        title   = "Hearthstone",
        sub     = "Left-click to pick up. Right-click to cast.",
        secure  = true,
        secureAttributes = {
            ["type2"] = "item",
            ["item2"] = "Hearthstone",
        },
        onClick = function(self, button)
            if button == "LeftButton" then
                local bagID, slotID = FindHearthstone()
                if bagID and slotID then
                    PickupContainerItem(bagID, slotID)
                else
                    print("|cFF00FF00OmniInventory|r: Hearthstone not found in bags.")
                end
            end
        end,
        onDragStart = function(self)
            local bagID, slotID = FindHearthstone()
            if bagID and slotID then
                PickupContainerItem(bagID, slotID)
            end
        end,
        onEnter = function(self)
            self:SetBackdropBorderColor(0.9, 0.8, 0.2, 1)
            local bagID, slotID = FindHearthstone()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if bagID and slotID then
                GameTooltip:SetBagItem(bagID, slotID)
            else
                GameTooltip:SetHyperlink("item:6948")
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Not found in bags", 1, 0, 0)
            end
            GameTooltip:Show()
        end,
        onLeave = function(self)
            self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.6)
            GameTooltip:Hide()
        end,
        isAvailable = function()
            return FindHearthstone() ~= nil
        end,
    },
    {
        key     = "openables",
        icon    = "Interface\\Icons\\INV_Misc_Clam_01",
        title   = "Openable Opener",
        sub     = "Left-click to pick up. Right-click to open.",
        secure  = true,
        secureAttributes = {
            ["type2"] = "item",
        },
        onClick = function(self, button)
            if button == "LeftButton" then
                local bagID, slotID = FindFirstOpenableContainer()
                if bagID and slotID then
                    PickupContainerItem(bagID, slotID)
                end
            elseif button == "RightButton" then
                if not self:GetAttribute("item2") then
                    print("|cFF00FF00OmniInventory|r: No openable containers found in bags.")
                end
            end
        end,
        onEnter = function(self)
            self:SetBackdropBorderColor(0.9, 0.8, 0.2, 1)
            local bagID, slotID = FindFirstOpenableContainer()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if bagID and slotID then
                GameTooltip:SetBagItem(bagID, slotID)
            else
                GameTooltip:SetText("Openable Opener", 1, 0.82, 0)
                GameTooltip:AddLine("No openable containers (clams, lockboxes) found.", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end,
        onLeave = function(self)
            self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.6)
            GameTooltip:Hide()
        end,
    },
    {
        key     = "disenchant",
        icon    = "Interface\\Icons\\Spell_Holy_RemoveCurse",
        title   = "Disenchant",
        sub     = "Right-click to disenchant an item in your bags.",
        secure  = true,
        secureAttributes = {
            ["type2"] = "spell",
            ["spell2"] = "Disenchant",
        },
        isAvailable = function()
            return HasSpell("Disenchant")
        end,
    },
    {
        key     = "picklock",
        icon    = "Interface\\Icons\\Spell_Nature_RogueProgress",
        title   = "Pick Lock",
        sub     = "Right-click to pick a lockbox in your bags.",
        secure  = true,
        secureAttributes = {
            ["type2"] = "spell",
            ["spell2"] = "Pick Lock",
        },
        isAvailable = function()
            return HasSpell("Pick Lock")
        end,
    },
}

local function IsFooterCustomButtonEnabled(key)
    local global = OmniInventoryDB and OmniInventoryDB.global
    if not global then return true end
    global.footerButtons = global.footerButtons or {}
    if global.footerButtons[key] == nil then
        global.footerButtons[key] = true
    end
    return global.footerButtons[key] ~= false
end

local function StyleFooterMiniButton(btn)
    btn:SetBackdrop({
        edgeFile = "Interface\\Buttons\\UI-Quickslot-Depress",
        edgeSize = 2,
        insets = { left = -1, right = -1, top = -1, bottom = -1 },
    })
    btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.6)

    btn:HookScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.9, 0.8, 0.2, 1)
        if self._tooltipTitle then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self._tooltipTitle, 1, 1, 1)
            if self._tooltipSub then
                GameTooltip:AddLine(self._tooltipSub, 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end
    end)
    btn:HookScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.6)
        GameTooltip:Hide()
    end)
end

local function CreateFooterMiniButton(parent, def)
    -- SecureActionButtonTemplate buttons MUST be parented outside the
    -- mainFrame chain (see OmniInventorySecureAnchor in CreateMainFrame).
    -- 3.3.5a's combat lockdown propagates protected status from a
    -- SecureActionButtonTemplate descendant up through its parent chain,
    -- which would make Show/Hide on OmniInventoryFrame forbidden in
    -- combat.  We arrange for those buttons to live under
    -- mainFrame.secureAnchor (a plain Frame on UIParent) and let
    -- SetPoint place them visually over the footer.
    local actualParent = parent
    if def.secure then
        if mainFrame and mainFrame.secureAnchor then
            actualParent = mainFrame.secureAnchor
        else
            -- mainFrame not yet built (in standalone test contexts) --
            -- fall back to the regular parent so the button still works.
            actualParent = parent
        end
    end

    local template = def.secure and "SecureActionButtonTemplate" or nil
    local btn = CreateFrame("Button", nil, actualParent, template)
    btn:RegisterForClicks("AnyUp")

    if def.secure then
        for k, v in pairs(def.secureAttributes or {}) do
            btn:SetAttribute(k, v)
        end
    end

    btn:SetSize(DIM.FOOTER_BTN_SIZE, DIM.FOOTER_BTN_SIZE)

    local trim = def.trimIcon ~= false
    local iconTex = btn:CreateTexture(nil, "OVERLAY")
    iconTex:SetAllPoints(btn)
    iconTex:SetTexture(def.icon)
    if trim then
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    btn.icon = iconTex

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(btn)
    hl:SetTexture(def.icon)
    if trim then
        hl:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    hl:SetBlendMode("ADD")
    hl:SetVertexColor(0.25, 0.25, 0.25, 0.4)

    StyleFooterMiniButton(btn)

    if not def.onEnter then
        btn._tooltipTitle = def.title
        btn._tooltipSub = def.sub
    else
        btn:SetScript("OnEnter", def.onEnter)
    end
    if type(def.onLeave) == "function" then
        btn:SetScript("OnLeave", def.onLeave)
    end

    btn:SetScript("OnMouseDown", function(self)
        if self.icon then self.icon:SetVertexColor(0.75, 0.75, 0.75) end
    end)
    btn:SetScript("OnMouseUp", function(self)
        if self.icon then self.icon:SetVertexColor(1, 1, 1) end
    end)

    if type(def.onClick) == "function" then
        if def.secure then
            btn:SetScript("PreClick", def.onClick)
        else
            btn:SetScript("OnClick", def.onClick)
        end
    elseif type(def.fn) == "string" then
        btn.__openFn = def.fn
        btn.__closeFn = def.fn:gsub("^Open", "Close")
        btn.__toggleFrame = def.toggleFrame
        btn:SetScript("OnClick", function(self)
            local openFn = _G[self.__openFn]
            local closeFn = _G[self.__closeFn]
            local toggleFrName = self.__toggleFrame
            local toggleFr = toggleFrName and _G[toggleFrName]

            if toggleFr and toggleFr.IsShown and toggleFr:IsShown() then
                if type(closeFn) == "function" then
                    closeFn()
                elseif toggleFr.Hide then
                    toggleFr:Hide()
                end
                return
            end

            if type(openFn) == "function" then
                openFn()
            else
                print("|cFF00FF00OmniInventory|r: " .. self.__openFn .. "() is not available on this client.")
            end
        end)
    end

    if type(def.onDragStart) == "function" then
        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnDragStart", def.onDragStart)
    end
    if type(def.onReceiveDrag) == "function" then
        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnReceiveDrag", def.onReceiveDrag)
    end
    return btn
end

local function AddThousandsSeparators(value)
    local str = tostring(math.floor(tonumber(value) or 0))
    local sign = ""
    if string.sub(str, 1, 1) == "-" then
        sign = "-"
        str = string.sub(str, 2)
    end
    local left, count = str, 0
    repeat
        left, count = string.gsub(left, "^(-?%d+)(%d%d%d)", "%1,%2")
    until count == 0
    return sign .. left
end

local function FormatTooltipNumber(value)
    value = tonumber(value) or 0
    local absValue = math.abs(value)
    if absValue >= 1000000 then
        return string.format("%.1fM", value / 1000000)
    end
    if absValue >= 1000 then
        return AddThousandsSeparators(value)
    end
    return tostring(math.floor(value))
end

local function FormatTooltipLabelIcon(itemID, fallbackIcon, label)
    local icon = fallbackIcon
    if itemID and GetItemIcon then
        icon = GetItemIcon(itemID) or icon
    end
    if icon then
        return string.format("|T%s:13:13:0:0|t %s", icon, label)
    end
    return label
end

local function FormatTooltipIconLabel(iconPath, label)
    if iconPath and iconPath ~= "" then
        return string.format("|T%s:13:13:0:0|t %s", iconPath, label)
    end
    return label
end

local function GetCurrentHonorPoints()
    if GetHonorCurrency then
        local honor = select(1, GetHonorCurrency())
        if type(honor) == "number" then
            return honor
        end
    end
    return 0
end

local function GetCurrentArenaPoints()
    if GetArenaCurrency then
        local a, b, c = GetArenaCurrency()
        if type(a) == "number" and a >= 0 then
            return a
        end
        if type(b) == "number" and b >= 0 then
            return b
        end
        if type(c) == "number" and c >= 0 then
            return c
        end
    end
    if GetArenaPoints then
        local arena = GetArenaPoints()
        if type(arena) == "number" and arena >= 0 then
            return arena
        end
    end
    return 0
end

local function GetStoneKeeperShardCount()
    if GetCurrencyInfo then
        local _, amount = GetCurrencyInfo(161)
        if type(amount) == "number" and amount > 0 then
            return amount
        end
    end
    if GetItemCount then
        return GetItemCount(DIM.STONE_KEEPER_SHARD_ITEM_ID, true) or 0
    end
    return 0
end

local function GetTrackedItemCurrencyCount(itemID)
    if not itemID or not GetItemCount then
        return 0
    end
    return GetItemCount(itemID, true) or 0
end

local function CollectTooltipCurrencies()
    local rows = {
        {
            key = "honor",
            label = "Honor Points",
            value = GetCurrentHonorPoints(),
            color = { 0.95, 0.35, 0.35 },
            icon = "Interface\\Icons\\inv_bannerpvp_01",
        },
        {
            key = "arena",
            label = "Arena Points",
            value = GetCurrentArenaPoints(),
            color = { 0.45, 0.85, 1.00 },
            icon = "Interface\\Icons\\achievement_pvp_h_14",
        },
    }

    for i = 1, #DIM.TRACKED_TOOLTIP_CURRENCIES do
        local entry = DIM.TRACKED_TOOLTIP_CURRENCIES[i]
        rows[#rows + 1] = {
            key = entry.key,
            label = entry.label,
            value = GetTrackedItemCurrencyCount(entry.itemID),
            itemID = entry.itemID,
            color = entry.color,
        }
    end

    rows[#rows + 1] = {
        key = "stoneKeeperShard",
        label = "Stone Keeper's Shard",
        value = GetStoneKeeperShardCount(),
        itemID = DIM.STONE_KEEPER_SHARD_ITEM_ID,
        color = { 0.80, 0.80, 1.00 },
    }

    return rows
end

local function ShowFooterMoneyTooltip(owner)
    if not owner then
        return
    end

    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText("Money", 1, 0.85, 0.25)
    GameTooltip:AddLine(
        FormatTooltipIconLabel("Interface\\MoneyFrame\\UI-GoldIcon", (owner._moneyText and owner._moneyText ~= "") and owner._moneyText or "0"),
        1, 1, 1
    )

    -- Alt Gold Breakdown
    local realmName = GetRealmName()
    local realmData = OmniInventoryDB and OmniInventoryDB.realm and OmniInventoryDB.realm[realmName]
    if realmData then
        local alts = {}
        local totalGold = 0
        local currentPlayer = UnitName("player")
        for charName, charData in pairs(realmData) do
            local gold = charData.gold or 0
            totalGold = totalGold + gold
            table.insert(alts, { name = charName, gold = gold, isCurrent = (charName == currentPlayer) })
        end

        if #alts > 1 then
            table.sort(alts, function(a, b)
                if a.isCurrent ~= b.isCurrent then
                    return a.isCurrent
                end
                return a.name < b.name
            end)

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Characters", 0.6, 0.85, 1)
            for _, alt in ipairs(alts) do
                local nameStr = alt.name
                if alt.isCurrent then
                    nameStr = "|cfffffffff" .. nameStr .. " (You)|r"
                else
                    nameStr = "|cff00ff9a" .. nameStr .. "|r"
                end
                local formatted = Omni.Utils and Omni.Utils.FormatMoney and Omni.Utils:FormatMoney(alt.gold) or (math.floor(alt.gold / 10000) .. "g")
                GameTooltip:AddDoubleLine(nameStr, formatted, 1, 1, 1, 1, 1, 1)
            end
            GameTooltip:AddLine(" ")
            local totalFormatted = Omni.Utils and Omni.Utils.FormatMoney and Omni.Utils:FormatMoney(totalGold) or (math.floor(totalGold / 10000) .. "g")
            GameTooltip:AddDoubleLine("|cffc7c7cfTotal Gold|r", totalFormatted, 1, 0.85, 0.25, 1, 1, 1)
        end
    end

    local currencies = CollectTooltipCurrencies()
    if #currencies > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Currencies", 0.6, 0.85, 1)
        for i = 1, #currencies do
            local row = currencies[i]
            local value = tonumber(row.value) or 0
            if value > 0 then
                local color = row.color or { 0.9, 0.9, 0.9 }
                local leftLabel = FormatTooltipLabelIcon(row.itemID, row.icon, row.label)
                local rightValue = FormatTooltipNumber(value)
                GameTooltip:AddDoubleLine(leftLabel, rightValue, color[1], color[2], color[3], 1, 1, 1)
            end
        end

        local honor = GetCurrentHonorPoints()
        local stoneKeeperShards = GetStoneKeeperShardCount()
        local honorFromShards = math.floor(stoneKeeperShards * (100000 / DIM.STONE_KEEPER_SHARDS_PER_100K_HONOR))
        local totalHonor = honor + honorFromShards
        local arenaFromTotalHonor = math.floor(totalHonor / DIM.HONOR_PER_ARENA_POINT)

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Conversions", 0.8, 0.7, 1)
        if arenaFromTotalHonor > 0 then
            GameTooltip:AddDoubleLine(
                FormatTooltipIconLabel("Interface\\Icons\\achievement_pvp_h_14", "Arena from Total Honor (62:1)"),
                FormatTooltipNumber(arenaFromTotalHonor),
                0.45, 0.85, 1.00, 1, 1, 1
            )
        end
        if honorFromShards > 0 then
            GameTooltip:AddDoubleLine(
                FormatTooltipIconLabel("Interface\\Icons\\inv_bannerpvp_01", "Honor from Shards"),
                FormatTooltipNumber(honorFromShards),
                0.95, 0.35, 0.35, 1, 1, 1
            )
        end
        if honorFromShards > 0 then
            GameTooltip:AddDoubleLine(
                FormatTooltipIconLabel("Interface\\Icons\\inv_bannerpvp_01", "Total Honor (current+shards)"),
                FormatTooltipNumber(totalHonor),
                0.95, 0.55, 0.55, 1, 1, 1
            )
        end
    end

    GameTooltip:Show()
end

function Frame:CreateFooter()
    local footer = CreateFrame("Frame", nil, mainFrame)
    footer:SetHeight(DIM.FOOTER_HEIGHT)
    footer:SetPoint("BOTTOMLEFT", DIM.PADDING, DIM.PADDING)
    footer:SetPoint("BOTTOMRIGHT", -DIM.PADDING, DIM.PADDING)

    footer.bg = footer:CreateTexture(nil, "BACKGROUND")
    footer.bg:SetAllPoints()
    footer.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    footer.bg:SetVertexColor(0.15, 0.15, 0.15, 1)

    footer.topBorder = footer:CreateTexture(nil, "BORDER")
    footer.topBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    footer.topBorder:SetVertexColor(0.35, 0.35, 0.35, 1)
    footer.topBorder:SetHeight(1)
    footer.topBorder:SetPoint("TOPLEFT", 0, 0)
    footer.topBorder:SetPoint("TOPRIGHT", 0, 0)

    -- FontString has no EnableMouse in 3.3.5a — use a button as hit box for the !
    footer.bagFullAlert = CreateFrame("Button", nil, footer)
    footer.bagFullAlert:SetPoint("LEFT", 6, 0)
    footer.bagFullAlert:SetHeight(DIM.FOOTER_HEIGHT)
    footer.bagFullAlert:SetWidth(16)
    footer.bagFullAlert:EnableMouse(true)
    footer.bagFullAlert.label = footer.bagFullAlert:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    footer.bagFullAlert.label:SetPoint("CENTER", 0, 0)
    footer.bagFullAlert.label:SetText("!")
    footer.bagFullAlert.label:SetTextColor(1, 0.12, 0.12, 1)
    footer.bagFullAlert:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Bags full", 1, 0.12, 0.12)
        GameTooltip:AddLine("No free inventory slots.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    footer.bagFullAlert:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    footer.bagFullAlert:Hide()

    footer.slots = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footer.slots:SetPoint("LEFT", 6, 0)
    footer.slots:SetText("0/0")

    footer.slotsSep = footer:CreateTexture(nil, "OVERLAY")
    footer.slotsSep:SetTexture("Interface\\Buttons\\WHITE8X8")
    footer.slotsSep:SetVertexColor(0.35, 0.35, 0.35, 1)
    footer.slotsSep:SetSize(1, 14)
    footer.slotsSep:Hide()



    footer.customSep = footer:CreateTexture(nil, "OVERLAY")
    footer.customSep:SetTexture("Interface\\Buttons\\WHITE8X8")
    footer.customSep:SetVertexColor(0.35, 0.35, 0.35, 1)
    footer.customSep:SetSize(1, 14)
    footer.customSep:Hide()

    footer.customButtons = {}
    for _, def in ipairs(FOOTER_CUSTOM_BUTTONS) do
        local btn = CreateFooterMiniButton(footer, def)
        btn:Hide()
        btn.__def = def
        footer.customButtons[def.key] = btn
    end
    footer.customButtonOrder = FOOTER_CUSTOM_BUTTONS



    footer.money = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footer.money:SetPoint("RIGHT", -6, 0)
    footer.money:SetText("0g 0s 0c")

    footer.moneyHitBox = CreateFrame("Button", nil, footer)
    footer.moneyHitBox:SetPoint("RIGHT", footer.money, "RIGHT", 2, 0)
    footer.moneyHitBox:SetHeight(DIM.FOOTER_HEIGHT)
    footer.moneyHitBox:SetWidth(90)
    footer.moneyHitBox:EnableMouse(true)
    footer.moneyHitBox:SetScript("OnEnter", function(self)
        ShowFooterMoneyTooltip(self)
    end)
    footer.moneyHitBox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    footer.moneyHitBox._moneyText = footer.money:GetText() or "0"

    -- Money display as gold/silver/copper coin icons (toggleable in settings).
    -- Built manually: a container frame holding direct coin textures + number texts,
    -- right-anchored so they're always flush to the footer's right edge.
    local coinTextures = {
        gold   = "Interface\\MoneyFrame\\UI-GoldIcon",
        silver = "Interface\\MoneyFrame\\UI-SilverIcon",
        copper = "Interface\\MoneyFrame\\UI-CopperIcon",
    }
    footer.moneyIcons = CreateFrame("Frame", nil, footer)
    footer.moneyIcons:SetHeight(DIM.FOOTER_HEIGHT)
    footer.moneyIcons:SetPoint("RIGHT", -6, 0)
    footer.moneyIcons:SetFrameLevel(footer:GetFrameLevel() + 2)
    footer.moneyIcons:Hide()
    footer.moneyIcons.tex = {}
    footer.moneyIcons.txt = {}
    for _, key in ipairs({ "gold", "silver", "copper" }) do
        local tex = footer.moneyIcons:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(coinTextures[key])
        tex:SetSize(13, 13)
        local txt = footer.moneyIcons:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetJustifyH("RIGHT")
        footer.moneyIcons.tex[key] = tex
        footer.moneyIcons.txt[key] = txt
    end

    -- Overflow flyout: when ribbon + money can't fit, extra buttons
    -- are re-parented here and revealed above the footer on demand
    footer.overflowPopup = CreateFrame("Frame", nil, footer)
    footer.overflowPopup:SetFrameStrata("DIALOG")
    footer.overflowPopup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    footer.overflowPopup:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    footer.overflowPopup:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    footer.overflowPopup:Hide()

    footer.overflowBtn = CreateFrame("Button", nil, footer)
    footer.overflowBtn:SetSize(DIM.FOOTER_BTN_SIZE, DIM.FOOTER_BTN_SIZE)
    footer.overflowBtn:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
    local overflowTex = footer.overflowBtn:GetNormalTexture()
    if overflowTex then
        overflowTex:SetVertexColor(0.18, 0.18, 0.18, 0.9)
    end
    footer.overflowBtn.label = footer.overflowBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    footer.overflowBtn.label:SetPoint("CENTER")
    footer.overflowBtn.label:SetText(">>")
    StyleFooterMiniButton(footer.overflowBtn)
    footer.overflowBtn._tooltipTitle = "More"
    footer.overflowBtn._tooltipSub   = "Launchers that didn't fit"
    footer.overflowBtn:SetScript("OnClick", function(self)
        local popup = footer.overflowPopup
        if not popup then return end
        if popup:IsShown() then popup:Hide() else popup:Show() end
    end)
    footer.overflowBtn:Hide()

    -- Live reflow when the window is resized; cheap enough per-frame
    footer:SetScript("OnSizeChanged", function()
        if Frame.UpdateFooterCustomButtons then Frame:UpdateFooterCustomButtons() end
    end)

    mainFrame.footer = footer
end

-- Lays out custom + addon launcher buttons between AH embed host and money.
-- Buttons that don't fit are re-parented into an overflow flyout, toggled by a » tile.

local function SyncBagFullAlertHitBox(footer)
    local b = footer.bagFullAlert
    if not b or not b.label then return end
    local lw = b.label:GetStringWidth() or 8
    b:SetWidth(math.max(14, lw + 6))
end

local function GetMoneyIconWidth(frame)
    if not frame or not frame.tex then return 0 end
    -- Sum visible (text right-edge to icon left-edge) widths.
    local w = 0
    for _, key in ipairs({ "gold", "silver", "copper" }) do
        local txt = frame.txt[key]
        local tex = frame.tex[key]
        if txt and txt:IsShown() and tex and tex:IsShown() then
            w = w + (txt:GetStringWidth() or 0) + 13 + 1 + 4 -- icon + gap + spacing
        end
    end
    if w > 0 then w = w - 4 end -- trim trailing spacing
    return w
end

local function LayoutMoneyIcons(footer, gold, silver, copper)
    local icons = footer and footer.moneyIcons
    if not icons or not icons:IsShown() then return end
    local show = {
        gold   = gold > 0,
        silver = gold > 0 or silver > 0,
        copper = true,
    }
    -- Build left-to-right groups, then place from right edge inward.
    local groups = {}
    if show.copper then
        table.insert(groups, { tex = icons.tex.copper, txt = icons.txt.copper, val = copper })
    end
    if show.silver then
        table.insert(groups, { tex = icons.tex.silver, txt = icons.txt.silver, val = silver })
    end
    if show.gold then
        table.insert(groups, { tex = icons.tex.gold, txt = icons.txt.gold, val = gold })
    end

    -- Hide all first, then show only groups.
    for _, key in ipairs({ "gold", "silver", "copper" }) do
        icons.tex[key]:Hide()
        icons.txt[key]:Hide()
    end

    local offset = 0
    for _, g in ipairs(groups) do
        g.txt:SetText(tostring(g.val))
        g.txt:Show()
        g.tex:Show()
        g.txt:ClearAllPoints()
        g.txt:SetPoint("RIGHT", icons, "RIGHT", -offset, 0)
        g.tex:ClearAllPoints()
        g.tex:SetPoint("RIGHT", g.txt, "LEFT", -1, 0)
        local tw = g.txt:GetStringWidth() or 0
        offset = offset + tw + 13 + 1 + 4
    end
    icons:SetWidth(math.max(0, offset - 4))
end

local function GetMoneyDisplayWidth(footer)
    if footer.moneyIcons and footer.moneyIcons:IsShown() then
        return GetMoneyIconWidth(footer.moneyIcons)
    end
    return footer.money:GetStringWidth() or 0
end

local function SyncFooterMoneyHitBox(footer)
    local hitBox = footer and footer.moneyHitBox
    if not hitBox then
        return
    end
    local active = (footer.moneyIcons and footer.moneyIcons:IsShown() and footer.moneyIcons) or footer.money
    if not active then
        return
    end
    local width = ((active == footer.moneyIcons) and GetMoneyIconWidth(active) or (active:GetStringWidth() or 0)) + 10
    hitBox:SetWidth(math.max(45, width))
    hitBox:ClearAllPoints()
    hitBox:SetPoint("RIGHT", active, "RIGHT", 2, 0)
end

local function GetFooterSlotsBlockWidth(footer)
    local w = (footer.slots and footer.slots:GetStringWidth()) or 0
    if footer.bagFullAlert and footer.bagFullAlert:IsShown() then
        w = w + 1 + ((footer.bagFullAlert:GetWidth()) or 14)
    end
    return w
end

local function ComputeRibbonAvailableWidth(footer)
    local footerWidth = footer:GetWidth()
    if not footerWidth or footerWidth <= 0 then
        return math.huge
    end

    local slotsBlock = GetFooterSlotsBlockWidth(footer)
    local leftEdge = 6 + slotsBlock

    local moneyReserve = GetMoneyDisplayWidth(footer) + 6 + DIM.MONEY_SAFETY_GAP
    return footerWidth - leftEdge - moneyReserve
end

local function CollectRibbonItems(footer)
    local items = {}
    local secureAnchor = mainFrame and mainFrame.secureAnchor

    local function appendGroup(orderList, buttonsMap, isEnabledFn, sep)
        local groupHasMember = false
        for _, def in ipairs(orderList) do
            local btn = buttonsMap[def.key]
            if btn then
                local enabled = isEnabledFn(def.key)
                if enabled then
                    if not groupHasMember then
                        groupHasMember = true
                        table.insert(items, { kind = "sep", obj = sep })
                    end
                    table.insert(items, { kind = "btn", obj = btn, def = def })
                else
                    btn:ClearAllPoints()
                    -- Secure buttons stay under secureAnchor so mainFrame
                    -- never picks up SecureActionButtonTemplate descendants
                    -- (which would propagate protection up the chain and
                    -- break combat Show/Hide on the bag frame).
                    if def.secure and secureAnchor then
                        btn:SetParent(secureAnchor)
                    else
                        btn:SetParent(footer)
                    end
                    btn:Hide()
                end
            end
        end
        if not groupHasMember then
            sep:ClearAllPoints()
            sep:Hide()
        end
    end

    appendGroup(footer.customButtonOrder, footer.customButtons, IsFooterCustomButtonEnabled, footer.customSep)
    return items
end

-- Footer custom buttons use SecureActionButtonTemplate so right-click
-- works in combat, but that means ClearAllPoints / SetParent / SetPoint /
-- Show / Hide on them are protected and blocked during combat lockdown.
-- If the first layout pass happens while in combat (e.g. login mid-fight),
-- the buttons never get positioned and stay invisible.  We combat-gate
-- the whole reflow and defer it to PLAYER_REGEN_ENABLED.
Frame._pendingFooterUpdate = false

function Frame:UpdateFooterCustomButtons()
    if not mainFrame or not mainFrame.footer then return end
    local footer = mainFrame.footer
    if not footer.customButtons then return end

    -- Secure buttons can't be repositioned in combat; defer and retry
    -- once combat ends (Events.lua PLAYER_REGEN_ENABLED -> UpdateLayout
    -- -> UpdateSlotCount -> UpdateFooterCustomButtons).
    if InCombatLockdown and InCombatLockdown() then
        self._pendingFooterUpdate = true
        return
    end
    self._pendingFooterUpdate = false

    -- Ensure the secure anchor is shown and visible only when the main frame is open
    if mainFrame.secureAnchor then
        if mainFrame:IsShown() then
            mainFrame.secureAnchor:SetAlpha(1)
            mainFrame.secureAnchor:Show()
        else
            mainFrame.secureAnchor:Hide()
        end
    end

    if footer.customButtons.openables then
        local btn = footer.customButtons.openables
        if not InCombatLockdown() then
            local bagID, slotID = FindFirstOpenableContainer()
            if bagID and slotID then
                local link = GetContainerItemLink(bagID, slotID)
                local name = link and GetItemInfo(link)
                if name then
                    btn:SetAttribute("type2", "item")
                    btn:SetAttribute("item2", name)
                else
                    btn:SetAttribute("type2", nil)
                    btn:SetAttribute("item2", nil)
                end
            else
                btn:SetAttribute("type2", nil)
                btn:SetAttribute("item2", nil)
            end
        end
        if btn.icon then
            local bagID2, slotID2 = FindFirstOpenableContainer()
            if bagID2 and slotID2 then
                btn.icon:SetVertexColor(1, 1, 1, 1)
            else
                btn.icon:SetVertexColor(0.45, 0.45, 0.45, 0.75)
            end
        end
    end

    -- Dim icon on gated-footer buttons (hearthstone / disenchant / picklock)
    -- when their runtime availability check fails. The button stays visible
    -- so the user sees their settings toggle has effect; icon color tells
    -- them whether the action is currently usable.
    for _, def in ipairs(footer.customButtonOrder) do
        if type(def.isAvailable) == "function" then
            local btn = footer.customButtons[def.key]
            if btn and btn.icon then
                if def.isAvailable() then
                    btn.icon:SetVertexColor(1, 1, 1, 1)
                else
                    btn.icon:SetVertexColor(0.45, 0.45, 0.45, 0.75)
                end
            end
        end
    end

    local inlineAnchor = footer.slots
    local inlineAnchorGap = DIM.FOOTER_SEP_GAP + 2

    local secureAnchor = mainFrame.secureAnchor

    local items = CollectRibbonItems(footer)
    local totalNeededWidth = 0
    for _, item in ipairs(items) do
        if item.kind == "sep" then
            totalNeededWidth = totalNeededWidth + DIM.SEP_SLOT_WIDTH
        else
            totalNeededWidth = totalNeededWidth + DIM.FOOTER_BTN_SIZE + DIM.FOOTER_BTN_GAP
        end
    end

    local available     = ComputeRibbonAvailableWidth(footer)
    local mustOverflow  = totalNeededWidth > available
    local inlineBudget  = mustOverflow and (available - DIM.OVERFLOW_SLOT_COST) or available

    local slotsBlock = GetFooterSlotsBlockWidth(footer)
    local leftEdge = 6 + slotsBlock
    local currentX = leftEdge + inlineAnchorGap

    local inlinePrev        = nil
    local runningWidth      = 0
    local overflowButtons   = {}
    local lastInlineSep     = nil

    local function parentFor(item)
        if item.def and item.def.secure and secureAnchor then
            return secureAnchor
        end
        return footer
    end

    local function placeInline(item)
        local obj = item.obj
        local kind = item.kind
        obj:ClearAllPoints()
        
        local parent = parentFor(item)
        obj:SetParent(parent)

        -- Calculate the exact xOffset relative to parent to prevent cross-parent SetPoint bugs in WoW
        local xOffset = currentX
        if inlinePrev then
            local gap = DIM.FOOTER_BTN_GAP
            if kind == "sep" then
                gap = DIM.FOOTER_SEP_GAP
            elseif inlinePrev == lastInlineSep then
                gap = DIM.FOOTER_SEP_GAP
            end
            currentX = currentX + gap
            xOffset = currentX
        end

        obj:SetPoint("LEFT", parent, "LEFT", xOffset, 0)
        obj:Show()

        if kind == "sep" then
            lastInlineSep = obj
            currentX = currentX + DIM.SEP_SLOT_WIDTH
        else
            currentX = currentX + DIM.FOOTER_BTN_SIZE
        end
        inlinePrev = obj
    end

    for i, item in ipairs(items) do
        local cost = (item.kind == "sep") and DIM.SEP_SLOT_WIDTH or (DIM.FOOTER_BTN_SIZE + DIM.FOOTER_BTN_GAP)
        local nextItem = items[i + 1]

        local wouldOverflow = (runningWidth + cost) > inlineBudget
        -- A sep alone at the tail is meaningless; if the next button won't fit, overflow the sep too
        if item.kind == "sep" and nextItem and nextItem.kind == "btn" then
            local btnCost = DIM.FOOTER_BTN_SIZE + DIM.FOOTER_BTN_GAP
            if (runningWidth + cost + btnCost) > inlineBudget then
                wouldOverflow = true
            end
        end

        -- Secure buttons are forced inline -- the overflow popup is a
        -- descendant of footer (mainFrame) and would re-expose
        -- SecureActionButtonTemplate protection up through mainFrame.
        -- In practice up to 4 secure buttons is a tight cluster; they
        -- usually fit. If a future custom button adds to the secure set
        -- we may need a parallel overflow popup on secureAnchor -- for
        -- now, force-inline and hope for the best.
        local forceInline = item.kind == "btn" and item.obj and item.obj.__def and item.obj.__def.secure

        if (not mustOverflow or not wouldOverflow) or forceInline then
            placeInline(item)
            if forceInline then
                runningWidth = runningWidth + cost
            else
                runningWidth = runningWidth + cost
            end
        else
            if item.kind == "sep" then
                item.obj:ClearAllPoints()
                item.obj:Hide()
            else
                table.insert(overflowButtons, item.obj)
            end
        end
    end

    if mustOverflow and #overflowButtons > 0 then
        local attachAnchor = inlinePrev or inlineAnchor
        local attachGap    = inlinePrev and DIM.FOOTER_BTN_GAP or inlineAnchorGap
        footer.overflowBtn:ClearAllPoints()
        footer.overflowBtn:SetPoint("LEFT", attachAnchor, "RIGHT", attachGap, 0)
        footer.overflowBtn:Show()

        local popup = footer.overflowPopup
        local popupPad = 4
        local popupWidth = popupPad * 2 + #overflowButtons * DIM.FOOTER_BTN_SIZE + (#overflowButtons - 1) * DIM.FOOTER_BTN_GAP
        local popupHeight = popupPad * 2 + DIM.FOOTER_BTN_SIZE
        popup:ClearAllPoints()
        popup:SetSize(popupWidth, popupHeight)
        popup:SetPoint("BOTTOMRIGHT", footer.overflowBtn, "TOPRIGHT", 2, 4)

        local prevPopupBtn
        for _, btn in ipairs(overflowButtons) do
            btn:ClearAllPoints()
            -- Non-secure only -- secure ones are forced inline above.
            btn:SetParent(popup)
            if prevPopupBtn then
                btn:SetPoint("LEFT", prevPopupBtn, "RIGHT", DIM.FOOTER_BTN_GAP, 0)
            else
                btn:SetPoint("LEFT", popupPad, 0)
            end
            btn:Show()
            prevPopupBtn = btn
        end
    else
        footer.overflowBtn:ClearAllPoints()
        footer.overflowBtn:Hide()
        footer.overflowPopup:Hide()
    end

    -- The secure anchor must mirror the footer's screen position so
    -- SetPoint math (which coordinates target footer frames inside
    -- mainFrame) still lands the secure buttons visibly on top of the
    -- footer, even though they live outside mainFrame's parent chain.
    if mainFrame._requestSecureAnchorReposition then
        mainFrame._requestSecureAnchorReposition()
    end
end



-- =============================================================================
-- Resize Handle
-- =============================================================================

function Frame:CreateResizeHandle()
    local handle = CreateFrame("Button", nil, mainFrame)
    handle:SetSize(16, 16)
    handle:SetPoint("BOTTOMRIGHT", -2, 2)
    handle:EnableMouse(true)

    handle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    handle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    handle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    handle:SetScript("OnMouseDown", function()
        mainFrame:StartSizing("BOTTOMRIGHT")
    end)

    handle:SetScript("OnMouseUp", function()
        mainFrame:StopMovingOrSizing()
        Frame:SavePosition()
        Frame:UpdateLayout()
        if Frame.UpdateFooterCustomButtons then Frame:UpdateFooterCustomButtons() end
    end)

    mainFrame.resizeHandle = handle
end

-- =============================================================================
-- Event Registration
-- =============================================================================

function Frame:RegisterEvents()
    if not mainFrame then return end

    -- Connect to Event bucket system for bag updates only
    -- Note: Bank events and PLAYER_MONEY are handled by Omni.Events:Init()
    if Omni.Events then
        Omni.Events:RegisterBucketEvent("BAG_UPDATE", function(changedBags)
            -- UpdateLayout self-defers in combat; PLAYER_REGEN_ENABLED
            -- replays a full pass once lockdown clears.
            Frame:UpdateLayout(changedBags)
        end)

        Omni.Events:RegisterEvent("BAG_UPDATE_COOLDOWN", function()
            if not mainFrame or not mainFrame:IsShown() then return end
            if InCombat() then return end
            if not Omni.ItemButton or not Omni.ItemButton.UpdateCooldown then return end
            for _, btn in ipairs(itemButtons) do
                Omni.ItemButton:UpdateCooldown(btn)
            end
        end)
    end
end

-- =============================================================================
-- Position Persistence
-- =============================================================================

function Frame:SavePosition()
    if not mainFrame then return end

    local point, _, _, x, y = mainFrame:GetPoint()
    local width, height = mainFrame:GetSize()

    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.char = OmniInventoryDB.char or {}
    OmniInventoryDB.char.position = {
        point = point,
        x = x,
        y = y,
        width = width,
        height = height,
    }
end

function Frame:LoadPosition()
    if not mainFrame then return end

    local pos = OmniInventoryDB and OmniInventoryDB.char and OmniInventoryDB.char.position
    if pos then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
        if pos.width and pos.height then
            mainFrame:SetSize(pos.width, pos.height)
        end
    end
end

function Frame:SetScale(scale)
    if not mainFrame then return end
    scale = math.max(0.5, math.min(scale or 1, 2.0))
    mainFrame:SetScale(scale)

    if Omni.Data and Omni.Data.SetFrameSetting then
        Omni.Data:SetFrameSetting("bag", "scale", scale)
    else
        OmniInventoryDB = OmniInventoryDB or {}
        OmniInventoryDB.char = OmniInventoryDB.char or {}
        OmniInventoryDB.char.settings = OmniInventoryDB.char.settings or {}
        OmniInventoryDB.char.settings.scale = scale
    end
end

function Frame:GetScale()
    if Omni.Data and Omni.Data.GetFrameSetting then
        return Omni.Data:GetFrameSetting("bag", "scale", 1.0)
    end
    if mainFrame and mainFrame.GetScale then
        return mainFrame:GetScale()
    end
    local settings = OmniInventoryDB and OmniInventoryDB.char and OmniInventoryDB.char.settings
    return settings and settings.scale or 1
end

function Frame:GetItemScale()
    return GetSavedItemScale()
end

function Frame:SetItemScale(scale)
    if InCombat() then return false end
    scale = math.max(DIM.ITEM_SCALE_MIN, math.min(scale or 1, DIM.ITEM_SCALE_MAX))

    if Omni.Data and Omni.Data.SetFrameSetting then
        Omni.Data:SetFrameSetting("bag", "itemScale", scale)
    else
        OmniInventoryDB = OmniInventoryDB or {}
        OmniInventoryDB.char = OmniInventoryDB.char or {}
        OmniInventoryDB.char.settings = OmniInventoryDB.char.settings or {}
        OmniInventoryDB.char.settings.itemScale = scale
    end

    self:InvalidateRenderCaches({ clearLayout = true })

    self:UpdateLayout()
    return true
end

function Frame:GetItemGap()
    return GetSavedItemGap()
end

function Frame:SetItemGap(gap)
    if InCombat() then return false end
    gap = math.max(DIM.ITEM_GAP_MIN, math.min(gap or DIM.ITEM_SPACING, DIM.ITEM_GAP_MAX))

    if Omni.Data and Omni.Data.SetFrameSetting then
        Omni.Data:SetFrameSetting("bag", "itemGap", gap)
    else
        OmniInventoryDB = OmniInventoryDB or {}
        OmniInventoryDB.char = OmniInventoryDB.char or {}
        OmniInventoryDB.char.settings = OmniInventoryDB.char.settings or {}
        OmniInventoryDB.char.settings.itemGap = gap
    end

    self:InvalidateRenderCaches({ clearLayout = true })

    self:UpdateLayout()
    return true
end

function Frame:ResetPosition()
    if not mainFrame then return end
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    self:SavePosition()
    self:SetScale(1.0)
end

-- =============================================================================
-- Theme System (A46)
-- =============================================================================
-- "rounded" = default WoW tooltip-style borders, inset icons
-- "square"  = pfUI-compatible: no rounded edge, full-crop icons, thin border

function Frame:ApplyTheme()
    if not mainFrame then return end
    local isSquare = Omni.Features and Omni.Features.IsSquareTheme
        and Omni.Features:IsSquareTheme() or false

    if isSquare then
        mainFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        mainFrame:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
        mainFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    else
        mainFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        mainFrame:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
        mainFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end

    -- Update item button icon texCoords live
    if Omni.ItemButton and Omni.ItemButton.ApplyThemeToAllButtons then
        Omni.ItemButton:ApplyThemeToAllButtons()
    end
end

-- =============================================================================
-- View Modes
-- =============================================================================

function Frame:SetView(mode)
    currentView = NormalizeViewMode(mode)
    self._combatGridFallbackActive = false
    self._combatGridFallbackOriginalView = nil
    self:InvalidateRenderCaches({ clearLayout = true })

    -- Any explicit view change away from "bag" invalidates the
    -- remembered pre-bag view -- otherwise a later bag toggle could
    -- restore to a view the user has since moved past.
    if currentView ~= "bag" then
        preBagViewMode = nil
    end

    self:_RefreshViewButtonLabel()

    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.char = OmniInventoryDB.char or {}
    OmniInventoryDB.char.settings = OmniInventoryDB.char.settings or {}
    OmniInventoryDB.char.settings.viewMode = currentView

    self:UpdateBagIconVisuals()
    Frame:UpdateLayout(nil, { forceFull = true, immediate = true, reason = "view_change" })
end

function Frame:CycleView()
    local modes = { "grid", "flow", "list", "bag" }
    local nextIdx = 1

    for i, mode in ipairs(modes) do
        if mode == currentView then
            nextIdx = (i % #modes) + 1
            break
        end
    end

    Frame:SetView(modes[nextIdx])
end

function Frame:GetView()
    return currentView
end

function Frame:CycleSort()
    if not Omni.Sorter then return end

    local modes = Omni.Sorter:GetModes()
    local currentMode = Omni.Sorter:GetDefaultMode()
    local nextIdx = 1

    for i, mode in ipairs(modes) do
        if mode == currentMode then
            nextIdx = (i % #modes) + 1
            break
        end
    end

    local newMode = modes[nextIdx]
    Omni.Sorter:SetDefaultMode(newMode)
    self:InvalidateRenderCaches({ clearLayout = true })

    -- Update button tooltip on next hover
    if mainFrame and mainFrame.header and mainFrame.header.sortBtn then
        -- Capitalize first letter for display
        local displayMode = newMode:gsub("^%l", string.upper)
        mainFrame.header.sortBtn.text:SetText(displayMode)
    end

    if Omni.BankFrame and Omni.BankFrame.UpdateSortButton then
        Omni.BankFrame:UpdateSortButton()
        if Omni.BankFrame.UpdateLayout then
            Omni.BankFrame:UpdateLayout()
        end
    end

    -- Refresh layout with new sort
    Frame:UpdateLayout(nil, { forceFull = true, immediate = true, reason = "sort_change" })
end

function Frame:UpdateSortButton()
    if mainFrame and mainFrame.header and mainFrame.header.sortBtn then
        local mode = Omni.Sorter and Omni.Sorter:GetDefaultMode() or "category"
        local displayMode = mode:gsub("^%l", string.upper)
        mainFrame.header.sortBtn.text:SetText(displayMode)
    end
end

-- =============================================================================
-- View Mode (bags only; bank lives in Omni.BankFrame)
-- =============================================================================

function Frame:SetMode(mode)
    currentMode = "bags"
    self:UpdateBagIconVisuals()
    self:UpdateLayout()
end

-- Backwards-compat stubs: bank now lives in its own frame
function Frame:SetBankOpen(_) end
function Frame:UpdateBankTabState() end

-- =============================================================================
-- Combat-safe in-place content refresh
-- =============================================================================

-- Combat-safe refresh. Walks the persistent slotButtons map (one
-- entry per physical bag slot, pre-parented and SetID'd OOC) and mirrors
-- the live container state onto each button using ONLY insecure calls
-- (SetAlpha + ItemButton:SetItem). Items that pop in during combat become
-- visible and clickable at whatever position the last OOC render parked
-- their slot button (their sorted home, or the overflow strip for slots
-- that were empty at last render). Items used during combat clear by
-- fading to alpha 0.
-- SetParent / SetPoint / SetID / Show / Hide are NEVER called here --
-- those are protected on ContainerFrameItemButtonTemplate children.
function Frame:RefreshCombatContent(changedBags)
    if not mainFrame or not OmniC_Container then return end
    changedBags = NarrowChangedBagsToSelectedScope(changedBags)

    -- List view parks all slot buttons at alpha 0 and drives its
    -- own insecure row widgets -- which are OOC-only anyway (list row
    -- clicks call PickupContainerItem directly and are blocked in combat).
    -- Flipping slot-button alpha here would punch ghost icons through the
    -- list layout, so we short-circuit and let PLAYER_REGEN_ENABLED do a
    -- clean full re-render once combat ends.
    if currentView == "list" then
        self:UpdateSlotCount()
        self:UpdateMoney()
        return
    end

    local affected
    if type(changedBags) == "table" then
        local hasEntries = false
        for _ in pairs(changedBags) do hasEntries = true break end
        if not hasEntries then
            self:UpdateSlotCount()
            self:UpdateMoney()
            return { requiresFlowRelayout = false }
        end
        if hasEntries and not changedBags._trigger then
            affected = changedBags
        end
    end

    -- Rebuild the populated-button list so search / cooldown passes
    -- that run during combat see every visible item, including ones that
    -- arrived after the last OOC render.
    local refreshed = {}
    local meta = {
        requiresFlowRelayout = false,
    }

    local selectedScopeBagID = IsValidBagID(selectedBagID) and selectedBagID or nil

    IterateSlotButtons(function(bagID, slotID, btn)
        if selectedScopeBagID and bagID ~= selectedScopeBagID then
            SetButtonItem(btn, nil)
            pcall(btn.SetAlpha, btn, 0)
            return
        end
        local info
        if affected == nil or affected[bagID] then
            local previousInfo = btn.itemInfo
            info = OmniC_Container.GetContainerItemInfo(bagID, slotID)
            if info then
                if Omni.Categorizer then
                    info.category = info.category or Omni.Categorizer:GetCategory(info)
                end
                info.isQuickFiltered = btn.itemInfo and btn.itemInfo.isQuickFiltered or false
                if currentView == "flow"
                        and not meta.requiresFlowRelayout
                        and DoesFlowSlotChangeRequireRelayout(previousInfo, info) then
                    meta.requiresFlowRelayout = true
                end
                SetButtonItem(btn, info)
                pcall(btn.SetAlpha, btn, 1)
                table.insert(refreshed, btn)
            else
                if currentView == "flow"
                        and not meta.requiresFlowRelayout
                        and DoesFlowSlotChangeRequireRelayout(previousInfo, nil) then
                    meta.requiresFlowRelayout = true
                end
                if currentView == "grid" or currentView == "bag" then
                    SetButtonItem(btn, { bagID = bagID, slotID = slotID, __empty = true })
                    pcall(btn.SetAlpha, btn, EMPTY_SLOT_ALPHA)
                else
                    SetButtonItem(btn, nil)
                    pcall(btn.SetAlpha, btn, 0)
                end
            end
        else
            if btn.itemInfo then
                table.insert(refreshed, btn)
            end
        end
    end)

    itemButtons = refreshed

    self:UpdateSlotCount()
    self:UpdateMoney()

    return meta
end

function Frame:SnapshotBagSlotState(bagID, slotID)
    return GetBagSlotStateKey(bagID, slotID)
end

function Frame:RequestOptimisticFlowRefresh(bagID, slotID, options)
    if not mainFrame or not mainFrame:IsShown() or InCombat() or currentView ~= "flow" then
        return false
    end
    if not bagID or not slotID or bagID < 0 or bagID > 4 or slotID < 1 then
        return false
    end

    local stateKey = options and options.stateKey or GetBagSlotStateKey(bagID, slotID)
    if not stateKey then
        return false
    end

    local watchKey = tostring(bagID) .. ":" .. tostring(slotID)
    optimisticFlowRefreshWatches[watchKey] = {
        bagID = bagID,
        slotID = slotID,
        stateKey = stateKey,
        elapsed = 0,
        waitForCursorClear = options and options.waitForCursorClear == true or false,
    }

    StartOptimisticFlowRefreshWatcher()
    return true
end

-- =============================================================================
-- Layout Update
-- =============================================================================

function Frame:UpdateLayout(changedBags, opts)
    if not mainFrame then return end
    self:UpdateTitle()
    -- Global lock: pause all layout updates while locked (e.g.
    -- during sort/swap operations). Combat gating still applies below.
    if Omni.Features and Omni.Features.IsGlobalLocked and Omni.Features:IsGlobalLocked()
            and not (opts and opts.forceFull) then
        return
    end
    if not (opts and opts.__coalesced) and not (opts and opts.immediate) then
        self:_QueueLayoutUpdate(changedBags, opts)
        return
    end

    local perfTotal = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("frame.UpdateLayout.total")
    local forceFull = opts and opts.forceFull == true
    local updateReason = (opts and opts.reason) or "layout"

    self._bagSlotCache = self._bagSlotCache or {}
    local sizeChanged = false
    for _, bagID in ipairs(DIM.BAG_IDS) do
        local currentSlots = GetContainerNumSlots(bagID) or 0
        if currentSlots ~= (self._bagSlotCache[bagID] or 0) then
            sizeChanged = true
            self._bagSlotCache[bagID] = currentSlots
        end
    end
    if sizeChanged then
        forceFull = true
        updateReason = updateReason .. "_size_change"
    end

    if not InCombat() and self:_RestoreCombatGridFallback() then
        forceFull = true
        updateReason = "restore_" .. updateReason
    end
    changedBags = NarrowChangedBagsToSelectedScope(changedBags)
    if not forceFull and type(changedBags) == "table" then
        local hasEntries = false
        for _ in pairs(changedBags) do
            hasEntries = true
            break
        end
        if not hasEntries then
            if Omni._perfEnabled and Omni.Perf then
                Omni.Perf:End("frame.UpdateLayout.total", perfTotal, {
                    skipped = "irrelevant_bag",
                    reason = updateReason,
                    view = currentView or "unknown",
                })
            end
            return
        end
    end
    if not forceFull and mainFrame.IsShown and not mainFrame:IsShown() then
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("frame.UpdateLayout.total", perfTotal, { skipped = "hidden", reason = updateReason })
        end
        return
    end

    -- Combat policy
    -- Structural ops on ContainerFrameItemButton children are risky in
    -- combat, so normal updates only refresh existing slot-button content.
    -- First-open lockdown is the exception: we try a physical grid
    -- bootstrap, then restore the user's saved view after combat.
    if InCombat() then
        pendingCombatRender = true
        if hasRenderedOnce then
            if mainFrame.combatHint then mainFrame.combatHint:Hide() end
            if self._combatGridFallbackActive then
                self:RenderCombatGridFallback()
            else
                self:RefreshCombatContent(changedBags)
            end
        else
            local renderedGrid = self:RenderCombatGridFallback()
            if renderedGrid then
                if mainFrame.combatHint then mainFrame.combatHint:Hide() end
            elseif mainFrame:IsShown() and mainFrame.combatHint then
                mainFrame.combatHint:Show()
                mainFrame.combatHint:SetText("Bag contents will appear after combat.")
            end
        end
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("frame.UpdateLayout.total", perfTotal, {
                skipped = "combat_refresh",
                reason = updateReason,
                view = currentView or "unknown",
            })
        end
        return
    end

    if burstRefreshPending and not (IsMerchantOpen() or HasBagChangeEntries(changedBags)) then
        StopBurstFullRefresh()
    end

    if not forceFull
            and hasRenderedOnce
            and HasBagChangeEntries(changedBags)
            and currentView ~= "list" then
        local refreshMeta = self:RefreshCombatContent(changedBags)
        local shouldForceFlowConsistency = (currentView == "flow")
        local shouldForceFlowRelayout = currentView == "flow"
            and refreshMeta
            and refreshMeta.requiresFlowRelayout == true
        if shouldForceFlowConsistency or shouldForceFlowRelayout then
            StopBurstFullRefresh()
            lastOptimisticFlowRefreshAt = (GetTime and GetTime()) or 0
            forceFull = true
        end

        if not forceFull then
            -- Burst full relayouts are expensive and mainly needed
            -- for flow-lane/category reconstruction. In bag/grid modes the
            -- incremental slot refresh is already sufficient, especially
            -- during mass operations like disenchant/vendor spam.
            local allowBurstFull = (currentView == "flow")
                and (updateReason ~= "bag_update_chunk")
            local now = (GetTime and GetTime()) or 0
            local suppressBurst = allowBurstFull
                and lastOptimisticFlowRefreshAt > 0
                and now > 0
                and (now - lastOptimisticFlowRefreshAt) <= DIM.OPTIMISTIC_FLOW_REFRESH_SUPPRESS_WINDOW
            if allowBurstFull and not suppressBurst then
                RequestBurstFullRefresh()
            end
            if Omni._perfEnabled and Omni.Perf then
                Omni.Perf:End("frame.UpdateLayout.total", perfTotal, {
                    skipped = "incremental_slot_refresh",
                    reason = updateReason,
                    view = currentView or "unknown",
                })
            end
            return
        end
    end

    if mainFrame.combatHint then
        mainFrame.combatHint:Hide()
    end

    local items = {}
    local perfCollect = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("frame.UpdateLayout.collect")
    if OmniC_Container then
        items = OmniC_Container.GetAllBagItems()
    end
    if Omni._perfEnabled and Omni.Perf then
        Omni.Perf:End("frame.UpdateLayout.collect", perfCollect, { itemCount = #items, reason = updateReason })
    end

    -- Cross-character search logic
    if isSearchActive and searchText ~= "" and OmniInventoryDB and OmniInventoryDB.realm then
        local currentRealm = GetRealmName()
        local realmData = OmniInventoryDB.realm[currentRealm]
        if realmData then
            local currentOwner = Omni.Data and (Omni.Data.currentViewedChar or Omni.Data.playerName)
            for charName, charData in pairs(realmData) do
                if charName ~= currentOwner then
                    -- Scan bags
                    if charData.bags then
                        for _, item in ipairs(charData.bags) do
                            local altItem = {
                                bagID = item.bagID,
                                slotID = item.slotID,
                                hyperlink = item.link,
                                link = item.link,
                                stackCount = item.count or 1,
                                quality = item.quality or 0,
                                iconFileID = GetItemIcon(item.link),
                                __offline = true,
                                __owner = charName,
                                __location = "bags",
                            }
                            if Omni.MatchItemQuery and Omni.MatchItemQuery(altItem, searchText) then
                                table.insert(items, altItem)
                            end
                        end
                    end
                    -- Scan bank
                    if charData.bank then
                        for _, item in ipairs(charData.bank) do
                            local altItem = {
                                bagID = item.bagID,
                                slotID = item.slotID,
                                hyperlink = item.link,
                                link = item.link,
                                stackCount = item.count or 1,
                                quality = item.quality or 0,
                                iconFileID = GetItemIcon(item.link),
                                __offline = true,
                                __owner = charName,
                                __location = "bank",
                            }
                            if Omni.MatchItemQuery and Omni.MatchItemQuery(altItem, searchText) then
                                table.insert(items, altItem)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Categorize items
    if Omni.Categorizer then
        local perfCategorize = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("frame.UpdateLayout.categorize")
        for _, item in ipairs(items) do
            item.category = item.category or Omni.Categorizer:GetCategory(item)
        end
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("frame.UpdateLayout.categorize", perfCategorize, { reason = updateReason })
        end
    end

    if IsValidBagID(selectedBagID) then
        local filtered = {}
        for _, item in ipairs(items) do
            if item.bagID == selectedBagID then
                table.insert(filtered, item)
            end
        end
        items = filtered
    end

    -- Collect the set of categories actually present so the
    -- dynamic tab bar below only shows filters that would return
    -- something. Do this AFTER the bag filter so tabs reflect the
    -- currently-viewed scope.
    local presentCategories = {}
    for _, item in ipairs(items) do
        if item.category then
            presentCategories[item.category] = true
        end
    end
    self:RebuildFilterTabs(presentCategories)

    -- Quick filter handling.
    --
    -- Out of combat, a category tab doesn't dim non-matches anymore --
    -- it re-orders the layout so the selected category pins to the
    -- top-left and everything else flows below it (handled in
    -- RenderFlowView via the `pinnedLaneTop` hint). Clicking the tab
    -- again toggles the filter off and the bag sorts back to normal.
    --
    -- In combat we can't restructure the layout safely, so we fall
    -- Exact equality matches stop "Attunable" from catching
    -- "Account Attunable" via substring.
    -- When a filter tab is active, always dim the non-matching
    -- items so the selection pops. In flow mode OOC we ALSO re-order
    -- (the selected category gets pinned top-left by RenderFlowView's
    -- LPT block), so the user sees the filter both promoted and the
    -- rest grayed out in place. If the category later empties out,
    -- RebuildFilterTabs clears activeFilter and the dim goes with it.
    local quickFilter = self:GetActiveFilter()
    if quickFilter then
        local hasMatch = false
        for _, item in ipairs(items) do
            if item.category == quickFilter then
                hasMatch = true
                break
            end
        end
        for _, item in ipairs(items) do
            local matches = hasMatch and item.category == quickFilter
            item.isQuickFiltered = not matches
        end
    else
        for _, item in ipairs(items) do
            item.isQuickFiltered = false
        end
    end

    -- Sort items
    if Omni.Sorter then
        local perfSort = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("frame.UpdateLayout.sort")
        items = Omni.Sorter:Sort(items, Omni.Sorter:GetDefaultMode())
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("frame.UpdateLayout.sort", perfSort, { itemCount = #items, reason = updateReason })
        end
    end

    -- Render based on view mode
    if currentView == "list" then
        local perfRenderList = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("frame.UpdateLayout.renderList")
        self:RenderListView(items)
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("frame.UpdateLayout.renderList", perfRenderList, { reason = updateReason })
        end
    else
        -- Combined Grid/Flow rendering
        local perfRenderFlow = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("frame.UpdateLayout.renderFlow")
        local flowPath = self:RenderFlowView(items, { reason = updateReason }) or "na"
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("frame.UpdateLayout.renderFlow", perfRenderFlow, {
                reason = updateReason,
                flowPath = flowPath,
            })
        end
    end

    -- Update footer
    self:UpdateBagIconTextures()
    self:UpdateBagIconVisuals()
    self:UpdateSlotCount()
    self:UpdateMoney()

    -- Apply search
    local perfSearch = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("frame.UpdateLayout.search")
    self:ApplySearch(searchText or "")
    if Omni._perfEnabled and Omni.Perf then
        Omni.Perf:End("frame.UpdateLayout.search", perfSearch, { reason = updateReason })
    end

    hasRenderedOnce = true
    pendingCombatRender = false
    lastRenderedShowSignature = ComputeShowSignature()
    if Omni._perfEnabled and Omni.Perf then
        Omni.Perf:End("frame.UpdateLayout.total", perfTotal, {
            itemCount = #items,
            view = currentView or "unknown",
            quickFilter = self:GetActiveFilter() or "none",
            reason = updateReason,
        })
    end
end

-- =============================================================================
-- Flow/Grid View Rendering
-- =============================================================================

function Frame:RenderFlowView(items, layoutOpts)
    if not mainFrame or not mainFrame.scrollChild then
        return "na"
    end

    local isOfflineCharView = false
    if Omni.Data and Omni.Data.currentViewedChar and Omni.Data.playerName then
        isOfflineCharView = (Omni.Data.currentViewedChar ~= Omni.Data.playerName)
    end

    CancelDeferredFlowItemPaint()

    local scrollChild = mainFrame.scrollChild

    -- Make sure every physical bag slot has a persistent button
    -- before we begin. This is the foundation of combat safety: any item
    -- that lands in any slot already has a pre-parented, pre-SetID button
    -- ready to accept content updates from RefreshCombatContent without
    -- needing a protected structural call.
    EnsureSlotButtons()

    if isOfflineCharView then
        if IterateSlotButtons then
            IterateSlotButtons(function(bagID, slotID, btn)
                pcall(btn.Hide, btn)
            end)
        end
    end

    if Omni.Pool then
        for _, btn in ipairs(offlineFlowButtons) do
            Omni.Pool:Release("ItemButton", btn)
            pcall(btn.Hide, btn)
        end
    end
    ClearArray(offlineFlowButtons)

    ClearArray(itemButtons)

    local categories = renderScratch.categories
    local categoryOrder = renderScratch.categoryOrder
    local touched = renderScratch.touched
    local usedCategoryKeys = renderScratch.usedCategoryKeys
    local usedTouchedBags = renderScratch.usedTouchedBags
    local headerByCategory = renderScratch.headerByCategory
    local seenCategoryThisPass = {}
    local seenTouchedBagsThisPass = {}

    for i = 1, #usedCategoryKeys do
        local key = usedCategoryKeys[i]
        local bucket = categories[key]
        if bucket then
            ClearArray(bucket)
        end
    end
    ClearArray(usedCategoryKeys)
    for i = 1, #usedTouchedBags do
        local bagID = usedTouchedBags[i]
        local bagTouched = touched[bagID]
        if bagTouched then
            ClearMap(bagTouched)
        end
    end
    ClearArray(usedTouchedBags)
    ClearArray(categoryOrder)
    ClearMap(headerByCategory)

    local freezeHeadersForVendor = false
    for _, row in ipairs(listRows) do row:Hide() end


    local hInset = 8
    local usableWidth = mainFrame.content:GetWidth() - hInset
    local itemGap = self:GetItemGap()
    local sectionHeaderHeight = (currentView == "grid") and 0 or 20 -- No headers in grid mode
    local sectionSpacing = (currentView == "grid") and itemGap or 8
    local dualCategoryLanes = (currentView ~= "grid")
    local laneGap = 10
    local itemScale = self:GetItemScale()
    local itemSize = DIM.ITEM_SIZE * itemScale
    local itemStep = itemSize + itemGap

    local function columnsForLaneWidth(laneW)
        local inner = laneW - itemGap
        local c = math.floor(inner / itemStep)
        return math.max(c, 1)
    end

    local yLeft = -itemGap
    local yRight = -itemGap
    local yOffset = -itemGap

    local itemBySlot = nil
    local bagSlotCounts = nil
    local bagItemCounts = nil
    local bagPreviewScopeSet = nil

    if currentView == "grid" then
        -- Bagnon-like grid: keep physical slot order and render empty
        -- slots inline so players always see full bag capacity.
        itemBySlot = {}
        categories["All"] = categories["All"] or {}
        seenCategoryThisPass["All"] = true
        usedCategoryKeys[#usedCategoryKeys + 1] = "All"
        categoryOrder[1] = "All"

        for _, itemInfo in ipairs(items) do
            if (not itemInfo.__offline or not itemInfo.__owner) and IsValidBagID(itemInfo.bagID) and itemInfo.slotID and itemInfo.slotID > 0 then
                itemBySlot[itemInfo.bagID] = itemBySlot[itemInfo.bagID] or {}
                itemBySlot[itemInfo.bagID][itemInfo.slotID] = itemInfo
            end
        end

        -- Insert sorted filled items first
        for _, itemInfo in ipairs(items) do
            if (itemInfo.__offline and itemInfo.__owner) or (IsValidBagID(itemInfo.bagID) and itemInfo.slotID and itemInfo.slotID > 0) then
                table.insert(categories["All"], itemInfo)
            end
        end

        local collapseEmpty = false
        if Omni.Data and Omni.Data.Get then
            collapseEmpty = (Omni.Data:Get("collapseEmptySlots") == true)
        end

        local emptyGroups = {}
        for _, bagID in ipairs(DIM.BAG_IDS) do
            local numSlots = GetContainerNumSlots(bagID) or 0
            for slotID = 1, numSlots do
                local info = itemBySlot[bagID] and itemBySlot[bagID][slotID] or nil
                if not info then
                    local grp = GetFreeSpaceCategoryName(bagID)
                    emptyGroups[grp] = emptyGroups[grp] or {
                        bagID = bagID,
                        slotID = slotID,
                        __empty = true,
                        category = grp,
                        emptyCount = 0,
                    }
                    emptyGroups[grp].emptyCount = emptyGroups[grp].emptyCount + 1
                end
            end
        end

        if collapseEmpty then
            local sortedGrps = {}
            for name, item in pairs(emptyGroups) do
                table.insert(sortedGrps, { name = name, item = item })
            end
            table.sort(sortedGrps, function(a, b) return a.name < b.name end)
            for _, grp in ipairs(sortedGrps) do
                table.insert(categories["All"], grp.item)
            end
        else
            for _, bagID in ipairs(DIM.BAG_IDS) do
                local numSlots = GetContainerNumSlots(bagID) or 0
                for slotID = 1, numSlots do
                    local info = itemBySlot[bagID] and itemBySlot[bagID][slotID] or nil
                    if not info then
                        table.insert(categories["All"], { bagID = bagID, slotID = slotID, __empty = true, emptyCount = 1 })
                    end
                end
            end
        end
    elseif currentView == "bag" then
        itemBySlot = {}
        bagSlotCounts = {}
        bagItemCounts = {}
        local bagScope = {}
        bagPreviewScopeSet = {}

        if IsValidBagID(selectedBagID) then
            table.insert(bagScope, selectedBagID)
            bagPreviewScopeSet[selectedBagID] = true
        else
            for _, bagID in ipairs(DIM.BAG_IDS) do
                table.insert(bagScope, bagID)
                bagPreviewScopeSet[bagID] = true
            end
        end

        for _, bagID in ipairs(bagScope) do
            categories[bagID] = categories[bagID] or {}
            seenCategoryThisPass[bagID] = true
            usedCategoryKeys[#usedCategoryKeys + 1] = bagID
            table.insert(categoryOrder, bagID)
            bagSlotCounts[bagID] = GetContainerNumSlots(bagID) or 0
            bagItemCounts[bagID] = 0
        end

        -- Handle alt bag scope
        local altBagsSeen = {}
        local altBagOrders = {}
        for _, item in ipairs(items) do
            if item.__offline and item.__owner then
                local altKey = item.__owner .. "_" .. item.bagID
                if not altBagsSeen[altKey] then
                    altBagsSeen[altKey] = true
                    table.insert(altBagOrders, { key = altKey, owner = item.__owner, bagID = item.bagID })
                end
            end
        end
        table.sort(altBagOrders, function(a, b)
            if a.owner ~= b.owner then
                return a.owner < b.owner
            end
            return a.bagID < b.bagID
        end)

        for _, altBag in ipairs(altBagOrders) do
            local altKey = altBag.key
            categories[altKey] = categories[altKey] or {}
            seenCategoryThisPass[altKey] = true
            usedCategoryKeys[#usedCategoryKeys + 1] = altKey
            table.insert(categoryOrder, altKey)

            local totalSlots = 0
            local currentRealm = GetRealmName()
            local charData = OmniInventoryDB and OmniInventoryDB.realm and OmniInventoryDB.realm[currentRealm] and OmniInventoryDB.realm[currentRealm][altBag.owner]
            if charData and charData.bagSizes then
                totalSlots = charData.bagSizes[tostring(altBag.bagID)] or 0
            end
            bagSlotCounts[altKey] = totalSlots
            bagItemCounts[altKey] = 0
        end

        for _, item in ipairs(items) do
            if not item.__offline or not item.__owner then
                if IsValidBagID(item.bagID) then
                    itemBySlot[item.bagID] = itemBySlot[item.bagID] or {}
                    itemBySlot[item.bagID][item.slotID] = item
                    bagItemCounts[item.bagID] = (bagItemCounts[item.bagID] or 0) + 1
                end
            else
                local altKey = item.__owner .. "_" .. item.bagID
                bagItemCounts[altKey] = (bagItemCounts[altKey] or 0) + 1
            end
        end

        -- Insert sorted filled items first
        for _, item in ipairs(items) do
            if not item.__offline or not item.__owner then
                local bagID = item.bagID
                if IsValidBagID(bagID) and categories[bagID] then
                    table.insert(categories[bagID], item)
                end
            else
                local altKey = item.__owner .. "_" .. item.bagID
                if categories[altKey] then
                    table.insert(categories[altKey], item)
                end
            end
        end

        -- Append empty slots (only for current player's active bags)
        for _, bagID in ipairs(bagScope) do
            local totalSlots = bagSlotCounts[bagID] or 0
            for slotID = 1, totalSlots do
                local info = itemBySlot[bagID] and itemBySlot[bagID][slotID] or nil
                if not info then
                    table.insert(categories[bagID], { bagID = bagID, slotID = slotID, __empty = true })
                end
            end
        end
    else
        -- FLOW MODE: Group by assigned category
        for _, item in ipairs(items) do
            local cat = item.category or "Miscellaneous"
            if not seenCategoryThisPass[cat] then
                categories[cat] = categories[cat] or {}
                seenCategoryThisPass[cat] = true
                usedCategoryKeys[#usedCategoryKeys + 1] = cat
                table.insert(categoryOrder, cat)
            end
            table.insert(categories[cat], item)
        end

        -- Collect all empty slots in the active bags
        local activeBags = {}
        if IsValidBagID(selectedBagID) then
            activeBags[1] = selectedBagID
        else
            for _, bagID in ipairs(DIM.BAG_IDS) do
                table.insert(activeBags, bagID)
            end
        end

        local collapseEmpty = false
        if Omni.Data and Omni.Data.Get then
            collapseEmpty = (Omni.Data:Get("collapseEmptySlots") == true)
        end

        local emptyGroups = {}
        for _, bagID in ipairs(activeBags) do
            local numSlots = GetContainerNumSlots(bagID) or 0
            for slotID = 1, numSlots do
                local info = OmniC_Container.GetContainerItemInfo(bagID, slotID)
                if not info then
                    local freeSpaceCat = GetFreeSpaceCategoryName(bagID)
                    emptyGroups[freeSpaceCat] = emptyGroups[freeSpaceCat] or {
                        bagID = bagID,
                        slotID = slotID,
                        __empty = true,
                        category = freeSpaceCat,
                        emptyCount = 0,
                    }
                    emptyGroups[freeSpaceCat].emptyCount = emptyGroups[freeSpaceCat].emptyCount + 1
                end
            end
        end

        if collapseEmpty then
            for catName, item in pairs(emptyGroups) do
                if not seenCategoryThisPass[catName] then
                    categories[catName] = categories[catName] or {}
                    seenCategoryThisPass[catName] = true
                    usedCategoryKeys[#usedCategoryKeys + 1] = catName
                    table.insert(categoryOrder, catName)
                end
                table.insert(categories[catName], item)
            end
        else
            for _, bagID in ipairs(activeBags) do
                local numSlots = GetContainerNumSlots(bagID) or 0
                for slotID = 1, numSlots do
                    local info = OmniC_Container.GetContainerItemInfo(bagID, slotID)
                    if not info then
                        local freeSpaceCat = GetFreeSpaceCategoryName(bagID)
                        local emptyItem = {
                            bagID = bagID,
                            slotID = slotID,
                            __empty = true,
                            category = freeSpaceCat,
                            emptyCount = 1,
                        }
                        if not seenCategoryThisPass[freeSpaceCat] then
                            categories[freeSpaceCat] = categories[freeSpaceCat] or {}
                            seenCategoryThisPass[freeSpaceCat] = true
                            usedCategoryKeys[#usedCategoryKeys + 1] = freeSpaceCat
                            table.insert(categoryOrder, freeSpaceCat)
                        end
                        table.insert(categories[freeSpaceCat], emptyItem)
                    end
                end
            end
        end

        -- Sort categories
        if Omni.Categorizer then
            table.sort(categoryOrder, function(a, b)
                local infoA = Omni.Categorizer:GetCategoryInfo(a)
                local infoB = Omni.Categorizer:GetCategoryInfo(b)
                local prioA = infoA and infoA.priority or 99
                local prioB = infoB and infoB.priority or 99
                if prioA ~= prioB then
                    return prioA < prioB
                end
                return a < b
            end)
        end

        -- BoE & Free Space bubble: bubble the BoE category followed
        -- by all Free Space categories to the absolute tail of the priority order.
        local reordered = {}
        for _, catName in ipairs(categoryOrder) do
            if catName ~= "BoE" and not string.match(catName, "^Free Space") then
                table.insert(reordered, catName)
            end
        end
        categories["BoE"] = categories["BoE"] or {}
        table.insert(reordered, "BoE")
        for _, catName in ipairs(categoryOrder) do
            if string.match(catName, "^Free Space") then
                table.insert(reordered, catName)
            end
        end
        categoryOrder = reordered

        if IsMerchantOpen() then
            if not vendorFlowLayoutFreeze then
                local frozenOrder = {}
                local seedOrder = (flowLayoutCache and flowLayoutCache.order) or categoryOrder
                for _, catName in ipairs(seedOrder) do
                    frozenOrder[#frozenOrder + 1] = catName
                end
                vendorFlowLayoutFreeze = {
                    order = frozenOrder,
                    laneAssignment = flowLayoutCache and flowLayoutCache.laneAssignment or nil,
                }
            else
                local frozenSeen = {}
                local finalOrder = {}
                for _, catName in ipairs(vendorFlowLayoutFreeze.order or {}) do
                    finalOrder[#finalOrder + 1] = catName
                    frozenSeen[catName] = true
                    categories[catName] = categories[catName] or {}
                end
                for _, catName in ipairs(categoryOrder) do
                    if not frozenSeen[catName] then
                        finalOrder[#finalOrder + 1] = catName
                        frozenSeen[catName] = true
                    end
                end
                vendorFlowLayoutFreeze.order = finalOrder
                categoryOrder = finalOrder
            end
        else
            vendorFlowLayoutFreeze = nil
        end
    end

    local headerIndex = 0
    -- BoE tail anchor: captured when we render the BoE section
    -- so the overflow strip below can slot in under BoE's lane at
    -- BoE's own half-width.
    local boeAnchor = nil
    local flowMode = (currentView ~= "grid" and currentView ~= "bag")
    local merchantOpen = IsMerchantOpen()
    if not flowMode then
        vendorFlowLayoutFreeze = nil
    end
    if flowMode and merchantOpen and not wasMerchantOpen and flowLayoutCache then
        local seededOrder = {}
        local cachedOrder = flowLayoutCache.order or categoryOrder
        for _, catName in ipairs(cachedOrder or {}) do
            seededOrder[#seededOrder + 1] = catName
        end
        vendorFlowLayoutFreeze = {
            order = seededOrder,
            laneAssignment = flowLayoutCache.laneAssignment or nil,
        }
    end
    local compositionSignature = nil
    local laneSignature = nil
    local canReuseLaneAssignment = false
    local flowContentOnly = false

    if flowMode then
        compositionSignature = BuildFlowCompositionSignature(
            categories,
            categoryOrder,
            usableWidth,
            itemStep,
            activeFilter
        )
        laneSignature = self:BuildFlowLaneSignature(
            categoryOrder,
            usableWidth,
            itemStep,
            activeFilter
        )
        freezeHeadersForVendor = merchantOpen
            and flowLayoutCache ~= nil
            and flowLayoutCache.signature == compositionSignature
        canReuseLaneAssignment = flowLayoutCache
            and flowLayoutCache.laneSignature == laneSignature
            and flowLayoutCache.laneAssignment ~= nil
        if currentView == "flow" and flowLayoutCache
                and compositionSignature
                and flowLayoutCache.signature == compositionSignature
                and flowLayoutCache.laneSignature == laneSignature
                and merchantOpen == wasMerchantOpen
                and (flowLayoutCache.renderCacheEpoch or 0) == (Frame._renderCacheEpoch or 0)
                and flowLayoutCache.order
                and flowLayoutCache.headerByCategory then
            local needSplitLanes = dualCategoryLanes and #categoryOrder > 1
            if (not needSplitLanes) or flowLayoutCache.laneAssignment then
                flowContentOnly = true
            end
        end
    end

    if flowContentOnly then
        ClearArray(categoryOrder)
        for i = 1, #flowLayoutCache.order do
            categoryOrder[i] = flowLayoutCache.order[i]
        end
        ClearMap(headerByCategory)
        for k, v in pairs(flowLayoutCache.headerByCategory) do
            headerByCategory[k] = v
        end
    end

    -- LPT (Longest Processing Time first) lane partitioning for
    -- flow mode. We predict each section's height, sort categories by
    -- height descending, and greedily assign each to the currently
    -- shorter lane. That places the tallest sections at the top of each
    -- lane and folds smaller categories into whichever side still has
    -- room -- otherwise a single giant category (e.g. Attunable with 50
    -- items) sinks one lane entirely while everything else stacks on
    -- the other, wasting half the frame.
    --
    -- BoE is included in the LPT partition (so its own size balances
    -- correctly), then bubbled to the end of whichever lane it landed
    -- on so the overflow strip still anchors at the bottom of BoE's
    -- lane for combat-safe slot appearance.
    local laneAssignment = nil
    if flowContentOnly then
        laneAssignment = flowLayoutCache.laneAssignment
    end
    local forceVendorFrozenLanes = flowMode
        and merchantOpen
        and vendorFlowLayoutFreeze ~= nil
        and vendorFlowLayoutFreeze.laneAssignment ~= nil
    if not flowContentOnly and flowMode and dualCategoryLanes and #categoryOrder > 1 then
        if forceVendorFrozenLanes then
            laneAssignment = vendorFlowLayoutFreeze.laneAssignment
            canReuseLaneAssignment = true
        elseif canReuseLaneAssignment then
            laneAssignment = flowLayoutCache.laneAssignment
        end
        local laneColumns = columnsForLaneWidth((usableWidth - laneGap) * 0.5)
        local function sectionHeight(catName)
            if IsCategoryCollapsed(catName) then
                return sectionHeaderHeight + sectionSpacing
            end
            local n = categories[catName] and #categories[catName] or 0
            if n <= 0 then
                return sectionHeaderHeight + sectionSpacing
            end
            local rows = math.ceil(n / laneColumns)
            return sectionHeaderHeight + rows * itemStep + sectionSpacing
        end
        local function categoryPriority(name)
            if Omni.Categorizer then
                local info = Omni.Categorizer:GetCategoryInfo(name)
                return info and info.priority or 99
            end
            return 99
        end

        -- Active quick filter? Pin that category to the top of
        -- the left lane and fold every other section around it using
        -- greedy shortest-lane assignment (no LPT rebalance, so the
        -- selected tab stays at top-left as the user requested). The
        -- caller already suppresses item dimming OOC, so this re-order
        -- is the entire "push the filter to top-left" behavior.
        local pinnedCategory = nil
        if activeFilter and categories[activeFilter] then
            pinnedCategory = activeFilter
        end

        local leftLane, rightLane = {}, {}
        local leftH, rightH = 0, 0
        if not laneAssignment then
            laneAssignment = {}
        end

        if not canReuseLaneAssignment and pinnedCategory then
            table.insert(leftLane, pinnedCategory)
            laneAssignment[pinnedCategory] = "left"
            leftH = sectionHeight(pinnedCategory)

            local rest = {}
            for _, name in ipairs(categoryOrder) do
                if name ~= pinnedCategory then table.insert(rest, name) end
            end
            table.sort(rest, function(a, b)
                return categoryPriority(a) < categoryPriority(b)
            end)
            for _, name in ipairs(rest) do
                if rightH < leftH then
                    table.insert(rightLane, name)
                    rightH = rightH + sectionHeight(name)
                    laneAssignment[name] = "right"
                else
                    table.insert(leftLane, name)
                    leftH = leftH + sectionHeight(name)
                    laneAssignment[name] = "left"
                end
            end
        elseif not canReuseLaneAssignment then
            -- LPT: sort by predicted height descending, greedy
            -- into shorter lane for balance. Tallest sections land at
            -- the top of each lane.
            local byHeight = {}
            for _, name in ipairs(categoryOrder) do table.insert(byHeight, name) end
            table.sort(byHeight, function(a, b)
                local ha, hb = sectionHeight(a), sectionHeight(b)
                if ha ~= hb then return ha > hb end
                return categoryPriority(a) < categoryPriority(b)
            end)
            for _, name in ipairs(byHeight) do
                if rightH < leftH then
                    table.insert(rightLane, name)
                    rightH = rightH + sectionHeight(name)
                    laneAssignment[name] = "right"
                else
                    table.insert(leftLane, name)
                    leftH = leftH + sectionHeight(name)
                    laneAssignment[name] = "left"
                end
            end
        end

        -- Render order: left lane top-to-bottom, then right lane
        -- top-to-bottom. Each section's lane is fixed by laneAssignment
        -- below so the render loop ignores live y-based greedy.
        if canReuseLaneAssignment then
            local leftOrdered = {}
            local rightOrdered = {}
            for _, name in ipairs(categoryOrder) do
                if laneAssignment[name] == "right" then
                    table.insert(rightOrdered, name)
                else
                    table.insert(leftOrdered, name)
                end
            end
            -- Cache reuse keeps lane placement stable, but quick-filter
            -- UX requires the active tab category to stay top-left across
            -- bag-update redraws. If the pinned category is in the left lane,
            -- bubble it to the front before we flatten left→right render order.
            if activeFilter and laneAssignment[activeFilter] == "left" then
                for i = 1, #leftOrdered do
                    if leftOrdered[i] == activeFilter then
                        table.remove(leftOrdered, i)
                        table.insert(leftOrdered, 1, activeFilter)
                        break
                    end
                end
            end
            local final = {}
            for _, n in ipairs(leftOrdered) do table.insert(final, n) end
            for _, n in ipairs(rightOrdered) do table.insert(final, n) end
            categoryOrder = final
        else
            local final = {}
            for _, n in ipairs(leftLane) do table.insert(final, n) end
            for _, n in ipairs(rightLane) do table.insert(final, n) end
            categoryOrder = final
        end
    end

    if currentView ~= "flow" or not flowContentOnly then
        for _, header in ipairs(categoryHeaders) do
            header:Hide()
        end
    end

    local perfFlowPath = nil
    if currentView == "flow" and Omni._perfEnabled and Omni.Perf then
        perfFlowPath = Omni.Perf:Begin(
            flowContentOnly and "frame.UpdateLayout.renderFlow.content" or "frame.UpdateLayout.renderFlow.full")
    end

    if Omni.ItemButton and Omni.ItemButton.BeginItemRenderBatch then
        Omni.ItemButton:BeginItemRenderBatch()
    end
    local flowSlotPaintIndex = 0
    for _, catName in ipairs(categoryOrder) do
        local catItems = categories[catName]
        local isBoeAnchor = (flowMode and catName == "BoE")
        if catItems and (#catItems > 0 or isBoeAnchor) then
            local laneX, laneY, columns, laneW
            local useRight = false
            if dualCategoryLanes then
                laneW = (usableWidth - laneGap) * 0.5
                local edgePad = hInset * 0.5
                local leftX = edgePad + itemGap
                local rightX = edgePad + laneW + laneGap + itemGap
                -- Prefer the pre-computed LPT lane assignment
                -- (flow mode). If we don't have one (bag mode), fall
                -- back to a live greedy shortest-lane check: y values
                -- grow more negative as content stacks, so the larger
                -- (less negative) y has more room. Ties go left.
                if laneAssignment and laneAssignment[catName] then
                    useRight = (laneAssignment[catName] == "right")
                else
                    useRight = (yRight > yLeft)
                end
                laneX = useRight and rightX or leftX
                laneY = useRight and yRight or yLeft
                columns = columnsForLaneWidth(laneW)
            else
                laneW = usableWidth
                laneX = itemGap
                laneY = yOffset
                columns = columnsForLaneWidth(usableWidth)
            end

            if currentView ~= "grid" then
                local header
                local reusedHeader = false
                local headerSlotIndex = nil
                if flowLayoutCache and flowLayoutCache.headerByCategory
                        and (freezeHeadersForVendor or flowContentOnly) then
                    local cachedIdx = flowLayoutCache.headerByCategory[catName]
                    if cachedIdx then
                        header = categoryHeaders[cachedIdx]
                        if header then
                            reusedHeader = true
                            headerSlotIndex = cachedIdx
                            headerIndex = math.max(headerIndex, cachedIdx)
                        end
                    end
                end
                if not header then
                    headerIndex = headerIndex + 1
                    header = categoryHeaders[headerIndex]
                    if not header then
                        -- Create category header as clickable Button
                        header = CreateFrame("Button", nil, scrollChild)
                        header:SetHeight(16)
                        header.textLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        header.textLabel:SetPoint("LEFT", header, "LEFT", 0, 0)

                        header.SetText = function(self, val)
                            self.textLabel:SetText(val)
                            self:SetWidth(math.max(self.textLabel:GetStringWidth() or 0, 40))
                        end
                        header.SetTextColor = function(self, r, g, b)
                            self.textLabel:SetTextColor(r, g, b)
                        end

                        header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                        local lastClick = 0
                        header:SetScript("OnClick", function(self, button)
                            if button == "RightButton" then
                                if Omni.Features and Omni.Features.IsAtBank and Omni.Features:IsAtBank() then
                                    Frame:TransferCategoryItems(self.catName, true)
                                end
                                return
                            end
                            local now = GetTime()
                            if (now - lastClick) <= 0.35 then
                                lastClick = 0
                                if Frame.OpenCategoryEditDialog then
                                    Frame:OpenCategoryEditDialog(self.catName)
                                end
                            else
                                lastClick = now
                                local cat = self.catName
                                if cat and OmniInventoryDB and OmniInventoryDB.char then
                                    OmniInventoryDB.char.collapsedCategories = OmniInventoryDB.char.collapsedCategories or {}
                                    local current = OmniInventoryDB.char.collapsedCategories[cat]
                                    OmniInventoryDB.char.collapsedCategories[cat] = not current
                                    if Frame.UpdateLayout then
                                        Frame:InvalidateRenderCaches()
                                        Frame:UpdateLayout(nil, { reason = "category_collapse" })
                                    end
                                end
                            end
                        end)
                        header:SetScript("OnEnter", function(self)
                            self.textLabel:SetTextColor(1, 1, 1)
                            if Omni.Features and Omni.Features.IsAtBank and Omni.Features:IsAtBank() then
                                GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
                                GameTooltip:AddLine(self.catName, 1, 1, 1)
                                GameTooltip:AddLine("Right-click to deposit all items in this category", 0.3, 0.9, 0.3)
                                GameTooltip:Show()
                            end
                        end)
                        header:SetScript("OnLeave", function(self)
                            local r, g, b = 1, 1, 1
                            if currentView == "bag" then
                                r, g, b = 0.9, 0.8, 0.4
                            elseif Omni.Categorizer then
                                r, g, b = Omni.Categorizer:GetCategoryColor(self.catName)
                            end
                            self.textLabel:SetTextColor(r, g, b)
                            GameTooltip:Hide()
                        end)

                        categoryHeaders[headerIndex] = header
                    end
                    headerSlotIndex = headerIndex
                end

                header.catName = catName
                headerByCategory[catName] = headerSlotIndex

                local collapsed = IsCategoryCollapsed(catName)
                local prefix = collapsed and "+ " or "- "

                if not reusedHeader then
                    header:ClearAllPoints()
                    header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", laneX, laneY)

                    local r, g, b = 1, 1, 1
                    if currentView == "bag" then
                        r, g, b = 0.9, 0.8, 0.4
                    elseif Omni.Categorizer then
                        r, g, b = Omni.Categorizer:GetCategoryColor(catName)
                    end
                    header:SetTextColor(r, g, b)
                    if currentView == "bag" then
                        local usedSlots = bagItemCounts and bagItemCounts[catName] or #catItems
                        local totalSlots = bagSlotCounts and bagSlotCounts[catName] or #catItems
                        local displayName = "Unknown Bag"
                        if type(catName) == "string" and string.find(catName, "_") then
                            local altName, bagIDStr = string.match(catName, "^([^_]+)_(%-?%d+)$")
                            if altName and bagIDStr then
                                local bagID = tonumber(bagIDStr)
                                displayName = altName .. "'s " .. GetBagDisplayName(bagID)
                            end
                        else
                            displayName = GetBagDisplayName(catName)
                        end
                        header:SetText(prefix .. displayName .. " (" .. usedSlots .. "/" .. totalSlots .. ")")
                    else
                        header:SetText(prefix .. catName .. " (" .. #catItems .. ")")
                    end
                elseif flowContentOnly and header then
                    if currentView == "bag" then
                        local usedSlots = bagItemCounts and bagItemCounts[catName] or #catItems
                        local totalSlots = bagSlotCounts and bagSlotCounts[catName] or #catItems
                        local displayName = "Unknown Bag"
                        if type(catName) == "string" and string.find(catName, "_") then
                            local altName, bagIDStr = string.match(catName, "^([^_]+)_(%-?%d+)$")
                            if altName and bagIDStr then
                                local bagID = tonumber(bagIDStr)
                                displayName = altName .. "'s " .. GetBagDisplayName(bagID)
                            end
                        else
                            displayName = GetBagDisplayName(catName)
                        end
                        header:SetText(prefix .. displayName .. " (" .. usedSlots .. "/" .. totalSlots .. ")")
                    else
                        header:SetText(prefix .. catName .. " (" .. #catItems .. ")")
                    end
                end
                header:Show()

                laneY = laneY - sectionHeaderHeight
            end

            local collapsed = IsCategoryCollapsed(catName)
            if not collapsed then
                local layoutIndex = 0
                for i, itemInfo in ipairs(catItems) do
                    -- Look up the persistent slot button for this item's
                    -- (bag, slot). It was created, parented to the bag's
                    -- ItemContainer, and SetID'd by EnsureSlotButtons above, so
                    -- we only need to reposition and SetItem here -- all of
                    -- which is still OOC because UpdateLayout is combat-gated.
                    local bagID = itemInfo.bagID
                    local slotID = itemInfo.slotID
                    local btn
                    if itemInfo.__offline or isOfflineCharView then
                        if Omni.Pool then
                            btn = Omni.Pool:Acquire("ItemButton")
                        end
                        if btn then
                            table.insert(offlineFlowButtons, btn)
                            if btn:GetParent() ~= scrollChild then
                                pcall(btn.SetParent, btn, scrollChild)
                            end
                        end
                    else
                        btn = (bagID and slotID) and GetSlotButton(bagID, slotID) or nil
                    end

                    if btn then
                        if slotID then
                            pcall(btn.SetID, btn, slotID)
                        end
                        layoutIndex = layoutIndex + 1
                        flowSlotPaintIndex = flowSlotPaintIndex + 1
                        local col = ((layoutIndex - 1) % columns)
                        local row = math.floor((layoutIndex - 1) / columns)
                        local x = laneX + col * itemStep
                        local y = laneY - row * itemStep

                        local needsReposition = (btn._oiLayoutX ~= x) or (btn._oiLayoutY ~= y)
                        local needsMetrics = (btn._oiLayoutScale ~= itemScale)
                        local slotItem = itemInfo
                        local nextRenderKey = ItemRenderKey(slotItem)
                        local skipItemPaint = flowContentOnly and (btn._oiRenderKey == nextRenderKey)
                        local deferItemPaint = (not skipItemPaint)
                            and layoutOpts and layoutOpts.reason == "show_open"
                            and flowSlotPaintIndex > FLOW_SHOW_OPEN_DEFER_AFTER

                        if deferItemPaint then
                            if needsReposition then
                                btn:ClearAllPoints()
                                btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, y)
                                btn._oiLayoutX = x
                                btn._oiLayoutY = y
                            end
                            if needsMetrics then
                                ApplyItemButtonMetrics(btn, itemScale)
                                btn._oiLayoutScale = itemScale
                            end
                            pcall(btn.Show, btn)
                            btn:SetAlpha(0)
                            deferredFlowPaintQueue[#deferredFlowPaintQueue + 1] = { btn, slotItem }
                        elseif skipItemPaint then
                            if flowContentOnly and not needsReposition and not needsMetrics then
                                local targetA = (slotItem and slotItem.__empty) and EMPTY_SLOT_ALPHA or 1
                                if not btn:IsShown() then btn:Show() end
                                btn:SetAlpha(targetA)
                            else
                                if needsReposition then
                                    btn:ClearAllPoints()
                                    btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, y)
                                    btn._oiLayoutX = x
                                    btn._oiLayoutY = y
                                end
                                if needsMetrics then
                                    ApplyItemButtonMetrics(btn, itemScale)
                                    btn._oiLayoutScale = itemScale
                                end
                                local targetA = (slotItem and slotItem.__empty) and EMPTY_SLOT_ALPHA or 1
                                if not btn:IsShown() then btn:Show() end
                                btn:SetAlpha(targetA)
                            end
                        elseif flowContentOnly and not needsReposition and not needsMetrics then
                            btn:SetAlpha(1)
                            local success = pcall(function()
                                SetButtonItem(btn, slotItem)
                                btn._oiRenderKey = nextRenderKey
                                btn:Show()
                            end)
                            if not success then
                                pcall(SetButtonItem, btn, nil)
                                if btn.icon then btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
                                pcall(btn.Show, btn)
                                btn._oiRenderKey = "error"
                            end
                            if slotItem and slotItem.__empty then
                                btn:SetAlpha(EMPTY_SLOT_ALPHA)
                            end
                        else
                            if needsReposition then
                                btn:ClearAllPoints()
                                btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, y)
                                btn._oiLayoutX = x
                                btn._oiLayoutY = y
                            end
                            if needsMetrics then
                                ApplyItemButtonMetrics(btn, itemScale)
                                btn._oiLayoutScale = itemScale
                            end
                            btn:SetAlpha(1)
                            local success = pcall(function()
                                SetButtonItem(btn, slotItem)
                                btn._oiRenderKey = nextRenderKey
                                btn:Show()
                            end)
                            if not success then
                                pcall(SetButtonItem, btn, nil)
                                if btn.icon then btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
                                pcall(btn.Show, btn)
                                btn._oiRenderKey = "error"
                            end
                            if slotItem and slotItem.__empty then
                                btn:SetAlpha(EMPTY_SLOT_ALPHA)
                            end
                        end

                        touched[bagID] = touched[bagID] or {}
                        if not seenTouchedBagsThisPass[bagID] then
                            seenTouchedBagsThisPass[bagID] = true
                            usedTouchedBags[#usedTouchedBags + 1] = bagID
                        end
                        touched[bagID][slotID] = true
                        table.insert(itemButtons, btn)
                    end
                end

                local catRows = math.ceil(layoutIndex / columns)
                local itemsBottomY = laneY - (catRows * itemStep)
                laneY = itemsBottomY - sectionSpacing
            else
                laneY = laneY - sectionSpacing
            end

            if isBoeAnchor then
                -- Remember BoE's lane geometry. The overflow
                -- strip anchors to BoE's x/columns (same half-width
                -- column) but uses the lane's final bottom y (captured
                -- after the loop), so BoE can sit at the top of its
                -- lane per LPT without the overflow grid overlapping
                -- the sections rendered below it.
                boeAnchor = {
                    x = laneX,
                    columns = columns,
                    laneW = laneW,
                    lane = useRight and "right" or "left",
                }
            end

            if dualCategoryLanes then
                if useRight then
                    yRight = laneY
                else
                    yLeft = laneY
                end
            else
                yOffset = laneY
            end
        end
    end
    if Omni.ItemButton and Omni.ItemButton.EndItemRenderBatch then
        Omni.ItemButton:EndItemRenderBatch()
    end

    local mainBottomY
    if dualCategoryLanes then
        mainBottomY = math.min(yLeft, yRight)
    else
        mainBottomY = yOffset
    end

    -- Overflow strip
    --
    -- Every slot button that did NOT receive an item from the sorted pass
    -- gets parked in a grid at alpha 0 immediately below the BoE section
    -- (its own dual-lane column), so any item that lands in a previously
    -- empty slot during combat visually pops in "under BoE" without
    -- needing a protected SetPoint call. This guarantees:
    --
    --   1) Every bag slot has a real, on-screen position at all times --
    --      RefreshCombatContent can just SetAlpha(1) + SetItem and the
    --      user sees the new item immediately.
    --
    --   2) Items that are used / sold / moved during combat can fade out
    --      (alpha 0) in place without protected Hide() calls, and come
    --      back cleanly on the next OOC render.
    --
    -- If flow mode didn't render a BoE anchor (grid/bag view), we fall
    -- back to full-width overflow anchored at the deepest lane.
    local overflowX, overflowColumns, overflowTop
    if boeAnchor then
        overflowX = boeAnchor.x
        overflowColumns = boeAnchor.columns
        -- Park overflow at the bottom of BoE's entire lane (not
        -- directly below BoE's item rows) so sections rendered under
        -- BoE in the same lane aren't overlapped by the pre-parked
        -- grid when combat pops a new item into a previously empty
        -- slot.
        local laneBottomY = (boeAnchor.lane == "right") and yRight or yLeft
        overflowTop = laneBottomY - OVERFLOW_ROW_GAP
    else
        overflowX = itemGap
        overflowColumns = columnsForLaneWidth(usableWidth)
        overflowTop = mainBottomY - OVERFLOW_ROW_GAP
    end

    local occupancySig = ""
    local skipOverflowRepark = false
    if flowMode then
        occupancySig = BuildScopedSlotOccupancySignature(bagPreviewScopeSet)
        skipOverflowRepark = flowContentOnly
            and not bagPreviewScopeSet
            and flowLayoutCache
            and flowLayoutCache.occupancySignature == occupancySig
    end

    local overflowIndex = 0
    if skipOverflowRepark then
        local scopedTotal = GetScopedBagSlotsTotal(bagPreviewScopeSet)
        local nTouched = CountTouchedSlotsInScope(touched, bagPreviewScopeSet)
        overflowIndex = math.max(0, scopedTotal - nTouched)
    else
        if isOfflineCharView then
            -- When viewing an offline character, all items use pool buttons.
            -- The real player's slot buttons were already hidden above.
            -- Skip the overflow parking entirely.
            overflowIndex = 0
        else
        IterateSlotButtons(function(bagID, slotID, btn)
            if bagPreviewScopeSet and not bagPreviewScopeSet[bagID] then
                pcall(btn.SetAlpha, btn, 0)
                if btn._oiRenderKey ~= "empty" then
                    pcall(SetButtonItem, btn, nil)
                    btn._oiRenderKey = "empty"
                end
                return
            end
            local isTouched = touched[bagID] and touched[bagID][slotID]
            if isTouched then return end

            local col = overflowIndex % overflowColumns
            local row = math.floor(overflowIndex / overflowColumns)
            local x = overflowX + col * itemStep
            local y = overflowTop - row * itemStep

            local needsReposition = (btn._oiLayoutX ~= x) or (btn._oiLayoutY ~= y)
            local needsMetrics = (btn._oiLayoutScale ~= itemScale)
            if not needsReposition and not needsMetrics and btn._oiRenderKey == "empty" then
                local a = btn.GetAlpha and btn:GetAlpha() or 0
                if a < 0.01 then
                    pcall(btn.Show, btn)
                    overflowIndex = overflowIndex + 1
                    return
                end
            end
            pcall(function()
                if needsReposition then
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, y)
                    btn._oiLayoutX = x
                    btn._oiLayoutY = y
                end
                if needsMetrics then
                    ApplyItemButtonMetrics(btn, itemScale)
                    btn._oiLayoutScale = itemScale
                end
                btn:SetAlpha(0)
            end)
            if btn._oiRenderKey ~= "empty" then
                pcall(SetButtonItem, btn, nil)
                btn._oiRenderKey = "empty"
            end
            pcall(btn.Show, btn)

            overflowIndex = overflowIndex + 1
        end)
        end -- not isOfflineCharView
    end

    local overflowRows = math.ceil(overflowIndex / math.max(overflowColumns, 1))
    local overflowExtent = overflowRows > 0
        and (OVERFLOW_ROW_GAP + overflowRows * itemStep)
        or 0

    -- Scroll height has to accommodate the deepest point on the page,
    -- which is either the deepest lane (mainBottomY) or the bottom of
    -- the overflow strip anchored at the bottom of BoE's lane.
    local overflowAnchorY
    if boeAnchor then
        overflowAnchorY = (boeAnchor.lane == "right") and yRight or yLeft
    else
        overflowAnchorY = mainBottomY
    end
    local overflowBottom = overflowAnchorY - overflowExtent
    local deepestY = math.min(mainBottomY, overflowBottom)
    scrollChild:SetHeight(math.abs(deepestY) + itemGap)

    if perfFlowPath and Omni._perfEnabled and Omni.Perf then
        Omni.Perf:End(
            flowContentOnly and "frame.UpdateLayout.renderFlow.content" or "frame.UpdateLayout.renderFlow.full",
            perfFlowPath,
            {
                flowContentOnly = flowContentOnly == true,
                overflowSkipped = skipOverflowRepark == true,
            })
    end

    if #deferredFlowPaintQueue > 0 then
        ScheduleDeferredFlowItemPaint()
    end

    if flowMode then
        flowLayoutCache = {
            signature = compositionSignature,
            laneSignature = laneSignature,
            laneAssignment = laneAssignment,
            headerByCategory = headerByCategory,
            order = categoryOrder,
            renderCacheEpoch = Frame._renderCacheEpoch or 0,
            itemContentSignature = BuildFlowItemContentSignature(items),
            occupancySignature = occupancySig,
        }
        if merchantOpen and vendorFlowLayoutFreeze and laneAssignment then
            vendorFlowLayoutFreeze.laneAssignment = laneAssignment
        end
    else
        flowLayoutCache = nil
    end
    wasMerchantOpen = merchantOpen
    if currentView == "flow" then
        return flowContentOnly and "content" or "full"
    end
    return "na"
end

-- =============================================================================
-- List View Rendering (Data Table)
-- =============================================================================


function Frame:RenderListView(items)
    if not mainFrame or not mainFrame.scrollChild then return end

    local scrollChild = mainFrame.scrollChild

    -- Park every persistent slot button at alpha 0 so flow buttons
    -- don't peek through the list layout. We never Release them back to
    -- the pool -- they stay allocated so we can flip straight back to
    -- flow/grid without re-parenting (which is protected during combat).
    IterateSlotButtons(function(_, _, btn)
        pcall(btn.SetAlpha, btn, 0)
    end)
    if Omni.Pool then
        for _, btn in ipairs(offlineFlowButtons) do
            Omni.Pool:Release("ItemButton", btn)
            pcall(btn.Hide, btn)
        end
    end
    ClearArray(offlineFlowButtons)

    itemButtons = {}

    for _, row in ipairs(listRows) do
        row:Hide()
    end

    for _, header in ipairs(categoryHeaders) do
        header:Hide()
    end

    -- Rows are now plain Buttons (see CreateFrame above) so there
    -- is nothing secure to configure. Kept as a no-op to keep the call
    -- sites below trivially correct.
    local function ConfigureSecureRowUse(row)
        if row then row.secureUseConfigured = false end
    end

    -- Layout constants
    local ROW_HEIGHT = 22
    local ICON_SIZE = 18
    local contentWidth = mainFrame.content:GetWidth() - 8
    local yOffset = -4

    for i, itemInfo in ipairs(items) do
        -- Get or create row frame
        local row = listRows[i]
        if not row then
            -- Plain Button (no secure template) so list rows do NOT
            -- promote OmniInventoryFrame to "protected by association".
            -- List view's row clicks are insecure-only by design (they
            -- call PickupContainerItem directly which is forbidden in
            -- combat anyway); secure use/swap during combat is handled
            -- by the flow/grid item buttons via ContainerFrameItemButton
            -- Template.
            row = CreateFrame("Button", nil, scrollChild)
            row:SetHeight(ROW_HEIGHT)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            -- Background (alternating)
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")

            -- Icon
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(ICON_SIZE, ICON_SIZE)
            row.icon:SetPoint("LEFT", 4, 0)

            -- Name
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.name:SetWidth(180)
            row.name:SetJustifyH("LEFT")

            -- Type
            row.itemType = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.itemType:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
            row.itemType:SetWidth(80)
            row.itemType:SetJustifyH("LEFT")
            row.itemType:SetTextColor(0.7, 0.7, 0.7)

            -- Quantity
            row.qty = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.qty:SetPoint("RIGHT", -8, 0)
            row.qty:SetWidth(30)
            row.qty:SetJustifyH("RIGHT")

            -- Hover highlight
            row:SetScript("OnEnter", function(self)
                self.bg:SetVertexColor(0.3, 0.3, 0.3, 1)
                if self.itemInfo then
                    self.__omniUsesCustomTooltip = true
                    if Omni.ItemButton and Omni.ItemButton.SetOmniItemTooltipOwner then
                        Omni.ItemButton.SetOmniItemTooltipOwner(self)
                    else
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    end
                    if self.itemInfo.__offline and self.itemInfo.__owner then
                        pcall(GameTooltip.SetHyperlink, GameTooltip, self.itemInfo.hyperlink)
                        GameTooltip:AddLine(" ")
                        local ownerName = self.itemInfo.__owner or "Unknown Character"
                        local locationStr = self.itemInfo.__location and (self.itemInfo.__location:gsub("^%l", string.upper)) or "Bags"
                        GameTooltip:AddLine("Held by: " .. ownerName .. " (" .. locationStr .. ")", 0.9, 0.8, 0.4)
                    else
                        local ok = pcall(GameTooltip.SetBagItem, GameTooltip, self.itemInfo.bagID, self.itemInfo.slotID)
                        if not ok and self.itemInfo.hyperlink then
                            pcall(GameTooltip.SetHyperlink, GameTooltip, self.itemInfo.hyperlink)
                            if self.itemInfo.__offline then
                                GameTooltip:AddLine(" ")
                                local charName = Omni.Data and Omni.Data.currentViewedChar or "Unknown Character"
                                GameTooltip:AddLine("Offline Item (" .. charName .. ")", 0.5, 0.5, 0.5)
                            end
                        end
                    end
                    GameTooltip:Show()
                    if Omni.ItemButton and Omni.ItemButton.FinalizeOmniItemTooltipLayout then
                        Omni.ItemButton.FinalizeOmniItemTooltipLayout()
                    end
                    if Omni.ItemButton and Omni.ItemButton.RefreshCompareTooltips then
                        Omni.ItemButton:RefreshCompareTooltips()
                    end
                    if IsMerchantOpen() and (not CursorHasItem or not CursorHasItem()) and ShowContainerSellCursor then
                        ShowContainerSellCursor(self.itemInfo.bagID, self.itemInfo.slotID)
                    elseif CursorUpdate then
                        CursorUpdate(self)
                    end
                end
            end)
            row:SetScript("OnLeave", function(self)
                local alpha = (i % 2 == 0) and 0.15 or 0.1
                self.bg:SetVertexColor(0.1, 0.1, 0.1, 1)
                self.__omniUsesCustomTooltip = false
                if Omni.ItemButton and Omni.ItemButton.HideTooltipIfOwnedBy then
                    Omni.ItemButton.HideTooltipIfOwnedBy(self)
                elseif GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self then
                    GameTooltip:Hide()
                end
                if ResetCursor then
                    ResetCursor()
                end
            end)
            row:SetScript("PreClick", function(self, mouseButton)
                if Omni.ItemButton and Omni.ItemButton.OnPreClick then
                    Omni.ItemButton:OnPreClick(self, mouseButton)
                end
            end)
            row:HookScript("OnClick", function(self, mouseButton)
                local mb = mouseButton
                if mb == "RightButtonUp" or mb == "RightButtonDown" then
                    mb = "RightButton"
                elseif mb == "LeftButtonUp" or mb == "LeftButtonDown" then
                    mb = "LeftButton"
                end
                if self.itemInfo and self.itemInfo.__offline then
                    if mb == "LeftButton" and IsModifiedClick() then
                        HandleModifiedItemClick(self.itemInfo.hyperlink)
                    end
                    return
                end
                if mb == "RightButton" and self.itemInfo then
                    local bagID, slotID = self.itemInfo.bagID, self.itemInfo.slotID
                    if bagID and slotID and bagID >= 0 and slotID >= 1 then
                        if Omni.ItemButton and Omni.ItemButton.HandleBagSlotRightClickInventory then
                            Omni.ItemButton:HandleBagSlotRightClickInventory(bagID, slotID, self.secureUseConfigured)
                        end
                    end
                    return
                end
                if mb ~= "LeftButton" or not self.itemInfo then
                    return
                end
                local bagID, slotID = self.itemInfo.bagID, self.itemInfo.slotID
                if not bagID or not slotID or bagID < 0 or slotID < 1 then
                    return
                end
                if InCombatLockdown and InCombatLockdown() then
                    return
                end
                PickupContainerItem(bagID, slotID)
            end)
            listRows[i] = row
        end

        -- Position row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, yOffset)

        -- Set background color (alternating rows)
        if i % 2 == 0 then
            row.bg:SetVertexColor(0.15, 0.15, 0.15, 1)
        else
            row.bg:SetVertexColor(0.1, 0.1, 0.1, 1)
        end

        -- Error boundary
        local success, err = pcall(function()
            -- Set icon
            row.icon:SetTexture(itemInfo.iconFileID or "Interface\\Icons\\INV_Misc_QuestionMark")

            -- Get item info for name and type
            local itemName, _, quality, _, _, itemType, itemSubType = nil, nil, itemInfo.quality, nil, nil, nil, nil
            if itemInfo.hyperlink then
                itemName, _, quality, _, _, itemType, itemSubType = GetItemInfo(itemInfo.hyperlink)
            end

            -- Set name with quality color
            local QUALITY_COLORS = {
                [0] = { 0.62, 0.62, 0.62 },
                [1] = { 1.00, 1.00, 1.00 },
                [2] = { 0.12, 1.00, 0.00 },
                [3] = { 0.00, 0.44, 0.87 },
                [4] = { 0.64, 0.21, 0.93 },
                [5] = { 1.00, 0.50, 0.00 },
                [6] = { 0.90, 0.80, 0.50 },
                [7] = { 0.00, 0.80, 1.00 },
            }
            local qColor = QUALITY_COLORS[quality or 1] or QUALITY_COLORS[1]
            local displayName = itemName or itemInfo.hyperlink or "Unknown"
            if itemInfo.__offline and itemInfo.__owner then
                displayName = displayName .. " |cFF808080[" .. itemInfo.__owner .. "]|r"
            end
            row.name:SetText(displayName)
            row.name:SetTextColor(qColor[1], qColor[2], qColor[3])

            -- Set type
            row.itemType:SetText(itemSubType or itemType or "")

            -- Set quantity
            local count = itemInfo.stackCount or 1
            if count > 1 then
                row.qty:SetText(count)
            else
                row.qty:SetText("")
            end
        end)

        if not success then
             row.name:SetText("Error loading item")
             row.name:SetTextColor(1, 0, 0)
             row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        -- Store item info for click/tooltip
        row.itemInfo = itemInfo
        row:SetScript("PreClick", nil)
        ConfigureSecureRowUse(row, itemInfo.bagID, itemInfo.slotID)

        -- Apply quick filter dimming
        if itemInfo.__offline then
            row:SetAlpha(0.65)
            row.icon:SetDesaturated(true)
        elseif itemInfo.isQuickFiltered then
            row:SetAlpha(0.28)
            row.icon:SetDesaturated(true)
        else
            row:SetAlpha(1.0)
            row.icon:SetDesaturated(false)
        end

        row:Show()
        yOffset = yOffset - ROW_HEIGHT
    end

    scrollChild:SetHeight(math.abs(yOffset) + 8)
end

-- =============================================================================
-- Search
-- =============================================================================

local function GetItemSearchInfo(itemInfo)
    if not itemInfo or not itemInfo.hyperlink then
        return nil
    end

    local link = itemInfo.hyperlink
    local name, _, quality, iLvl, reqLevel, classType, subClassType, _, equipLoc = GetItemInfo(link)

    -- Retrieve quest and soulbound info
    local isBOP = false
    local isBOE = false
    local isBOU = false
    local isBOA = false
    local isQuest = false

    -- Check soulbound using API
    if Omni.API and Omni.API.IsItemSoulbound and itemInfo.bagID and itemInfo.slotID then
        isBOP = Omni.API:IsItemSoulbound(itemInfo.bagID, itemInfo.slotID)
    end

    -- Tooltip scanning for bind and quest info
    local scanningTooltip = _G["OmniScanningTooltip"]
    if scanningTooltip then
        scanningTooltip:ClearLines()
        if itemInfo.bagID and itemInfo.slotID then
            local ok = pcall(scanningTooltip.SetBagItem, scanningTooltip, itemInfo.bagID, itemInfo.slotID)
            if not ok and link then
                pcall(scanningTooltip.SetHyperlink, scanningTooltip, link)
            end
        else
            scanningTooltip:SetHyperlink(link)
        end

        for i = 1, scanningTooltip:NumLines() do
            local leftFrame = _G["OmniScanningTooltipTextLeft" .. i]
            local leftText = leftFrame and leftFrame:GetText()
            if leftText then
                local lowerText = string.lower(leftText)
                if string.find(lowerText, "bind on pickup") or string.find(lowerText, "binds on pickup") then
                    isBOP = true
                elseif string.find(lowerText, "bind on equip") or string.find(lowerText, "binds on equip") then
                    isBOE = true
                elseif string.find(lowerText, "bind on use") or string.find(lowerText, "binds on use") then
                    isBOU = true
                elseif string.find(lowerText, "binds to account") or string.find(lowerText, "binds to battle.net account") then
                    isBOA = true
                elseif string.find(lowerText, "quest item") then
                    isQuest = true
                end
            end
        end
    end

    -- Quest item from API if available
    if GetContainerItemQuestInfo and itemInfo.bagID and itemInfo.slotID then
        local isQuestItem, _, isActive = GetContainerItemQuestInfo(itemInfo.bagID, itemInfo.slotID)
        if isQuestItem or isActive then
            isQuest = true
        end
    end

    return {
        name = name or "",
        quality = quality or 0,
        iLvl = iLvl or 0,
        reqLevel = reqLevel or 0,
        classType = classType or "",
        subClassType = subClassType or "",
        equipLoc = equipLoc or "",
        isBOP = isBOP,
        isBOE = isBOE,
        isBOU = isBOU,
        isBOA = isBOA,
        isQuest = isQuest,
    }
end

local function GetCachedItemSearchInfo(itemInfo)
    if not itemInfo then return nil end
    if not itemInfo.__searchInfo then
        itemInfo.__searchInfo = GetItemSearchInfo(itemInfo)
    end
    return itemInfo.__searchInfo
end

local function CompareValue(itemVal, operator, targetVal)
    if not itemVal or not targetVal then return false end
    if operator == ">=" then
        return itemVal >= targetVal
    elseif operator == "<=" then
        return itemVal <= targetVal
    elseif operator == ">" then
        return itemVal > targetVal
    elseif operator == "<" then
        return itemVal < targetVal
    elseif operator == "!=" or operator == "<>" then
        return itemVal ~= targetVal
    else
        return itemVal == targetVal
    end
end

local function ParseNumericComparison(valStr)
    local operator, numStr = string.match(valStr, "^([><=!]+)%s*(%d+)$")
    if not operator then
        numStr = string.match(valStr, "^(%d+)$")
        operator = "="
    end
    return operator, tonumber(numStr)
end

local qualityNames = {
    [0] = "poor", [1] = "common", [2] = "uncommon", [3] = "rare",
    [4] = "epic", [5] = "legendary", [6] = "artifact", [7] = "heirloom"
}

local function MatchQuality(info, queryVal)
    local op, num = ParseNumericComparison(queryVal)
    if num then
        return CompareValue(info.quality, op, num)
    else
        local qName = qualityNames[info.quality]
        if qName then
            return string.find(qName, queryVal, 1, true) ~= nil
        end
    end
    return false
end

local function MatchItemLevel(info, queryVal)
    local op, num = ParseNumericComparison(queryVal)
    if num then
        return CompareValue(info.iLvl, op, num)
    end
    return false
end

local function MatchType(info, queryVal)
    local lowerQuery = string.lower(queryVal)
    return string.find(string.lower(info.classType), lowerQuery, 1, true) ~= nil
        or string.find(string.lower(info.subClassType), lowerQuery, 1, true) ~= nil
        or string.find(string.lower(info.equipLoc), lowerQuery, 1, true) ~= nil
end

local function IsItemInEquipmentSet(itemInfo, targetSetName)
    if not itemInfo then return false end
    if Omni.API and Omni.API.IsItemInEquipmentSet and itemInfo.bagID and itemInfo.slotID then
        local inSet = Omni.API:IsItemInEquipmentSet(itemInfo.bagID, itemInfo.slotID, targetSetName)
        if inSet then return true end
    end

    if not GetNumEquipmentSets or not GetEquipmentSetInfo then return false end
    local numSets = GetNumEquipmentSets()
    local link = itemInfo.hyperlink
    local targetItemID = link and tonumber(string.match(link, "item:(%d+)"))
    if not targetItemID then return false end

    for index = 1, numSets do
        local setName = GetEquipmentSetInfo(index)
        if setName and (targetSetName == "" or string.find(string.lower(setName), string.lower(targetSetName), 1, true)) then
            local itemIDs = GetEquipmentSetItemIDs(setName)
            if itemIDs then
                for _, id in pairs(itemIDs) do
                    if id == targetItemID then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function MatchKeyword(info, keyword)
    if keyword == "bop" or keyword == "soulbound" or keyword == "bound" then
        return info.isBOP
    elseif keyword == "boe" then
        return info.isBOE
    elseif keyword == "bou" then
        return info.isBOU
    elseif keyword == "boa" then
        return info.isBOA
    elseif keyword == "quest" then
        return info.isQuest
    end
    return false
end

local function MatchTooltip(itemInfo, queryVal)
    local scanningTooltip = _G["OmniScanningTooltip"]
    if not scanningTooltip then return false end
    scanningTooltip:ClearLines()
    if itemInfo.bagID and itemInfo.slotID then
        local ok = pcall(scanningTooltip.SetBagItem, scanningTooltip, itemInfo.bagID, itemInfo.slotID)
        if not ok and itemInfo.hyperlink then
            pcall(scanningTooltip.SetHyperlink, scanningTooltip, itemInfo.hyperlink)
        end
    else
        scanningTooltip:SetHyperlink(itemInfo.hyperlink)
    end
    local lowerQuery = string.lower(queryVal)
    for i = 1, scanningTooltip:NumLines() do
        local leftFrame = _G["OmniScanningTooltipTextLeft" .. i]
        local leftText = leftFrame and leftFrame:GetText()
        if leftText and string.find(string.lower(leftText), lowerQuery, 1, true) then
            return true
        end
        local rightFrame = _G["OmniScanningTooltipTextRight" .. i]
        local rightText = rightFrame and rightFrame:GetText()
        if rightText and string.find(string.lower(rightText), lowerQuery, 1, true) then
            return true
        end
    end
    return false
end

local function MatchSingleAtom(itemInfo, info, atom)
    atom = string.gsub(atom, "^%s*(.-)%s*$", "%1")
    if atom == "" then return true end

    local negate = false
    if string.sub(atom, 1, 1) == "!" then
        negate = true
        atom = string.sub(atom, 2)
        atom = string.gsub(atom, "^%s*(.-)%s*$", "%1")
    end

    local match = false
    local prefix, val = string.match(atom, "^([^:]+):(.*)$")
    if prefix then
        prefix = string.lower(prefix)
        if prefix == "q" or prefix == "quality" then
            match = MatchQuality(info, val)
        elseif prefix == "ilvl" or prefix == "lvl" or prefix == "level" then
            match = MatchItemLevel(info, val)
        elseif prefix == "t" or prefix == "type" or prefix == "slot" then
            match = MatchType(info, val)
        elseif prefix == "s" or prefix == "set" then
            match = IsItemInEquipmentSet(itemInfo, val)
        elseif prefix == "tooltip" or prefix == "t" or prefix == "~t" then
            match = MatchTooltip(itemInfo, val)
        elseif prefix == "bind" then
            match = MatchKeyword(info, string.lower(val))
        else
            match = string.find(string.lower(info.name), string.lower(atom), 1, true) ~= nil
        end
    else
        local lowerAtom = string.lower(atom)
        if lowerAtom == "bop" or lowerAtom == "soulbound" or lowerAtom == "bound"
            or lowerAtom == "boe" or lowerAtom == "bou" or lowerAtom == "boa" or lowerAtom == "quest" then
            match = MatchKeyword(info, lowerAtom)
        elseif lowerAtom == "equipment" or lowerAtom == "equip" then
            match = (info.equipLoc ~= "" and info.equipLoc ~= "INVTYPE_NON_EQUIP_TEXT")
        else
            match = string.find(string.lower(info.name), lowerAtom, 1, true) ~= nil
        end
    end

    if negate then
        return not match
    else
        return match
    end
end

local function MatchItemQuery(itemInfo, query)
    if not itemInfo or not itemInfo.hyperlink then
        return false
    end

    query = string.gsub(query or "", "^%s*(.-)%s*$", "%1")
    if query == "" then
        return true
    end

    -- Try rule engine expression (MyBags / Bagshui style)
    if string.match(query, "%a+%b()") then
        if Omni.Rules and Omni.Rules.Compile then
            local func, err = Omni.Rules:Compile(query)
            if func then
                local ok, result = pcall(Omni.Rules.Match, Omni.Rules, func, itemInfo)
                if ok then
                    return result
                end
            end
        end
    end

    local info = GetCachedItemSearchInfo(itemInfo)
    if not info then
        return false
    end

    for orPart in string.gmatch(query, "[^|]+") do
        orPart = string.gsub(orPart, "^%s*(.-)%s*$", "%1")
        if orPart ~= "" then
            local andMatch = true
            for andPart in string.gmatch(orPart, "[^%s]+") do
                if not MatchSingleAtom(itemInfo, info, andPart) then
                    andMatch = false
                    break
                end
            end
            if andMatch then
                return true
            end
        end
    end

    return false
end

Frame.MatchItemQuery = MatchItemQuery
Omni.MatchItemQuery = MatchItemQuery

local function OpenCharacterSelectMenu(anchorFrame)
    local dropdown = _G["OmniCharacterDropdownMenu"]
    if not dropdown then
        dropdown = CreateFrame("Frame", "OmniCharacterDropdownMenu", UIParent, "UIDropDownMenuTemplate")
    end

    local realmName = GetRealmName()
    local characters = {}
    if OmniInventoryDB and OmniInventoryDB.realm and OmniInventoryDB.realm[realmName] then
        for name, data in pairs(OmniInventoryDB.realm[realmName]) do
            table.insert(characters, { name = name, class = data.class })
        end
    end
    table.sort(characters, function(a, b) return a.name < b.name end)

    local menuList = {
        { text = "Select Character", isTitle = true, notCheckable = true }
    }

    for _, char in ipairs(characters) do
        local colorStr = "FFFFFFFF"
        if char.class then
            local colorTable = RAID_CLASS_COLORS[char.class]
            if colorTable then
                colorStr = string.format("FF%02x%02x%02x", colorTable.r * 255, colorTable.g * 255, colorTable.b * 255)
            end
        end
        local isCurrent = (Omni.Data.currentViewedChar == char.name) or (not Omni.Data.currentViewedChar and char.name == Omni.Data.playerName)
        local displayName = char.name
        if char.name == Omni.Data.playerName then
            displayName = "You"
        end
        table.insert(menuList, {
            text = string.format("|c%s%s|r", colorStr, displayName),
            checked = isCurrent,
            func = function()
                if char.name == Omni.Data.playerName then
                    Omni.Data.currentViewedChar = nil
                else
                    Omni.Data.currentViewedChar = char.name
                end

                if Omni.Frame then
                    Omni.Frame:InvalidateRenderCaches({ clearLayout = true })
                    Omni.Frame:UpdateTitle()
                    Omni.Frame:UpdateLayout(nil, { forceFull = true, immediate = true, reason = "char_switch" })
                end
                if Omni.BankFrame then
                    Omni.BankFrame:UpdateTitle()
                    Omni.BankFrame:UpdateLayout()
                end
            end
        })
    end

    EasyMenu(menuList, dropdown, anchorFrame, 0, 0, "MENU")
end

Omni.Frame.OpenCharacterSelectMenu = OpenCharacterSelectMenu

function Frame:UpdateTitle()
    if not mainFrame or not mainFrame.header or not mainFrame.header.title then return end
    local viewedChar = Omni.Data and Omni.Data.currentViewedChar
    if viewedChar and viewedChar ~= Omni.Data.playerName then
        local colorStr = "FFFFFFFF"
        local realm = OmniInventoryDB.realm[Omni.Data.realmName]
        local charData = realm and realm[viewedChar]
        if charData and charData.class then
            local colorTable = RAID_CLASS_COLORS[charData.class]
            if colorTable then
                colorStr = string.format("FF%02x%02x%02x", colorTable.r * 255, colorTable.g * 255, colorTable.b * 255)
            end
        end
        mainFrame.header.title.text:SetText(string.format("|c%s%s|r's Bags", colorStr, viewedChar))
    else
        mainFrame.header.title.text:SetText("|cFF00FF00Omni|rInventory")
    end
end

function Frame:ApplySearch(text)
    local perfToken = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("frame.ApplySearch")
    searchText = text or ""
    isSearchActive = (searchText ~= "")

    if not isSearchActive then
        -- Clear search - show all itemButtons
        for _, btn in ipairs(itemButtons) do
            if Omni.ItemButton then
                Omni.ItemButton:ClearSearch(btn)
            end
        end
        -- Show all list rows (they'll be rebuilt on next update anyway)
        for _, row in ipairs(listRows) do
            if row.itemInfo then
                if row.itemInfo.isQuickFiltered then
                    row:SetAlpha(0.28)
                    if row.icon then row.icon:SetDesaturated(true) end
                else
                    row:SetAlpha(1)
                    if row.icon then row.icon:SetDesaturated(false) end
                end
            end
        end
        return
    end

    local matchedButtons = 0

    -- Filter Grid/Flow view buttons
    for _, btn in ipairs(itemButtons) do
        local itemInfo = btn.itemInfo
        local isMatch = MatchItemQuery(itemInfo, searchText)

        if Omni.ItemButton then
            Omni.ItemButton:SetSearchMatch(btn, isMatch)
        end
        if isMatch then
            matchedButtons = matchedButtons + 1
        end
    end

    -- Filter List view rows
    local matchedRows = 0
    for _, row in ipairs(listRows) do
        if row:IsShown() and row.itemInfo then
            local itemInfo = row.itemInfo
            local isMatch = MatchItemQuery(itemInfo, searchText)

            if isMatch then
                row:SetAlpha(1)
                if row.icon then row.icon:SetDesaturated(false) end
                matchedRows = matchedRows + 1
            else
                row:SetAlpha(0.3)
                if row.icon then row.icon:SetDesaturated(true) end
            end
        end
    end
    if Omni._perfEnabled and Omni.Perf then
        Omni.Perf:End("frame.ApplySearch", perfToken, {
            queryLen = string.len(searchText or ""),
            visibleButtons = #itemButtons,
            matchedButtons = matchedButtons,
            matchedRows = matchedRows,
        })
    end
end

-- =============================================================================
-- Footer Updates
-- =============================================================================

-- Footer emphasis: money + slot count fonts; slot fill color is driven in UpdateSlotCount
function Frame:RefreshFooterMoneyStyle()
    if not mainFrame or not mainFrame.footer then return end
    local footer = mainFrame.footer
    if not footer.money or not footer.slots then return end

    local emphasize = Omni.Data and Omni.Data:Get("footerMoneyEmphasis") == true
    local path, size = GameFontNormal:GetFont()
    size = (size or 12) + 2
    if emphasize then
        footer.money:SetFont(path, size, "OUTLINE")
        footer.slots:SetFont(path, size, "OUTLINE")
        if footer.bagFullAlert and footer.bagFullAlert.label then
            footer.bagFullAlert.label:SetFont(path, size + 2, "OUTLINE")
        end
    else
        footer.money:SetFontObject(GameFontNormalSmall)
        footer.slots:SetFontObject(GameFontNormalSmall)
        if footer.bagFullAlert and footer.bagFullAlert.label then
            local ap, as = GameFontNormal:GetFont()
            footer.bagFullAlert.label:SetFont(ap, (as or 12) + 2, "OUTLINE")
        end
    end
    SyncBagFullAlertHitBox(footer)
    if self.UpdateFooterCustomButtons then
        self:UpdateFooterCustomButtons()
    end
    self:UpdateSlotCount()
end

function Frame:UpdateSlotCount()
    if not mainFrame or not mainFrame.footer then return end

    local free, total = 0, 0
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        local numFree = GetContainerNumFreeSlots(bagID) or 0
        total = total + numSlots
        free = free + numFree
    end

    local used = total - free
    local footer = mainFrame.footer
    local slots = footer.slots
    slots:SetText(string.format("%d/%d", used, total))

    local bagsFull = total > 0 and free == 0
    local alert = footer.bagFullAlert
    if alert then
        if bagsFull then
            alert:Show()
            SyncBagFullAlertHitBox(footer)
            slots:ClearAllPoints()
            slots:SetPoint("LEFT", alert, "RIGHT", 1, 0)
        else
            alert:Hide()
            slots:ClearAllPoints()
            slots:SetPoint("LEFT", footer, "LEFT", 6, 0)
        end
    end

    local emphasize = Omni.Data and Omni.Data:Get("footerMoneyEmphasis") == true
    if emphasize then
        local t = 0
        if total > 0 then
            t = used / total
        end
        local br, bg, bb = 0.55, 0.80, 1.00
        local rr, rg, rb = 1.00, 0.15, 0.15
        slots:SetTextColor(br + (rr - br) * t, bg + (rg - bg) * t, bb + (rb - bb) * t, 1)
    else
        slots:SetTextColor(1, 1, 1, 1)
    end


    if self.UpdateFooterCustomButtons then
        self:UpdateFooterCustomButtons()
    end
end

function Frame:UpdateMoney()
    if not mainFrame or not mainFrame.footer then return end

    local money = 0
    local viewedChar = Omni.Data and Omni.Data.currentViewedChar
    if viewedChar and viewedChar ~= Omni.Data.playerName then
        local realm = OmniInventoryDB.realm[Omni.Data.realmName]
        local charData = realm and realm[viewedChar]
        money = charData and charData.gold or 0
    else
        money = GetMoney() or 0
    end

    local footer = mainFrame.footer
    local useIcons = Omni.Data and Omni.Data:Get("footerMoneyIcons") == true

    local text
    if Omni.Utils and Omni.Utils.FormatMoney then
        text = Omni.Utils:FormatMoney(money)
    else
        local gold = math.floor(money / 10000)
        local silver = math.floor((money % 10000) / 100)
        local copper = money % 100
        text = string.format("%dg %ds %dc", gold, silver, copper)
    end

    if useIcons and footer.moneyIcons then
        footer.money:Hide()
        footer.moneyIcons:Show()
        local gold = math.floor(money / 10000)
        local silver = math.floor((money % 10000) / 100)
        local copper = money % 100
        LayoutMoneyIcons(footer, gold, silver, copper)
    else
        if footer.moneyIcons then footer.moneyIcons:Hide() end
        footer.money:Show()
        footer.money:SetText(text)
    end

    if footer.moneyHitBox then
        footer.moneyHitBox._moneyText = text
        SyncFooterMoneyHitBox(footer)
    end
end

-- =============================================================================
-- Show/Hide/Toggle
-- =============================================================================

function Frame:Show()
    if not mainFrame then
        local _, err = pcall(function()
            currentView = GetSavedViewMode()
            selectedBagID = GetSavedBagFilter()
            self:CreateMainFrame()
            self:SetView(currentView)
            self:LoadPosition()
        end)
        if Omni and Omni._toggleStats then
            Omni._toggleStats.lastShowErr = err
        end
    end

    if not mainFrame then return end

    -- pcall the actual Show so combat taint / engine block ("Interface
    -- action failed because of an AddOn") never tears down the binding
    -- handler. The .pcall returns ok=true on success so we record it
    -- for /oi debug. The frame being shown is non-protected, so this
    -- should always succeed -- if it doesn't, we want to know.
    local okShow, errShow = pcall(mainFrame.Show, mainFrame)
    if Omni and Omni._toggleStats then
        Omni._toggleStats.showCalls = (Omni._toggleStats.showCalls or 0) + 1
        if okShow then
            Omni._toggleStats.showOK = (Omni._toggleStats.showOK or 0) + 1
        end
        if errShow then
            Omni._toggleStats.lastShowErr = tostring(errShow)
        end
    end

    pcall(function()
        local sig = ComputeShowSignature()
        local viewAllowsFastShow = (currentView == "grid" or currentView == "bag")
        local canFastShow = hasRenderedOnce
            and not pendingCombatRender
            and lastRenderedShowSignature ~= nil
            and sig == lastRenderedShowSignature
            and viewAllowsFastShow

        if canFastShow then
            self:UpdateBagIconTextures()
            self:UpdateBagIconVisuals()
            self:UpdateSlotCount()
            self:UpdateMoney()
            self:RefreshCombatContent({ _trigger = true })
            if searchText and searchText ~= "" then
                self:ApplySearch(searchText)
            end
        else
            self:UpdateLayout(nil, { reason = "show_open" })
        end
    end)
end

function Frame:Hide()
    if not mainFrame then return end

    local okHide, errHide = pcall(mainFrame.Hide, mainFrame)
    if Omni and Omni._toggleStats then
        Omni._toggleStats.hideCalls = (Omni._toggleStats.hideCalls or 0) + 1
        if okHide then
            Omni._toggleStats.hideOK = (Omni._toggleStats.hideOK or 0) + 1
        end
        if errHide then
            Omni._toggleStats.lastHideErr = tostring(errHide)
        end
    end

    pcall(function()
        vendorFlowLayoutFreeze = nil
        wasMerchantOpen = false
        ClearMap(optimisticFlowRefreshWatches)
        ClearArray(itemButtons)

        if Omni.NewItems then
            wipe(Omni.NewItems)
        end

        for _, byBag in pairs(slotButtons) do
            for _, btn in pairs(byBag) do
                if btn then
                    btn._cachedSearchName = nil
                    btn._cachedSearchNameLower = nil
                    if btn.newGlow then
                        if btn.newGlow.pulse then
                            btn.newGlow.pulse:Stop()
                        end
                        btn.newGlow:Hide()
                    end
                end
            end
        end

        if not InCombat()
                and OmniInventoryDB and OmniInventoryDB.global
                and OmniInventoryDB.global.autoSortOnClose then
            Frame:PhysicalSortBags()
        end

        -- Auto-tidy on close (AdiBags TidyBags).
        if not InCombat() and Omni.Features and Omni.Features.ShouldAutoTidyOnClose
                and Omni.Features:ShouldAutoTidyOnClose() then
            Omni.Features:RunTidy()
        end
    end)
end

function Frame:IsShown()
    return mainFrame and mainFrame:IsShown() or false
end

function Frame:Toggle()
    if self:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function Frame:PhysicalSortBags()
    -- Use the multi-phase PhysicalSort engine (A14) when available;
    -- fall back to Blizzard's native SortBags for compatibility.
    if Omni.PhysicalSort and Omni.PhysicalSort.Sort then
        Omni.PhysicalSort:Sort({ consolidateStacks = true, routeSpecialized = true })
    elseif SortBags then
        SortBags()
    end
end

function Frame:SetBagFilter(bagID)
    if bagID ~= nil and not IsValidBagID(bagID) then return end

    selectedBagID = bagID

    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.char = OmniInventoryDB.char or {}
    OmniInventoryDB.char.settings = OmniInventoryDB.char.settings or {}
    OmniInventoryDB.char.settings.selectedBagID = selectedBagID

    self:UpdateBagIconVisuals()
    self:UpdateLayout()
end

function Frame:ToggleBagPreview(bagID)
    if not IsValidBagID(bagID) then return end

    local clickedActive = (selectedBagID == bagID)

    if clickedActive then
        -- Unselect: restore the prior view only if we remembered one.
        -- If the user chose bag view themselves (via the View button),
        -- leave them in bag view on unselect instead of forcing flow.
        self:SetBagFilter(nil)
        if currentView == "bag" and preBagViewMode then
            local restoreTo = preBagViewMode
            preBagViewMode = nil
            self:SetView(restoreTo)
        end
    else
        -- Select: capture the non-bag view once, then switch to bag view
        if currentView ~= "bag" then
            preBagViewMode = currentView
            self:SetView("bag")
        end
        self:SetBagFilter(bagID)
    end
end

-- Inner scope: Lua chunk limit is 200 locals
do
    local function canBagAcceptItem(bagID, itemFamily)
        local _, bagFamily = GetContainerNumFreeSlots(bagID)
        bagFamily = bagFamily or 0

        if bagFamily == 0 then
            return true
        end
        if not itemFamily or itemFamily == 0 then
            return false
        end
        if bit and bit.band then
            return bit.band(itemFamily, bagFamily) > 0
        end
        return true
    end

    local function findFirstOpenSlotExcludingBag(excludedBagID, itemFamily)
        for _, bagID in ipairs(DIM.BAG_IDS) do
            if bagID ~= excludedBagID and canBagAcceptItem(bagID, itemFamily) then
                local slots = GetContainerNumSlots(bagID) or 0
                for slotID = 1, slots do
                    local texture = GetContainerItemInfo(bagID, slotID)
                    if not texture then
                        return bagID, slotID
                    end
                end
            end
        end
        return nil, nil
    end

    local function findFirstOpenSlotExcludingSwap(excludedBagID, newBagBagID, newBagSlotID, itemFamily)
        for _, bagID in ipairs(DIM.BAG_IDS) do
            if bagID ~= excludedBagID and canBagAcceptItem(bagID, itemFamily) then
                local slots = GetContainerNumSlots(bagID) or 0
                for slotID = 1, slots do
                    if not (bagID == newBagBagID and slotID == newBagSlotID) then
                        local texture = GetContainerItemInfo(bagID, slotID)
                        if not texture then
                            return bagID, slotID
                        end
                    end
                end
            end
        end
        return nil, nil
    end

    local function CountFreeSlotsExcluding(excludedBagID, newBagBagID, newBagSlotID)
        local count = 0
        for _, bagID in ipairs(DIM.BAG_IDS) do
            if bagID ~= excludedBagID then
                local slots = GetContainerNumSlots(bagID) or 0
                for slotID = 1, slots do
                    if not (bagID == newBagBagID and slotID == newBagSlotID) then
                        local texture = GetContainerItemInfo(bagID, slotID)
                        if not texture then
                            count = count + 1
                        end
                    end
                end
            end
        end
        return count
    end

    local function FindLockedSwappingBags()
        local sourceBagID, sourceSlotID, targetBagID
        local bankBagIDs = { 5, 6, 7, 8, 9, 10, 11 }

        -- 1. Scan player bag slots to find locked equipped bag slot
        for _, bagID in ipairs(DIM.BAG_IDS) do
            if bagID > 0 then
                local invID = ContainerIDToInventoryID(bagID)
                if invID and IsInventoryItemLocked(invID) then
                    targetBagID = bagID
                    break
                end
            end
        end

        -- If bank is open, check bank bag slots too
        if not targetBagID and _G.BankFrame and _G.BankFrame:IsShown() then
            for _, bagID in ipairs(bankBagIDs) do
                local invID = ContainerIDToInventoryID(bagID)
                if invID and IsInventoryItemLocked(invID) then
                    targetBagID = bagID
                    break
                end
            end
        end

        if not targetBagID then return nil end

        -- 2. Scan all bags to find the locked container item (the new bag)
        for _, bagID in ipairs(DIM.BAG_IDS) do
            local slots = GetContainerNumSlots(bagID) or 0
            for slotID = 1, slots do
                local _, _, isLocked = GetContainerItemInfo(bagID, slotID)
                if isLocked then
                    local link = GetContainerItemLink(bagID, slotID)
                    local itemEquipLoc
                    if link then
                        local _, _, _, _, _, _, _, _, eqLoc = GetItemInfo(link)
                        itemEquipLoc = eqLoc
                    end
                    if itemEquipLoc == "INVTYPE_BAG" then
                        sourceBagID = bagID
                        sourceSlotID = slotID
                        break
                    end
                end
            end
            if sourceBagID then break end
        end

        -- Check bank bags too if bank is open
        if not sourceBagID and _G.BankFrame and _G.BankFrame:IsShown() then
            for _, bagID in ipairs(bankBagIDs) do
                local slots = GetContainerNumSlots(bagID) or 0
                for slotID = 1, slots do
                    local _, _, isLocked = GetContainerItemInfo(bagID, slotID)
                    if isLocked then
                        local link = GetContainerItemLink(bagID, slotID)
                        local itemEquipLoc
                        if link then
                            local _, _, _, _, _, _, _, _, eqLoc = GetItemInfo(link)
                            itemEquipLoc = eqLoc
                        end
                        if itemEquipLoc == "INVTYPE_BAG" then
                            sourceBagID = bagID
                            sourceSlotID = slotID
                            break
                        end
                    end
                end
                if sourceBagID then break end
            end
        end

        if sourceBagID and sourceSlotID and targetBagID then
            return sourceBagID, sourceSlotID, targetBagID
        end
        return nil
    end

    Frame.FindLockedSwappingBags = FindLockedSwappingBags

    local function stopForceEmptyJob()
        if forceEmptyFrame then
            forceEmptyFrame:SetScript("OnUpdate", nil)
            forceEmptyFrame:SetScript("OnEvent", nil)
            forceEmptyFrame:UnregisterEvent("BAG_UPDATE")
            forceEmptyFrame:UnregisterEvent("ITEM_LOCK_CHANGED")
        end
        forceEmptyJob = nil
    end

    local function finishForceEmptyJob()
        if not forceEmptyJob then
            return
        end

        if forceEmptyJob.type == "empty" then
            print(string.format("|cFF00FF00OmniInventory|r: Force-empty bag %d moved %d, blocked %d.",
                forceEmptyJob.sourceBagID, forceEmptyJob.movedCount, forceEmptyJob.blockedCount))
        end

        stopForceEmptyJob()
        if Frame and Frame.UpdateLayout then
            Frame:UpdateLayout()
        end
    end

    local function runForceEmptyStep()
        if not forceEmptyJob then
            return
        end

        if forceEmptyJob.type == "empty" then
            if #forceEmptyJob.slots == 0 then
                finishForceEmptyJob()
                return
            end

            local sourceBagID = forceEmptyJob.sourceBagID
            local slotEntry = table.remove(forceEmptyJob.slots, 1)
            local slotID = slotEntry.slotID
            local attempts = slotEntry.attempts or 0

            local texture, _, isLocked = GetContainerItemInfo(sourceBagID, slotID)
            if not texture then
                runForceEmptyStep()
                return
            end
            if isLocked then
                attempts = attempts + 1
                if attempts >= DIM.FORCE_EMPTY_MAX_LOCK_RETRIES then
                    forceEmptyJob.blockedCount = forceEmptyJob.blockedCount + 1
                    runForceEmptyStep()
                else
                    slotEntry.attempts = attempts
                    table.insert(forceEmptyJob.slots, slotEntry)
                end
                return
            end

            local itemLink = GetContainerItemLink(sourceBagID, slotID)
            local itemFamily = (itemLink and GetItemFamily(itemLink)) or 0
            local targetBagID, targetSlotID = findFirstOpenSlotExcludingBag(sourceBagID, itemFamily)
            if not targetBagID or not targetSlotID then
                forceEmptyJob.blockedCount = forceEmptyJob.blockedCount + 1
                runForceEmptyStep()
                return
            end

            PickupContainerItem(sourceBagID, slotID)
            if CursorHasItem and CursorHasItem() then
                PickupContainerItem(targetBagID, targetSlotID)
            end

            if CursorHasItem and CursorHasItem() then
                ClearCursor()
                attempts = attempts + 1
                if attempts >= DIM.FORCE_EMPTY_MAX_MOVE_RETRIES then
                    forceEmptyJob.blockedCount = forceEmptyJob.blockedCount + 1
                    runForceEmptyStep()
                else
                    slotEntry.attempts = attempts
                    table.insert(forceEmptyJob.slots, slotEntry)
                end
            else
                forceEmptyJob.movedCount = forceEmptyJob.movedCount + 1
                forceEmptyJob.awaitingEvent = true
                forceEmptyJob.awaitElapsed = 0
            end

        elseif forceEmptyJob.type == "swap" then
            if forceEmptyJob.phase == 1 then
                -- Phase 1: Empty targetBagID
                if #forceEmptyJob.slots > 0 then
                    local sourceBagID = forceEmptyJob.targetBagID
                    local slotEntry = table.remove(forceEmptyJob.slots, 1)
                    local slotID = slotEntry.slotID
                    local attempts = slotEntry.attempts or 0

                    local texture, _, isLocked = GetContainerItemInfo(sourceBagID, slotID)
                    if not texture then
                        runForceEmptyStep()
                        return
                    end
                    if isLocked then
                        attempts = attempts + 1
                        if attempts >= DIM.FORCE_EMPTY_MAX_LOCK_RETRIES then
                            forceEmptyJob.blockedCount = forceEmptyJob.blockedCount + 1
                            runForceEmptyStep()
                        else
                            slotEntry.attempts = attempts
                            table.insert(forceEmptyJob.slots, slotEntry)
                        end
                        return
                    end

                    local itemLink = GetContainerItemLink(sourceBagID, slotID)
                    local itemFamily = (itemLink and GetItemFamily(itemLink)) or 0
                    local targetBagID, targetSlotID = findFirstOpenSlotExcludingSwap(forceEmptyJob.targetBagID, forceEmptyJob.sourceBagID, forceEmptyJob.sourceSlotID, itemFamily)
                    if not targetBagID or not targetSlotID then
                        print("|cFF00FF00OmniInventory|r: Aborting swap - out of free space.")
                        stopForceEmptyJob()
                        return
                    end

                    PickupContainerItem(sourceBagID, slotID)
                    if CursorHasItem and CursorHasItem() then
                        PickupContainerItem(targetBagID, targetSlotID)
                    end

                    if CursorHasItem and CursorHasItem() then
                        ClearCursor()
                        attempts = attempts + 1
                        if attempts >= DIM.FORCE_EMPTY_MAX_MOVE_RETRIES then
                            forceEmptyJob.blockedCount = forceEmptyJob.blockedCount + 1
                            runForceEmptyStep()
                        else
                            slotEntry.attempts = attempts
                            table.insert(forceEmptyJob.slots, slotEntry)
                        end
                    else
                        forceEmptyJob.movedCount = forceEmptyJob.movedCount + 1
                        forceEmptyJob.awaitingEvent = true
                        forceEmptyJob.awaitElapsed = 0
                        table.insert(forceEmptyJob.shuffledItems, {
                            originalSlotID = slotID,
                            tempBagID = targetBagID,
                            tempSlotID = targetSlotID,
                        })
                    end
                else
                    forceEmptyJob.phase = 2
                    forceEmptyJob.awaitingEvent = true
                    forceEmptyJob.awaitElapsed = 0
                end

            elseif forceEmptyJob.phase == 2 then
                -- Phase 2: Equip the new bag
                local texture, _, isLocked = GetContainerItemInfo(forceEmptyJob.sourceBagID, forceEmptyJob.sourceSlotID)
                if isLocked then
                    return
                end

                PickupContainerItem(forceEmptyJob.sourceBagID, forceEmptyJob.sourceSlotID)
                if CursorHasItem and CursorHasItem() then
                    local invSlot = ContainerIDToInventoryID(forceEmptyJob.targetBagID)
                    if invSlot then
                        PutItemInBag(invSlot)
                    end
                end

                forceEmptyJob.phase = 3
                forceEmptyJob.awaitingEvent = true
                forceEmptyJob.awaitElapsed = 0

            elseif forceEmptyJob.phase == 3 then
                -- Phase 3: Store the old bag (now empty and on the cursor)
                if CursorHasItem and CursorHasItem() then
                    PickupContainerItem(forceEmptyJob.sourceBagID, forceEmptyJob.sourceSlotID)
                end

                if CursorHasItem and CursorHasItem() then
                    local tempBag, tempSlot = findFirstOpenSlotExcludingSwap(forceEmptyJob.targetBagID, nil, nil, 0)
                    if tempBag and tempSlot then
                        PickupContainerItem(tempBag, tempSlot)
                    end
                end

                if CursorHasItem and CursorHasItem() then
                    ClearCursor()
                end

                forceEmptyJob.phase = 4
                forceEmptyJob.slots = {}
                for _, info in ipairs(forceEmptyJob.shuffledItems) do
                    table.insert(forceEmptyJob.slots, {
                        slotID = info.originalSlotID,
                        tempBagID = info.tempBagID,
                        tempSlotID = info.tempSlotID,
                        attempts = 0,
                    })
                end
                forceEmptyJob.awaitingEvent = true
                forceEmptyJob.awaitElapsed = 0

            elseif forceEmptyJob.phase == 4 then
                -- Phase 4: Refill items
                if #forceEmptyJob.slots > 0 then
                    local entry = table.remove(forceEmptyJob.slots, 1)
                    local targetSlotID = entry.slotID
                    local tempBagID = entry.tempBagID
                    local tempSlotID = entry.tempSlotID
                    local attempts = entry.attempts or 0

                    local texture, _, isLocked = GetContainerItemInfo(tempBagID, tempSlotID)
                    if not texture then
                        runForceEmptyStep()
                        return
                    end
                    if isLocked then
                        attempts = attempts + 1
                        if attempts >= DIM.FORCE_EMPTY_MAX_LOCK_RETRIES then
                            forceEmptyJob.blockedCount = forceEmptyJob.blockedCount + 1
                            runForceEmptyStep()
                        else
                            entry.attempts = attempts
                            table.insert(forceEmptyJob.slots, entry)
                        end
                        return
                    end

                    PickupContainerItem(tempBagID, tempSlotID)
                    if CursorHasItem and CursorHasItem() then
                        PickupContainerItem(forceEmptyJob.targetBagID, targetSlotID)
                    end

                    if CursorHasItem and CursorHasItem() then
                        ClearCursor()
                        attempts = attempts + 1
                        if attempts >= DIM.FORCE_EMPTY_MAX_MOVE_RETRIES then
                            forceEmptyJob.blockedCount = forceEmptyJob.blockedCount + 1
                            runForceEmptyStep()
                        else
                            entry.attempts = attempts
                            table.insert(forceEmptyJob.slots, entry)
                        end
                    else
                        forceEmptyJob.movedCount = forceEmptyJob.movedCount + 1
                        forceEmptyJob.awaitingEvent = true
                        forceEmptyJob.awaitElapsed = 0
                    end
                else
                    print(string.format("|cFF00FF00OmniInventory|r: Successfully swapped bag %d.", forceEmptyJob.targetBagID))
                    stopForceEmptyJob()
                    if Frame and Frame.UpdateLayout then
                        Frame:UpdateLayout()
                    end
                end
            end
        end
    end

    local function ensureForceEmptyFrame()
        if forceEmptyFrame then return end
        forceEmptyFrame = CreateFrame("Frame")
        forceEmptyFrame:RegisterEvent("BAG_UPDATE")
        forceEmptyFrame:RegisterEvent("ITEM_LOCK_CHANGED")
        forceEmptyFrame:SetScript("OnEvent", function(_, event, arg1)
            if not forceEmptyJob then return end
            if event == "BAG_UPDATE" and arg1 ~= nil then
                if forceEmptyJob.type == "empty" and arg1 ~= forceEmptyJob.sourceBagID then
                    forceEmptyJob.awaitingEvent = false
                elseif forceEmptyJob.type == "swap" then
                    forceEmptyJob.awaitingEvent = false
                end
                return
            end
            forceEmptyJob.awaitingEvent = false
        end)
        forceEmptyFrame:SetScript("OnUpdate", function(_, elapsed)
            if not forceEmptyJob then return end
            if forceEmptyJob.awaitingEvent then
                forceEmptyJob.awaitElapsed = forceEmptyJob.awaitElapsed + (elapsed or 0)
                if forceEmptyJob.awaitElapsed < DIM.FORCE_EMPTY_EVENT_TIMEOUT then
                    return
                end
                forceEmptyJob.awaitingEvent = false
            end
            if CursorHasItem and CursorHasItem() then
                if forceEmptyJob.type == "empty" or (forceEmptyJob.type == "swap" and forceEmptyJob.phase ~= 2 and forceEmptyJob.phase ~= 3) then
                    return
                end
            end
            if InCombat() then
                stopForceEmptyJob()
                return
            end
            runForceEmptyStep()
        end)
    end

function Frame:ForceEmptyBag(sourceBagID)
    if not IsValidBagID(sourceBagID) then return end

    if CursorHasItem and CursorHasItem() then
        print("|cFF00FF00OmniInventory|r: Clear cursor item before force-empty.")
        return
    end

    local sourceSlots = GetContainerNumSlots(sourceBagID) or 0
    if sourceSlots <= 0 then
        print("|cFF00FF00OmniInventory|r: That bag has no slots.")
        return
    end

    local slots = {}
    for slotID = 1, sourceSlots do
        local texture = GetContainerItemInfo(sourceBagID, slotID)
        if texture then
            table.insert(slots, { slotID = slotID, attempts = 0 })
        end
    end

    if #slots == 0 then
        print("|cFF00FF00OmniInventory|r: Bag is already empty.")
        return
    end

    if forceEmptyJob then
        stopForceEmptyJob()
    end

    forceEmptyJob = {
        type = "empty",
        sourceBagID = sourceBagID,
        slots = slots,
        movedCount = 0,
        blockedCount = 0,
        awaitingEvent = false,
        awaitElapsed = 0,
    }

    ensureForceEmptyFrame()
end

function Frame:StartBagSwap(sourceBagID, sourceSlotID, targetBagID)
    if not IsValidBagID(targetBagID) or not IsValidBagID(sourceBagID) then return end
    if targetBagID == 0 then return end -- Backpack cannot be swapped

    if InCombat() then
        print("|cFF00FF00OmniInventory|r: Cannot swap bags during combat.")
        return
    end

    local filledCount = 0
    local targetSlots = GetContainerNumSlots(targetBagID) or 0
    local slotsToEmpty = {}
    for slotID = 1, targetSlots do
        local texture = GetContainerItemInfo(targetBagID, slotID)
        if texture then
            filledCount = filledCount + 1
            table.insert(slotsToEmpty, { slotID = slotID, attempts = 0 })
        end
    end

    if filledCount == 0 then
        ClearCursor()
        PickupContainerItem(sourceBagID, sourceSlotID)
        if CursorHasItem() then
            local invSlot = ContainerIDToInventoryID(targetBagID)
            PutItemInBag(invSlot)
        end
        if CursorHasItem() then
            PickupContainerItem(sourceBagID, sourceSlotID)
        end
        if CursorHasItem() then ClearCursor() end
        print(string.format("|cFF00FF00OmniInventory|r: Successfully swapped empty bag slot %d.", targetBagID))
        if Frame and Frame.UpdateLayout then
            Frame:UpdateLayout()
        end
        return
    end

    local freeSlots = CountFreeSlotsExcluding(targetBagID, sourceBagID, sourceSlotID)
    if freeSlots < filledCount then
        print(string.format("|cFF00FF00OmniInventory|r: Not enough free slots to swap this bag. Need %d slots, have %d.", filledCount, freeSlots))
        return
    end

    if forceEmptyJob then
        stopForceEmptyJob()
    end

    forceEmptyJob = {
        type = "swap",
        phase = 1,
        targetBagID = targetBagID,
        sourceBagID = sourceBagID,
        sourceSlotID = sourceSlotID,
        slots = slotsToEmpty,
        movedCount = 0,
        blockedCount = 0,
        awaitingEvent = false,
        awaitElapsed = 0,
        shuffledItems = {},
    }

    ensureForceEmptyFrame()
    print(string.format("|cFF00FF00OmniInventory|r: Swapping bag %d (moving %d items)...", targetBagID, filledCount))
end

end -- force-empty inner scope

-- =============================================================================
-- Initialization
-- =============================================================================

function Frame:SetMerchantOpen(isOpen)
    Omni._merchantOpen = (isOpen == true)
end

function Frame:Init()
    Omni._merchantOpen = false
    currentView = GetSavedViewMode()
    selectedBagID = GetSavedBagFilter()

    self:CreateMainFrame()
    self:LoadPosition()

    if not InCombat() and Omni.Pool and Omni.Pool.Prewarm then
        Omni.Pool:Prewarm("ItemButton", 160)
    end

    -- Park every prewarmed button on the limbo parent OOC so the
    -- first OOC render can freely SetParent them onto the right bag's
    -- ItemContainer. SetParent on a ContainerFrameItemButton is still
    -- protected, so all of this MUST happen out of combat.
    if not InCombat() then
        local pool = Omni.Pool and Omni.Pool:Get("ItemButton")
        local available = pool and pool.available
        if available then
            for _, btn in ipairs(available) do
                pcall(btn.ClearAllPoints, btn)
                pcall(btn.Hide, btn)
            end
        end
    end

    -- Eagerly populate the hidden layout so a first open
    -- mid-combat already has bag-slot buttons parked and click-routable.
    -- If login itself is combat-locked, UpdateLayout will attempt the
    -- lightweight grid bootstrap instead of the normal sorted flow pass.
    self:_RefreshViewButtonLabel()
    self:UpdateResortButtonVisibility()
    self:ApplyTheme()
    pcall(function()
        Frame:UpdateLayout(nil, { forceFull = true, reason = "init_prewarm", immediate = true })
    end)

    local errorFrame = CreateFrame("Frame")
    errorFrame:RegisterEvent("UI_ERROR_MESSAGE")
    errorFrame:SetScript("OnEvent", function(_, event, msg)
        if msg == ERR_DESTROY_NONEMPTY_BAG then
            if Frame.FindLockedSwappingBags then
                local sourceBagID, sourceSlotID, targetBagID = Frame.FindLockedSwappingBags()
                if sourceBagID and sourceSlotID and targetBagID then
                    if type(targetBagID) == "number" and targetBagID >= 1 and targetBagID <= 4 then
                        Frame:StartBagSwap(sourceBagID, sourceSlotID, targetBagID)
                    elseif type(targetBagID) == "number" and targetBagID >= 5 and targetBagID <= 11 then
                        if BankFrame and BankFrame.StartBankBagSwap then
                            BankFrame:StartBankBagSwap(sourceBagID, sourceSlotID, targetBagID)
                        end
                    end
                end
            end
        end
    end)
end

function Frame:OpenCategoryEditDialog(catName)
    if not catName or catName == "BoE" or string.match(catName, "^Free Space") or catName == "Free Space" then
        return
    end

    if not self.categoryEditDialog then
        local dialog = CreateFrame("Frame", "OmniCategoryEditDialog", mainFrame)
        dialog:SetFrameStrata("DIALOG")
        dialog:SetFrameLevel(mainFrame:GetFrameLevel() + 15)
        dialog:SetSize(280, 260)
        dialog:SetPoint("CENTER", mainFrame, "CENTER", 0, 20)
        dialog:EnableMouse(true)
        dialog:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        dialog:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
        dialog:SetBackdropBorderColor(0.45, 0.38, 0.15, 1)

        -- Close button
        dialog.closeBtn = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
        dialog.closeBtn:SetSize(18, 18)
        dialog.closeBtn:SetPoint("TOPRIGHT", -4, -4)
        dialog.closeBtn:SetScript("OnClick", function() dialog:Hide() end)

        -- Title
        dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.title:SetPoint("TOPLEFT", 12, -12)
        dialog.title:SetText("Edit Category")

        -- Name EditBox
        dialog.nameLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dialog.nameLabel:SetPoint("TOPLEFT", 12, -35)
        dialog.nameLabel:SetText("Display Name:")

        dialog.nameBg = CreateFrame("Frame", nil, dialog)
        dialog.nameBg:SetPoint("TOPLEFT", 12, -50)
        dialog.nameBg:SetSize(256, 20)
        dialog.nameBg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        dialog.nameBg:SetBackdropColor(0.02, 0.02, 0.02, 0.8)
        dialog.nameBg:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

        dialog.nameBox = CreateFrame("EditBox", nil, dialog.nameBg)
        dialog.nameBox:SetAllPoints(dialog.nameBg)
        dialog.nameBox:SetFontObject(ChatFontNormal)
        dialog.nameBox:SetTextColor(1, 1, 1)
        dialog.nameBox:SetTextInsets(4, 4, 0, 0)
        dialog.nameBox:SetAutoFocus(false)
        dialog.nameBox:SetScript("OnEscapePressed", function() dialog:Hide() end)

        -- Priority Slider
        dialog.prioLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dialog.prioLabel:SetPoint("TOPLEFT", 12, -80)
        dialog.prioLabel:SetText("Priority (Sort Order): 50")

        dialog.prioSlider = CreateFrame("Slider", "OmniCategoryPrioSlider", dialog, "OptionsSliderTemplate")
        dialog.prioSlider:SetPoint("TOPLEFT", 12, -95)
        dialog.prioSlider:SetWidth(256)
        dialog.prioSlider:SetMinMaxValues(1, 99)
        dialog.prioSlider:SetValueStep(1)
        dialog.prioSlider:SetScript("OnValueChanged", function(self, val)
            dialog.prioLabel:SetText("Priority (Sort Order): " .. math.floor(val))
        end)
        _G[dialog.prioSlider:GetName() .. 'Text']:SetText("")
        _G[dialog.prioSlider:GetName() .. 'Low']:SetText("1 (High)")
        _G[dialog.prioSlider:GetName() .. 'High']:SetText("99 (Low)")

        -- Color Swatch
        dialog.colorLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dialog.colorLabel:SetPoint("TOPLEFT", 12, -125)
        dialog.colorLabel:SetText("Category Color:")

        dialog.swatch = dialog:CreateTexture(nil, "OVERLAY")
        dialog.swatch:SetSize(24, 24)
        dialog.swatch:SetPoint("TOPLEFT", 12, -140)
        dialog.swatch:SetTexture("Interface\\Buttons\\WHITE8X8")

        -- RGB Sliders
        local function UpdateSwatch()
            local r = dialog.rSlider:GetValue()
            local g = dialog.gSlider:GetValue()
            local b = dialog.bSlider:GetValue()
            dialog.swatch:SetVertexColor(r, g, b)
        end

        local function CreateRGBSlider(name, labelText, offset)
            local lbl = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("TOPLEFT", 48, offset)
            lbl:SetText(labelText)

            local s = CreateFrame("Slider", "OmniCategoryColor" .. name, dialog, "OptionsSliderTemplate")
            s:SetPoint("TOPLEFT", 100, offset + 4)
            s:SetWidth(168)
            s:SetMinMaxValues(0, 1)
            s:SetValueStep(0.01)
            s:SetScript("OnValueChanged", function()
                UpdateSwatch()
            end)
            _G[s:GetName() .. 'Text']:SetText("")
            _G[s:GetName() .. 'Low']:SetText("")
            _G[s:GetName() .. 'High']:SetText("")
            return s
        end

        dialog.rSlider = CreateRGBSlider("Red", "Red:", -130)
        dialog.gSlider = CreateRGBSlider("Green", "Green:", -150)
        dialog.bSlider = CreateRGBSlider("Blue", "Blue:", -170)

        -- Buttons: Save, Reset, Cancel
        dialog.saveBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        dialog.saveBtn:SetSize(70, 22)
        dialog.saveBtn:SetPoint("BOTTOMLEFT", 12, 12)
        dialog.saveBtn:SetText("Save")
        dialog.saveBtn:SetScript("OnClick", function()
            local currentCat = dialog.currentCatName
            local newName = dialog.nameBox:GetText() or ""
            newName = string.gsub(newName, "^%s*(.-)%s*$", "%1") -- trim

            if newName ~= "" and currentCat then
                OmniInventoryDB.global.categoryRenames = OmniInventoryDB.global.categoryRenames or {}
                OmniInventoryDB.global.categoryCustoms = OmniInventoryDB.global.categoryCustoms or {}

                local origName = Omni.Categorizer.GetOriginalCategoryName(currentCat)
                if newName ~= origName then
                    OmniInventoryDB.global.categoryRenames[origName] = newName
                else
                    OmniInventoryDB.global.categoryRenames[origName] = nil
                end

                local r = dialog.rSlider:GetValue()
                local g = dialog.gSlider:GetValue()
                local b = dialog.bSlider:GetValue()
                local p = math.floor(dialog.prioSlider:GetValue())

                OmniInventoryDB.global.categoryCustoms[newName] = {
                    priority = p,
                    color = { r = r, g = g, b = b },
                }

                -- Refresh layouts
                if Omni.Frame and Omni.Frame.UpdateLayout then
                    Omni.Frame:InvalidateRenderCaches()
                    Omni.Frame:UpdateLayout()
                end
                if Omni.BankFrame and Omni.BankFrame.UpdateLayout then
                    Omni.BankFrame:UpdateLayout()
                end
                if Omni.GuildBankFrame and Omni.GuildBankFrame.UpdateLayout then
                    Omni.GuildBankFrame:UpdateLayout()
                end
            end
            dialog:Hide()
        end)

        dialog.resetBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        dialog.resetBtn:SetSize(70, 22)
        dialog.resetBtn:SetPoint("BOTTOMLEFT", dialog.saveBtn, "BOTTOMRIGHT", 8, 0)
        dialog.resetBtn:SetText("Reset")
        dialog.resetBtn:SetScript("OnClick", function()
            local currentCat = dialog.currentCatName
            if currentCat then
                local origName = Omni.Categorizer.GetOriginalCategoryName(currentCat)
                if OmniInventoryDB and OmniInventoryDB.global then
                    if OmniInventoryDB.global.categoryRenames then
                        OmniInventoryDB.global.categoryRenames[origName] = nil
                    end
                    if OmniInventoryDB.global.categoryCustoms then
                        OmniInventoryDB.global.categoryCustoms[currentCat] = nil
                        OmniInventoryDB.global.categoryCustoms[origName] = nil
                    end
                end

                -- Refresh layouts
                if Omni.Frame and Omni.Frame.UpdateLayout then
                    Omni.Frame:InvalidateRenderCaches()
                    Omni.Frame:UpdateLayout()
                end
                if Omni.BankFrame and Omni.BankFrame.UpdateLayout then
                    Omni.BankFrame:UpdateLayout()
                end
                if Omni.GuildBankFrame and Omni.GuildBankFrame.UpdateLayout then
                    Omni.GuildBankFrame:UpdateLayout()
                end
            end
            dialog:Hide()
        end)

        dialog.cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        dialog.cancelBtn:SetSize(70, 22)
        dialog.cancelBtn:SetPoint("BOTTOMRIGHT", -12, 12)
        dialog.cancelBtn:SetText("Cancel")
        dialog.cancelBtn:SetScript("OnClick", function()
            dialog:Hide()
        end)

        self.categoryEditDialog = dialog
        tinsert(UISpecialFrames, "OmniCategoryEditDialog")
    end

    local dialog = self.categoryEditDialog
    dialog.currentCatName = catName

    -- Load current values
    local info = Omni.Categorizer:GetCategoryInfo(catName)
    dialog.title:SetText("Edit Category: |cffffd700" .. catName .. "|r")
    dialog.nameBox:SetText(catName)
    dialog.prioSlider:SetValue(info.priority or 50)
    dialog.rSlider:SetValue(info.color.r or 0.5)
    dialog.gSlider:SetValue(info.color.g or 0.5)
    dialog.bSlider:SetValue(info.color.b or 0.5)
    dialog.swatch:SetVertexColor(info.color.r or 0.5, info.color.g or 0.5, info.color.b or 0.5)

    dialog:Show()
end

Omni.Frame.OpenCategoryEditDialog = function(self, catName) Frame:OpenCategoryEditDialog(catName) end

function Frame:TransferCategoryItems(catName, toBank)
    if InCombatLockdown and InCombatLockdown() then return end
    if not catName or catName == "" then return end

    if toBank then
        for bagID = 0, 4 do
            local numSlots = GetContainerNumSlots(bagID) or 0
            for slotID = 1, numSlots do
                local info = OmniC_Container.GetContainerItemInfo(bagID, slotID)
                if info then
                    local category = Omni.Categorizer:GetCategory(info)
                    if category == catName then
                        UseContainerItem(bagID, slotID)
                    end
                end
            end
        end
        local keyringSlots = GetContainerNumSlots(-2) or 0
        for slotID = 1, keyringSlots do
            local info = OmniC_Container.GetContainerItemInfo(-2, slotID)
            if info then
                local category = Omni.Categorizer:GetCategory(info)
                if category == catName then
                    UseContainerItem(-2, slotID)
                end
            end
        end
    else
        local mainSlots = GetContainerNumSlots(-1) or 0
        for slotID = 1, mainSlots do
            local info = OmniC_Container.GetContainerItemInfo(-1, slotID)
            if info then
                local category = Omni.Categorizer:GetCategory(info)
                if category == catName then
                    UseContainerItem(-1, slotID)
                end
            end
        end
        for bagID = 5, 11 do
            local numSlots = GetContainerNumSlots(bagID) or 0
            for slotID = 1, numSlots do
                local info = OmniC_Container.GetContainerItemInfo(bagID, slotID)
                if info then
                    local category = Omni.Categorizer:GetCategory(info)
                    if category == catName then
                        UseContainerItem(bagID, slotID)
                    end
                end
            end
        end
    end
end

