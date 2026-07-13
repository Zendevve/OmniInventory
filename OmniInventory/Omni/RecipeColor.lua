-- =============================================================================
-- OmniInventory Known Recipe Coloring
-- =============================================================================
-- Colors item icons green in bag/bank/mailbox/inbox/trade/loot/merchant
-- when the item is a recipe the player has already learned.
-- Pattern based on the RecipeColor reference addon.
-- =============================================================================

local addonName, Omni = ...

Omni.RecipeColor = {}
local RecipeColor = Omni.RecipeColor

local GREEN_R, GREEN_G, GREEN_B = 0, 1, 0

local scanLines = {}

local function InitScanLines()
    wipe(scanLines)
    for i = 1, 30 do
        local line = _G["OmniScanningTooltipTextLeft" .. i]
        if line then
            scanLines[i] = line
        else
            break
        end
    end
end

local function GetItemIDFromLink(link)
    if link then
        local _, _, id = string.find(link, "|c%x+|Hitem:(%d+):")
        if id then return tonumber(id) end
    end
    return nil
end

function RecipeColor:IsRecipeItem(itemID)
    if not itemID or itemID <= 0 then return false end
    local _, _, _, _, _, itemClass = GetItemInfo(itemID)
    return itemClass == "Recipe"
end

function RecipeColor:IsRecipeItemByLink(link)
    local itemID = GetItemIDFromLink(link)
    return self:IsRecipeItem(itemID)
end

local function HasAlreadyKnownLine()
    local tooltip = _G["OmniScanningTooltip"]
    if not tooltip then return false end
    local numLines = tooltip:NumLines()
    for i = 1, numLines do
        local line = scanLines[i]
        local text = line and line:GetText()
        if text and string.find(text, "Already known") then
            return true
        end
    end
    return false
end

function RecipeColor:IsKnownRecipeByLink(link)
    if not link then return false end
    local tooltip = _G["OmniScanningTooltip"]
    if not tooltip then return false end
    tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tooltip:ClearLines()
    tooltip:SetHyperlink(link)
    return HasAlreadyKnownLine()
end

function RecipeColor:IsKnownRecipe(bag, slot)
    local tooltip = _G["OmniScanningTooltip"]
    if not tooltip then return false end
    tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tooltip:ClearLines()
    if bag == BANK_CONTAINER then
        tooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(slot))
    elseif bag == "GuildBank" then
        tooltip:SetGuildBankItem(slot[1], slot[2])
    elseif bag == "Merchant" then
        tooltip:SetMerchantItem(slot)
    elseif bag == "Buyback" then
        tooltip:SetBuybackItem(slot)
    elseif bag == "MailBox" then
        tooltip:SetInboxItem(slot[1], slot[2])
    elseif bag == "MailBoxOpen" then
        local mailID = InboxFrame and InboxFrame.openMailID
        if not mailID or mailID == 0 then return false end
        tooltip:SetInboxItem(mailID, slot)
    else
        tooltip:SetBagItem(bag, slot)
    end
    return HasAlreadyKnownLine()
end

function RecipeColor:IsEnabled()
    return OmniInventoryDB
        and OmniInventoryDB.global
        and OmniInventoryDB.global.enableKnownRecipeOverlay ~= false
end

-- =============================================================================
-- Blizzard Native Frames: Mail Inbox
-- =============================================================================

function RecipeColor:ColorKnownRecipesInMail()
    if not MailFrame or not MailFrame:IsVisible() then return end
    local numItems = GetInboxNumItems()
    local pageNum  = InboxFrame.pageNum or 1
    local startIdx = (pageNum - 1) * INBOXITEMS_TO_DISPLAY + 1
    for frameSlot = 1, INBOXITEMS_TO_DISPLAY do
        local mailIndex = startIdx + (frameSlot - 1)
        if mailIndex > numItems then break end
        local _, _, _, _, _, _, _, itemCount, wasRead = GetInboxHeaderInfo(mailIndex)
        local icon = _G["MailItem" .. frameSlot .. "ButtonIcon"]
        if not icon then break end
        local isKnown = false
        if itemCount and itemCount > 0 then
            for attachIndex = 1, ATTACHMENTS_MAX_RECEIVE do
                local link = GetInboxItemLink(mailIndex, attachIndex)
                if link and self:IsRecipeItemByLink(link) and self:IsKnownRecipeByLink(link) then
                    isKnown = true
                    break
                end
            end
        end
        if isKnown then
            SetDesaturation(icon, nil)
            icon:SetVertexColor(GREEN_R, GREEN_G, GREEN_B)
        else
            icon:SetVertexColor(1, 1, 1)
            SetDesaturation(icon, wasRead and 1 or nil)
        end
    end
end

