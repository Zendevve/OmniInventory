local addonName, NS = ...

NS.FrameHeader = {}
local FrameHeader = NS.FrameHeader

-- Theme constants (shared with main Frame module)
local COLORS = {
    HEADER  = {0.15, 0.15, 0.15, 1.00},
    ACCENT  = {0.20, 0.20, 0.20, 1.00},
}

function FrameHeader:Create(parentFrame)
    local header = {}

    -- Header Background (Flat & Darker)
    header.bg = parentFrame:CreateTexture(nil, "ARTWORK")
    header.bg:SetTexture(unpack(COLORS.HEADER))
    header.bg:SetPoint("TOPLEFT", 0, 0)
    header.bg:SetPoint("TOPRIGHT", 0, 0)
    header.bg:SetHeight(40)

    -- Make header draggable
    header.dragArea = CreateFrame("Button", nil, parentFrame)
    header.dragArea:SetPoint("TOPLEFT", 0, 0)
    header.dragArea:SetPoint("TOPRIGHT", 0, 0)
    header.dragArea:SetHeight(40)
    header.dragArea:RegisterForDrag("LeftButton")
    header.dragArea:SetScript("OnDragStart", function() parentFrame:StartMoving() end)
    header.dragArea:SetScript("OnDragStop", function() parentFrame:StopMovingOrSizing() end)

    -- Header Separator Line
    header.separator = parentFrame:CreateTexture(nil, "OVERLAY")
    header.separator:SetTexture(unpack(COLORS.ACCENT))
    header.separator:SetPoint("TOPLEFT", 0, -40)
    header.separator:SetPoint("TOPRIGHT", 0, -40)
    header.separator:SetHeight(1)

    -- Character Dropdown Button
    header.charButton = self:CreateCharacterButton(parentFrame)

    -- Delete Character Button (Hidden by default)
    header.deleteBtn = self:CreateDeleteButton(parentFrame, header.charButton)

    -- Space Counter
    header.spaceCounter = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.spaceCounter:SetPoint("LEFT", header.charButton, "RIGHT", 10, 0)
    header.spaceCounter:SetText("0/0")

    -- Search Box
    header.searchBox = self:CreateSearchBox(parentFrame)

    -- Money Frame
    header.moneyFrame = self:CreateMoneyFrame(parentFrame)

    return header
end

