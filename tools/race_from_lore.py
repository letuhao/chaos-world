"""Transcribe Lore Bible species entities into `RaceDef` resources (ADR 0253).

346 of 400 canon characters name a species with no `RaceDef`, so their portraits load, validate
and can never be selected: `PortraitCatalog.for_race` resolves by race id and no race of that name
exists. The Bible already carries every field a `RaceDef` declares, so the fix is TRANSCRIPTION
rather than a second place to retune the same numbers.

Deterministic and offline. It reads the Bible and writes `.tres`; it never invents a value. A field
the Bible omits is written at its declared `RaceDef` default and reported, because a guessed number
in a balance table is worse than an absent one.

Refuses by default to overwrite an existing `.tres`. The five hand-authored races predate this rule
and keep their values; `--force` exists for a deliberate re-transcription and is reported loudly,
because silently replacing authored balance with transcribed balance is the exact drift ADR 0253
exists to stop.
"""

from __future__ import annotations

import re

from .common import GAME_DIR, ToolError, fail, info, ok

RACE_ROOT = GAME_DIR / "data" / "races"
STAT_CONTRACT = GAME_DIR / "src" / "contracts" / "stat.gd"
LORE_PREFIX = "races."

## Scalar fields copied straight through. Listed rather than iterated so a field added to the Bible
## is a deliberate edit here, not a silent new line in every generated resource.
SCALAR_FIELDS = (
    "dominance",
    "manifestation_threshold",
    "gestation_days",
    "base_fertility",
    "base_potency",
    "offspring_variance",
    "realm_ceiling",
    "lifespan",
)

## Dictionary fields, whose KEYS must be declared stats.
DICT_FIELDS = ("base_attributes", "percent_modifiers", "affinities")


def declared_stats() -> set[str]:
    """Every stat key `contracts/stat.gd` declares, read as TEXT.

    This process has no Godot runtime, and the alternative — accepting any key the Bible happens to
    use — would produce modifiers the game silently ignores, which is the failure ADR 0253 exists to
    prevent. `sorted` over a materialised listing so the error names the same key every run.
    """
    if not STAT_CONTRACT.is_file():
        raise ToolError(f"{STAT_CONTRACT} does not exist; cannot tell a declared stat from a typo")
    text = STAT_CONTRACT.read_text(encoding="utf-8", errors="replace")
    found = {
        value for _, value in re.findall(r'^const ([A-Z_]+) := &"([a-z_]+)"', text, re.MULTILINE)
    }
    if not found:
        raise ToolError(f"{STAT_CONTRACT} declares no stat constants; the read is wrong, not empty")
    return found


def base_attribute_ids() -> list[str]:
    """`Stat.BASE_ATTRIBUTES`, in declaration order, resolved to their literal ids.

    The constant lists CONSTANT NAMES (`PHYSIQUE,`), not literal strings, so it is resolved through
    the same text parse. Read rather than hardcoded because the baseline is the plain-mortal 1.0 for
    exactly this set: a hardcoded list would let a peer add a seventh attribute and leave every
    transcribed race granting 0.0 for it, which is the silent-zero defect this fill exists to stop.
    """
    text = STAT_CONTRACT.read_text(encoding="utf-8", errors="replace")
    block = re.search(r"const BASE_ATTRIBUTES := \[(.*?)\]", text, re.DOTALL)
    if block is None:
        raise ToolError(f"{STAT_CONTRACT} declares no BASE_ATTRIBUTES array")
    tokens = [
        token.strip() for token in block.group(1).replace("\n", "").split(",") if token.strip()
    ]
    by_name = {
        name: value
        for name, value in re.findall(r'^const ([A-Z_]+) := &"([a-z_]+)"', text, re.MULTILINE)
    }
    unknown = [token for token in tokens if token not in by_name]
    if unknown:
        raise ToolError(
            f"BASE_ATTRIBUTES names {unknown}, which {STAT_CONTRACT.name} does not declare"
        )
    if not tokens:
        raise ToolError("BASE_ATTRIBUTES resolved to an empty list; the read is wrong, not empty")
    return [by_name[token] for token in tokens]


## `actor_stats.gd` derives this as `physique * 2.0`, then applies percent modifiers. Mirrored here
## only to REFUSE a species the game would reject, never to author a number: see `strike_refusal`.
ATTACK_PHYSICAL_PER_PHYSIQUE = 2.0


