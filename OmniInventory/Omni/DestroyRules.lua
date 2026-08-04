-- =============================================================================
-- OmniInventory Destroy Rules Engine
-- =============================================================================
-- Purpose: Keep-rules-first evaluator for item destruction and loot decisions.
--   Separate from RulesEngine:EvaluateItem() to avoid the quality==0 short-circuit
--   that blocks "keep grey" rules.
-- =============================================================================

local addonName, Omni = ...

Omni.DestroyRules = {}
local DestroyRules = Omni.DestroyRules

-- Action constants
DestroyRules.ACTION_KEEP    = "keep"
DestroyRules.ACTION_DESTROY = "destroy"
DestroyRules.ACTION_LOOT    = "loot"
DestroyRules.ACTION_SKIP    = "skip"
DestroyRules.ACTION_SELL    = "sell"

-- Protected quality threshold (never auto-destroy Rare+ unless explicit dangerous rule)
local PROTECTED_QUALITY = 3
-- Default value threshold (1 gold = 10000 copper)
local DEFAULT_VALUE_THRESHOLD = 10000

--- Get destroy rules from DB
local function GetDestroyRules()
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    local rules = OmniInventoryDB.global.destroyRules or {}
    -- Function closures cannot persist in SavedVariables, so rules that
    -- survived a UI reload lose their compiledFunc. Lazy-recompile them
    -- on first access so they keep matching without an explicit Init pass.
    for _, rule in pairs(rules) do
        local formula = rule.rule or rule.formula
        if rule and formula and formula ~= "" and not rule.compiledFunc then
            local func, err = DestroyRules:CompileRule(formula)
            if func then
                rule.compiledFunc = func
            end
        end
    end
    return rules
end

--- Get category loot preferences from DB
local function GetCategoryLootPrefs()
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    return OmniInventoryDB.global.categoryLootPrefs or {}
end

--- Get item overrides from DB
local function GetItemOverrides()
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    return OmniInventoryDB.global.destroyItemOverrides or {}
end

--- Check if auto-destroy is enabled
function DestroyRules:IsEnabled()
    if Omni.Data then
        return Omni.Data:Get("autoDestroyEnabled") == true
    end
    return false
end

--- Check if dry-run mode is active
function DestroyRules:IsDryRun()
    if Omni.Data then
        local val = Omni.Data:Get("destroyDryRun")
        if val ~= nil then return val end
    end
    return true -- Default: dry-run ON
end

--- Get value threshold
function DestroyRules:GetValueThreshold()
    if Omni.Data then
        local val = Omni.Data:Get("destroyValueThreshold")
        if val then return val end
    end
    return DEFAULT_VALUE_THRESHOLD
end

--- Hard-coded protection check (cannot be overridden)
local function IsProtected(slotData)
    if not slotData then return true end
    
    -- Quest items always protected
    if slotData.class == "Quest" then return true end
    
    -- BoP equipment always protected
    if (slotData.bindType == "BoP" or slotData.isBound) 
       and (slotData.class == "Armor" or slotData.class == "Weapon") then
        return true
    end
    
    -- BoA always protected
    if slotData.bindType == "BoA" or slotData.quality == 7 then
        return true
    end
    
    -- Pinned items protected
    if Omni.Data and slotData.itemID and Omni.Data:IsPinned(slotData.itemID) then
        return true
    end
    
    -- Items in junkExclude protected
    if Omni.Data and slotData.itemID then
        local exclude = Omni.Data:Get("junkExclude") or {}
        if exclude[slotData.itemID] then return true end
    end
    
    -- Items in destroy exclude list protected
    local overrides = GetItemOverrides()
    if slotData.itemID and overrides[slotData.itemID] == "never_destroy" then
        return true
    end
    
    -- Value threshold protection
    local threshold = DestroyRules:GetValueThreshold()
    if slotData.vendorPrice and slotData.vendorPrice > threshold then
        return true
    end
    
    -- Quality >= 3 (Rare+) protected unless explicitly overridden
    if slotData.quality and slotData.quality >= PROTECTED_QUALITY then
        return true
    end
    
    return false
end

