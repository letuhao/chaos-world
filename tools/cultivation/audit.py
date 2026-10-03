"""Content-graph audit for the body-cultivation generation contract (ADR 0028).

Checks the relationships the runtime depends on, so a broken contract fails the
tool instead of surfacing as an unreachable realm in play:

- every ladder realm has a seed, and every seed's items, meridians, and
  recipes resolve in content;
- every entry gate is reachable from the previous realm's training ceiling;
- every entry gate can actually fail (ADR 0036's reachability rule has a
  counterpart, and a gate nothing can fail is not a gate);
- the craft chain for each realm pill and elixir is closed.

Gate soundness is separate from gate reachability. A gate above what the path
can produce is unreachable; a gate below what the ladder already grants is
unfailable. Both were invisible here: this file asserted that gates lined up
with each other and never asked whether the number could matter.
"""

from __future__ import annotations

import re

from ..common import REPO_ROOT, ToolError
from . import ladder as ladder_module
from .report import DERIVED_FIELDS, REALM_DIR, chance_range, load
from .seed import realms as ladder_realms

DATA = REPO_ROOT / "game" / "data"
QI_REALM_DIR = DATA / "qi_cultivation" / "realms"
# The one runtime file whose arithmetic the gate-soundness checks mirror. It is
# read, never edited: the tool's model of the runtime is only allowed to be as
# good as its evidence.
QI_TRAINING = REPO_ROOT / "game/src/modules/qi_cultivation/training.gd"
TOLERANCE = 1e-6


def _ids(*parts: str) -> set[str]:
    root = DATA.joinpath(*parts)
    if not root.is_dir():
        return set()
    return {path.stem for path in root.glob("*.tres")}


def _label(path) -> str:
    """Repo-relative path for a message, without assuming the path is in the repo.

    The probes below take their subject from a module global so a caller can aim
    them at a copy of the tree; a message must never be the thing that crashes.
    """
    try:
        return path.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def ceiling_resolves_next_realm(path=None) -> bool:
    """Whether `QiTraining._quality_ceiling` refines toward the NEXT realm's floor.

    This is the satisfiability premise of the whole qi path. Capping at the
    current realm's own `dantian_quality_required` made 28 of 29 transitions
    demand more quality than the realm below could produce (ADR 0036); the fix
    was to resolve the next realm's seed. Nothing asserted that, so the same
    regression would be invisible again.
    """
    target = QI_TRAINING if path is None else path
    if not target.is_file():
        return False
    text = target.read_text(encoding="utf-8", errors="replace")
    body = re.search(r"(?ms)^static func _quality_ceiling\(.*?^\s*return\b.*?$", text)
    if not body:
        return False
    source = body.group(0)
    return "next_seed.dantian_quality_required" in source and "ladder.next(" in source


