"""Split item asset families so every seed reaches its own icon.

`MIN_UNIQUE_IMAGE_TARGET` wants 2,000 unique item images against 8,020 seeds,
which is 4 seeds per family. Two different shapes of group get there, and they
need different rules:

    ladders  five-seed grade ladders (base/refined/aged/primed/perfected). Five
             seeds of ONE object type, so the ladder takes a single icon.
             Splitting only these caps at 1604 families, because a five-seed
             group can never average below five seeds per family.
    groups   everything else with 6+ seeds, where members are DISTINCT items
             rather than grade variants. Group these by form, not per seed, so
             two grades of one object share art while two different objects do
             not. This is where the headroom above 1604 actually is.

Both actions are resumable: a group whose family already exists in the index is
skipped, so an interrupted run can simply be repeated. Palette and subject are
assigned by position in the sorted work list rather than by a hash, because a
hash collides when a run draws many groups from one subcategory and the icons
come out indistinguishable - see the note in the ladder module.

Every icon still goes through `assets generate`, so the shared UNET, the RMBG
cutout, the 256 install and the index write-up are the audited path. This tool
only decides *which* seeds share an icon and *what* to ask for.
"""

from __future__ import annotations

from ..common import fail, ok  # noqa: F401  re-exported for sibling tool modules


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "assets-sweep", help="split item asset families toward the unique-image floor"
    )
    actions = parser.add_subparsers(dest="assets_sweep_action", required=True)
    for name, help_text in (
        ("ladders", "give each five-seed grade ladder its own icon"),
        ("groups", "give each distinct-item group its own icon"),
    ):
        action = actions.add_parser(name, help=help_text)
        action.add_argument("--limit", type=int, default=16, help="max groups this run")
        action.add_argument("--seed-base", type=int, default=10_000_000)
        action.add_argument("--dry-run", action="store_true", help="list without rendering")


def run(args) -> int:
    if args.assets_sweep_action == "ladders":
        from . import ladders
    else:
        from . import groups as ladders  # same contract: discover() plus run(args)

    return ladders.run(args)
