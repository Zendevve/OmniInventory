-- =============================================================================
-- OmniInventory Core Entry Point
-- =============================================================================
-- The definitive inventory management addon for WoW 3.3.5a
-- Architecturally forward-compatible with Retail
-- =============================================================================

local addonName, Omni = ...

-- =============================================================================
-- Namespace Setup
-- =============================================================================

_G.OmniInventory = Omni

Omni.version = "2.1.0"
Omni.author = "Zendevve"

-- Convenience top-level Toggle. DIRECT call (no pcall) is critical
-- for combat toggle: pcall in a tainted binding context breaks the
-- secure execution environment, causing mainFrame:Show() to fail
-- silently in combat. The Show/Hide methods themselves wrap their
-- internal pcall(mainFrame.Show/Hide) for error recording only.
function Omni:Toggle()
    if not self or not self.Frame then return end
    self.Frame:Toggle()
end

-- =============================================================================
-- Event Handler
-- =============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")

-- Track invocations of the bag toggle so /oi debug can confirm
-- that the keybind is actually reaching addon code in (and out of) combat.
Omni._toggleStats = {
    total = 0,
    inCombat = 0,
    lastEvent = nil,
    lastWasCombat = false,
    shownBefore = nil,
    shownAfter = nil,
    showCalls = 0,
    hideCalls = 0,
    showOK = 0,
    hideOK = 0,
    lastShowErr = nil,
    lastHideErr = nil,
    lastBlocked = nil,
    lastBlockedFunc = nil,
}

-- Capture ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN so /oi debug
-- can tell us the exact protected function the engine refused.
local blockedSink = CreateFrame("Frame")
blockedSink:RegisterEvent("ADDON_ACTION_BLOCKED")
blockedSink:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blockedSink:SetScript("OnEvent", function(_, ev, addon, func)
    if addon == "OmniInventory" or addon == nil then
        Omni._toggleStats.lastBlocked = ev
        Omni._toggleStats.lastBlockedFunc = tostring(func)
    end
end)


-- Bag-function overrides hoisted to module scope so we can re-apply
-- on PLAYER_ENTERING_WORLD / after combat. Some addons (and the default UI
-- after a UI reload) re-bind the global bag functions, which silently breaks
-- our toggle path. Re-applying defensively guarantees our keybind reaches
-- Omni.Frame:Toggle.
local function recordEntry(reason)
    Omni._toggleStats.total = Omni._toggleStats.total + 1
    Omni._toggleStats.lastEvent = reason or "toggle"
    Omni._toggleStats.lastWasCombat = (InCombatLockdown and InCombatLockdown()) and true or false
    if Omni._toggleStats.lastWasCombat then
        Omni._toggleStats.inCombat = Omni._toggleStats.inCombat + 1
    end
    Omni._toggleStats.shownBefore =
        (Omni.Frame and Omni.Frame.IsShown and Omni.Frame:IsShown()) and true or false
end

local function recordExit()
    Omni._toggleStats.shownAfter =
        (Omni.Frame and Omni.Frame.IsShown and Omni.Frame:IsShown()) and true or false
end

local function SafeToggle(reason)
    recordEntry(reason or "toggle")
    if Omni.Frame then
        local shownBefore = Omni._toggleStats.shownBefore
        if shownBefore then
            Omni._toggleStats.hideCalls = Omni._toggleStats.hideCalls + 1
            Omni.Frame:Hide()
            Omni._toggleStats.hideOK = Omni._toggleStats.hideOK + 1
        else
            Omni._toggleStats.showCalls = Omni._toggleStats.showCalls + 1
            Omni.Frame:Show()
            Omni._toggleStats.showOK = Omni._toggleStats.showOK + 1
        end
    end
    recordExit()
end

local function SafeShow(reason)
    recordEntry(reason or "show")
    if Omni.Frame then
        Omni._toggleStats.showCalls = Omni._toggleStats.showCalls + 1
        Omni.Frame:Show()
        Omni._toggleStats.showOK = Omni._toggleStats.showOK + 1
    end
    recordExit()
end