def validate() -> list[str]:
    """Every finding in the body-cultivation content contract.

    The content directories are read from module globals so `mutate.py` can aim every
    probe at a copy of the tree. This function only ever reads.
    """
    findings: list[str] = []
    ladder = ladder_realms()
    meridians = _ids("meridians")
    acupoints = _ids("body_cultivation", "acupoints")
    items = _ids("items", "consumable") | _ids("items", "material")
    recipes = _ids("recipes")

    if len(ladder) != 30:
        findings.append(f"ladder has {len(ladder)} realms, expected 30")
    if len(acupoints) != 60:
        findings.append(f"{len(acupoints)} acupoint definitions, expected 60")
    if len(meridians) != 20:
        findings.append(f"{len(meridians)} meridian definitions, expected 20")

    seeds: list[dict] = []
    for realm_id, _name, _tier in ladder:
        path = REALM_DIR / f"{realm_id}.tres"
        seeds.append(load(realm_id) if path.is_file() else {})
        if not path.is_file():
            findings.append(f"no realm seed for {realm_id}")

    for index, (realm_id, _name, _tier) in enumerate(ladder):
        seed = seeds[index]
        if not seed:
            continue
        scalars = seed["scalars"]
        # The four ladder scalars (`power_budget`, `capacity_factor`,
        # `throughput_factor`, `technique_factor`) are deliberately absent: they were a
        # second, private power scale and went with the ladder. A realm's strength is
        # authored in `core/realm_power_table.tres` and its work is authored here, so
        # requiring them would demand numbers nothing produces.
        for field in (
            "progress_required",
            "insight_required",
            "quality_required",
            "quality_target",
            "integrity_target",
            "chance_base",
            "chance_cap",
        ):
            if float(scalars.get(field, 0.0)) <= 0.0:
                findings.append(f"{realm_id}: {field} is missing or not positive")
        # `work_required`, `acupoint_work` and `meridian_work` are DERIVED from
        # `progress_required` and the ladder index by `BodyRealmSeed`. They used to be
        # authored beside it, byte-identical in all 30 seeds and read by nothing in
        # `src/`, so the first edit to one of the three would desync the gate from its
        # own price. A seed that still carries one of them is stale, not tuned.
        for derived in DERIVED_FIELDS:
            if derived in scalars:
                findings.append(
                    f"{realm_id}: {derived} is a derived value and must not be authored in"
                    " the seed; run `cultivation retune` and delete the line"
                )
        for item_id in (
            scalars.get("breakthrough_item"),
            scalars.get("strengthening_item"),
            scalars.get("recovery_item"),
        ):
            if str(item_id) not in items:
                findings.append(f"{realm_id}: item {item_id} does not exist")
        for field in ("required_meridians", "channel_training"):
            for meridian_id in seed["arrays"].get(field, []):
                if meridian_id not in meridians:
                    findings.append(f"{realm_id}: {field} names unknown meridian {meridian_id}")
        for recipe in (
            f"body_{realm_id}_pill_recipe",
            f"body_{realm_id}_elixir_recipe",
            f"body_{realm_id}_recovery_recipe",
        ):
            if recipe not in recipes:
                findings.append(f"{realm_id}: recipe {recipe} does not exist")
        # Breakthrough risk must never reach certainty at any realm.
        chance_cap = float(scalars.get("chance_cap", 1.0))
        if chance_cap >= 1.0:
            findings.append(
                f"{realm_id}: chance_cap {chance_cap} is a guaranteed success, so the"
                " deviation and recovery loop can never fire there"
            )
        quality_gate = float(scalars["quality_required"])
        # A gate at or below the quality a fresh huyệt already carries is not a gate: an
        # actor that has done nothing passes it. This is what made the first eight
        # breakthroughs a formality (0.400-0.490 against a fresh 0.5). Checked for EVERY
        # realm, not just the first — a fresh huyệt unlocking mid-ladder arrives at the
        # same 0.5 and has to be trained up to the gate like any other.
        fresh = ladder_module.fresh_acupoint_quality()
        if fresh is None:
            findings.append(
                "gate_soundness_premise_unreadable: cannot read the fresh acupoint quality"
                f" from {_label(ladder_module.ACUPOINT_DEFAULTS)}, so the quality gates were"
                " not checked"
            )
        elif quality_gate <= fresh + TOLERANCE:
            findings.append(
                f"gate_below_fresh_quality: {realm_id}: quality gate {quality_gate} is at or"
                f" below the {fresh} quality a fresh huyệt already has, so the gate is"
                " passed without training"
            )
        if index == 0 or not seeds[index - 1]:
            continue
        previous = seeds[index - 1]["scalars"]
        quality_ceiling = float(previous["quality_target"])
        # REACHABILITY, then SOUNDNESS. The gate cannot exceed what the realm below can
        # train to. It must also fall strictly below it: the headroom between the two is
        # the span of huyệt quality an actor can hold at the moment of the attempt, and
        # a gate pinned onto the ceiling pins that span to zero — average quality is one
        # number and acupoint quality cannot enter the roll on ANY realm.
        if quality_gate > quality_ceiling + TOLERANCE:
            findings.append(
                f"gate_above_previous_ceiling: {realm_id}: quality gate {quality_gate} is"
                f" above the previous realm's training ceiling {quality_ceiling}"
            )
        elif quality_gate >= quality_ceiling - TOLERANCE:
            findings.append(
                f"quality_gate_no_headroom: {realm_id}: quality gate {quality_gate} is not"
                f" below the previous realm's training ceiling {quality_ceiling}, so there"
                " is no span of huyệt quality for a breakthrough roll to price"
            )
        refinement_gate = float(scalars["required_refinement"])
        refinement_ceiling = float(previous["refinement_cap"])
        if refinement_gate > refinement_ceiling:
            findings.append(
                f"gate_above_previous_ceiling: {realm_id}: refinement gate "
                f"{refinement_gate} exceeds the previous realm's cap {refinement_ceiling}"
            )
    findings.extend(_gate_soundness_findings(ladder, seeds))
    findings.extend(_qi_gate_soundness_findings(ladder))
    return findings


