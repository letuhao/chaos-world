# 0045 World content data model

- Status: Accepted
- Date: 2026-10-02

## Context

World Creation (ADR 0019) defines the Transcendent-tier system but leaves world content — tiers, laws, factions, locations, inhabitants — as untyped `Dictionary` data. The game needs data-driven content definitions so authors can add world content without code changes.

## Decision

- Five Resource classes in `game/src/modules/world/`:
  - `WorldTierDef` — tier_id, display_name, realm_min, realm_max, law_slots, available_life_forms, upkeep_rate_min/max, time_flow_min/max, size_min/max
  - `WorldLawDef` — law_id, display_name, group, value_min, value_max, description, tier_ids
  - `WorldFactionDef` — faction_id, display_name, dao_alignment, home_tier, philosophy, relationships
  - `WorldLocationDef` — location_id, display_name, tier, faction_id, resources, inhabitant_types, danger_level
  - `WorldInhabitantDef` — inhabitant_id, display_name, type, tier_ids, loyalty_min/max, combat_power_min/max
- All IDs are `StringName`; all ranges are min/max pairs; all cross-references use StringName IDs (no nested Resources).
- Content lives under `game/data/world/` as `.tres` files: `tiers/`, `laws/`, `factions/`, `locations/`, `inhabitants/`.
- `WorldFactionDef.relationships` is `Array[Dictionary]` with `faction_id` and `stance` keys.

## Consequences

- World content is data-driven: adding a tier, law, faction, location, or inhabitant is authoring a `.tres`, not code.
- `tools data audit` can validate cross-references (location → tier, faction → tier, inhabitant → tier).
- The 5 Resource classes follow the existing `DomainDef`/`BossDef` pattern.
