# 0129 Difficulty scales a fraction of what is carried and never a magnitude the game computes

- Status: Accepted
- Date: 2026-10-04
- Depends on: ADR 0050 (realm strength is authored data, not a computed curve), ADR 0116 (the
  realm rate is one shared curve in `core`), ADR 0127 (the soul outlives its actor)
- Resolves: BL-0066 (difficulty presets)

## Context

The game has no difficulty setting, and a rebirth loop needs one: how much a death costs the
soul, how many lives exist, and how much a guardian item is worth are the three numbers that
make death mean anything.

This repo has three separate power-shaped tables and a written rule about adding a fourth.
`core/realm_power_table.tres` is authored per realm id; `item_magnitude_scale.json` and the
technique ladder are deliberately independent and are never derived from one another. ADR 0050
records the failure that produced the rule — reading a shared exponential as a gain made one
number mean two things — and `AGENTS.md` states the consequence plainly: adding a scale at all
is a reviewed change, and a new power-shaped number needs an ADR rather than a second curve.

A difficulty dial is exactly the shape that mistake takes. Scaling combat by it makes the
realm table move one side and not the other, which breaks the invariant that makes a 551x
ladder safe.

## Decision

**Difficulty is an authored preset table with a closed set of five scalars, all of them
fractions of what the player already holds. It never multiplies anything the game computes.**

- **A new `difficulty` module owns the table and its facade.** Not `core/`: a difficulty dial
  is feature logic, and `AGENTS.md` forbids feature logic in `core/`. Not `app/`: the selected
  id persists into `module_data`, which is the exact `APP_STATE_MARKERS` shape
  (`tools/arch/rules.py:169-176`), and `app/` is the composition root that wires.
- **The table is keyed by a stable difficulty id, never by an enum index and never by a
  realm.** An inserted preset cannot shift anything else onto the wrong number, for ADR 0050's
  reason applied to a new axis.
- **The shipped default preset is exactly `1.00` on all five scalars.** Selecting the default
  difficulty is therefore arithmetically a no-op and every existing number stays valid. This
  is the "R1 at 1.0" rule of the realm power table applied to a preset axis, and the guard
  asserts it so the baseline cannot drift into a hidden rebalance.
- **The scalar set is closed and is exactly these five:** soul damage share, death loss cap,
  guardian effectiveness, loot ceiling, tribulation preparation credit. A sixth column is a
  second power curve in disguise and fails the guard. Every scalar is bounded and finite; none
  may be named after a realm, tier, ordinal or index.
- **`scalars()` is one verb answering five questions.** Fifteen modules already sit at the
  twelve-method facade cap, so a per-scalar getter would spend the cap on four verbs that
  answer one question.
- **`difficulty` depends on nothing, and consumers pull from it.** The inversion is the ADR
  0093 rule: the observer registers with the subject, so `soul` declares the edge and calls
  the facade, and `difficulty` never names `soul`.
- **A scalar with no consumer is removed, not left authored.** An audit measured it: only
  `soul_damage_share` and `death_loss_cap` were read anywhere, so selecting a preset changed
  exactly one number in the game and three columns were theatre.
  `guardian_effectiveness` now has one consumer — `_heal` restores the pool to that fraction of
  full rather than all of it, so a harder preset makes the guardian a weaker rescue, which is
  the only reading that makes it a difficulty rather than a duplicate of `soul_damage_share`.
  `loot_ceiling` and `tribulation_preparation_credit` have no honest consumer yet: scaling a
  drop tier or a tribulation's preparation credit needs a decision about what those are
  measured against, and inventing one here would be a second guess about a power-shaped
  number. Both are recorded in the backlog and neither is read by code.
- **Combat reads nothing.** Nothing in an exchange or a damage formula has a place a
  difficulty id belongs, and the place it would be tempted into — the damage share — is on the
  forbidden list below. `tools/arch` cannot see a code-only cycle between two modules, so a
  structural test reads both module sources and fails if either names the other's path.

## Consequences

- **Forbidden, each with its authority:** cultivation progress or breakthrough speed (ADR 0116
  — one shared `RATE_STEP`, bounded by the authored work budget); any realm power multiplier
  (ADR 0050); `RealmRate` (ADR 0116); the combat damage share and its anti-stall ceilings (the
  exchange deliberately spends a share so the realm table moves both sides together); a health
  pool maximum (a difficulty dial on a pool maximum is a stat composer, which ADR 0084 forbids
  in the same shape); a boss's vitality or attack (breaks the two-sided invariant); and any
  `StatProvider` contribution.
- **Difficulty takes no time.** A difficulty that rises with playtime needs a clock the repo
  refuses (DEF-0111), so it is not available. An accrual takes explicit `periods` from a
  caller that owns time, as `holdings` already does.
- **A guard nobody has seen fire is not a guard.** The check asserts shape — every preset
  carries all five scalars, the default row is neutral, the ladder is ordered, no sixth column,
  no realm-shaped key — and the suite mutates a throwaway copy to prove each assertion
  actually fires, the `tools cultivation mutate` precedent.
- **Two stale entries are corrected in the same change.** The claim that nothing damages a
  health pool is false: `combat/exchange.gd` and `combat_engine/spine.gd` both subtract from
  it. An agent that believes the entry builds a second death path on top of an existing one.
- **Selecting a difficulty is a player choice and is stored with the run.** It is not a global
  setting, because a save that cannot say what it was playing under is not self-describing.
