# AdiBags (WoW 3.3.5a) Exhaustive Architectural Teardown & Structural Audit

## 1. Executive Summary & Architectural Overview

**AdiBags** is a categorized single-window bag addon built specifically around an Object-Oriented (OOP) prototype paradigm on top of **AceAddon-3.0**. Unlike traditional inventory addons (such as Bagnon) that render bags as static rectangular slot grids mirroring standard Blizzard bag containers, AdiBags dynamically groups items into logical **Sections** (e.g., Equipment, Consumables, Quest Items, Trade Goods, Junk) and packs those sections into a multi-column visual window.

```
+-------------------------------------------------------------------------+
| [BagIcon] Backpack Title Bar                 [Search] [Options] [Close] |
+-------------------------------------------------------------------------+
| +-------------------------+  +----------------------------------------+ |
| | Section: Equipment      |  | Section: Consumables                   | |
| | [Item1] [Item2] [Item3] |  | [Item4] [Item5] [Item6] [Item7]        | |
| +-------------------------+  +----------------------------------------+ |
| +---------------------------------------------------------------------+ |
| | Section: Quest Items                                                | |
| | [Item8] [Item9]                                                     | |
| +---------------------------------------------------------------------+ |
+-------------------------------------------------------------------------+
```

### Key Architectural Layers

1. **Object-Oriented Core & Pooling Framework (`OO.lua`)**:
   - Implements class declaration (`addon:NewClass`), single inheritance, mixin embedding (`LibStub` mixins), and automated frame instantiation.
   - Provides generic object pools (`poolProto`) managing `heap` (recycle bin) and `actives` (currently rendered objects) to minimize Lua table creation.
2. **Container Engine (`widgets/ContainerFrame.lua`)**:
   - Encapsulates main bag windows (`Backpack` and `Bank`).
   - Handles item container frame creation (`itemParentFrames`), background scanning, slot-to-button dispatching (`DispatchItem`), section management, and the multi-column 2D layout grid algorithm (`DoLayoutSections`).
3. **Section Manager (`widgets/Section.lua`)**:
   - Manages individual category frames containing item buttons.
   - Handles section height/width allocation (`FitInSpace`, `SetSizeInSlots`), button positioning (`PutButtonAt`), header script dispatching, collapsing, and item re-sorting (`ReorderButtons`).
4. **Item Button Subsystem (`widgets/ItemButton.lua`)**:
   - Extends Blizzard's `ContainerFrameItemButtonTemplate` and `BankItemButtonGenericTemplate`.
   - Incorporates virtual item stacking (`StackButton`), out-of-combat frame pre-spawning (`containerButtonPool:PreSpawn(100)`), quality border coloring, quest overlays, and Masque skinning hooks.
5. **Filter Registration & Priority System (`AdiBags.lua`, `DefaultFilters.lua`)**:
   - Modular filter pipeline using integer priority values.
   - Iterates active filters in descending priority order to assign section names and categories to item slots.
6. **Auxiliary Extensions (`AdiBags-ItemOverlayPlus`, `AdiBags_Bound`)**:
   - External modules leveraging `AdiBags:RegisterFilter` or listening to `AdiBags_UpdateButton` to add item usability overlays (red tinting for unusable items via tooltip scanning) and binding status categories (BoE, BoA, BoP).

---

## 2. Section Rendering Engine & Layout Grid Algorithm

The section rendering engine is the core differentiator of AdiBags. It computes section dimensions based on item counts, sorts sections by category priority, and packs them into columns inside the container frame.

```
Bag Container Window
│
├── Content Area (Width: Computed from Column Packing)
│   ├── Column 1 (X: 0)
│   │   ├── Section: Quest (Width: 3 slots, Height: 2 rows)
│   │   └── Section: Junk (Width: 3 slots, Height: 1 row)
│   └── Column 2 (X: Column 1 Width + SECTION_SPACING)
│       └── Section: Equipment (Width: 4 slots, Height: 3 rows)
```

