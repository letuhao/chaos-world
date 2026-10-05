class_name ReconcileStamp
extends RefCounted

## How STALE each place is, at each authored magnitude (ADR 0170). `location_id ->
## {magnitude -> last folded count}`, integers only, beside `TimeLadder` and
## `RealmRate` because `core` is a LAYER (`tools/arch/rules.py:29`) so this adds
## ZERO new arch edges.
##
## ## Derived, and DISCARDABLE, and that is the whole argument for it
##
## "Delete the stamp and the next reconcile is simply a full pass. A ledger that can
## be wrong forever is a hazard; a stamp that is wrong only until the next reconcile is
## a cache" (ADR 0170). So nothing here is load-bearing state: a missing key reads as
## never-folded, and [method forget] deletes a place without touching a fact.
##
## ## NOT a `WorldFact` field, and the reason is mechanical
##
## `record` only raises (ADR 0113) and ADR 0065 makes fate "earned, never removed". A
## place folded to period 40 and then to period 12 is a POSITION ON THE LADDER, not a
## monotone fact: putting it on the ledger would make every reader decide whether it is
## fresh, and a mutable field on the one monotone truth is a second writer on it.
##
## ## Keyed by NAME, never by index — ADR 0050's anti-shift rule
##
## Both halves of the key are names: `location_id` is a durable string (ADR 0113), and
## the magnitude is the `TimeLadder` row id. A magnitude row inserted above this one
## changes no answer here, exactly as it changes none in `magnitudes_crossed`. An index
## key would silently re-stamp every place below the insertion (`AGENTS.md:140`).
##
## ## Periods or magnitudes? MAGNITUDES, and the number stored is a FOLD COUNT
##
## The stored number is the count of that magnitude already folded at this place — NOT a
## period count. Two reasons, both load-bearing:
## 1. A period count would have to be re-expressed in the same unit the ladder converts
##    from, which is the ladder's authored `ratio_periods` — so a retune of one ratio
##    would silently re-interpret every stamp already written. A fold count survives the
##    retune, because it is a position on the scale rather than a span in its unit.
## 2. Magnitudes truncate INDEPENDENTLY and the surplus is DROPPED
##    (`core/time_ladder.gd:180-185`), so a period watermark could never be advanced by
##    whole periods: folding 400 periods at a 360-period month leaves the month at 1 and
##    40 periods of surplus that belong to nobody. Storing the fold count means the
##    NEXT reconcile asks `magnitudes_crossed(span)` again and drops the same surplus,
##    which is the rule rather than a second opinion about it.
##
## The two are convertible: periods read through [method folded_periods], and that is a
## read for DISPLAY, never a write path back into a watermark.
##
## ## No clock, no driver, no loop this file cannot bound
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (ADR 0089 / DEF-0111): a span is
## handed DOWN by the caller that owns time. Every loop walks `TimeLadder.magnitudes()`
## or a caller-supplied array; there is no `while` at all, so
## `tests/arch_rules/test_no_unbounded_wait.gd` has nothing here to refuse.
##
## Every stored value is clamped into `[0, INT_MAX]` on the way in and on the way out,
## because a stamp is DERIVED: a hand-edited or corrupted payload must answer a number
## rather than propagate one that makes a subtraction wrap (ADR 0042's engine-headroom
## question, asked here of a cache rather than of a power ladder).

## The key shape every payload is written in, and the one [method to_dict] emits.
## `String` keys throughout, no `StringName`: this payload is destined for a save blob
## and a UI summary, where an interned name is not a value — the same rule
## `WorldFact.to_dict` and `InstitutionClaim` state for the same reason.
const VERSION := 1

## Above any fold count a `.tres`-authored ladder can reach, and far inside GDScript's
## 64-bit `int`. A stamp is a cache: a corrupt one is deleted, never preserved.
const MAX_FOLD := 0x7FFFFFFFFFFFFFFF


## An empty stamp set. A payload nobody has written and a payload that could not be
## read are the same value, so "no place is stale" has one spelling instead of three.
static func empty() -> Dictionary:
	return {"version": VERSION, "stamps": {}}


