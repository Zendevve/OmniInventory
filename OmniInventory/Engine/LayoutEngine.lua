-- =============================================================================
-- OmniInventory Engine/LayoutEngine.lua
-- Unified 3-Mode Layout Engine (Flow, Grid, List) with Single-Pass Solver
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or _G.OmniInventory or _G.Omni

local LayoutEngine = {}
Omni.LayoutEngine = LayoutEngine

-- Layout Mode Constants
Omni.LAYOUT_MODE_FLOW = 1
Omni.LAYOUT_MODE_GRID = 2
Omni.LAYOUT_MODE_LIST = 3

LayoutEngine.MODE_FLOW = Omni.LAYOUT_MODE_FLOW
LayoutEngine.MODE_GRID = Omni.LAYOUT_MODE_GRID
LayoutEngine.MODE_LIST = Omni.LAYOUT_MODE_LIST

-- Default Metrics
local DEFAULT_SLOT_SIZE = 36
local DEFAULT_SPACING = 4
local DEFAULT_MAX_COLUMNS = 10
local DEFAULT_ROW_HEIGHT = 24
local DEFAULT_HEADER_HEIGHT = 22

--- Unified single-pass layout calculation for Flow Mode (Category Lanes)
-- @param containerFrame Master UI container frame
-- @param sections Array of section category tables containing item buttons
-- @param maxColumns Maximum columns per section lane
-- @param slotSize Size of item icon buttons
-- @param spacing Spacing between slots and sections
function LayoutEngine:CalculateFlowLayout(containerFrame, sections, maxColumns, slotSize, spacing)
    if not containerFrame or not sections then return end

    maxColumns = math.max(1, maxColumns or DEFAULT_MAX_COLUMNS)
    slotSize = slotSize or DEFAULT_SLOT_SIZE
    spacing = spacing or DEFAULT_SPACING
    local headerHeight = DEFAULT_HEADER_HEIGHT

    local content = containerFrame.content or containerFrame

    -- Sort sections by priority descending, then by name ascending
    table.sort(sections, function(a, b)
        local prioA = a.priority or a.categoryPriority or 0
        local prioB = b.priority or b.categoryPriority or 0
        if prioA == prioB then
            return (a.name or "") < (b.name or "")
        end
        return prioA > prioB
    end)

    -- Use BinPacker height-balancing solver if available
    local targetColumns = containerFrame.targetColumns or 1
    local minHeightTarget = containerFrame.maxHeightTarget or 250

    local packedColumns, totalWidth, totalHeight
    if Omni.BinPacker then
        packedColumns, totalWidth, totalHeight = Omni.BinPacker:PackSections(
            sections, targetColumns, maxColumns, slotSize, spacing, minHeightTarget, headerHeight
        )
    end

    -- If BinPacker generated columns, position section frames and children
    if packedColumns and #packedColumns > 0 then
        for _, colData in ipairs(packedColumns) do
            for _, info in ipairs(colData.sections) do
                local sec = info.section
                if sec.frame then
                    sec.frame:SetParent(content)
                    sec.frame:ClearAllPoints()
                    sec.frame:SetPoint("TOPLEFT", content, "TOPLEFT", info.x, -info.y)
                    sec.frame:SetSize(info.width, info.height)
                    sec.frame:Show()

                    local secCols = info.cols
                    local buttons = sec.buttons or sec.slots or {}
                    for idx, btn in ipairs(buttons) do
                        local r = math.floor((idx - 1) / secCols)
                        local c = (idx - 1) % secCols
                        btn:SetParent(sec.frame)
                        btn:ClearAllPoints()
                        btn:SetPoint("TOPLEFT", sec.frame, "TOPLEFT", c * (slotSize + spacing), -(headerHeight + r * (slotSize + spacing)))
                        btn:SetSize(slotSize, slotSize)
                        btn:Show()
                    end
                end
            end
        end

        containerFrame.contentWidth = totalWidth
        containerFrame.contentHeight = totalHeight
        if content.SetSize then content:SetSize(math.max(1, totalWidth), math.max(1, totalHeight)) end
        return totalWidth, totalHeight
    end

    -- Fallback: Direct single-pass height flow solver
    local colWidth = (slotSize + spacing) * maxColumns
    local currentCol, currentX, currentY = 1, 0, 0
    local columnHeights = { [1] = 0 }
    local maxHeightTarget = containerFrame.maxHeightTarget or 400

    for _, section in ipairs(sections) do
        local buttons = section.buttons or section.slots or {}
        local numSlots = #buttons
        local sectionCols = math.max(1, math.min(numSlots, maxColumns))
        local sectionRows = math.max(1, math.ceil(numSlots / sectionCols))
        local sectionHeight = headerHeight + (sectionRows * (slotSize + spacing))

        if currentY > 0 and (currentY + sectionHeight) > maxHeightTarget then
            currentCol = currentCol + 1
            currentX = (currentCol - 1) * (colWidth + spacing * 2)
            currentY = 0
            columnHeights[currentCol] = 0
        end

        if section.frame then
            section.frame:SetParent(content)
            section.frame:ClearAllPoints()
            section.frame:SetPoint("TOPLEFT", content, "TOPLEFT", currentX, -currentY)
            section.frame:SetSize(sectionCols * (slotSize + spacing), sectionHeight)
            section.frame:Show()

            for idx, btn in ipairs(buttons) do
                local r = math.floor((idx - 1) / sectionCols)
                local c = (idx - 1) % sectionCols
                btn:SetParent(section.frame)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", section.frame, "TOPLEFT", c * (slotSize + spacing), -(headerHeight + r * (slotSize + spacing)))
                btn:SetSize(slotSize, slotSize)
                btn:Show()
            end
        end

        currentY = currentY + sectionHeight + spacing
        columnHeights[currentCol] = currentY
    end

    local maxH = 0
    for _, h in pairs(columnHeights) do
        if h > maxH then maxH = h end
    end
    local maxW = currentCol * (colWidth + spacing * 2)

    containerFrame.contentWidth = maxW
    containerFrame.contentHeight = maxH
    if content.SetSize then content:SetSize(math.max(1, maxW), math.max(1, maxH)) end

    return maxW, maxH
