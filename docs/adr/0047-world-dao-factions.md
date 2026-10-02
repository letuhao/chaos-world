# 0047 World dao factions

- Status: Accepted
- Date: 2026-10-02

## Context

The world has three major dao factions that shape politics, conflict, and player alignment. Each faction follows a distinct dao path (ADR 0003) and controls territories across the four world tiers (ADR 0046).

## Decision

- Three major dao factions:
  - `qi_dao` — Qi Dao (气道) — Way of Energy — Azure — Creation through energy
  - `body_dao` — Body Dao (体道) — Way of Form — Gold — Preservation through form
  - `mind_dao` — Mind Dao (神道) — Way of Spirit — Violet — Transcendence through spirit
- Each faction has: dao_alignment, home_tier, philosophy, relationships.
- `relationships` is `Array[Dictionary]` with `faction_id` and `stance` (allied/neutral/hostile).
- Faction stance is symmetric: if A is hostile to B, B is hostile to A.
- Factions control locations (`WorldLocationDef.faction_id`) and field inhabitants (`WorldInhabitantDef`).

## Consequences

- Faction alignment gates player access to locations, inhabitants, and quests.
- Adding a faction is authoring a `.tres`, not code.
- Faction relationships are data-driven: changing stance is editing a `.tres`.
- The three factions map to the three cultivation paths (ADR 0003): qi, body, mind.
