# 0147 The unread MindRealmSeed fields are deleted rather than wired

- Status: Accepted
- Date: 2026-10-04
- Amends: ADR 0024 (mind realm contracts), ADR 0096 (deleted rather than given a fourth role)

## Context

Four fields on every `MindRealmSeed` were authored, shipped and read by nothing.
Measured, not assumed: the only hit for any of them in `res://src` is the `@export`
line itself, the only writer is `tools/cultivation/seed_systems.py`, and no ADR names
them — ADR 0024's enumeration of the contract stops at rewards. They are
`sea_milestone_work`, `meridian_milestone_work`, `insight_required` and
`resonance_required`.

**AGENTS.md's RATE_STEP rule does not depend on the two work-budget fields.** The rule
bounds `RATE_STEP` by "the smallest per-realm step in the three authored
`progress_required` ladders", and `test_realm_rate.gd` computes the bound from
`BUDGET_FIELD := "progress_required"`. Deleting `sea_milestone_work` and
`meridian_milestone_work` leaves the ceiling (qi R29→R30, `2900/2800`) exactly where
it was. BL-0155 asserted the opposite and was wrong; `tools realm_power check` passes
unchanged.

## Decision

**Delete `sea_milestone_work`, `meridian_milestone_work` and `resonance_required`. Wire
none of them.**

- **The two work budgets gate verbs that are already gated.** `strengthen_sea` spends a
  mandatory per-realm `sea_catalyst`; `train_channel` spends the realm's
  `training_item`. ADR 0096 rejected a fourth mandatory consumable on exactly this
  reasoning — it doubles a boundary's cost and adds no choice to it. Charging work as
  well is the same decision taken twice. `train_channel` is the worse of the two: it is
  the verb that raises a channel to `required_channel_state` (STRENGTHENED), which IS
  the next realm's entry gate, so a work threshold there taxes the gate-raising verb
  itself.
- **`resonance_required` is a duplicate of a body field and cannot be a gate.** It is
  byte-identical to `BodyRealmSeed.resonance_rank` at all 30 realms, and
  `MeridianNetwork.resonance_rank` is one shared field written only by
  `body_cultivation/training.gd`. Nothing on the mind or qi path raises it, so
  requiring it in `strengthen_anchor` — the R19+ milestone that is the only thing that
  pays for the anchor — locks any actor who never trains body out of that milestone
  permanently. It is the most tempting of the four to wire and the one that must not be.
- **`insight_required` is a weaker copy of a gate that already binds.** It is exactly
  `comprehension_required * 0.5` at all 30 realms, and `comprehension_required` is
  enforced on the same stat in `MindBreakthroughCondition` and
  `MindAdvancement._gates`. A threshold below one already enforced can never be the
  deciding term.

Guard: `game/tests/modules/mind_cultivation/test_mind_seed_unread_fields.gd`, in three
legs — the class property list, the shipped `.tres` text, and an unconditional liveness
term asserting the scanned set is the whole ladder and still loads.

## Consequences

- **`insight_required` stays, and is still dead.** Deleting it is one edit in
  `game/tests/modules/test_seed_generator_parity.gd`, outside this change's files;
  BL-0146 carries it. It is the only one of the four left.
- **A `.tres` line for a property the class dropped is silently ignored by Godot 4.7.**
  Measured: deleting all four `@export`s while the 30 seeds still authored them produced
  no error and no warning. So `tools/cultivation/seed_systems.py` still emits all four,
  and a regeneration onto a clean tree re-authors them. Leg 2 of the guard is what makes
  that visible; that file is not this path's to edit — the same shape ADR 0096 left
  behind.
- **The whole blast radius is one red case.** Removing the four `@export`s and leaving the
  seeds authoring them costs `test_mind_insight_is_half_of_comprehension` and nothing
  else: no `res://src` reader, no other case.
- No mechanic changed. No verb, gate, item or stat moved.