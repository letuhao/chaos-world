# 0881 the twelve aptitudes are the source layer and a build resolves the matrix from what it built

- Status: Accepted
- Date: 2026-10-06

## Context

- Keepverse ships an aptitude layer
  (`gk-core/src/FusionRpg.Core/Stats/Aptitudes/`): TWELVE aptitudes in three postures
  of four (`Might Fortitude Vigor Onslaught | Agility Composure Pierce Focus | Bulwark
  Retribution Precision Ferocity`), resolved by per-mille edges `k * share^gamma *
  span` onto derived channels, with points supplied by allocation scopes and a posture
  that is READ, never stored. It also ships an allocation UI, presets and respec.
- The roles the twelve name are the flat-pair vocabulary wave 1/2 just converted:
  Vigor -> `shield.*`, Pierce -> `penetration` + `shield.pen`, Precision -> `accuracy`,
  Ferocity -> `crit_chance`/`crit_damage`, Bulwark -> parry/block halves, Composure ->
  `crit_resist`, Agility -> `evasion`, Focus -> qi/efficiency, Might -> offence,
  Fortitude -> mitigation, Onslaught -> guard breaks + reflect, Retribution -> reflect.

## Decision

- `core/aptitude.gd` is the roster: three postures of four, ordinals append-only and
  Keepverse's own 0..11, the count derived from the lists. An aptitude is a SOURCE,
  never a channel: no aptitude id is ever a `derived()` id.
- `core/aptitude_edge.gd` + `core/aptitude_matrix.gd` are the matrix. An edge is
  `{channel, source, k, mode}`; the pure resolver turns POINTS into SHARES over the
  actor's COUNTED points, then `k * share^gamma * span` per edge, summing per channel.
  `CONTEST` is ladder-free (bounded contest points); `MAGNITUDE` takes the caller's
  ladder value — Keepverse PS-3's split, ported.
- The port is floats end to end. Keepverse's per-mille integer `k` and its two
  rounding points are NOT carried (our stat stack is floats); the formula is the same.
- NO allocation verb exists. Points arrive from the three majors' own resolution (qi,
  body, mind) and from learned techniques, and are re-resolved at BREAKTHROUGH and on
  LEARNING A TECHNIQUE. There is nothing to pick because there is no picker.
- A non-aptitude key neither grants nor dilutes; an empty or zeroed allocation resolves
  to nothing at all, not to zero-valued contributions; `validate()` NAMES a malformed
  edge (unknown source, empty channel, negative k) rather than letting it contribute
  nothing silently — Keepverse's load-time catch, kept.
- Keepverse's allocation scopes and layer weights are NOT ported yet: one pool now;
  per-major scoping lands only if the majors' grants need it, in its own change.
- The one shared spelling, `&"agility"` (`Stat` attribute AND aptitude id), is
  deliberate, exactly one id wide, pinned by a test; the two layers stay distinct.

## Consequences

- The matrix is testable with nothing configured — it is pure — and the shipped edge
  TABLE is data: it lands next with `core/aptitude_matrix.tres` and its own table test.
- Every build's identity is its DISTRIBUTION across the twelve: a build that spreads
  its practice pays `share^gamma` for it, which is what "any build resolves the matrix"
  means concretely.
- Next slices: the shipped edge table + the `ActorStats` contribution; then the three
  majors' grants and the breakthrough / technique-learn re-resolution hooks.
