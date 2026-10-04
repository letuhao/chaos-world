# 0162 The chip floor is the one health a DECLINING mechanism still pays

- Status: Accepted
- Date: 2026-10-04
- Amends: ADR 0071's headline claim "mind never subtracts health", and its
  Consequences bullet "S8's chip floor is bypassed by the zero". ADR 0067 and ADR 0068
  are untouched; the immunity invariant they establish is what forced this.

## Context

ADR 0071's title, its Decision ("`resolve` returns `amount == 0.0`") and its
Consequences ("A mind mechanism returning `amount 0.0` still passes the spine: ... S8's
chip floor is bypassed by the zero") all say one thing: a mind strike spends no health.
The mechanism agrees. `MindDamage.resolve` returns `DamageProposal.new(0.0, effects...)`.

The spine does not. `CombatSpine.resolve_hit` S8 (`spine.gd:149`) is

```
outcome.amount = maxf(outcome.amount, chip_floor(outcome.base, tuning))
```

and `outcome.base` is S1's `technique.magnitude * RealmRate.factor` — **the technique's
magnitude, not the mechanism's answer**. So a landed mind hit spends
`maxf(min_chip_abs, base * min_chip_share)` health: at the shipped `1.0` / `0.01` and a
magnitude of `100.0`, exactly `1.0` HP. ADR 0071 was never amended and its own test
(`test_mind_damage.gd`) asserted the shipped behaviour while describing it as "FALSE of
`resolve_hit`'s returned amount".

Two resolutions were available.

## Decision

**Keep the floor. The chip floor is the single, deliberate exception to "a mechanism that
declines pays no health", and it is keyed on `base`, not on the mechanism's answer.**
ADR 0071's headline claim is amended by this narrowing: mind **erodes the sea and never
subtracts a SHARE of its own erosion**, and it **still pays the shared chip floor** like
every other landed hit.

**Why not exempt a zero-amount, effect-carrying proposal from S8.** That boundary was
implemented in review and rejected on a counter-example the ADR has to name, because
`effects` is not a statement about health:

- **It erases a physical blow.** `BodyDamage.resolve` builds `subtotal` by summing
  per-site values and then carries a `BodyWounds` effect per site (`body_damage.gd:126-136`).
  ADR 0070's one legal refusal is exactly `subtotal == 0.0` (`body_damage.gd:263`), and
  `body_damage.gd:65-72` states in prose that this "is not immunity" **because S8's chip
  floor restores a LANDED hit to at least `min_chip_abs`**. Under a `0.0 + effects` rule a
  refused body strike — which still carries its wound rows whenever `sites` is non-empty —
  would cost zero health. That is immunity reachable through the armour stat, which is the
  single thing ADR 0068 exists to make arithmetically unreachable.
- **`effects` cannot carry the distinction the ADR would need.** A fourth path that
  erodes without eroding would be right to want the exemption, and it is indistinguishable
  from body under this rule. The seam would need a new field — a `declines_health` flag —
  and a flag on the proposal is a `path_id` branch by another name, which is what ADR
  0067's seam exists to prevent.

**Why the floor on `base` and not on the amount.** The floor's stated purpose (ADR 0067) is
that S7 must not be able to drive a landed hit to zero. That is a property of the SPINE's
own stages S6/S7, not of the mechanism: S6 multiplies and S7 scales whatever S4 produced.
Flooring on `outcome.amount` would make S8 vacuous — S7 already drove it to zero, and
`maxf(0.0, 0.0)` restores nothing. Flooring on `base` is what makes the floor survive S7,
which is the only reason it is there. S8 therefore answers "was a technique swung at this
target and did it land?", which is the question immunity is actually about.

**The cost, stated plainly.** ADR 0071's headline claim is weakened. A mind strike is no
longer free: it spends 1.0 HP per landed strike at the shipped tuning. That is a real
behavioural change from the ADR's title and is deliberate. It is bounded, it is shared with
qi and body, and it is 1/100th of a normal qi hit at the fixture's magnitude — so the ADR's
*design intent* ("a mind duel has a floor of safety qi and body do not have") survives,
while its *literal wording* does not.

## Consequences

- `MindDamage` is unchanged. No mechanism edit, no tuning edit, no `.tres` edit.
- `CombatSpine` S8 is unchanged. The spine does not grow and its immunity invariant is
  untouched: a mechanism returning a non-zero amount is still floored, and a zero-amount
  EMPTY proposal is still floored, so no landed hit of any kind can be erased.
- Health still moves for a mind path ONLY through `MindDamage.tick_rupture` above
  `RUPTURE_THRESHOLD`, plus this 1.0 chip. Both are now named in one place.
- A body refusal (`subtotal == 0.0`) still costs `min_chip_abs`, as ADR 0070 intended.
- `test_combat_immunity.gd` keeps proving the invariant with an EMPTY zero-amount
  proposal, which is the correct worst case and is unaffected.
- `test_mind_damage.gd` asserts the floor as the documented exception rather than as a
  known falsehood, and pins it explicitly.
- Cross-references: ADR 0068's immunity invariant is unchanged and is the reason; ADR
  0070's body refusal is unchanged; ADR 0069's qi always lands is unchanged.