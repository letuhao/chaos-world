class_name WorldReconcile
extends RefCounted

## The lazy, observation-driven advance and the reconcile pass (ADR 0170, ADR 0173 (c)).
##
## ## ## THE HAZARD THIS FILE EXISTS NOT TO SHIP — READ THIS FIRST
##
## ADR 0173 (c) names it: "an observation-driven clock DEADLOCKS if every advance source
## is itself gated on someone being present. The world freezes forever, every elapsed
## calculation returns zero, and the failure is silent — nothing errors, everything is
## simply always zero."
##
## **THE RULE: ANY observation advances FIRST, then reads.** A reader is a TRIGGER,
## never a precondition of the trigger. There is no `if someone_is_here: advance()` and
## no `if visited: fold()` in this file, and there must never be one: gating the advance
## on presence makes presence itself conditional on the advance, and the world deadlocks
## with every answer reading zero.
##
## ## ## How it is prevented mechanically, not by discipline
##
## 1. [method observe] calls [method _fold] UNCONDITIONALLY on entry, before it has read
##    a single stamp. A never-visited place has NO stamp row, so
##    `ReconcileStamp.folded(..) == 0` and the first observation folds the whole span —
##    `tests/core/test_reconcile_stamp.gd` pins that a read on a never-visited place
##    returns a NON-ZERO elapsed value, which is the one test in that file that must
##    never be softened.
## 2. The fold is a MAX against the crossed count ([method ReconcileStamp.fold_all]),
##    so re-reading, re-entering, or reading out of order can never make a place look
##    LESS folded. A "has this happened" check anywhere in this path could only ever
##    return false for a place nobody stood in, and that false is what freezes the world.
## 3. Nothing here can LOWER anything. `ReconcileStamp.fold` raises only, `WorldEpoch`
## raises only, and `WorldFact.record` raises only — so no ordering of observations can
##    move history backwards even if a caller drives them out of order.
##
## ## O(1) in places, O(magnitudes) in arithmetic
##
## A coarse crossing writes ONE stamp row per magnitude and visits ZERO places. A
## reconcile is `O(places asked about)`, clamped through `RowBudget.cap()`, and each
## place costs `O(magnitudes crossed)`. A 10^9-year span costs the same handful of
## integer divisions as one period (`TimeLadder.conversion_work`), and leaves the rest
## of the world uniformly stale — which is a FLAG, not a walk (ADR 0170, Consequences).
##
## ## The worklist is built BEFORE the loop and is not mutated by it
##
## That is the shape `tests/arch_rules/test_no_unbounded_wait.gd` accepts. There is no
## `while` in this file at all, and no recursive walk: the one place that touches the
## content tree goes through `ContentScan` (`core/content_scan.gd`, `MAX_DEPTH := 32`),
## never a local `_scan` (AGENTS.md:54).
##
## ## No clock, ever
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (ADR 0089 / DEF-0111). A span is
## handed DOWN by the caller that owns time, and this file adds no frame driver — an
## observation is a trigger, not a driver (`tests/app/test_status_clock.gd:222-230`
## pins exactly three frame drivers in the tree and this is not one).

## The cap a pass folds BEFORE folding it, refused rather than reached.
##
## `RowBudget.MAX_ROWS` is comfortably above every authored pool and low enough that an
## accidental runaway is a refusal rather than a machine that stops responding
## (`core/row_budget.gd:22-25`).
const MAX_PLACES := RowBudget.MAX_ROWS

## How many buckets one place's observation is folded into. The authored magnitude count
## plus a floor, so a ladder that lost its `.tres` cannot silently fold nothing and
## report a clean pass — a ladder that answers "nothing happened" to everything is the
## silent-freeze hazard `TimeLadder`'s own table load names.
const MIN_BUCKETS := 1

## The refusal reasons, named rather than free text so a caller can branch and a test can
## assert. `too_many_places` is the overflow; the rest are inputs that cannot be met.
const REASON_NO_SPAN := "no_span"
const REASON_OVERFLOW := "too_many_places"
const REASON_EMPTY_LOCATION := "empty_location"


