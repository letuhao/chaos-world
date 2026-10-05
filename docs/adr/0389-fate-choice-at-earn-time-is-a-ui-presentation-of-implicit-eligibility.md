# 0389 Fate choice at earn time is a UI presentation of implicit eligibility

- Status: Accepted
- Date: 2026-10-06
- Amends: ADR 0065 (fate is earned, never chosen)
- Consistent with: ADR 0113 (fact ledger), ADR 0196 (fate tag vocabulary)

## Context

When a fate's trigger fires and multiple fates are eligible, the UI presents a
choice of 1 of 2-3 fates. The backend resolves this through existing earn logic:
the "choice" is which fate's trigger condition is already met. This is not a new
earn path — it is a UI presentation of implicit backend eligibility.

## Decision

- **`FateDef.eligible_choices`** is a new `@export` field: a list of fate ids
  that can be offered together when this fate's trigger fires. Empty means the
  fate is never part of a choice group.
- **The choice is a UI presentation, not a backend branch.** The backend does
  not choose. When multiple fates in a choice group are eligible (their gate
  conditions are met and the actor does not already hold them), the UI presents
  them as a choice. The player picks one, and the backend earns it through the
  existing `earn_fate` path.
- **The earn-only invariant is preserved.** The choice is which fate to earn,
  not whether to earn it. There is no purchase, no cheat, no trade. The fate is
  still earned through `earn_fate`, which is exactly-once and permanent.
- **A fate is eligible when:** the actor does not already hold it, and its gate
  conditions (prerequisites) are met. The eligibility check reads the same gate
  evaluator (`DestinyGate`) that every other fate gate uses.
- **The choice group is symmetric.** If fate A lists fate B in `eligible_choices`,
  then fate B lists fate A. The UI reads `eligible_choices` from the fate whose
  trigger fired and presents all eligible fates in that group.
- **No new gate verb.** The choice is not a gate — it is a UI presentation.
  The gate evaluator is unchanged.

## Consequences

- The UI reads `eligible_choices` from the fate definition and, when multiple
  fates in the group are eligible, presents them as a choice.
- The backend is unchanged: `earn_fate` is still the only way to earn a fate.
- The choice is a presentation of which fate's trigger already fired, not a new
  earn path. The player is choosing between fates they have already earned the
  right to, not purchasing or cheating.
- Content authors can create choice groups by authoring `eligible_choices` on
  fate `.tres` files. No code change is needed.