--- Evaluate a single item against destroy rules
-- Returns: action ("keep"|"destroy"|"loot"|"skip"|"sell"|nil), reason string
function DestroyRules:Evaluate(slotData)
    if not slotData then return nil, "no data" end
    
    -- Hard-coded protection always wins
    if IsProtected(slotData) then
        return DestroyRules.ACTION_KEEP, "protected item"
    end
    
    -- Check per-item overrides first
    local overrides = GetItemOverrides()
    if slotData.itemID then
        local override = overrides[slotData.itemID]
        if override == "always_destroy" then
            return DestroyRules.ACTION_DESTROY, "item override: always destroy"
        elseif override == "always_loot" then
            return DestroyRules.ACTION_LOOT, "item override: always loot"
        elseif override == "never_destroy" then
            return DestroyRules.ACTION_KEEP, "item override: never destroy"
        end
    end
    
    -- Check destroy rules (keep-rules-first: Keep rules win over all others)
    local rules = GetDestroyRules()
    local keepMatch = nil
    local destroyMatch = nil
    local nonKeepMatch = nil

    for _, rule in ipairs(rules) do
        if rule.enabled ~= false then
            if rule.compiledFunc then
                local ok, result = pcall(rule.compiledFunc, slotData)
                if ok and result then
                    -- Normalize action (API stores lowercase, Options UI stores
                    -- capitalized like "Keep"/"Destroy").
                    local action = rule.action and string.lower(rule.action) or "destroy"
                    if action == "keep" then
                        keepMatch = rule.name or "unnamed keep rule"
                        break -- Keep wins immediately
                    elseif action == "destroy" and not destroyMatch then
                        destroyMatch = rule.name or "unnamed destroy rule"
                    elseif not nonKeepMatch then
                        nonKeepMatch = rule -- loot / skip / sell
                    end
                end
            end
        end
    end

    if keepMatch then
        return DestroyRules.ACTION_KEEP, "keep rule: " .. keepMatch
    end

    if nonKeepMatch then
        local action = string.lower(nonKeepMatch.action or "destroy")
        if action == "loot" then
            return DestroyRules.ACTION_LOOT, "rule: " .. (nonKeepMatch.name or "unnamed")
        elseif action == "skip" then
            return DestroyRules.ACTION_SKIP, "rule: " .. (nonKeepMatch.name or "unnamed")
        elseif action == "sell" then
            return DestroyRules.ACTION_SELL, "rule: " .. (nonKeepMatch.name or "unnamed")
        end
    end

    if destroyMatch then
        return DestroyRules.ACTION_DESTROY, "destroy rule: " .. destroyMatch
    end
    
    -- Check category loot preferences
    if Omni.Categorizer and Omni.Categorizer.GetCategory then
        local category = Omni.Categorizer:GetCategory(slotData)
        if category then
            local prefs = GetCategoryLootPrefs()
            if prefs[category] then
                -- Normalize case (Options UI stores capitalized prefs)
                local action = string.lower(prefs[category])
                if action == "destroy" then
                    return DestroyRules.ACTION_DESTROY, "category preference: " .. category
                elseif action == "loot" then
                    return DestroyRules.ACTION_LOOT, "category preference: " .. category
                elseif action == "skip" then
                    return DestroyRules.ACTION_SKIP, "category preference: " .. category
                elseif action == "sell" then
                    return DestroyRules.ACTION_SELL, "category preference: " .. category
                end
            end
        end
    end
    
    -- Fallback: junk items (quality 0) → sell at vendor
    if slotData.quality == 0 then
        return DestroyRules.ACTION_SELL, "grey junk (auto-sell)"
    end
    
    -- Default: loot
    return DestroyRules.ACTION_LOOT, "default"
end

--- Build slotData from bag/slot
function DestroyRules:BuildSlotData(bagID, slotID)
    local link = GetContainerItemLink(bagID, slotID)
    if not link then return nil end
    
    local texture, count, locked, quality, readable, lootable, itemLink = GetContainerItemInfo(bagID, slotID)
    local itemID = tonumber(string.match(link, "item:(%d+)"))
    -- GetItemInfo returns: name, link, quality, iLevel, reqLevel, itemType,
    -- itemSubType, maxStack, equipLoc, icon, vendorPrice, classID, subClassID...
    local name, _, quality2, iLevel, _, itemClass, itemSubType, _, _, _, vendorPrice = GetItemInfo(link)
    
    return {
        bagID = bagID,
        slotID = slotID,
        itemID = itemID,
        name = name or "Unknown",
        hyperlink = link,
        quality = quality or 0,
        count = count or 1,
        locked = locked,
        vendorPrice = vendorPrice or 0,
        itemLevel = iLevel or 0,
        class = itemClass or "",
        itemSubType = itemSubType or "",
        bindType = nil, -- Will be resolved by Rules engine if needed
        isBound = nil,
    }
end

--- Build slotData from loot slot
function DestroyRules:BuildSlotDataFromLoot(lootSlot)
    if not lootSlot or not GetLootSlotInfo then return nil end
    
    local lootIcon, lootName, lootQuantity, currencyID, lootQuality, locked, isQuestItem, questId, isActive = GetLootSlotInfo(lootSlot)
    if not lootName then return nil end
    
    local link = GetLootSlotLink and GetLootSlotLink(lootSlot) or nil
    local itemID = link and tonumber(string.match(link, "item:(%d+)")) or nil
    local vendorPrice = 0
    local itemClass = ""
    local itemSubType = ""
    local itemLevel = 0
    
    if link then
        local _, _, _, iLvl, _, class, subType, _, _, _, price = GetItemInfo(link)
        vendorPrice = price or 0
        itemClass = class or ""
        itemSubType = subType or ""
        itemLevel = iLvl or 0
    end
    
    return {
        lootSlot = lootSlot,
        itemID = itemID,
        name = lootName,
        hyperlink = link,
        quality = lootQuality or 0,
        count = lootQuantity or 1,
        locked = locked,
        vendorPrice = vendorPrice,
        itemLevel = itemLevel,
        class = itemClass,
        itemSubType = itemSubType,
        isQuestItem = isQuestItem,
        currencyID = currencyID,
    }