function FrameHeader:CreateCharacterButton(parentFrame)
    local btn = CreateFrame("Button", "ZenBagsCharButton", parentFrame)
    btn:SetSize(120, 20)
    btn:SetPoint("TOPLEFT", 10, -10)
    btn:SetFrameLevel(parentFrame:GetFrameLevel() + 10)

    -- Dropdown arrow texture
    local arrowTex = btn:CreateTexture(nil, "ARTWORK")
    arrowTex:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    arrowTex:SetSize(16, 16)
    arrowTex:SetPoint("RIGHT", -2, 0)
    btn.arrow = arrowTex

    -- Character name text
    local charText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charText:SetPoint("LEFT", 4, 0)
    charText:SetJustifyH("LEFT")
    charText:SetText(UnitName("player"))
    btn.text = charText

    -- Button background (subtle)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0.2, 0.2, 0.2, 0.3)
    bg:Hide()
    btn.bg = bg

    -- Hover effect
    btn:SetScript("OnEnter", function(self)
        self.bg:Show()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Switch Character")
        GameTooltip:AddLine("View bags from other characters on this realm", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self.bg:Hide()
        GameTooltip:Hide()
    end)

    -- Click to show dropdown
    btn:SetScript("OnClick", function()
        NS.Frames:ShowCharacterDropdown()
    end)

    return btn
end

function FrameHeader:CreateDeleteButton(parentFrame, charButton)
    local btn = NS.Utils:CreateFlatButton(parentFrame, "X", 20, 20, function()
        local charKey = NS.Data:GetSelectedCharacter()
        if charKey then
            NS.Data:DeleteCharacterCache(charKey)
            charButton.text:SetText(UnitName("player"))
            NS.Frames.searchBox:SetText("")
            NS.Frames:Update(true)
            print("|cFFFF0000ZenBags:|r Deleted cache for " .. charKey)
        end
    end)
    btn:SetPoint("LEFT", charButton, "RIGHT", 5, 0)
    btn:SetFrameLevel(parentFrame:GetFrameLevel() + 10)

    -- Style the delete button (Red hover)
    btn:SetScript("OnEnter", function(self)
        NS.Utils:CreateBackdrop(self)
        self:SetBackdropColor(0.8, 0.1, 0.1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Delete Character Data")
        GameTooltip:AddLine("Remove cached data for this character.", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.15, 1)
        GameTooltip:Hide()
    end)
    btn:Hide()

    return btn
end

function FrameHeader:CreateSearchBox(parentFrame)
    local searchBox = CreateFrame("EditBox", nil, parentFrame)
    searchBox:SetPoint("TOPLEFT", 20, -50)
    searchBox:SetPoint("TOPRIGHT", -40, -50)
    searchBox:SetHeight(24)
    searchBox:SetAutoFocus(false)
    searchBox:SetFont("Fonts\\FRIZQT__.TTF", 12)
    searchBox:SetTextColor(0.9, 0.9, 0.9, 1)

    -- Simple dark background with border
    NS.Utils:CreateBackdrop(searchBox)
    searchBox:SetBackdropColor(0.15, 0.15, 0.15, 1)
    searchBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        local pool = NS.Pools:GetPool("ItemButton")
        if pool then
            for btn in pairs(pool.active) do
                btn:UpdateSearch(text)
            end
        end
    end)

    -- Search Icon
    local searchIcon = searchBox:CreateTexture(nil, "OVERLAY")
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", searchBox, "LEFT", 5, 0)
    searchIcon:SetVertexColor(0.6, 0.6, 0.6)

    -- Adjust text inset for icon
    searchBox:SetTextInsets(25, 10, 0, 0)

    return searchBox
end

function FrameHeader:CreateMoneyFrame(parentFrame)
    local moneyFrame = CreateFrame("Frame", nil, parentFrame)
    moneyFrame:SetSize(250, 25)
    moneyFrame:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", 15, 18)

    -- Gold
    moneyFrame.goldText = moneyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    moneyFrame.goldText:SetPoint("LEFT", moneyFrame, "LEFT", 0, 0)
    moneyFrame.goldText:SetText("0")

    moneyFrame.goldIcon = moneyFrame:CreateTexture(nil, "ARTWORK")
    moneyFrame.goldIcon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    moneyFrame.goldIcon:SetSize(16, 16)
    moneyFrame.goldIcon:SetPoint("LEFT", moneyFrame.goldText, "RIGHT", 3, 0)

    -- Silver
    moneyFrame.silverText = moneyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    moneyFrame.silverText:SetPoint("LEFT", moneyFrame.goldIcon, "RIGHT", 8, 0)
    moneyFrame.silverText:SetText("0")

    moneyFrame.silverIcon = moneyFrame:CreateTexture(nil, "ARTWORK")
    moneyFrame.silverIcon:SetTexture("Interface\\MoneyFrame\\UI-SilverIcon")
    moneyFrame.silverIcon:SetSize(16, 16)
    moneyFrame.silverIcon:SetPoint("LEFT", moneyFrame.silverText, "RIGHT", 3, 0)

    -- Copper
    moneyFrame.copperText = moneyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    moneyFrame.copperText:SetPoint("LEFT", moneyFrame.silverIcon, "RIGHT", 8, 0)
    moneyFrame.copperText:SetText("0")

    moneyFrame.copperIcon = moneyFrame:CreateTexture(nil, "ARTWORK")
    moneyFrame.copperIcon:SetTexture("Interface\\MoneyFrame\\UI-CopperIcon")
    moneyFrame.copperIcon:SetSize(16, 16)
    moneyFrame.copperIcon:SetPoint("LEFT", moneyFrame.copperText, "RIGHT", 3, 0)

    return moneyFrame
end

function FrameHeader:UpdateMoneyDisplay(moneyFrame, money)
    local gold = floor(money / 10000)
    local silver = floor((money % 10000) / 100)
    local copper = money % 100

    moneyFrame.goldText:SetText(gold)
    moneyFrame.silverText:SetText(silver)
    moneyFrame.copperText:SetText(copper)
end

function FrameHeader:UpdateSpaceCounter(spaceCounter, used, total)
    spaceCounter:SetText(used .. "/" .. total)
end
