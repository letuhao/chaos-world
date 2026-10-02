"""Content-graph audit for the body-cultivation generation contract (ADR 0028).

Checks the relationships the runtime depends on, so a broken contract fails the
tool instead of surfacing as an unreachable realm in play:

- every ladder realm has a seed, and every seed's items, meridians, and
  recipes resolve in content;
- every entry gate is reachable from the previous realm's training ceiling;
- the craft chain for each realm pill and elixir is closed.
"""

from __future__ import annotations

from ..common import REPO_ROOT, ToolError
from .report import REALM_DIR, load
from .seed import realms as ladder_realms

DATA = REPO_ROOT / "game" / "data"
TOLERANCE = 1e-6


def _ids(*parts: str) -> set[str]:
    root = DATA.joinpath(*parts)
    if not root.is_dir():
        return set()
    return {path.stem for path in root.glob("*.tres")}


def validate() -> list[str]:
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
            "insight_required",
            "quality_required",
            "quality_target",
            "work_required",
            "acupoint_work",
            "meridian_work",
        ):
            if float(scalars.get(field, 0.0)) <= 0.0:
                findings.append(f"{realm_id}: {field} is missing or not positive")
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
        # The enforced gate and the authored budget must be one quantity.
        if (
            abs(
                float(scalars.get("progress_required", 0.0))
                - float(scalars.get("work_required", 0.0))
            )
            > TOLERANCE
        ):
            findings.append(
                f"{realm_id}: progress_required and work_required disagree; the gate and the"
                " authored budget must describe the same labour"
            )
        # Breakthrough risk must never reach certainty at any realm.
        chance_cap = float(scalars.get("chance_cap", 1.0))
        if chance_cap >= 1.0 or chance_cap < 0.70:
            findings.append(
                f"{realm_id}: chance_cap {chance_cap} leaves the deviation loop unreachable"
            )
        if index == 0 or not seeds[index - 1]:
            continue
        previous = seeds[index - 1]["scalars"]
        quality_gate = float(scalars["quality_required"])
        quality_ceiling = float(previous["quality_target"])
        if abs(quality_gate - quality_ceiling) > TOLERANCE:
            findings.append(
                f"{realm_id}: quality gate {quality_gate} is not the previous realm's "
                f"training target {quality_ceiling}"
            )
        refinement_gate = float(scalars["required_refinement"])
        refinement_ceiling = float(previous["refinement_cap"])
        if refinement_gate > refinement_ceiling:
            findings.append(
                f"{realm_id}: refinement gate {refinement_gate} exceeds the previous "
                f"realm's cap {refinement_ceiling}"
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
            f"{index + 1:02d} {realm_id}: work={scalars['work_required']} "
            f"Q={scalars['quality_target']} insight={scalars['insight_required']} "
            f"resonance={scalars['resonance_rank']}"
        )
    return "\n".join(lines)


def run() -> int:
    findings = validate()
    if findings:
        raise ToolError("; ".join(findings))
    return 0
