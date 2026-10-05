"""Deterministic item migration from the legacy modifier stub to the catalog.

Rewrites each `game/data/items/**/<id>.tres` from raw `flat_modifiers` /
`percent_modifiers` stat maps to the master-catalog model (ADR 0025): `rarity`,
`realm`, `fixed_modifiers` (master option ids with authored values) and
`roll_spec`. Stable ids, acquisition sources and descriptions are preserved; the
legacy blocks are removed so no competing modifier system survives.

Atomic and deterministic: the same catalog produces the same bytes, and running
it again after a completed migration is a no-op.
"""

from __future__ import annotations

import re
import zlib
from pathlib import Path

from .common import ToolError, fail, info, ok
from .options import DEFAULT_CATALOG, _load_jsonl

ITEMS_DIRNAME = Path("game") / "data" / "items"
REALM_DEFAULTS = Path("game") / "src" / "core" / "realm_defaults.gd"

# grade -> tier, using the same tier gates as the runtime (ADR 0007). Rarity is
# a separate quality axis and is deliberately *not* a blind grade mapping:
# immortal/divine grades do not silently become rare/legendary, they stay in the
# bands declared here (ADR 0025).
GRADE_TIER = {
    "mortal": 1,
    "spirit": 2,
    "earth": 2,
    "heaven": 3,
    "immortal": 3,
    "divine": 4,
}
GRADE_RARITY = {
    "mortal": "common",
    "spirit": "magic",
    "earth": "rare",
    "heaven": "rare",
    "immortal": "legendary",
    "divine": "legendary",
}
RARITY_COUNT = {"common": 1, "magic": 2, "rare": 3, "legendary": 4}
CATEGORY_CONTEXT = {
    "equipment": ("prefix", "postfix"),
    "consumable": ("base", "prefix"),
    "technique": ("base", "prefix"),
    "material": ("base", "prefix"),
    "key": ("base",),
    "currency": ("base",),
    "quest": ("base",),
    "misc": ("base", "prefix"),
}
# A meaningful fixed option per category, so no item is left with an empty fixed
# channel or a decorative effect (ADR 0028).
CATEGORY_FIXED = {
    "equipment": ("core_attack_physical", "core_defense_physical"),
    "consumable": ("restore_health",),
    "technique": ("base_comprehension",),
    "material": ("craft_potency",),
    "key": ("key_reach",),
    "currency": ("trade_value",),
    "quest": ("quest_potency",),
    "misc": ("craft_potency",),
}
UNIT_FIXED_VALUE = {"magnitude": 6.0, "rate": 0.03, "fraction": 0.02}
TIER_BANDS = {1: range(0, 9), 2: range(9, 18), 3: range(18, 27), 4: range(27, 30)}

_SCALAR = re.compile(r'(?m)^%s = &"([^"]*)"')
_DICT_BLOCK = re.compile(r"(?ms)^%s = \{\n(.*?)^\}")


def register(subparsers) -> None:
    parser = subparsers.add_parser("items", help="item definition migration")
    actions = parser.add_subparsers(dest="items_action", required=True)
    migrate = actions.add_parser(
        "migrate", help="convert legacy modifier stubs to master option references"
    )
    migrate.add_argument("--root", default=None, help="items root (default game/data/items)")
    migrate.add_argument("--catalog", default=None)
    migrate.add_argument("--apply", action="store_true", help="write changes (default: dry run)")
    migrate.add_argument("--limit", type=int, default=0, help="stop after N files")

    link = actions.add_parser(
        "link-boss-loot",
        help=(
            "make every `boss:<id>` acquisition source real by adding the item to "
            "that boss's loot array"
        ),
    )
    link.add_argument("--apply", action="store_true", help="write changes (default: dry run)")


def run(args) -> int:
    if getattr(args, "data_action", None) == "items":
        if getattr(args, "items_action", None) == "link-boss-loot":
            return _link_boss_loot(getattr(args, "apply", False))
        root = Path(args.root) if getattr(args, "root", None) else None
        catalog = Path(args.catalog) if getattr(args, "catalog", None) else DEFAULT_CATALOG
        return _migrate(root, catalog, getattr(args, "apply", False), getattr(args, "limit", 0))
    raise ToolError(f"unknown items action: {getattr(args, 'items_action', None)}")


BOSS_LOOT = re.compile(r"(?m)^loot = Array\[StringName\]\(\[(.*?)\]\)$")


def _boss_loot_entries(text: str) -> list[str] | None:
    match = BOSS_LOOT.search(text)
    if not match:
        return None
    return re.findall(r'&"([^"]+)"', match.group(1))


