# 0025 Master option catalog ownership: fixed plus rolled modifier model

- Status: Proposed
- Date: 2026-10-02

## Context

`ItemDef` carries stub `flat_modifiers` / `percent_modifiers` (raw stat→value maps) and
`ItemInstance` carries bare affix ids with no rolling or equipment behavior. The clarified
model is authoritative: the current modifier implementation is a stub. A single master
modifier/option pool becomes the source of truth for every modifier definition, and every
in-game item has item-authored fixed modifiers plus a rolled-modifier channel.

## Decision

- One master option catalog (JSONL under `game/data/`) is the sole authored source for item
  effects and roll configuration. It owns option identity, target binding, operations, units,
  eligibility, roll rules, exclusivity, and presentation.
- Stat ids, actor derivation formulas, and resource semantics stay owned by their existing
  code/contracts/modules. The catalog never redefines them.
- `ItemDef` gains first-class `fixed_modifiers` (master option id + item-authored fixed value)
  and a roll specification (derived pool reference, count/budget policy, eligible affix
  positions). Realized rolls live on the instance, not the shared definition.
- Both fixed and rolled modifiers reference the same master option ids and effect semantics.
- The stub `flat_modifiers` / `percent_modifiers` maps and bare affix-id fields are migrated
  through a deterministic, tested path — not preserved as a parallel system.
- Every item category (equipment, consumable, material, technique, key, currency, quest,
  misc) uses both channels, with explicit activation (equip, use, socket, crafting).

## Consequences

- One effect-definition source; derived pools, loot, sets, sockets, and enchantments
  reference option ids and never copy an effect implementation.
- Fixed values are validated under the catalog's fixed-value policy; they are not roll formulas.
- Runtime reads the master JSONL or a deterministic generated projection (one export-safe
  path); stale projections fail by content/version hash.
- Distribution audits the catalog's eligible/weighted pools and generation outcomes.
