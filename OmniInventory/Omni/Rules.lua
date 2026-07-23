-- =============================================================================
-- OmniInventory Rule Engine + User-Defined Categories
-- =============================================================================
-- Purpose: Bagshui-style rule engine with compiled expressions.
--   * Rules:Compile(ruleString) -> compiled function via loadstring()
--   * 30+ built-in rule functions (Quality, Name, Type, BindsOnEquip, etc.)
--   * User-defined categories with name, sequence, item list, rule, classes
--   * Recursive MatchCategory with call-stack loop prevention
--   * Error tracking with re-validation on category updates
-- =============================================================================

local addonName, Omni = ...

Omni.Rules = {}
local Rules = Omni.Rules

-- =============================================================================
-- State
-- =============================================================================

local ruleFunctions = {}     -- name -> function(item, character, ...)
local compiledRules = {}     -- ruleString -> { func, err }
local matchCategoryStack = {} -- loop prevention for recursive MatchCategory
local matchCategoryStackDepth = 0

-- =============================================================================
-- Built-in Rule Functions
-- =============================================================================
-- Each function receives (item, character) where item is an itemInfo table
-- and character is the character name (optional).

-- Quality(n) or Quality(">=3") or Quality("epic")
local qualityNames = {
    [0] = "poor", [1] = "common", [2] = "uncommon", [3] = "rare",
    [4] = "epic", [5] = "legendary", [6] = "artifact", [7] = "heirloom"
}

local function parseNumArg(arg)
    if type(arg) == "number" then return arg end
    if type(arg) == "string" then
        local op, num = string.match(arg, "^([><=!]+)%s*(%d+)$")
        if op and num then return tonumber(num), op end
        num = string.match(arg, "^(%d+)$")
        if num then return tonumber(num), "=" end
    end
    return nil
end

ruleFunctions.Quality = function(item, character, arg)
    if not item then return false end
    local q = item.quality
    if q == nil then return false end
    local num, op = parseNumArg(arg)
    if num then
        if op == ">=" then return q >= num
        elseif op == "<=" then return q <= num
        elseif op == ">" then return q > num
        elseif op == "<" then return q < num
        elseif op == "!=" or op == "<>" then return q ~= num
        else return q == num end
    end
    if type(arg) == "string" then
        local qName = qualityNames[q]
        if qName then return string.find(qName, string.lower(arg), 1, true) ~= nil end
    end
    return false
end

ruleFunctions.Name = function(item, character, arg)
    if not item or not arg then return false end
    local name = item.name or (item.hyperlink and GetItemInfo(item.hyperlink)) or ""
    return string.find(string.lower(name), string.lower(tostring(arg)), 1, true) ~= nil
end

ruleFunctions.NameExact = function(item, character, arg)
    if not item or not arg then return false end
    local name = item.name or (item.hyperlink and GetItemInfo(item.hyperlink)) or ""
    return string.lower(name) == string.lower(tostring(arg))
end

ruleFunctions.Id = function(item, character, arg)
    if not item then return false end
    local id = item.itemID
    if not id then return false end
    local num = tonumber(arg)
    if num then return id == num end
    return false
end

ruleFunctions.Type = function(item, character, arg)
    if not item or not arg then return false end
    local itemType = item.itemType or ""
    local subType = item.itemSubType or ""
    local lowerArg = string.lower(tostring(arg))
    return string.find(string.lower(itemType), lowerArg, 1, true) ~= nil
        or string.find(string.lower(subType), lowerArg, 1, true) ~= nil
end

ruleFunctions.Subtype = function(item, character, arg)
    if not item or not arg then return false end
    local subType = item.itemSubType or ""
    return string.find(string.lower(subType), string.lower(tostring(arg)), 1, true) ~= nil
end

ruleFunctions.EquipLocation = function(item, character, arg)
    if not item or not arg then return false end
    local equipSlot = item.equipSlot or ""
    return string.lower(equipSlot) == string.lower(tostring(arg))
end