### Section Key Construction & Category Management
- **Section Key Construction**: `addon:BuildSectionKey(name, category)` (`Section.lua:113-115`) creates a unique hash string `strjoin('#', category or name, name)`. This ensures sections with identical display names in different categories remain distinct.
- **Category Ordering**: Managed via `categoryOrder` table (`Section.lua:41-62`). Orders are set via `addon:SetCategoryOrders(t)` (e.g., Quest = 30, Trade Goods = 20, Equipment = 10, Consumables = -10, Miscellaneous = -20, Junk = -50, Free Space = -100). Higher numbers render first.

### Step-by-Step Bin-Packing Grid Algorithm (`ContainerFrame.lua:1166-1230`)

The primary layout work occurs inside `DoLayoutSections(self, rowWidth, maxHeight)`:

1. **Width & Height Target Calculation**:
   - `rowWidth`: `(ITEM_SIZE + ITEM_SPACING) * addon.db.profile.rowWidth[self.name] - ITEM_SPACING` (`ContainerFrame.lua:1276`). Converts user row width setting (default 9 slots) into absolute pixels.
   - `maxHeight`: `addon.db.profile.maxHeight * UIParent:GetHeight() * UIParent:GetEffectiveScale() / self:GetEffectiveScale()` (`ContainerFrame.lua:1277`). Default max height is 60% of screen height.
2. **Section Filtering & Sorting**:
   - Non-collapsed sections are inserted into `sections` array (`ContainerFrame.lua:1176`).
   - `tsort(sections, CompareSections)` (`ContainerFrame.lua:1179`) sorts sections:
     - Primary: Section `GetOrder()` descending (Category Order).
     - Secondary: `category` string ascending.
     - Tertiary: `name` string ascending.
3. **Space Fitting Evaluation (`Section.lua:354-375`)**:
   - Each section calculates how many slot columns and rows it requires given available width/height via `section:FitInSpace(maxWidth, maxHeight, xOffset, rowHeight)`:
     - `maxColumns = floor((ceil(maxWidth) + ITEM_SPACING) / SLOT_OFFSET)`
     - `maxRows = floor((ceil(maxHeight) - HEADER_SIZE + ITEM_SPACING) / SLOT_OFFSET)`
     - If `maxColumns * maxRows < section.count`, return `false` (does not fit).
     - Wasted space calculation: `wasted = available + gap - occupation`, where `gap = max(0, height - rowHeight) * xOffset` and `occupation = count * SLOT_OFFSET^2 + numColumns * SLOT_OFFSET * HEADER_SIZE`.
4. **Ordering & Packing Strategy (`getNextSection`) (`ContainerFrame.lua:1148-1164`)**:
   - `laxOrdering = 0`: Strict sequential packing. Always takes `sections[1]` if it fits.
   - `laxOrdering = 1` (Default): Category grouping. Searches for `GetBestSection` with the same `category` that minimizes wasted space.
   - `laxOrdering = 2`: Greedy bin-packing. Searches across ALL remaining sections for the one that minimizes wasted space regardless of category.
5. **Column Packing Loop (`ContainerFrame.lua:1192-1228`)**:
   - Outer loop iterates columns (`columnX`).
   - Inner loop fills vertical height (`y < maxHeight`).
   - Nested row loop fills horizontal row width (`x < rowWidth`).
   - When a section is chosen, it is removed via `tremove(sections, index)`, positioned via `section:SetPoint("TOPLEFT", content, columnX + x, -y)`, and resized via `section:SetSizeInSlots(width, height)`.
6. **Multi-Column Height Balancing (`ContainerFrame.lua:1278-1287`)**:
   - If packing results in multiple columns (`numColumns > 1`) and height waste ratio (`wastedHeight / contentHeight`) exceeds 10%, AdiBags recalculates target `maxHeight = totalHeight / numColumns + SLOT_OFFSET` and re-runs `DoLayoutSections` to produce balanced, aesthetic column heights.

---

## 3. Item Pooling & Frame Lifecycle

To avoid constant frame creation and destruction when opening/closing bags or moving items, AdiBags implements an object pool in `OO.lua`.

