# Master prompt: complete Mind Cultivation, Thức Hải and Meridian progression

You are the implementation agent for **Chaos World**, a Godot 4.7.x action RPG. Enhance the existing Mind Cultivation system and its Thức Hải (Sea of Consciousness) reservoir across all 30 canonical realms. Deliver working progression, obtainable breakthrough and strengthening items, authored initial states and content seeds, explicit conditions, rewards, a balanced power ladder, persistence, usable UI and tests. Extend the existing ADRs and code where they own this behavior. Continue through implementation and integration; a brainstorm, ADR, generated catalog or headless stub alone does not complete this task.

Repository: `D:/Works/source/chaos-world`.

## 1. Authority and execution

- Read the current `AGENTS.md` and applicable local instructions. Code/config is the repository truth; recheck every observation below before editing.
- Keep Godot standard/GDScript for runtime, Python through `uv` for tooling, English documentation and gameplay descriptions. Use supported commands through `uv run python -m tools <task>`.
- If `.codegraph/` exists, query CodeGraph before locating or reading code. Otherwise use targeted `rg` searches. Read relevant facades, owners and tests; avoid loading the whole repository.
- Preserve unrelated work. Record initial Git status and identify overlapping edits before touching a file. Do not reset, discard or silently overwrite another agent's changes.
- Follow layer direction, facade-only module access, registry rules and facade budgets. Core/contracts changes need an ADR and appropriate tests. Do not bypass boundaries through global `class_name`, arbitrary component lookups or unchecked dictionaries.
- Extend fitting types/helpers and use native runtime behavior. Add only the small data, state and transactions this task needs. Do not create parallel actor, inventory, realm, meridian, modifier or save systems.
- Load relevant repository skills individually: `rpg`, `godot-resources`, `save-systems`, `godot-gdscript-headless-testing`, and UI/GDScript skills as needed.
- Implement in dependency order. Use small complete vertical slices, with passing checks before extending them. Delegation is optional unless applicable instructions require it; shared trackers, ADR numbering and central schemas have one writer.
- Durable architectural decisions belong in lean ADRs. Use existing JSONL trackers for scope and residual work. Do not add repository planning/status/design Markdown or copy these preparation artifacts into its docs.
- Ask the user only for a material public, security, billing, data-loss or hard-to-reverse policy choice that current instructions do not settle. Resolve routine reversible design choices and prove them.

## 2. Research findings to verify

Prepared on 2026-10-02 against the current working tree. These are observations, not frozen requirements.

| Owner | Observed behavior and implication |
|---|---|
| `modules/mind_cultivation/mind_path.gd` | 30 stage names aligned to the shared ladder. Path ID `mind_cultivation`. Use them. Do not introduce another realm axis. |
| `modules/mind_cultivation/api.gd` | `attach()` adds `mind_power` and `awareness` pools + `MindProvider`. `attach_sea()` creates a `SeaOfConsciousness` component + `SeaProvider`. `sea()` reads the component. Attachment must become idempotent and preserve existing state. |
| `modules/mind_cultivation/sea_of_consciousness.gd` | Stores `tier` (shallow/deep/vast), `capacity`, `current`, `clarity`, `turbulence`. Has `fill`/`drain`/`add_turbulence`/`calm`. No damage concept; turbulence is the mind analogue of injury. |
| `modules/mind_cultivation/sea_provider.gd` | Emits `SEA_CAPACITY`, `SEA_CLARITY`, `SEA_TURBULENCE`, `SEA_FULL` from the sea component. |
| `modules/mind_cultivation/provider.gd` | `MindProvider` emits derived stats from base attributes + rank + meridian power bonus. Uses linear rank scaling (`1.0 + rank * 0.05`). |
| `modules/mind_cultivation/stats.gd` | Constants for `PERCEPTION`, `MENTAL_CLARITY`, derived stats, sea stats, and resources `MIND_POWER`, `AWARENESS`. |
| `core/meridian_network.gd` | 20 meridians with states Closed/Open/Expanded/Strengthened/Damaged. `unlock_for_realm` creates Closed states. `refine_meridian` adds depth on strengthened channels. Damage overwrites structural state; repair returns to Open. |
| `core/meridian_defaults.gd` | 12 primary (tiers 0/3/6) + 8 extraordinary (tiers 9/12/15). All bonuses 0.05/0.10/0.05. |
| `core/meridian_state.gd` | Per-meridian state with `get_bonus()` returning 0.5 when damaged. |
| `core/actor.gd` | Save schema version 2. Meridians serialized. Mind components (sea) not serialized by this payload. |
| `core/actor_stats.gd` | Providers overwrite query results. Provider iteration order can become hidden ownership. |
| `core/breakthrough.gd` | Shared advancement with `BreakthroughCondition`. `try_advance_gated` applies tribulation/inside-world/world/ascension gates for Immortal+. |
| `core/tribulation.gd` | Four phases (warning/trial/climax/aftermath). `apply_result` grants rewards or applies failure. Damages all meridians on failure. |
| `core/inside_world.gd` | Seed/Pocket/Inner tiers. `is_stable()` at stability >= 0.5. |
| `core/world_creation.gd` | Micro/Small/Great tiers. `is_stable()` at stability >= 0.3. |
| `core/ascension_state.gd` | Three stages, dao_level 1-5, `is_complete()` at stage 3 + level 5. |
| `modules/body_cultivation/` | Most complete reference: acupoints, training, breakthrough, realm seeds, data-driven content, full tests. Follow this pattern. |
| `modules/qi_cultivation/` | Dantian with three tiers, quality, damage. Provider with meridian flow bonus. No training/breakthrough action layer yet. |
| `modules/items/` | ItemDef, RecipeDef, Inventory, Crafting. Crafting has a known bug (DEF-0028): station check is tautological, time gating unimplemented. |
| `tools/test.py` | Can return success when Godot/project is missing. A skipped suite is not acceptance evidence. |
| UI | No main scene in `project.godot`. Reuse current app/UI if present; otherwise deliver a small playable cultivation slice. |

