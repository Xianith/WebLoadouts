#!/usr/bin/env python3
"""
WebLoadouts — Companion Build Scraper
Fetches talent build strings from Wowhead, Icy Veins, and Archon,
then writes them into Data.lua for the addon to use in-game.

Usage:
    pip install requests beautifulsoup4 lxml
    pip install playwright && playwright install chromium   # optional, for Icy Veins
    python scrape_builds.py                                 # scrape all specs
    python scrape_builds.py --spec fury-warrior             # scrape one spec
    python scrape_builds.py --source wowhead                # scrape one source
    python scrape_builds.py --list                          # list all specs
    python scrape_builds.py --dry-run                       # print results, don't write

Output:  Data.lua (in the same directory as this script)
"""

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

import requests
from bs4 import BeautifulSoup

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).parent.resolve()
DATA_LUA_PATH = SCRIPT_DIR / "Data.lua"

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/131.0.0.0 Safari/537.36"
)

REQUEST_DELAY = 2.0  # seconds between HTTP requests (be polite)

# Talent strings start with C and are 80-300 chars of base64
TALENT_STRING_RE = re.compile(r'C[A-Za-z0-9+/]{50,300}={0,2}')

# ---------------------------------------------------------------------------
# Spec definitions — maps specID to metadata needed for URL construction
# ---------------------------------------------------------------------------

SPECS = {
    # WARRIOR
    71:   {"class": "warrior",      "spec": "arms",          "role": "dps",    "className": "Warrior",      "specName": "Arms"},
    72:   {"class": "warrior",      "spec": "fury",          "role": "dps",    "className": "Warrior",      "specName": "Fury"},
    73:   {"class": "warrior",      "spec": "protection",    "role": "tank",   "className": "Warrior",      "specName": "Protection"},
    # PALADIN
    65:   {"class": "paladin",      "spec": "holy",          "role": "healer", "className": "Paladin",      "specName": "Holy"},
    66:   {"class": "paladin",      "spec": "protection",    "role": "tank",   "className": "Paladin",      "specName": "Protection"},
    70:   {"class": "paladin",      "spec": "retribution",   "role": "dps",    "className": "Paladin",      "specName": "Retribution"},
    # HUNTER
    253:  {"class": "hunter",       "spec": "beast-mastery",  "role": "dps",   "className": "Hunter",       "specName": "Beast Mastery"},
    254:  {"class": "hunter",       "spec": "marksmanship",   "role": "dps",   "className": "Hunter",       "specName": "Marksmanship"},
    255:  {"class": "hunter",       "spec": "survival",       "role": "dps",   "className": "Hunter",       "specName": "Survival"},
    # ROGUE
    259:  {"class": "rogue",        "spec": "assassination",  "role": "dps",   "className": "Rogue",        "specName": "Assassination"},
    260:  {"class": "rogue",        "spec": "outlaw",         "role": "dps",   "className": "Rogue",        "specName": "Outlaw"},
    261:  {"class": "rogue",        "spec": "subtlety",       "role": "dps",   "className": "Rogue",        "specName": "Subtlety"},
    # PRIEST
    256:  {"class": "priest",       "spec": "discipline",     "role": "healer","className": "Priest",       "specName": "Discipline"},
    257:  {"class": "priest",       "spec": "holy",           "role": "healer","className": "Priest",       "specName": "Holy"},
    258:  {"class": "priest",       "spec": "shadow",         "role": "dps",   "className": "Priest",       "specName": "Shadow"},
    # DEATH KNIGHT
    250:  {"class": "death-knight", "spec": "blood",          "role": "tank",  "className": "Death Knight", "specName": "Blood"},
    251:  {"class": "death-knight", "spec": "frost",          "role": "dps",   "className": "Death Knight", "specName": "Frost"},
    252:  {"class": "death-knight", "spec": "unholy",         "role": "dps",   "className": "Death Knight", "specName": "Unholy"},
    # SHAMAN
    262:  {"class": "shaman",       "spec": "elemental",      "role": "dps",   "className": "Shaman",       "specName": "Elemental"},
    263:  {"class": "shaman",       "spec": "enhancement",    "role": "dps",   "className": "Shaman",       "specName": "Enhancement"},
    264:  {"class": "shaman",       "spec": "restoration",    "role": "healer","className": "Shaman",       "specName": "Restoration"},
    # MAGE
    62:   {"class": "mage",         "spec": "arcane",         "role": "dps",   "className": "Mage",         "specName": "Arcane"},
    63:   {"class": "mage",         "spec": "fire",           "role": "dps",   "className": "Mage",         "specName": "Fire"},
    64:   {"class": "mage",         "spec": "frost",          "role": "dps",   "className": "Mage",         "specName": "Frost"},
    # WARLOCK
    265:  {"class": "warlock",      "spec": "affliction",     "role": "dps",   "className": "Warlock",      "specName": "Affliction"},
    266:  {"class": "warlock",      "spec": "demonology",     "role": "dps",   "className": "Warlock",      "specName": "Demonology"},
    267:  {"class": "warlock",      "spec": "destruction",    "role": "dps",   "className": "Warlock",      "specName": "Destruction"},
    # MONK
    268:  {"class": "monk",         "spec": "brewmaster",     "role": "tank",  "className": "Monk",         "specName": "Brewmaster"},
    269:  {"class": "monk",         "spec": "windwalker",     "role": "dps",   "className": "Monk",         "specName": "Windwalker"},
    270:  {"class": "monk",         "spec": "mistweaver",     "role": "healer","className": "Monk",         "specName": "Mistweaver"},
    # DRUID
    102:  {"class": "druid",        "spec": "balance",        "role": "dps",   "className": "Druid",        "specName": "Balance"},
    103:  {"class": "druid",        "spec": "feral",          "role": "dps",   "className": "Druid",        "specName": "Feral"},
    104:  {"class": "druid",        "spec": "guardian",       "role": "tank",  "className": "Druid",        "specName": "Guardian"},
    105:  {"class": "druid",        "spec": "restoration",    "role": "healer","className": "Druid",        "specName": "Restoration"},
    # DEMON HUNTER
    577:  {"class": "demon-hunter", "spec": "havoc",          "role": "dps",   "className": "Demon Hunter", "specName": "Havoc"},
    581:  {"class": "demon-hunter", "spec": "vengeance",      "role": "tank",  "className": "Demon Hunter", "specName": "Vengeance"},
    # EVOKER
    1467: {"class": "evoker",       "spec": "devastation",    "role": "dps",   "className": "Evoker",       "specName": "Devastation"},
    1468: {"class": "evoker",       "spec": "preservation",   "role": "healer","className": "Evoker",       "specName": "Preservation"},
    1473: {"class": "evoker",       "spec": "augmentation",   "role": "dps",   "className": "Evoker",       "specName": "Augmentation"},
}

