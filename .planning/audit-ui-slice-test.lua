-- Focused verification for AuditUI slice fixes (not part of the addon).
-- Loads MerchantOverlay, OpsTheme, Options in a minimal Lua 5.1 sandbox.
local passed, failed = 0, 0
local function check(name, cond)
    if cond then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name)
    end
end

-- ---------------------------------------------------------------------------
-- 1) OpsTheme: Hex never crashes on any input; PAL built from valid hex.
-- ---------------------------------------------------------------------------
local Omni = {}
local function loadFile(path)
    local chunk, err = loadfile(path)
    assert(chunk, path .. ": " .. tostring(err))
    chunk("OmniInventory", Omni)
end
loadFile("D:/COMPROG/OmniInventory/OmniInventory/UI/OpsTheme.lua")
local OpsTheme = Omni.OpsTheme
assert(OpsTheme, "OpsTheme not exported")

-- Can't call local Hex directly; validate every PAL entry is a sane RGBA table
local function validColor(c)
    return type(c) == "table" and #c >= 3
        and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
end
local badColors = 0
for k, v in pairs(OpsTheme.PAL) do
    if type(v) == "table" and k ~= "SPACING" and k ~= "ROUNDED" and k ~= "EDGE_INSETS"
        and k ~= "SECTION" and k ~= "SEMANTIC" and not validColor(v) then
        badColors = badColors + 1
        print("  bad PAL color: " .. tostring(k))
    end
end
check("OpsTheme.PAL all colors valid (no crash)", badColors == 0)
for k, v in pairs(OpsTheme.PAL.SECTION) do
    if not validColor(v) then badColors = badColors + 1 end
end
check("OpsTheme.PAL.SECTION colors valid", badColors == 0)

local r, g, b, a = OpsTheme:GetQualityColor(3)
check("GetQualityColor(3) returns 4 numbers", type(r) == "number" and type(g) == "number" and type(b) == "number" and type(a) == "number")
r, g, b, a = OpsTheme:GetQualityColor(nil) -- any input
check("GetQualityColor(nil) returns 4 numbers", type(r) == "number" and type(g) == "number" and type(b) == "number" and type(a) == "number")
r, g, b, a = OpsTheme:GetQualityColor("junk")
check("GetQualityColor('junk') returns 4 numbers", type(r) == "number" and type(g) == "number" and type(b) == "number" and type(a) == "number")

-- ---------------------------------------------------------------------------
-- 2) MerchantOverlay: quest-item protection + no global _ pollution
-- ---------------------------------------------------------------------------
local savedGetItemInfo = GetItemInfo
GetItemInfo = function() return "Test Item", "item:6948:0:0:0:0:0:0:0:0", 1 end
local questItemInfo = nil -- nil => not a quest item
GetContainerItemQuestInfo = function() return questItemInfo end
hooksecurefunc = function() end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
loadFile("D:/COMPROG/OmniInventory/OmniInventory/UI/MerchantOverlay.lua")
local MO = Omni.MerchantOverlay
assert(MO, "MerchantOverlay not exported")

MO.enabled = true
questItemInfo = true
check("IsProtected: active quest item (q1) protected",
    MO:IsProtected(0, 1, "item:1000:0:0:0:0:0:0:0:0", 1) == true)
questItemInfo = false
check("IsProtected: non-quest q1 not protected by quest check",
    MO:IsProtected(0, 1, "item:1000:0:0:0:0:0:0:0:0", 1) == false)
questItemInfo = nil
check("IsProtected: quest stub nil => not protected",
    MO:IsProtected(0, 1, "item:1000:0:0:0:0:0:0:0:0", 1) == false)
check("IsProtected: quality 3 still protected",
    MO:IsProtected(0, 1, "item:1000:0:0:0:0:0:0:0:0", 3) == true)
check("IsProtected: disabled => not protected", (function()
    MO.enabled = false
    local v = MO:IsProtected(0, 1, "item:1000:0:0:0:0:0:0:0:0", 4)
    MO.enabled = true
    return v == false
end)())
check("no global _ pollution from IsProtected", rawget(_G, "_") == nil)

-- ---------------------------------------------------------------------------
-- 3) Options: target toggle persistence
-- ---------------------------------------------------------------------------
-- Load Options.lua after OpsTheme (already loaded). It needs no other
-- top-level globals (functions only touch the world when called).
local OpsThemeFrameStub = nil
loadFile("D:/COMPROG/OmniInventory/OmniInventory/UI/Options.lua")
local Settings = Omni.Settings
assert(Settings, "Settings not exported")

OmniInventoryDB = nil
Settings:Init()
check("Settings:Init with fresh DB defaults to bag", Settings.activeConfigTarget == "bag")

OmniInventoryDB = { char = { settings = { configTarget = "bank" } } }
Settings:Init()
check("Settings:Init restores saved bank target", Settings.activeConfigTarget == "bank")

OmniInventoryDB = { char = { settings = { configTarget = "bag" } } }
Settings:Init()
check("Settings:Init restores saved bag target", Settings.activeConfigTarget == "bag")

OmniInventoryDB = { char = { settings = { configTarget = "garbage" } } }
Settings:Init()
check("Settings:Init falls back on invalid saved target", Settings.activeConfigTarget == "bag")

print(string.format("RESULT: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
