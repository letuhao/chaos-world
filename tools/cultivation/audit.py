"""Content-graph audit for the body-cultivation generation contract (ADR 0028).

Checks the relationships the runtime depends on, so a broken contract fails the
tool instead of surfacing as an unreachable realm in play:

- every ladder realm has a seed, and every seed's items, meridians, and
  recipes resolve in content;
- every entry gate is reachable from the previous realm's training ceiling;
- every entry gate can actually fail (ADR 0036's reachability rule has a
  counterpart, and a gate nothing can fail is not a gate);
- the craft chain for each realm pill and elixir is closed;
- every qi boundary is walkable by pressing verbs and worth pressing
  (`qi_gate_ladder_findings`).

Gate soundness is separate from gate reachability. A gate above what the path
can produce is unreachable; a gate below what the ladder already grants is
unfailable. Both were invisible here: this file asserted that gates lined up
with each other and never asked whether the number could matter.

Satisfiable is separate again, and it is a third thing: 26 of the 30 qi seeds
demanded channel DEPTH, `channel_met` composes state AND depth, and every test
went through the facade to ask whether the gate was enforced. None asked whether
it could be met by pressing buttons, so the depth ladder read `open` only, every
boundary past seed 4 was skipped, `refine_meridian` was unreachable and 25 of 29
transitions were unwalkable under a green suite.
"""

from __future__ import annotations

import re
from pathlib import Path

from ..common import REPO_ROOT, ToolError
from . import ladder as ladder_module
from .report import DERIVED_FIELDS, chance_range, load, load_seed
from .seed import realms as ladder_realms

DATA = REPO_ROOT / "game" / "data"


def _family_dir(family_name: str) -> Path:
    """The data_dir of a declared content family (ADR 0184).

    Read from `tools/arch/families.json`, never hardcoded: a mod adding a new
    cultivation path declares its seed family there, and the validation follows
    the declaration rather than a second copy of where each path lives.
    """
    from ..arch.rules import load_families  # noqa: PLC0415

    families = load_families()
    if family_name not in families:
        raise ToolError(
            f"content family '{family_name}' is not declared in tools/arch/families.json"
        )
    return DATA / families[family_name]["data_dir"]


def _family_ids(family_name: str) -> set[str]:
    """Every `.tres` stem under a declared family's data_dir."""
    root = _family_dir(family_name)
    if not root.is_dir():
        return set()
    return {path.stem for path in root.glob("*.tres")}


# The three cultivation seed directories, read from the family declaration
# (ADR 0184) rather than hardcoded, so a mod adding a new path declares it in
# `tools/arch/families.json` and the validation follows.
REALM_DIR = _family_dir("body_realms")
QI_REALM_DIR = _family_dir("qi_realms")
MERIDIAN_DIR = _family_dir("meridians")
# The one runtime file whose arithmetic the gate-soundness checks mirror. It is
# read, never edited: the tool's model of the runtime is only allowed to be as
# good as its evidence.
QI_TRAINING = REPO_ROOT / "game/src/modules/qi_cultivation/training.gd"
TOLERANCE = 1e-6
# The three consumable roles a qi seed names. `training_item` is the one that
# matters to the ladder: `train_channel` refuses without it, so a realm whose
# elixir does not resolve has no verb to press and every boundary above it is
# unwalkable no matter what the other two gates say.
QI_ITEM_ROLES = ("training_item", "breakthrough_item", "recovery_item")


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
    meridians = _family_ids("meridians")
    acupoints = _family_ids("body_acupoints")
    items = _ids("items", "consumable") | _ids("items", "material")
    recipes = _family_ids("recipes")

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

    # Generic seed-family check: every declared cultivation path must have a
    # seed for every realm on the ladder. Runs for ANY declared path, not just
    # body and qi, so a mod adding a new path is covered the moment it declares
    # the family (ADR 0184). Body and qi are checked again below with their own
    # path-specific logic; this is the generic floor that needs no path knowledge.
    from ..arch.rules import load_families  # noqa: PLC0415

    for _info in load_families().values():
        if "path" not in _info or _info["path"] in ("body", "qi"):
            continue
        _dir = DATA / _info["data_dir"]
        for realm_id, _name2, _tier in ladder:
            if not (_dir / f"{realm_id}.tres").is_file():
                findings.append(f"{_info['path']}: no realm seed for {realm_id}")

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
    findings.extend(qi_gate_ladder_findings(ladder))
    # The authored meridian corpus is checked against the list the runtime plays, not
    # used to grade anything. Both readings agree today, and that agreement is the
    # hazard: nothing else would notice the moment one of them moved (BL-0755).
    findings.extend(
        meridian_tier_divergence_findings(
            ladder_module.meridian_tiers(), _meridian_tiers(MERIDIAN_DIR)
        )
    )
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