def _link_boss_loot(apply: bool) -> int:
    """Make `boss:<id>` sources truthful by editing the boss, not the claim.

    A set piece or unique that names a boss but is absent from that boss's loot
    array has no reachable drop path, which the acquisition audit rejects. This
    adds the missing ids, deterministically and idempotently.
    """
    from .common import REPO_ROOT  # noqa: PLC0415

    data_root = REPO_ROOT / "game" / "data"
    wanted: dict[str, set[str]] = {}
    for path in sorted(data_root.rglob("*.tres")):
        if "items" not in path.parts and "socket" not in path.parts:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        item_id = scalar(text, "id")
        if not item_id:
            continue
        for source in re.findall(r'&"(boss:[^"]+)"', text):
            wanted.setdefault(source[len("boss:") :], set()).add(item_id)
    if not wanted:
        info("no boss-sourced items found")
        ok("boss loot already consistent")
        return 0
    bosses = {
        scalar(path.read_text(encoding="utf-8"), "id"): path
        for path in sorted((data_root / "bosses").rglob("*.tres"))
    }
    changed = 0
    missing: list[str] = []
    for boss_id, item_ids in sorted(wanted.items()):
        path = bosses.get(boss_id)
        if path is None:
            missing.append(boss_id)
            continue
        text = path.read_text(encoding="utf-8")
        entries = _boss_loot_entries(text)
        if entries is None:
            missing.append(boss_id)
            continue
        absent = sorted(i for i in item_ids if i not in entries)
        if not absent:
            continue
        merged = entries + absent
        rendered = ", ".join(f'&"{i}"' for i in merged)
        updated = BOSS_LOOT.sub(f"loot = Array[StringName]([{rendered}])", text, count=1)
        if updated != text:
            changed += 1
            if apply:
                path.write_text(updated, encoding="utf-8")
    for boss_id in missing:
        fail(f"boss '{boss_id}' is named by an item's source but no such boss exists")
    verb = "linked" if apply else "would link"
    info(f"{verb} {changed} boss loot array(s) across {len(wanted)} boss route(s)")
    if missing:
        return 1
    ok("boss loot consistent with boss-sourced items")
    return 0


# --- helpers ---------------------------------------------------------------


def items_root(root: Path | None) -> Path:
    from .common import REPO_ROOT  # noqa: PLC0415

    return root if root is not None else REPO_ROOT / ITEMS_DIRNAME


def realm_ladder() -> list[str]:
    """Canonical 30-realm ladder ids, read from the Godot source of truth."""
    from .common import REPO_ROOT  # noqa: PLC0415

    text = (REPO_ROOT / REALM_DEFAULTS).read_text(encoding="utf-8")
    ids = re.findall(r'_make\(&"([a-z_]+)"', text)
    if len(ids) != 30:
        raise ToolError(f"expected 30 realms in {REALM_DEFAULTS}, found {len(ids)}")
    return ids


def scalar(text: str, field: str) -> str:
    match = re.search(rf'(?m)^{field} = &"([^"]*)"', text)
    return match.group(1) if match else ""


def dict_block(text: str, field: str) -> list[tuple[str, float]]:
    match = re.search(rf"(?ms)^{field} = \{{\n(.*?)^\}}", text)
    if not match:
        return []
    pairs = []
    for line in match.group(1).splitlines():
        found = re.match(r'^\s*"([^"]+)":\s*(-?[\d.]+)\s*,?\s*$', line)
        if found:
            pairs.append((found.group(1), float(found.group(2))))
    return pairs


def option_for(stat_id: str, percent: bool, records: dict[str, dict]) -> str | None:
    """Master option id whose target is `stat_id` with the matching operation.

    Aliases are never guessed: a stat without a matching option is reported, not
    mapped to a similarly named one (ADR 0025).
    """
    want = "PERCENT" if percent else "FLAT"
    fallback = None
    for rid in sorted(records):
        record = records[rid]
        if record["status"] != "active":
            continue
        target = record["target"]
        if target["type"] != "stat" or target["id"] != stat_id:
            continue
        if record["op"] == want:
            return rid
        fallback = fallback or rid
    return fallback


def realm_for(item_id: str, grade: str, ladder: list[str]) -> str:
    """Canonical realm id for an item.

    Prefers a realm id the item's own id already names (breakthrough bundles
    encode theirs), otherwise spreads deterministically across the grade's tier
    band so all 30 realms stay reachable without hand-authoring 8000 ids.
    """
    tier = GRADE_TIER.get(grade, 1)
    band = list(TIER_BANDS.get(tier, TIER_BANDS[1]))
    named = [r for r in ladder if r in item_id]
    if named:
        return max(named, key=len)
    return ladder[band[zlib.crc32(item_id.encode("utf-8")) % len(band)]]