Relevant ADRs, with their observed status:

- **Accepted:** 0001 actor/stats, 0003 path architecture, 0005 shared ladder, 0006 display vocabulary, 0007 items, 0008 acquisition audit, 0009 tier bundles, 0010 generation batches, 0011-rate-stats, 0022 damage-reduction.
- **Draft:** 0011-qi-cultivation, 0012-body-cultivation, 0013-mind-cultivation, 0014-dantian-meridians, 0015-huyet-meridians, 0016-thuc-hai-meridians, 0017-meridian-network, 0018-inside-world, 0019-world-creation, 0020-tribulation, 0021-ascension, 0023-body-cultivation-realm-seeds.
- Draft 0013 defines Mind Cultivation's path, resources, base attributes, derived stats, and breakthrough concept.
- Draft 0016 defines Thức Hải tiers, sea mechanics (capacity/clarity/turbulence), mind+meridian interaction, and breakthrough challenges.
- Draft 0017 defines the shared meridian network (core), states, unlock progression, and cross-system interactions.
- Draft 0014 says Qi owns meridians; Draft 0017 and current code place the network in core. Preserve shared core ownership.

Read/traverse these behaviors before designing edits:

1. Actor initialization → Mind attachment → sea attachment → path initiation → resource owner → training tick → stats → technique use/UI → save/load.
2. Realm profile → source-side preparation → preview → item reservation → attempt/trial → atomic success/failure → permanent award/recovery → save/load.
3. Meridian definition → eligibility → structural training → injury overlay → repair → shared Qi/Body/Mind stats.
4. Boss/domain/gather source → owned materials → alchemy → realized consumable → correct activation → consumed state.
5. Authored content seed → deterministic generation/registration → validation → runtime resource → distribution/balance report.

## 3. Brainstorm and selected direction

Considered approaches:

1. Mind as a pure stat multiplier: simple but makes the sea and meridians decorative labels.
2. Independent mind meridian network: duplicates the shared network and creates cross-system inconsistency.
3. Mind reads meridians but cannot mutate them: preserves shared ownership but makes mind progression dependent on other paths.
4. **One Thức Hải reservoir, authored realm profiles, shared meridian network with mind-specific training policy, and recoverable turbulence:** preserves current ownership, supports every tier, and gives mind a distinct combat identity.

Implement option 4. Mind-only progression must remain viable. Qi cultivation can help clarity/purity; Body cultivation can help meridian repair. Neither requires matching Mind realm or a mandatory second path. Do not add organ rarity, sockets, random anatomy, a new currency or a second skill tree.

The intended fantasy is **hunt and craft → prepare the sea and channels → fill/refine mind power and gain insight → attempt breakthrough → earn the next mental stage → strengthen it**. Rewards must affect actual storage, flow, technique performance or a used high-tier anchor mechanic.

## 4. Single ownership and invariant decisions

### Mind power and Thức Hải

- The existing actor `mind_power` ResourcePool owns current usable mind power. Thức Hải owns structural tier, trained stage, clarity and recoverable turbulence. Sea fullness/draining must read/mutate that same pool.
- Remove or adapt duplicated Sea current/capacity state through a deterministic migration. A compatible Sea view is acceptable; two independently saved energy balances are not.
- Preserve the core `max_qi` stat's identity and other paths. Mind power is a distinct pool; do not merge it with qi or create a competing universal energy.
- Lower sea is active in realms 1–9, Middle sea in 10–18, Upper sea in 19–30. These are stages of the same active reservoir. Tier changes preserve absolute stored mind power and existing training; they do not refill or bank three full pools.
- Structural clarity and mind power purity are different. Clarity describes the sea's stability; purity is the bounded refinement of stored energy. Keep one truth for each.
- Capacity is derived from the modified base capacity, trained profile, attained channel capacity effects and turbulence. Never persist an equipment-inflated maximum as permanent structure.
- Newly initiated actors need a positive authored capacity, an empty usable reservoir, bounded initial clarity/turbulence and Closed eligible channels. Do not inherit today's accidental full-at-attach behavior. Preserve legitimate legacy balances on migration.
- Changing maximum clamps current downward and never grants free mind power on a subsequent increase. Reattachment, equip/unequip, healing and reload cannot refill energy.