# Class comment groupings for Lua output (maps class name -> list of specIDs)
CLASS_GROUPS = [
    ("WARRIOR",      "Arms(71), Fury(72), Prot(73)",                           [71, 72, 73]),
    ("PALADIN",      "Holy(65), Prot(66), Ret(70)",                            [65, 66, 70]),
    ("HUNTER",       "BM(253), MM(254), Surv(255)",                            [253, 254, 255]),
    ("ROGUE",        "Assassin(259), Outlaw(260), Sub(261)",                   [259, 260, 261]),
    ("PRIEST",       "Disc(256), Holy(257), Shadow(258)",                      [256, 257, 258]),
    ("DK",           "Blood(250), Frost(251), Unholy(252)",                    [250, 251, 252]),
    ("SHAMAN",       "Ele(262), Enh(263), Resto(264)",                         [262, 263, 264]),
    ("MAGE",         "Arcane(62), Fire(63), Frost(64)",                        [62, 63, 64]),
    ("WARLOCK",      "Afflic(265), Demo(266), Destro(267)",                    [265, 266, 267]),
    ("MONK",         "BM(268), WW(269), MW(270)",                              [268, 269, 270]),
    ("DRUID",        "Balance(102), Feral(103), Guardian(104), Resto(105)",    [102, 103, 104, 105]),
    ("DH",           "Havoc(577), Vengeance(581)",                             [577, 581]),
    ("EVOKER",       "Devastation(1467), Preservation(1468), Augmentation(1473)", [1467, 1468, 1473]),
]


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

_session = None

def get_session():
    global _session
    if _session is None:
        _session = requests.Session()
        _session.headers.update({
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        })
    return _session


def fetch_page(url, label=""):
    """Fetch a URL with rate limiting and error handling."""
    session = get_session()
    print(f"  Fetching: {url}" + (f" ({label})" if label else ""))
    try:
        resp = session.get(url, timeout=30)
        resp.raise_for_status()
        time.sleep(REQUEST_DELAY)
        return resp.text
    except requests.RequestException as e:
        print(f"  WARNING: Failed to fetch {url}: {e}")
        return None


