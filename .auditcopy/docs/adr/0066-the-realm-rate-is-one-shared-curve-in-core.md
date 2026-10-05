# 0066 The realm rate is one shared curve in core

- Status: Accepted
- Date: 2026-10-02
- Amends: ADR 0050 (rates are not magnitudes), AGENTS.md 126-127 (rate ownership, the triplication rule)

## Context

Three modules carry a copy of the same number: `QiRealmProfile`
(`qi_cultivation/realm_profile.gd`), `BodyRealmProfile` (`body_cultivation/realm_profile.gd`),
`MindRealmProfile` (`mind_cultivation/realm_profile.gd`). They are byte-identical apart from
the `class_name` and the doc comment: `RATE_STEP := 1.02`, `NEUTRAL := 1.0`, and
`factor(realm_id)` = `pow(RATE_STEP, float(ordinal))`, ordinal read via
`RealmDefaults.ladder().index_of(realm_id)`.

Each file gives the same reason: *"They are separate classes because a module may only reach
another module through its `api.gd` facade, and the alternative — one shared curve — is the
magnitude ladder this replaced."* Both halves are wrong.

**The facade rule was never in play.** It constrains cross-module edges. `core/` is a layer,
not a module: `LAYER_DEPS["core"] == {"core", "contracts"}` and `PRIVATE_UNITS == {"app"}`
(`tools/arch/rules.py:29,35`). All three cultivation modules already declare `core` in
`tools/arch/registry.json`, so a function in `core/` creates **zero** new edges.

**A shared rate is not the magnitude ladder.** That held until ADR 0050 deleted `PowerLadder`
and made realm strength authored data in `core/realm_power_table.tres`. A **RATE** ("what is
one unit of this realm's training worth") is not a **MAGNITUDE** ("how strong is a thing from
this realm"), and ADR 0050 requires a rate never to read the magnitude table. The curve returns
`1.02^29 = 1.776` and never opens `realm_power_table.tres`; `RealmScaling` reads the authored
`RealmDef.power`.

The duplication also bought a test. `tests/core/test_realm_rate_parity.gd` has 4 tests; two —
`test_the_three_paths_agree_on_the_rate`, `test_the_rate_step_constant_is_identical_in_all_three` —
compare the copies and the constants against each other, and assert `x == x` against one copy.

## Decision

- **`core/realm_rate.gd` (`class_name RealmRate`) holds the one curve.** `RATE_STEP := 1.02`,
  `NEUTRAL := 1.0`, `factor(realm_id) = RATE_STEP^ordinal`, ordinal via
  `RealmDefaults.ladder().index_of` so it cannot drift from `RealmDef.index`. Unknown or empty
  realm id returns `NEUTRAL`. The three `realm_profile.gd` files are deleted.
- **`test_realm_rate_parity.gd` is deleted, not rewritten.** Its two inter-copy assertions are
  meaningless against a single copy. Its other assertions are real coverage and carry forward
  to `tests/core/test_realm_rate.gd`: the rate rises strictly at all 30 realms and the price of
  a breakthrough rises strictly — the invariant named in all three doc comments; the span is
  under 2x and still rises; unknown and empty ids return `NEUTRAL`. Those monotonicity pins
  must be carried forward; losing them drops the invariant.
- **`RealmRate.factor()` is invariant under `RealmDef.power`.** The rate does not read, derive
  or track the authored magnitude. Assert it: change a `RealmDef.power`, `factor` is unchanged.
  That makes the ADR 0050 rate/magnitude split machine-checked rather than a comment.
- **The bound survives.** `RATE_STEP^29 < 2.0`, and `RATE_STEP` stays at or below the smallest
  per-realm step in the authored work budget (`AGENTS.md:128`), or the rate outruns the price
  and the deep realms get cheap. `RATE_STEP` is authored, not derived.
- **Migration is a mechanical rename:** `QiRealmProfile.factor`, `BodyRealmProfile.factor`,
  `MindRealmProfile.factor` -> `RealmRate.factor`; `*RealmProfile.NEUTRAL` ->
  `RealmRate.NEUTRAL`. Six source call sites — `qi_cultivation/training.gd:44`,
  `qi_cultivation/provider.gd:54-55`, `body_cultivation/training.gd:66`,
  `body_cultivation/provider.gd:63-64`, `mind_cultivation/training.gd:61`,
  `mind_cultivation/provider.gd:63-64` — plus the callers under `game/tests/`.
- **`AGENTS.md:126-127` is wrong and this ADR supersedes that claim.** `RATE_STEP` is not
  "deliberately triplicated": the stated reason fails against both `LAYER_DEPS` and the
  registry. `AGENTS.md:126-127` is corrected to name `core/realm_rate.gd`; `AGENTS.md:128` is
  unaffected. An ADR is required because this is a `core/` change and because it corrects a
  rule `AGENTS.md` states in its own text.

## Consequences

- One rate curve for the three paths. Retuning `RATE_STEP` cannot desynchronise two copies.
- `test_realm_rate_parity.gd` goes with its subject. `test_realm_rate.gd` carries the
  monotonicity, span and `NEUTRAL` pins forward and adds the `RealmDef.power` invariance check.
- `tools arch` reports the same edge count: `core` is already a declared dep of all three.