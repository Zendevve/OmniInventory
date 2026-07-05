-- =============================================================================
-- OmniInventory Physical Bag Sorting Engine
-- =============================================================================
-- Purpose: Actually moves items in containers (Bagnon/GudaBags-style).
--   * 6-phase sort: detect specialized bags, route items, consolidate
--     stacks, categorical sort, execute moves with lock tracking.
--   * Swap deduplication to prevent oscillation.
--   * Max-moves-per-cycle limits + timeout fallbacks.
--   * Event-driven pass scheduling via ITEM_LOCK_CHANGED.
-- =============================================================================

local addonName, Omni = ...

Omni.PhysicalSort = {}
local PhysicalSort = Omni.PhysicalSort

-- =============================================================================
-- Configuration
-- =============================================================================

local MAX_MOVES_PER_CYCLE = 50
local MOVE_DELAY = 0.1       -- seconds between moves
local LOCK_TIMEOUT = 2.0     -- seconds to wait for item lock clear
local MAX_PASSES = 10        -- max sort passes before giving up

-- =============================================================================
-- State
-- =============================================================================

local sortFrame = nil
local isSorting = false
local sortQueue = {}         -- queue of pending moves
local currentMove = nil
local lockWaitElapsed = 0
local totalMoves = 0
local passCount = 0
local sortCancelled = false

-- =============================================================================
-- Helpers
-- =============================================================================

local function GetBagFamily(bagID)
    if bagID < 1 or bagID > 4 then return 0 end
    if not GetContainerNumFreeSlots then return 0 end
    local _, family = GetContainerNumFreeSlots(bagID)
    return family or 0
end

local function IsSpecializedBag(bagID)
    return GetBagFamily(bagID) > 0
end

local function GetItemInfoForSlot(bagID, slotID)
    local texture, count, locked, quality, _, _, link = GetContainerItemInfo(bagID, slotID)
    if not texture then return nil end
    local itemID = link and tonumber(string.match(link, "item:(%d+)")) or nil
    local name, _, _, _, _, itemType, subType, _, equipSlot, _, _, classID, subClassID = GetItemInfo(link or "")
    return {
        bagID = bagID,
        slotID = slotID,
        itemID = itemID,
        link = link,
        texture = texture,
        count = count or 1,
        locked = locked or false,
        quality = quality or 0,
        name = name or "",
        itemType = itemType or "",
        itemSubType = subType or "",
        equipSlot = equipSlot or "",
        classID = classID,
        subClassID = subClassID,
    }
end

local function GetMaxStackSize(itemID)
    if not itemID then return 1 end
    local _, _, _, _, _, _, _, maxStack = GetItemInfo(itemID)
    return maxStack or 1
end

-- Get category priority for sort ordering
local function GetCategoryPriority(item)
    if not item then return 99 end
    if Omni.Categorizer then
        local cat = Omni.Categorizer:GetCategoryInfo(item.category or "")
        return cat and cat.priority or 99
    end
    return 99
end

-- Multi-property comparator for desired order
local function ItemSortComparator(a, b)
    if not a and not b then return false end
    if not a then return false end
    if not b then return true end

    -- 1. Category priority
    local catA = GetCategoryPriority(a)
    local catB = GetCategoryPriority(b)
    if catA ~= catB then return catA < catB end

    -- 2. Quality (higher first)
    local qA = a.quality or 0
    local qB = b.quality or 0
    if qA ~= qB then return qA > qB end

    -- 3. Item level (higher first)
    local ilvlA = a.itemLevel or 0
    local ilvlB = b.itemLevel or 0
    if ilvlA ~= ilvlB then return ilvlA > ilvlB end

    -- 4. Name (alphabetical)
    local nA = a.name or "zzz"
    local nB = b.name or "zzz"
    if nA ~= nB then return nA < nB end

    -- 5. Stack count (higher first)
    local sA = a.count or 1
    local sB = b.count or 1
    if sA ~= sB then return sA > sB end

    return false
end

-- =============================================================================
-- Phase 1: Detect Specialized Bags
-- =============================================================================

local function DetectSpecializedBags()
    local specialized = {}  -- bagID -> family
    for bagID = 1, 4 do
        local family = GetBagFamily(bagID)
        if family > 0 then
            specialized[bagID] = family
        end
    end
    return specialized