def looks_like_talent_string(s):
    """Check if a string looks like a valid WoW talent export string.

    Real WoW talent strings have a distinctive pattern:
    - Start with 'C' (version byte)
    - Followed by several characters then a run of 'A's (zero-padded spec/class data)
    - Typically 80-200 characters long
    - Example: CgEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgGDjxMsMzMzM...
    """
    if not s or len(s) < 60 or len(s) > 250:
        return False
    if not s.startswith("C"):
        return False
    # Must be valid base64 chars
    if not re.match(r'^C[A-Za-z0-9+/]{59,248}={0,2}$', s):
        return False
    # Real talent strings always contain a run of consecutive 'A's (the zero-padded header)
    # This filters out random base64 blobs (images, SVG, JSON, etc.)
    if "AAAAAAA" not in s:
        return False
    return True


# ---------------------------------------------------------------------------
# Wowhead scraper
# ---------------------------------------------------------------------------

def wowhead_url(spec_info):
    """Build Wowhead guide URL for a spec."""
    return (
        f"https://www.wowhead.com/guide/classes/"
        f"{spec_info['class']}/{spec_info['spec']}/"
        f"talent-builds-pve-{spec_info['role']}"
    )


def scrape_wowhead(spec_id, spec_info):
    """
    Scrape talent builds from a Wowhead spec guide page.

    Wowhead uses custom BBCode-style markup in their guide HTML:
      - Hero spec headers: [h3]...[color=cN]HeroSpecName[/color][/h3]
      - Row labels: [icon name=...] Single Target ... [copy="Label"]STRING[/copy]
      - The [copy] tags contain the talent import string with a short label.

    We parse positionally: find hero spec headers and [copy] tags in order,
    then combine them into descriptive build names like "Slayer — Raid ST".
    """
    url = wowhead_url(spec_info)
    html = fetch_page(url, f"Wowhead {spec_info['specName']} {spec_info['className']}")
    if not html:
        return []

    builds = []

    # --- Primary strategy: positional parse of hero spec headers + [copy] tags ---
    # Hero spec headers look like: [color=c6]Slayer[\/color]  (note escaped slash)
    hero_pattern = re.compile(r'\[color=c\d\]([A-Za-z][A-Za-z \'-]+)\[\\/color\]')
    # Copy tags look like: [copy=\"Label\"]TALENT_STRING[   (closed by [ for next tag)
    copy_pattern = re.compile(r'\[copy=\\"([^"\\]+)\\"\]([A-Za-z0-9+/=]+)\[')

    # Collect all markers with their positions
    markers = []
    for m in hero_pattern.finditer(html):
        name = m.group(1).strip()
        # Only accept known WoW hero spec names (allowlist approach)
        KNOWN_HERO_SPECS = {
            # Warrior
            "Slayer", "Mountain Thane", "Colossus",
            # Paladin
            "Herald of the Sun", "Lightsmith", "Templar",
            # Hunter
            "Dark Ranger", "Pack Leader", "Sentinel",
            # Rogue
            "Deathstalker", "Fatebound", "Trickster",
            # Priest
            "Archon", "Oracle", "Voidweaver",
            # Death Knight
            "Deathbringer", "Rider of the Apocalypse", "San'layn",
            # Shaman
            "Farseer", "Stormbringer", "Totemic",
            # Mage
            "Frostfire", "Spellslinger", "Sunfury",
            # Warlock
            "Diabolist", "Hellcaller", "Soul Harvester",
            # Monk
            "Conduit of the Celestials", "Master of Harmony", "Shado-Pan",
            # Druid
            "Druid of the Claw", "Elune's Chosen", "Keeper of the Grove", "Wildstalker",
            # Demon Hunter
            "Aldrachi Reaver", "Fel-Scarred",
            # Evoker
            "Chronowarden", "Flameshaper", "Scalecommander",
        }
        if name in KNOWN_HERO_SPECS:
            markers.append(("hero", m.start(), name))
    for m in copy_pattern.finditer(html):
        talent_str = m.group(2)
        if looks_like_talent_string(talent_str):
            markers.append(("copy", m.start(), m.group(1), talent_str))

    markers.sort(key=lambda x: x[1])

    # Walk through markers to associate hero spec with builds
    current_hero = ""
    for marker in markers:
        if marker[0] == "hero":
            current_hero = marker[2]
        elif marker[0] == "copy":
            label = marker[2]    # e.g., "Raid ST", "Mythic+", "Delving"
            talent_str = marker[3]
            # Skip duplicates
            if not any(b["talentString"] == talent_str for b in builds):
                builds.append({
                    "name": label,
                    "talentString": talent_str,
                    "source": "wowhead",
                    "contentType": guess_content_type(label),
                    "heroSpec": current_hero,
                    "notes": "",
                })

    # --- Fallback: data-export-string attributes ---
    if not builds:
        soup = BeautifulSoup(html, "lxml")
        for el in soup.select("[data-export-string]"):
            talent_str = el.get("data-export-string", "")
            name = el.get("data-name", "") or el.get_text(strip=True)
            if looks_like_talent_string(talent_str):
                if not any(b["talentString"] == talent_str for b in builds):
                    builds.append({
                        "name": name or f"Build {len(builds)+1}",
                        "talentString": talent_str,
                        "source": "wowhead",
                        "contentType": guess_content_type(name),
                        "heroSpec": "",
                        "notes": "",
                    })

    # --- Fallback: brute-force regex ---
    if not builds:
        for match in TALENT_STRING_RE.finditer(html):
            talent_str = match.group(0)
            if looks_like_talent_string(talent_str):
                if not any(b["talentString"] == talent_str for b in builds):
                    builds.append({
                        "name": f"Build {len(builds)+1}",
                        "talentString": talent_str,
                        "source": "wowhead",
                        "contentType": "general",
                        "heroSpec": "",
                        "notes": "",
                    })

    return builds