### Shared meridians

- Keep one `Actor.meridians` network in core, accessible through the existing boundary. Mind-specific training policy belongs in `mind_cultivation`; Qi/Body use the same network.
- Preserve the 20 stable channel IDs. Structural states remain Closed → Open → Expanded → Strengthened. At least-state checks are ordinal comparisons, not string inequality.
- Injury is an independent recoverable flag/severity with a defined penalty. It does not erase structural attainment. Repair restores previous attained benefits.
- Legacy `damaged` saves have lost the old structural state. Migrate to the minimum defensible Open state with injury; do not invent a former Strengthened state. Preserve uninjured saved states exactly.
- Eligibility and opening are separate. A realm award exposes eligible Closed channels; explicit training opens them. Define shared unlock authority using valid path realms, and keep Mind's adjacent progression/item/attempt gates intact even if another path unlocks channels earlier.
- Realms 19–30 reinforce the **same network** through twelve network resonance ranks. Resonance is bounded physiological reinforcement, not twelve new channels, a new cultivation path or another realm ladder.
- Network/reservoir mutations emit change signals at their owner. Cache refresh and resource maximum reconciliation must occur without UI/tests manually repairing state.
- Flow/capacity/power contributions apply once with declared stacking. Injury penalizes all applicable contributions consistently across Qi, Body and Mind.

### Conditions, strengthening and awards

- Use one authored Mind realm profile per canonical realm ID. It links entry conditions, its three consumable roles, training milestones, effects, trial/anchor requirements and rewards. Use typed Resources and the existing data pipeline; do not encode content rules as thirty branches.
- Profile R describes **entering R and training while in R**. Entry into R requires completed Thức Hải/meridian milestones of R−1, not training that only unlocks after entering R.
- R1 is initiation of an unstarted Mind path, not an invented realm 0 in the canonical ladder. R2–R30 are adjacent advances. R30 can have terminal strengthening/mastery; it cannot advance to R31.
- Realm success unlocks the new profile/tier/channels. It does not automatically complete the target realm's strengthening. Target training uses its Thức Hải/meridian catalysts and grants its own once-only improvement.
- Training uses elapsed time/explicit work and resource costs, with deterministic completion. Queries/previews never progress it. Permit cancellation/resumption with an explicit resource policy; one catalyst starts/reserves a defined milestone, not one item for every frame.
- Track partial channel transitions/work so long milestones can resume. A selected two-of-four channel requirement must be achievable by player choice and remain valid after save/load.
- Every advancement and strengthening award has a stable completion identity. Restore state and recompute effects on load; do not replay grant logic.

## 5. Complete proposed realm seeds and power ladder

The companion JSON expands every row into three item definitions, a realm profile, source/recipe seeds, explicit previous-stage gates and awards. Names and numbers below are proposed tuning, not claims that they are already implemented.

Channel groups:

- A: Lung, Large Intestine, Stomach, Spleen.
- B: Heart, Small Intestine, Bladder, Kidney.
- C: Pericardium, Triple Burner, Gallbladder, Liver.
- E: Du Mai, Ren Mai, Chong Mai, Dai Mai.
- Q: Yin Qiao, Yang Qiao. W: Yin Wei, Yang Wei.

Each row's channel training is **after entry**, and previous structural gains persist. Thus R10 entry requires twelve Strengthened primaries; R10 then exposes and trains E. R19 entry requires all twenty Strengthened channels; resonance begins after entry. No entry depends on its own award.

P is a reference power budget, C a healthy capacity factor, F a throughput factor and T a technique factor. **P is never another stat multiplier.** Proposed schedules are Mortal `1 × 1.25^(local−1)`, Spirit `8 × 1.22^(local−1)`, Immortal `55 × 1.20^(local−1)`, Transcendent `330 × 1.35^(local−1)`. C=`P^0.85`, F=`P^0.40`, T=`P^0.55`.

