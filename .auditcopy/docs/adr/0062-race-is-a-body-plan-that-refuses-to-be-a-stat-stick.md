# 0062 A race is a body plan that refuses to be a stat stick

- Status: Accepted
- Date: 2026-10-02
- Amends: ADR 0002 (`SpeciesDef` grows from reproduction parameters into a body plan)

## Context

`SpeciesDef` exists with six fields and is wired to nothing: `game/data/species/` holds only
`.gitkeep`, `FertilityApi.attach(actor, species)` is never called with a species, and
`PregnancyStatus.species_id` / `offspring_variance` are written by nobody. It also models only
reproduction — `gestation_days`, `base_fertility`, `base_potency` — so it answers "how does this
thing reproduce" and not "what is this thing".

The obvious design is a race that is a bag of bonuses. That is wrong twice over:

- It has no optimum, so every character converges on the same race and the choice stops being a
  choice.
- It is invisible at the moment it matters. A stat stick is read once on a character sheet, while
  the questions a race actually answers — *can this body cultivate this path at all*, *what does it
  feed on*, *how long does it live* — are answered in combat and at every breakthrough.

A race also has no current home. `fertility` averages both parents' base attributes in
`_resolve_labor`, so a child of any two parents is the same actor regardless of who they are. The
birth system produces bodies, not beings.

## Decision

- **A race is a body plan, and it is one value, not a blend.** A child of two different races is
  born *one* race, never a mixture. `RaceDef` gains `dominance` — how strongly the race asserts in
  a contested conception — and the shares resolve to the single highest-dominant race that clears
  `manifestation_threshold`, falling back to the `baseline` race when none does.
- **Every race carries a liability as authored data, in the same `Resource` as its advantage.**
  A race without a liability is a content bug. The liabilities are structural, not numeric: a
  closed `path_restrictions` list, `lifespan`, resource pools the body does not have, or an affinity
  it cannot hold. A stat penalty is the weakest of these and never sufficient alone.
- **`RaceDef` replaces `SpeciesDef` and inherits its reproduction fields.** `gestation_days`,
  `base_fertility`, `base_potency` and `offspring_variance` are race data, not a separate species
  concept, and the old class is deleted rather than kept as an alias.
- **Race grants are additive over an authored baseline and are projected as source-tagged
  modifiers**, rebuilt from the ledger on every attach, never accumulated. Source tag
  `race:<race_id>`. Base-attribute grants are applied once through `set_base` at attach, because a
  modifier cannot lower a base attribute.
- **A race is assigned once, at conception, and is immutable for the actor's life.** There is no
  transformation, no assimilation, and no way to become another race. Ascension does not change it.
- **`race` is its own module** with `contracts` + `core` deps and nothing else, so `bloodline` and
  `clan` can both depend on it without either depending on the other.

## Consequences

- The birth system stops averaging attributes blindly: `resolve_race(parent_a, parent_b)` is a pure
  function of two actors and a roll, so it is headless-testable and deterministic.
- A race is legible without opening a stat sheet — the UI reads which paths it closes, not a delta
  it has to diff.
- `dominance` is the whole reason mixing is a decision: a high-dominance race swallows a
  low-dominance partner's line, so the pairing the player chooses is a real choice with a real
  failure mode.
- Adding a race is authoring a `.tres` under `game/data/races/`, never code.
- `SpeciesDef` had no production caller, so deleting it costs nothing. `game/data/species/` becomes
  `game/data/races/`.