# ---------------------------------------------------------------------------
# Archon scraper
# ---------------------------------------------------------------------------

def archon_urls(spec_info):
    """Build Archon URLs for a spec (one for M+, one for Raid)."""
    base = f"https://www.archon.gg/wow/builds/{spec_info['spec']}/{spec_info['class']}"
    return [
        (f"{base}/mythic-plus/talents/10/all-dungeons/this-week", "mythicplus"),
        (f"{base}/raid/talents/mythic/all-bosses/this-week",      "raid"),
    ]


def scrape_archon(spec_id, spec_info):
    """
    Scrape talent builds from Archon.

    Archon is a Next.js app that embeds talent strings as Wowhead links:
    href="wowhead.com/talent-calc/blizzard/STRING"
    """
    builds = []

    for url, content_type in archon_urls(spec_info):
        html = fetch_page(url, f"Archon {spec_info['specName']} {spec_info['className']} {content_type}")
        if not html:
            continue

        # Look for talent strings in Wowhead talent-calc links
        calc_pattern = re.compile(
            r'(?:href|data-href|content)=["\']'
            r'(?:https?://)?(?:www\.)?wowhead\.com/talent-calc/blizzard/'
            r'(C[A-Za-z0-9+/]{50,300}={0,2})["\']'
        )
        found_strings = []
        for match in calc_pattern.finditer(html):
            talent_str = match.group(1)
            if looks_like_talent_string(talent_str) and talent_str not in found_strings:
                found_strings.append(talent_str)

        # Also try bare talent string patterns in JSON data (Next.js embeds data in script tags)
        if not found_strings:
            for match in TALENT_STRING_RE.finditer(html):
                talent_str = match.group(0)
                if looks_like_talent_string(talent_str) and talent_str not in found_strings:
                    found_strings.append(talent_str)

        # Try to find build names from the page
        soup = BeautifulSoup(html, "lxml")
        type_label = "Mythic+" if content_type == "mythicplus" else "Raid"

        for i, talent_str in enumerate(found_strings):
            name = f"{type_label} Build" if i == 0 else f"{type_label} Build {i+1}"

            # Skip duplicates across content types
            if not any(b["talentString"] == talent_str for b in builds):
                builds.append({
                    "name": name,
                    "source": "archon",
                    "contentType": content_type,
                    "heroSpec": "",
                    "talentString": talent_str,
                    "notes": "",
                })

    return builds


# ---------------------------------------------------------------------------
# Icy Veins scraper
# ---------------------------------------------------------------------------

def icyveins_url(spec_info):
    """Build Icy Veins spec builds URL."""
    return (
        f"https://www.icy-veins.com/wow/"
        f"{spec_info['spec']}-{spec_info['class']}-pve-"
        f"{spec_info['role']}-spec-builds-talents"
    )


