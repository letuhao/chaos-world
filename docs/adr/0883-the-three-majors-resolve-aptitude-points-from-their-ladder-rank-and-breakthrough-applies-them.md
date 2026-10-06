# 0883 the three majors resolve aptitude points from their ladder rank and breakthrough applies them

- Status: Accepted
- Date: 2026-10-06

## Context

- ADR 0881/0882 wired the matrix and the fold, but nothing FED points: every actor's
  store was empty and the layer was inert in production.
- The port's rule, from the owner: nothing is user-picked. Aptitude points are resolved
  from what an actor has BUILT, at the two stages a build changes identity —
  breakthrough and technique learn.
- `Breakthrough.try_advance` is the ONE success site all three majors reach (its own
  docblock: the milestone commit lives there so no path can forget it), and it already
  re-scales. `TechniquesApi.learn` is the one moment a codex row is written.

## Decision

- The three majors ARE the three postures: `body_cultivation -> force`,
  `qi_cultivation -> finesse`, `mind_cultivation -> bastion`. A build's posture is
  therefore a READ (`AptitudeGrant.dominant_posture`, Keepverse's `DominantPosture`
  rule: ties resolve to NONE), never a stored field and never a pick.
- A started path grants `(ladder_index + 1) * per_realm` points, split evenly across its
  posture's four aptitudes. The budgets are DATA (`core/aptitude_grants.tres`), and only
  their RATIOS matter — the matrix's share normalisation cancels absolute size.
- `AptitudeGrant.apply(actor)` REPLACES the store from the build. Replace, never merge:
  "resolve from what you built" means a stale value nobody built must not survive.
- The hook is `Breakthrough.try_advance`, after `RealmScaling.apply` (so the ladder the
  next fold reads is already pushed) and before `path_advanced` is emitted.
- `technique_points` states what ONE learned technique adds, into the dominant posture,
  split the same way. The learn hook lands in this wave's next slice, in the techniques
  module, which owns the codex count; core gains no knowledge of a module component.
- An unstarted path, an unknown path, an off-ladder rank and a malformed row each grant
  NOTHING — all four are legitimate build states, so none of them is an error.

## Consequences

- Breakthrough now changes an actor's statistics through the matrix, not only its ladder
  position: the same actor at a higher realm has a different aptitude distribution once
  its majors advance, which is what "any build resolves the matrix" means in play.
- The seed budgets (`4.0` per realm per major, `2.0` per technique) are an initial
  authored pass, not balance.
- Next: the technique-learn half — the techniques module adds `technique_points` into
  the dominant posture on learn, and re-applies after a breakthrough (which replaced the
  store).
