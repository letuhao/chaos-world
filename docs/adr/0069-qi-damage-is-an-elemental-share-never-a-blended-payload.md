# 0069 Qi damage is an elemental share, never a blended payload

- Status: Accepted
- Date: 2026-10-02

## Context

One spine, one seam (ADR 0067) and one defensive vocabulary (ADR 0068) carry all three paths. The qi mechanism still owes a shape. ADR 0004 already owns the element table, the multiplier and the per-element stats; qi may read them and must not restate them.

The load-bearing question is where the matchup sits relative to resistance. Getting this wrong is what produces "fire is always strong": a rule that scales the attacker's element rather than letting the defender's build answer it.

## Decision

`resolve` returns, for a clean hit:

```
share    = technique.element_share (or default) if element valid else 0
m_e      = magnitude * share ;  m_0 = magnitude * (1 - share)
resist   = clampf(defender element_resistance_<e>/RESIST_DIVISOR - mastery_pen, 0, RESIST_CAP)
mit      = 1 - resist
match    = rules.multiplier(attacker_element, defender_element)
total    = (m_0 * ATTACK_SPIRITUAL + m_e * element_power_<e> * match * mit) * (1 - DAMAGE_REDUCTION)
```

**`match` sits BETWEEN the elemental magnitude and mitigation.** Resistance applies after matchup, so a `RESIST_CAP` target is a hard counter even to a `STRONG` 1.5. Two rejections: applying matchup after mitigation scales a 0.5 `WEAK` into a hedge and re-flattens per-target variance; applying it to the whole sum guts `m_0` and punishes a realm-scaled magnitude with a vocabulary rule.

**Resistance applies to the ELEMENTAL TERM ONLY.** The raw share `t_0` is the floor. There is no separate floor constant, and a wrong element is a weaker hit, never a null one. An actor with zero affinity for every element deals raw-only damage and is refused nothing — which is exactly qi's premise, the inverse of body's (ADR 0070). `ElementRules.NOURISH = 0.75` means qi always does something.

**Hybrid payloads are REJECTED, with the proof.** Measured against `ElementDefaults.base()` through `ElementRules.multiplier`: every tier-1 row mean is exactly **0.950000** (25 cells, grand mean 0.950000), and a 50/50 blend of any two tier-1 elements also has mean exactly **0.950000**. But the single-element population spans 0.5..1.5 (ratio **3.0x**) while every blend row spans 0.625..1.25 (ratio **2.0x**). The mean is identical and the spread strictly narrower, because each element is overcome by exactly one, overcomes exactly one, nourishes exactly one and is neutral to the rest: over one row there is exactly one `STRONG`, one `WEAK`, one `NOURISH` and two `NEUTRAL`, for `(1.5 + 0.5 + 0.75 + 1.0 + 1.0)/5 = 0.95`. A symmetric blend is therefore mathematically the act of declining to have an element: it gives up the read and keeps nothing. ONE element per attack; the only permitted mixing is element-against-non-element via `element_share`.

**Mastery is a PENETRATION lever, subtracted BEFORE the clamp**, so it can never amplify past `RESIST_CAP`. `ElementProvider.contribute` emits `element_power_<e> = maxf(0, affinity * (1 + mastery * 0.1))` and `element_resistance_<e> = maxf(0, affinity * 0.5 + will * 0.2)`, reading mastery post-modifier so an item modifier flows once (ADR 0026). `element_mastery_<e>` is a base attribute, not provider output.

**The realm-invariance fix.** `element_power_<e>` is NOT in `RealmScaling.SCALED_STATS` (7 ids: `MAX_HEALTH`, `MAX_QI`, `MAX_STAMINA`, `ATTACK_PHYSICAL`, `ATTACK_SPIRITUAL`, `DEFENSE_PHYSICAL`, `DEFENSE_SPIRITUAL`), so it would be realm-FLAT while `ATTACK_SPIRITUAL` grows by the authored `RealmDef.power` **1.00 -> 551.46**. Measured element fraction of a qi hit at `share = 0.8`: 0.7619 at R1, 0.3678 at R11, 0.0058 at R30 — a silent realm degression of the element channel to noise. The fix is a source-tagged `StatModifier.new(power_id, Op.MULT, realm.power, RealmScaling.SOURCE)` added in `ElementsApi.attach`, which makes the fraction exactly invariant (0.8 at every realm). `element_resistance_<e>` deliberately gets NO such modifier: it is a RATE, and a rate must never track a magnitude (ADR 0050).

