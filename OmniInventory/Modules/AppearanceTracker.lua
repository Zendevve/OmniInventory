-- =============================================================================
-- OmniInventory AppearanceTracker Module
-- =============================================================================
-- Purpose: ChromieCraft appearance collection tracker (WoTLK 3.3.5a)
-- 3.3.5a has no client-side transmog collection API; the collection lives on
-- the server and the only unlock signal is the chat message the server prints
-- when an item's appearance is added. This module mirrors that collection
-- locally (per realm) so bag icons and tooltips can show whether an item's
-- appearance is already collected without equipping it.
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or {}

local AppearanceTracker = {}
Omni.AppearanceTracker = AppearanceTracker

-- Keywords that identify an appearance unlock message. ChromieCraft
-- messages look like "Appearance added to your collection: [item link]".
local UNLOCK_KEYWORDS = { "appearance", "collection", "transmog" }

local function ExtractItemID(text)
    if not text then return nil end
    local itemID = string.match(text, "item:(%d+)")
    return itemID and tonumber(itemID) or nil
end

local function LooksLikeUnlockMessage(text)
    if not text then return false end
    local lower = string.lower(text)
    for i = 1, #UNLOCK_KEYWORDS do
        if string.find(lower, UNLOCK_KEYWORDS[i], 1, true) then
            return true
        end
    end
    return false
end

function AppearanceTracker:IsEnabled()
    return OmniInventoryDB and OmniInventoryDB.global
        and OmniInventoryDB.global.appearanceTracker ~= false
end

function AppearanceTracker:GetCollection(realmName)
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.appearances = OmniInventoryDB.appearances or {}
    realmName = realmName or GetRealmName()
    OmniInventoryDB.appearances[realmName] = OmniInventoryDB.appearances[realmName] or {}
    return OmniInventoryDB.appearances[realmName]
end

-- Currently equipped items are always in the collection: equipping them
-- unlocks the appearance server-side, so the live equip scan catches gear
-- that was put on before the tracker started recording.
function AppearanceTracker:IsCollected(itemID)
    if not itemID then return false end
    if self.equipped and self.equipped[itemID] then return true end
    local collection = OmniInventoryDB and OmniInventoryDB.appearances
        and OmniInventoryDB.appearances[GetRealmName()]
    return collection and collection[itemID] == true or false
end

-- Only armor and weapons with a real equip slot have appearances.
function AppearanceTracker:CanHaveAppearance(link)
    if not link then return false end
    local ok, _, _, _, _, _, class, _, _, equipSlot = pcall(GetItemInfo, link)
    if not ok or not class then return false end
    if class ~= "Armor" and class ~= "Weapon" then return false end
    if not equipSlot or equipSlot == "" or equipSlot == "INVTYPE_BAG"
            or equipSlot == "INVTYPE_NON_EQUIP" then
        return false
    end
    return true
end

function AppearanceTracker:RecordUnlock(itemID)
    if not itemID then return false end
    local collection = self:GetCollection()
    if collection[itemID] then return false end
    collection[itemID] = true
    return true
end

function AppearanceTracker:RefreshEquipped()
    local equipped = {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local itemID = ExtractItemID(link)
            if itemID then equipped[itemID] = true end
        end
    end
    self.equipped = equipped
end

function AppearanceTracker:SeedFromEquipped()
    local added = 0
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local itemID = ExtractItemID(link)
            if itemID and self:RecordUnlock(itemID) then
                added = added + 1
            end
        end
    end
    self:RefreshEquipped()
    return added
end

function AppearanceTracker:Count()
    local collection = OmniInventoryDB and OmniInventoryDB.appearances
        and OmniInventoryDB.appearances[GetRealmName()]
    local count = 0
    if collection then
        for _ in pairs(collection) do
            count = count + 1
        end
    end
    return count
end

function AppearanceTracker:Reset()
    local collection = OmniInventoryDB and OmniInventoryDB.appearances
        and OmniInventoryDB.appearances[GetRealmName()]
    local count = 0
    if collection then
        for _ in pairs(collection) do
            count = count + 1
        end
        table.wipe(collection)
    end
    return count
end

local function RefreshOpenFrames()
    if Omni.Frame and Omni.Frame.IsShown and Omni.Frame:IsShown() then
        Omni.Frame:UpdateLayout(nil, { reason = "appearance_tracker" })
    end
end

-- =============================================================================
-- Event Handling
-- =============================================================================

local trackerFrame = CreateFrame("Frame", "OmniAppearanceTrackerFrame")
trackerFrame:RegisterEvent("CHAT_MSG_SYSTEM")
trackerFrame:RegisterEvent("CHAT_MSG_LOOT")
trackerFrame:RegisterEvent("PLAYER_LOGIN")
trackerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
trackerFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
trackerFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "CHAT_MSG_SYSTEM" or event == "CHAT_MSG_LOOT" then
        if not AppearanceTracker:IsEnabled() then return end
        if not LooksLikeUnlockMessage(arg1) then return end
        local itemID = ExtractItemID(arg1)
        if itemID and AppearanceTracker:RecordUnlock(itemID) then
            RefreshOpenFrames()
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        AppearanceTracker:RefreshEquipped()
        RefreshOpenFrames()
    elseif event == "PLAYER_LOGIN" then
        AppearanceTracker:RefreshEquipped()
        if AppearanceTracker:IsEnabled() then
            AppearanceTracker:SeedFromEquipped()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        AppearanceTracker:RefreshEquipped()
    end
end)

return AppearanceTracker
