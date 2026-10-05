# 0259 The world clock is saved beside the ledgers it moves

- Status: Accepted
- Date: 2026-10-05

## Context

ADR 0128 makes the save an autosaved envelope with `envelope.actor` and
`envelope.world`. `save_slot.gd:32` declares the world's keys:

```gdscript
const WORLD_KEYS: Array[String] = ["holdings", "market", "custody", "soul", "anchor", "polity"]
```

Six ledgers, all persisted. **No clock.** `app/world_pulse.gd` keeps the running period
total in memory and `save/clock.gd` keeps the autosave counter in memory, so both are
session-only: a player who quits and returns resumes at period zero with a full ledger.

That makes the programme's promise true for *state* and false for *elapsed time*. "The
world never rewinds" holds — nothing is lost — but a year of accrual that happened before
the quit is not distinguishable from a year that happened after it, because the number
that would say so was never written. `BL-0891` tracks this.

It also blocks ADR 0258, which needs a **persistent elapsed-time root** to measure an age
against. Persisting a number with no authority behind it just persists a wrong number, so
the clock has to be real before the age that reads it can be.

## Decision

### 1. One world clock, held in the shared world store

The clock is a single authoritative period count. It is installed into the **same shared
world store** the six ledgers use — the one `SaveApi.publish_world` reaches and
`SaveApi._snapshot_world` reads — so it persists by the existing mechanism rather than a
new one. That store is already body-independent and already survives a body swap, which is
exactly what a clock must be: the world does not get younger when the hero does.

This is the same argument ADR 0127 made for the soul ledger, and the reason it is not
repeated here as a new idea.

### 2. It is a `WORLD_KEYS` entry, so persistence is a list edit

`"world_time"` joins the six. `SaveSlot`, `SaveApi.publish_world` and
`SaveApi._snapshot_world` all iterate that one array, so no save code changes. A key with
no store installed is already skipped and named rather than invented, so an unwired clock
is loud rather than silently absent.

### 3. The clock is a COUNT, and only the composition root advances it

No module owns time (ADR 0089 / DEF-0111 — no `Time.get_ticks*`, no `_process`, no
`get_tree()` outside the composition root's existing fold). `app/world_pulse.gd` already
hands down an explicit whole-period count to every accrual verb; the clock records that
same count. A module that wants to know the time asks; it never advances it.

### 4. `TimeLadder` converts, the clock counts

The clock stores **periods**, never seconds and never years. `core/time_ladder.gd` is the
only converter, by integer division against authored ratios (ADR 0173), and a reader that
wants years calls `magnitudes_crossed(clock.periods())`. Storing a converted value would
put a ratio in two places and let a retune of the table silently disagree with a save.

### 5. The clock only moves forward

Every advance is a non-negative integer. There is no setter that accepts a negative or a
replacement value: a clock that could be wound back is the rewind ADR 0131 and ADR 0128
refuse, and the refusal is now structural rather than a convention. A restore reads the
persisted count; it never authors one.

## Consequences

- `save_slot.gd` gains one entry. `save_envelope` and `save_round_trip` cover the path.
- ADR 0258's age is measured against this, so an age survives a save and a body swap.
- A world ledger that accrues over time (the hearth, holdings, a market) can be checked
  against the clock rather than against a session-local counter.
- BL-0891 is answered. BL-0890 (combat seconds never convert to periods) is a separate
  gap about the *rate table* and is not answered by this — the clock is the root, not the
  conversion of every verb onto it.

## Rejected

- **Persisting seconds.** It puts `PERIOD_SECONDS` in the save format, so a retune of the
  base ratio reinterprets every existing save. Periods are the base unit already.
- **A new autoload or a frame driver.** The composition root already folds time; a second
  driver is the class of change DEF-0111 exists to prevent.
- **Deriving the clock from the ledgers.** The ledgers record what happened, not when; a
  clock inferred from them is a clock that rewinds whenever a ledger is reset.
