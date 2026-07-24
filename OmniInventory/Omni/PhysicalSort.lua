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
local totalWaitElapsed = 0
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

local function GenerateSortKey(item)
    if not item then return 0 end
    if item.__sortKey then return item.__sortKey end

    local catPrio = GetCategoryPriority(item)
    local invCatPrio = math.max(0, 100 - catPrio) -- Higher is better (0-100)
    
    local quality = math.min(10, item.quality or 0)
    local ilvl = math.min(999, item.itemLevel or 0)
    local itemID = math.min(99999, item.itemID or 0)
    local count = math.min(9999, item.count or 1)

    -- Max possible key = 100 * 10^13 = 10^15 (fits within 53-bit float precision of 9 * 10^15)
    item.__sortKey = (invCatPrio * 10000000000000) 
                   + (quality    * 1000000000000) 
                   + (ilvl       * 1000000000) 
                   + (itemID     * 10000) 
                   + count

    return item.__sortKey
end

-- Multi-property comparator for desired order
local function ItemSortComparator(a, b)
    if not a and not b then return false end
    if not a then return false end
    if not b then return true end

    local keyA = GenerateSortKey(a)
    local keyB = GenerateSortKey(b)

    if keyA ~= keyB then 
        return keyA > keyB 
    end

    -- Fallback for identical keys (e.g. same itemID but different random enchants)
    local nA = a.name or "zzz"
    local nB = b.name or "zzz"
    return nA < nB
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
                local space = maxStack - (target.count or 1)
                if space > 0 and (source.count or 1) > 0 then
                    local toMove = math.min(space, (source.count or 1))
                    table.insert(moves, {
                        fromBag = source.bagID,
                        fromSlot = source.slotID,
                        toBag = target.bagID,
                        toSlot = target.slotID,
                        type = "merge",
                    })
                    target.count = (target.count or 1) + toMove
                    source.count = (source.count or 1) - toMove
                    if source.count <= 0 then
                        source.__empty = true
                    end
                end
            end
        end
    end

    return moves
end

-- =============================================================================
-- Phase 4: Build Desired Order
-- =============================================================================

local function BuildDesiredOrder(allItems, specializedBags)
    local activeItems = {}
    for _, item in ipairs(allItems) do
        if not item.__empty then
            table.insert(activeItems, item)
        end
    end

    -- Sort by desired order
    table.sort(activeItems, ItemSortComparator)

    -- Phase 5: Target Slot Assignment Matrix
    -- We split available slots into Specialized slots (e.g. Quiver, Herb Bag) and General slots.
    local specializedSlots = {}
    local generalSlots = {}

    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        local family = specializedBags[bagID]
        if family and family > 0 then
            specializedSlots[bagID] = {}
            for slot = 1, numSlots do
                table.insert(specializedSlots[bagID], {bagID = bagID, slotID = slot})
            end
        else
            for slot = 1, numSlots do
                table.insert(generalSlots, {bagID = bagID, slotID = slot})
            end
        end
    end

    local frontIdx = 1
    local backIdx = #generalSlots
    local targetPositions = {}

    for _, item in ipairs(activeItems) do
        local placed = false

        -- 1. Try to place in specialized bags first (bags 1-4)
        for bagID, slots in pairs(specializedSlots) do
            if #slots > 0 and ShouldItemGoInBag(item, bagID, specializedBags) then
                local target = table.remove(slots, 1) -- pop front
                table.insert(targetPositions, {
                    item = item,
                    targetBag = target.bagID,
                    targetSlot = target.slotID,
                })
                placed = true
                break
            end
        end
        
        -- 2. Fall back to normal bags matrix logic
        if not placed then
            local isJunk = (item.quality == 0) or (GetCategoryPriority(item) >= 90)

            if isJunk and backIdx >= frontIdx then
                -- Place junk at the tail
                local target = generalSlots[backIdx]
                backIdx = backIdx - 1
                table.insert(targetPositions, {
                    item = item,
                    targetBag = target.bagID,
                    targetSlot = target.slotID,
                })
            elseif frontIdx <= backIdx then
                -- Place normal items at the front
                local target = generalSlots[frontIdx]
                frontIdx = frontIdx + 1
                table.insert(targetPositions, {
                    item = item,
                    targetBag = target.bagID,
                    targetSlot = target.slotID,
                })
            end
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

