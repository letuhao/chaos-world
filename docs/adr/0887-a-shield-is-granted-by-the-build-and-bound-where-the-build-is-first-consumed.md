# 0887 a shield is granted by the build and bound where the build is first consumed

- Status: Accepted
- Date: 2026-10-06

## Context

- ADR 0879 shipped `CombatShield` as the S9 binding of the four `SHIELD_*` ids and
  recorded the gap plainly: production bound no shield, so the gate always read an
  absent component. The audit (DEF-0347) confirmed it: `CombatShield.attach` had zero
  callers, and the aptitude matrix's vigor edges (`shield.capacity`, `shield.regen`,
  `shield.toughness`) were writing values nothing consumed.
- What GRANTS a shield was never decided. Vigor already prices one, which is the
  answer this ADR takes: the build grants it.

## Decision

- The grant rule IS the build: a resolved `shield.capacity` above `0.0` means this body
  has a pool, and `0.0` — the default every actor carries — means no shield. No content
  item, technique or status is required; the aptitude layer's vigor edges are the
  producer of record.
- `CombatShield.ensure(owner)` is the binding verb. It is idempotent, it binds FULL on
  first call, it refreshes an already-bound `CombatShield`, and it leaves any other
  component under the key UNTOUCHED — which is what keeps the duck-typed test doubles in
  `test_combat_shield_gate`/`test_combat_reflect` behaving as doubles.
- The binding happens WHERE THE BUILD IS FIRST CONSUMED, not at creation time: the spine
  calls `ensure(target)` once per resolve (so any fight sees the pool) and
  `CombatEngineApi.tick_shields(actor, delta)` ensures and refills on the frame clock.
  A created-but-unfought body that has already broken through still gains its pool at
  the next frame tick, so the composition root's loop is the creation-time wire without
  an actor needing to be hit first.
- Regen rides `app/status_loop.gd`'s `_tick_combat`, the SAME clock as the statuses,
  the wound decay and the three mind ticks (ADR 0089's one-time-wire rule: two systems
  aging on two clocks are two systems nobody can reason about). Time is the caller's;
  `CombatShield.tick(delta)` takes it, the spine still never reads regen.
- The attacker half (`SHIELD_PEN`) needed no work: the matrix's `pierce` edge already
  produces `shield.pen`, and the spine consumes it through `_absorb`'s second argument.

## Consequences

- Vigor is now a real stat from the first frame after a breakthrough that grants it: the
  pool binds, absorbs at S9, and refills on the app clock. The audit's "paid for and
  invisible" finding is closed; `DEF-0347` is `done`.
- `ensure` costs one component lookup per resolve and one capacity read on first bind —
  no draws, no state creation for an unbuilt body.
- What is still absent is CONTENT that prices capacity higher (the vigor edge's `k` sits
  in DEF-0344's placeholder family list) and a readout for the pool; neither blocks the
  mechanic being reachable.
