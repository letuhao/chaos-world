# A commit must never reinforce the anchor it creates

`WorldAnchor._commit_inside_world` called `strengthen_anchor()`. Removed.

## Why it was wrong

`MindAnchor._inside_ok` requires `anchor_strengthened`, and
`MindTraining.strengthen_anchor` is the only other route to it — it is a paid resonance
milestone. The commit was stamping the one flag the *next* realm's gate demands.

`Breakthrough.try_advance` calls `WorldAnchor.commit` for every path
(`core/breakthrough.gd:56`). So on the Mind path the chain was:

```
Breakthrough.try_advance
  WorldAnchor.commit(actor, 18)
    _commit_inside_world -> strengthen_anchor()      # the flag
  MindAnchor.commit(actor, 18)                        # creates, trialls, never reinforces
```

`MindAnchor.stage_met` then read **open** with the milestone never paid. The anchor
tiers were decorative: a player could walk R19-R30 without ever reinforcing an anchor.

`MindAnchor`'s own commit was written correctly and says so — *"it never REINFORCES it,
which is the one clause of a demanded stage the commit cannot satisfy"* — and the tier
tests exercised `MindAnchor.commit` **directly**, bypassing the production chain. The
suite was green against a function the player never reaches.

## The rule

A commit creates, trialls and stabilises. It never reinforces. Reinforcement is a
separately paid action, because it is exactly what the next gate asks for.

Nothing outside `mind_cultivation` reads the flag: core's own `_inside_met` checks the
law and the stability, not the anchor. So this costs body and qi nothing.

## What it costs

Two suites encoded the old behaviour and now fail honestly: `test_high_tier_traversal`
asserted the gate was already met with nothing paid, and the Mind traversal never stocks
the realm's `training_item`, so it cannot pay the milestone. Both need a Mind-aware
fixture. That work is not done.