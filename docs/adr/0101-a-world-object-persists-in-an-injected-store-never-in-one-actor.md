# 0101 A world object persists in an injected store, never in one actor

- Status: Accepted
- Date: 2026-10-03
- Depends on: ADR 0027 (`module_data` is String-keyed and JSON-round-tripped), ADR 0083
  (three states), ADR 0085 (a claim never moves ground), ADR 0097 (the owner ref), DEF-0119
  (no world-level persistence root)
- Resolves: DEF-0119

## Context

ADR 0097 built a resource node whose holder is a world fact, and recorded honestly that this
repo has **no world store**: `LootState` is `actor.module_data` and dies with the actor,
`DomainApi` keeps a map under `actor.module_data["domain_run"]` and **erases it on leave**
keeping only `discovered`, and `ItemStateStore` is the only file-backed store and is
items-only.

That gap stopped being a note and became a bug the moment it was written down. Storing a
holder per actor is not a simplification — it is **incorrect**, and the tests found it. Two
actors each keep their own copy of the ledger, so a rival reads a held node as vacant and
overwrites the holder outright. That is precisely the silent conquest ADR 0085 forbids, and
it would have shipped, because every single-actor test passes.

## Decision

**A world object lives in an injected store. `actor.module_data` is a mirror for the save,
never the source of truth.**

- **`set_store(RefCounted)` takes any object with `read_ledger()` and `write_ledger(ledger)`.**
  Every verb reads and writes that store, so two actors always see one world. `attach` still
  mirrors onto the actor so a single-player save carries the holdings.
- **The default is the actor mirror, and that default is documented as wrong the moment a
  second holder exists.** It is a seam, not an endorsement: `app/` installs the real store and
  a test installs `WorldLedger`.
- **`WorldLedger` is the whole fix, not a file-backed store.** It is in-memory and it is the
  shape a persistent store copies. A save format for the world is its own decision, and this
  repo's rule is that a new persistence path needs its own ADR rather than arriving inside a
  feature.
- **The method names are `read_ledger` / `write_ledger`, never `load` / `save`.** Those are
  global GDScript builtins, and a `RefCounted` method of that name resolves to the builtin —
  a **compile error rather than a loud failure**, so it stays invisible until someone runs the
  suite. This cost one debugging cycle and is recorded so the next author does not rediscover
  it.

**The three states survive persistence, and `normalize` is where that is enforced.** An
unowned node is written back as `{"vacant": true}`, never `{}`: `{}` means "not a node at
all" (ADR 0083), and collapsing the two makes an unclaimed vein indistinguishable from a vein
that does not exist — which is exactly what a claim reads to decide between taking ground and
challenging it. `release` writes the vacant marker for the same reason.

**A refused write persists nothing, and that includes a challenge.** A contest row that was
built but never saved is a claim that silently did not happen, and the next challenger would
open a second standoff on a node that already had one. Every mutating path calls `_save`,
including the refusal paths that changed nothing.

## Consequences

- **A second holder is now visible, so a challenge is a challenge.** Before this, a rival
  claim silently won; `test_holdings_claim.gd` asserts `holder` is byte-identical across a
  challenge, which is ADR 0085's invariant and was previously unenforced.
- **A store that returns a malformed ledger cannot poison the world.** Both directions
  normalize, so the skeleton is authored in exactly one place (`HoldingsState.empty`) and no
  caller can half-write a new key.
- **The seam generalises.** Any future world-scoped ledger — a market, a territory, a
  dungeon — takes the same `set_store` shape rather than inventing a second persistence
  mechanism.
- **A persistent implementation is still owed, and is not this ADR.** `WorldLedger` dies with
  the process, which is correct for a test and wrong for a shipped game. The real store needs a
  file format, a migration story for `SCHEMA_VERSION`, and a decision about whether the world
  is per-save or shared across saves. Recorded as work rather than half-built here.
- **Any module that reaches for `actor.module_data` for a WORLD fact is now wrong by
  construction**, and the failure is silent — the single-actor test still passes. That is the
  argument for the claim test being about two actors rather than one.