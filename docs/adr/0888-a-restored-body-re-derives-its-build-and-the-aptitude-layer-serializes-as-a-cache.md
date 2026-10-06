# 0888 a restored body re-derives its build and the aptitude layer serializes as a cache

- Status: Accepted
- Date: 2026-10-06

## Context

- The audit (DEF-0348) found the aptitude layer absent from persistence: `ActorStats`
  serialized nothing, so a loaded actor's points read `{}` and its ladder `1.0` until
  `TechniquesApi.attach` re-resolved by accident of accessing a codex, and its MAGNITUDE
  edges folded low for the rest of the session.
- The same audit found a PRE-EXISTING hole the aptitude layer sat on top of: nothing on
  the load path called `RealmScaling.apply` at all. `Actor.from_dict` restores base and
  paths, `ActorFactory.restore_cultivation` re-mounts providers and element halves, but
  the eight `RealmScaling.SCALED_STATS` multipliers were only ever written by
  `Breakthrough.try_advance` and `DomainSpawner`. A loaded R5 body therefore read
  `MAX_HEALTH`, `MAX_QI`, both attacks, both defenses and `STATUS_DEFENSE` at R1
  strength until its next breakthrough — and, once ADR 0887 shipped, so did the shield
  capacity the fold feeds.
- The owner chose BOTH remedies for the persistence question: serialize the layer AND
  refresh on load.

## Decision

- `ActorStats.to_dict()` / `from_dict(data)` carry the aptitude points and the ladder as
  primitives. `Actor.to_dict()` writes them under a `"stats"` key beside `"base"`;
  `Actor.from_dict` restores them right after the paths. The payload is a CACHE, never
  the truth: an absent key is the neutral default, and a re-derive REPLACES it.
- `ActorFactory.refresh_build(actor)` is the ONE refresh verb: `RealmScaling.apply`
  (which also pushes the aptitude ladder), `_refresh_element_realm`, then
  `AptitudeGrant.apply` (which re-derives the points from the restored build and
  replaces the cache). Idempotent by construction — all three strip or replace before
  writing.
- `restore_cultivation` calls it at its tail, so EVERY restore path funnels through the
  refresh: the workbench's `restore_actor`, `_mount_player_modules`, and any future
  caller cannot forget one of the three halves. The refresh also fixes the pre-existing
  realm hole above in the same change, because it is the same omission.

## Consequences

- A restored body's derived stats now equal the live body's, at a real realm, for the
  realm multiplier, the element halves, the ladder and the aptitude fold. That is the
  acceptance `tests/app/test_restored_build_refresh.gd` asserts, and the idempotence
  case pins the strip-before-write discipline.
- The cache means a body restored before anything re-derives it still carries its
  points; because `refresh_build` overwrites them from the build, a hand-edited or
  stale save cannot smuggle a build the body did not earn.
- Older payloads without `"stats"` restore the neutral default and are then refreshed
  from their paths, so no migration is required and no version bump is taken (an
  additive key both readers tolerate).
