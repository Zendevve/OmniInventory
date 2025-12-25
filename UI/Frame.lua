-- =============================================================================
-- OmniInventory Main Frame
-- =============================================================================
-- Purpose: Primary window container with header, search, content area,
-- footer, and window management (move, resize, position persistence).
-- =============================================================================

local addonName, Omni = ...

Omni.Frame = {}
local Frame = Omni.Frame

-- =============================================================================
-- Constants
-- =============================================================================

local FRAME_MIN_WIDTH = 350
local FRAME_MIN_HEIGHT = 300
local FRAME_DEFAULT_WIDTH = 450
local FRAME_DEFAULT_HEIGHT = 400
local HEADER_HEIGHT = 24
local FOOTER_HEIGHT = 24
local SEARCH_HEIGHT = 24
local PADDING = 8
local ITEM_SIZE = 37
local ITEM_SPACING = 4

-- =============================================================================
-- Frame State
-- =============================================================================

local mainFrame = nil
local itemButtons = {}  -- Active item buttons
local currentView = "grid"
local isSearchActive = false
local searchText = ""

-- =============================================================================
-- Frame Creation
-- =============================================================================

function Frame:CreateMainFrame()
    if mainFrame then return mainFrame end

    -- Main window
    mainFrame = CreateFrame("Frame", "OmniInventoryFrame", UIParent)
    mainFrame:SetSize(FRAME_DEFAULT_WIDTH, FRAME_DEFAULT_HEIGHT)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetFrameLevel(100)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:SetResizable(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetMinResize(FRAME_MIN_WIDTH, FRAME_MIN_HEIGHT)

    -- Backdrop
    mainFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    mainFrame:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    mainFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Make tabbable
    tinsert(UISpecialFrames, "OmniInventoryFrame")

    -- Create components
    self:CreateHeader()
    self:CreateSearchBar()
    self:CreateContentArea()
    self:CreateFooter()
    self:CreateResizeHandle()

    -- Register for updates
    self:RegisterEvents()

    -- Start hidden
    mainFrame:Hide()

    return mainFrame
end

-- =============================================================================
-- Header
-- =============================================================================

function Frame:CreateHeader()
    local header = CreateFrame("Frame", nil, mainFrame)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", PADDING, -PADDING)
    header:SetPoint("TOPRIGHT", -PADDING, -PADDING)

    -- Background
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    header.bg:SetVertexColor(0.15, 0.15, 0.15, 1)

    -- Title
    header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.title:SetPoint("LEFT", 6, 0)
    header.title:SetText("|cFF00FF00Omni|r Inventory")

    -- Close button
    header.closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    header.closeBtn:SetSize(20, 20)
    header.closeBtn:SetPoint("RIGHT", -2, 0)
    header.closeBtn:SetScript("OnClick", function()
        Frame:Hide()
    end)

    -- View toggle button
    header.viewBtn = CreateFrame("Button", nil, header)
    header.viewBtn:SetSize(50, 18)
    header.viewBtn:SetPoint("RIGHT", header.closeBtn, "LEFT", -4, 0)
    header.viewBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    header.viewBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
    header.viewBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    header.viewBtn.text = header.viewBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header.viewBtn.text:SetPoint("CENTER")
    header.viewBtn.text:SetText("Grid")

    header.viewBtn:SetScript("OnClick", function()
        Frame:CycleView()
    end)

    header.viewBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.3, 0.3, 1)
    end)
    header.viewBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.2, 1)
    end)

    -- Make header draggable
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        mainFrame:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        mainFrame:StopMovingOrSizing()
        Frame:SavePosition()
    end)

    mainFrame.header = header
end

-- =============================================================================
-- Search Bar
-- =============================================================================

