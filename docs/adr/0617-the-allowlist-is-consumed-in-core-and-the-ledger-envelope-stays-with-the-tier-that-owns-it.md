# 0617 The allowlist is consumed in `core`, and the ledger envelope stays with the tier

- Status: Accepted
- Date: 2026-10-06
- Depends on: ADR 0063 (a percent rides the member's own growth), ADR 0064 (position
  and standing never derive), ADR 0066 (one shared shape in `core`, never a
  per-module copy), ADR 0068 (a shape test, not a hope), ADR 0083 (three tiers, one
  vocabulary), ADR 0084 (recognition, access and transmission, never power), ADR 0271
  (a kind is registered, not nested), ADR 0278 (a new kind is a `.tres` drop)
- Amends: nothing. Supersedes nothing.
- Resolves: DEF-0337

## Context

ADR 0084 makes a position's allowlist the **only** stat surface an institution has,
and ADR 0278 ships one generic `InstitutionPositionDef` so a trading guild, a hunting
guild and a farmers' circle are content rather than modules. But 0278 **deliberately
omitted** the allowlist field, and it named why: the code that consumed it was
`SectProjection._grant`, inside `sect`. A generic allowlist with no projection is an
author writing numbers that go nowhere, so the field was withheld until the CONSUMER
moved.

The omission held. A guild could be founded, hold offices and publish standing — and
could not recognise anybody, because the one function that turns standing into a stat
modifier was unreachable from a kind that is not a sect.

## Decision

**1. THE CONSUMER IS IN `core/`; `InstitutionPositionDef` carries the allowlist.**
`core/institution_projection.gd` is a pure function of
`(allowlist, standing, source_tag, actor)` and names no module, no app and no clock —
which is the whole reason it could move down a layer. `core` is a LAYER, so this adds
zero edges. The loop it replaces was already a pure function of those four arguments;
the sect coupling was the catalog lookup and two envelope keys, and neither moved.

**2. `grant` VALIDATES, then STRIPS, then WRITES — and that order is the design.**
Stripping inside `grant` rather than leaving it to the caller is what makes a rebuild
idempotent by construction: a caller cannot compound by forgetting to. The validation
runs first so a **refusal is non-destructive** — a member does not lose recognition
they already hold because a `.tres` was mistyped (ADR 0083's third state is "this was
refused", and a refused verb writes nothing, ADR 0044).

*Measured, not designed:* the first version wrote without stripping. Five rebuilds
climbed the modifier stack `2, 4, 6, 8, 10, 12` while every assertion about the sheet
still looked plausible. The idempotence test caught it; nothing else would have.

**3. A SOURCE TAG is the inversion, and it beats a re-read of the definition.**
ADR 0084 has a ledger record what it granted so a rebuild can strip what it added. The
tag already answers that, and answers it *better*: it survives the defining `.tres`
being deleted, which is exactly the case ADR 0063 raises. So `grant` returns the
granted map for a panel or a history line to publish and **writes no ledger keys at
all** — `applied_standing` and `granted_percent` stay `sect`'s own, `InstitutionClaim`
grows no envelope, and three tiers do not grow three copies (ADR 0066).

**4. AN EMPTY ALLOWLIST IS CONTENT.** An office nobody is recognised for is a real
office — the ordinary member, a polity's administrative ministries — and it is
ADR 0083's FIRST state, not its third. All three shipped guild `.tres` files author
exactly this.

**5. THE CAP BOUNDS THE RATIO AND NEVER THE LEDGER'S NUMBER.** Nothing in the
projector reads `standing_cap` and nothing clamps. A guild publishing a cap of 150
hands a member at 150 exactly the recognition a member at 100 has, while the ledger
still reads 150 — which is ADR 0064's politics layer, and a clamp would delete it.

**6. An id the stat sheet cannot NAME is refused by name; an id it can name but that
reads zero is not.** A PERCENT on a stat with no derivation is `(0.0 + 0.0) * (1 + p)
= 0.0`, a grant that reads as landed and moves nothing. A stat reading zero because the
member invested nothing in it is an ordinary sheet. `tools arch` cannot see either, so
the runtime half is `unknown_stat` and the content half is a shape test over every id
the shipped `.tres` files name, measured on an actor invested in **every** attribute —
which is the only sheet on which "has no derivation" and "has no investment" separate.

**7. "NO FAULT" IS `null`, NOT `""`.** `unknown_stat` answers `null` or the offending
id, and the two cannot be told apart by their text. `{"": 0.0}` is an allowlist Godot
loads without complaint and `""` is a legal `String`, so the version that returned `""`
for both reported that allowlist CLEAN and then wrote a modifier on `&""` that no reader
can look up — a grant that exists, compounds, and is invisible. **A sentinel has to be a
value the domain cannot produce.**

## Consequences

- **A guild can now recognise a member**, and the grant falls when standing falls.
  `test_institution_projection.gd` founds The Lantern Exchange off its own `.tres`,
  seats a member, and measures the movement — including the demotion, which ADR 0084
  says must be as well tested as the promotion.
- **`SectProjection._grant` may now delegate its modifier loop** and keep only its two
  envelope writes. The drop-in is measured, not asserted: every allowlist any shipped
  `sect` OR `nation` office authors is pushed through the shared projection and must
  produce one PERCENT per id at the standing's own percent. `NationOfficeDef` is a
  **third** copy of the field, so a sect-only sweep would have reported "every shipped
  allowlist" while measuring half of them.
- **`SectPositionDef.recognises` should be DELETED, not carried.** It has zero callers
  and the read it performs now lives on `InstitutionProjection.recognises`. Two places
  naming an allowlist is ADR 0066's failure mode in a new place. `sect` was outside this
  slice's claim; the change is reported, not made.
- **The projector writes no ledger, so the tier that owns the claim still owns the
  envelope.** `InstitutionFounding.found` writes a claim and grants nothing; the
  projection is the second half and `app/` is where the two are wired. Until that line
  exists, a guild's grant is reachable and correct but **nothing in production calls it**
  — the same honest state `InstitutionBoot.install` records.
- **A modder's typo is now loud and local**: the refusal carries the offending id, so a
  panel can render it and the author can find it, rather than a silent zero.
- **`grant` writes ONE percent per id per tag.** `NationProjection.build` SUMS the
  percent of every held office, so `nation` cannot be migrated by handing this the union
  of its allowlists — the union grants one percent and drops the sum. Such a tier grants
  once per office under a **per-office** tag, which this makes free because every tag is
  namespaced. No allowlist VALUE is ever read, because an authored multiplier is the
  magnitude ADR 0084 refuses a second way.
- **The cap bounds EACH grant, not the sum across institutions.** A member of two guilds
  receives two capped percents on one id. ADR 0084's "no ladder of authored positions can
  add up to an uncapped multiplier" is about positions within one institution, where a
  member holds one at a time — so nothing is violated, but the political stat surface
  scales with how many institutions a player joins and that is a design consequence, not
  an oversight.