-- =============================================================================
-- OmniInventory MainContainer Component
-- =============================================================================
-- Purpose: Master container frame with dedicated drag handle title bar
-- WoTLK 3.3.5a Compatible - Uses only native APIs
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or {}

local MainContainer = {
    frame = nil,
    isOpen = false,
}
Omni.MainContainer = MainContainer

function Omni.CreateMainContainer(name)
    name = name or "OmniInventoryMainContainer"
    if _G[name] then return _G[name] end

    local mainFrame = CreateFrame("Frame", name, UIParent)
    mainFrame:SetSize(450, 500)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetMovable(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:Hide()

    -- Apply OpenCode TUI Backdrop
    if Omni.OpsTheme and Omni.OpsTheme.ApplyFrameBackdrop then
        Omni.OpsTheme:ApplyFrameBackdrop(mainFrame)
    else
        mainFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        mainFrame:SetBackdropColor(0.086, 0.078, 0.075, 0.95) -- #161413
        mainFrame:SetBackdropBorderColor(0.353, 0.337, 0.329, 1.0)
    end

    -- DEDICATED DRAG HANDLE TITLE BAR
    -- Mouse dragging is NEVER registered on the main window frame container directly.
    local titleBar = CreateFrame("Frame", name .. "TitleBar", mainFrame)
    titleBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(28)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")

    -- Title Bar Background
    titleBar.bg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBar.bg:SetAllPoints()
    titleBar.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    titleBar.bg:SetVertexColor(0.122, 0.110, 0.102, 1.0) -- surfaceSoft #1f1c1a

    -- Title Text
    titleBar.titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleBar.titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleBar.titleText:SetText("|cFF00FF00Omni|rInventory [Master Container]")

    -- Dedicated Drag Handlers
    titleBar:SetScript("OnDragStart", function(self)
        mainFrame:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function(self)
        mainFrame:StopMovingOrSizing()
    end)

    -- Close Button [x]
    local closeBtn = CreateFrame("Button", name .. "CloseButton", titleBar)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)

    closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    closeBtn.text:SetPoint("CENTER")
    closeBtn.text:SetText("[x]")

    closeBtn:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 0.23, 0.18, 1)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self.text:SetTextColor(0.94, 0.93, 0.91, 1)
    end)
    closeBtn:SetScript("OnClick", function(self)
        mainFrame:Hide()
    end)

    -- Content Frame
    local contentFrame = CreateFrame("Frame", name .. "Content", mainFrame)
    contentFrame:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -2)
    contentFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 0, 0)

    mainFrame.TitleBar = titleBar
    mainFrame.CloseButton = closeBtn
    mainFrame.Content = contentFrame

    -- Ensure main container ITSELF enables mouse but NEVER registers dragging
    mainFrame:EnableMouse(true)

    return mainFrame
end

function MainContainer:Init()
    if not self.frame then
        self.frame = Omni.CreateMainContainer("OmniInventoryMainContainer")
    end
end

function MainContainer:Show()
    self:Init()
    self.frame:Show()
    self.isOpen = true
end

function MainContainer:Hide()
    if self.frame then
        self.frame:Hide()
    end
    self.isOpen = false
end

function MainContainer:Toggle()
    self:Init()
    if self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function MainContainer:ToggleConfig()
    if Omni.Options and Omni.Options.Toggle then
        Omni.Options:Toggle()
    else
        DEFAULT_CHAT_FRAME:AddMessage("[!] OmniInventory Options Panel")
    end
end
