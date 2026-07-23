-- =============================================================================
-- OmniInventory AutoRepair Module
-- =============================================================================
-- Purpose: Guild vs player fund priority repair module for WoW 3.3.5a
-- WoTLK 3.3.5a Compatible - Uses only native APIs
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or {}

local AutoRepair = {
    enabled = true,
    useGuildFunds = true,
}
Omni.AutoRepair = AutoRepair

local frame = CreateFrame("Frame", "OmniAutoRepairFrame")

local function FormatMoney(copper)
    if not copper or copper <= 0 then return "0c" end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop = copper % 100

    local result = ""
    if gold > 0 then
        result = result .. string.format("%dg ", gold)
    end
    if silver > 0 or gold > 0 then
        result = result .. string.format("%ds ", silver)
    end
    if cop > 0 or (gold == 0 and silver == 0) then
        result = result .. string.format("%dc", cop)
    end
    return (result:gsub("%s+$", ""))
end

function AutoRepair:ExecuteRepair()
    if not self.enabled then return end
    if not CanMerchantRepair or not CanMerchantRepair() then return end

    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return end

    local formattedCost = FormatMoney(cost)

    -- Guild Fund Repair Priority
    if self.useGuildFunds and CanGuildBankRepair and CanGuildBankRepair() then
        local guildBankMoney = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or -1
        if guildBankMoney == -1 or guildBankMoney >= cost then
            RepairAllItems(1)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("[OK] Repaired all items using Guild Funds (cost: %s)", formattedCost))
            return
        end
    end

    -- Player Fund Repair Fallback
    local playerMoney = GetMoney()
    if playerMoney >= cost then
        RepairAllItems(0)
        DEFAULT_CHAT_FRAME:AddMessage(string.format("[OK] Repaired all items using Player Funds (cost: %s)", formattedCost))
    else
        DEFAULT_CHAT_FRAME:AddMessage(string.format("[!] Insufficient funds to repair all items (cost: %s)", formattedCost))
    end
end

frame:RegisterEvent("MERCHANT_SHOW")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "MERCHANT_SHOW" then
        AutoRepair:ExecuteRepair()
    end
end)
