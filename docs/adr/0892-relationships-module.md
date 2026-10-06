# 0892 Relationships is a standalone module

- **Status**: accepted
- **Supersedes**: none
- **Corrects**: none

## Context

The social system at `game/src/modules/social/` tracks bonds as `{id: float}` — a bare standing value with no history, no emotional signature, and no dual cultivation partner tracking. The dual cultivation sub-path needs partner tracking, emotional signatures, and history. The collection layer needs to read relationship data for wife/husband collections.

The program spans: race (heterosis), bloodline, clan, wife/husband collections, relationship system, social interactive enhancement, and dual cultivation. Relationships is the foundation that serves dual cultivation partner tracking and the collection layer.

## Decision

- **Relationships is a new standalone module** at `game/src/modules/relationships/` with a facade API.
- It tracks all dual cultivation history and relationships **as a log** — frequent partners increase relationship and can take advantages.
- It reads bond data from `social/` (via facade) but maintains its own richer per-partner state: a 7-axis emotional signature, a bounded interaction history, a dual cultivation partner flag, and frequent-partner advantages.
- It is **compositional** — it does not duplicate `SocialBond`'s standing/trust axes, only reads them through `SocialApi.bond_entry()` and layers relationship-specific state on top.
- **Registry deps**: `["contracts", "core", "social", "dual_cultivation"]` — reads bond class from `social`, reads DC stats from `dual_cultivation`.

## Module Structure

```
game/src/modules/relationships/
  api.gd                        # Facade — 12 public methods
  relationship_state.gd         # Per-actor state (module_data key)
  relationship_entry.gd         # Per-NPC relationship row
  emotional_signature.gd        # 7-emotion vector
  interaction_log.gd            # Bounded history per partner
  relationship_type.gd          # Enum: NONE, FRIEND, ROMANTIC, SPOUSE, DC_PARTNER
  frequent_partner.gd           # Advantage calculation
  dual_cultivation_tracker.gd   # DC-specific history per partner
  stats.gd                      # Module-owned stat ids
  provider.gd                   # StatProvider for relationship stats
```

**Contract**: `game/src/contracts/relationship_events.gd` — typed signals:
- `relationship_started(actor_id, partner_id, type)`
- `relationship_ended(actor_id, partner_id, reason)`
- `interaction_logged(actor_id, partner_id, interaction_type)`
- `frequent_partner_reached(actor_id, partner_id)`

## Facade API (12 methods)

```gdscript
class_name RelationshipsApi

# --- Relationship lifecycle ---
static func start_relationship(actor: Actor, partner_id: StringName, type: StringName) -> Dictionary
static func end_relationship(actor: Actor, partner_id: StringName, reason: StringName) -> Dictionary
static func relationship_type(actor: Actor, partner_id: StringName) -> StringName

# --- Interaction logging ---
static func log_interaction(actor: Actor, partner_id: StringName, interaction_type: StringName, emotional_delta: Dictionary = {}) -> Dictionary
static func interaction_count(actor: Actor, partner_id: StringName) -> int

# --- Emotional signature ---
static func emotional_signature(actor: Actor, partner_id: StringName) -> Dictionary
static func emotional_energy(actor: Actor) -> float

# --- Dual cultivation tracking ---
static func mark_dual_cultivation_partner(actor: Actor, partner_id: StringName) -> Dictionary
static func is_dual_cultivation_partner(actor: Actor, partner_id: StringName) -> bool
static func dual_cultivation_history(actor: Actor, partner_id: StringName) -> Array

# --- Frequent partner advantages ---
static func frequent_partner_tier(actor: Actor, partner_id: StringName) -> int
static func frequent_partner_advantage(actor: Actor, partner_id: StringName) -> Dictionary

# --- Read model ---
static func summary(actor: Actor) -> Dictionary
static func tick(actor: Actor, delta: float) -> int
```

## Relationship State Per NPC

`RelationshipEntry` (one per partner, stored in `RelationshipState.entries`):

| Field | Type | Description |
|---|---|---|
| `partner_id` | `StringName` | NPC identifier |
| `relationship_type` | `StringName` | `NONE`, `FRIEND`, `ROMANTIC`, `SPOUSE`, `DC_PARTNER` |
| `emotional_signature` | `EmotionalSignature` | 7-axis emotion vector |
| `interaction_log` | `InteractionLog` | Last 100 interactions |
| `is_dual_cultivation_partner` | `bool` | DC partner flag |
| `dual_cultivation_history` | `Array[Dictionary]` | DC-specific records |
| `total_interactions` | `int` | Lifetime count (never decays) |
| `frequent_partner_tier` | `int` | 0=none, 1=frequent (10+), 2=close (25+), 3=intimate (50+) |
| `relationship_started_at` | `float` | World clock timestamp |
| `relationship_ended_at` | `float` | 0.0 if active |
| `end_reason` | `StringName` | Why it ended (if ended) |

## Emotional Signature

`EmotionalSignature` — a `Vector7` of emotion intensities, each in `[0.0, 1.0]`:

| Index | Emotion | Baseline | Raised by | Lowered by |
|---|---|---|---|---|
| 0 | Joy | 0.3 | gifts, shared victories, DC | betrayal, abandonment |
| 1 | Trust | 0.2 | kept promises, honesty | lies, betrayal |
| 2 | Fear | 0.1 | threats, danger | protection, safety |
| 3 | Surprise | 0.2 | unexpected acts | routine interactions |
| 4 | Sadness | 0.1 | separation, loss | reunion, gifts |
| 5 | Disgust | 0.0 | cruelty, violation | kindness, respect |
| 6 | Anger | 0.1 | betrayal, insult | apology, justice |

