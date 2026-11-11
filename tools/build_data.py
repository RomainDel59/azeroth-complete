"""Builds the generated data files of Azeroth Complete (AzerothComplete/Data/*.lua).

Two sources are combined:

* QuestieDB (GPL-3.0, https://github.com/Questie/QuestieDB): quest structure (zones, levels,
  prerequisites, chains), quest givers and recipe sources. Only identifiers and numbers are kept,
  plus English names used as a last resort when the client cannot provide a text.
* The game client tables of the targeted WoW Forever build, as published by wago.tools:
  recipes, instances, encounters and collectible identifiers, and the localized strings the
  client API does not expose.

Usage:
    python -I tools/build_data.py [--build 1.60.1.70888] [--cache DIR] [--questiedb DIR]

Downloads are cached; delete the cache directory to refresh them.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import platform
import shutil
import subprocess
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "AzerothComplete" / "Data"
DEFAULT_BUILD = "1.60.1.70888"
LOCALES = ("enUS", "frFR")
QUESTIEDB_REPO = "https://github.com/Questie/QuestieDB.git"
WAGO_URL = "https://wago.tools/db2/{table}/csv?build={build}{locale}"

# Client tables read by the builder. Localized tables are also fetched for every locale.
TABLES = ("QuestV2", "AreaTable", "Map", "LoadingScreens", "ChrRaces", "ChrClasses", "QuestSort",
          "SkillLine", "SkillLineAbility", "SpellReagents", "SpellEffect", "ItemEffect",
          "ItemXItemEffect", "DungeonEncounter", "Mount", "BattlePetSpecies", "Toy",
          "TransmogSet", "CharTitles")
LOCALIZED_TABLES = ("AreaTable", "QuestSort", "SkillLine", "DungeonEncounter", "Toy")

# Quest flags (cmangos quest_template conventions used by QuestieDB).
QUEST_FLAG_DAILY = 0x1000
QUEST_FLAG_WEEKLY = 0x8000
SPECIAL_FLAG_REPEATABLE = 0x1
SPECIAL_FLAG_EVENT = 0x2

# Flags written into the generated quest rows; keep in sync with Core/Constants.lua.
FLAG_REPEATABLE = 1
FLAG_DAILY = 2
FLAG_WEEKLY = 4
FLAG_EVENT = 8
FLAG_BREADCRUMB = 16

# Spell effects.
EFFECT_CREATE_ITEM = "24"
EFFECT_LEARN_SPELL = "36"

# Skill line categories: 11 = professions, 9 = secondary skills (only the crafting ones are kept).
SECONDARY_PROFESSIONS = {129: "secondary", 185: "secondary", 356: "secondary"}
GATHERING_PROFESSIONS = {182, 186, 393}

# Map instance types.
INSTANCE_DUNGEON = 1
INSTANCE_RAID = 2
INSTANCE_PVP = 3

# Continent groups of the quest zones; keep in sync with Core/Constants.lua.
CONTINENT_EASTERN_KINGDOMS = 0
CONTINENT_KALIMDOR = 1
CONTINENT_BATTLEGROUNDS = 2
CONTINENT_OTHER = 3
TRANSIT_EASTERN_KINGDOMS = {369}

# Name markers of client rows that are not real content.
JUNK_MARKERS = ("[DEPRECATED]", "<UNUSED>", "<NYI>", "<TXT>", "<TEST>", "[PH]", "<DO NOT USE>",
                "REUSE", "[DNT]", "UNUSED", "DEPRECATED", "<CHANGE TO GOSSIP>", "ZZOLD", "zzOLD",
                "Test ", "TEST ", "nothing to see here", "<unused>")

MAX_SOURCES_PER_KIND = 6


def log(message: str) -> None:
    print(f"[build_data] {message}", flush=True)


# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

def download(url: str, target: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "azeroth-complete-build/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response, open(target, "wb") as out:
        shutil.copyfileobj(response, out)


def fetch_tables(cache: Path, build: str) -> None:
    cache.mkdir(parents=True, exist_ok=True)
    wanted = [(t, None) for t in TABLES] + [(t, loc) for t in LOCALIZED_TABLES for loc in LOCALES]
    for table, locale in wanted:
        target = cache / (f"{table}.{locale}.csv" if locale else f"{table}.csv")
        if target.exists() and target.stat().st_size > 0:
            continue
        log(f"downloading {target.name}")
        download(WAGO_URL.format(table=table, build=build, locale=f"&locale={locale}" if locale else ""), target)


def read_table(cache: Path, table: str, locale: str | None = None) -> list[dict[str, str]]:
    path = cache / (f"{table}.{locale}.csv" if locale else f"{table}.csv")
    with open(path, encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def questie_lua(questiedb: Path) -> Path:
    binaries = questiedb / "tools" / "lua-binary"
    if platform.system() == "Windows":
        return binaries / "lua.exe"
    return binaries / "linux-x64" / "lua"


def load_questie(questiedb: Path, cache: Path) -> dict:
    if not questiedb.exists():
        log(f"cloning QuestieDB into {questiedb}")
        subprocess.run(["git", "clone", "--depth", "1", QUESTIEDB_REPO, str(questiedb)], check=True)
    lua = questie_lua(questiedb)
    log("exporting the combined Forever databases")
    subprocess.run([str(lua), "tools/export-forever.lua", "--include-authored"], cwd=questiedb, check=True)
    dump = cache / "questie.json"
    subprocess.run([str(lua), str(ROOT / "tools" / "questie_dump.lua"), str(questiedb), str(dump)], check=True)
    with open(dump, encoding="utf-8") as handle:
        return json.load(handle)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def to_int(value, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def is_junk(name: str | None) -> bool:
    if not name:
        return True
    return any(marker.lower() in name.lower() for marker in JUNK_MARKERS)


def lua_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "")
    return f'"{escaped}"'


def lua_value(value) -> str:
    """Serializes numbers, strings, lists (arrays) and dicts (keyed tables) as compact Lua."""
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(round(value, 2))
    if isinstance(value, str):
        return lua_string(value)
    if isinstance(value, (list, tuple)):
        # Trailing nils are dropped; inner nils stay positional.
        items = list(value)
        while items and items[-1] is None:
            items.pop()
        return "{" + ",".join(lua_value(v) for v in items) + "}"
    if isinstance(value, dict):
        parts = []
        for key in sorted(value, key=lambda k: (isinstance(k, str), k)):
            if isinstance(key, int):
                parts.append(f"[{key}]={lua_value(value[key])}")
            elif key.isidentifier():
                parts.append(f"{key}={lua_value(value[key])}")
            else:
                parts.append(f"[{lua_string(key)}]={lua_value(value[key])}")
        return "{" + ",".join(parts) + "}"
    raise TypeError(f"cannot serialize {type(value)}")


def write_lua(name: str, header: str, assignments: list[tuple[str, object]], build: str) -> None:
    """Writes one data file; each assignment becomes `ns.Data.<key> = <value>`, one row per line for maps."""
    lines = [
        "-- Generated by tools/build_data.py. Do not edit by hand.",
        f"-- Client build: {build}.",
        f"-- {header}",
        "local _, ns = ...",
        "ns.Data = ns.Data or {}",
        "",
    ]
    for key, value in assignments:
        if isinstance(value, dict) and value and all(isinstance(k, int) for k in value):
            lines.append(f"ns.Data.{key} = {{")
            for row_key in sorted(value):
                lines.append(f"[{row_key}]={lua_value(value[row_key])},")
            lines.append("}")
        else:
            lines.append(f"ns.Data.{key} = {lua_value(value)}")
    (DATA_DIR / name).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    log(f"wrote Data/{name}")


# ---------------------------------------------------------------------------
# Game world
# ---------------------------------------------------------------------------

class World:
    """Areas, maps and instances of the client, used to place quests."""

    def __init__(self, cache: Path, questie: dict):
        self.areas = {to_int(r["ID"]): r for r in read_table(cache, "AreaTable")}
        self.maps = {to_int(r["ID"]): r for r in read_table(cache, "Map")}
        self.loading = {to_int(r["ID"]): r for r in read_table(cache, "LoadingScreens")}
        self.sub_to_parent = {to_int(k): to_int(v) for k, v in questie["subZoneToParent"].items()}
        self.area_to_ui_map = {to_int(k): to_int(v) for k, v in questie["areaToUiMap"].items()}
        # Instance maps own an area; QuestieDB lists alternative areas used by dungeon quests.
        self.area_to_instance = {}
        for map_id, row in self.maps.items():
            if to_int(row["InstanceType"]) in (INSTANCE_DUNGEON, INSTANCE_RAID) and to_int(row["AreaTableID"]):
                self.area_to_instance[to_int(row["AreaTableID"])] = map_id
        for area, alternatives in questie.get("dungeonAreas", {}).items():
            instance = self.area_to_instance.get(to_int(area))
            if instance:
                for alternative in alternatives:
                    self.area_to_instance.setdefault(to_int(alternative), instance)

    def instance_of(self, area_id: int) -> int | None:
        """Returns the instance map that owns an area, climbing through its parents."""
        seen = set()
        current = area_id
        while current and current not in seen:
            seen.add(current)
            if current in self.area_to_instance:
                return self.area_to_instance[current]
            map_id = self.map_of(current)
            if self.instance_type(map_id) in (INSTANCE_DUNGEON, INSTANCE_RAID):
                return map_id
            parent = self.sub_to_parent.get(current)
            if not parent:
                row = self.areas.get(current)
                parent = to_int(row["ParentAreaID"]) if row else 0
            current = parent
        return None

    def continent_of(self, area_id: int) -> int:
        """Continent group of a zone: 0 = Eastern Kingdoms, 1 = Kalimdor, 2 = battlegrounds, 3 = other lands."""
        map_id = self.map_of(area_id)
        if map_id in (0, 1):
            return map_id
        kind = self.instance_type(map_id)
        if kind == INSTANCE_PVP:
            return CONTINENT_BATTLEGROUNDS
        row = self.maps.get(map_id)
        parent = to_int(row["ParentMapID"], -1) if row else -1
        if parent in (0, 1):
            return parent
        # Transit maps (the Deeprun Tram) belong to the continent their entrance is on.
        return CONTINENT_EASTERN_KINGDOMS if map_id in TRANSIT_EASTERN_KINGDOMS else CONTINENT_OTHER

    def top_area(self, area_id: int) -> int:
        """Climbs from a sub-zone to the zone that owns it."""
        seen = set()
        current = area_id
        while current not in seen:
            seen.add(current)
            parent = self.sub_to_parent.get(current)
            if not parent:
                row = self.areas.get(current)
                parent = to_int(row["ParentAreaID"]) if row else 0
            if not parent or parent == current:
                return current
            current = parent
        return current

    def map_of(self, area_id: int) -> int | None:
        row = self.areas.get(area_id)
        return to_int(row["ContinentID"]) if row else None

    def instance_type(self, map_id: int | None) -> int:
        row = self.maps.get(map_id) if map_id is not None else None
        return to_int(row["InstanceType"]) if row else 0

    def loading_screen(self, map_id: int) -> int:
        row = self.maps.get(map_id)
        screen = self.loading.get(to_int(row["LoadingScreenID"])) if row else None
        if not screen:
            return 0
        for column in ("MainImageFileDataID", "WideScreen169FileDataID", "WideScreenFileDataID", "NarrowScreenFileDataID"):
            if to_int(screen.get(column)):
                return to_int(screen[column])
        return 0


# ---------------------------------------------------------------------------
# Quests
# ---------------------------------------------------------------------------

def quest_flags(q: dict) -> int:
    flags = 0
    special = to_int(q.get("specialFlags"))
    quest = to_int(q.get("questFlags"))
    if special & SPECIAL_FLAG_REPEATABLE:
        flags |= FLAG_REPEATABLE
    if quest & QUEST_FLAG_DAILY:
        flags |= FLAG_DAILY
    if quest & QUEST_FLAG_WEEKLY:
        flags |= FLAG_WEEKLY
    if special & SPECIAL_FLAG_EVENT:
        flags |= FLAG_EVENT
    if q.get("breadcrumbForQuestId"):
        flags |= FLAG_BREADCRUMB
    return flags


def first_of(entries, index: int) -> int | None:
    """startedBy/finishedBy hold {npcs, objects, items}; returns the first id of one kind."""
    if not isinstance(entries, list) or len(entries) <= index:
        return None
    group = entries[index]
    if isinstance(group, list) and group:
        return to_int(group[0])
    return None


def giver_of(entries) -> list | None:
    """Encodes the first giver as {kind, id}: 1 = NPC, 2 = object, 3 = item."""
    for index, kind in ((0, 1), (1, 2), (2, 3)):
        found = first_of(entries, index)
        if found:
            return [kind, found]
    return None


def build_quests(world: World, questie: dict, valid_ids: set[int]) -> tuple[dict, dict, dict, dict]:
    """Returns (quests, zones, instance quests, referenced entities)."""
    npcs, objects = questie["npcs"], questie["objects"]
    quests: dict[int, list] = {}
    placement: dict[int, tuple[str, int]] = {}  # quest -> ("zone", areaId) | ("sort", sortId) | ("instance", mapId)
    skipped = defaultdict(int)

    for key, q in questie["quests"].items():
        quest_id = to_int(key)
        if quest_id not in valid_ids:
            skipped["absent from the client"] += 1
            continue
        if is_junk(q.get("name")):
            skipped["placeholder name"] += 1
            continue
        zone = to_int(q.get("zoneOrSort"))
        if zone == 0:
            giver = first_of(q.get("startedBy"), 0)
            entity = npcs.get(str(giver)) if giver else None
            zone = to_int(entity.get("zoneID")) if entity else 0
        if zone > 0:
            instance = world.instance_of(zone)
            if instance is not None:
                placement[quest_id] = ("instance", instance)
            else:
                placement[quest_id] = ("zone", world.top_area(zone))
        elif zone < 0:
            placement[quest_id] = ("sort", -zone)
        else:
            placement[quest_id] = ("sort", 0)

        skill = q.get("requiredSkill")
        quests[quest_id] = [
            0,  # 1: placement key, filled below
            to_int(q.get("requiredLevel")),
            to_int(q.get("questLevel")),
            to_int(q.get("requiredRaces")),
            to_int(q.get("requiredClasses")),
            quest_flags(q),
            [to_int(x) for x in q.get("preQuestGroup") or []] or None,
            [to_int(x) for x in q.get("preQuestSingle") or []] or None,
            [to_int(x) for x in q.get("exclusiveTo") or []] or None,
            to_int(q.get("nextQuestInChain")) or None,
            to_int(q.get("xp")) or None,
            giver_of(q.get("startedBy")),
            giver_of(q.get("finishedBy")),
            [to_int(skill[0]), to_int(skill[1])] if isinstance(skill, list) and len(skill) >= 2 else None,
            [[to_int(r[0]), to_int(r[1])] for r in q.get("reputationReward") or [] if isinstance(r, list) and len(r) >= 2] or None,
            to_int(q.get("breadcrumbForQuestId")) or None,
            q.get("name"),
        ]

    # Drop references to quests absent from the client: they can never be completed. Quests
    # that exist in the client but are not displayed (placeholder names) stay as
    # prerequisites, since the server may still flag them completed.
    for row in quests.values():
        for index in (6, 7, 8):
            if row[index]:
                row[index] = [x for x in row[index] if x in valid_ids] or None
        if row[9] and row[9] not in quests:
            row[9] = None
        if row[15] and row[15] not in quests:
            row[15] = None

    for reason, count in sorted(skipped.items()):
        log(f"quests skipped ({reason}): {count}")

    zones: dict[int, dict] = {}
    sorts: dict[int, dict] = {}
    instances: dict[int, list[int]] = defaultdict(list)
    for quest_id, (kind, key) in placement.items():
        if quest_id not in quests:
            continue
        if kind == "zone":
            zones.setdefault(key, {"quests": []})["quests"].append(quest_id)
            quests[quest_id][0] = key
        elif kind == "sort":
            sorts.setdefault(key, {"quests": []})["quests"].append(quest_id)
            quests[quest_id][0] = -key
        else:
            instances[key].append(quest_id)
            quests[quest_id][0] = to_int(world.maps[key]["AreaTableID"])

    def describe(quest_ids: list[int]) -> dict:
        levels = [quests[q][2] for q in quest_ids if quests[q][2] > 0]
        return {"chains": build_chains(quest_ids, quests),
                "levels": [min(levels), max(levels)] if levels else None}

    zone_rows = {}
    for area_id, entry in zones.items():
        zone_rows[area_id] = {"continent": world.continent_of(area_id), "uiMap": world.area_to_ui_map.get(area_id),
                              **describe(entry["quests"])}
    sort_rows = {sort_id: describe(entry["quests"]) for sort_id, entry in sorts.items()}

    referenced = {"npcs": set(), "objects": set(), "items": set()}
    for row in quests.values():
        for giver in (row[11], row[12]):
            if giver:
                referenced[("npcs", "objects", "items")[giver[0] - 1]].add(giver[1])
    log(f"quests: {len(quests)} in {len(zone_rows)} zones, {len(sort_rows)} categories, {len(instances)} instances")
    return quests, zone_rows, sort_rows, {"instances": dict(instances), "referenced": referenced}


def build_chains(quest_ids: list[int], quests: dict[int, list]) -> list[list[int]]:
    """Groups the quests of one zone into chains: a chain starts at a quest without an in-zone
    prerequisite and gathers every quest reachable through prerequisites or follow-ups.
    Each chain is ordered by dependency depth, then level, then id."""
    members = set(quest_ids)
    parents: dict[int, set[int]] = defaultdict(set)
    for quest_id in quest_ids:
        row = quests[quest_id]
        for pre in (row[6] or []) + (row[7] or []):
            if pre in members:
                parents[quest_id].add(pre)
        follow = row[9]
        if follow and follow in members and follow != quest_id:
            parents[follow].add(quest_id)
        if row[15] and row[15] in members:
            parents[row[15]].add(quest_id)

    # Connected components of the dependency graph.
    neighbours: dict[int, set[int]] = defaultdict(set)
    for child, ps in parents.items():
        for parent in ps:
            neighbours[child].add(parent)
            neighbours[parent].add(child)

    def depth(quest_id: int, memo: dict[int, int], stack: set[int]) -> int:
        if quest_id in memo:
            return memo[quest_id]
        if quest_id in stack:
            return 0
        stack.add(quest_id)
        value = 1 + max((depth(p, memo, stack) for p in parents.get(quest_id, ())), default=-1)
        stack.discard(quest_id)
        memo[quest_id] = value
        return value

    memo: dict[int, int] = {}
    seen: set[int] = set()
    chains = []
    for quest_id in sorted(quest_ids, key=lambda q: (quests[q][2], q)):
        if quest_id in seen:
            continue
        component, todo = [], [quest_id]
        seen.add(quest_id)
        while todo:
            current = todo.pop()
            component.append(current)
            for other in neighbours.get(current, ()):
                if other not in seen:
                    seen.add(other)
                    todo.append(other)
        component.sort(key=lambda q: (depth(q, memo, set()), quests[q][2], q))
        chains.append(component)
    chains.sort(key=lambda c: (min(quests[q][2] for q in c), c[0]))
    return chains


# ---------------------------------------------------------------------------
# Professions
# ---------------------------------------------------------------------------

def build_professions(cache: Path, questie: dict, referenced: dict) -> dict:
    skill_lines = {to_int(r["ID"]): r for r in read_table(cache, "SkillLine")}
    kept = {}
    for line_id, row in skill_lines.items():
        category = to_int(row["CategoryID"])
        parent = to_int(row["ParentSkillLineID"])
        if is_junk(row["DisplayName_lang"]) or parent:
            continue
        if category == 11:
            kept[line_id] = "gathering" if line_id in GATHERING_PROFESSIONS else "primary"
        elif line_id in SECONDARY_PROFESSIONS:
            kept[line_id] = "secondary"
    # Forever splits every profession into a parent and a child skill line; abilities of both
    # belong to the parent profession.
    owner = {line_id: line_id for line_id in kept}
    for line_id, row in skill_lines.items():
        parent = to_int(row["ParentSkillLineID"])
        if parent in kept and not is_junk(row["DisplayName_lang"]):
            owner[line_id] = parent

    reagents = {}
    for row in read_table(cache, "SpellReagents"):
        pairs = []
        for i in range(8):
            item, count = to_int(row[f"Reagent_{i}"]), to_int(row[f"ReagentCount_{i}"])
            if item > 0 and count > 0:
                pairs.append([item, count])
        if pairs:
            reagents[to_int(row["SpellID"])] = pairs

    creates, learns = {}, {}
    for row in read_table(cache, "SpellEffect"):
        spell = to_int(row["SpellID"])
        if row["Effect"] == EFFECT_CREATE_ITEM and to_int(row["EffectItemType"]):
            creates.setdefault(spell, to_int(row["EffectItemType"]))
        elif row["Effect"] == EFFECT_LEARN_SPELL and to_int(row["EffectTriggerSpell"]):
            learns.setdefault(spell, to_int(row["EffectTriggerSpell"]))

    item_effects = {to_int(r["ID"]): to_int(r["SpellID"]) for r in read_table(cache, "ItemEffect")}
    taught_by: dict[int, list[int]] = defaultdict(list)
    for row in read_table(cache, "ItemXItemEffect"):
        spell = item_effects.get(to_int(row["ItemEffectID"]))
        if not spell:
            continue
        taught = learns.get(spell, spell)
        taught_by[taught].append(to_int(row["ItemID"]))

    items, npcs = questie["items"], questie["npcs"]
    professions = {}
    for row in read_table(cache, "SkillLineAbility"):
        line = owner.get(to_int(row["SkillLine"]))
        spell = to_int(row["Spell"])
        if not line or not (spell in reagents or spell in creates):
            continue
        sources = []
        for recipe_item in sorted(set(taught_by.get(spell, []))):
            entry = items.get(str(recipe_item)) or {}
            source = {"item": recipe_item}
            for key in ("vendors", "npcDrops", "objectDrops", "questRewards"):
                ids = [to_int(x) for x in entry.get(key) or []]
                if key in ("vendors", "npcDrops"):
                    # Prefer the most relevant sources: named, placed NPCs, lowest level first.
                    ids = [x for x in ids if str(x) in npcs and npcs[str(x)].get("spawn")]
                    ids.sort(key=lambda x: (to_int(npcs[str(x)].get("minLevel")), x))
                if ids:
                    source[key] = ids[:MAX_SOURCES_PER_KIND]
                    if key in ("vendors", "npcDrops"):
                        referenced["npcs"].update(source[key])
                    elif key == "objectDrops":
                        referenced["objects"].update(source[key])
            sources.append(source)
            referenced["items"].add(recipe_item)
        acquire = to_int(row["AcquireMethod"])
        recipe = [
            spell,
            to_int(row["MinSkillLineRank"]),
            to_int(row["TrivialSkillLineRankLow"]),
            to_int(row["TrivialSkillLineRankHigh"]),
            # 0 = trainer or recipe item, anything else = learned automatically with the skill.
            0 if acquire == 0 else 1,
            creates.get(spell),
            reagents.get(spell),
            sources or None,
        ]
        professions.setdefault(line, {"kind": kept[line], "icon": to_int(skill_lines[line]["SpellIconFileID"]), "recipes": {}})
        professions[line]["recipes"].setdefault(spell, recipe)

    result = {}
    for line, entry in professions.items():
        recipes = sorted(entry["recipes"].values(), key=lambda r: (r[1], r[0]))
        result[line] = {"kind": entry["kind"], "icon": entry["icon"], "recipes": recipes}
        log(f"profession {line} ({skill_lines[line]['DisplayName_lang']}): {len(recipes)} recipes")
    for line, kind in kept.items():
        result.setdefault(line, {"kind": kind, "icon": to_int(skill_lines[line]["SpellIconFileID"]), "recipes": []})
    return result


# ---------------------------------------------------------------------------
# Instances
# ---------------------------------------------------------------------------

def build_instances(cache: Path, world: World, instance_quests: dict[int, list[int]], quests: dict) -> tuple[dict, dict]:
    encounters: dict[int, dict[str, dict]] = defaultdict(dict)
    for row in read_table(cache, "DungeonEncounter"):
        name = row["Name_lang"]
        if is_junk(name):
            continue
        map_id = to_int(row["MapID"])
        current = encounters[map_id].get(name)
        # The same boss appears once per difficulty; keep the lowest difficulty row.
        if current is None or to_int(row["DifficultyID"]) < current["difficulty"]:
            encounters[map_id][name] = {"id": to_int(row["ID"]), "order": to_int(row["OrderIndex"]),
                                        "difficulty": to_int(row["DifficultyID"])}

    instances = {}
    for map_id, row in world.maps.items():
        kind = to_int(row["InstanceType"])
        if kind not in (INSTANCE_DUNGEON, INSTANCE_RAID) or is_junk(row["MapName_lang"]):
            continue
        bosses = sorted(encounters.get(map_id, {}).values(), key=lambda e: (e["order"], e["id"]))
        quest_ids = instance_quests.get(map_id, [])
        if not bosses and not quest_ids:
            continue
        levels = [quests[q][2] for q in quest_ids if q in quests and quests[q][2] > 0]
        instances[map_id] = {
            "kind": kind,
            "area": to_int(row["AreaTableID"]),
            "players": to_int(row.get("MaxPlayers")),
            "art": world.loading_screen(map_id),
            "bosses": [e["id"] for e in bosses],
            "chains": build_chains(quest_ids, quests) if quest_ids else [],
            "levels": [min(levels), max(levels)] if levels else None,
        }
    log(f"instances: {sum(1 for i in instances.values() if i['kind'] == INSTANCE_DUNGEON)} dungeons, "
        f"{sum(1 for i in instances.values() if i['kind'] == INSTANCE_RAID)} raids")
    return instances, encounters


# ---------------------------------------------------------------------------
# Collections
# ---------------------------------------------------------------------------

def build_collections(cache: Path) -> dict:
    mounts = sorted(to_int(r["ID"]) for r in read_table(cache, "Mount") if not is_junk(r["Name_lang"]))
    pets = sorted(to_int(r["ID"]) for r in read_table(cache, "BattlePetSpecies"))
    toys = sorted({to_int(r["ItemID"]) for r in read_table(cache, "Toy") if to_int(r["ItemID"])})
    sets = sorted(to_int(r["ID"]) for r in read_table(cache, "TransmogSet") if not is_junk(r["Name_lang"]))
    titles = sorted({to_int(r["Mask_ID"]) for r in read_table(cache, "CharTitles") if not is_junk(r["Name_lang"])})
    log(f"collections: {len(mounts)} mounts, {len(pets)} pets, {len(toys)} toys, {len(sets)} sets, {len(titles)} titles")
    return {"mounts": mounts, "pets": pets, "toys": toys, "sets": sets, "titles": titles}


# ---------------------------------------------------------------------------
# Constants and localized client strings
# ---------------------------------------------------------------------------

def build_races(cache: Path) -> dict:
    races, alliance, horde = {}, 0, 0
    for row in read_table(cache, "ChrRaces"):
        bit = to_int(row["PlayableRaceBit"], -1)
        if bit < 0:
            continue
        races[to_int(row["ID"])] = bit
        side = to_int(row["Alliance"], -1)
        if side == 0:
            alliance |= 1 << bit
        elif side == 1:
            horde |= 1 << bit
    return {"raceBits": races, "allianceRaces": alliance, "hordeRaces": horde}


def build_strings(cache: Path, locale: str, zones: dict, sorts: dict, professions: dict,
                  instances: dict, encounter_ids: set[int], toys: list[int]) -> dict:
    """Client strings the game API does not expose, used when the client cannot provide them."""
    areas = {to_int(r["ID"]): r["AreaName_lang"] for r in read_table(cache, "AreaTable", locale)}
    sort_names = {to_int(r["ID"]): r["SortName_lang"] for r in read_table(cache, "QuestSort", locale)}
    lines = {to_int(r["ID"]): r["DisplayName_lang"] for r in read_table(cache, "SkillLine", locale)}
    bosses = {to_int(r["ID"]): r["Name_lang"] for r in read_table(cache, "DungeonEncounter", locale)}
    toy_sources = {to_int(r["ItemID"]): r["SourceText_lang"] for r in read_table(cache, "Toy", locale)}
    wanted_areas = set(zones) | {i["area"] for i in instances.values()}
    return {
        "areas": {a: areas[a] for a in sorted(wanted_areas) if areas.get(a)},
        "questSorts": {s: sort_names[s] for s in sorted(sorts) if sort_names.get(s)},
        "skillLines": {s: lines[s] for s in sorted(professions) if lines.get(s)},
        "encounters": {e: bosses[e] for e in sorted(encounter_ids) if bosses.get(e)},
        "toySources": {t: toy_sources[t] for t in toys if toy_sources.get(t)},
    }


def build_entities(world: World, questie: dict, referenced: dict) -> dict:
    """Quest givers and recipe sources: English fallback name and one map position
    {areaId, x, y, uiMapId} (coordinates in percent of the map)."""
    def place(entity: dict) -> list | None:
        spawn = entity.get("spawn")
        if not spawn:
            return None
        area = to_int(spawn["zone"])
        ui_map = world.area_to_ui_map.get(area) or world.area_to_ui_map.get(world.top_area(area))
        return [area, round(float(spawn["x"]), 1), round(float(spawn["y"]), 1), ui_map]

    npcs = {}
    for npc_id in sorted(referenced["npcs"]):
        entity = questie["npcs"].get(str(npc_id))
        if entity:
            npcs[npc_id] = [entity.get("name"), place(entity)]
    objects = {}
    for object_id in sorted(referenced["objects"]):
        entity = questie["objects"].get(str(object_id))
        if entity:
            objects[object_id] = [entity.get("name"), place(entity)]
    items = {}
    for item_id in sorted(referenced["items"]):
        entity = questie["items"].get(str(item_id))
        if entity:
            items[item_id] = [entity.get("name")]
    return {"npcs": npcs, "objects": objects, "items": items}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--build", default=DEFAULT_BUILD, help="WoW Forever client build to read the tables of")
    parser.add_argument("--cache", type=Path, default=ROOT / ".cache", help="download cache directory")
    parser.add_argument("--questiedb", type=Path, default=None, help="existing QuestieDB checkout (cloned into the cache otherwise)")
    args = parser.parse_args()

    cache = args.cache / args.build
    fetch_tables(cache, args.build)
    questie = load_questie(args.questiedb or args.cache / "QuestieDB", cache)
    world = World(cache, questie)
    valid_ids = {to_int(r["ID"]) for r in read_table(cache, "QuestV2")}

    quests, zones, sorts, extra = build_quests(world, questie, valid_ids)
    referenced = extra["referenced"]
    professions = build_professions(cache, questie, referenced)
    instances, encounters = build_instances(cache, world, extra["instances"], quests)
    collections = build_collections(cache)
    entities = build_entities(world, questie, referenced)
    encounter_ids = {boss for instance in instances.values() for boss in instance["bosses"]}

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    attribution = "Quest structure from QuestieDB (GPL-3.0); identifiers from the WoW Forever client tables."
    write_lua("Quests.lua", attribution, [("Quests", quests)], args.build)
    write_lua("Zones.lua", attribution, [("Zones", zones), ("QuestSorts", sorts)], args.build)
    write_lua("Entities.lua", "Quest givers and recipe sources from QuestieDB (GPL-3.0).",
              [("Npcs", entities["npcs"]), ("Objects", entities["objects"]), ("Items", entities["items"])], args.build)
    write_lua("Professions.lua", "Recipes from the client tables; recipe sources from QuestieDB (GPL-3.0).",
              [("Professions", professions)], args.build)
    write_lua("Instances.lua", attribution, [("Instances", instances)], args.build)
    write_lua("Collections.lua", "Collectible identifiers from the client tables.",
              [("Collections", collections)], args.build)
    write_lua("Constants.lua", "Race bits from the client tables.", [("Races", build_races(cache)),
              ("Build", args.build)], args.build)
    for locale in LOCALES:
        strings = build_strings(cache, locale, zones, sorts, professions, instances, encounter_ids, collections["toys"])
        name = f"Strings.{locale}.lua"
        lines = [
            "-- Generated by tools/build_data.py. Do not edit by hand.",
            f"-- Localized client strings ({locale}) for texts the game API does not expose.",
            "local _, ns = ...",
            f'if GetLocale() ~= "{locale}" and "{locale}" ~= "enUS" then return end',
            "ns.Data = ns.Data or {}",
            "ns.Data.Strings = ns.Data.Strings or {}",
            f'ns.Data.Strings["{locale}"] = {lua_value(strings)}',
        ]
        (DATA_DIR / name).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        log(f"wrote Data/{name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