def strike_refusal(attributes: dict[str, float], percent_modifiers: dict[str, float]) -> str | None:
    """Why this species cannot strike, or `None` when it can.

    `test_every_shipped_race_is_born_with_a_physique_and_can_strike` fails the build on a shipped
    race whose derived `ATTACK_PHYSICAL` is 0.0, and `tidecaller.tres` explains why in prose: "an
    omitted grant is a grant of 0.0 - `_grant` only ever ADDS ... Omitting it does not make this
    body even-framed, it makes it unable to hit anything."

    Transcribing such a species would write a race that passes every resource check and cannot
    attack, so it is refused and reported rather than shipped. Whether `wake` — whose Bible entity
    authors `attack_physical: -1.0` — becomes a race at all is a content decision, not a
    transcription one, and this tool does not make it.
    """
    physique = float(attributes.get("physique", 0.0))
    modifier = float(percent_modifiers.get("attack_physical", 0.0))
    if physique * ATTACK_PHYSICAL_PER_PHYSIQUE * (1.0 + modifier) == 0.0:
        if physique == 0.0:
            return f"physique is 0.0 after percent_modifiers ({1.0 + modifier})"
        return f"attack_physical is {modifier}, which zeroes a physique of {physique}"
    return None


def snake(tag: str) -> str:
    """`cold-adapted` -> `cold_adapted`.

    A hyphen in a `StringName` would not match a `has_trait` gate, which is the whole reason tags
    are converted rather than copied.
    """
    return re.sub(r"[^a-z0-9]+", "_", str(tag).strip().lower()).strip("_")


def _quote(value: str) -> str:
    escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def _float(value: object) -> str:
    """GDScript float literal. A whole number still gets a `.0`, per this function's contract.

    `str(int(3.0))` would emit `3`, which Godot accepts for a `float` property but which reads as an
    int in a `.tres` a human is auditing, and makes a byte-comparison of two transcriptions differ
    from a hand-authored file for no reason.
    """
    number = float(value)
    return str(int(number)) + ".0" if number == int(number) else repr(number)


def transcribe(
    entity_id: str,
    entity: dict,
    stats: set[str],
    base_ids: list[str] | None = None,
) -> tuple[str, list[str], list[str], str | None]:
    """(`body`, unknown_stat_keys, omitted_fields, strike_refusal) for one species entity.

    `base_ids` defaults to the real `Stat.BASE_ATTRIBUTES` so a caller that forgets it cannot
    silently transcribe without the baseline — the omission that made 18 species unable to strike.
    """
    problems: list[str] = []
    omitted: list[str] = []
    attrs = entity.get("attributes") or {}
    if base_ids is None:
        base_ids = base_attribute_ids()

    # An omitted attribute is a grant of 0.0, not of 1.0: `_grant` only ADDS, so a body that leaves
    # `will` out is born with no will rather than an even-framed one. Every transcribed race is
    # therefore seeded with the plain-mortal 1.0 that `commonborn` writes for all seven, and the
    # Bible's authored values are overlaid on top. 11 species name NO attributes at all, so this is
    # the common case rather than a safety net.
    merged_base = {attribute: 1.0 for attribute in base_ids}
    merged_base.update({str(k): float(v) for k, v in (attrs.get("base_attributes") or {}).items()})

    for field in ("base_attributes", "percent_modifiers"):
        for key in attrs.get(field) or {}:
            if key not in stats:
                problems.append(
                    f"{entity_id}: {field} names '{key}', which contracts/stat.gd does not declare"
                )

    # Checked AFTER the undeclared-stat sweep, not before it. A species this rule refuses is still
    # worth reporting a typo in: the author is about to go fix its attributes, and a misspelled stat
    # key there is exactly what they would otherwise miss.
    missing_scalars = [field for field in SCALAR_FIELDS if field not in attrs]
    if missing_scalars:
        # Refuse BEFORE the strike check: a species with no dominance, gestation, fertility, ceiling
        # or lifespan is not a partially-specified race, it is an unimplemented one.
        return (
            "",
            problems,
            missing_scalars,
            f"the Bible specifies none of its balance: no {', '.join(missing_scalars)}",
        )

    bare = str(entity_id).removeprefix(LORE_PREFIX)
    lines = [
        '[gd_resource type="Resource" script_class="RaceDef" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="res://src/modules/race/race_def.gd" id="1_race"]',
        "",
        "[resource]",
        'script = ExtResource("1_race")',
        f'id = &"{bare}"',
        f"display_name = {_quote(entity.get('name') or bare)}",
    ]
    summary = str(entity.get("summary") or "").replace("\n", " ").strip()
    lines.append(f"description = {_quote(summary)}")

    for field in SCALAR_FIELDS:
        # No default is written. An omitted scalar means the Bible says nothing about it, and
        # `RaceDef`'s declared default is the CLASS's idea of an ordinary body, not this species's —
        # so filling it silently authors a balance decision nobody made. 5 species omit all eight.
        if field not in attrs:
            omitted.append(field)
            continue
        lines.append(f"{field} = {_float(attrs[field])}")

    closed = attrs.get("closed_paths") or []
    closed_text = ", ".join(f'&"{snake(p)}"' for p in closed)
    lines.append(f"closed_paths = Array[StringName]([{closed_text}])")

    for field in DICT_FIELDS:
        raw = merged_base if field == "base_attributes" else (attrs.get(field) or {})
        # `sorted` so two runs emit byte-identical files rather than differing on dict order.
        pairs = ", ".join(f"{_quote(k)}: {_float(raw[k])}" for k in sorted(raw))
        lines.append(f"{field} = {{{pairs}}}")

    tags = entity.get("tags") or []
    tag_text = ", ".join(f'&"{snake(t)}"' for t in tags if snake(t))
    lines.append(f"tags = Array[StringName]([{tag_text}])")
    lines.append("")
    refusal = strike_refusal(
        merged_base, {str(k): float(v) for k, v in (attrs.get("percent_modifiers") or {}).items()}
    )
    return ("\n".join(lines), problems, omitted, refusal)


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "race_from_lore",
        help="transcribe Lore Bible species entities into RaceDef resources (ADR 0253)",
    )
    actions = parser.add_subparsers(dest="race_from_lore_action", required=True)
    actions.add_parser("report", help="list what would be written; writes nothing")
    write = actions.add_parser("write", help="write the transcribed RaceDef resources")
    write.add_argument(
        "--force",
        action="store_true",
        help="overwrite an existing RaceDef - refuses by default so hand-authored balance survives",
    )
    write.add_argument(
        "--limit", type=int, default=0, help="stop after this many species (0 = all)"
    )


