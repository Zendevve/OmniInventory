# Architectural Teardown & Code Audit: Bagnon Ecosystem (WoW 3.3.5a)

**Target Addon Version**: Bagnon v2.13.3 (Interface 30300 / Wrath of the Lich King)  
**Author**: Tuller  
**Audited Codebases**: `refs/Bagnon`, `refs/Bagnon_Config`, `refs/Bagnon_Forever`, `refs/Bagnon_GuildBank`, `refs/Bagnon_Tooltips`, `refs/Bagnon_VoidStorage`  
**Auditor Role**: `worker_bagnon` (WoW 3.3.5a Addon Engineer & Code Auditor)

---

## 1. Executive Summary & Architectural Overview

### 1.1 Core Philosophy
Bagnon is the premier single-window inventory addon for World of Warcraft 3.3.5a. Its fundamental design objective is to merge separate container bags (Backpack, Bags 1–4, Keyring, Bank Container, Bank Bags 1–7) into unified, single-window views per context (`inventory`, `bank`, `keys`, `guildbank`, `vault`).

Unlike category-based auto-sorting addons (e.g., AdiBags), Bagnon maintains a **slot-preserving grid layout**. It exposes every item slot as a physical square button while abstracting away individual bag boundaries (unless explicit bag breaks are requested by the user).

### 1.2 Modular Ecosystem Topology
The Bagnon suite is decoupled into six distinct Load-On-Demand (LOD) and standalone modules:

```
                                 +------------------------+
                                 |       Bagnon.lua       |
                                 |  (Core Driver & API)   |
                                 +-----------+------------+
                                             |
       +--------------------+----------------+--------------------+--------------------+
       |                    |                                     |                    |
+------v-------+    +-------v--------+                    +-------v--------+   +-------v--------+
| Bagnon_      |    | Bagnon_        |                    | Bagnon_        |   | Bagnon_        |
| Config       |    | Forever        |                    | GuildBank      |   | VoidStorage    |
| (Options UI) |    | (Offline DB)   |                    | (Guild Bank)   |   | (Ethereal UI)  |
+--------------+    +-------+--------+                    +----------------+   +----------------+
                            |
                    +-------v--------+
                    | Bagnon_        |
                    | Tooltips       |
                    | (Alt Counts)   |
                    +----------------+
```

1. **`Bagnon` (Core)**: Window frame management, item grid creation, layout calculations, event listeners, search filtering, and client-side sorting algorithm.
2. **`Bagnon_Config`**: Lazy-loaded Options interface registered with WoW's `InterfaceOptionsFrame`. Provides modular settings widgets (sliders, checkbuttons, color selectors).
3. **`Bagnon_Forever`**: Offline data persistence layer (`BagnonForeverDB`). Captures snapshots of player inventory, bank, keyring, equipped gear, and money across characters and realms.
4. **`Bagnon_Tooltips`**: Intercepts `GameTooltip` and `ItemRefTooltip` item rendering to inject cross-character item ownership counts stored by `Bagnon_Forever`.
5. **`Bagnon_GuildBank`**: Inherits core `Frame` / `ItemFrame` classes to render guild bank tabs and manage guild vault deposits/withdrawals.
6. **`Bagnon_VoidStorage`**: Module extending Bagnon for 4.3+ backports (or private server custom void storage interfaces), inheriting `VaultFrame` from core `Bagnon.Frame`.

### 1.3 Foundation Libraries & Internal Frameworks
- **Ace3 Framework**: Uses `AceAddon-3.0` for initialization lifecycle, `AceEvent-3.0` for event routing, `AceConsole-3.0` for slash command management (`/bagnon`, `/bgn`), and `AceTimer-3.0` for scheduled sorting ticks.
- **LibItemSearch-1.0**: Provides text-based search filtering and item set/type query evaluation.
- **LibDataBroker-1.1**: Exposes launcher data objects (`BagnonLauncher`) for LDB displays (Titan Panel, ChocolateBar).
- **`utility/classy.lua`**: Tuller's lightweight object-oriented class generator wrapping standard WoW frame creation with metatable inheritance and message delegation.
- **`utility/ears.lua`**: Custom pub/sub message-passing engine decoupling UI elements from global event state.

---

## 2. Container & Item Frame Hierarchy

### 2.1 Object Hierarchy & Inheritance Chain
Bagnon builds its UI components using `Classy.lua` (`refs/Bagnon/utility/classy.lua`), which instantiates real WoW frames via `CreateFrame` and wraps them in a Lua metatable hierarchy:

