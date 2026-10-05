# 0071 Mind damage erodes the sea and never subtracts health

- Status: Accepted
- Date: 2026-10-02

## Context

One spine, one seam (ADR 0067) and one defensive vocabulary (ADR 0068) carry all three paths. The seam already fixes the shape: qi/body return `amount` only, mind returns `amount 0.0` plus `effects[]`. Mind fights the `mind_power` reservoir (ADR 0016) and, through it, the only input the mind breakthrough roll is allowed to read (ADR 0051). So the mechanism is a consequence, not a choice.

## Decision

`resolve` returns `amount == 0.0` and turbulence / clarity / awareness effects:

```
base      = attacker MENTAL_ATTACK * share
d         = defender MENTAL_DEFENSE
mit       = clampf(d/(d+base), 0, MENTAL_DEFENSE_CAP=0.6)      # 0 at d=0, ->0.6 asymptotic
if OBSCURE: mit = maxf(mit, defender ILLUSION_RESISTANCE)      # illusions read THEIR stat
mit       = clampf(mit, 0, ILLUSION_RESISTANCE_CAP=0.8)
coh       = 1 - COHERENCE_DAMP * awareness_ratio(defender)     # 1.0 -> 0.5 at full awareness
g         = base * (1-mit) * coh * (FOCUS_MULT if focused else 1.0)
g        /= defender_sea.structural_capacity                   # a SHARE of THAT sea
```

**Mind never subtracts health.** It raises sea turbulence, which erodes clarity and depresses `effective_capacity`. The real formula in `SeaOfConsciousness` is `effective_capacity() = structural_capacity * (1.0 - turbulence * 0.5)`.

**Health moves ONLY through rupture bleed**, per combat tick, above `RUPTURE_THRESHOLD = 0.70`: `hp_loss = MAX_HEALTH * RUPTURE_BLEED(0.15) * (turbulence - 0.70)/(1-0.70) * delta`. Below the threshold health is FLAT — a mind duel has a floor of safety qi (ADR 0069) and body (ADR 0070) do not have.

**`structural_capacity` is the denominator, and why.** `MENTAL_ATTACK` is scaled by `MindProvider` as `(perception * 2.0 + mental_clarity * 1.5) * MindRealmProfile.factor` — a bounded RATE, `1.02^29 = 1.775845` (62.5 -> 110.99 on the pinned test actor), not a magnitude. `sea_capacity` is the AUTHORED magnitude, **100.0 at R1 -> 825.0 at R30** across the 30 `MindRealmSeed` `.tres`. Without the denominator those two do not share a scale and the deep realms become a one-hit kill; with it, "one full strike" is the same SHARE of that sea at every realm.

**Collapse: the loser is disarmed, not killed.** `turbulence == 1.0` held for `RUPTURE_COLLAPSE_TIME = 3.0` continuous seconds demotes the sea one tier, resets `structural_capacity` to that tier's floor, floors `clarity` at `COLLAPSE_CLARITY_FLOOR = 0.15`, and applies a `mind_deviation` StatusEffect (60s) zeroing `MIND_TECHNIQUE_POWER`. **The loser is disarmed for a minute, not killed.**

**Progression consequence — a mind fight can COST A REALM.** Clarity is the SOLE input to the mind breakthrough roll: `MindAdvancement._chance` is `clampf(MIN_CHANCE + sea.clarity * CLARITY_TO_CHANCE, MIN_CHANCE, MAX_CHANCE)` = `0.05 + clarity * 0.5`, clamped to 0.05..0.95. Clarity is raised only by `MindTraining.cultivate`: `set_clarity(minf(seed.clarity_required, sea.clarity + gain / 1000.0))`, capped at the current realm's own `clarity_required`. No other path can have its cultivation progress damaged in combat.

**The defensive identity is four levers, none of which is "raise a resistance stat":** (1) the depleting AWARENESS reserve, which feeds `coh`; (2) `MindTraining.meditate` mid-fight, which calms turbulence; (3) specialising the counter-stat — `ILLUSION_RESISTANCE` is read ONLY by OBSCURE and never by DISRUPT or ATTEND, so a clarity build and an illusion-resistance build are different defenders of the same skill; (4) the mind tank — accept sea damage, deny rupture bleed, which is the structural INVERSE of qi resistance and body armour, both of which reduce the incoming amount and leave you whole.

**The 40% floor is structural.** `MENTAL_DEFENSE` enters only through `d/(d+base)`, hard-capped at `MENTAL_DEFENSE_CAP = 0.6`, so **40% of every mind strike always lands at any `mental_clarity`** and at any realm. This is the mind analogue of the chip-floor immunity invariant (ADR 0068) and obeys the same ADR 0051 rule: the breakthrough roll must not read a quantity the entry gate already pins. A gate input is a precondition, not the difficulty dial — so mind difficulty comes from coherence, awareness and matchup of intent, never from stacking `mental_clarity`.

**BL-0114 verdict: RENAME, do not fold.** `MindStats.CRITICAL_CHANCE = &"critical_chance"` = `minf(0.75, 0.05 + perception * 0.003 + awareness_ratio * 0.1)` and `MindStats.DODGE_CHANCE = &"dodge_chance"` = `minf(0.6, perception * 0.002 + awareness_ratio * 0.05)` are different StringNames from core's `Stat.CRIT_CHANCE`/`Stat.EVASION`. Rename to `mind_focus_chance` (2x turbulence only) and `mind_avoidance` (0.1 coherence only). Folding into core would make every mind stat boost every qi and body hit; neither ever gates a non-mind hit.

**`Stat.DAMAGE_REDUCTION` is NEVER read by the mind mechanism.** A qi/body tank does nothing to erosion.

## Consequences

- A mind mechanism returning `amount 0.0` still passes the spine: S6 crit multiplies nothing, S8's chip floor is bypassed by the zero, S9's shield absorbs nothing.
- `TURBULENCE_TO_CLARITY`, `RUPTURE_THRESHOLD`, `RUPTURE_BLEED`, `RUPTURE_COLLAPSE_TIME`, `MENTAL_DEFENSE_CAP`, `ILLUSION_RESISTANCE_CAP`, `COHERENCE_DAMP`, `FOCUS_MULT` and `COLLAPSE_CLARITY_FLOOR` live in a `MindDamageProfile` Resource.
- `clarity_delta = -TURBULENCE_TO_CLARITY * g` for every kind, floored at 0, so erosion saturates and cannot invert.
- The two renamed ids are a save-affecting rename: `critical_chance`/`dodge_chance` need a migration note alongside the schema history.
- `mind_deviation` must be a real `StatusEffect` with a duration and a `MIND_TECHNIQUE_POWER` zero, not a bespoke mind flag.
- Cross-references: ADR 0069's qi always lands; ADR 0070's body subtracts health; this one never does.