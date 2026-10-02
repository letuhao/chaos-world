# 0050 Realm strength is authored data, not a computed curve

- Status: Accepted
- Date: 2026-10-02
- Supersedes: ADR 0042 (one power ladder, one data block, one guard)

## Context

ADR 0042 put every magnitude in the game behind one function, `P(Θ) = C · exp(a·r + b·r² + c·s)`,
with `Θ` the realm index. It solved a real defect: four systems each answered "how strong is
this?" and Mind's damage channel sat 154x above body and qi at the same realm.

It then stopped paying for itself.

- **The shape outlived the need.** Once every reader agreed, the ladder's value was that they
  agreed. What it became instead was a reason no subsystem could own its own numbers: any
  new magnitude had to be routed through a curve that was already superlinear, or a guard had
  to be widened.
- **The endpoint became unreadable.** The shipped dials put `P(29)` at **1.13e46**. No stat,
  save payload or UI row carries that, so the "magnitude" read was a number only a curve
  could produce and only a curve could consume.
- **The guard was a tax on honest code.** `tools power check` failed any
  `1.0 + realm_index * k` in `src/`, so a subsystem with a genuinely bounded, genuinely local
  number had to write `# power: rate-read` to be allowed to exist. A rule that forbids the
  obvious shape does not remove private curves; it teaches people to annotate them.
- **Two shapes had already forced their way in.** `PowerLadder.value` was called with `realm_index`
  by tribulation and with `realm_index * stage_span` everywhere else — the same function, two
  disagreeing index conventions, both correct in isolation.

The owner's decision: remove the ladder.

## Decision

- **A realm's strength is authored data.** `core/realm_power_table.tres` holds one multiplier
  per realm id. The runtime reads it verbatim. Nothing in `src/` computes a magnitude from a
  realm index.
- **`RealmDef.power` carries the number**, loaded from that table in `RealmDefaults._all()`.
  It is an **input**, never a cached derived value — the trap that deleted this field once,
  when filling it from the ladder made building the ladder recurse into itself.
- **Keyed by realm id, not by ladder position.** A realm inserted mid-ladder then cannot
  silently shift every realm below it onto the wrong number. A missing entry resolves to 1.0
  (unscaled), never 0.0.
- **`tools/realm_power.py` emits and guards the table.** `emit` writes it from an authored
  per-tier step (1.12 / 1.22 / 1.32 / 1.45) and refuses to overwrite without `--force`;
  `check` asserts *shape* — one entry per realm and no others, R1 at 1.0, strictly rising,
  finite, top at or below 1e6 — **not** the recipe. A guard that re-derived the numbers would
  make the recipe the real source of truth and the file a cache, which is ADR 0042's failure
  wearing a data file as a disguise. `emit` exists so the first draft is arithmetic, not a
  language model guessing thirty balance numbers.
- **`RealmScaling` reads `realm.power`** and nothing else.
- **`Tribulation.difficulty` is Tribulation's own rating**: `TYPE_PRESSURE[type] *
  max_waves`. Six authored constants and the wave count that already existed. Difficulty is a
  challenge rating, not a stat magnitude; pricing it off the realm's stat multiplier made the
  reward table a second balance dial nobody owned and pushed the essence award toward the
  9999 pool ceiling. It also removes a latent bug: an unknown realm id used to yield
  difficulty 0.0, a free heavenly tribulation.
- **`PowerLadder`, `PowerScaleTuning`, `power_scale.tres` and `tools/power.py` are deleted**,
  along with the `tools check` step. `tools/options.py` and `tools/cultivation/*` read the
  table instead.

## Consequences

- **Escalation survives as data.** The step into a higher tier is bigger than the step below it
  (1.12 → 1.22 → 1.32 → 1.45), so a Transcendent arrival still costs more than an Immortal
  one. `test_realm_power.gd` pins that property on the numbers.
- **R30 is 551x R1**, near the 601x the pre-ADR-0042 per-tier ladders used (ADR 0016), so the
  seed work requirements and capacities already on disk are not re-based by orders of
  magnitude. This is a starting point for a balance ruling, not the ruling.
- **Retuning is a one-line data edit.** No formula to re-derive, no pin to re-solve, no guard
  to widen, and no test that must be re-pinned to a pasted number.
- **No shared magnitude is left to hide a curve in.** A subsystem that needs a realm-shaped
  number must now say whose number it is and where it lives. That is the cost, and it is the
  point: the ladder's failure was never that four systems disagreed, it was that agreeing cost
  every subsystem its own numbers.
- **Rates are explicitly not magnitudes.** A rate ("what is one unit of this realm's training
  worth") must never read the magnitude table; `AGENTS.md` now states that rule and each path
  owns its rate step.
- **`tools/options.py` keeps its own authored item magnitude table**
  (`game/data/item_options/item_magnitude_scale.json`). That is a second per-realm scale and
  deserves an explicit ruling from the owner: either it is a different quantity that may differ
  (item magnitudes are not actor stats), or the two should be reconciled.