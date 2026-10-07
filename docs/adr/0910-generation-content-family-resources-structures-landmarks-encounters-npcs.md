# 0910 Generation passes: content family (slice 4b)

- Status: Accepted
- Date: 2026-10-07

## Context

The terrain family (ADR 0909) lays ground; nothing lives on it. The plan
names resources, settlements, structures, landmarks, encounters and NPC
markers — all content that must coexist on one chunk without eating each
other's placements or outrunning collision.

## Decision

- `resources`: harvestables with `yield` payloads (`{kind: amount}`,
  ints only), blocking per entry. `structures`: counted placements with
  clearance + `settlements` plot-groups that land whole or not at all
  (caps 6 / 2 per chunk). `landmarks`: at most one POI per chunk, visible
  prop + `layers["landmark"]`; entrances set `suggests_edge` but build no
  edge — graph wiring stays authored. `encounters`/`npc_spawns`: data-only
  layers, never rendered, never blocking; NPCs gather at settlement
  doorsteps, roles without structures mark nothing.
- `props` concatenates across writers in the pipeline (order-independent);
  clearance readers chain `requires()` (scatter → resources → structures →
  landmarks). Collision requires every props writer and stays last.
- Shared math lives in `WorldmapPlacement` (fits, overlap, open ground,
  taken cells): one answer, no drifting copies.
- Everything defaults off/empty: old configs generate byte-identically.

## Consequences

- Harvest, building and spawn systems read props/layers; they were absent,
  so no caller changes.
- What this ADR does NOT do: bridges over road gaps, the template registry,
  navigation regions, or the metadata summary (4c).
