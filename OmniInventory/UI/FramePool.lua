-- =============================================================================
-- OmniInventory UI/FramePool.lua
-- Typed Object Frame Pools & Dummy Parent Bag Frame Factory with Combat Lockdown Safeguards
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or _G.OmniInventory or _G.Omni

local FramePool = {
    itemButtons = { heap = {}, actives = {} },
    sections    = { heap = {}, actives = {} },
    rows        = { heap = {}, actives = {} },
    dummyBags   = {},
    createdButtonCount = 0,
    createdSectionCount = 0,
    createdRowCount = 0,
    isInitialized = false,
}
Omni.FramePool = FramePool

-- Pre-spawn Pool Target Constants
local PRESPAWN_ITEM_BUTTONS = 120
local PRESPAWN_SECTIONS     = 30
local PRESPAWN_ROWS         = 40

--- Helper to safely check combat status
local function IsCombat()
    if Omni.Compat and Omni.Compat.IsCombat then
        return Omni.Compat.IsCombat()
    end
    return InCombatLockdown and InCombatLockdown()
end

--- Returns or creates a dummy frame with ID set to container bag index
-- @param parent Parent frame (or UIParent)
-- @param bagID Bag container integer ID (e.g. 0 to 4, -1 for bank)
-- @return Dummy bag frame object
function FramePool:GetDummyBag(parent, bagID)
    if not bagID then return nil end
    parent = parent or UIParent

    if not self.dummyBags[bagID] then
        if IsCombat() then
            -- Guard against creating frame in combat
            return nil
        end
        local f = CreateFrame("Frame", "OmniInventoryDummyBag" .. bagID, parent)
        f:SetID(bagID)
        self.dummyBags[bagID] = f
    end

    local dummy = self.dummyBags[bagID]
    if dummy:GetParent() ~= parent and not IsCombat() then
        dummy:SetParent(parent)
    end
    return dummy
end

--- Internal button factory for ContainerFrameItemButtonTemplate
local function CreateNewItemButton(id)
    local buttonName = "OmniInventoryItemButton" .. id
    local button = CreateFrame("Button", buttonName, nil, "ContainerFrameItemButtonTemplate")
    button:SetID(0)
    button.isOmniPooled = true
    if Omni.ItemButton and type(Omni.ItemButton.Decorate) == "function" then
        Omni.ItemButton.Decorate(button)
    end
    return button
end

