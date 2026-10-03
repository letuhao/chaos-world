# 0059 A path-scoped realm gate reads one path's rank, and a dual technique commits both

- Status: Accepted
- Date: 2026-10-03
- Supersedes: nothing. Refines ADR 0053 and ADR 0054's requirement consequence.

## Context

`ItemRequirement._actor_realm_index` takes the **maximum** ordinal across `PathState.ALL`,
documented as deliberate so an item never demands one specific system. That is right for
equipment. It is wrong for a technique: a qi technique gated on "best path" is learnable by
an actor whose body is at R30 and whose qi has never moved past R3, which is precisely the
build the path-typed slots exist to make a mistake.

`PathState` already carries what is needed — `Actor.path(PathState.QI)` returns the one
`PathState`, and `RealmDefaults.ladder().index_of(state.rank_id)` is the same shared ordinal
the profile classes read. The blocker is purely the *shape* of the existing field: one
scalar compared against a max.

## Decision

- **`ItemRequirement` gains `min_path_realm: Dictionary`**, `path_id -> minimum ordinal`,
  default `{}`. Semantics: **every** named path must individually reach its floor. Empty
  means no path-scoped restriction, exactly like `is_empty()` today, and it composes with
  `min_realm_index` rather than replacing it — `min_realm_index` stays the "any path" gate
  items use, `min_path_realm` is the "this path" gate techniques use. Read by a path module
  through `PathState` and `RealmDefaults`, never through a sibling's facade: both are in
  `contracts/` and `core/`, so reading them breaks no boundary.
- **A `DUAL` technique requires both of its paths at the floor.** It is not an either/or.
  An either/or reading would let an actor hold a qi+body technique while at R30 qi and R1
  body, which makes the *other* path free and deletes the only slot cost that a dual build
  pays. Requiring both turns a second path into a second investment, which is the same
  reason the realm ladder is priced in work rather than granted. The cost is that a dual
  technique has a smaller audience; the genre pays for that deliberately, and
  `modules/dual_cultivation/` already scopes its content to that audience.
- **A dual technique's weaker ceiling is expressed by grade and the ladder, not by a
  penalty field.** `MAG_GRADE` and `TechniqueDef.magnitude` already decide strength; a
  special "dual discount" multiplier would be a third way to say the same thing.
- **A `SHARED` technique uses `min_realm_index`** (best path) and never a path key.

## Consequences

- `min_realm_index` and `min_path_realm` are two gates with two meanings. The `unmet()`
  row for a path gate reports `path_id` as its `id`, so a panel can say which path is short
  without re-deriving anything.
- The three cultivation facades are each at the 12-method cap, so none of them grows. The
  technique module reads `PathState` directly and the path modules learn nothing about
  techniques — the dependency runs one way and needs no new facade method.
- `is_empty()` must include the new dictionary, or a profile carrying only a path gate
  would report as unrestricted and silently admit everyone.
- The alternative (either/or, one path at the floor) is recorded as DEF-0099 so a human
  can overrule this without reopening the ADR.