ruleFunctions.ItemLevel = function(item, character, arg)
    if not item then return false end
    local ilvl = item.itemLevel
    if ilvl == nil and item.hyperlink then
        local _, _, _, iLvl = GetItemInfo(item.hyperlink)
        ilvl = iLvl
    end
    if ilvl == nil then return false end
    local num, op = parseNumArg(arg)
    if num then
        if op == ">=" then return ilvl >= num
        elseif op == "<=" then return ilvl <= num
        elseif op == ">" then return ilvl > num
        elseif op == "<" then return ilvl < num
        elseif op == "!=" or op == "<>" then return ilvl ~= num
        else return ilvl == num end
    end
    return false
end

ruleFunctions.MinLevel = function(item, character, arg)
    if not item then return false end
    local reqLevel = item.requiredLevel
    if reqLevel == nil and item.hyperlink then
        local _, _, _, _, rLvl = GetItemInfo(item.hyperlink)
        reqLevel = rLvl
    end
    if reqLevel == nil then return false end
    local num = tonumber(arg)
    if num then return reqLevel >= num end
    return false
end

ruleFunctions.BindsOnEquip = function(item, character)
    if not item then return false end
    return item.bindType == "BoE"
end

ruleFunctions.BindsOnPickup = function(item, character)
    if not item then return false end
    return item.bindType == "BoP" or item.isBound == true
end

ruleFunctions.BindsOnUse = function(item, character)
    if not item then return false end
    return item.bindType == "BoU"
end

ruleFunctions.BindsOnAccount = function(item, character)
    if not item then return false end
    return item.bindType == "BoA" or item.quality == 7
end

ruleFunctions.Soulbound = function(item, character)
    if not item then return false end
    return item.isBound == true
end

ruleFunctions.Quest = function(item, character)
    if not item then return false end
    if item.bagID and item.slotID and GetContainerItemQuestInfo then
        local isQuest = GetContainerItemQuestInfo(item.bagID, item.slotID)
        return isQuest and true or false
    end
    return false
end

ruleFunctions.ActiveQuest = function(item, character)
    if not item then return false end
    if item.bagID and item.slotID and GetContainerItemQuestInfo then
        local _, _, isActive = GetContainerItemQuestInfo(item.bagID, item.slotID)
        return isActive and true or false
    end
    return false
end

ruleFunctions.Stacks = function(item, character, arg)
    if not item then return false end
    local count = item.stackCount or 1
    local num, op = parseNumArg(arg)
    if num then
        if op == ">=" then return count >= num
        elseif op == "<=" then return count <= num
        elseif op == ">" then return count > num
        elseif op == "<" then return count < num
        else return count == num end
    end
    return count > 1
end

ruleFunctions.Count = function(item, character, arg)
    return ruleFunctions.Stacks(item, character, arg)
end

ruleFunctions.EmptySlot = function(item, character)
    if not item then return false end
    return item.__empty == true
end

ruleFunctions.Openable = function(item, character)
    if not item then return false end
    if item.hasLoot ~= nil then return item.hasLoot end
    return false
end

ruleFunctions.Bag = function(item, character, arg)
    if not item or not item.bagID then return false end
    local bagStr = tostring(arg)
    for part in string.gmatch(bagStr, "[^,]+") do
        local minB, maxB = string.match(part, "^%s*(%-?%d+)%s*-%s*(%-?%d+)%s*$")
        if minB and maxB then
            local bagID = item.bagID
            if bagID >= tonumber(minB) and bagID <= tonumber(maxB) then
                return true
            end
        else
            local num = tonumber(part)
            if num and item.bagID == num then
                return true
            end
        end
    end
    return false
end

ruleFunctions.BagType = function(item, character, arg)
    if not item or not item.bagID then return false end
    if not GetContainerNumFreeSlots then return false end
    local _, bagType = GetContainerNumFreeSlots(item.bagID)
    bagType = bagType or 0
    local num = tonumber(arg)
    if num then return bagType == num end
    return false
end

