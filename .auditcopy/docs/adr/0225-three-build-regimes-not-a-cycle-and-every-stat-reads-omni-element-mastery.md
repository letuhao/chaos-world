# 0225 Three build regimes, not a cycle, and every stat reads omni + element + mastery

- Status: Proposed
- Date: 2026-10-05

## Context

ADR 0200 fixes mitigation and ADR 0215 fixes rate contests. Neither says anything about how
BODY, QI and MIND relate to each other, and that is the balance question.

A symmetric rock-paper-scissors was considered and rejected: the source design tried it for a
year and measured it failing. Its cycle closed at ~65% per arrow in simulation but collapsed
on shipped coefficients, with three separate redistribution passes each moving which build
dominated (`Vigor`, then `Fortitude`, then `Bulwark`) and each still beating all eleven others.
Its own conclusion was that redistribution alone had failed three times and a fourth attempt
should not be one either — the fix was to change the mechanism, not the numbers.

The fiction also does not want a cycle. In the genre the three paths are not equal and
rotating; body has an enormous floor and a hard ceiling, mind has an enormous ceiling and no
floor, and qi is the generalist that is never the wrong answer. That is an **asymmetry of cost
and of peak**, not a rotation of advantages.

## Decision

### Three regimes, not a cycle

| | **QI** | **BODY** | **MIND** |
| --- | --- | --- | --- |
| Cost to raise | 1× (baseline) | high | high |
| Content that feeds it | broad | narrow | narrow |
| Advantage | never the wrong answer | cannot be killed by physical damage | bypasses defense entirely |
| Ceiling | none | hard stop | none; the body is fragile |

**QI is the baseline because it is what the world supports.** Every sect teaches it, every item
feeds it, every realm seed advances it. BODY and MIND are expensive on purpose, and the cost
lands in **two** places at once so no single exploit removes it:

1. **Narrower content** — fewer items, bosses and techniques feed them.
2. **Slower advancement on the shared ladder** — BODY pays a higher cost per rank and a lower
   `chance_base`, so at equal effort a body cultivator sits at a lower `rank_id`. It is the
   same 30-realm ladder (`body_path.gd`) and there is **no artificial threshold lock**: the
   extra cost is real work, never a wall, and a player who chooses badly can walk it back.

**"Expensive" also means BODY must *do* things, not only train.** Fighting, being injured,
killing, regenerating and growing are BODY's loop; training alone is not a body path. That
requirement is delivered by the injury system ("destroy and recreate") rather than by a stat.

**BODY does not peak early.** It scales throughout and is merely harder to *start*. An
early-peak design was rejected: it makes a realm-5 pick wrong by realm 25, and this game has
respec and no class, so a player who chose well would be punished for it with no way back.

**The advantage is absolute, not eventual.** Each regime is the *only* answer to its own
problem, not merely better at it. BODY is the only defense that works against a physical
threat; MIND is the only attack that works against a defended one. That is what makes the
higher cost a trade rather than the tax an unanswerable axis becomes.

### Every stat reads omni + element + mastery, additively

```
total = omni + element + mastery
```

The third term is recovered from the original design
(`chaos-backend-service/docs/combat-core/02_Damage_System_Design.md:126-128`, worked example
at `:507-510` where `40 + 120 + 200 = 360`).

**"Mastery" is a REGIME-SPECIFIC TRACK, not one shared stat** — this is the owner's ruling and
it is what separates the three regimes:

| Regime | mastery track | advances by |
| --- | --- | --- |
| **BODY** | **weapon mastery** (greatsword, staff/spear, fists, footwork, bracing, twin blades) and **material art mastery** (metals, woods/fiber, beast bone, mineral, blood) | using the weapon; tempering matter into the body |
| **QI** | `element_mastery_<e>`, which already ships | casting that element |
| **MIND** | **status mastery** (a cc group: daze, silence, blind, terror, doubt, heart demon) and **expression-damage mastery** (emotion, will, intent, voice) | imposing states; projecting presence |

