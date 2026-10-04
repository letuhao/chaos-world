# 0154 The importer merges provenance and never dedupes by substring

- Status: Accepted
- Date: 2026-10-04

## Context

`lore ingest` merges imported records into authored ones. The merge has been
correct about prose since ADR 0144's incident: `AGENT_OWNED_FIELDS` protects
`summary`, `tags`, `name`, `type`, and `lore_ref`, and `attributes` is merged key
by key with `lore_depth` protected explicitly.

Two defects survived that, and both were invisible in the way this program can least
afford.

**`provenance` was assigned, not merged.** It was not in `AGENT_OWNED_FIELDS`, so
the importer's block overwrote the current one wholesale. Every re-import therefore
erased `author`, `created`, and every `abstract-pattern:` basis entry — while the
run still printed `agent-authored records preserved`, because the *prose* really did
survive. The half of the record that says WHO wrote a thing and WHY was the half
being eaten. Measured on this tree: 372 records lost their agent provenance, and
`cosmology.body_dao` lost `abstract-pattern:a-reading-needs-the-smallest-budget-that-holds-it`
— the actual derivation of its reading.

**`_is_import_line` deduplicated by substring.** To avoid duplicating its own
output on a re-run, the importer excluded existing lines containing the literal
`"tools lore ingest"`. That is a text search over a whole JSON blob, so any record
mentioning the importer anywhere was dropped from `existing` and replaced wholesale.
An imported record an agent later *extended* keeps `author: tools lore ingest` and
gains `extended_by` — so the NORMAL growth path for this bible was the broken one.
`civilizations.star_regent` lost `extended_by: w3-civs` on every re-ingest.

The existing self-test had the evidence in it and did not read it: its fixture has
always contained `"provenance": {"author": "an-agent"}` and has never asserted on
provenance. Three fields were asserted; the fourth was written down and ignored
(INC-0016).

## Decision

**`provenance` is merged by `_merge_provenance`, never assigned.** The importer
owns exactly one provenance field, `schema_version`. Everything else is the agent's:
`author` outranks the importer's, `created` stays the date the record was actually
authored, and `basis` is a union so a re-import that no longer sees the game file an
entry came from cannot delete the record of it.

**Every existing line is a merge candidate, including the importer's own.** Keyed
merging on `id` already de-duplicates correctly. A text predicate that decides
whether a record is replaceable is unsound against JSON, where an agent's
`extended_by` sits in the same object as the importer's `author`.

**The "preserved" report counts parsed records carrying agent work**, via
`_carries_agent_work`: a non-importer `author`, an `extended_by`, or a basis entry
more specific than the `authored-game-data` marker. The old count used the same
substring predicate, so it reported a number unrelated to what the merge preserved.

## Consequences

- `lore ingest` is idempotent: two consecutive runs now produce a zero-line diff.
  Verified by snapshot-and-diff, not by the absence of an error.
- `attributes` and `provenance` are both merges, so `_import_view` excludes both
  from the "overwritten" report; a preserved record legitimately differs from a
  fresh import there.
- The repair was done by restoring provenance from `HEAD`, which was authoritative
  because `lore/` was clean before the damaging run. A dirty tree would have needed
  the same care per record — the lesson is that `lore/` should be committed before
  any `lore ingest`.
- `tools/selftest_cases.py` asserts the red paths: agent `author`, `created`, the
  `abstract-pattern:` basis entry, and `extended_by` on an importer-authored record.
  It also asserts the **counterweight** — that a record no agent touched still has
  its game-owned scalars refreshed and still carries `schema_version` — because
  "preserve the agent's work" is otherwise satisfiable by never overwriting anything,
  which would pass the preservation case while letting the bible drift from the
  authored `.tres` with nothing reporting it.
- `--force` remains the deliberate, announced destructive path.