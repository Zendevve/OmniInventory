# OmniInventory

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/Zendevve/OmniInventory/releases)
[![WoW](https://img.shields.io/badge/world%20of%20warcraft-3.3.5a-orange.svg)](https://wowpedia.blizzard.com/wotlk)
[![License](https://img.shields.io/badge/license-Proprietary-red.svg)](LICENSE)
[![Donate](https://img.shields.io/badge/buy%20me%20a%20coffee-donate-yellow.svg)](https://buymeacoffee.com/zendevve)

**OmniInventory** is a premium, high-performance inventory, bags, bank, and guild bank management addon for **World of Warcraft 3.3.5a** (Wrath of the Lich King). Developed by **Zendevve**, it replaces the default Blizzard bag frames with a unified, searchable, and highly customizable interface.

OmniInventory is fully client-side with zero server-side database requirements. All data is persisted via WoW's `SavedVariables` system (`OmniInventoryDB`).

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Slash Commands](#slash-commands)
- [Search Syntax](#search-syntax)
- [Compatibility](#compatibility)
- [Support](#support)
- [License](#license)

---

## Features

### Unified Layouts

| View | Description |
|------|-------------|
| **Flow View** | AdiBags-inspired layout that automatically organizes items into logical category lanes (Consumables, Trade Goods, Quest, Equipment, etc.). Left-click category headers to collapse/expand. |
| **List View** | Text-based, searchable table of all inventory items. |
| **Grid View** | Bagnon-style unified container grid that preserves physical slot order. |

- **Category Collapsing** -- Left-click category headers in Flow View to collapse/expand. Preferences persist per-character across sessions.
- **Bag Preview Mode** -- Click any bag icon in the header ribbon to isolate a single bag's contents. Click again to return to the full view.
- **Pinned / Favorite Items** -- Shift+Right-click any item to pin it. Pinned items float to the top of Flow View.

### Visual Overlays

- **Quality Border Colors** -- Color-coded borders match item rarity (Poor through Legendary).
- **Item Level Overlay** -- Displays iLevel directly on weapons and armor in your bags.
- **New Item Glow** -- Golden pulsing highlight on recently acquired items.
- **Bound Item Indicator** -- Optional lock icon on soulbound (BoP) and heirloom (BoA) items.
- **Unusable Item Overlay** -- Tints unusable gear (level/class locks) and unlearned recipes red.
- **Specialty Bag Highlights** -- Colored borders on empty slots and common items inside specialty bags:

| Bag Type | Color |
|----------|-------|
| Ammo / Quiver | Gold |
| Soul Bag | Purple |
| Leatherworking | Brown |
| Inscription | Light Blue |
| Herbs | Green |
| Mining | Copper-Orange |
| Engineering | Cyan |
| Gems | Teal |
| Tackle Box | Deep Blue |

- **Bag Type Tags** -- Shows family tag text (Ammo, Herb, Mining, etc.) on specialty bag slot icons in the header.
- **Collapsed Empty Slots** -- Collapses all empty slots into a single button per bag type, displaying a count of free spaces.

### Search & Filtering

- **Quick Filter Tabs** -- Category filter tabs across the bottom of the frame. "All" clears the filter; "New" shows session-acquired items; custom categories are generated dynamically.
- **Tooltip Text Search** -- `~t:text` or `tooltip:text` scans inside item tooltips (works offline and cached).
- **Quality Search** -- `~q:quality` or `quality:quality` filters by item rarity (e.g. `~q:epic` or `~q:4`).
- **Equipment Search** -- `~e`, `~equip`, or `equipment` filters and displays only equippable items.
- **Bag Preview** -- Click a bag icon in the header to filter the view to that bag only.

See [Search Syntax](#search-syntax) for the full reference.

### Bank & Guild Bank

- **Separate Bank Frame** -- Dedicated bank frame with its own scale, item scale, and item gap settings. Open via `/oi bankswitch` or the settings panel.
- **Bank Bag Cycling** -- Cycle between bank bag views (all, main bank, bag 5 through 11) with `/oi bankswitch`.
- **Guild Bank Frame** -- Fully integrated guild bank support with Blizzard's default guild bank frame suppression and deposit-from-bags compatibility.
- **Keyring Popup** -- Click the keyring icon in the header ribbon to open a popup showing all keys.

### Offline Character Viewing

- **Cross-Character Inventory** -- Click the title bar to select another character on your realm and view their bags, bank, and equipped items offline.
- **Realm-wide Tooltip Counts** -- Hovering over any item displays a breakdown of which alts on your realm own the item (Bags, Bank, Equipped) and the grand total.

### Automation & Economy

- **Auto-Sell Junk** -- Automatically sells all grey-quality items when you interact with any merchant, displaying net earnings in chat. Configurable junk include/exclude lists allow you to mark specific items as junk or protect them from auto-sell.
- **Auto-Repair** -- Automatically repairs all equipped gear and bag gear when talking to a repair vendor.
- **Guild Bank Repair** -- Auto-repair can optionally use Guild bank funds if permissions allow.
- **Auto-Loot** -- Automatically loots all items when a loot frame opens.
- **Auto-Tidy on Close** -- Compacts bag layout and sorts when the bag window is closed.
- **Clam Opener** -- Run `/oi clams` to search and open all clams in your inventory sequentially with a debounced click-queue. Pauses automatically if the cursor is busy or loot frames are open, and cancels instantly if you enter combat.
- **Money Tracker** -- Records gold history per character over time (capped at 5-minute intervals, 24-hour history) for trend display in the footer tooltip.
- **Currency Frame** -- Dedicated frame showing Emblems, Badges, and other currency tokens (Honor, Arena Points, Emblems of Frost/Triumph/Conquest/Valor/Heroism, Badge of Justice, Champion's Seal, and more). Toggle with `/oi currency`.
- **Sell Protection** -- Double-right-click required to sell valuable items (Soulbound gear, active quest items, rare/epic loot) at vendors.

### UI & Customization

- **Theme Toggle** -- Switch between Rounded (default WoW borders) and Square (pfUI-compatible cropped icons).
- **Resizable & Movable** -- Drag to reposition, resize from the corner. Position and scale persist across sessions.
- **Frame Scale** -- 50%--200% slider in settings for both bag and bank frames.
- **Item Scale** -- Independent item icon scale (50%--200%).
- **Item Gap** -- Adjustable spacing between item icons (0--20 px).
- **Bold Footer** -- Larger outlined gold and bag count. Slot count text shifts from light blue to red as bags fill.
- **Custom Tooltip Placement** -- Right, Left, or Fixed screen corners (Bottom-Right, Bottom-Left, Top-Left, Top-Right) with adjustable X/Y insets (0--400 px each).
- **Footer Buttons** -- Toggleable quick-access buttons in the footer: Reset Instances, Hearthstone, Clam Opener, Disenchant, Pick Lock.
- **Third-Party Addon Launcher** -- Ribbon integration for AtlasLoot and other addons.
- **Resort Button** -- Optional button that appears when a dry-run detects the layout could be reorganized.
- **Global Lock** -- Pause all layout updates during sort/swap operations.
- **Combat Safety** -- Full combat-lockdown awareness. The addon remaps default bag keybinds (B / Shift-B) to its own secure binding (`OMNIINVENTORY_TOGGLE`) so toggling works in combat. Layout updates defer automatically and replay when combat ends.
- **Cache Warmer** -- Pre-loads `GetItemInfo` for known item IDs on login and zone-in to avoid tooltip delays.
- **LibDataBroker (LDB) Support** -- Registers a data source for broker display addons. Left-click toggles bags; right-click opens settings.

### Auto-Display

The bag frame can auto-open when interacting with:

- Bank NPCs
- Vendor NPCs
- Mailbox
- Auction House
- Trade window
- Crafting stations
- Guild Bank

Each trigger is individually configurable in the settings panel.

---

## Installation

### Prerequisites

- **World of Warcraft 3.3.5a** (Wrath of the Lich King) client -- any stock private server build.
- No additional library dependencies are required. Optional integrations with **Masque** (icon skinning) and **LibDataBroker** (broker displays) are auto-detected at runtime.

### Steps

1. Download the latest release from the [Releases](https://github.com/Zendevve/OmniInventory/releases) page, or clone the repository:

   ```bash
   git clone https://github.com/Zendevve/OmniInventory.git
   ```

2. Copy or move the `OmniInventory` subdirectory into your WoW AddOns folder:

   ```
   World of Warcraft/
   └── Interface/
       └── AddOns/
           └── OmniInventory/          <-- this directory
               ├── Core.lua
               ├── Bindings.xml
               ├── OmniInventory.toc
               ├── Omni/
               └── UI/
   ```

3. Restart the game client (or `/reload` in-game) and ensure **OmniInventory** is checked in the **AddOns** menu on the character selection screen.

4. Bind a key to **Toggle OmniInventory Bags** in the **Key Bindings** menu (under the **OmniInventory** header) for best in-combat performance. By default, the addon remaps the B key if it is still on a default Blizzard bag binding.

---

## Configuration

Open the settings panel with `/oi config` or by right-clicking the LibDataBroker icon. The panel provides tabbed controls for **Bag Frame** and **Bank Frame** settings independently.

### Settings Overview

| Section | Options |
|---------|---------|
| **Frame Scale** | 50%--200% |
| **Item Scale** | 50%--200% |
| **Item Gap** | 0--20 px |
| **View Mode** | Cycle between Flow, List, and Grid views |
| **Sort Mode** | Cycle default sort order (Category, Quality, Name, iLevel, Usage) |
| **Theme** | Rounded (default) or Square (pfUI-compatible) |
| **New Items** | Highlight recently acquired items with a golden glow |
| **Bold Footer** | Larger gold/bag count with fill-color slot text |
| **Bound Lanes** | Separate Soulbound and Heirloom items into dedicated category lanes |
| **Red Overlays** | Tint unusable gear and unlearned recipes red |
| **Item Levels** | Display iLevel on weapons and armor |
| **Auto-Sell Junk** | Sell grey items automatically at vendors |
| **Auto-Repair** | Repair all gear at repair vendors |
| **Use Guild Funds** | Spend guild bank gold for repairs (requires guild permissions) |
| **Double-Click Sell Protection** | Require double-right-click to sell valuable items |
| **Collapse Empty Slots** | Show one collapsed empty-slot button per bag type |
| **Tooltip Placement** | Right, Left, or Fixed corner with X/Y inset sliders |
| **Auto-Display** | Per-event toggles: Bank, Vendor, Mail, AH, Trade, Craft |
| **Cache Warmer** | Pre-load item info on login to avoid tooltip delays |
| **Auto-Loot** | Loot all items when a loot frame opens |
| **Money Tracker** | Record gold history for trend display |
| **Bound Indicator** | Show chain icon on soulbound items |
| **Bag Type Tags** | Show family tag text on specialty bags |
| **Auto-Tidy on Close** | Compact and sort bags when the window closes |
| **Resort Button** | Show a button when layout could be reorganized |
| **Footer Buttons** | Toggle Reset Instances, Hearthstone, Clam Opener, Disenchant, Pick Lock |
| **Addon Buttons** | Toggle AtlasLoot launcher |

All settings persist in `OmniInventoryDB` and survive logout/relog.

---

## Slash Commands

| Command | Aliases | Description |
|---------|---------|-------------|
| `/oi` | `/omni`, `/omniinventory`, `/zb`, `/zenbags` | Toggle the main inventory frame |
| `/oi config` | `/oi settings`, `/oi options` | Open the settings panel |
| `/oi clams` | `/oi openclams` | Auto-open all clams in bags |
| `/oi currency` | `/oi currencies` | Toggle the currency frame |
| `/oi bankswitch` | `/oi switchbank` | Cycle bank bag view (all / main / bag 5--11) |
| `/oi sort` | `/oi physort` | Physical bag sort (moves items between bags) |
| `/oi sortcancel` | | Cancel an in-progress physical sort |
| `/oi tidy` | | Run auto-tidy (sort + compact) |
| `/oi lock` | | Toggle global lock (pause all layout updates) |
| `/oi rules` | | List available rule functions |
| `/oi categories` | `/oi cats` | List user-defined categories |
| `/oi debug` | | Display toggle stats, combat state, and override info |
| `/oi forceshow` | | Bypass safe toggle and call raw `Show` |
| `/oi forcehide` | | Bypass safe toggle and call raw `Hide` |
| `/oi footerdump` | | Dump live footer button state |
| `/oi pool` | | Display object pool statistics |
| `/oi perf on` | | Enable performance profiling |
| `/oi perf off` | | Disable performance profiling |
| `/oi perf reset` | | Clear perf samples |
| `/oi perf report` | | Print timing summary |
| `/oi perf dump` | | Print JSON snapshot markers |
| `/oi help` | | Display command list |

---

## Search Syntax

OmniInventory supports prefix-based search operators in the filter bar:

| Syntax | Description | Example |
|--------|-------------|---------|
| `~t:text` | Search inside item tooltips | `~t:crit` finds items with "Critical Strike" in tooltip |
| `tooltip:text` | Alias for `~t` | `tooltip:hit` |
| `~q:quality` | Filter by item rarity name | `~q:epic` shows only Epic items |
| `~q:N` | Filter by rarity number (0=Poor, 1=Common, ..., 5=Legendary) | `~q:4` shows Epic items |
| `~e` / `~equip` / `equipment` | Filter to equippable items only | `~e` |
| *(plain text)* | Matches item name | `sword` |

---

## Compatibility

- **Target client**: World of Warcraft 3.3.5a (Interface version `30300`).
- **Server requirements**: None. Works on any stock 3.3.5a server.
- **Optional integrations** (auto-detected at runtime):
  - [Masque](https://www.curseforge.com/wow/addons/masque) -- full icon skin override.
  - [LibDataBroker-1.1](https://www.curseforge.com/wow/addons/libdatabroker-1-1) -- broker display data source.
  - [AtlasLoot](https://www.curseforge.com/wow/addons/atlasloot) -- footer launcher button (auto-hidden when AtlasLoot is not loaded).

---

## Support the Project

If OmniInventory makes your WoW experience better and saves you time, please consider buying me a coffee to support its ongoing development!

**[Buy Me A Coffee](https://buymeacoffee.com/zendevve)**

Your support is highly appreciated and directly helps keep the addon updated, optimized, and packed with new features. Thank you!

---

## License

This project is published under a proprietary **Copyright Notice and Limited Personal Use** license (c) 2026 Zendevve. All rights reserved.

**Permitted:**
- Download, study, fork, and install for personal, non-commercial use within World of Warcraft.

**Not permitted without prior written permission:**
- Modify, rename, redistribute, re-upload, bundle, or incorporate source code or assets into other projects.
- Sell, sublicense, or include in commercial offerings.
- Remove copyright notices or claim authorship.

Forking is permitted only for personal viewing, study, backup, or installation. Forks may not be modified, redistributed, or published as derivative works.

For full terms, read the [LICENSE](LICENSE) file at the root of the repository.