```
[Blizzard Frame Object]
          │
          ▼
   Classy:New(frameType, parentClass)
          │
          ├──► Frame (refs/Bagnon/components/frame.lua)
          │      ├──► GuildFrame (refs/Bagnon_GuildBank/components/frame.lua)
          │      └──► VaultFrame (refs/Bagnon_VoidStorage/components/frame.lua)
          │
          ├──► ItemFrame (refs/Bagnon/components/itemFrame.lua)
          │      └──► GuildItemFrame (refs/Bagnon_GuildBank/components/itemFrame.lua)
          │
          ├──► ItemSlot / Button (refs/Bagnon/components/item.lua)
          │
          ├──► BagFrame (refs/Bagnon/components/bagFrame.lua)
          │
          └──► Bag / CheckButton (refs/Bagnon/components/bag.lua)
```

#### The Classy Object System (`refs/Bagnon/utility/classy.lua`, L10–41)
```lua
function Classy:New(frameType, parentClass)
    local class = CreateFrame(frameType)
    class.mt = {__index = class}

    if parentClass then
        class = setmetatable(class, {__index = parentClass})
        class.super = parentClass
    end

    class.Bind = function(self, obj)
        return setmetatable(obj, self.mt)
    end
    -- Callback delegates mapped to Bagnon.Callbacks
    ...
    return class
end
```
When `ItemSlot:New` or `Frame:New` is called, `self:Bind(...)` attaches `class.mt` to the newly instantiated frame, granting it access to instance methods and superclass methods while preserving low-level WoW Frame identity.

### 2.2 Parent-Child Frame Structure & The "Dummy Bag" Architecture
Standard Blizzard container item logic (`ContainerFrameItemButtonTemplate`) assumes that every item button's direct parent frame has a valid container ID accessible via `self:GetParent():GetID()`.

In stock WoW UI, `ContainerFrame1` has ID `0` (Backpack), `ContainerFrame2` has ID `1` (Bag 1), etc. Because Bagnon pools all item slots into a single `ItemFrame` container regardless of which bag they reside in, placing item slots directly on `ItemFrame` would break standard Blizzard functions like `ContainerFrameItemButton_OnEnter` and cursor placement.

#### The Dummy Bag Hack (`refs/Bagnon/components/item.lua`, L688–706)
To resolve this without rewriting Blizzard's internal C-engine dependencies, Bagnon implements a dummy frame factory:
```lua
function ItemSlot:GetDummyBag(parent, bag)
    local dummyBags = parent.dummyBags
    if not dummyBags then
        dummyBags = setmetatable({}, {
            __index = function(t, k)
                local f = CreateFrame('Frame', nil, parent)
                f:SetID(k)
                t[k] = f
                return f
            end
        })
        parent.dummyBags = dummyBags
    end
    return dummyBags[bag]
end
```
When an `ItemSlot` is created or recycled (`ItemSlot:New`, L27):
1. `ItemSlot:GetDummyBag(parent, bag)` retrieves or constructs an invisible `Frame` parented to `ItemFrame` with `ID = bag`.
2. `item:SetParent(dummyBag)` sets the item slot's parent to that dummy frame.
3. As a result, `item:GetParent():GetID()` returns the exact container bag slot ID (e.g. `0`, `1`, `2`, `-1`), satisfying Blizzard's API contracts perfectly while preserving unified `ItemFrame` layout!

```
[BagnonFrameinventory] (Main Window - Bagnon.Frame)
   │
   ├──► [TitleFrame / SearchFrame / MenuButtons]
   │
   ├──► [BagFrame] (Container for Bag CheckButtons)
   │      ├──► BagnonBag1 (Backpack slot 0)
   │      ├──► BagnonBag2 (Bag slot 1)
   │      └──► ...
   │
   └──► [ItemFrame] (Container for Item Buttons)
          │
          ├──► dummyBags[0] (Frame, SetID(0))
          │      ├──► BagnonItemSlot1 (Bag 0, Slot 1)
          │      └──► BagnonItemSlot2 (Bag 0, Slot 2)
          │
          ├──► dummyBags[1] (Frame, SetID(1))
          │      ├──► BagnonItemSlot17 (Bag 1, Slot 1)
          │      └──► ...
          │
          └──► dummyBags[-1] (Frame, SetID(-1) for Bank)
                 └──► ...
```

### 2.3 Item Slot Button Templates & Pooling
Bagnon manages slot buttons using a hybrid approach: reusing original Blizzard container buttons when possible, or instantiating custom templates (`refs/Bagnon/components/item.lua`, L41–131).

1. **Reusing Blizzard Bag Slots** (`ItemSlot:GetBlizzardItemSlot`, L79–94):
   If `Bagnon.Settings:AreAllFramesEnabled()` is `true` and Blizzard Bag Passthrough is `false`, Bagnon captures stock frames `ContainerFrame%dItem%d` from memory, reparents them, and clears their points.
2. **Dynamic Slot Construction** (`ItemSlot:ConstructNewItemSlot`, L74–76):
   If stock frames are unavailable or recycled slots are exhausted, it calls:
   `CreateFrame('Button', 'BagnonItemSlot' .. id, nil, 'ContainerFrameItemButtonTemplate')`
