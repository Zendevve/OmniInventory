-- =============================================================================
-- OmniInventory UI/VirtualScrollView.lua
-- Virtualized Window Scroll View & Viewport Controller for Bank and List Views
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or _G.OmniInventory or _G.Omni

local VirtualScrollView = {}
Omni.VirtualScrollView = VirtualScrollView

-- Default Viewport Metrics
local VISIBLE_BUTTON_WINDOW = 40
local DEFAULT_SLOT_SIZE     = 36
local DEFAULT_SPACING       = 4
local DEFAULT_COLUMNS       = 10

--- Creates a virtualized scroll viewport instance
-- @param parent Parent UI container frame
-- @param name Sub-frame global identifier
-- @param width Viewport width
-- @param height Viewport height
-- @return Viewport object table
function VirtualScrollView:Create(parent, name, width, height)
    parent = parent or UIParent
    name = name or "OmniInventoryVirtualScrollView"
    width = width or 400
    height = height or 300

    local view = {
        name = name,
        width = width,
        height = height,
        columns = DEFAULT_COLUMNS,
        slotSize = DEFAULT_SLOT_SIZE,
        spacing = DEFAULT_SPACING,
        slotDataList = {},
        visibleButtons = {},
        totalItems = 0,
        scrollTop = 0,
    }

    -- Outer Viewport Mask Frame
    local container = CreateFrame("Frame", name, parent)
    container:SetSize(width, height)
    container:SetClampedToScreen(true)
    view.container = container

    -- ScrollFrame Viewport Mask
    local scrollFrame = CreateFrame("ScrollFrame", name .. "ScrollFrame", container)
    scrollFrame:SetAllPoints(container)
    view.scrollFrame = scrollFrame

    -- ScrollChild Canvas
    local scrollChild = CreateFrame("Frame", name .. "ScrollChild", scrollFrame)
    scrollChild:SetSize(width, height)
    scrollFrame:SetScrollChild(scrollChild)
    view.scrollChild = scrollChild

    -- Vertical ScrollBar Slider Component
    local scrollBar = CreateFrame("Slider", name .. "ScrollBar", scrollFrame, "UIPanelScrollBarTemplate")
    scrollBar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -2, -18)
    scrollBar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -2, 18)
    scrollBar:SetWidth(16)
    view.scrollBar = scrollBar

    scrollBar:SetScript("OnValueChanged", function(self, value)
        scrollFrame:SetVerticalScroll(value)
        view:UpdateViewport(value)
    end)

    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValue(0)
    scrollBar:SetValueStep(1)

    -- Instantiate Fixed Window of Visible Pooled Item Buttons (~40 buttons)
    local isCombat = InCombatLockdown and InCombatLockdown()
    for i = 1, VISIBLE_BUTTON_WINDOW do
        local btn = nil
        if Omni.FramePool and not isCombat then
            btn = Omni.FramePool:AcquireItemButton(scrollChild, 0, i)
        end
        if not btn and not isCombat then
            btn = CreateFrame("Button", name .. "Btn" .. i, scrollChild, "ContainerFrameItemButtonTemplate")
            btn:SetID(i)
        end
        if btn then
            if not isCombat then btn:Hide() end
            table.insert(view.visibleButtons, btn)
        end
    end

    -- Scroll Event Intercept: O(1) startOffset re-binding pass
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = scrollBar:GetValue() or 0
        local step = (view.slotSize + view.spacing)
        local minVal, maxVal = scrollBar:GetMinMaxValues()
        local newScroll = current - (delta * step)
        if newScroll < minVal then newScroll = minVal end
        if newScroll > maxVal then newScroll = maxVal end
        scrollBar:SetValue(newScroll)
    end)

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        view:UpdateViewport(offset)
    end)

    -- Attach controller methods to view instance
    for k, v in pairs(VirtualScrollView) do
        if type(v) == "function" then
            view[k] = v
        end
    end

    return view
end

