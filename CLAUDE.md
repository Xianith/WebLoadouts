# CLAUDE.md — WoW Addon Developer Project File

> **I am Claude, a full World of Warcraft addon developer.**
> This file is my living project reference. I maintain it, update it, and use it to track all knowledge, decisions, architecture, and progress for this addon project.

---

## Project: WebLoadouts (Working Title)

**Goal:** Create an addon that adds a dropdown menu to the talent selection screen — visually consistent with Blizzard's native loadout dropdown — that allows players to browse and one-click import talent builds from popular community websites (Wowhead, Icy Veins, Archon, Raidbots, etc).

**Target Game Version:** Retail WoW (The War Within / Midnight era, Interface 110105+)
**Language:** Lua + XML (WoW addon standard)
**License:** TBD

---

## 1. Understanding the Base Game Talent System

### 1.1 Architecture Overview

The modern WoW talent system (introduced in Dragonflight, continued in The War Within) uses a hierarchical data model:

```
[TraitSystem] - TraitConfig >< TraitTree < TraitNode < TraitNodeEntry - TraitDefinition - Spell
```

**Key entities:**

- **TraitConfig** — When you apply talent choices, you apply them to a config. Switching loadouts = switching TraitConfig. A config can contain multiple TraitTrees (professions), but for player talents there is exactly 1 TraitTree.
- **TraitTree** — A list of TraitNodes + currency cost info. Visually there's a separate class tree and spec tree, but in the API it's all 1 tree per class.
- **TraitNode** — Roughly equivalent to a button/talent in the tree UI. Nodes can have multiple entries (choice nodes have 2; single-option nodes have 1).
- **TraitNodeEntry** — Info about a specific talent choice, including rank count.
- **TraitDefinition** — Contains spellID and other relevant info about what a talent actually does.

### 1.2 Core APIs

| API Namespace | Purpose |
|---|---|
| `C_Traits` | Generic trait system APIs (works across talent trees, professions, dragonriding) |
| `C_ClassTalents` | Player class talent-specific APIs (loadouts, configs, import/export) |
| `C_ProfSpecs` | Profession specialization-specific APIs |

**Critical Functions for Our Addon:**

```lua
-- Loadout Management
C_ClassTalents.GetActiveConfigID()                    -- Get active config ID
C_ClassTalents.GetLastSelectedSavedConfigID(specID)   -- Last selected loadout for a spec
C_ClassTalents.ImportLoadout(configID, entries, name)  -- Import a loadout (the key function)
ClassTalentHelper.SwitchToLoadoutByIndex(index)        -- Switch loadout by dropdown index

-- Import/Export Strings
C_Traits.GenerateImportString(configID)                -- Export a loadout to string
C_Traits.GenerateInspectImportString(target)           -- Export an inspected target's build

-- Tree Inspection
C_Traits.GetConfigInfo(configID)                       -- Get config details (includes treeIDs)
C_Traits.GetTreeNodes(treeID)                          -- Get all nodes in a tree
C_Traits.GetNodeInfo(configID, nodeID)                 -- Get node info (entryIDs, etc)
C_Traits.GetEntryInfo(configID, entryID)               -- Get entry info (definitionID)
C_Traits.GetDefinitionInfo(definitionID)               -- Get spell info for a talent

-- View Loadout (for building caches / previewing builds without applying)
C_ClassTalents.InitializeViewLoadout(specID, level)    -- Prep a view config
C_ClassTalents.ViewLoadout(entries)                    -- Load entries into view config
-- View config ID: Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID
```

### 1.3 Talent Build String Format

Blizzard uses a **base64-encoded binary format** for talent build sharing. Key details:

