-- =============================================================================
-- OmniInventory DB/CacheWarmer.lua
-- Frame-Budgeted Async Background Scanner & Tooltip Cache Engine
-- =============================================================================
-- Scans bag/bank slots and item links asynchronously using a hidden GameTooltip.
-- Operates via a frame-budgeted OnUpdate worker pass (yielding at 4.0ms) to prevent
-- main-thread UI frame drops or hover micro-stutter during rapid bag updates.
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or _G.Omni or _G.OmniInventory or {}
_G.OmniInventory = Omni
_G.Omni = Omni

local CacheWarmer = {
    queue = {},
    isProcessing = false,
    FRAME_BUDGET_MS = 4.0 -- 4.0ms maximum frame budget per tick
}
Omni.CacheWarmer = CacheWarmer
Omni.DB = Omni.DB or {}
Omni.DB.CacheWarmer = CacheWarmer

-- Create hidden GameTooltip dedicated scanner instance
local scannerTooltip = CreateFrame("GameTooltip", "OmniInventoryScanTooltip", nil, "GameTooltipTemplate")
scannerTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
CacheWarmer.scannerTooltip = scannerTooltip

-- OnUpdate worker frame
local workerFrame = CreateFrame("Frame", "OmniInventoryCacheWarmerFrame", UIParent)
workerFrame:Hide()
CacheWarmer.frame = workerFrame

--- Worker function executed every frame tick while queue has tasks
local function OnUpdateWorker(self, elapsed)
    local startTime = debugprofilestop()

    while #CacheWarmer.queue > 0 do
        local task = table.remove(CacheWarmer.queue, 1)
        scannerTooltip:ClearLines()

        if task.bag and task.slot then
            scannerTooltip:SetBagItem(task.bag, task.slot)
        elseif task.link then
            scannerTooltip:SetHyperlink(task.link)
        end

        local numLines = scannerTooltip:NumLines() or 0
        local isBound = false
        local isQuest = false
        local isUnusable = false
        local textLines = {}

        for i = 1, numLines do
            local fontString = _G["OmniInventoryScanTooltipTextLeft" .. i]
            if fontString then
                local txt = fontString:GetText()
                if txt then
                    table.insert(textLines, txt)
                    -- Check for soulbound / bind text
                    if txt == ITEM_SOULBOUND or txt == ITEM_BIND_ON_PICKUP or txt == ITEM_BIND_QUEST then
                        isBound = true
                    end
                    -- Check for quest item markers
                    if txt == ITEM_BIND_QUEST or string.find(txt, "Quest Item") or string.find(txt, "Quest") then
                        isQuest = true
                    end
                    -- Check for red unusable requirement text (R > 0.9, G < 0.2, B < 0.2)
                    local r, g, b = fontString:GetTextColor()
                    if r and g and b and r > 0.9 and g < 0.2 and b < 0.2 then
                        isUnusable = true
                    end
                end
            end
        end

        -- Execute callback if provided
        if type(task.cb) == "function" then
            task.cb({
                isBound = isBound,
                isQuest = isQuest,
                isUnusable = isUnusable,
                numLines = numLines,
                lines = textLines
            }, task)
        end

        -- Frame Budget Check: Yield if elapsed time exceeds 4.0ms
        if (debugprofilestop() - startTime) > CacheWarmer.FRAME_BUDGET_MS then
            return
        end
    end

    -- Queue empty: deactivate OnUpdate ticker
    CacheWarmer.isProcessing = false
    self:Hide()
end

workerFrame:SetScript("OnUpdate", OnUpdateWorker)

--- Queue a bag slot or item link scan task.
-- @param bagID number|nil Bag ID (or nil if scanning link)
-- @param slotID number|nil Slot ID (or nil if scanning link)
-- @param itemLink string|nil Item link or string (or nil if scanning bag/slot)
-- @param callback function|nil Callback function(resultTable, task)
function CacheWarmer:QueueScan(bagID, slotID, itemLink, callback)
    table.insert(self.queue, {
        bag = bagID,
        slot = slotID,
        link = itemLink,
        cb = callback
    })
    if not self.isProcessing then
        self.isProcessing = true
        self.frame:Show()
    end
end

--- Clear all pending queued scan tasks and stop the worker frame ticker.
function CacheWarmer:ClearQueue()
    table.wipe(self.queue)
    self.isProcessing = false
    self.frame:Hide()
end

--- Get the current count of pending scan tasks in queue.
-- @return number Pending task count
function CacheWarmer:GetQueueLength()
    return #self.queue
end

--- Pre-warm GetItemInfo and tooltip cache for an array of item links or IDs.
-- @param itemLinks table Array of item links or IDs
function CacheWarmer:WarmCache(itemLinks)
    if type(itemLinks) ~= "table" then return end
    for _, link in ipairs(itemLinks) do
        if link then
            self:QueueScan(nil, nil, link, nil)
        end
    end
end

function CacheWarmer:OnInitialize()
    -- Ready for async scanning
end

if Omni.RegisterModule then
    Omni:RegisterModule("CacheWarmer", CacheWarmer)
end

return CacheWarmer