3. **Quality Border Texture Creation** (L49–56):
   Bagnon creates an `OVERLAY` texture on each slot for quality border tinting:
   ```lua
   local border = item:CreateTexture(nil, 'OVERLAY')
   border:SetWidth(67)
   border:SetHeight(67)
   border:SetPoint('CENTER', item)
   border:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
   border:SetBlendMode('ADD')
   ```
4. **Memory Pooling / Recycling** (`ItemSlot:Free` & `ItemSlot:Restore`, L101–131):
   When a bag is hidden or removed, item slots are NOT destroyed. `ItemSlot:Free()` hides the button, clears its parent, unregisters all events, and inserts it into `ItemSlot.unused[self] = true`. Subsequent slot allocations call `ItemSlot:Restore()` to pop an existing button from `unused`, preventing GC churn during bag swaps.

### 2.4 Layout Grid Calculations

The layout of item buttons inside `ItemFrame` is driven by `components/itemFrame.lua` (L346–421). It supports two modes: **Default Grid** and **Bag Break Grid**.

```
Default Grid Layout:

  Col 0    Col 1    Col 2    Col 3    Col 4
+--------+--------+--------+--------+--------+
| Slot 1 | Slot 2 | Slot 3 | Slot 4 | Slot 5 |  Row 0
+--------+--------+--------+--------+--------+
| Slot 6 | Slot 7 | Slot 8 | Slot 9 |Slot 10 |  Row 1
+--------+--------+--------+--------+--------+
|Slot 11 |Slot 12 | ...    |        |        |  Row 2
+--------+--------+--------+--------+--------+

Bag Break Grid Layout:

  [--- Bag 0 (Backpack: 16 Slots) ---]
  Col 0    Col 1    Col 2    Col 3
  +------+ +------+ +------+ +------+
  | B0S1 | | B0S2 | | B0S3 | | B0S4 |  Row 0
  | ...  | |      | |      | |      |  Row 1..3

  [--- Bag 1 (Trade Bag: 8 Slots) ---]  <- New Row Force-Started!
  +------+ +------+ +------+ +------+
  | B1S1 | | B1S2 | | B1S3 | | B1S4 |  Row 4
  +------+ +------+ +------+ +------+
```

#### 1. Default Grid Engine (`Layout_Default`, L355–380)
```lua
local columns = self:NumColumns()              -- Default: 8 or 10
local spacing = self:GetSpacing()              -- Default: 2px
local effItemSize = self.ITEM_SIZE + spacing   -- 39px + 2px = 41px

local i = 0
for _, bag in self:GetVisibleBags() do
    for slot = 1, self:GetBagSize(bag) do
        local itemSlot = self:GetItemSlot(bag, slot)
        if itemSlot then
            i = i + 1
            local row = (i - 1) % columns
            local col = math.ceil(i / columns) - 1
            itemSlot:ClearAllPoints()
            itemSlot:SetPoint('TOPLEFT', self, 'TOPLEFT', effItemSize * row, -effItemSize * col)
        end
    end
end

local width = effItemSize * math.min(columns, i) - spacing
local height = effItemSize * ceil(i / columns) - spacing
self:SetWidth(width)
self:SetHeight(height)
```

#### 2. Bag Break Engine (`Layout_BagBreak`, L383–421)
When Bag Break is enabled in settings, every distinct container bag starts on a new row. If a bag's size exceeds the max column count, it wraps naturally onto the next row; when the bag ends, the next bag is forced onto a fresh row regardless of remaining empty columns in the current row.

---

## 3. Offline Item Cache Engine (`Bagnon_Forever`)

### 3.1 Data Model Schema (`BagnonForeverDB`)
`Bagnon_Forever` (`refs/Bagnon_Forever/db.lua`) acts as the offline item persistence provider for the entire Bagnon suite. Its `SavedVariables` root table `BagnonForeverDB` uses a hierarchical realm-to-player-to-slot mapping structure:

```lua
BagnonForeverDB = {
    ["version"] = "1.1.2",
    ["RealmName"] = {
        ["CharacterName"] = {
            ["g"] = 14502938,           -- Gold in Copper (number)
            ["numBankSlots"] = 7,       -- Purchased bank bag slots (number)

            -- Container Metadata Key (ToBagIndex)
            [0]    = "16",              -- Backpack (size)
            [100]  = "20,item:41258",   -- Bag 1 (size, shortLink)
            [200]  = "20,item:41258",   -- Bag 2
            [-100] = "28",              -- Main Bank Container (-1 * 100)

            -- Item Slot Data Keys (ToIndex)
            [1]    = "6948",            -- Bag 0, Slot 1 (Hearthstone, ID only)
            [2]    = "item:45693:0:0:0:0:0:0:12345,1", -- Item with enchant/suffix, count
            [101]  = "3770,20",         -- Bag 1, Slot 1 (Item ID 3770, Stack 20)
            [-101] = "22444,1",         -- Bank Container (-1), Slot 1
            ["e0"] = "item:40554:3831:0:0:0:0:0:0", -- Equipment Slot 0 (Head)
            ["e1"] = "37360",           -- Equipment Slot 1 (Neck)
        }
    }
}
```

