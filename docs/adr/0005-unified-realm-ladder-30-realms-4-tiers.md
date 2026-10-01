# 0005 Unified realm ladder (30 realms, 4 tiers)

- Status: Accepted
- Date: 2026-10-01

## Context

ADR 0003 let each cultivation path define its own ladder; ADR 0004 gave elemental mastery six ranks. The game needs one shared progression spine so every cultivation system (qi, body, soul, elemental mastery, ...) advances through the same realms.

## Decision

- One shared ladder of **30 realms in 4 tiers**: Mortal (9), Spirit (9), Immortal (9), Transcendent (3).
- `RealmDef` (Resource: id, display_name, tier, index) and `RealmLadder` (ordered lookup: `realm`, `index_of`, `tier_of`, `next`) are core types; `RealmDefaults` holds the 30 realms.
- `CultivationPathDef` no longer defines ranks; every path advances along the shared ladder, and `PathState.rank_id` is one of the 30 realm ids.
- Elemental mastery uses the shared ladder; element tier gating derives from realm tier (`min(3, tier)`); per-element proficiency (`element_mastery_<e>`) stays separate.
- Realm names are data: adding or renaming a realm changes `RealmDefaults` (or a `.tres`), not rules code.

## Consequences

- Supersedes ADR 0003's per-path ladder and ADR 0004's six mastery ranks; the rest of both ADRs stands.
- All systems share one progression vocabulary, so cross-system gating and comparison are trivial.
- The ladder is treated as append-only: inserting a realm shifts indices, so changing it requires a save-schema migration.
