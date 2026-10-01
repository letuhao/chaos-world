# 0002 Actor extension points and reproduction modules

- Status: Accepted
- Date: 2026-10-01

## Context

ADR 0001's actor base has fixed vitals and core stats. Succubus/dual-cultivation and fertility are focus features but are not universal to every actor, so they must not bloat `core`. Core needs generic extension points; the features live in modules.

## Decision

- Generalize `vitals` into a named **`ResourcePool`** map; modules add pools (`essence`, `desire`, `corruption`, `yin`, `yang`) without changing core.
- Add **`statuses: Array[StatusEffect]`** and a **`relationships`** map (`partner_id -> affinity`) to `Actor`.
- Add `contracts/stat_provider.gd`: modules contribute derived stats; `app/` registers providers at boot (DIP).
- Module **`dual_cultivation`** owns: base attributes `charm`, `fertility`, `potency`; derived stats `allure`, `seduction_resist`, `essence_drain`, `dual_cultivation_rate`, `harmony`, `essence_capacity`, `essence_regen`, `qi_transfer_rate`, `yin_yang_balance`, `purity`, `deviation_risk`; resources `essence`, `desire`, `corruption`, `yin`, `yang`; and `DualTechniqueDef` / `TraitDef`.
- Module **`fertility`** owns the conception → gestation → birth state machine (`NONE -> CONCEIVED -> GESTATING -> LABOR -> POSTPARTUM`), derived stats `conception_chance`, `gestation_speed`, `parturition_safety`, `offspring_quality`, `multiple_birth_chance`, `maternal_resilience`, `recovery_rate`, offspring inheritance, and `SpeciesDef`.
- `fertility` depends on `dual_cultivation` (declared in the registry) for the shared fertility/potency stats; both otherwise depend only on `core`/`contracts`.
- All feature content is data-driven: adding a species, technique, or trait is a `.tres`, not code.
- These features are **pure gameplay mechanics**: no sexual or explicit content anywhere.

## Consequences

- Core stays lean; every actor carries only the pools and statuses it uses.
- Pregnancy is a status, not a stat; modules read `Actor` and never reach into each other's internals.
- Offspring are ordinary `Actor`s (realm 0) with inherited base attributes and spirit roots.
- Adding or altering these modules follows the standard module workflow; new core extension points would need another ADR.
