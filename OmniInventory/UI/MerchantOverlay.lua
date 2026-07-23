-- =============================================================================
-- OmniInventory MerchantOverlay Component
-- =============================================================================
-- Purpose: Merchant sell protection guard rails for Rare/Epic, Equipment Sets, and Locked items
-- WoTLK 3.3.5a Compatible - Uses only native APIs
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or {}

local MerchantOverlay = {
    enabled = true,
    minProtectedQuality = 3, -- Rare (3) and Epic (4+)
    manualLocks = {}, -- Manually locked itemIDs
}
Omni.MerchantOverlay = MerchantOverlay

function MerchantOverlay:IsItemInEquipmentSet(itemLink)
    if not itemLink or not GetEquipmentSetLocations then return false end
    local equipmentSets = GetEquipmentSetLocations()
    if not equipmentSets then return false end

    for setName, location in pairs(equipmentSets) do
        if location then
            local player, bank, bags, slot, bag = EquipmentManager_UnpackLocation(location)
            if bags and bag and slot then
                local link = GetContainerItemLink(bag, slot)
                if link and link == itemLink then
                    return true
                end
            end
        end
    end
    return false
end

function MerchantOverlay:IsProtected(bag, slot, itemLink, quality)
    if not self.enabled then return false end
    if not itemLink and bag and slot then
        itemLink = GetContainerItemLink(bag, slot)
    end
    if not itemLink then return false end

    if not quality then
        _, _, quality = GetItemInfo(itemLink)
    end

    -- 1. Quality check (Quality >= 3: Rare/Epic/Legendary)
    if quality and quality >= self.minProtectedQuality then
        return true
    end

    -- 2. Manual lock check
    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if itemID and self.manualLocks[itemID] then
        return true
    end

    -- 3. Equipment set item check
    if self:IsItemInEquipmentSet(itemLink) then
        return true
    end

    return false
end

function MerchantOverlay:PlayErrorSound()
    if PlaySoundFile then
        pcall(PlaySoundFile, "Sound\\Interface\\UI_70_OBLITERUM_FORGE_ERROR.ogg")
    end
    PlaySound("igQuestFailed")
end

function MerchantOverlay:TriggerProtectionAlert(itemLink)
    self:PlayErrorSound()
    local itemName = itemLink and GetItemInfo(itemLink) or itemLink or "Item"
    DEFAULT_CHAT_FRAME:AddMessage(string.format("[!] Protected Item: Cannot sell %s", itemLink or itemName))
end

-- Safely monitor container item selling actions when MerchantFrame is open using hooksecurefunc
if hooksecurefunc then
    hooksecurefunc("UseContainerItem", function(bag, slot, onSelf)
        if MerchantFrame and MerchantFrame:IsShown() and bag and slot then
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, quality = GetItemInfo(link)
                if MerchantOverlay:IsProtected(bag, slot, link, quality) then
                    MerchantOverlay:TriggerProtectionAlert(link)
                end
            end
        end
    end)
end
