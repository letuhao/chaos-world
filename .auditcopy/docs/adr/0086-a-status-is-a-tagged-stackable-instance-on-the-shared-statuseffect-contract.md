# 0086 A status is a tagged, stackable instance on the shared StatusEffect contract

- Status: Proposed
- Date: 2026-10-03

## Context

`contracts/status_effect.gd` is 25 lines: `id`, `remaining`, `tick`, `is_permanent`,
`is_expired`. `Actor.statuses: Array[StatusEffect]` holds them and `add_status` /
`has_status` / `tick_statuses` (`core/actor.gd:133,139,146`) iterate a flat array.
Three consumers already exist and none is a timer: `heavenly_blessing`
(`core/tribulation.gd:322`), `PregnancyStatus` — a four-stage state machine that
`extends StatusEffect` (`modules/fertility/pregnancy.gd:1-2`) — and ADR 0075's
environment zones, which require every hazard to publish non-empty `mitigation_tags`.
A DoT needs a magnitude; a control needs a gate. Both are data on the same instance, so
twenty statuses must not become twenty subclasses.

Two designs proposed different shapes: extend the contract, or subclass it in the combat
layer. A module-owned subclass keeps `contracts/` untouched, but ADR 0075 requires
environment hazards to obey the *same* application, refresh and cleanse rules, and
environment is not combat. A subclass that assumes a combat source is the wrong home for
shared vocabulary.

**`contracts/` may depend on `contracts/` alone** (`tools/arch/rules.py:30`) and is in
`BARE_REF_UNITS` (`rules.py:60`), so a bare reference out of it to `ElementStats` or a
module `StatusDef` is an enforced violation. The contract therefore carries **no element
type**: an element is a `StringName` tag, which is all ADR 0069's "one element per
attack" rule needs.

## Decision

**One shared contract, extended in place. No subclass per status; a subclass only for a
genuine state machine.**

- Fields, all defaulted so the live constructor calls keep compiling: `id`, `element:
  StringName`, `kind`, `scope`, `stacking`, `magnitude: float`, `magnitude_cap: float`,
  `stacks: int`, `remaining`, `tick_interval`, `tick_elapsed`, `source: StringName`,
  `mitigation_tags: Array[StringName]`, `payload: Dictionary`.
- `enum Kind { DOT, STAT_MODIFIER, CONTROL, AMPLIFIER, BURST }`, `enum Scope { COMBAT,
  CULTIVATION }`, `enum Stacking { REFRESH, STACK, REPLACE }`. `Op` is **not**
  duplicated — `Stat.Op` is reused (ADR 0068: a second enum is a second place to get
  FLAT-on-a-rate wrong).
- `mitigation_tags` is REQUIRED and non-empty. Empty is an authoring error `tools data
  audit` rejects, exactly as ADR 0075 rules for a hazard zone. It is the ONE purge
  vocabulary, read by the combat layer, environment and consumables alike.
- **Stacking, precisely.** `REFRESH`: duration `max(remaining, incoming)`, magnitude
  keeps the **stronger** value — a weak re-application never shortens a strong one.
  `STACK`: duration `max(remaining, incoming)`, `magnitude += incoming` then
  `magnitude = min(magnitude, magnitude_cap)`, `stacks += 1`. `REPLACE`: duration and
  magnitude both overwritten. Linear addition is deliberate — `_buckets()` already sums
  FLAT and PERCENT linearly per stat (`core/actor_stats.gd:185-198`) — and `Op.MULT` is
  **banned** for a status, because N instances would compound to 1024x and make a
  status's strength a function of how often it was applied.
- `Scope.COMBAT` is resisted by `Stat.STATUS_RESISTANCE`; `Scope.CULTIVATION` is not — a
  blessing the game pays out must not tax the player for receiving it.
- A subclass stays legal and stays required for a machine: `PregnancyStatus` keeps its
  `extends StatusEffect`. What is refused is a subclass per *status*, and any subclass
  that assumes a single source, because the base class is the shared vocabulary rather
  than a combat-owned type.

## Consequences

- `contracts/` stays a leaf layer: no `ElementStats`, no module `StatusDef`, and no
  `StatModifier` construction inside a status. A status is **data**; the module that
  applies it turns `magnitude` into `StatModifier`s.
- Adding a 21st status is a def, not a class, and `tribulation.gd:322` and
  `fertility/api.gd:41` are untouched.
- The op on a stat id is enforced against the **stat**, never against the status:
  `Stat.DAMAGE_REDUCTION` (baseline `0.0`, `core/actor_stats.gd:172`) takes FLAT only,
  and PERCENT on it is the ADR 0022 no-op.
- Adding these fields is an ADR-level change to a `contracts/` interface
  (`AGENTS.md:155`); this is that ADR.