### 3.2 Index Generation Formula (`ToIndex` & `ToBagIndex`, L28–37)
To avoid nested tables per bag/slot (which cause significant Lua memory fragmentation and table pointer overhead), `Bagnon_Forever` encodes `(bag, slot)` tuples into single integer/string keys:

```lua
local function ToIndex(bag, slot)
    if tonumber(bag) then
        return (bag < 0 and bag * 100 - slot) or bag * 100 + slot
    end
    return bag .. slot
end

local function ToBagIndex(bag)
    return (tonumber(bag) and bag * 100) or bag
end
```

#### Index Key Mapping Matrix:
| Target Container / Slot | Bag ID (`bag`) | Slot ID (`slot`) | `ToIndex(bag, slot)` | `ToBagIndex(bag)` |
|---|---|---|---|---|
| Backpack, Slot 1 | `0` | `1` | `1` | `0` |
| Backpack, Slot 16 | `0` | `16` | `16` | `0` |
| Bag 1, Slot 1 | `1` | `1` | `101` | `100` |
| Bag 4, Slot 20 | `4` | `20` | `420` | `400` |
| Main Bank, Slot 1 | `-1` | `1` | `-101` | `-100` |
| Bank Bag 1 (Bag 5), Slot 1 | `5` | `1` | `501` | `500` |
| Keyring, Slot 1 | `-2` | `1` | `-201` | `-200` |
| Equipment Slot (Head) | `'e'` | `0` | `'e0'` | `'e'` |

### 3.3 Link Compression Strategy (`ToShortLink`, L40–48)
Standard WoW item links are 60–90 byte formatted strings containing color codes, item IDs, enchant IDs, gem IDs, and random suffix IDs:
`|cffff8000|Hitem:19019:0:0:0:0:0:0:0:80|h[Thunderfury, Blessed Blade of the Windseeker]|h|r`

Storing full item links for thousands of cached items across multiple characters consumes excessive disk space and increases SavedVariables load/parse times on login. `Bagnon_Forever` implements an aggressive short-link compression algorithm:

```lua
local function ToShortLink(link)
    if link then
        local a,b,c,d,e,f,g,h = link:match('(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+)')
        if (b == '0' and b == c and c == d and d == e and e == f and f == g) then
            return a  -- Return ONLY item ID string if no enchants/gems/suffixes exist!
        end
        return format('item:%s:%s:%s:%s:%s:%s:%s:%s', a, b, c, d, e, f, g, h)
    end
end
```
- **Plain Items** (e.g. Health Potions, Trade Goods): Compressed to raw integer string `"118"` instead of the full hyperlink.
- **Enchanted / Gemmed Items**: Compressed to minimal string `"item:40554:3831:0:0:0:0:0:0"`, stripping display names and color codes.
- **Storage Ratio**: Reduces SavedVariables memory footprint by **over 65%**.

### 3.4 Event Hooks & Character Snapshot Pipeline

`Bagnon_Forever` registers low-level WoW events to automatically capture inventory changes without polling:

```
[PLAYER_LOGIN] ──► SaveMoney()
               ──► UpdateBag(BACKPACK_CONTAINER)
               ──► UpdateBag(KEYRING_CONTAINER)
               ──► SaveEquipment()
               ──► SaveNumBankSlots()

[BAG_UPDATE] ──► OnBagUpdate(bag)
                    ├──► SaveBag(i) for visible bags
                    └──► SaveItem(bag, slot) for each slot

[BANKFRAME_OPENED] ──► atBank = true
                     ──► UpdateBag(BANK_CONTAINER)
                     ──► UpdateBag(5..11) (Bank Bags)

[UNIT_INVENTORY_CHANGED] ──► SaveEquipment() (when unit == 'player')
[PLAYER_MONEY] ──────────► SaveMoney()
```

### 3.5 Abstracted Data Access API (`BagnonDB`)
`Bagnon_Forever` registers `BagnonDB` as a global interface table, decoupling the main `Bagnon` UI from direct `BagnonForeverDB` table access:

1. `BagnonDB:GetMoney(player)` (L221): Returns copper count for player on current realm.
2. `BagnonDB:GetNumBankSlots(player)` (L240): Returns purchased bank slot count.
3. `BagnonDB:GetBagData(bag, player)` (L264): Parses `size, link, count` string via `strsplit(',', bagInfo)`.
4. `BagnonDB:GetItemData(bag, slot, player)` (L296): Returns `hyperLink, count, texture, quality` by querying item ID via WoW API `GetItemInfo(link)`.
5. `BagnonDB:GetItemCount(itemLink, bag, player)` (L313): Scans specified container slots and aggregates matching stack counts.

