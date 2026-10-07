# 0908 Domain descent through the travel seam

- Status: Accepted
- Date: 2026-10-07

## Context

ADR 0904 promised a domain node "points at its `DomainMap` template" with
no code behind it. The run lives on the actor (`DomainApi`), the feet live
in the scene, and neither may name the other's owner: the scene has no actor,
`app/` owns the composition.

## Decision

- A node config naming `domain_template` (+ `domain_seed`) turns arrival
  into a DESCENT: the scene enters a real run through an app-installed seam
  (`WorldmapApi.install_domain`, same shape as the gate table), pushes the
  exact `{node, cell}` onto a return stack, and stands on the far cell with
  no chunks rendered.
- The run starts BEFORE scene state moves: a refused entry leaves the player
  where they stood. Inside, `step`/`destroy_at` refuse `inside_domain` —
  rooms are walked on the domain's own surface, which already plays.
- `return_from_domain` leaves through the seam, pops the cell, and restores
  node/config/size/seed around the UNTOUCHED streamer: the overworld was only
  unrendered, so mutations, cache and range are exactly as left.
- Above ground, return refuses `not_inside`; with no seam installed, descent
  refuses `no_domain_seam`.

## Consequences

- Descending and pressing Enter mint the same kind of run (one entry point).
- What this ADR does NOT do: render rooms inside the venture scene, nest
  descents (the stack allows it; no surface reaches it), or persist runs
  across sessions (the run is actor state; the save already carries it).
