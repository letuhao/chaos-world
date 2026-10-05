"""Sweep every unsplit grade ladder in the relabelled consumable block.

Discovers the remaining five-seed ladders whose seeds all still sit on the broad
category family, and gives each its own icon. This is the scalable path to the
MIN_UNIQUE_IMAGE_TARGET floor: one render converts one ladder from "shares a
generic image" to "has its own image", and the seeds move onto a specific
id_prefix rule that outranks the broad one.

Resumable: a ladder whose family already exists in the index is skipped, so an
interrupted run can be repeated safely.

Palette choice is deterministic from a stable hash of the prefix, so a re-run
reproduces the same art instead of drifting. Only one of the twelve palettes is
green, which keeps jade under the art-direction ceiling of two per eight.

The work list is materialised before the loop and never grows, so the loop
bound is fixed and it always terminates. Failures are recorded and the sweep
continues; a single bad theme word must not abandon 116 good ladders.
"""

from __future__ import annotations

import collections
import math
import re
import subprocess
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent

from .. import assets  # noqa: E402

STAGES = {"base", "refined", "aged", "primed", "perfected"}
SUBCATEGORIES = [
    "formula",
    "draft",
    "scroll",
    "mantra",
    "treaty",
    "jade_slip",
    "rite",
    "grimoire",
    "sigil",
    "manual",
]

# Two subject variants per subcategory so a block does not read as one repeated
# object, chosen by the same stable hash as the palette.
SUBJECTS = {
    "formula": [
        "a single carved stone tablet lying FLAT and viewed from DIRECTLY ABOVE, so the "
        "camera looks straight down on its broad face and no ground or surface can appear "
        "beside it. One thick slab of stone with a flat top face ruled by a shallow "
        "engraved square grid of straight lines, its four chipped edges visible around the face",
        "a single carved stone tablet lying FLAT and viewed from DIRECTLY ABOVE. One thick "
        "slab of stone with a flat top face bearing one deeply incised circular seal and a "
        "ring of short radiating grooves around it, chipped edges all round",
    ],
    "draft": [
        "a single open codex lying flat: a thick book opened wide with both covers spread "
        "and a blank unmarked page block between them",
        "a single closed folio standing upright on its fore edge: one thick book with "
        "covers meeting in a clean square spine and a clasp at the throat",
    ],
    "scroll": [
        "a single wide scroll partly unrolled: a broad sheet of heavy paper curving away "
        "from a plain cylindrical roller at the top",
        "a single narrow scroll standing rolled: a tight cylinder of paper bound by one "
        "plain cord, its ends showing as concentric rings",
    ],
    "mantra": [
        "a single narrow mantra strip rolled into a tight scroll, one end tied with a "
        "short cord, the paper surface blank and unmarked",
        "a single folded mantra leaf: a small square of heavy paper folded once along its "
        "diagonal and pierced by one round hole",
    ],
    "treaty": [
        "a single folded treaty sheet: a broad rectangle of heavy paper folded twice, "
        "bound by one plain cord and closed with one round wax seal",
        "a single treaty tablet: a thin flat rectangle of dark stone with a shallow "
        "engraved border line running just inside its rim",
    ],
    "jade_slip": [
        "a single flat stone slip: one thin upright tablet with rounded corners and a "
        "shallow carved channel running its length",
        "a single flat stone slip: one thin upright tablet of banded stone with a row of "
        "small drilled holes along one edge",
    ],
    "rite": [
        "a single shallow rite bowl on a short foot: a wide open mouth, a plain rolled lip "
        "and one incised band below it",
        "a single rite token: a flat upright plate shaped as one symmetrical pair of "
        "upswept wings meeting at a central ridge",
    ],
    "grimoire": [
        "a single thick bound grimoire standing closed and upright: a heavy board-book "
        "with a cracked spine, a frayed cloth cover and one broad clasp",
        "a single thick grimoire standing upright and open: a heavy book on its fore edge "
        "with covers spread and a blank unmarked page block between them",
    ],
    "sigil": [
        "a single carved sigil disc: a flat round stone disc split by one vertical cleft, "
        "ring grain visible, its rim left rough",
        "a single carved sigil ring: a flat open circle of stone with a shallow spiral "
        "channel cut around its inner edge",
    ],
    "manual": [
        "a single bound manual standing closed and upright: a thick rectangular volume "
        "with a plain board cover and one spine band",
        "a single bound manual standing upright and open: a thick book on its fore edge "
        "with covers spread and a blank unmarked page block between them",
    ],
}

