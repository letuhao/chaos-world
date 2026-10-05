# 0074 Every inhabitant of a domain is an Actor built by one constructor

- Status: Accepted
- Date: 2026-10-03

## Context

The governing constraint of this program: **this game has `Actor` as the base for every pc, npc and mob.** A monster, a mini-boss, a boss, a rival cultivator and the player are the same thing at different magnitudes.

That premise is already structurally free — `Actor` is `RefCounted`, one shape, and every module extends it by composition rather than inheritance. What does not exist is any way to *make* one. Four `Actor.new` sites exist in `game/src`: `actor_factory.gd:9` (the player), `actor.gd:302` (deserialization), `player_adapter.gd:251` (the player again), and `fertility/api.gd:115` (one offspring). **There is no NPC, mob, miniboss, boss or rival-cultivator constructor anywhere** (BL-0216). `ActorFactory` exposes `build`, `with_dual_cultivation`, `with_fertility`, `with_body_cultivation` — four entry points, all player-shaped.

The risk this ADR closes is a parallel hierarchy: `MobActor extends Actor`, `NpcActor extends Actor`, each with its own stats block, its own save path, and a combat spine that has to know about all of them.

## Decision

**One constructor mints every inhabitant. A role is a tag, not a class.**

- `ActorFactory.spawn(inhabitant_ref: InhabitantDef, role: StringName) -> Actor`. `role ∈ {mob, miniboss, boss, npc, rival_cultivator}`. The returned value is always an `Actor`; there is no second type to downcast.
- **A role is a `StringName` on `Actor.tags`,** read by content, never branched on in a mechanism. The one forbidden pattern is `if role == "boss"` inside damage resolution — same rule as ADR 0067's no-`if/else`-on-`path_id` invariant, for the same reason: three mechanisms that each branch on role are three mechanisms that disagree.
- **Stats come from the shared actor model.** `RealmScaling` (ADR 0050) scales a realm's power; an inhabitant's magnitude is authored on its own def and applied once. A mini-boss is not a different stat pipeline — it is a bigger number plus a tier tag.
- **Every inhabitant persists through the same `Actor.to_dict()`/`from_dict` path** (ADR 0027). No inhabitant gets a bespoke save field; anything that does is a bug.
- **Rival cultivators are the same shape as the player.** An NPC that cultivates enrols a `PathState` and gets the same providers; it is not a special "questgiver" class with a reduced stat block.
- The contract is a test, not a comment: one suite asserts every role yields an `Actor`, that no inhabitant class exists outside `Actor`, and that a spawned inhabitant round-trips through `to_dict()`.

## Consequences

- The user's premise becomes true in code rather than intent: one base class for pc, npc and mob, by construction (BL-0216).
- The combat spine (ADR 0067, BL-0209) resolves damage against whatever `Actor` it is handed; a mob and the player take the identical code path, so a new creature type costs a def, not a code change.
- Population becomes data: a room's `actor_spawn_refs` name `InhabitantDef`s, and the resolver mints Actors for them (BL-0217). AC2 and AC3 are then tests of the factory, not of each creature.
- **Cost this ADR accepts:** a mini-boss and a mob differ by numbers and tags, so any mechanic that wants genuinely different *behaviour* by tier needs an extension point rather than a role branch. That is the correct place for the cost to land — a component, not a subclass.