function RecipeColor:ColorKnownRecipesInOpenMail()
    if not OpenMailFrame or not OpenMailFrame:IsVisible() then return end
    local mailID = InboxFrame and InboxFrame.openMailID
    if not mailID or mailID == 0 then return end
    for attachIndex = 1, ATTACHMENTS_MAX_RECEIVE do
        local link = GetInboxItemLink(mailID, attachIndex)
        if link then
            local btn = _G["OpenMailAttachmentButton" .. attachIndex]
            if btn and btn:IsShown() then
                if self:IsKnownRecipeByLink(link) then
                    SetItemButtonTextureVertexColor(btn, GREEN_R, GREEN_G, GREEN_B)
                    if attachIndex == 1 and OpenMailPackageButton then
                        SetItemButtonTextureVertexColor(OpenMailPackageButton, GREEN_R, GREEN_G, GREEN_B)
                    end
                end
            end
        end
    end
end

-- =============================================================================
-- Blizzard Native Frames: Trade
-- =============================================================================

function RecipeColor:ColorKnownRecipesInTrade()
    if not TradeFrame or not TradeFrame:IsVisible() then return end
    local tooltip = _G["OmniScanningTooltip"]
    if not tooltip then return end
    for id = 1, MAX_TRADE_ITEMS do
        local pb = _G["TradePlayerItem" .. id .. "ItemButton"]
        if pb then SetItemButtonTextureVertexColor(pb, 1, 1, 1) end
        local rb = _G["TradeRecipientItem" .. id .. "ItemButton"]
        if rb then SetItemButtonTextureVertexColor(rb, 1, 1, 1) end
    end
    for id = 1, MAX_TRADE_ITEMS do
        local pb = _G["TradePlayerItem" .. id .. "ItemButton"]
        if pb and pb.hasItem then
            tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
            tooltip:ClearLines()
            tooltip:SetTradePlayerItem(id)
            for i = 1, tooltip:NumLines() do
                local line = scanLines[i]
                local text = line and line:GetText()
                if text and string.find(text, "Already known") then
                    SetItemButtonTextureVertexColor(pb, GREEN_R, GREEN_G, GREEN_B)
                    break
                end
            end
        end
        local rb = _G["TradeRecipientItem" .. id .. "ItemButton"]
        if rb and GetTradeTargetItemInfo(id) then
            tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
            tooltip:ClearLines()
            tooltip:SetTradeTargetItem(id)
            for i = 1, tooltip:NumLines() do
                local line = scanLines[i]
                local text = line and line:GetText()
                if text and string.find(text, "Already known") then
                    SetItemButtonTextureVertexColor(rb, GREEN_R, GREEN_G, GREEN_B)
                    break
                end
            end
        end
    end
end

-- =============================================================================
-- Blizzard Native Frames: Loot
-- =============================================================================

function RecipeColor:ColorKnownRecipesInLoot()
    if not LootFrame or not LootFrame:IsVisible() then return end
    local tooltip = _G["OmniScanningTooltip"]
    if not tooltip then return end
    for i = 1, LOOTFRAME_NUMBUTTONS do
        local button = _G["LootButton" .. i]
        if button then SetItemButtonTextureVertexColor(button, 1, 1, 1) end
    end
    for i = 1, LOOTFRAME_NUMBUTTONS do
        local button = _G["LootButton" .. i]
        if button and button:IsVisible() and button.slot then
            if LootSlotIsItem(button.slot) then
                local link = GetLootSlotLink(button.slot)
                if link and self:IsRecipeItemByLink(link) then
                    tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
                    tooltip:ClearLines()
                    tooltip:SetLootItem(button.slot)
                    for j = 1, tooltip:NumLines() do
                        local line = scanLines[j]
                        local text = line and line:GetText()
                        if text and string.find(text, "Already known") then
                            SetItemButtonTextureVertexColor(button, GREEN_R, GREEN_G, GREEN_B)
                            break
                        end
                    end
                end
            end
        end
    end
end

-- =============================================================================
-- Blizzard Native Frames: Merchant
-- =============================================================================

