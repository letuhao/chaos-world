# 0484 An open VFX vocabulary for action techniques

- Status: Accepted
- Date: 2026-10-06
- Depends on: ADR 0056 (a def lives in its owning module), ADR 0483 (six action slot types)
- Amends: nothing

## Context

Action techniques need VFX types so the VFX generation pass can assign visuals later. The vocabulary must be open — new types appendable without breaking existing content.

## Decision

**`VfxType` is an open enum in `game/src/modules/techniques/vfx_type.gd`:**

- 5 categories: offensive, defensive, movement, control, summon
- 22 types: projectile, beam, aoe, nova, chain, explosion, meteor, pull, push, shield, barrier, heal, buff, dash, teleport, blink, trap, zone, stun, slow, summon, transform
- Each slot type maps to VFX categories: assault→offensive, barrier→defensive, suppression→control, restoration→defensive, evasion→movement, transcendence→summon+offensive

**Open means:** new types are appended to `ALL` and `CATEGORY`. Existing techniques keep their VFX type string. `is_valid()` checks membership.

## Consequences

- `TechniqueDef` grows a `vfx_type` export (default `""` = unassigned).
- The diversity validator reports VFX coverage per slot type.
- VFX generation agents read `vfx_type` to assign visuals.
