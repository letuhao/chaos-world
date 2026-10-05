# 0399 The sect tier runs on the generic founding path: a profile adapter, one envelope, and one rename

- Status: Accepted
- Date: 2026-10-06
- Depends on: ADR 0271 (a kind is registered, not nested; the generic `found` takes a profile),
  ADR 0278 (a new organization kind is a `.tres` drop), ADR 0083 (three tiers, one vocabulary),
  ADR 0084 (recognition, access and transmission, never power), ADR 0064 (position and standing
  never derive from each other), ADR 0066 (one shared curve, never a per-module copy)
- Amends: nothing. Supersedes: nothing.
- Resolves: the sect half of ADR 0271's "the sect migration is the next slice"

## Context

ADR 0271 decision 2 built `core/institution_founding.gd` and left `sect_founding.gd` READ ONLY
until this slice. `SectApi.found` assembled the ledger itself: `SectFounding.write` built a
skeleton, a roster, a treasury, an obligation merge and a fit grant, and the module kept its own
price gate and its own draw. A guild founded through the generic path and a sect founded through
the module path were two implementations of one verb, which is the failure this programme exists
to remove — and the reason a guild could not be the second real tier.

## Decision

**1. `SectApi.found` is PROFILE ASSEMBLY plus `InstitutionFounding.found`.** `SectFounding.write`
is deleted. What stayed in `sect` is only what `core/` cannot know: the authored cost, the standing
cap, the treasury prefixes, the top office, and the founding fit grant capped by a doctrine's own
`affinity_floor`. `SectFounding.profile` assembles them as primitives.

**The refusal ORDER is unchanged** — `no_actor`, `unknown_sect`, `unknown_doctrine`,
`already_founded`, `no_top_position`, `founding_cost_unmet` — because the first three are asked in
the facade (the profile cannot be built without a def and a doctrine) and the last three come back
out of the generic writer, whose own tail is the same.

**2. The generic writer returns a CLAIM; `SectState.normalize` owns the ENVELOPE.** The claim is
eleven keys. The sect is sixteen: `doctrine`, `succession`, `schisms`, `history`,
`applied_standing`, `granted_percent` on top of the claim. Handing one to the other without
normalizing dropped half the ledger, and the symptom was `_record` reading a missing `history` key
— which reads like a broken verb rather than a missing envelope.

**3. `founding_cost`: the PROFILE ADAPTER translates, and `core/` keeps reading a NUMBER.**
`SectDef.founding_cost` is authored `{currency, amount, found, outstanding}`; `InstitutionDef`'s is
an `int` and its own `founding_profile()` passes it straight through. `InstitutionFounding.cost`
coerces a non-numeric value to `0` **without raising**, so a profile carrying the raw dictionary
founds EVERY SECT FOR FREE — measured, with the red path asserted in `test_sect_migration.gd`.
Rejected the alternative: teaching `core/` to accept the dictionary would make the generic def's
own authored shape the second one, and `currency` is a display concept with no other use in `core/`,
which is the mistake `InstitutionLedger` refuses one layer down by not knowing its own save slot.
The profile is documented as "a plain dictionary of primitives the tier assembles from its own
defs"; translating an authored shape into that contract is the tier's job.

**4. `FUNDING_POOL` stays `sect_founding_funds`, and the profile NAMES it.** The pool id is written
into every actor's save, so it is a compatibility namespace rather than a rule worth sharing — the
same reasoning `InstitutionLedger` gives for `SOURCE_PREFIX`. The funding RULE is shared; the
currency is this tier's.

**5. The sect REGISTERS its own kind, into the shared registry and only when absent.** Nothing ships
the `sect` row: `InstitutionBoot.install()` discovers `.tres` under `res://data/institutions/`, and
sect content lives at `res://data/sect/` on its own def class — and `install()` has no production
caller yet (DEF-0326). A tier that cannot answer its own capability question would be refused
`unknown_kind` on every founding. Whoever gets there first wins and there is one row per process.

**6. The ONE observable change: the treasury's opening line is renamed.** `sect` opened
`treasury_<id>_hall`; the generic writer opens `treasury_<id>_all`. They were the SAME line under
two names, so exactly one survives and the surviving name is the generic one. It is a line id and
not a number: nothing settles a treasury line (`SectDuty` settles `claim.obligation`, a different
map), and `SectState.normalize` filters on the `treasury_<id>_` PREFIX, so a save written before
this carries its `_hall` line rather than losing it silently.

**7. `FIT_CAP` is BOUNDED BY, not asserted EQUAL TO.** The instruction was to assert
`SectState.FIT_CAP == 100` against the founding cap. That assertion cannot be made: `FIT_CAP` bounds
the fit AXIS and `FOUNDER_FIT_CAP` bounds the founding GRANT, and both being round numbers is a
coincidence rather than a relationship — writing them as equal would assert the coincidence and fail
the day either was retuned. What is asserted instead is the two real bounds: the grant is a
DERIVATION of the points rather than a second number, it never exceeds `FIT_CAP`, and the one place a
`.tres` author's `min_purity` meets the ceiling (`SectDef.member_obligation_lines`) is pinned for
every shipped sect.

**8. The claim shape is pinned by a TEST.** `tools arch` reads references, and `BARE_REF_UNITS` is
`("ui", "app", "contracts")` — so a second `(position, standing, obligation, standing_cap)` class in
`modules/*` or `core/` reports ZERO violations. `tests/core/test_institution_claim_shape_single.gd`
is that human expressed as an assertion.

## Consequences

- **DEF-0333 is NOT closed by this slice**, and the reason is a boundary rather than a difficulty.
  A trading guild cannot project recognition because `InstitutionPositionDef` has no
  `standing_percent_stats` AND `SectProjection._grant` is the only consumer of one. Both halves are
  `core/`, outside this slice's claim. Recorded with the plan in `docs/deferred.jsonl`.
- **`InstitutionClaim.from_dict` does not clamp `standing` into `standing_cap`**; `SectState.normalize`
  and `InstitutionLedger.read` both do. A hand-edited save carrying 999 on a cap of 40 yields a
  claim of 999 and a ledger of 40. Bounded in consequence (`normalized()` clamps, the percent is
  capped) and pinned as a measurement in the shape suite. `core/`'s to fix, one clamp in one method.
- **`SectPositionDef.recognises` has zero callers.** Dead content that the DEF-0333 extraction must
  either carry into `core/` or delete.
- **`sect` is now the authority on its own kind row.** `InstitutionRegistry.instance()` gains a `sect`
  row the first time any founding resolves. Every registry suite builds its own instance, so nothing
  else observes it.
- **The sect suite is 1566 tests and stayed green**, with three founding-treasury assertions rewritten
  to the surviving line name and the rest untouched.