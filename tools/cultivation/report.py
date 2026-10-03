"""Deterministic balance report for the body-cultivation realm ladder.

Reads the generated `BodyRealmSeed` profiles and prints the ladder as the game
resolves it: profile factors, entry gates, work, and the combat stats the
provider derives from them. Read-only and non-gating; two runs on the same data
produce byte-identical output.
"""

from __future__ import annotations

import re

from ..common import REPO_ROOT, ToolError, info, ok
from .ladder import attempt_band
from .seed import realms as ladder_realms

REALM_DIR = REPO_ROOT / "game" / "data" / "body_cultivation" / "realms"

# Mirrors `BodyAdvancement.QUALITY_TO_CHANCE`.
QUALITY_TO_CHANCE = 0.5

# The fields `BodyRealmSeed` now derives rather than authors, so the report reads
# the authored one and never reports a number the runtime does not use.
DERIVED_FIELDS = ("work_required", "acupoint_work", "meridian_work")

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
    """Parse one realm seed: scalars, StringNames, StringName arrays, dict blocks."""
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
    # `rewards = {"physique": 2.0, ...}`. The ladder-granted physique audit reads
    # this, and a reward it cannot see would make that audit silently vacuous.
    dicts = {
        key: {
            option: float(value)
            for option, value in re.findall(r'"([^"]+)"\s*:\s*(-?[\d.]+)', body)
        }
        for key, body in re.findall(r"(?ms)^([a-z_]+)\s*=\s*\{(.*?)\}", text)
    }
    return {"scalars": scalars, "arrays": arrays, "dicts": dicts}


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


def chance_range(seed: dict, ceiling: float | None = None) -> tuple[float, float]:
    """Worst and best breakthrough chance for the realm, as an actor can reach it.

    An actor attempting to ENTER this realm holds every unlocked huyệt at no less
    than `quality_required` (that is what `_acupoints_ready` gates on) and at no more
    than the previous realm's `quality_target` (that is what `cultivate` will not
    exceed). `gate..ceiling` is therefore the whole span available at the moment of
    the attempt, and `BodyAdvancement._chance` maps it through
    `chance_base + quality * 0.5`, clamped to `chance_cap`.

    `ceiling` defaults to this realm's own `quality_target`, which is the right answer
    for the first realm (nothing below it) and an over-estimate for every other — the
    ladder's `attempt_band` supplies the real ceiling.

    When the two ends come out equal the band is degenerate: nothing an actor can
    train separates the worst case from the best. The caller must report that rather
    than print a range that looks like a choice.
    """
    scalars = seed["scalars"]
    base = float(scalars.get("chance_base", 0.0))
    cap = float(scalars.get("chance_cap", 1.0))
    gate = float(scalars.get("quality_required", 0.0))
    reach = float(scalars.get("quality_target", 0.0)) if ceiling is None else ceiling
    return attempt_band(0, gate, reach, base, cap)


def band_is_live(seed: dict, ceiling: float | None = None) -> bool:
    """Whether acupoint quality can change this realm's outcome at all."""
    worst, best = chance_range(seed, ceiling)
    return best - worst > 1e-9


def _ceiling_at(index: int, seeds: list[tuple[int, str, dict]]) -> float | None:
    """The huyệt ceiling an actor has while attempting realm `index`.

    Entering realm `index` means standing in realm `index - 1`, so the ceiling is the
    PREVIOUS seed's `quality_target`. The first realm has no previous, so it is
    `None` and `chance_range` falls back to its own target.
    """
    if index <= 0:
        return None
    return float(seeds[index - 1][2]["scalars"].get("quality_target", 0.0))


def _row(
    index: int, realm_id: str, seed: dict, strength: float, ceiling: float | None
) -> tuple[str, ...]:
    scalars = seed["scalars"]
    attack, defense, power = derived_stats(seed, strength)
    worst, best = chance_range(seed, ceiling)
    return (
        str(index + 1),
        realm_id,
        f"{strength:.2f}",
        f"{float(scalars.get('quality_required', 0.0)):.3f}",
        f"{float(scalars.get('quality_target', 0.0)):.3f}",
        f"{float(scalars.get('progress_required', 0.0)):.0f}",
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
        row = _row(index, realm_id, seed, strengths[index], _ceiling_at(index, seeds))
        info(
            " ".join(
                value.ljust(width) for value, (_, width) in zip(row, COLUMNS, strict=True)
            ).rstrip()
        )

    total_work = sum(float(seed["scalars"].get("progress_required", 0.0)) for _, _, seed in seeds)
    risks = [
        (1.0 - chance_range(seed, _ceiling_at(index, seeds))[1], index + 1, realm_id)
        for index, realm_id, seed in seeds
    ]
    worst_risk, worst_at, worst_realm = min(risks)
    dead = [
        (index + 1, realm_id)
        for index, realm_id, seed in seeds
        if not band_is_live(seed, _ceiling_at(index, seeds))
    ]
    info("")
    info(f"realms: {len(seeds)}  total work: {total_work:.0f}")
    info(
        f"strength spans {strengths[0]:.2f} -> {strengths[-1]:.2f} "
        f"({strengths[-1] / max(strengths[0], 1e-12):.1f}x), authored in "
        "core/realm_power_table.tres"
    )
    info(
        f"breakthrough failure rate stays at or above {worst_risk * 100.0:.0f}% even with"
        f" perfect huyệt (worst realm: R{worst_at} {worst_realm})"
    )
    if dead:
        listed = ", ".join(f"R{index} {realm_id}" for index, realm_id in dead)
        info(
            f"warn {len(dead)} realm(s) have a zero-width chance band, so huyệt quality "
            f"cannot enter the roll there and 'even with perfect huyệt' is vacuous: {listed}"
        )
    info(
        "entry gate = the realm's own quality floor, set a headroom below the previous "
        "realm's quality ceiling (ADR 0028)"
    )
    info(
        "chance = chance_base + average huyệt quality * 0.5, capped by chance_cap,"
        " over the span quality_required..previous realm's quality_target that an actor"
        " attempting this realm can actually hold; comprehension does not enter the roll"
    )
    ok(f"body ladder report for {len(seeds)} realms")
    return 0