**Decay**: Each emotion decays toward its baseline at `0.5% per day` (driven by `tick()`). The decay is **output-bounded** — it can never push an emotion below baseline, only toward it.

**DC interaction effect**: A dual cultivation session adds `+0.15` to Joy, `+0.10` to Trust, `+0.05` to Surprise (novelty). These are **additive to the signature**, not replacements.

## Interaction Log

`InteractionLog` — bounded history per partner:

- **Capacity**: 100 interactions per NPC (oldest evicted when full — this is a **log**, not a ledger; eviction is safe because the aggregate `total_interactions` and `frequent_partner_tier` are stored separately and never evicted).
- **Each entry**: `{type: StringName, emotional_delta: Dictionary, timestamp: float, dc_session: bool}`
- **Query methods**: `entries_since(timestamp)`, `entries_by_type(type)`, `count_by_type(type)`, `dc_session_count()`
- **Decay**: Entries older than 30 days are pruned during `tick()`. Pruning is **bounded** — it iterates the fixed 100-entry array once.

## Frequent Partner Advantages

| Tier | Threshold | Advantage |
|---|---|---|
| 0 (none) | 0–9 interactions | None |
| 1 (frequent) | 10+ interactions | +10% emotional energy generation, +5% DC efficiency |
| 2 (close) | 25+ interactions | +20% emotional energy, +10% DC efficiency, unlocks `ROMANTIC` type |
| 3 (intimate) | 50+ interactions | +30% emotional energy, +15% DC efficiency, unlocks `SPOUSE` type |

**Yin-yang counterpart**: Advantages are **output-bounded** (they multiply gains, never add flat stats). The cost is **emotional energy divided among partners** — maintaining N active relationships divides emotional energy by `sqrt(N)`, so spreading attention thin yields diminishing returns. This prevents a strict best response (dating everyone).

## Dual Cultivation Partner Tracking

`DualCultivationTracker` — per-partner DC history:

- **Flag**: `is_dual_cultivation_partner` set on first DC session with that partner.
- **History entries**: `{technique_id: StringName, essence_transferred: float, harmony_achieved: float, timestamp: float, partner_bond_class: StringName}`
- **Query**: `dual_cultivation_history()` returns all entries; `dc_session_count()` returns total sessions.
- **DC efficiency bonus**: `frequent_partner_advantage()` returns a multiplier applied to `DualCultivationStats.DUAL_CULTIVATION_RATE` when the partner is a DC partner. This is a **rate multiplier**, not a flat add — it scales with the shared realm rate, never replaces it.

## Yin-Yang Counterparts

| Advantage | Counterpart |
|---|---|
| Frequent partner DC efficiency bonus | Emotional energy divided by `sqrt(N)` among N active partners |
| Emotional energy generation | Decays 0.5%/day toward baseline; neglected partners lose energy faster |
| DC partner flag (unlocks techniques) | Relationship can be ended; ended DC partners retain history but lose active advantages |
| Multiple relationship types | Max 5 active `ROMANTIC`/`SPOUSE`, max 10 `DC_PARTNER` — hard caps prevent spam |
| Joy/Trust increase from DC | Sadness/Anger increase on relationship end (−0.2 Sadness, −0.15 Anger for 7 days) |

**Relationship end**: When `end_relationship()` is called, the entry is marked ended (not deleted — history is preserved). The emotional signature shifts: Sadness +0.2, Anger +0.15, decaying over 7 days. The DC partner flag is **cleared** (you are no longer an active DC partner), but `dual_cultivation_history()` retains all past sessions.

## Stats Owned

```gdscript
class_name RelationshipsStats
const EMOTIONAL_ENERGY := &"relationship_emotional_energy"      # float, [0, 100]
const ACTIVE_RELATIONSHIPS := &"relationship_active_count"       # int
const DC_PARTNER_COUNT := &"relationship_dc_partner_count"       # int
const HIGHEST_TIER := &"relationship_highest_tier"               # int
```

`RelationshipsProvider` extends `StatProvider`, reads `RelationshipState` from the actor's component slot, contributes these four stats.

## Persistence

- `RelationshipState` rides `actor.module_data[&"relationship_state"]` — same pattern as `SocialState`, `PursuitLedger`, `ConsentLedger`.
- `RelationshipState.to_dict()` / `from_dict()` — versioned schema (`SCHEMA_VERSION := 1`).
- Every mutating verb calls `_persist(state, actor)` immediately — same pattern as `SocialApi._persist`.
- `tick(actor, delta)` is called from the same driver that calls `SocialApi.tick` — decays emotional signatures, prunes old log entries, returns count of entries that moved.

## Content Safety

All mechanics are **clinical and mechanical**. The emotional signature is a numeric vector, not prose. Dual cultivation history records technique IDs and numbers, not descriptions. No explicit content is authored, stored, or displayed. The module tracks **that** a session happened and **what it produced**, never what occurred during it.

## Consequences

- The social system's `Actor.relationships` becomes a real system, not a bare `{id: float}`.
- Dual cultivation has a partner tracking foundation.
- The collection layer can read relationship data for wife/husband collections.
- The module is compositional — it reads `social/` bonds, never writes them.
- The 100-entry log cap and 30-day prune are hard limits — a log that grows without bound is the 67 GB crash shape.
- Frequent partner bonuses are **rate multipliers**, never flat adds — a flat add is a second stat composer (ADR 0084 violation).
