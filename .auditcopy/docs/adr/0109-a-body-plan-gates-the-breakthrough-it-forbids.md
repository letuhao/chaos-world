# 0109 A body plan gates the breakthrough it forbids, and the gate is a refusal with a reason

- Status: Accepted
- Date: 2026-10-03
- Depends on: ADR 0062 (a race is a body plan), ADR 0078 (a race is attached but never assigned)
- Amends: ADR 0062's claim that the body answers "what realm can it never pass"

## Context

ADR 0078 recorded a true finding against ADR 0062, and it still holds:

> A race gates nothing yet. `race_gate.gd` exists and is testable, but no gate reads it.

Verified now: `RaceApi` and `RaceGate` have **zero occurrences** in `body_cultivation`,
`qi_cultivation`, `mind_cultivation` or `core`. The whole partition rule — every race closes at
least one of qi/body/mind — is authored content that nothing enforces. A player who picks a
stoneborn can walk straight into mind cultivation, because nothing ever asked.

That is the specific failure ADR 0062 was written to prevent. It closed paths on paper and left
them open in play, which is worse than not authoring the field: the content test says the rule
holds and the game does not honour it.

## Decision

- **The three cultivation modules read `RaceGate` at the breakthrough seam, and nowhere else.**
  `QiCultivationApi.attempt_breakthrough`, `BodyCultivationApi`'s equivalent and
  `MindCultivationApi`'s consult it before rolling. It is a **precondition**, not a modifier: it
  can refuse, and it can never make a breakthrough easier.
- **`race` is added as a declared dependency of `qi_cultivation`, `body_cultivation` and
  `mind_cultivation`** in `tools/arch/registry.json`. This is a three-way edge, so the cycle check
  matters: `race` depends on `[contracts, core]` only and references none of them, so the graph
  stays acyclic.
- **A closed path refuses with a reason, using the existing vocabulary.** The refusal is
  `RaceGate.path_unmet(actor, path_id)`, whose entries are the `{kind, id, required, actual, label}`
  shape `ItemRequirement.unmet()` already produces — so a breakthrough screen renders the reason
  without inventing wording. It is a refusal, not a silent false.
- **`realm_ceiling` is enforced at the same seam.** A body with a hard ceiling cannot attempt the
  realm above it. This is the second half of ADR 0062's claim, which was equally unenforced.
- **No cultivation module reaches past `RaceApi`/`RaceGate`.** They declare the dep and call the
  facade, so the boundary rule and `tools arch` both hold.

## Consequences

- The partition rule stops being content and becomes behaviour: the `closed_paths` a race author
  writes is now the reason a player cannot take a path they were told they cannot take.
- The refusal is **previewable**, not just refusable — the same `path_unmet` list answers "may I
  attempt this?" before the player commits, which is the ADR 0034 rule that a gate and its
  preview wording must be the same string.
- An actor with **no race takes no restriction**, and that is deliberate and unchanged: a content
  gap must not gate content, or an unauthored body would lock a player out of a path.
- `tools arch` now sees three new declared edges. If anyone later makes `race` depend on a
  cultivation module the cycle check fails immediately, which is the point of declaring it.
- **Known gap, owned here:** nothing enforces `lifespan`, so a short-lived race has no mechanical
  consequence yet. A third gate, and a real decision about what expires — recorded rather than
  quietly dropped.