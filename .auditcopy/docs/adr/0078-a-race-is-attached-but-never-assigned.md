# 0078 A race is attached but never assigned

- Status: Accepted (partly superseded — see below)
- Date: 2026-10-03
- Supersedes: ADR 0062 (a race is a body plan that refuses to be a stat stick)
- Consistent with: BL-0229, BL-0235
- Partly superseded by: ADR 0079 (bloodline and clan were empty then; they are not now), ADR 0108
  (birth resolves race and purity), ADR 0109 (race now gates the breakthrough)

## Status of this record, read first

This ADR was written against a tree where `race` shipped but nothing consumed it. Four of its
findings were true then and **three are now false**, because the lineage program was completed
afterwards. Stating which is which, so the next reader does not act on a stale claim:

| Finding | Then | Now |
|---|---|---|
| 1. `SpeciesDef` survives and is the live fertility parameter type | TRUE | **FALSE** — deleted. `FertilityApi.attach(actor)` takes no species; gestation reads `RaceDef.gestation_days` (ADR 0108) |
| 2. the field is named `closed_paths`, not `path_restrictions` | TRUE | TRUE — unchanged |
| 3. `commonborn` has no liability, so `has_liability()` is false | TRUE | **FALSE** — `commonborn` now closes `mind_cultivation`; the content test passes |
| 4. a race gates nothing and birth still averages | TRUE | **FALSE** — birth resolves one race and per-lineage purity (ADR 0108), and all three cultivation facades consult `RaceGate` at the breakthrough seam (ADR 0109) |

The reasoning below is preserved because it was right when written and because the evidence
method is the reusable part: every claim was a `file:line` count, not an impression.

## Context

ADR 0062 shipped `race` as a module with a body-plan `RaceDef`, and it reads as done. Four of its
claims are contradicted by the tree. The reasoning behind them is sound and is preserved below as
design; only the status was wrong.

## The four false claims, with evidence

**1. "`SpeciesDef` ... the old class is deleted rather than kept as an alias" (ADR 0062:39, and
`:59` "deleting it costs nothing").** It survives and is still the live parameter type.
- `modules/fertility/species_def.gd:1` — `class_name SpeciesDef`, six `@export`s.
- `modules/fertility/api.gd:11` `attach(actor: Actor, species: SpeciesDef = null)`,
  `:49` `advance(..., species: SpeciesDef = null)`, `:101` `_gestation_step(..., species: SpeciesDef)`.
- `app/actor_factory.gd:41` `with_fertility(actor: Actor, species: SpeciesDef = null)`.
- `modules/fertility/pregnancy.gd:13` `var species_id: StringName`.
- All four reproduction fields are **duplicated** onto `RaceDef`
  (`modules/race/race_def.gd:36-39`). Two classes now own the same numbers.

**2. "The liabilities are structural, not numeric: a closed `path_restrictions` list, `lifespan`, ..."
(ADR 0062:35).** The field is named `closed_paths`, not `path_restrictions`
(`race_def.gd:52`); `path_restrictions` has zero occurrences in `game/` or `tools/`.

**3. "Every race carries a liability ... A race without a liability is a content bug"
(ADR 0062:33-34).** `game/data/races/commonborn.tres` has `closed_paths = Array[StringName]([])`,
`realm_ceiling = 0`, `lifespan = 36500.0`, so `RaceDef.has_liability()` is **false**
(`race_def.gd:100-101`). `RaceCatalog.race_ids()` returns it
(`race_catalog.gd:29-36`), so the guard test
`tests/modules/race/test_race_content.gd:85-95` — which asserts the opposite for every authored
race — cannot pass against the shipped content.

**4. "The questions a race actually answers ... are answered in combat and at every breakthrough"
(ADR 0062:20-21), and "The birth system stops averaging attributes blindly"
(ADR 0062:51-52).** Nothing reads race at a breakthrough, and birth still averages.
- Zero occurrences of `RaceApi`, `RaceGate`, `allows_realm`, `allows_path` or
  `realm_ceiling_exceeded` in `modules/body_cultivation/`, `modules/qi_cultivation/`,
  `modules/mind_cultivation/` or `core/`. `RaceGate` is called only from `race/api.gd`,
  `race/race_resolver.gd` and `race/stats.gd`.
- `FertilityApi._resolve_labor` (`modules/fertility/api.gd:112-118`) builds a child from
  `_combine(actor.stats.base_dict(), status.partner_base, quality)`, and `_combine`
  (`api.gd:89-96`) is `(a + b) * 0.5 * quality` — the arithmetic mean of both parents. It never
  calls `RaceApi`, so a child is raceless.

## Decision

**The body-plan design stands. Its implementation is partial, and the record says so.**

- **What ships:** the `race` module (13 scripts), `RaceDef` with `dominance`,
  `manifestation_threshold`, `closed_paths`, `realm_ceiling`, `lifespan`, `base_attributes`,
  `percent_modifiers`, `affinities`, a `BASELINE_TAG` fallback, source-tagged projection
  (`race_projection.gd`), an `Actor`-ledger `race_state.gd`, and four authored races
  (`commonborn`, `emberblood`, `stoneborn`, `tidecaller`). Declared deps are exactly
  `[contracts, core]` in `tools/arch/registry.json`, so ADR 0062:46-47 holds.
- **`SpeciesDef` is not dead code.** It is the parameter every fertility entry point still takes.
  Deleting it is a live refactor, not a rename: the call sites are `FertilityApi.attach`,
  `FertilityApi.advance`, `_gestation_step`, `ActorFactory.with_fertility` and
  `PregnancyStatus.species_id`. Until they are repointed, `SpeciesDef` and `RaceDef` both carry
  gestation, fertility, potency and variance.
- **`commonborn` is the counterexample the design forbids.** Either it gains a liability, or
  `has_liability()` stops being a universal rule and the baseline race becomes the named exception.
  That is a content or design ruling, not a code fix.
- **A race gates nothing yet.** `race_gate.gd` exists and is testable
  (`tests/modules/race/test_race_gate.gd`, `test_race_gate_refusal.gd`), but no gate reads it.
- **`resolve_race` is a pure function in `race/race_resolver.gd`**, headless-testable as ADR 0062
  claimed — but only its own tests call it. `FertilityApi` does not.

## Consequences

- **BL-0229 and BL-0235 already say this**, in the backlog's own words: *"race is attached but
  never assigned, so every actor is raceless and all its gates are theatre"* and *"Birth produces
  an average, not a being: labor never resolves race"*. ADR 0062 was the durable record failing to
  say what the backlog said.
- ADR 0062's Context (that `SpeciesDef` was wired to nothing and modelled only reproduction) was
  accurate when written and is now **half** accurate: `game/data/species/` still holds only
  `.gitkeep`, and `FertilityApi.attach` is still never called with a species — but
  `RaceApi.attach` now is, and `commonborn` carries the `baseline` tag ADR 0062 asked for.
- Racing is not a character-creation choice yet. It is a module with a facade, an authored
  catalog and a resolver, waiting on one caller.
