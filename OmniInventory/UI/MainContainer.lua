-- =============================================================================
-- OmniInventory MainContainer Bridge Component
-- =============================================================================
-- Purpose: Bridge module delegating Master Container commands directly to UI/Frame.lua
-- WoTLK 3.3.5a Compatible - Uses only native APIs
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or {}

local MainContainer = {
    isOpen = false,
}
Omni.MainContainer = MainContainer

function MainContainer:Init()
    if Omni.Frame and Omni.Frame.Init then
        Omni.Frame:Init()
    end
end

function MainContainer:Show()
    if Omni.Frame and Omni.Frame.Show then
        Omni.Frame:Show()
    elseif Omni.Frame and Omni.Frame.Toggle then
        Omni.Frame:Toggle()
    end
    self.isOpen = true
end

function MainContainer:Hide()
    if Omni.Frame and Omni.Frame.Hide then
        Omni.Frame:Hide()
    end
    self.isOpen = false
end

function MainContainer:Toggle()
    if Omni.Frame and Omni.Frame.Toggle then
        Omni.Frame:Toggle()
    end
    self.isOpen = (Omni.Frame and Omni.Frame.IsShown and Omni.Frame:IsShown()) or false
end

function MainContainer:ToggleConfig()
    if Omni.Options and Omni.Options.Toggle then
        Omni.Options:Toggle()
    elseif Omni.Settings and Omni.Settings.Toggle then
        Omni.Settings:Toggle()
    end
end