local function SafeHide(reason)
    recordEntry(reason or "hide")
    if Omni.Frame then
        Omni._toggleStats.hideCalls = Omni._toggleStats.hideCalls + 1
        Omni.Frame:Hide()
        Omni._toggleStats.hideOK = Omni._toggleStats.hideOK + 1
    end
    recordExit()
end

-- Stable identity for our overrides so /oi debug can detect when
-- another addon has stolen them.
local OmniToggleAll   = function() SafeToggle("ToggleAllBags") end
local OmniOpenAll     = function() SafeShow("OpenAllBags") end
local OmniCloseAll    = function() SafeHide("CloseAllBags") end
local OmniToggleBack  = function() SafeToggle("ToggleBackpack") end
local OmniOpenBack    = function() SafeShow("OpenBackpack") end
local OmniCloseBack   = function() SafeHide("CloseBackpack") end
local OmniToggleBag   = function(_) SafeToggle("ToggleBag") end
local OmniOpenBag     = function(_) SafeShow("OpenBag") end
local OmniCloseBag    = function(_) SafeHide("CloseBag") end

Omni._overrideMarker = OmniToggleAll

-- Reassigning these globals is insecure and always allowed -- it's
-- the per-frame Hide / UnregisterAllEvents / SetScript on the protected
-- Blizzard ContainerFrames + BankFrame that gets us into combat-lockdown
-- trouble. We split the two so we can safely re-apply the global overrides
-- from any event (including PLAYER_ENTERING_WORLD after an in-combat
-- /reload) without firing "Interface action failed because of an AddOn."
-- The Blizzard-frame suppression is performed only out of combat; the
-- OnShow/OnEvent hooks installed there persist across reloads anyway.
local blizzardSuppressionDone = false

local function SuppressBlizzardBagFrames()
    if blizzardSuppressionDone then return end
    if InCombatLockdown and InCombatLockdown() then return end

    -- IMPORTANT: We must NOT call Hide(), UnregisterAllEvents(), or
    -- SetScript() on the Blizzard ContainerFrames from addon code.  Those
    -- are protected-frame operations and calling them from outside a
    -- secure context TAINTS the frames.  Once tainted, the binding system
    -- cannot interact with them in combat, which prevents our global
    -- overrides (ToggleBackpack, etc.) from ever being called.
    --
    -- Instead, we hook OnShow from WITHIN the frame's secure context.
    -- The hook hides the Blizzard frame and shows our frame instead.
    -- The hook function receives `self` as the ContainerFrame, so
    -- calling self:Hide() runs in the frame's own secure context.
    --
    -- Combat safety: the hook fires from Blizzard's secure OnShow handler
    -- even in combat. The body is wrapped in pcall because Blizzard
    -- frames are protected and any failed Hide/Show from this non-native
    -- callback would surface as a silent engine error. We also short-
    -- circuit our own Show() in combat; combat display is handled by
    -- the dedicated OMNIINVENTORY_TOGGLE binding path, not via Blizzard's
    -- frame show chain.
    for i = 1, 13 do
        local containerFrame = _G["ContainerFrame" .. i]
        if containerFrame then
            pcall(containerFrame.HookScript, containerFrame, "OnShow",
                function(self)
                    pcall(self.Hide, self)
                    if not (InCombatLockdown and InCombatLockdown()) then
                        if Omni.Frame and Omni.Frame.Show then
                            pcall(Omni.Frame.Show, Omni.Frame)
                        end
                    end
                end)
        end
    end

    if _G.BankFrame then
        pcall(_G.BankFrame.UnregisterAllEvents, _G.BankFrame)
    end

    blizzardSuppressionDone = true
end

-- Blizzard_GuildBankUI is a load-on-demand addon, so it may not
-- exist yet when the rest of the bag suppression runs. Force-load it and
-- strip its OnShow/OnEvent once it's actually loaded, and again on the
-- ADDON_LOADED sink below in case something else triggers the load first.
local guildBankSuppressionDone = false

