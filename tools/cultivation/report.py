"""Deterministic balance report for the body-cultivation realm ladder.

Reads the generated `BodyRealmSeed` profiles and prints the ladder as the game
resolves it: profile factors, entry gates, work, and the combat stats the
provider derives from them. Read-only and non-gating; two runs on the same data
produce byte-identical output.
"""

from __future__ import annotations

import re

from ..common import REPO_ROOT, ToolError, info, ok
from .seed import minf
from .seed import realms as ladder_realms

REALM_DIR = REPO_ROOT / "game" / "data" / "body_cultivation" / "realms"

# Mirrors `BodyAdvancement.QUALITY_TO_CHANCE`.
QUALITY_TO_CHANCE = 0.5

# Provider composition (BodyProvider.contribute) for a reference body at full
# integrity with no meridian bonus, so the report shows the profile factors
# alone and stays comparable across realms.
REFERENCE_BODY = {"bone_density": 1.0, "muscle_fiber": 1.0, "organ_vitality": 1.0}

COLUMNS = (
    ("#", 3),
    ("realm", 20),
    ("strength", 8),
    ("Qreq", 6),
    ("Qtrg", 6),
    ("work", 7),
    ("insight", 8),
    ("reso", 5),
    ("chance", 7),
    ("attack", 9),
    ("defense", 9),
    ("power", 9),
)


def load(realm_id: str) -> dict:
    """Parse one realm seed: scalars, StringNames, and StringName arrays."""
    path = REALM_DIR / f"{realm_id}.tres"
    if not path.is_file():
        raise ToolError(f"missing realm seed: {path.relative_to(REPO_ROOT).as_posix()}")
    text = path.read_text(encoding="utf-8")
    scalars: dict[str, object] = {}
    for key, raw in re.findall(r'(?m)^([a-z_]+)\s*=\s*&"([^"]*)"$', text):
        scalars[key] = raw
    for key, raw in re.findall(r"(?m)^([a-z_]+)\s*=\s*(-?[\d.]+)$", text):
        scalars[key] = float(raw)
    for key, raw in re.findall(r"(?m)^([a-z_]+)\s*=\s*(-?\d+)$", text):
        scalars[key] = int(raw)
    arrays = {
        key: re.findall(r'&"([^"]*)"', raw)
        for key, raw in re.findall(r"(?ms)^([a-z_]+)\s*=\s*Array\[StringName\]\(\[(.*?)\]\)", text)
    }
    return {"scalars": scalars, "arrays": arrays}


def derived_stats(seed: dict, strength: float) -> tuple[float, float, float]:
    """Attack / defense / body power for the reference body. Mirrors the provider.

    `strength` is the realm's authored multiplier, read from
    `core/realm_power_table.tres` — the same source the runtime reads. It used to be
    the seed's deleted `technique_factor`, whose `.get(..., 1.0)` default made every
    realm report the same attack and defence: a flat ladder that looked plausible.
    """
    body = REFERENCE_BODY
    attack = (body["muscle_fiber"] * 2.0 + body["bone_density"] * 1.0) * strength
    defense = (body["bone_density"] * 1.5 + body["organ_vitality"] * 1.0) * strength
    power = (body["bone_density"] + body["muscle_fiber"] + body["organ_vitality"]) * 0.5
    return attack, defense, power * strength


def chance_range(seed: dict) -> tuple[float, float]:
    """Worst and best breakthrough chance for the realm, ignoring acupoints.

    The floor is the realm's own `chance_base` with no huyệt trained; the best is
    with every point at the realm's quality target. Both are clamped to
    `chance_cap`, which is what guarantees no realm is a free success.
    """
    scalars = seed["scalars"]
    base = float(scalars.get("chance_base", 0.0))
    cap = float(scalars.get("chance_cap", 1.0))
    worst = minf(base, cap)
    best = minf(base + float(scalars.get("quality_target", 0.0)) * QUALITY_TO_CHANCE, cap)
    return worst, best


def _row(index: int, realm_id: str, seed: dict, strength: float) -> tuple[str, ...]:
    scalars = seed["scalars"]
    attack, defense, power = derived_stats(seed, strength)
    worst, best = chance_range(seed)
    return (
        str(index + 1),
        realm_id,
        f"{strength:.2f}",
        f"{float(scalars.get('quality_required', 0.0)):.3f}",
        f"{float(scalars.get('quality_target', 0.0)):.3f}",
        f"{float(scalars.get('work_required', 0.0)):.0f}",
        f"{float(scalars.get('insight_required', 0.0)):.0f}",
        str(scalars.get("resonance_rank", 0)),
        f"{worst:.2f}-{best:.2f}",
        f"{attack:.1f}",
        f"{defense:.1f}",
        f"{power:.1f}",
    )


def run() -> int:
    from ..realm_power import read_multipliers

    strengths = read_multipliers()
    seeds = []
    for index, (realm_id, _name, _tier) in enumerate(ladder_realms()):
        seeds.append((index, realm_id, load(realm_id)))

    info(" ".join(name.ljust(width) for name, width in COLUMNS))
    info(" ".join("-" * width for _, width in COLUMNS))
    for index, realm_id, seed in seeds:
        row = _row(index, realm_id, seed, strengths[index])
        info(
            " ".join(
                value.ljust(width) for value, (_, width) in zip(row, COLUMNS, strict=True)
            ).rstrip()
        )

    total_work = sum(float(seed["scalars"].get("work_required", 0.0)) for _, _, seed in seeds)
    worst_risk = min(
        1.0 - chance_range(seed)[1] for _, _, seed in seeds if chance_range(seed)[1] < 1.0
    )
    info("")
    info(f"realms: {len(seeds)}  total work: {total_work:.0f}")
    info(
        f"strength spans {strengths[0]:.2f} -> {strengths[-1]:.2f} "
        f"({strengths[-1] / max(strengths[0], 1e-12):.1f}x), authored in "
        "core/realm_power_table.tres"
    )
    info(
        f"breakthrough failure rate stays at or above {worst_risk * 100.0:.0f}% even with"
        " perfect huyệt"
    )
    info(
        "entry gate = previous realm's quality target; refinement gate = previous "
        "realm's cap (ADR 0028)"
    )
    info(
        "chance = chance_base + average huyệt quality * 0.5, capped by chance_cap;"
        " comprehension does not enter the roll"
    )
    ok(f"body ladder report for {len(seeds)} realms")
    return 0