ruleFunctions.Equipped = function(item, character)
    if not item or not item.itemID then return false end
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local id = tonumber(string.match(link, "item:(%d+)"))
            if id == item.itemID then return true end
        end
    end
    return false
end

ruleFunctions.Outfit = function(item, character, arg)
    if not item then return false end
    if Omni.API and Omni.API.IsItemInEquipmentSet and item.bagID and item.slotID then
        return Omni.API:IsItemInEquipmentSet(item.bagID, item.slotID, tostring(arg or ""))
    end
    return false
end

ruleFunctions.RequiresClass = function(item, character, arg)
    if not item or not arg then return false end
    local _, class = UnitClass("player")
    if not class then return false end
    return string.lower(class) == string.lower(tostring(arg))
end

ruleFunctions.PlayerInGroup = function(item, character)
    return GetNumRaidMembers and GetNumRaidMembers() > 0
        or GetNumPartyMembers and GetNumPartyMembers() > 0
end

ruleFunctions.CharacterLevelRange = function(item, character, arg)
    if not item then return false end
    local level = UnitLevel("player")
    local minL, maxL = string.match(tostring(arg or ""), "(%d+)%s*-%s*(%d+)")
    if minL and maxL then
        return level >= tonumber(minL) and level <= tonumber(maxL)
    end
    local num = tonumber(arg)
    if num then return level == num end
    return false
end

ruleFunctions.Location = function(item, character, arg)
    if not item or not arg then return false end
    local lowerArg = string.lower(tostring(arg))
    -- Support inventory locations
    if lowerArg == "bag" or lowerArg == "bags" then
        return item.bagID ~= nil and item.bagID >= 0 and item.bagID <= 4
    elseif lowerArg == "bank" then
        return item.bagID == -1 or (item.bagID ~= nil and item.bagID >= 5 and item.bagID <= 11)
    elseif lowerArg == "keyring" then
        return item.bagID == -2
    elseif lowerArg == "guild" or lowerArg == "vault" or lowerArg == "guildbank" then
        return item.guildBankTab ~= nil
    end

    -- Default: Fallback to zone text matching
    local zone = GetZoneText() or ""
    local subZone = GetSubZoneText() or ""
    return string.find(string.lower(zone), lowerArg, 1, true) ~= nil
        or string.find(string.lower(subZone), lowerArg, 1, true) ~= nil
end

ruleFunctions.Subzone = function(item, character, arg)
    if not item or not arg then return false end
    local subZone = GetSubZoneText() or ""
    return string.find(string.lower(subZone), string.lower(tostring(arg)), 1, true) ~= nil
end

ruleFunctions.LootMethod = function(item, character, arg)
    if not arg then return false end
    local method = GetLootMethod()
    local methodNames = { [0] = "freeforall", [1] = "roundrobin", [2] = "master", [3] = "group" }
    local mName = methodNames[method]
    if mName then return string.lower(mName) == string.lower(tostring(arg)) end
    return false
end

ruleFunctions.ItemString = function(item, character, arg)
    if not item or not item.hyperlink or not arg then return false end
    return string.find(item.hyperlink, tostring(arg), 1, true) ~= nil
end

ruleFunctions.Tooltip = function(item, character, arg)
    if not item or not arg then return false end
    local scanningTooltip = _G["OmniScanningTooltip"]
    if not scanningTooltip then return false end
    scanningTooltip:ClearLines()
    if item.bagID and item.slotID then
        local ok = pcall(scanningTooltip.SetBagItem, scanningTooltip, item.bagID, item.slotID)
        if not ok and item.hyperlink then
            pcall(scanningTooltip.SetHyperlink, scanningTooltip, item.hyperlink)
        end
    elseif item.hyperlink then
        scanningTooltip:SetHyperlink(item.hyperlink)
    else
        return false
    end
    local lowerArg = string.lower(tostring(arg))
    for i = 1, scanningTooltip:NumLines() do
        local textFrame = _G["OmniScanningTooltipTextLeft" .. i]
        local text = textFrame and textFrame:GetText()
        if text and string.find(string.lower(text), lowerArg, 1, true) then
            return true
        end
    end
    return false