function Frame:CreateSearchBar()
    local searchBar = CreateFrame("Frame", nil, mainFrame)
    searchBar:SetHeight(SEARCH_HEIGHT)
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

    -- Search editbox
    searchBar.editBox = CreateFrame("EditBox", "OmniSearchBox", searchBar, "InputBoxTemplate")
    searchBar.editBox:SetPoint("LEFT", searchBar.icon, "RIGHT", 4, 0)
    searchBar.editBox:SetPoint("RIGHT", -6, 0)
    searchBar.editBox:SetHeight(18)
    searchBar.editBox:SetAutoFocus(false)
    searchBar.editBox:SetFontObject(GameFontNormalSmall)

    -- Remove default borders
    searchBar.editBox:SetBackdrop(nil)
    if searchBar.editBox.Left then searchBar.editBox.Left:Hide() end
    if searchBar.editBox.Right then searchBar.editBox.Right:Hide() end
    if searchBar.editBox.Middle then searchBar.editBox.Middle:Hide() end

    searchBar.editBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText() or ""
        Frame:ApplySearch(searchText)
    end)

    searchBar.editBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    mainFrame.searchBar = searchBar
    mainFrame.searchBox = searchBar.editBox
end

-- =============================================================================
-- Content Area (ScrollFrame)
-- =============================================================================

function Frame:CreateContentArea()
    local content = CreateFrame("ScrollFrame", "OmniContentScroll", mainFrame, "UIPanelScrollFrameTemplate")
    content:SetPoint("TOPLEFT", mainFrame.searchBar, "BOTTOMLEFT", 0, -4)
    content:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -PADDING - 20, PADDING + FOOTER_HEIGHT + 4)

    -- Scroll child
    local scrollChild = CreateFrame("Frame", "OmniContentChild", content)
    scrollChild:SetSize(content:GetWidth(), 1)  -- Height set dynamically
    content:SetScrollChild(scrollChild)

    -- Style scrollbar
    local scrollBar = _G["OmniContentScrollScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 20, -16)
        scrollBar:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 20, 16)
    end

    mainFrame.content = content
    mainFrame.scrollChild = scrollChild
end

-- =============================================================================
-- Footer
-- =============================================================================

function Frame:CreateFooter()
    local footer = CreateFrame("Frame", nil, mainFrame)
    footer:SetHeight(FOOTER_HEIGHT)
    footer:SetPoint("BOTTOMLEFT", PADDING, PADDING)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)

    -- Background
    footer.bg = footer:CreateTexture(nil, "BACKGROUND")
    footer.bg:SetAllPoints()
    footer.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    footer.bg:SetVertexColor(0.12, 0.12, 0.12, 1)

    -- Bag space counter
    footer.slots = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footer.slots:SetPoint("LEFT", 6, 0)
    footer.slots:SetText("0/0")

    -- Money display
    footer.money = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footer.money:SetPoint("RIGHT", -6, 0)
    footer.money:SetText("0g 0s 0c")

    mainFrame.footer = footer
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
    end)

    mainFrame.resizeHandle = handle
end

-- =============================================================================
-- Event Registration
-- =============================================================================

