-- =============================================================================
-- OmniInventory MinimapButton Component
-- =============================================================================
-- Purpose: 31x31 3-layer clamped minimap button for WoW 3.3.5a
-- WoTLK 3.3.5a Compatible - Adheres strictly to wow-addon-development skill rules
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or {}

local MinimapBtn = {
    button = nil,
    isDragging = false,
    angle = 225 * (math.pi / 180), -- Default position: 225 deg (bottom-left)
}
Omni.MinimapButton = MinimapBtn

local frame = CreateFrame("Frame", "OmniMinimapButtonEventFrame")

function MinimapBtn:Create()
    if self.button then return self.button end

    local btn = CreateFrame("Button", "OmniInventoryMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:EnableMouse(true)
    btn:SetMovable(true)

    -- Layer 1: Background (BACKGROUND)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    btn.bg = bg

    -- Layer 2: Icon (ARTWORK)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -5)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_28")
    btn.icon = icon

    -- Layer 3: Border (OVERLAY)
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    btn.border = border

    -- Highlight Texture
    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(20, 20)
    highlight:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -5)
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    btn.highlight = highlight

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            if Omni.MainContainer and Omni.MainContainer.ToggleConfig then
                Omni.MainContainer:ToggleConfig()
            end
        else
            if Omni.MainContainer and Omni.MainContainer.Toggle then
                Omni.MainContainer:Toggle()
            end
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("OmniInventory [2.1.0]")
        GameTooltip:AddLine("Left-Click: Toggle Master Container", 1, 1, 1)
        GameTooltip:AddLine("Right-Click: Toggle Configuration", 1, 1, 1)
        GameTooltip:AddLine("Drag: Move Minimap Button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        MinimapBtn.isDragging = true
    end)

    btn:SetScript("OnDragStop", function(self)
        MinimapBtn.isDragging = false
        MinimapBtn:SavePosition()
    end)

    btn:SetScript("OnUpdate", function(self)
        if MinimapBtn.isDragging then
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            if mx and my and scale and scale > 0 then
                cx, cy = cx / scale, cy / scale
                MinimapBtn.angle = math.atan2(cy - my, cx - mx)
                MinimapBtn:UpdatePosition()
            end
        end
    end)

    self.button = btn
    self:LoadPosition()
    return btn
end

function MinimapBtn:UpdatePosition()
    if not self.button then return end

    local angle = self.angle or (225 * (math.pi / 180))
    local radius = 80
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius

    -- Square Minimap Clamping Support (SexyMap / ElvUI)
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape ~= "ROUND" then
        local diagRadius = 103.13708498985 -- math.sqrt(2 * 80^2) - 10
        local qX = math.max(-radius, math.min(radius, x * (diagRadius / radius)))
        local qY = math.max(-radius, math.min(radius, y * (diagRadius / radius)))
        x, y = qX, qY
    end

    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function MinimapBtn:SavePosition()
    if not OmniInventoryDB then OmniInventoryDB = {} end
    if not OmniInventoryDB.global then OmniInventoryDB.global = {} end
    OmniInventoryDB.global.minimapAngle = self.angle
end

function MinimapBtn:LoadPosition()
    if OmniInventoryDB and OmniInventoryDB.global and OmniInventoryDB.global.minimapAngle then
        self.angle = OmniInventoryDB.global.minimapAngle
    end
    self:UpdatePosition()
end

function MinimapBtn:Init()
    self:Create()
    self:UpdatePosition()
end

function MinimapBtn:Show()
    if not self.button then self:Create() end
    self.button:Show()
end

function MinimapBtn:Hide()
    if self.button then self.button:Hide() end
end

function MinimapBtn:Toggle()
    if self.button and self.button:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Event Sync on PLAYER_LOGIN after SexyMap / ElvUI initialization pass
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        MinimapBtn:Init()
    end
end)
