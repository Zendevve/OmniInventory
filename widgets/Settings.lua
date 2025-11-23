local addonName, NS = ...

NS.Settings = {}

-- Helper to create a 1px border around a frame (matching main frame)
local function CreateBorder(f)
    if f.border then return end
    f.border = {}

    -- Top
    f.border.t = f:CreateTexture(nil, "BORDER")
    f.border.t:SetTexture(0.0, 0.0, 0.0, 1) -- Black
    f.border.t:SetPoint("TOPLEFT", -1, 1)
    f.border.t:SetPoint("TOPRIGHT", 1, 1)
    f.border.t:SetHeight(1)

    -- Bottom
    f.border.b = f:CreateTexture(nil, "BORDER")
    f.border.b:SetTexture(0.0, 0.0, 0.0, 1)
    f.border.b:SetPoint("BOTTOMLEFT", -1, -1)
    f.border.b:SetPoint("BOTTOMRIGHT", 1, -1)
    f.border.b:SetHeight(1)

    -- Left
    f.border.l = f:CreateTexture(nil, "BORDER")
    f.border.l:SetTexture(0.0, 0.0, 0.0, 1)
    f.border.l:SetPoint("TOPLEFT", -1, 1)
    f.border.l:SetPoint("BOTTOMLEFT", -1, -1)
    f.border.l:SetWidth(1)

    -- Right
    f.border.r = f:CreateTexture(nil, "BORDER")
    f.border.r:SetTexture(0.0, 0.0, 0.0, 1)
    f.border.r:SetPoint("TOPRIGHT", 1, 1)
    f.border.r:SetPoint("BOTTOMRIGHT", 1, -1)
    f.border.r:SetWidth(1)
end

function NS.Settings:Init()
    -- Create Settings Frame
    self.frame = CreateFrame("Frame", "ZenBagsSettingsFrame", UIParent)
    self.frame:SetSize(400, 500)
    self.frame:SetPoint("CENTER")

    -- Flat Dark Background
    local bg = self.frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0.10, 0.10, 0.10, 0.95)

    -- Pixel Border (matching main frame)
    CreateBorder(self.frame)

    self.frame:SetFrameStrata("DIALOG") -- Ensure it appears above other frames
    self.frame:SetFrameLevel(100) -- High frame level
    self.frame:EnableMouse(true)
    self.frame:SetMovable(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", self.frame.StartMoving)
    self.frame:SetScript("OnDragStop", self.frame.StopMovingOrSizing)
    self.frame:Hide()

    -- Header Background (matching main frame)
    local headerBg = self.frame:CreateTexture(nil, "ARTWORK")
    headerBg:SetTexture(0.15, 0.15, 0.15, 1) -- COLORS.HEADER
    headerBg:SetPoint("TOPLEFT", 0, 0)
    headerBg:SetPoint("TOPRIGHT", 0, 0)
    headerBg:SetHeight(40)

    -- Header Drag Area
    local headerDrag = CreateFrame("Button", nil, self.frame)
    headerDrag:SetPoint("TOPLEFT", 0, 0)
    headerDrag:SetPoint("TOPRIGHT", 0, 0)
    headerDrag:SetHeight(40)
    headerDrag:RegisterForDrag("LeftButton")
    headerDrag:SetScript("OnDragStart", function() self.frame:StartMoving() end)
    headerDrag:SetScript("OnDragStop", function() self.frame:StopMovingOrSizing() end)

    -- Header Separator Line
    local separator = self.frame:CreateTexture(nil, "OVERLAY")
    separator:SetTexture(0.20, 0.20, 0.20, 1) -- COLORS.ACCENT
    separator:SetPoint("TOPLEFT", 0, -40)
    separator:SetPoint("TOPRIGHT", 0, -40)
    separator:SetHeight(1)

    -- Title (in header)
    self.title = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.title:SetPoint("LEFT", headerBg, "LEFT", 15, 0)
    self.title:SetText("ZenBags Settings")

    -- Close Button (in header, raised frame level)
    self.closeBtn = CreateFrame("Button", nil, self.frame, "UIPanelCloseButton")
    self.closeBtn:SetPoint("TOPRIGHT", 0, 0)
    self.closeBtn:SetFrameLevel(self.frame:GetFrameLevel() + 10)

    -- Create Controls
    self:CreateControls()
end

function NS.Settings:CreateControls()
    local yOffset = -55 -- Start below header

    -- === Appearance Section ===
    self:CreateHeader("Appearance", yOffset)
    yOffset = yOffset - 30

    -- UI Scale Slider
    self:CreateSlider("Scale", "UI Scale", 0.5, 1.5, 0.1, function(value)
        NS.Config:Set("scale", value)
        NS.Frames.mainFrame:SetScale(value)
    end, yOffset)
    yOffset = yOffset - 50

    -- Opacity Slider
    self:CreateSlider("Opacity", "Opacity", 0.3, 1.0, 0.1, function(value)
        NS.Config:Set("opacity", value)
        NS.Frames.mainFrame:SetAlpha(value)
    end, yOffset)
    yOffset = yOffset - 50

    -- Item Size Slider
    self:CreateSlider("ItemSize", "Item Size", 30, 45, 1, function(value)
        NS.Config:Set("itemSize", value)
        NS.Frames:Update(true)
    end, yOffset)
    yOffset = yOffset - 50

    -- Spacing Slider
    self:CreateSlider("Padding", "Item Spacing", 2, 10, 1, function(value)
        NS.Config:Set("padding", value)
        NS.Frames:Update(true)
    end, yOffset)
    yOffset = yOffset - 60 -- Extra space

    -- === Behavior Section ===
    self:CreateHeader("Behavior", yOffset)
    yOffset = yOffset - 30

    -- Enable Search Checkbox
    self:CreateCheckbox("EnableSearch", "Enable Search Bar", function(checked)
        NS.Config:Set("enableSearch", checked)
        if checked then
            NS.Frames.searchBox:Show()
        else
            NS.Frames.searchBox:Hide()
        end
    end, yOffset)
    yOffset = yOffset - 30

    -- Show Tooltips Checkbox
    self:CreateCheckbox("ShowTooltips", "Show Item Tooltips", function(checked)
        NS.Config:Set("showTooltips", checked)
    end, yOffset)
    yOffset = yOffset - 30

    -- Auto Sort Checkbox
    self:CreateCheckbox("SortOnUpdate", "Auto-Sort Items", function(checked)
        NS.Config:Set("sortOnUpdate", checked)
    end, yOffset)
    yOffset = yOffset - 50

    -- Reset Button
    local resetBtn = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    resetBtn:SetSize(120, 25)
    resetBtn:SetPoint("BOTTOM", 0, 20)
    resetBtn:SetText("Reset Defaults")
    resetBtn:SetScript("OnClick", function()
        NS.Config:Reset()
        self:RefreshControls()
        NS.Frames:Update(true)
        print("|cFF00FF00ZenBags:|r Settings reset to defaults.")
    end)
end

function NS.Settings:CreateHeader(text, y)
    local header = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 20, y)
    header:SetText(text)
    header:SetTextColor(0.9, 0.9, 0.9, 1)

    -- Add separator line under header
    local line = self.frame:CreateTexture(nil, "ARTWORK")
    line:SetTexture(0.20, 0.20, 0.20, 1)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 20, y - 18)
    line:SetPoint("TOPRIGHT", -20, y - 18)
