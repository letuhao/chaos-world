# 0913 In-game debug overlay for streaming and generation (slice 6)

- Status: Accepted
- Date: 2026-10-07

## Context

Streaming and generation were observable headlessly (`debug_summary`)
but invisible in play: borders existed behind a flag no surface set, and
the read never reached a screen.

## Decision

- `WorldmapScene.set_debug` toggles border + chunk-id painting
  (`ThemeDB.fallback_font`, no asset dependency); `debug_summary` gains
  `seed`, `passes`, chunk-local `pois` in map cells, and the domain block
  stays.
- `VentureBoot.read` trims everything to primitives (edge cells as pairs,
  ranges, simulated ids); the venture screen gains a Debug toggle button
  and a text overlay (node/seed, holders/loaded/simulated counts, ranges,
  passes, edges/POIs). Off paints nothing; unopened refuses.
- The overlay reads the same summaries the tests assert: one address for
  probes and players, never a second opinion.

## Consequences

- Debug words are player-visible but read-only: no verb hides behind them.
- What this ADR does NOT do: a minimap, region tinting, or encounter
  visualization (POI rows, not pictures).
