# 0128 The save is an autosaved envelope with one readable slot and an unreadable backup

- Status: Accepted
- Date: 2026-10-04
- Depends on: ADR 0027 (`module_data` persistence), ADR 0037 (actor `SCHEMA_VERSION` and its
  migration ladder), ADR 0101 (the injected world store), ADR 0127 (the soul outlives its
  actor), DEF-0053 (a hand-built dictionary cannot prove an old save is readable), DEF-0059
  (the shipped save persisted items only), DEF-0147 (no persistent world store)
- Resolves: DEF-0059, DEF-0147

## Context

There is no save system. `app/item_state_store.gd` writes `user://item_workbench_state.json`
in place, so a crash truncates the only save; `Actor.to_dict` has no production caller at all
(DEF-0059), so cultivation progress, the dantian, the sea and module ledgers are all dropped
on quit.

The requirements are four, and two of them are in tension by design: the game saves itself
and the player never decides **when**; a soul sticks to the save; a backup exists on disk; the
player cannot choose to load the backup. Nothing in the repo decides any of this, and the
world store three modules already need (ADR 0101 §Consequences) is the same missing piece.

## Decision

**A new `save` module owns the envelope, the policy and the rotation. The player-facing
surface is deliberately almost empty.**

- **The envelope wraps `Actor.to_dict()` whole and untouched, under `envelope.actor`.** Its
  own `version` key stays `SCHEMA_VERSION` and its `module_data` rides inside it, so item
  state is carried by the one existing path rather than a second one. No `statuses` key:
  `core/actor.gd:305-309` makes that omission deliberate and pins the version.
- **World ledgers ride beside the actor, not inside it**, under `envelope.world`: `holdings`,
  `market`, `custody`, and `soul`. This is ADR 0101's answer to a second holder applied to the
  whole world, and ADR 0127's answer for the soul.
- **`envelope_version` and the actor's `SCHEMA_VERSION` are independent ladders.** A save
  migration never rewrites an actor payload, and a new world key never bumps an actor version
  — the ADR 0037 rule, since `SCHEMA_VERSION` is asserted at exactly 4.
- **The store is one `SaveStore` per slot, constructed fresh per write and per load.** It is
  the ADR 0101 object (`read_ledger` / `write_ledger`, never `load` / `save`), injected into
  the three world modules and the soul. Because the world modules keep their store in a
  `static var`, `attach` always re-installs rather than installing only when absent; a second
  slot that skipped it would read the first slot's holdings and every single-slot test would
  pass.
- **Write order is snapshot, rotate, write temp, atomic rename.** Every ledger is read first
  and a failure aborts before touching disk, so a partial world never becomes a file. The
  previous primary becomes the backup, the new envelope is written to a temp path, and only
  the rename promotes it. **After any failed write exactly one readable file exists, and it is
  a complete generation.** A rename failure reports `rename_failed` and leaves the temp file;
  it never retries, because a half-recovered write is how one bad write becomes two.
- **The player chooses nothing.** Boot reads `exists()` and either restores the live slot or
  builds a fresh hero and writes once. There is no save screen, no save button, and no slot
  list. A corrupt primary **silently restores the backup** — the alternative is a modal
  reporting an error the player has no way to act on — and the recovery is reported in the
  facade's own return value and `summary()`, never in a prompt. `item_state_store.gd:28-31`
  set the precedent that an unreadable file reads as recoverable rather than as an error.
- **The autosave schedule is a period counter hung off the existing frame driver.** A
  `SaveClock.pull(delta)` in the module turns seconds into whole periods and is called from
  the one `_process` that already exists. It adds **zero** frame drivers
  (`tests/app/test_status_clock.gd` pins the tree to exactly three) and reads no
  `Time.get_ticks_*` (DEF-0111). Because a save can only land on a period boundary, *when*
  saving happens is decided entirely by boundaries the player never sees.
- **A module writing to `user://` is not banned, but it is the only module that does it, and
  that is pinned.** No filesystem rule exists in `tools/arch` — the detector regex matches
  `res://` only — so the fact is converted into a checked invariant by a test rather than left
  as a convention about one file.
- **One carve-out, named rather than left as a contradiction.** The workbench keeps a
  player-facing Save and Load (`ui/screens/item_workbench.gd` `act_save` / `act_load`) bound to
  `app/item_workbench_body.gd`'s `_save_state` / `_load_state`, which write
  `user://item_workbench_state.json` carrying `ItemsApi.serialize(actor)` alone. **This is not
  the envelope and cannot touch it**: `SaveApi.persist` has exactly two call sites, both in the
  composition root (the period clock and the death branch), so the player can neither cause nor
  suppress an envelope write — that half of "the player chooses nothing" holds as shipped.

  What it does mean is that a player sees two controls called Save and Load with two different
  meanings, so "the player chooses nothing" is true of the RUN and not of the BAG. That is the
  honest reading, stated here rather than left for an audit to discover as a contradiction: the
  item-only store is a convenience for a single subsystem, the envelope is the run, and
  re-pointing the buttons at the envelope would hand the player exactly the manual
  save-and-restore this ADR forbids. Closing the pair is a decision about the workbench, not
  about the save, and it is recorded as BL-0714 rather than done here.

## Consequences

- **`ui/` may not reach `save`.** It is absent from `rules.UI_MODULES`, so any `ui/ → save`
  reference is a hard violation. The save status line is a routed screen bound through `app/`.
- **The backup being unreachable is a rule with teeth.** A test scans `res://src` for any
  shipped caller naming the backup slot or a rollback verb, allow-listing only the store's
  private fallback. Without that guard "no backup affordance" is a claim rather than an
  invariant.
- **An unreadable save may lose a run and never says so.** This is the accepted cost of a
  design where the player cannot intervene. `persist` returns its failure reason rather than
  an empty string, so the condition is observable in tests even though it is invisible in play.
- **DEF-0119 is now decided for storage and still open for the politics layer.** A world
  persistence root exists at envelope scope. Whether an institution ledger is player-contact
  only or genuinely world-scoped remains a separate question and is recorded as such.
- **A checked-in envelope fixture is required, not optional.** DEF-0053's own wording is that
  a hand-built dictionary cannot prove an old save is still readable, so the migration ladder
  ships with a real on-disk fixture in the `tests/fixtures/save_v2.json` shape.