end

function NS.Settings:CreateSlider(key, label, minVal, maxVal, step, callback, y)
    local slider = CreateFrame("Slider", "ZenBagsSlider"..key, self.frame, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 30, y)
    slider:SetWidth(200)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    -- slider:SetObeyStepOnDrag(true) -- Not available in Classic

    _G[slider:GetName().."Low"]:SetText(minVal)
    _G[slider:GetName().."High"]:SetText(maxVal)
    _G[slider:GetName().."Text"]:SetText(label)

    -- Value Label
    local valueLabel = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueLabel:SetPoint("TOP", slider, "BOTTOM", 0, 0)

    slider:SetScript("OnValueChanged", function(self, value)
        -- Round to avoid floating point weirdness
        value = math.floor(value / step + 0.5) * step
        valueLabel:SetText(string.format("%.1f", value))
        callback(value)
    end)

    -- Store for refresh
    self.controls = self.controls or {}
    self.controls[key] = { type = "slider", frame = slider }
end

function NS.Settings:CreateCheckbox(key, label, callback, y)
    local cb = CreateFrame("CheckButton", "ZenBagsCheck"..key, self.frame, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 25, y)
    _G[cb:GetName().."Text"]:SetText(label)

    cb:SetScript("OnClick", function(self)
        callback(self:GetChecked())
    end)

    -- Store for refresh
    self.controls = self.controls or {}
    self.controls[key] = { type = "checkbox", frame = cb }
end

function NS.Settings:RefreshControls()
    if not self.controls then return end

    -- Update UI with current config values
    local config = NS.Config

    -- Sliders
    self.controls["Scale"].frame:SetValue(config:Get("scale"))
    self.controls["Opacity"].frame:SetValue(config:Get("opacity"))
    self.controls["ItemSize"].frame:SetValue(config:Get("itemSize"))
    self.controls["Padding"].frame:SetValue(config:Get("padding"))

    -- Checkboxes
    self.controls["EnableSearch"].frame:SetChecked(config:Get("enableSearch"))
    self.controls["ShowTooltips"].frame:SetChecked(config:Get("showTooltips"))
    self.controls["SortOnUpdate"].frame:SetChecked(config:Get("sortOnUpdate"))
end

function NS.Settings:Toggle()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:RefreshControls()
        self.frame:Show()
    end
end