def _successors(ladder: list) -> dict[str, str]:
    """Realm id -> the id of the next realm up, the relation `ladder.next()` gives.

    Keyed by id, never carried as an index the caller compares against: an
    inserted realm must not shift every realm below it (ADR 0050), and an
    index-keyed check is exactly the shape that would.
    """
    out: dict[str, str] = {}
    for index, (realm_id, _name, _tier) in enumerate(ladder):
        if index + 1 < len(ladder):
            out[realm_id] = ladder[index + 1][0]
    return out


def _meridian_tiers(directory) -> dict[str, int]:
    """The AUTHORED corpus: `game/data/meridians/*.tres` id -> `tier`.

    Not what the runtime plays. `MeridianNetwork.unlock_for_realm` reads
    `MeridianDefaults.all()`, and nothing loads these files (BL-0755), so this is read
    only as the OTHER HALF of `meridian_tier_divergence_findings` — the copy that must
    not drift from the source. Grading gates with it was grading dead data.
    """
    tiers: dict[str, int] = {}
    root = Path(directory)
    if not root.is_dir():
        return tiers
    for path in root.glob("*.tres"):
        scalars = load_seed(path)["scalars"]
        if "id" in scalars and "tier" in scalars:
            tiers[str(scalars["id"])] = int(scalars["tier"])
    return tiers


def meridian_tier_divergence_findings(
    runtime_tiers: dict[str, int] | None, corpus_tiers: dict[str, int]
) -> list[str]:
    """Every meridian where the RUNTIME and the authored `.tres` corpus disagree.

    Both exist and only one plays. `unlock_for_realm` walks `MeridianDefaults.all()`,
    so `_build()` decides whether a channel is ever in the actor's hands, and the
    twenty `.tres` under `game/data/meridians` are read by nothing. They agree today,
    which is the whole hazard: a retune of `_build()` would have moved the gates while
    every finding graded the untouched copy stayed green. Two findings for one defect is
    two fixes, so membership and tier are reported together under one prefix and the
    message names which side the game actually honours.
    """
    if runtime_tiers is None:
        return []
    findings: list[str] = []
    for meridian_id in sorted(set(runtime_tiers) | set(corpus_tiers)):
        played = runtime_tiers.get(meridian_id)
        authored = corpus_tiers.get(meridian_id)
        if played is None:
            findings.append(
                f"qi_meridian_tier_diverges: {meridian_id} is authored in"
                f" {MERIDIAN_DIR}/{meridian_id}.tres at tier {authored}, but"
                " MeridianDefaults._build() does not define it, so it unlocks for nobody"
            )
        elif authored is None:
            findings.append(
                f"qi_meridian_tier_diverges: {meridian_id} unlocks at tier {played} in"
                f" MeridianDefaults._build(), but {MERIDIAN_DIR}/{meridian_id}.tres is absent"
                " from the authored corpus"
            )
        elif played != authored:
            findings.append(
                f"qi_meridian_tier_diverges: {meridian_id} unlocks at tier {played} in"
                f" MeridianDefaults._build() and tier {authored} in"
                f" {MERIDIAN_DIR}/{meridian_id}.tres; the runtime's number is the one that"
                " plays, so the authored copy is already dead data"
            )
    return findings