def existing_fixed(text: str) -> list[tuple[str, float]]:
    """Fixed option entries already authored on this definition."""
    match = re.search(r"(?ms)^fixed_modifiers = Array\[Dictionary\]\(\[(.*?)^\]\)", text)
    if not match:
        return []
    pairs = re.findall(r'\{"option_id": &"([a-z_]+)", "value": (-?[\d.]+)\}', match.group(1))
    return [(option_id, float(value)) for option_id, value in pairs]


def migrate_text(text: str, records: dict[str, dict], ladder: list[str]) -> tuple[str, list[str]]:
    """Return the migrated text plus any diagnostics for this definition.

    Idempotent: existing catalog fields are stripped and rewritten from the
    merged fixed list, so re-running after a completed migration is a no-op.
    Legacy stat values fold in once and are then carried forward.
    """
    notes: list[str] = []
    category = scalar(text, "category") or "misc"
    grade = scalar(text, "grade") or "mortal"
    item_id = scalar(text, "id") or "?"
    rarity = GRADE_RARITY.get(grade, "common")
    realm = realm_for(item_id, grade, ladder)

    # Already-authored entries are preserved; a legacy stat value wins for the
    # option it maps to, so the first migration keeps the authored magnitude.
    merged: dict[str, float] = dict(existing_fixed(text))
    order: list[str] = list(merged)
    for is_percent, field in ((False, "flat_modifiers"), (True, "percent_modifiers")):
        for stat_id, value in dict_block(text, field):
            option_id = option_for(stat_id, is_percent, records)
            if option_id is None:
                notes.append(f"{item_id}: no catalog option for stat '{stat_id}' ({field})")
                continue
            if option_id not in merged:
                order.append(option_id)
            merged[option_id] = value
    if not merged:
        for option_id in CATEGORY_FIXED.get(category, ()):
            if option_id in records:
                merged[option_id] = UNIT_FIXED_VALUE[records[option_id]["unit"]]
                order.append(option_id)
                break
        else:
            notes.append(f"{item_id}: category '{category}' has no fixed option")

    for field in ("flat_modifiers", "percent_modifiers"):
        text = re.sub(rf"(?ms)^{field} = \{{\n.*?^\}}\n", "", text)
    for field in ("rarity", "realm"):
        text = re.sub(rf'(?m)^{field} = &"[^"]*"\n', "", text)
    text = re.sub(r"(?ms)^fixed_modifiers = Array\[Dictionary\]\(\[.*?^\]\)\n", "", text)
    text = re.sub(r"(?m)^roll_spec = \{.*\}\n", "", text)
    text = re.sub(r"\n{3,}", "\n\n", text)

    lines = [f'{{"option_id": &"{oid}", "value": {merged[oid]:g}}},' for oid in order]
    contexts = ", ".join(f'"{c}"' for c in CATEGORY_CONTEXT.get(category, ("base",)))
    block = [f'rarity = &"{rarity}"', f'realm = &"{realm}"']
    if lines:
        block.append("fixed_modifiers = Array[Dictionary]([")
        block.extend(f"\t{line}" for line in lines)
        block.append("])")
    block.append(f'roll_spec = {{"count": {RARITY_COUNT[rarity]}, "contexts": [{contexts}]}}')
    text = re.sub(
        r"(?m)^(category = .+)$",
        lambda m: m.group(1) + "\n" + "\n".join(block),
        text,
        count=1,
    )
    # Equipment must stay a distinct instance: a stackable item merges and loses
    # its rolls, sockets and binding, so it can never be equipped (ADR 0025).
    if category == "equipment" and "stackable = false" not in text:
        if re.search(r"(?m)^stackable = ", text):
            text = re.sub(r"(?m)^stackable = .*$", "stackable = false", text, count=1)
        else:
            text = re.sub(r"(?m)^(subcategory = .+)$", "\\1\nstackable = false", text, count=1)
    return text, notes


def _migrate(root: Path | None, catalog: Path, apply: bool, limit: int) -> int:
    records = {r["id"]: r for r in _load_jsonl(catalog)}
    ladder = realm_ladder()
    base = items_root(root)
    if not base.is_dir():
        raise ToolError(f"items root not found: {base}")
    paths = sorted(base.rglob("*.tres"))
    if limit:
        paths = paths[:limit]
    changed = 0
    notes: list[str] = []
    for path in paths:
        original = path.read_text(encoding="utf-8")
        updated, file_notes = migrate_text(original, records, ladder)
        notes.extend(file_notes)
        if updated != original:
            changed += 1
            if apply:
                path.write_text(updated, encoding="utf-8")
    verb = "migrated" if apply else "would migrate"
    info(f"{verb} {changed} of {len(paths)} item definitions")
    for note in notes[:20]:
        info(f"  {note}")
    if len(notes) > 20:
        info(f"  ... {len(notes) - 20} more")
    ok("item migration complete")
    return 0
