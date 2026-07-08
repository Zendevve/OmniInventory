-- =============================================================================
-- OmniInventory Bank Frame
-- =============================================================================
-- Standalone bank window that docks to the left of the main bag frame
-- whenever BANKFRAME_OPENED fires. Closes on BANKFRAME_CLOSED.
-- =============================================================================

local addonName, Omni = ...

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
    local isOfflineBank = not (Omni.Features and Omni.Features:IsAtBank())
    if (viewedChar and viewedChar ~= Omni.Data.playerName) or isOfflineBank then
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
    local isOfflineBank = not (Omni.Features and Omni.Features:IsAtBank())
    if (viewedChar and viewedChar ~= Omni.Data.playerName) or isOfflineBank then
        local info = OmniC_Container.GetContainerItemInfo(bagID, slotID)
        return info and info.hyperlink
    end
    return orig_GetContainerItemLink(bagID, slotID)
end

Omni.BankFrame = {}
local BankFrame = Omni.BankFrame

-- =============================================================================
-- Constants
-- =============================================================================

local FRAME_MIN_WIDTH = 350
local FRAME_MIN_HEIGHT = 300
local FRAME_DEFAULT_WIDTH = 450
local FRAME_DEFAULT_HEIGHT = 500
local HEADER_HEIGHT = 24
local FOOTER_HEIGHT = 24
local SEARCH_HEIGHT = 24
local PADDING = 8
local ITEM_SIZE = 37
local ITEM_SPACING = 4
local FRAME_GAP = 6
local BAG_ICON_SIZE = 18
local RIBBON_GAP = 3
local RIBBON_SEP_GAP = 5
local RIBBON_ICON_BTN_SIZE = 20
local SETTINGS_ICON = "Interface\\Icons\\Trade_Engineering"
local BANK_BAG_IDS = { 5, 6, 7, 8, 9, 10, 11 }

-- =============================================================================
-- State
-- =============================================================================

local bankFrame = nil
local itemButtons = {}
local categoryHeaders = {}
local listRows = {}
local searchText = ""
local isSearchActive = false
local selectedBankBagID = nil
local currentBankView = "flow"
local bankForceEmptyFrame = nil
local bankForceEmptyJob = nil
local BANK_FORCE_EMPTY_EVENT_TIMEOUT = 0.35
local BANK_FORCE_EMPTY_MAX_LOCK = 20
local BANK_FORCE_EMPTY_MAX_MOVE = 6

-- =============================================================================
-- Helpers
-- =============================================================================

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function SetButtonItem(btn, itemInfo)
    if not btn then return end
    if Omni.ItemButton and Omni.ItemButton.SetItem then
        Omni.ItemButton:SetItem(btn, itemInfo)
    end
end

local function GetSharedItemScale()
    if Omni.Data and Omni.Data.GetFrameSetting then
        return Omni.Data:GetFrameSetting("bank", "itemScale", 1.0)
    end
    if Omni.Frame and Omni.Frame.GetItemScale then
        return Omni.Frame:GetItemScale()
    end
    return 1
end

local function GetSharedItemGap()
    if Omni.Data and Omni.Data.GetFrameSetting then
        return Omni.Data:GetFrameSetting("bank", "itemGap", ITEM_SPACING)
    end
    if Omni.Frame and Omni.Frame.GetItemGap then
        return Omni.Frame:GetItemGap()
    end
    return ITEM_SPACING
end

local function ApplyBankItemMetrics(btn, itemSize)
    if not btn then return end
    pcall(function()
        btn:SetScale(1)
        btn:SetSize(itemSize, itemSize)
        if btn.glow then
            btn.glow:SetSize(itemSize * 1.5, itemSize * 1.5)
        end
    end)
end

local function GetBankContentWidth()
    if not bankFrame or not bankFrame.content then
        return FRAME_DEFAULT_WIDTH
    end

    local width = bankFrame.content:GetWidth() or 0
    local left = bankFrame.content.GetLeft and bankFrame.content:GetLeft() or nil
    local right = bankFrame.content.GetRight and bankFrame.content:GetRight() or nil
    if right and left and right > left then
        width = right - left
    end
    return math.max(width, 1)
end

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

local function GetPurchasedBankSlotsCount()
    local viewedChar = Omni.Data and Omni.Data.currentViewedChar
    local targetChar = (viewedChar and viewedChar ~= Omni.Data.playerName) and viewedChar or Omni.Data.playerName
    local isOfflineBank = not (Omni.Features and Omni.Features:IsAtBank())
    if (viewedChar and viewedChar ~= Omni.Data.playerName) or isOfflineBank then
        local realmName = GetRealmName()
        local realm = OmniInventoryDB and OmniInventoryDB.realm and OmniInventoryDB.realm[realmName]
        local charData = realm and realm[targetChar]
        return charData and charData.bankSlots or 0
    end
    return (GetNumBankSlots and GetNumBankSlots()) or 0
end

local function IsValidBankBagID(bagID)
    if bagID == nil then return false end
    if bagID == -1 then return true end
    if type(bagID) == "number" and bagID >= 5 and bagID <= 11 then
        local idx = bagID - 4
        local numPurchased = GetPurchasedBankSlotsCount()
        return idx <= numPurchased
    end
    return false
end

local function GetSavedBankBagFilter()
    local settings = OmniInventoryDB and OmniInventoryDB.char and OmniInventoryDB.char.settings
    local id = settings and settings.selectedBankBagID
    if id == nil then return nil end
    if IsValidBankBagID(id) then
        return id
    end
    return nil
end

local function GetBagDisplayName(bagID)
    if bagID == 0 then
        return BACKPACK_CONTAINER or "Backpack"
    elseif bagID == -1 then
        return "Bank"
    elseif bagID == -2 then
        return KEYRING or "Keyring"
    elseif bagID and bagID >= 1 and bagID <= 11 then
        local name = GetBagName(bagID)
        if name and name ~= "" then
            return name
        end
        return string.format("Bag %d", bagID)
    end
    return tostring(bagID or "")
end

local function NormalizeBankView(mode)
    if mode == "grid" or mode == "flow" or mode == "list" or mode == "bag" then
        return mode
    end
    return "flow"
end

local function GetSavedBankView()
    local settings = OmniInventoryDB and OmniInventoryDB.char and OmniInventoryDB.char.settings
    return NormalizeBankView(settings and settings.bankViewMode)
end

local VIEW_LABELS = {
    grid = "Grid",
    flow = "Flow",
    list = "List",
    bag = "Bag",
}

function BankFrame:UpdateViewButton()
    if bankFrame and bankFrame.header and bankFrame.header.viewBtn then
        local displayMode = VIEW_LABELS[currentBankView] or "Flow"
        bankFrame.header.viewBtn.text:SetText(displayMode)
    end
end

local function GetBankBagIconTexture(bagID)
    local viewedChar = Omni.Data and Omni.Data.currentViewedChar
    local isOfflineBank = not (Omni.Features and Omni.Features:IsAtBank())
    if (viewedChar and viewedChar ~= Omni.Data.playerName) or isOfflineBank then
        if not (viewedChar and viewedChar ~= Omni.Data.playerName) then
            local inv = ContainerIDToInventoryID and ContainerIDToInventoryID(bagID)
            local tex = inv and GetInventoryItemTexture("player", inv)
            if tex then return tex end
        end
        return "Interface\\Icons\\INV_Misc_Bag_10_Blue"
    end
    local inv = ContainerIDToInventoryID and ContainerIDToInventoryID(bagID)
    local tex = inv and GetInventoryItemTexture("player", inv)
    return tex or "Interface\\Icons\\INV_Misc_Bag_10_Blue"
end

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

