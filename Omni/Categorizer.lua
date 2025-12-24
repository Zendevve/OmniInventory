-- =============================================================================
-- OmniInventory Categorizer (Stub)
-- =============================================================================
-- Will contain the filter pipeline and category assignment logic
-- =============================================================================

local addonName, Omni = ...

Omni.Categorizer = {}
local Categorizer = Omni.Categorizer

function Categorizer:Init()
    -- TODO: Implement categorization pipeline
end

function Categorizer:CategorizeItem(itemInfo)
    -- TODO: Return category for an item
    return "Uncategorized"
end

print("|cFF00FF00OmniInventory|r: Categorizer stub loaded")