local function SuppressBlizzardGuildBank()
    if guildBankSuppressionDone then return end
    if InCombatLockdown and InCombatLockdown() then return end

    if IsAddOnLoaded and not IsAddOnLoaded("Blizzard_GuildBankUI") then
        pcall(LoadAddOn, "Blizzard_GuildBankUI")
    end

    if Omni.GuildBankFrame and Omni.GuildBankFrame.InstallSetGuildBankTabInfoShim then
        Omni.GuildBankFrame:InstallSetGuildBankTabInfoShim()
    end

    local gb = _G.GuildBankFrame
    if not gb then return end

    -- Keep GuildBankFrame logically shown (off-screen, alpha 0) so
    -- UseContainerItem / bag right-click deposit and engine guild-bank state
    -- still work. Hiding it entirely breaks deposit-from-bags.
    pcall(gb.Hide, gb)
    pcall(gb.SetScript, gb, "OnShow", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -12000, -12000)
        self:SetSize(1, 1)
        self:SetAlpha(0)
        self:SetScale(0.01)
        self:EnableMouse(false)
        self:Show()
    end)

    guildBankSuppressionDone = true
end

-- Remap B / Shift-B to the addon binding so the keypress reaches
-- OmniInventory:Toggle() directly through the secure binding system,
-- bypassing the Blizzard ContainerFrame show/hide which is blocked in
-- combat. We only remap keys that are still on a default Blizzard bag
-- binding so we never clobber a user's custom keybind. SetBinding is a
-- protected operation; this runs only OOC from the OverrideBags entry
-- point (which itself is combat-gated).
local function RemapBagKeybindings()
    if InCombatLockdown and InCombatLockdown() then return end

    local bBinding = GetBindingAction and GetBindingAction("B")
    if bBinding and (bBinding == "TOGGLEBACKPACK"
            or bBinding == "TOGGLEBAGS"
            or bBinding == "OPENALLBAGS") then
        SetBinding("B", "OMNIINVENTORY_TOGGLE")
    end

    local shiftBBinding = GetBindingAction and GetBindingAction("SHIFT-B")
    if shiftBBinding and (shiftBBinding == "TOGGLEBACKPACK"
            or shiftBBinding == "TOGGLEBAGS"
            or shiftBBinding == "OPENALLBAGS") then
        SetBinding("SHIFT-B", "OMNIINVENTORY_TOGGLE")
    end
end

local function OverrideBags()
    ToggleAllBags  = OmniToggleAll
    OpenAllBags    = OmniOpenAll
    CloseAllBags   = OmniCloseAll
    ToggleBackpack = OmniToggleBack
    OpenBackpack   = OmniOpenBack
    CloseBackpack  = OmniCloseBack
    ToggleBag      = OmniToggleBag
    OpenBag        = OmniOpenBag
    CloseBag       = OmniCloseBag

    SuppressBlizzardBagFrames()
    SuppressBlizzardGuildBank()
    -- Remap default bag keys to our addon binding. Combat toggle only
    -- works through our secure binding; the Blizzard ContainerFrame
    -- path is blocked by combat lockdown.
    RemapBagKeybindings()
end

-- NOTE: The previous "combatToggleDriver" (a hidden Frame driven via
-- SetAttribute + OnAttributeChanged) has been removed.  It did not
-- provide combat-safe Show/Hide because the driver's OnAttributeChanged
-- handler ran in insecure addon-code context, so calls to Show/Hide on
-- the protected OmniInventoryFrame were still blocked during combat
-- lockdown.  Combat safety now relies on the key binding handler's
-- clean execution context propagating through SafeToggle/SafeShow/
-- SafeHide -> Frame:Show/Hide -> mainFrame:Show/Hide (see the
-- Binding Entry Points section above).

-- =============================================================================
-- Combat-Safe Binding Entry Points (Bindings.xml)
-- =============================================================================
-- These globals are called by the key binding body. They delegate to the
-- Safe* wrappers which call Frame:Show/Hide/Toggle directly.
--
-- Combat safety comes from the binding handler's own execution context:
-- when the player sets the binding via the Key Binding UI the handler
-- runs "clean" (un-tainted), and that clean context propagates through
-- the entire Lua call stack -- SafeToggle -> Frame:Show -> mainFrame:Show
-- -- so Show/Hide on the protected OmniInventoryFrame succeeds even
-- during combat lockdown.  This is the same mechanism that both
-- ArkInventory (RawHook on ToggleBackpack) and GudaBags (direct global
-- replacement) rely on.
--
-- A previous revision routed combat toggles through a hidden
-- "combatToggleDriver" frame via SetAttribute + OnAttributeChanged.
-- That approach was broken because the driver is a plain Frame whose
-- OnAttributeChanged handler runs in insecure addon-code context,
-- so Show/Hide on the protected main frame was still blocked during
-- combat lockdown.  The attribute driver has been removed.

