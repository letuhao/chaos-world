"""Give every distinct-item group its own icon.

The corpus splits into two shapes of group, and only one of them is a grade
ladder. `ladders.py` handles those. This module handles everything else: chains
of 6+ seeds whose members are DISTINCT items rather than five grades of one
object.

Grouping rule is form, not seed. `U6_divine_withe_fillet` and `U6_earth_withe_fillet`
are one object at two grades and share an icon; `U6_divine_withe_grail` is a
different object and gets its own. The distinguishing token is everything after
the grade, so the group key is the tail. That yields ~2,061 families from 2,390
seeds, which is what carries the library past the 1,604 ceiling that ladder
splitting alone hits (8,020 seeds / 5 = 1,604, and a five-seed group can never
average below five seeds per family).

Palette and subject come from `subjects.py` and are assigned by position in the
sorted work list, not by a hash: a hash collides when a run draws many groups
from one subcategory and the icons come out indistinguishable.

Every icon still goes through `assets generate`, so the shared UNET, the RMBG
cutout, the 256 install and the index write-up stay on the audited path. This
module only decides which seeds share an icon and what to ask for.
"""

from __future__ import annotations

import collections
import re
import subprocess
import time
from pathlib import Path

from .. import assets
from .subjects import PALETTES, SUBJECTS, VALUE_WORDS

REPO = Path(__file__).resolve().parent.parent.parent

STAGES = {"base", "refined", "aged", "primed", "perfected"}
GRADES = {
    "mortal",
    "earth",
    "heaven",
    "spirit",
    "immortal",
    "divine",
    "primordial",
    "transcendent",
}

FRAMING = (
    "The complete object sits wholly inside the frame with wide empty margins on "
    "all four sides, a clear band of empty space all around it, nothing touching "
    "any edge. Painterly anime gouache, crisp dark ink contour, soft upper-left "
    "light, one clear identifying detail, readable silhouette at 32x32."
)


def display_names() -> dict[str, str]:
    """Seed id -> display_name, read from the .tres corpus."""
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
    """(family_id, subject_key, group_key, seeds) for every unsplit tail group."""
    items = assets._load_items()
    records = assets._load_index()
    issues: list[str] = []
    winners = assets._resolve(items, records, issues)
    existing = {record["id"] for record in records}
    names = display_names()

    chains: dict[tuple[str, str, str], list[str]] = collections.defaultdict(list)
    for item_id, meta in items.items():
        found = re.match(r"^([A-Za-z]+\d+)_", item_id)
        if found:
            chains[(meta["category"], meta["subcategory"], found.group(1))].append(item_id)
    ladders = {
        key
        for key, seeds in chains.items()
        if len(seeds) == 5 and all(s.rsplit("_", 1)[-1] in STAGES for s in seeds)
    }

    groups: dict[tuple[str, str, str], list[str]] = collections.defaultdict(list)
    for key, seeds in chains.items():
        if key in ladders or len(seeds) < 6:
            continue
        for item_id in seeds:
            parts = item_id.split("_")
            graded = len(parts) >= 2 and parts[1] in GRADES
            tail = "_".join(parts[2:] if graded else parts[1:])
            groups[(key[0], key[1], tail)].append(item_id)

    work: list[tuple[str, str, str, list[str]]] = []
    for (category, subcategory, tail), seeds in sorted(groups.items()):
        subject_key = f"{category}/{subcategory}"
        if subject_key not in SUBJECTS:
            continue
        # Skip when these seeds no longer all share one family: already split.
        resolved = {winners.get(seed) for seed in seeds}
        if len(resolved) != 1:
            continue
        # Skip when that family is already a SPECIFIC rule, not the broad
        # category/subcategory one. A seed can be claimed by a narrower family
        # that another sweep run created - `consumable-edelweiss-dao-broth` had
        # claimed the F15 poise seed - and the new family would then lose the
        # resolve, so the CLI rejects it as "does not win its selected matches".
        # Comparing against the broad id alone missed those and the run failed
        # on every attempt.
        broad = f"{category}-{subcategory.replace('_', '-')}-family"
        if resolved != {broad}:
            continue
        label = names.get(sorted(seeds)[0], tail)
        slug = re.sub(r"[^a-z0-9]+", "-", label.lower()).strip("-")
        family_id = f"{category}-{subcategory.replace('_', '-')}-{slug}"[:80]
        if family_id in existing:
            continue
        work.append((family_id, subject_key, tail, sorted(seeds)))
    return work


def run(args) -> int:
    work = discover()
    print(f"discovered {len(work)} unsplit groups; this run takes {min(args.limit, len(work))}")
    if args.dry_run:
        for family_id, subject_key, tail, seeds in work[: args.limit]:
            print(f"  {family_id:56} {subject_key:22} {len(seeds)} seeds  tail={tail[:24]}")
        return 0

    failures: list[str] = []
    todo = work[: args.limit]  # bounded; work is already materialised
    per_subject = collections.Counter()
    for index, (family_id, subject_key, tail, seeds) in enumerate(todo):
        palette, value = PALETTES[index % len(PALETTES)]
        # Walk the subject list per subcategory, but stride by a co-prime of its
        # length so a run that draws many groups from ONE subcategory still lands
        # on different objects. Two subjects per subcategory was not enough: a run
        # of 15 broth groups produced 15 near-identical corked bottles. Most groups
        # are singletons (1160 of 1194), so each one is the only member of its own
        # item and has to be distinguishable from its neighbours, not just valid.
        variants = SUBJECTS[subject_key]
        stride = 3 if len(variants) % 3 else 1
        variant = (per_subject[subject_key] * stride) % len(variants)
        per_subject[subject_key] += 1
        subject = variants[variant]
        slug = subject_key.split("/")[1].replace("_", "-")
        tag = re.sub(r"[^a-z0-9-]+", "-", f"{slug}-{tail}").strip("-")
        prompt = (
            f"Exactly one single {subject}, one object only, seen from DIRECTLY "
            f"ABOVE so that no ground plane appears beside it. {VALUE_WORDS[value]} "
            f"Predominantly {palette}; the pale highlight covers only a small "
            f"fraction of the object and the colour stays within that palette. "
            f"{FRAMING}"
        )
        command = [
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
            f"motif:{slug}-{variant}",
            "--visual-trait",
            f"palette:{tag}",
            "--seed",
            str(args.seed_base + index),
        ]
        for item_id in seeds:
            command += ["--match-item", item_id]

        started = time.monotonic()
        result = subprocess.run(command, cwd=REPO, capture_output=True, text=True)
        if result.returncode != 0:
            last = (result.stdout or result.stderr or "").strip().splitlines()[-1:]
            print(f"[{index + 1}/{len(todo)}] {family_id} FAILED {last}", flush=True)
            failures.append(family_id)
            continue
        elapsed = time.monotonic() - started
        print(f"[{index + 1}/{len(todo)}] {family_id} ok {elapsed:.0f}s", flush=True)

    print(f"\n=== group sweep summary ===\nran {len(todo)}, failures {len(failures)}")
    for name in failures:
        print(f"  FAIL {name}")
    print(f"remaining: {len(discover())}")
    return 1 if failures else 0