## # ## ## THE OBSERVATION
##
## Advance `location_id`'s clock over `span_periods` against its stored stamp, and
## ANSWER what elapsed. **Any observation advances first and reads second** — see the
## class docstring, which is the whole hazard.
##
## ## What is returned
##
## A primitives-only report, and every key is always present so a caller never reads a
## missing field as a zero:
## - `location_id`, `span_periods`, `stamped_before` (was there a stamp at all?)
## - `crossed` and `elapsed_periods` answer DIFFERENT questions, and the pair is the
##   whole contract
##
## - `crossed` — `{magnitude: whole count}` for EVERY authored magnitude the total has
##   reached, zeros included. A function of `span_periods` ALONE: this place's state is
##   not consulted, because the question is about the world clock rather than about this
##   place. A zero is a real answer ("this total crosses no second month"), and a caller
##   that could not tell a zero from a bucket nobody authored would have to treat every
##   missing key as an error.
## - `elapsed_periods` — what THIS visit newly contributed: the total minus what this
##   place had already folded, clamped at zero. **A re-read of an unchanged total pays
##   nothing** ("a place returning to scope is FOLDED, never replayed", ADR 0170), and a
##   total shorter than what this place folded pays nothing rather than a negative.
## - `advanced` — whether `elapsed_periods` is non-zero, so a caller can tell a no-op read
##   from a fold. It is deliberately NOT `not crossed.is_empty()`: with the raw map that
##   would be true for every non-zero span including a pure re-read, which is exactly the
##   "every read looks like a successful read" silence the ADR 0173 (c) hazard names.
##
## The stamp itself stays a MAX per magnitude ([method ReconcileStamp.fold_all]), so no
## ordering of these two arithmetic paths can lower a place — the subtraction above is a
## READ of the difference, never a write that moves a count down (ADR 0113).
##
## `offered` is left to the consumer: a reconcile READS the ledger's count for a place
## and never rewrites it (ADR 0170), and one bucket per magnitude crossed is handed to
## `WorldPulse.offer` by the caller — never one beat per period, which is the loop
## `world_pulse.gd:353-354` runs and ADR 0173 (b) retires.
static func observe(stamps: Dictionary, location_id: StringName, span_periods: int) -> Dictionary:
	var span := maxi(0, span_periods)
	var stamped_before := ReconcileStamp.knows_place(stamps, location_id)
	var was := ReconcileStamp.folded_periods(stamps, location_id)
	# `span_periods` is the TOTAL the world has moved, so the two answers here are about
	# DIFFERENT things and must not be conflated.
	#
	# `crossed` is the RAW ladder division of the total: every authored magnitude, whole
	# count, ZEROES INCLUDED. It answers "what has this place's whole elapsed time
	# reached", which is a function of the total alone and not of the place — the place is
	# NOT consulted for it. The zero entries are load-bearing rather than filler: a caller
	# asking "did this span cross a second month?" must get `0` and not `null`, because a
	# missing key reads as an unknown bucket to every consumer
	# (`TimeLadder.magnitudes_crossed` emits them for the same reason,
	# `core/time_ladder.gd:207`).
	#
	# `elapsed_periods` is the only newly-elapsed figure, and it is what a player is owed:
	# "a place returning to scope is FOLDED, never replayed" (ADR 0170). Two arrivals at a
	# one-year total pay 4380 then 0, and an arrival after the world doubles pays exactly
	# the NEW 4380 — which `test_reconcile_reachability.gd` pins through the production
	# chain. The clamp is load-bearing for the same reason: a span SHORTER than what this
	# place already folded (a stale or replayed read) owes nothing, never a negative.
	#
	# Neither figure is a subtraction on the WRITE path. `ReconcileStamp.fold_all` is the
	# only writer and it is a MAX per magnitude, so no ordering of observations can lower
	# a place — the ADR 0113 property `test_an_early_observation_does_not_move_a_later_one_backwards`
	# pins survives any change to this arithmetic.
	#
	# Advance FIRST, unconditionally, before any read of the place's state is returned.
	# There is no presence check in front of this line and there may never be one.
	#
	# The WRITE takes the ABSOLUTE division and `fold_all` maxima it, so a place's date
	# is the highest count the world has ever reached and no fold can lower it (ADR 0113).
	# The two ANSWERS are about this VISIT: `crossed` is what the visit newly folded
	# (`ReconcileStamp.newly_folded`, zeros present so a caller reads `0` and not a
	# missing key) and `elapsed_periods` is the periods it added. Reporting the absolute
	# map for a re-read would say "1 month" about a visit that folded none, which is
	# exactly the silence ADR 0173 (c) names.
	var absolute := TimeLadder.magnitudes_crossed(span)
	var out := ReconcileStamp.fold_all(stamps, location_id, absolute)
	var crossed := ReconcileStamp.newly_folded(stamps, location_id, absolute)
	var elapsed := maxi(0, span - was)
	return {
		"location_id": String(location_id),
		"span_periods": span,
		"stamped_before": stamped_before,
		"elapsed_periods": elapsed,
		"crossed": crossed,
		"advanced": elapsed > 0,
		"stamps": out,
	}


