# 0089 Statuses tick from the composition root and stay session-only

- Status: Proposed
- Date: 2026-10-03

## Context

Two measured facts make this system theatre today:

- **`Actor.tick_statuses` has no production caller.** Its only call sites are
  `tests/core/test_actor_statuses.gd:18,26`. Nothing in `game/src` calls it.
- **`Actor.to_dict()` emits no `statuses` key** (`core/actor.gd:268-292`,
  `SCHEMA_VERSION := 4` at `:17`). Every status is session-only, and DEF-0059 records
  that the shipped save persists items only anyway.

So no DoT can tick, no status can expire, and nothing survives a load — while ADR 0075
has already made `StatusEffect` load-bearing for environment and ADR 0071 requires a
`mind_deviation` status. **A status system nobody can tick is decoration.** Three
adjacent facts constrain the answer: `InputHandler.tick(delta)` is the only per-frame
driver and it calls `_skill_system.tick` (`app/input_handler.gd:120-125`); ADR 0056
forbids a stateful system in `app/`; and `APP_STATE_MARKERS`
(`tools/arch/rules.py:147-154`) makes exactly that a gateable violation.

`core/actor.gd` is 398 lines against a 400 budget (`rules.py:115`) — a warning, not a
gate — and ADR 0027 already sets the precedent for keeping module state in
`actor.module_data`.

## Decision

**The tick caller is the combat-engine module's facade, wired from `app/`. Statuses
stay session-only; no schema bump yet.**

- `CombatEngine`'s facade owns `tick_statuses(actor, delta)`. It calls
  `Actor.tick_statuses` and, for each surviving status, applies its tick channel
  (DoT damage, amplifier reads). `app/` calls it once per frame — from the same
  `InputHandler.tick` that already drives the frame
  (`app/input_handler.gd:120-125`) — so the loop has exactly one caller and no second
  clock. `app/` wires; the module owns the rules (ADR 0056).
- **Persistence: session-only. `SCHEMA_VERSION` stays 4.** Not `module_data`, not a v5
  slot. A status written into a payload is a designer retune silently rewriting an old
  save, which is the exact failure ADR 0056 rejected when it chose "persist ids, not
  definitions" — and unlike item state, statuses have **no** def id to rehydrate from,
  because the catalogue is authored data that does not exist yet.
- **This is a `Proposed` interim, and the trigger to revisit is written down:** when the
  catalogue ships (ADR 0090) *and* a cultivation outcome can read a status across a
  save — a burn that damages a dantian, a blessing that persists — persistence becomes
  a schema decision with its own ADR and `SCHEMA_VERSION 4 -> 5`, mirroring ADR 0070's
  wound precedent. Until then a status is a fight-scoped fact and losing it on load is
  correct.
- **Purge:** COMBAT-scope statuses are cleared on combat exit, by the same caller that
  ticks them. CULTIVATION-scope statuses are never purged by combat state.
- A status's stat effect is computed **once at apply time** and held as `StatModifier`s;
  ticking never adds or removes one. On expiry the owning source tag
  (`status:<id>`) is removed in full — the `SocketEffects.apply` shape
  (`modules/socket/socket_effects.gd:39-48`), remove-before-add, so a rebuild cannot
  accumulate drift.

## Consequences

- The DoT channel and ADR 0075's environment hazard have the caller they both need, and
  the "no production caller" finding that has now recurred five times
  (`attach_shield`, `ElementsApi.attach`, `tick_statuses`, `path_def`, `PlayerAdapter.attack`)
  stops recurring for this one.
- `CombatApi` is AT or OVER the 12-method facade cap (`rules.py:112`): it exposes 13
  public methods today and `tools arch` already fails on it. **`tick_statuses` therefore
  belongs to `CombatEngine` (the spine module), not to `CombatApi`**, or it displaces an
  existing verb. This ADR does not fix the over-cap facade — that is another agent's
  in-flight change — but it must not be made worse by a fourteenth.
- A session-only status is untestable across a save, and that is accepted rather than
  hidden. `tools arch` and `tools test` stay green either way, which is why the
  definition of done here is a **production caller**, not a test.
- `Actor.to_dict()` is untouched, so `core/actor.gd` does not grow and the 398-line
  budget is not moved for this feature.
