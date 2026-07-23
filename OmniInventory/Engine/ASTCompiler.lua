-- =============================================================================
-- OmniInventory Engine/ASTCompiler.lua
-- Rule String Lexer, Tokenizer & Executable AST Closure Compiler (Zero loadstring)
-- =============================================================================

local addonName, Omni = ...
Omni = Omni or _G.OmniInventory or _G.Omni

local ASTCompiler = {}
Omni.ASTCompiler = ASTCompiler

-- Token Types
local TOKEN_IDENTIFIER = "IDENT"
local TOKEN_NUMBER     = "NUMBER"
local TOKEN_STRING     = "STRING"
local TOKEN_OPERATOR   = "OP"
local TOKEN_LPAREN     = "LPAREN"
local TOKEN_RPAREN     = "RPAREN"
local TOKEN_COMMA      = "COMMA"

ASTCompiler.TOKEN_IDENTIFIER = TOKEN_IDENTIFIER
ASTCompiler.TOKEN_NUMBER     = TOKEN_NUMBER
ASTCompiler.TOKEN_STRING     = TOKEN_STRING
ASTCompiler.TOKEN_OPERATOR   = TOKEN_OPERATOR
ASTCompiler.TOKEN_LPAREN     = TOKEN_LPAREN
ASTCompiler.TOKEN_RPAREN     = TOKEN_RPAREN
ASTCompiler.TOKEN_COMMA      = TOKEN_COMMA

--- Lexical Scanner: Converts rule formula string into token stream
function ASTCompiler.Tokenize(formula)
    if type(formula) ~= "string" or formula == "" then
        return {}
    end

    local tokens = {}
    local pos = 1
    local len = #formula

    while pos <= len do
        local c = formula:sub(pos, pos)
        
        if c:match("%s") then
            pos = pos + 1
        elseif c == "(" then
            table.insert(tokens, { type = TOKEN_LPAREN, value = "(" })
            pos = pos + 1
        elseif c == ")" then
            table.insert(tokens, { type = TOKEN_RPAREN, value = ")" })
            pos = pos + 1
        elseif c == "," then
            table.insert(tokens, { type = TOKEN_COMMA, value = "," })
            pos = pos + 1
        elseif c == ">" or c == "<" or c == "=" or c == "!" then
            local startPos = pos
            if pos < len then
                local nextC = formula:sub(pos + 1, pos + 1)
                if nextC == "=" then
                    pos = pos + 1
                end
            end
            local opStr = formula:sub(startPos, pos)
            table.insert(tokens, { type = TOKEN_OPERATOR, value = opStr })
            pos = pos + 1
        elseif c:match("[%a_]") then
            local startPos = pos
            while pos <= len and formula:sub(pos, pos):match("[%w_.]") do
                pos = pos + 1
            end
            local word = formula:sub(startPos, pos - 1)
            local lowerWord = word:lower()
            if lowerWord == "and" or lowerWord == "or" or lowerWord == "not" then
                table.insert(tokens, { type = TOKEN_OPERATOR, value = lowerWord })
            else
                table.insert(tokens, { type = TOKEN_IDENTIFIER, value = word })
            end
        elseif c == '"' or c == "'" then
            local quote = c
            local startPos = pos + 1
            pos = pos + 1
            while pos <= len and formula:sub(pos, pos) ~= quote do
                pos = pos + 1
            end
            table.insert(tokens, { type = TOKEN_STRING, value = formula:sub(startPos, pos - 1) })
            pos = pos + 1
        elseif c:match("[%d]") then
            local startPos = pos
            while pos <= len and formula:sub(pos, pos):match("[%d.]") do
                pos = pos + 1
            end
            local numVal = tonumber(formula:sub(startPos, pos - 1)) or 0
            table.insert(tokens, { type = TOKEN_NUMBER, value = numVal })
        else
            pos = pos + 1 -- Skip unrecognized character
        end
    end

    return tokens
end

--- Recursive Descent Parser: Builds AST Node Tree from Token Stream
local function ParseOrExpr(state)
    local left = state:ParseAndExpr()
    while state:Peek() and state:Peek().type == TOKEN_OPERATOR and state:Peek().value:lower() == "or" do
        state:Next()
        local right = state:ParseAndExpr()
        left = {
            kind = "LOGICAL",
            op = "OR",
            left = left,
            right = right
        }
    end
    return left
end

local function ParseAndExpr(state)
    local left = state:ParseNotExpr()
    while state:Peek() and state:Peek().type == TOKEN_OPERATOR and state:Peek().value:lower() == "and" do
        state:Next()
        local right = state:ParseNotExpr()
        left = {
            kind = "LOGICAL",
            op = "AND",
            left = left,
            right = right
        }
    end
    return left
