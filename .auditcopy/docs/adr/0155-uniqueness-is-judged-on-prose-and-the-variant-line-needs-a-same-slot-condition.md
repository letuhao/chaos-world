# 0155 Uniqueness is judged on prose, and the variant line needs a same-slot condition

- Status: Accepted
- Date: 2026-10-04

## Context

The completion gate for the character program is 1000 characters that are each
"not a duplicate or shallow variant" and that meet "diversity thresholds".
`unique_characters check` verified neither. It checked each row in isolation, and
every defect below is a RELATIONSHIP between two rows that no per-record check can
see.

The failure this guards is specific and has already happened in this program in a
different tool: an agent satisfies the letter of a requirement by renaming.
Renaming is the cheapest way to look original, so any uniqueness check keyed on
names, ids, or per-row fields passes a catalog of one character written
forty times.

## Decision

**Uniqueness is judged on `canon.role_in_story` + `canon.lore` +
`canon.first_appearance`, as token Jaccard.** Not on names, and deliberately not
on `appearance`: two characters with the same build are not duplicates, and
including appearance fields would fail every set of siblings and look-alikes,
which is a shape a good cast actually has.

Exact Jaccard rather than an embedding or a model. A validator that can be argued
with is not a validator, and this one runs in `tools check`.

**Two thresholds, and the shallow-variant line additionally requires an identical
structural slot** — same `role`, same `identity.path`, same `appearance.race`,
same `identity.faction`:

- `>= 0.80` — duplicate. Fails.
- `>= 0.55` AND same slot — shallow variant. Fails.

The slot condition is what makes 0.55 safe. Two unrelated characters will write
similar sentences about the same world; what makes it a monoculture is the slot
as well. Two characters in the same role, on the same path, of the same race, in
the same faction, saying substantially the same thing, is the monoculture this
catalog exists to prevent — whatever they are called.

**Name collision is a separate failure.** A name is the one field a reader sees,
so two characters sharing one is a defect even when the backgrounds are
unrelated, and the Jaccard check cannot see it.

**Concentration is reported on `path` and `race` only** (`DIVERSITY_GUARDED_AXES`),
never on `role`. `role` has three values, so in a four-record cast one must repeat
and reach 2/4 = 50% by arithmetic alone. Guarding it would fire on every catalog
under roughly eight characters and teach authors to invent meaningless roles to
silence a linter. `path` and `race` grow with the setting, so concentration there
is a fact about the world rather than about the sample size.

Concentration is **reported, never failed by default**; `diversity --fail-on-warn`
is the release-gate form.

**Duplicate detection is O(n²) pairwise, on purpose.** At 1000 records that is
roughly 500k comparisons over precomputed token sets — seconds, not minutes. A
candidate prefilter would trade a known false-negative rate for speed this does not
need, and the false negative it introduces is invisible and specific: two agents
who independently write the same character, which is precisely the case worth
catching.

Drafts with an empty identity text are skipped rather than compared.

## Consequences

- `_duplicate_findings` runs over the whole catalog inside `_validate`, so it is
  part of `unique_characters check` and therefore of `tools check`.
- `unique_characters diversity` is the read-only view an authoring agent steers
  by, and it prints the tag axes in use so an author can see a monoculture forming
  before it reaches the gate.
- The thresholds are single constants with the reasoning attached. Moving 0.55 is
  a decision about what counts as the same character, not a tuning knob.
- The self-test cases are calibrated to specific measured scores, and the comments
  record them: 0.92 for a one-word swap (which hits the *duplicate* line and would
  pass a variant case for the wrong reason), 0.71 for the fixture that exercises
  the variant line, 0.12 for a fully rewritten background. A fixture that cannot
  distinguish the two lines tests nothing about either (INC-0016).