## The payload `stamps` came from, repaired. Never throws: a save is untrusted input,
## so a hand-edited or foreign payload is DIAGNOSED as the empty set rather than
## partially applied — half a stamp table is worse than none, because it would leave
## places silently stale with nothing reporting it.
##
## Every value is coerced to an `int` in `[0, MAX_FOLD]` and an unnamed magnitude is
## DROPPED, because an unnamed row can never be read back by any verb and would persist
## a freshness claim no query can reach — a cache nothing can ask for.
static func normalize(payload: Variant) -> Dictionary:
	var out := empty()
	if not payload is Dictionary:
		return out
	var rows = (payload as Dictionary).get("stamps", {})
	if not rows is Dictionary:
		return out
	for key in (rows as Dictionary).keys():
		var location := String(key)
		var row = (rows as Dictionary)[key]
		if location.is_empty() or not row is Dictionary:
			continue
		var folded: Dictionary = {}
		for magnitude in (row as Dictionary).keys():
			var name := String(magnitude)
			if name.is_empty():
				continue
			folded[name] = _fold((row as Dictionary)[magnitude])
		# A place is kept once it names SOMETHING, which is the `WorldFact.normalize` rule
		# restated: a row that cannot be read by any verb is a cache nothing can ask for.
		# **A zero fold count survives on purpose** — a place observed over a span shorter
		# than one coarse magnitude is legitimately folded-at-zero and must still read as
		# VISITED, or the next reconcile would treat it as never seen and re-fold the world.
		if not folded.is_empty():
			out["stamps"][location] = folded
	return out


## One place's fold counts as primitives, or `{}` for a place that has never folded.
## A COPY, never a view: mutating the answer changes no stamp, so a caller cannot reach
## past [method fold] to edit a cache by hand. Rejected: handing back the stored
## dictionary, which is the second writer this file exists to avoid.
static func folds_for(stamps: Dictionary, location_id: StringName) -> Dictionary:
	var rows = normalize(stamps)["stamps"]
	if not rows is Dictionary:
		return {}
	var entry = (rows as Dictionary).get(String(location_id))
	if not entry is Dictionary:
		return {}
	return (entry as Dictionary).duplicate()


## How many of `magnitude` this place has already folded, or `0` for a place or
## magnitude it has never folded.
##
## `0` and not "never visited" is deliberate: a never-visited place reads as zero
## folds, so the first observation of it folds the whole span. That is the deadlock
## guard `WorldReconcile.observe` is built on — a place nobody has stood in still
## reports elapsed time (ADR 0173 (c)).
static func folded(stamps: Dictionary, location_id: StringName, magnitude: StringName) -> int:
	return int(folds_for(stamps, location_id).get(String(magnitude), 0))


## `stamps` with `location_id -> magnitude` raised to `count`. **RAISES ONLY, and
## never lowers one**: a lower value would move a place BACKWARDS on the ladder, which
## is the decrement ADR 0113's monotone ledger exists to forbid and ADR 0170's epoch
## exists to replace. A caller asking to lower a stamp is asking for a retraction, so
## [method forget] is the answer they want and it deletes rather than decrements.
##
## `count` is clamped into `[0, MAX_FOLD]`: a negative fold count would make the next
## span compute as a longer one, which is the "silently stale" shape ADR 0170 refuses.
static func fold(
	stamps: Dictionary, location_id: StringName, magnitude: StringName, count: int
) -> Dictionary:
	var out := normalize(stamps)
	if location_id == &"" or magnitude == &"":
		return out
	var rows := out["stamps"] as Dictionary
	# **Read the existing row ONCE, through the two-argument `get`.** A guard of the
	# shape `if rows.get(key, {}) is Dictionary:` is a TRAP: the default IS a
	# Dictionary, so the guard holds for a place that was never stamped, and the
	# single-argument `get` inside the body then answers `null` and the cast throws.
	var entry: Dictionary = (rows.get(String(location_id), {}) as Dictionary).duplicate()
	entry[String(magnitude)] = _fold(count)
	rows[String(location_id)] = entry
	return out