-- Toggle bags (key binding). Safe in combat when binding is clean.
function OmniInventory_ToggleBags()
    SafeToggle("binding_toggle")
end

-- Toggle bank (key binding). Safe in combat.
function OmniInventory_ToggleBank()
    if Omni.BankFrame then
        Omni.BankFrame:Toggle()
    end
end

-- Open bags (key binding). Safe in combat when binding is clean.
function OmniInventory_OpenBags()
    SafeShow("binding_show")
end

-- Close bags (key binding). Safe in combat when binding is clean.
function OmniInventory_CloseBags()
    SafeHide("binding_hide")
end

Omni._OverrideBags = OverrideBags

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_GuildBankUI" then
        SuppressBlizzardGuildBank()
        if Omni.GuildBankFrame and Omni.GuildBankFrame.InstallSetGuildBankTabInfoShim then
            Omni.GuildBankFrame:InstallSetGuildBankTabInfoShim()
        end
        return
    end

    if event == "ADDON_LOADED" and arg1 == addonName then
        OmniInventoryDB = OmniInventoryDB or {}
        if Omni.Perf and Omni.Perf.SyncEnabledFromSettings then
            Omni.Perf:SyncEnabledFromSettings()
        end

        if Omni.Data then
            Omni.Data:Init()
        end



    elseif event == "PLAYER_LOGIN" then
        if Omni.Data then
            Omni.Data:Init()
            local rName = GetRealmName()
            if OmniInventoryDB and OmniInventoryDB.realm and OmniInventoryDB.realm[rName] then
                OmniInventoryDB.realm[rName]["Unknown Character"] = nil
            end
        end
        if Omni.Pool then Omni.Pool:Init() end
        if Omni.Events then Omni.Events:Init() end
        if Omni.Categorizer then Omni.Categorizer:Init() end
        if Omni.Sorter then Omni.Sorter:Init() end
        if Omni.Rules then Omni.Rules:Init() end
        if Omni.Utils and Omni.Utils.EnsureBlizzardContainerItemButtons then
            Omni.Utils:EnsureBlizzardContainerItemButtons()
        end
        if Omni.Frame then Omni.Frame:Init() end
        if Omni.BankFrame then Omni.BankFrame:Init() end
        if Omni.GuildBankFrame then Omni.GuildBankFrame:Init() end
        if Omni.Settings then Omni.Settings:Init() end
        if Omni.Features then Omni.Features:Init() end

        -- Override the global bag functions so our key bindings
        -- reach Frame:Toggle/Show/Hide. Combat safety relies on the
        -- binding handler's clean execution context propagating
        -- through the direct call chain (see Binding Entry Points).
        OverrideBags()


    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Re-apply: late-loading addons may have replaced our globals.
        -- Safe in combat -- the Blizzard-frame suppression inside
        -- OverrideBags is itself combat-gated.
        OverrideBags()

        -- Cache warmer + money tracker fire on zone-in.
        if Omni.Features then
            if Omni.Features.WarmCache then Omni.Features:WarmCache() end
            if Omni.Features.RecordMoney then Omni.Features:RecordMoney() end
        end


    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Same defensive re-apply once combat lockdown lifts; this also
        -- gives SuppressBlizzardBagFrames a chance to run if an
        -- in-combat /reload deferred it.
        OverrideBags()

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Combat started. Nothing extra to do; the binding handler's
        -- clean context is what makes Show/Hide safe during lockdown
        -- (see Binding Entry Points section above).
    end
end)

-- =============================================================================
-- Slash Commands
-- =============================================================================

SLASH_OMNIINVENTORY1 = "/omniinventory"
SLASH_OMNIINVENTORY2 = "/omni"
SLASH_OMNIINVENTORY3 = "/oi"

SLASH_ZENBAGS1 = "/zb"
SLASH_ZENBAGS2 = "/zenbags"

