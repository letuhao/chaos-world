# 0042 One power ladder, one data block, one guard

- Status: Accepted (superseded by ADR 0050)
- Superseded by: ADR 0050 - the ladder was removed; realm strength is authored data
- Date: 2026-10-02
- Amends: ADR 0013/0016 (per-tier Mind power budgets), ADR 0028 (body/qi budget convention)
- Adapted from: Keepverse `docs/architecture/power/ssot-power-scale.md`

## Context

Four systems each answered "how strong is this?" and none agreed:

| Scale | R1 | R30 | Growth |
|---|---|---|---|
| `realm.power` (`RealmScaling`, 7 core stats) | 1.0 | 3.9 | 3.9x |
| `items` option catalog `realm_factor` | 1.0 | 3.9 | 3.9x |
| `MindProvider._power_budget` (technique output) | 1.0 | 601.43 | **601x** |
| `Tribulation._compute_difficulty` | 1.0 | 5.35 | 5.35x |

Mind's damage channel was **154x** stronger than body and qi at the same realm. That is not a
balance opinion, it is a defect: one of the three cultivation paths was not on the same scale as
the other two, and nothing in the repo could say so.

Keepverse hit the same wall and solved it with a single index and a single function
(`P(Θ) = C + A·Θ + B·Θ(Θ−1)/2`), with three properties this repo was missing: the curve constants
live in one data block, one pin makes the dial retunable without moving authored content, and a
guard fails on any private curve. This ADR adopts that shape.

## Decision

- **`Θ` is the realm index.** The game already has exactly one progression ladder, so `Θ` *is* that
  ladder. Nothing reads a raw level, tier, or rank id to compute a magnitude.
- **`P(Θ) = C + A·Θ + B·Θ(Θ−1)/2`** in `core/power_ladder.gd`. Increment linear, cumulative
  triangular. `Θ(Θ−1)` is a product of consecutive integers and therefore always even, so the
  triangular term is exact and the sum never rounds.
- **Two reads, one ladder.** Magnitudes read `P(Θ)`; contests read `Θ`. Contests are sigmoids over
  a *difference* of two same-scale quantities, so a superlinear index would make a fixed one-realm
  gap worth more at R30 than at R5 and the fight would stop being a fight. `Θ(Θ−1)` being even is
  also why one function can serve both without the reads contaminating each other.
- **The constants are data.** `core/power_scale.tres` holds `C`, `B`, the pin, and the contest
  scale. `PowerLadder` holds no numeric literal, and the guard fails if one appears.
- **`A` is derived, never authored.** `A = (pin_value − C − B·pin(pin_index−1)/2) / pin_index`.
  Authoring it would let the pin drift, and the pin is the only thing that lets `B` be retuned
  without re-resolving authored content.
- **`tools/power.py` is a deterministic Python mirror** reading the same `.tres`, so a guard, a
  report, or a balance audit cannot disagree with the running game. Both sides do the same
  arithmetic in the same order; `test_power_ladder.gd` pins the shared values so a divergence is a
  test failure rather than a quiet disagreement.
- **`tools power check` gates.** It fails on a private power curve in `src/`, a numeric literal in
  the ladder, a broken pin, or an unrecognised verdict annotation.
- **A curve that is legitimately not a magnitude declares itself.** `# power: rate-read` on the
  line. This keeps "correctly a rate" distinguishable from "not migrated yet", which a blanket
  allowlist cannot express, and an unknown verdict fails so the vocabulary cannot be widened by
  accident.

## Migration

Done in this change, in the order that keeps numbers honest:

1. **`realm.power` derives from the ladder.** At `B = 0` this is exactly the previous
   `1.0 + i * 0.1`, so adopting the ladder moved **no** number. 3339 realm assertions and 1359
   traversal assertions were unchanged.