| # | Realm ID | Breakthrough item | Sea structure / catalyst | Meridian training after entry | P / C / F / T |
|---:|---|---|---|---|---|
| 1 | `qi_refining` | First Thought Initiation Pill | Shallow sea / Clarity Stone | A: 4 open; First Mind Dew | 1.00 / 1.00 / 1.00 / 1.00 |
| 2 | `foundation` | Focus Stabilization Pill | Focused sea / Focus Binding Sand | A: 2 expanded; Focus Circuit Resin | 1.25 / 1.21 / 1.09 / 1.13 |
| 3 | `core_formation` | Clarity Condensation Pill | Clear sea / Clarity Lattice Jade | A: 4 expanded; Clarity Circuit Dew | 1.56 / 1.46 / 1.20 / 1.28 |
| 4 | `nascent_soul` | Insight Embryo Elixir | Insight sea / Insight Cradle Dew | B: 4 open; Insight Circuit Resin | 1.95 / 1.77 / 1.31 / 1.45 |
| 5 | `spirit_transformation` | Enlightenment Transformation Pill | Enlightened sea / Transforming Mind Amber | A: 4 expanded; B: 4 expanded; Spirit Flow Dew | 2.44 / 2.14 / 1.43 / 1.63 |
| 6 | `void_refinement` | Void Seam Refinement Pill | Void sea / Void Suture Silk | A: 4 strengthened; Void Channel Resin | 3.05 / 2.58 / 1.56 / 1.85 |
| 7 | `body_integration` | Perception Integration Pill | Integrated sea / Perception Fusion Ore | C: 4 open; Integrated Circuit Dew | 3.81 / 3.12 / 1.71 / 2.09 |
| 8 | `great_ascension` | Awareness Compression Elixir | Expanded sea / Awareness Compression Crystal | C: 4 expanded; Awareness Channel Resin | 4.77 / 3.77 / 1.87 / 2.36 |
| 9 | `tribulation` | Ninefold Mind Crossing Pill | Crossing sea / Crossing Stabilizer | A: 4 strengthened; B: 4 strengthened; C: 4 strengthened; Twelvefold Circuit Dew | 5.96 / 4.56 / 2.04 / 2.67 |
| 10 | `spirit_condensation` | Refined Mind Condensation Pill | Refined sea basin / Refined Sea Pearl | E: 4 open; Extraordinary Channel Dew | 8.00 / 5.86 / 2.30 / 3.14 |
| 11 | `spirit_sea` | Mind Tide Elixir | Tidewall sea / Tidewall Coral | E: 4 expanded; Mind Tide Resin | 9.76 / 6.93 / 2.49 / 3.50 |
| 12 | `spirit_palace` | Palace Keystone Pill | Palace sea / Palace Foundation Jade | E: 4 strengthened; Palace Circuit Dew | 11.91 / 8.21 / 2.69 / 3.91 |
| 13 | `spirit_manifestation` | Mind Image Elixir | Manifestation sea / Manifestation Prism | Q: 2 open; Qiao Channel Dew | 14.53 / 9.72 / 2.92 / 4.36 |
| 14 | `spirit_severing` | Severance Purification Pill | Purified sea / Severance Purity Salt | Q: 2 expanded; Qiao Expansion Resin | 17.72 / 11.51 / 3.16 / 4.86 |
| 15 | `spirit_unity` | Harmonic Unity Pill | Harmonic sea / Harmonic Mind Crystal | Q: 2 strengthened; Qiao Tempering Dew | 21.62 / 13.64 / 3.42 / 5.42 |
| 16 | `spirit_domain` | Domain Boundary Elixir | Domain sea / Domain Boundary Ore | W: 2 open; Wei Channel Dew | 26.38 / 16.15 / 3.70 / 6.05 |
| 17 | `spirit_sovereign` | Sovereign Seal Pill | Sovereign sea / Sovereign Mind Jade | W: 2 expanded; Wei Expansion Resin | 32.18 / 19.12 / 4.01 / 6.75 |
| 18 | `spirit_ascension` | Mind Ascension Elixir | Ascension sea / Ascension Anchor Pearl | W: 2 strengthened; Wei Tempering Dew | 39.26 / 22.64 / 4.34 / 7.53 |
| 19 | `earth_immortal` | Earth Mind Foundation Pill | Upper world-seed anchor / World Seed Kernel | all 20 strengthened; resonance 1; Earth Resonance Dew | 55.00 / 30.15 / 4.97 / 9.06 |
| 20 | `heaven_immortal` | Heaven Pattern Elixir | Celestial axis / Celestial Axis Stone | all 20 strengthened; resonance 2; Heaven Resonance Resin | 66.00 / 35.21 / 5.34 / 10.02 |
| 21 | `golden_immortal` | Golden Mind Tempering Pill | Golden matrix / Golden Law Matrix | all 20 strengthened; resonance 3; Golden Resonance Dew | 79.20 / 41.11 / 5.75 / 11.07 |
| 22 | `mystic_immortal` | Mystic Law Elixir | Pocket-world lattice / Mystic Spatial Thread | all 20 strengthened; resonance 4; Mystic Resonance Resin | 95.04 / 48.00 / 6.18 / 12.24 |
| 23 | `true_immortal` | True Mind Restoration Pill | True-law anchor / True Law Heart | all 20 strengthened; resonance 5; True Resonance Dew | 114.05 / 56.04 / 6.65 / 13.53 |
| 24 | `primordial_immortal` | Primordial Source Elixir | Source anchor / Primordial Source Sand | all 20 strengthened; resonance 6; Primordial Resonance Resin | 136.86 / 65.44 / 7.15 / 14.96 |
| 25 | `great_luo` | Great Luo Convergence Pill | Inner-world lattice / Great Luo Lattice | all 20 strengthened; resonance 7; Great Luo Resonance Dew | 164.23 / 76.41 / 7.69 / 16.54 |
| 26 | `dao_fruit` | Dao Fruit Ripening Elixir | Dao-fruit anchor / Dao Fruit Pith | all 20 strengthened; resonance 8; Dao Fruit Resonance Resin | 197.07 / 89.21 / 8.28 / 18.28 |
| 27 | `immortal_sovereign` | Immortal Crown Pill | Immortal crown anchor / Immortal Sovereign Keystone | all 20 strengthened; resonance 9; Sovereign Resonance Dew | 236.49 / 104.17 / 8.90 / 20.21 |
| 28 | `transcendent` | Transcendent Origin Elixir | Origin-world anchor / Origin World Kernel | all 20 strengthened; resonance 10; Origin Circuit Resin | 330.00 / 138.27 / 10.17 / 24.28 |
| 29 | `dao_ancestor` | Dao Ancestor Fusion Pill | Ancestral-law anchor / Ancestral Law Keystone | all 20 strengthened; resonance 11; Ancestral Circuit Dew | 445.50 / 178.45 / 11.47 / 28.63 |
| 30 | `primordial_origin` | Primordial Genesis Elixir | Genesis anchor / Genesis Anchor Crystal | all 20 strengthened; resonance 12; Genesis Circuit Resin | 601.42 / 230.31 / 12.93 / 33.77 |