end

--- Compile a destroy rule formula into a callable function
function DestroyRules:CompileRule(formula)
    if not formula or formula == "" then return nil, "empty formula" end
    
    -- Try ASTCompiler first (zero-loadstring)
    if Omni.ASTCompiler and Omni.ASTCompiler.Compile then
        local func, astNode = Omni.ASTCompiler.Compile(formula)
        if func then
            return function(slotData)
                local matched = Omni.ASTCompiler.EvaluateNode(astNode, slotData)
                return matched == true
            end
        end
    end
    
    -- Fallback to Rules:Compile (loadstring-based)
    if Omni.Rules and Omni.Rules.Compile then
        local func, err = Omni.Rules:Compile(formula)
        if func then
            return function(slotData)
                return func(slotData) == true
            end
        end
        return nil, err
    end
    
    return nil, "no compiler available"
end

--- Add/Update a destroy rule
function DestroyRules:AddRule(id, opts)
    if not id then return false, "id required" end
    opts = opts or {}
    
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    OmniInventoryDB.global.destroyRules = OmniInventoryDB.global.destroyRules or {}
    
    local formula = opts.rule or opts.formula or ""
    local compiledFunc = nil
    if formula ~= "" then
        local func, err = self:CompileRule(formula)
        if func then
            compiledFunc = func
        end
    end

    local rule = {
        id = id,
        name = opts.name or id,
        action = string.lower(opts.action or "destroy"),
        rule = formula,
        formula = formula, -- UI alias (Options tab reads/writes this field)
        compiledFunc = compiledFunc,
        enabled = opts.enabled ~= false,
        priority = opts.priority or 50,
    }

    OmniInventoryDB.global.destroyRules[id] = rule
    return true
end

--- Remove a destroy rule
function DestroyRules:RemoveRule(id)
    if not id then return end
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    if OmniInventoryDB.global.destroyRules then
        OmniInventoryDB.global.destroyRules[id] = nil
    end
end

--- Get all destroy rules sorted by priority
function DestroyRules:GetAllRules()
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    local rules = OmniInventoryDB.global.destroyRules or {}
    local list = {}
    for _, r in pairs(rules) do
        -- Lazy recompile (function closures don't survive SavedVariables)
        local formula = r.rule or r.formula
        if formula and formula ~= "" and not r.compiledFunc then
            local func, err = self:CompileRule(formula)
            if func then
                r.compiledFunc = func
            end
        end
        table.insert(list, r)
    end
    table.sort(list, function(a, b)
        return (a.priority or 50) < (b.priority or 50)
    end)
    return list
end

--- Compile all destroy rules
function DestroyRules:CompileAll()
    local rules = self:GetAllRules()
    for _, rule in ipairs(rules) do
        local formula = rule.rule or rule.formula
        if formula and formula ~= "" then
            local func, err = self:CompileRule(formula)
            if func then
                rule.compiledFunc = func
            end
        end
    end
end

--- Set category loot preference
function DestroyRules:SetCategoryPref(category, action)
    if not category then return end
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    OmniInventoryDB.global.categoryLootPrefs = OmniInventoryDB.global.categoryLootPrefs or {}
    if action then
        OmniInventoryDB.global.categoryLootPrefs[category] = string.lower(action)
    else
        OmniInventoryDB.global.categoryLootPrefs[category] = nil
    end
end

--- Get all category loot preferences
function DestroyRules:GetCategoryPrefs()
    return GetCategoryLootPrefs()
end

--- Set item override
function DestroyRules:SetItemOverride(itemID, action)
    if not itemID then return end
    OmniInventoryDB = OmniInventoryDB or {}
    OmniInventoryDB.global = OmniInventoryDB.global or {}
    OmniInventoryDB.global.destroyItemOverrides = OmniInventoryDB.global.destroyItemOverrides or {}
    if action then
        OmniInventoryDB.global.destroyItemOverrides[itemID] = action
    else
        OmniInventoryDB.global.destroyItemOverrides[itemID] = nil
    end
end

--- Get item override
function DestroyRules:GetItemOverride(itemID)
    if not itemID then return nil end
    local overrides = GetItemOverrides()
    return overrides[itemID]
end