end

ruleFunctions.RecentlyChanged = function(item, character)
    if not item or not item.itemID then return false end
    if Omni.Categorizer and Omni.Categorizer.IsNewItem then
        return Omni.Categorizer:IsNewItem(item.itemID)
    end
    return false
end

ruleFunctions.Transmog = function(item, character)
    -- 3.3.5a doesn't have transmog; always false
    return false
end

ruleFunctions.PeriodicTable = function(item, character, arg)
    -- PT integration placeholder; returns false if PT not loaded
    if not item or not item.itemID or not arg then return false end
    if not _G.PeriodicTable then return false end
    return _G.PeriodicTable and _G.PeriodicTable.ItemInSet and _G.PeriodicTable:ItemInSet(item.itemID, tostring(arg)) or false
end

ruleFunctions.ProfessionCraft = function(item, character, arg)
    -- Placeholder: checks if item is craftable by a profession
    if not item or not item.itemID then return false end
    return false
end

ruleFunctions.ProfessionReagent = function(item, character, arg)
    -- Placeholder: checks if item is a reagent for a profession
    if not item or not item.itemID then return false end
    return false
end

local function GetItemVendorPrice(item)
    if not item then return 0 end
    if item.vendorPrice then return item.vendorPrice end
    if item.hyperlink then
        local _, _, _, _, _, _, _, _, _, _, price = GetItemInfo(item.hyperlink)
        return price or 0
    end
    return 0
end

local function ParseMoneyString(val)
    if type(val) == "number" then return val end
    local valStr = tostring(val)
    local g = tonumber(string.match(valStr, "(%d+)%s*[gG]")) or 0
    local s = tonumber(string.match(valStr, "(%d+)%s*[sS]")) or 0
    local c = tonumber(string.match(valStr, "(%d+)%s*[cC]")) or 0
    if g > 0 or s > 0 or c > 0 then
        return g * 10000 + s * 100 + c
    end
    return tonumber(valStr) or 0
end

ruleFunctions.VendorPriceUnder = function(item, character, arg)
    if not item or not arg then return false end
    local price = GetItemVendorPrice(item)
    local target = ParseMoneyString(arg)
    return price < target
end

ruleFunctions.VendorPriceOver = function(item, character, arg)
    if not item or not arg then return false end
    local price = GetItemVendorPrice(item)
    local target = ParseMoneyString(arg)
    return price > target
end

-- Aliases / Shorthands matching ArkInventory
ruleFunctions.q = ruleFunctions.Quality
ruleFunctions.tt = ruleFunctions.Tooltip
ruleFunctions.ilvl = ruleFunctions.ItemLevel
ruleFunctions.ireq = ruleFunctions.MinLevel
ruleFunctions.loc = ruleFunctions.Location
ruleFunctions.sb = ruleFunctions.Soulbound
ruleFunctions.vpu = ruleFunctions.VendorPriceUnder
ruleFunctions.vpo = ruleFunctions.VendorPriceOver
ruleFunctions.bag = ruleFunctions.Bag


-- MatchCategory: recursive category matching with loop prevention
ruleFunctions.MatchCategory = function(item, character, arg)
    if not item or not arg then return false end
    if not Omni.Categories then return false end

    matchCategoryStackDepth = matchCategoryStackDepth + 1
    if matchCategoryStackDepth > 10 then
        matchCategoryStackDepth = matchCategoryStackDepth - 1
        return false -- loop prevention
    end

    local catName = tostring(arg)
    local result = Omni.Categories:ItemMatchesCategory(item, catName)

    matchCategoryStackDepth = matchCategoryStackDepth - 1
    return result
end

-- =============================================================================
-- Rule Compilation
-- =============================================================================