end

--- Unified single-window Grid Mode solver preserving physical bag slot order
-- @param containerFrame Master UI container frame
-- @param buttons Flat array of item button frames
-- @param maxColumns Columns per row in grid
-- @param slotSize Size of item icon buttons
-- @param spacing Spacing between item buttons
function LayoutEngine:CalculateGridLayout(containerFrame, buttons, maxColumns, slotSize, spacing)
    if not containerFrame or not buttons then return end

    maxColumns = math.max(1, maxColumns or DEFAULT_MAX_COLUMNS)
    slotSize = slotSize or DEFAULT_SLOT_SIZE
    spacing = spacing or DEFAULT_SPACING

    local content = containerFrame.content or containerFrame

    local totalSlots = #buttons
    local numRows = math.max(1, math.ceil(totalSlots / maxColumns))

    for idx, btn in ipairs(buttons) do
        local r = math.floor((idx - 1) / maxColumns)
        local c = (idx - 1) % maxColumns

        btn:SetParent(content)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", c * (slotSize + spacing), -r * (slotSize + spacing))
        btn:SetSize(slotSize, slotSize)
        btn:Show()
    end

    local totalWidth = maxColumns * (slotSize + spacing) - spacing
    local totalHeight = numRows * (slotSize + spacing) - spacing

    containerFrame.contentWidth = totalWidth
    containerFrame.contentHeight = totalHeight
    if content.SetSize then content:SetSize(math.max(1, totalWidth), math.max(1, totalHeight)) end

    return totalWidth, totalHeight
end

--- Compact List Mode solver displaying data rows in a searchable table
-- @param containerFrame Master UI container frame
-- @param itemRows Array of row frames or row slot tables
-- @param rowHeight Height per list row in pixels
-- @param spacing Spacing between rows
function LayoutEngine:CalculateListLayout(containerFrame, itemRows, rowHeight, spacing)
    if not containerFrame or not itemRows then return end

    rowHeight = rowHeight or DEFAULT_ROW_HEIGHT
    spacing = spacing or 1
    local content = containerFrame.content or containerFrame
    local containerWidth = containerFrame:GetWidth() or 400

    for idx, row in ipairs(itemRows) do
        local frame = row.frame or row
        if frame and frame.SetPoint then
            frame:SetParent(content)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(idx - 1) * (rowHeight + spacing))
            if frame.SetSize then frame:SetSize(containerWidth, rowHeight) end
            frame:Show()
        end
    end

    local totalHeight = #itemRows * (rowHeight + spacing)
    containerFrame.contentWidth = containerWidth
    containerFrame.contentHeight = totalHeight
    if content.SetSize then content:SetSize(math.max(1, containerWidth), math.max(1, totalHeight)) end

    return containerWidth, totalHeight