local function BuildMoveList(targetPositions, allItems, specializedBags)
    local moves = {}

    -- 1. Initialize virtual board from allItems to ensure reference equality
    local virtualBags = {}
    for bagID = 0, 4 do
        virtualBags[bagID] = {}
    end
    for _, item in ipairs(allItems) do
        if not item.__empty then
            virtualBags[item.bagID][item.slotID] = item
        end
    end

    -- Helper to find an empty slot in the virtual board
    local function FindVirtualEmptySlot(item, preferredBag)
        -- First try the preferred bag
        if preferredBag and ShouldItemGoInBag(item, preferredBag, specializedBags) then
            local numSlots = GetContainerNumSlots(preferredBag) or 0
            for slotID = 1, numSlots do
                if not virtualBags[preferredBag][slotID] then
                    return preferredBag, slotID
                end
            end
        end
        -- Then search all bags (0-4)
        for bagID = 0, 4 do
            if ShouldItemGoInBag(item, bagID, specializedBags) then
                local numSlots = GetContainerNumSlots(bagID) or 0
                for slotID = 1, numSlots do
                    if not virtualBags[bagID][slotID] then
                        return bagID, slotID
                    end
                end
            end
        end
        return nil, nil
    end

    local maxIterations = 1000
    local iterations = 0
    local done = false

    while not done and iterations < maxIterations do
        iterations = iterations + 1
        done = true

        for _, tp in ipairs(targetPositions) do
            local item = tp.item
            local curBag, curSlot = item.bagID, item.slotID

            if curBag ~= tp.targetBag or curSlot ~= tp.targetSlot then
                done = false

                -- Check what's currently at the target slot
                local occupant = virtualBags[tp.targetBag][tp.targetSlot]
                if occupant then
                    -- Target is occupied; find a virtual empty slot to move the occupant to
                    local tempBag, tempSlot = FindVirtualEmptySlot(occupant, tp.targetBag)
                    if tempBag and tempSlot then
                        table.insert(moves, {
                            fromBag = tp.targetBag,
                            fromSlot = tp.targetSlot,
                            toBag = tempBag,
                            toSlot = tempSlot,
                            type = "temp",
                        })
                        virtualBags[tempBag][tempSlot] = occupant
                        virtualBags[tp.targetBag][tp.targetSlot] = nil
                        occupant.bagID = tempBag
                        occupant.slotID = tempSlot
                    else
                        break
                    end
                end

                -- Now the target slot is empty; move the item there
                table.insert(moves, {
                    fromBag = curBag,
                    fromSlot = curSlot,
                    toBag = tp.targetBag,
                    toSlot = tp.targetSlot,
                    type = "place",
                })
                virtualBags[tp.targetBag][tp.targetSlot] = item
                virtualBags[curBag][curSlot] = nil
                item.bagID = tp.targetBag
                item.slotID = tp.targetSlot
            end
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

local previousPassSwaps = {}
local sortOpts = {}

local function StopSort(reason)
    isSorting = false
    sortQueue = {}
    currentMove = nil
    if sortFrame then
        sortFrame:SetScript("OnUpdate", nil)
        sortFrame:UnregisterEvent("ITEM_LOCK_CHANGED")
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
        -- We finished this pass. Try another pass if we haven't hit the limit.
        passCount = passCount + 1
        if passCount >= MAX_PASSES then
            StopSort("complete (max passes)")
        else
            -- Run next pass
            PhysicalSort:RunSortPass()
        end
        return
    end

    if totalMoves >= MAX_MOVES_PER_CYCLE * MAX_PASSES then
        StopSort("reached absolute move limit")
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        StopSort("interrupted by combat")
        return
    end

    if CursorHasItem and CursorHasItem() then
        return -- wait for cursor to clear
    end

    currentMove = table.remove(sortQueue, 1)
    if not currentMove then return end

    -- Verify source still has an item
    local texture = GetContainerItemInfo(currentMove.fromBag, currentMove.fromSlot)
    if not texture then
        ExecuteNextMove() -- skip and proceed
        return
    end

    -- Verify target hasn't been blocked
    local targetTexture = GetContainerItemInfo(currentMove.toBag, currentMove.toSlot)
    if targetTexture and currentMove.type ~= "merge" then
        ExecuteNextMove() -- skip
        return
    end

    -- Execute the move
    PickupContainerItem(currentMove.fromBag, currentMove.fromSlot)
    PickupContainerItem(currentMove.toBag, currentMove.toSlot)
    totalMoves = totalMoves + 1
    totalWaitElapsed = 0
end