local function CreateRibbonIconButton(parent, iconTexture, tooltipTitle, tooltipSub, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(RIBBON_ICON_BTN_SIZE, RIBBON_ICON_BTN_SIZE)
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

local function CreateRibbonTextButton(parent, text, tooltipTitle, tooltipSub, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(46, RIBBON_ICON_BTN_SIZE)
    StyleRibbonButton(btn)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text)

    btn._tooltipTitle = tooltipTitle
    btn._tooltipSub = tooltipSub
    btn:SetScript("OnClick", onClick)
    return btn
end

local function BankBagSlotIndex(bagID)
    return bagID - 4
end

local function BankBagSlotsMax()
    return NUM_BANKBAGSLOTS or 7
end

local function HandleUnpurchasedBankBagClick(bagID)
    local viewedChar = Omni.Data and Omni.Data.currentViewedChar
    local isOfflineBank = not (Omni.Features and Omni.Features:IsAtBank())
    if (viewedChar and viewedChar ~= Omni.Data.playerName) or isOfflineBank then
        return true
    end
    local slotIndex = BankBagSlotIndex(bagID)
    local numSlots, full = GetNumBankSlots()
    numSlots = numSlots or 0
    if slotIndex <= numSlots then
        return false
    end
    if full or numSlots >= BankBagSlotsMax() then
        return true
    end
    if slotIndex ~= numSlots + 1 then
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage("Purchase bank bag slots in order.", 1, 0.1, 0.1, 1)
        end
        return true
    end
    local cost = GetBankSlotCost and GetBankSlotCost(numSlots)
    if not cost then
        return true
    end
    local bf = _G.BankFrame
    if bf then
        bf.nextSlotCost = cost
    end
    if PlaySound then
        PlaySound("igMainMenuOption")
    end
    StaticPopup_Show("CONFIRM_BUY_BANK_SLOT")
    return true
end

local function SavePosition()
    if not bankFrame then return end
    local point, _, _, x, y = bankFrame:GetPoint()
    local width, height = bankFrame:GetSize()
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.char = OmniInventoryDB.char or {}
    OmniInventoryDB.char.bankPosition = {
        point = point,
        x = x,
        y = y,
        width = width,
        height = height,
        userMoved = bankFrame.userMoved,
    }
end

local function LoadPosition()
    if not bankFrame then return end
    local pos = OmniInventoryDB and OmniInventoryDB.char and OmniInventoryDB.char.bankPosition
    if not pos then return end

    if pos.width and pos.height then
        bankFrame:SetSize(pos.width, pos.height)
    end
    if pos.userMoved then
        bankFrame.userMoved = true
        bankFrame:ClearAllPoints()
        bankFrame:SetPoint(pos.point or "CENTER", UIParent,
            pos.point or "CENTER", pos.x or 0, pos.y or 0)
    end
end

-- Anchor to the left of the main bag frame if available
local function AnchorToMainFrame()
    if not bankFrame then return end
    if bankFrame.userMoved then return end

    local main = _G.OmniInventoryFrame
    if main and main:IsShown() then
        bankFrame:ClearAllPoints()
        bankFrame:SetPoint("TOPRIGHT", main, "TOPLEFT", -FRAME_GAP, 0)
    else
        bankFrame:ClearAllPoints()
        bankFrame:SetPoint("CENTER", UIParent, "CENTER", -250, 0)
    end
end

-- =============================================================================
-- Frame Construction
-- =============================================================================

local function CreateHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", PADDING, -PADDING)
    header:SetPoint("TOPRIGHT", -PADDING, -PADDING)

    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    header.bg:SetVertexColor(0.15, 0.15, 0.15, 1)

    local titleBtn = CreateFrame("Button", nil, header)
    titleBtn:SetHeight(16)
    titleBtn:SetPoint("LEFT", 6, 0)
    
    local titleText = titleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", 0, 0)
    titleText:SetText("|cFF00FF00Omni|r Bank")
    titleBtn:SetFontString(titleText)
    titleBtn.text = titleText

    titleBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("OmniInventory Characters", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click to select another character's bank to view offline.", 1, 1, 1, true)
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
    header.closeBtn:SetScript("OnClick", function()
        if CloseBankFrame then CloseBankFrame() end
        BankFrame:Hide()
    end)

    header.optBtn = CreateRibbonIconButton(header, SETTINGS_ICON,
        "Settings", "Open the OmniInventory settings panel",
        function()
            if Omni.Settings then
                Omni.Settings:Toggle()
            else
                print("|cFF00FF00OmniInventory|r: Settings not loaded")
            end
        end)
    header.optBtn:SetPoint("RIGHT", header.closeBtn, "LEFT", -RIBBON_GAP, 0)

    header.viewBtn = CreateRibbonTextButton(header, "Flow",
        "View Mode", "Click to cycle bank view modes (Grid / Flow / List / Bag)",
        function() BankFrame:CycleView() end)
    header.viewBtn:SetPoint("RIGHT", header.optBtn, "LEFT", -RIBBON_GAP, 0)

    header.sortBtn = CreateRibbonTextButton(header, "Sort",
        "Sort Mode", "Click to cycle the active sort",
        function() BankFrame:CycleSort() end)
    header.sortBtn:SetPoint("RIGHT", header.viewBtn, "LEFT", -RIBBON_GAP, 0)

    header.sortBtn:HookScript("OnEnter", function(self)
        local mode = Omni.Sorter and Omni.Sorter:GetDefaultMode() or "category"
        self._tooltipSub = "Current: " .. mode
    end)

    local initMode = Omni.Sorter and Omni.Sorter:GetDefaultMode() or "category"
    local initDisplay = initMode:gsub("^%l", string.upper)
    header.sortBtn.text:SetText(initDisplay)

    header.ribbonSep = header:CreateTexture(nil, "OVERLAY")
    header.ribbonSep:SetTexture("Interface\\Buttons\\WHITE8X8")
    header.ribbonSep:SetVertexColor(0.35, 0.35, 0.35, 1)
    header.ribbonSep:SetSize(1, 14)
    header.ribbonSep:SetPoint("RIGHT", header.sortBtn, "LEFT", -RIBBON_SEP_GAP, 0)

    header.bagBar = CreateFrame("Frame", nil, header)
    header.bagBar:SetSize((BAG_ICON_SIZE + 2) * #BANK_BAG_IDS, BAG_ICON_SIZE)
    header.bagBar:SetPoint("RIGHT", header.ribbonSep, "LEFT", -RIBBON_SEP_GAP, 0)

    header.bagButtons = {}
    for index, bagID in ipairs(BANK_BAG_IDS) do
        local bagBtn = CreateFrame("Button", nil, header.bagBar)
        bagBtn:SetSize(BAG_ICON_SIZE, BAG_ICON_SIZE)
        bagBtn:SetPoint("LEFT", (index - 1) * (BAG_ICON_SIZE + 2), 0)
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
                if CursorHasItem and CursorHasItem() then
                    BankFrame:EquipBankBagFromCursor(self.bagID)
                    return
                end
                if HandleUnpurchasedBankBagClick(self.bagID) then
                    return
                end
                BankFrame:ToggleBankBagPreview(self.bagID)
            elseif mouseButton == "RightButton" then
                BankFrame:ForceEmptyBankBag(self.bagID)
            end
        end)
        bagBtn:SetScript("OnReceiveDrag", function(self)
            BankFrame:EquipBankBagFromCursor(self.bagID)
        end)
        bagBtn:SetScript("OnEnter", function(self)
            local slotIndex = BankBagSlotIndex(self.bagID)
            local viewedChar = Omni.Data and Omni.Data.currentViewedChar
            local isOfflineBank = not (Omni.Features and Omni.Features:IsAtBank())
            local isOffline = (viewedChar and viewedChar ~= Omni.Data.playerName) or isOfflineBank

            local numPurchased, bankBagsFull
            if isOffline then
                numPurchased = GetPurchasedBankSlotsCount()
                bankBagsFull = numPurchased >= BankBagSlotsMax()
            else
                numPurchased, bankBagsFull = GetNumBankSlots()
            end
            numPurchased = numPurchased or 0
            local nextToBuy = (not isOffline) and (not bankBagsFull) and numPurchased < BankBagSlotsMax()
                and (slotIndex == numPurchased + 1)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            if slotIndex > numPurchased then
                GameTooltip:AddLine(BANK_BAG_PURCHASE or "Purchase this bank slot", 1, 0.2, 0.2)
                if isOffline then
                    GameTooltip:AddLine("Not purchased (Offline View)", 0.75, 0.75, 0.75)
                elseif nextToBuy then
                    GameTooltip:AddLine("Left-click: Purchase this slot (gold confirmation)", 0.8, 0.8, 0.8)
                elseif not bankBagsFull then
                    GameTooltip:AddLine("Buy earlier bank bag slots first.", 0.75, 0.75, 0.75)
                end
            else
                local name = GetBagName and GetBagName(self.bagID) or ("Bank bag " .. tostring(slotIndex))
                local slots = GetContainerNumSlots(self.bagID) or 0
                if slots > 0 and name and name ~= "" then
                    GameTooltip:AddLine(name, 1, 1, 1)
                else
                    GameTooltip:AddLine("Empty bank bag slot " .. tostring(slotIndex), 1, 1, 1)
                end
                if isOffline then
                    GameTooltip:AddLine("Left-click: Show only this bank section", 0.8, 0.8, 0.8)
                    GameTooltip:AddLine("Left-click (again): Show all bank slots", 0.8, 0.8, 0.8)
                else
                    GameTooltip:AddLine("Left-click: Show only this bank section", 0.8, 0.8, 0.8)
                    GameTooltip:AddLine("Left-click (again): Show all bank slots", 0.8, 0.8, 0.8)
                    GameTooltip:AddLine("Drag a bag here to equip in this slot", 0.6, 0.9, 0.6)
                    GameTooltip:AddLine("Right-click: Move items to other bank space", 0.8, 0.8, 0.8)
                end
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
        parent:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        parent:StopMovingOrSizing()
        parent.userMoved = true
        SavePosition()
    end)

    parent.header = header
    return header
end

local function CreateSearchBar(parent)
    local searchBar = CreateFrame("Frame", nil, parent)
    searchBar:SetHeight(SEARCH_HEIGHT)
    searchBar:SetPoint("TOPLEFT", parent.header, "BOTTOMLEFT", 0, -4)
    searchBar:SetPoint("TOPRIGHT", parent.header, "BOTTOMRIGHT", 0, -4)

    searchBar.bg = searchBar:CreateTexture(nil, "BACKGROUND")
    searchBar.bg:SetAllPoints()
    searchBar.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    searchBar.bg:SetVertexColor(0.1, 0.1, 0.1, 1)

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

    searchBar.editBox = CreateFrame("EditBox", "OmniBankSearchBox", searchBar)
    searchBar.editBox:SetPoint("LEFT", searchBar.icon, "RIGHT", 4, 0)
    searchBar.editBox:SetPoint("RIGHT", clearBtn, "LEFT", -4, 0)
    searchBar.editBox:SetHeight(18)
    searchBar.editBox:SetAutoFocus(false)
    searchBar.editBox:SetFontObject(ChatFontNormal)
    searchBar.editBox:SetTextColor(1, 1, 1, 1)
    searchBar.editBox:SetTextInsets(2, 2, 0, 0)

    clearBtn:SetScript("OnClick", function()
        searchBar.editBox:SetText("")
        searchBar.editBox:ClearFocus()
    end)

    searchBar.editBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText() or ""
        isSearchActive = (searchText ~= "")
        if BankFrame and BankFrame.UpdateLayout then
            BankFrame:UpdateLayout()
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

    parent.searchBar = searchBar
    parent.searchBox = searchBar.editBox
    searchBar.clearBtn = clearBtn
    searchBar.helpBtn = helpBtn
    return searchBar
end

local function CreateContentArea(parent)
    local content = CreateFrame("ScrollFrame", "OmniBankContentScroll", parent, "UIPanelScrollFrameTemplate")
    content:SetPoint("TOPLEFT", parent.searchBar, "BOTTOMLEFT", 0, -4)
    content:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -PADDING - 20, PADDING + FOOTER_HEIGHT + 4)

    local scrollChild = CreateFrame("Frame", "OmniBankContentChild", content)
    scrollChild:SetSize(content:GetWidth(), 1)
    content:SetScrollChild(scrollChild)

    local scrollBar = _G["OmniBankContentScrollScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 20, -16)
        scrollBar:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 20, 16)
    end

    -- Per-bag ItemContainer frames for the bank, mirroring the
    -- main bag's setup. ContainerFrameItemButton_OnClick reads bag from
    -- self:GetParent():GetID(), so each button must live under a parent
    -- whose SetID matches its bag (-1 main bank, 5..11 bank bags).
    parent.itemContainers = {}
    local function MakeItemContainer(bagID)
        local f = CreateFrame("Frame", nil, scrollChild)
        f:SetSize(1, 1)
        f:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        f:SetID(bagID)
        f:Show()
        parent.itemContainers[bagID] = f
        return f
    end
    MakeItemContainer(-1)
    for bagID = 5, 11 do
        MakeItemContainer(bagID)
    end
    parent._makeItemContainer = MakeItemContainer

    parent.content = content
    parent.scrollChild = scrollChild
end

local function GetBankItemContainer(bagID)
    if not bankFrame or not bankFrame.itemContainers then return nil end
    local container = bankFrame.itemContainers[bagID]
    if container then return container end
    if InCombatLockdown and InCombatLockdown() then return nil end
    if bankFrame._makeItemContainer then
        return bankFrame._makeItemContainer(bagID)
    end
    return nil
end

local function CreateFooter(parent)
    local footer = CreateFrame("Frame", nil, parent)
    footer:SetHeight(FOOTER_HEIGHT)
    footer:SetPoint("BOTTOMLEFT", PADDING, PADDING)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)

    footer.bg = footer:CreateTexture(nil, "BACKGROUND")
    footer.bg:SetAllPoints()
    footer.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    footer.bg:SetVertexColor(0.12, 0.12, 0.12, 1)

    footer.slots = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footer.slots:SetPoint("LEFT", 6, 0)
    footer.slots:SetText("0/0")

    footer.note = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footer.note:SetPoint("RIGHT", -6, 0)
    footer.note:SetTextColor(0.6, 0.6, 0.6)
    footer.note:SetText("Bank")

    parent.footer = footer