function Frame:RegisterEvents()
    if not mainFrame then return end

    -- Connect to Event bucket system
    if Omni.Events then
        Omni.Events:RegisterBucketEvent("BAG_UPDATE", function(changedBags)
            if mainFrame:IsShown() then
                Frame:UpdateLayout(changedBags)
            end
        end)

        Omni.Events:RegisterEvent("PLAYER_MONEY", function()
            Frame:UpdateMoney()
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

-- =============================================================================
-- View Modes
-- =============================================================================

function Frame:SetView(mode)
    currentView = mode or "grid"

    if mainFrame and mainFrame.header and mainFrame.header.viewBtn then
        local labels = { grid = "Grid", flow = "Flow", list = "List" }
        mainFrame.header.viewBtn.text:SetText(labels[currentView] or "Grid")
    end

    Frame:UpdateLayout()
end

function Frame:CycleView()
    local modes = { "grid", "flow", "list" }
    local nextIdx = 1

    for i, mode in ipairs(modes) do
        if mode == currentView then
            nextIdx = (i % #modes) + 1
            break
        end
    end

    Frame:SetView(modes[nextIdx])
end

-- =============================================================================
-- Layout Update
-- =============================================================================

function Frame:UpdateLayout(changedBags)
    if not mainFrame or not mainFrame:IsShown() then return end

    -- Get all items via Shim
    local items = {}
    if OmniC_Container then
        items = OmniC_Container.GetAllBagItems()
    end

    -- Categorize items
    if Omni.Categorizer then
        for _, item in ipairs(items) do
            item.category = Omni.Categorizer:GetCategory(item)
        end
    end

    -- Sort items
    if Omni.Sorter then
        items = Omni.Sorter:Sort(items, Omni.Sorter:GetDefaultMode())
    end

    -- Render based on view mode
    if currentView == "grid" then
        self:RenderGridView(items)
    elseif currentView == "flow" then
        self:RenderFlowView(items)
    else
        self:RenderGridView(items)  -- Fallback
    end

    -- Update footer
    self:UpdateSlotCount()
    self:UpdateMoney()

    -- Apply search if active
    if searchText and searchText ~= "" then
        self:ApplySearch(searchText)
    end
end

-- =============================================================================
-- Grid View Rendering
-- =============================================================================

function Frame:RenderGridView(items)
    if not mainFrame or not mainFrame.scrollChild then return end

    local scrollChild = mainFrame.scrollChild

    -- Release existing buttons back to pool
    if Omni.Pool then
        for _, btn in ipairs(itemButtons) do
            Omni.Pool:Release("ItemButton", btn)
        end
    end
    itemButtons = {}

    -- Calculate layout
    local contentWidth = mainFrame.content:GetWidth() - 20
    local columns = math.floor(contentWidth / (ITEM_SIZE + ITEM_SPACING))
    columns = math.max(columns, 1)

    local rows = math.ceil(#items / columns)
    local contentHeight = rows * (ITEM_SIZE + ITEM_SPACING) + ITEM_SPACING
    scrollChild:SetSize(contentWidth, contentHeight)

    -- Create/position buttons
    for i, itemInfo in ipairs(items) do
        local btn

        if Omni.Pool then
            btn = Omni.Pool:Acquire("ItemButton")
        else
            btn = Omni.ItemButton:Create(scrollChild)
        end

        if btn then
            btn:SetParent(scrollChild)

            local col = ((i - 1) % columns)
            local row = math.floor((i - 1) / columns)
            local x = ITEM_SPACING + col * (ITEM_SIZE + ITEM_SPACING)
            local y = -(ITEM_SPACING + row * (ITEM_SIZE + ITEM_SPACING))

            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, y)

            Omni.ItemButton:SetItem(btn, itemInfo)
            btn:Show()

            table.insert(itemButtons, btn)
        end
    end
end

-- =============================================================================
-- Flow View Rendering (Category Sections)
-- =============================================================================

function Frame:RenderFlowView(items)
    if not mainFrame or not mainFrame.scrollChild then return end

    local scrollChild = mainFrame.scrollChild

    -- Group by category
    local categories = {}
    local categoryOrder = {}

    for _, item in ipairs(items) do
        local cat = item.category or "Miscellaneous"
        if not categories[cat] then
            categories[cat] = {}
            table.insert(categoryOrder, cat)
        end
        table.insert(categories[cat], item)
    end

    -- Sort categories by priority
    if Omni.Categorizer then
        table.sort(categoryOrder, function(a, b)
            local infoA = Omni.Categorizer:GetCategoryInfo(a)
            local infoB = Omni.Categorizer:GetCategoryInfo(b)
            return (infoA.priority or 99) < (infoB.priority or 99)
        end)
    end

    -- Release existing buttons
    if Omni.Pool then
        for _, btn in ipairs(itemButtons) do
            Omni.Pool:Release("ItemButton", btn)
        end
    end
    itemButtons = {}

    -- Layout
    local contentWidth = mainFrame.content:GetWidth() - 20
    local columns = math.floor(contentWidth / (ITEM_SIZE + ITEM_SPACING))
    columns = math.max(columns, 1)

    local yOffset = -ITEM_SPACING
    local HEADER_HEIGHT = 20

    for _, catName in ipairs(categoryOrder) do
        local catItems = categories[catName]
        if catItems and #catItems > 0 then
            -- Category header
            local header = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", ITEM_SPACING, yOffset)

            local r, g, b = 1, 1, 1
            if Omni.Categorizer then
                r, g, b = Omni.Categorizer:GetCategoryColor(catName)
            end
            header:SetTextColor(r, g, b)
            header:SetText(catName .. " (" .. #catItems .. ")")

            yOffset = yOffset - HEADER_HEIGHT

            -- Items in this category
            for i, itemInfo in ipairs(catItems) do
                local btn
                if Omni.Pool then
                    btn = Omni.Pool:Acquire("ItemButton")
                else
                    btn = Omni.ItemButton:Create(scrollChild)
                end

                if btn then
                    btn:SetParent(scrollChild)

                    local col = ((i - 1) % columns)
                    local row = math.floor((i - 1) / columns)
                    local x = ITEM_SPACING + col * (ITEM_SIZE + ITEM_SPACING)
                    local y = yOffset - row * (ITEM_SIZE + ITEM_SPACING)

                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, y)

                    Omni.ItemButton:SetItem(btn, itemInfo)
                    btn:Show()

                    table.insert(itemButtons, btn)
                end
            end

            local catRows = math.ceil(#catItems / columns)
            yOffset = yOffset - (catRows * (ITEM_SIZE + ITEM_SPACING)) - ITEM_SPACING
        end
    end

    scrollChild:SetHeight(math.abs(yOffset) + ITEM_SPACING)
end

-- =============================================================================
-- Search
-- =============================================================================

function Frame:ApplySearch(text)
    searchText = text or ""
    isSearchActive = (searchText ~= "")

    if not isSearchActive then
        -- Clear search - show all
        for _, btn in ipairs(itemButtons) do
            Omni.ItemButton:ClearSearch(btn)
        end
        return
    end

    local lowerSearch = string.lower(searchText)

    for _, btn in ipairs(itemButtons) do
        local itemInfo = btn.itemInfo
        local isMatch = false

        if itemInfo and itemInfo.hyperlink then
            local name = GetItemInfo(itemInfo.hyperlink)
            if name and string.find(string.lower(name), lowerSearch, 1, true) then
                isMatch = true
            end
        end

        Omni.ItemButton:SetSearchMatch(btn, isMatch)
    end
end

-- =============================================================================
-- Footer Updates
-- =============================================================================

function Frame:UpdateSlotCount()
    if not mainFrame or not mainFrame.footer then return end

    local free, total = 0, 0
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID)
        local numFree = GetContainerNumFreeSlots(bagID)
        total = total + numSlots
        free = free + numFree
    end

    local used = total - free
    mainFrame.footer.slots:SetText(string.format("%d/%d", used, total))
end

function Frame:UpdateMoney()
    if not mainFrame or not mainFrame.footer then return end

    local money = GetMoney() or 0
    local gold = math.floor(money / 10000)
    local silver = math.floor((money % 10000) / 100)
    local copper = money % 100

    mainFrame.footer.money:SetText(string.format("%dg %ds %dc", gold, silver, copper))
end

-- =============================================================================
-- Show/Hide/Toggle
-- =============================================================================

function Frame:Show()
    if not mainFrame then
        self:CreateMainFrame()
        self:LoadPosition()
    end

    mainFrame:Show()
    self:UpdateLayout()
end

function Frame:Hide()
    if mainFrame then
        mainFrame:Hide()
    end
end

function Frame:Toggle()
    if mainFrame and mainFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function Frame:IsShown()
    return mainFrame and mainFrame:IsShown()
end

-- =============================================================================
-- Initialization
-- =============================================================================

function Frame:Init()
    -- Frame is created on first show
end

print("|cFF00FF00OmniInventory|r: Frame loaded")