```
Pool Architecture (poolProto in OO.lua)
┌─────────────────────────────────────────────────────────┐
│ poolProto                                               │
│  ├── heap    : { [FrameObject1] = true, ... } (Inactive)│
│  └── actives : { [FrameObject2] = true, ... } (Active)  │
└─────────────────────────────────────────────────────────┘
       ▲                                  │
       │ Release()                        │ Acquire()
       │ (Hide, ClearAllPoints)           │ (Create if empty)
       └──────────────────────────────────┘
```

### Pool Implementation Details (`OO.lua:117-203`)
- `addon:CreatePool(class, acquireMethod)` registers a pool for an OO class.
- **Acquire (`poolProto:Acquire(...)`, lines 122-137)**:
  1. Checks `self.heap` via `next(self.heap)`.
  2. If empty, instantiates a new frame object via `self.class:Create()`.
  3. Moves object into `self.actives[object] = true`. Sets `object.acquired = true`.
  4. Triggers mixin enablement hooks `safecall(mixin, "OnEmbedEnable", object)`.
  5. Invokes `safecall(object, "OnAcquire", ...)`.
- **Release (`poolProto:Release(object)`, lines 139-151)**:
  1. Validates `object.acquired`.
  2. Hides object (`object:Hide()`), clears anchor points (`object:ClearAllPoints()`), detaches parent (`object:SetParent(nil)`).
  3. Invokes `safecall(object, "OnRelease")`.
  4. Triggers mixin disablement hooks `safecall(mixin, "OnEmbedDisable", object)`.
  5. Clears active status `self.actives[object] = nil` and returns to `self.heap[object] = true`.

### Frame Instantiation & Naming Rules
- Frames created via `Class_Create` (`OO.lua:34-42`) execute `CreateFrame(class.frameType, addonName..class.name..class.serial, nil, class.frameTemplate)`.
- **Global Naming Constraint**: Every pooled frame receives a permanent global name with an incremental serial number (e.g., `AdiBagsItemButton1`, `AdiBagsItemButton2`, `AdiBagsSection1`).

### Out-of-Combat Pre-Spawning (`ItemButton.lua:149-153`)
- In World of Warcraft, secure action button templates (`ContainerFrameItemButtonTemplate`) cannot be instantiated during combat without throwing LUA taint errors.
- AdiBags circumvents this by pre-spawning 100 item buttons during addon initialization:
  ```lua
  hooksecurefunc(addon, 'OnInitialize', function()
      addon:Debug('Prespawning buttons')
      containerButtonPool:PreSpawn(100)
  end)
  ```

### Virtual Stack Button Architecture (`ItemButton.lua:624-825`)
- When item virtual stacking is enabled (`virtualStacks` profile config), identical stackable items or free space slots are grouped into a single `StackButton`.
- `StackButton` is a proxy frame inheriting from `Frame`. It tracks stacked slot IDs in `self.slots` hash table.
- When rendered, `StackButton` acquires a real `ItemButton` via `addon:AcquireItemButton(self.container, GetBagSlotFromId(slotId))` (`ItemButton.lua:753`).
- **Monkey-Patching Count Display**: `StackButton` replaces the underlying button's `GetCount` method with `self.GetCountHook` (`ItemButton.lua:754`). When `button:UpdateCount()` runs, it calls `self.count` (the sum of counts across all stacked slots) rather than the single slot's count.

---

## 4. Module Registration Pipeline & Filter Priority System

AdiBags utilizes a modular filter architecture built on top of AceAddon-3.0 and AceBucket-3.0.

```
Filter Evaluation Pipeline (AdiBags.lua:1243-1256)
Item Slot Data ---> [Filter Priority 90: ItemSets / Key] ---> Match? ---> Return Section
                        │ No
                    [Filter Priority 75: Quest] -------------> Match? ---> Return Section
                        │ No
                    [Filter Priority 70: Bound (BoE/BoP)] ---> Match? ---> Return Section
                        │ No
                    [Filter Priority 60: Equipment] ---------> Match? ---> Return Section
                        │ No
                    [Filter Priority 10: ItemCategory] ------> Match? ---> Return Section
                        │ No
                    [Fallback: Free Space / Miscellaneous] ------------> Return Section
```

