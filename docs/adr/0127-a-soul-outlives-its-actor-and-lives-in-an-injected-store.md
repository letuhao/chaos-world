# 0127 A soul outlives its actor and lives in an injected store

- Status: Accepted
- Date: 2026-10-04
- Depends on: ADR 0027 (`module_data` is String-keyed and JSON-round-tripped), ADR 0101 (a
  world object persists in an injected store), ADR 0065 (fate is earned, never chosen and
  never removed), DEF-0119 (no world-level persistence root), DEF-0147 (no persistent store)
- Resolves: the storage half of DEF-0119

## Context

The game has one persistence root: `actor.module_data`, copied verbatim by
`Actor.to_dict` (`core/actor.gd:293-298`) and restored by `from_dict`. It has the actor's
lifetime. ADR 0101 recorded that a holder stored there is not a simplification but a **bug**
the moment a second holder exists, and named the durable answer: a world object lives in an
injected store and the actor copy is a mirror for the save.

A soul is the clearest case that root cannot hold. A soul outlives the body it inhabits by
construction — the whole feature is a body dying and the soul continuing. Putting the soul
ledger in `module_data` makes it die with exactly the actor it exists to outlive, and the
failure is silent: every single-actor test passes.

The storage question is therefore settled before any rebirth behaviour is written. What is
owed is the arithmetic and the gate, not the location.

## Decision

**A new `soul` module owns a versioned soul ledger that lives in an injected store. The
actor mirror is a save carrier, never the source of truth.**

- **`SoulApi.set_store(store)` takes any object with `read_ledger()` / `write_ledger(ledger)`,
  exactly as ADR 0101 specified for `holdings`.** Every verb reads and writes that store, so
  one soul is one soul regardless of which body is currently carrying it. The method names
  are not `load` / `save`: those resolve to the GDScript builtins on a `RefCounted` and are a
  compile error, invisible until the suite runs (ADR 0101 §Decision).
- **`soul` declares no sibling module dependency in its first form.** It may depend on
  `core` and `contracts`, which is free (`tools/arch/enforce.py` exempts
  `modules/* → core|contracts`). It may **not** depend on `destiny`, because `destiny` earns
  onto a *body's* `module_data` and the next body is a different `Actor`. A declared-but-dead
  edge is the seam ADR 0065 §Consequences warns about.
- **The ledger carries bounded state only.** `integrity` within `[0, integrity_max]`, `lives`
  within `[0, lives_max]`, a monotone `incarnation`, an `origin_history`, and damage/repair
  trails capped at a fixed row limit — the `DestinyState.HISTORY_LIMIT` precedent, whose
  reason is that a save cannot grow without limit.
- **An unreadable payload normalizes to empty and is never partially applied.** A row naming
  an authored id the catalog no longer ships is **dropped**, not persisted — the
  `DestinyState.normalize` rule, so a save from a wider content build cannot smuggle an
  arrival.
- **Difficulty is read, never stored twice.** The soul ledger names a `difficulty_id`; the
  numbers live in one authored table (ADR 0129). The id is a save's memory of its own
  difficulty, which is what makes the save self-describing.

## Consequences

- **A test asserts the store, not the actor, holds the ledger.** Reading
  `actor.get_module_data(SoulState.MODULE_KEY)` and asserting it is empty while
  `store.read_ledger()` is not is the only thing that catches the regression, because every
  other test passes when the soul is wrongly stored on the actor.
- **The soul survives `Actor.to_dict` by not being in it.** `persist` reads the soul before
  serialising the actor, so a save taken at the moment of death still carries it. A new body
  gets the ledger by one `attach`, and nothing else.
- **Rebirth is a body swap, not a state restore.** What crosses is the ledger; what is rebuilt
  is the body. This is what makes the world consequence honest (ADR 0130).
- **A `WorldFact` write from `soul` must be registered in the same change.**
  `tests/arch_rules/test_fact_ledger_writers.gd` asserts an exact writer list, so a new writer
  turns the arch suite red until it is named there. A death is a world-visible fact (ADR 0113)
  and this is the cost of recording one.
- **A repair verb is owed and is deferred.** A damaged soul having somewhere to be repaired
  needs a world anchor, and the only building-adjacent module is `holdings` — which is at its
  twelve-method facade cap. Recorded as work rather than half-built here.