**Mastery is NOT realm rank.** A high-realm body cultivator can be a complete novice with a
weapon they have never trained, and a high-realm mind cultivator can have never projected
anything. If mastery merely scaled with `rank_id` it would be a second copy of the ladder and
worth nothing.

**Material arts may BUILD a part the body does not have.** Not a buff to an existing limb —
*grow* one. This is the literal payoff of "destroy and recreate" and it is the reason the
injury system is a BODY requirement rather than a decoration.

**Every weapon and material carries a counterpart** (the yin-yang rule in `AGENTS.md`), so a
build is a choice rather than an optimum. **No CC is unresistable**: every mind status is a
contest the target can win, because a disable nobody can answer is a tax, not a mechanic.

**Omni is additive-only, never multiplicative**, from the same source and stated there as a
rule: *"Omni stats chỉ cộng, không nhân"* — multiplying them *"causes snowball"*. One rule for
every stat, no exceptions, because a single multiplicative omni is the whole anti-one-trick
protection.

### Mind's missing contest, and where the rest of the vocabulary lands

MIND has a power pair (`MENTAL_ATTACK` / `MENTAL_DEFENSE`) but no avoidance contest, which is
why it has one here: **`MIND_CLARITY` (attacker) against `MIND_VEIL` (defender)**. Not
`dodge`, because nothing physical moves; not `block`, because it is not absorption. It asks
whether the defender's mind is present enough to be struck at all, and `ILLUSION_RESISTANCE`
becomes the mind-specific defense half an `OBSCURE` attack reads.

| Mechanism | Builds | Stat ids |
| --- | --- | --- |
| dodge | QI | `ACCURACY` / `EVASION` |
| block | BODY | meridian armour (`state_rank`, `tissue_defence`) feeding `ABSORPTION` |
| veil | MIND | `MIND_CLARITY` / `MIND_VEIL` |
| shield | all three, one pool each | `body_shield`, `qi_shield`, `mind_shield` |
| reflect | all three | `reflect_rate`/`reflect_damage` with `reflect_resist_*`, bounded by `proc_depth_limit` |

`tissue_defence` becomes one **source** feeding `ABSORPTION`, so meridian armor and the new
stat are not two answers to one question.

## Consequences

- No symmetry guard is written, because none is claimed. The yin-yang rule in `AGENTS.md`
  still binds: every stat ships with its counterpart, and a mechanic that is a strict best
  response is a defect — the regimes satisfy this by *coverage*, each being unanswerable in its
  own lane rather than by countering another regime.
- A balance measurement must therefore be **three-way and asymmetric**: it reports whether any
  regime is unanswerable, not whether a cycle closes. Win rate against a mirror is the metric;
  a clock is never the metric, because a clock clears a dominant corner by changing the win
  condition rather than by fixing anything.
- `ATTACK_SPIRITUAL` is currently read by BOTH qi and mind, and all three read
  `DAMAGE_REDUCTION`. One build may not accumulate several channels that multiply each other,
  so splitting those two is part of this change and not a follow-up.
- `mind_damage.gd:58-59` records that its sea denominator was justified by a realm-invariance
  claim the shipped numbers refute: the erosion share decays ~4.6x from R1 to R30 and that
  decay is build-independent, because the ATTACKER's rate sits in the numerator against the
  DEFENDER's 8.25x `structural_capacity`. **Decided here rather than deferred**, because MIND's
  ceiling means nothing while its own attack lands a quarter as hard at R30 as at R1: a build
  whose advantage decays with the ladder is not the high-ceiling regime this ADR describes.
  The fix is to make the share a function of the *defender's* sea only — divide by
  `structural_capacity` **and** normalize the numerator by the same ladder factor, so the share
  is realm-invariant by construction and not by coincidence of two numbers happening to track.
  That is a progression-arithmetic change, so it must be proved by a realm-invariance test
  across all 30 `MindRealmSeed` `.tres` rather than asserted in prose.
- The 30-realm ladder is unchanged. What changes is that magnitudes carry it and rates do
  not, so a stronger cultivator hits harder rather than more surely (ADR 0215).