# WebLoadouts

A World of Warcraft addon that brings community talent builds from **Wowhead**, **Archon**, and **Icy Veins** directly into your talent loadout dropdown — no more alt-tabbing to copy and paste talent strings.

## What It Does

WebLoadouts hooks into the native talent loadout dropdown (the one you see when you press **N** and click your loadout name). It adds build options from popular community sites right below your existing loadouts, organized by source and hero spec.

**Pick a build. Click apply. Done.**

### Features

- **One-click imports** — Select a community build from the dropdown and it opens Blizzard's import dialog pre-filled, ready to apply
- **Organized by source** — Builds grouped under Wowhead, Archon, and Icy Veins submenus
- **Hero spec grouping** — Within each source, builds are sorted by hero spec (Slayer, Mountain Thane, etc.)
- **All 39 specs covered** — Pre-bundled builds for every class and specialization
- **WebLoadout Tools panel** — Toggle sources on/off, view guide URLs, see last sync time, and clear all loadouts
- **Zero taint** — Uses `Menu.ModifyMenu` and Blizzard's own import dialog, so no addon-action-forbidden errors
- **Tooltips** — Hover over any build to see source, hero spec, content type, and guide URL

## Build Data

Talent build data is sourced from **[wow.xianith.com/webloadouts](https://wow.xianith.com/webloadouts)** and bundled with the addon. Builds are updated with each addon release.

## Installation

1. Download the latest release
2. Extract the `WebLoadouts` folder into your addons directory:
   ```
   World of Warcraft/_retail_/Interface/AddOns/WebLoadouts/
   ```
3. Restart WoW or type `/reload`

## Usage

1. Open your talent window (**N** key)
2. Click the loadout dropdown at the top
3. Scroll down past your loadouts — you'll see **Wowhead**, **Archon**, and **Icy Veins** submenus
4. Hover to expand a source, pick a hero spec, and click a build
5. The import dialog appears pre-filled — name it and click **Apply**

### WebLoadout Tools

Click **WebLoadout Tools** at the bottom of the loadout dropdown to open the tools panel:

- **Toggle Sources** — Enable or disable Wowhead, Archon, or Icy Veins builds
- **Build Sources** — View and copy the guide URLs for your current spec
- **Last Synced** — See when the bundled build data was last updated
- **Clear All Loadouts** — Remove all in-game loadouts for your current spec (active loadout preserved)
