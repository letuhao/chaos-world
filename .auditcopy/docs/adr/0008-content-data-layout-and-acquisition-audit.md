# 0008 Content data layout and acquisition audit

- Status: Accepted
- Date: 2026-10-01

## Context

Items (especially breakthrough items) are obtained through chains: crafted from materials, dropped by bosses, rewarded by domains. Gaps — an item with no source, a boss with no domain, a recipe missing a material — are easy to miss and only surface late. Content must be auditable before the systems that consume it exist.

## Decision

- Content lives under `game/data/` as `.tres` resources:
  - `data/items/<category>/` — material, consumable, equipment, technique, quest, key, currency, misc.
  - `data/recipes/`, `data/bosses/`, `data/domains/`, `data/species/`, `data/traits/`, `data/elements/`, `data/cultivation_paths/`.
- Acquisition model: `ItemDef.sources: Array[StringName]`, entries `"<type>:<ref>"` where type is one of `craft`, `boss`, `domain`, `gather`, `quest`, `vendor`, `drop`, `starter`. `gather`/`starter` are base sources (no ref); the rest reference a content id.
- Reference fields: `RecipeDef.inputs`/`outputs`, `BossDef.domain_id`/`loot`, `DomainDef.boss_ids`.
- `tools data audit` parses `.tres` under the data root (no Godot runtime) and checks the dependency layers:
  - undefined references (recipe/boss/domain/material ids),
  - unobtainable items (no sources),
  - recipe cycles,
  - bosses without domains and domains without bosses,
  - inconsistent links (an item claims a boss/recipe that does not list it).
- `tools data audit` runs inside `tools check`, so content gaps fail the gate; `tools data report` lists content.

## Consequences

- Content is validated before, and without, the systems that consume it.
- Breakthrough items must have a reachable acquisition path.
- New content types extend the schema in `tools/data`; `RecipeDef` lives in `items`, `BossDef`/`DomainDef` in `world`.
