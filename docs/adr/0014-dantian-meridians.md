# 0014 Dantian and meridian system (Đan Điền + Mạch)

- Status: Draft
- Date: 2026-10-02

## Context

ADR 0011 established Qi Cultivation with a `qi` pool, `qi_purity`, and a `dantian_capacity` base attribute — but left the storage mechanism and channel network undefined. ADR 0005 unified all paths on a 30-realm ladder (Mortal 1-9, Spirit 10-18, Immortal 19-27, Transcendent 28-30). The game needs a concrete qi storage model (Dantian) and a shared channel network (Meridians) that all three cultivation systems (ADR 0011/0012/0013) use. This ADR covers mortal + spirit tiers (realms 1-18); immortal/transcendent reserved for later ADRs.

## Decision

### Đan Điền (Dantian) — Qi Storage

- **Three tiers** aligned to the shared ladder (ADR 0005):
  - **Lower Dantian** (下丹田) — realms 1-9 (Mortal): stores basic qi; capacity scales with realm.
  - **Middle Dantian** (中丹田) — realms 10-18 (Spirit): stores refined qi; unlocks at Spirit tier.
  - **Upper Dantian** (上丹田) — reserved for Immortal/Transcendent (future ADR).
- **Capacity**: `dantian_capacity` base attribute (ADR 0011) is the Lower Dantian cap. Middle Dantian cap = `dantian_capacity * realm_multiplier * 2`. Breakthrough requires the active dantian full.
- **Quality** (0-1): affects `qi_purity` (ADR 0011) and technique effectiveness. Improved by body cultivation (ADR 0012), pills, and successful breakthroughs.
- **Damage**: failed breakthroughs reduce effective capacity by 25% until healed (pill or rest). Damage does not lower `dantian_capacity` base — it applies a temporary modifier.

### Mạch (Meridians) — Shared Channel Network

- **20 meridians** in two groups:
  - **12 Primary** (十二經脈): Lung, Large Intestine, Stomach, Spleen, Heart, Small Intestine, Bladder, Kidney, Pericardium, Triple Burner, Gallbladder, Liver.
  - **8 Extraordinary** (奇經八脈): Du Mai, Ren Mai, Chong Mai, Dai Mai, Yin Qiao, Yang Qiao, Yin Wei, Yang Wei.
- **States**: Closed → Open → Expanded → Strengthened. Damaged is a modifier on any state (-50% flow until healed).
- **Unlock progression** (mortal + spirit tiers):
  - Realms 1-3: 4 primary (Lung, Large Intestine, Stomach, Spleen).
  - Realms 4-6: 4 primary (Heart, Small Intestine, Bladder, Kidney).
  - Realms 7-9: 4 primary (Pericardium, Triple Burner, Gallbladder, Liver).
  - Realms 10-12: 4 extraordinary (Du, Ren, Chong, Dai).
  - Realms 13-15: 2 extraordinary (Yin Qiao, Yang Qiao).
  - Realms 16-18: 2 extraordinary (Yin Wei, Yang Wei).
- **State bonuses**: Open +10% cultivation speed each; Expanded +5% capacity each; Strengthened +5% technique power each. Bonuses are additive within a state, multiplicative across states.
- **Breakthrough challenges**: each realm requires specific meridians Open (realm N requires `min(4 + floor(N/3), 12)` primary meridians open). Insufficient meridians → qi deviation risk (ADR 0011 failure path). Higher realms require Expanded state on key meridians.
- **Cross-system interactions**: body cultivation (ADR 0012) strengthens meridians (Expanded/Strengthened); mind cultivation (ADR 0013) senses through meridians (perception bonus); failed breakthroughs damage both dantian and meridians.

### Integration

- Cultivation speed = `base * (1 + meridian_open_bonus) * realm_multiplier` (ADR 0011 `QiProvider` reads meridian state via facade).
- Breakthrough requires: full dantian + required meridians Open + comprehension ≥ threshold + pill (ADR 0011).
- Failed breakthrough: dantian damage (capacity -25%) + 1-3 random meridians Damaged.
- Meridians are shared across all 3 systems — owned by `qi_cultivation` module (ADR 0017 defines the network), exposed via `api.gd` facade for all modules to read. Body cultivation (ADR 0015) can mutate meridian state (expand/strengthen/repair); mind cultivation (ADR 0016) reads only.

## Consequences

- Extends `qi_cultivation` module (ADR 0011) — no `core/` or `contracts/` changes.
- `dantian_capacity` base attribute (ADR 0011) is the anchor; Middle Dantian derives from it.
- Meridian state is data-driven (`.tres`); adding/renaming meridians is authoring, not code.
- Breakthrough failure now has two recovery tracks: heal dantian (pills/rest) and repair meridians (pills/specific techniques).
- ADR 0015 (Body/Huyệt) and ADR 0016 (Mind/Thức Hải) read meridian state via `qi_cultivation/api.gd` — no direct module-to-module references.
- Meridian unlock is tied to realm (ADR 0005), so realm-up automatically opens new meridians; player chooses which to Expand/Strengthen.
- Shared meridian network means body/mind cultivation investments benefit qi progression and vice versa — cross-system synergy is emergent, not hardcoded.
