# 0896 Collection is a read-only module that pays narrative rewards

- **Status**: accepted
- **Supersedes**: none
- **Corrects**: none

## Context

The program spans: race (heterosis), bloodline, clan, wife/husband collections, relationship system, social interactive enhancement, and dual cultivation. The collection layer is the expression of "collect enough → get rewarded" — a collection game feel.

The reward path doesn't need a new ADR — `QuestDef.GRANT_KINDS` is closed at `[fate, destiny, item]`, but you can pay a dual reward as `GRANT_FATE` with a dual-specific source string, reusing the existing shape. No fourth grant kind.

## Decision

- **Collection is a new module** at `game/src/modules/collection/` that reads from existing modules (`social`, `dual_cultivation`, `fertility`, `destiny`) and tracks collection progress.
- It pays rewards through the existing quest grant system (`GRANT_FATE` with source `"collection:<tier_id>"`).
- The UI screens are pure consumers of facades, following the established `UiScreen` pattern.
- No existing module is modified.
- **Collection rewards are narrative, not power.** Fates are narrative rewards (new story content, new dialogue options), not power rewards. This preserves the yin-yang: collecting partners does not make you stronger, it opens narrative doors.

## Module Structure

**New module**: `game/src/modules/collection/`

**Facade**: `game/src/modules/collection/api.gd`

```gdscript
class_name CollectionApi
extends RefCounted

# The collection state for an actor: partners, bond classes, dual cultivation milestones, heterosis
static func summary(actor: Actor) -> Dictionary

# Record a collection event and return the new state
static func record_event(actor: Actor, event_type: StringName, partner_id: StringName = &"") -> Dictionary

# Claim a tier reward. Returns {ok, reason, fate_id}
static func claim_tier(actor: Actor, tier_id: int) -> Dictionary

# The heterosis status for an actor
static func heterosis_status(actor: Actor) -> Dictionary

# The relationship history for an actor
static func history(actor: Actor) -> Array[Dictionary]
```

**What it tracks** (all read from facades, never stored):
- Partners collected: `SocialApi` bonds at `CONFIDANT` or above
- Bond classes reached: `SocialBondClass` ladder
- Dual cultivation milestones: `DualCultivationApi` pool/stats thresholds
- Heterosis: `FertilityApi` offspring lineage spike/decay

**How it pays rewards**: Through `DestinyApi.earn_fate` with source `"collection:tier_<id>"`. No new ADR needed — `QuestDef.GRANT_KINDS` is closed at `[fate, destiny, item]` and the source string is the namespace.

**Module dependencies**: `collection` → `social`, `dual_cultivation`, `fertility`, `destiny` (all through facades). No cycles.

## UI Screens

### RelationshipScreen
**File**: `game/src/ui/screens/relationship_screen.gd`
**Class**: `RelationshipScreen extends UiScreen`

Shows: list of partners, bond class, emotional signature, history log. The emotional signature is a derived label from the bond's axes (standing band + trust band + dominant cause kind) — e.g. "devoted warrior", "cunning ally", "distant lover" — computed in the collection module, not the screen.

**Verbs**: `select_partner`, `view_history`

**summary() contract**:
```gdscript
{
    "actor": String,
    "read_only": false,
    "partner_count": int,
    "partners": Array[Dictionary],  # each partner's summary from PartnerRow
    "selected_partner": String,      # partner id or ""
    "selected_bond_class": String,
    "selected_emotional_signature": String,
    "history": Array[Dictionary],    # {date, event_type, partner_id, detail}
    "actions": Array[String],
    "enabled": Dictionary,
}
```

### DualCultivationScreen
**File**: `game/src/ui/screens/dual_cultivation_screen.gd`
**Class**: `DualCultivationScreen extends UiScreen`

Shows: three pillars (Essence, Desire, Harmony), breakthrough gates, resonance combinations, active partner. The three pillars map to existing `DualCultivationStats`: Essence (capacity/regen/drain), Desire (charm/allure/desire pool), Harmony (yin/yang balance/deviation risk). Resonance combinations are derived from the active partner's yin/yang balance against the actor's — computed in the collection module.

**Verbs**: `start_session`, `end_session`, `attempt_breakthrough`

**summary() contract**:
```gdscript
{
    "actor": String,
    "read_only": false,
    "pillars": Array[Dictionary],   # three pillars from PillarRow
    "gates": Array[Dictionary],     # {gate_id, name, threshold, current, open}
    "resonances": Array[Dictionary], # {combo_id, name, partner_yin_yang, actor_yin_yang, effect}
    "active_partner": String,       # partner id or ""
    "can_start": bool,
    "can_breakthrough": bool,
    "actions": Array[String],
    "enabled": Dictionary,
}
```

### CollectionScreen
**File**: `game/src/ui/screens/collection_screen.gd`
**Class**: `CollectionScreen extends UiScreen`

Shows: 12 reward tiers, current progress, claimed status. Read-only except for the claim verb.

**Verbs**: `claim_tier`

**summary() contract**:
```gdscript
{
    "actor": String,
    "read_only": false,
    "tier_count": int,
    "tiers": Array[Dictionary],      # each tier from CollectionTierRow
    "current_progress": int,        # total collection points
    "next_tier": int,               # next unclaimed tier id, 0 if all claimed
    "actions": Array[String],
    "enabled": Dictionary,
}
```

### HeterosisScreen
**File**: `game/src/ui/screens/heterosis_screen.gd`
**Class**: `HeterosisScreen extends UiScreen`

