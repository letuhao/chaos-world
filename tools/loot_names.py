"""Rewrite the loot catalogs' salvage display names so no raw realm id reaches a player.

The generator at `tools/acquisition/seed.py:475` builds a salvage pool's
`display_name` as::

    f"{graph.boss_display_name(boss_id) or boss_id} salvage ({realm_id})"

`realm_id` is an internal snake_case id, so every generated row shipped as
"Iron Sage salvage (dao_fruit)" — 5074 of them across the loot catalogs. The
ids are already English words (`dao_fruit`, `great_luo`, `spirit_severing`), so
the fix is a display transform, not new authored data.

This rewrites the VALUE of an existing catalog row and never touches its KEY:
the key is the stable, opaque id the data files reference, and AGENTS.md makes
re-keying a gate failure.

Run `uv run python -m tools loot names` to apply, `--check` to report, and
`--dry-run` to print a sample without writing.
"""

from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
LOCALE_DIR = REPO_ROOT / "game" / "locale"

# "Iron Sage salvage (dao_fruit)" -> group 1 boss text, group 2 realm id.
SALVAGE = re.compile(r"^(?P<prefix>.*?salvage \()(?P<id>[a-z0-9_]+)(?P<suffix>\).*)$")

# A realm id is only rewritten when it is an all-lowercase token with no
# punctuation: `dao_fruit` and the single-word `foundation` are both ids and
# both leak, so the underscore is NOT required. Anything carrying a space, a
# capital, or punctuation is already a name and is left alone, which makes a
# second run a no-op and keeps a hand-edited row intact.
RAW_ID = re.compile(r"^[a-z0-9_]+$")

# Exceptions to plain title case, keyed by id. A few of these are established
# cultivation terms whose English spelling is not the mechanical title case of
# the id, and a player reads them as words rather than as a capitalised id.
OVERRIDES = {
    "great_luo": "Great Luo",
    "du_mai": "Du Mai",
    "qi_refining": "Qi Refining",
    "dao_fruit": "Dao Fruit",
    "dao_ancestor": "Dao Ancestor",
}


def display_name(realm_id: str) -> str:
    """The player-facing name for a realm id."""
    if realm_id in OVERRIDES:
        return OVERRIDES[realm_id]
    return " ".join(word.capitalize() for word in realm_id.split("_"))


def rewrite(text: str) -> tuple[str, int]:
    """Return the rewritten catalog text and how many rows changed.

    Only the realm id between the parentheses is touched. Everything before it
    on the line — the key, the boss display name, the opening bracket — is
    copied through verbatim, so a row's KEY can never change.
    """
    changed = 0
    out = []
    for line in text.splitlines(keepends=True):
        match = SALVAGE.match(line.strip())
        if match and RAW_ID.match(match.group("id")):
            newline = "\n" if line.endswith("\n") else ""
            body = line[: len(line) - len(newline)]
            cut = body.index(match.group("prefix")) + len(match.group("prefix"))
            line = (
                body[:cut]
                + display_name(match.group("id"))
                + body[cut + len(match.group("id")) :]
                + newline
            )
            changed += 1
        out.append(line)
    return "".join(out), changed


def catalog_files() -> list[Path]:
    return sorted(
        p for p in LOCALE_DIR.glob("*.tres") if "salvage (" in p.read_text(encoding="utf-8")
    )


def _names(args) -> int:
    files = catalog_files()
    if not files:
        print("no catalog leaks a salvage realm id")
        return 0

    total = 0
    for path in files:
        original = path.read_text(encoding="utf-8")
        rewritten, changed = rewrite(original)
        total += changed
        if args.dry_run:
            shown = 0
            for old_line, new_line in zip(
                original.splitlines(), rewritten.splitlines(), strict=False
            ):
                if old_line != new_line and shown < args.sample:
                    print(f"  - {old_line.strip()[:120]}")
                    print(f"  + {new_line.strip()[:120]}")
                    shown += 1
            status = "would rewrite"
        else:
            if changed and not args.check:
                path.write_text(rewritten, encoding="utf-8", newline="")
            status = "would rewrite" if args.check else ("rewrote" if changed else "clean")
        print(f"{path.name}: {changed} row(s) {status}")

    print(f"\n{total} row(s) {'carry' if args.check else 'had'} a raw realm id")
    if args.check and total:
        print("run: uv run python -m tools loot names")
        return 1
    return 0


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "loot", help="loot content: names (drop a raw realm id from a salvage name)"
    )
    actions = parser.add_subparsers(dest="action", required=True)
    names = actions.add_parser(
        "names", help="rewrite salvage display names so no raw realm id reaches a player"
    )
    names.add_argument(
        "--check", action="store_true", help="report only; non-zero if any row leaks"
    )
    names.add_argument("--dry-run", action="store_true", help="print a sample, write nothing")
    names.add_argument("--sample", type=int, default=5, help="rows to print under --dry-run")
    names.set_defaults(func=_names)


def run(args) -> int:
    return args.func(args)