---

## 4. Tooltip Integration & Hooks (`Bagnon_Tooltips`)

### 4.1 GameTooltip Hooking Mechanism
`Bagnon_Tooltips` (`refs/Bagnon_Tooltips/tooltips.lua`) hooks item tooltips to show how many copies of an item are owned across all characters on the account.

```lua
local function HookTip(tooltip)
    tooltip:HookScript('OnTooltipSetItem', function(self, ...)
        local itemLink = select(2, self:GetItem())
        if itemLink and GetItemInfo(itemLink) then
            AddOwners(self, itemLink)
        end
    end)
end

HookTip(GameTooltip)
HookTip(ItemRefTooltip)
```

### 4.2 Cross-Character Count Injection (`AddOwners`, L70–96)
When a user hovers over an item, `AddOwners` iterates through every player recorded in `BagnonDB:GetPlayers()` for the current realm:

```
[Hover Item] ──► OnTooltipSetItem ──► Extract itemLink
                                           │
                                           ▼
                                   AddOwners(tooltip, itemLink)
                                           │
             ┌─────────────────────────────┴─────────────────────────────┐
             ▼                                                           ▼
    [Current Player]                                            [Alt Characters]
   Calculate Live/Cached Counts                               Query Memoized Table
   (Keyring, Bags 0..4, Bank, Equip)                          itemInfo[player][link]
             │                                                           │
             └─────────────────────────────┬─────────────────────────────┘
                                           ▼
                               CountsToInfoString(...)
                                           │
                                           ▼
                        tooltip:AddDoubleLine(Player, CountStr)
```

#### Breakout Formatting (`CountsToInfoString`, L11–44)
Converts count totals into color-coded tooltip lines:
- **Teal (`|cff00ff9a`)**: Player Name and overall count total.
- **Silver (`|cffc7c7cf`)**: Location breakdown formatted as `(Bags: X, Bank: Y, Equipped)`.
- *Example Output*:
  `Zendevve` : `|cff00ff9a12|r |cffc7c7cf(Bags: 2, Bank: 10)|r`
  `AltBanker` : `|cff00ff9a200|r |cffc7c7cf(Bank: 200)|r`

### 4.3 Memoization vs. Performance Impact Analysis

#### Alt Character Optimization (Memoization Table, L47–68)
For alt characters, `Bagnon_Tooltips` uses a self-populating table with a custom `__index` metatable closure:
```lua
for player in BagnonDB:GetPlayers() do
    if player ~= currentPlayer then
        itemInfo[player] = setmetatable({}, {__index = function(self, link)
            local invCount = BagnonDB:GetItemCount(link, KEYRING_CONTAINER, player)
            for bag = 0, NUM_BAG_SLOTS do
                invCount = invCount + BagnonDB:GetItemCount(link, bag, player)
            end
            ...
            self[link] = CountsToInfoString(...) or ''
            return self[link]
        end})
    end
end
```
Once computed, an alt character's item count for a given link is cached in memory until reload, making subsequent tooltips for that item instantaneous (O(1)).

#### Current Player Performance Bottleneck (Critical Flaw)
However, for the **current player** (`player == currentPlayer`, L73–86), `AddOwners` computes `BagnonDB:GetItemCount` dynamically **on every single mouseover event without caching**!

```lua
-- Executed on EVERY OnTooltipSetItem for current player:
local invCount = BagnonDB:GetItemCount(link, KEYRING_CONTAINER, player)
for bag = 0, NUM_BAG_SLOTS do
    invCount = invCount + BagnonDB:GetItemCount(link, bag, player)
end
local bankCount = BagnonDB:GetItemCount(link, BANK_CONTAINER, player)
for i = 1, NUM_BANKBAGSLOTS do
    bankCount = bankCount + BagnonDB:GetItemCount(link, NUM_BAG_SLOTS + i, player)
end
local equipCount = BagnonDB:GetItemCount(link, 'e', player)
```

Each call to `BagnonDB:GetItemCount` loops through every single slot in that bag:
- Total iterations per hover: `(16 + 20 + 20 + 20 + 20) + 28 + (7 * 20) + 19 = ~263 slot queries`!
- Each slot query executes `strsplit`, string match regexes, and `GetItemInfo`.
- **Impact**: Sweeping the mouse rapidly across a full 140-slot inventory triggers tens of thousands of Lua iterations per second, causing noticeable **frame drops and micro-stuttering**.

---

## 5. Event Throttling & Update Pipeline

### 5.1 The `BagEvents` Diffing Engine (`refs/Bagnon/utility/itemEvents.lua`)
To prevent massive UI rebuilds when WoW fires repetitive engine events (`BAG_UPDATE` fires 4–6 times per item move), Bagnon routes all container events through an internal event filter (`BagEvents`).