-- Build a sandbox environment for compiled rules
local function buildRuleEnv(item, character)
    local env = {}
    -- Add all rule functions as callable
    for name, func in pairs(ruleFunctions) do
        env[name] = function(...) return func(item, character, ...) end
    end
    -- Add native Lua math, string, table libraries
    env.math = math
    env.string = string
    env.table = table
    env.tonumber = tonumber
    env.tostring = tostring
    env.type = type
    env.pairs = pairs
    env.ipairs = ipairs
    env.next = next
    env.select = select
    return env
end

--- Compile a rule string into a function.
--- @param ruleString string
--- @return function|nil compiledFunc
--- @return string|nil error
function Rules:Compile(ruleString)
    if not ruleString or ruleString == "" then return nil, "empty rule" end

    -- Check cache
    if compiledRules[ruleString] then
        local cached = compiledRules[ruleString]
        return cached.func, cached.err
    end

    -- Lua 5.1 (WoW 3.3.5a) compilation: loadstring the rule body
    -- as a function that receives (item, character), then setfenv its
    -- environment to our sandbox so rule functions (Quality, Name, etc.)
    -- are globally accessible inside the rule expression.
    local chunk, err = loadstring(string.format([[
        return function(item, character)
            return %s
        end
    ]], ruleString), "OmniRule")

    if not chunk then
        compiledRules[ruleString] = { func = nil, err = err or "compile error" }
        return nil, err
    end

    local ok, ruleFunc = pcall(chunk)
    if not ok or type(ruleFunc) ~= "function" then
        local perr = tostring(ruleFunc)
        compiledRules[ruleString] = { func = nil, err = perr }
        return nil, perr
    end

    -- Wrap in a closure that builds the env per-call and sets it
    local function compiledFunc(item, character)
        local env = buildRuleEnv(item, character)
        setfenv(ruleFunc, env)
        local ok2, result = pcall(ruleFunc, item, character)
        if not ok2 then
            return false
        end
        return result == true
    end

    compiledRules[ruleString] = { func = compiledFunc, err = nil }
    return compiledFunc, nil
end

--- Match a compiled rule against an item.
--- @param compiledFunc function
--- @param item table itemInfo
--- @param character string|nil
--- @return boolean
function Rules:Match(compiledFunc, item, character)
    if not compiledFunc or not item then return false end
    return compiledFunc(item, character) == true
end

--- Register a custom rule function.
--- @param name string
--- @param func function(item, character, ...)
function Rules:RegisterFunction(name, func)
    if type(name) == "string" and type(func) == "function" then
        ruleFunctions[name] = func
        -- Invalidate compiled cache since env changed
        compiledRules = {}
    end
end

--- Get all registered rule function names.
--- @return table
function Rules:GetFunctionNames()
    local names = {}
    for name in pairs(ruleFunctions) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

--- Clear the compiled rule cache (call when rules change).
function Rules:ClearCache()
    compiledRules = {}
end

-- =============================================================================
-- User-Defined Categories & Dynamic Rules (R1)
-- =============================================================================

Omni.Categories = Omni.Categories or {}
local Categories = Omni.Categories

local compiledCategories = {}  -- name/id -> { compiledRule, itemList, err }

local function ensureDB()
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.profile = OmniInventoryDB.profile or {}
    OmniInventoryDB.profile.rules = OmniInventoryDB.profile.rules or {}
    OmniInventoryDB.profile.categories = OmniInventoryDB.profile.categories or {}
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    OmniInventoryDB.global.userCategories = OmniInventoryDB.global.userCategories or {}
    return OmniInventoryDB.profile.rules, OmniInventoryDB.profile.categories, OmniInventoryDB.global.userCategories
end

--- Sync local state to RulesEngine and clear caches
function Categories:SyncToEngine()
    if Omni.RulesEngine and Omni.RulesEngine.SyncFromDB then
        Omni.RulesEngine:SyncFromDB()
    end
    if Omni.Categorizer and Omni.Categorizer.ClearCategoryCache then
        Omni.Categorizer:ClearCategoryCache()
    end
    if Rules and Rules.ClearCache then
        Rules:ClearCache()
    end
