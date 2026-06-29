# OmniInventory

[![Version](https://img.shields.io/badge/version-2.0--alpha-blue.svg)](#)
[![WoW](https://img.shields.io/badge/world%20of%20warcraft-3.3.5a-orange.svg)](#)
[![License](https://img.shields.io/badge/license-Proprietary-red.svg)](LICENSE)

**OmniInventory** is a premium, high-performance inventory, bags, bank, and guild bank management addon for World of Warcraft 3.3.5a (Wrath of the Lich King). Developed by **Zendevve**, it cleans up stock Blizzard clutter and unifies all bag slots into cohesive, searchable, and highly custom views.

OmniInventory is fully client-side and optimized for stock 3.3.5a servers, with zero server-side database requirements.

---

## ✨ Features

### 📦 Unified Layouts
* **Grid View**: A unified, Bagnon-style container grid that preserves physical slot order.
* **Flow View**: An AdiBags-inspired layout that organizes your items automatically into logical category lanes (Consumables, Trade Goods, Quest, Equipment, etc.).
* **List View**: A text-based, searchable list view of all your inventory items.
* **Category Collapsing**: Left-click category headers in Flow View to collapse/expand them. Your preferences are saved per-character and persist across sessions.
* **Specialty Bag Highlights**: Empty slots and common items inside specialty bags display colored borders indicating their profession family:
  * 🏹 **Ammo/Quiver**: Gold
  * 🔮 **Soul Bag**: Purple
  * 🌿 **Herbs**: Green
  * ⛏️ **Mining**: Copper-Orange
  * ⚙️ **Engineering**: Cyan
  * 🧪 **Gems**: Teal
  * 🧵 **Leatherworking**: Brown
  * 🖋️ **Inscription**: Light Blue
  * 🎣 **Tackle Box**: Deep Blue

### 🔍 Advanced Search Filters
Filter your unified bags instantly. The search bar supports advanced prefix matching:
* `~t:text` or `tooltip:text`: Scans inside item tooltips (works offline and cached).
* `~q:quality` or `quality:quality`: Filters by item rarity (e.g. `~q:epic` or `~q:4`).
* `~e` or `~equip` or `equipment`: Filters and displays only items that can be equipped.

### ⚙️ Automation & Economy
* **Auto-Sell Junk**: Automatically sells all gray-quality items when you interact with any merchant, displaying your net earnings in chat.
* **Auto-Repair**: Automatically repairs all equipped gear and bag gear when talking to a repair vendor.
* **Guild Bank Repair support**: Auto-repair can be set to use Guild funds if permissions allow.
* **Automated Clam Opener**: Run `/oi clams` to search and open all clams in your inventory sequentially with a debounced click-queue. Pauses automatically if the cursor is busy or loot frames are open, and cancels instantly if you enter combat.

### 👥 Multi-Character QoL
* **Realm-wide Tooltip Counts**: Hovering over any item displays a breakdown of which alts on your realm own the item (Bags, Bank, Equipped) and the grand total.
* **Cross-Character Gold Tracker**: Hovering over your gold in the bottom-right footer displays a breakdown of the gold held by each of your characters on the realm, along with a grand total sum.
* **Soulbound & Account Bound Lanes**: Soulbound (BoP) and Account Bound (BoA / Heirlooms) gear are automatically separated into dedicated sections in Flow View.

---

## ⌨️ Slash Commands

* `/omni` or `/oi` - Toggle the main inventory frame.
* `/oi config` - Open the Options / Settings window.
* `/oi clean` - Clean and sort your bags.
* `/oi clams` or `/oi openclams` - Start opening clams automatically.
* `/oi reapply` - Re-apply bag function overrides.

---

## 🔧 Installation

1. Download or clone this repository.
2. Move the `OmniInventory` subdirectory to your World of Warcraft installation:
   `World of Warcraft/Interface/AddOns/OmniInventory`
3. Restart or log in to the game and ensure the addon is checked in your AddOns menu.

---

## 📄 License & Terms

This project is published under a proprietary **Copyright Notice and Limited Personal Use** license.
* You may download, study, fork, and install this software solely for personal, non-commercial use within World of Warcraft.
* You may not modify, rename, redistribute, re-upload, bundle, or copy source code / assets into other projects without prior written permission from the copyright holder.

For full terms and details, please read the [LICENSE](LICENSE) file at the root of the repository.