def scrape_icyveins_requests(spec_id, spec_info):
    """
    Try to scrape Icy Veins with plain HTTP requests.
    Icy Veins renders talent strings client-side, so this often returns nothing.
    Falls back to looking for strings in inline script data.
    """
    url = icyveins_url(spec_info)
    html = fetch_page(url, f"Icy Veins {spec_info['specName']} {spec_info['className']}")
    if not html:
        return []

    builds = []

    # Look for talent strings in script tags (sometimes SSR'd or in __NEXT_DATA__)
    for match in TALENT_STRING_RE.finditer(html):
        talent_str = match.group(0)
        if looks_like_talent_string(talent_str):
            if not any(b["talentString"] == talent_str for b in builds):
                builds.append({
                    "name": f"Build {len(builds)+1}",
                    "source": "icyveins",
                    "contentType": "general",
                    "heroSpec": "",
                    "talentString": talent_str,
                    "notes": "",
                })

    # Also check for data attributes
    soup = BeautifulSoup(html, "lxml")
    for el in soup.select("[data-talent-string], [data-export-string], .export-string__code"):
        talent_str = (
            el.get("data-talent-string")
            or el.get("data-export-string")
            or el.get_text(strip=True)
        )
        if looks_like_talent_string(talent_str):
            if not any(b["talentString"] == talent_str for b in builds):
                builds.append({
                    "name": f"Build {len(builds)+1}",
                    "source": "icyveins",
                    "contentType": "general",
                    "heroSpec": "",
                    "talentString": talent_str,
                    "notes": "",
                })

    return builds


def scrape_icyveins_playwright(spec_id, spec_info):
    """
    Scrape Icy Veins using Playwright (headless browser) to handle
    client-side rendering. Requires: pip install playwright && playwright install chromium
    """
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("  WARNING: playwright not installed. Skipping Icy Veins headless scrape.")
        print("           Install with: pip install playwright && playwright install chromium")
        return []

    url = icyveins_url(spec_info)
    print(f"  Fetching (headless): {url} (Icy Veins {spec_info['specName']} {spec_info['className']})")

    builds = []
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page(user_agent=USER_AGENT)
            page.goto(url, timeout=60000, wait_until="domcontentloaded")

            # Wait for talent content to render
            page.wait_for_timeout(3000)

            # Look for export string elements
            elements = page.query_selector_all(".export-string__code, [data-export-string], [data-talent-string]")
            for el in elements:
                talent_str = (
                    el.get_attribute("data-export-string")
                    or el.get_attribute("data-talent-string")
                    or el.inner_text()
                )
                if talent_str:
                    talent_str = talent_str.strip()
                    if looks_like_talent_string(talent_str):
                        if not any(b["talentString"] == talent_str for b in builds):
                            builds.append({
                                "name": f"Build {len(builds)+1}",
                                "source": "icyveins",
                                "contentType": "general",
                                "talentString": talent_str,
                                "notes": "",
                            })

            # Also look for copy buttons / talent string containers
            copy_buttons = page.query_selector_all("button[data-clipboard-text], [onclick*='copy']")
            for btn in copy_buttons:
                talent_str = btn.get_attribute("data-clipboard-text") or ""
                if looks_like_talent_string(talent_str.strip()):
                    talent_str = talent_str.strip()
                    if not any(b["talentString"] == talent_str for b in builds):
                        builds.append({
                            "name": f"Build {len(builds)+1}",
                            "source": "icyveins",
                            "contentType": "general",
                            "talentString": talent_str,
                            "notes": "",
                        })

            # Brute force: get all page text and search for talent strings
            if not builds:
                page_html = page.content()
                for match in TALENT_STRING_RE.finditer(page_html):
                    talent_str = match.group(0)
                    if looks_like_talent_string(talent_str):
                        if not any(b["talentString"] == talent_str for b in builds):
                            builds.append({
                                "name": f"Build {len(builds)+1}",
                                "source": "icyveins",
                                "contentType": "general",
                                "talentString": talent_str,
                                "notes": "",
                            })

            browser.close()

    except Exception as e:
        print(f"  WARNING: Playwright scrape failed: {e}")

    time.sleep(REQUEST_DELAY)
    return builds


def scrape_icyveins(spec_id, spec_info):
    """Try plain HTTP first, fall back to Playwright if no results."""
    builds = scrape_icyveins_requests(spec_id, spec_info)
    if not builds:
        builds = scrape_icyveins_playwright(spec_id, spec_info)
    return builds


# ---------------------------------------------------------------------------
# Content type guesser
# ---------------------------------------------------------------------------

def guess_content_type(name):
    """Guess content type from build name."""
    name_lower = name.lower()
    # Wowhead uses "Raid ST", "ST Raid", "Raid MT", "MT Raid", "Multitarget"
    if any(kw in name_lower for kw in ["raid", "single target", "single-target", " st", "st ",
                                         "multitarget", "multi-target", " mt", "mt "]):
        return "raid"
    if any(kw in name_lower for kw in ["mythic", "m+", "aoe", "dungeon", "keys"]):
        return "mythicplus"
    if any(kw in name_lower for kw in ["pvp", "arena", "battleground", "bg"]):
        return "pvp"
    if any(kw in name_lower for kw in ["level", "leveling"]):
        return "leveling"
    if any(kw in name_lower for kw in ["delve", "delving", "open world"]):
        return "delves"
    return "general"


