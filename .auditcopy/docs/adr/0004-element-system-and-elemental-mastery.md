# 0004 Element system and elemental mastery

- Status: Accepted
- Date: 2026-10-01

## Context

Combat and cultivation need a shared element vocabulary with strengths and weaknesses. Cultivation novels use the Chinese 五行 (generating 相生 / overcoming 相克 cycles) plus advanced derived elements. The set must be extensible: adding an element must be data, not code.

## Decision

- Elements are data: `ElementDef` (Resource) holds `id`, `tier`, `generates`, `overcomes`, `color`. `ElementRules` is built from a list of `ElementDef`s; the default set is `ElementDefaults`.
- Default set — tier 1 五行 (metal, wood, water, fire, earth) plus tier 2 advanced (lightning, ice, wind, light, dark).
- Relationships: `generates` (相生, nourish) and `overcomes` (相克, weakness/strength). `ElementRules.multiplier(attacker, defender)` is a pure function: 1.5 overcomes, 0.5 overcome-by, 0.75 nourishes, else 1.0.
- Per-element derived stats are emitted by `ElementProvider` (ADR 0002) as dynamic ids: `element_power_<e>`, `element_resistance_<e>`, `element_mastery_<e>`. Innate affinities live in `Actor.affinities`.
- Elemental mastery is a cultivation path (ADR 0003): `CultivationPathDef` (core) with ranks Awakened → Attuned → Adept → Master → Grandmaster → Sovereign; ranks gate element tiers (1 → 2 → 3).
- The `elements` module depends only on core/contracts.

## Consequences

- Adding an element = authoring an `ElementDef` `.tres` (or appending to `ElementDefaults`); no rules code changes.
- Damage math (combat layer) reads `ElementRules.multiplier`; the `elements` module owns no combat logic.
- Light/dark are mutual counters; tier-3 (void/chaos/time) is reserved for a later ADR and gated by mastery.