end

local function CreateResizeHandle(parent)
    local handle = CreateFrame("Button", nil, parent)
    handle:SetSize(16, 16)
    handle:SetPoint("BOTTOMRIGHT", -2, 2)
    handle:EnableMouse(true)

    handle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    handle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    handle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    handle:SetScript("OnMouseDown", function()
        parent:StartSizing("BOTTOMRIGHT")
    end)
    handle:SetScript("OnMouseUp", function()
        parent:StopMovingOrSizing()
        SavePosition()
        BankFrame:UpdateLayout()
    end)

    parent.resizeHandle = handle
end

function BankFrame:CreateMainFrame()
    if bankFrame then return bankFrame end

    bankFrame = CreateFrame("Frame", "OmniInventoryBankFrame", UIParent)
    bankFrame:SetSize(FRAME_DEFAULT_WIDTH, FRAME_DEFAULT_HEIGHT)
    bankFrame:SetPoint("CENTER")
    bankFrame:SetFrameStrata("HIGH")
    bankFrame:SetFrameLevel(100)
    bankFrame:EnableMouse(true)
    bankFrame:SetMovable(true)
    bankFrame:SetResizable(true)
    bankFrame:SetClampedToScreen(true)
    bankFrame:SetMinResize(FRAME_MIN_WIDTH, FRAME_MIN_HEIGHT)

    bankFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bankFrame:SetBackdropColor(0.05, 0.09, 0.08, 0.95)
    bankFrame:SetBackdropBorderColor(0.3, 0.55, 0.45, 1)

    local scale = BankFrame:GetScale()
    bankFrame:SetScale(scale or 1)

    tinsert(UISpecialFrames, "OmniInventoryBankFrame")

    CreateHeader(bankFrame)
    CreateSearchBar(bankFrame)
    CreateContentArea(bankFrame)
    CreateFooter(bankFrame)
    CreateResizeHandle(bankFrame)

    selectedBankBagID = GetSavedBankBagFilter()
    currentBankView = GetSavedBankView()
    BankFrame:UpdateViewButton()
    BankFrame:UpdateBankBagButtonVisuals()
    BankFrame:UpdateBankBagButtonIcons()

    bankFrame:Hide()

    bankFrame:SetScript("OnShow", function()
        AnchorToMainFrame()
        BankFrame:UpdateLayout()
    end)

    bankFrame:SetScript("OnHide", function()
        if CloseBankFrame then CloseBankFrame() end
    end)

    return bankFrame
end

-- =============================================================================
-- Rendering
-- =============================================================================