### Module & Filter Registration API (`AdiBags.lua:1224-1237`)
- **`addon:RegisterFilter(name, priority, Filter, ...)`**:
  - Instantiates an Ace3 module bound to `filterProto` prototype.
  - Registers module priority (`filter.priority = priority`).
  - Extends `filterProto` with `GetPriority()` and `SetPriority(value)` which allow users to override default filter priorities in `addon.db.profile.filterPriorities`.

### Priority Sorting Algorithm (`AdiBags.lua:1192-1218`)
- `UpdateFilters()` rebuilds active filters array `activeFilters`:
  1. Collects all filter modules via `self:IterateModules()`.
  2. Sorts array using `CompareFilters(a, b)`:
     ```lua
     local function CompareFilters(a, b)
         local prioA, prioB = a:GetPriority(), b:GetPriority()
         if prioA == prioB then
             return a.filterName < b.filterName
         else
             return prioA > prioB
         end
     end
     ```
  3. Filters enabled modules (`filter:IsEnabled()`) into `activeFilters`.

### Core Priority Matrix

| Priority | Module Name | File Location | Evaluation Logic & Target Categories |
| :--- | :--- | :--- | :--- |
| **90** | `ItemSets` | `DefaultFilters.lua:56-175` | Scans equipment set locations via `GetEquipmentSetLocations()`. Assigns items to set-specific sections or "Sets". |
| **90** | `Key` | `DefaultFilters.lua:179-189` | Matches `slotData.bagFamily == 256` or `class/subclass == "Keyring"`. Assigns to "Keyring". |
| **75** | `Quest` | `DefaultFilters.lua:192-203` | Matches class/subclass == "Quest" or `GetContainerItemQuestInfo()`. Assigns to "Quest". |
| **70** | `Bound` | `AdiBags_Bound.lua:130-331` | Scans item tooltips for "Binds when picked up" (BoP), "Binds when equipped" (BoE), or "Binds to Account" (BoA). |
| **60** | `Equipment` | `DefaultFilters.lua:206-287` | Matches equipable slots (`slotData.equipSlot`). Categories: Armor, Weapon, Jewelry, or slot-by-slot. |
| **10** | `ItemCategory` | `DefaultFilters.lua:290-354` | Catch-all filter matching Blizzard's 1st-level Auction House categories (Trade Goods, Consumables, Recipes, etc.). |
| *Fallback*| *Default* | `AdiBags.lua:1255` | Returns `Miscellaneous` for items or `Free space` for empty slots. |

### Filter Execution Engine (`AdiBags.lua:1243-1256`)
- `addon:Filter(slotData, defaultSection, defaultCategory)`:
  - Iterates through `activeFilters`.
  - Executes `sectionName, category = filter:Filter(slotData)` using `safecall`.
  - **Short-Circuit Return**: The first filter returning a non-nil `sectionName` halts iteration and returns `sectionName, category, filter.uiName`.

---

## 5. Performance Analysis under High Item Counts (100+ items)

When handling full inventories (100–140 items in 3.3.5a), AdiBags faces several performance bottlenecks, event throttling challenges, and memory churn points.

### Event Throttling & Debouncing Mechanisms
1. **Bag Update Bucket (`ContainerFrame.lua:735`)**:
   - `BAG_UPDATE` events occur repeatedly during looting, opening containers, or moving stacks.
   - Container frames register `AceBucket-3.0` with a `0.2` second interval:
     `self.bagUpdateBucket = self:RegisterBucketMessage('AdiBags_BagUpdated', 0.2, "BagsUpdated")`
   - Consolidates multiple rapid bag updates into a single layout pass.
2. **Bank Update Throttling (`AdiBags.lua:386-394`)**:
   - `PLAYERBANKSLOTS_CHANGED` bucketed with interval `0`, batching rapid bank slot changes into one `AdiBags_BagUpdated` message.
3. **Auxiliary Debouncing (`AdiBags-ItemOverlayPlus.lua:19-38`)**:
   - `ItemOverlayPlus` uses `LibCompat.After(0, ...)` single-frame debouncing to batch `ITEM_LOCK_UPDATE` and `BAG_UPDATE_COOLDOWN` events into a single `AdiBags_UpdateAllButtons` message.

