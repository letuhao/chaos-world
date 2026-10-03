# 0067 one spine one seam: a mechanism returns a proposal

- Status: Accepted
- Date: 2026-10-02

## Context

Keepverse solved the same problem with one overlay calculator that already carries three payload shapes — `OverlayCombatCalculator.Compute` fans over `ElementPayloadComponent[]`, branches on `CombatPolicy.DefenseShape`, and narrows `double` to `long` with `checked`. Porting it ports every branch it grew, permille integers included. The real cost is drift: three damage functions inside `modules/combat/` converge on the same three questions — does a miss cost a roll, is crit an input to mitigation, is reduction a fraction — and answer them independently.

## Decision

One 11-stage spine in `modules/combat/`, in this order, unchangeable without an ADR.

- **S1** `base *= RealmRate.factor(attacker.realm())`, so the ladder scales MAGNITUDE only.
- **S2** band roll, ONE `rng` draw, resolving `missed | parried | blocked` before anything computes.
- **S3** crit roll, a SECOND draw, on a clean hit ONLY.
- **S4** `mechanism.resolve(ctx) -> DamageProposal` — per-path.
- **S5** `mechanism.mitigate(ctx, proposal) -> DamageProposal` — per-path.
- **S6** `amount *= CRIT_DAMAGE` if clean hit.
- **S7** `ampFactor(amp - reduction)`, reciprocal, one mitigation shape for all three paths.
- **S8** `maxf(amount, maxf(1.0, base * 0.01))`.
- **S9** `Shield.absorb(amount) -> overflow`, health taking `-overflow`.
- **S10** reflect, POST-shield, `rate * share`, chain depth <= 6.
- **S11** lifesteal, a SEPARATE packet after HP.

S4 and S5 are the only per-path stages; the other nine are shared.

**Four load-bearing orderings, each independently assertable in a test.** S1 before S2: the ladder must not make a hit land MORE OFTEN, or it is an invisible second dial on `Stat.EVASION`. S2 before S4: a MISS never invokes a mechanism, a property all three mechanisms can be tested for. S4 before S6: crit multiplies what the mechanism produced and is never an INPUT to it, so the three cannot disagree on a shared stat. S7 before S8, and S8 before S9: reduction runs, THEN the floor restores the chip; reverse these and enough `DAMAGE_REDUCTION` returns zero from a landed crit. That last pair is what makes immunity unreachable.

`Stat.DAMAGE_REDUCTION` is FLAT with baseline `0.0` (ADR 0022) — a subtraction, not a fraction — so S7 can drive `amount` to `0.0`, S8 restores it, and a landed hit is always `>= MIN_CHIP_ABS = 1.0`. **No per-mille cap constant exists**: Keepverse needed `BlockCapPermille`, `ParryCapPermille` and `ShieldPolicy.ChipFloorKPm` because its reduction is linear and reaches total. A floor is a DISTRIBUTIONAL claim ("of hits that land, at least `q` produce at least this much"), not a truncation of an authored stat, so ADR 0050's ban on hard progression ceilings holds. `Stat.EVASION` caps at `0.6`, so landed probability is `>= 0.4` and there is no second miss channel.

The seam is `contracts/damage_mechanism.gd`, an abstract base with two virtuals, reached by component id `&"damage_mechanism"` (`modules/combat/mechanism_slot.gd`). Not a `Dictionary` of callables: a dictionary has no name, so the repo rule "any script implementing a `contracts/` interface must pass the same contract tests" has nothing to point at. Not a bare component lookup with a downcast: `Actor.component()` returns `RefCounted`, so `as` on null is silent and surfaces three stages later as "the mechanism did nothing". `contracts` is in `BARE_REF_UNITS` (`rules.py`), so the edge IS enforced, and `contracts/` is the only layer where a shared name can exist without one path owning it. **Invariant to test: no `if/else on path_id` anywhere in `modules/combat/`**, proven by swapping the stub for qi — a one-line `app/` change, zero combat edits.

`DamageProposal` is `{amount: float, effects: Array[Dictionary]}`, not a float, because mind's mechanism never subtracts health at all (ADR 0071): it erodes the sea. `amount` lets the spine own every shared stage while `effects[]` stay the path's own state writes, applied AFTER HP. qi/body return `amount` only.

Float end-to-end, **never round**: every consumer is already float (`ResourcePool`, `Shield.absorb`, `ActorStats`, `StatModifier`) and Keepverse's `long`/permille exists for a server-authoritative wire chaos-world does not have — its determinism need is the injected `RandomNumberGenerator` the repo already uses. **No rounding anywhere**, because rounding is the one operation whose result depends on how stages are grouped, so one `roundf()` destroys every "order doesn't matter except where I say" test. **No divisions in the spine**: `band.gd` compares thresholds. **Non-negative sign discipline**: the spine returns non-negative and the sign flips in exactly one place, S9's `change_resource(&"health", -overflow)`. **One `is_finite` guard** at S6's entrance, because `maxf(NaN, chip) == NaN` and `ResourcePool.change` has no guard of its own.

Deliberately NOT ported: per-component/element weighting (the shared spine carries no element payload — that is the qi mechanism's job, ADR 0069), `PierceFactor`, `AmpFactor` / `AmpFactorReciprocal`, `ClampedContest`, per-mille integers, all rounding, a second RNG convention, a `mitigation.gd` (S5 is one subtraction), a `defense.gd` (defense is a mechanism's INPUT). None is re-added without an ADR.

## Consequences

- Each per-path mechanism (0069 qi, 0070 body, 0071 mind) implements the same two virtuals and ships the same contract tests under `game/tests/contracts/`.
- Every stage is one private function, so each ordering above is a two-line test rather than a debate.
- `modules/combat` already declares only `contracts` and `core` in `tools/arch/registry.json`, so the seam adds no module-graph change: `contracts` is already reachable, and `enforce.py` fails only on DETECTED references.
- `api.gd` exposes 2 public methods (`attach_shield`, `shield`) today; the spine's entry point keeps it far under `MAX_FACADE_PUBLIC_METHODS` (12).
- Tuning constants live in `modules/combat/combat_damage.tres` (`CombatTuning`), mirroring `RealmScaling` reading `RealmDef.power` instead of hardcoding 551.0.
- `Shield.absorb` is untouched, so S9 carries no port risk; the shield's `capacity/toughness/pen/regen` channels are read-only inputs (ADR 0068).
- The spine's tuning surface is exactly one Resource, so a rebalance is a `.tres` edit and no test re-pins a literal.
- A fourth path costs one new file and one `app/` line. No stage is revisited.