def run(args) -> int:
    try:
        from .lore.model import load_bible
    except ImportError as error:
        fail(f"cannot read the Lore Bible ({error}); refusing to emit races that might be invented")
        return 1
    bible = load_bible()
    species = {
        key: value
        for key, value in bible.entities.items()
        if str(key).startswith(LORE_PREFIX) and isinstance(value, dict)
    }
    if not species:
        fail("the Lore Bible carries no races.* entities; refusing to write an empty race table")
        return 1
    try:
        stats = declared_stats()
    except ToolError as error:
        fail(str(error))
        return 1

    existing = {path.stem for path in RACE_ROOT.glob("*.tres")} if RACE_ROOT.is_dir() else set()
    report_only = args.race_from_lore_action == "report"
    # `report` has no `--force`, so read it defensively rather than adding a flag that means
    # nothing on the read-only path. `report` writes nothing, so the value cannot matter there.
    force = bool(getattr(args, "force", False))
    try:
        base_ids = base_attribute_ids()
    except ToolError as error:
        fail(str(error))
        return 1
    problems: list[str] = []
    refusals: list[tuple[str, str]] = []
    would_write = skipped = 0
    for entity_id in sorted(species):
        body, entity_problems, omitted, refusal = transcribe(
            entity_id, species[entity_id], stats, base_ids
        )
        problems.extend(entity_problems)
        bare = str(entity_id).removeprefix(LORE_PREFIX)
        # Skipped BEFORE the refusal is reported: an already-authored race carries its completion in
        # its own `.tres`, and `commonborn`/`emberblood`/`stoneborn`/`tidecaller` all omit the three
        # fertility scalars the Bible never specified. Calling those refusals would report four
        # shipped races as unimplemented, which is the opposite of the truth.
        if bare in existing and not force:
            skipped += 1
            continue
        if refusal is not None:
            refusals.append((bare, refusal))
            continue
        if not report_only:
            RACE_ROOT.mkdir(parents=True, exist_ok=True)
            target = RACE_ROOT / f"{bare}.tres"
            target.write_text(body, encoding="utf-8", newline="\n")
            if bare in existing:
                info(f"{bare}.tres OVERWRITTEN from the Bible (--force); check the diff")
        would_write += 1

    print(f"Lore species: {len(species)} | authored races on disk: {len(existing)}")
    print(f"declared stats in contracts/stat.gd: {len(stats)}")
    print(f"base attributes seeded at the plain-mortal 1.0: {', '.join(base_ids)}")
    verb = "would write" if report_only else "wrote"
    print(f"{verb} {would_write} RaceDef(s); skipped {skipped} already authored")
    if refusals:
        print(f"\nREFUSED {len(refusals)} species - staying lore-only rather than shipping a guess")
        for bare, reason in refusals:
            print(f"  {bare}: {reason}")
        print(
            "  a refused species has no RaceDef, so no character naming it can be selected. Each\n"
            "  one is a gap in the Lore Bible's attributes, not in this tool: it invents nothing."
        )
    for problem in problems:
        fail(problem)
    if problems:
        return 1
    ok("every transcribed stat key is declared in contracts/stat.gd")
    return 0
