"""The authored body-cultivation balance ladders, in one place.

Three things used to hold their own copy of these numbers: the bootstrap
generator (`seed.py`), the balance report (`report.py`), and the guards in
`audit.py`. A retune that reached only one of them was invisible to the other
two, which is how `chance_base` grew past `chance_cap` on five realms and
`quality_required` sank below the quality a fresh huyệt already has. Everything
now reads this module, so a retune is one edit.

None of this is a power scale. A MAGNITUDE is `core/realm_power_table.tres` (keyed
by realm id) or `game/data/item_options/item_magnitude_scale.json`; a RATE is
`BodyRealmProfile.factor()`. These are probabilities, floors and ceilings, and they
are never derived from a realm index by the runtime - they are read off the seed.
What they may share with a magnitude is nothing, and nothing here reads one.

Shape, not recipe, is what the guards assert (`balance.py`). The recipe lives here
so a designer retunes one number instead of thirty, and so the generator that
bootstraps a missing seed cannot disagree with the report that reads it.
"""

from __future__ import annotations

import re

from ..common import REPO_ROOT

# `minf`/`maxf` mirror GDScript's clamp helpers so the tooling and the runtime read
# the same intent.
minf = min
maxf = max

# `BodyProgress.MILESTONE_PHYSIQUE_RATIO`: the physique a completed realm milestone
# grants. READ, never duplicated - if the runtime changes it, the physique floor
# below moves with it and the guard re-derives it rather than trusting a stale copy.
BODY_PROGRESS = REPO_ROOT / "game/src/modules/body_cultivation/progress.gd"

# `AcupointDefaults.from_definition`: the quality a brand-new huyệt starts at.
# READ for the same reason. Every quality floor is meaningless without it: a gate
# below this value is passed by an actor that has done nothing at all.
ACUPOINT_DEFAULTS = REPO_ROOT / "game/src/modules/body_cultivation/acupoint_defaults.gd"

# The qi channel ladder is written in `MeridianState`'s own vocabulary, and both
# the rungs and the arrival state are read rather than copied for the same
# reason. A Python copy of these four names would keep grading a ladder the
# runtime no longer has, and an unknown name does not fail `meets()` — it reads
# as rank 0, so a typo silently WEAKENS a gate instead of breaking loudly.
MERIDIAN_STATE = REPO_ROOT / "game/src/core/meridian_state.gd"
# Read for `_state_from_def` only: the state every unlocked channel is minted in.
MERIDIAN_NETWORK = REPO_ROOT / "game/src/core/meridian_network.gd"

# --- The quality ladder ------------------------------------------------------
# Q(R) is the CEILING: `BodyTraining.cultivate` refines quality toward it and never
# past it. It has to sit above the quality a fresh huyệt already carries, or
# cultivation cannot raise quality at all and the whole huyệt axis is inert.
QUALITY_CEILING_BASE = 0.62
QUALITY_STEP = 0.0105

# The entry gate sits this far BELOW the previous realm's ceiling. The gap is the
# player's decision: `_acupoints_ready` demands the floor, `cultivate` will pay out
# to the ceiling, and everything between is what a breakthrough roll is buying. It
# used to be zero - the gate WAS the ceiling - so average huyệt quality at the
# moment of an attempt was a single number and acupoint quality could not enter the
# roll on any realm, not just the five whose clamp swallowed it.
QUALITY_HEADROOM = 0.08

# The reservoir charge target stays a fixed distance above the quality ceiling: the
# body is charged at least as far as its huyệt are trained.
INTEGRITY_GAP = 0.05

# --- The breakthrough chance band --------------------------------------------
# The floor a realm offers before any huyệt work, and the ceiling that stops any
# realm from becoming certain.
#
# The floor DECLINES with depth. That is the point: a deeper realm promises less on
# its own and the player buys certainty with training. The old floor ROSE by 0.008
# per realm while the ceiling FELL by the same amount, so the two crossed at R26 and
# the clamp above the floor made the huyệt term unreachable from there up.
CHANCE_BASE_START = 0.49
CHANCE_BASE_DECAY = 0.008

# The ceiling is `floor + half the quality ceiling + this`, so it is guaranteed by
# construction to sit above anything a fully trained body can reach. The clamp is
# then a backstop against over-training, not the thing that prices the attempt.
CHANCE_CAP_HEADROOM = 0.05

# --- The physique floor ------------------------------------------------------
# `BodyBreakthroughCondition` compares `get_base(Stat.PHYSIQUE)`, and the ladder's
# only base-physique grants are the breakthrough reward and the milestone bonus.
# Arrival physique is therefore determined by the ladder, so a floor at or under it
# can never be unmet. The floor sits this far ABOVE that grant: the ladder never
# hands out the physique its own gate demands, and the difference is the player's to
# find in learned techniques (`ItemUse._apply_learned` is the only other writer of a
# base attribute, and it is permanent).
PHYSIQUE_MARGIN = 12.0

# The physique the ladder grants for clearing a realm: the seed's own reward plus
# one milestone. Authored here so `seed.py` and the guard cannot disagree.
PHYSIQUE_REWARD = 2.0


def _runtime_constant(path, name: str) -> float | None:
    """A `const NAME := <number>` read from a runtime script, or None."""
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8", errors="replace")
    found = re.search(rf"(?m)^const {name}\s*:?=\s*(-?[\d.]+)", text)
    return float(found.group(1)) if found else None