## `stamps` with every magnitude this pass folded already raised by `crossed` — the one
## O(magnitudes) write a whole reconcile pass makes, once per place rather than once
## per consumer (ADR 0170: "one stamp write per magnitude").
##
## Built from the authored row array `TimeLadder.magnitudes()` plus the caller's own
## `crossed` map, so a magnitude nobody authored is folded too rather than silently
## skipped: a caller that folds a bucket the table does not name has still folded it.
static func fold_all(
	stamps: Dictionary, location_id: StringName, crossed: Dictionary
) -> Dictionary:
	var out := normalize(stamps)
	if location_id == &"":
		return out
	var wanted: Array[String] = []
	for row in TimeLadder.magnitudes():
		wanted.append(String(row.get("name", "")))
	for magnitude in crossed.keys():
		wanted.append(String(magnitude))
	var rows := out["stamps"] as Dictionary
	# One read of the existing row, not a guard plus a second read: see `fold` above for
	# why `rows.get(key, {}) is Dictionary` admits a row that is not there.
	var entry: Dictionary = (rows.get(String(location_id), {}) as Dictionary).duplicate()
	for magnitude in wanted:
		if magnitude.is_empty() or not crossed.has(magnitude):
			continue
		# **A MAX, and it has to stay one.** `fold_all` is public and is called directly,
		# with an ABSOLUTE crossed map, by most of this file's suite — so `maxi` is its
		# contract: a magnitude is stored at the highest count it has ever been seen at,
		# and no ordering of folds can lower it (ADR 0113). Making this additive was tried
		# and it is wrong for that caller: a direct `fold_all` of the same month twice
		# would read as two months ("one month folded: expected 1, got 2").
		#
		# Accumulation across VISITS therefore does not belong here. It lives in
		# `WorldReconcile.observe`, which subtracts what the place already folded (see
		# `newly_folded`) and hands a DELTA — and a delta against a max is exactly what
		# makes the second arrival's date advance without any write ever going down.
		entry[magnitude] = maxi(entry.get(magnitude, 0), _fold(crossed[magnitude]))
	rows[String(location_id)] = entry
	return out


## The stamp set with `location_id` DELETED — the whole of the discardability argument,
## stated as a verb. No fact moves, no count falls, and the next reconcile of that place
## is a full pass over the span rather than an error.
##
## Deleting a place nobody stamped is not a failure, for the reason `WorldFact.ids` has
## one spelling for "nothing happened".
static func forget(stamps: Dictionary, location_id: StringName) -> Dictionary:
	var out := normalize(stamps)
	(out["stamps"] as Dictionary).erase(String(location_id))
	return out


## How many places carry a stamp, and therefore how many are NOT stale. The cheap
## question a caller can ask before deciding to reconcile: a pass over zero places
## costs nothing, and a pass over every place costs a full walk it may not need.
static func place_count(stamps: Dictionary) -> int:
	return (normalize(stamps)["stamps"] as Dictionary).size()


## Whether `location_id` carries any stamp at all. `folded(..) > 0` cannot answer this:
## a place that has been observed over a span shorter than one coarse magnitude is
## legitimately folded-at-zero and must still be known as visited.
static func knows_place(stamps: Dictionary, location_id: StringName) -> bool:
	return (normalize(stamps)["stamps"] as Dictionary).has(String(location_id))


## The whole span `location_id` has folded, in periods — the read `tools ui drive`
## prints a world's date from, and O(1) rather than a walk over the magnitudes.
##
## **This is the BASE row and nothing else**, because the base's authored ratio is one
## period (`TimeLadder.BASE`, `ratio_for(BASE) == 1`): the base fold count IS the span,
## while every coarser row is that span re-bucketed with the surplus DROPPED
## (`core/time_ladder.gd:180-185`). Summing the rows instead would read 400 periods as
## 1156, which is a date nobody lived through.
##
## **The one place a ratio retune would be felt**, and it is worth naming: this value is
## only the span while `period` keeps its authored ratio of one. That is why it is a READ
## and never a write path — no caller folds from it, so re-pricing the base row changes
## what a date PRINTS and never what a stamp means.
static func folded_periods(stamps: Dictionary, location_id: StringName) -> int:
	return folded(stamps, location_id, TimeLadder.BASE)


