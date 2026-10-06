# 0879 the shield is a capacity pool the spine drains through absorb(amount, penetration)

- Status: Accepted
- Date: 2026-10-06

## Context

- ADR 0076 deleted `shield.gd` and left `CombatSpine.SHIELD_COMPONENT` a duck-typed slot
  tagged "wave E's to write". The gate has been live and tested against doubles since;
  the four `CombatStats.SHIELD_*` ids (`capacity`, `toughness`, `pen`, `regen`) were
  declared, defaulted and read by nothing.
- The gate's original contract was `absorb(amount) -> overflow`, which cannot carry the
  attacker's cut: `SHIELD_PEN` is the ATTACKER's number, and a component that sees only
  the defender cannot read it.

## Decision

- `CombatShield` (`modules/combat_engine/shield.gd`) is the shipped binding.
- The contract is `absorb(amount: float, penetration: float) -> float`, returning the
  overflow it did NOT take. `CombatSpine._absorb` passes the attacker's `SHIELD_PEN` as
  the second argument. The slot stays DUCK-TYPED — the spine names no class — so a test
  double binds the same way.
- The pool math: penetration is spent off the pool BEFORE the blow; removal is
  `min(current * toughness, amount)`, capped at the blow itself; the return is
  `amount - removal`. A shield removes damage; it never deals it. `toughness` is
  `1.0 + SHIELD_TOUGHNESS` and can only be RAISED by authoring — `ActorStats._put`
  floors a channel at zero, so a negative modifier is unreachable; the weakening half
  of the shield is the attacker's `SHIELD_PEN`.
- `regen` is refilled by `tick(delta)` only. Time belongs to a combat tick, never to one
  hit's resolution — the same rule `combat_tuning.gd` states for the field.
- The component holds NO actor reference: `refresh(owner)` pulls the four numbers (with
  their neutral defaults folded), because actor → component → actor is a RefCounted
  cycle and a cycle leaks. `attach(actor)` is the one FULL bind; `refresh` never refills.

## Consequences

- All four `SHIELD_*` ids now have a reader; authoring them does something.
- Production still binds no shield: `CombatShield.attach` is the verb a composition root
  or content will call when shields ship as gear, and an unbound actor absorbs nothing,
  exactly as before.
- Tests: `tests/modules/combat_engine/test_combat_shield_component.gd` pins the pool,
  the cut, toughness scaling, regen and caps, refresh semantics, and the spine path; the
  doubles in the two older shield suites take the second argument as an unused default.