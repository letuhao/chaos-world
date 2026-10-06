# 0882 the matrix folds into the actor before modifiers and the realm pushes the ladder

- Status: Accepted
- Date: 2026-10-06

## Context

- ADR 0881 shipped the pure matrix (roster, edges, shares, `k * share^gamma * span`) but
  wired nothing: no actor carried points and no table existed.
- `ActorStats._recompute` applies `(base + flat) * (1 + percent) * mult` through `_put`,
  and the provider path applies the same formula to a provider's baseline. A
  contribution added AFTER `_put` would double-apply a channel's flat/percent/mult.
- The realm ladder already enters through `RealmScaling.apply`, which writes a MULT
  modifier on `SCALED_STATS` and already runs at BREAKTHROUGH (`core/breakthrough.gd`).

## Decision

- The table is DATA: `core/aptitude_table.tres` holds `edge_rows` (one dictionary per
  edge — `core/time_ladder_table.tres`'s own table shape), plus `share_exponent` and
  `contest_span`. `AptitudeTable.to_edges()` compiles rows to typed edges once; a row
  that cannot compile is dropped, and the table's test pins
  `to_edges().size() == edge_rows.size()` so a dropped row is caught, not silent.
- `ActorStats` gains the aptitude store (`set_aptitude`/`set_aptitudes`, `aptitude`,
  `aptitude_points`) and folds the matrix FIRST in `_recompute`, by injecting each
  contribution into the channel's FLAT bucket. The contribution then enters the same
  formula as every other source, exactly once: a channel with both an attribute formula
  and an edge sums its bases before the modifier math.
- The ladder is PUSHED, never computed: `RealmScaling.apply` calls
  `stats.set_aptitude_ladder(realm.power)` (neutral `1.0` when no path). MAGNITUDE edges
  read it; CONTEST edges never do.
- Two authored-data guards, both pinned by the table test: a MAGNITUDE edge must not
  target a `RealmScaling.SCALED_STATS` channel (the realm MULT already scales those,
  so an edge on top would apply the ladder twice), and one channel carries ONE climb
  behavior — every edge onto it shares a mode.
- Every aptitude feeds at least one channel and every `k` is positive: an aptitude with
  no edge is decoration and a zero-k edge is a dead wire.
- The seed coefficients are an INITIAL AUTHORED PASS, not balance. Retuning them is a
  balance change; the table's SHAPE is this ADR's.
- An edge onto a channel a PROVIDER owns is invisible: the provider path computes that
  id's baseline from a fresh `_buckets()` and overrides the derived value. Stated
  rather than guarded (no generic registry exists to check it), which is why the seed
  feeds core/combat ids only.

## Consequences

- An actor with no aptitudes is byte-identical to before: the fold returns before it
  even loads the table.
- The breakthrough stage already re-resolves the ladder because it already calls
  `RealmScaling.apply`; the second stage (technique learn) lands with the majors' grants.
- Next: the three majors' own resolution of points (what a build HAS DONE feeds which
  aptitudes) and the technique-learn re-resolution hook.