# ---------------------------------------------------------------------------
# Data.lua writer
# ---------------------------------------------------------------------------

def escape_lua_string(s):
    """Escape a string for Lua double-quoted string literal."""
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def write_data_lua(all_builds, output_path):
    """
    Write the complete Data.lua file with scraped builds.
    Preserves the static parts (SourceInfo, ContentTypeInfo, ClassInfo)
    and replaces BundledBuilds with fresh data.
    """
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")

    lines = []
    lines.append("----------------------------------------------------------------------")
    lines.append("-- WebLoadouts -- Data.lua")
    lines.append("-- Pre-bundled talent builds from popular community websites.")
    lines.append(f"-- Auto-generated by scrape_builds.py on {timestamp}")
    lines.append("-- Organized by specID.")
    lines.append("----------------------------------------------------------------------")
    lines.append("")
    lines.append("local ADDON_NAME, WL = ...")
    lines.append("")
    lines.append(f'WL.DataLastSynced = "{timestamp}"')
    lines.append("")

    # SourceInfo
    lines.append("-- Source display info (name, color, icon texture)")
    lines.append("WL.SourceInfo = {")
    lines.append('    wowhead = {')
    lines.append('        name  = "Wowhead",')
    lines.append('        color = "|cffff8040",')
    lines.append('        icon  = "Interface\\\\Icons\\\\INV_Misc_Book_09",')
    lines.append('        url   = "wowhead.com",')
    lines.append('    },')
    lines.append('    icyveins = {')
    lines.append('        name  = "Icy Veins",')
    lines.append('        color = "|cff42a5f5",')
    lines.append('        icon  = "Interface\\\\Icons\\\\Spell_Frost_FrostBolt02",')
    lines.append('        url   = "icy-veins.com",')
    lines.append('    },')
    lines.append('    archon = {')
    lines.append('        name  = "Archon",')
    lines.append('        color = "|cff66bb6a",')
    lines.append('        icon  = "Interface\\\\Icons\\\\Achievement_Arena_5v5_4",')
    lines.append('        url   = "archon.gg",')
    lines.append('    },')
    lines.append('    manual = {')
    lines.append('        name  = "My Imports",')
    lines.append('        color = "|cffaaaaaa",')
    lines.append('        icon  = "Interface\\\\Icons\\\\INV_Scroll_11",')
    lines.append('        url   = nil,')
    lines.append('    },')
    lines.append("}")
    lines.append("")

    # ContentTypeInfo
    lines.append("-- Content type display info")
    lines.append("WL.ContentTypeInfo = {")
    lines.append('    raid       = { name = "Raid",       shortName = "Raid",  icon = "Interface\\\\Icons\\\\Achievement_Dungeon_ClassicDungeonMaster" },')
    lines.append('    mythicplus = { name = "Mythic+",    shortName = "M+",    icon = "Interface\\\\Icons\\\\INV_Relics_Hourglass" },')
    lines.append('    pvp        = { name = "PvP",        shortName = "PvP",   icon = "Interface\\\\Icons\\\\Achievement_PVP_A_A" },')
    lines.append('    leveling   = { name = "Leveling",   shortName = "Lvl",   icon = "Interface\\\\Icons\\\\Achievement_Level_10" },')
    lines.append('    delves     = { name = "Delves",     shortName = "Delve", icon = "Interface\\\\Icons\\\\INV_Misc_Key_15" },')
    lines.append('    general    = { name = "General",    shortName = "Gen",   icon = "Interface\\\\Icons\\\\INV_Misc_QuestionMark" },')
    lines.append("}")
    lines.append("")

    # ClassInfo
    lines.append("-- Class info for display")
    lines.append("WL.ClassInfo = {")
    class_info = [
        (1,  "Warrior",      "WARRIOR",     "c79c6e"),
        (2,  "Paladin",      "PALADIN",     "f58cba"),
        (3,  "Hunter",       "HUNTER",      "abd473"),
        (4,  "Rogue",        "ROGUE",       "fff569"),
        (5,  "Priest",       "PRIEST",      "ffffff"),
        (6,  "Death Knight", "DEATHKNIGHT", "c41f3b"),
        (7,  "Shaman",       "SHAMAN",      "0070de"),
        (8,  "Mage",         "MAGE",        "69ccf0"),
        (9,  "Warlock",      "WARLOCK",     "9482c9"),
        (10, "Monk",         "MONK",        "00ff96"),
        (11, "Druid",        "DRUID",       "ff7d0a"),
        (12, "Demon Hunter", "DEMONHUNTER", "a330c9"),
        (13, "Evoker",       "EVOKER",      "33937f"),
    ]
    for cid, name, file, color in class_info:
        lines.append(f'    [{cid}]  = {{ name = "{name}", {" " * (14-len(name))}file = "{file}", {" " * (13-len(file))}color = "|cff{color}" }},')
    lines.append("}")
    lines.append("")

    # BundledBuilds
    lines.append("----------------------------------------------------------------------")
    lines.append("-- Bundled Builds -- Key = specID")
    lines.append(f"-- Scraped from Wowhead, Icy Veins, Archon on {timestamp}")
    lines.append("----------------------------------------------------------------------")
    lines.append("")
    lines.append("WL.BundledBuilds = {")

    for class_name, spec_list, spec_ids in CLASS_GROUPS:
        lines.append(f"    -- {class_name}: {spec_list}")
        for spec_id in spec_ids:
            builds = all_builds.get(spec_id, [])
            if not builds:
                lines.append(f"    [{spec_id}] = {{}},")
            else:
                lines.append(f"    [{spec_id}] = {{")
                for build in builds:
                    name = escape_lua_string(build["name"])
                    source = escape_lua_string(build["source"])
                    ct = escape_lua_string(build["contentType"])
                    hero = escape_lua_string(build.get("heroSpec", ""))
                    ts = escape_lua_string(build["talentString"])
                    notes = escape_lua_string(build.get("notes", ""))
                    lines.append(f'        {{ name = "{name}", source = "{source}", contentType = "{ct}", heroSpec = "{hero}", talentString = "{ts}", notes = "{notes}" }},')
                lines.append("    },")
        lines.append("")

    lines.append("}")
    lines.append("")

    # Data access helpers
    lines.append("----------------------------------------------------------------------")
    lines.append("-- Data access helpers")
    lines.append("----------------------------------------------------------------------")
    lines.append("")
    lines.append("function WL:GetBundledBuilds(specID, source)")
    lines.append("    local builds = self.BundledBuilds[specID]")
    lines.append('    if not builds then return {} end')
    lines.append("")
    lines.append("    local results = {}")
    lines.append("    for _, b in ipairs(builds) do")
    lines.append('        if b.talentString and b.talentString ~= "" then')
    lines.append("            if not source or b.source == source then")
    lines.append("                table.insert(results, b)")
    lines.append("            end")
    lines.append("        end")
    lines.append("    end")
    lines.append("    return results")
    lines.append("end")
    lines.append("")
    lines.append("function WL:GetAllBuildsForCurrentSpec()")
    lines.append("    local specID = self:GetPlayerSpecID()")
    lines.append("    if not specID then return {} end")
    lines.append("")
    lines.append("    local bySource = {}")
    lines.append("")
    lines.append("    -- Bundled builds")
    lines.append("    local bundled = self.BundledBuilds[specID] or {}")
    lines.append("    for _, build in ipairs(bundled) do")
    lines.append('        if build.talentString and build.talentString ~= "" then')
    lines.append('            local src = build.source or "wowhead"')
    lines.append("            if not bySource[src] then bySource[src] = {} end")
    lines.append("            table.insert(bySource[src], {")
    lines.append("                name          = build.name,")
    lines.append("                talentString  = build.talentString,")
    lines.append("                contentType   = build.contentType,")
    lines.append('                heroSpec      = build.heroSpec or "",')
    lines.append("                notes         = build.notes,")
    lines.append("                isBundled     = true,")
    lines.append("            })")
    lines.append("        end")
    lines.append("    end")
    lines.append("")
    lines.append("    -- User builds for this spec")
    lines.append("    local userBuilds = self:GetBuilds(specID)")
    lines.append("    for _, entry in ipairs(userBuilds) do")
    lines.append('        local src = entry.build.source or "manual"')
    lines.append("        if not bySource[src] then bySource[src] = {} end")
    lines.append("        table.insert(bySource[src], {")
    lines.append("            id            = entry.id,")
    lines.append("            name          = entry.build.name,")
    lines.append("            talentString  = entry.build.talentString,")
    lines.append("            contentType   = entry.build.contentType,")
    lines.append('            heroSpec      = entry.build.heroSpec or "",')
    lines.append("            notes         = entry.build.notes,")
    lines.append("            isBundled     = false,")
    lines.append("        })")
    lines.append("    end")
    lines.append("")
    lines.append("    return bySource")
    lines.append("end")
    lines.append("")

    content = "\n".join(lines)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"\nWrote {output_path} ({len(content)} bytes)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def parse_spec_filter(spec_filter):
    """Parse a --spec argument like 'fury-warrior' into a list of specIDs."""
    if not spec_filter:
        return list(SPECS.keys())

    spec_filter = spec_filter.lower().strip()
    matches = []
    for spec_id, info in SPECS.items():
        slug = f"{info['spec']}-{info['class']}"
        if spec_filter in slug or spec_filter == info["spec"] or spec_filter == info["class"]:
            matches.append(spec_id)

    if not matches:
        print(f"ERROR: No spec matches '{spec_filter}'.")
        print("Use --list to see all available specs.")
        sys.exit(1)

    return matches


