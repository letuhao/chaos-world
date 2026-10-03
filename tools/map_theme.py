"""`uv run python -m tools map_theme check` — does every shipped theme still have prose?

`tools/map_assets.py:363` writes `environment_theme` into every row of
`game/assets/map-asset-index.jsonl` from `ENVIRONMENT_THEMES`. The prose is LOAD-BEARING:
it is pasted verbatim into ComfyUI prompts, so a theme value is not a label but the text
that renders an image. `migrate` cannot refresh an existing value, which means a theme
added to the index can never acquire its prose by re-running a migration.

That is not hypothetical. Commit `7bf3e4bc` shortened four `environment_theme` strings
to fit a line budget. The generator was never re-run, so 260+ index rows silently kept
prose the source no longer contained, and every gate in this repo stayed green: nothing
compared the two sides. `373ffd06` restored the text by value-preserving implicit
concatenation, which is also why `ruff format` must never be allowed to re-wrap it — the
formatter joins implicitly-concatenated literals that fit on one line, and a "fix" that
reverts is not a fix.

So the check is a set comparison in one direction only: every theme the INDEX names must
appear in the SOURCE. The reverse is deliberately not required — a source entry with no
index row is an unused theme, which is a content choice, not a defect, and failing on it
would make the gate cry wolf on the next theme authored before its art.
"""

from __future__ import annotations

import argparse
import json

from .common import GAME_DIR, ToolError, fail, info, ok
from .map_assets import ENVIRONMENT_THEMES

INDEX = GAME_DIR / "assets" / "map-asset-index.jsonl"


def index_themes() -> dict[str, int]:
    """Every `environment_theme` in the index, with how many rows carry it.

    A malformed line is counted and reported rather than skipped silently: the index is
    1235 rows of generated JSONL, and a row that stops parsing is a row whose prompt
    never renders, which is exactly the silent failure this guard exists to catch.
    """
    counts: dict[str, int] = {}
    if not INDEX.is_file():
        raise ToolError(f"{INDEX.relative_to(GAME_DIR)} is missing")
    for number, line in enumerate(INDEX.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except ValueError as exc:
            fail(f"{INDEX.relative_to(GAME_DIR)}:{number}: unparseable row ({exc})")
            continue
        theme = row.get("environment_theme")
        if isinstance(theme, str) and theme.strip():
            counts[theme] = counts.get(theme, 0) + 1
    return counts


def register(subparsers: argparse._SubParsersAction) -> None:
    parser = subparsers.add_parser(
        "map_theme",
        help="every environment_theme the index ships must still have its prose in source",
    )
    actions = parser.add_subparsers(dest="action", required=True)
    check = actions.add_parser("check", help="fail when a shipped theme has no prose")
    check.add_argument(
        "--fail-on",
        choices=("warn", "error"),
        default="error",
        help="'warn' reports without failing (default: error)",
    )


def run(args: argparse.Namespace) -> int:
    if args.action != "check":
        raise ToolError(f"unknown action {args.action}")

    counts = index_themes()
    if not counts:
        fail("the index names no environment_theme at all, so this check is vacuous")
        return 1

    rows = sum(counts.values())
    # The index stores the PROSE, not the environment key: map_assets.py:363 writes
    # `ENVIRONMENT_THEMES.get(record["environment"], "")`, so a row's environment_theme is
    # the value that was pasted into the prompt. Comparing it against the dict's KEYS
    # reports all 19 themes missing and is the one mistake available here - a name is not
    # the text a renderer receives.
    authored = set(ENVIRONMENT_THEMES.values())
    missing = {theme: n for theme, n in counts.items() if theme not in authored}
    known = len(ENVIRONMENT_THEMES)

    if missing:
        detail = (
            "Every one of these is prose the generator pasted into a prompt and can no "
            "longer reproduce, so re-running `map_assets migrate` will not repair the "
            "rows that already carry it. Restore the text in tools/map_assets.py by hand. "
            "Do NOT shorten it to fit a line budget: keep it as an implicitly-concatenated "
            "literal, because `ruff format` joins those and `tools fmt` will otherwise "
            "undo the fix (INC-0015, commits 7bf3e4bc then 373ffd06)."
        )
        for theme, count in sorted(missing.items(), key=lambda kv: -kv[1]):
            info(f"  {count:>5} row(s)  {theme!r}")
        if args.fail_on == "error":
            fail(f"{detail} {sum(missing.values())} row(s) over {len(missing)} theme(s)")
            return 1
        info(detail)
        return 0

    ok(
        f"every environment_theme the index ships ({len(counts)} distinct over {rows} "
        f"rows) has prose in map_assets.py ({known} themes authored) - INC-0015"
    )
    return 0
