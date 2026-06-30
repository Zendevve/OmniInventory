# OmniInventory — Reference Addon Feature Gap Analysis

> Studied every file/line of: **AdiBags** (+ `AdiBags_Bound`, `AdiBags-ItemOverlayPlus`), **Bagnon** (+ `Bagnon_Config`, `Bagnon_Forever`, `Bagnon_GuildBank`, `Bagnon_Tooltips`, `Bagnon_VoidStorage`), **Bagshui**, **GudaBags**.
> Compared against our current `OmniInventory/` codebase (Core, Omni/*, UI/*).

---

## A. Features They Have That We Don't

### A1. Masque / Button Skinning Support
**Who:** AdiBags (full), Bagnon (partial)
**What:** AdiBags integrates `Masque` (formerly ButtonFacade) to let users skin item buttons with any Masque preset. It creates separate Masque groups for backpack vs. bank buttons, hooks `ReSkin`/`__Disable` to re-add buttons when the user changes skin, and hides its own default border when Masque is active.
**Our state:** We have a *disabled* Masque integration block in `Core.lua` (commented out). It was attempted but "not functional."
**Gap:** Full Masque support — group registration, `AddButton`/`RemoveButton` lifecycle, ReSkin hook, border suppression.

### A2. LibSharedMedia-3.0 (Customizable Backgrounds / Borders / Fonts)
**Who:** AdiBags
**What:** Uses `LibSharedMedia-3.0` to let users pick any registered background texture, border texture, font, and sound from any addon that registers media. The skin system stores `background`, `border`, `borderWidth`, `insets`, and per-container colors (Backpack vs. Bank).
**Our state:** Hardcoded `WHITE8X8` background and `UI-Tooltip-Border` edge. No user customization of textures.
**Gap:** LibSharedMedia integration for background/border/font selection.

### A3. Virtual Stacking (Display-Only Stacking Across Bags)
**Who:** AdiBags
**What:** `virtualStacks` setting group that visually merges identical items across bags into a single button (showing total count) without actually moving them. Sub-options: `freeSpace` (merge empty slots), `others` (merge non-stackable identical items), `stackable` (merge partial stacks), `incomplete` (only merge incomplete stacks), `notWhenTrading` (disable at vendor/mail/bank/etc.). The container frame's `FilterSlot()` returns a `stackHint` so the layout engine knows which buttons to virtual-stack together.
**Our state:** No virtual stacking. Each physical slot is its own button.
**Gap:** Virtual stack display with per-context toggles.

### A4. Filter Priority System with Per-Filter Options
**Who:** AdiBags, Bagshui
**What:** AdiBags has a `RegisterFilter(name, priority, ...)` system where each filter is an AceAddon module with its own `OnInitialize`, `OnEnable`, `Filter(slotData)` function, and `GetFilterOptions()` AceConfig table. Filters are evaluated in priority order; the first match wins. Each filter has its own SavedVariables namespace. Examples: `ItemSets` (priority 90, with `oneSectionPerSet` and `mergedSets` options), `Quest` (75), `Equipment` (60, with `dispatchRule` = one/category/slot and `armorTypes` toggle), `ItemCategory` (10, with `splitBySubclass`, `mergeGems`, `mergeGlyphs`), `Junk` (85, with `sources`, `include`/`exclude` lists).
**Our state:** Hardcoded priority pipeline in `Categorizer:GetCategory()` with fixed order. No per-filter options UI. Manual overrides are a flat `categoryOverrides[itemID]` table.
**Gap:** Pluggable filter modules with per-filter config, priority reordering, enable/disable toggles.

### A5. Equipment Set Tracking (One-Section-per-set, Merged Sets)
**Who:** AdiBags, Bagnon (search), Bagshui (Outfit rule), GudaBags
**What:** AdiBags' `ItemSets` filter uses `GetEquipmentSetLocations()` + `EquipmentManager_UnpackLocation()` to track exactly which *slot instances* (not just itemIDs) belong to equipment sets. Supports `oneSectionPerSet` (each set gets its own section) and per-character `mergedSets` (merge specific sets into one "Sets" section). Bagnon's LibItemSearch supports `s:<setName>` search. Bagshui has `Outfit()` rule function with ItemRack and Outfitter integration. GudaBags has `EquipmentSets` scanner.
**Our state:** `IsEquipmentSetItem()` in Categorizer iterates `GetEquipmentSetItemIDs(name)` by itemID only (slower, misses specific instances). No per-set section, no merge option, no ItemRack/Outfitter support.
**Gap:** Location-based set tracking, per-set sections, merge toggles, third-party outfit addon support.

### A6. Junk Filter with Include/Exclude Lists + Third-Party Support
**Who:** AdiBags
**What:** The `Junk` filter has: `sources` (toggle low-quality vs. junk-category), `include` list (always-junk), `exclude` list (never-junk, defaults to Hearthstone [6948]), and integrates with **Scrap** and **BrainDead** addons. Uses a metatable cache for `IsJunk` lookups. The `AdiBags_OverrideFilter` message lets users right-click items to add/remove from include/exclude.
**Our state:** `autoSellJunk` sells quality==0 items. No include/exclude lists, no third-party junk addon support, no per-item junk override.
**Gap:** Include/exclude lists, Scrap/BrainDead integration, right-click override.

### A7. Collapsible Sections with Persisted State
**Who:** AdiBags, Bagshui
**What:** AdiBags sections have `IsCollapsed()`/`SetCollapsed()` backed by `db.char.collapsedSections[key]`. Clicking a section header toggles collapse. Bagshui has group hide/show with persisted state.
**Our state:** We have `collapsedCategories` in `OmniInventoryDB.char` and `IsCategoryCollapsed()` in Frame.lua, but this appears to be for category-level collapse. The implementation is present but less granular than AdiBags' per-section-key collapse.
**Gap:** We have partial support; AdiBags' is more mature with per-section-key persistence and header click hooks.

### A8. Section Header Script Hooks (Click / Drag / Tooltip)
**Who:** AdiBags
**What:** `RegisterSectionHeaderScript` / `UnregisterSectionHeaderScript` via `CallbackHandler-1.0`. Modules can register `OnClick`, `OnEnter`, `OnLeave`, `OnReceiveDrag` handlers on section headers. The `FilterOverride` module uses this to let users right-click section headers to override the filter for those items. `SectionVisibilityDropdown` adds a dropdown to show/hide sections.
**Our state:** No section header interaction beyond visual display.
**Gap:** Extensible section header scripts, right-click filter override, section visibility dropdown.

### A9. Bin-Packing Layout Algorithm (FitInSpace with Wasted-Space Calculation)
**Who:** AdiBags
**What:** `Section:FitInSpace(maxWidth, maxHeight, xOffset, rowHeight)` calculates whether a section can fit in the available space, computing `numColumns`, `numRows`, `wasted` space, and `height`. The container frame's `LayoutSections()` uses a greedy algorithm to place sections in rows, minimizing wasted space. `laxOrdering` controls how strictly sections must be ordered.
**Our state:** Flow view uses a simpler lane-based layout. No wasted-space optimization or bin-packing.
**Gap:** Bin-packing layout with wasted-space minimization.

### A10. LibDataBroker (LDB) Data Source + Launcher
**Who:** AdiBags (DataSource module), Bagnon (launcher + broker display widget)
**What:** AdiBags' `DataSource` module registers an LDB data object showing bag space usage, clickable to toggle bags. Bagnon creates a `BagnonLauncher` LDB object (left-click=inventory, shift+left=bank, alt+left=keys, right-click=options) AND has a `BrokerDisplay` widget that can embed any LDB data object into the bag frame's header.
**Our state:** We have a `MinimapButton.lua` but no LDB integration.
**Gap:** LDB data source + launcher; embeddable broker display widget.

### A11. Offline Inventory Database (Cross-Character Bag/Bank/Equipment/Gold)
**Who:** Bagnon_Forever, GudaBags (SharedData), Bagshui (CharacterData)
**What:** Bagnon_Forever stores every character's bags, bank, keyring, equipped items, gold, and bank slot count in `BagnonForeverDB`. Any character can view any other character's inventory. Uses `ToShortLink()` to minimize storage (stores just itemID when no enchant/suffix). GudaBags stores mailbox contents too. Bagshui has `CharacterData` with profession crafts/reagents/equipped history.
**Our state:** `Data.lua` saves `realm[realmName][playerName]` with bags/bank/gold/class/lastSeen, but it's a simple snapshot. No equipment, no keyring, no mailbox, no offline viewing UI.
**Gap:** Full offline inventory with equipment, keyring, mailbox; cross-character viewing UI.

### A12. Configurable Auto-Display (Show Bags at Vendor/Bank/Mail/AH/Trade/Craft/GuildBank/PlayerFrame)
**Who:** Bagnon
**What:** `Settings:IsFrameShownAtEvent(frameID, event)` — per-frame, per-event auto-open/close configuration. Events: `bank`, `vendor`, `ah`, `trade`, `guildbank`, `craft`, `player`, `mail`. Each can be independently enabled per frame (inventory vs. bank vs. keys).
**Our state:** We auto-show at bank (`BANKFRAME_OPENED`) and guild bank, but no configurable auto-display for vendor/mail/AH/trade/craft/player frame.
**Gap:** Per-event, per-frame auto-display configuration.

### A13. Per-Frame Settings (Scale / Opacity / Color / Border Color / Layer / Components)
**Who:** Bagnon
**What:** `FrameSettings` + `SavedFrameSettings` store per-frame: position, scale, opacity, color (r,g,b,a), border color, frame strata/layer, hasBagFrame, hasMoneyFrame, hasDBOFrame, hasSearchToggle, hasSortButton, hasOptionsToggle, itemFrameSpacing, itemFrameColumns, bagBreak, reverseSlotOrder, dataBrokerObject. Each frame (inventory/bank/keys) has independent settings.
**Our state:** Global settings only (scale, opacity, columns, itemSize). One position for the main frame.
**Gap:** Per-frame independent settings for all visual/layout properties.

### A14. Physical Bag Sorting (Actually Moves Items in Containers)
**Who:** Bagnon (sorting.lua), GudaBags (SortEngine.lua)
**What:** Bagnon's `Sort` module physically rearranges items: builds a `spaces` array, computes desired `order` via multi-property comparator, then `PickupContainerItem` swaps items into place with iterative passes. GudaBags has a 6-phase sort: (1) detect specialized bags, (2) route specialized items to correct bags, (3) consolidate partial stacks, (4) categorical sort with equip-slot ordering, (5) execute moves with lock tracking, (6) event-driven pass scheduling via `ITEM_LOCK_CHANGED`. Includes swap deduplication to prevent oscillation, max-moves-per-cycle limits, and timeout fallbacks.
**Our state:** Visual sort only (`Sorter.lua` reorders the display array). No physical item movement.
**Gap:** Physical bag sorting with stack consolidation, specialized bag routing, lock tracking.

### A15. Advanced Search Grammar (Typed Searches with Operators)
**Who:** Bagnon (LibItemSearch-1.0)
**What:** Full search grammar: `n:name` (name search), `t:type` (type/subtype/equipLoc), `q:>=4` (quality with comparison operators), `ilvl:>=200` (item level), `boe`/`bop`/`bou`/`quest`/`boa` (tooltip keyword search), `s:setName` (equipment set search). Supports union (`|`), intersect (`&`), negation (`!`). `RegisterTypedSearch` API for extensibility. Tooltip scanning with per-itemID cache.
**Our state:** Plain text substring search on item names.
**Gap:** Typed search grammar with quality/ilvl/type/bind/equipment-set filters and boolean operators.

### A16. VoidStorage Support
**Who:** Bagnon_VoidStorage
**What:** Full VoidStorage frame replacement with transfer dialogs, deposit/withdraw buttons, and item frame.
**Our state:** No VoidStorage support (3.3.5a doesn't have VoidStorage, but Retail does — our stated target).
**Gap:** VoidStorage frame (for Retail forward-compatibility).

### A17. Rule Engine with Compiled Expressions
**Who:** Bagshui
**What:** Full rule engine: `Rules:Compile(ruleString)` uses `loadstring()` to compile rule expressions into functions. `Rules:Match(compiledRule, item, character)` executes in a protected environment. 30+ built-in rule functions: `ActiveQuest`, `Bag`, `BagType`, `BindsOnEquip`, `CharacterLevelRange`, `Count`, `EmptySlot`, `EquipLocation`, `Equipped`, `Id`, `ItemString`, `LootMethod`, `MatchCategory` (recursive category matching with call-stack loop prevention), `MinLevel`, `Location`, `Name`, `NameExact`, `Openable`, `Outfit` (ItemRack/Outfitter), `PeriodicTable`, `PlayerInGroup`, `ProfessionCraft`, `ProfessionReagent`, `Quality`, `RecentlyChanged`, `RequiresClass`, `Soulbound`, `Stacks`, `Subtype`, `Subzone`, `Tooltip`, `Transmog`. Rules support `and`/`or`/`not` operators and function calls with arguments. Error tracking with re-validation on category updates.
**Our state:** Hardcoded category checks. No user-defined rules. (We had a `Rules` module that was disabled — `Omni.Rules:Init()` is called in Core.lua but the module isn't in the .toc.)
**Gap:** Full rule engine with compiled expressions, 30+ rule functions, recursive matching, error tracking.

### A18. User-Defined Categories with Class-Specific Rules
**Who:** Bagshui
**What:** `Categories` class (built on `ObjectList` prototype): users create custom categories with `name`, `nameSort`, `sequence` (evaluation order), `list` (direct item ID assignments), and `rule` (rule expression). Categories can be **class-specific** — a `classes` table with per-class `list` and `rule`. Categories are compiled once and cached. Direct assignment via right-click in Edit Mode. Auto-split menus for category selection.
**Our state:** Fixed category set in `Categorizer.lua`. Manual overrides via `categoryOverrides[itemID]` but no UI, no rules, no class-specific categories.
**Gap:** User-defined categories with rules, item lists, class-specific sub-categories, and a management UI.

### A19. User-Defined Multi-Field Sort Orders
**Who:** Bagshui
**What:** `SortOrders` class: users create custom sort orders with an array of `{lookup, field, direction, reverseWords}` entries. Each field can be any valid item property (name, quality, type, subtype, count, bagNum, slotNum, etc.) or a lookup-object property (e.g., `Category.name`). Direction is `asc`/`desc` per field. `reverseWords` reverses name word order (handles "of the Whale" suffixes — "Sword of the Whale" → "Whale the of Sword" for sorting). Per-group sort order assignment.
**Our state:** Fixed sort modes: `category`, `quality`, `name`, `ilvl`. No user-defined multi-field orders.
**Gap:** User-defined multi-field sort orders with per-field direction, reverse-words, lookup objects.

### A20. Row/Group Layout Structure with Edit Mode
**Who:** Bagshui
**What:** Layout is a 2D table: `layout[row][group] = { name, categories, sortOrder, hide, ... }`. Groups are visual containers that hold categorized items. **Edit Mode** allows drag-and-drop group rearrangement with group move targets (between rows and columns), category assignment via dropdown, group hide/show, and per-group sort order selection. The `UpdateWindow()` function uses a sophisticated column-fitting algorithm that shrinks group widths until everything fits within `maxColumns`.
**Our state:** Flow/Grid/List views with category headers. No user-editable layout structure, no drag-and-drop group arrangement.
**Gap:** Editable row/group layout with drag-and-drop, per-group categories/sort, column-fitting algorithm.

### A21. Profiles System (Import / Export / Switch)
**Who:** Bagshui, AdiBags (AceDB profiles), Bagnon
**What:** Bagshui has a full `Profiles` class with create/duplicate/delete/import/export. Profiles store the entire layout structure, category assignments, sort orders, and settings. Users can switch between profiles per-character. AdiBags and Bagnon use AceDB-3.0's built-in profile system with `OnProfileChanged`/`OnProfileCopied`/`OnProfileReset` callbacks.
**Our state:** Single global `OmniInventoryDB` with no profile switching.
**Gap:** Profile system with create/duplicate/switch/import/export.

### A22. PeriodicTable Integration
**Who:** Bagshui
**What:** `PeriodicTable` (PT) library integration via the `pt`/`tx` rule function. PT is a community-maintained taxonomy of item sets (e.g., "Consumable.Buff.Food", "Trade Goods.Metal.Stone"). Users can categorize items by PT set membership in rules.
**Our state:** No PeriodicTable integration.
**Gap:** PeriodicTable set-based categorization.

### A23. Skins System
**Who:** Bagshui
**What:** `Skins` class with per-skin settings: item slot margins, group margins, group padding, label positions, border styles, background colors. Skins can be user-defined and shared. `BsSkin` provides fudge factors for margin adjustments.
**Our state:** Hardcoded visual constants in `DIM` table.
**Gap:** User-definable skin system with margin/padding/color/border customization.

### A24. Mailbox Scanner
**Who:** GudaBags
**What:** `MailboxScanner` module: scans all inbox items on `MAIL_INBOX_UPDATE` (debounced), stores to database. Hooks `SendMail` to capture outgoing mail to alts. Hooks `PlaceAuctionBid` to capture AH buyouts. Tracks sender, subject, money, COD, days left, wasRead. Multi-attachment support (TurtleWoW up to 12). `MailboxFrame` UI to view stored mailbox contents.
**Our state:** No mailbox scanning or viewing.
**Gap:** Mailbox content scanning, outgoing mail tracking, AH buyout capture, mailbox viewing UI.

### A25. Quest Item Bar (Dedicated Usable Quest Item Bar)
**Who:** GudaBags
**What:** `QuestItemBar`: a separate draggable bar showing usable quest items. 2 main slots with pinning (Alt+Click in bags to pin, Alt+Right-Click to unpin). Flyout on hover showing extra quest items. `SecureActionButtonTemplate` with `type="item"` for combat-safe use. Keybindings (`GUDA_USE_QUEST_ITEM_1/2`) wired via `SetBindingClick`. PreClick/PostClick gating for modifier suppression. Pre-created buttons out of combat. Quest border overlay (yellow).
**Our state:** Quest items are categorized into "Quest Items" category but no dedicated bar.
**Gap:** Dedicated quest item bar with pinning, flyout, keybindings, secure use.

### A26. Tracked Item Bar
**Who:** GudaBags
**What:** `TrackedItemBar`: a bar for user-tracked items (similar to quest item bar but for any pinned items).
**Our state:** We have `Data:PinItem()`/`IsPinned()` and pinned items sort first, but no dedicated bar UI.
**Gap:** Dedicated tracked-item bar UI.

### A27. Money Tracker
**Who:** GudaBags
**What:** `MoneyTracker` module: tracks gold over time, presumably with history/graph.
**Our state:** We display current gold and save it per character but no historical tracking.
**Gap:** Gold history tracking with trend display.

### A28. CacheWarmer (Pre-load Item Info)
**Who:** GudaBags, Bagshui (`LoadListItemsIntoGameCache`)
**What:** GudaBags' `CacheWarmer` pre-loads `GetItemInfo()` for known item IDs to avoid tooltip delays. Bagshui's `Categories:LoadListItemsIntoGameCache()` iterates all category item lists and calls `BsItemInfo:LoadItemIntoLocalGameCache(itemId)` on `PLAYER_ENTERING_WORLD`.
**Our state:** We rely on `GET_ITEM_INFO_RECEIVED` bucketing to re-render when data arrives, but no proactive cache warming.
**Gap:** Proactive item info cache warming on login.

### A29. AutoLoot
**Who:** GudaBags
**What:** `AutoLoot` module — presumably auto-loots loot frames.
**Our state:** No auto-loot feature.
**Gap:** Auto-loot functionality.

### A30. Item Fixes Database
**Who:** Bagshui
**What:** `Config/ItemFixes.lua` — a database of item corrections for Vanilla client quirks (wrong categories, missing data, etc.).
**Our state:** No item fixes database.
**Gap:** Item data correction table for client quirks.

### A31. Character Data (Profession Crafts / Reagents / Equipped History)
**Who:** Bagshui
**What:** `CharacterData` component tracks: profession crafts (items you can craft), profession reagents (items used by your recipes), equipped history (items you've worn). Used by `ProfessionCraft()`, `ProfessionReagent()`, and `Equipped()` rule functions.
**Our state:** No profession or equipped history tracking.
**Gap:** Profession craft/reagent tracking, equipped item history.

### A32. Share / Import / Export System
**Who:** Bagshui
**What:** `Share` component for sharing categories, sort orders, profiles, and skins via export strings.
**Our state:** No sharing system.
**Gap:** Export/import of configuration objects.

### A33. Log Window
**Who:** Bagshui
**What:** `LogWindow` component — a debug log window for tracking addon behavior.
**Our state:** We have `/oi debug` print output and `Perf` profiler but no persistent log window.
**Gap:** Persistent log window UI.

### A34. Bag Type Tags / Icons
**Who:** AdiBags
**What:** `FAMILY_TAGS` and `FAMILY_ICONS` tables map bag family bitmasks to localized tags and icons (Quiver, Ammo Pouch, Soul Bag, Leatherworking Bag, Inscription Bag, Herb Bag, Enchanting Bag, Engineering Bag, Keyring, Gem Bag, Mining Bag, Tackle Box). `GetFamilyTag(family)` returns the tag and icon. `showBagType` setting controls display.
**Our state:** We detect bag type for "Free Space (BagName)" categories but don't show family tags/icons.
**Gap:** Bag family tag/icon display.

### A35. Currency Frame Module
**Who:** AdiBags
**What:** `CurrencyFrame` module showing tracked currencies (emblems, badges, seals, etc.) in the bag frame.
**Our state:** We have `TRACKED_TOOLTIP_CURRENCIES` in Frame.lua for tooltip display, but no dedicated currency frame.
**Gap:** Dedicated currency display frame.

### A36. Item Level Display Module
**Who:** AdiBags
**What:** `ItemLevel` module — displays item levels on item buttons.
**Our state:** We have `showItemLevel` setting but the display is basic.
**Gap:** More sophisticated item level display (e.g., upgrade level, stat level).

### A37. New Item Tracking Module (with Glow)
**Who:** AdiBags (`NewItemTracking`), GudaBags
**What:** AdiBags' `NewItemTracking` module tracks new items with a glow overlay and session-based tracking. `SearchHighlight` module highlights search matches.
**Our state:** We have `newItems` tracking in Events.lua and `highlightNewItems` setting, but no glow overlay or search highlight.
**Gap:** New item glow overlay, search match highlighting.

### A38. TidyBags Module
**Who:** AdiBags
**What:** `TidyBags` module — automatically tidies/organizes bag layout.
**Our state:** No auto-tidy feature.
**Gap:** Auto-tidy bag layout.

### A39. Bank Switcher Module
**Who:** AdiBags
**What:** `BankSwitcher` module — presumably switches between bank bag views.
**Our state:** We have a separate BankFrame but no bank bag switching.
**Gap:** Bank bag view switching.

### A40. Tooltip Info Module
**Who:** AdiBags, Bagnon_Tooltips
**What:** AdiBags' `TooltipInfo` module adds extra info to item tooltips. `Bagnon_Tooltips` adds item count info (how many you have across bags/bank) to tooltips.
**Our state:** We have `UI/Tooltip.lua` but it's for tooltip placement, not adding info to tooltips.
**Gap:** Tooltip augmentation (item counts, extra info).

### A41. Item Overlay / Scanning Tooltip
**Who:** AdiBags-ItemOverlayPlus
**What:** Uses a scanning tooltip to extract additional item data (upgrade level, enchant info, etc.) and display overlays on item buttons.
**Our state:** We have a scanning tooltip in `API.lua` for bind detection but don't extract overlay data.
**Gap:** Advanced tooltip scanning for overlay data (upgrade info, enchant info).

### A42. Bound Item Indicator
**Who:** AdiBags_Bound
**What:** Shows a visual indicator on items that are soulbound.
**Our state:** We categorize soulbound items separately but don't show a bound indicator on the button.
**Gap:** Visual bound indicator on item buttons.

### A43. Bindings.xml (Key Bindings)
**Who:** Bagnon, GudaBags, Bagshui
**What:** All three have `Bindings.xml` for configurable key bindings (toggle bags, toggle bank, toggle keys, use quest item 1/2, etc.).
**Our state:** No `Bindings.xml`. We use slash commands and bag function overrides only.
**Gap:** Configurable key bindings via the WoW key binding UI.

### A44. Localization System
**Who:** All four addons
**What:** AdiBags has `Localization.lua` with 650+ strings in multiple languages. Bagnon has per-locale files (cn/de/es/fr/ru/tw). Bagshui has `Locale/` with enUS and zhCN. GudaBags has `Localization.lua`.
**Our state:** All strings are hardcoded in English.
**Gap:** Localization framework with multi-language support.

### A45. Client Compatibility Layer
**Who:** GudaBags (`ClientCompat`), Bagshui (`Compat`)
**What:** GudaBags' `ClientCompat` module handles API differences between client versions (TurtleWoW vs. Ascension vs. Vanilla). Bagshui has `Compat` component for similar purposes.
**Our state:** We have `API.isWotLK`/`isRetail` detection but limited compatibility shimming.
**Gap:** More comprehensive client compatibility layer for private server quirks.

### A46. Theme System (Rounded / Square Slot Styles)
**Who:** GudaBags
**What:** `Theme` module with `GetSlotStyle()` (rounded vs. square) and `GetQualityBorderStyle()`. Square style hides rounded borders and crops icons (pfUI-compatible). Rounded uses default WoW borders.
**Our state:** Hardcoded visual style.
**Gap:** Theme system with style presets.

---

## B. Features We Both Have, But They Do Better

### B1. Event Bucketing / Coalescing
**Theirs:** AdiBags uses `AceBucket-3.0` (battle-tested library). Bagnon uses `AceTimer-3.0` for scheduled sorting. GudaBags uses `Guda_ScheduleTimer` with debounced BAG_UPDATE handling.
**Ours:** Custom `Events:RegisterBucketEvent()` with 50ms window + chunked bag updates. Works but is hand-rolled and less battle-tested.
**Better:** Consider adopting AceBucket-3.0 or improving our custom implementation with better edge-case handling.

### B2. Object Pooling
**Theirs:** AdiBags uses `addon:CreatePool(class, "AcquireSection")` with `IterateActiveObjects()`. Bagshui uses `ObjectManager` with comprehensive lifecycle management.
**Ours:** `Pool.lua` with `Acquire`/`Release`/`ReleaseAll`/`Prewarm`. Good implementation but lacks `IterateActiveObjects()` and per-object lifecycle hooks.
**Better:** Add active object iteration and lifecycle hooks (OnAcquire/OnRelease callbacks).

### B3. Sort Stability
**Theirs:** AdiBags uses an `itemCompareCache` metatable to cache comparator results. Bagnon uses multi-property `Sort.Proprieties` chain. Bagshui uses compiled sort functions with per-field direction.
**Ours:** Decorate-sort-undecorate with index tie-break in `Sorter.lua`. Good stability but only 4 fixed modes.
**Better:** Add more sort fields (type, subtype, equip slot, count, bag/slot position) and allow custom comparator chains.

### B4. Bag Function Override / Blizzard Frame Suppression
**Theirs:** AdiBags uses `RawHook` on all bag functions + `CloseSpecialWindows`. Bagnon uses `hooksecurefunc` + custom replacement functions with pass-through fallback. Both handle the bank frame by hooking `Show`/`Hide`/`IsShown`/`OnEvent`.
**Ours:** We reassign globals (`ToggleAllBags = OmniToggleAll`) and suppress Blizzard frames with `SetScript("OnShow", ...)` + `UnregisterAllEvents`. We have combat-safety tracking (`_toggleStats`) and `ADDON_ACTION_BLOCKED` sinks. More defensive but more fragile.
**Better:** Consider using AceHook-3.0 for safer hooking with automatic fallback. Our combat-safety tracking is actually *more* sophisticated than theirs.

### B5. Guild Bank Support
**Theirs:** Bagnon_GuildBank is a full guild bank frame replacement with tabs, item frames, money frame, and saved settings. GudaBags has guild bank support.
**Ours:** `GuildBankFrame.lua` with `InstallSetGuildBankTabInfoShim()`, off-screen Blizzard frame preservation, event handling.
**Better:** Bagnon's is a complete replacement with per-tab settings; ours is more of an overlay.

### B6. Search
**Theirs:** Bagnon has a full search grammar (see A15). AdiBags has `SearchHighlight` module. Bagshui has `Ui.SearchBox` with rule-based search.
**Ours:** Plain substring search on item names in `Frame.lua`.
**Better:** Add typed search (quality, type, ilvl, bind) at minimum.

### B7. Settings / Options UI
**Theirs:** AdiBags uses `AceConfig-3.0` + `AceGUI-3.0` with a full options panel (filters, layout, skin, modules). Bagnon_Config has per-panel options (general, display, frame, color) with custom widgets (checkButton, colorSelector, dropdown, slider). Bagshui has a comprehensive `Settings` class with type-specific setting info and a `Profiles.Ui`. GudaBags has `SettingsPopup`.
**Ours:** `UI/Options.lua` — we have a settings panel but it's less comprehensive.
**Better:** Adopt AceConfig-3.0 or expand our custom settings with more options (per-filter config, skin settings, profile management).

### B8. New Item Detection
**Theirs:** AdiBags has a dedicated `NewItemTracking` module with glow. GudaBags scans for new items with `bagSlotContents` tracking. Bagshui has `bagshuiStockState` (NEW/UP/DOWN/NO_CHANGE).
**Ours:** `Events.lua` tracks `newItems[slotKey]` by comparing `bagSlotContents` before/after. `Categorizer` has `IsNewItem()`/`MarkAsNew()`.
**Better:** Add stock state tracking (UP/DOWN for count changes) and visual glow overlay.

### B9. Clam Opener
**Theirs:** GudaBags has `ClamOpener` module.
**Ours:** `Core.lua` has `StartClamOpener()` with `FindNextClam()`, combat safety, blocking frame detection, 0.5s delay.
**Better:** Roughly equivalent. GudaBags may have more clam types or better edge-case handling.

### B10. Vendor Sell Protection
**Theirs:** Not directly present in references (AdiBags' Junk filter handles *what* to sell, not *protection*).
**Ours:** `Core.lua` has `UseContainerItem` hook with double-right-click protection for valuable items (quality >= 3, soulbound, quest items).
**Better:** We're actually *ahead* here — this is a feature they don't have.

### B11. Auto-Sell Junk / Auto-Repair
**Theirs:** AdiBags' Junk filter identifies junk but doesn't auto-sell. GudaBags may have auto-sell.
**Ours:** `Events.lua` `MERCHANT_SHOW` handler auto-sells quality==0 items and auto-repairs (with guild bank option).
**Better:** We're ahead on auto-sell/repair. Could improve by integrating with a junk filter's include/exclude lists.

### B12. Find Dungeon Popup
**Theirs:** Not present in any reference addon.
**Ours:** `Frame.lua` has a full Find Dungeon popup with presets (Vanilla/TBC/WotLK), custom filter input, and `.finddungeon` command integration.
**Better:** We're ahead — this is unique to OmniInventory (likely Ascension-specific).

### B13. Performance Profiler
**Theirs:** Not present as a standalone module in any reference.
**Ours:** `Perf.lua` with `Begin`/`End`/`RecordValue`/`CountBucket`, p95 percentile, JSON export, `/oi perf report`.
**Better:** We're ahead — this is unique to OmniInventory.

---

## C. Implementation Patterns They Do Better

### C1. Module System (AceAddon-3.0)
**Theirs:** AdiBags and Bagnon use `AceAddon-3.0`: `NewAddon`/`NewModule` with `OnInitialize`/`OnEnable`/`OnDisable` lifecycle, `SetDefaultModuleState`, `SetDefaultModulePrototype`, `IterateModules()`. Modules can be independently enabled/disabled. Filters are modules with `isFilter` flag.
**Ours:** Flat `Omni.*` namespace with `Init()` functions called from `Core.lua`. No enable/disable lifecycle, no module iteration.
**Better:** Adopt a module system (AceAddon-3.0 or custom) with lifecycle management and independent enable/disable.

### C2. Message Bus (CallbackHandler / AceEvent)
**Theirs:** AdiBags uses `SendMessage`/`RegisterMessage` extensively: `AdiBags_BagUpdated`, `AdiBags_FiltersChanged`, `AdiBags_LayoutChanged`, `AdiBags_ConfigChanged`, `AdiBags_GlobalLockChanged`, `AdiBags_InteractingWindowChanged`, `AdiBags_BagOpened`/`Closed`, `AdiBags_BagFrameCreated`, `AdiBags_OrderChanged`, `AdiBags_UpdateAllButtons`, `AdiBags_PreFilter`, `AdiBags_PreContentUpdate`, `AdiBags_SectionCreated`, `AdiBags_OverrideFilter`. Bagnon uses `Callbacks:SendMessage`. Bagshui uses `BAGSHUI_*` events.
**Ours:** Direct function calls between modules. No message bus.
**Better:** Decouple modules via a message bus for better extensibility and testability.

### C3. OO System
**Theirs:** AdiBags has `OO.lua` with `NewClass`/`NewPool` and class prototypes. Bagnon uses `Classy` library. Bagshui has `prototypes.ObjectList` and `prototypes.Inventory` with inheritance.
**Ours:** Flat tables with methods. No class hierarchy.
**Better:** Add a lightweight OO system for widgets (Container, Section, ItemButton, Group) with inheritance and pooling.

### C4. Database / SavedVariables Management
**Theirs:** AdiBags and Bagnon use `AceDB-3.0` with profile support, `RegisterNamespace` for per-module settings, and `OnProfileChanged` callbacks. Bagshui has a custom `ObjectList` with versioning and migration functions. GudaBags has `Guda_DB` (global) + `Guda_CharDB` (per-char).
**Ours:** `Data.lua` with manual `MergeDefaults` and flat global/char/realm structure. No profiles, no versioning, no migration.
**Better:** Adopt AceDB-3.0 or add versioning + migration + profiles to our Data module.

### C5. Global Lock / Update Pausing
**Theirs:** AdiBags has `SetGlobalLock(locked)` that sends `AdiBags_GlobalLockChanged` to pause all updates during combat/equipment swaps. Container frames have `PauseUpdates()`/`ResumeUpdates()`.
**Ours:** We gate `UpdateLayout` on `InCombatLockdown()` and defer to `PLAYER_REGEN_ENABLED`, but no explicit global lock.
**Better:** Add an explicit global lock for cleaner update pausing during sort/swap operations.

### C6. Interacting Window Tracking
**Theirs:** AdiBags tracks `UpdateInteractingWindow` for bank/mail/merchant/AH/trade/guildbank events, exposing `GetInteractingWindow()` and `atBank` flag. Used to control virtual stacking behavior (`notWhenTrading`).
**Ours:** We track `Omni._merchantOpen` for vendor transitions but don't track other interacting windows.
**Better:** Track all interacting windows for context-aware behavior (virtual stacking, auto-display, etc.).

### C7. LayeredRegion Widget System
**Theirs:** AdiBags has `LayeredRegion` widget with `AddWidget` for composable header/bottom regions. The container frame has `HeaderLeftRegion`, `HeaderRightRegion`, `BottomLeftRegion`, `BottomRightRegion` that widgets can be added to with ordering.
**Ours:** Fixed header/footer layout in `Frame.lua`.
**Better:** Composable widget regions for extensible header/footer content.

### C8. Dry Run Layout Comparison
**Theirs:** Bagshui's `ManageDryRun(phase1)` does a dry-run categorize/sort, compares proposed vs. current layout state, and only triggers a resort if there are differences. This prevents items from shifting around when the window is open.
**Ours:** We use show signatures (`ComputeShowSignature`) to detect changes, but don't do a dry-run sort comparison.
**Better:** Dry-run sort comparison to avoid unnecessary item reordering.

### C9. Resort Button
**Theirs:** Bagshui shows a resort button when `enableResortIcon` is true (dry run detected changes).
**Ours:** No resort button — sorting happens automatically.
**Better:** Add a resort button that appears when items could be reorganized.

### C10. Empty Slot Stacking
**Theirs:** Bagshui has `stackEmptySlots` setting with `emptySlotStackingAllowed` logic, `expandEmptySlotStacks` temporary expansion, `_bagshuiPreventEmptySlotStack` per-slot prevention, and `ResetEmptySlotStackCounts()`.
**Ours:** `collapseEmptySlots` setting exists but the implementation is simpler.
**Better:** More sophisticated empty slot stacking with per-slot prevention and expansion.

### C11. Edit Mode
**Theirs:** Bagshui has a full Edit Mode: `Inventory.EditMode.lua` with group move targets, category assignment, group hide/show, sort order selection, and drag-and-drop group rearrangement.
**Ours:** No edit mode.
**Better:** Add an edit mode for layout customization.

### C12. Garbage Collection Optimization
**Theirs:** Bagshui explicitly reuses variables ("Reusable variables for MatchCategory() to reduce garbage collector load"), uses `BsUtil.TableClear()` instead of creating new tables, and avoids creating throwaway tables in hot paths. GudaBags' SortEngine has a `propertyCache` with `PROPERTY_CACHE_MAX` eviction.
**Ours:** We use `renderScratch` and `stableSortRows` for reuse, and `ClearArray`/`ClearMap` helpers, but could be more aggressive.
**Better:** More aggressive table/variable reuse in hot paths, especially in categorization and sorting.

---

## D. Summary Priority Matrix

| Priority | Feature | Source | Effort |
|----------|---------|--------|--------|
| **High** | Rule Engine + User Categories | Bagshui | Large |
| **High** | Advanced Search Grammar | Bagnon | Medium |
| **High** | Physical Bag Sorting | Bagnon/GudaBags | Large |
| **High** | Offline Inventory DB | Bagnon_Forever | Medium |
| **High** | Key Bindings (Bindings.xml) | All | Small |
| **High** | Collapsible Sections (mature) | AdiBags | Small |
| **High** | Per-Frame Settings | Bagnon | Medium |
| **High** | Configurable Auto-Display | Bagnon | Small |
| **Medium** | Masque Support | AdiBags | Medium |
| **Medium** | LibSharedMedia Integration | AdiBags | Medium |
| **Medium** | Virtual Stacking | AdiBags | Medium |
| **Medium** | Filter Priority System | AdiBags | Medium |
| **Medium** | Equipment Set Tracking (location-based) | AdiBags | Medium |
| **Medium** | Junk Include/Exclude Lists | AdiBags | Small |
| **Medium** | LDB Data Source/Launcher | AdiBags/Bagnon | Small |
| **Medium** | User-Defined Sort Orders | Bagshui | Medium |
| **Medium** | Profiles System | Bagshui/Bagnon | Medium |
| **Medium** | Mailbox Scanner | GudaBags | Medium |
| **Medium** | Quest Item Bar | GudaBags | Medium |
| **Medium** | Message Bus | AdiBags | Medium |
| **Medium** | Module System (lifecycle) | AdiBags | Medium |
| **Medium** | Localization Framework | All | Large |
| **Low** | Bin-Packing Layout | AdiBags | Large |
| **Low** | Edit Mode (drag-and-drop layout) | Bagshui | Large |
| **Low** | PeriodicTable Integration | Bagshui | Medium |
| **Low** | Skins System | Bagshui | Medium |
| **Low** | Row/Group Layout Structure | Bagshui | Large |
| **Low** | VoidStorage Support | Bagnon | Medium |
| **Low** | Currency Frame | AdiBags | Small |
| **Low** | Money Tracker | GudaBags | Small |
| **Low** | CacheWarmer | GudaBags/Bagshui | Small |
| **Low** | AutoLoot | GudaBags | Small |
| **Low** | Tooltip Item Counts | Bagnon_Tooltips | Small |
| **Low** | Item Fixes Database | Bagshui | Small |
| **Low** | Character Data (professions) | Bagshui | Medium |
| **Low** | Share/Import/Export | Bagshui | Medium |
| **Low** | Log Window | Bagshui | Small |
| **Low** | Bag Type Tags/Icons | AdiBags | Small |
| **Low** | New Item Glow | AdiBags | Small |
| **Low** | TidyBags | AdiBags | Small |
| **Low** | Bank Switcher | AdiBags | Small |
| **Low** | Bound Item Indicator | AdiBags_Bound | Small |
| **Low** | Item Overlay (tooltip scan) | AdiBags-ItemOverlayPlus | Medium |
| **Low** | Theme System | GudaBags | Small |
| **Low** | Client Compatibility Layer | GudaBags/Bagshui | Medium |
| **Low** | Dry Run Layout Comparison | Bagshui | Medium |
| **Low** | Resort Button | Bagshui | Small |
| **Low** | Empty Slot Stacking (mature) | Bagshui | Small |
| **Low** | GC Optimization | Bagshui | Ongoing |
| **Low** | Global Lock | AdiBags | Small |
| **Low** | Interacting Window Tracking | AdiBags | Small |
| **Low** | LayeredRegion Widgets | AdiBags | Medium |
| **Low** | OO System | AdiBags/Bagnon | Medium |
| **Low** | AceDB / Versioning / Migration | AdiBags | Medium |

---

## E. Features We Have That They Don't

For completeness, these are unique to OmniInventory:

1. **Find Dungeon Popup** — `.finddungeon` command integration with presets (Ascension-specific)
2. **Performance Profiler** — `Perf.lua` with p95, JSON export, bucket counters
3. **Vendor Sell Protection** — Double-right-click confirmation for valuable items
4. **Combat Safety Tracking** — `_toggleStats` with `ADDON_ACTION_BLOCKED` sink, `forceshow`/`forcehide` debug commands
5. **Tooltip Placement Options** — `itemTooltipPlacement` with right/left/fixed_br/fixed_bl/fixed_tl/fixed_tr
6. **Footer Money Emphasis** — Larger outlined gold + slot count with blue→red fill tint
7. **Addon Launcher Buttons** — Footer buttons for third-party addons (AtlasLoot) with auto-hide
8. **Honor/Arena Point Conversion** — Footer currency display with conversion rates
9. **Stone Keeper's Shard / Wintergrasp Mark** — Currency tracking in footer
10. **Optimistic Flow Refresh** — Watcher-based refresh after item operations
11. **Burst Full Refresh** — Coalesced delayed refresh after rapid changes
12. **C_Container Polyfill** — Modern Retail-style API shim for 3.3.5a
