# 0017 Meridian network system (Mạch)

- Status: Draft
- Date: 2026-10-02

## Context

ADR 0011/0012/0013 define three cultivation systems (Qi, Body, Mind) that each store energy in a different reservoir (Đan Điền, Huyệt, Thức Hải). All three rely on **Mạch** (meridians) — energy channels that surround the body and accelerate progression. ADR 0014/0015/0016 define how each reservoir interacts with meridians, but the shared network itself — its structure, states, unlock progression, and cross-system rules — needs a single definition so all three systems build on the same foundation.

## Decision

### Structure

- **12 Primary Meridians** (十二經脈) — main channels; unlock progressively through Mortal tier (realms 1-9).
- **8 Extraordinary Meridians** (奇經八脈) — special channels; unlock through Spirit tier (realms 10-18).
- Meridian definitions are data (`MeridianDef` Resource): `id`, `name`, `type` (primary/extraordinary), `tier` (required realm to unlock), `capacity_bonus`, `flow_bonus`, `power_bonus`.

### States (per meridian)

| State | Effect |
|---|---|
| **Closed** (閉塞) | Not yet opened; no energy flow |
| **Open** (打通) | Energy flows; grants `flow_bonus` (+% cultivation speed) |
| **Expanded** (拓寬) | Wider channel; grants `capacity_bonus` (+% storage) and increased flow |
| **Strengthened** (強化) | Reinforced; grants `power_bonus` (+% technique power) |
| **Damaged** (損傷) | From failed breakthroughs; −% all bonuses until healed |

State transitions: Closed → Open → Expanded → Strengthened (forward only). Any state → Damaged (on failed breakthrough). Damaged → Open (on repair).

### Unlock progression

- Realms 1-3: 4 primary meridians unlockable
- Realms 4-6: 4 more primary meridians
- Realms 7-9: last 4 primary meridians
- Realms 10-12: 4 extraordinary meridians
- Realms 13-15: 2 more extraordinary meridians
- Realms 16-18: last 2 extraordinary meridians

### Cross-system interactions

1. **Qi flows through meridians** → faster qi cultivation, stronger qi techniques (ADR 0014).
2. **Body essence strengthens meridians** → higher capacity, body technique power (ADR 0015).
3. **Mind power senses through meridians** → perception, spiritual sense range (ADR 0016).
4. **Meridian damage penalizes all 3 systems** → cultivation speed and technique power reduced network-wide.
5. **Body cultivation repairs meridians** → unique recovery mechanism (pills or natural healing also work).

### Breakthrough integration

- Each realm breakthrough requires specific meridians in Open/Expanded/Strengthened state (defined in `RealmDef`).
- Deviation risk scales with unprepared meridians.
- Failed breakthrough damages the required meridians (all 3 systems affected).
- Recovery: body cultivation repair, pills, or natural healing over time.

### Data model

- `Actor.meridians: Dictionary` — `meridian_id → MeridianState`.
- `MeridianState`: `id`, `state`, `tier`, `capacity_bonus`, `flow_bonus`, `power_bonus`.
- Stored in `Actor.to_dict()` / `from_dict()` with schema version bump.
- Meridian network is **core** infrastructure — shared by all cultivation systems.

## Consequences

- ADR 0014/0015/0016 reference this ADR for meridian structure and states; they define only the reservoir-specific interaction.
- Meridian bonuses feed into `ActorStats` derived stats (cultivation rate, capacity, technique power) via stat providers.
- Meridian damage is a cross-system debuff — all three cultivation paths read the same `meridians` dictionary.
- Adding a new meridian = authoring a `.tres`; no core change.
- Changing meridian states or unlock rules touches `core/` — requires a new ADR.
- Save schema version increments; migration path from v1 → v2 adds the `meridians` field.