end

local function ParseNotExpr(state)
    if state:Peek() and state:Peek().type == TOKEN_OPERATOR and state:Peek().value:lower() == "not" then
        state:Next()
        local operand = ParseNotExpr(state)
        return {
            kind = "UNARY",
            op = "NOT",
            operand = operand
        }
    end
    return state:ParsePrimaryExpr()
end

local function ParsePrimaryExpr(state)
    local tok = state:Peek()
    if not tok then return nil end

    if tok.type == TOKEN_LPAREN then
        state:Next() -- consume '('
        local expr = ParseOrExpr(state)
        if state:Peek() and state:Peek().type == TOKEN_RPAREN then
            state:Next() -- consume ')'
        end
        return expr
    elseif tok.type == TOKEN_IDENTIFIER then
        local identTok = state:Next()
        -- Check if it's a function call ident(...)
        if state:Peek() and state:Peek().type == TOKEN_LPAREN then
            state:Next() -- consume '('
            local args = {}
            if state:Peek() and state:Peek().type ~= TOKEN_RPAREN then
                repeat
                    local argExpr = ParseOrExpr(state)
                    if argExpr then table.insert(args, argExpr) end
                    if state:Peek() and state:Peek().type == TOKEN_COMMA then
                        state:Next() -- consume ','
                    else
                        break
                    end
                until not state:Peek() or state:Peek().type == TOKEN_RPAREN
            end
            if state:Peek() and state:Peek().type == TOKEN_RPAREN then
                state:Next() -- consume ')'
            end
            return {
                kind = "CALL",
                name = identTok.value,
                args = args
            }
        end

        -- Check if followed by comparison operator (e.g. quality >= 2)
        if state:Peek() and state:Peek().type == TOKEN_OPERATOR and state:Peek().value ~= "and" and state:Peek().value ~= "or" and state:Peek().value ~= "not" then
            local opTok = state:Next()
            local rightTok = state:Next()
            local rightVal = rightTok and rightTok.value or nil
            return {
                kind = "COMPARE",
                ident = identTok.value,
                op = opTok.value,
                value = rightVal
            }
        end

        return {
            kind = "IDENT",
            name = identTok.value
        }
    elseif tok.type == TOKEN_STRING or tok.type == TOKEN_NUMBER then
        local litTok = state:Next()
        return {
            kind = "LITERAL",
            value = litTok.value
        }
    end

    state:Next()
    return nil
end

function ASTCompiler.Parse(tokens)
    if not tokens or #tokens == 0 then return nil end

    local state = {
        tokens = tokens,
        index = 1,
        Peek = function(self) return self.tokens[self.index] end,
        Next = function(self)
            local tok = self.tokens[self.index]
            if tok then self.index = self.index + 1 end
            return tok
        end,
        ParseOrExpr = ParseOrExpr,
        ParseAndExpr = ParseAndExpr,
        ParseNotExpr = ParseNotExpr,
        ParsePrimaryExpr = ParsePrimaryExpr,
    }

    return ParseOrExpr(state)
end

