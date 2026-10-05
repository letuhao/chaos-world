class_name WorldClock
extends RefCounted

## The world clock: ONE authoritative count of whole periods, saved beside the ledgers it
## moves (ADR 0259).
##
## ## What this closes
##
## `SaveSlot.WORLD_KEYS` carried six ledgers and **no clock**. `app/world_pulse.gd` kept the
## running period total in memory and `save/clock.gd` kept the autosave counter in memory, so
## both were session-only: a player who quit and returned resumed at period zero with a full
## ledger. Nothing was lost, so "the world never rewinds" held — but a year of accrual before
## the quit was indistinguishable from a year after it, because the number that would say so
## was never written. `BL-0891`.
##
## ## The clock is a COUNT, and only the composition root advances it
##
## No module owns time (ADR 0089 / DEF-0111): there is no `Time.get_ticks*`, no `_process`
## and no `get_tree()` in this file. [method advance] takes an explicit non-negative whole
## period count from the caller that owns time, which is the verb every accrual in this
## program already demands. A module that wants the time ASKS — [method periods] — and never
## advances it.
##
## ## It only moves FORWARD, and that refusal is STRUCTURAL
##
## [method advance] is the only verb that moves the count, and it refuses a negative span.
## There is deliberately **no `set_periods(count)`**: a clock that could be wound back is the
## rewind ADR 0131 and ADR 0128 refuse, and a refusal a caller can route around is a
## convention rather than a boundary. A restore ([method write_ledger]) is the one path that
## reads a count, because a restore READS the persisted count and never authors one.
##
## ## `TimeLadder` converts, this clock only counts
##
## ## A CONVERTED VALUE IS NOT STORED HERE, AND NEVER MAY BE.
##
## The payload holds `periods` and nothing else. A reader wanting years calls
## `TimeLadder.magnitudes_crossed(clock.periods())` (ADR 0173's division against the authored
## ratios). Storing a converted value as well would put the ratio in TWO places, so a retune
## of `time_ladder_table.tres` would silently disagree with every existing save — a save whose
## "year" field was a whole number under the old table is not a year under the new one, and
## nothing anywhere would say which table authored it. The count is the only thing that
## survives a table retune, which is precisely why it is the only thing stored.
##
## ## The store, so `SaveApi` can snapshot it like any other world
##
## [method read_ledger] / [method write_ledger] are ADR 0101's shape, which is what
## `SaveApi.install_store` reaches and `SaveApi._snapshot_world` reads — so `world_time`
## persists by the EXISTING mechanism rather than a new one. This class is in `core/`
## because it is a layer (the `RealmRate` argument, ADR 0066), so it costs ZERO new arch
## edges; the normizer is static so `app/world_ledger_store.gd` can route the key without
## naming anything else here.
##
## ## WHY IT IS A WORLD ROOT AND NOT AN ACTOR FIELD
##
## The world does not get younger when the hero does. A period count stored in
## `actor.module_data` would die with the exact body it exists to outlive, and every
## single-actor test would still pass — the silent failure ADR 0127 named for the soul
## ledger, applied to time. `tests/core/test_world_clock.gd` proves the body-independence by
## swapping the actor, because that is the property most likely to be broken by a well-meaning
## convenience later.

## The envelope key this clock rides. Declared HERE as well as in
## `SaveSlot.WORLD_KEYS`, because `modules/save` may not name this file's internals and this
## file may not name `modules/save`. The two are asserted equal by test rather than by a
## `preload`, which would be an upward edge (`world_polity_ledger.gd`'s precedent).
const WORLD_KEY := "world_time"

const SCHEMA_VERSION := 1

## The containers this ledger owns, in the exact shape it normalizes.
## `app/world_ledger_store.gd` routes a key by container NAME and may not reach this file's
## normalizer, so the table is authored here and asserted against the store's copy by test.
## **One container, one count** — there is no `seconds` and no `years` here to route.
const CONTAINERS: Array[String] = ["periods"]

## A corrupt-save guard on the count, not a budget. A hand-edited save must not be able to
## claim a period total that no number in this program has a name for; the same role
## `WorldPolityLedger.PERIOD_CAP` plays for a debt line.
const PERIOD_CAP := 1000000000

## The world store, and the ONE thing that may advance the count.
##
## **An instance, never a static or a singleton.** The headless runner drives every suite in
## ONE process, so a static clock would leak one suite's periods into every later suite; a
## store is handed to `SaveApi.install_store` and its state dies with the reference the
## caller holds. Nothing in this file is process-wide.
var _ledger: Dictionary = {}

# --- The persisted shape -----------------------------------------------------


## The empty clock. A missing slot, an unreadable payload and this are the same value, so
## "no time has passed" has one spelling instead of three.
static func empty() -> Dictionary:
	return normalize_payload({})