- The string contains: spec ID, a tree checksum, and selected talent information.
- Format is documented in `Blizzard_ClassTalentImportExport.lua` (in the game's FrameXML).
- **Important:** It uses a non-standard base64 variant. Standard base64 decoders will fail on it.
- All major community sites (Wowhead, Icy Veins, etc.) use this same string format for copy/paste.
- The string is what appears when you click "Share" in the talent UI and is what you paste to "Import."

### 1.4 The Default Talent UI Structure

The Blizzard talent frame is composed of:

```
ClassTalentFrame
├── TalentsTab
│   ├── LoadoutDropDown          -- The loadout selector dropdown
│   │   └── GetSelectionID()     -- Returns currently selected loadout config ID
│   ├── SearchBox                -- Talent search
│   ├── ApplyButton              -- "Apply Changes"
│   └── [Talent Node Buttons]    -- The actual tree
├── SpecTab                      -- Spec selection tab
└── [Bottom Buttons]
    ├── ImportButton              -- Opens import dialog
    └── ShareButton               -- Copies export string to clipboard
```

**The Loadout Dropdown** is our primary integration point. In the default UI:
- It shows a list of saved loadouts (up to the Blizzard max, typically 10).
- Includes "Starter Build" as a default option.
- Has a cogwheel for editing loadout name and action bar sharing settings.
- "Import" and "Share" buttons below the dropdown.

**Getting the current selected loadout (from Wowpedia, the most reliable approach):**

```lua
function GetSelectedLoadoutConfigID()
    local lastSelected = PlayerUtil.GetCurrentSpecID() and
        C_ClassTalents.GetLastSelectedSavedConfigID(PlayerUtil.GetCurrentSpecID())
    local selectionID = ClassTalentFrame
        and ClassTalentFrame.TalentsTab
        and ClassTalentFrame.TalentsTab.LoadoutDropDown
        and ClassTalentFrame.TalentsTab.LoadoutDropDown.GetSelectionID
        and ClassTalentFrame.TalentsTab.LoadoutDropDown:GetSelectionID()
    -- Priority: [UI dropdown] > [API] > ['ActiveConfigID'] > nil
    return selectionID or lastSelected or C_ClassTalents.GetActiveConfigID() or nil
end
```

**Known Limitation:** There is **no reliable API** for determining which player-created loadout is currently selected. This causes occasional bugs in both addons and the default UI.

### 1.5 Taint Concerns

**CRITICAL:** Addon-driven talent changes can cause **taint** — Blizzard's security system that prevents addons from executing protected functions. Key issues:

- Directly applying talents from addon code can taint the UI, causing errors like `ADDON_ACTION_FORBIDDEN`.
- The workaround used by most addons (Talent Loadout Ex, etc.) is to **stage the import** and have the user click the native "Apply Changes" button.
- Using `LibUIDropDownMenu` or similar libraries for dropdown menus avoids tainting the default dropdown.
- We must **never** call protected functions from addon code during combat or from untrusted execution paths.
- Reference bug: https://github.com/Stanzilla/WoWUIBugs/issues/447

---

## 2. Existing Addon Landscape (Competitive Research)

| Addon | Downloads | What It Does | Gap We Fill |
|---|---|---|---|
| **Talent Loadout Ex** | 2.8M+ | Unlimited local loadout saves | No web import |
| **Talent Loadout Manager** | 372K+ | Custom loadouts beyond default limit | No web import |
| **Improved Talent Loadouts** | 277K+ | Accountwide unlimited loadouts | No web import |
| **Talent Tree Tweaks** | 4.5M+ | QoL improvements (mini tree previews, export from dropdown, import-to-existing) | No web import |
| **BtWLoadouts** | Popular | Full character setup manager (talents + gear + action bars) | No web import |

**Key Insight:** None of these addons provide **direct integration with community talent websites**. Players must still: visit website → copy string → open WoW → open talents → click import → paste → create loadout. Our addon collapses this to: open talents → pick build from dropdown → apply.

---

## 3. Target Talent Websites

### 3.1 Primary Targets (must-have)

| Site | URL Pattern | How Builds Are Shared |
|---|---|---|
| **Wowhead** | `wowhead.com/talent-calc/...` | Talent calculator with copy-to-clipboard export strings. Guides embed strings. |
| **Icy Veins** | `icy-veins.com/wow/CLASS-SPEC-pve-guide` | Guides include talent build strings. Talent calculator at `/wow/the-war-within-talent-calculator`. |
| **Archon** | `archon.gg/wow` | Data-driven builds from top players. Export strings available. |

### 3.2 Secondary Targets (nice-to-have)

| Site | Notes |
|---|---|
| **Raidbots** | Sim-based; users paste their own strings, not a build source per se |
| **Murlok.io** | Aggregated top player builds per spec/content type |
| **Subcreation** | M+ meta builds aggregated from top runs |
| **WarcraftLogs** | Top parses include talent strings |

### 3.3 Data Strategy

Since the addon runs **client-side** with no internet access from within WoW:

**Option A: Pre-Bundled Builds (Recommended for v1)**
- Ship the addon with a curated set of builds per class/spec/content type.
- Builds are stored as talent build strings in a Lua data table.
- Update the data table with each addon release.
- Label each build with source (e.g., "Wowhead - M+ Fire Mage", "Icy Veins - Raid Holy Paladin").

**Option B: Companion App / External Updater**
- A lightweight external tool (Python/Node) that scrapes/fetches builds from websites.
- Writes updated Lua data files to the addon's SavedVariables or data directory.
- Player runs the tool before launching WoW.

**Option C: Manual Import with Enhanced UX**
- Instead of pre-bundled data, provide a much better import UX.
- Dropdown with labeled slots: "Wowhead Raid Build", "Icy Veins M+ Build", etc.
- Player pastes strings into labeled slots that persist across sessions.
- Essentially: a **named clipboard manager** for talent strings, organized by source.

**Decision: Start with Option C (enhanced import UX) + Option A (ship some default builds).**
This gives immediate value without scraping concerns, and we can add auto-updating later.

---

## 4. Addon Architecture

### 4.1 Addon Name: `WebLoadouts`

**Install Path:** `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\WebLoadouts`

### 4.2 File Structure

```
WebLoadouts/
├── WebLoadouts.toc              -- Table of contents
├── CLAUDE.md                       -- This file (not loaded by WoW)
├── Core.lua                        -- Addon initialization, event handling
├── UI.lua                          -- Dropdown menu, frames, integration with talent UI
├── Data.lua                        -- Pre-bundled talent build strings
├── Storage.lua                     -- SavedVariables management (user-saved imports)
├── ImportExport.lua                -- String validation, parsing, applying builds
├── Config.lua                      -- Slash commands, settings panel
├── Libs/                           -- Embedded libraries
│   ├── LibStub/
│   ├── LibUIDropDownMenu/          -- Taint-free dropdown menus
│   └── AceAddon-3.0/ (optional)
└── Media/                          -- Icons, textures
    └── icons/                      -- Source-specific icons (wowhead, icyveins, etc.)
```

### 4.3 TOC File Template

```toc
## Interface: 110105
## Title: WebLoadouts
## Notes: Import talent builds from Wowhead, Icy Veins, Archon and more — right from the talent screen.
## Author: [Author]
## Version: 1.0.0
## SavedVariables: WebLoadoutsDB
## Dependencies:
## OptionalDeps: LibStub, LibUIDropDownMenu
## IconTexture: Interface\AddOns\WebLoadouts\Media\icon

Libs\LibStub\LibStub.lua
Libs\LibUIDropDownMenu\LibUIDropDownMenu.xml

Core.lua
Storage.lua
Data.lua
ImportExport.lua
UI.lua
Config.lua
```

### 4.4 UI Design Concept

The addon adds a **secondary dropdown button** near the existing loadout dropdown in the talent frame. Design goals:

1. **Visual Consistency** — Match Blizzard's dropdown style (same font, backdrop, highlight colors).
2. **Hierarchical Menu:**
   ```
   [📥 Web Builds ▾]
   ├── 🔶 Wowhead
   │   ├── Raid - Single Target
   │   ├── Raid - AoE / Cleave
   │   ├── Mythic+
   │   └── [Custom...]
   ├── 🔷 Icy Veins
   │   ├── Raid Build
   │   ├── Mythic+ Build
   │   └── [Custom...]
   ├── 🟢 Archon
   │   ├── Top Raid Build
   │   ├── Top M+ Build
   │   └── [Custom...]
   ├── ── Separator ──
   ├── 📋 My Imports
   │   ├── [Saved Build 1]
   │   ├── [Saved Build 2]
   │   └── [+ Add Import...]
   └── ⚙ Settings
   ```
3. **One-Click Apply** — Selecting a build from the dropdown immediately stages it in the talent UI (shows the changes). User still clicks "Apply Changes" to finalize (avoids taint).
4. **Tooltip Preview** — Hovering over a build shows the talent string, source URL, date updated, and optionally a mini-tree preview (stretch goal, like Talent Tree Tweaks does).

### 4.5 Data Storage (SavedVariables)

```lua
WebLoadoutsDB = {
    version = 1,
    userBuilds = {
        -- Key: unique ID, Value: build info
        ["user-1"] = {
            name = "My Raid Build",
            source = "wowhead",        -- or "icyveins", "archon", "manual", etc.
            specID = 253,               -- Beast Mastery Hunter
            talentString = "BYGAAAAAAAAAAAAAAAAAAAAAAIRSSSSiI...",
            contentType = "raid",       -- "raid", "mythicplus", "pvp", "leveling", "delves"
            dateAdded = 1709000000,
            notes = "From Wowhead guide, updated 2025-02-27",
        },
    },
    settings = {
        showButton = true,              -- Show the dropdown button on talent frame
        buttonPosition = "RIGHT",       -- Position relative to loadout dropdown
        autoApply = false,              -- Auto-stage on selection (vs just copy to clipboard)
        showSourceIcons = true,         -- Show website favicons in menu
        enabledSources = {
            wowhead = true,
            icyveins = true,
            archon = true,
        },
    },
}
```

---

## 5. Key Technical Challenges

### 5.1 Hooking into the Talent Frame

The talent frame (`ClassTalentFrame`) is loaded on demand — it doesn't exist at PLAYER_LOGIN. We need to hook into it when it loads:

```lua
-- Method 1: Hook the frame creation
hooksecurefunc("ClassTalentFrame_LoadUI", function() ... end)

-- Method 2: Wait for the addon to load
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "Blizzard_ClassTalentUI" then
        -- ClassTalentFrame now exists, safe to hook
        self:InitializeUI()
    end
end)
```

### 5.2 Importing a Build String Without Taint

The safest approach is to use Blizzard's own import mechanism:

```lua
-- 1. Validate the string
local isValid = C_Traits.IsValidImportString(talentString)

-- 2. Use the ClassTalentLoadoutImportDialog (Blizzard's built-in import dialog)
-- This is the same dialog that opens when you click "Import" in the talent UI
ClassTalentLoadoutImportDialog.ImportControl:SetText(talentString)
ClassTalentLoadoutImportDialog.NameControl:SetText(buildName)

-- OR: Use the internal import pathway
-- The Blizzard code calls ClassTalentFrame.TalentsTab:ImportLoadout(importString)
-- which stages the changes and requires the user to click "Apply Changes"
```

### 5.3 Detecting Current Class/Spec

```lua
local specID = PlayerUtil.GetCurrentSpecID()
local className, classFile, classID = UnitClass("player")
local specIndex = GetSpecialization()
local specID, specName = GetSpecializationInfo(specIndex)
```

### 5.4 Menu Framework

Use `LibUIDropDownMenu` to avoid taint, OR build a custom frame-based menu (cleaner, more control):

```lua
-- Custom approach: Build a ScrollFrame-based dropdown
-- This avoids all taint issues since we never touch Blizzard's dropdown system
-- We create our own button + popup frame near the loadout dropdown
```

---

## 6. Development Roadmap

### Phase 1: MVP (v0.1) ✅ COMPLETE
- [x] Basic addon structure (TOC, Core, events)
- [x] Detect talent frame load, hook into it (ADDON_LOADED for Blizzard_ClassTalentUI)
- [x] Add a button near the loadout dropdown ("Web Builds")
- [x] Custom dropdown menu (frame-based, no UIDropDownMenu, zero taint risk)
- [x] Clicking a build opens Blizzard's import dialog pre-filled with the string
- [x] SavedVariables for user's custom imports (full CRUD)
- [x] "Add Import" dialog with source/content type selection
- [x] Slash commands (/wl help, /wl add, /wl list, /wl export, /wl delete, etc.)
- [x] Right-click to copy build string
- [x] Tooltip previews on hover
- [x] Click-away-to-close behavior
- [x] Data.lua scaffold for all 39 specs with bundled build structure

### Phase 2: Full UX (v0.2)
- [ ] Hierarchical menu (organized by source → content type)
- [ ] Ship pre-bundled builds for all specs (Data.lua)
- [ ] "Add Import" flow — user pastes a string, names it, assigns source/content type
- [ ] Tooltip on hover showing build details
- [ ] Settings panel (slash command + interface options)

### Phase 3: Polish (v0.3)
- [ ] Visual polish — match Blizzard dropdown aesthetic perfectly
- [ ] Source icons (Wowhead orange, Icy Veins blue, Archon green)
- [ ] Mini talent tree preview on hover (stretch goal)
- [ ] Spec filtering — only show builds for current spec
- [ ] Build validation — warn if string is for wrong spec/class

### Phase 4: Advanced (v1.0)
- [ ] Companion updater tool for fetching latest builds
- [ ] Community sharing — export/import build collections
- [ ] Integration with popular addons (ElvUI, WeakAuras)
- [ ] Localization

---

## 7. Reference Links

- [Warcraft Wiki: Dragonflight Talent System](https://warcraft.wiki.gg/wiki/Dragonflight_Talent_System)
- [Wowpedia: Dragonflight Talent System](https://wowpedia.fandom.com/wiki/Dragonflight_Talent_System)
- [Wowpedia: Using UIDropDownMenu](https://wowpedia.fandom.com/wiki/Using_UIDropDownMenu)
- [API C_Traits.GenerateImportString](https://wowpedia.fandom.com/wiki/API_C_Traits.GenerateImportString)
- [API C_ClassTalents.InitializeViewLoadout](https://warcraft.wiki.gg/wiki/API_C_ClassTalents.InitializeViewLoadout)
- [LibUIDropDownMenu (CurseForge)](https://www.curseforge.com/wow/addons/libuidropdownmenu)
- [Talent Tree Tweaks (reference addon)](https://www.curseforge.com/wow/addons/talent-tree-tweaks)
- [Talent Loadout Manager (reference addon)](https://www.curseforge.com/wow/addons/talent-loadout-manager)
- [LibTalentTree-1.0](https://www.curseforge.com/wow/addons/libtalenttree) — enriched talent tree info library
- [Blizzard FrameXML: Blizzard_ClassTalentImportExport.lua](https://github.com/Gethe/wow-ui-source) — official import/export code
- [Blizzard Forum: Technical info for external talent calculators](https://us.forums.blizzard.com/en/wow/t/technical-information-for-external-talent-calculators/1329690/10)

---

## 8. Notes & Decisions Log

| Date | Decision |
|---|---|
| 2025-02-27 | Project created. Initial research phase — understanding the base talent UI, API, and string format. |
| 2025-02-27 | Decided on hybrid approach: ship pre-bundled builds + enhanced import UX for user's own strings. |
| 2025-02-27 | Will use custom frame-based dropdown (not UIDropDownMenu) to completely avoid taint risk. |
| 2025-02-27 | Addon name: WebLoadouts (working title). |
| 2025-02-27 | Primary sources: Wowhead, Icy Veins, Archon. Secondary: Murlok.io, Subcreation. |
| 2025-02-27 | Phase 1 complete. Built full addon skeleton with all 7 files. Uses Blizzard's own import dialog to avoid taint. |
| 2025-02-27 | Import strategy: primary = open Blizzard dialog pre-filled; fallback = stage via TalentsTab:ImportLoadout(). |
| 2025-02-27 | Menu uses reusable button pool pattern for performance. Click-catcher frame for close-on-click-away. |

---

## 9. Current Status

**Phase:** Phase 1 MVP — COMPLETE
**Next Step:** Phase 2 — Populate Data.lua with real talent strings from Wowhead/Icy Veins/Archon guides. Polish the visual styling. Add Interface Options panel.

### Files Created (Phase 1):
| File | Lines | Purpose |
|---|---|---|
| `WebLoadouts.toc` | 17 | Addon manifest |
| `Core.lua` | ~120 | Bootstrap, events, talent frame hook |
| `Storage.lua` | ~170 | SavedVariables, build CRUD, settings |
| `Data.lua` | ~250 | Bundled builds scaffold, source/content type metadata |
| `ImportExport.lua` | ~170 | String validation, import via Blizzard dialog, clipboard |
| `UI.lua` | ~520 | Main button, custom popup menu, Add Import dialog |
| `Config.lua` | ~160 | Slash commands, help, clear confirmation, settings stub |

---

*This file is maintained by Claude. Last updated: 2025-02-27.*
