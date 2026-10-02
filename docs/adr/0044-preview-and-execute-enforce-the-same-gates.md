# 0044 Preview and execute must enforce the same gates

- Status: Accepted
- Date: 2026-10-02
- Amends: ADR 0024 (qi breakthrough), ADR 0033 (reachable gates)

## Context

An audit of the cultivation domain found three places where the qi path told the
player one thing and did another, plus one phantom resource. Each had a green
suite.

1. **A scarred dantian was spendable.** `preview` reported `dantian_injured` as an
   unmet condition, but `QiBreakthroughCondition._dantian_ready` — the gate
   `execute` validates through — never checked injury. Worse, `Dantian.damage`
   lowers usable capacity to 75% *and* clamps the reservoir down with it, so a
   scarred dantian refills to a full ratio again and passes the fill gate on a
   structurally compromised core. The preview's warning was decorative.
2. **Rewards were granted before the advance was confirmed.** `execute` applied
   `seed.rewards` and zeroed the reservoir, then called
   `Breakthrough.try_advance_gated`, which can still refuse. A refusal therefore
   returned `false` with the rewards already paid and the reservoir drained, for a
   realm the actor never entered.
3. **`qi_purity` was a second qi axis.** Registered in `QiPath.resource_ids`,
   created *full* on attach, read once by `QiProvider`, and multiplied into
   `QI_ABSORPTION`, `TECHNIQUE_POWER`, and `QI_SENSE_RANGE` by
   `(0.5 + purity * 0.5)`. No production code ever wrote it, so the factor was
   always exactly `1.0` — a gate that looked real and gated nothing, wired into
   three combat stats.
4. **`Dantian.trained_stage`** was declared, serialized, and deserialized but never
   written anywhere, unlike `SeaOfConsciousness.trained_stage`, which mind's
   training layer actually maintains.

## Decision

- **The condition object is the only gate.** `_dantian_ready` rejects an injured
  dantian outright. A scar must be healed with the realm's `recovery_item`
  (ADR 0031), not refilled around.
- **Nothing is granted until the advance is confirmed.** `try_advance_gated` runs
  first; rewards, the reservoir drain, and `synchronize` follow it. A refusal now
  leaves the actor byte-for-byte as found.
- **`qi_purity` is deleted**, not deprecated: the stat const, the path entry, the
  facade re-export, the pool creation, and the `_purity` reader all go, and the
  three multipliers lose the dead factor. The objective says one active reservoir,
  and the dantian owns structural tier, quality, and injury only.
- **`Dantian.trained_stage` is deleted.** Round-tripping a value nothing writes is
  worse than not having it: a save diff would show it moving for no reason.

## Consequences

- `test_qi_recovery.gd` gains a paired test: a scarred dantian is refused with the
  injury as the *only* unmet condition, and the same actor healed is spendable.
  Both open the required channels first, so a "refused" assertion cannot pass for
  the wrong reason.
- `test_qi_path.gd` and `test_qi_stats.gd` now assert exactly one qi reservoir;
  the purity test became a test that absorption is *not* scaled by a second axis.
- The grant reorder is behaviour-preserving on every reachable path — the gates
  are validated before the pill is consumed, so `try_advance_gated` does not
  refuse in practice. It is hardening against a refactor that reorders again.
- Removing `QiStats.QI_PURITY` is a breaking change to the module's public surface.
  Nothing outside the module referenced it; `tools arch` confirms.