function RecipeColor:ColorKnownRecipesAtMerchant()
    if not MerchantFrame or not MerchantFrame:IsVisible() then return end
    local numMerchantItems = GetMerchantNumItems()
    for i = 1, MERCHANT_ITEMS_PER_PAGE do
        local index = ((MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE) + i
        if index <= numMerchantItems then
            if self:IsKnownRecipe("Merchant", index) then
                local itemButton     = _G["MerchantItem" .. i .. "ItemButton"]
                local merchantButton = _G["MerchantItem" .. i]
                SetItemButtonNameFrameVertexColor(merchantButton, GREEN_R, GREEN_G, GREEN_B)
                SetItemButtonSlotVertexColor(merchantButton, GREEN_R, GREEN_G, GREEN_B)
                SetItemButtonTextureVertexColor(itemButton, GREEN_R, GREEN_G, GREEN_B)
                SetItemButtonNormalTextureVertexColor(itemButton, GREEN_R, GREEN_G, GREEN_B)
            end
        end
    end
end

local BUYBACK_ITEMS_PER_PAGE = 12
local greenBuybackButtons = {}
local greenBuybackSlot = false

function RecipeColor:ColorKnownRecipesInBuybackTab()
    if not MerchantFrame or not MerchantFrame:IsVisible() then return end
    for btn in pairs(greenBuybackButtons) do
        SetItemButtonTextureVertexColor(btn, 1, 1, 1)
    end
    greenBuybackButtons = {}
    local numBuyback = GetNumBuybackItems()
    for i = 1, BUYBACK_ITEMS_PER_PAGE do
        local itemButton     = _G["MerchantItem" .. i .. "ItemButton"]
        local merchantButton = _G["MerchantItem" .. i]
        if itemButton and i <= numBuyback and GetBuybackItemInfo(i) and self:IsKnownRecipe("Buyback", i) then
            SetItemButtonNameFrameVertexColor(merchantButton, GREEN_R, GREEN_G, GREEN_B)
            SetItemButtonSlotVertexColor(merchantButton, GREEN_R, GREEN_G, GREEN_B)
            SetItemButtonTextureVertexColor(itemButton, GREEN_R, GREEN_G, GREEN_B)
            SetItemButtonNormalTextureVertexColor(itemButton, GREEN_R, GREEN_G, GREEN_B)
            greenBuybackButtons[itemButton] = true
        end
    end
end

function RecipeColor:ColorKnownRecipesInBuybackSlot()
    if not MerchantFrame or not MerchantFrame:IsVisible() then return end
    local bbButton = _G["MerchantBuyBackItemItemButton"]
    if not bbButton then return end
    if greenBuybackSlot then
        SetItemButtonTextureVertexColor(bbButton, 1, 1, 1)
        greenBuybackSlot = false
    end
    local bbIndex = GetNumBuybackItems()
    if bbIndex > 0 and GetBuybackItemInfo(bbIndex) and self:IsKnownRecipe("Buyback", bbIndex) then
        SetItemButtonTextureVertexColor(bbButton, GREEN_R, GREEN_G, GREEN_B)
        greenBuybackSlot = true
    end
end

-- =============================================================================
-- Initialization
-- =============================================================================

function RecipeColor:Init()
    if self._initialized then return end
    self._initialized = true

    InitScanLines()

    -- MAIL HOOKS
    if InboxFrame_Update then
        local origInbox = InboxFrame_Update
        _G["InboxFrame_Update"] = function(...)
            origInbox(...)
            if RecipeColor:IsEnabled() then
                RecipeColor:ColorKnownRecipesInMail()
            end
        end
    end
    if OpenMail_Update then
        local origOpenMail = OpenMail_Update
        _G["OpenMail_Update"] = function(...)
            origOpenMail(...)
            if not RecipeColor:IsEnabled() then return end
            if OpenMailPackageButton then
                SetItemButtonTextureVertexColor(OpenMailPackageButton, 1, 1, 1)
            end
            for j = 1, ATTACHMENTS_MAX_RECEIVE do
                local btn = _G["OpenMailAttachmentButton" .. j]
                if btn then SetItemButtonTextureVertexColor(btn, 1, 1, 1) end
            end
            RecipeColor:ColorKnownRecipesInOpenMail()
        end
    end

    -- TRADE HOOKS
    if TradeFrame_Update then
        local origTrade = TradeFrame_Update
        _G["TradeFrame_Update"] = function(...)
            origTrade(...)
            if RecipeColor:IsEnabled() then
                RecipeColor:ColorKnownRecipesInTrade()
            end
        end
    end
    if TradeFrame_UpdatePlayerItem then
        local origTP = TradeFrame_UpdatePlayerItem
        _G["TradeFrame_UpdatePlayerItem"] = function(...)
            origTP(...)
            if RecipeColor:IsEnabled() then
                RecipeColor:ColorKnownRecipesInTrade()
            end
        end
    end
    if TradeFrame_UpdateTargetItem then
        local origTT = TradeFrame_UpdateTargetItem
        _G["TradeFrame_UpdateTargetItem"] = function(...)
            origTT(...)
            if RecipeColor:IsEnabled() then
                RecipeColor:ColorKnownRecipesInTrade()
            end
        end
    end

    -- LOOT HOOK
    if LootFrame_Update then
        local origLoot = LootFrame_Update
        _G["LootFrame_Update"] = function(...)
            origLoot(...)
            if RecipeColor:IsEnabled() then
                RecipeColor:ColorKnownRecipesInLoot()
            end
        end
    end

    -- MERCHANT HOOKS
    if MerchantFrame_Update then
        local origMerchant = MerchantFrame_Update
        _G["MerchantFrame_Update"] = function(...)
            origMerchant(...)
            if not RecipeColor:IsEnabled() then return end
            if MerchantFrame.selectedTab == 2 then
                RecipeColor:ColorKnownRecipesInBuybackTab()
            else
                RecipeColor:ColorKnownRecipesAtMerchant()
                RecipeColor:ColorKnownRecipesInBuybackSlot()
            end
        end
    end
end
