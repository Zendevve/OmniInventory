local addonName, NS = ...

NS.FrameContent = {}
local FrameContent = NS.FrameContent

local SECTION_PADDING = 20

-- Render the entire item grid with masonry layout
function FrameContent:Render(parentFrame, contentFrame, query)
    -- Get items based on view mode (cached vs live)
    local allItems = {}

    if NS.Data:IsViewingOtherCharacter() then
        -- Viewing cached character
        parentFrame.deleteBtn:Show()

        -- Get cached inventory or bank items
        if parentFrame.currentView == "bags" then
            allItems = NS.Data:GetCachedInventoryItems()
        else
            allItems = NS.Data:GetCachedBankItems()
        end
    else
        parentFrame.deleteBtn:Hide()

        -- Viewing current character: Load live items + cached offline bank
        allItems = NS.Inventory:GetItems()

        -- If viewing bank and bank is closed, load cached items
        local isOfflineBank = (parentFrame.currentView == "bank" and not NS.Data:IsBankOpen())
        if isOfflineBank then
            local cachedItems = NS.Data:GetCachedBankItems()
            local combinedItems = {}

            -- Only include non-bank items from live inventory
            for _, item in ipairs(allItems) do
                if item.location ~= "bank" then
                    table.insert(combinedItems, item)
                end
            end

            -- Add cached bank items
            for _, item in ipairs(cachedItems) do
                table.insert(combinedItems, item)
            end
            allItems = combinedItems
        end
    end

    -- Filter by location and search query
    local items = {}
    for _, item in ipairs(allItems) do
        if item.location == parentFrame.currentView then
            if query == "" then
                table.insert(items, item)
            else
                local name = GetItemInfo(item.link)
                if name and name:lower():find(query, 1, true) then
                    table.insert(items, item)
                end
            end
        end
    end

    -- Group by Category
    local groups = {}
    for _, item in ipairs(items) do
        local cat = item.category or "Miscellaneous"
        if not groups[cat] then groups[cat] = {} end
        table.insert(groups[cat], item)
    end

    -- Sort Groups by Priority
    local sortedCats = {}
    for cat in pairs(groups) do table.insert(sortedCats, cat) end
    table.sort(sortedCats, function(a, b)
        local collapsedA = NS.Config:IsSectionCollapsed(a)
        local collapsedB = NS.Config:IsSectionCollapsed(b)

        if collapsedA ~= collapsedB then
            return not collapsedA
        end

        local prioA = NS.Categories.Priority[a] or 99
        local prioB = NS.Categories.Priority[b] or 99
        return prioA < prioB
    end)

    -- Object Pooling: Release old buttons and headers
    self:ReleasePooledObjects(parentFrame)

    -- Masonry Layout Configuration
    local ITEM_SIZE = NS.Config:Get("itemSize")
    local PADDING = NS.Config:Get("padding")
    local width = parentFrame.mainFrame:GetWidth()
    local availableWidth = width - 60

    local MIN_SECTION_WIDTH = 300
    local numSectionCols = math.floor(availableWidth / MIN_SECTION_WIDTH)
    if numSectionCols < 1 then numSectionCols = 1 end

    local sectionWidth = availableWidth / numSectionCols
    local itemCols = math.floor((sectionWidth - PADDING) / (ITEM_SIZE + PADDING))
    if itemCols < 1 then itemCols = 1 end

    local sectionGridWidth = itemCols * ITEM_SIZE + (itemCols - 1) * PADDING
    local sectionXOffset = (sectionWidth - sectionGridWidth) / 2
    if sectionXOffset < 0 then sectionXOffset = 0 end

    -- Masonry State
    local colHeights = {}
    for i = 1, numSectionCols do colHeights[i] = 0 end

    -- Render Sections
    local btnIdx = 1

    for _, cat in ipairs(sortedCats) do
        local catItems = groups[cat]

        -- Find shortest column
        local minHeight = colHeights[1]
        local minCol = 1
        for i = 2, numSectionCols do
            if colHeights[i] < minHeight then
                minHeight = colHeights[i]
                minCol = i
            end
        end

        -- Calculate Section Position
        local sectionX = (minCol - 1) * sectionWidth
        local sectionY = minHeight

        -- Create Section Header
        local hdr = self:CreateSectionHeader(parentFrame, contentFrame, cat, catItems, sectionGridWidth, sectionX, sectionXOffset, sectionY)
        table.insert(parentFrame.headers, hdr)

        local currentSectionHeight = 30 -- Header height
        local isCollapsed = NS.Config:IsSectionCollapsed(cat)

        -- Render Items Grid (if not collapsed)
        if not isCollapsed then
            btnIdx = self:RenderItemsGrid(parentFrame, contentFrame, catItems, btnIdx, sectionX, sectionY, sectionXOffset, currentSectionHeight, itemCols, ITEM_SIZE, PADDING)

            -- Calculate section height
            local numRows = math.ceil(#catItems / itemCols)
            local gridHeight = numRows * ITEM_SIZE + (numRows - 1) * PADDING
            currentSectionHeight = currentSectionHeight + gridHeight
        end

        -- Update column height
        colHeights[minCol] = colHeights[minCol] + currentSectionHeight + SECTION_PADDING
    end

    -- Set content height to max column height
    local maxColHeight = 0
    for _, h in ipairs(colHeights) do
        if h > maxColHeight then maxColHeight = h end
    end
    contentFrame:SetHeight(maxColHeight)
end

function FrameContent:ReleasePooledObjects(parentFrame)
    -- Release buttons
    local pool = NS.Pools:GetPool("ItemButton")
    if pool then
        for i = #parentFrame.buttons, 1, -1 do
            local btn = parentFrame.buttons[i]
            if btn then
                pool:Release(btn)
            end
        end
    end
    wipe(parentFrame.buttons)

    -- Release headers
    local headerPool = NS.Pools:GetPool("SectionHeader")
    if headerPool then
        for i = #parentFrame.headers, 1, -1 do
            local hdr = parentFrame.headers[i]
            if hdr then
                headerPool:Release(hdr)
            end
        end
    end
    wipe(parentFrame.headers)
end

function FrameContent:CreateSectionHeader(parentFrame, contentFrame, cat, catItems, sectionGridWidth, sectionX, sectionXOffset, sectionY)
    local headerPool = NS.Pools:GetPool("SectionHeader")
    local hdr = headerPool:Acquire()
    hdr:SetParent(contentFrame)
    hdr:SetWidth(sectionGridWidth)
    hdr:SetPoint("TOPLEFT", sectionX + sectionXOffset, -sectionY)

    -- Check collapsed state
    local isCollapsed = NS.Config:IsSectionCollapsed(cat)

    -- Set text
    if isCollapsed then
        hdr.text:SetText("[+] " .. cat .. " (" .. #catItems .. ")")
    else
        hdr.text:SetText("[-] " .. cat .. " (" .. #catItems .. ")")
    end

    -- Hide icon texture
    hdr.icon:SetTexture(nil)

    -- Ensure header is clickable and on top
    hdr:SetFrameLevel(contentFrame:GetFrameLevel() + 10)
    hdr:RegisterForClicks("AnyUp")

    -- Click handler to toggle
    hdr:SetScript("OnClick", function(self, button)
        -- Only handle right-click clear if mouse is actually over the header
        if button == "RightButton" and cat == "New Items" and MouseIsOver(self) then
            NS.Inventory:ClearAllNewItems()
        elseif button ~= "RightButton" or cat ~= "New Items" then
            -- Left-click or any click on non-New Items headers
            NS.Config:ToggleSectionCollapsed(cat)
            NS.Frames:Update(true)
        end
    end)

    -- Hover effects
    hdr:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 0)  -- Yellow

        if cat == "New Items" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("New Items")
            GameTooltip:AddLine("Right-click to clear all new items.", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    hdr:SetScript("OnLeave", function(self)
        self.text:SetTextColor(1, 1, 1)  -- White
        GameTooltip:Hide()
    end)

    hdr:Show()

    return hdr
end

function FrameContent:RenderItemsGrid(parentFrame, contentFrame, catItems, btnIdx, sectionX, sectionY, sectionXOffset, currentSectionHeight, itemCols, ITEM_SIZE, PADDING)
    for i, itemData in ipairs(catItems) do
        -- Get the dummy bag frame for this item's bag
        local dummyBag = NS.FrameHelpers:GetOrCreateDummyBag(parentFrame.mainFrame, itemData.bagID)

        -- Object Pooling: Acquire button from pool
        local pool = NS.Pools:GetPool("ItemButton")
        local btn = pool:Acquire()

        -- Parent the button to the dummy bag
        btn:SetParent(dummyBag)
        btn:SetSize(ITEM_SIZE, ITEM_SIZE)

        parentFrame.buttons[btnIdx] = btn

        -- Grid Position within Section
        local row = math.floor((i - 1) / itemCols)
        local col = (i - 1) % itemCols

        local itemX = sectionX + sectionXOffset + col * (ITEM_SIZE + PADDING)
        local itemY = sectionY + currentSectionHeight + row * (ITEM_SIZE + PADDING)

        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", itemX, -itemY)

        -- Data
        btn:SetID(itemData.slotID)

        -- Handle Offline vs Live Tooltips
        local isCached = NS.Data:IsCached(itemData.bagID)

        if isCached then
            btn.dummyOverlay:Show()
            btn.dummyOverlay.itemLink = itemData.link
        else
            btn.dummyOverlay:Hide()
        end

        -- Store data for search highlighting
        btn.itemLink = itemData.link

        SetItemButtonTexture(btn, itemData.texture)
        SetItemButtonCount(btn, itemData.count)

        -- Quality/Quest Border
        local isQuestItem, questId, isActive = GetContainerItemQuestInfo(itemData.bagID, itemData.slotID)

        local quality = itemData.quality
        if questId or isQuestItem then
            quality = 4 -- Epic color for quest items
        end

        if btn.UpdateQuality then
            btn:UpdateQuality(quality)
        end

        -- Cooldown
        if btn.cooldown then
            ContainerFrame_UpdateCooldown(itemData.bagID, btn)
        else
            if not btn.Cooldown then
                btn.Cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
                btn.Cooldown:SetAllPoints()
            end
            ContainerFrame_UpdateCooldown(itemData.bagID, btn)
        end

        -- Junk Overlay
        if not btn.junkIcon then
            btn.junkIcon = btn:CreateTexture(nil, "OVERLAY")
            btn.junkIcon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Coin-Up")
            btn.junkIcon:SetPoint("TOPLEFT", 2, -2)
            btn.junkIcon:SetSize(12, 12)
        end
        if itemData.quality == 0 then btn.junkIcon:Show() else btn.junkIcon:Hide() end

        -- Item Level Display
        if btn.ilvl then
            if itemData.iLevel then
                btn.ilvl:SetText(itemData.iLevel)
            else
                btn.ilvl:SetText("")
            end
        end

        -- New Item Highlight
        if NS.Inventory:IsNew(itemData.bagID, itemData.slotID) then
            if not btn.newGlow then
                btn.newGlow = btn:CreateTexture(nil, "OVERLAY")
                btn.newGlow:SetTexture("Interface\\Cooldown\\star4")
                btn.newGlow:SetPoint("CENTER")
                btn.newGlow:SetSize(ITEM_SIZE * 1.8, ITEM_SIZE * 1.8)
                btn.newGlow:SetBlendMode("ADD")
                btn.newGlow:SetVertexColor(1, 1, 0, 0.8)

                -- Animation
                local ag = btn.newGlow:CreateAnimationGroup()
                local spin = ag:CreateAnimation("Rotation")
                spin:SetDegrees(360)
                spin:SetDuration(10)
                ag:SetLooping("REPEAT")
                ag:Play()
                btn.newGlow.ag = ag
            end
            btn.newGlow:Show()
            btn.newGlow.ag:Play()
        else
            if btn.newGlow then
                btn.newGlow:Hide()
                btn.newGlow.ag:Stop()
            end
        end

        -- Store item data reference
        btn.itemData = itemData

        -- Standard Template handles clicks now!
        btn:Show()

        -- Clear New Status on Hover
        btn:SetScript("OnEnter", function(self)
            if self.itemData then
                NS.Inventory:ClearNew(self.itemData.bagID, self.itemData.slotID)
            end

            -- Standard Tooltip
            if self.itemData.location == "bank" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.itemData.link then
                    GameTooltip:SetHyperlink(self.itemData.link)
                end
                GameTooltip:Show()
            else
                ContainerFrameItemButton_OnEnter(self)
            end
        end)

        btn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        btnIdx = btnIdx + 1
    end

    return btnIdx
end