local clamOpenerFrame = CreateFrame("Frame")
local CLAM_IDS = {
    [5523]  = true,  -- Small Barnacled Clam
    [5524]  = true,  -- Thick-shelled Clam
    [7973]  = true,  -- Big-mouth Clam
    [15874] = true,  -- Soft-shelled Clam
}
local openClamsRunning = false
local delayAccumulator = 0
local OPEN_DELAY = 0.5

local function FindNextClam()
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, numSlots do
            local link = GetContainerItemLink(bagID, slotID)
            if link then
                local itemID = tonumber(string.match(link, "item:(%d+)"))
                if itemID and CLAM_IDS[itemID] then
                    return bagID, slotID
                end
            end
        end
    end
    return nil
end

local function StopClamOpener(reason)
    openClamsRunning = false
    clamOpenerFrame:SetScript("OnUpdate", nil)
    if reason then
        print("|cFF00FF00OmniInventory|r: " .. reason)
    end
end

local function StartClamOpener()
    if openClamsRunning then
        StopClamOpener("Clam opener stopped.")
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        print("|cFF00FF00OmniInventory|r: Cannot open clams in combat.")
        return
    end

    local bagID, slotID = FindNextClam()
    if not bagID then
        print("|cFF00FF00OmniInventory|r: No clams found in your bags.")
        return
    end

    openClamsRunning = true
    delayAccumulator = 0
    print("|cFF00FF00OmniInventory|r: Opening clams...")

    clamOpenerFrame:SetScript("OnUpdate", function(self, elapsed)
        delayAccumulator = delayAccumulator + elapsed
        if delayAccumulator >= OPEN_DELAY then
            delayAccumulator = 0

            if not openClamsRunning then
                StopClamOpener()
                return
            end

            if InCombatLockdown and InCombatLockdown() then
                StopClamOpener("Clam opener stopped due to combat.")
                return
            end

            if CursorHasItem() then
                return
            end

            local blocking = (LootFrame and LootFrame:IsShown()) or (MailFrame and MailFrame:IsShown()) or (TradeFrame and TradeFrame:IsShown()) or (MerchantFrame and MerchantFrame:IsShown())
            if blocking then
                return
            end

            local nextBag, nextSlot = FindNextClam()
            if not nextBag then
                StopClamOpener("All clams opened.")
                return
            end

            UseContainerItem(nextBag, nextSlot)
        end
    end)
end

