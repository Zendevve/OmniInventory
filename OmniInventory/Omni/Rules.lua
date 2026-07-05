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
-- User-Defined Categories (A18)
-- =============================================================================

Omni.Categories = Omni.Categories or {}
local Categories = Omni.Categories

local categoriesDB = nil       -- OmniInventoryDB.global.userCategories
local compiledCategories = {}  -- name -> { compiledRule, itemList, err }

local function ensureCategoriesDB()
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    OmniInventoryDB.global.userCategories = OmniInventoryDB.global.userCategories or {}
    return OmniInventoryDB.global.userCategories
end

--- Create or update a user-defined category.
--- @param name string Category name
--- @param opts table { sequence, list, rule, classes, nameSort }
function Categories:Create(name, opts)
    if not name or name == "" then return false, "name required" end
    local db = ensureCategoriesDB()
    opts = opts or {}
    db[name] = {
        name = name,
        sequence = opts.sequence or 50,
        list = opts.list or {},
        rule = opts.rule or "",
        classes = opts.classes or {},
        nameSort = opts.nameSort or name,
    }
    self:Compile(name)
    return true
end

--- Delete a user-defined category.
--- @param name string
function Categories:Delete(name)
    local db = ensureCategoriesDB()
    db[name] = nil
    compiledCategories[name] = nil
end

--- Get a user-defined category definition.
--- @param name string
--- @return table|nil
function Categories:Get(name)
    local db = ensureCategoriesDB()
    return db[name]
end

--- Get all user-defined category names, sorted by sequence.
--- @return table
function Categories:GetAll()
    local db = ensureCategoriesDB()
    local list = {}
    for name, cat in pairs(db) do
        table.insert(list, cat)
    end
    table.sort(list, function(a, b)
        return (a.sequence or 50) < (b.sequence or 50)
    end)
    return list
end

--- Compile a category's rule and cache it.
--- @param name string
function Categories:Compile(name)
    local cat = self:Get(name)
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
end

--- Compile all user-defined categories.
function Categories:CompileAll()
    local db = ensureCategoriesDB()
    for name in pairs(db) do
        self:Compile(name)
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

    -- Check class-specific lists
    local cat = self:Get(catName)
    if cat and cat.classes then
        local _, class = UnitClass("player")
        if class and cat.classes[class] and cat.classes[class].list then
            for _, itemID in ipairs(cat.classes[class].list) do
                if itemID == item.itemID then return true end
            end
        end
    end

    -- Check rule
    if compiled.compiledRule then
        return Rules:Match(compiled.compiledRule, item)
    end

    -- Check class-specific rules
    if cat and cat.classes then
        local _, class = UnitClass("player")
        if class and cat.classes[class] and cat.classes[class].rule then
            local classCompiled = compiledCategories[catName .. "_" .. class]
            if not classCompiled then
                local func, err = Rules:Compile(cat.classes[class].rule)
                if func then
                    compiledCategories[catName .. "_" .. class] = { compiledRule = func }
                    classCompiled = compiledCategories[catName .. "_" .. class]
                end
            end
            if classCompiled and classCompiled.compiledRule then
                return Rules:Match(classCompiled.compiledRule, item)
            end
        end
    end

    return false
end

--- Add an item to a category's direct list.
--- @param catName string
--- @param itemID number
function Categories:AddItem(catName, itemID)
    if not catName or not itemID then return end
    local cat = self:Get(catName)
    if not cat then return end
    cat.list = cat.list or {}
    -- Avoid duplicates
    for _, id in ipairs(cat.list) do
        if id == itemID then return end
    end
    table.insert(cat.list, itemID)
    self:Compile(catName)
end

--- Remove an item from a category's direct list.
--- @param catName string
--- @param itemID number
function Categories:RemoveItem(catName, itemID)
    if not catName or not itemID then return end
    local cat = self:Get(catName)
    if not cat or not cat.list then return end
    for i, id in ipairs(cat.list) do
        if id == itemID then
            table.remove(cat.list, i)
            self:Compile(catName)
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
    -- Clear compiled rules cache to allow custom rule to be evaluated in new compilations
    for k in pairs(compiledRules) do
        compiledRules[k] = nil
    end
    return true
end

function Rules:Init()
    -- Compile all user-defined categories on load
    if Omni.Categories then
        Omni.Categories:CompileAll()
    end
end