--- AST Evaluator Node Runner
function ASTCompiler.EvaluateNode(node, slotData, sig)
    if not node then return false end
    slotData = slotData or {}

    local kind = node.kind
    if kind == "LOGICAL" then
        local leftVal = ASTCompiler.EvaluateNode(node.left, slotData, sig)
        if node.op == "AND" then
            if not leftVal then return false end
            return ASTCompiler.EvaluateNode(node.right, slotData, sig)
        elseif node.op == "OR" then
            if leftVal then return true end
            return ASTCompiler.EvaluateNode(node.right, slotData, sig)
        end
    elseif kind == "UNARY" then
        if node.op == "NOT" then
            return not ASTCompiler.EvaluateNode(node.operand, slotData, sig)
        end
    elseif kind == "COMPARE" then
        local targetVal = nil
        local ident = node.ident:lower()
        if ident == "quality" or ident == "rarity" then
            targetVal = slotData.quality or (sig and sig.quality) or 0
        elseif ident == "itemid" or ident == "id" then
            targetVal = slotData.itemID or (sig and sig.itemID) or 0
        elseif ident == "class" or ident == "type" then
            targetVal = slotData.class or (sig and sig.class) or ""
        elseif ident == "subclass" or ident == "subtype" then
            targetVal = slotData.subClass or (sig and sig.subClass) or ""
        elseif ident == "count" or ident == "stack" then
            targetVal = slotData.count or 1
        elseif ident == "name" then
            targetVal = slotData.name or (sig and sig.name) or ""
        end

        local op = node.op
        local val = node.value
        if type(targetVal) == "number" then
            val = tonumber(val) or 0
            if op == ">=" then return targetVal >= val
            elseif op == "<=" then return targetVal <= val
            elseif op == ">" then return targetVal > val
            elseif op == "<" then return targetVal < val
            elseif op == "==" or op == "=" then return targetVal == val
            elseif op == "!=" or op == "<>" then return targetVal ~= val
            end
        else
            targetVal = tostring(targetVal or ""):lower()
            val = tostring(val or ""):lower()
            if op == "==" or op == "=" then return targetVal == val
            elseif op == "!=" or op == "<>" then return targetVal ~= val
            end
        end
    elseif kind == "CALL" then
        local name = node.name:lower()
        if name == "isquest" then
            return (slotData.class == "Quest") or (sig and sig.isQuest) or false
        elseif name == "isbound" or name == "bound" then
            return (slotData.isBound) or (sig and sig.isBound) or false
        elseif name == "isjunk" or name == "junk" then
            return (slotData.quality == 0) or (sig and sig.quality == 0) or false
        elseif name == "itemid" or name == "id" then
            local targetID = slotData.itemID or (sig and sig.itemID) or 0
            for _, arg in ipairs(node.args) do
                local argVal = ASTCompiler.EvaluateNode(arg, slotData, sig)
                if type(argVal) ~= "number" and arg.value then argVal = tonumber(arg.value) end
                if targetID == argVal then return true end
            end
            return false
        elseif name == "type" or name == "class" then
            local targetClass = (slotData.class or (sig and sig.class) or ""):lower()
            for _, arg in ipairs(node.args) do
                local argVal = tostring(arg.value or ""):lower()
                if targetClass == argVal then return true end
            end
            return false
        elseif name == "quality" then
            local targetQual = slotData.quality or (sig and sig.quality) or 0
            if #node.args > 0 then
                local firstArg = node.args[1]
                if firstArg.kind == "COMPARE" or firstArg.kind == "LITERAL" then
                    local val = tonumber(firstArg.value) or 0
                    return targetQual >= val
                end
            end
            return targetQual >= 1
        end
    elseif kind == "IDENT" then
        local name = node.name:lower()
        if name == "isquest" then return (slotData.class == "Quest") or false
        elseif name == "junk" then return (slotData.quality == 0) or false
        elseif name == "boe" then return (sig and sig.isBOE) or false
        elseif name == "bop" then return (sig and sig.isBOP) or false
        end
    elseif kind == "LITERAL" then
        return node.value
    end

    return false
end

--- Compiles Token Stream into Executable AST Closure Function (Zero loadstring)
function ASTCompiler.Compile(tokens_or_formula)
    local tokens = tokens_or_formula
    if type(tokens_or_formula) == "string" then
        tokens = ASTCompiler.Tokenize(tokens_or_formula)
    end

    local astNode = ASTCompiler.Parse(tokens)

    -- Return closure function wrapping compiled AST logic
    local function Evaluator(slotData, sig)
        if not slotData then
            return 0, "Miscellaneous", 0
        end

        -- Fast bitmask evaluation short-circuit
        if slotData.quality == 0 then
            return Omni.MASK_JUNK or 0x00000010, "Junk", -50
        end
        if slotData.bagFamily == 256 or slotData.bagType == 256 then
            return Omni.MASK_KEYRING or 0x00000200, "Keyring", 90
        end

        -- Evaluate custom compiled AST rule if node tree exists
        if astNode then
            local matched = ASTCompiler.EvaluateNode(astNode, slotData, sig)
            if matched then
                local bitmask = (sig and sig.bitmask) or 0
                local catName = (sig and sig.categoryName) or "Custom Rule"
                local priority = (sig and sig.categoryPriority) or 100
                return bitmask, catName, priority
            end
        end

        -- Default classification fallback matrix
        local class = slotData.class
        if class == "Weapon" or class == "Armor" then
            return Omni.MASK_EQUIPMENT or 0x00000001, "Equipment", 60
        elseif class == "Consumable" then
            return Omni.MASK_CONSUMABLE or 0x00000002, "Consumables", 50
        elseif class == "Quest" then
            return Omni.MASK_QUEST or 0x00000004, "Quest Items", 80
        elseif class == "Trade Goods" then
            return Omni.MASK_TRADE_GOODS or 0x00000008, "Trade Goods", 40
        elseif class == "Recipe" then
            return Omni.MASK_RECIPE or 0x00000100, "Recipes", 70
        end

        return 0, "Miscellaneous", 0
    end

    return Evaluator, astNode
end