--- Binds container item data array to virtualized scroll view
-- @param slotDataList Array of item slot records
-- @param columns Number of columns per row
-- @param slotSize Size of item icon buttons
-- @param spacing Spacing between slots
function VirtualScrollView:SetData(slotDataList, columns, slotSize, spacing)
    self.slotDataList = slotDataList or {}
    self.totalItems = #self.slotDataList
    self.columns = math.max(1, columns or DEFAULT_COLUMNS)
    self.slotSize = slotSize or DEFAULT_SLOT_SIZE
    self.spacing = spacing or DEFAULT_SPACING

    local rowHeight = self.slotSize + self.spacing
    local totalRows = math.ceil(self.totalItems / self.columns)
    local totalContentHeight = math.max(self.height, totalRows * rowHeight)

    self.scrollChild:SetSize(self.width, totalContentHeight)

    local maxScroll = math.max(0, totalContentHeight - self.height)
    self.scrollBar:SetMinMaxValues(0, maxScroll)

    -- Reset scroll top if out of range
    local currentScroll = self.scrollBar:GetValue() or 0
    if currentScroll > maxScroll then
        currentScroll = maxScroll
        self.scrollBar:SetValue(currentScroll)
    end

    self:UpdateViewport(currentScroll)
end

--- Intercepts scroll ticks and re-binds visible 40 frame window in O(1) time
-- @param scrollTop Current vertical scroll offset in pixels
function VirtualScrollView:UpdateViewport(scrollTop)
    self.scrollTop = math.max(0, scrollTop or 0)
    local rowHeight = self.slotSize + self.spacing

    -- Compute slot start offset: startRow = math.floor(scrollTop / rowHeight)
    local startRow = math.floor(self.scrollTop / rowHeight)
    local startOffset = startRow * self.columns

    local numVisible = #self.visibleButtons
    local isCombat = InCombatLockdown and InCombatLockdown()

    for i = 1, numVisible do
        local btn = self.visibleButtons[i]
        local dataIndex = startOffset + i

        if dataIndex <= self.totalItems then
            local data = self.slotDataList[dataIndex]
            if data and btn then
                -- 1. Bag ID & Slot ID Re-binding
                btn.bagID = data.bagID or 0
                btn.slotID = data.slotID or dataIndex
                btn.itemInfo = data.itemInfo or data
                if btn.SetID then btn:SetID(btn.slotID) end

                -- 2. Dummy Bag Parent Adjustment (for WoW native C-API compatibility)
                if data.bagID and Omni.FramePool and not isCombat then
                    local dummyParent = self.container or btn:GetParent()
                    local dummyBag = Omni.FramePool:GetDummyBag(dummyParent, data.bagID)
                    if dummyBag and btn:GetParent() ~= dummyBag then
                        btn:SetParent(dummyBag)
                    end
                end

                -- 3. Render Item Visuals via renderCallback, Omni.ItemButton wrapper, or native fallback
                if data.renderCallback then
                    data.renderCallback(btn, data)
                elseif Omni.ItemButton and Omni.ItemButton.SetItem then
                    Omni.ItemButton:SetItem(btn, data.itemInfo or data)
                else
                    -- Native texture & count fallback
                    local iconTex = _G[btn:GetName() .. "IconTexture"]
                    if iconTex then
                        iconTex:SetTexture(data.icon or data.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
                    end

                    local countText = _G[btn:GetName() .. "Count"]
                    if countText then
                        if data.count and data.count > 1 then
                            countText:SetText(data.count)
                            countText:Show()
                        else
                            countText:SetText("")
                            countText:Hide()
                        end
                    end
                end

                -- 4. Calculate position inside viewport canvas
                if not isCombat then
                    local relIndex = i - 1
                    local r = math.floor(relIndex / self.columns)
                    local c = relIndex % self.columns

                    local xPos = c * (self.slotSize + self.spacing)
                    local yPos = (startRow + r) * rowHeight

                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", xPos, -yPos)
                    btn:SetSize(self.slotSize, self.slotSize)
                    btn:Show()
                end
            elseif btn then
                if not isCombat then btn:Hide() end
            end
        elseif btn then
            if not isCombat then btn:Hide() end
        end
    end
end

--- Cleanup and release allocated pooled frames
function VirtualScrollView:Destroy()
    local isCombat = InCombatLockdown and InCombatLockdown()
    if self.visibleButtons and Omni.FramePool and not isCombat then
        for _, btn in ipairs(self.visibleButtons) do
            Omni.FramePool:ReleaseItemButton(btn)
        end
    end
    self.visibleButtons = {}
    if self.container and not isCombat then self.container:Hide() end
end

return VirtualScrollView

