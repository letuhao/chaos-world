"""Prove the difficulty guard fires: mutate a throwaway copy, assert each rule (ADR 0129).

Run by hand; `tools difficulty check` is the gate. A guard nobody has seen fire is not a
guard (ADR 0098), and this is how the six rules are shown to actually catch their defect.

Every case writes to a scratch file under the session temp dir and never touches the authored
table: AGENTS.md records INC-0007, where another agent's commit captured a live mutation probe
into history where the working-tree guard could not see it.
"""

from __future__ import annotations

import shutil
import sys
import tempfile
from pathlib import Path

from tools import difficulty
from tools.common import ToolError, fail, ok

MUTATIONS: tuple[tuple[str, str, str], ...] = (
    (
        "a_missing_scalar",
        '"loot_ceiling": 1.0,',
        "",
    ),
    (
        "a_sixth_column",
        '"tribulation_preparation_credit": 1.0\n},',
        '"tribulation_preparation_credit": 1.0,\n"loot_yield": 1.2\n},',
    ),
    (
        "a_realm_shaped_column",
        '"tribulation_preparation_credit": 1.0\n},',
        '"tribulation_preparation_credit": 1.0,\n"realm_bonus": 1.2\n},',
    ),
    (
        "a_drifted_neutral_row",
        '"soul_damage_share": 1.0,\n"death_loss_cap": 1.0,\n"guardian_effectiveness": 1.0,\n'
        '"loot_ceiling": 1.0,\n"tribulation_preparation_credit": 1.0\n},\n&"hard"',
        '"soul_damage_share": 0.95,\n"death_loss_cap": 1.0,\n"guardian_effectiveness": 1.0,\n'
        '"loot_ceiling": 1.0,\n"tribulation_preparation_credit": 1.0\n},\n&"hard"',
    ),
    (
        "an_unordered_ladder",
        '"soul_damage_share": 1.5,',
        '"soul_damage_share": 0.9,',
    ),
    (
        "an_out_of_bounds_scalar",
        '"death_loss_cap": 1.5,',
        '"death_loss_cap": 400.0,',
    ),
)


def _mutate(source: Path, target: Path, find: str, replace: str) -> bool:
    text = source.read_text(encoding="utf-8")
    if find not in text:
        return False
    target.write_text(text.replace(find, replace, 1), encoding="utf-8")
    return True


def run(argv: list[str] | None = None) -> int:
    authored = difficulty.GAME_DIR / difficulty.TABLE_REL
    if not authored.is_file():
        fail(f"{authored} not found")
        return 1
    real_game_dir = difficulty.GAME_DIR
    scratch = Path(tempfile.mkdtemp(prefix="difficulty-guard-"))
    # `TABLE_REL` is relative to `GAME_DIR`, so the fake game dir must reproduce the two
    # directories under it — pointing GAME_DIR at a flat scratch dir would miss the file and
    # every case would "pass" by reading nothing, which is the failure this whole file exists
    # to rule out.
    fake_game = scratch / "game"
    table_dir = fake_game / Path(difficulty.TABLE_REL).parent
    table_dir.mkdir(parents=True, exist_ok=True)
    # The pristine copy lives OUTSIDE `table_dir`, because each case clears that directory so
    # `read_table` sees exactly one preset table — a source inside it would be deleted before
    # the second case ran, and every later case would then "pass" by finding nothing.
    pristine = scratch / "pristine.tres"
    shutil.copy(authored, pristine)
    failures = 0
    try:
        for name, find, replace in MUTATIONS:
            target = table_dir / "difficulty_table.tres"
            if not _mutate(pristine, target, find, replace):
                fail(f"{name}: the mutation no longer matches the table - update it")
                failures += 1
                continue
            for sibling in table_dir.glob("*.tres"):
                if sibling != target:
                    sibling.unlink()
            difficulty.GAME_DIR = fake_game
            try:
                presets = difficulty.read_table()
            except ToolError as exc:
                # The parser refused it outright, which is a stronger catch than a warning.
                ok(f"guard fires on {name} (the parser refused it: {exc})")
                continue
            difficulty.GAME_DIR = fake_game
            verdict = difficulty._check(argparse_shim())
            if verdict == 0:
                fail(f"guard did NOT fire on {name} (parsed {sorted(presets)})")
                failures += 1
            else:
                ok(f"guard fires on {name}")
    finally:
        difficulty.GAME_DIR = real_game_dir
        shutil.rmtree(scratch, ignore_errors=True)
    if failures:
        fail(f"difficulty guard: {failures} mutation(s) went uncaught")
        return 1
    ok(f"difficulty guard fires on all {len(MUTATIONS)} mutations")
    return 0


def argparse_shim():
    """`_check` reads no arguments; a shim keeps the signature honest without argparse."""
    return None


if __name__ == "__main__":
    sys.exit(run())
