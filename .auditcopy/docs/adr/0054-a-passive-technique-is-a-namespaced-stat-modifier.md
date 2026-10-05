# 0054 A passive technique is a namespaced StatModifier, not a provider

- Status: Accepted
- Date: 2026-10-02

## Context

A passive technique keeps contributing while equipped and stops on unequip. The repo already has
two mechanisms for contributing stats to an actor, and they are not interchangeable.

`StatProvider` is a pure function recomputed on every read. Its removal API is
`clear_providers()`, which drops *every* provider for the actor — there is no per-provider
removal. Worse, a provider that owns a stat id *overrides* the modifier pipeline's value for
that id.

`StatModifier` is a stored, tagged entry: `(stat, op, value, source)`. Removal is
`remove_modifiers_from(source)`, an exact string filter. Equipment, sockets, set bonuses and
realm scaling all use it, each in a disjoint namespace (`instance_id`, `socket:<id>`,
`set:<id>:<tier>`, `&"realm"`).

A passive technique needs N independently-toggleable contributors on one actor. Only
`StatModifier` can express that.

The one genuine hazard is namespace collision: `remove_modifiers_from` is a linear filter with
no prefix matching, so two owners sharing a tag annihilate each other silently.

## Decision

- **A passive technique's contribution is `StatModifier`s**, applied and removed exactly as
  `equipment.gd` does, via `ItemEffects.stat_modifiers` and `resource_modifiers`.
- **The source tag is `technique:<technique_id>`** — a namespaced prefix, never a bare id, so a
  technique can never collide with `&"realm"` or an instance id.
- **Never a provider.** A provider-backed technique would make the whole actor's stat ownership
  depend on which of several techniques is equipped.
- **Rebuild is remove-all-then-re-add**, copying the proven `SocketEffects.apply` shape. Rebuilding
  any number of times must not accumulate drift.
- **Suspension mirrors equipment.** An unaffordable upkeep leaves the technique equipped and
  contributing nothing; it never unequips and never blocks an equip.
- **Requirements read base allocation only**, so a technique can never satisfy its own
  requirement with the stats it grants. This transfers for free from the modifier mechanism,
  because modifiers never touch base values.

## Numbers

- The source tag is `"technique:" + technique_id` and nothing else; a rebuild is
  `remove_modifiers_from(tag)` then re-add. There is no per-rung tag, because one rebuild
  replaces every rung's contribution atomically.
- **`passive_options: Array[Dictionary]` is `ItemDef.fixed_modifiers` verbatim**
  (`{option_id, value}`), resolved through `OptionCatalog.fixed_effect`. A passive technique
  is an item row that never got equipped, so `ItemEffects.stat_modifiers` /
  `resource_modifiers` turn it into `StatModifier`s with no new code path.
- 36 of the 111 pool options are technique-legal, 29 of them `cult_*`. These give a passive
  an identity rather than making it a stat stick:
  - `cult_technique_power` / `cult_technique_cost_reduction` — rewrite how every technique
    costs and hits. Prefix/postfix contexts only, so they read as a modifier on the
    technique system, never as a base stat.
  - qi: `cult_qi_control`, `cult_qi_affinity`, `cult_qi_regen_rate`, `cult_dantian_capacity`.
  - body: `cult_bone_density`, `cult_muscle_fiber`, `cult_organ_vitality`, `cult_regeneration`.
  - mind: `cult_mental_attack`, `cult_mental_defense`, `cult_mental_clarity`,
    `cult_perception`, `cult_dodge_chance`, `cult_illusion_resistance`.
  - `dual_cultivation` shared: `cult_charm`, `cult_fertility`, `cult_purity`,
    `cult_dual_cultivation_rate`, `cult_essence_capacity`, `cult_essence_regen` — described
    clinically and mechanically and never otherwise.
- `cult_physical_attack` / `cult_physical_defense` are `deprecated` against invented ids;
  use `core_attack_physical` / `core_defense_physical`.
- `cult_conception_chance`, `cult_gestation_speed` and `cult_maternal_resilience` are
  **equipment-only** and a technique may not carry them (DEF-0100).
- A passive holds **2 options maximum**. That cap is what keeps a codex page a comparison
  rather than a table of numbers, and why the pool above is a menu, not a template.

## Consequences

- The passives cost roughly 110 lines in one new file and require no change to `ActorStats`,
  `Equipment`, or the modifier pipeline. This is a thin new consumer, not a fork.
- `EquipmentUpkeep.settle()` is welded to `Equipment.SLOTS`, so a technique slot needs its own
  settle loop sharing the same `_pay`. The class itself is already generic.
- Realm requirements resolve to the highest rank across all three paths, so a *path-scoped*
  requirement cannot reuse `ItemRequirement.min_realm_index` unchanged. That is the one
  requirement change this forces, and it belongs to the module, not to `items`.
  **Resolved by ADR 0059:** `ItemRequirement` gains `min_path_realm`, and a DUAL technique
  requires both of its paths.
- A pre-existing gap is worth fixing in the same change: `Equipment.rebuild()` reads effects
  directly and ignores suspension, so rebuilding a suspended slot would reactivate it.