**Tier-2 dominance is a live defect in the shipped data.** In `ElementDefaults.advanced()` every element has empty `generates`, and `lightning`/`ice`/`wind` have two `overcomes` while `light`/`dark` have one each. Measured row means over the 10-element graph: tier-1 rows 0.875..0.975, `lightning` and `ice` **1.100000**, `wind`/`light`/`dark` **1.050000**, grand mean 0.997500. Each tier-2 row is above every tier-1 row. Fix: a per-tier mastery divisor `1.0 + (tier-1)*TIER_MASTERY_STEP` inside `ElementProvider`, so tier 1 is bit-for-bit unchanged (divisor 1.000) and the tax falls only on the dominant tier (1.100 row mean -> 1.000 at step 0.10). This is element policy inside the stat's own formula, which is what ADR 0004 assigns to `ElementProvider`; combat never sees it.

`ElementRules` is INJECTED by the caller, and `"elements"` is ALSO added to combat's registry deps so the registry does not lie about an edge that exists. `TechniqueDef.element` ALREADY EXISTS (`modules/techniques/technique_def.gd`, surfaced as `"element"` by the techniques read model), so qi's only new authored field is one additive `@export var element_share: float` — 0 meaning "use the default". Not a `contracts/` change: ADR 0056 puts a def in its owning module.

## Consequences

- One element per attack is machine-checkable against `ElementRules`; a blend has no code path. The 0.95/3.0x-vs-2.0x figures above are a property of the shipped `ElementDefaults`, so changing an element's `overcomes` list re-opens the question and the test must re-measure rather than restate 0.95.
- The proof is a property of the FIVE-element tier-1 set. It does not transfer to tier 2, whose rows are not balanced (see below); that asymmetry is a separate argument and is stated separately rather than borrowed.
- `RESIST_DIVISOR`, `RESIST_CAP`, `mastery_pen` and the default share live in `combat_damage.tres` on a `CombatTuning` Resource (ADR 0067), never as literals in the mechanism `.gd`. A balance edit is then a data edit, the same rule `RealmScaling` follows by reading `RealmDef.power` instead of hardcoding 551.0 (ADR 0050).
- An unelemented `TechniqueDef` yields `share = 0` and a pure raw hit; qi never returns 0.0 for a landed hit. `resolve` may still decline a hit it has no elemental reading for, exactly as `DamageMechanism.resolve` documents ("Returns 0.0 for a hit it declines"), but that is the seam's contract and not the element table's.
- `ElementsApi.attach` gains a modifier write, so it must not be called twice on one actor: `ActorStats.add_provider` appends unguarded, and the realm modifier would then be applied against a stale power baseline.
- The tier mastery divisor needs a shape test: tier-1 output bit-identical before and after, tier-2 strictly reduced. It divides the MASTERY term only, so an actor's `element_power_<e>` still rises monotonically with mastery — the tax changes what tier 2 costs, never whether mastery pays.
- `element_resistance_<e>` staying realm-flat is a deliberate second defect accepted here: a defender's resistance is an authored rate that a player invests in per point, and scaling it by 551.46 would make deep-realm qi immunity automatic. Recorded, not silently inherited.
- `ElementRules.weak_against(id)` already exists and returns every element that overcomes `id`, so the UI can answer "what hurts me" without a new query and without qi owning a rules clone.
- The `element_share` export is subject to the ADR 0022 trap only if someone later authors it as a rate stat with a `PERCENT` modifier; it is a coefficient on an authored magnitude, not a `0.0`-baseline rate, so it takes no modifier at all today.
- Cross-references: ADR 0070 refuses a strike outright where qi always lands; ADR 0071 has no element at all; both consume the same `CombatTuning` seam.