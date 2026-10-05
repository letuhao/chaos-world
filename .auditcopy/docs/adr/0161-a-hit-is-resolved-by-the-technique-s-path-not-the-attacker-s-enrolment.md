# 0161 A hit is resolved by the TECHNIQUE's path, not the attacker's enrolment

- Status: Accepted
- Date: 2026-10-04

## Context

`MechanismSlot` holds ONE `DamageMechanism` per actor, and `CombatSpine.resolve_hit`
reads it off the attacker at S4. ADR 0067 made that slot the seam, and it is a good
seam: one component, three mechanisms, and no `if/else on path_id` anywhere in
`modules/`.

`CombatBoot.bind_mechanisms` chose the slot's contents from the attacker's ENROLMENT:
exactly one of `BodyDamage` / `MindDamage`, and qi otherwise. That rule is correct as
an answer to "which mechanism is bound when nothing says otherwise", and qi is the right
neutral — it is the only mechanism whose input the element provider gives every
root-built actor, and qi never raises immunity (BRIEF 2.2), so it cannot dominate a build
that spent nothing on `ATTACK_SPIRITUAL`.

It was the wrong answer to "which mechanism is THIS HIT worth", and in production it
collapsed to qi universally. `ItemWorkbenchApp._build_actor` and
`CharacterCreationFlow._body` both enrol the player on all three paths, so
`has_body == has_mind` was true on EVERY player actor and every one of them bound
`QiDamage`. Body and mind could not fire in the shipped app at all — not rarely, NEVER.
The three-mechanism program was fully built, fully tested (5561 green), and unreachable.

Three fixes were available:

1. **Narrow the player's enrolment to one path.** Deleting the dual-cultivator the game
   ships, to make a rule true. Rejected.
2. **Select by the attacker's component set alone.** Already the rule; it is the thing
   that fails, since a tri-path actor has all of them.
3. **Select by the ATTACKING TECHNIQUE's path.** `TechniqueDef.path` already exists and
   is populated on all 55 authored `.tres`: 22 `qi_cultivation`, 20 `body_cultivation`
   (11 active), 10 `mind_cultivation`, 6 `shared`, 13 DUAL.

Option 3 needs no new authored data and makes a stronger claim: the mechanism is a
property of the STRIKE, not of the thrower. A tri-cultivator throwing a palm strike at a
meridian and a mind technique at a sea is exactly what three paths sharing one ladder was
designed to allow.

## Decision

**A hit's mechanism is selected per hit, from the ATTACKING TECHNIQUE's path, gated on
the attacker's ability to produce it. The slot binding is unchanged and becomes the
fallback.**

Two questions, in order, both must answer yes:

1. **Does the technique ask for this mechanism?** `TechniqueDef.path_ids()` → the one
   mechanism a path-exclusive technique names.
2. **Can this attacker produce it?** It carries the input the mechanism reads: an
   `acupoints` component for body, a `sea_of_consciousness` for mind. qi is ungated —
   its inputs are STATS, and `ElementsApi.attach` registers the element side as a stat
   PROVIDER, not a component, so there is no component to be missing.

No candidate passing → the INSTALLED mechanism (`bind_mechanisms`' rule, verbatim).
`SHARED` names no path, so it takes the installed one. A DUAL names two and takes the
first it can produce, enumerated in authored order — deterministic, and the author's
stated ordering rather than one this file invented.

**Two consequences worth naming, because both are traps.**

*The gate reads COMPONENTS, not the currently-bound mechanism.* Gating on
`MechanismSlot.peek(attacker)` is a tautology that reads like a working guard: the
player's bound mechanism is qi precisely BECAUSE it carries both other sets, so "is my
bound mechanism `BodyDamage`?" answers no on every player actor and the rule rejects body
for exactly the actors it exists to enable. The component is the fact; the slot is a
cache of a decision made elsewhere.

*Selection is strictly a WIDENING.* Every actor that resolved before still resolves the
same way: an actor lacking the inputs falls back to the installed mechanism. No
reachable hit is lost.

**Mechanism selection and context construction are ONE answer.** `QiDamage.builder` is
meaningless under `BodyDamage`, so the `ctx_builder` is chosen from the same selection
that chose the mechanism; the two cannot drift because there is only one rule.

## Consequences

- **The spine is untouched.** It has no "unless the caller says otherwise" parameter, and
  it must not: such a parameter would put a per-path concept into the one file in the
  module that may never name one. `CombatBoot.resolve_hit` binds the selected mechanism
  to the attacker for the duration of the call and restores the previous one on every
  return path — including the throwing one, so a mechanism cannot leave an attacker bound
  to a body mechanism it was not built with.
- **`CombatSpine.resolve_hit`'s `ctx_builder` stops defaulting to empty in production.**
  `ItemWorkbenchApp._resolve_technique_hit` passes `CombatBoot.ctx_builder_for(...)`, so
  `element_share`, `aim_meridian` and the elements rule table finally reach `ctx.data`.
  Every authored `element_share` (0.1–1.0 across the `.tres`) stops reading
  `default_element_share` and starts being the number the author wrote.
- **`CombatBoot.has_attack_resolver` is corrected.** It read
  `is_null() or is_valid()`, which is `true` in every case, so `PlayerAdapter.attack`'s
  only gate was open and `strike`'s refusal was unreachable. One conjunct fixes both.
- **A dual-path technique now behaves differently from before, deliberately.** Its two
  paths map to two mechanisms where they previously both meant qi. That is the point.
- **A pathless `SHARED` technique is unchanged** — it takes the installed mechanism,
  which is the qi fallback, so all six `shared_*.tres` behave exactly as they did.
- **The three mechanisms' arithmetic is untouched.** This is a wiring ADR; every number
  in `qi_damage.gd`, `body_damage.gd` and `mind_damage.gd` is unchanged.