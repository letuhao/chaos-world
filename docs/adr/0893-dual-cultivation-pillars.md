# 0893 Dual cultivation is a mind+body sub-path with three pillars

- **Status**: accepted
- **Supersedes**: none
- **Corrects**: none

## Context

The existing dual_cultivation module at `game/src/modules/dual_cultivation/` is essentially empty — 30 strings in an array plus a stat provider. No realm seeds, no training verb, no breakthrough. The succubus path needs a real progression system.

Body and mind are the same 30-realm ladder, not two ladders. PathState.rank_id names a realm on one shared ladder; body and mind differ only in reservoir (acupoints/meridians vs. sea-of-consciousness), not in ranking.

Adding a fourth PathState.ALL entry is actively dangerous:
- `Breakthrough.owed_index` loops `actor.paths.values()` for unearned indices ≥ 18 — a fourth entry demands a second tribulation for one realm, against a single `actor.ascension` slot.
- `RaceStats` computes "open path count" as `ALL.size() - closed_paths.size()` — a fourth path makes every actor read 4/3 paths open unless all 5 races gain an entry.
- `character_creation_flow.gd:382` matches over ALL with no arm for a new id — it would silently enrol nobody.

## Decision

- **Dual cultivation is a nested sub-state on MIND** with the hard invariant `dual.rank_id == mind.rank_id`.
- It does not have its own realm ladder, its own breakthrough transaction, or its own path registration.
- The three pillars (Ngũ Cảm, Tam Tàng, Tâm Cung) share a single "dual realm" — no independent progression.
- Each pillar has its own breakthrough gate. The realm breakthrough gate still exists but requires unlocking all 3 pillar gates first.
- **No required order** — all three pillars can unlock simultaneously or in any order when the user has enough condition.
- The succubus has no stages within realms (unlike other systems). The three pillars ARE the stages.
- Emotional energy (Tâm Nguyên) is **active** — requires interaction and action to grant, not passive generation.

## State Structure

**File:** `game/src/modules/dual_cultivation/dual_state.gd`

```gdscript
class_name DualState
extends RefCounted

var rank_id: StringName          # mirrors mind.rank_id (hard invariant)
var active: bool = false          # is dual cultivation currently active
var partner_id: StringName = &"" # resonance partner actor id
var tam_nguyen: float = 0.0       # active emotional energy (0-200)

# Pillar 1: Ngũ Cảm — 5 senses × 4 stages (0=physical, 1=qi, 2=meridian, 3=realm)
var senses: Dictionary = {       # sense_id -> stage int
    "skin": 0, "eyes": 0, "tongue": 0, "ears": 0, "nose": 0
}

# Pillar 2: Tam Tàng — 3 palaces × 3 levels (0=sealed, 1=awakened, 2=refined, 3=perfected)
var palaces: Dictionary = {      # palace_id -> level int
    "am_cung": 0, "hau_phu": 0, "nu_tang": 0
}

# Pillar 3: Tâm Cung — 7 hearts × 2 states (0=locked, 1=awakened)
var hearts: Dictionary = {       # heart_id -> state int
    "hy": 0, "no": 0, "ai": 0, "cu": 0, "ai_love": 0, "duc": 0, "tinh": 0
}

# Pillar gates — unlocked flags
var pillar_gates: Dictionary = {
    "ngu_cam": false, "tam_tang": false, "tam_cung": false
}
```

Stored as actor module data under key `&"dual_cultivation_state"`. The `rank_id` is synchronized from `mind.rank_id` on every mind breakthrough resolution — never set independently.

## Facade API

**File:** `game/src/modules/dual_cultivation/api.gd` (extend existing)

```gdscript
# --- Lifecycle ---
static func enter_dual(actor: Actor, partner_id: StringName = &"") -> bool
static func exit_dual(actor: Actor) -> bool
static func is_dual_active(actor: Actor) -> bool
static func state(actor: Actor) -> DualState

# --- Pillar verbs ---
static func train_sense(actor: Actor, sense_id: StringName) -> bool
static func upgrade_palace(actor: Actor, palace_id: StringName) -> bool
static func awaken_heart(actor: Actor, heart_id: StringName) -> bool

# --- Gates ---
static func pillar_gate_status(actor: Actor, pillar_id: StringName) -> Dictionary
static func all_gates_unlocked(actor: Actor) -> bool

# --- Resonance ---
static func resonance_status(actor: Actor) -> Array[Dictionary]
static func activate_resonance(actor: Actor, combo_id: StringName) -> bool

# --- Tâm Nguyên ---
static func grant_tam_nguyen(actor: Actor, amount: float, source: StringName) -> void
static func tam_nguyen(actor: Actor) -> float

# --- Read ---
static func summary(actor: Actor) -> Dictionary
```