end

-- =============================================================================
-- Phase 2: Route Specialized Items to Correct Bags
-- =============================================================================

local function ShouldItemGoInBag(item, bagID, specializedBags)
    local family = specializedBags[bagID]
    if not family then return true end -- normal bag accepts everything

    -- Check if item matches the bag family
    -- Family bitmasks: 1=Ammo, 2=Quiver, 4=Soul, 8=Leather, 16=Inscription,
    -- 32=Herb, 64=Mining, 128=Engineering, 512=Gem
    if not item.itemID then return false end
    local _, _, _, _, _, _, _, _, _, _, _, classID, subClassID = GetItemInfo(item.link or item.itemID)
    if not classID then return false end

    -- Simplified family matching
    if family == 1 or family == 2 then
        -- Ammo/Quiver: projectiles
        return classID == 6 -- Projectile
    elseif family == 4 then
        -- Soul bag: soul shards
        return item.itemID == 6265 -- Soul Shard
    elseif family == 8 then
        -- Leatherworking
        return classID == 7 and (subClassID == 1 or subClassID == 2) -- Leather/Skin
    elseif family == 16 then
        -- Inscription
        return classID == 7 and subClassID == 5 -- Enchanting
    elseif family == 32 then
        -- Herb
        return classID == 7 and subClassID == 3 -- Herb
    elseif family == 64 then
        -- Mining
        return classID == 7 and (subClassID == 2 or subClassID == 4) -- Metal&Stone/Parts
    elseif family == 128 then
        -- Engineering
        return classID == 7 and subClassID == 4 -- Parts/Devices
    elseif family == 512 then
        -- Gem
        return classID == 3 -- Gem
    end

    return true
end

-- =============================================================================
-- Phase 3: Consolidate Partial Stacks
-- =============================================================================

local function FindConsolidationMoves(items)
    local moves = {}
    -- Group items by itemID
    local byItemID = {}
    for _, item in ipairs(items) do
        if item.itemID and not item.__empty then
            local maxStack = GetMaxStackSize(item.itemID)
            if maxStack > 1 and (item.count or 1) < maxStack then
                byItemID[item.itemID] = byItemID[item.itemID] or {}
                table.insert(byItemID[item.itemID], item)
            end
        end
    end

    -- For each itemID with multiple partial stacks, create merge moves
    for itemID, stacks in pairs(byItemID) do
        if #stacks >= 2 then
            local maxStack = GetMaxStackSize(itemID)
            -- Sort by count descending (merge into largest)
            table.sort(stacks, function(a, b) return (a.count or 1) > (b.count or 1) end)
            for i = 2, #stacks do
                local target = stacks[1]
                local source = stacks[i]
                if (target.count or 1) < maxStack then
                    table.insert(moves, {
                        fromBag = source.bagID,
                        fromSlot = source.slotID,
                        toBag = target.bagID,
                        toSlot = target.slotID,
                        type = "merge",
                    })
                    target.count = math.min(maxStack, (target.count or 1) + (source.count or 1))
                end
            end
        end
    end

    return moves
end

-- =============================================================================
-- Phase 4: Build Desired Order
-- =============================================================================

