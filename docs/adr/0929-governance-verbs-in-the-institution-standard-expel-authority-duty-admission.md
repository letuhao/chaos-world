# 0929 Governance verbs in the institution standard: expel, authority, duty, admission

- Status: Proposed
- Date: 2026-10-08

## Context

The standard could found, join, leave and project, but a guild could not govern: the
shipped Lantern Exchange authors `expel` on its top seat and nothing executed it, duty
lines opened on every join that nothing could settle, and admission was ungated. The
four shipped contracts (`Expellable`, `Authorised`, `Dutiable`, `AdmitTable`) decide all
four acts and return plans; no applier existed.

## Decision

Four verbs on `InstitutionMembership`, each driving its contract and applying the plan;
a refusal writes nothing (checks run above the commit line, ADR 0044):

- `expel(registry, actor, institution_id, target: Actor, force)`: costs are DERIVED —
  the expelled forfeits their whole standing, the expeller pays that plus
  `EXPEL_MARGIN` — and the contract owns the rule (authority, self, membership, peer,
  asymmetry). The target is an `Actor` because the claim lives on the body; severing a
  roster row by id would strand the recognition. D8: the cost IS the counter.
- `has_authority(...)`: the `Authorised.holds` read, writing nothing on any path.
  `serve` and admission enforce exactly what their contracts demand (nothing about
  authority: a debt needing permission to pay is a trap). D8: the peer rule counters it.
- `serve(registry, actor, institution_id, periods)`: the `Dutiable` clamp per line,
  keeping zero keys; `nothing_owed`/`no_periods` are the contract's. D8: settled count.
- `join` takes an optional `admit` table (the def authors NO admission rows, so the
  caller hands `{invite_only, invited, requirements, values}` in); empty is today's
  open house. D8: capacity seats, invitation admits.

## Consequences

- A guild purges, gates, collects and refuses by named reason; `sect` keeps its own
  expel until a later slice delegates it (prediction: it should, the plan keys match).
- `test_institution_membership_shape.gd` asserts the 12-verb surface and must grow the
  three new names (exact edit reported, file outside this slice).
- MEASURED while proving admission: `AdmitTable._all_vacant` calls `String(actual)`
  where numeric unmet rows carry a float, and `String(float)` raises — so any numeric
  bar aborts `admits()` mid-call. One-word fix reported (`str(...)`), file outside
  this slice; the shipped suite never drove `admits()` with a numerically-unmet row.
