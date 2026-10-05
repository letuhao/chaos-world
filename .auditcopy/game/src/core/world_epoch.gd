class_name WorldEpoch
extends RefCounted

## Which history a world is currently living (ADR 0170, "The epoch: rewriting history
## without un-recording a fact").
##
## ## "Cleared" means the epoch advanced, NEVER that a fact was withdrawn
##
## A Transcendent retreat spans 10^9 years: lower worlds age, sect lineages rise and
## die whole, and places are destroyed outright. The ledger records every one of those
## occurrences and they STAY recorded; what changes is which epoch's state they describe.
## `founded_temple@1`, `temple_destroyed@1`, `founded_temple@2` are three true things,
## not one thing recorded, erased, and recorded again.
##
## ## A place's current state is DERIVED from (ledger, epoch)
##
## Never a mutable field and never a decrement. `WorldFact` is monotone by design
## (ADR 0113: a thing that happened, `record` only raises) and ADR 0065 makes "fate is
## earned, never removed" a house rule; a negative write would break both, which is why
## this file has no verb that can lower anything. [method state_of] is the ONLY shape a
## reader is given, and it computes rather than stores.
##
## ## A destroyed world is RETIRED, not deleted
##
## It stops being current and a successor carries the next epoch ([method retire] then
## [method successor]). Nothing is ever un-recorded, so a save written in epoch 1 still
## reads correctly after the world has been rebuilt — that is the property the retirement
## buys and the reason it is not a delete.
##
## ## The epoch is the reconcile stamp's SIBLING, and it is discardable too
##
## The stamp says how stale a place is; the epoch says which history it is living. Same
## owner, same `core/` home, same argument: delete the epoch set and the world resolves
## to epoch 1, which is a full pass rather than a corruption.
##
## ## What an epoch advance costs: the SAME budget as any other span
##
## `EVENT_BUDGET` (ADR 0173 (b)) — a billion-year skip does not get an unbounded number
## of events because it destroyed a world, it gets `C`, and exceeding it fails loudly
## rather than truncating. [method advance] routes the check through the SSOT's own
## `exceeds_budget`, so there is one budget in the repository rather than two that
## could drift.
##
## ## No clock, no driver, no loop this file cannot bound
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (ADR 0089 / DEF-0111), and no
## `while` at all. Every loop walks an authored or caller-supplied array, so
## `tests/arch_rules/test_no_unbounded_wait.gd` has nothing here to refuse.

## The epoch a world starts in. One, because a world that has never been rebuilt has
## never been anything else — and `delete` therefore resolving to epoch 1 is a full
## pass, not a corruption.
const FIRST := 1

## The key shape every payload is written in. `String` keys throughout, no `StringName`:
## this payload is destined for a save blob and a UI summary, where an interned name is
## not a value — the same rule `WorldFact.to_dict` states for the same reason.
const VERSION := 1


## No epochs recorded at all. A world nobody has named reads as epoch [constant FIRST],
## which is the same answer as "it has never been rebuilt".
static func empty() -> Dictionary:
	return {"version": VERSION, "worlds": {}}


## The payload `epochs` came from, repaired. Never throws — a save is untrusted input,
## so a foreign or hand-edited payload is DIAGNOSED as the empty set rather than
## partially applied. A world id is kept only when it names something AND the epoch is a
## whole number of at least [constant FIRST]: a world at epoch 0 or below is not a world
## this file can read, and storing it would let a subtraction underflow the next advance.
static func normalize(payload: Variant) -> Dictionary:
	var out := empty()
	if not payload is Dictionary:
		return out
	var worlds = (payload as Dictionary).get("worlds", {})
	if not worlds is Dictionary:
		return out
	for key in (worlds as Dictionary).keys():
		var world_id := String(key)
		if world_id.is_empty():
			continue
		var epoch := int((worlds as Dictionary)[key])
		if epoch >= FIRST:
			out["worlds"][world_id] = epoch
	return out


## The epoch `world_id` is living, or [constant FIRST] for a world nobody recorded.
##
## A missing world and a world in its first epoch are the SAME answer, which is what
## makes the overlay discardable: dropping the set resolves everything to epoch 1 and
## re-reads the whole ledger rather than losing history.
static func current(epochs: Dictionary, world_id: StringName) -> int:
	var worlds := normalize(epochs)["worlds"] as Dictionary
	return maxi(FIRST, int(worlds.get(String(world_id), FIRST)))


