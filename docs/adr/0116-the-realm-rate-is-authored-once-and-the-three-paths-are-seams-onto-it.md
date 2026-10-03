# 0116 The realm rate is authored once and the three paths are seams onto it

- **Status**: accepted
- **Amends**: ADR 0066, ADR 0081 (both recorded the migration as complete; it had not begun)

## Context

ADR 0066 created `core/realm_rate.gd` and ordered the three `*RealmProfile.gd` copies
deleted. ADR 0081 then recorded the migration as done. Neither happened: three copies
survived with `RATE_STEP := 1.02` authored in all three, and six production call sites
used them.

The replacement guard could not see this. `tests/core/test_realm_rate.gd` called
`RealmRate.factor` three times and compared the results — asserting `x == x`. It passed
unchanged with all three copies intact, and its own header said the copies "were
byte-identical apart from their `class_name`". The deleted `test_realm_rate_parity.gd`
had named the exact failure: *nothing stops one path being retuned and the other two left
behind.*

A second defect: the rate's bound was `<= 1.05`, a typed-in constant **looser than the
data**. The real ceiling, computed from the authored `progress_required` ladders, is qi's
`dao_ancestor → primordial_origin` at `2900/2800` ≈ 1.0357. A retune to 1.04 satisfied the
old check and inverted qi's deepest breakthrough price.

## Decision

**1. One shared rate stands.** Not deference to the ADRs — the game already reads
`RealmRate` for this same question in `combat_engine` (the S1 damage gate) and `economy`
(valuation). Under per-path rates, one R30 actor's *training* would convert at 1.78× while
its *damage* was gated and its *money* priced by another number: two answers to "what is
R30 worth" inside a single actor, and incoherent today.

The honest case for per-path rates is real but is already carried by three *different
authored budgets* — body `progress_required` 40→4000, qi 100→2900, mind 100→13197. That
is a strictly more expressive knob than one compounding exponent: per realm, per path,
arbitrary shape. A second rate curve would put the same fact in an unauthored, invisible
place as well, which is ADR 0050's "a power-shaped number must be authored and visible or
not exist".

The price paid: mind training can no longer be made worth more per unit than body without
editing the authored mind budget.

**2. The three classes become rename seams.** `RATE_STEP` and `NEUTRAL` alias `core`,
`factor` delegates. Zero authored numbers in any module and **zero call-site edits**,
because six sites belonged to in-flight work. Retiring them is the mechanical
`*RealmProfile.factor → RealmRate.factor` rename, then deleting the three files.

**3. The guard compares four independent surfaces, not one surface with itself** — parity
across all 30 realms, constant parity, and a **structural pin that reads source text** and
rejects any `const RATE_STEP` that is not the alias.

**4. The bound is computed from the seeds**, not typed in. The first transition is skipped
because qi and mind author R1 and R2 equal, so the entry price has no predecessor.

## Consequences

- **`tools arch` cannot see any of this.** `BARE_REF_UNITS` excludes `modules/*`, so the
  GDScript guard is the only enforcement. That is the standing shape of this repo's
  invariants: the gate sees structure, the test sees meaning.
- **A numerically-identical fourth copy stays green under every value assertion.** Proven
  by mutation: a private `const RATE_STEP := 1.02` with its own `pow` produced
  **403 passed / 3 failed**, every value assertion green and only the structural pins
  firing. Value parity is therefore insufficient, and this is why the guard reads source
  rather than comparing numbers.
- Three `RATE_STEP` *names* remain, as aliases. "Not triplicated" is now true of authored
  numbers and still arguable of names, so `AGENTS.md` was corrected in the same change to
  say which is which.
- The first transition stays excluded by a property of the data rather than by
  convenience. If qi or mind ever author R1 ≠ R2 the exclusion can be revisited, and the
  test says so.