-- =============================================================================
-- OmniInventory Core/SlashCommands.lua
-- CLI Command Parsing & Handler Dispatch
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or _G.OmniInventory or _G.Omni

local SlashCommands = {}
Omni.SlashCommands = SlashCommands

local function PrintHelp()
    Omni:Print("Commands:")
    Omni:Print("  /omni toggle   -> Toggle Main Inventory Container")
    Omni:Print("  /omni bank     -> Toggle Bank Container")
    Omni:Print("  /omni config   -> Open Configuration Panel")
    Omni:Print("  /omni reset    -> Reset UI Layout and Frame Positions")
    Omni:Print("  /omni debug    -> Toggle Debug Diagnostic Mode")
    Omni:Print("  /omni profiler -> Toggle Live Performance Profiler HUD")
    Omni:Print("  /omni perf     -> Toggle Live Performance Profiler HUD")
end

local function SlashHandler(msg)
    local cmd, rest = string.match(msg or "", "^%s*(%S+)%s*(.-)$")
    cmd = string.lower(cmd or "")

    if cmd == "" or cmd == "toggle" then
        if Omni.MainContainer and type(Omni.MainContainer.Toggle) == "function" then
            Omni.MainContainer:Toggle()
        else
            Omni:Print("[!] Main container UI not yet initialized.")
        end
    elseif cmd == "bank" then
        if Omni.BankContainer and type(Omni.BankContainer.Toggle) == "function" then
            Omni.BankContainer:Toggle()
        else
            Omni:Print("[!] Bank container UI not yet initialized.")
        end
    elseif cmd == "config" or cmd == "options" then
        if Omni.Options and type(Omni.Options.Open) == "function" then
            Omni.Options:Open()
        elseif Omni.MainContainer and type(Omni.MainContainer.ToggleConfig) == "function" then
            Omni.MainContainer:ToggleConfig()
        else
            Omni:Print("[!] Options panel not yet initialized.")
        end
    elseif cmd == "reset" then
        if _G.OmniInventoryDB then
            _G.OmniInventoryDB = { version = Omni.VERSION, realms = {} }
        end
        Omni:Print("[OK] Settings and UI layout positions reset to defaults.")
    elseif cmd == "debug" then
        Omni.debug = not Omni.debug
        Omni:Print("[OK] Debug mode is now " .. (Omni.debug and "|cFF00FF00ENABLED|r" or "|cFFFF0000DISABLED|r") .. ".")
    elseif cmd == "profiler" or cmd == "perf" then
        if Omni.Perf and type(Omni.Perf.ToggleProfilerHUD) == "function" then
            Omni.Perf:ToggleProfilerHUD()
        else
            Omni:Print("[!] Performance profiler not loaded.")
        end
    else
        PrintHelp()
    end
end

-- Register Slash Commands
SLASH_OMNIINVENTORY1 = "/omni"
SLASH_OMNIINVENTORY2 = "/oi"
SLASH_OMNIINVENTORY3 = "/omniinv"
SlashCmdList["OMNIINVENTORY"] = SlashHandler

return SlashCommands