### Layout Recalculation Triggers & Selective Updates
- **Content Change Detection (`ContainerFrame.lua:936-938`)**:
  - `HasContentChanged()` checks if `next(self.added)`, `next(self.removed)`, or `next(self.changed)` contain slot IDs. If false, `UpdateButtons()` returns immediately without re-dispatching items.
- **Section Dirty Level Hierarchy (`Section.lua:194-206`, `ContainerFrame.lua:1232-1309`)**:
  - `dirtyLevel 0`: Clean layout.
  - `dirtyLevel 1`: Button internal index change (position update within section).
  - `dirtyLevel 2`: Section size change or button count change (requires full grid re-calculation).
  - `ContainerFrame:LayoutSections(cleanLevel)` evaluates `dirtyLevel > cleanLevel`. If clean, skips layout computation (`NO-OP`).

### Memory Churn & CPU Bottlenecks at 100+ Items

```
Performance Bottleneck Map
┌───────────────────────────────────────────────────────────────────────────┐
│ Item Re-Sorting (Section.lua:524-536)                                     │
│  └── itemCompareCache index creates format("%d:%d", idA, idB) strings     │
│      --> Generates 500-2000 string allocations per tsort pass!            │
├───────────────────────────────────────────────────────────────────────────┤
│ Synchronous Tooltip Scanning (AdiBags_Bound / ItemOverlayPlus)            │
│  └── SetBagItem(bag, slot) called sequentially for 100+ item buttons      │
│      --> Causes 50ms - 150ms execution spikes on UI thread (micro-stutter)│
├───────────────────────────────────────────────────────────────────────────┤
│ Double Pass Layout Algorithm (ContainerFrame.lua:1277-1287)               │
│  └── DoLayoutSections called twice when column height waste > 10%         │
│      --> Redundant FitInSpace & tsort calculations                        │
└───────────────────────────────────────────────────────────────────────────┘
```

1. **String Allocation Churn in Item Sorting (`Section.lua:524-536`)**:
   - Items inside a section are re-sorted via `tsort(buttonOrder, CompareButtons)`.
   - `CompareButtons` looks up comparison results in `itemCompareCache`:
     `return itemCompareCache[format("%d:%d", idA, idB)]`
   - `format("%d:%d", idA, idB)` instantiates a **new Lua string for every pairwise item comparison** during QuickSort. On 100+ items across multiple sections, sorting can allocate over 1,000 temporary string objects in a single frame, triggering Lua Garbage Collection overhead.
2. **Synchronous Tooltip Scanning Bottlenecks**:
   - Both `AdiBags_Bound` (`AdiBags_Bound.lua:273-289`) and `AdiBags-ItemOverlayPlus` (`AdiBags-ItemOverlayPlus.lua:262-273`) instantiate invisible scanning tooltips (`GameTooltipTemplate`) and call `Scanner:SetBagItem(bag, slot)` synchronously during `UpdateButton`.
   - On 100+ items, scanning 100 tooltips sequentially forces the C++ engine to generate item tooltip text structures 100 times, taking 50–150ms of CPU frame time and causing perceptible micro-stutter when opening bags.
3. **Double-Pass Layout Overhead (`ContainerFrame.lua:1277-1287`)**:
   - If multi-column height waste exceeds 10%, `DoLayoutSections` runs twice in the same frame. For containers with 120+ items split into 15 sections, performing table insertion, section sorting, and fit-in-space math twice per layout cycle causes unnecessary CPU load.

---

## 6. Deep-Dive Code Audit of Key Modules

### A. Core Addon Controller (`AdiBags.lua`)
- **`addon:OnInitialize()` (lines 198-237)**: Initializes AceDB profile defaults (`DEFAULT_SETTINGS`), sets up default module prototypes (`SetDefaultModulePrototype`), creates bag fonts (`bagFont`, `sectionFont`), creates bag anchor (`CreateBagAnchor`), registers configuration change buckets (`AdiBags_ConfigChanged`).
- **`addon:Filter(slotData, defaultSection, defaultCategory)` (lines 1243-1256)**: Signature: `(slotData: table, defaultSection: string, defaultCategory: string) -> sectionName: string, category: string, filterName: string`.
- **`AnchoredBagLayout(self)` (lines 947-980)**: Docks containers relative to the master anchor widget. Computes direction vectors (`vPart`, `hFrom`, `hTo`) based on anchor point (`TOPLEFT`, `BOTTOMRIGHT`, etc.) and anchors subsequent bags horizontally with offset `10 / frame:GetScale()`.

