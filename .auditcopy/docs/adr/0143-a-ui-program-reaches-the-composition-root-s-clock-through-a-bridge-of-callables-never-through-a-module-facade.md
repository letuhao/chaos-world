# A UI program reaches the composition root's clock through a bridge of callables

Completes the ADR 0114 chain's player-facing half. Touches no `core/` or `contracts/`
behaviour, so it ships with no companion change.

## Status

Accepted.

## Context

`WorldPulse` owns the world's period tick. `advance_one_period()` and `world_summary()`
existed on the composition root and had **zero callers**, so a player could not advance the
world, see the world's news, or observe that time had passed. The tick ran and nothing read
it.

The obvious repair — let a screen call `EventApi.advance` — is wrong twice over.

## Decision

`ui/` reaches the clock as **two plain callables on a bridge**, built by the composition
root, exactly as `LootBridge` already does for the loot program.

This is forced rather than chosen, and the forcing is the point:

- `app` is a `PRIVATE_UNITS` entry (`tools/arch/rules.py`), so no screen may reference it.
- `event` is **not** in `rules.UI_MODULES`, so no screen may name `EventApi`.
- `ScreenRoutes` — the only "a player can reach this" table — lives in `app/`.

So the bridge is the only legal seam that exists. Two consequences follow and both are
recorded because each is a trap:

**A screen must not call `EventApi.advance`.** That would make a *second* dispatcher for one
moment: it would skip the ambient news, the one-open-per-pull budget and the institution
settling that `WorldPulse.pull` owns. The pulse is the only thing that may decide what a
period means.

**A screen must not be handed the clock's numbers.** `WorldPulse.PERIOD_SECONDS` and
`PERIOD_FACT` are `app/`'s and unreachable from `ui/`. A panel that restated them would be a
second copy of a rate — the exact failure `tests/core/test_realm_rate.gd` exists to catch in
GDScript, and which no rule catches in a panel. The clock arrives through the bridge or it
does not arrive; a screen with an unfilled bridge names the missing seam rather than
showing zeros.

## Consequences

- **The surface is a panel on the already-routed World route**, not a new screen. A new
  screen needs a `ScreenRoutes` entry, a `nav_route_*` action in `project.godot` and a
  binding arm — and `test_ui_conventions.gd` fails any shipped screen with no route.
- **Rejected: duck-typing up to the root.** Walking the tree to find an
  `advance_one_period` method would be invisible to the architecture checker and would break
  on any shell refactor. An instrument that cannot see its own violation is not an
  instrument; this repo has been bitten by that shape repeatedly.
- **Rejected: a bridge slot for `available_events`.** A seam nobody lands is a feature that
  measures as dead. Two slots, both used.
- The wiring lives in `app/item_workbench_app.gd`, which is where `ui/` is *supposed* to be
  unable to reach — that is the point of the composition root.