## ## There is deliberately NO "newly crossed" filter, and this is where it was removed
##
## An earlier revision of `WorldReconcile.observe` routed the raw ladder division through
## a `newly_crossed(stamps, location_id, crossed)` that dropped every magnitude this
## place already held, and read `elapsed_periods` off the survivors. **Measured, it was
## wrong twice over, and the reason is that the filter conflated two different questions.**
##
## 1. It made `crossed` a function of the PLACE rather than of the span, and a filter
##    that returns `{}` for an unchanged total cannot answer "this total crosses no second
##    month" with a `0` — it answers with an ABSENT key, and a caller reading a default
##    (`crossed.get(&"month", -1)`) gets `-1`. The zero entries are the answer; filtering
##    them out is what made `test_a_re_observed_place_does_not_pay_a_second_bucket` red.
## 2. `elapsed_periods` taken from the BASE bucket of that filtered map is wrong whenever
##    the place has folded a LARGER span than the one in hand: a place folded at 360
##    handed a 12-period span reported zero newly elapsed, while the same place handed
##    8760 after folding 4380 reported all 8760 instead of the 4380 that actually elapsed.
##
## **[method fold_all]'s `maxi` IS the idempotency, per BUCKET and by itself.** The write
## path needs no filter: `maxi(existing, crossed)` already refuses to replay a bucket a
## place holds, so "a place returning to scope is FOLDED, never replayed" (ADR 0170) is
## enforced where the write happens rather than by pre-filtering its input. Adding a
## filter on top bought nothing and cost the two answers above — and a pre-filter is the
## more dangerous shape, because it makes the WRITER depend on a READ of what was already
## stored, so a stale or hand-edited stamp changes what gets written.


## What `absolute` adds for `location_id` that this place has not folded YET, keyed by
## magnitude, with the zeros PRESENT.
##
## **A subtraction on the READ, never on the write.** [method fold_all] stores
## `maxi(existing, crossed)` per magnitude, so the write path already refuses to replay a
## bucket; this exists because the ANSWER a caller reads is a different question from the
## one the writer answers. `magnitudes_crossed` is the absolute division and says "1 month"
## for a re-read of a one-month total — true of the span, false of the visit.
## `test_a_re_observed_place_does_not_pay_a_second_bucket` pins the visit reading, so a
## magnitude the place already holds answers `0` here rather than repeating itself.
##
## The zeros are load-bearing rather than filler: that test reads
## `crossed.get(&"month", -1)` and expects `0`, so an ABSENT key would answer `-1` and a
## missing bucket would read as an unknown one to every consumer — the same reason
## `TimeLadder.magnitudes_crossed` emits its own zeros (`core/time_ladder.gd:196-198`).
##
## A place folded nothing yet gets every magnitude whole, which is the ADR 0173 (c)
## property: a first arrival folds the WHOLE span, because a filter gated on "have I been
## here" is the deadlock that ADR names.
static func newly_folded(
	stamps: Dictionary, location_id: StringName, absolute: Dictionary
) -> Dictionary:
	var fresh: Dictionary = {}
	for magnitude in absolute.keys():
		var name := StringName(str(magnitude))
		var count := int(absolute[magnitude])
		fresh[name] = maxi(0, count - folded(stamps, location_id, name))
	return fresh


## One place as primitives only, for a screen or a headless drive that wants this place
## rather than the whole set. Sorted magnitude names, so two runs of the same pass agree
## on the row order.
static func view(stamps: Dictionary, location_id: StringName) -> Dictionary:
	var folds := folds_for(stamps, location_id)
	var names: Array[String] = []
	var counts: Array[int] = []
	for key in folds.keys():
		names.append(String(key))
	names.sort()
	for name in names:
		counts.append(int(folds[name]))
	return {
		"location_id": String(location_id),
		"stamped": folds_for(stamps, location_id).size() > 0,
		"periods_folded": folded_periods(stamps, location_id),
		"magnitudes": names,
		"counts": counts,
	}


## The shipped stamp set as primitives only, so `tools ui drive` can print a world's
## date with no display and a test can assert without reaching into a nested map.
##
## `locations` and `periods_folded` are both SORTED BY ID rather than taken in
## dictionary order: `WorldFact.ids` makes the same refusal for the same reason, and a
## summary whose row order changes between runs cannot be diffed against anything.
static func summary(stamps: Dictionary) -> Dictionary:
	var rows := normalize(stamps)["stamps"] as Dictionary
	var names: Array[String] = []
	var periods: Array[int] = []
	var total := 0
	for key in rows.keys():
		names.append(String(key))
	names.sort()
	for name in names:
		var folded_at_place := folded_periods(stamps, StringName(name))
		periods.append(folded_at_place)
		total += folded_at_place
	return {
		"version": VERSION,
		"places": rows.size(),
		"locations": names,
		"periods_folded": periods,
		"total_periods_folded": total,
	}


## A stored or supplied count, clamped into `[0, MAX_FOLD]` and an `int`. One coercion
## for every door a number can arrive at, because a stamp is derived and must never
## carry a value that makes a later subtraction wrap.
static func _fold(value: Variant) -> int:
	return clampi(int(value), 0, MAX_FOLD)