## Whether `world_id` is RETIRED — it was rebuilt and a successor carries the next epoch.
##
## A retirement is recorded, never inferred from a successor existing, so "this world was
## cleared" is answerable without looking anything else up.
static func is_retired(epochs: Dictionary, world_id: StringName) -> bool:
	var worlds := normalize(epochs)["worlds"] as Dictionary
	return bool(worlds.get(_retired_key(world_id), false))


## `epochs` with `world_id` living at `epoch`. **RAISES ONLY, never lowers**: a lower
## epoch would un-apply history that was already applied, which is the decrement ADR
## 0170 replaces with an overlay. A caller asking to go backwards is asking to withdraw
## a fact, so [method retire] is the answer they want.
##
## An epoch below [constant FIRST] is refused by clamping rather than by an error: it is
## the only input that cannot produce a state, and it is a cache-scrubbing mistake rather
## than a design, so the clamped value is diagnosable and the loud refusal is kept for the
## case that really cannot be met — the event budget.
static func advance_to(epochs: Dictionary, world_id: StringName, epoch: int) -> Dictionary:
	var out := normalize(epochs)
	if world_id == &"":
		return out
	(out["worlds"] as Dictionary)[String(world_id)] = maxi(
		FIRST, maxi(current(out, world_id), epoch)
	)
	return out


## `epochs` with `world_id` advanced by `periods_periods` worth of history: the number of
## whole EPOCHS the span pays for, given `periods_per_epoch` authored periods each.
##
## `EVENT_BUDGET` is the ceiling and it FAILS LOUDLY through
## `TimeLadder.exceeds_budget`, naming the world, the span and the count. A span of any
## length gets `C` events; one that would buy more epochs than `C` is refused rather than
## truncated, because "a silently truncated history is worse than a refusal" (ADR 0173
## (b)) — the ledger is monotone and cannot un-record what it was never told.
##
## Returns the epoch set and the pass report, `{ok, reason, world_id, epoch, epochs}`,
## primitives only: the set is handed back because it is DERIVED, so the caller folds it
## forward rather than mutating a shared one in place.
static func advance(
	epochs: Dictionary, world_id: StringName, span_periods: int, periods_per_epoch: int
) -> Dictionary:
	var out := normalize(epochs)
	var report := {
		"ok": false, "reason": "", "world_id": String(world_id), "epoch": current(out, world_id)
	}
	if world_id == &"":
		report["reason"] = "empty_world_id"
		return {"ok": false, "reason": report["reason"], "epochs": out}
	if periods_per_epoch < 1:
		report["reason"] = "non_positive_epoch_periods"
		return {"ok": false, "reason": report["reason"], "epochs": out}
	var epochs_crossed := maxi(0, span_periods) / periods_per_epoch
	if TimeLadder.exceeds_budget(epochs_crossed, world_id, span_periods):
		return {
			"ok": false,
			"reason": "over_budget",
			"epochs": out,
		}
	out = advance_to(out, world_id, current(out, world_id) + epochs_crossed)
	report["ok"] = true
	report["epoch"] = current(out, world_id)
	return {"ok": true, "epoch": report["epoch"], "epochs": out}


## `epochs` with `world_id` RETIRED: it stops being current, its occurrences stay
## recorded, and [method successor] carries the next epoch.
##
## Nothing is deleted. That is the whole difference from a delete, and it is why a save
## written in epoch 1 still reads correctly after the world has been rebuilt.
static func retire(epochs: Dictionary, world_id: StringName) -> Dictionary:
	var out := normalize(epochs)
	if world_id == &"":
		return out
	var worlds := out["worlds"] as Dictionary
	worlds[String(world_id)] = maxi(current(out, world_id), FIRST)
	worlds[_retired_key(world_id)] = true
	return out


## The epoch a successor of `world_id` would carry, and the epoch set with it applied to
## `successor_id`. The retired world is untouched and un-rewritten.
##
## A successor that is ALREADY recorded at a higher epoch keeps that epoch: history that
## was already rewritten is not rewritten again.
static func successor(
	epochs: Dictionary, world_id: StringName, successor_id: StringName
) -> Dictionary:
	var out := retire(epochs, world_id)
	if successor_id == &"":
		return out
	return advance_to(out, successor_id, current(out, world_id) + 1)


