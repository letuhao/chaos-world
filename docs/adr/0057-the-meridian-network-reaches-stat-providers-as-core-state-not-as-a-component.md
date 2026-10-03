# 0057 The meridian network reaches stat providers as core state, not as a component

- Status: Accepted
- Date: 2026-10-03
- Supersedes: nothing. Closes BL-0118 and BL-0133.

## Context

`Actor.meridians` is a plain field (`core/actor.gd`), created in `_init` and replaced on
load. But all three cultivation providers read the network the same way:

```gdscript
var network := context.component(&"meridians")
```

which looks the network up in the **module component** bag. Only the qi facade ever wrote
that slot (`qi_cultivation/api.gd:19`), and `QiCultivationApi` had no callers in `src/`. So
for a body-only or mind-only actor — which is what the game actually builds — the lookup
returned `null` and `_meridian_power_bonus` returned `0.0` unconditionally.

The consequence was not a crash but silence: meridian state, refinement depth, and all
twelve resonance ranks (ADR 0034) contributed **nothing** to any stat. A player spent sixteen
channel elixirs per realm to train channels and bought no attack, defense, poise, speed,
capacity, regeneration, or body power. Only `get_flow_bonus()` survived, because
`BodyTraining.cultivate` reads `actor.meridians` directly off the field.

A second defect sat alongside it: `Actor._init` connected the `changed` signals of `traits`,
`affinities`, and resources to the stats invalidator, but never `meridians`. The connect
existed only in `from_dict`, so on a normally constructed actor `MeridianNetwork._emit_changed`
invalidated nothing. It was masked because `BodyTraining.strengthen` and `cultivate` both
end in `mark_stats_dirty` — it would have bitten the first meridian mutation that did not.

## Decision

- **`StatContext` carries the network.** A new untyped `meridians: RefCounted` field plus a
  `meridian_network()` accessor. It is untyped on purpose: `MeridianNetwork` lives in
  `core/`, and `contracts/` must never depend upward on it. Every other type `StatContext`
  names (`ResourcePool`, `NameList`, `AffinityMap`, `PathState`) lives in `contracts/`; this one
  cannot, so providers cast it themselves.
- **`Actor._init` supplies it and connects the signal**, alongside `traits` and `affinities`.
  One place creates the network, one place invalidates on it changing.
- **`from_dict` re-points the context.** The restored network *replaces* the one `_init` built,
  so leaving the context holding the discarded object would have been a new instance of the
  same class of bug.
- **No module registers `meridians` as a component.** The qi facade's copy at `api.gd:19` is
  deleted; a second, divergent source of truth for core state is exactly what this removes.

## Consequences

- Meridian training, refinement and resonance now pay out, on every path, for every actor.
- A provider that wants a network reads `context.meridian_network()`; reading
  `component(&"meridians")` is now unambiguously wrong and returns null.
- `contracts/` gained a field. It is a handle, not a behaviour, so the type stays loose and
  the dependency direction stays clean.
- `game/tests/modules/body_cultivation/test_body_provider.gd` gained the end-to-end proof the
  audit found missing: an actor built through `ActorFactory.with_body_cultivation`, where a
  strengthened channel measurably moves a stat. That test fails against the old code.
- `test_meridian_network.gd` covers the invalidation contract: mutating the network on a
  normally constructed actor marks the actor's stats dirty.