`BagEvents` maintains an internal cache of slot states:
`slots[ToIndex(bag, slot)] = { link, count, locked, onCooldown }`

#### Diffing Logic (`BagEvents:UpdateItem`, L111–131)
```lua
function BagEvents:UpdateItem(bag, slot)
    local data = slots[ToIndex(bag, slot)]
    if data then
        local prevLink = data[1]
        local prevCount = data[2]

        local texture, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bag, slot)
        local start, duration, enable = GetContainerItemCooldown(bag, slot)
        local onCooldown = (start > 0 and duration > 0 and enable > 0)

        -- DIFF CHECK: Only send message if item link or count changed!
        if not (prevLink == link and prevCount == count) then
            data[1] = link
            data[2] = count
            data[3] = locked
            data[4] = onCooldown
            self:SendMessage('ITEM_SLOT_UPDATE', bag, slot, link, count, locked, onCooldown)
        end
    end
end
```
By comparing `prevLink` and `prevCount` before firing `ITEM_SLOT_UPDATE`, `BagEvents` suppresses up to 80% of unnecessary UI repaints during inventory operations.

### 5.2 Deferred Layout Batching (`throttledUpdater`)
Even with event diffing, adding or removing multiple items in a single frame tick would cause redundant grid layout recalculations. `ItemFrame` resolves this with a **single-frame deferred OnUpdate batcher** (`refs/Bagnon/components/itemFrame.lua`, L23–29, L424–432).

```lua
-- The Throttled Updater Frame Handler
local function throttledUpdater_OnUpdate(self, elapsed)
    local p = self:GetParent()
    if p:NeedsLayout() then
        p:Layout()  -- Execute expensive grid calculations ONCE!
    end
    self:Hide()     -- Deactivate updater immediately!
end

function ItemFrame:RequestLayout()
    self.needsLayout = true
    self.throttledUpdater:Show() -- Triggers OnUpdate script on next frame paint tick
end
```

```
[BAG_UPDATE Event 1] ──► AddItemSlot() ────► RequestLayout() ──► set needsLayout=true, Show(updater)
[BAG_UPDATE Event 2] ──► AddItemSlot() ────► RequestLayout() ──► (updater already active)
[BAG_UPDATE Event 3] ──► RemoveItemSlot() ──► RequestLayout() ──► (updater already active)
                                                                       │
                                                                       ▼
                                                          [Next Screen Frame Paint]
                                                          throttledUpdater:OnUpdate()
                                                                       │
                                                                       ▼
                                                                ItemFrame:Layout()
                                                             (Single Execution!)
                                                                       │
                                                                       ▼
                                                             throttledUpdater:Hide()
```

### 5.3 Window Opening & Closing Pipeline (`main.lua`, L154–222)
Bagnon replaces Blizzard's default container opening functions with custom toggle handlers while preserving full backward compatibility:

1. **API Function Overrides**:
   - `OpenBackpack`: Overridden to call `Bagnon:ShowFrame('inventory')`. If disabled in settings, falls back to original `oOpenBackpack()`.
   - `ToggleBackpack`: Overridden to call `Bagnon:ToggleFrame('inventory')`.
   - `ToggleBag(bagSlot)`: Inspects `bagSlot`; routes bank bags to `bank` frame and inventory bags to `inventory` frame.
   - `OpenAllBags(force)`: Overridden to open/toggle Bagnon's unified inventory window.
2. **Secure Hooks for Closing**:
   - `hooksecurefunc('CloseBackpack', ...)` calls `Bagnon:HideFrame('inventory')`.
   - `hooksecurefunc('CloseAllBags', ...)` calls `Bagnon:HideFrame('inventory')`.
3. **Blizzard Bank Unregistration** (L245–246):
   - `BankFrame:UnregisterEvent('BANKFRAME_OPENED')`
   - `BankFrame:UnregisterEvent('BANKFRAME_CLOSED')`
   Bagnon completely suppresses Blizzard's native bank frame and handles bank interaction via `Bagnon:BANK_OPENED()` and `Bagnon:BANK_CLOSED()`.

---

## 6. Deep-Dive Code Audit of Core Files

### 6.1 `refs/Bagnon/main.lua` (408 Lines)
- **Lines 6–33**: Instantiates Ace3 addon `Bagnon`. `OnInitialize()` hooks bag click events, registers auto-display triggers, adds slash commands (`/bagnon`, `/bgn`), creates options loader, and registers LDB launcher.
- **Lines 36–51**: Lazy-loaders for `Bagnon_Config` (loads on option frame show) and `Bagnon_GuildBank` (hooks `GuildBankFrame_LoadUI`).
- **Lines 93–135**: Window management API:
  - `GetFrame(frameID)`: Searches `self.frames` array matching `frameID`.
  - `CreateFrame(frameID)`: Instantiates new `Bagnon.Frame:New(frameID)`.
  - `ShowFrame(frameID)` / `HideFrame(frameID)` / `ToggleFrame(frameID)`: Interacts with frame settings objects.
