# 0388 Encounter system: random fate opportunities and prophecy drops

- Status: Accepted
- Date: 2026-10-06
- Consistent with: ADR 0065 (fate is earned), ADR 0113 (fact ledger), ADR 0076 (encounter exchange)

## Context

The destiny module (ADR 0065) earns fate through deeds — combat, quests, story events.
But there is no system that creates *opportunities* for fate-earning during exploration.
The world module has locations and inhabitants but no random event layer. Players need
encounters that offer fate choices and drop prophecy items to create emergent storytelling.

## Decision

**New `encounter` module** — random fate opportunities during exploration.

- **`EncounterDef`** — authored encounter types with trigger conditions and rewards.
  Each encounter has: `id`, `display_name`, `description`, `trigger` (location/fate-held
  condition), `fate_choices` (1-2 fates offered), `prophecy_id` (optional prophecy drop),
  `weight` (relative spawn probability), `cooldown` (turns before re-triggering).
- **`EncounterState`** — tracks which encounters have been seen/resolved per actor.
  Stored under `actor.module_data["encounter_state"]` (ADR 0027 pattern). Monotone:
  an encounter is seen once and stays seen (ADR 0065 earn-only).
- **`EncounterApi`** — facade: `trigger_encounter`, `resolve_encounter`, `state`, `summary`.
  Earn-only: no purchase, no cheat, no removal.

**Prophecy system** — items that hint at fates.

- **`ProphecyDef`** — authored prophecy items. Each has: `id`, `display_name`,
  `description`, `hint_fate_id` (the fate it hints at), `hint_text` (the hint shown).
- **Uniqueness gate**: no two prophecies hint at the same fate. Enforced by
  `ProphecyCatalog.validate()` and a test.
- Prophecies are earned through encounters, never purchased.

**Integration with destiny module**:
- Encounters offer fate choices (1 of 2) — compatible with Gap 2's `FateDef.eligible_choices`.
- Prophecies hint at fates the player hasn't earned yet.
- The encounter module depends on `destiny` through its facade only.

**Yin-yang balance**:
- Prophecy hints are vague enough to not spoil, specific enough to guide.
- Encounter cooldowns prevent farming.
- Fate choices are exclusive — choosing one closes the other (ADR 0065).

## Consequences

- New module `encounter` with `EncounterDef`, `ProphecyDef`, `EncounterState`, `EncounterApi`.
- New data: `game/data/encounter/encounters/`, `game/data/encounter/prophecies/`.
- Encounters are earn-only: no purchase path exists.
- Prophecies are unique: a validation gate enforces one-to-one fate hinting.
- The encounter system integrates with the world module (location-based triggers)
  and the destiny module (fate choices and prophecy hints).