## Pillar 1: Ngũ Cảm (Five Senses)

**File:** `game/src/modules/dual_cultivation/sense.gd`

| Sense | ID | Stage 0 | Stage 1 | Stage 2 | Stage 3 |
|---|---|---|---|---|---|
| Skin | `skin` | Physical touch | Sense qi flow | Sense meridians | Sense realm boundaries |
| Eyes | `eyes` | Physical sight | Observe spiritual power | See emotions | See through illusions |
| Tongue | `tongue` | Physical taste | Analyze substances | Detect poison/medicine | Taste spiritual energy |
| Ears | `ears` | Physical hearing | Hear sound laws | Hear vibrations | Hear heart-sounds |
| Nose | `nose` | Physical smell | Track by scent | Sense life force | Sense aura |

**Training costs (Tâm Nguyên):**

| Transition | Cost |
|---|---|
| Stage 0→1 | 20 |
| Stage 1→2 | 40 |
| Stage 2→3 | 80 |

**Gate requirement:** All 5 senses ≥ Stage 2 (Sense Meridians).

## Pillar 2: Tam Tàng (Three Palaces)

**File:** `game/src/modules/dual_cultivation/palace.gd`

| Palace | ID | Function | Level 1 | Level 2 | Level 3 |
|---|---|---|---|---|---|
| Âm Cung | `am_cung` | Mị Nguyên — main energy | Awakened | Refined | Perfected |
| Hậu Phủ | `hau_phu` | U Nguyên — absorb/transform | Awakened | Refined | Perfected |
| Nhũ Tàng | `nu_tang` | Sinh Nguyên — life force | Awakened | Refined | Perfected |

**Upgrade costs (Tâm Nguyên + essence):**

| Transition | TN Cost | Essence Cost |
|---|---|---|
| Level 0→1 | 30 | 10 |
| Level 1→2 | 60 | 20 |
| Level 2→3 | 120 | 40 |

**Gate requirement:** All 3 palaces ≥ Level 2 (Refined).

## Pillar 3: Tâm Cung (Seven Hearts)

**File:** `game/src/modules/dual_cultivation/heart.gd`

| Heart | ID | Effect when awakened |
|---|---|---|
| Hỷ Tâm (Joy) | `hy` | +10% recovery speed |
| Nộ Tâm (Anger) | `no` | +8% power burst |
| Ai Tâm (Sorrow) | `ai` | +12% mental endurance |
| Cụ Tâm (Fear) | `cu` | +10% danger intuition |
| Ái Tâm (Love) | `ai_love` | +10% bonding/empathy |
| Dục Tâm (Desire) | `duc` | +8% motivation (general desire, NOT sexual) |
| Tĩnh Tâm (Calm) | `tinh` | Control over all other hearts |

**Awakening cost:** 50 Tâm Nguyên each.

**Gate requirement:** ≥ 5 of 7 hearts awakened, **including Tĩnh Tâm** (calm is the anchor — without it, the other six are unstable).

## Pillar Gates and Realm Breakthrough Integration

**File:** `game/src/modules/dual_cultivation/pillar_gate.gd`

The three pillar gates are **additional clauses** in `MindBreakthroughCondition.can_breakthrough()`. The existing mind breakthrough transaction (preview → start → resolve_attempt) is unchanged; the pillar gates are AND-ed into the existing condition check.

```gdscript
# In MindBreakthroughCondition.can_breakthrough(), add:
and DualCultivationApi.all_gates_unlocked(actor)
```

**No required order** — all three pillars can be trained simultaneously or in any order. The gates are independent per-pillar but all three must be true for the realm breakthrough.

**On mind breakthrough success:** `dual.rank_id` is synchronized to the new `mind.rank_id`. Pillar progress is **not reset** — senses, palaces, and hearts persist across realms.

## Active Tâm Nguyên Generation

**File:** `game/src/modules/dual_cultivation/tam_nguyen.gd`

Tâm Nguyên is **active-only** — no passive generation. It is granted by specific interactions:

