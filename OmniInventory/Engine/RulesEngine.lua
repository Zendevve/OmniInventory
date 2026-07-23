-- =============================================================================
-- OmniInventory Engine/RulesEngine.lua
-- Fast-Path Bitmask Evaluator & Priority Filter Pipeline Engine
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or _G.OmniInventory or _G.Omni

local RulesEngine = {
    rules = {},
    ruleOrder = {},
}
Omni.RulesEngine = RulesEngine

-- 32-Bit Bitmask Definitions for Fast-Path Engine Classification
Omni.MASK_EQUIPMENT   = 0x00000001 -- Bit 0: Weapons / Armor
Omni.MASK_CONSUMABLE  = 0x00000002 -- Bit 1: Potions / Flasks / Food
Omni.MASK_QUEST       = 0x00000004 -- Bit 2: Quest Items / Starters
Omni.MASK_TRADE_GOODS = 0x00000008 -- Bit 3: Crafting Reagents / Gems
Omni.MASK_JUNK        = 0x00000010 -- Bit 4: Gray items / Low-level white junk
Omni.MASK_BOE         = 0x00000020 -- Bit 5: Binds when equipped
Omni.MASK_BOP         = 0x00000040 -- Bit 6: Binds when picked up
Omni.MASK_SET_ITEM    = 0x00000080 -- Bit 7: Equipment set member
Omni.MASK_RECIPE      = 0x00000100 -- Bit 8: Profession recipes
Omni.MASK_KEYRING     = 0x00000200 -- Bit 9: Keys / Lockpicks

-- Local bit operation aliases (WoW 3.3.5a native bit library with standalone fallback)
local band = (bit and bit.band) or function(a, b) return 0 end
local bor  = (bit and bit.bor)  or function(a, b) return 0 end

RulesEngine.band = band
RulesEngine.bor  = bor

--- Registers or Updates a Rule in the Filter Pipeline
function RulesEngine:AddRule(id, priority, name, bitmask, formula, categoryID, enabled)
    if not id or not name then return end

    local ASTCompiler = Omni.ASTCompiler
    local closure = nil
    if formula and formula ~= "" then
        if ASTCompiler and ASTCompiler.Compile then
            closure = ASTCompiler.Compile(formula)
        end
        if not closure and Omni.Rules and Omni.Rules.Compile then
            local compiledFunc, compileErr = Omni.Rules:Compile(formula)
            if compiledFunc then
                closure = function(slotData, signature)
                    if compiledFunc(slotData) then
                        return 0, categoryID or name, priority or 50
                    end
                end
            end
        end
    end

    local rule = {
        id = id,
        priority = priority or 50,
        name = name,
        bitmask = bitmask or 0,
        formula = formula,
        categoryID = categoryID or id,
        closure = closure,
        enabled = (enabled ~= false),
    }

    self.rules[id] = rule
    self:RebuildRuleOrder()
    return rule
end

--- Re-sorts rule order array by priority (lower sequence number = higher precedence)
function RulesEngine:RebuildRuleOrder()
    table.wipe(self.ruleOrder)
    for _, rule in pairs(self.rules) do
        table.insert(self.ruleOrder, rule)
    end

    table.sort(self.ruleOrder, function(a, b)
        if a.priority == b.priority then
            return tostring(a.name) < tostring(b.name)
        end
        return a.priority < b.priority
    end)
end

--- Remove rule by ID
function RulesEngine:RemoveRule(id)
    if self.rules[id] then
        self.rules[id] = nil
        self:RebuildRuleOrder()
    end
end

--- Set rule enabled status
function RulesEngine:SetRuleEnabled(id, enabled)
    if self.rules[id] then
        self.rules[id].enabled = (enabled ~= false)
    end
end

--- Clear compiled rule closures and cached state
function RulesEngine:ClearCache()
    for _, rule in pairs(self.rules) do
        if rule.formula and rule.formula ~= "" and Omni.Rules and Omni.Rules.Compile then
            local compiledFunc = Omni.Rules:Compile(rule.formula)
            if compiledFunc then
                local catID = rule.categoryID
                local prio = rule.priority
                rule.closure = function(slotData, signature)
                    if compiledFunc(slotData) then
                        return 0, catID or rule.name, prio or 50
                    end
                end
            end
        end
    end
end

--- Sync rules engine state from Omni.Categories rules
function RulesEngine:SyncFromDB()
    table.wipe(self.rules)
    if Omni.Categories and Omni.Categories.GetAllRules then
        local rules = Omni.Categories:GetAllRules()
        for _, r in ipairs(rules or {}) do
            self:AddRule(
                r.id or r.name,
                r.priority or r.sequence or 50,
                r.name,
                r.bitmask or 0,
                r.rule or "",
                r.categoryTarget or r.categoryID or r.name,
                r.enabled ~= false
            )
        end
    end
    self:RebuildRuleOrder()
end

--- Fast-Path Bitmask Evaluation & Rule Pipeline Execution
-- Returns: bitmask, categoryID, categoryName, categoryPriority
function RulesEngine:EvaluateItem(slotData, signature)
    slotData = slotData or {}

    -- 1. Fast-Path Bitmask Evaluation Short-Circuits
    -- Junk Quality Short-Circuit
    if slotData.quality == 0 then
        return Omni.MASK_JUNK, "Junk", "Junk", -50
    end

    -- Keyring Container Short-Circuit
    if slotData.bagFamily == 256 or slotData.bagType == 256 then
        return Omni.MASK_KEYRING, "Keyring", "Keyring", 90
    end

    -- Fast Bitmask Signature Check if signature has bitmask preset
    if signature and signature.bitmask and signature.bitmask > 0 then
        if signature.categoryName then
            return signature.bitmask, signature.categoryID or signature.categoryName, signature.categoryName, signature.categoryPriority or 50
        end
    end

    -- 2. Priority Filter Pipeline Execution (Custom User Rules)
    for _, rule in ipairs(self.ruleOrder) do
        if rule.enabled ~= false then
            if rule.closure then
                local bitmask, catName, priority = rule.closure(slotData, signature)
                if bitmask and catName then
                    return bitmask, rule.categoryID or catName, catName, priority or rule.priority
                end
            elseif rule.bitmask > 0 and signature and signature.bitmask then
                if band(signature.bitmask, rule.bitmask) > 0 then
                    return rule.bitmask, rule.categoryID or rule.name, rule.name, rule.priority
                end
            end
        end
    end

    -- 3. Default Item Class Category Mapping Fallback Matrix
    local class = slotData.class
    if class == "Weapon" or class == "Armor" then
        local cat = (slotData.isEquipped or (signature and signature.isSetItem)) and "Equipment Sets" or "Equipment"
        return Omni.MASK_EQUIPMENT, cat, cat, 60
    elseif class == "Consumable" then
        return Omni.MASK_CONSUMABLE, "Consumables", "Consumables", 50
    elseif class == "Quest" then
        return Omni.MASK_QUEST, "Quest Items", "Quest Items", 80
    elseif class == "Trade Goods" or class == "Gem" then
        return Omni.MASK_TRADE_GOODS, "Trade Goods", "Trade Goods", 40
    elseif class == "Recipe" then
        return Omni.MASK_RECIPE, "Recipes", "Recipes", 70
    elseif class == "Container" then
        return 0, "Bags", "Bags", 30
    end

    return 0, "Miscellaneous", "Miscellaneous", 0
end
