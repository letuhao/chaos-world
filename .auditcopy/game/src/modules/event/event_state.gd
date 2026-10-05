class_name EventState
extends RefCounted

## The versioned event ledger, stored as a plain dictionary under
## `actor.module_data["event_state"]` (ADR 0027 pattern, the `DestinyState`
## precedent). Core persists it without ever naming an event type.
##
## ## What this ledger is
##
## **What the world is currently living through**, plus the short, bounded trail of
## what it lived through before. An event opens at a stage, holds there for an
## authored number of PERIODS, and moves on only when a caller that owns time says
## how many elapsed. There is no clock here (DEF-0111): `opened_period` is a count
## the director was handed, never a timestamp it read.
##
## ## String keys throughout, and no StringName inner key
##
## `Actor.to_dict` converts only the OUTER `module_data` key with `String(key)`. An
## inner `StringName` key reaches the save untouched and breaks every round trip,
## and no checker in this repo can see it. So the discipline is written by hand and
## pinned by a JSON round trip in the test suite, exactly as `NationState` does it.
##
## ## `resolved` is the once-guard, and it is not optional
##
## ADR 0061: a reward is paid ONCE. An event is removed from `active` when it
## resolves, so `resolved` is what stops a second resolution of the same event from
## paying a second time — and it is what makes "resolved in period 7" a fact the
## world keeps rather than a number a screen re-derives.

const SCHEMA_VERSION := 1
## `actor.module_data` key.
const MODULE_KEY := &"event_state"
## The history trail is a bounded explanation of what the world has lived through,
## not a full audit log. A save cannot grow without limit.
const HISTORY_LIMIT := 128
## How many events one actor may have open at once. Beyond it, `begin` refuses —
## a world in twelve simultaneous crises is not a richer world, it is a content bug.
const MAX_ACTIVE := 12
## The separator joining an event id to a period into a `resolved` key. A character
## no authored id contains, so the key always splits back apart.
const PERIOD_SEPARATOR := "@"

## The refusal reasons this module authors. Collected in one place because a refusal
## is a NAMED game rule, not input validation, and a panel must render a reason it did
## not have to invent (ADR 0084).
const R_NO_ACTOR := "no_actor"
const R_UNKNOWN_EVENT := "unknown_event"
const R_ALREADY_ACTIVE := "already_active"
const R_TRIGGER_UNMET := "trigger_unmet"
const R_WRONG_LOCATION := "wrong_location"
const R_NOT_ACTIVE := "not_active"
const R_ALREADY_RESOLVED := "already_resolved"
const R_STAGE_UNMET := "stage_unmet"
const R_NO_CONFLICT := "not_a_conflict"
const R_NOT_DECLARED := "not_declared"
const R_NO_WINNER := "no_winner"
const R_UNKNOWN_WINNER := "unknown_winner"
const R_TOO_MANY_ACTIVE := "too_many_active_events"
const R_UNKNOWN_LOCATION := "unknown_location"
const R_NO_STAGES := "event_authors_no_stage"
const R_UNKNOWN_PAY_KIND := "unknown_pay_kind"
const R_STANDING_IS_DECLARED := "standing_is_declared_not_granted"


## The empty ledger.
static func empty() -> Dictionary:
	return normalize({})


## A refusal, in ADR 0083's third state: the action EXISTS and is refused. Never a
## `0`, never a `""` a caller has to interpret, and never a UI string — `reason` is one
## of the constants above, and the payload carries the authored ids it concerns.
static func refuse(reason: String, detail: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "reason": reason}
	for key in detail.keys():
		out[String(key)] = detail[key]
	return out


## Normalize a persisted payload field by field.
##
## Four rules, and the second is the one that earns its cost:
##   1. An empty payload returns the full skeleton immediately, never a partial.
##   2. **A payload that cannot be read is diagnosed as empty, never partially
##      applied** — half a ledger is worse than none, because it silently changes
##      what the world is living through.
##   3. An entry naming content the build no longer ships is dropped rather than
##      persisted, so a save from a wider content build cannot smuggle in an event
##      the current build does not define.
##   4. Every field is coerced on the way in, because a save is untrusted input.
##
## `resolved` is deliberately NOT filtered: an event that resolved is a thing that
## happened, and losing that row would let the prize be paid twice. An event whose
## `.tres` has since been deleted still reads as resolved, which is the correct
## answer to "may this pay again?".
static func normalize(payload: Dictionary, known_ids: Dictionary = {}) -> Dictionary:
	var out := {
		"version": SCHEMA_VERSION,
		"location_id": "",
		"period": 0,
		"sequence": 0,
		"active": {},
		"resolved": {},
		"paid": {},
		"history": [],
	}
	if payload.is_empty():
		return out
	var data := payload as Dictionary
	out["location_id"] = String(data.get("location_id", ""))
	out["period"] = maxi(0, int(data.get("period", 0)))
	out["sequence"] = maxi(0, int(data.get("sequence", 0)))

	var active = data.get("active", {})
	if active is Dictionary:
		for event_id in (active as Dictionary).keys():
			var key := String(event_id)
			if not _known(key, known_ids):
				continue
			var entry = (active as Dictionary)[event_id]
			if not (entry is Dictionary):
				continue
			out["active"][key] = _active_entry(entry as Dictionary)

	var resolved = data.get("resolved", {})
	if resolved is Dictionary:
		for event_id in (resolved as Dictionary).keys():
			var key := String(event_id)
			var period = (resolved as Dictionary)[event_id]
			if not (period is int or period is float):
				continue
			out["resolved"][key] = maxi(0, int(period))

	var paid = data.get("paid", {})
	if paid is Dictionary:
		for event_id in (paid as Dictionary).keys():
			var row = (paid as Dictionary)[event_id]
			if not (row is Dictionary):
				continue
			out["paid"][String(event_id)] = {
				"period": maxi(0, int((row as Dictionary).get("period", 0))),
				"rows": maxi(0, int((row as Dictionary).get("rows", 0))),
			}

	var history = data.get("history", [])
	if history is Array:
		for record in history as Array:
			if not (record is Dictionary):
				continue
			# Rebuilt field by field rather than duplicated: a file-backed save makes
			# one JSON hop, and a copied number comes back as a float.
			var entry := record as Dictionary
			(
				out["history"]
				. append(
					{
						"kind": String(entry.get("kind", "")),
						"event_id": String(entry.get("event_id", "")),
						"detail": String(entry.get("detail", "")),
						"sequence": int(entry.get("sequence", 0)),
						"period": int(entry.get("period", 0)),
					}
				)
			)
			if (out["history"] as Array).size() >= HISTORY_LIMIT:
				break
	return out