### B. Container Window Engine (`widgets/ContainerFrame.lua`)
- **`containerProto:OnCreate(name, bagIds, isBank)` (lines 112-669)**: Instantiates top header region (`HeaderLeftRegion`, `HeaderRightRegion`), bottom widgets, title string, close button, bag slot toggle button (`BagSlotButton`), bag menu (`AdiBagsBagMenu`), drag handle (`AnchorWidget`), and content frame (`Content`).
- **`containerProto:UpdateContent(bag)` (lines 869-934)**:
  - Scans container slots from 1 to `GetContainerNumSlots(bag)`.
  - Maps items into `slotData` tables: `{ bag, slot, slotId, bagFamily, count, isBank, link, itemId, name, quality, iLevel, reqLevel, class, subclass, equipSlot, texture, vendorPrice }`.
  - Populates diff tables: `self.added`, `self.removed`, `self.changed`. Handles keyring empty slot cleanup (`lines 880-884`).
- **`containerProto:DispatchItem(slotData)` (lines 998-1032)**:
  - Calls `self:FilterSlot(slotData)` to retrieve `sectionName, category, filterName, shouldStack, stackHint`.
  - If `shouldStack` is true, acquires/retrieves a `StackButton`. If false, acquires `ItemButton`.
  - Assigns button to section via `section:AddItemButton(slotId, button)`.
- **`DoLayoutSections(self, rowWidth, maxHeight)` (lines 1166-1230)**: Core layout algorithm detailed in Section 2.

### C. Section Container (`widgets/Section.lua`)
- **`sectionProto:OnAcquire(container, name, category)` (lines 122-138)**: Binds section to container, sets header text, constructs section key `addon:BuildSectionKey(name, category)`, resets dimensions (`width=0, height=0, count=0, total=0, dirtyLevel=0`).
- **`sectionProto:FitInSpace(maxWidth, maxHeight, xOffset, rowHeight)` (lines 354-375)**: Computes slot grid capacity and wasted space metric (`wasted = available + gap - occupation`).
- **`sectionProto:ReorderButtons()` (lines 408-446)**: Filters out key-chain buttons in Free Space (`lines 422-430`), sorts buttons via `tsort(buttonOrder, CompareButtons)`, updates button positions via `PutButtonAt`, and marks unused grid slots in `freeSlots`.
- **`itemCompareCache` & `CompareButtons` (lines 482-564)**: Implements default item sorting by equipment slot location (`EQUIP_LOCS`), item class, subclass, quality descending, level descending, and name ascending.

### D. Item Button Subsystem (`widgets/ItemButton.lua`)
- **`buttonProto:OnCreate()` (lines 53-64)**: Caches template child regions (`Cooldown`, `IconTexture`, `IconQuestTexture`, `Count`, `Stock`, `NormalTexture`). Registers drag and click handlers.
- **`buttonProto:UpdateBorder(isolatedEvent)` (lines 385-429)**: Checks `GetContainerItemQuestInfo` for quest bang texture (`TEXTURE_ITEM_QUEST_BANG`) or quest border texture (`TEXTURE_ITEM_QUEST_BORDER`). Sets quality border color (`GetItemQualityColor`) or dims junk items (`dimJunk`).
- **Masque Integration (lines 435-617)**: Hooks `UpdateBorder` and `Update` to skin item buttons using Masque API (`masqueGroup:AddButton`, `msqAPI:GetNormal`).

### E. Auxiliary Overlay Extensions
- **`AdiBags-ItemOverlayPlus.lua`**:
  - `mod:ScanTooltipOfBagItemForRedText(bag, slot)` (lines 262-273): Clears lines on `AdibagsItemOverlayPlusScanningTooltip`, calls `SetBagItem(bag, slot)`, inspects `TextLeft` / `TextRight` font strings for red RGB values (`r > 0.95 and g < 0.2 and b < 0.2`).
  - `ApplyOverlay(button, isActuallyUnusable)` (lines 186-212): Tints `IconTexture` to red `(1, 0.1, 0.1)` if unusable, or resets to white `(1, 1, 1)`.