Use these numerical gates as a complete initial proposal:

- During realm R, the Thức Hải clarity training target is `Q(R)=0.40+0.015×(R−1)`; purity training target is `U(R)=0.45+0.015×(R−1)`. They are bounded floors/entitlements, never instructions to lower an already higher legitimate value.
- Entry R>1 needs the prior completed Thức Hải milestone, clarity ≥ Q(R−1), purity ≥ U(R−1), healthy required channels, healthy nonzero active capacity and a full current reservoir within a declared small numerical tolerance.
- Entry comprehension floor is `10+6×(R−1)+2×(R−1)^2`. Its earned insight source/rate must be implemented and balanced; a threshold without an attainable source is invalid.
- Cultivation work before entry is `round(100×max(1,R−1)^1.45)`; Thức Hải milestone work is `round(20×R^1.4)`; meridian milestone work is `round(15×R^1.4)`. Work is not a hardcoded real-time duration. The runtime computes work from actual rate and elapsed simulation time once.
- R1 uses a novice preparation/initiation route and its authored initial state; it does not require a full reservoir that does not yet exist.
- Turbulence cannot make entry easier by shrinking the fullness target. Required healthy-state checks occur before fullness and chance checks.

Separate entry awards from completed training factors. Completing Thức Hải training earns that stage's C/clarity entitlement; completing network training earns the appropriate F/T reinforcement. Intermediate channel states can contribute their defined incremental effects. A profile change sets the applicable absolute factor; repeated calls never compound it.

Reuse the existing stat stack. Replace the Mind provider's private linear rank formula with the chosen profile factors for the axes they own; do not also multiply those axes by P or the old Mind rank factor. Preserve global `RealmScaling` unless a measured coherent cross-system rebalance is required. Integrate mental/spiritual combat effects deliberately so technique power and spiritual attack do not count the same gain twice.

Clarity, purity and channel bonuses may influence these axes through their own defined bounded contributions. Document whether each effect is already included in the reference profile, then test actual composed values; P is a design reference, not proof of actual actor combat power. Finalize/tune the schedule against current item bounds, actors and encounter difficulty. If the item project changes global realm scaling, reconcile the policy first.

For each final profile, require one real preparation test/constraint that expresses its theme through existing resource/training/trial mechanics. Avoid inventing thirty minigames. Capacity, efficiency and channel rewards must be observable in a working consumer.

## 6. Obtainable items and content generation

Generate/register the following roles for **each realm**, with stable IDs, meaningful description, canonical target realm, grade, recipe, source, activation, costs, fixed effect selections and permitted rolls:

1. `mind_<realm_id>_breakthrough_pill`: entry consumable, required only when a valid attempt starts.
2. `mind_<realm_id>_sea_catalyst`: starts the matching realm's Thức Hải strengthening milestone.
3. `mind_<realm_id>_meridian_catalyst`: starts the matching realm's channel/resonance strengthening milestone.

These are 90 proposed consumable seeds, not 90 new equipment items or 90 arbitrary rarity variants. Resolve proposed subtypes such as `tonic` against the live item taxonomy. Do not satisfy the request with renamed clones carrying unused modifiers.

**Reconcile ADR 0009:** its four tier bundles are accepted. Keep them and their existing consumers valid. Add a lean amendment extending Mind to per-realm bundles; do not rewrite accepted history or replace every other system's tier bundles. Reuse tier ingredient/source families where fitting. Keep Mind IDs namespaced and avoid borrowing another system's exclusive material IDs.