## ## ## The reconcile pass
##
## Fold the crossed magnitudes for the places ASKED ABOUT, in one pass, clamped through
## [method RowBudget.cap] and **refused loudly on overflow**.
##
## ## Why it refuses rather than truncating
##
## "A reconcile that truncates reports nothing the player can see, and that is why it
## refuses instead. `RowBudget` truncates a *screen* and says 'N of M'
## (`row_budget.gd:14-16`), the right trade there. A truncated reconcile leaves a place
## silently stale, and the player walks into a district that believes it is a decade old"
## (ADR 0170). So exceeding [constant MAX_PLACES] `push_error` naming the count and the
## cap and RETURNS refused — no stamp is written, no place is half-folded, and the caller
## can act on `ok == false`. `AGENTS.md:56`, `:75`: make the feature fail loudly.
##
## ## The cap is checked ONCE, against the worklist, BEFORE the loop
##
## Not per place and not inside it: `RowBudget.cap` is one shared helper "because the
## value only means something as a single number" (`row_budget.gd:17-20`), and a cap
## re-checked per iteration is a cap that can be crossed by a list that grew between the
## check and the walk. The worklist is the caller's array, read once into the loop below
## and never appended to — and every bucket below is folded with ONE call per place, the
## `for` the arch rule can see, never a `while` over a span or a period count.
static func reconcile(stamps: Dictionary, places: Array, span_periods: int) -> Dictionary:
	var span := maxi(0, span_periods)
	var asked := places.size()
	var report := {
		"ok": true,
		"reason": "",
		"places_asked": asked,
		"places_folded": 0,
		"span_periods": span,
		"cap": MAX_PLACES,
		"crossed": {},
		"stamps": stamps,
		"locations": [],
	}
	if span <= 0:
		report["ok"] = false
		report["reason"] = REASON_NO_SPAN
		return report
	if asked > MAX_PLACES:
		report["ok"] = false
		report["reason"] = REASON_OVERFLOW
		push_error(
			(
				(
					"WorldReconcile: a pass over %d places was asked for and the cap is %d. "
					% [asked, MAX_PLACES]
				)
				+ "Refusing rather than truncating: a reconcile that drops a place leaves it "
				+ "silently stale and the player walks into a district that believes it is a "
				+ "decade old (ADR 0170). No stamp was written."
			)
		)
		return report
	var out := ReconcileStamp.normalize(stamps)
	var folded_locations: Array[String] = []
	var buckets := 0
	# **The crossed map is computed ONCE, before the loop, and never inside it.** Inside
	# the loop it would be the shape `TimeLadder` exists to replace: one division per
	# authored magnitude per PLACE, so a pass over the cap would convert the same span
	# `cap` times to learn something that is a function of the span alone. This is the
	# single biggest reason the pass is O(magnitudes) and not O(magnitudes x places).
	var crossed := TimeLadder.magnitudes_crossed(span)
	for place in places:
		var location_id := StringName(str(place))
		if location_id == &"":
			report["ok"] = false
			report["reason"] = REASON_EMPTY_LOCATION
			return report
		# One stamp write per place, raised against the crossed count. This is the ONLY
		# place a pass folds, and it never reads the ledger: a reconcile changes what a
		# place HAS BECOME and never what it PROMISES (ADR 0170).
		out = ReconcileStamp.fold_all(out, location_id, crossed)
		buckets += maxi(MIN_BUCKETS, TimeLadder.magnitudes().size())
		folded_locations.append(String(location_id))
	report["places_folded"] = asked
	report["crossed"] = crossed
	report["locations"] = folded_locations
	report["buckets"] = buckets
	report["stamps"] = out
	return report


## Every `location_id` the authored world ships, read through [method ContentScan] so the
## depth cap is the repo's (`core/content_scan.gd:22`, `MAX_DEPTH := 32`) and never a
## local `_scan` this guard cannot see (AGENTS.md:54).
##
## **This is a READ of the authored tree, not a reconcile of it.** ADR 0170 refuses a
## "reconcile-everything sweep on load — trigger: never", so nothing here folds a place;
## it exists so a caller can report which places exist without hand-listing them.
##
## The locations directory is read at whatever depth an author nests it, and a `.tres`
## that does not load or names no `location_id` is SKIPPED rather than refused: a broken
## content row is a content gap, and `DomainMinimap._zones` is deliberately not fogged
## because a hazard must be visible before you stand in it.
static func shipped_locations(root: String = "res://data/world/locations") -> Array[StringName]:
	var out: Array[StringName] = []
	for path in ContentScan.files_under(root, ContentScan.DEFAULT_SUFFIX):
		var def = load(path)
		if not def is WorldLocationDef:
			continue
		var location_id := (def as WorldLocationDef).location_id
		if location_id != &"":
			out.append(location_id)
	return out


## The shipped shape as primitives only, so `tools ui drive` can print a world's date
## with no display and a test can assert without reaching into a nested map.
##
## `summary` delegates to the two files that own the numbers — [method ReconcileStamp.summary]
## and [method WorldEpoch.summary] — rather than re-deriving them, because two copies of
## a summary is how the repo got four copies of `RATE_STEP` (ADR 0116).
static func summary(stamps: Dictionary, epochs: Dictionary = WorldEpoch.empty()) -> Dictionary:
	var folded := ReconcileStamp.summary(stamps)
	return {
		"places": int(folded.get("places", 0)),
		"locations": folded.get("locations", []),
		"total_periods_folded": int(folded.get("total_periods_folded", 0)),
		"periods_folded": folded.get("periods_folded", []),
		"cap": MAX_PLACES,
		"buckets": maxi(MIN_BUCKETS, TimeLadder.magnitudes().size()),
		"event_budget": TimeLadder.EVENT_BUDGET,
		"epoch": WorldEpoch.summary(epochs),
	}