| Interaction | TN Granted |
|---|---|
| Combat victory | +10 |
| Combat defeat | +5 |
| Cultivating with partner | +15 |
| Meditating with partner | +20 |
| Quest completion | +12 |
| Training a sense/palace/heart | −cost (sink) |

**Cap:** 200 maximum.

**Decay:** If no active interaction for 7 in-game days, TN decays 10% per day. This forces continued engagement.

**Yin-yang:** TN is the universal sink for all dual progression. You cannot max all three pillars without active play.

## Cộng Minh (Resonance) Combinations

**File:** `game/src/modules/dual_cultivation/resonance.gd`

Resonance combinations are **passive and automatic** when their prerequisites are met. They require an active `partner_id` (resonance partner). No activation cost — the cost is the prerequisite levels.

| # | Combination | Prerequisite | Bonus |
|---|---|---|---|
| 1 | Mị Nhãn + Cụ Tâm | Eyes ≥ 3, Fear awakened | +15% evasion vs ambushes |
| 2 | Linh Nhĩ + Ai Tâm | Ears ≥ 3, Sorrow awakened | +20% dialogue insight |
| 3 | Mị Bì + Tĩnh Tâm | Skin ≥ 3, Calm awakened | +10% dodge |
| 4 | Nhũ Tàng + Hỷ Tâm | Nhũ Tàng ≥ 2, Joy awakened | +25% recovery speed |
| 5 | Âm Cung + Ái Tâm | Âm Cung ≥ 2, Love awakened | +15% partner synergy |
| 6 | Hậu Phủ + Nộ Tâm | Hậu Phủ ≥ 2, Anger awakened | +10% power when corrupted |
| 7 | Linh Thiệt + Dục Tâm | Tongue ≥ 3, Desire awakened | +20% poison resistance |
| 8 | Linh Tỵ + Cụ Tâm | Nose ≥ 3, Fear awakened | +15% tracking |
| 9 | Mị Nhãn + Ái Tâm | Eyes ≥ 3, Love awakened | +20% illusion resist |
| 10 | Linh Nhĩ + Tĩnh Tâm | Ears ≥ 3, Calm awakened | +10% combat prediction |
| 11 | Nhũ Tàng + Ai Tâm | Nhũ Tàng ≥ 2, Sorrow awakened | +15% willpower |
| 12 | Âm Cung + Tĩnh Tâm | Âm Cung ≥ 2, Calm awakened | +10% cultivation speed |

## Hybrid Stat Resolver

**File:** `game/src/modules/dual_cultivation/provider.gd` (extend existing)

The existing `DualCultivationProvider.contribute()` is extended to read the dual state and contribute:

- **Dual cultivation speed bonus:** +10% when all 3 pillar gates unlocked
- **Distraction penalty:** −20% mind cultivation speed while dual is active
- **Resonance modifiers:** Each active resonance contributes its stat modifier
- **Corruption interaction:** Dục Tâm resonance adds +5 corruption per use; corruption > 50% reduces TN generation by 25%

The hybrid resolver is **additive** on top of the existing body + mind stat contributions. It does not replace them.

## Yin-Yang Counterparts

| Advantage | Counterpart |
|---|---|
| +10% cultivation speed (all gates) | −20% mind cultivation speed while dual active |
| Resonance bonuses (12 combos) | Requires partner — solo cultivators get nothing |
| Active TN generation (up to +20/session) | TN decays 10%/day after 7 days inactive |
| Pillar progress persists across realms | Failed mind breakthrough damages a random sense/palace |
| Dục Tâm: +8% motivation | Each use adds +5 corruption; high corruption reduces TN generation |
| Heart awakening: permanent stat boost | Tĩnh Tâm gate requirement forces Calm before power |

## Consequences

- The dual_cultivation module becomes a real progression system, not a read-only derivation.
- The succubus path has a full pillar system with authored content.
- The realm rate is ONE shared curve — no `pow(`, no `RATE_STEP` const, no ladder reads in provider.
- The hard constraint `dual.rank_id == mind.rank_id` is enforced by synchronization, not by convention.
- Tâm Nguyên is active-only — no idle generation, no time-based accrual.
- Resonance requires a partner — solo cultivators get nothing.
- Pillar gates are AND-ed into mind breakthrough — non-optional.
- Dục Tâm is general desire, not sexual content. All text is clinical and mechanical.