Every proposed row shares two material definitions across its three recipes: one gathered cultivation herb and one guardian core obtained only from its boss. All three outputs are craft-only at alchemy. Each guardian belongs to a real domain, and domain/boss/item links are bidirectional and audited. Domains may group three adjacent realm rows, yielding ten proposed domain families, with fixed authored encounters rather than scaling enemies to the player. Reuse existing compatible encounters/materials instead of padding counts.

**Availability invariant:** all mandatory preparations for entry R are obtainable and usable while the Mind actor is in R−1; the R1 novice route works without a started Mind path. A source can be difficult, but it cannot require entry to the realm it is meant to unlock. Within a grouped domain, a later guardian/area requirement cannot block the earlier recipe.

Grade is the existing six-grade content taxonomy; rarity and exact item realm remain separate. The companion uses mortal/spirit/immortal/divine for tier-aligned bundle roles. At a tier boundary, the target-grade breakthrough item must have an explicit attempt-use policy allowing the source realm's actor to prepare that transition. Do not weaken ordinary equipment-grade requirements or grant target tier early.

**Modifier integration:** the current item modifiers are a stub. The planned/live master modifier pool is the SSOT for effect definitions. Items author their fixed modifier selections/values and declare derived pools for realized rolls. Both channels reference that catalog. Never create a second cultivation modifier catalog or hardcode its effect implementation in this generator.

- Resolve the companion's fixed/rolled *intents* to valid live catalog IDs; they are not registered IDs today.
- The item's essential role, target and training/attempt gate are typed progression behavior. Fixed/rolled benefits use a real action/stat consumer and a bounded budget. Holding the item does not apply its effects.
- Example benefits: bounded attempt stability or matching training efficiency. Optional roll variation cannot replace required insight, healthy structure, preparation, world/trial completion or adjacent-rank checks.
- Never roll a Boolean fullness flag, realm grant, eligibility unlock or guaranteed trial success as a numeric stat bonus. Clarity and resource changes use their actual implemented owner/units and final clamps.
- Preserve realized rolls/identity on inventory, consume, stack and save/load. Definition-ID-only stacks cannot silently discard these effects. Integrate with the item project's ownership/instance solution.
- If the modifier foundation is absent, deliver its smallest correctly owned shared support first or coordinate a concrete prerequisite. Do not claim these items are complete while their promised effects are decorative.

Extend `tools data new/edit/audit/distribution` at their responsible helpers to support final profile/seed types and registry references. Make generation deterministic/idempotent by stable IDs, refuse collisions and support reviewed regeneration without overwriting unrelated/manual content. Use one authored final definition source and deterministic projections; do not maintain independent JSONL and `.tres` truths.

Audits must check 30-profile coverage, 90-role coverage or a deliberately reconciled equivalent, valid canonical IDs, typed units/effects, positive non-no-op benefits, legal grades/subtypes, recipes, boss/domain links, source-side reachability and no acquisition cycles. Audit modifier targets against owner schema; do not assume today's core-only stat list covers cultivation stats.

## 7. Breakthrough transaction, risk and recovery

Implement preview and execution in the responsible Mind layer using the shared advancement mechanism. Preview gives structured unmet conditions and costs; it never consumes items, changes progression, starts a trial or advances RNG.

Execution must validate ownership/current source rank, exact adjacent target, profile completeness, trained Thức Hải/network, health/fullness/purity/work/insight, usable item and trial prerequisites before any mutation. The actor can have only one active progression attempt; duplicate UI calls cannot start two.

Persist an attempt identity, actor/path/source/target/profile identity, consumed/reserved costs, preparation snapshot, RNG state if used, trial progress/result and granted-outcome state. Implement the smallest concrete transaction/state model, not a general-purpose workflow engine.

Default cost policy:

- Rejected/blocked preview or execution: no costs, progress loss or RNG change.
- Valid committed start: one breakthrough item is consumed/reserved according to an explicit atomic policy; required attempt costs are deducted once.
- Cancelling after committed start counts as a failed attempt with disclosed recoverable consequences; it cannot refund/reroll into a free second attempt.
- Success advances exactly one realm and grants the bound outcome once. Failure keeps rank and permanent strengthening, applies declared recoverable losses and leaves no half-created permanent target reward.
- Inventory overflow, unknown content/effects, missing outputs and invalid costs fail before mutation or restore the whole operation; no swallowed partial failure.

For realms 1–18, use a bounded preparation/chance rule consistent with the live breakthrough stat. Hard gates remain hard. Publish the actual evaluated chance and failure costs in UI. Strong preparation must have a meaningful measurable benefit; failure cannot erase attained sea/channel progression.

Use persisted/injected RNG only where randomness is actually needed. Preview, load, reconnect and repeated resolve calls cannot reroll. This is local-game correctness, not a request to build networking or an anti-cheat service.

Recovery must be playable without a higher realm: Mind purification, Thức Hải calming and channel repair via an available pill/rest/training route, with optional Qi/Body assistance. Turbulence penalties are recoverable, have a measurable duration/cost and cannot stack into permanent progression lock. Damage targets a bounded set of relevant channels; it must not indiscriminately reset the whole network.

