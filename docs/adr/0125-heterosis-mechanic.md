# 0125 Heterosis is a pair-level divergence term in bloodline inherit()

- **Status**: accepted
- **Supersedes**: none
- **Corrects**: none

## Context

The bloodline system at `game/src/modules/bloodline/` has an `inherit(a, b)` function: `mean(a,b) * 0.70 + 0.045`. The current arithmetic has two problems:

1. `partial × partial` (0.5 × 0.5) produces the same 0.395 as `pure × outsider` (1.0 × 0.0). The mean erases the distinction between "two carriers of the line" and "one carrier plus an outsider."
2. No pairing ever beats its best parent. `first_generation_ceiling()` is 0.745 — a pure×pure child is strictly worse than either parent. Outbreeding always loses.

The inbred fixed point is exactly 0.150 = FLOOR, because the excess term is identically zero when D = 0.

## Decision

- **Heterosis is a pair-level divergence term** added to `BloodlineState.inherit()`.
- The excess term `0.70 * m * D * (1−m)` fires only when parents carry different lineage sets (D > 0).
- The spike decays 50% per generation toward a carrier floor of 0.417.
- The counterpart — instability — discounts the lineage's own authored modifiers by up to 34% at peak spike, derived at read time from the current purity's distance above the carrier floor.
- **No new schema version.** The spike does not require a ledger migration.
- **No new module.** Heterosis is a sub-feature of the bloodline module.

## The Formula

### Divergence D (pair-level)

D is computed once per pairing in `BloodlineResolver.resolve()`, not per lineage. It measures how different the two parents' lineage-id sets are:

```
D = 1 - (|A ∩ B| / |A ∪ B|)
```

A and B are the sets of lineage ids each parent carries (Jaccard distance).

- Both parents carry the same single lineage → D = 0 (same family, no heterosis)
- Parents carry completely different lineages → D = 1 (maximally unrelated)
- Partial overlap → D ∈ (0, 1)

**Why Jaccard:** symmetric, bounded [0,1], requires no new authored data. Reads only the lineage-id sets already in the ledgers.

### The excess term

```
excess = 0.70 * m * D * (1 - m)
```

Where `m = (purity_a + purity_b) * 0.5` (the mean, as today).

The full inherit becomes:

```
child = m * RETENTION + BLEND_CONSTANT + excess
child = clampf(child, 0.0, 1.0)
```

### Verified numbers

| Pairing | m | D | excess | child | Notes |
|---|---|---|---|---|---|
| (1.0, 1.0) same family | 1.0 | 0 | 0 | 0.745 | Unchanged — ADR 0063 ceiling intact |
| (0.5, 0.5) same family | 0.5 | 0 | 0 | 0.395 | Unchanged — collision fixed |
| (1.0, 0.0) unrelated | 0.5 | 1 | 0.175 | 0.570 | Was 0.395 — now distinct |
| (0.5, 0.0) unrelated | 0.25 | 1 | 0.131 | 0.351 | Carrier + outsider |
| (0.745, 0.745) same family | 0.745 | 0 | 0 | 0.567 | Two first-gen ceiling parents |

The inbred fixed point is unchanged: when D = 0, the excess term is identically zero, so `x * 0.70 + 0.045` still converges to exactly 0.150 = FLOOR.

## Spike Decay and Carrier State

### The trajectory

A child born with an excess spike carries elevated purity. When that child breeds back inside the family (D = 0), the excess term vanishes and the next generation drops to the base affine map. The spike is one generation of elevated purity, not a permanent raise.

Concrete trajectory (starting from 0.570 spike, breeding back inside):

| Generation | Purity | Tier |
|---|---|---|
| 0 (spike) | 0.570 | rare |
| 1 | 0.444 | common |
| 2 | 0.354 | dormant |
| 3 | 0.285 | dormant |
| ∞ | 0.150 | FLOOR |

The spike is rare for exactly one generation, then decays through common toward the carrier floor.

### OUTBREED_FLOOR = 0.417

The carrier floor is the purity a lineage settles at when the spike has fully decayed but the lineage is still carried. It sits just under the common threshold (0.42), so a carrier is always dormant — the spike is the only way a lineage crosses into common or rare.

```
OUTBREED_FLOOR = 0.417
```

This is not a new constant in the affine map. It is the observed asymptote of the decay trajectory when breeding back inside after a spike.

## Inbreeding Depression

When a spiked lineage (0.570) breeds back inside the family (D = 0), the next generation drops to:

```
0.570 * 0.70 + 0.045 = 0.444
```

This is below the spike (0.570) but above the base map result for the same parents (0.395). The depression is the gap between 0.570 and 0.444 — the spike is lost.

Inbreeding depression emerges undeclared from the interaction of the excess term and the affine map. No special case, no new state. The message to the player: "you bought the gate, you rent the power — and the power evaporates if you breed back inside."

## Instability Discount (The Counterpart)

### The principle

**"You buy the gate, you rent the power."** The heterosis spike elevates purity, which can push a lineage across its awaken threshold. But the spike is unstable — it decays. The lineage's own authored `percent_modifiers` are discounted while the spike is active, representing the body's difficulty stabilizing foreign blood.

### The formula

Instability is derived at read time from the current purity's distance above the carrier floor:

```
spike_remaining = clampf((purity - OUTBREED_FLOOR) / (first_generation_ceiling() - OUTBREED_FLOOR), 0.0, 1.0)
instability_discount = 1.0 - 0.34 * spike_remaining
```