local function CollectBankItems()
    local perfCollect = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("bank.CollectBankItems.total")
    local items = {}
    if OmniC_Container and OmniC_Container.GetAllBankItems then
        items = OmniC_Container.GetAllBankItems() or {}
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

    if Omni.Categorizer then
        local perfCategorize = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("bank.CollectBankItems.categorize")
        for _, item in ipairs(items) do
            item.category = item.category or Omni.Categorizer:GetCategory(item)
        end
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("bank.CollectBankItems.categorize", perfCategorize)
        end
    end

    if Omni.Sorter then
        local perfSort = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("bank.CollectBankItems.sort")
        items = Omni.Sorter:Sort(items, Omni.Sorter:GetDefaultMode())
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("bank.CollectBankItems.sort", perfSort, { itemCount = #items })
        end
    end

    if IsValidBankBagID(selectedBankBagID) then
        local filtered = {}
        for _, item in ipairs(items) do
            if item.bagID == selectedBankBagID then
                table.insert(filtered, item)
            end
        end
        items = filtered
    end

    if Omni._perfEnabled and Omni.Perf then
        Omni.Perf:End("bank.CollectBankItems.total", perfCollect, { itemCount = #items })
    end
    return items
end

function BankFrame:SetBankBagFilter(bagID)
    if bagID ~= nil and not IsValidBankBagID(bagID) then
        return
    end
    selectedBankBagID = bagID
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.char = OmniInventoryDB.char or {}
    OmniInventoryDB.char.settings = OmniInventoryDB.char.settings or {}
    OmniInventoryDB.char.settings.selectedBankBagID = selectedBankBagID
    self:UpdateBankBagButtonVisuals()
    self:UpdateLayout()
end

function BankFrame:ToggleBankBagPreview(bagID)
    if not IsValidBankBagID(bagID) then return end
    if selectedBankBagID == bagID then
        self:SetBankBagFilter(nil)
    else
        self:SetBankBagFilter(bagID)
    end
end

function BankFrame:SetView(mode)
    currentBankView = NormalizeBankView(mode)

    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.char = OmniInventoryDB.char or {}
    OmniInventoryDB.char.settings = OmniInventoryDB.char.settings or {}
    OmniInventoryDB.char.settings.bankViewMode = currentBankView

    self:UpdateViewButton()
    self:UpdateLayout()
end

function BankFrame:CycleView()
    local modes = { "grid", "flow", "list", "bag" }
    local nextIdx = 1
    for i, mode in ipairs(modes) do
        if mode == currentBankView then
            nextIdx = (i % #modes) + 1
            break
        end
    end
    self:SetView(modes[nextIdx])
end

function BankFrame:UpdateSortButton()
    if bankFrame and bankFrame.header and bankFrame.header.sortBtn then
        local mode = Omni.Sorter and Omni.Sorter:GetDefaultMode() or "category"
        local displayMode = mode:gsub("^%l", string.upper)
        bankFrame.header.sortBtn.text:SetText(displayMode)
    end
end

function BankFrame:CycleSort()
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

    -- Update sort buttons on both frames
    self:UpdateSortButton()
    if Omni.Frame and Omni.Frame.UpdateSortButton then
        Omni.Frame:UpdateSortButton()
    elseif _G.OmniInventoryFrame and _G.OmniInventoryFrame.header and _G.OmniInventoryFrame.header.sortBtn then
        local displayMode = newMode:gsub("^%l", string.upper)
        _G.OmniInventoryFrame.header.sortBtn.text:SetText(displayMode)
    end

    -- Refresh layouts
    self:UpdateLayout()
    if Omni.Frame and Omni.Frame.UpdateLayout then
        Omni.Frame:UpdateLayout()
    end
end

function BankFrame:UpdateBankBagButtonIcons()
    if not bankFrame or not bankFrame.header or not bankFrame.header.bagButtons then
        return
    end
    local numPurchased = GetPurchasedBankSlotsCount()
    for _, bagID in ipairs(BANK_BAG_IDS) do
        local btn = bankFrame.header.bagButtons[bagID]
        if btn and btn.icon then
            btn.icon:SetTexture(GetBankBagIconTexture(bagID))
            local slotIndex = BankBagSlotIndex(bagID)
            local slots = GetContainerNumSlots(bagID) or 0
            local purchased = slotIndex <= numPurchased
            if btn.icon.SetVertexColor then
                if not purchased then
                    btn.icon:SetVertexColor(1, 0.15, 0.15)
                else
                    btn.icon:SetVertexColor(1, 1, 1)
                end
            end
            if btn.icon.SetDesaturated then
                local emptySocket = purchased and slots <= 0
                if not purchased or emptySocket then
                    btn.icon:SetDesaturated(1)
                else
                    btn.icon:SetDesaturated(0)
                end
            end
        end
    end
end

function BankFrame:UpdateBankBagButtonVisuals()
    if not bankFrame or not bankFrame.header or not bankFrame.header.bagButtons then
        return
    end
    for _, bagID in ipairs(BANK_BAG_IDS) do
        local btn = bankFrame.header.bagButtons[bagID]
        if btn then
            local r, g, b = 0.4, 0.4, 0.4
            if selectedBankBagID == bagID then
                r, g, b = 0.2, 0.8, 0.2
            end
            if btn.borderTop then btn.borderTop:SetVertexColor(r, g, b, 1) end
            if btn.borderBottom then btn.borderBottom:SetVertexColor(r, g, b, 1) end
            if btn.borderLeft then btn.borderLeft:SetVertexColor(r, g, b, 1) end
            if btn.borderRight then btn.borderRight:SetVertexColor(r, g, b, 1) end
        end
    end
end

function BankFrame:EquipBankBagFromCursor(bagID)
    if bagID == -1 then
        if ClearCursor then ClearCursor() end
        return
    end
    if not IsValidBankBagID(bagID) then
        if ClearCursor then ClearCursor() end
        return
    end
    local viewedChar = Omni.Data and Omni.Data.currentViewedChar
    local isOfflineBank = not (Omni.Features and Omni.Features:IsAtBank())
    if (viewedChar and viewedChar ~= Omni.Data.playerName) or isOfflineBank then
        if ClearCursor then ClearCursor() end
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        print("|cFF00FF00OmniInventory|r: Cannot change bank bags during combat.")
        return
    end
    if not (CursorHasItem and CursorHasItem()) then
        return
    end
    local inv = ContainerIDToInventoryID and ContainerIDToInventoryID(bagID)
    if not inv or not PutItemInBag then
        return
    end

    local targetHasBag = (GetContainerNumSlots(bagID) or 0) > 0
    if not targetHasBag then
        PutItemInBag(inv)
        return
    end

    local tempBagID, tempSlotID
    for _, bID in ipairs(BANK_BAG_IDS) do
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
        print("|cFF00FF00OmniInventory|r: No free bank slot available to perform bank bag swap.")
        return
    end

    PickupContainerItem(tempBagID, tempSlotID)
    BankFrame:StartBankBagSwap(tempBagID, tempSlotID, bagID)
end

local function CanBankSlotAcceptItem(bagID, itemFamily)
    local numFree, bagType = GetContainerNumFreeSlots(bagID)
    if not numFree or numFree <= 0 then
        return false
    end
    bagType = bagType or 0
    if bagType == 0 then
        return true
    end
    if not itemFamily or itemFamily == 0 then
        return false
    end
    if bit and bit.band then
        return bit.band(itemFamily, bagType) > 0
    end
    return true
end

local function FindFirstOpenBankSlotExcluding(excludedBagID, itemFamily)
    for _, bid in ipairs(BANK_BAG_IDS) do
        if bid ~= excludedBagID and CanBankSlotAcceptItem(bid, itemFamily) then
            local slots = GetContainerNumSlots(bid) or 0
            for slotID = 1, slots do
                local texture = GetContainerItemInfo(bid, slotID)
                if not texture then
                    return bid, slotID
                end
            end
        end
    end
    return nil, nil
end

local function FindFirstOpenBankSlotExcludingSwap(excludedBagID, newBagBagID, newBagSlotID, itemFamily)
    for _, bid in ipairs(BANK_BAG_IDS) do
        if bid ~= excludedBagID and CanBankSlotAcceptItem(bid, itemFamily) then
            local slots = GetContainerNumSlots(bid) or 0
            for slotID = 1, slots do
                if not (bid == newBagBagID and slotID == newBagSlotID) then
                    local texture = GetContainerItemInfo(bid, slotID)
                    if not texture then
                        return bid, slotID
                    end
                end
            end
        end
    end
    return nil, nil
end

local function CountFreeBankSlotsExcluding(excludedBagID, newBagBagID, newBagSlotID)
    local count = 0
    for _, bid in ipairs(BANK_BAG_IDS) do
        if bid ~= excludedBagID then
            local slots = GetContainerNumSlots(bid) or 0
            for slotID = 1, slots do
                if not (bid == newBagBagID and slotID == newBagSlotID) then
                    local texture = GetContainerItemInfo(bid, slotID)
                    if not texture then
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

local function StopBankForceEmptyJob()
    if bankForceEmptyFrame then
        bankForceEmptyFrame:SetScript("OnUpdate", nil)
        bankForceEmptyFrame:SetScript("OnEvent", nil)
        bankForceEmptyFrame:UnregisterEvent("BAG_UPDATE")
        bankForceEmptyFrame:UnregisterEvent("ITEM_LOCK_CHANGED")
        bankForceEmptyFrame:UnregisterEvent("PLAYERBANKSLOTS_CHANGED")
    end
    bankForceEmptyJob = nil
end

local function FinishBankForceEmptyJob()
    if not bankForceEmptyJob then
        return
    end
    if bankForceEmptyJob.type == "empty" then
        print(string.format(
            "|cFF00FF00OmniInventory|r: Bank clear bag %s moved %d, blocked %d.",
            tostring(bankForceEmptyJob.sourceBagID),
            bankForceEmptyJob.movedCount,
            bankForceEmptyJob.blockedCount
        ))
    end
    StopBankForceEmptyJob()
    if BankFrame and BankFrame.UpdateLayout then
        BankFrame:UpdateLayout()
    end
end

local function RunBankForceEmptyStep()
    if not bankForceEmptyJob then
        return
    end

    if bankForceEmptyJob.type == "empty" then
        if #bankForceEmptyJob.slots == 0 then
            FinishBankForceEmptyJob()
            return
        end
        local source = bankForceEmptyJob.sourceBagID
        local entry = table.remove(bankForceEmptyJob.slots, 1)
        local slotID = entry.slotID
        local attempts = entry.attempts or 0

        local texture, _, isLocked = GetContainerItemInfo(source, slotID)
        if not texture then
            RunBankForceEmptyStep()
            return
        end
        if isLocked then
            attempts = attempts + 1
            if attempts >= BANK_FORCE_EMPTY_MAX_LOCK then
                bankForceEmptyJob.blockedCount = bankForceEmptyJob.blockedCount + 1
                RunBankForceEmptyStep()
            else
                entry.attempts = attempts
                table.insert(bankForceEmptyJob.slots, entry)
            end
            return
        end
        local itemLink = GetContainerItemLink(source, slotID)
        local fam = (itemLink and GetItemFamily(itemLink)) or 0
        local tBag, tSlot = FindFirstOpenBankSlotExcluding(source, fam)
        if not tBag or not tSlot then
            bankForceEmptyJob.blockedCount = bankForceEmptyJob.blockedCount + 1
            RunBankForceEmptyStep()
            return
        end
        if PickupContainerItem then
            PickupContainerItem(source, slotID)
        end
        if CursorHasItem and CursorHasItem() and PickupContainerItem then
            PickupContainerItem(tBag, tSlot)
        end
        if CursorHasItem and CursorHasItem() and ClearCursor then
            ClearCursor()
            attempts = attempts + 1
            if attempts >= BANK_FORCE_EMPTY_MAX_MOVE then
                bankForceEmptyJob.blockedCount = bankForceEmptyJob.blockedCount + 1
                RunBankForceEmptyStep()
            else
                entry.attempts = attempts
                table.insert(bankForceEmptyJob.slots, entry)
            end
        else
            bankForceEmptyJob.movedCount = bankForceEmptyJob.movedCount + 1
            bankForceEmptyJob.awaitingEvent = true
            bankForceEmptyJob.awaitElapsed = 0
        end

    elseif bankForceEmptyJob.type == "swap" then
        if bankForceEmptyJob.phase == 1 then
            -- Phase 1: Empty targetBagID
            if #bankForceEmptyJob.slots > 0 then
                local source = bankForceEmptyJob.targetBagID
                local entry = table.remove(bankForceEmptyJob.slots, 1)
                local slotID = entry.slotID
                local attempts = entry.attempts or 0

                local texture, _, isLocked = GetContainerItemInfo(source, slotID)
                if not texture then
                    RunBankForceEmptyStep()
                    return
                end
                if isLocked then
                    attempts = attempts + 1
                    if attempts >= BANK_FORCE_EMPTY_MAX_LOCK then
                        bankForceEmptyJob.blockedCount = bankForceEmptyJob.blockedCount + 1
                        RunBankForceEmptyStep()
                    else
                        entry.attempts = attempts
                        table.insert(bankForceEmptyJob.slots, entry)
                    end
                    return
                end

                local itemLink = GetContainerItemLink(source, slotID)
                local fam = (itemLink and GetItemFamily(itemLink)) or 0
                local tBag, tSlot = FindFirstOpenBankSlotExcludingSwap(bankForceEmptyJob.targetBagID, bankForceEmptyJob.sourceBagID, bankForceEmptyJob.sourceSlotID, fam)
                if not tBag or not tSlot then
                    print("|cFF00FF00OmniInventory|r: Aborting swap - out of free bank space.")
                    StopBankForceEmptyJob()
                    return
                end

                if PickupContainerItem then
                    PickupContainerItem(source, slotID)
                end
                if CursorHasItem and CursorHasItem() and PickupContainerItem then
                    PickupContainerItem(tBag, tSlot)
                end

                if CursorHasItem and CursorHasItem() and ClearCursor then
                    ClearCursor()
                    attempts = attempts + 1
                    if attempts >= BANK_FORCE_EMPTY_MAX_MOVE then
                        bankForceEmptyJob.blockedCount = bankForceEmptyJob.blockedCount + 1
                        RunBankForceEmptyStep()
                    else
                        entry.attempts = attempts
                        table.insert(bankForceEmptyJob.slots, entry)
                    end
                else
                    bankForceEmptyJob.movedCount = bankForceEmptyJob.movedCount + 1
                    bankForceEmptyJob.awaitingEvent = true
                    bankForceEmptyJob.awaitElapsed = 0
                    table.insert(bankForceEmptyJob.shuffledItems, {
                        originalSlotID = slotID,
                        tempBagID = tBag,
                        tempSlotID = tSlot,
                    })
                end
            else
                bankForceEmptyJob.phase = 2
                bankForceEmptyJob.awaitingEvent = true
                bankForceEmptyJob.awaitElapsed = 0
            end

        elseif bankForceEmptyJob.phase == 2 then
            -- Phase 2: Equip new bag
            local texture, _, isLocked = GetContainerItemInfo(bankForceEmptyJob.sourceBagID, bankForceEmptyJob.sourceSlotID)
            if isLocked then
                return
            end

            PickupContainerItem(bankForceEmptyJob.sourceBagID, bankForceEmptyJob.sourceSlotID)
            if CursorHasItem and CursorHasItem() then
                local invSlot = ContainerIDToInventoryID(bankForceEmptyJob.targetBagID)
                if invSlot and PutItemInBag then
                    PutItemInBag(invSlot)
                end
            end

            bankForceEmptyJob.phase = 3
            bankForceEmptyJob.awaitingEvent = true
            bankForceEmptyJob.awaitElapsed = 0

        elseif bankForceEmptyJob.phase == 3 then
            -- Phase 3: Store old bag
            if CursorHasItem and CursorHasItem() then
                PickupContainerItem(bankForceEmptyJob.sourceBagID, bankForceEmptyJob.sourceSlotID)
            end

            if CursorHasItem and CursorHasItem() then
                local tempBag, tempSlot = FindFirstOpenBankSlotExcludingSwap(bankForceEmptyJob.targetBagID, nil, nil, 0)
                if tempBag and tempSlot then
                    PickupContainerItem(tempBag, tempSlot)
                end
            end

            if CursorHasItem and CursorHasItem() and ClearCursor then
                ClearCursor()
            end

            bankForceEmptyJob.phase = 4
            bankForceEmptyJob.slots = {}
            for _, info in ipairs(bankForceEmptyJob.shuffledItems) do
                table.insert(bankForceEmptyJob.slots, {
                    slotID = info.originalSlotID,
                    tempBagID = info.tempBagID,
                    tempSlotID = info.tempSlotID,
                    attempts = 0,
                })
            end
            bankForceEmptyJob.awaitingEvent = true
            bankForceEmptyJob.awaitElapsed = 0

        elseif bankForceEmptyJob.phase == 4 then
            -- Phase 4: Refill items
            if #bankForceEmptyJob.slots > 0 then
                local entry = table.remove(bankForceEmptyJob.slots, 1)
                local targetSlotID = entry.slotID
                local tempBagID = entry.tempBagID
                local tempSlotID = entry.tempSlotID
                local attempts = entry.attempts or 0

                local texture, _, isLocked = GetContainerItemInfo(tempBagID, tempSlotID)
                if not texture then
                    RunBankForceEmptyStep()
                    return
                end
                if isLocked then
                    attempts = attempts + 1
                    if attempts >= BANK_FORCE_EMPTY_MAX_LOCK then
                        bankForceEmptyJob.blockedCount = bankForceEmptyJob.blockedCount + 1
                        RunBankForceEmptyStep()
                    else
                        entry.attempts = attempts
                        table.insert(bankForceEmptyJob.slots, entry)
                    end
                    return
                end

                PickupContainerItem(tempBagID, tempSlotID)
                if CursorHasItem and CursorHasItem() and PickupContainerItem then
                    PickupContainerItem(bankForceEmptyJob.targetBagID, targetSlotID)
                end

                if CursorHasItem and CursorHasItem() and ClearCursor then
                    ClearCursor()
                    attempts = attempts + 1
                    if attempts >= BANK_FORCE_EMPTY_MAX_MOVE then
                        bankForceEmptyJob.blockedCount = bankForceEmptyJob.blockedCount + 1
                        RunBankForceEmptyStep()
                    else
                        entry.attempts = attempts
                        table.insert(bankForceEmptyJob.slots, entry)
                    end
                else
                    bankForceEmptyJob.movedCount = bankForceEmptyJob.movedCount + 1
                    bankForceEmptyJob.awaitingEvent = true
                    bankForceEmptyJob.awaitElapsed = 0
                end
            else
                print(string.format("|cFF00FF00OmniInventory|r: Successfully swapped bank bag %d.", bankForceEmptyJob.targetBagID))
                StopBankForceEmptyJob()
                if BankFrame and BankFrame.UpdateLayout then
                    BankFrame:UpdateLayout()
                end
            end
        end
    end
end

local function ensureBankForceEmptyFrame()
    if bankForceEmptyFrame then return end
    bankForceEmptyFrame = CreateFrame("Frame")
    bankForceEmptyFrame:RegisterEvent("BAG_UPDATE")
    bankForceEmptyFrame:RegisterEvent("ITEM_LOCK_CHANGED")
    bankForceEmptyFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    bankForceEmptyFrame:SetScript("OnEvent", function(_, event, arg1)
        if not bankForceEmptyJob then
            return
        end
        if event == "BAG_UPDATE" and arg1 ~= nil then
            if bankForceEmptyJob.type == "empty" and arg1 ~= bankForceEmptyJob.sourceBagID then
                bankForceEmptyJob.awaitingEvent = false
            elseif bankForceEmptyJob.type == "swap" then
                bankForceEmptyJob.awaitingEvent = false
            end
            return
        end
        bankForceEmptyJob.awaitingEvent = false
    end)
    bankForceEmptyFrame:SetScript("OnUpdate", function(self, elapsed)
        if not bankForceEmptyJob then
            return
        end
        if bankForceEmptyJob.awaitingEvent then
            bankForceEmptyJob.awaitElapsed = bankForceEmptyJob.awaitElapsed + (elapsed or 0)
            if bankForceEmptyJob.awaitElapsed < BANK_FORCE_EMPTY_EVENT_TIMEOUT then
                return
            end
            bankForceEmptyJob.awaitingEvent = false
        end
        if CursorHasItem and CursorHasItem() then
            if bankForceEmptyJob.type == "empty" or (bankForceEmptyJob.type == "swap" and bankForceEmptyJob.phase ~= 2 and bankForceEmptyJob.phase ~= 3) then
                return
            end
        end
        if InCombat() then
            StopBankForceEmptyJob()
            return
        end
        RunBankForceEmptyStep()
    end)
end

function BankFrame:ForceEmptyBankBag(sourceBagID)
    if not IsValidBankBagID(sourceBagID) then return end
    local viewedChar = Omni.Data and Omni.Data.currentViewedChar
    local isOfflineBank = not (Omni.Features and Omni.Features:IsAtBank())
    if (viewedChar and viewedChar ~= Omni.Data.playerName) or isOfflineBank then
        return
    end
    if CursorHasItem and CursorHasItem() then
        print("|cFF00FF00OmniInventory|r: Clear cursor before force-empty.")
        return
    end
    if InCombat() then
        print("|cFF00FF00OmniInventory|r: Bank force-empty is unavailable during combat.")
        return
    end
    local sourceSlots = GetContainerNumSlots(sourceBagID) or 0
    if sourceSlots <= 0 then
        print("|cFF00FF00OmniInventory|r: That bank space has no slots.")
        return
    end
    local slots = {}
    for s = 1, sourceSlots do
        local tex = GetContainerItemInfo(sourceBagID, s)
        if tex then
            table.insert(slots, { slotID = s, attempts = 0 })
        end
    end
    if #slots == 0 then
        print("|cFF00FF00OmniInventory|r: Already empty.")
        return
    end
    if bankForceEmptyJob then
        StopBankForceEmptyJob()
    end
    bankForceEmptyJob = {
        type = "empty",
        sourceBagID = sourceBagID,
        slots = slots,
        movedCount = 0,
        blockedCount = 0,
        awaitingEvent = false,
        awaitElapsed = 0,
    }
    ensureBankForceEmptyFrame()
end

function BankFrame:StartBankBagSwap(sourceBagID, sourceSlotID, targetBagID)
    if not IsValidBankBagID(targetBagID) or not IsValidBankBagID(sourceBagID) then return end
    local viewedChar = Omni.Data and Omni.Data.currentViewedChar
    local isOfflineBank = not (Omni.Features and Omni.Features:IsAtBank())
    if (viewedChar and viewedChar ~= Omni.Data.playerName) or isOfflineBank then
        return
    end

    if InCombat() then
        print("|cFF00FF00OmniInventory|r: Cannot swap bank bags during combat.")
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
        if ClearCursor then ClearCursor() end
        PickupContainerItem(sourceBagID, sourceSlotID)
        if CursorHasItem() then
            local invSlot = ContainerIDToInventoryID(targetBagID)
            if invSlot and PutItemInBag then PutItemInBag(invSlot) end
        end
        if CursorHasItem() then
            PickupContainerItem(sourceBagID, sourceSlotID)
        end
        if CursorHasItem() and ClearCursor then ClearCursor() end
        print(string.format("|cFF00FF00OmniInventory|r: Successfully swapped empty bank bag slot %d.", targetBagID))
        if BankFrame and BankFrame.UpdateLayout then
            BankFrame:UpdateLayout()
        end
        return
    end

    local freeSlots = CountFreeBankSlotsExcluding(targetBagID, sourceBagID, sourceSlotID)
    if freeSlots < filledCount then
        print(string.format("|cFF00FF00OmniInventory|r: Not enough free bank slots to swap this bag. Need %d slots, have %d.", filledCount, freeSlots))
        return
    end

    if bankForceEmptyJob then
        StopBankForceEmptyJob()
    end

    bankForceEmptyJob = {
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

    ensureBankForceEmptyFrame()
    print(string.format("|cFF00FF00OmniInventory|r: Swapping bank bag %d (moving %d items)...", targetBagID, filledCount))
end

function BankFrame:RenderFlowView(items)
    if not bankFrame or not bankFrame.scrollChild then return end

    local scrollChild = bankFrame.scrollChild

    if Omni.Pool then
        for _, btn in ipairs(itemButtons) do
            Omni.Pool:Release("ItemButton", btn)
            pcall(btn.Hide, btn)
        end
    end
    itemButtons = {}

    for _, header in ipairs(categoryHeaders) do
        header:Hide()
    end

    local hInset = 8
    local usableWidth = GetBankContentWidth() - hInset
    scrollChild:SetWidth(math.max(usableWidth, 1))
    local itemScale = GetSharedItemScale()
    local itemGap = GetSharedItemGap()
    local itemSize = ITEM_SIZE * itemScale
    local itemStep = itemSize + itemGap
    local sectionHeaderHeight = 20
    local sectionSpacing = 8
    local laneGap = 10

    local function columnsForLaneWidth(laneW)
        local inner = laneW - itemGap
        local c = math.floor(inner / itemStep)
        return math.max(c, 1)
    end

    local yLeft = -itemGap
    local yRight = -itemGap
    local yOffset = -itemGap
    local renderedSectionCount = 0

    local categories = {}
    local categoryOrder = {}
    local collapseEmpty = false
    if Omni.Data and Omni.Data.Get then
        collapseEmpty = (Omni.Data:Get("collapseEmptySlots") == true)
    end

    local activeBags = {}
    if selectedBankBagID ~= nil then
        activeBags[1] = selectedBankBagID
    else
        table.insert(activeBags, -1)
        for _, bagID in ipairs(BANK_BAG_IDS or {5,6,7,8,9,10,11}) do
            table.insert(activeBags, bagID)
        end
    end

    if currentBankView == "bag" then
        -- BAG MODE: Group by physical bagID
        for _, bagID in ipairs(activeBags) do
            categories[bagID] = {}
            table.insert(categoryOrder, bagID)
        end

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
            if a.owner ~= b.owner then return a.owner < b.owner end
            return a.bagID < b.bagID
        end)
        for _, altBag in ipairs(altBagOrders) do
            categories[altBag.key] = {}
            table.insert(categoryOrder, altBag.key)
        end

        for _, item in ipairs(items) do
            if not item.__offline or not item.__owner then
                local bagID = item.bagID
                if categories[bagID] then
                    table.insert(categories[bagID], item)
                end
            else
                local altKey = item.__owner .. "_" .. item.bagID
                if categories[altKey] then
                    table.insert(categories[altKey], item)
                end
            end
        end
        -- Append empty slots to their respective bags (current player only)
        for _, bagID in ipairs(activeBags) do
            local numSlots = GetContainerNumSlots(bagID) or 0
            for slotID = 1, numSlots do
                local info = OmniC_Container.GetContainerItemInfo(bagID, slotID)
                if not info then
                    table.insert(categories[bagID], { bagID = bagID, slotID = slotID, __empty = true, emptyCount = 1 })
                end
            end
        end
    else
        -- FLOW MODE: Group by assigned category
        for _, item in ipairs(items) do
            local cat = item.category or "Miscellaneous"
            if not categories[cat] then
                categories[cat] = {}
                table.insert(categoryOrder, cat)
            end
            table.insert(categories[cat], item)
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
                if not categories[catName] then
                    categories[catName] = {}
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
                        if not categories[freeSpaceCat] then
                            categories[freeSpaceCat] = {}
                            table.insert(categoryOrder, freeSpaceCat)
                        end
                        table.insert(categories[freeSpaceCat], emptyItem)
                    end
                end
            end
        end

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

        -- Bubble all categories starting with "Free Space" to the absolute end
        local reordered = {}
        for _, catName in ipairs(categoryOrder) do
            if not string.match(catName, "^Free Space") then
                table.insert(reordered, catName)
            end
        end
        for _, catName in ipairs(categoryOrder) do
            if string.match(catName, "^Free Space") then
                table.insert(reordered, catName)
            end
        end
        categoryOrder = reordered
    end

    local dualCategoryLanes = #categoryOrder > 1

    local headerIndex = 0
    for _, catName in ipairs(categoryOrder) do
        local catItems = categories[catName]
        if catItems and #catItems > 0 then
            renderedSectionCount = renderedSectionCount + 1

            local laneX, laneY, columns
            if dualCategoryLanes then
                local laneW = (usableWidth - laneGap) * 0.5
                local edgePad = hInset * 0.5
                local leftX = edgePad + itemGap
                local rightX = edgePad + laneW + laneGap + itemGap
                local useRight = (renderedSectionCount % 2 == 0)
                laneX = useRight and rightX or leftX
                laneY = useRight and yRight or yLeft
                columns = columnsForLaneWidth(laneW)
            else
                laneX = itemGap
                laneY = yOffset
                columns = columnsForLaneWidth(usableWidth)
            end

            headerIndex = headerIndex + 1
            local header = categoryHeaders[headerIndex]
            if not header then
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
                header:RegisterForClicks("LeftButtonUp")
                local lastClick = 0
                header:SetScript("OnClick", function(self)
                    local now = GetTime()
                    if (now - lastClick) <= 0.35 then
                        lastClick = 0
                        if Omni.Frame and Omni.Frame.OpenCategoryEditDialog then
                            Omni.Frame:OpenCategoryEditDialog(self.catName)
                        end
                    else
                        lastClick = now
                    end
                end)
                categoryHeaders[headerIndex] = header
            end
            header.catName = catName

            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", laneX, laneY)

            local r, g, b = 1, 1, 1
            if currentBankView == "bag" then
                local totalSlots = 0
                local filled = 0
                local displayName = "Unknown Bag"
                if type(catName) == "string" and string.find(catName, "_") then
                    local altName, bagIDStr = string.match(catName, "^([^_]+)_(%-?%d+)$")
                    if altName and bagIDStr then
                        local bagID = tonumber(bagIDStr)
                        displayName = altName .. "'s " .. GetBagDisplayName(bagID)
                        local currentRealm = GetRealmName()
                        local charData = OmniInventoryDB and OmniInventoryDB.realm and OmniInventoryDB.realm[currentRealm] and OmniInventoryDB.realm[currentRealm][altName]
                        if charData and charData.bagSizes then
                            totalSlots = charData.bagSizes[tostring(bagID)] or 0
                        end
                    end
                else
                    displayName = GetBagDisplayName(catName)
                    totalSlots = GetContainerNumSlots(catName) or 0
                end
                for _, item in ipairs(catItems) do
                    if not item.__empty then
                        filled = filled + 1
                    end
                end
                header:SetTextColor(0.9, 0.8, 0.4)
                header:SetText(displayName .. " (" .. filled .. "/" .. totalSlots .. ")")
            else
                if Omni.Categorizer then
                    r, g, b = Omni.Categorizer:GetCategoryColor(catName)
                end
                header:SetTextColor(r, g, b)
                header:SetText(catName .. " (" .. #catItems .. ")")
            end
            header:Show()

            laneY = laneY - sectionHeaderHeight

            local layoutIndex = 0
            for i, itemInfo in ipairs(catItems) do
                local btn
                if Omni.Pool then
                    btn = Omni.Pool:Acquire("ItemButton")
                elseif Omni.ItemButton then
                    btn = Omni.ItemButton:Create(scrollChild)
                end

                if btn then
                    layoutIndex = layoutIndex + 1
                    local col = ((layoutIndex - 1) % columns)
                    local row = math.floor((layoutIndex - 1) / columns)
                    local x = laneX + col * itemStep
                    local y = laneY - row * itemStep

                    local container = (itemInfo.__offline and itemInfo.__owner) and scrollChild or (GetBankItemContainer(itemInfo.bagID or -1) or scrollChild)
                    if btn:GetParent() ~= container then
                        pcall(btn.SetParent, btn, container)
                    end
                    pcall(ApplyBankItemMetrics, btn, itemSize)
                    pcall(btn.ClearAllPoints, btn)
                    pcall(btn.SetPoint, btn, "TOPLEFT", scrollChild, "TOPLEFT", x, y)

                    local ok = pcall(function()
                        SetButtonItem(btn, itemInfo)
                        btn:Show()
                    end)
                    if ok then
                        if btn:GetParent() ~= container then
                            pcall(btn.SetParent, btn, container)
                        end
                        if itemInfo.slotID and btn.SetID then
                            pcall(btn.SetID, btn, itemInfo.slotID)
                        end
                    end
                    if not ok then
                        pcall(SetButtonItem, btn, nil)
                        if btn.icon then btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
                        pcall(btn.Show, btn)
                    end

                    table.insert(itemButtons, btn)
                end
            end

            local catRows = math.ceil(layoutIndex / columns)
            laneY = laneY - (catRows * itemStep) - sectionSpacing

            if dualCategoryLanes then
                if (renderedSectionCount % 2 == 0) then
                    yRight = laneY
                else
                    yLeft = laneY
                end
            else
                yOffset = laneY
            end
        end
    end

    local bottomY = dualCategoryLanes and math.min(yLeft, yRight) or yOffset
    scrollChild:SetHeight(math.abs(bottomY) + itemGap)
end

function BankFrame:RenderGridView(items)
    if not bankFrame or not bankFrame.scrollChild then return false end

    local scrollChild = bankFrame.scrollChild
    local previousButtons = itemButtons
    itemButtons = {}
    local releasedPreviousToPool = false

    if InCombat() then
        for _, btn in ipairs(previousButtons) do
            pcall(btn.SetAlpha, btn, 0)
        end
    elseif Omni.Pool then
        for _, btn in ipairs(previousButtons) do
            Omni.Pool:Release("ItemButton", btn)
        end
        releasedPreviousToPool = true
    end

    for _, header in ipairs(categoryHeaders) do
        header:Hide()
    end

    local itemBySlot = {}
    for _, item in ipairs(items or {}) do
        if (not item.__offline or not item.__owner) and item.bagID and item.slotID then
            itemBySlot[item.bagID] = itemBySlot[item.bagID] or {}
            itemBySlot[item.bagID][item.slotID] = item
        end
    end

    local itemScale = GetSharedItemScale()
    local itemGap = GetSharedItemGap()
    local itemSize = ITEM_SIZE * itemScale
    local itemStep = itemSize + itemGap
    local usableWidth = math.max(1, GetBankContentWidth() - itemGap)
    scrollChild:SetWidth(usableWidth)
    local columns = math.max(math.floor((usableWidth + itemGap) / itemStep), 1)
    local index = 0
    local rendered = false

    local function renderSlot(bagID, slotID, customItemInfo)
        index = index + 1
        local container = (customItemInfo and customItemInfo.__offline and customItemInfo.__owner) and scrollChild or (GetBankItemContainer(bagID) or scrollChild)
        local btn = (not releasedPreviousToPool) and previousButtons[index] or nil
        if not btn then
            if InCombat() and Omni.ItemButton then
                local createdOK, created = pcall(Omni.ItemButton.Create, Omni.ItemButton, container)
                if createdOK then
                    btn = created
                end
            end
            if not btn and Omni.Pool then
                local acquiredOK, acquired = pcall(Omni.Pool.Acquire, Omni.Pool, "ItemButton")
                if acquiredOK then
                    btn = acquired
                end
            end
            if not btn and Omni.ItemButton then
                local createdOK, created = pcall(Omni.ItemButton.Create, Omni.ItemButton, container)
                if createdOK then
                    btn = created
                end
            end
        end
        if not btn then return end

        local col = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local x = itemGap + col * itemStep
        local y = -itemGap - row * itemStep

        if btn:GetParent() ~= container then
            pcall(btn.SetParent, btn, container)
        end
        pcall(ApplyBankItemMetrics, btn, itemSize)
        pcall(btn.ClearAllPoints, btn)
        pcall(btn.SetPoint, btn, "TOPLEFT", scrollChild, "TOPLEFT", x, y)
        pcall(btn.SetAlpha, btn, 1)

        local itemInfo = customItemInfo or (itemBySlot[bagID] and itemBySlot[bagID][slotID])
        pcall(SetButtonItem, btn, itemInfo or { bagID = bagID, slotID = slotID, __empty = true })
        if btn:GetParent() ~= container then
            pcall(btn.SetParent, btn, container)
        end
        if slotID and btn.SetID then
            pcall(btn.SetID, btn, slotID)
        end
        pcall(btn.Show, btn)
        table.insert(itemButtons, btn)
        rendered = true
    end

    local collapseEmpty = false
    if Omni.Data and Omni.Data.Get then
        collapseEmpty = (Omni.Data:Get("collapseEmptySlots") == true)
    end

    local activeBankBags = {}
    if IsValidBankBagID(selectedBankBagID) then
        table.insert(activeBankBags, selectedBankBankID or selectedBankBagID)
    else
        table.insert(activeBankBags, -1)
        for _, bagID in ipairs(BANK_BAG_IDS) do
            table.insert(activeBankBags, bagID)
        end
    end

    local slotsToRender = {}
    local activeBagsSet = {}
    for _, bagID in ipairs(activeBankBags) do
        activeBagsSet[bagID] = true
    end

    -- Insert sorted filled items first
    for _, itemInfo in ipairs(items or {}) do
        if (itemInfo.__offline and itemInfo.__owner) or (itemInfo.bagID and activeBagsSet[itemInfo.bagID]) then
            table.insert(slotsToRender, { bagID = itemInfo.bagID, slotID = itemInfo.slotID, itemInfo = itemInfo })
        end
    end

    if collapseEmpty then
        local emptyGroups = {}
        for _, bagID in ipairs(activeBankBags) do
            local slots = GetContainerNumSlots(bagID) or 0
            for slotID = 1, slots do
                local itemInfo = itemBySlot[bagID] and itemBySlot[bagID][slotID]
                if not itemInfo then
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

        local sortedGrps = {}
        for name, item in pairs(emptyGroups) do
            table.insert(sortedGrps, { name = name, item = item })
        end
        table.sort(sortedGrps, function(a, b) return a.name < b.name end)
        for _, grp in ipairs(sortedGrps) do
            table.insert(slotsToRender, { bagID = grp.item.bagID, slotID = grp.item.slotID, itemInfo = grp.item })
        end
    else
        for _, bagID in ipairs(activeBankBags) do
            local slots = GetContainerNumSlots(bagID) or 0
            for slotID = 1, slots do
                local itemInfo = itemBySlot[bagID] and itemBySlot[bagID][slotID]
                if not itemInfo then
                    table.insert(slotsToRender, { bagID = bagID, slotID = slotID, itemInfo = nil })
                end
            end
        end
    end

    for _, slot in ipairs(slotsToRender) do
        renderSlot(slot.bagID, slot.slotID, slot.itemInfo)
    end

    if not releasedPreviousToPool then
        for i = index + 1, #previousButtons do
            local btn = previousButtons[i]
            pcall(SetButtonItem, btn, nil)
            pcall(btn.SetAlpha, btn, 0)
            table.insert(itemButtons, btn)
        end
    end

    local rows = math.ceil(index / columns)
    scrollChild:SetHeight(math.max(rows * itemStep + itemGap, 1))
    return rendered
end

function BankFrame:UpdateLayout()
    local perfTotal = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("bank.UpdateLayout.total")
    if not bankFrame or not bankFrame:IsShown() then return end
    self:UpdateTitle()

    self:UpdateBankBagButtonIcons()
    self:UpdateBankBagButtonVisuals()

    local items = CollectBankItems()

    if currentBankView == "grid" or InCombat() then
        for _, row in ipairs(listRows) do row:Hide() end
        local perfRender = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("bank.UpdateLayout.renderGrid")
        self:RenderGridView(items)
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("bank.UpdateLayout.renderGrid", perfRender, { itemCount = #items })
        end
        self:UpdateSlotCount()
        self:ApplySearch(searchText or "")
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("bank.UpdateLayout.total", perfTotal, { itemCount = #items, view = "grid" })
        end
        return
    elseif currentBankView == "list" then
        for _, row in ipairs(listRows) do row:Hide() end
        local perfRender = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("bank.UpdateLayout.renderList")
        self:RenderListView(items)
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("bank.UpdateLayout.renderList", perfRender, { itemCount = #items })
        end
        self:UpdateSlotCount()
        self:ApplySearch(searchText or "")
        if Omni._perfEnabled and Omni.Perf then
            Omni.Perf:End("bank.UpdateLayout.total", perfTotal, { itemCount = #items, view = "list" })
        end
        return
    end

    -- Hide list rows for flow / bag mode
    for _, row in ipairs(listRows) do row:Hide() end

    local perfRender = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("bank.UpdateLayout.renderFlow")
    self:RenderFlowView(items)
    if Omni._perfEnabled and Omni.Perf then
        Omni.Perf:End("bank.UpdateLayout.renderFlow", perfRender, { itemCount = #items })
    end
    self:UpdateSlotCount()

    local perfSearch = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("bank.UpdateLayout.search")
    self:ApplySearch(searchText or "")
    if Omni._perfEnabled and Omni.Perf then
        Omni.Perf:End("bank.UpdateLayout.search", perfSearch)
    end
    if Omni._perfEnabled and Omni.Perf then
        Omni.Perf:End("bank.UpdateLayout.total", perfTotal, { itemCount = #items, view = "flow" })
    end
end

function BankFrame:UpdateSlotCount()
    if not bankFrame or not bankFrame.footer then return end

    local free, total = 0, 0
    local mainSlots = GetContainerNumSlots(-1) or 0
    local mainFree = GetContainerNumFreeSlots(-1) or 0
    total = total + mainSlots
    free = free + mainFree

    for bagID = 5, 11 do
        local slots = GetContainerNumSlots(bagID) or 0
        local freeSlots = GetContainerNumFreeSlots(bagID) or 0
        total = total + slots
        free = free + freeSlots
    end

    local used = total - free
    bankFrame.footer.slots:SetText(string.format("%d/%d", used, total))
end

function BankFrame:ApplySearch(text)
    local perfToken = Omni._perfEnabled and Omni.Perf and Omni.Perf:Begin("bank.ApplySearch")
    searchText = text or ""
    isSearchActive = (searchText ~= "")

    if not isSearchActive then
        for _, btn in ipairs(itemButtons) do
            if Omni.ItemButton then
                Omni.ItemButton:ClearSearch(btn)
            end
        end
        return
    end

    local lowerSearch = string.lower(searchText)
    local matchedButtons = 0
    for _, btn in ipairs(itemButtons) do
        local info = btn.itemInfo
        local isMatch = false
        if info and Omni.MatchItemQuery then
            isMatch = Omni.MatchItemQuery(info, searchText)
        end
        if Omni.ItemButton then
            Omni.ItemButton:SetSearchMatch(btn, isMatch)
        end
        if isMatch then
            matchedButtons = matchedButtons + 1
        end
    end
    if Omni._perfEnabled and Omni.Perf then
        Omni.Perf:End("bank.ApplySearch", perfToken, {
            queryLen = string.len(searchText or ""),
            visibleButtons = #itemButtons,
            matchedButtons = matchedButtons,
        })
    end
end

-- =============================================================================
-- Show / Hide / Toggle
-- =============================================================================

function BankFrame:Show()
    if not bankFrame then
        self:CreateMainFrame()
        LoadPosition()
    end
    AnchorToMainFrame()
    pcall(bankFrame.Show, bankFrame)
end

function BankFrame:Hide()
    if bankFrame then
        pcall(bankFrame.Hide, bankFrame)
    end
end

function BankFrame:Toggle()
    if bankFrame and bankFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function BankFrame:IsShown()
    return bankFrame and bankFrame:IsShown()
end

function BankFrame:GetFrame()
    return bankFrame
end

function BankFrame:Init()
    -- Frame is created lazily on first show
end

function BankFrame:UpdateTitle()
    if not bankFrame or not bankFrame.header or not bankFrame.header.title then return end
    local viewedChar = Omni.Data and Omni.Data.currentViewedChar
    local isOfflineBank = not (Omni.Features and Omni.Features:IsAtBank())
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
        bankFrame.header.title.text:SetText(string.format("|c%s%s|r's Bank", colorStr, viewedChar))
    else
        if isOfflineBank then
            bankFrame.header.title.text:SetText("|cFF00FF00Omni|r Bank (Offline)")
        else
            bankFrame.header.title.text:SetText("|cFF00FF00Omni|r Bank")
        end
    end
end

function BankFrame:SetScale(scale)
    if not bankFrame then return end
    scale = math.max(0.5, math.min(scale or 1, 2.0))
    bankFrame:SetScale(scale)

    if Omni.Data and Omni.Data.SetFrameSetting then
        Omni.Data:SetFrameSetting("bank", "scale", scale)
    else
        OmniInventoryDB = OmniInventoryDB or {}
        OmniInventoryDB.char = OmniInventoryDB.char or {}
        OmniInventoryDB.char.settings = OmniInventoryDB.char.settings or {}
        OmniInventoryDB.char.settings.scale = scale
    end
end

function BankFrame:GetScale()
    if Omni.Data and Omni.Data.GetFrameSetting then
        return Omni.Data:GetFrameSetting("bank", "scale", 1.0)
    end
    if bankFrame and bankFrame.GetScale then
        return bankFrame:GetScale()
    end
    local settings = OmniInventoryDB and OmniInventoryDB.char and OmniInventoryDB.char.settings
    return settings and settings.scale or 1
end

function BankFrame:GetItemScale()
    if Omni.Data and Omni.Data.GetFrameSetting then
        return Omni.Data:GetFrameSetting("bank", "itemScale", 1.0)
    end
    local settings = OmniInventoryDB and OmniInventoryDB.char and OmniInventoryDB.char.settings
    return settings and settings.itemScale or 1.0
end

function BankFrame:SetItemScale(scale)
    if InCombat() then return false end
    scale = math.max(0.5, math.min(scale or 1, 2.0))

    if Omni.Data and Omni.Data.SetFrameSetting then
        Omni.Data:SetFrameSetting("bank", "itemScale", scale)
    else
        OmniInventoryDB = OmniInventoryDB or {}
        OmniInventoryDB.char = OmniInventoryDB.char or {}
        OmniInventoryDB.char.settings = OmniInventoryDB.char.settings or {}
        OmniInventoryDB.char.settings.itemScale = scale
    end

    self:UpdateLayout()
    return true
end

function BankFrame:GetItemGap()
    if Omni.Data and Omni.Data.GetFrameSetting then
        return Omni.Data:GetFrameSetting("bank", "itemGap", ITEM_SPACING)
    end
    local settings = OmniInventoryDB and OmniInventoryDB.char and OmniInventoryDB.char.settings
    return settings and settings.itemGap or ITEM_SPACING
end

function BankFrame:SetItemGap(gap)
    if InCombat() then return false end
    gap = math.max(0, math.min(gap or ITEM_SPACING, 20))

    if Omni.Data and Omni.Data.SetFrameSetting then
        Omni.Data:SetFrameSetting("bank", "itemGap", gap)
    else
        OmniInventoryDB = OmniInventoryDB or {}
        OmniInventoryDB.char = OmniInventoryDB.char or {}
        OmniInventoryDB.char.settings = OmniInventoryDB.char.settings or {}
        OmniInventoryDB.char.settings.itemGap = gap
    end

    self:UpdateLayout()
    return true
end

function BankFrame:RenderListView(items)
    if not bankFrame or not bankFrame.scrollChild then return end

    local scrollChild = bankFrame.scrollChild

    -- Hide all flow/grid buttons
    if Omni.Pool then
        for _, btn in ipairs(itemButtons) do
            Omni.Pool:Release("ItemButton", btn)
            pcall(btn.Hide, btn)
        end
    end
    itemButtons = {}

    for _, header in ipairs(categoryHeaders) do
        header:Hide()
    end

    for _, row in ipairs(listRows) do
        row:Hide()
    end

    local ROW_HEIGHT = 22
    local ICON_SIZE = 18
    local yOffset = -4

    for i, itemInfo in ipairs(items) do
        local row = listRows[i]
        if not row then
            row = CreateFrame("Button", nil, scrollChild)
            row:SetHeight(ROW_HEIGHT)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(ICON_SIZE, ICON_SIZE)
            row.icon:SetPoint("LEFT", 4, 0)

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.name:SetWidth(180)
            row.name:SetJustifyH("LEFT")

            row.itemType = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.itemType:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
            row.itemType:SetWidth(80)
            row.itemType:SetJustifyH("LEFT")
            row.itemType:SetTextColor(0.7, 0.7, 0.7)

            row.qty = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.qty:SetPoint("RIGHT", -8, 0)
            row.qty:SetWidth(30)
            row.qty:SetJustifyH("RIGHT")

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
                        local ok
                        if self.itemInfo.bagID == -1 then
                            if BankButtonIDToInvSlotID then
                                local invID = BankButtonIDToInvSlotID(self.itemInfo.slotID, nil)
                                ok = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", invID)
                            end
                        else
                            ok = pcall(GameTooltip.SetBagItem, GameTooltip, self.itemInfo.bagID, self.itemInfo.slotID)
                        end
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
                end
            end)
            row:SetScript("OnLeave", function(self)
                self.bg:SetVertexColor(0.1, 0.1, 0.1, 1)
                self.__omniUsesCustomTooltip = false
                if Omni.ItemButton and Omni.ItemButton.HideTooltipIfOwnedBy then
                    Omni.ItemButton.HideTooltipIfOwnedBy(self)
                elseif GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self then
                    GameTooltip:Hide()
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
                    if bagID and slotID then
                        UseContainerItem(bagID, slotID)
                    end
                    return
                end
                if mb ~= "LeftButton" or not self.itemInfo then
                    return
                end
                local bagID, slotID = self.itemInfo.bagID, self.itemInfo.slotID
                if not bagID or not slotID then
                    return
                end
                if InCombatLockdown and InCombatLockdown() then
                    return
                end
                PickupContainerItem(bagID, slotID)
            end)
            listRows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, yOffset)

        if i % 2 == 0 then
            row.bg:SetVertexColor(0.15, 0.15, 0.15, 1)
        else
            row.bg:SetVertexColor(0.1, 0.1, 0.1, 1)
        end

        local success, err = pcall(function()
            row.icon:SetTexture(itemInfo.iconFileID or "Interface\\Icons\\INV_Misc_QuestionMark")
            local itemName, _, quality, _, _, itemType, itemSubType = nil, nil, itemInfo.quality, nil, nil, nil, nil
            if itemInfo.hyperlink then
                itemName, _, quality, _, _, itemType, itemSubType = GetItemInfo(itemInfo.hyperlink)
            end
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

            row.itemType:SetText(itemSubType or itemType or "")

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

        row.itemInfo = itemInfo
        if itemInfo.__offline then
            row:SetAlpha(0.65)
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
