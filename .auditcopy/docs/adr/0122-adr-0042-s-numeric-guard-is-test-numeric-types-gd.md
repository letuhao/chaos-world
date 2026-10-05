# 0122 ADR 0042's numeric guard is test_numeric_types.gd

- **Status**: accepted
- **Corrects**: ADR 0042 (a citation; its Decision is untouched)

## Context

ADR 0042:83-85 cites `tests/core/test_power_numeric.gd` as the suite that "measures"
the numeric claims rather than arguing them. **That file does not exist.**

```
Get-ChildItem game/tests/core -Name | Where-Object { $_ -match 'power|numeric' }
  test_numeric_types.gd
  test_realm_power.gd
```

The three assertions 0042 makes about it are real and live, in
`tests/core/test_numeric_types.gd:14-37`: `int64` max positive (`:16`), `+ 1` wrapping
negative rather than promoting to float (`:17`), `2^62` positive (`:19`), `2^53` exact
in both `int` and `double` (`:31`), `2^53 + 1` rounding back (`:33`), `1e308` positive
and `1e308 * 10` infinite (`:36-37`).

So the guard is not missing; the ADR points one filename away from it. A dead test
citation is the same failure as a dead decision — the next agent who trusts it opens
`test_power_numeric.gd`, finds nothing, and concludes the numeric guard was deleted with
the ladder.

## Decision

- **The guard is `tests/core/test_numeric_types.gd:14-37`.** Recorded once, here, so a
  search for the name lands somewhere real.
- **The correction is a superseding ADR, not an edit to 0042.** 0042 is accepted and
  already superseded on its Decision by ADR 0050; rewriting history is how an audit
  loses the fact that the citation was ever wrong.

Rejected: *edit 0042:84.* Immutable once accepted. Rejected: *add a `test_power_numeric.gd`
alias file* — a second name for one suite is the ADR 0066 shape in the test tree, and it
would make the next audit find two answers again.

## Consequences

- ADR 0042's numeric section stands on its reasoning; only the path changes. Its
  conclusion — no overflow exposure, precision not range — is unaffected and still
  measured rather than assumed.
- **Nothing is enforced.** An ADR can cite a path that never existed and the gate is
  green, which is the general gap ADR 0120 records for deletions. A checker that
  resolves every `file:line` an ADR cites would catch both classes; it needs an owner of
  `tools/adr/`.