## What `world_id` IS NOW, derived from the occurrences the reader hands in and the epoch
## it reads at. Never stored, never a mutable field, never a decrement.
##
## ## `occurrences` is one row per thing that happened: `{id, epoch, amount}`, and the
## ## list is MONOTONE — the reader hands back every occurrence ever recorded and this
## function decides which ones still apply. An occurrence whose epoch is ABOVE the one
## being read has not happened YET in that history (`founded_temple@2` does not exist
## while a reader still resolves epoch 1), and one at or below it has.
##
## ## **The ledger's count never falls because this function never writes.** There is no
## decrement verb in this file and none in `WorldFact`; a reader that wants a count for
## the current epoch sums the rows this returns and can report zero for a place whose
## history was rewritten, while `WorldFact.count` still answers for every occurrence.
## That separation — a derived overlay over a monotone ledger — is the whole of ADR 0170's
## epoch, and a place's state is therefore a function of (ledger, epoch) rather than a
## field either could lower.
##
## Sorted by id, for the reason `WorldFact.ids` sorts: two runs of the same overlay must
## agree on the row order or the answer cannot be diffed against anything.
static func state_of(epochs: Dictionary, world_id: StringName, occurrences: Array) -> Dictionary:
	var epoch := current(epochs, world_id)
	var applied: Array[String] = []
	var deferred: Array[String] = []
	var counts: Dictionary = {}
	var epoch_keys: Array[int] = []
	# **Read every occurrence ONCE.** A guard of the shape
	# `if occ.get("epoch") is Dictionary:` admits a row with no epoch, and the body then
	# answers `null` and the cast throws. Reading once also means the count and the
	# applied name can never disagree about which rows were taken.
	for occurrence in occurrences:
		var row := _occurrence(occurrence)
		if row.is_empty():
			continue
		var id := String(row["id"])
		if int(row["epoch"]) <= epoch:
			counts[id] = int(counts.get(id, 0)) + int(row["amount"])
			applied.append(id)
			epoch_keys.append(int(row["epoch"]))
		else:
			# NOT erased and NOT "has not happened": it belongs to a history this world
			# is not living, so the reader is told which rows it did not take. A row that
			# was silently dropped would be indistinguishable from one that never existed,
			# and the ledger cannot un-record what it was never shown.
			deferred.append(id)
	applied.sort()
	deferred.sort()
	epoch_keys.sort()
	return {
		"world_id": String(world_id),
		"epoch": epoch,
		"retired": is_retired(epochs, world_id),
		"applied": applied,
		"applied_epochs": epoch_keys,
		"deferred": deferred,
		"counts": counts,
	}


## Every world id in `epochs`, sorted by string value. Published so a caller can report
## which worlds have been rebuilt without walking a raw dictionary whose key order is not
## specified to be stable across platforms.
static func worlds(epochs: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for key in (normalize(epochs)["worlds"] as Dictionary).keys():
		ids.append(String(key))
	ids.sort()
	return ids


## The shipped epoch set as primitives only, so `tools ui drive` can print a world's
## date with no display and a test can assert without reaching into a nested map.
static func summary(epochs: Dictionary) -> Dictionary:
	var rows := normalize(epochs)["worlds"] as Dictionary
	var ids: Array[String] = []
	var current_epochs: Array[int] = []
	var retired: Array[String] = []
	for key in rows.keys():
		ids.append(String(key))
	for id in ids:
		current_epochs.append(int(rows[id]))
		if bool(rows.get(_retired_key(StringName(id)), false)):
			retired.append(id)
	ids.sort()
	return {
		"version": VERSION,
		"worlds": worlds(epochs).size(),
		"ids": ids,
		"current": current_epochs,
		"retired": retired,
		"first_epoch": FIRST,
	}


## The key a retirement is recorded under, kept beside the epoch rather than inside it:
## a world at epoch 7 that is retired must still read as 7.
static func _retired_key(world_id: StringName) -> String:
	return "retired:%s" % String(world_id)


## One occurrence row, coerced. An empty result means the row names nothing, which is
## dropped rather than stored: an unnamed occurrence can never be read back by any verb,
## so keeping it would persist a claim no query can reach.
static func _occurrence(row: Variant) -> Dictionary:
	if row is Dictionary:
		var source := row as Dictionary
		if String(source.get("id", "")).is_empty():
			return {}
		return {
			"id": String(source.get("id", "")),
			"epoch": maxi(FIRST, int(source.get("epoch", FIRST))),
			"amount": maxi(1, int(source.get("amount", 1))),
		}
	if row is WorldBeat:
		var beat := row as WorldBeat
		if beat.fact == &"":
			return {}
		return {"id": String(beat.fact), "epoch": FIRST, "amount": maxi(1, beat.amount)}
	return {}
