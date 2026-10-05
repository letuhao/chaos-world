# 0012 Body cultivation (Luyện Thể)

- Status: Accepted
- Date: 2026-10-02

## Context

ADR 0003 established pluggable cultivation paths; ADR 0005 unified them on a shared 30-realm ladder; ADR 0006 gave each path its own stage-name vocabulary. Body Cultivation is the second major system (after Qi Cultivation) and the physical refinement path. It must coexist with Qi Cultivation on the same actor, feed into the shared stat pipeline, and give body cultivators a distinct combat identity (tanky melee vs. ranged qi).

## Decision

- **Path**: `path_id: "body_cultivation"`, display name "Body Cultivation". 30 stage names aligned to the shared ladder (ADR 0005/0006): Skin Tempering, Muscle Forging, Bone Refining, Marrow Cleansing, Tendon Strengthening, Organ Tempering, Blood Refining, Iron Body, Copper Body, Silver Body, Gold Body, Jade Body, Diamond Body, Adamant Body, Body of Laws, Body of Dao, Body of Void, Body of Chaos, Body of Creation, Body of Destruction, Body of Eternity, Body of Immortality, Body of Transcendence, Body of Unity, Body of Origin, Body of Heaven, Body of Earth, Body of Humanity, Body of Divinity, Body of the Dao.
- **Resources** (`ResourcePool`): `body_integrity` (physical condition/durability, consumed by body techniques and restored by rest/pills); `stamina` (already in core — body cultivation raises its maximum and regen via derived stats).
- **Base attributes** (module-specific, stored in `ActorStats._base` alongside core's 7): `bone_density` (skeletal durability), `muscle_fiber` (contractile force/speed), `organ_vitality` (internal organ resilience). `physique` (core, ADR 0001) is amplified by body cultivation.
- **Derived stats** (emitted by `BodyProvider`): `physical_attack` (melee/unarmed damage bonus), `physical_defense` (physical damage reduction), `move_speed` (base movement bonus), `carry_capacity` (equipment weight limit), `regeneration` (passive health/stamina regen), `poise` (knockback/stagger resistance), `body_cultivation_power` (amplifies body technique effects).
- **Progression**: `LadderProgression` (shared ladder). Breakthrough requires: `body_integrity` pool full, `physique` threshold, Body Tempering Pill (item). Failure causes body deviation: damaged meridians (temporary `physique` penalty via modifier) and reduced breakthrough chance.
- **Stat provider**: `BodyProvider` implements `StatProvider` (ADR 0002). Reads base attributes, `body_integrity` ratio, and path rank; emits derived stats scaled by realm multipliers.
- **Module structure**: `game/src/modules/body_cultivation/` — `api.gd` (facade), `provider.gd` (`BodyProvider`), `stats.gd` (`BodyCultivationStats` constants), `body_path.gd` (`CultivationPathDef` resource). No changes to `core/` or `contracts/`.
- **Interactions**: Body cultivation enhances physical combat (unarmed/melee). Realm tier gates advanced body techniques (Iron Body at Spirit tier, Gold Body at Immortal tier, etc.). `carry_capacity` affects equipment load limits. Body cultivators trade ranged damage for durability and poise.

## Consequences

- Body Cultivation is the second path on the shared ladder; adding more paths (soul, sword, etc.) follows the same pattern.
- `body_integrity` is a new pool consumed by body techniques; combat modules must check it before executing body skills.
- Breakthrough failure introduces a temporary debuff modifier on `physique`; the modifier stack (ADR 0001) handles this without core changes.
- `carry_capacity` creates a new equipment constraint; the inventory/equipment system must read this derived stat.
- Body technique gating by realm tier means the combat system must query `PathState.rank_id` tier before allowing technique use.
- The module depends only on `core/` and `contracts/`; it may be referenced by other modules only through `api.gd`.