def milestone_physique_ratio() -> float | None:
    """`BodyProgress.MILESTONE_PHYSIQUE_RATIO`, the per-milestone physique grant."""
    return _runtime_constant(BODY_PROGRESS, "MILESTONE_PHYSIQUE_RATIO")


def fresh_acupoint_quality() -> float | None:
    """`AcupointDefaults.from_definition`'s starting `point.quality`."""
    if not ACUPOINT_DEFAULTS.is_file():
        return None
    text = ACUPOINT_DEFAULTS.read_text(encoding="utf-8", errors="replace")
    found = re.search(r"(?m)^\s*point\.quality\s*=\s*(-?[\d.]+)", text)
    return float(found.group(1)) if found else None


def channel_state_ranks() -> dict[str, int] | None:
    """`MeridianState.STATE_ORDER` as `{state name: rank}`, or None if unreadable.

    The names, not indices, because the seeds author `required_channel_state` by
    name and a rank only means something beside the runtime's own order.
    """
    if not MERIDIAN_STATE.is_file():
        return None
    text = MERIDIAN_STATE.read_text(encoding="utf-8", errors="replace")
    names = dict(re.findall(r'(?m)^const (\w+)\s*:?=\s*&"([^"]+)"$', text))
    order = re.search(r"(?m)^const STATE_ORDER\s*:?=\s*\{([^}]*)\}", text)
    if not order:
        return None
    ranks: dict[str, int] = {}
    for key, rank in re.findall(r"(\w+)\s*:\s*(-?\d+)", order.group(1)):
        if key not in names:
            return None
        ranks[names[key]] = int(rank)
    return ranks or None


def fresh_channel() -> tuple[str, int] | None:
    """`(state, refinement)` of a channel no actor has ever trained.

    `MeridianNetwork._state_from_def` mints every unlocked channel from
    `MeridianState.new()`, so arrival is that class's own declared defaults and
    nothing else. Reading `_state_from_def` is what makes this a premise rather
    than an assumption: a network that granted a channel its final rung on unlock
    would make every channel gate vacuous, and an assumption here would grade a
    state the runtime never produces.
    """
    if not MERIDIAN_STATE.is_file() or not MERIDIAN_NETWORK.is_file():
        return None
    text = MERIDIAN_STATE.read_text(encoding="utf-8", errors="replace")
    state = re.search(r'(?m)^var state:\s*StringName\s*=\s*&"([^"]+)"$', text)
    depth = re.search(r"(?m)^var refinement:\s*int\s*=\s*(-?\d+)$", text)
    if not state or not depth:
        return None
    network = MERIDIAN_NETWORK.read_text(encoding="utf-8", errors="replace")
    factory = re.search(r"(?ms)^func _state_from_def\(.*?^\s*return\b.*?$", network)
    if not factory or "MeridianState.new()" not in factory.group(0):
        return None
    return state.group(1), int(depth.group(1))


# --- Ladders -----------------------------------------------------------------


def quality_ceiling(index: int) -> float:
    """Q(R): the huyệt quality `cultivate` refines toward while in realm `index`."""
    return QUALITY_CEILING_BASE + QUALITY_STEP * index


def quality_gate(index: int) -> float:
    """The huyệt quality floor for entering realm `index`.

    Exactly `QUALITY_HEADROOM` under the ceiling, so the gate is reachable inside the
    realm below and leaves the player room above it.
    """
    return quality_ceiling(index) - QUALITY_HEADROOM


def integrity_target(index: int) -> float:
    """U(R): the body-integrity pool ratio the breakthrough demands."""
    return quality_ceiling(index) + INTEGRITY_GAP


def chance_base(index: int) -> float:
    """The chance a realm offers with no huyệt work behind it."""
    return CHANCE_BASE_START - CHANCE_BASE_DECAY * index


def chance_cap(index: int) -> float:
    """The hard ceiling. Above anything a fully trained body can roll."""
    return chance_base(index) + 0.5 * quality_ceiling(index) + CHANCE_CAP_HEADROOM


def integrity_maximum(index: int) -> float:
    """The reservoir's magnitude, in absolute units. A magnitude, not a rate."""
    return 100.0 * (1.0 + 0.1 * index)


def free_physique(index: int, ratio: float) -> float:
    """Base physique the ladder grants before the actor reaches realm `index`.

    Sums what clearing each earlier realm hands out: the breakthrough reward plus
    that realm's one-time milestone. Zero at `index == 0`.
    """
    return sum(PHYSIQUE_REWARD + integrity_maximum(earlier) * ratio for earlier in range(index))


def physique_required(index: int, ratio: float) -> float:
    """The physique floor for entering realm `index`: the free grant plus a margin."""
    return free_physique(index, ratio) + PHYSIQUE_MARGIN


def attempt_band(
    index: int, gate: float, ceiling: float, base: float, cap: float
) -> tuple[float, float]:
    """Worst and best breakthrough chance actually reachable while entering `index`.

    `BodyBreakthroughCondition._acupoints_ready` forces EVERY unlocked huyệt to at
    least `gate`, and `BodyTraining.cultivate` will not carry one past `ceiling`, so
    `gate..ceiling` is the whole span an actor can hold at the moment of the attempt.
    Both ends run through `BodyAdvancement._chance`: add half the quality to the
    floor, then clamp to the ceiling.

    Modelling anything outside that span - a bare `chance_base`, or a
    `quality_target` the actor is not standing in yet - describes a state no actor
    can be in, and reports a band wider than the game has.
    """
    lower = minf(base + 0.5 * gate, cap)
    upper = minf(base + 0.5 * ceiling, cap)
    return lower, maxf(lower, upper)