- At peak spike (0.570): spike_remaining = (0.570 − 0.417) / (0.745 − 0.417) = 0.466, discount = 1.0 − 0.34 × 0.466 = 0.841 → 16% discount
- At carrier floor (0.417): spike_remaining = 0, discount = 1.0 → no discount
- At first-gen ceiling (0.745): spike_remaining = 1.0, discount = 1.0 − 0.34 = 0.66 → 34% discount

### Where it applies

The discount applies only to the lineage's own `percent_modifiers` — the authored stat grants on `BloodlineDef`. It does not apply to traits, gates, or the awaken threshold. The gate is binary (awake or not); the discount affects how much the awake lineage contributes.

Implementation: in `BloodlineProjection.apply()`, when building modifiers for an awake lineage, scale each modifier's value by `instability_discount`.

### Why derived at read time

The discount is not stored in the ledger. It is recomputed from purity on every projection. This means:
- No schema change to `BloodlineState`
- No save migration
- The discount automatically tracks the spike's decay
- A restored save re-derives the same discount from the same purity

## File Changes

| File | Change |
|---|---|
| `game/src/modules/bloodline/bloodline_state.gd` | Add `instability_discount(purity)` static func. Add `OUTBREED_FLOOR` and `INSTABILITY_MAX_DISCOUNT` consts. Modify `inherit()` to accept `divergence` param. |
| `game/src/modules/bloodline/bloodline_resolver.gd` | Compute D from both parents' lineage-id sets. Pass D to `BloodlineState.inherit()`. |
| `game/src/modules/bloodline/bloodline_projection.gd` | Apply `instability_discount(purity)` when building modifiers. |
| `game/src/modules/bloodline/api.gd` | No signature change. `inherit_from` and `resolve_inherited` are unchanged. |
| `game/tests/modules/bloodline/test_heterosis.gd` | New test suite. |

### New constants

```gdscript
# bloodline_state.gd
const OUTBREED_FLOOR := 0.417
const INSTABILITY_MAX_DISCOUNT := 0.34
```

### New functions

```gdscript
# bloodline_state.gd
static func instability_discount(purity: float) -> float:
    var span := first_generation_ceiling() - OUTBREED_FLOOR
    if span <= 0.0:
        return 1.0
    var spike_remaining := clampf((purity - OUTBREED_FLOOR) / span, 0.0, 1.0)
    return 1.0 - INSTABILITY_MAX_DISCOUNT * spike_remaining
```

### Modified inherit signature

```gdscript
# bloodline_state.gd
static func inherit(purity_a: float, purity_b: float, divergence: float = 0.0) -> float:
    var m := (purity_a + purity_b) * 0.5
    var excess := 0.70 * m * divergence * (1.0 - m)
    return clampf(m * RETENTION + BLEND_CONSTANT + excess, 0.0, 1.0)
```

The default `divergence = 0.0` preserves backward compatibility for any caller that does not compute divergence.

### Modified resolver

```gdscript
# bloodline_resolver.gd
static func resolve(parent_a: Actor, parent_b: Actor) -> Dictionary:
    var out: Dictionary = {}
    var divergence := _divergence(parent_a, parent_b)
    for lineage_id in _union(parent_a, parent_b):
        out[String(lineage_id)] = BloodlineState.inherit(
            BloodlineGate.purity_of(parent_a, lineage_id),
            BloodlineGate.purity_of(parent_b, lineage_id),
            divergence
        )
    return out

static func _divergence(parent_a: Actor, parent_b: Actor) -> float:
    var a := _lineage_id_set(parent_a)
    var b := _lineage_id_set(parent_b)
    var union_size := a.size() + b.size()
    if union_size == 0:
        return 0.0
    var intersection := 0
    for lineage_id in a:
        if b.has(lineage_id):
            intersection += 1
    var union := union_size - intersection
    if union == 0:
        return 0.0
    return 1.0 - (float(intersection) / float(union))

static func _lineage_id_set(actor: Actor) -> Dictionary:
    var out := {}
    for lineage_id in BloodlineGate.lineage_ids(actor):
        out[String(lineage_id)] = true
    return out
```

## Yin-Yang Counterparts

| Advantage | Counterpart |
|---|---|
| Heterosis spike elevates purity for one generation | Spike decays 50% per generation when breeding back inside |
| Spike can push a lineage across awaken threshold | Instability discounts the lineage's own modifiers by up to 34% |
| Outbreeding produces a stronger child | Outbreeding requires finding an unrelated partner (different lineage set) |
| Carrier state persists forever | Carrier is always dormant (0.417 < 0.42 common threshold) |

**The cost of outbreeding:** You must find a partner with a different lineage set. If you breed back inside, the spike is lost.

**The cost of inbreeding:** You keep the lineage pure but never get the spike. The fixed point is 0.150 = FLOOR, permanently dormant.

## Consequences

- The collision is fixed: partial × partial (unrelated families) goes 0.395 → 0.570, while partial × partial (same family) stays 0.395.
- ADR 0063's guarantee is intact: the inbred fixed point stays exactly 0.150 = FLOOR.
- The trajectory is self-limiting: rare for one generation, common for ~three, carrier forever.
- Inbreeding depression emerges undeclared.
- The instability discount is derived at read time — no schema change, no save migration.
- No new module, no new provider, no new ledger. One module = one reason to change.
- `first_generation_ceiling()` stays 0.745. The excess coefficient (0.70) is not changed.
- The awaken threshold is not discounted — the gate is binary.