end

-- =============================================================================
-- DYNAMIC RULES API
-- =============================================================================

--- Get all user-defined dynamic rules, sorted by priority ascending
function Categories:GetAllRules()
    local rulesDB, _, globalCats = ensureDB()
    local list = {}

    -- Collect from profile.rules
    for id, r in pairs(rulesDB) do
        table.insert(list, r)
    end

    -- Legacy migration / fallback check from global.userCategories if rulesDB is empty
    if #list == 0 then
        for name, cat in pairs(globalCats) do
            if cat.rule and cat.rule ~= "" then
                local ruleObj = {
                    id = name,
                    name = name,
                    categoryTarget = cat.categoryTarget or name,
                    filterType = cat.filterType or "expression",
                    filterValue = cat.filterValue or cat.rule,
                    rule = cat.rule,
                    priority = cat.sequence or 50,
                    enabled = (cat.enabled ~= false),
                }
                rulesDB[name] = ruleObj
                table.insert(list, ruleObj)
            end
        end
    end

    table.sort(list, function(a, b)
        if (a.priority or 50) == (b.priority or 50) then
            return tostring(a.name) < tostring(b.name)
        end
        return (a.priority or 50) < (b.priority or 50)
    end)
    return list
end

--- Get a dynamic rule by ID
function Categories:GetRule(id)
    if not id then return nil end
    local rulesDB = ensureDB()
    return rulesDB[id]
end

--- Create or update a dynamic rule
function Categories:CreateRule(id, opts)
    if not id or id == "" then return false, "id required" end
    local rulesDB, _, globalCats = ensureDB()
    opts = opts or {}

    local name = opts.name or id
    local priority = opts.priority or opts.sequence or 50
    local ruleFormula = opts.rule or ""
    local catTarget = opts.categoryTarget or opts.categoryID or name

    local ruleObj = {
        id = id,
        name = name,
        categoryTarget = catTarget,
        filterType = opts.filterType or "expression",
        filterValue = opts.filterValue or ruleFormula,
        rule = ruleFormula,
        priority = priority,
        enabled = (opts.enabled ~= false),
        list = opts.list or {},
    }

    rulesDB[id] = ruleObj

    -- Sync to legacy global.userCategories format for backwards compatibility
    globalCats[name] = {
        name = name,
        sequence = priority,
        rule = ruleFormula,
        categoryTarget = catTarget,
        enabled = (opts.enabled ~= false),
    }

    self:Compile(id)
    self:SyncToEngine()
    return true
end

function Categories:UpdateRule(id, opts)
    return self:CreateRule(id, opts)
end

--- Delete a dynamic rule
function Categories:DeleteRule(id)
    if not id then return end
    local rulesDB, _, globalCats = ensureDB()
    local rule = rulesDB[id]
    if rule then
        if rule.name and globalCats[rule.name] then
            globalCats[rule.name] = nil
        end
        rulesDB[id] = nil
    end
    compiledCategories[id] = nil
    self:SyncToEngine()
end

--- Toggle a dynamic rule's enabled state
function Categories:ToggleRuleEnabled(id)
    local rule = self:GetRule(id)
    if rule then
        rule.enabled = not (rule.enabled == true)
        self:SyncToEngine()
        return rule.enabled
    end
    return false
end

--- Move rule UP in precedence (swaps priority with previous rule)
function Categories:MoveRuleUp(id)
    local rules = self:GetAllRules()
    local idx = nil
    for i, r in ipairs(rules) do
        if r.id == id then idx = i break end
    end
    if idx and idx > 1 then
        local curRule = rules[idx]
        local prevRule = rules[idx - 1]
        local tempPrio = curRule.priority or 50
        curRule.priority = prevRule.priority or 50
        prevRule.priority = tempPrio
        if curRule.priority == prevRule.priority then
            curRule.priority = math.max(1, curRule.priority - 1)
        end
        self:SyncToEngine()
    end
end

