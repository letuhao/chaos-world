# 0911 Generation passes: navigation, metadata, template registry (slice 4c)

- Status: Accepted
- Date: 2026-10-07

## Context

Content without an index forces every consumer to re-walk every layer, and
config without validation fails mid-chunk. Slice 4c closes the plan's
generation list: navigation regions, a metadata summary, and reusable
templates.

## Decision

- `navigation` flood-fills connected walkable regions (index pointer, never
  `pop_front`; visited set bounds by cell count). Regions are coarse:
  post-generation mutations can re-split, so exact answers stay with
  `standable`.
- `metadata` requires everything it summarizes and nothing requires it; POIs
  collect landmark/encounter/npc/structure entries as primitives at one
  address.
- `WorldmapTemplates` registers biome/settlement/road/chunk/region dicts
  with refusing validators; `chunk_config` expands biome + template +
  overrides (later wins). One seeded greenwood biome proves the registry;
  content packs register without code change.
- Collision stays last WRITER; navigation/metadata are readers-after.

## Consequences

- The plan's generation list is complete: terrain, water, elevation,
  scatter, resources, structures, landmarks, roads, encounters, NPCs,
  collision, navigation, metadata — plus five template kinds.
- What this ADR does NOT do: road-water crossings, height blocking, or
  persisting template choice per save (configs ride the caller, not the
  envelope).