def qi_gate_ladder_findings(
    ladder: list,
    realm_dir=None,
    meridian_source=None,
    items: set[str] | None = None,
) -> list[str]:
    """Every qi boundary must be walkable by pressing verbs, and worth pressing.

    Two independent facts, and they fail separately: a boundary whose gate no
    elixir count reaches is a dead end, and a boundary whose gate a fresh actor
    already passes is a formality. Every test in the repo went through the facade
    and asserted the gate was ENFORCED, never that it was SATISFIABLE BY BUTTONS,
    so a flat `open` demand passed the whole suite while 25 of 29 boundaries were
    unwalkable and `refine_meridian` was unreachable.

    ## What is checked, and why that is enough without simulating the press loop

    `QiTraining.train_channel` walks a channel closed -> open -> expanded ->
    strengthened and then deepens it, refusing depth at the STANDING realm's
    `channel_refinement_cap`; `QiBreakthroughCondition` then asks the NEXT realm's
    seed. So for boundary R -> R+1 the gate is reachable by pressing buttons iff
    all of these hold, and each is asserted separately because each has its own
    cause and its own fix:

    - `R+1.required_channel_refinement <= R.channel_refinement_cap`. This is the
      one whose absence let the defect through: depth past the standing cap is
      refused before the elixir is spent, so no count of presses reaches it.
    - depth is only ever demanded on a channel at `strengthened`, because
      `MeridianNetwork.refine_meridian` refuses any other state.
    - `required_channel_state` names a real rung, and one the climb can reach:
      the verb walks the rungs in `MeridianState.STATE_ORDER` order, so a name
      the runtime does not know reads as rank 0 (`STATE_ORDER.get(required, 0)`)
      and SILENTLY WEAKENS the gate rather than failing it.
    - every named channel is unlocked while standing in R
      (`MeridianNetwork.unlock_for_realm`), or `get_meridian` returns null and
      `channel_met(null)` is false at any refinement.
    - the three consumables resolve in content, or `train_channel` refuses on
      `has_item` before it ever advances anything.

    The loop itself is NOT simulated: it needs an actor, an inventory and an
    item economy, none of which exist in Python. `tests/modules/qi_cultivation/
    test_qi_channel_ladder.gd` walks it through the real verbs. This guard asserts
    the structural property that makes such a walk terminate in success, so a
    content edit that breaks it is caught by `tools check` without an engine.

    Every input is injectable so a probe can aim this at a fixture; the defaults
    are the shipped corpus.
    """
    findings: list[str] = []
    ranks = ladder_module.channel_state_ranks()
    arrival = ladder_module.fresh_channel()
    # The tiers come from `MeridianDefaults._build()`, the list `unlock_for_realm`
    # actually iterates. `game/data/meridians` is the AUTHORED copy and nothing loads
    # it, so grading with it graded a corpus the player never receives (BL-0755);
    # `meridian_tier_divergence_findings` is what keeps the two from drifting.
    tiers = ladder_module.meridian_tiers(meridian_source)
    if ranks is None or arrival is None or tiers is None:
        return [
            "gate_ladder_premise_unreadable: cannot read MeridianState's rung order, the state"
            " a fresh channel arrives in, or MeridianDefaults' unlock tiers"
            f" ({_label(ladder_module.MERIDIAN_STATE)},"
            f" {_label(ladder_module.MERIDIAN_NETWORK)},"
            f" {_label(ladder_module.MERIDIAN_DEFAULTS)}), so the qi gate ladder was not"
            " checked"
        ]
    fresh_state, fresh_depth = arrival
    seeds_dir = Path(QI_REALM_DIR if realm_dir is None else realm_dir)
    known_items = _ids("items", "consumable") if items is None else items
    position = {realm_id: index for index, (realm_id, _n, _t) in enumerate(ladder)}

    seeds: dict[str, dict] = {}
    for realm_id, _name, _tier in ladder:
        path = seeds_dir / f"{realm_id}.tres"
        # A missing or malformed seed is `qi_gate_missing`'s finding, not a second
        # one from here: two findings for one defect is two fixes.
        if path.is_file():
            seeds[realm_id] = load_seed(path)

    for realm_id, _name, _tier in ladder:
        seed = seeds.get(realm_id)
        if not seed:
            continue
        scalars = seed["scalars"]
        channels = seed["arrays"].get("required_meridians", [])
        state = str(scalars.get("required_channel_state", ""))
        depth = int(scalars.get("required_channel_refinement", 0))
        cap = int(scalars.get("channel_refinement_cap", 0))

        if state not in ranks:
            findings.append(
                f"qi_gate_channel_state_unknown: {realm_id}: required_channel_state {state!r} is"
                f" not one of MeridianState's rungs ({', '.join(sorted(ranks))}), and the"
                " runtime reads an unknown rung as 0, so this gate is silently weaker than"
                " it reads"
            )
        if depth > 0 and state != "strengthened":
            findings.append(
                f"qi_gate_depth_below_strengthened: {realm_id} demands channel depth {depth} but"
                f" gates on {state or '(none)'!r}; MeridianNetwork.refine_meridian refuses a"
                " channel that is not strengthened, so the depth is unreachable at any elixir"
                " count"
            )
        if depth > cap:
            findings.append(
                f"qi_gate_demands_more_depth_than_its_own_cap: {realm_id} demands depth {depth}"
                f" above its own cap {cap}, so even standing in this realm the last {depth - cap}"
                " step cannot be trained"
            )
        if not channels:
            findings.append(
                f"qi_gate_names_no_channel: {realm_id} names no required channel, so its"
                " channel gate checks zero channels and can never be unmet"
            )
        elif state in ranks and ranks[state] <= ranks[fresh_state] and depth <= fresh_depth:
            findings.append(
                f"qi_gate_vacuous_for_a_bare_actor: {realm_id} asks only for {state} at depth"
                f" {depth}, and every channel an actor arrives with is {fresh_state} at depth"
                f" {fresh_depth}, so the gate is passed without training"
            )
        for role in QI_ITEM_ROLES:
            item = str(scalars.get(role, ""))
            if not item or item not in known_items:
                findings.append(
                    f"qi_gate_item_missing: {realm_id}: {role} is {item or '(unauthored)'!r} and"
                    " does not resolve in items/consumable, so the verb that advances this gate"
                    " is refused before it does anything"
                )
        for meridian_id in channels:
            if meridian_id not in tiers:
                findings.append(
                    f"qi_gate_channel_unknown: {realm_id} names channel {meridian_id}, which is"
                    " not a meridian definition"
                )

    # The boundary walk. Bounded by the ladder's own length: each id is visited
    # once, and no body appends to the container it is walking (INC-0002).
    successors = _successors(ladder)
    for standing, target_id in successors.items():
        standing_seed = seeds.get(standing)
        target_seed = seeds.get(target_id)
        if not standing_seed or not target_seed:
            continue
        standing_cap = int(standing_seed["scalars"].get("channel_refinement_cap", 0))
        target_scalars = target_seed["scalars"]
        wanted = int(target_scalars.get("required_channel_refinement", 0))
        if wanted > standing_cap:
            findings.append(
                f"qi_gate_demands_more_depth_than_the_realm_below_offers: {target_id} demands"
                f" depth {wanted}, but an actor standing in {standing} can only reach"
                f" {standing_cap}: train_channel refuses depth at the standing realm's cap"
                " before it spends the elixir, so no count of presses reaches this boundary"
            )
        standing_index = position[standing]
        for meridian_id in target_seed["arrays"].get("required_meridians", []):
            if meridian_id in tiers and tiers[meridian_id] > standing_index:
                findings.append(
                    f"qi_gate_channel_never_unlocks: {target_id} names channel {meridian_id},"
                    f" which unlocks at tier {tiers[meridian_id]}, but an actor standing in"
                    f" {standing} (index {standing_index}) does not hold it, so the gate can"
                    " never be met"
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
