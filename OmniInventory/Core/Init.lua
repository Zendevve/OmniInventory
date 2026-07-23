-- =============================================================================
-- OmniInventory Core/Init.lua
-- Addon Bootstrap, Namespace Allocation, Versioning, Defaults & Core Frame
-- =============================================================================

local addonName, Omni = ...
if not Omni then
    Omni = {}
    _G.OmniInventory = Omni
    _G.Omni = Omni
else
    _G.OmniInventory = Omni
    _G.Omni = Omni
end

-- Addon Metadata & Versioning
Omni.addonName = addonName or "OmniInventory"
Omni.VERSION = "2.1.0"
Omni.BUILD = 30300 -- WotLK 3.3.5a Client Build Target
Omni.AUTHOR = "Zendevve"

-- Global Constants
Omni.BAG_BACKPACK = 0
Omni.BAG_BANK = -1
Omni.KEYRING_BAG = -2
Omni.NUM_BAG_SLOTS = 4
Omni.NUM_BANK_SLOTS = 7

-- Layout Modes
Omni.LAYOUT_MODE_FLOW = 1
Omni.LAYOUT_MODE_GRID = 2
Omni.LAYOUT_MODE_LIST = 3

-- Module Pipeline
Omni.modules = Omni.modules or {}

function Omni:RegisterModule(name, moduleTable)
    if not name or type(name) ~= "string" then return end
    moduleTable = moduleTable or {}
    moduleTable.name = name
    self.modules[name] = moduleTable
    if self.debug then
        self:Print("Registered module: " .. name)
    end
    return moduleTable
end

function Omni:GetModule(name)
    return self.modules[name]
end

function Omni:Print(msg, ...)
    if msg then
        local text = string.format(msg, ...)
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[OmniInventory]|r " .. text)
        end
    end
end

-- Default Settings Matrix
Omni.Defaults = {
    profile = {
        layoutMode = Omni.LAYOUT_MODE_FLOW,
        slotSize = 36,
        spacing = 4,
        maxColumns = 10,
        sortOrder = "QUALITY_DESC",
        autoVendor = true,
        autoRepair = true,
        useGuildFunds = true,
        autoClam = true,
        showMinimapButton = true,
        minimapPos = 45,
    }
}

-- Core Event Frame Setup
local coreFrame = CreateFrame("Frame", "OmniInventoryCore", UIParent)
Omni.coreFrame = coreFrame

local function OnCoreEvent(self, event, arg1, ...)
    if event == "ADDON_LOADED" and (arg1 == addonName or arg1 == "OmniInventory") then
        -- Initialize SavedVariables schema if not present
        if not _G.OmniInventoryDB then
            _G.OmniInventoryDB = {
                version = Omni.VERSION,
                realms = {}
            }
        end
        Omni:Print("Loaded v" .. Omni.VERSION .. " (WotLK 3.3.5a). Type /omni for options.")
    elseif event == "PLAYER_LOGIN" then
        -- Trigger module initializations
        for name, mod in pairs(Omni.modules) do
            if type(mod.OnInitialize) == "function" then
                mod:OnInitialize()
            end
        end
    end
end

coreFrame:RegisterEvent("ADDON_LOADED")
coreFrame:RegisterEvent("PLAYER_LOGIN")
coreFrame:SetScript("OnEvent", OnCoreEvent)