## A clock rebuilt from a saved payload, JSON hop included.
##
## Normalization is the MIGRATION and it is total: the count is coerced to an integer and
## clamped into `[0, PERIOD_CAP]`. A negative, fractional or absurd value is a corrupt save,
## not a rewind request — this is a REPAIR, and it refuses to manufacture a negative count
## out of one, because a clock that reads backwards is the rewind ADR 0131 forbids.
##
## An OLD version is accepted and folded onto the current shape, so a save written before
## this slot existed reads as period zero rather than failing. A FUTURE version is refused by
## name in `app/world_ledger_store.gd`, never silently read.
static func normalize_payload(payload: Dictionary) -> Dictionary:
	var raw = payload.get("periods", 0)
	var count := 0
	if (raw is int or raw is float) and not (raw is bool):
		count = clampi(int(raw), 0, PERIOD_CAP)
	return {"version": SCHEMA_VERSION, "periods": count}


## A clock as the disk should carry it, JSON-safe. `String` keys and a plain `int`, for the
## reason `WorldPolityLedger.to_dict` states: these travel into save blobs where an interned
## name is not a value and where a float would lose the low digits of a large count.
static func to_dict(ledger: Dictionary) -> Dictionary:
	return normalize_payload(ledger)


## How many whole periods `ledger` carries, as a plain integer. The one read a caller wants,
## so a panel, a test and a gate cannot drift into answering differently about the same clock.
static func periods_of(ledger: Dictionary) -> int:
	return int(normalize_payload(ledger).get("periods", 0))


# --- The store ---------------------------------------------------------------


func _init() -> void:
	_ledger = empty()


## The current ledger, normalized. Returns a copy so a caller cannot mutate the clock by
## holding on to what it was handed.
##
## Named `read_ledger` rather than `load` because `load` is a global GDScript builtin and a
## method with that name on a `RefCounted` resolves to the builtin — a compile error rather
## than a loud failure, so it is invisible until someone runs it.
func read_ledger() -> Dictionary:
	return normalize_payload(_ledger)


## The restore path. **It READS a persisted count and never AUTHORS one.**
##
## This is the only door a count arrives through, and it is deliberately not a setter: it
## takes the whole normalized payload the envelope carried, so there is no spelling of
## "replace the count with an arbitrary number" for a caller to reach for. A clock restored
## with no persisted key lands on `empty()` — period zero — because that is a new game's
## answer, not an authored one.
##
## The value is read through [method normalize_payload], so a corrupt payload is repaired to
## a count rather than believed.
func write_ledger(ledger: Dictionary) -> void:
	_ledger = normalize_payload(ledger)


## How many whole periods the world has advanced. **The whole read surface of a clock.**
##
## A caller wanting years converts here rather than storing a conversion
## (`TimeLadder.magnitudes_crossed(periods)`); a caller wanting nothing calls this and moves
## on. There is no `set_periods`, because there is no way to author a count at runtime —
## only to advance one forward, or to restore the one the last session persisted.
func periods() -> int:
	return periods_of(_ledger)


## Move the clock forward by `periods` whole periods, and report whether it moved.
##
## ## Forward-only is STRUCTURAL, not a convention
##
## A negative span is REFUSED and returns `{"ok": false, "reason": "negative_advance"}`. There
## is no argument that winds the clock backwards, so the rewind ADR 0131 and ADR 0128 refuse
## is not available to a caller who wants it — there is no code path to call. A zero span is
## a frame in which the world did not move, which is `ok` and not a refusal: the composition
## root's fold hands down zero on a delta that elapsed nothing, and that must not be an error
## (`WorldPulse.pull`'s own reason).
##
## Returns `{ok, reason, periods}` where `periods` is the clock's new count, so a caller reads
## the result without a second call and a second call could not race it.
func advance(periods: int) -> Dictionary:
	if periods < 0:
		return {"ok": false, "reason": "negative_advance", "periods": self.periods()}
	var moved := self.periods() + periods
	if moved > PERIOD_CAP:
		# The cap is a corrupt-save guard, and an advance past it is the same defect
		# arriving from the live side rather than from a file: refuse it loudly rather than
		# silently clamping a real period count down.
		return {"ok": false, "reason": "over_cap", "periods": self.periods()}
	_ledger = normalize_payload({"periods": moved})
	return {"ok": true, "reason": "", "periods": moved}


## Whether this clock has ever counted anything, so a caller can tell "no world has advanced
## yet" from "no store is wired".
func is_empty() -> bool:
	return periods() == 0


## The clock as primitives, so `tools ui drive` can print it and a test can assert on it
## without reaching into the object.
func summary() -> Dictionary:
	return {
		"world_key": WORLD_KEY,
		"periods": periods(),
		"version": SCHEMA_VERSION,
	}
