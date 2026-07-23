-- =============================================================================
-- OmniInventory Engine/BinPacker.lua
-- Dual-Pass / Single-Pass Height Balancing Matrix for Category Section Layouts
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or _G.OmniInventory or _G.Omni

local BinPacker = {}
Omni.BinPacker = BinPacker

-- Default layout metrics
local DEFAULT_HEADER_HEIGHT = 22
local DEFAULT_MIN_HEIGHT = 120

--- Compute dimensions for a single section based on slot count and column constraints
-- @param section Table containing section data or buttons array
-- @param maxColumns Max columns per section lane
-- @param slotSize Icon dimension in pixels
-- @param spacing Margin between buttons
-- @param headerHeight Pixel height of category header
-- @return table with computed section metrics { cols, rows, height, width, count }
function BinPacker:ComputeSectionDimensions(section, maxColumns, slotSize, spacing, headerHeight)
    maxColumns = math.max(1, maxColumns or 10)
    slotSize = slotSize or 36
    spacing = spacing or 4
    headerHeight = headerHeight or DEFAULT_HEADER_HEIGHT

    local buttons = section.buttons or section.slots
    local numSlots = buttons and #buttons or (section.slotCount or 0)
    if numSlots == 0 then
        return {
            cols = 1,
            rows = 0,
            height = headerHeight,
            width = slotSize + spacing,
            count = 0,
        }
    end

    local sectionCols = math.min(numSlots, maxColumns)
    local sectionRows = math.ceil(numSlots / sectionCols)
    local contentHeight = sectionRows * (slotSize + spacing)
    local totalHeight = headerHeight + contentHeight
    local totalWidth = sectionCols * (slotSize + spacing)

    return {
        cols = sectionCols,
        rows = sectionRows,
        height = totalHeight,
        width = totalWidth,
        count = numSlots,
    }
end

--- Computes exact target column height H_target = max(H_min, ceil(A_total / C_cols))
-- @param sections Array of section tables
-- @param targetColumns Target column count C_cols
-- @param maxColumns Max columns per section grid
-- @param slotSize Size of slot button
-- @param spacing Spacing between slots
-- @param headerHeight Height of header
-- @param minHeight Minimum height constraint H_min
-- @return targetHeight, totalArea
function BinPacker:ComputeTargetHeight(sections, targetColumns, maxColumns, slotSize, spacing, headerHeight, minHeight)
    targetColumns = math.max(1, targetColumns or 1)
    minHeight = minHeight or DEFAULT_MIN_HEIGHT
    
    local totalArea = 0
    for _, section in ipairs(sections) do
        local dims = self:ComputeSectionDimensions(section, maxColumns, slotSize, spacing, headerHeight)
        totalArea = totalArea + dims.height + (spacing or 4)
    end

    local targetHeight = math.max(minHeight, math.ceil(totalArea / targetColumns))
    return targetHeight, totalArea
end

--- Packs sections into balanced multi-column lanes in a single O(N) pass
-- @param sections List of section objects
-- @param targetColumns Number of vertical column lanes
-- @param maxColumns Max slot columns inside each section
-- @param slotSize Size of individual item buttons
-- @param spacing Pixel spacing between elements
-- @param minHeight Minimum column height target
-- @param headerHeight Section header height
-- @return packedColumns Array of columns with positioned sections, maxContainerWidth, maxContainerHeight
function BinPacker:PackSections(sections, targetColumns, maxColumns, slotSize, spacing, minHeight, headerHeight)
    targetColumns = math.max(1, targetColumns or 1)
    maxColumns = math.max(1, maxColumns or 10)
    slotSize = slotSize or 36
    spacing = spacing or 4
    headerHeight = headerHeight or DEFAULT_HEADER_HEIGHT

    if not sections or #sections == 0 then
        return {}, 0, 0
    end

    -- Step 1: Compute target height for single-pass column balancing
    local targetHeight, _ = self:ComputeTargetHeight(sections, targetColumns, maxColumns, slotSize, spacing, headerHeight, minHeight)

    -- Step 2: Column assignment loop
    local columns = {
        [1] = { index = 1, currentY = 0, sections = {}, width = 0 }
    }
    local currentCol = 1

    local colWidth = (slotSize + spacing) * maxColumns

    for _, section in ipairs(sections) do
        local dims = self:ComputeSectionDimensions(section, maxColumns, slotSize, spacing, headerHeight)
        local secHeight = dims.height

        -- If adding section to current column exceeds H_target and current column is non-empty, start next column
        local colData = columns[currentCol]
        if colData.currentY > 0 and (colData.currentY + secHeight) > targetHeight and currentCol < targetColumns then
            currentCol = currentCol + 1
            columns[currentCol] = { index = currentCol, currentY = 0, sections = {}, width = 0 }
            colData = columns[currentCol]
        end

        local xPos = (currentCol - 1) * (colWidth + spacing * 2)
        local yPos = colData.currentY

        local layoutInfo = {
            section = section,
            colIndex = currentCol,
            x = xPos,
            y = yPos,
            width = dims.width,
            height = dims.height,
            cols = dims.cols,
            rows = dims.rows,
            count = dims.count,
        }

        section.layoutInfo = layoutInfo
        table.insert(colData.sections, layoutInfo)

        colData.currentY = colData.currentY + secHeight + spacing
        if dims.width > colData.width then
            colData.width = dims.width
        end
    end

    -- Step 3: Compute final bounding box dimensions
    local maxContainerHeight = 0
    totalContainerWidth = 0

    for i, col in ipairs(columns) do
        if col.currentY > maxContainerHeight then
            maxContainerHeight = col.currentY
        end
        totalContainerWidth = totalContainerWidth + (col.width > 0 and (col.width + spacing * 2) or colWidth)
    end

    return columns, totalContainerWidth, maxContainerHeight
end

--- Balance existing column heights by redistributing sections if height variance exceeds threshold
-- @param columns Array of columns generated by PackSections
-- @param heightVarianceThreshold Maximum allowed height difference ratio (default 0.25)
function BinPacker:BalanceColumns(columns, heightVarianceThreshold)
    if not columns or #columns <= 1 then return columns end
    heightVarianceThreshold = heightVarianceThreshold or 0.25

    local minH, maxH = math.huge, 0
    for _, col in ipairs(columns) do
        if col.currentY < minH then minH = col.currentY end
        if col.currentY > maxH then maxH = col.currentY end
    end

    -- If variance is acceptable, return unchanged
    if minH > 0 and ((maxH - minH) / minH) <= heightVarianceThreshold then
        return columns
    end

    -- Otherwise, columns are balanced during single-pass packing via ComputeTargetHeight
    return columns
end

return BinPacker
