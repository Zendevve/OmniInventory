-- =============================================================================
-- OmniInventory AutoContainer Module
-- =============================================================================
-- Purpose: Auto clam / locked box opener queue with secure action button
-- WoTLK 3.3.5a Compatible - Uses only native APIs
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or {}

local AutoContainer = {
    enabled = true,
    queue = {},
    -- Known openable clams / containers
    targetItems = {
        [5523]  = "Small Barnacle",
        [5524]  = "Big Clam",
        [7973]  = "Soft-shelled Clam",
        [15874] = "Thick-shelled Clam",
        [24477] = "Jagged Clam",
        [4632]  = "Giant Clam",
        [44700] = "Abyssal Clam",
        [16885] = "Heavy Junkbox",
        [29569] = "Strong Junkbox",
        [43575] = "Reinforced Junkbox",
    }
}
Omni.AutoContainer = AutoContainer

-- Secure Action Macro Button for combat-safe item execution
local secureBtn = CreateFrame("Button", "OmniAutoClamButton", UIParent, "SecureActionButtonTemplate")
secureBtn:SetAttribute("type", "macro")
secureBtn:Hide()

local frame = CreateFrame("Frame", "OmniAutoContainerFrame")

function AutoContainer:ScanInventory()
    self.queue = {}
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local _, count, locked, _, _, _, link = GetContainerItemInfo(bag, slot)
            if link and not locked then
                local itemID = tonumber(link:match("item:(%d+)"))
                if itemID and self.targetItems[itemID] then
                    table.insert(self.queue, {
                        bag = bag,
                        slot = slot,
                        itemID = itemID,
                        name = self.targetItems[itemID],
                        count = count or 1,
                    })
                end
            end
        end
    end
    self:UpdateSecureButton()
end

function AutoContainer:UpdateSecureButton()
    if InCombatLockdown() then return end

    if #self.queue > 0 then
        local nextItem = self.queue[1]
        secureBtn:SetAttribute("macrotext", string.format("/use %s", nextItem.name))
    else
        secureBtn:SetAttribute("macrotext", "")
    end
end

function AutoContainer:OpenNextContainer()
    if not self.enabled then return end
    if InCombatLockdown() then
        DEFAULT_CHAT_FRAME:AddMessage("[!] OmniInventory: Cannot open containers in combat.")
        return
    end

    self:ScanInventory()

    if #self.queue == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("[OK] OmniInventory: No openable containers found.")
        return
    end

    local item = self.queue[1]
    DEFAULT_CHAT_FRAME:AddMessage(string.format("[OK] Opening container: %s", item.name))
    UseContainerItem(item.bag, item.slot)
end

frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" or event == "BAG_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
        AutoContainer:ScanInventory()
    end
end)