# Twelve hue-spread palettes; exactly one is green, to stay under the
# art-direction ceiling of two jade icons per eight.
PALETTES = [
    ("charcoal, black and cold silver", "a very dark object"),
    ("deep indigo, violet and cold white", "a mid-dark object"),
    ("sienna, burnt orange and ochre", "a warm mid object"),
    ("onyx black, charcoal and thin white banding", "a very dark object"),
    ("copper, rust orange and dull tan", "a warm mid object"),
    ("slate blue, black and cold grey", "a very dark object"),
    ("antique gold, ivory and pale brass", "a warm mid object"),
    ("oxblood, deep crimson and bone white", "a very dark object"),
    ("chalk white, pale grey and cold silver", "a pale luminous object"),
    ("umber, oxblood and faded tan", "a mid-dark object"),
    ("pale rose white, ivory and faint silver", "a pale luminous object"),
    ("deep bottle green, black and cold jade", "a mid-dark object"),
]

VALUE_WORDS = {
    "a very dark object": (
        "The whole object sits in the dark half of the value range and only the raised "
        "edges catch a thin highlight."
    ),
    "a low-key dark object": (
        "The whole object sits in the dark half of the value range and only the raised "
        "edges catch a thin highlight."
    ),
    "a mid-dark object": (
        "The object stays below the light half of the value range; only the top edge and "
        "one facet catch a thin highlight."
    ),
    "a pale luminous object": (
        "The object is the brightest thing in frame, glowing softly from within."
    ),
    "a warm mid object": (
        "The object stays in the middle of the value range with one clear lit top plane "
        "and a darker underside."
    ),
}

FRONT_VIEW = (
    "Straight-on view, upright and centred. The complete object sits wholly inside the "
    "frame with wide empty margins on all four sides, a clear band of empty space all "
    "around it, nothing touching any edge."
)


def display_names() -> dict[str, str]:
    names: dict[str, str] = {}
    for path in (REPO / "game" / "data" / "items").rglob("*.tres"):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        found = re.search(r'^id = &"([^"]+)"', text, re.M)
        label = re.search(r'^display_name = "([^"]+)"', text, re.M)
        if found:
            names[found.group(1)] = label.group(1) if label else "?"
    return names


def discover() -> list[tuple[str, str, str, list[str]]]:
    """(family_id, subcategory, prefix, seeds) for every ladder still unsplit."""
    items = assets._load_items()
    records = assets._load_index()
    issues: list[str] = []
    winners = assets._resolve(items, records, issues)
    existing = {r["id"] for r in records}
    names = display_names()

    work: list[tuple[str, str, str, list[str]]] = []
    for sub in SUBCATEGORIES:  # fixed list
        broad = f"consumable-{sub.replace('_', '-')}-family"
        chains: dict[str, list[str]] = collections.defaultdict(list)
        for item_id, meta in items.items():
            if meta["category"] != "consumable" or meta["subcategory"] != sub:
                continue
            match = re.match(r"^([A-Za-z]+\d+)_", item_id)
            if match:
                chains[match.group(1)].append(item_id)
        for prefix, seeds in sorted(chains.items()):
            seeds.sort()
            # Whole five-stage ladder only.
            if not all(s.rsplit("_", 1)[-1] in STAGES for s in seeds):
                continue
            # Every seed must still sit on the broad family, or it is already split.
            if {winners.get(s) for s in seeds} != {broad}:
                continue
            slug = re.sub(r"[^a-z0-9]+", "-", names.get(seeds[0], prefix).lower()).strip("-")
            slug = re.sub(r"-(aged|base|refined|primed|perfected)$", "", slug)
            family_id = f"consumable-{sub.replace('_', '-')}-{slug}"[:80]
            if family_id in existing:
                continue
            work.append((family_id, sub, prefix, seeds))
    return work


