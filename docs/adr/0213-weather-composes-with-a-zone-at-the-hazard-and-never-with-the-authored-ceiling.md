# 0213 Weather composes with a zone at the hazard and never with the authored ceiling

- Status: Accepted
- Date: 2026-10-05
- Closes: BL-0841
- Depends on: ADR 0075 (accepted), ADR 0210, ADR 0211

## Context

The resolution is correct and unreachable. `DomainMap.effective_intensity` exists and works:
authored band + a one-directional shift, clamped to the authored ladder
(`domain_map.gd:237-242`). But nothing that *spends* reads it.

- `EnvironmentField.apply` calls `zone.magnitude()` (`environment_field.gd:637-657` →
  `environment_zone_def.gd:102-106`), and `magnitude()` reads `resolved_intensity()`
  — the **authored** band. The map is not in scope: `apply`'s signature is
  `(actor, zone, path_id)` and has no `DomainMap`, so the effective band is structurally
  unreachable from it.
- The measured result: calm `0.700000` == weathered `0.700000` with an effective band of 3
  against an authored band of 2 — `super_hot` row `[0.35, 0.70, 1.40]`
  (`environment_zone_def.gd:55`). The whole weather system is a label on the minimap.
- The only readers of the effective band are `DomainMap.zones()` (`domain_map.gd:259`),
  `DomainMinimap._zones` (`domain_minimap.gd:182-201`) and the explore model's weather line
  (`domain_explore_model.gd:150`) — all read model, none gameplay.

A second, quieter problem hides behind it. `weather_shift_for` is **+1 or 0 and never −1**
(`domain_map.gd:212-220`), despite its docblock promising `-1, 0 or +1`. The docblock is
stale; the code is one-directional. That is the correct behaviour (a player may have routed
around a hazard on the promise it was authored at band 2) but it is not what the prose says,
and the prose is what an agent reads.

## Decision

**Weather composes DOWNWARD onto the hazard, at the hazard's own resolution point, and it
never touches the authored ladder.**

- **Composition, not override.** The effective band is `zone.intensity + weather.shift`, clamped
  to `EnvironmentZoneDef.BANDS`. The authored value stays exactly as authored — that is what
  makes "this room was authored at band 2" a fact a player can be told and a designer can
  revert. A weather that *replaced* the band would make the authoring meaningless and the
  minimap's `authored_intensity` a lie.
- **Element-keyed, one-directional, ±1 band. Kept exactly as built** (`domain_map.gd:202-242`):
  the weather carries an element (`domain_map.gd:52-59`), it moves only a zone that authors
  that element in its own `tags`, it only ever moves **up**, and never more than one band. A
  `verdant` room is not heated by dry weather, and an authored annihilation cannot be exceeded.
  **The docblock's `−1` is deleted** — the code is right and the prose is wrong.
- **The seam is the hazard's magnitude read, not `apply`'s signature.** `apply` gains no
  parameter. The effective band is resolved where the band is consumed — one function reads
  "what band is this zone at, right now" — so `apply`, the minimap and any future reader cannot
  disagree. Three readers of one number is the whole defect BL-0841 names.
- **Granularity: the zone, never the tile and never the room.** A zone is the smallest authored
  hazard volume (`environment_zone_def.gd:90`), the weather shifts the zone, and two zones in
  one room may move independently. Weather that moved per-tile would be a second spatial system
  for no authored content.
- **Weather never applies a status, never invents a zone, and never touches mitigation.** Kept
  as decided (`domain_map.gd:49-51`): it re-weights one band and stops. A weather that granted
  its own hazard would be a global flag, which is precisely what ADR 0075's "zones are volumes,
  not globals" forbids.
- **`WEATHER_NONE` means no bias, not weak bias** (`domain_map.gd:61-63`, `:198-199`): an
  unknown weather id is refused by name rather than read as calm, so a typo cannot delete a
  mechanic while appearing to work.

## Consequences

- **A storm domain's furnace actually gets worse.** The read model and the hazard will agree,
  which is what lets a player make a real decision: *is this band-2 authored room safe enough
  to cross, or is the weather making it a band-3 room today?*
- **The authored ladder remains the balance ceiling.** Weather can only ever move a hazard to
  the band the designer already admitted exists, so the number of authored bands stays three
  and the content audit stays a three-value check.
- **`domain_map.gd:204` docblock is corrected** as part of the change — one line, and it is a
  `-1` claim that is false in code.
- **Weather is compositional, not adversarial.** Two weathers cannot stack, and a room cannot be
  made worse by weather than its own authored band allows. If a domain ever needs a *second*
  weather layer (a tide, a season), it is a new closed vocabulary beside `WEATHERS` and its own
  ADR — never a second term added to this shift.