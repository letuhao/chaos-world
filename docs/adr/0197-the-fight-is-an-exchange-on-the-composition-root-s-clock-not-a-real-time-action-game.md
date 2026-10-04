# 0197 The fight is an EXCHANGE on the composition root's clock, not a real-time action game

- Status: Accepted
- Date: 2026-10-04

## Context

The engine is complete and reachable, and a player still cannot FIGHT: the only place
combat happens is `combat_readout.tscn`, a debug readout that fires one blow at a
stationary drill body. `CombatBoot.strike` (one bare swing), `CombatBoot.resolve_hit`
(technique hits), `StatusLoop.tick` (the combat tick) and `LootApi` (the encounter run)
all exist and all have production callers. What does not exist is a FIGHT: two sides,
alternating, with a winner and a loser and a record of it.

**The shape is already decided by the systems, not open.** Three things pin it:

- `CombatExchange.exchange` (ADR 0076) is one TURN: the player's blow, then the boss's
  answer, in one call, resolved from both sides' own numbers. It is press-driven and has
  no turn counter (`exchange.gd:111`). ADR 0126 settled that combat is "a headless
  exchange over the existing share model and the spatial layer does not block it".
- `StatusLoop` (ADR 0106/0089) is the ONE clock. `tests/app/test_status_clock.gd`
  asserts the exact set of frame drivers in `res://src` is
  `[item_workbench_app.gd, nav_probe.gd, player_adapter.gd]` — so a new per-frame driver
  is not available without editing a deliberate allowlist.
- ADR 0173 removed real-time clocks from the WORLD, leaving a "turn tier": combat decay,
  statuses and technique upkeep are measured in real seconds handed down by the frame.

**The design docs describe a 2D action game that was never built.** BL-0023 ("2D Godot
adapter for Actor", DEF-0010) is still `todo`, and `input_handler.gd`, `skill_system.gd`
and `consumable_system.gd` — the files `docs/world/input-skill-system-design.md`
documents in detail — **do not exist on disk** (ADR 0056 deleted the prototype).
`PlayerAdapter` DOES exist (`game/src/app/player_adapter.gd`, a `CharacterBody2D`) and is
mounted by `WorldStage`, `DomainWorld.place_player` and `CharacterCreationProgram`, but no
`.tscn` mounts it as the playable slice and `PlayerAdapter.attack` is exercised only by
tests. So the design doc describes a program half-deleted and half-built; the live game is
a screen stack.

**The owner's ruling is about LENGTH, not about a control scheme.** The anchor: two
same-power actors, no heal, no dodge, resolve in 60 s; offence shortens it, defence/heal/
shield lengthen it; `Stat.ATTACK_SPEED` (1.0 baseline, 2.5 cap) is the blow-rate lever.
That is a statement about *how many blows a pool survives*, and it is satisfiable by any
loop that spends a bounded number of blows.

## Decision

**The loop is a turn-based EXCHANGE driven by the composition root, and both sides
resolve through `CombatSpine`.**

1. **One exchange = one call, alternating.** The existing `CombatExchange.exchange` shape
   is kept verbatim: the player's blow, the boss's answer, one verdict. No new turn
   system, no initiative queue, no round counter.

2. **The clock is the frame `StatusLoop` already owns**, handed down as `delta`. Nothing
   new ticks. A blow is *available* when the attacker's `attack_speed` says it is; the
   availability is a gate on the PRESS, not a background timer, so a fight advances only
   while the player acts — the same rule ADR 0167/0173 gave every other action.

3. **The enemy is a real `Actor`**, minted by `ActorFactory` and resolved by the same
   `CombatBoot.resolve_hit` a player blow uses. A boss therefore wounds at a meridian,
   erodes a sea and takes statuses exactly as a hero does, and a wound ledger accumulates
   across a fight rather than being reset per press.

4. **The outcome is written where a duel is already written**: `CombatDuel`'s win/defeat
   ledger and the ADR 0089 combat-exit purge. A fight that ends is a fight that purges.

5. **`Stat.ATTACK_SPEED` is the only rate lever.** No new duration constant. Offence
   shortens the fight because a faster rate spends the same pool in fewer blows; defence,
   heal and shield lengthen it because they enlarge the pool or reduce each blow. This is
   the anchor's arithmetic falling out of the existing ladder — `hits_to_kill` is already
   ~25 at every realm — with no new number invented.

## Consequences

- **A player can fight, win, lose, and see it persist**, using only composed seams.
- **The debug readout is not the fight any more**; it stays as the per-stage view.
- **No 2D action layer is built.** `PlayerAdapter` keeps its `_physics_process` and its
  spatial affordances, but the loop does not depend on positioning, dodging or a frame
  rate, so a headless probe drives a whole fight with a verb list.
- **A boss's vitality must scale with its realm** for a same-realm boss to land near the
  anchor's ~25 blows. That is the owner's ruling applied to content and is **not** this
  ADR's change: authored `LootTier.vitality` is content, another lane owns the retune, and
  nothing here writes a `.tres`.
- **This ADR does NOT reverse ADR 0123/0126.** The share model keeps resolving
  `CombatApi.exchange` for authored bosses; the spine resolves the actor-facing blows.
  The fight loop is the place both are reachable from, which is what makes the split
  legible rather than hidden.
- **`combat/` and `combat_engine/` arithmetic is untouched.** This change adds wiring in
  `app/` and one screen in `ui/`, and reads module facades only.