def run(args) -> int:
    work = discover()
    print(f"discovered {len(work)} unsplit ladders; this run takes {min(args.limit, len(work))}")
    if args.dry_run:
        for family_id, sub, prefix, seeds in work[: args.limit]:
            print(f"  {family_id:58} {sub:10} {prefix} {len(seeds)} seeds")
        return 0

    failures: list[str] = []
    todo = work[: args.limit]  # bounded slice; the list itself is already fixed
    # Palette and subject are assigned by POSITION, not by hash. A hash made reruns
    # reproducible but collided: run 2 drew many ladders from one subcategory and the
    # draft books came out near-identical. Position still reproduces for a given work
    # list, because the list is sorted, but it also guarantees adjacent icons differ.
    per_sub = collections.Counter()
    for index, (family_id, sub, _prefix, seeds) in enumerate(todo):
        palette, value = PALETTES[index % len(PALETTES)]
        variants = SUBJECTS[sub]
        count = len(variants)
        stride = next(s for s in (5, 3, 2) if s < count and math.gcd(s, count) == 1)
        variant = (per_sub[sub] * stride) % count
        per_sub[sub] += 1
        subject = variants[variant]
        tag = re.sub(r"[^a-z0-9-]+", "-", family_id.rsplit("-", 1)[-1]).strip("-")
        seed = args.seed_base + index
        prompt = (
            f"Exactly one single {subject}, one object only. {VALUE_WORDS[value]} "
            f"Predominantly {palette}; the pale highlight covers only a small fraction of "
            f"the object and the colour stays strictly within that palette. {FRONT_VIEW} "
            "Painterly anime gouache, crisp dark ink contour, soft upper-left light, one "
            "clear identifying detail, readable silhouette at 32x32."
        )
        cmd = [
            "uv",
            "run",
            "python",
            "-m",
            "tools",
            "assets",
            "generate",
            "--family-id",
            family_id,
            "--prompt",
            prompt,
            "--size",
            "1024",
            "--target-size",
            "256",
            "--visual-trait",
            f"form:{tag}",
            "--visual-trait",
            f"motif:{sub.replace('_', '-')}-{variant}",
            "--visual-trait",
            f"palette:{tag}",
            "--seed",
            str(seed),
        ]
        for item_id in seeds:
            cmd += ["--match-item", item_id]

        # An install with no index record is left by a run killed between the two
        # writes, and would otherwise fail this family forever with
        # "refusing to overwrite", so clear it and let the render redo both.
        if assets.clear_unreferenced_install(family_id):
            print(
                f"[{index + 1}/{len(todo)}] {family_id} cleared an unreferenced "
                "install from an interrupted run",
                flush=True,
            )

        started = time.monotonic()
        result = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
        if result.returncode != 0:
            tail = (result.stdout or result.stderr or "").strip().splitlines()[-1:]
            print(f"[{index + 1}/{len(todo)}] {family_id} FAILED {tail}", flush=True)
            failures.append(family_id)
            continue
        print(
            f"[{index + 1}/{len(todo)}] {family_id} ok {time.monotonic() - started:.0f}s",
            flush=True,
        )

    print(f"\n=== sweep summary ===\nran {len(todo)}, failures {len(failures)}")
    for name in failures:
        print(f"  FAIL {name}")
    print(f"remaining undiscovered: {len(discover())}")
    return 1 if failures else 0