local function HandleSlashCommand(msg)
    msg = string.lower(msg or "")

    if msg == "config" or msg == "settings" or msg == "options" then
        if Omni.Settings then
            Omni.Settings:Toggle()
        else
            print("|cFF00FF00OmniInventory|r: Settings panel not yet implemented.")
        end

    elseif msg == "pool" then
        if Omni.Pool then
            Omni.Pool:Debug()
        end

    elseif msg == "debug" then
        local stats = Omni._toggleStats or {}
        print("|cFF00FF00OmniInventory|r debug:")
        print(string.format("  Toggle invocations: %d (in combat: %d)",
            stats.total or 0, stats.inCombat or 0))
        print(string.format("  Last entry path: %s (was combat: %s)",
            tostring(stats.lastEvent), tostring(stats.lastWasCombat)))
        print(string.format("  Last shown before/after: %s -> %s",
            tostring(stats.shownBefore), tostring(stats.shownAfter)))
        print(string.format("  Show calls: %d (ok: %d), Hide calls: %d (ok: %d)",
            stats.showCalls or 0, stats.showOK or 0, stats.hideCalls or 0, stats.hideOK or 0))
        if stats.lastShowErr then
            print("  Last Show err: " .. tostring(stats.lastShowErr))
        end
        if stats.lastHideErr then
            print("  Last Hide err: " .. tostring(stats.lastHideErr))
        end
        if stats.lastBlocked then
            print(string.format("  Last engine block: %s on %s",
                tostring(stats.lastBlocked), tostring(stats.lastBlockedFunc)))
        end
        print(string.format("  Frame shown: %s",
            tostring(Omni.Frame and Omni.Frame:IsShown() or false)))
        print(string.format("  InCombatLockdown(): %s",
            tostring(InCombatLockdown and InCombatLockdown() or false)))
        print(string.format("  ToggleAllBags is ours: %s",
            tostring(ToggleAllBags == Omni._overrideMarker)))
        local mf = _G.OmniInventoryFrame
        if mf then
            print(string.format("  OmniInventoryFrame protected: %s",
                tostring(mf.IsProtected and mf:IsProtected() or "n/a")))
            print(string.format("  OmniInventoryFrame forbidden: %s",
                tostring(mf.IsForbidden and mf:IsForbidden() or "n/a")))
        end
        if Omni.Pool then Omni.Pool:Debug() end

    elseif msg == "perf on" then
        if Omni.Perf then
            Omni.Perf:SetEnabled(true)
            print("|cFF00FF00OmniInventory|r: perf profiling enabled.")
        end

    elseif msg == "perf off" then
        if Omni.Perf then
            Omni.Perf:SetEnabled(false)
            print("|cFF00FF00OmniInventory|r: perf profiling disabled.")
        end

    elseif msg == "perf reset" then
        if Omni.Perf then
            Omni.Perf:Reset()
            print("|cFF00FF00OmniInventory|r: perf samples cleared.")
        end

    elseif msg == "perf report" then
        if Omni.Perf then
            Omni.Perf:PrintReport()
        end

    elseif msg == "perf dump" then
        if Omni.Perf then
            print("OMNI_PERF_JSON_BEGIN")
            print(Omni.Perf:ExportJson())
            print("OMNI_PERF_JSON_END")
        end

    elseif msg == "forceshow" then
        -- Bypass every Omni layer and call the bare frame method
        -- directly. If THIS triggers the popup the issue is not in our
        -- toggle plumbing -- it's lockdown on the frame itself.
        local mf = _G.OmniInventoryFrame
        if not mf then
            print("|cFFFF4040OmniInventory|r: OmniInventoryFrame not created yet.")
        else
            print(string.format("|cFF00FF00OmniInventory|r forceshow: combat=%s shown=%s protected=%s",
                tostring(InCombatLockdown and InCombatLockdown() or false),
                tostring(mf:IsShown()),
                tostring(mf.IsProtected and mf:IsProtected() or "n/a")))
            local ok, err = pcall(mf.Show, mf)
            print("  raw mf:Show -> ok=" .. tostring(ok) .. " err=" .. tostring(err))
        end

    elseif msg == "forcehide" then
        local mf = _G.OmniInventoryFrame
        if not mf then
            print("|cFFFF4040OmniInventory|r: OmniInventoryFrame not created yet.")
        else
            local ok, err = pcall(mf.Hide, mf)
            print("|cFF00FF00OmniInventory|r forcehide: ok=" .. tostring(ok) .. " err=" .. tostring(err))
        end

    elseif msg == "reapply" then
        if Omni._OverrideBags then
            Omni._OverrideBags()
            print("|cFF00FF00OmniInventory|r: bag overrides re-applied.")
        end

    elseif msg == "reset" then
        print("|cFF00FF00OmniInventory|r: Resetting...")

    elseif msg == "openclams" or msg == "clams" then
        StartClamOpener()

    elseif msg == "currency" or msg == "currencies" then
        if Omni.Features and Omni.Features.ToggleCurrencyFrame then
            Omni.Features:ToggleCurrencyFrame()
        end

    elseif msg == "bank" then
        if Omni.BankFrame then
            Omni.BankFrame:Toggle()
        end

    elseif msg == "guildbank" or msg == "gb" then
        if Omni.GuildBankFrame then
            Omni.GuildBankFrame:Toggle()
        end

    elseif msg == "bankswitch" or msg == "switchbank" then
        if Omni.Features and Omni.Features.CycleBankBagView then
            Omni.Features:CycleBankBagView()
        end

    elseif msg == "tidy" then
        if Omni.Features and Omni.Features.RunTidy then
            Omni.Features:RunTidy()
        end

    elseif msg == "sort" or msg == "physort" then
        if Omni.PhysicalSort and Omni.PhysicalSort.Sort then
            Omni.PhysicalSort:Sort({ consolidateStacks = true, routeSpecialized = true })
        elseif Omni.Frame and Omni.Frame.PhysicalSortBags then
            Omni.Frame:PhysicalSortBags()
        end

    elseif msg == "sortcancel" then
        if Omni.PhysicalSort and Omni.PhysicalSort.Cancel then
            Omni.PhysicalSort:Cancel()
        end

    elseif msg == "rules" or msg == "rule" then
        if Omni.Rules then
            local names = Omni.Rules:GetFunctionNames()
            print("|cFF00FF00OmniInventory|r: Available rule functions (" .. #names .. "):")
            local line = ""
            for i, name in ipairs(names) do
                line = line .. name
                if i < #names then line = line .. ", " end
                if string.len(line) > 70 then
                    print("  " .. line)
                    line = ""
                end
            end
            if line ~= "" then print("  " .. line) end
        end

    elseif msg == "categories" or msg == "cats" then
        if Omni.Categories then
            local cats = Omni.Categories:GetAll()
            if #cats == 0 then
                print("|cFF00FF00OmniInventory|r: No user-defined categories.")
            else
                print("|cFF00FF00OmniInventory|r: User-defined categories (" .. #cats .. "):")
                for _, cat in ipairs(cats) do
                    local err = Omni.Categories:GetError(cat.name)
                    local suffix = err and " |cFFFF4040[ERROR: " .. err .. "]|r" or ""
                    local itemCount = cat.list and #cat.list or 0
                    print(string.format("  |cFFFFFF00%s|r (seq:%d, items:%d, rule:%s)%s",
                        cat.name, cat.sequence or 50, itemCount,
                        (cat.rule and cat.rule ~= "") and "yes" or "no",
                        suffix))
                end
            end
        end

    elseif msg == "lock" then
        if Omni.Features and Omni.Features.SetGlobalLock then
            local locked = not Omni.Features:IsGlobalLocked()
            Omni.Features:SetGlobalLock(locked)
            print("|cFF00FF00OmniInventory|r: Global lock " .. (locked and "enabled" or "disabled") .. ".")
        end

    elseif msg == "help" then
        print("|cFF00FF00OmniInventory|r Commands:")
        print("  |cFFFFFF00/oi|r - Toggle bags")
        print("  |cFFFFFF00/oi config|r - Open settings")
        print("  |cFFFFFF00/oi openclams|r - Automatically open clams in bags")
        print("  |cFFFFFF00/oi debug|r - Toggle stats / combat / overrides")
        print("  |cFFFFFF00/oi forceshow|r - Bypass and try raw mainFrame:Show")
        print("  |cFFFFFF00/oi forcehide|r - Bypass and try raw mainFrame:Hide")
        print("  |cFFFFFF00/oi pool|r - Pool stats")
        print("  |cFFFFFF00/oi perf on|r - Enable perf profiling")
        print("  |cFFFFFF00/oi perf off|r - Disable perf profiling")
        print("  |cFFFFFF00/oi perf reset|r - Clear perf samples")
        print("  |cFFFFFF00/oi perf report|r - Print timing summary")
        print("  |cFFFFFF00/oi perf dump|r - Print JSON snapshot markers")
        print("  |cFFFFFF00/oi reapply|r - Re-apply bag function overrides")
        print("  |cFFFFFF00/oi currency|r - Toggle currency frame")
        print("  |cFFFFFF00/oi bank|r - Toggle bank window (offline/cached)")
        print("  |cFFFFFF00/oi guildbank|r - Toggle guild bank window (offline/cached)")
        print("  |cFFFFFF00/oi bankswitch|r - Cycle bank bag view")
        print("  |cFFFFFF00/oi tidy|r - Run auto-tidy (sort + compact)")
        print("  |cFFFFFF00/oi sort|r - Physical bag sort (move items)")
        print("  |cFFFFFF00/oi sortcancel|r - Cancel in-progress sort")
        print("  |cFFFFFF00/oi rules|r - List available rule functions")
        print("  |cFFFFFF00/oi categories|r - List user-defined categories")
        print("  |cFFFFFF00/oi lock|r - Toggle global lock (pause updates)")

    else
        SafeToggle("slash")
    end
end

SlashCmdList["OMNIINVENTORY"] = HandleSlashCommand
SlashCmdList["ZENBAGS"] = HandleSlashCommand