local function PumpSortEngine(eventBag, eventSlot)
    if not isSorting or not currentMove then return end

    -- Fast reject if the lock event isn't for our involved slots
    -- Note: bag and slot might be nil if pumped manually or via timeout fallback
    if eventBag and eventSlot then
        local matchesFrom = (eventBag == currentMove.fromBag and eventSlot == currentMove.fromSlot)
        local matchesTo = (eventBag == currentMove.toBag and eventSlot == currentMove.toSlot)
        if not (matchesFrom or matchesTo) then
            return
        end
    end

    local _, _, locked = GetContainerItemInfo(currentMove.fromBag, currentMove.fromSlot)
    local targetLocked = false
    local _, targetCount = GetContainerItemInfo(currentMove.toBag, currentMove.toSlot)
    if targetCount then
        local _, _, tl = GetContainerItemInfo(currentMove.toBag, currentMove.toSlot)
        targetLocked = tl
    end

    if not locked and not targetLocked then
        currentMove = nil
        totalWaitElapsed = 0
        ExecuteNextMove()
    end
end

local function StartSortFrame()
    if not sortFrame then
        sortFrame = CreateFrame("Frame")
        sortFrame:SetScript("OnEvent", function(self, event, bag, slot)
            if isSorting and event == "ITEM_LOCK_CHANGED" then
                PumpSortEngine(bag, slot)
            end
        end)
    end
    sortFrame:RegisterEvent("ITEM_LOCK_CHANGED")

    totalWaitElapsed = 0
    sortFrame:SetScript("OnUpdate", function(self, elapsed)
        if not isSorting then
            self:SetScript("OnUpdate", nil)
            return
        end
        
        -- Fallback timeout in case events are dropped by server
        if currentMove then
            totalWaitElapsed = totalWaitElapsed + (elapsed or 0)
            if totalWaitElapsed > LOCK_TIMEOUT then
                -- Timeout occurred. Clear current move and proceed to retry or skip
                currentMove = nil
                totalWaitElapsed = 0
                ExecuteNextMove()
            end
        else
            -- Initial bootstrap or stuck
            totalWaitElapsed = totalWaitElapsed + (elapsed or 0)
            if totalWaitElapsed > MOVE_DELAY then
                totalWaitElapsed = 0
                ExecuteNextMove()
            end
        end
    end)
end

function PhysicalSort:RunSortPass()
    local specializedBags = DetectSpecializedBags()
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

    local consolidateMoves = {}
    if sortOpts.consolidateStacks ~= false then
        consolidateMoves = FindConsolidationMoves(allItems)
    end

    local targetPositions = BuildDesiredOrder(allItems, specializedBags)
    local placeMoves = BuildMoveList(targetPositions, allItems, specializedBags)

    sortQueue = {}
    for _, m in ipairs(consolidateMoves) do table.insert(sortQueue, m) end
    for _, m in ipairs(placeMoves) do table.insert(sortQueue, m) end

    -- Deduplicate against previous passes and within current pass
    local validQueue = {}
    local currentPassSwaps = {}
    
    for _, m in ipairs(sortQueue) do
        local key = string.format("%d:%d->%d:%d", m.fromBag, m.fromSlot, m.toBag, m.toSlot)
        local reverseKey = string.format("%d:%d->%d:%d", m.toBag, m.toSlot, m.fromBag, m.fromSlot)
        
        if previousPassSwaps[key] or previousPassSwaps[reverseKey] then
            -- Skip inter-pass oscillation
        elseif currentPassSwaps[key] then
            -- Skip duplicate move in same pass
        else
            previousPassSwaps[key] = true
            currentPassSwaps[key] = true
            table.insert(validQueue, m)
        end
    end
    sortQueue = validQueue

    if #sortQueue == 0 then
        StopSort(passCount == 0 and "complete - nothing to sort" or "complete")
        if Omni.Frame and Omni.Frame.UpdateLayout then
            Omni.Frame:UpdateLayout(nil, { forceFull = true, reason = "physical_sort" })
        end
        return
    end
    
    if passCount == 0 then
        print("|cFF00FF00OmniInventory|r: Sorting bags...")
        StartSortFrame()
    end
end

-- =============================================================================
-- Public API
-- =============================================================================

--- Start a physical bag sort.
--- @param opts table|nil { consolidateStacks, routeSpecialized }
function PhysicalSort:Sort(opts)
    if isSorting then
        print("|cFF00FF00OmniInventory|r: Sort already in progress.")
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        print("|cFF00FF00OmniInventory|r: Cannot sort in combat.")
        return
    end

    sortOpts = opts or {}
    isSorting = true
    sortCancelled = false
    totalMoves = 0
    passCount = 0
    previousPassSwaps = {}
    
    self:RunSortPass()
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
