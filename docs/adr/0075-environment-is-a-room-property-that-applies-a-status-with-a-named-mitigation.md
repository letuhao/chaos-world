# 0075 Environment is a room property that applies a status with a named mitigation

- Status: Accepted
- Date: 2026-10-03

## Context

A domain has severe environments: super-hot, super-cold, a static-charged world, toxic, and more. Today **none of it exists** — measured zero occurrences of `weather`, `temperature`, `hazard`, `qi_density` (as a place), or `spawn_table` anywhere in `game/src` or `game/data`; every "treasure" hit is an item-id prefix. `WorldLocationDef` carries `danger_level: int` — a number, not a hazard. BL-0063 ("Spiritual environment and Qi density") has no foothold at all.

The mechanic already exists to hang this on: `StatusEffect` (ADR 0002) is modelled, and `Actor.add_status` / `tick_statuses(delta)` (`actor.gd:133,146`) are live.

The design risk is the one the whole setting invites: an environment that becomes a flat damage tax, mitigated by a generic "resistance" affix, detaching the hazard from the cultivation fantasy it is supposed to dramatize.

## Decision

**An environment zone is a room or corridor property that applies a `StatusEffect`, and every hazard names the lever that reduces it.**

- `EnvironmentZoneDef` = `zone_id`, `kind` (super_hot, super_cold, static, toxic, void, …), `intensity`, `tags`, `mitigation_tags`. It is a room fixture (ADR 0073), so it uses the same `Area2D` realization as every other fixture and the same authoring surface.
- **A zone applies a status, it does not subtract directly.** Damage-over-time rides `StatusEffect` through `Actor.tick_statuses`, so every hazard obeys the same duration, stacking and cleanse rules as every other status. `super_hot` is a burn status whose intensity is the zone's, not a bespoke `health -= f(x)` at some call site.
- **Every hazard must publish `mitigation_tags`** — the levers that reduce it. A zone with an empty `mitigation_tags` is an authoring error the audit rejects, not a free tax.
- **Mitigation is drawn from the existing four levers, and they are genuinely different:** a gear affix (items), a technique (techniques module), a consumable pill (items/consumable), or **spirit-root affinity** (race). The last is the load-bearing one — a fire-rooted cultivator is comfortable in a super-hot zone, a frost-rooted one is not — which is what keeps the hazard inside the cultivation fiction instead of beside it.
- **Zones are volumes, not globals.** Super-heat is a region of a room you route around or prepare for; it is not a weather flag that applies to the whole domain. Weather is a *domain-level* property that biases which zones are active — never a replacement for them.
- **Telegraph before damage.** A zone's boundary is visible and a status's application is announced, so an actor crossing into it can retreat. A hazard that cannot be seen before it hurts is a trap (ADR 0073 fixtures), not an environment.
- **The test is the contract:** a hot zone measurably damages an actor with no mitigation and measurably less with one, headless, and the mitigation lever is named by the def rather than inferred.

## Consequences

- The severe-environment requirement lands on `StatusEffect`, an existing mechanism, rather than a parallel damage channel (BL-0218).
- Spirit-root affinity becomes a *playable* mitigation, which is the first consumer giving `race` a reason to matter in traversal rather than only in character creation.
- The audit gains a rule that is enforceable from code as authored: a zone def with empty `mitigation_tags` fails `tools data audit`. This is the shape the repo already prefers — a rule that hard-fails, not a warning nobody reads.
- **Deliberately not decided here:** whether environment modifies cultivation *gain* (a qi-density multiplier, BL-0063) as opposed to only survival. The mechanic is the same; the balance surface is not, and that belongs with the ladder work, not here.
