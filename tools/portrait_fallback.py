"""Generate the committed fallback face for every authored body plan (ADR 0238).

A fallback exists so an authored `PortraitDef` never names a layer that is absent from the
repository. The art supply is untracked by policy (`.gitignore:8`), which without this leaves every
portrait an empty box on a clean clone — the seventeen that resolve on a developer's machine look
finished locally and are blank everywhere else.

What it draws is deliberately NOT art: a flat head-and-shoulders silhouette with no face, on a
transparent ground, at the `dialogue_portrait` install canvas from `character_assets.py:268`. A
silhouette cannot be mistaken for a render, so the difference between a fallback and real art stays
visible instead of being inferred.

The tint is DERIVED from each body's dominant `affinities` entry rather than authored per portrait,
because a fallback identifies the body plan and not the individual: two bodies sharing a dominant
affinity share a tint, which is correct. A body with no dominant affinity is neutral grey.

Deterministic and offline. It never contacts the image service, never reads a render, and never
overwrites a real render: it refuses any target that already exists, so running it twice cannot
replace authored art with a placeholder.

Usage: `uv run python -m tools portrait_fallback --write`
"""

from __future__ import annotations

import re

from . import unique_characters
from .character_bundle_sync import bare_id
from .common import GAME_DIR, ToolError, fail, info, ok

#: Where committed fallbacks live, and the one subdirectory `.gitignore:8` does NOT swallow.
FALLBACK_ROOT = GAME_DIR / "assets" / "characters" / "portraits"

#: The `dialogue_portrait` install canvas (`character_assets.py:268`). Matching it means a fallback
#: can be swapped for a real portrait by editing one path, with no canvas change and no re-import of
#: a differently-sized image.
CANVAS = (384, 512)

#: Dominant affinity -> RGB. Values are chosen to read as a hue at a glance and to sit clearly
#: apart from each other; none is the ivory/ash/jade/brass family `art_fidelity` measures real art
#: against, so a fallback can never be mistaken for a passing render.
AFFINITY_RGB = {
    "fire": (198, 84, 52),
    "earth": (150, 116, 72),
    "water": (72, 122, 156),
    "ice": (140, 176, 196),
    "wood": (96, 138, 96),
    "metal": (140, 144, 150),
}

#: Used when no affinity dominates. `commonborn` carries all six at 2.0, so it has no dominant
#: entry and must not inherit one body's identity by accident.
NEUTRAL_RGB = (150, 148, 145)


def _ranked_affinity_rgb(pairs: list[tuple[str, str]]) -> tuple[int, int, int]:
    """The colour for the top affinity, or neutral when there is no single one.

    Shared by both sources below so the two cannot disagree about what "dominant" means — the same
    reason `_visual_traits` is shared between `build_def` and `_fallback_def`, where a retyped copy
    reproduced the exact ambiguity it was written to prevent.

    A tie yields NEUTRAL rather than the first in alphabetical order, because a body with two equal
    affinities has no single identity and must not be handed one by a sort.
    """
    if not pairs:
        return NEUTRAL_RGB
    # `max` over a materialised list; ties resolve to the first in authored order, so the result is
    # deterministic rather than dependent on dict ordering.
    ranked = sorted(pairs, key=lambda item: (-float(item[1]), item[0]))
    top = ranked[0]
    rgb = AFFINITY_RGB.get(top[0], NEUTRAL_RGB)
    if len(ranked) > 1 and float(ranked[1][1]) == float(top[1]):
        return NEUTRAL_RGB
    return rgb


def catalog_races() -> list[str]:
    """Every body-plan id the character catalog actually names, bare.

    Read from the catalog rather than from either race table, because the question this tool answers
    is "which faces must exist for the shipped cast", and the cast is the only thing that makes a
    fallback reachable. Measured: 401 characters name 30 species, of which only 4 have a `.tres`,
    so a tool driven by the race table alone derives 5 faces and leaves 347 characters unable to
    publish anything at all.
    """
    ids: set[str] = set()
    for record in unique_characters.readable_catalog():
        if not isinstance(record, dict):
            continue
        race = bare_id(str((record.get("appearance") or {}).get("race", "")))
        if race:
            ids.add(race)
    return sorted(ids)


def lore_races() -> dict[str, tuple[int, int, int]]:
    """`(bare_id, rgb)` for every `races.<id>` entity the Lore Bible carries.

    The Bible is the single authoring surface for a species (ADR 0253), so it is the right source
    for a species that has no `RaceDef` yet — reading it here means a fallback tint is TRANSCRIBED
    from authored affinities rather than invented per species.

    An affinity with no entry in [constant AFFINITY_RGB] — `dark`, `light`, `wind`, which 15 of the
    30 species lead with — yields neutral rather than a colour invented here. Assigning an element
    a hue is art direction, and `docs/art-direction.md` is where that belongs; this tool will not
    decide it. Those species therefore share the neutral placeholder, which is the honest reading of
    "no colour identity assigned yet".
    """
    try:
        from .lore.model import load_bible
    except ImportError as error:
        raise ToolError(
            f"cannot read the Lore Bible ({error}); refusing to invent fallback tints"
        ) from error
    bible = load_bible()
    out: dict[str, tuple[int, int, int]] = {}
    for key, entity in bible.entities.items():
        if not str(key).startswith("races.") or not isinstance(entity, dict):
            continue
        affinities = (entity.get("attributes") or {}).get("affinities") or {}
        pairs = [(str(name), str(value)) for name, value in affinities.items()]
        out[str(key).removeprefix("races.")] = _ranked_affinity_rgb(pairs)
    return out


