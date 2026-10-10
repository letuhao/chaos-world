# 0942 the actor's public surface is a budget-and-ownership rule, not a count

- Status: Accepted
- Date: 2026-10-10

## Context

`gdlint`'s `max-public-methods` (20, instance methods; statics are not counted) flagged
`core/actor.gd` at 24 and `core/actor_stats.gd` at 22 — the two most-depended-on classes
in the tree, where every method has a caller.

**A public method on `Actor` is not a convenience wrapper — it is a contract with every
module.** So the fix must remove surface, never rename it away: the number of things that
can be asked of an actor is what the budget protects, and a count met by moving the same
verb into a component accessor is a real reduction only when the verb really was the
component's.

## Decision

**1. A forward that only forwards belongs where its rule lives.** Four one-line forwards
were removed; each was a second name for a rule owned elsewhere:

| removed | rule lives in | callers now |
|---|---|---|
| `Actor.set_relationship` / `Actor.affinity_with` | `ActorAffinity` | `actor.affinity_rules().…(actor, …)` — ONE public door replacing two |
| `Actor.polity_version` / `Actor.set_polity_version` | `ActorSave` | `ActorSave.polity_version(actor)` / `ActorSave.set_polity_version(actor, v)` |
| `ActorStats.set_context` | the actor that mints the sheet | `stats._set_context(...)` — renamed private, one caller (`Actor`) |

The affinity pair is the shape to copy: the two forwards each cost one public slot and
each said "keeps the name every caller already uses"; publishing the delegate instead
(`affinity_rules()`) keeps the rule where it lives and costs ONE slot for two verbs.

**2. An unused read is deleted, not kept for symmetry.** `Actor.starting_age_years()` had
zero callers once `race_projection.gd` applied the archived body plan's number to
`age_years` itself; it and its private `_starting_age_of` are gone. The constant
`STARTING_AGE_YEARS` stays — `age_years` still starts there for a body with no plan.

**3. Dead code is deleted.** `ActorStats.clear_providers()` had no caller in `src/`,
`tests/` or `tools/`.

## Consequences

- `actor.gd` 24 → 20 public instance methods; `actor_stats.gd` 22 → 20.
- **The budget is a design constraint, not a lint exemption**: no method was renamed to
  hide it, none made public to satisfy a caller, and no ignore comment was added.
- **A future verb on `Actor` costs an argument at review time.** The question is "which
  module's rule is this?"; if the answer is not "the actor's own", the verb belongs on
  the delegate that owns the rule (`ActorAffinity`, `ActorPools`, `ActorSave`) and the
  actor publishes that accessor once.
- Callers of the removed doors were re-pointed in the same change: `save/api.gd`,
  `tests/core/test_world_polity_ledger.gd`, `tests/core/test_actor_statuses.gd` and
  `tests/core/test_tribulation.gd`; a tree-wide sweep for every old spelling returns
  nothing.
