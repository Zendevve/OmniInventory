# Changelog

All notable changes to OmniInventory will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial OmniInventory v2.0 architecture
- API Shim layer (`Omni/API.lua`) - bridges 3.3.5a to Retail-style APIs
- Event Bucketing system (`Omni/Events.lua`) - coalesces rapid BAG_UPDATE events
- Object Pool system (`Omni/Pool.lua`) - frame recycling for zero GC churn
- SavedVariables persistence (`Omni/Data.lua`) - cross-character data
- MCAF framework documentation structure
- AGENTS.md with self-learning rules
- Smooth fade-in animation on bag window open (150ms)

### Changed
- Moved ZenBags v1 to `legacy/` folder
- Consolidated bank event handling into Events.lua
- Wrapped Pawn addon integration in pcall for safety

### Fixed
- **C_Container API** - Replaced Retail-only C_Container calls with native WotLK functions
- **BackdropTemplate** - Removed (doesn't exist in 3.3.5a)
- **SetFromAlpha/SetToAlpha** - Replaced with SetChange() for animations
- **SetObeyStepOnDrag** - Removed from Options slider (not in 3.3.5a)
- **SetTexture color calls** - Fixed to use SetTexture(file) + SetVertexColor()
- **Bag toggle bug** - Fixed window appearing then disappearing when pressing B
- **isBankOpen state** - Added SetBankOpen() function for proper state management
- **Duplicate event handlers** - Removed redundant bank event handlers from Frame.lua
- **Unused variables** - Cleaned up origToggleAllBags, origOpenBag, origCloseBag

## [1.0.0] - Legacy (ZenBags)

### Added
- One-click junk selling at vendors
- Quick search auto-focus on keypress
- Smart sorting by item usage frequency
- Cross-character item tracking
- Rule-based categorization
- Gear upgrade detection

---

[Unreleased]: https://github.com/Zendevve/OmniInventory/compare/v1.0-legacy...HEAD
[1.0.0]: https://github.com/Zendevve/OmniInventory/releases/tag/v1.0-legacy