2. **Items migrated with zero movement.** `MAGNITUDE_POLICY["magnitude"][2]` is `0.10`, which is
   exactly the ladder's `A` at `B = 0` — the catalog had independently re-derived `1 + 0.1·Θ`.
   Routing it through `PowerLadder` moves no item and stops items drifting from the stats they
   modify. The `rate` and `fraction` units keep a linear ramp off `Θ`, annotated `rate-read`: a
   rate is a contest input, so linear is correct there by the two-reads rule.
3. **Tribulation difficulty** now reads `PowerLadder.value(realm_index)`, so a fight cannot drift
   away from the stats it tests.
4. **Mind reconciled.** `_power_budget` is deleted. Mind now scales by the same `P(Θ)` as body and
   qi, which is a balance change and therefore re-pinned the Mind suites. Three assertions that had
   encoded the *divergence* as intended behaviour — `P(R30) == 601.425`, `C at R30 is huge`, and
   `R30 ≥ 10x R1` — were rewritten to assert the shared ladder instead of being repinned to a
   lower number. Two test helpers had their own private copies of the old curve
   (`test_mind_power_curve._power_budget`, `test_mind_provider.TECHNIQUE_FACTOR`); both now derive
   from the ladder, so a future ladder change lands as a real failure rather than passing quietly.

`LEGACY_POWER_CURVES` in `tools/power.py` is empty. It exists so a future offender is tracked with a
named reason instead of silently permitted, and the guard fails on a stale entry.

## Numeric types: measured, not assumed

The owner asked whether the ladder could overflow Godot's integers and whether doubles would be
safer. Both are engine properties, so `tests/core/test_power_numeric.gd` measures them rather than
arguing from a comment:

- **GDScript `int` is 64-bit signed**, not 32-bit. Asserted directly: `int64` max is positive,
  `int64` max `+ 1` wraps negative rather than promoting to `float`, and `2^62` is positive.
- **GDScript `float` is a 64-bit IEEE-754 double.** `2^53` is exact, `2^53 + 1` is not
  representable and rounds back, and `1e308` is finite and positive.
- **`Θ` is bounded at 29** by the 30-realm ladder, and the suite asserts that bound rather than
  trusting it.

So there is **no overflow exposure**. Even at `B = 100` — far steeper than any shipped dial —
`P(29)` is about `6.2e5`, thirteen orders of magnitude below `int64` max. The ladder already *is*
double-based (`c`, `b`, and `value()` are all `float`), so there is no type change to make.

The real limit is **precision, not range**, and only for a fractional `B`: `0.4 × 29 × 28 / 2` is
not exactly representable in binary, so the ladder is accurate to roughly `1e-14` relative rather
than bit-exact. That is the reason Keepverse uses integer per-mille — its curve must stay
byte-identical across a replay lock. This game's ladder feeds stats and save payloads with no
byte-identical replay requirement, so doubles are the right choice; if a byte-exact requirement
ever appears, move the curve to per-mille integers and keep the `P(Θ)` signature.

One measurement caught a mistake worth recording: the suite initially asserted `P(Θ)` was integral.
It is not — `A` is derived as `0.1` from the pin, so `P(1) = 1.1`. The property that justifies
doubles is determinism and preserved relative precision, not integrality.

## Consequences

- The four scales are one. Mind's technique channel is no longer 154x out of line with body and qi.
- `B = 0` today, so the ladder is linear and the local exponent is flat. Turning `B` up is now a
  single `.tres` edit that cannot move content authored against the pin — the property that was
  impossible before.
- A 3.9x total stat growth across 30 realms is modest for the genre. That is now an explicit,
  reviewable dial position rather than four systems disagreeing about it.
- `Θ` and `P(Θ)` are different things and both are named. Code that wants "how strong" and code
  that wants "how likely" must say which.
- The guard's regex heuristic is a heuristic. It flags the shapes a private ladder takes
  (`pow(base, progression)`, `1.0 + progression *`, a tier-keyed curve table) and requires a
  declared verdict otherwise; a sufficiently obfuscated private curve could still slip through, so
  review remains part of the contract.