# 0359 Six action slot types, each with a distinct role

- Status: Accepted
- Date: 2026-10-06
- Depends on: ADR 0053 (equipping is a build choice), ADR 0054 (passive vs active)
- Amends: nothing

## Context

The technique program needs 6 individual slot types so each technique has a distinct role. Currently all techniques share one slot type. The user approved 6 types: Assault, Barrier, Suppression, Restoration, Evasion, Transcendence.

## Decision

**6 action slot types:**

| # | Slot | Role |
|---|---|---|
| 1 | assault | Offensive — direct damage, burst, DPS |
| 2 | barrier | Defensive — damage reduction, guard, tanking |
| 3 | suppression | Control — stuns, slows, debuffs, crowd control |
| 4 | restoration | Support — healing, buffs, regeneration, cleanse |
| 5 | evasion | Movement — dashes, blinks, dodges, speed |
| 6 | transcendence | Ultimate — powerful, long cooldown, game-changing |

Each technique carries a `slot_type` field. A technique can only equip in a slot of its own type. `TechniqueSlots` manages 6 typed slots.

## Consequences

- `TechniqueDef` grows a `slot_type` export.
- `TechniqueSlots` grows from 1 universal slot to 6 typed slots.
- The diversity validator checks all 6 slot types are represented per build.
- Existing techniques default to `assault` (most are offensive).
