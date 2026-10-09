class_name SectSuccession
extends RefCounted

## A succession is **walked, never rolled** (ADR 0084, taking ADR 0058's ascension
## shape). One authored stage per call, a period between stages, and no `rng` at
## all — so the outcome is a pure function of the ledger and a test needs no seeded
## generator to prove it.
##
## ## What is NOT in this file
##
## No `rng`, no `RandomNumberGenerator`, no `randi`, no seeding hook. Rolling
## `standing / threshold` would make a promotion a gambling event and a gate that can
## satisfy itself, which is the exact reason ADR 0084 rejects it — and a reader who
## wants to be sure can grep this module for those three names, which is what
## `test_sect_succession.gd` does.
##
## ## The walk has to START somewhere, and starting it is separate
##
## ADR 0058 refuses a fifth `ascend` step because `commit` already began the
## ascent; there is no such step here, so opening a vacancy IS a step and `open` is
## the verb that does it. One action is one stage, and every refusal names itself.
##
## ## No loop walks these stages
##
## `stages_walked` is a **count**, not an index, and it is clamped against
## `SectPositionDef.walk_length()` before anything reads it. A corrupt save holding a
## negative number or a million therefore talks this module into nothing at all
## rather than into a very long `for` — which is the rule AGENTS.md states for every
## loop in this repo.

## The walk sides, in the order they succeed each other. Both are authored constants
## on `SectDef` rather than literals here, so a save and a screen read the same two
## words.
const VACANT := SectDef.SUCCESSION_VACANT
const SEATED := SectDef.SUCCESSION_SEATED
## The cap on periods a caller may wait in one call. A bounded parameter rather than
## an unbounded one: "wait until it comes due" must not be a way to skip the walk.
const MAX_WAIT_PERIODS := 8

## The named reason each refusal of the walk uses. Strings rather than an `enum`
## because every one of them crosses the facade as a `String` and is written into a
## history record; an ordinal in either place would be a number whose meaning
## changes the moment somebody reorders this file.
const R_NO_SUCH_WALK := "no_such_walk"
const R_NOT_VACANT := "seat_not_vacant"
const R_PERIOD_NOT_ELAPSED := "period_not_elapsed"
const R_WALK_COMPLETE := "walk_complete"
## A second immediate `open` on a seat whose walk is already in progress. The row IS
## the walk's memory, so re-opening it would RESET the accrued vacancy and every
## stage taken — a silent loss wearing the word "open" (the capability's
## `already_open`, `contracts/successive.gd`).
const R_ALREADY_OPEN := "already_open"
## A `wait` that named no time at all. Zero or negative is a caller bug rather than a
## quiet no-op: a settlement that moved nothing must not read as one that ran (the
## capability's `no_periods`).
const R_NO_PERIODS := "no_periods"


## The walk in progress on `position_id`, or `{}`. Read rather than re-derived so
## `advance_succession` and a panel cannot disagree about what stage a seat is at.
static func walk(ledger: Dictionary, position_id: StringName) -> Dictionary:
	return SectState.succession(ledger, position_id)


## Whether `position_id` has a walk open right now — begun, not finished. This is
## the shape of the refusal a second immediate call gets.
static func is_open(ledger: Dictionary, position_id: StringName) -> bool:
	return SectState.succession_open(ledger, position_id)


## Open a walk by recording that `position_id` is `vacant`.
##
## `held_periods` is how many periods the seat has been empty, clamped at zero and
## **capped at [constant MAX_WAIT_PERIODS]** — the same bound `wait` carries, because
## one call must never be a way to skip the walk. It is carried in the ledger so a
## caller that waited in one period and a caller that waited in three arrive at the
## same answer. **No clock is read here**: periods are an explicit argument from a
## caller that owns time (DEF-0111).
static func open(ledger: Dictionary, position_id: StringName, held_periods: int) -> Dictionary:
	var row := {
		"side": VACANT,
		"stage": 0,
		"held_periods": clampi(held_periods, 0, MAX_WAIT_PERIODS),
		"complete": false,
	}
	(ledger["succession"] as Dictionary)[String(position_id)] = row
	return row


## Add `periods` to the vacancy a seat has sat in, **capped at [constant
## MAX_WAIT_PERIODS] per call** — the bound that keeps "wait until it comes due" from
## being a way to skip the walk. Bounded at zero, and a no-op for a seat with no walk
## open; `SectApi.advance_succession` refuses both cases by name BEFORE calling here,
## so this primitive's no-op is a backstop rather than the answer a caller reads.
static func accrue(ledger: Dictionary, position_id: StringName, periods: int) -> int:
	var bounded := mini(periods, MAX_WAIT_PERIODS)
	if bounded <= 0:
		return 0
	var row := walk(ledger, position_id)
	if row.is_empty() or String(row["side"]) != VACANT:
		return 0
	row["held_periods"] = maxi(0, int(row["held_periods"]) + bounded)
	(ledger["succession"] as Dictionary)[String(position_id)] = row
	return int(row["held_periods"])


## Take ONE authored stage of the walk on `position_id`. Returns the row written.
##
## This is the whole verb, and it is deliberately three statements rather than a
## loop: count where the walk is, refuse if it is done, otherwise add one. The count
## is clamped against the office's authored `walk_length()` first, so a ledger that
## arrived from a save rather than from this function cannot describe a walk longer
## than the content allows.
static func step(ledger: Dictionary, office: SectPositionDef) -> Dictionary:
	var position_id := office.id
	# A Dictionary keyed by office id, not an Array: several offices can be walking a
	# succession at once, and an Array here would make the second walk overwrite the
	# first. `SectState.normalize` writes the same shape, so the two agree.
	var stages: Dictionary = ledger.get("succession", {})
	var row := SectState.succession(ledger, position_id)
	var walked := clampi(int(row.get("stage", 0)), 0, office.walk_length())
	row["stage"] = walked + 1
	# The seat is seated the moment the last stage lands, and the walk is finished
	# in the same step. Splitting those two facts is what would let a seat read as
	# `seated` and `complete: false` at once, which is a state nothing can act on.
	row["side"] = SEATED if walked + 1 >= office.walk_length() else VACANT
	row["complete"] = walked + 1 >= office.walk_length()
	# The vacancy clock is SPENT here, not merely read. Every stage costs the office's
	# authored `succession_periods`, so the next stage has to wait its own turn — a
	# walk that leaves the count standing would be paced by the FIRST period alone,
	# and the seat would then take every remaining stage back-to-back with nothing
	# between them. This is what makes "one stage per period" a property of the walk
	# rather than a thing the first `wait` has to be remembered for.
	row["held_periods"] = maxi(0, int(row.get("held_periods", 0)) - office.succession_periods)
	stages[String(position_id)] = row
	ledger["succession"] = stages
	return row


## How many stages a full walk of this office's method takes, clamped into what the
## ledger is allowed to hold. Used by the facade's "how far is this from done" read.
static func walked_of(ledger: Dictionary, office: SectPositionDef) -> int:
	var row := walk(ledger, office.id)
	return clampi(int(row.get("stage", 0)), 0, office.walk_length())


## Whether this walk may take its next stage. A walk is held up by exactly one
## thing — the vacancy clock — and that clock is a period count the caller handed in
## rather than anything read from a ledger, so the rule takes the count as its
## argument. This is the one place ADR 0084's "refuses a further step until a period
## elapses" actually lives.
static func may_step(office: SectPositionDef, periods_held: int) -> bool:
	return periods_held >= maxi(0, office.succession_periods)
