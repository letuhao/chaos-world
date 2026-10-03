"""Mutation probes for the body-cultivation balance guards.

`cultivation validate` asserting clean proves only that today's data happens to
satisfy the rules. It does not prove the rules can FAIL. A guard that has never
been seen red is indistinguishable from a guard that cannot fire, and the whole
class of defect here — a band that silently collapsed, a gate nobody had to meet —
is exactly what a vacuous assertion hides.

So each rule gets a mutation: a copy of the tree with one authored number broken in
the way that rule exists to catch, validated against that copy, and asserted to be
caught. The mutations are applied to a TEMPORARY COPY and the real data is never
touched; `run` restores nothing because it never changed anything.

Run it with `uv run python -m tools cultivation mutate`.
"""

from __future__ import annotations

import re
import shutil
import tempfile
from pathlib import Path

from ..common import ToolError, info, ok
from . import audit, report
from .report import REALM_DIR
from .seed import realms as ladder_realms

# realm id -> (scalar, broken value, the finding prefix that must fire)
#
# One per guard, each breaking a DIFFERENT number so a rule cannot pass by accident
# on a neighbour's mutation. The values are chosen to be reachable states of the
# data, not absurd numbers: the guards must fire on plausible edits, or they will not
# fire on the plausible edit a designer actually makes.
MUTATIONS: tuple[tuple[str, str, str, str], ...] = (
    # `chance_base` climbing above the ceiling is what the ORIGINAL degenerate band
    # was. Re-running that exact shape must fail.
    ("primordial_origin", "chance_base", "0.95", "degenerate_chance_band"),
    # A gate pinned onto the previous realm's ceiling leaves zero span, which is the
    # condition the shipped data had at every realm. qi_refining's own ceiling is 0.62.
    ("foundation", "quality_required", "0.620000", "quality_gate_no_headroom"),
    # A gate above the ceiling makes the realm unreachable.
    ("foundation", "quality_required", "0.700000", "gate_above_previous_ceiling"),
    # A gate at the quality a fresh huyệt already carries is passed without training.
    # That is what the first eight breakthroughs did (0.400-0.490 against a fresh 0.5).
    ("qi_refining", "quality_required", "0.400000", "gate_below_fresh_quality"),
    # Same rule, mid-ladder, where a huyệt newly unlocked also arrives at 0.5.
    ("spirit_sea", "quality_required", "0.500000", "gate_below_fresh_quality"),
    # The ladder grants physique for itself; a floor under that grant can never bind.
    ("great_luo", "physique_required", "10.0", "body_physique_gate_dead"),
    # A certainty ceiling retires the deviation loop.
    ("qi_refining", "chance_cap", "1.0", "guaranteed success"),
    # The duplicate-ladder defect: re-authoring a derived value is stale data, and it is
    # an INSERTION rather than a substitution because the field no longer exists.
    ("qi_refining", "+work_required", "40.0", "derived value"),
    ("qi_refining", "+acupoint_work", "10.0", "derived value"),
)


def _with_broken_scalar(seeds: Path, realm_id: str, scalar: str, value: str) -> None:
    """Break one scalar in one seed of a throwaway copy of the seed directory.

    A `+` prefix INSERTS the line instead of replacing one. That is how a field which
    no longer exists is exercised: the duplicate-ladder rule exists to catch a stale
    authored `work_required`, so the probe has to write one back.
    """
    target = seeds / f"{realm_id}.tres"
    if not target.is_file():
        raise ToolError(f"no realm seed to mutate: {target}")
    text = target.read_text(encoding="utf-8")
    if scalar.startswith("+"):
        field = scalar[1:]
        if re.search(rf"(?m)^{field} = ", text):
            raise ToolError(f"{realm_id} already declares `{field}`; the insert probe is void")
        broken, count = re.subn(
            rf"(?m)^(id = &\"{realm_id}\")$", f"\\1\n{field} = {value}", text, count=1
        )
    else:
        broken, count = re.subn(rf"(?m)^{scalar} = -?[\d.]+$", f"{scalar} = {value}", text, count=1)
    if count != 1:
        raise ToolError(f"{realm_id}: could not break `{scalar}` in the staged seed")
    target.write_text(broken, encoding="utf-8")


def _validate_against(seeds: Path | None) -> list[str]:
    """`audit.validate` reading realm seeds from `seeds`, or from the real tree.

    Only the seed directory is overridden. Every other content directory — items,
    recipes, meridians, acupoints, the qi path — is untouched by these mutations, so
    copying the whole of `game/data` would stage thousands of files to change thirty.
    The override covers `report` too, because that is the module holding the directory
    `audit` resolves seeds through.

    Nothing here writes to the repo: `audit` and `report` only read.
    """
    if seeds is None:
        return audit.validate()
    saved = (audit.REALM_DIR, report.REALM_DIR)
    audit.REALM_DIR = seeds
    report.REALM_DIR = seeds
    try:
        return audit.validate()
    finally:
        audit.REALM_DIR, report.REALM_DIR = saved


def _stage() -> Path:
    """A throwaway copy of the realm seed directory."""
    staged = Path(tempfile.mkdtemp(prefix="chaos_world_mutate_")) / "realms"
    shutil.copytree(REALM_DIR, staged)
    return staged


def run() -> int:
    realms = {realm_id for realm_id, _name, _tier in ladder_realms()}
    for realm_id, _scalar, _value, _prefix in MUTATIONS:
        if realm_id not in realms:
            raise ToolError(f"mutation names {realm_id}, which is not on the ladder")

    baseline = _validate_against(None)
    if baseline:
        raise ToolError(
            "the unmutated data does not validate, so a mutation cannot be shown to be"
            f" caught: {'; '.join(baseline)}"
        )
    info("baseline: real data validates clean")

    uncaught: list[str] = []
    staged = _stage()
    pristine = {path.name: path.read_text(encoding="utf-8") for path in staged.glob("*.tres")}
    try:
        for realm_id, scalar, value, prefix in MUTATIONS:
            # Restore every seed between mutations: they must not be able to mask each
            # other, and a mutation that only fires because of its predecessor's damage
            # has proved nothing about its own guard.
            for name, text in pristine.items():
                (staged / name).write_text(text, encoding="utf-8")
            _with_broken_scalar(staged, realm_id, scalar, value)
            findings = _validate_against(staged)
            caught = [f for f in findings if prefix in f]
            label = f"{realm_id}.{scalar} = {value}"
            if caught:
                info(f"caught  {label}: {caught[0][:140]}")
            else:
                uncaught.append(f"{label} (expected `{prefix}`)")
                info(f"MISSED  {label}: nothing matched `{prefix}`")
    finally:
        # The staged tree is the only thing written, and it is outside the repo.
        shutil.rmtree(staged.parent, ignore_errors=True)

    if uncaught:
        raise ToolError("a balance guard did not fire: " + "; ".join(uncaught))
    ok(f"all {len(MUTATIONS)} balance guards fire on the mutation that breaks them")
    return 0