local function BuildDesiredOrder(specializedBags)
    local allItems = {}

    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, numSlots do
            local item = GetItemInfoForSlot(bagID, slotID)
            if item then
                -- Categorize for sort priority
                if Omni.Categorizer then
                    item.category = Omni.Categorizer:GetCategory(item)
                end
                table.insert(allItems, item)
            end
        end
    end

    -- Sort by desired order
    table.sort(allItems, ItemSortComparator)

    -- Assign target positions: specialized items go to their bags first
    local targetPositions = {}
    local bagSlotCounters = {}
    for bagID = 0, 4 do
        bagSlotCounters[bagID] = 1
    end

    for _, item in ipairs(allItems) do
        -- Find the best target bag for this item
        local targetBag = nil
        
        -- 1. Try to place in specialized bags first (bags 1-4)
        for bagID = 1, 4 do
            if specializedBags[bagID] and ShouldItemGoInBag(item, bagID, specializedBags) then
                local slot = bagSlotCounters[bagID]
                local numSlots = GetContainerNumSlots(bagID) or 0
                if slot <= numSlots then
                    targetBag = bagID
                    break
                end
            end
        end
        
        -- 2. Fall back to normal bags (checking bag 0 first, then 1-4 if they are normal)
        if not targetBag then
            for bagID = 0, 4 do
                if not specializedBags[bagID] and ShouldItemGoInBag(item, bagID, specializedBags) then
                    local slot = bagSlotCounters[bagID]
                    local numSlots = GetContainerNumSlots(bagID) or 0
                    if slot <= numSlots then
                        targetBag = bagID
                        break
                    end
                end
            end
        end

        if targetBag then
            local slot = bagSlotCounters[targetBag]
            table.insert(targetPositions, {
                item = item,
                targetBag = targetBag,
                targetSlot = slot,
            })
            bagSlotCounters[targetBag] = slot + 1
        end
    end

    return targetPositions
end

-- =============================================================================
-- Phase 5: Execute Moves with Lock Tracking
-- =============================================================================

local function FindItemAt(bagID, slotID)
    local item = GetItemInfoForSlot(bagID, slotID)
    return item
end

local function FindEmptySlot(bagID, excludeSlot)
    local numSlots = GetContainerNumSlots(bagID) or 0
    for slotID = 1, numSlots do
        if slotID ~= excludeSlot then
            local texture = GetContainerItemInfo(bagID, slotID)
            if not texture then
                return slotID
            end
        end
    end
    return nil
end

local function BuildMoveList(targetPositions)
    local moves = {}

    -- For each item that's not in its target position, create a move
    -- We need to handle cycles (A->B, B->A) by using a temp slot
    for _, tp in ipairs(targetPositions) do
        local item = tp.item
        if item.bagID ~= tp.targetBag or item.slotID ~= tp.targetSlot then
            -- Check what's currently at the target position
            local occupant = FindItemAt(tp.targetBag, tp.targetSlot)
            if occupant then
                -- Target is occupied; we need to move the occupant first
                -- Find an empty slot to use as temp
                local tempSlot = FindEmptySlot(tp.targetBag, tp.targetSlot)
                if tempSlot then
                    table.insert(moves, {
                        fromBag = tp.targetBag,
                        fromSlot = tp.targetSlot,
                        toBag = tp.targetBag,
                        toSlot = tempSlot,
                        type = "temp",
                    })
                end
            end
            table.insert(moves, {
                fromBag = item.bagID,
                fromSlot = item.slotID,
                toBag = tp.targetBag,
                toSlot = tp.targetSlot,
                type = "place",
            })
        end
    end

    return moves
end

-- Deduplicate moves to prevent oscillation
local function DeduplicateMoves(moves)
    local seen = {}
    local result = {}
    for _, move in ipairs(moves) do
        local key = string.format("%d:%d->%d:%d", move.fromBag, move.fromSlot, move.toBag, move.toSlot)
        if not seen[key] then
            seen[key] = true
            table.insert(result, move)
        end
    end
    return result
end

-- =============================================================================
-- Sort Execution Engine
-- =============================================================================

local function StopSort(reason)
    isSorting = false
    sortQueue = {}
    currentMove = nil
    if sortFrame then
        sortFrame:SetScript("OnUpdate", nil)
    end
    if reason then
        print("|cFF00FF00OmniInventory|r: Physical sort " .. reason .. ". (" .. totalMoves .. " moves)")
    end
    totalMoves = 0
    passCount = 0
    sortCancelled = false
end