## The next sequence number. Strictly increasing, so history order is ledger order
## after a restore as it was before it.
static func next_sequence(ledger: Dictionary) -> int:
	return maxi(0, int(ledger.get("sequence", 0))) + 1


## Whether `event_id` is open right now.
static func is_active(ledger: Dictionary, event_id: StringName) -> bool:
	return (ledger.get("active", {}) as Dictionary).has(String(event_id))


## The open row for `event_id`, or `{}` when it is not open.
static func active_entry(ledger: Dictionary, event_id: StringName) -> Dictionary:
	var entry = (ledger.get("active", {}) as Dictionary).get(String(event_id), null)
	return (entry as Dictionary) if entry is Dictionary else {}


## Whether `event_id` has already resolved. The once-guard every pay reads.
static func has_resolved(ledger: Dictionary, event_id: StringName) -> bool:
	return (ledger.get("resolved", {}) as Dictionary).has(String(event_id))


## The period `event_id` resolved in, or -1 when it has not. -1 rather than 0:
## period 0 is a real period, and folding it into "never" would let a same-period
## resolution pay twice.
static func resolved_period(ledger: Dictionary, event_id: StringName) -> int:
	return int((ledger.get("resolved", {}) as Dictionary).get(String(event_id), -1))


## Whether `event_id`'s prize has already been paid. Separate from `has_resolved` so
## an event resolved by an external verdict (`resolve`) and an event resolved by its
## own last stage (`advance`) are each guarded once, and a refactor that merges the
## two paths cannot silently drop the guard.
static func has_paid(ledger: Dictionary, event_id: StringName) -> bool:
	return (ledger.get("paid", {}) as Dictionary).has(String(event_id))


## Append one bounded history row. Refusing past the cap rather than trimming: a
## trimmed trail silently loses the row that explains what the player is owed.
static func record(ledger: Dictionary, kind: String, event_id: StringName, detail: String) -> void:
	var history: Array = ledger["history"]
	if history.size() >= HISTORY_LIMIT:
		return
	(
		history
		. append(
			{
				"kind": kind,
				"event_id": String(event_id),
				"detail": detail,
				"sequence": int(ledger.get("sequence", 0)),
				"period": int(ledger.get("period", 0)),
			}
		)
	)


## Every open event id, canonically ordered by STRING value. `Array[StringName].sort()`
## is not specified to order by the interned string, and the order is load-bearing to
## a codex cycling the list, so it is pinned to the one comparison that cannot drift.
static func active_ids(ledger: Dictionary) -> Array[StringName]:
	var strings: Array[String] = []
	for key in (ledger.get("active", {}) as Dictionary).keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out


## The `resolved` map keyed `"<event_id>@<period>"`, the one shape a screen reads
## when it wants "what has happened, and when" in a single primitive table.
static func resolved_rows(ledger: Dictionary) -> Dictionary:
	var out := {}
	for event_id in (ledger.get("resolved", {}) as Dictionary).keys():
		var period := int((ledger["resolved"] as Dictionary)[event_id])
		out["%s%s%d" % [String(event_id), PERIOD_SEPARATOR, period]] = period
	return out


# --- Internals -------------------------------------------------------------


static func _known(key: String, known_ids: Dictionary) -> bool:
	return known_ids.is_empty() or known_ids.has(key)


static func _active_entry(entry: Dictionary) -> Dictionary:
	var history: Array[Dictionary] = []
	var stored = entry.get("history", [])
	if stored is Array:
		for record in stored as Array:
			if record is Dictionary:
				history.append((record as Dictionary).duplicate(true))
			if history.size() >= HISTORY_LIMIT:
				break
	var standoff = entry.get("standoff_id", "")
	return {
		"stage_id": String(entry.get("stage_id", "")),
		"opened_period": maxi(0, int(entry.get("opened_period", 0))),
		"periods_held": maxi(0, int(entry.get("periods_held", 0))),
		"last_resolved_period": maxi(0, int(entry.get("last_resolved_period", 0))),
		"territory_id": String(entry.get("territory_id", "")),
		# The standoff `NationApi` opened when this event was declared. Written by
		# `begin` and read by `resolve`, and never re-derived: the quota and the
		# prize are `nation`'s to keep (ADR 0085).
		"standoff_id":
		"" if not (standoff is String or standoff is StringName) else String(standoff),
		"declared": bool(entry.get("declared", false)),
		"history": history,
	}