def authored_races() -> list[tuple[str, tuple[int, int, int]]]:
    """`(race_id, rgb)` for every body plan the shipped cast can name.

    Two sources, in precedence order, and the ORDER IS THE RULE:

    1. **`game/data/races/*.tres`** — an authored `RaceDef`. The game already reads these, so an
       authored affinity outranks the Bible wherever the two disagree.
    2. **The Lore Bible's `races.<id>` entities** — for every species the catalog names that has no
       `RaceDef`. Added because the cast names 30 species against a race table of 5, so the table
       alone leaves 347 of 401 characters with no fallback and therefore nothing publishable.

    Text rather than `load()` for the reason `PortraitCatalog` reads its tree by text: this process
    has no Godot runtime, and a `.tres` of another type in the same directory must be skipped rather
    than mis-cast. `sorted` over a materialised listing so the order never depends on the
    filesystem, and the two sources are merged into ONE sorted list so two runs cannot emit
    different files in a different order.
    """
    root = GAME_DIR / "data" / "races"
    if not root.is_dir():
        raise ToolError(f"{root} does not exist; the race table is the source of body plans")
    found: dict[str, tuple[int, int, int]] = {}
    for path in sorted(root.glob("*.tres")):
        text = path.read_text(encoding="utf-8", errors="replace")
        race_id = re.search(r'^id = &"([^"]+)"', text, re.MULTILINE)
        affinities = re.search(r"^affinities = \{(.+)\}\s*$", text, re.MULTILINE)
        if race_id is None or affinities is None:
            continue
        pairs = re.findall(r'"(\w+)":\s*([0-9.]+)', affinities.group(1))
        found[race_id.group(1)] = _ranked_affinity_rgb(pairs)
    for race_id, rgb in lore_races().items():
        # Authored wins. `setdefault` is the whole of that rule, so it cannot be forgotten below.
        found.setdefault(race_id, rgb)
    return sorted(found.items())


def draw_silhouette(rgb: tuple[int, int, int]):
    """A head-and-shoulders RGBA silhouette at [CANVAS], transparent outside the figure.

    Drawn from primitives rather than traced from a render: a fallback that resembles a specific
    person is a fallback that will eventually be mistaken for them. Two ellipses and a rounded
    shoulder mass give a readable bust at any size, and the shape is identical across every body so
    the ONLY thing that varies is the tint the body plan earned.
    """
    from PIL import Image, ImageDraw

    width, height = CANVAS
    image = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    fill = (rgb[0], rgb[1], rgb[2], 255)
    # Shoulders: a wide ellipse whose top edge sits below the head, so the neck reads as a gap
    # between two masses rather than one blob.
    draw.ellipse((width * 0.06, height * 0.52, width * 0.94, height * 1.30), fill=fill)
    # Head.
    draw.ellipse((width * 0.30, height * 0.16, width * 0.70, height * 0.62), fill=fill)
    return image


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "portrait_fallback",
        help="generate the committed fallback face for every authored body plan (ADR 0238)",
    )
    actions = parser.add_subparsers(dest="portrait_fallback_action", required=True)
    actions.add_parser(
        "report", help="list the body plans and the tint each would get; writes nothing"
    )
    write = actions.add_parser("write", help="write any fallback that does not already exist")
    write.add_argument(
        "--force",
        action="store_true",
        help="overwrite an existing file — refuses by default so real art is never replaced",
    )


def run(args) -> int:
    races = authored_races()
    if not races:
        fail("no RaceDef found; nothing to derive a fallback from")
        return 1
    if args.portrait_fallback_action == "report":
        print(f"fallback root: {FALLBACK_ROOT}")
        print(f"canvas: {CANVAS[0]}x{CANVAS[1]} (the dialogue_portrait install geometry)")
        for race_id, rgb in races:
            target = FALLBACK_ROOT / f"{race_id}.png"
            state = "EXISTS" if target.is_file() else "absent"
            print(f"  {race_id:<22} rgb{rgb}  {state}")
        ok(f"{len(races)} authored body plan(s)")
        return 0

    written: list[str] = []
    kept: list[str] = []
    for race_id, rgb in races:
        target = FALLBACK_ROOT / f"{race_id}.png"
        if target.is_file() and not args.force:
            kept.append(race_id)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        draw_silhouette(rgb).save(target, format="PNG", optimize=True)
        written.append(race_id)
    for race_id in kept:
        info(f"{race_id}.png already exists; left alone (pass --force to overwrite)")
    ok(f"wrote {len(written)} fallback face(s) to {FALLBACK_ROOT}")
    for race_id in written:
        print(f"  {race_id}.png")
    return 0