Shows: heterosis status, spike magnitude, decay rate, carrier state. Read-only.

**summary() contract**:
```gdscript
{
    "actor": String,
    "read_only": true,
    "has_heterosis": bool,
    "spike_magnitude": float,
    "decay_rate": float,
    "carrier_state": bool,
    "generation": int,
    "lineage": Array[Dictionary],   # {generation, spike, expressed, partner_race}
}
```

## UI Panels

### PartnerRow
**File**: `game/src/ui/panels/partner_row.gd`
**Class**: `PartnerRow extends PanelContainer`

Shows one partner: name, bond class, emotional signature, standing, trust. Formats all numbers here, not in the screen.

**summary() contract**:
```gdscript
{
    "partner_id": String,
    "display_name": String,
    "bond_class": String,
    "emotional_signature": String,
    "standing": float,
    "trust": float,
    "is_active": bool,
    "card_tone": StringName,  # "PartnerCard" or "LockedCard"
}
```

### PillarRow
**File**: `game/src/ui/panels/pillar_row.gd`
**Class**: `PillarRow extends PanelContainer`

Shows one dual cultivation pillar: name, current value, maximum, stage (1–4).

**summary() contract**:
```gdscript
{
    "pillar_id": String,
    "display_name": String,
    "current": float,
    "maximum": float,
    "stage": int,
    "stage_count": int,
    "progress": float,  # 0.0 to 1.0
}
```

### CollectionTierRow
**File**: `game/src/ui/panels/collection_tier_row.gd`
**Class**: `CollectionTierRow extends PanelContainer`

Shows one collection tier: tier number, threshold, reward fate id, claimed status.

**summary() contract**:
```gdscript
{
    "tier_id": int,
    "threshold": int,
    "reward_fate": String,
    "claimed": bool,
    "can_claim": bool,
    "progress": float,  # 0.0 to 1.0
}
```

### HeterosisStatusRow
**File**: `game/src/ui/panels/heterosis_status_row.gd`
**Class**: `HeterosisStatusRow extends PanelContainer`

Shows heterosis status: spike magnitude, decay rate, carrier state, generation.

**summary() contract**:
```gdscript
{
    "has_heterosis": bool,
    "spike_magnitude": float,
    "decay_rate": float,
    "carrier_state": bool,
    "generation": int,
}
```

## Collection Framing

**What's tracked** (collection points):
- Each partner at CONFIDANT+: 1 point
- Each bond class reached (FRIEND, CONFIDANT, SWORN): 1 point each
- Each dual cultivation pillar stage (2, 3, 4): 1 point each
- Heterosis carrier: 2 points
- Heterosis expressed: 3 points

**Reward thresholds** (12 tiers):
| Tier | Requirement | Reward |
|------|-----------|--------|
| 1 | 1 partner | fate `collection:tier_1` |
| 2 | 3 partners | fate `collection:tier_2` |
| 3 | 5 partners | fate `collection:tier_3` |
| 4 | 1 partner at FRIEND | fate `collection:tier_4` |
| 5 | 3 partners at FRIEND | fate `collection:tier_5` |
| 6 | 1 partner at CONFIDANT | fate `collection:tier_6` |
| 7 | 3 partners at CONFIDANT | fate `collection:tier_7` |
| 8 | 1 partner at SWORN | fate `collection:tier_8` |
| 9 | Pillar stage 2 (any) | fate `collection:tier_9` |
| 10 | Pillar stage 3 (any) | fate `collection:tier_10` |
| 11 | Heterosis carrier | fate `collection:tier_11` |
| 12 | All above | fate `collection:tier_12` |

**Rewards**: Each tier pays a fate through `DestinyApi.earn_fate` with source `"collection:tier_<id>"`. Fates are narrative rewards (new story content, new dialogue options), not power rewards. This preserves the yin-yang: collecting partners does not make you stronger, it opens narrative doors.

## Yin-Yang Counterparts

**Cost of collecting**:
- Time and attention spent on relationships is time not spent on solo cultivation
- Each partner requires maintenance — `SocialApi.tick` decays standing, so neglected partners drop bond classes
- Dual cultivation sessions cost essence and risk corruption (`DualCultivationStats.ESSENCE_DRAIN`, `CORRUPTION`)

**Cost of dual cultivation**:
- Essence drain during sessions
- Corruption accumulation reduces purity (`DualCultivationStats.PURITY = 1.0 - corruption`)
- Deviation risk if yin/yang balance is lost (`DualCultivationStats.DEVIATION_RISK`)

**Cost of heterosis**:
- Outbred spike decays over generations (each generation loses 50% of spike)
- Carrier state means the trait is carried but not expressed — the player must actively seek outbred partners to express it
- Opportunity cost of seeking outbred partners vs. same-lineage partners (same-lineage preserves bloodline purity, which has its own rewards)

**No strict best response**:
- Collecting partners is not strictly better than solo cultivation — partners require maintenance and the rewards are narrative, not power
- Dual cultivation is not strictly better than solo cultivation — it costs essence and risks corruption
- Heterosis is not strictly better than pure lineage — the spike decays and the carrier state has an opportunity cost

## Consequences

- The collection layer reads from facades on every call, never caches — no drift from source modules.
- UI screens render; the module decides — no screen owns game rules.
- Every pool is clamped through `RowBudget.cap()` — no unbounded row growth.
- Collection rewards are narrative, not power — no strict best response.
- Emotional signature is derived from axes, not stored — no drift when axes change.
- No explicit sexual content — all text is clinical and mechanical.
