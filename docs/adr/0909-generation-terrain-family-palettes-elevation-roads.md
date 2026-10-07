# 0909 Generation passes: terrain family and the layer fold (slice 4a)

- Status: Accepted
- Date: 2026-10-07

## Context

Four passes could not cover the plan's generation list, and every new layer
threatened a chunk-shape migration. Slice 4a lays the terrain family and
the rule that keeps later slices migration-free.

## Decision

- Terrain reads a `palette` ctx list (default base ground alone: old chunks
  regenerate byte-identically); missing art is skipped, never holed.
- Elevation is pure data (`layers["elevation"]`, 0-2, patchy 3x3 blocks):
  nothing blocks on height. Cliffs are 4b's to place, reading this layer.
- Roads carve `packed_trail` bands (ctx `roads`, default 0), skipping water
  and height-2 cells; the stream gap is a ford/bridge 4b's structures span.
- The pipeline folds: `terrain`/`props`/`walkable` stay first-class and every
  other returned layer lands in `chunk.layers` under its own name. Passes
  return top-level either way; later passes read custom layers from
  `chunk["layers"]` (contract pinned).
- Registration order in `default_generator` follows `requires()` chains
  (roads last among terrain writers).

## Consequences

- 4b/4c add passes without touching generator/chunk/contract.
- What this ADR does NOT do: road-water crossings, height blocking, or the
  template registry (4b/4c).
