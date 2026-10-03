# 0098 Balance ladders are authored gate scalars, not a fourth power table

- Status: Accepted
- Date: 2026-10-03

## Context

AGENTS.md fixes the number of per-realm tables at three — `core/realm_power_table.tres` (ADR
0050), `game/data/item_options/item_magnitude_scale.json`, and the technique ladder (ADR 0055) —
and forbids computing any of them from a realm index.

Retuning the body ladder created `tools/cultivation/ladder.py`, which computes per-realm values
from an index: `quality_ceiling(i)`, `chance_base(i)`, `integrity_maximum(i)`, and
`free_physique(i)` summing `range(i)`. Read cold, that looks like a fourth index-derived table
and a direct breach of the rule above.

It is not, and the difference is worth stating before an agent "reconciles" it away.

## Decision

- **These are gates and budgets, not magnitudes.** Quality ceiling and floor, integrity target
  and maximum, chance base and cap, physique required, and the work budget are probabilities,
  floors and ceilings. A magnitude answers "how strong is a thing from this realm"; none of these
  do. They read no magnitude and share no number with one.
- **The 30 `.tres` seeds are the single source of truth.** The runtime reads every gate off the
  seed. It never computes one, and never derives one from a realm index.
- **`ladder.py` is the recipe those seeds are generated from, not a table anything reads.** It
  exists so a designer retunes one number instead of thirty, and so the bootstrap generator
  (`seed`) cannot disagree with the report (`report`) or the guards (`audit`) that read the seeds.
  Three copies of one ladder is how `chance_base` grew past `chance_cap` on five realms.
- **`cultivation retune` is an explicit named act.** Index arithmetic reaches the seeds only
  through it, never as a side effect of `seed`.
- **The guards assert shape, not the recipe.** `cultivation validate` checks the properties a
  designer must not break — a live chance band, a quality gate with headroom below the previous
  ceiling and above fresh quality, a physique floor above the free grant, a derived field never
  authored — so the numbers stay hand-editable and the recipe may change without touching a guard.
- **A guard nobody has seen fire is not a guard.** `cultivation mutate` breaks one authored number
  per rule on a throwaway copy of the seeds and asserts the rule catches it. It never touches real
  data, and it runs in `tools check` so a rule that goes vacuous fails the gate instead of waiting
  for the next balance change to expose it.

## Consequences

- An inserted realm shifts no magnitude — that remains the reason the three tables are keyed by
  realm id. It *would* shift gate values if `retune` were run, which is acceptable because a gate
  is balance rather than a power claim, and is the reason `retune` is separate from `seed`.
- Editing a seed by hand is supported. `retune` re-derives from the recipe; `validate` catches a
  seed the recipe no longer explains.
- The runtime's independence from the recipe is the load-bearing part. If a gate ever starts being
  computed from a realm ordinal at runtime, this decision is void and the seeds stop being data.
