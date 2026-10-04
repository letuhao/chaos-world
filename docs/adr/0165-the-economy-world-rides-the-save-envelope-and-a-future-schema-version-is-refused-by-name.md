# 0165 The economy world rides the save envelope, and a future SCHEMA_VERSION is refused by name

- Status: Accepted
- Date: 2026-10-04
- Depends on: ADR 0027 (`module_data` is JSON-round-tripped), ADR 0101 (the injected world
  store, and the persistent store it owed), ADR 0102 (a lot escrows a realized instance),
  ADR 0128 (the autosaved envelope, `SaveStore`, `SavePaths`, the two version ladders)
- Resolves: DEF-0223, DEF-0147

## Context

ADR 0101 settled the **shape** — `set_store` takes anything with `read_ledger()` /
`write_ledger(ledger)` — and named the persistent store as its own debt, because a save
format for the world is a separate decision. ADR 0128 then built that store for the **soul**
and left the three economy ledgers on bare in-memory dictionaries: `WorldLedger`,
`MarketWorldLedger` and `CustodyWorldLedger` are `var _ledger: Dictionary` with no file I/O,
and each docstring says so. Their own docstrings admit it.

So a claimed vein, a listed lot and an open custody claim die at quit. `SaveApi._snapshot_world`
faithfully wrote `world["holdings"] = {}` for a key with no store behind it — a ledger believed
saved that was never read. The criterion that should have been `no` is `no`.

## Decision

**The three ledgers ride the ADR 0128 envelope in the keys it already declares, through the
`SaveStore` that already exists. No fourth persistence mechanism is added.**

- **`WorldLedgerStore` is the ADR 0101 store SHAPE bound to ONE envelope key.** It takes a
  `key` from `SaveSlot.WORLD_KEYS` and is built by a `SaveStore` over the same envelope, so it
  is not a new store class but a per-slot *view* of the existing one. `read_ledger()` returns
  `SaveStore` `world()[key]`, `write_ledger` writes only that key, and the `SaveStore` instance
  is re-read from disk on every call. It therefore cannot read another ledger's world and
  cannot merge two.
- **Each ledger keeps its OWN normalizer, and the store never normalizes.** `WorldLedger`
  normalizes with `HoldingsState`, `MarketWorldLedger` with `MarketState`, `CustodyWorldLedger`
  with `CustodyState`, and a store that normalized with the wrong one would silently drop the
  floor and every open lot — the conflation ADR 0101 records, and `test_economy_boot.gd` already
  pins for `EconomyBoot`. A store holds bytes; the module that owns the shape owns the meaning.
- **One file, one envelope, `user://save/primary.json`.** There is no per-ledger file. The
  world is **per-save, not shared across saves**: `SaveStore` already rotates one primary and one
  backup, and a second file per ledger would be a second slot list and a second rotation policy
  for a world that has to be restored atomically with the actor it describes.
- **`SCHEMA_VERSION` is per-ledger and additive-only, and it is the module's own.** A new field
  in a ledger does **not** bump `SaveSlot.ENVELOPE_VERSION`: an envelope key appearing is not an
  envelope change, and ADR 0128 pins the two ladders as independent. A ledger whose `version` is
  **higher** than the module's `SCHEMA_VERSION` is **REFUSED BY NAME**
  (`WorldLedgerStore.REASON_FUTURE_SCHEMA = "future_schema"`), never silently accepted: a newer
  build may have moved the holder into a field this build drops on write, so reading it here
  would destroy the newer run's world on the next autosave. A ledger from an **older** version is
  accepted and re-normalized, which is the migration story — `normalize` is the ladder's floor
  and authoring it in one place is what makes the step idempotent.
- **A corrupt or truncated file is REFUSED BY NAME and the module reports it**
  (`WorldLedgerStore.REASON_LEDGER_UNREADABLE = "ledger_unreadable"`). It is never read as an
  empty world: `is_empty()` returning true after a refusal is what silently loses every claim, so
  the store records the refusal and `read_ledger()` answers the **un-normalized** empty skeleton
  rather than a fabricated one — the module's own `normalize` supplies the skeleton, and a
  caller can ask `last_reason()` for what happened. `SaveStore.restore` routes an unreadable
  primary to the backup first, so a truncated file is usually a *recovered* generation rather
  than a refusal; the refusal is what remains when neither slot is readable.

## Consequences

- **The three ledgers stay separate by construction, and the test proves it rather than trusting
  the docstring.** A key is a constructor argument, not a shared field, so
  `market_store.write_ledger(holdings_ledger)` writes the `holdings` key of the market store's
  world, and `HoldingsState.normalize` never sees it. A wrong-key write is a **silent no-op on
  the wrong container**, not a corruption — and the test asserts the floor and the claim are
  untouched after a cross-key write.
- **A lost ledger is observable, which is the whole point.** `HoldingsApi.summary` now publishes
  `store_installed`, so a caller can tell "no store wired" from "a store holding an empty world",
  which was previously impossible — the audit's "the module reports it rather than starting
  empty" criterion.
- **The persistent store closes the debt ADR 0101 named, and ADR 0101's remaining warning still
  stands:** `WorldLedger` is retained as the in-memory seam a unit test installs, never the
  production path. `EconomyBoot._install_stores` keeps installing the three in-memory ledgers
  ONLY when no save-backed store is present, so every existing suite keeps its behaviour
  unmodified while the shipped root gets the durable one.
- **A save written before this change still reads.** The envelope key already existed and already
  serialized as `{}`, so old saves load with an empty world rather than failing; only the
  `version`-from-the-future case is a hard refusal, and it is one this build could not have
  written.
- **DEF-0119's open half is untouched.** This decides storage, not whether an institution ledger
  is player-contact only; ADR 0128 records the same split.