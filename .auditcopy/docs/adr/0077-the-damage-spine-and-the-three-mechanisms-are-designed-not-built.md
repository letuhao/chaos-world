# 0077 The damage spine and the three mechanisms are designed, not built

- Status: Accepted
- Date: 2026-10-03
- Supersedes: ADR 0067 (one spine one seam), ADR 0068 (the defensive vocabulary),
  ADR 0069 (qi damage is an elemental share), ADR 0070 (body damage is flat subtraction),
  ADR 0071 (mind damage erodes the sea)
- Consistent with: BL-0209, BL-0221, BL-0222, DEF-0090, DEF-0095

## Context

Five Accepted ADRs describe a damage system in the present tense: an 11-stage spine, a
`contracts/damage_mechanism.gd` seam returning a `DamageProposal`, one mechanism per cultivation
path, a `CombatTuning` Resource holding every tuning literal, and a contract-test suite. A future
agent reading any of them would build against those classes.

**None of them exists.** Measured across `game/` and `tools/` (14276 files, every `.gd`, `.tres`,
`.tscn`, `.json`, `.jsonl`, `.py`):

| Symbol ADR 0067/0068/0069/0070/0071 name | Hits in `game/` + `tools/` |
|---|---|
| `damage_mechanism` / `DamageMechanism` | 0 |
| `DamageProposal` | 0 |
| `CombatTuning` | 0 |
| `combat_damage` (the `.tres`) | 0 |
| `RESIST_DIVISOR`, `RESIST_CAP` | 0 |
| `BodyDamageProfile`, `MindDamageProfile` | 0 |
| `resolve_location`, `point_multiplier`, `aim_meridian` | 0 |
| `BLOCKED_MULT`, `BROAD_MULT`, `WOUND_THRESHOLD`, `NECROSIS_*` | 0 |
| `element_share` | 0 |

- `game/src/modules/combat/` holds exactly two scripts: `api.gd` and `shield.gd`. No spine file,
  no `mechanism_slot.gd`, no band roll, no tuning resource.
- `game/tests/modules/combat/` and `game/tests/contracts/` **do not exist**. ADR 0068's four
  band/reflection property tests and ADR 0067's per-mechanism contract tests have no directory.
- `combat`'s declared deps are `[contracts, core]`. ADR 0069 states `"elements"` is *also* added
  to them "so the registry does not lie about an edge that exists"; no such edge exists.

## Decision

**The five designs stand as designs. Their status is unimplemented, and that is the ruling.**

- `modules/combat/` is two files. `api.gd` exposes `attach_shield` / `shield` and nothing else —
  which is exactly what ADR 0067 and ADR 0056 already said, and still true. `shield.gd` is a
  standalone `capacity/toughness/pen/regen` record; nothing calls `absorb()`.
- Every ADR that names a constant, a Resource, or a test as *existing* is describing work to do.
  Read `CombatTuning`, `BodyDamageProfile`, `MindDamageProfile`, `element_share`, `RESIST_DIVISOR`,
  the band roll and the necrosis thresholds as a specification, not as a symbol to call.
- **The arithmetic in those ADRs is not wasted and must not be re-derived by the next agent.**
  ADR 0069's tier-1 row mean of exactly `0.950000` and its `3.0x`-vs-`2.0x` spread proof, ADR
  0070's `0.25 == one failed breakthrough's worth`, and ADR 0071's `100 -> 825` sea capacity are
  all still checkable against the shipped data (`game/data/body_cultivation/acupoints`: 60 defs;
  `MindRealmSeed.sea_capacity`: `qi_refining.tres` 100.0, `primordial_origin.tres` 825.0).
- **What does exist, and is what a mechanism will read:** `ElementRules` with
  `NEUTRAL 1.0 / STRONG 1.5 / WEAK 0.5 / NOURISH 0.75` and `weak_against(id)`
  (`modules/elements/rules.gd:6-9,44`); `ElementProvider.contribute` emitting
  `element_power_<e>` and `element_resistance_<e>` (`modules/elements/provider.gd:15-24`);
  `MeridianState.STATE_ORDER` and `state_rank()` (`core/meridian_state.gd:15,45`);
  `damage_meridian` / `repair_meridian` (`core/meridian_network.gd:90,98`);
  `SeaOfConsciousness.effective_capacity() = structural_capacity * (1.0 - turbulence * 0.5)`
  (`modules/mind_cultivation/sea_of_consciousness.gd:27`).

## Consequences

- `Actor.SCHEMA_VERSION` is **4**. ADR 0070's "4 -> 5 so wounds persist" describes a migration that
  has not happened; there is no wound severity in the payload.
- ADR 0071's BL-0114 verdict never landed: `MindStats.CRITICAL_CHANCE` / `DODGE_CHANCE` still emit
  `critical_chance` / `dodge_chance` (`modules/mind_cultivation/provider.gd:39-40`, pinned by
  `tests/modules/mind_cultivation/test_mind_stats.gd:22-23`), and BL-0114 is still `todo`. There is
  no `mind_deviation` `StatusEffect`.
- The `elements` tier-2 dominance ADR 0069 measured is **still live**: every entry in
  `ElementDefaults.advanced()` has empty `generates`, `lightning`/`ice`/`wind` carry two `overcomes`
  and `light`/`dark` one (`modules/elements/default_elements.gd:20-24`). No per-tier mastery
  divisor exists in `ElementProvider`.
- Build order is recorded, not invented: BL-0209 (the spine), BL-0221/BL-0222 (no damage model at
  all, `combat` 100% dead), DEF-0090 (active techniques blocked on the pipeline), DEF-0095
  (nothing anywhere damages a health pool). DEF-0078/DEF-0007/DEF-0090 are a known cycle, so the
  recorded order is not a sequence.
- An ADR claiming a class exists is not evidence it exists. The backlog says otherwise for this
  one, in BL-0209's own words: *"Accepted in docs and implemented nowhere"*.