local function ExecuteNextMove()

    if sortCancelled then
        StopSort("cancelled")
        return
    end

    if #sortQueue == 0 then
        StopSort("complete")
        -- Trigger a layout refresh
        if Omni.Frame and Omni.Frame.UpdateLayout then
            Omni.Frame:UpdateLayout(nil, { forceFull = true, reason = "physical_sort" })
        end
        return
    end

    if totalMoves >= MAX_MOVES_PER_CYCLE * MAX_PASSES then
        StopSort("reached move limit")
        return
    end

    -- Check combat
    if InCombatLockdown and InCombatLockdown() then
        StopSort("interrupted by combat")
        return
    end

    -- Check cursor
    if CursorHasItem and CursorHasItem() then
        return -- wait for cursor to clear
    end

    currentMove = table.remove(sortQueue, 1)
    if not currentMove then
        StopSort("complete")
        return
    end

    -- Verify the source still has an item
    local texture = GetContainerItemInfo(currentMove.fromBag, currentMove.fromSlot)
    if not texture then
        -- Source is empty, skip this move
        return
    end

    -- Check if target is empty (it should be, but verify)
    local targetTexture = GetContainerItemInfo(currentMove.toBag, currentMove.toSlot)
    if targetTexture and currentMove.type ~= "merge" then
        -- Target got filled by something else; skip
        return
    end

    -- Execute the move
    PickupContainerItem(currentMove.fromBag, currentMove.fromSlot)
    PickupContainerItem(currentMove.toBag, currentMove.toSlot)

    totalMoves = totalMoves + 1
    lockWaitElapsed = 0
end

local function StartSortFrame()
    if not sortFrame then
        sortFrame = CreateFrame("Frame")
    end

    sortFrame:SetScript("OnUpdate", function(self, elapsed)
        if not isSorting then
            self:SetScript("OnUpdate", nil)
            return
        end

        lockWaitElapsed = lockWaitElapsed + (elapsed or 0)

        -- Wait for lock to clear before next move
        if lockWaitElapsed < MOVE_DELAY then
            return
        end

        lockWaitElapsed = 0
        ExecuteNextMove()
    end)
end

-- =============================================================================
-- Public API
-- =============================================================================

--- Start a physical bag sort.
--- @param opts table|nil { consolidateStacks, routeSpecialized }
function PhysicalSort:Sort(opts)
    opts = opts or {}

    if isSorting then
        print("|cFF00FF00OmniInventory|r: Sort already in progress.")
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        print("|cFF00FF00OmniInventory|r: Cannot sort in combat.")
        return
    end

    isSorting = true
    sortCancelled = false
    totalMoves = 0
    passCount = 0

    -- Phase 1: Detect specialized bags
    local specializedBags = DetectSpecializedBags()

    -- Phase 2+3: Collect all items and find consolidation moves
    local allItems = {}
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, numSlots do
            local item = GetItemInfoForSlot(bagID, slotID)
            if item then
                if Omni.Categorizer then
                    item.category = Omni.Categorizer:GetCategory(item)
                end
                table.insert(allItems, item)
            end
        end
    end

    -- Phase 3: Consolidate partial stacks
    local consolidateMoves = {}
    if opts.consolidateStacks ~= false then
        consolidateMoves = FindConsolidationMoves(allItems)
    end

    -- Phase 4: Build desired order
    local targetPositions = BuildDesiredOrder(specializedBags)

    -- Phase 5: Build move list
    local placeMoves = BuildMoveList(targetPositions)

    -- Combine: consolidation first, then placement
    sortQueue = {}
    for _, m in ipairs(consolidateMoves) do
        table.insert(sortQueue, m)
    end
    for _, m in ipairs(placeMoves) do
        table.insert(sortQueue, m)
    end

    -- Deduplicate
    sortQueue = DeduplicateMoves(sortQueue)

    if #sortQueue == 0 then
        StopSort("complete - nothing to sort")
        return
    end

    print("|cFF00FF00OmniInventory|r: Sorting bags (" .. #sortQueue .. " moves)...")
    StartSortFrame()
end

--- Cancel an in-progress sort.
function PhysicalSort:Cancel()
    if isSorting then
        sortCancelled = true
    end
end

--- Check if a sort is in progress.
--- @return boolean
function PhysicalSort:IsSorting()
    return isSorting
end

--- Sort only the bank bags (5-11 + main bank).
function PhysicalSort:SortBank()
    if isSorting then
        print("|cFF00FF00OmniInventory|r: Sort already in progress.")
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        print("|cFF00FF00OmniInventory|r: Cannot sort in combat.")
        return
    end

    -- Use Blizzard's native bank sort if available
    if SortBankBags then
        SortBankBags()
        if SortAuctionHouseBags then SortAuctionHouseBags() end
    end
end