def _gate_soundness_findings(ladder: list, seeds: list[dict]) -> list[str]:
    """Every body gate must be able to fail, and must let huyệt quality matter.

    Two failure classes, both invisible until now because the checks above only
    compared gates to each other:

    - `body_physique_gate_dead` — a floor at or below the physique the ladder
      hands out for free. `BodyBreakthroughCondition` compares
      `get_base(Stat.PHYSIQUE)` against `physique_required`, and the ladder's
      only physique grants are the breakthrough reward and the milestone bonus
      (`BodyProgress.grant`). Arrival physique is therefore fully determined by
      the ladder, so a floor under it can never be unmet.
    - `degenerate_chance_band` — `chance_base >= chance_cap`. `BodyAdvancement._chance`
      clamps to the cap, so the acupoint term is swallowed and huyệt quality
      cannot enter the roll. `cultivation report` renders that as a zero-width
      band while its own summary claims acupoints can be spent to buy certainty.
    """
    findings: list[str] = []
    ratio = ladder_module.milestone_physique_ratio()
    if ratio is None:
        # A silent 0.0 here would make the arrival ceiling far too low and the
        # dead-gate check silently pass. An unreadable premise must be loud.
        findings.append(
            "gate_soundness_premise_unreadable: cannot read MILESTONE_PHYSIQUE_RATIO from "
            f"{_label(ladder_module.BODY_PROGRESS)}, so physique gate soundness was not checked"
        )
        return findings

    granted = 0.0
    dead: list[str] = []
    for index, (realm_id, _name, _tier) in enumerate(ladder):
        seed = seeds[index]
        if not seed:
            continue
        required = float(seed["scalars"].get("physique_required", 0.0))
        if required <= granted + TOLERANCE:
            dead.append(f"{realm_id} (floor {required:g} <= {granted:.2f} granted on arrival)")
        granted += float(seed["dicts"].get("rewards", {}).get("physique", 0.0))
        granted += float(seed["scalars"].get("integrity_maximum", 0.0)) * ratio
    if dead:
        findings.append(
            f"body_physique_gate_dead: {len(dead)} of {len(ladder)} realms gate on a "
            "physique floor the ladder already grants for free, so the gate can never be "
            f"unmet: {'; '.join(dead)}"
        )

    # The band is measured the way an actor reaches it: `quality_required` is the floor
    # `_acupoints_ready` enforces, the PREVIOUS realm's `quality_target` is the ceiling
    # `cultivate` will not exceed, and `chance_base + quality*0.5` clamped to
    # `chance_cap` maps that span to a range of outcomes. Zero width means no training
    # decision exists, whatever the two authored numbers say individually.
    degenerate: list[str] = []
    for index, (realm_id, _name, _tier) in enumerate(ladder):
        seed = seeds[index]
        if not seed:
            continue
        ceiling = float(seeds[index - 1]["scalars"]["quality_target"]) if index else None
        worst, best = chance_range(seed, ceiling)
        if best - worst > 1e-9:
            continue
        scalars = seed["scalars"]
        degenerate.append(
            f"{realm_id} (band {worst:.4f}-{best:.4f}; chance_base"
            f" {scalars.get('chance_base')}, chance_cap {scalars.get('chance_cap')},"
            f" quality span {scalars.get('quality_required')}"
            f"-{'own target' if ceiling is None else f'{ceiling:.4f}'})"
        )
    if degenerate:
        findings.append(
            f"degenerate_chance_band: {len(degenerate)} realm(s) offer a zero-width chance"
            " band across every huyệt quality an actor can hold while attempting them, so"
            " training the body cannot change the outcome and 'acupoint quality buys"
            f" certainty' is false there: {'; '.join(degenerate)}"
        )
    return findings


