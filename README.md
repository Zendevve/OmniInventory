# OmniInventory

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](#)
[![WoW](https://img.shields.io/badge/world%20of%20warcraft-3.3.5a-orange.svg)](#)
[![License](https://img.shields.io/badge/license-Proprietary-red.svg)](LICENSE)
[![Donate](https://img.shields.io/badge/buy%20me%20a%20coffee-donate-yellow.svg)](https://buymeacoffee.com/zendevve)

**OmniInventory** is a premium, high-performance inventory, bags, bank, and guild bank management addon for World of Warcraft 3.3.5a (Wrath of the Lich King). Developed by **Zendevve**, it cleans up stock Blizzard clutter and unifies all bag slots into cohesive, searchable, and highly custom views.

OmniInventory is fully client-side and optimized for stock 3.3.5a servers, with zero server-side database requirements.

---

## Features

### Unified Layouts
* **Grid View**: A unified, Bagnon-style container grid that preserves physical slot order.
* **Flow View**: An AdiBags-inspired layout that organizes your items automatically into logical category lanes (Consumables, Trade Goods, Quest, Equipment, etc.).
* **List View**: A text-based, searchable list view of all your inventory items.
* **Bag View**: A per-bag preview mode -- click any bag icon in the header ribbon to isolate a single bag.
* **Category Collapsing**: Left-click category headers in Flow View to collapse/expand them. Preferences are saved per-character and persist across sessions.
* **Specialty Bag Highlights**: Empty slots and common items inside specialty bags display colored borders indicating their profession family:
  * **Ammo/Quiver** -- Gold
  * **Soul Bag** -- Purple
  * **Leatherworking** -- Brown
  * **Inscription** -- Light Blue
  * **Herbs** -- Green
  * **Mining** -- Copper-Orange
  * **Engineering** -- Cyan
  * **Gems** -- Teal
  * **Tackle Box** -- Deep Blue
* **Item Level Overlay**: Displays iLevel directly on weapons and armor in your bags.
* **Quality Border Colors**: Color-coded borders match item rarity (Poor through Legendary).
* **New Item Glow**: Golden pulsing highlight on recently acquired items.
* **Pin / Favorite Items**: Shift+Right-click any item to pin it. Pinned items float to the top of Flow View.
* **Bound Item Indicator**: Optional lock icon on soulbound items.
* **Masque Support**: Integrates with Masque for full skin override if installed.

### Search & Filtering
* **Quick Filter Tabs**: Category filter tabs across the bottom of the frame. "All" clears the filter; "New" shows session-acquired items; custom categories are generated dynamically.
* **Tooltip Text Search**: `~t:text` or `tooltip:text` scans inside item tooltips (works offline and cached).
* **Quality Search**: `~q:quality` or `quality:quality` filters by item rarity (e.g. `~q:epic` or `~q:4`).
* **Equipment Search**: `~e` or `~equip` or `equipment` filters and displays only equippable items.
* **Bag Preview**: Click a bag icon in the header to filter the view to that bag only. Click again to return to the full view.

### Bank & Guild Bank
* **Separate Bank Frame**: Dedicated bank frame with its own scale, item scale, and item gap settings. Open via `/oi bankswitch` or the settings panel.
* **Bank Bag Cycling**: Cycle between bank bag views with `/oi bankswitch`.
* **Guild Bank Frame**: Fully integrated guild bank support with Blizzard's guild bank suppression and deposit-from-bags compatibility.
* **Keyring Popup**: Click the keyring icon in the header ribbon to open a popup showing all keys.

### Offline Character Viewing
* **Cross-Character Inventory**: Click the title bar to select another character on your realm and view their bags, bank, and equipped items offline.
* **Realm-wide Tooltip Counts**: Hovering over any item displays a breakdown of which alts on your realm own the item (Bags, Bank, Equipped) and the grand total.

### Automation & Economy
* **Auto-Sell Junk**: Automatically sells all gray-quality items when you interact with any merchant, displaying your net earnings in chat.
* **Auto-Repair**: Automatically repairs all equipped gear and bag gear when talking to a repair vendor.
* **Guild Bank Repair**: Auto-repair can be set to use Guild funds if permissions allow.
* **Auto-Loot**: Automatically loots all items when a loot frame opens.
* **Auto-Tidy on Close**: Compacts bag layout and sorts when the bag window is closed.
* **Automated Clam Opener**: Run `/oi clams` to search and open all clams in your inventory sequentially with a debounced click-queue. Pauses automatically if the cursor is busy or loot frames are open, and cancels instantly if you enter combat.
* **Money Tracker**: Records gold history per character over time for trend display in the footer tooltip.
* **Currency Frame**: Dedicated frame showing Emblems, Badges, and other currency tokens. Toggle with `/oi currency`.

### UI & Customization
* **Theme Toggle**: Switch between Rounded (default WoW borders) and Square (pfUI-compatible cropped icons).
* **Resizable & Movable**: Drag to reposition, resize from the corner. Position and scale persist across sessions.
* **Frame Scale**: 50%-200% slider in settings for both bag and bank frames.
* **Item Scale**: Independent item icon scale (50%-200%).
* **Item Gap**: Adjustable spacing between item icons (0-20px).
* **Bold Footer**: Larger outlined gold and bag count with fill-color slot text.
* **Collapsible Empty Slots**: Collapses all empty slots into a single button per bag type.
* **Custom Tooltip Placement**: Right, Left, or Fixed screen corners (Bottom-Right, Bottom-Left, Top-Left, Top-Right) with adjustable X/Y insets.
* **Footer Buttons**: Toggleable quick-access buttons -- Reset Instances, Hearthstone, Clam Opener, Disenchant, Pick Lock.
* **Third-Party Addon Launcher**: Ribbon integration for AtlasLoot and other addons.
* **Resort Button**: Optional button that appears when a dry-run detects the layout could be reorganized.
* **Global Lock**: Pause all layout updates during sort/swap operations.
* **Combat Safety**: Full combat-lockdown awareness. Layout updates defer automatically and replay when combat ends.

### Auto-Display
The bag frame can auto-open when interacting with:
* Bank NPCs
* Vendor NPCs
* Mailbox
* Auction House
* Trade window
* Crafting stations

---

## Slash Commands

| Command | Description |
|---|---|
| `/oi` or `/omni` or `/omniinventory` | Toggle the main inventory frame |
| `/oi config` | Open the Settings panel |
| `/oi clams` or `/oi openclams` | Auto-open all clams in bags |
| `/oi currency` | Toggle the currency frame |
| `/oi bankswitch` | Cycle bank bag view |
| `/oi sort` or `/oi physort` | Physical bag sort (moves items between bags) |
| `/oi sortcancel` | Cancel an in-progress physical sort |
| `/oi tidy` | Run auto-tidy (sort + compact) |
| `/oi lock` | Toggle global lock (pause updates) |
| `/oi reapply` | Re-apply bag function overrides |
| `/oi rules` | List available rule functions |
| `/oi categories` | List user-defined categories |
| `/oi debug` | Display toggle stats, combat state, and override info |
| `/oi forceshow` | Bypass safe toggle and call raw Show |
| `/oi forcehide` | Bypass safe toggle and call raw Hide |
| `/oi pool` | Display object pool statistics |
| `/oi perf on` | Enable performance profiling |
| `/oi perf off` | Disable performance profiling |
| `/oi perf reset` | Clear perf samples |
| `/oi perf report` | Print timing summary |
| `/oi perf dump` | Print JSON snapshot markers |
| `/oi help` | Display command list |

---

## Installation

1. Download or clone this repository.
2. Move the `OmniInventory` subdirectory to your World of Warcraft installation:
   ```
   World of Warcraft/Interface/AddOns/OmniInventory
   ```
3. Restart or log in to the game and ensure the addon is checked in your AddOns menu.

---

## Support the Project

If OmniInventory makes your WoW experience better and saves you time, please consider buying me a coffee to support its ongoing development!

**[Buy Me A Coffee](https://buymeacoffee.com/zendevve)**

Your support is highly appreciated and directly helps keep the addon updated, optimized, and packed with new features. Thank you!

---

## License & Terms

This project is published under a proprietary **Copyright Notice and Limited Personal Use** license.
* You may download, study, fork, and install this software solely for personal, non-commercial use within World of Warcraft.
* You may not modify, rename, redistribute, re-upload, bundle, or copy source code / assets into other projects without prior written permission from the copyright holder.

For full terms and details, please read the [LICENSE](LICENSE) file at the root of the repository.