No new permadeath, irreversible sea destruction or permanent comprehension loss is required for this task. High-tier draft consequences that imply such policies must be reconciled explicitly; do not introduce them incidentally in shared failure code.

## 8. Realms 19–30: actual anchors and bound trials

Thức Hải and channels continue growing in every high realm; Upper is not an empty placeholder. Reconcile related **draft** ADRs into the minimum complete required progression slice.

- R19: prepare a World Seed/upper-anchor candidate inside the valid attempt, pass its real trial, then commit the Upper/Seed World anchor. Do not require an already active Upper Thức Hải or Inside World as a prerequisite for first creation.
- R19–21: strengthen the Seed World anchor's storage/stability. R22–24: Pocket World anchor with implemented law/control requirements. R25–27: Inner World anchor with implemented stability/retention requirements.
- R28: use the completed stable Inner World to form the Micro World candidate and earn dao awakening through a real bound ritual/trial. R29: Small World fusion. R30: Great World genesis/final ascension. Transition preconditions reference current stable anchors; target anchors are committed outcomes, not circular prerequisites.
- Keep anchor state with its responsible existing owner/module. Mind reads required results through allowed boundaries. Avoid adding module-typed fields or module imports to core just because a draft sketch mentioned `Actor.world`.
- Each required law/dao milestone must have a real attainment action, source, persisted identity and numerical effect. Do not gate on an arbitrary supplied `world_ready=true` or unimplemented element such as Time/Chaos.
- The bounded slice needs functioning anchor creation/training/stability, the required law/dao/ritual milestones and their relevant Mind effects. Full world travel, civilizations, breeding, world economies, recursive sub-worlds and legacy simulation are separate backlog scope. Do not claim those are delivered or make them hidden prerequisites.

A tribulation must be a playable, resumable challenge with preparation, actual resource/combat pressure and a won/lost outcome. Warning → Trial → Climax → Aftermath can remain the shared structure, but Aftermath alone never means success. Reuse completed current tribulation code and the combat API; implement only the encounter slice required here.

The R19 and R28 breakthrough consumables have a proposed `world_seed` role/tag: their craft chain supplies the seed for the bound creation attempt. Reconcile this with the live World Seed definition so one reserved item can fulfill both roles without being consumed twice. The R19 Thức Hải catalyst named World Seed Kernel is a separate post-entry training reagent. If the owner requires a distinct seed item, author and audit that additional current-side acquisition chain; do not leave an unspecified prerequisite.

Bind every trial result to its actor, Mind path, source/target realm and attempt ID. Consuming its success authorizes that target once. Success from another path/target, a stale trial, skipped phases or caller-supplied Boolean cannot advance. All gameplay-accessible progression paths must enforce this policy; a separate unguarded `try_advance` cannot remain a Mind bypass.

Required difficulty increases by authored target profile, not by current player scaling. Preparation has tested influence, and the trial always uses obtainable defenses. Rewards such as essence/insight/marks apply once and retain existing balances; creating a fresh reward resource must not overwrite previously earned essence.

If a required high-tier dependency is unavailable, implement the smallest real dependency at its owner or report it as incomplete. Do not pass all 30 profiles by injecting success flags, disabling gates or moving mandatory work into a deferral.

## 9. ADR/backlog reconciliation

Update **draft** `0013-mind-cultivation.md`, `0016-thuc-hai-meridians.md` and `0017-meridian-network.md` to capture the implemented ownership, resource semantics, 30-realm physiological coverage, turbulence/training and eligibility policy. Revise related high-tier drafts only for the delivered bounded integration and leave broader obligations visible. Allocate a new short ADR for changes to accepted decisions, especially per-realm bundles and core/contracts/stat/save policies.

Document durable choices with context, decision, real alternatives/tradeoffs and consequences. One reservoir and resonance on existing channels reduce duplicated lifecycle rules; their tradeoff is fewer independent anatomical storage choices. Keep final numbers/content in data, not copied into ADR prose. Accepted history is immutable: amend/supersede using a new numbered record.

Search existing trackers by meaning before creating IDs:

- Preserve completed BL-0005/DEF-0004 progression plumbing, BL-0016 audit, BL-0017 tier bundles, BL-0071 Qi module and BL-0073 Dantian/network. They represent delivered foundations; add linked enhancement scope rather than deleting completion history or falsely treating all gameplay as already complete.
- Enrich BL-0039 for channel training/repair and shared-body integration.
- Coordinate actual boss/domain/drop acquisition with BL-0030/DEF-0022 and BL-0031/DEF-0023. Finish the required route; do not close unrelated quest/vendor scope.
- Link trials to BL-0044/DEF-0027, saves to BL-0061, UI to BL-0062, balance tools to BL-0066 and data extension to BL-0070. Close broad entries only if their whole scope is complete.
- Reconcile DEF-0024's stale claim that meridians are unimplemented. DEF-0024/0025/0026 retain the full Inside World/World Creation/Ascension residual scope after the Mind anchor slice.
- Existing elemental/succubus breakthrough entries and acquisition criteria remain valid; this task must not fork their inventory, ladder or condition system.
- Use existing tooling to maintain schemas/history, adding tested update support if missing. IDs and ADR numbers are allocated serially. Keep original created/completed/resolved dates and source links.
- Mandatory scope in this prompt cannot be deferred merely because implementation is difficult. Deferrals describe genuine excluded work or a specific external blocker with a next action.