end

--- Smooth transition routine between visual presentation modes without frame destruction
-- @param containerFrame Target container frame
-- @param newMode Target layout mode (1=FLOW, 2=GRID, 3=LIST)
function LayoutEngine:SetMode(containerFrame, newMode)
    if not containerFrame then return end
    newMode = newMode or Omni.LAYOUT_MODE_FLOW
    if containerFrame.currentLayoutMode == newMode then return end

    local prevMode = containerFrame.currentLayoutMode
    containerFrame.currentLayoutMode = newMode

    -- Hide section frames if leaving Flow Mode
    if prevMode == Omni.LAYOUT_MODE_FLOW and containerFrame.sections then
        for _, sec in ipairs(containerFrame.sections) do
            if sec.frame then sec.frame:Hide() end
        end
    end

    -- Trigger layout calculation based on new mode
    if newMode == Omni.LAYOUT_MODE_FLOW then
        if containerFrame.sections then
            self:CalculateFlowLayout(
                containerFrame,
                containerFrame.sections,
                containerFrame.maxColumns or DEFAULT_MAX_COLUMNS,
                containerFrame.slotSize or DEFAULT_SLOT_SIZE,
                containerFrame.spacing or DEFAULT_SPACING
            )
        end
    elseif newMode == Omni.LAYOUT_MODE_GRID then
        if containerFrame.allButtons then
            self:CalculateGridLayout(
                containerFrame,
                containerFrame.allButtons,
                containerFrame.maxColumns or DEFAULT_MAX_COLUMNS,
                containerFrame.slotSize or DEFAULT_SLOT_SIZE,
                containerFrame.spacing or DEFAULT_SPACING
            )
        end
    elseif newMode == Omni.LAYOUT_MODE_LIST then
        if containerFrame.allRows then
            self:CalculateListLayout(
                containerFrame,
                containerFrame.allRows,
                containerFrame.rowHeight or DEFAULT_ROW_HEIGHT,
                1
            )
        end
    end
end

--- Dirty slot batch updater called by EventRouter deferred paint passes
-- @param dirtySlots Table of slot keys needing UI repaint
function LayoutEngine:UpdateDirtySlots(dirtySlots)
    if not dirtySlots then return end

    -- Notify active containers to update slot visuals
    if Omni.MainContainer and Omni.MainContainer.UpdateDirtySlots then
        Omni.MainContainer:UpdateDirtySlots(dirtySlots)
    end
end

--- Execute container layout update pass with performance profiling
-- @param containerFrame Target container frame
function LayoutEngine:Update(containerFrame)
    if not containerFrame then return end
    local startTime = debugprofilestop and debugprofilestop() or (GetTime and GetTime() * 1000 or 0)

    local mode = containerFrame.currentLayoutMode or LayoutEngine.MODE_FLOW
    local width, height = 0, 0

    if mode == LayoutEngine.MODE_FLOW then
        if containerFrame.sections then
            width, height = self:CalculateFlowLayout(
                containerFrame,
                containerFrame.sections,
                containerFrame.maxColumns or DEFAULT_MAX_COLUMNS,
                containerFrame.slotSize or DEFAULT_SLOT_SIZE,
                containerFrame.spacing or DEFAULT_SPACING
            )
        end
    elseif mode == LayoutEngine.MODE_GRID then
        if containerFrame.allButtons then
            width, height = self:CalculateGridLayout(
                containerFrame,
                containerFrame.allButtons,
                containerFrame.maxColumns or DEFAULT_MAX_COLUMNS,
                containerFrame.slotSize or DEFAULT_SLOT_SIZE,
                containerFrame.spacing or DEFAULT_SPACING
            )
        end
    elseif mode == LayoutEngine.MODE_LIST then
        if containerFrame.allRows then
            width, height = self:CalculateListLayout(
                containerFrame,
                containerFrame.allRows,
                containerFrame.rowHeight or DEFAULT_ROW_HEIGHT,
                1
            )
        end
    end

    local endTime = debugprofilestop and debugprofilestop() or (GetTime and GetTime() * 1000 or 0)
    local elapsed = math.max(0, endTime - startTime)

    if Omni.Perf and type(Omni.Perf.RecordFrameDraw) == "function" then
        Omni.Perf:RecordFrameDraw(elapsed)
    end

    return width, height, elapsed
end

return LayoutEngine

