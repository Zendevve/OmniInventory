-- =============================================================================
-- OmniInventory Tooltip Item Counts Module
-- =============================================================================
-- Purpose: Hooks GameTooltip and ItemRefTooltip to display cross-character
-- item counts (bags, bank) using the SavedVariables database.
-- =============================================================================

local addonName, Omni = ...

local Tooltip = {}
Omni.Tooltip = Tooltip

-- Reusable color codes
local COLOR_TEAL = "|cff00ff9a"
local COLOR_SILVER = "|cffc7c7cf"
local COLOR_GOLD = "|cffffd700"
local COLOR_WHITE = "|cffffffff"
local COLOR_END = "|r"

-- Helper to extract item ID from link
local function GetItemIDFromLink(link)
    if not link then return nil end
    if type(link) == "number" then return link end
    local id = string.match(link, "item:(%d+)")
    return id and tonumber(id) or nil
end

local function AddTooltipData(tooltip, targetItemID)
    if not OmniInventoryDB or not OmniInventoryDB.realm then return end

    local currentRealm = GetRealmName()
    local currentPlayer = UnitName("player")
    local realmData = OmniInventoryDB.realm[currentRealm]
    if not realmData then return end

    local characterCounts = {}
    local grandTotal = 0
    local charAdded = false

    -- Iterate all characters on this realm
    for playerName, charData in pairs(realmData) do
        local bagCount = 0
        if charData.bags then
            for _, item in ipairs(charData.bags) do
                if GetItemIDFromLink(item.link) == targetItemID then
                    bagCount = bagCount + (item.count or 1)
                end
            end
        end

        local bankCount = 0
        if charData.bank then
            for _, item in ipairs(charData.bank) do
                if GetItemIDFromLink(item.link) == targetItemID then
                    bankCount = bankCount + (item.count or 1)
                end
            end
        end

        local total = bagCount + bankCount
        if total > 0 then
            table.insert(characterCounts, {
                name = playerName,
                total = total,
                bags = bagCount,
                bank = bankCount,
                isCurrent = (playerName == currentPlayer)
            })
            grandTotal = grandTotal + total
        end
    end

    -- Query Guild Bank cache
    local guildCounts = {}
    if realmData.guilds then
        for guildName, guildData in pairs(realmData.guilds) do
            local totalGuildCount = 0
            local tabBreakdown = {}
            if guildData.tabs then
                for tabIndex, tabInfo in pairs(guildData.tabs) do
                    local tabCount = 0
                    if tabInfo.items then
                        for _, item in ipairs(tabInfo.items) do
                            if GetItemIDFromLink(item.link) == targetItemID then
                                tabCount = tabCount + (item.count or 1)
                            end
                        end
                    end
                    if tabCount > 0 then
                        totalGuildCount = totalGuildCount + tabCount
                        table.insert(tabBreakdown, (tabInfo.name or ("Tab " .. tabIndex)) .. ": " .. tabCount)
                    end
                end
            end
            if totalGuildCount > 0 then
                table.insert(guildCounts, {
                    name = guildName,
                    total = totalGuildCount,
                    breakdown = table.concat(tabBreakdown, ", ")
                })
                grandTotal = grandTotal + totalGuildCount
            end
        end
    end

    -- Check junk include/exclude status
    local hasJunkStatus = false
    local isIncluded = false
    local isExcluded = false
    if Omni.Features and Omni.Features.IsJunkItem then
        local exclude = Omni.Data and Omni.Data:Get("junkExclude") or {}
        local include = Omni.Data and Omni.Data:Get("junkInclude") or {}
        if include[targetItemID] then
            isIncluded = true
            hasJunkStatus = true
        elseif exclude[targetItemID] then
            isExcluded = true
            hasJunkStatus = true
        end
    end

    if #characterCounts == 0 and #guildCounts == 0 and not hasJunkStatus then return end

    -- Sort current player first, then others alphabetically
    if #characterCounts > 0 then
        table.sort(characterCounts, function(a, b)
            if a.isCurrent ~= b.isCurrent then
                return a.isCurrent
            end
            return a.name < b.name
        end)
    end

    -- Add a blank separator line if there are other lines
    tooltip:AddLine(" ")

    -- Render Junk Status
    if hasJunkStatus then
        if isIncluded then
            tooltip:AddDoubleLine(COLOR_SILVER .. "Junk Status:" .. COLOR_END, "|cffff4040Auto-Sold (Junk List)|r")
        elseif isExcluded then
            tooltip:AddDoubleLine(COLOR_SILVER .. "Junk Status:" .. COLOR_END, "|cff40ff40Protected (Excluded)|r")
        end
        charAdded = true
    end

    -- Render character counts
    for _, data in ipairs(characterCounts) do
        local nameStr = COLOR_TEAL .. data.name .. COLOR_END
        if data.isCurrent then
            nameStr = COLOR_WHITE .. data.name .. " (You)" .. COLOR_END
        end

        local countStr
        if data.bags > 0 and data.bank > 0 then
            countStr = COLOR_GOLD .. data.total .. COLOR_END .. COLOR_SILVER .. " (" .. data.bags .. " Bags, " .. data.bank .. " Bank)" .. COLOR_END
        elseif data.bags > 0 then
            countStr = COLOR_GOLD .. data.bags .. COLOR_END .. COLOR_SILVER .. " (Bags)" .. COLOR_END
        else
            countStr = COLOR_GOLD .. data.bank .. COLOR_END .. COLOR_SILVER .. " (Bank)" .. COLOR_END
        end

        tooltip:AddDoubleLine(nameStr, countStr)
        charAdded = true
    end

    -- Render guild counts
    for _, data in ipairs(guildCounts) do
        local nameStr = COLOR_TEAL .. data.name .. " (Guild)" .. COLOR_END
        local countStr = COLOR_GOLD .. data.total .. COLOR_END
        if data.breakdown ~= "" then
            countStr = countStr .. COLOR_SILVER .. " (" .. data.breakdown .. ")" .. COLOR_END
        end
        tooltip:AddDoubleLine(nameStr, countStr)
        charAdded = true
    end

    -- Add grand total if multiple characters/guilds have the item
    local totalSources = #characterCounts + #guildCounts
    if totalSources > 1 and grandTotal > 0 then
        tooltip:AddDoubleLine(
            COLOR_SILVER .. "Total:" .. COLOR_END,
            COLOR_GOLD .. grandTotal .. COLOR_END
        )
    end

    if charAdded then
        tooltip:Show()
    end
end

local function HookTooltip(tooltip)
    if not tooltip then return end

    tooltip:HookScript("OnTooltipSetItem", function(self)
        local _, link = self:GetItem()
        if not link then return end

        local itemID = GetItemIDFromLink(link)
        if not itemID then return end

        -- Prevent double appending in same draw pass
        if self._omniInventoryAdded == itemID then
            return
        end
        self._omniInventoryAdded = itemID

        AddTooltipData(self, itemID)
    end)

    tooltip:HookScript("OnTooltipCleared", function(self)
        self._omniInventoryAdded = nil
    end)
end

-- Hook default tooltips
HookTooltip(GameTooltip)
HookTooltip(ItemRefTooltip)
