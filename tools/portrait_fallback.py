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

import argparse
import re
from pathlib import Path

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


def authored_races() -> list[tuple[str, tuple[int, int, int]]]:
    """`(race_id, rgb)` for every `RaceDef`, read as TEXT.

    Text rather than `load()` for the reason `PortraitCatalog` reads its tree by text: this process
    has no Godot runtime, and a `.tres` of another type in the same directory must be skipped rather
    than mis-cast. `sorted` over a materialised listing so the order never depends on the filesystem.
    """
    root = GAME_DIR / "data" / "races"
    if not root.is_dir():
        raise ToolError(f"{root} does not exist; the race table is the source of body plans")
    found: list[tuple[str, tuple[int, int, int]]] = []
    for path in sorted(root.glob("*.tres")):
        text = path.read_text(encoding="utf-8", errors="replace")
        race_id = re.search(r'^id = &"([^"]+)"', text, re.MULTILINE)
        affinities = re.search(r"^affinities = \{(.+)\}\s*$", text, re.MULTILINE)
        if race_id is None or affinities is None:
            continue
        pairs = re.findall(r'"(\w+)":\s*([0-9.]+)', affinities.group(1))
        if not pairs:
            found.append((race_id.group(1), NEUTRAL_RGB))
            continue
        # `max` over a materialised list; ties resolve to the first in authored order, so a body
        # with two equal affinities is deterministic rather than dependent on dict ordering.
        ranked = sorted(pairs, key=lambda item: (-float(item[1]), item[0]))
        top = ranked[0]
        rgb = AFFINITY_RGB.get(top[0], NEUTRAL_RGB)
        if len(ranked) > 1 and float(ranked[1][1]) == float(top[1]):
            # Two affinities tied for the top: the body has no single identity, so it gets none.
            rgb = NEUTRAL_RGB
        found.append((race_id.group(1), rgb))
    return found


def draw_silhouette(rgb: tuple[int, int, int]) -> "Image.Image":  # noqa: F821
    """A head-and-shoulders silhouette at [CANVAS], transparent outside the figure.

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