--- Move rule DOWN in precedence (swaps priority with next rule)
function Categories:MoveRuleDown(id)
    local rules = self:GetAllRules()
    local idx = nil
    for i, r in ipairs(rules) do
        if r.id == id then idx = i break end
    end
    if idx and idx < #rules then
        local curRule = rules[idx]
        local nextRule = rules[idx + 1]
        local tempPrio = curRule.priority or 50
        curRule.priority = nextRule.priority or 50
        nextRule.priority = tempPrio
        if curRule.priority == nextRule.priority then
            curRule.priority = curRule.priority + 1
        end
        self:SyncToEngine()
    end
end

--- Check if an item matches a specific rule definition
function Categories:ItemMatchesRule(item, rule)
    if not item or not rule or rule.enabled == false then return false end

    -- Check direct item list
    if item.itemID and rule.list then
        for _, id in ipairs(rule.list) do
            if id == item.itemID then return true end
        end
    end

    -- Check rule formula
    if rule.compiledRule then
        return Rules:Match(rule.compiledRule, item)
    elseif rule.rule and rule.rule ~= "" then
        local func, err = Rules:Compile(rule.rule)
        if func then
            rule.compiledRule = func
            return Rules:Match(func, item)
        end
    end

    return false
end

-- =============================================================================
-- CATEGORY SECTION LANES API
-- =============================================================================

--- Create or update a user-defined category section lane.
--- @param name string Category name
--- @param opts table { sequence, list, rule, color, enabled }
function Categories:Create(name, opts)
    if not name or name == "" then return false, "name required" end
    local _, catsDB, globalCats = ensureDB()
    opts = opts or {}

    local catObj = {
        name = name,
        sequence = opts.sequence or opts.priority or 50,
        color = opts.color or { r = 0.5, g = 0.5, b = 0.5 },
        list = opts.list or {},
        rule = opts.rule or "",
        enabled = (opts.enabled ~= false),
    }

    catsDB[name] = catObj
    globalCats[name] = globalCats[name] or catObj

    self:Compile(name)
    self:SyncToEngine()
    return true
end

function Categories:UpdateCategory(name, opts)
    return self:Create(name, opts)
end

--- Delete a category section lane.
--- @param name string
function Categories:Delete(name)
    if not name then return end
    local _, catsDB, globalCats = ensureDB()
    catsDB[name] = nil
    globalCats[name] = nil
    compiledCategories[name] = nil
    self:SyncToEngine()
end

--- Get a user-defined category definition.
--- @param name string
--- @return table|nil
function Categories:Get(name)
    if not name then return nil end
    local _, catsDB, globalCats = ensureDB()
    return catsDB[name] or globalCats[name]
end

--- Get all user-defined category section lanes, sorted by sequence.
--- @return table
function Categories:GetAll()
    local _, catsDB, globalCats = ensureDB()
    local list = {}

    local seen = {}
    for name, cat in pairs(catsDB) do
        table.insert(list, cat)
        seen[name] = true
    end
    for name, cat in pairs(globalCats) do
        if not seen[name] then
            table.insert(list, cat)
        end
    end

    table.sort(list, function(a, b)
        if (a.sequence or 50) == (b.sequence or 50) then
            return tostring(a.name) < tostring(b.name)
        end
        return (a.sequence or 50) < (b.sequence or 50)
    end)
    return list
end

--- Move category lane UP in precedence
function Categories:MoveCategoryUp(name)
    local cats = self:GetAll()
    local idx = nil
    for i, c in ipairs(cats) do
        if c.name == name then idx = i break end
    end
    if idx and idx > 1 then
        local curCat = cats[idx]
        local prevCat = cats[idx - 1]
        local tempSeq = curCat.sequence or 50
        curCat.sequence = prevCat.sequence or 50
        prevCat.sequence = tempSeq
        if curCat.sequence == prevCat.sequence then
            curCat.sequence = math.max(1, curCat.sequence - 1)
        end
        self:SyncToEngine()
    end
end