def list_specs():
    """Print all available specs."""
    print("Available specs:")
    for class_name, spec_list, spec_ids in CLASS_GROUPS:
        print(f"\n  {class_name}:")
        for spec_id in spec_ids:
            info = SPECS[spec_id]
            slug = f"{info['spec']}-{info['class']}"
            print(f"    [{spec_id:>4}] {slug:<30} ({info['specName']} {info['className']}, {info['role']})")


def main():
    global REQUEST_DELAY
    parser = argparse.ArgumentParser(
        description="WebLoadouts companion scraper — fetch talent builds from community websites."
    )
    parser.add_argument("--spec", type=str, default=None,
                        help="Scrape only this spec (e.g., 'fury-warrior', 'frost', 'death-knight')")
    parser.add_argument("--source", type=str, default=None, choices=["wowhead", "icyveins", "archon"],
                        help="Scrape only this source")
    parser.add_argument("--output", type=str, default=str(DATA_LUA_PATH),
                        help=f"Output path (default: {DATA_LUA_PATH})")
    parser.add_argument("--list", action="store_true",
                        help="List all available specs and exit")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print results to stdout instead of writing Data.lua")
    parser.add_argument("--delay", type=float, default=REQUEST_DELAY,
                        help=f"Delay between requests in seconds (default: {REQUEST_DELAY})")
    args = parser.parse_args()

    if args.list:
        list_specs()
        return

    REQUEST_DELAY = args.delay

    spec_ids = parse_spec_filter(args.spec)
    sources = [args.source] if args.source else ["wowhead", "archon", "icyveins"]

    print(f"WebLoadouts Build Scraper")
    print(f"========================")
    print(f"Specs:   {len(spec_ids)} spec(s)")
    print(f"Sources: {', '.join(sources)}")
    print(f"Output:  {args.output}")
    print()

    # Collect all builds keyed by specID
    all_builds = {}
    total_found = 0

    for spec_id in spec_ids:
        info = SPECS[spec_id]
        label = f"{info['specName']} {info['className']}"
        print(f"\n--- {label} (specID {spec_id}) ---")

        spec_builds = []

        if "wowhead" in sources:
            builds = scrape_wowhead(spec_id, info)
            print(f"  Wowhead: found {len(builds)} build(s)")
            spec_builds.extend(builds)

        if "archon" in sources:
            builds = scrape_archon(spec_id, info)
            print(f"  Archon:  found {len(builds)} build(s)")
            spec_builds.extend(builds)

        if "icyveins" in sources:
            builds = scrape_icyveins(spec_id, info)
            print(f"  Icy Veins: found {len(builds)} build(s)")
            spec_builds.extend(builds)

        # Deduplicate by talent string
        seen = set()
        deduped = []
        for build in spec_builds:
            if build["talentString"] not in seen:
                seen.add(build["talentString"])
                deduped.append(build)
        spec_builds = deduped

        all_builds[spec_id] = spec_builds
        total_found += len(spec_builds)
        print(f"  Total unique: {len(spec_builds)}")

    print(f"\n{'='*50}")
    print(f"Total builds found: {total_found} across {len(spec_ids)} spec(s)")

    if args.dry_run:
        print("\n--- DRY RUN: Results ---")
        for spec_id, builds in sorted(all_builds.items()):
            if builds:
                info = SPECS[spec_id]
                print(f"\n[{spec_id}] {info['specName']} {info['className']}:")
                for b in builds:
                    print(f"  {b['source']:>10} | {b['contentType']:<12} | {b['name']}")
                    print(f"             {b['talentString'][:60]}...")
    else:
        # When scraping a subset, merge with existing data
        if args.spec or args.source:
            # Read existing builds from all_builds structure (fill in missing specs)
            for spec_id in SPECS:
                if spec_id not in all_builds:
                    all_builds[spec_id] = []

        write_data_lua(all_builds, args.output)

    print("\nDone!")


if __name__ == "__main__":
    main()