--- Internal section frame factory
local function CreateNewSectionFrame(id)
    local sectionName = "OmniInventorySection" .. id
    local f = CreateFrame("Frame", sectionName, UIParent)
    f:SetSize(200, 40)
    
    -- Section Title Header Text
    local header = f:CreateFontString(sectionName .. "Header", "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -2)
    header:SetJustifyH("LEFT")
    header:SetText("Category")
    f.headerText = header

    -- Section Hairline Divider
    local line = f:CreateTexture(sectionName .. "Divider", "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, 0)
    line:SetTexture(0.941, 0.910, 0.824, 0.15)
    f.divider = line

    f.buttons = {}
    f.isOmniPooled = true
    return f
end

--- Internal row frame factory for List Mode
local function CreateNewRowFrame(id)
    local rowName = "OmniInventoryListRow" .. id
    local f = CreateFrame("Button", rowName, UIParent)
    f:SetSize(400, 24)

    -- Item Icon
    local icon = f:CreateTexture(rowName .. "Icon", "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", f, "LEFT", 4, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    f.icon = icon

    -- Item Name Label
    local nameText = f:CreateFontString(rowName .. "Name", "OVERLAY", "GameFontHighlightSmall")
    nameText:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetText("Item Name")
    f.nameText = nameText

    -- Item Stack Count / Details Label
    local countText = f:CreateFontString(rowName .. "Count", "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    countText:SetJustifyH("RIGHT")
    countText:SetText("")
    f.countText = countText

    f.isOmniPooled = true
    return f
end

--- Pre-spawns pooled frames during PLAYER_LOGIN before combat triggers
function FramePool:PreloadPools()
    if self.isInitialized or IsCombat() then return end

    -- Pre-spawn 120 item buttons
    for i = 1, PRESPAWN_ITEM_BUTTONS do
        self.createdButtonCount = self.createdButtonCount + 1
        local btn = CreateNewItemButton(self.createdButtonCount)
        btn:Hide()
        table.insert(self.itemButtons.heap, btn)
    end

    -- Pre-spawn 30 section frames
    for i = 1, PRESPAWN_SECTIONS do
        self.createdSectionCount = self.createdSectionCount + 1
        local sec = CreateNewSectionFrame(self.createdSectionCount)
        sec:Hide()
        table.insert(self.sections.heap, sec)
    end

    -- Pre-spawn 40 list row frames
    for i = 1, PRESPAWN_ROWS do
        self.createdRowCount = self.createdRowCount + 1
        local row = CreateNewRowFrame(self.createdRowCount)
        row:Hide()
        table.insert(self.rows.heap, row)
    end

    self.isInitialized = true
end

--- Acquires an ItemButton frame from the pool safely
-- @param parentFrame Parent UI container frame
-- @param bagID Virtual or physical bag ID
-- @param slotID Container slot ID
-- @return ItemButton frame object, or nil if unavailable during combat
function FramePool:AcquireItemButton(parentFrame, bagID, slotID)
    local button = table.remove(self.itemButtons.heap)

    if not button then
        if IsCombat() then
            -- Guard against CreateFrame during active combat lockdown
            return nil
        end
        self.createdButtonCount = self.createdButtonCount + 1
        button = CreateNewItemButton(self.createdButtonCount)
    end

    if Omni.ItemButton and type(Omni.ItemButton.Decorate) == "function" then
        Omni.ItemButton.Decorate(button)
    end

    if bagID then
        local dummyBag = self:GetDummyBag(parentFrame, bagID)
        if dummyBag and not IsCombat() then
            button:SetParent(dummyBag)
        end
    elseif parentFrame and not IsCombat() then
        button:SetParent(parentFrame)
    end

    button:SetID(slotID or 0)
    button.bagID = bagID
    button.slotID = slotID

    self.itemButtons.actives[button] = true
    return button
end

--- Releases an ItemButton frame back to the heap pool
-- @param button ItemButton frame object
function FramePool:ReleaseItemButton(button)
    if not button or not self.itemButtons.actives[button] then return end

    button:Hide()
    button:ClearAllPoints()
    if not IsCombat() then
        button:SetParent(nil)
    end
    button.bagID = nil
    button.slotID = nil
    button.itemLink = nil

    self.itemButtons.actives[button] = nil
    table.insert(self.itemButtons.heap, button)
end

--- Acquires a Section frame from pool
-- @param parentFrame Container frame
-- @param categoryID ID of category
-- @param name Title of category
-- @return Section frame object, or nil if unavailable during combat
function FramePool:AcquireSection(parentFrame, categoryID, name)
    local section = table.remove(self.sections.heap)

    if not section then
        if IsCombat() then
            return nil
        end
        self.createdSectionCount = self.createdSectionCount + 1
        section = CreateNewSectionFrame(self.createdSectionCount)
    end

    if parentFrame and not IsCombat() then
        section:SetParent(parentFrame)
    end

    section.categoryID = categoryID
    section.categoryName = name
    if section.headerText then
        section.headerText:SetText(name or "Category")
    end
    table.wipe(section.buttons)

    self.sections.actives[section] = true
    return section
end

--- Releases a Section frame back to pool
-- @param section Section frame object
function FramePool:ReleaseSection(section)
    if not section or not self.sections.actives[section] then return end

    section:Hide()
    section:ClearAllPoints()
    if not IsCombat() then
        section:SetParent(nil)
    end
    section.categoryID = nil
    section.categoryName = nil
    table.wipe(section.buttons)

    self.sections.actives[section] = nil
    table.insert(self.sections.heap, section)
end

--- Acquires a List Row frame from pool
-- @param parentFrame Master container content frame
-- @param rowIndex Index of row
-- @return Row frame object, or nil if unavailable during combat
function FramePool:AcquireRow(parentFrame, rowIndex)
    local row = table.remove(self.rows.heap)

    if not row then
        if IsCombat() then
            return nil
        end
        self.createdRowCount = self.createdRowCount + 1
        row = CreateNewRowFrame(self.createdRowCount)
    end

    if parentFrame and not IsCombat() then
        row:SetParent(parentFrame)
    end

    row.rowIndex = rowIndex
    self.rows.actives[row] = true
    return row
end

--- Releases a List Row frame back to pool
-- @param row Row frame object
function FramePool:ReleaseRow(row)
    if not row or not self.rows.actives[row] then return end

    row:Hide()
    row:ClearAllPoints()
    if not IsCombat() then
        row:SetParent(nil)
    end
    row.rowIndex = nil

    self.rows.actives[row] = nil
    table.insert(self.rows.heap, row)
end

--- Releases all active frames across all pools
function FramePool:ReleaseAll()
    for button in pairs(self.itemButtons.actives) do
        self:ReleaseItemButton(button)
    end
    for section in pairs(self.sections.actives) do
        self:ReleaseSection(section)
    end
    for row in pairs(self.rows.actives) do
        self:ReleaseRow(row)
    end
end

--- Returns pool statistics for debugging and memory auditing
function FramePool:GetStats()
    local activeBtnCount = 0
    for _ in pairs(self.itemButtons.actives) do activeBtnCount = activeBtnCount + 1 end
    
    local activeSecCount = 0
    for _ in pairs(self.sections.actives) do activeSecCount = activeSecCount + 1 end

    local activeRowCount = 0
    for _ in pairs(self.rows.actives) do activeRowCount = activeRowCount + 1 end

    return {
        itemButtons = { total = self.createdButtonCount, heap = #self.itemButtons.heap, active = activeBtnCount },
        sections    = { total = self.createdSectionCount, heap = #self.sections.heap, active = activeSecCount },
        rows        = { total = self.createdRowCount, heap = #self.rows.heap, active = activeRowCount },
    }
end

-- Event Listener Frame for Pre-spawns on PLAYER_LOGIN
local poolEventFrame = CreateFrame("Frame", "OmniInventoryFramePoolEvent", UIParent)
poolEventFrame:RegisterEvent("PLAYER_LOGIN")
poolEventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        FramePool:PreloadPools()
    end
end)

return FramePool
