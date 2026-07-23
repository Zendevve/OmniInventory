-- =============================================================================
-- OmniInventory Performance Profiler & Real-Time TUI HUD Overlay
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or _G.OmniInventory or _G.Omni

Omni.Perf = Omni.Perf or {}
local Perf = Omni.Perf

-- Internal state variables
local metrics = {}
local stackByTag = {}
local bucketCounters = {}

-- Real-time metric tracking state
Perf.currentMemKB = 0
Perf.peakMemKB = 0
Perf.gcChurnRateKB = 0

Perf.lastFrameDrawMs = 0
Perf.peakFrameDrawMs = 0
Perf.totalFrameDrawMs = 0
Perf.frameDrawCount = 0

Perf.totalSlotsEvaluated = 0
Perf.totalDiffedUpdates = 0
Perf.lastSlotsEvaluated = 0
Perf.lastDiffedUpdates = 0

Perf.isPaused = false
Perf.refreshInterval = 0.5 -- default refresh rate in seconds

-- Rolling window buffers
local memSamples = {} -- { { time = sec, mem = KB }, ... }
local slotDiffSamples = {} -- { { time = sec, eval = N, diff = M }, ... }

local function nowMs()
    if debugprofilestop then
        return debugprofilestop()
    end
    if GetTime then
        return GetTime() * 1000
    end
    return 0
end

local function nowSec()
    if GetTime then
        return GetTime()
    end
    return os and os.clock and os.clock() or 0
end

local function ensureDb()
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.char = OmniInventoryDB.char or {}
    OmniInventoryDB.char.settings = OmniInventoryDB.char.settings or {}
    return OmniInventoryDB.char.settings
end

function Perf:IsEnabled()
    return Omni._perfEnabled ~= false
end

function Perf:SetEnabled(enabled)
    local settings = ensureDb()
    local on = enabled == true
    settings.debugPerf = on
    Omni._perfEnabled = on
end

function Perf:SyncEnabledFromSettings()
    local settings = ensureDb()
    Omni._perfEnabled = settings.debugPerf ~= false
    return Omni._perfEnabled
end

local function ensureMetric(key)
    local metric = metrics[key]
    if metric then
        return metric
    end
    metric = {
        key = key,
        count = 0,
        sumMs = 0,
        maxMs = 0,
        samples = {},
        sampleCap = 120,
        context = {},
    }
    metrics[key] = metric
    return metric
end