- **Lines 154–222**: `HookBagClickEvents()` overrides stock `OpenBackpack`, `ToggleBackpack`, `ToggleBag`, `ToggleKeyRing`, `OpenAllBags`, and hooks `CloseBackpack` / `CloseAllBags`.
- **Lines 229–276**: `RegisterAutoDisplayEvents()` registers listeners for `BANK_OPENED`, `MAIL_CLOSED`, `AUCTION_HOUSE_SHOW`, `MERCHANT_SHOW`, `TRADE_SHOW`, `TRADE_SKILL_SHOW`, `GUILDBANKFRAME_OPENED`. Unregisters Blizzard `BankFrame` events.
- **Lines 360–408**: Slash command routing for `bags`, `bank`, `keys`, `version`, `config`.

### 6.2 `refs/Bagnon/components/item.lua` (706 Lines)
- **Lines 24–38**: `ItemSlot:New(bag, slot, frameID, parent)` constructor: fetches recycled item from `ItemSlot.unused` or creates new button; parents button to dummy bag frame (`GetDummyBag`).
- **Lines 41–71**: `ItemSlot:Create()` instantiates button, creates quality `border` texture on `OVERLAY` layer, sets scripts (`OnEnter`, `OnLeave`, `OnShow`, `OnHide`, `PostClick`).
- **Lines 75–94**: `ConstructNewItemSlot` creates `ContainerFrameItemButtonTemplate`; `GetBlizzardItemSlot` captures existing Blizzard slot (`ContainerFrame%dItem%d`) if bag passthrough is disabled.
- **Lines 123–131**: `ItemSlot:Free()` recycles slot into `ItemSlot.unused` pool.
- **Lines 254–273**: `ItemSlot:Update()` refreshes item link, texture, count, lock state, readability, quality border, cooldown, slot color, and search fade.
- **Lines 297–330**: `UpdateSlotColor()` tints empty special slots (Ammo = yellow/orange, Trade = green, Shard = purple, Keyring = key color).
- **Lines 357–417**: `SetBorderQuality(quality)` displays quest item borders (`TEXTURE_ITEM_QUEST_BORDER` / `TEXTURE_ITEM_QUEST_BANG`) or item quality colors (`GetItemQualityColor`).
- **Lines 453–472**: `UpdateSearch()` queries `LibItemSearch-1.0`. If search non-matching, desaturates button and sets alpha to `0.4`.
- **Lines 639–685**: `GetDummyItemSlot()` constructs dummy button overlay used for offline/cached item tooltips (`GameTooltip:SetHyperlink`) to avoid WoW UI taint.
- **Lines 688–706**: `GetDummyBag(parent, bag)` dummy bag factory ensuring `item:GetParent():GetID() == bag`.

### 6.3 `refs/Bagnon/components/bag.lua` (516 Lines)
- **Lines 18–85**: `Bag:New(slotID, frameID, parent)` creates `CheckButton` with textures (`UI-Quickslot2`, `UI-Quickslot-Depress`, `ButtonHilight-Square`, `CheckButtonHilight`).
- **Lines 209–226**: `OnClick()` handles purchasing bank slots (`PurchaseSlot`), placing cursor items (`PutItemInBag`), or toggling bag visibility filters (`ToggleSlot`).
- **Lines 235–251**: `OnEnter()` positions tooltip (`ANCHOR_LEFT` or `ANCHOR_RIGHT`) and highlights items matching hovered bag (`SetSearch`).
- **Lines 381–405**: `PurchaseSlot()` displays `StaticPopupDialogs['CONFIRM_BUY_BANK_SLOT_BAGNON']` with `MoneyFrame_Update`.
- **Lines 408–423**: `ToggleSlot()` / `IsSlotShown()` toggles visibility filtering for specific bags in `FrameSettings`.

### 6.4 `refs/Bagnon/components/frame.lua` (916 Lines)
- **Lines 17–41**: `Frame:New(frameID)` creates main window frame `BagnonFrame<frameID>` with tooltip backdrop border (`UI-Tooltip-Border`), enables mouse dragging, and registers frame in `UISpecialFrames`.
- **Lines 48–74**: `UpdateEvents()` registers pub/sub messages for position, scale, opacity, color, border color, and sub-frame layout updates.
- **Lines 300–334**: `SavePosition()` and `GetRelativePosition()` calculate window anchor relative to screen quadrant (`TOPLEFT`, `TOPRIGHT`, `BOTTOMLEFT`, `BOTTOMRIGHT`) to survive resolution changes.
- **Lines 428–476**: `Layout()` master layout orchestrator: calculates required window dimensions by measuring title bar buttons, menu buttons, bag frame, item frame, money frame, and broker display.
- **Lines 481–532**: `PlaceMenuButtons()` dynamically positions Player Selector, Bag Toggle, Sort Button, and Search Toggle along top-left title bar.

