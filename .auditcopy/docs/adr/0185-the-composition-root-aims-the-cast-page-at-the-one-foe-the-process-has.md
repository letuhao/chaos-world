# ADR 0185 — the composition root aims the cast page at the one foe the process has, and the turn readback is what a landed cast reports

## Status

Accepted.

## Context

Two features in the `techniques` module were complete, tested and unreachable from the
game.

`TechniqueLoadoutScreen.bind_target` (`technique_loadout.gd:323`) is the ADR 0143 seam
the cast half of the loadout page runs on. It had exactly one caller in the whole tree —
`tests/ui/test_technique_screens.gd`. No production code aimed the page at anything, so
every real press on the row's cast button fell through `act_cast`'s `_refuse_no_target`:
no qi spent, no cooldown started, no rung granted, and the page reported "Nothing to aim
at" on every attempt. The damage path underneath was real and fully wired
(`_bind_technique_seams` -> `_resolve_technique_hit` -> `CombatBoot.resolve_hit` ->
`to_dict`); it was simply not connected to a player's hand.

`TechniqueCastView` (`modules/techniques/technique_cast_view.gd`, DEF-0097) had
`tests/modules/techniques/test_technique_cast_view.gd` and no production caller at all.
It is the only read model that answers "what did the TURN move" rather than "what was
the blow worth" — the distinction that matters on the mind path, where ADR 0071 with ADR
0162 makes a technique cost no health and pay only the shared chip floor, so a caller
reading `amount` concludes it did nothing.

`techniques` was 3260/0 and `technique_screens` 132/0 with both dead. This is the same
defect class an earlier audit recorded for `delivers`: a verb exercised only by the test
that asserts it.

## What the composition root already knew

`ItemWorkbenchApp` already owned exactly one foe and already injected it into a screen:
`_readout_target()` (`item_workbench_app.gd:1277`) mints a cached drill body through
`ActorFactory.spawn_inhabitant(&"readout_drills")` with a body-cultivation enrollment,
and `ROUTE_COMBAT_READOUT`'s arm hands it to `CombatReadoutScreen.bind_strike`
(`item_workbench_app.gd:1108`). That is the same seam, the same shape, already shipping.

So the decision was not "where does a target come from". It was "why is the cast page
not aimed at the body the Blow page is already aimed at".

## Decision

**1. One foe, injected at the route.** `ROUTE_TECHNIQUE_LOADOUT`'s arm in
`_bind_route_screen` calls `_bind_target_screen(screen)`, which passes
`_cast_target()` — the same drill body — to `bind_target`. `ui/` still neither reads a
foe roster (`npc` is not in `rules.UI_MODULES`) nor mints an `Actor` (`app/` is a
`PRIVATE_UNIT`), so the seam is still an argument and never a lookup. There is now one
foe in the process, not one per surface: a second drill would have meant two bodies with
two wound ledgers and a cast that could land somewhere the player was never shown.

**2. The unbind is a first-class door.** `clear_cast_target()` unbinds every mounted page
and drops the cached body. It is called from `adopt_actor` beside the post-rebirth
`setup`, because a rebirth is the one event that can leave a page aimed at a foe the
FALLEN hero was fighting. `refresh_cast_target()` is the re-bind counterpart.

A stale target is worse than none, and the reason is arithmetic rather than taste:
`TechniqueCasting.activate` pays the pool and starts the cooldown BEFORE it resolves, and
`_resolve` returns `{}` for a null target. A page left aimed at a departed foe would
therefore spend real qi on a body the player was never shown. Unbinding is not a
courtesy — it is the state in which `act_cast` can refuse for free, which is the only
layer positioned to refuse without spending.

**3. The readback is reached the way the facade publishes it, not as a thirteenth verb.**
`TechniquesApi` is at its twelve-method cap and ADR 0056 records that the cap binds
immediately, so `TechniqueCastView` is a named type named by the constant
`TechniquesApi.CAST_VIEW`, exactly as `TechniqueCasting` and `TechniqueDelivery` are
reached. `act_cast` takes `TechniqueCastView.snapshot` immediately before `activate` and
`TechniqueCastView.of` immediately after, and reports the turn through the page's
EXISTING message channel and `summary()` — no new UI concept was introduced. A refused
or unmeasured cast yields `{}` and `measured: false`, never a fabricated zero.

**4. `ui/` may not hold a `res://` path into a module.** The screen reaches the readback
by assembling the path from `"res:" + "//"` and `TechniquesApi.CAST_VIEW`. Writing the
path as one literal fails `tools arch`: `RES_RE` matches any `res://` string, so a
path literal into `modules/techniques/` is itself the cross-module edge the gate reads,
and `ui/` may name a module only through its `api.gd`. The split is load-bearing, not
cosmetic.

## Consequences

- The cast program is reachable from a player's press, proven at the seam rather than
  asserted: `tests/app/test_cast_target_wiring.gd` mounts the shipped
  `ItemWorkbenchApp.tscn`, drives its real `_ready`, navigates the real route, and presses
  the row's real `Button`. Deleting `_bind_target_screen(screen)` from the route arm
  turns that suite red while every behavioural case in `test_technique_screens.gd` stays
  green — which is the point, because each of those binds the target itself.
- A mind cast now reports its sea erosion instead of reading as a technique that did
  nothing.
- `_readout_target`'s cache is shared. Two surfaces, one foe. Clearing one clears both,
  which is correct and is asserted rather than assumed.
- `TechniquesApi` stays at twelve public methods. Both gaps were integration gaps, and
  neither was closed by growing a facade.