function Perf:RecordValue(key, elapsedMs, context)
    if not self:IsEnabled() then
        return
    end
    if not key or type(elapsedMs) ~= "number" then
        return
    end
    local metric = ensureMetric(key)
    metric.count = metric.count + 1
    metric.sumMs = metric.sumMs + elapsedMs
    if elapsedMs > metric.maxMs then
        metric.maxMs = elapsedMs
    end
    metric.samples[#metric.samples + 1] = elapsedMs
    if #metric.samples > metric.sampleCap then
        table.remove(metric.samples, 1)
    end
    if type(context) == "table" then
        metric.context = {}
        for k, v in pairs(context) do
            metric.context[k] = v
        end
    end
end

function Perf:Begin(key)
    if not self:IsEnabled() or not key then
        return nil
    end
    local startedAt = nowMs()
    stackByTag[key] = startedAt
    return startedAt
end

function Perf:End(key, token, context)
    if not self:IsEnabled() or not key then
        return
    end
    local startedAt = token or stackByTag[key]
    if not startedAt then
        return
    end
    local elapsed = nowMs() - startedAt
    self:RecordValue(key, elapsed, context)
    if not token then
        stackByTag[key] = nil
    end
end

function Perf:CountBucket(eventName, fired)
    if not self:IsEnabled() or not eventName then
        return
    end
    local entry = bucketCounters[eventName]
    if not entry then
        entry = { seen = 0, fired = 0 }
        bucketCounters[eventName] = entry
    end
    if fired then
        entry.fired = entry.fired + 1
    else
        entry.seen = entry.seen + 1
    end
end

-- =============================================================================
-- Metric Collectors: Memory, GC Churn, Frame Draw, Slot Diffing
-- =============================================================================

function Perf:UpdateMemory()
    if UpdateAddOnMemoryUsage then
        pcall(UpdateAddOnMemoryUsage)
    end

    local mem = 0
    if GetAddOnMemoryUsage then
        mem = GetAddOnMemoryUsage("OmniInventory") or GetAddOnMemoryUsage(addonName or "") or 0
    end
    if (not mem or mem <= 0) and gcinfo then
        mem = gcinfo()
    end
    mem = mem or 0

    self.currentMemKB = mem
    if mem > self.peakMemKB then
        self.peakMemKB = mem
    end

    -- Calculate GC Churn Rate over a 1-second rolling delta window
    local t = nowSec()
    memSamples[#memSamples + 1] = { time = t, mem = mem }

    -- Prune samples older than 1.0s
    local cutoff = t - 1.0
    while #memSamples > 1 and memSamples[1].time < cutoff do
        table.remove(memSamples, 1)
    end

    -- Calculate total positive allocations in rolling window
    local totalAlloc = 0
    for i = 2, #memSamples do
        local delta = memSamples[i].mem - memSamples[i - 1].mem
        if delta > 0 then
            totalAlloc = totalAlloc + delta
        end
    end

    local dt = #memSamples > 1 and (memSamples[#memSamples].time - memSamples[1].time) or 0
    if dt > 0.05 then
        self.gcChurnRateKB = totalAlloc / dt
    else
        self.gcChurnRateKB = 0
    end

    return self.currentMemKB, self.gcChurnRateKB
end

function Perf:RecordFrameDraw(elapsedMs)
    if not elapsedMs or elapsedMs < 0 then return end
    self.lastFrameDrawMs = elapsedMs
    if elapsedMs > self.peakFrameDrawMs then
        self.peakFrameDrawMs = elapsedMs
    end
    self.frameDrawCount = self.frameDrawCount + 1
    self.totalFrameDrawMs = self.totalFrameDrawMs + elapsedMs
    self:RecordValue("FrameDraw", elapsedMs)
end

function Perf:RecordSlotDiff(evaluatedCount, diffedCount)
    evaluatedCount = evaluatedCount or 0
    diffedCount = diffedCount or 0
    self.totalSlotsEvaluated = self.totalSlotsEvaluated + evaluatedCount
    self.totalDiffedUpdates = self.totalDiffedUpdates + diffedCount
    self.lastSlotsEvaluated = evaluatedCount
    self.lastDiffedUpdates = diffedCount

    local t = nowSec()
    slotDiffSamples[#slotDiffSamples + 1] = { time = t, eval = evaluatedCount, diff = diffedCount }

    -- Prune samples older than 5.0s
    local cutoff = t - 5.0
    while #slotDiffSamples > 1 and slotDiffSamples[1].time < cutoff do
        table.remove(slotDiffSamples, 1)
    end
end

function Perf:Reset()
    metrics = {}
    stackByTag = {}
    bucketCounters = {}

    self.peakMemKB = self.currentMemKB or 0
    self.gcChurnRateKB = 0

    self.lastFrameDrawMs = 0
    self.peakFrameDrawMs = 0
    self.totalFrameDrawMs = 0
    self.frameDrawCount = 0

    self.totalSlotsEvaluated = 0
    self.totalDiffedUpdates = 0
    self.lastSlotsEvaluated = 0
    self.lastDiffedUpdates = 0

    memSamples = {}
    slotDiffSamples = {}

    if self.hudFrame and self.hudFrame.UpdateDisplay then
        self.hudFrame:UpdateDisplay()
    end
end

-- =============================================================================
-- Snapshot & Export Helpers
-- =============================================================================

local function percentileFromSamples(samples, p)
    if not samples or #samples == 0 then
        return 0
    end
    local ordered = {}
    for i = 1, #samples do
        ordered[i] = samples[i]
    end
    table.sort(ordered)
    local idx = math.ceil(#ordered * p)
    if idx < 1 then idx = 1 end
    if idx > #ordered then idx = #ordered end
    return ordered[idx]
end

local function round2(v)
    return math.floor((v or 0) * 100 + 0.5) / 100
end

function Perf:GetSnapshot()
    local out = {
        meta = {
            addon = addonName or "OmniInventory",
            tsMs = nowMs(),
            version = Omni.version or "unknown",
            memKB = round2(self.currentMemKB),
            peakMemKB = round2(self.peakMemKB),
            gcChurnKBSec = round2(self.gcChurnRateKB),
            lastFrameMs = round2(self.lastFrameDrawMs),
            peakFrameMs = round2(self.peakFrameDrawMs),
            totalSlotsEvaluated = self.totalSlotsEvaluated,
            totalDiffedUpdates = self.totalDiffedUpdates,
        },
        metrics = {},
        buckets = {},
    }

    for k, v in pairs(metrics) do
        local avg = 0
        if v.count > 0 then
            avg = v.sumMs / v.count
        end
        out.metrics[k] = {
            count = v.count,
            avgMs = round2(avg),
            p95Ms = round2(percentileFromSamples(v.samples, 0.95)),
            maxMs = round2(v.maxMs),
            context = v.context,
        }
    end

    for eventName, info in pairs(bucketCounters) do
        out.buckets[eventName] = {
            seen = info.seen or 0,
            fired = info.fired or 0,
        }
    end

    return out
end

local function encodeScalar(v)
    local t = type(v)
    if t == "number" then
        return tostring(v)
    end
    if t == "boolean" then
        return v and "true" or "false"
    end
    if t == "string" then
        local s = string.gsub(v, "\\", "\\\\")
        s = string.gsub(s, "\"", "\\\"")
        return "\"" .. s .. "\""
    end
    return "null"
end

local function encodeTable(tbl)
    local isArray = true
    local maxN = 0
    for k, _ in pairs(tbl) do
        if type(k) ~= "number" then
            isArray = false
            break
        end
        if k > maxN then
            maxN = k
        end
    end

    if isArray then
        local parts = {}
        for i = 1, maxN do
            local value = tbl[i]
            if type(value) == "table" then
                parts[#parts + 1] = encodeTable(value)
            else
                parts[#parts + 1] = encodeScalar(value)
            end
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end

    local keys = {}
    for k, _ in pairs(tbl) do
        keys[#keys + 1] = tostring(k)
    end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do
        local value = tbl[key]
        local encodedValue = (type(value) == "table") and encodeTable(value) or encodeScalar(value)
        parts[#parts + 1] = "\"" .. key .. "\":" .. encodedValue
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function Perf:ExportJson()
    return encodeTable(self:GetSnapshot())
end

function Perf:PrintReport()
    local snapshot = self:GetSnapshot()
    print("|cFF00FF00OmniInventory|r perf report:")
    print(string.format("  Memory: %.1f KB (Peak: %.1f KB, GC Churn: %.1f KB/s)",
        snapshot.meta.memKB, snapshot.meta.peakMemKB, snapshot.meta.gcChurnKBSec))
    print(string.format("  Frame Draw: Last=%.2f ms, Peak=%.2f ms",
        snapshot.meta.lastFrameMs, snapshot.meta.peakFrameMs))
    print(string.format("  Slot Diffing: Total Eval=%d, Total Diffed=%d",
        snapshot.meta.totalSlotsEvaluated, snapshot.meta.totalDiffedUpdates))

    local keys = {}
    for key, _ in pairs(snapshot.metrics) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    if #keys == 0 then
        print("  (no custom metrics recorded)")
    else
        for _, key in ipairs(keys) do
            local m = snapshot.metrics[key]
            print(string.format("  %s -> n=%d avg=%.2fms p95=%.2fms max=%.2fms",
                key, m.count or 0, m.avgMs or 0, m.p95Ms or 0, m.maxMs or 0))
        end
    end
end

-- =============================================================================
-- OpenCode TUI Diagnostic Overlay HUD Frame (OmniInventoryPerfFrame)
-- =============================================================================

function Perf:SetPaused(paused)
    self.isPaused = (paused == true)
    if self.hudFrame and self.hudFrame.UpdateControls then
        self.hudFrame:UpdateControls()
    end
end

function Perf:TogglePause()
    self:SetPaused(not self.isPaused)
end

function Perf:SetRefreshInterval(interval)
    if type(interval) == "number" and interval > 0 then
        self.refreshInterval = interval
        if self.hudFrame and self.hudFrame.UpdateControls then
            self.hudFrame:UpdateControls()
        end
    end
end

function Perf:CreateProfilerHUD()
    if self.hudFrame then
        return self.hudFrame
    end

    if not CreateFrame then
        -- Standalone / mock fallback
        return nil
    end

    local f = CreateFrame("Frame", "OmniInventoryPerfFrame", UIParent)
    _G.OmniInventoryPerfFrame = f
    self.hudFrame = f

    f:SetSize(360, 270)
    f:SetPoint("CENTER", UIParent, "CENTER", 200, 100)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(selfFrame) selfFrame:StartMoving() end)
    f:SetScript("OnDragStop", function(selfFrame) selfFrame:StopMovingOrSizing() end)

    -- OpenCode TUI Dark Surface (#161412)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture(0.086, 0.078, 0.071, 0.96)

    -- Hairline border (#38322c)
    local function addBorderLine(pt1, relPt1, pt2, relPt2, w, h)
        local line = f:CreateTexture(nil, "BORDER")
        line:SetTexture(0.220, 0.196, 0.173, 1.0)
        line:SetPoint(pt1, f, relPt1)
        line:SetPoint(pt2, f, relPt2)
        if w then line:SetWidth(w) end
        if h then line:SetHeight(h) end
    end
    addBorderLine("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, 1)
    addBorderLine("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, 1)
    addBorderLine("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", 1, nil)
    addBorderLine("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", 1, nil)

    -- Title Bar / Drag Handle
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    titleBar:SetHeight(24)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints(titleBar)
    titleBg:SetTexture(0.12, 0.11, 0.10, 1.0)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleText:SetText("[PERFORMANCE PROFILER]")
    titleText:SetTextColor(0.90, 0.85, 0.75, 1.0)

    -- Close button [X]
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
    local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    closeTxt:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    closeTxt:SetText("[X]")
    closeTxt:SetTextColor(0.9, 0.3, 0.3, 1.0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    closeBtn:SetScript("OnEnter", function() closeTxt:SetTextColor(1.0, 0.5, 0.5, 1.0) end)
    closeBtn:SetScript("OnLeave", function() closeTxt:SetTextColor(0.9, 0.3, 0.3, 1.0) end)

    -- Main Content Text Display
    local textPanel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    textPanel:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
    textPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 42)
    textPanel:SetJustifyH("LEFT")
    textPanel:SetJustifyV("TOP")
    textPanel:SetSpacing(3)
    f.textPanel = textPanel

    -- Control Buttons Panel at Bottom
    local controlBar = CreateFrame("Frame", nil, f)
    controlBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
    controlBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
    controlBar:SetHeight(24)

    local function createTUIButton(text, width, onClick)
        local btn = CreateFrame("Button", nil, controlBar)
        btn:SetSize(width, 20)
        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("CENTER", btn, "CENTER", 0, 0)
        txt:SetText(text)
        txt:SetTextColor(0.8, 0.8, 0.8, 1.0)
        btn.txt = txt
        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function() txt:SetTextColor(1.0, 1.0, 1.0, 1.0) end)
        btn:SetScript("OnLeave", function()
            if not btn.isHighlight then
                txt:SetTextColor(0.8, 0.8, 0.8, 1.0)
            end
        end)
        return btn
    end

    -- [PAUSE] / [RESUME] Toggle
    local pauseBtn = createTUIButton("[PAUSE]", 62, function()
        Perf:TogglePause()
    end)
    pauseBtn:SetPoint("LEFT", controlBar, "LEFT", 0, 0)
    f.pauseBtn = pauseBtn

    -- [RESET] Button
    local resetBtn = createTUIButton("[RESET]", 60, function()
        Perf:Reset()
    end)
    resetBtn:SetPoint("LEFT", pauseBtn, "RIGHT", 6, 0)

    -- Refresh Interval Selectors
    local labelRate = controlBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labelRate:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
    labelRate:SetText("Hz:")
    labelRate:SetTextColor(0.6, 0.6, 0.6, 1.0)

    local btn01 = createTUIButton("[0.1s]", 44, function() Perf:SetRefreshInterval(0.1) end)
    btn01:SetPoint("LEFT", labelRate, "RIGHT", 4, 0)

    local btn05 = createTUIButton("[0.5s]", 44, function() Perf:SetRefreshInterval(0.5) end)
    btn05:SetPoint("LEFT", btn01, "RIGHT", 2, 0)

    local btn10 = createTUIButton("[1.0s]", 44, function() Perf:SetRefreshInterval(1.0) end)
    btn10:SetPoint("LEFT", btn05, "RIGHT", 2, 0)

    f.rateBtns = { [0.1] = btn01, [0.5] = btn05, [1.0] = btn10 }

    function f:UpdateControls()
        -- Update Pause button text
        if Perf.isPaused then
            self.pauseBtn.txt:SetText("[RESUME]")
            self.pauseBtn.txt:SetTextColor(0.2, 1.0, 0.4, 1.0)
            self.pauseBtn.isHighlight = true
        else
            self.pauseBtn.txt:SetText("[PAUSE]")
            self.pauseBtn.txt:SetTextColor(0.8, 0.8, 0.8, 1.0)
            self.pauseBtn.isHighlight = false
        end

        -- Update rate buttons
        for rate, btn in pairs(self.rateBtns) do
            if math.abs(Perf.refreshInterval - rate) < 0.01 then
                btn.txt:SetText(">" .. string.format("%.1fs", rate) .. "<")
                btn.txt:SetTextColor(1.0, 0.82, 0.0, 1.0)
                btn.isHighlight = true
            else
                btn.txt:SetText("[" .. string.format("%.1fs", rate) .. "]")
                btn.txt:SetTextColor(0.8, 0.8, 0.8, 1.0)
                btn.isHighlight = false
            end
        end
    end

    function f:UpdateDisplay()
        if not Perf.isPaused then
            Perf:UpdateMemory()
        end

        local statusStr = Perf.isPaused and "|cffff5555[PAUSED]|r" or "|cff55ff55[RUNNING]|r"

        local memVal = Perf.currentMemKB or 0
        local memStr = (memVal >= 1024) and string.format("%.2f MB", memVal / 1024) or string.format("%.1f KB", memVal)

        local peakVal = Perf.peakMemKB or 0
        local peakMemStr = (peakVal >= 1024) and string.format("%.2f MB", peakVal / 1024) or string.format("%.1f KB", peakVal)

        local gcStr = string.format("%.1f KB/sec", Perf.gcChurnRateKB or 0)
        local drawStr = string.format("%.2f ms", Perf.lastFrameDrawMs or 0)
        local peakDrawStr = string.format("%.2f ms", Perf.peakFrameDrawMs or 0)

        local evalCount = Perf.lastSlotsEvaluated or 0
        local diffCount = Perf.lastDiffedUpdates or 0
        local effPct = (evalCount > 0) and ((diffCount / evalCount) * 100) or 0
        local diffStr = string.format("%d eval / %d updates (%.1f%%)", evalCount, diffCount, effPct)

        local lines = {
            string.format("Status:             %s", statusStr),
            string.format("Memory Footprint:    |cffffffff%s|r  (Peak: %s)", memStr, peakMemStr),
            string.format("GC Churn Rate:       |cffffffff%s|r", gcStr),
            string.format("Frame Draw Duration: |cffffffff%s|r  (Peak: %s)", drawStr, peakDrawStr),
            string.format("Slot Diffing:        |cffffffff%s|r", diffStr),
            "----------------------------------------------",
        }

        local snapshot = Perf:GetSnapshot()
        local mCount = 0
        for k, m in pairs(snapshot.metrics) do
            if k ~= "FrameDraw" then
                mCount = mCount + 1
                if mCount <= 3 then
                    lines[#lines + 1] = string.format(" %-18s avg=%.2fms max=%.2fms (n=%d)", k .. ":", m.avgMs, m.maxMs, m.count)
                end
            end
        end

        if mCount == 0 then
            lines[#lines + 1] = " (no custom traces recorded)"
        end

        lines[#lines + 1] = "----------------------------------------------"
        lines[#lines + 1] = "|cff7a746eType /oi profiler to toggle HUD overlay|r"

        self.textPanel:SetText(table.concat(lines, "\n"))
        self:UpdateControls()
    end

    -- OnUpdate ticker
    local elapsedTicker = 0
    f:SetScript("OnUpdate", function(selfFrame, elapsed)
        elapsedTicker = elapsedTicker + elapsed
        if elapsedTicker < Perf.refreshInterval then return end
        elapsedTicker = 0

        selfFrame:UpdateDisplay()
    end)

    f:UpdateDisplay()
    return f
end

function Perf:ToggleProfilerHUD()
    local f = self.hudFrame
    if not f then
        f = self:CreateProfilerHUD()
    end

    if f then
        if f:IsShown() then
            f:Hide()
        else
            f:Show()
            f:UpdateDisplay()
        end
    end
end

function Perf:ShowHUD()
    local f = self.hudFrame or self:CreateProfilerHUD()
    if f then
        f:Show()
        f:UpdateDisplay()
    end
end

function Perf:HideHUD()
    if self.hudFrame then
        self.hudFrame:Hide()
    end
end

return Perf