Fix stale `AGENTS.md` operational statements only where needed: its greenfield/no-tools introduction did not match the inspected repository. Do not add a changelog or duplicate this plan there.

## 10. Implementation sequence and acceptance gates

**Wave 0 — orient and settle ownership.** Recheck changing files, trace the five flows, establish authoritative modifier/save/trial owners and reconcile trackers/ADR statuses. Run the smallest baseline checks needed. Record existing failures honestly and avoid disguising skipped tests as passes.

**Wave 1 — resource, state and transaction foundation.** Complete one reservoir, idempotent attachment, structural turbulence overlay, signal invalidation, relevant stat/modifier composition, save migration and safe item/crafting transactions. Deliver R1 initiation → R2 preparation/advance/failure/recovery as a playable vertical slice with an actual item acquisition route. Update its ADRs with the implementation.

**Wave 2 — profiles and generation.** Register deterministic definitions/seeds, source graph and distribution validation. Exercise R3–R18 from current-side sources. Complete channel milestones/tier transition semantics and interaction with Qi/Body. Validate all remaining proposed profiles structurally before generating a large content wave.

**Wave 3 — high-tier owners and integration.** Complete the required anchor, ritual/law/dao and tribulation slices, binding/outcome persistence, then R19–R30. Reconcile concurrent tribulation work without replacing functioning behavior. Use the same progression machinery; no separate high-tier reward engine.

**Wave 4 — gameplay, full traversal and balance.** Finish UI, save/resume and source-to-reward integration for all thirty rows; tune measured numeric/source budgets, verify migrations, run acceptance and clean residual tracking. Stop only when the required features work and checks actually execute.

UI must expose active realm/display name, Mind power current/max/purity, Thức Hải tier/clarity/turbulence/training, twenty channel states/injuries/resonance, attainable source guidance, condition failures, costs, chance/trial requirements, expected awards and recovery actions. Use keyboard-accessible controls, readable focus/contrast and textual state indicators. Critical information cannot depend only on color or hover. UI must call the same validated facade as tests/gameplay.

Smallest sufficient proof:

1. Content/graph audit: exactly 30 canonical profiles, entry/initiation/terminal semantics, every item role bound to a real consumer, legal references/units, and no source-after-target cycle.
2. Headless behavioral traversal of all 30 realms: valid normal acquisition/crafting/training/attempt APIs; tests may control time/RNG, but cannot directly set rank, channels or success flags to prove the core sequence. Assert entry, both training milestones, awards and factor application for every row.
3. Targeted regression tests: blocked attempts have zero effects; failed/aborted attempts consume once and recover; duplicate start/resolve/load cannot duplicate awards; missing/full inventory crafting is atomic; wrong/stale trial target is rejected; R18→R19 and R27→R28 have no circular prerequisite; R30 refuses another advance.
4. State/stat tests: turbulence/calming preserves structural attainment; no capacity/refill exploit; modifiers affect owned provider/resource outputs once; malformed/non-finite/negative data is rejected or migrated safely; repeated attach/load preserves state and provider count; Qi/Body see the same injury and recovery.
5. Persistence: actual legacy version-2 fixtures plus current round trips for partially trained channels, injured sea, realized items, active attempts/trials and once-granted outcomes. Save safely/atomically and restore signals/providers without resetting progression.
6. A launched playable slice exercised through actual controls, including acquisition/crafting, cultivation, strengthening, a blocked attempt, success/failure and recovery. Automated traversal can cover the remaining long progression, but UI/encounter behavior still needs direct smoke proof.
7. Deterministic balance/reachability report: healthy/current-stage versus injured/underprepared/overgeared cases, successive/tier-boundary power, time/work/insight/material costs, measured chance/failure recovery, modifier caps and current-side encounter access. Independent Mind progression must be possible. Report actual values rather than calling a reference catalog balanced.
8. Run `uv run python -m tools check` and relevant final data/distribution/balance commands. Add the new required deterministic audits to the fitting gate where appropriate. Prove Godot tests imported/executed and exited successfully; missing binaries, skipped tests or partial reports are unresolved acceptance, not success.

Use appropriate tests for these data, progression, transaction and save risks; do not add redundant tests of display labels. Broaden testing only for new failures or unresolved integration concerns.

Final report: material behavior/ADR changes, source-to-realm coverage, commands and actual execution results, playable verification, migrations and remaining genuine limitations. Do not claim completion of broad world simulation or unrelated item features. The requested outcome is a usable 30-realm Mind/Thức Hải/Meridian progression system that enriches the current architecture and acquisition loop.