def _qi_gate_soundness_findings(ladder: list) -> list[str]:
    """The qi path's gates are only reachable if the training ceiling is the next floor.

    `QiTraining.cultivate` refines quality toward `_quality_ceiling(rank_id)`.
    While standing in realm R that ceiling is realm R+1's `dantian_quality_required`,
    so every gate is satisfiable by one realm of the path's own training. If the
    ceiling ever resolves the CURRENT realm's floor again, quality can never rise
    past the gate of the realm the player is standing in, and the path dead-ends
    (ADR 0036: 28 of 29 transitions were unplayable). The data half is the range
    check below; a monotone ladder needs no further assertion because the ceiling
    and the next floor are the same number by that rule.
    """
    findings: list[str] = []
    if not ceiling_resolves_next_realm():
        findings.append(
            "qi_quality_ceiling_resolves_current_realm: "
            f"{_label(QI_TRAINING)} no longer refines quality "
            "toward the next realm's dantian_quality_required, so a realm's own quality "
            "gate is unreachable from the realm below it (ADR 0036)"
        )
    floors: list[tuple[str, float, float]] = []
    for realm_id, _name, _tier in ladder:
        path = QI_REALM_DIR / f"{realm_id}.tres"
        if not path.is_file():
            findings.append(f"qi_gate_missing: no qi realm seed for {realm_id}")
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        quality = re.search(r"(?m)^dantian_quality_required\s*=\s*([\d.]+)", text)
        fill = re.search(r"(?m)^dantian_fill_required\s*=\s*([\d.]+)", text)
        if not quality or not fill:
            findings.append(f"qi_gate_missing: {realm_id} declares no dantian quality/fill gate")
            continue
        floors.append((realm_id, float(quality.group(1)), float(fill.group(1))))
    # `QiAdvancement` compares the dantian's own quality RATIO and fill RATIO
    # against these two floors, so a floor above 1.0 is a gate the resource cannot
    # satisfy at any work budget. This is the satisfiability check that survives
    # contact with the ladder: no amount of circulating qi raises a ratio past 1.
    for realm_id, quality, fill in floors:
        for name, value in (("dantian_quality_required", quality), ("dantian_fill_required", fill)):
            if value <= 0.0 or value > 1.0:
                findings.append(
                    f"qi_gate_unsatisfiable: {realm_id}: {name} {value} is outside (0, 1.0]; the "
                    "dantian's quality and fill are ratios, so no amount of circulating qi "
                    "reaches it"
                )
    return findings


def context() -> str:
    """Compact context block for a generation prompt."""
    lines = []
    for index, (realm_id, _name, _tier) in enumerate(ladder_realms()):
        path = REALM_DIR / f"{realm_id}.tres"
        if not path.is_file():
            lines.append(f"{index + 1:02d} {realm_id}: (missing seed)")
            continue
        scalars = load(realm_id)["scalars"]
        lines.append(
            f"{index + 1:02d} {realm_id}: work={scalars['progress_required']} "
            f"Q={scalars['quality_target']} gate={scalars['quality_required']} "
            f"insight={scalars['insight_required']} "
            f"resonance={scalars['resonance_rank']}"
        )
    return "\n".join(lines)


def run() -> int:
    findings = validate()
    if findings:
        raise ToolError("; ".join(findings))
    return 0
