# 0906 The status delta stays realm-invariant; the tier-power knob is deleted after measurement

- Status: Accepted
- Date: 2026-10-07

## Context

ADR 0902's P11 ported Keepverse's tier-power term as a default-OFF knob
(`status_tier_power_weight`) and deferred the ruling to a cross-realm measurement. The T10
measurement (commit `105f1405b`) ran it: the realm power table spans `1 -> 551x` from R1 to
R30, and the delta feeds a `0..1` chance through `0.5 + delta / (2 * scale)`, so a gap term
`weight * gap` pins the reading at the ceiling once `weight >= scale / gap` — about `0.0009`
at the shipped scale. R1 against R30 reads floor or ceiling at ANY live weight; only
same-tier pairs move at all (R1 vs R10 moved `0.5 -> 0.498 / 0.48 / 0.30` at weights
`0.001 / 0.01 / 0.1`). A default-off knob whose first nonzero value is a cliff is not a
dial.

## Decision

**The status delta is realm-invariant, and the knob is DELETED — code, resource and tests —
rather than left default-off.** A tuning key nobody may turn is a lie in the tuning surface:
it invites a balance pass that the arithmetic already answered. Realm strength keeps
entering combat through the actor MAGNITUDES (`RealmScaling` over
`realm_power_table.tres`), never through the status apply chance.

The measurement is recorded where it can fire: `test_status_realm_invariance.gd` pins parity
for every realm pair in both directions and DERIVES the smallest saturating weight from the
authored numbers, so a reintroduced gap term fails there rather than being re-measured.

## Consequences

- `status_apply.gd` folds no gap; `_realm_power_gap` is gone with the key, and
  `combat_damage.tres` authors no `status_tier_power_weight`.
- Anyone porting further Keepverse apply math must not re-add a gap term without a new
  measurement and a new ADR — the invariant is the design, not an unfinished option.
- The deletion is save-compatible: tuning is a shipped resource, never save state.