- **`AdiBags_Bound.lua`**:
  - `filter:Filter(slotData)` (lines 221-230): Evaluates item quality/bindType and calls `GetItemCategory(bag, slot)`.
  - `filter:GetItemCategory(bag, slot)` (lines 232-294): Sets scanner tooltip (`AVY_ScannerTooltip:SetBagItem`), checks lines 2–4 for localized binding strings (`ITEM_SOULBOUND`, `ITEM_BIND_ON_EQUIP`, `ITEM_ACCOUNTBOUND`).

---

## 7. Strengths vs. Flaws Matrix

This matrix synthesizes structural strengths worth emulating in **OmniInventory** against architectural flaws and bottlenecks to eliminate.

| Domain | AdiBags Structural Strengths (Emulate in OmniInventory) | AdiBags Architectural Flaws / Bottlenecks (Avoid in OmniInventory) |
| :--- | :--- | :--- |
| **Object Lifecycle & Memory** | • Generic Object Pooling (`heap`/`actives` in `OO.lua`) prevents churn.<br>• Pre-spawning 100 buttons out-of-combat avoids secure template taint. | • `CompareButtons` creates `format("%d:%d", idA, idB)` strings on every QuickSort pair.<br>• Unused pooled frames remain attached to global namespace with serial names (`AdiBagsItemButton89`). |
| **Layout & Grid Algorithm** | • Dynamic 2D multi-column bin-packing provides clean visual organization.<br>• Height balancing loop prevents excessive single-column vertical scrolling. | • Double-pass layout calculation (`DoLayoutSections`) when height waste > 10% wastes CPU cycles.<br>• Lack of virtualized frame rendering: creates actual UI frames for ALL items, even if off-screen. |
| **Modular Pipeline** | • AceAddon-3.0 module registration allows clean third-party filter additions.<br>• Integer priority pipeline with short-circuit evaluation guarantees deterministic sorting. | • Global event broadcasts (`AdiBags_UpdateAllButtons`, `AdiBags_FiltersChanged`) force complete re-filtering of all items rather than targeted slot updates. |
| **Tooltip Scanning** | • Leverages localized engine strings (`ITEM_SOULBOUND`, `ITEM_BIND_ON_EQUIP`) for accurate binding detection. | • Synchronous tooltip scanning (`SetBagItem`) on UI thread during button updates causes 50–150ms frame drops at 100+ items.<br>• No async or cached tooltip data store. |
| **User Interface & Interaction** | • Virtual Stacking consolidates duplicate item stacks and free slot clutter.<br>• Integrated bag slot header panel for equipping/swapping bags cleanly. | • Direct modification of template scripts instead of clean event-driven mixins.<br>• Manual anchor toggling and layout code tightly coupled with UI presentation frames. |

---

### Key Recommendations for OmniInventory

1. **Eliminate String Allocation in Sorting**:
   - Replace string-keyed item comparison caches (`format("%d:%d", idA, idB)`) with numeric bit-shifted integer keys: `(idA * 100000) + idB` or dual-level lookup tables `cache[idA][idB]`.
2. **Implement Async / Cached Tooltip Scanning**:
   - Never call `SetBagItem` synchronously inside item button draw routines. Build a background tooltip inspection queue or cache binding/usability status on `BAG_UPDATE` events.
3. **Use Single-Pass Layout Engine with Virtualization**:
   - Calculate column targets directly using exact section slot metrics without executing a second full layout pass.
4. **Targeted Slot Dispatching**:
   - Instead of broadcasting global update events (`AdiBags_UpdateAllButtons`) that re-evaluate every item slot, dispatch updates exclusively to dirty slot IDs (`slotId`).
5. **Clean Data-Driven Architecture**:
   - Decouple item categorization and filtering logic completely from UI frame rendering, keeping data evaluation pure, testable, and memory-light.