--- Move category lane DOWN in precedence
function Categories:MoveCategoryDown(name)
    local cats = self:GetAll()
    local idx = nil
    for i, c in ipairs(cats) do
        if c.name == name then idx = i break end
    end
    if idx and idx < #cats then
        local curCat = cats[idx]
        local nextCat = cats[idx + 1]
        local tempSeq = curCat.sequence or 50
        curCat.sequence = nextCat.sequence or 50
        nextCat.sequence = tempSeq
        if curCat.sequence == nextCat.sequence then
            curCat.sequence = curCat.sequence + 1
        end
        self:SyncToEngine()
    end
end

--- Compile a category's rule and cache it.
--- @param name string
function Categories:Compile(name)
    local cat = self:Get(name) or self:GetRule(name)
    if not cat then return end

    local compiled = { compiledRule = nil, itemList = {}, err = nil }

    -- Build item list lookup
    if cat.list then
        for _, itemID in ipairs(cat.list) do
            compiled.itemList[itemID] = true
        end
    end

    -- Compile rule if present
    if cat.rule and cat.rule ~= "" then
        local func, err = Rules:Compile(cat.rule)
        if func then
            compiled.compiledRule = func
        else
            compiled.err = err
        end
    end

    compiledCategories[name] = compiled
    if cat.id then compiledCategories[cat.id] = compiled end
end

--- Compile all user-defined categories & rules.
function Categories:CompileAll()
    local rules = self:GetAllRules()
    for _, r in ipairs(rules) do
        self:Compile(r.id or r.name)
    end
    local cats = self:GetAll()
    for _, c in ipairs(cats) do
        self:Compile(c.name)
    end
end

--- Check if an item matches a user-defined category.
--- @param item table itemInfo
--- @param catName string
--- @return boolean
function Categories:ItemMatchesCategory(item, catName)
    if not item or not catName then return false end

    local compiled = compiledCategories[catName]
    if not compiled then
        self:Compile(catName)
        compiled = compiledCategories[catName]
    end
    if not compiled then return false end

    -- Check direct item list
    if item.itemID and compiled.itemList[item.itemID] then
        return true
    end

    -- Check rule
    if compiled.compiledRule then
        return Rules:Match(compiled.compiledRule, item)
    end

    return false
end

--- Add an item to a category's direct list.
--- @param catName string
--- @param itemID number
function Categories:AddItem(catName, itemID)
    if not catName or not itemID then return end
    local cat = self:Get(catName) or self:GetRule(catName)
    if not cat then return end
    cat.list = cat.list or {}
    for _, id in ipairs(cat.list) do
        if id == itemID then return end
    end
    table.insert(cat.list, itemID)
    self:Compile(catName)
    self:SyncToEngine()
end

--- Remove an item from a category's direct list.
--- @param catName string
--- @param itemID number
function Categories:RemoveItem(catName, itemID)
    if not catName or not itemID then return end
    local cat = self:Get(catName) or self:GetRule(catName)
    if not cat or not cat.list then return end
    for i, id in ipairs(cat.list) do
        if id == itemID then
            table.remove(cat.list, i)
            self:Compile(catName)
            self:SyncToEngine()
            return
        end
    end
end

--- Get compile error for a category (if any).
--- @param catName string
--- @return string|nil
function Categories:GetError(catName)
    local compiled = compiledCategories[catName]
    return compiled and compiled.err or nil
end

-- =============================================================================
-- Initialization
-- =============================================================================

--- Register a custom rule function from a third-party addon.
--- @param name string Name of the rule function (will be exposed in the sandbox)
--- @param func function Function that receives (item, character, ...) and returns boolean
function Rules:Register(name, func)
    if type(name) ~= "string" or type(func) ~= "function" then
        return false, "invalid arguments"
    end
    ruleFunctions[name] = func
    for k in pairs(compiledRules) do
        compiledRules[k] = nil
    end
    return true
end

function Rules:Init()
    if Omni.Categories then
        Omni.Categories:CompileAll()
        Omni.Categories:SyncToEngine()
    end
end