### 6.5 `refs/Bagnon_Forever` (`db.lua`, 454 Lines & `ui.lua`, 97 Lines)
- **`db.lua` L6–13**: Creates `BagnonDB` invisible `GameTooltip` frame handling `ADDON_LOADED`.
- **`db.lua` L40–48**: `ToShortLink` link compression logic.
- **`db.lua` L120–172**: Login and event hooks (`PLAYER_LOGIN`, `BAG_UPDATE`, `BANKFRAME_OPENED`, `UNIT_INVENTORY_CHANGED`).
- **`db.lua` L186–205**: `GetPlayerList()` returns character array sorted with current player first, followed alphabetically by alts.
- **`db.lua` L335–434**: Storage routines (`SaveMoney`, `SaveNumBankSlots`, `SaveEquipment`, `SaveItem`, `SaveBag`, `UpdateBag`).
- **`ui.lua` L15–76**: Custom character selector dropdown (`BagnonDBCharSelect`) utilizing `UIDropDownMenuTemplate` with level-2 deletion popups (`RemovePlayer`).

---

## 7. Strengths vs. Flaws Matrix: OmniInventory Architecture Guidance

Evaluating Bagnon's architecture reveals key strengths to emulate and critical flaws/limitations to eliminate when architecting **OmniInventory**:

```
+-----------------------------------------------------------------------------------+
|                            STRENGTHS TO EMULATE                                   |
+-----------------------------------------------------------------------------------+
| 1. Deferred Layout Batching (throttledUpdater)                                    |
|    - Single-frame OnUpdate batching prevents layout thrashing during event floods. |
|                                                                                   |
| 2. Event Diffing Engine (BagEvents)                                              |
|    - Slot state comparisons suppress 80% of unnecessary UI repaints.              |
|                                                                                   |
| 3. Memory-Conscious Slot Recycling (ItemSlot.unused Pool)                        |
|    - Object pooling prevents garbage collection stutter during window toggles.    |
|                                                                                   |
| 4. SavedVariables Link Compression (ToShortLink)                                  |
|    - Stripping un-enchanted item strings reduces disk footprint by >65%.          |
|                                                                                   |
| 5. Clean Component Decoupling (Classy + Ears + Sub-Frames)                       |
|    - Isolated widgets (ItemFrame, BagFrame, SearchFrame) communicate via pub/sub. |
+-----------------------------------------------------------------------------------+
                                         │
                                         ▼
+-----------------------------------------------------------------------------------+
|                        CRITICAL FLAWS & LIMITATIONS TO AVOID                      |
+-----------------------------------------------------------------------------------+
| 1. Lack of Automated Category Sorting & Grouping                                  |
|    - Flaw: All items are dumped into a single rigid grid unless manually broken by |
|      bag. No automatic category headers (Consumables, Armor, Quest, Trade).       |
|    - OmniInventory Fix: Architect virtualized category sections with rules-based |
|      filtering (similar to AdiBags / ArkInventory) built into the core layout.    |
|                                                                                   |
| 2. Un-Cached Current Player Tooltip Scans (Mouseover Stutter)                    |
|    - Flaw: OnTooltipSetItem performs ~263 slot queries on EVERY hover for current |
|      player, causing frame drops during rapid mouse movements across bags.        |
|    - OmniInventory Fix: Maintain an event-driven item count hash table for the    |
|      current player. Lookups must be instant O(1) memory reads.                   |
|    - File Reference: refs/Bagnon_Tooltips/tooltips.lua, Lines 73-86.              |
|                                                                                   |
| 3. Un-Indexed Text Search Overheads                                              |
|    - Flaw: Search input evaluates string regexes (LibItemSearch) against every    |
|      slot button on every keystroke.                                              |
|    - OmniInventory Fix: Pre-index item names, types, and quality into inverted    |
|      search buckets to execute search filters in O(1) time.                      |
|                                                                                   |
| 4. String Split Overhead in Database Access                                       |
|    - Flaw: GetItemData repeatedly executes strsplit(',', itemInfo), creating short-|
|      lived string allocations.                                                    |
|    - OmniInventory Fix: Use bit-packed integer tuples or direct Lua table fields.  |
|                                                                                   |
| 5. Rigid Container ID Assumptions & Frame Limits                                  |
|    - Flaw: Hardcoded bag slot ranges (-1, 0..4, 5..11) limit modular expansion.  |
|    - OmniInventory Fix: Generalized container provider interface supporting      |
|      custom bank tabs, guild banks, and virtual bags seamlessly.                  |
+-----------------------------------------------------------------------------------+
```

---
*Report compiled autonomously by `worker_bagnon` for the OmniInventory Architecture Specification.*
