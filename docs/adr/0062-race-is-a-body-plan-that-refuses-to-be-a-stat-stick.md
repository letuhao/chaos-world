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

## Correction 2026-10-05 (BL-0279): the partition holds, and the axis-lead claim is measured

**Recorded here rather than in a new ADR because nothing above changes.** The Decision
above names `lifespan` as one of the liabilities and Context above names "how long does it
live" as a question a race answers in combat; both sentences are still what this ADR says,
and this section says which of them the game currently performs.

### What was measured, from the five shipped `.tres` files

Leader per cultivation axis, by the strongest `base_attributes` value any body authors on
that axis's governing attributes (`spirit`/`aptitude`, `physique`, `comprehension`):

| axis | leaders (max authored value) | ties |
|---|---|---|
| `qi_cultivation` | `emberblood` 3.0 (`aptitude`) | 1 of 5 |
| `body_cultivation` | `stoneborn` 4.0 (`physique`) | 1 of 5 |
| `mind_cultivation` | `tidecaller` 3.0 (`comprehension`) | 1 of 5 |

**No body leads all three, so race x path is a partition today.** `commonborn` is a flat
1.0 across all seven attributes and therefore leads none of them; `emberblood_touched`
authors `physique: 2.0, will: 2.0` and leads none either, which is the content change that
made a fifth body addable without strengthening a specialist. The earlier audit that found
`commonborn` on top of every axis used a scoring function that scored a closed path as
`-1000.0`, so "leads an axis you are forbidden to enter" was an artefact of the arithmetic
rather than a balance property; that score is gone and the table above replaces it.

### The `MAX_TOP_AXES := 2` guard is deleted, and no cap replaces it

It was a constant invented inside a test file, with no ADR behind it, and the ADR text was
searched for a stated count of top axes: there is none. Two rules cannot both be invented —
one of them is always wrong and nothing said which. What is left is the sentence this ADR
actually states, asserted directly:

- **every race is genuinely refused somewhere**, read through ADR 0109's real gate
  (`test_race_content.gd::test_every_authored_race_is_genuinely_refused_somewhere`); and
- **no race leads every axis**, measured across the whole catalog
  (`test_race_axis_partition.gd::test_no_authored_race_leads_every_cultivation_axis`).

No number is capped, because no ADR states one. A cap could not be reintroduced as
`MAX_TOP_AXES := 1` without re-creating the defect: `emberblood_touched` is authored to lead
nothing precisely so that a fourth body can exist without strengthening the specialists, and
a cap of 1 would forbid the thing this roster does.

### What the measurement could not prove, and did not replace

`test_race_body_plan.gd` still holds each race's authored attributes against what the
pipeline derives. A mutation showed the limit of that: raising `commonborn` to
`physique/spirit/aptitude/comprehension/will: 9.0` — a body leading qi, body and mind, the
exact defect BL-0279 was filed against — turned that suite red nine times and every message
was about a number ("'tidecaller' is the top comprehension, as its plan says: expected
tidecaller, got commonborn"). A table of authored values cannot tell a retune from a
degenerate tree, because both are "a number moved", and it never states a claim about the
relationship *between* bodies. That is why the partition now has its own measurement
instead of resting on a restatement of the content.

### Correction 2026-10-05 (BL-0772): `lifespan` is authored and enforced by nothing

The Decision above lists `lifespan` among a race's structural liabilities and Context above
lists "how long does it live" among the questions a race answers in combat and at every
breakthrough. **Both are authored data that no system enforces.** Stated plainly, because
the sentences above would otherwise read as behaviour:

- `RaceDef.lifespan` is authored on all five races (`emberblood` 18,250 d to `tidecaller`
  58,400 d; `RaceDef`'s own default 36,500 d).
- `RaceProvider` publishes it as `race_lifespan`, scaled by realm tier through ADR 0169's
  `RealmLifespan` table.
- `RaceApi.summary` exposes it on the actor's own row and on every per-race row.
- **Nothing reads it.** A grep for `RaceStats.LIFESPAN` / `race_lifespan` over `game/src`
  returns three hits, all in `modules/race`: the constant's declaration, the one
  `contribute` line that writes it, and the `"race_lifespan_probe"` id of the one-collection
  bridge `RealmLifespan` reads. Not even the character-creation screen formats it —
  `character_creation_flow.gd` reads only `display_name` and `closed_paths` off a summary
  row.

**What it would take to make it real, none of which is decided here:** an age an actor
carries and persists (`Actor.to_dict()` serialises none, and `age_days` / `age_years` /
`elapsed_days` / `born_year` / `born_on` return zero hits across `game/src`); a clock that
advances it, which this repository does not have — the only `age` in the tree is
`FightLoop.age(delta)` (a combat rate gate), `BossEncounter.age(delta)` and
`SocialBond.age` (a bond counter), and none is an age; and a decision on what crossing the
lifespan *does* — death by age or a soft cap at the breakthrough seam — which ADR 0109
records as its open third gate and ADR 0169 defers explicitly. That work is BL-0037, in
`core`, and belongs to whoever owns time. It is **not** built here.

Consequently the partition above counts only refusals the game performs: a closed path and a
realm ceiling, read through ADR 0109's gate. A short lifespan is an **authored** liability
and is deliberately not counted as a refusal, because nothing compares an age against it —
`test_race_lifespan_is_inert.gd` pins exactly that: the value is published on every surface
a future system could consume, and no age exists to compare it against. That suite is
written to go **red** the day an age field lands, so the gap becomes a failing test when it
stops being a gap.