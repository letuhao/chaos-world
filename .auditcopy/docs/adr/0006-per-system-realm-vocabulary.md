# 0006 Per-system realm vocabulary

- Status: Accepted
- Date: 2026-10-01

## Context

ADR 0005 gives every cultivation system the same 30-realm ladder (4 tiers). Systems need their own display vocabulary — Elemental Mastery calls the first realm "Spark", not "Qi Refining" — without forking the ladder.

## Decision

- Keep one shared structural ladder (ADR 0005); `PathState.rank_id` remains a realm id.
- `CultivationPathDef.stage_names: Array[String]` holds this system's 30 display names, aligned by index to the realm ladder. `stage_name(realm_id)` returns the system name or falls back to the realm's display name.
- Vocabulary is display-only: rules, gating, saves, and cross-system comparisons all use realm ids.
- Elemental Mastery ships its 30 names (Awakening -> Command -> Dominion -> Transcendence); Succubus and other systems add their own later.

## Consequences

- One progression axis; systems differ only in presentation.
- Adding a system = authoring a `CultivationPathDef` with 30 stage names; no ladder changes.
- Stage-name arrays must stay aligned to the realm ladder (append-only), the same migration rule as ADR 0005.
