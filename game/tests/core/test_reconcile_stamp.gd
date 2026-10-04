extends TestCase

## ADR 0170 (a world advances in stages and a stage marks stale what it did not
## reconcile) and ADR 0173 (c) (a place advances when observed). `core/reconcile_stamp.gd`,
## `core/world_epoch.gd` and `core/world_reconcile.gd` are the implementation.
##
## ## The cases here assert the PROPERTIES the two ADRs buy, not the shape these files
## happen to have — a stamp that starts empty, stays per-place, never lowers, is safe to
## discard, and refuses loudly; an epoch that rewrites history without un-recording a
## fact. Values are MEASURED from the SSOT (`TimeLadder.ratio_for`, `RowBudget.MAX_ROWS`,
## `EVENT_BUDGET`) rather than typed in, so a playtest retune moves the expected numbers
## with it and the case still measures the property rather than a pinned numeral.

const MORTAL_PLAINS := &"mortal_plains"
const SPIRIT_PEAKS := &"spirit_peaks"
const LOWER_REALM := &"lower_realm"
const REBUILT_REALM := &"rebuilt_realm"

## A world fact recorded per epoch, so the epoch cases can name distinct occurrences
## rather than reusing one id and reading the ledger's total as if it were per-epoch.
const TEMPLE := "founded_temple"
const TEMPLE_DOWN := "temple_destroyed"

const STAMP_SRC := "res://src/core/reconcile_stamp.gd"
const EPOCH_SRC := "res://src/core/world_epoch.gd"
const RECONCILE_SRC := "res://src/core/world_reconcile.gd"


## A fresh stamp set. Built per case rather than shared, because the stamp is DERIVED and
## discardable — a suite that mutated one shared set would be testing an aliasing bug.
func _empty_stamps() -> Dictionary:
	return ReconcileStamp.empty()


func _hero() -> Actor:
	return Actor.new(&"hero")


## A span that crosses at least the authored month and day rows, so more than one bucket
## does work in the per-magnitude cases.
func _month_span() -> int:
	return TimeLadder.ratio_for(&"month")


# --- 1. THE DEADLOCK GUARD — the most important case in this file ----------------


## ## THE HAZARD, PROVEN ABSENT (ADR 0173 (c))
##
## "an observation-driven clock DEADLOCKS if every advance source is itself gated on
## someone being present. The world freezes forever, every elapsed calculation returns
## zero, and the failure is silent — nothing errors, everything is simply always zero."
##
## A never-visited place has no stamp row, so `ReconcileStamp.folded` answers `0` — and a
## reconcile written as `if visited: fold()` therefore folds NOTHING and reports a clean
## `ok: true`. The world freezes with no error anywhere. **This case is the only thing in
## the file that would catch that**, and it is why the first observation of a place must
## be a FULL fold rather than a skipped one.
func test_a_never_visited_place_still_reports_non_zero_elapsed() -> void:
	var stamps := _empty_stamps()
	assert_eq(ReconcileStamp.place_count(stamps), 0, "nothing has ever been stamped")
	assert_eq(ReconcileStamp.knows_place(stamps, MORTAL_PLAINS), false, "the place is unvisited")
	var span := _month_span()
	var seen := WorldReconcile.observe(stamps, MORTAL_PLAINS, span)
	assert_eq(seen["stamped_before"], false, "and the observation knows it was the first")
	assert_eq(
		int(seen["elapsed_periods"]),
		span,
		"a never-visited place elapsed the WHOLE span, not zero (the deadlock guard)"
	)
	assert_eq(
		int(seen["elapsed_periods"]) > 0, true, "non-zero, stated so the point survives an edit"
	)
	assert_eq(bool(seen["advanced"]), true, "and the first observation advanced the place")
	assert_eq(
		ReconcileStamp.place_count(seen["stamps"]),
		1,
		"the first observation wrote a stamp, so a second one can be told from the first"
	)


## The same guard at the coarsest span the clock represents, because a conversion that
## only ever agreed below the year is a per-period loop wearing a reconciliation's name.
## A 10^9-year span must also fold on the FIRST observation.
func test_the_first_observation_of_an_unvisited_place_folds_a_billion_year_span() -> void:
	var span := 1_000_000_000 * TimeLadder.ratio_for(&"year")
	var seen := WorldReconcile.observe(_empty_stamps(), SPIRIT_PEAKS, span)
	assert_eq(
		int(seen["elapsed_periods"]), span, "the whole billion-year span elapsed on first read"
	)
	assert_eq(
		int(ReconcileStamp.folded(seen["stamps"], SPIRIT_PEAKS, &"era")),
		span / TimeLadder.ratio_for(&"era"),
		"and the coarsest magnitude folded a whole bucket on the first read too"
	)


## **Repeated observations of an unvisited-in-the-stamp sense place never zero out.**
## The freeze hazard is silent precisely because every later read looks like a successful
## read; this pins the sequence a session actually produces — look, look again, look after
## a span — and requires each answer to be about the span that was handed down.
func test_repeated_observations_never_silently_read_zero() -> void:
	var stamps := _empty_stamps()
	var first := WorldReconcile.observe(stamps, SPIRIT_PEAKS, 1)
	assert_eq(int(first["elapsed_periods"]), 1, "the first look is the whole span")
	stamps = first["stamps"]
	var second := WorldReconcile.observe(stamps, SPIRIT_PEAKS, 1)
	assert_eq(int(second["elapsed_periods"]), 0, "the second look of the same span folded nothing")
	# A further, DIFFERENT span is what a session actually does next, and it must be
	# non-zero: a place that froze would read zero here too.
	var third := WorldReconcile.observe(second["stamps"], SPIRIT_PEAKS, 1)
	assert_eq(
		int(third["elapsed_periods"]), 1, "and a later span is still read, not zeroed forever"
	)


# --- 2. Stamps are per-place AND per-magnitude ---------------------------------


## One place advancing moves NOBODY ELSE. A stamp keyed by magnitude alone would make a
## visit to the mortal plains appear to have aged the spirit peaks, which is the
## "every reader must decide whether it is fresh" defect a shared row would introduce.
func test_one_place_advancing_does_not_move_another() -> void:
	var span := _month_span()
	var seen := WorldReconcile.observe(_empty_stamps(), MORTAL_PLAINS, span)
	var stamps: Dictionary = seen["stamps"]
	assert_eq(ReconcileStamp.place_count(stamps), 1, "only the observed place is stamped")
	assert_eq(
		ReconcileStamp.folded(stamps, MORTAL_PLAINS, &"month"),
		1,
		"the observed place folded a month"
	)
	assert_eq(
		ReconcileStamp.folded(stamps, SPIRIT_PEAKS, &"month"),
		0,
		"and the place nobody looked at folded nothing"
	)
	assert_eq(ReconcileStamp.folded_periods(stamps, SPIRIT_PEAKS), 0, "its whole span is zero")


## One place advancing moves no OTHER MAGNITUDE of the same place either, and the two
## counters are independent: a month-fold does not claim a day-fold, so a reader asking
## about days is not handed the month the place crossed a day inside.
func test_a_stamp_is_per_magnitude_as_well_as_per_place() -> void:
	var day := TimeLadder.ratio_for(&"day")
	var month := TimeLadder.ratio_for(&"month")
	var stamps: Dictionary = WorldReconcile.observe(_empty_stamps(), MORTAL_PLAINS, month)["stamps"]
	var crossed := TimeLadder.magnitudes_crossed(month)
	assert_eq(ReconcileStamp.folded(stamps, MORTAL_PLAINS, &"month"), 1, "one month folded")
	assert_eq(
		ReconcileStamp.folded(stamps, MORTAL_PLAINS, &"day"),
		int(crossed.get(&"day", 0)),
		"and the day count is the ladder's own, measured rather than typed"
	)
	assert_eq(
		ReconcileStamp.folded(stamps, MORTAL_PLAINS, &"day") != 1,
		true,
		"a day counter that happened to equal the month counter would prove nothing here"
	)
	# Raising one magnitude alone leaves the other exactly where it was. `folded_periods`
	# is the BASE row — its authored ratio is one period — so it is UNAFFECTED by raising
	# a coarse row, which is precisely why the date read is not a sum of the buckets
	# (a month + a year would then read 4,740 periods, a date nobody lived through).
	var raised: Dictionary = ReconcileStamp.fold(stamps, MORTAL_PLAINS, &"year", 3)
	assert_eq(ReconcileStamp.folded(raised, MORTAL_PLAINS, &"year"), 3, "the year was raised")
	assert_eq(
		ReconcileStamp.folded(raised, MORTAL_PLAINS, &"month"),
		1,
		"and raising one magnitude moved no other"
	)
	assert_eq(
		ReconcileStamp.folded_periods(raised, MORTAL_PLAINS),
		month,
		"the date read is the base fold, unchanged by a coarse row it never summed"
	)
	assert_eq(
		int(ReconcileStamp.folds_for(raised, MORTAL_PLAINS).get(&"year", 0)) >= 1,
		true,
		"while the coarse fold itself is there for the next pass to read"
	)


## A place folded at month 1, then handed a span of DAYS, crosses no month and pays no
## second month. This is the "a place returning to scope is FOLDED, never replayed" rule
## (ADR 0170) and the reason the stamp stores a fold count rather than a period watermark.
func test_a_re_observed_place_does_not_pay_a_second_bucket() -> void:
	var month := TimeLadder.ratio_for(&"month")
	var day := TimeLadder.ratio_for(&"day")
	var stamps: Dictionary = WorldReconcile.observe(_empty_stamps(), MORTAL_PLAINS, month)["stamps"]
	var again := WorldReconcile.observe(stamps, MORTAL_PLAINS, month)
	assert_eq(int(again["crossed"].get(&"month", -1)), 0, "the same span crosses no second month")
	assert_eq(
		ReconcileStamp.folded(again["stamps"], MORTAL_PLAINS, &"month"),
		1,
		"and the month fold is still one, not two"
	)
	assert_eq(int(again["elapsed_periods"]), 0, "a re-observation of a folded span is a no-op")
	var later := WorldReconcile.observe(again["stamps"], MORTAL_PLAINS, day)
	assert_eq(int(later["elapsed_periods"]), day, "and a genuinely new span still elapses in full")


# --- 3. The epoch never lowers a fact count -------------------------------------


## ## HISTORY REWRITES; THE LEDGER DOES NOT
##
## "founded_temple@1, temple_destroyed@1, founded_temple@2 are three true things, not one
## thing recorded, erased, and recorded again" (ADR 0170). So the ledger's count RISES
## through the epoch advance and every occurrence stays readable, while the DERIVED state
## the reader sees is rewritten.
func test_the_epoch_never_lowers_a_fact_count() -> void:
	var hero := _hero()
	var epoch_set := WorldEpoch.empty()
	assert_eq(
		WorldEpoch.current(epoch_set, LOWER_REALM),
		WorldEpoch.FIRST,
		"a world starts at its first epoch"
	)

	# Epoch 1: the temple is founded, then destroyed. Both are true and both stay true.
	WorldFact.record(hero, &"founded_temple", 1)
	var before_rebuild := WorldFact.count(hero, &"founded_temple")
	WorldFact.record(hero, &"temple_destroyed", 1)
	var destroyed_count := WorldFact.count(hero, &"temple_destroyed")

	# The world is rebuilt: the old one is RETIRED and a successor carries the next epoch.
	epoch_set = WorldEpoch.successor(epoch_set, LOWER_REALM, REBUILT_REALM)
	assert_eq(
		WorldEpoch.is_retired(epoch_set, LOWER_REALM),
		true,
		"the old world was retired, not deleted"
	)
	assert_eq(
		WorldEpoch.current(epoch_set, REBUILT_REALM),
		WorldEpoch.FIRST + 1,
		"the successor carries the next epoch"
	)
	assert_eq(
		WorldEpoch.current(epoch_set, LOWER_REALM),
		WorldEpoch.FIRST,
		"and the retired world keeps the epoch it lived"
	)

	# The new world's history: the temple founded again.
	WorldFact.record(hero, &"founded_temple", 1)
	var after_rebuild := WorldFact.count(hero, &"founded_temple")

	# THE ASSERTION: the ledger only ever ROSE, across the epoch advance.
	assert_eq(
		after_rebuild > before_rebuild,
		true,
		"the founded count rose through the rebuild (%d -> %d)" % [before_rebuild, after_rebuild]
	)
	assert_eq(
		WorldFact.count(hero, &"temple_destroyed"),
		destroyed_count,
		"and the destruction is still recorded"
	)
	assert_eq(WorldFact.has(hero, &"founded_temple"), true, "every occurrence is still readable")
	assert_eq(
		WorldFact.has(hero, &"temple_destroyed"),
		true,
		"including the one that history no longer applies"
	)
	assert_eq(
		WorldFact.fact(hero, &"founded_temple").since,
		1,
		"and `since` never moved, because the first record really was the first"
	)


## ## THE DERIVED STATE IS WHAT THE EPOCH REWRITES, AND THE LEDGER IS ONE MONOTONE ROW
##
## The ADR's own witness: "`founded_temple@1`, `temple_destroyed@1`, `founded_temple@2`
## are three true things, not one thing recorded, erased, and recorded again." So an
## occurrence's epoch is the EPOCH THAT HAPPENED IN, and the rule a reader resolves
## against is therefore cumulative: **an occurrence applies when the reader's epoch is at
## least the occurrence's epoch.** A row stamped 2 is not "not yet" at epoch 2 — it is one
## more true thing, and the overlay's job is to stop a reader COUNTING a row twice, not to
## hide it.
##
## Which is what makes the derived count differ from the ledger's total with neither number
## wrong: the ledger says a temple was founded twice (true), and the retired world says it
## held one (true of the history it actually lived).
func test_the_derived_state_is_rewritten_while_the_ledger_is_one_monotone_row() -> void:
	var epochs: Dictionary = WorldEpoch.successor(WorldEpoch.empty(), LOWER_REALM, REBUILT_REALM)
	var occurrences := [
		{"id": TEMPLE, "epoch": 1, "amount": 1},
		{"id": TEMPLE_DOWN, "epoch": 1, "amount": 1},
		{"id": TEMPLE, "epoch": 2, "amount": 1},
	]
	var retired_world := WorldEpoch.state_of(epochs, LOWER_REALM, occurrences)
	assert_eq(int(retired_world["epoch"]), 1, "the retired world resolves at the epoch it lived")
	assert_eq(int(retired_world["counts"].get(TEMPLE, 0)), 1, "and sees the one temple it had")
	assert_eq(int(retired_world["counts"].get(TEMPLE_DOWN, 0)), 1, "including its destruction")
	assert_eq(
		int(retired_world["counts"].get(TEMPLE, 0)) < 2,
		true,
		"the epoch-2 founding is not re-applied to a world that ended before it"
	)
	assert_eq(
		retired_world["deferred"],
		["founded_temple"],
		"and it is NAMED as not-taken, so a reader can tell it from a row that never existed"
	)

	var successor := WorldEpoch.state_of(epochs, REBUILT_REALM, occurrences)
	assert_eq(int(successor["epoch"]), 2, "the successor resolves at the next epoch")
	assert_eq(
		int(successor["counts"].get(TEMPLE, 0)),
		2,
		"the successor counts BOTH founders: they are two true things, not one rewritten"
	)
	assert_eq(
		(successor["applied_epochs"] as Array).has(1),
		true,
		"and it reports which epochs its applied rows came from"
	)
	assert_eq(
		(successor["applied"] as Array).has(TEMPLE_DOWN),
		true,
		"the destruction carries forward — it happened to this world too"
	)
	assert_eq(successor["deferred"].size(), 0, "and nothing is deferred at the newest epoch")


## A retired world's occurrences REMAIN RECORDED while a successor reads CLEAN — the
## property that lets a save written in epoch 1 still read correctly after a rebuild.
## The two worlds' histories do not overlap, so the successor's own founding is the only
## temple it reads, and the retired world's own end is still on the ledger either way.
func test_a_retired_worlds_occurrences_remain_recorded_while_a_successor_reads_clean() -> void:
	var hero := _hero()
	var epochs := WorldEpoch.empty()
	# Two distinct worlds' histories, both recorded on the one monotone ledger.
	WorldFact.record(hero, &"lower_realm_founded", 1)
	WorldFact.record(hero, &"lower_realm_destroyed", 1)
	epochs = WorldEpoch.successor(epochs, LOWER_REALM, REBUILT_REALM)
	WorldFact.record(hero, &"rebuilt_realm_founded", 1)

	var occurrences := [
		{"id": "lower_realm_founded", "epoch": 1, "amount": 1},
		{"id": "lower_realm_destroyed", "epoch": 2, "amount": 1},
		{"id": "rebuilt_realm_founded", "epoch": 2, "amount": 1},
	]
	var successor := WorldEpoch.state_of(epochs, REBUILT_REALM, occurrences)
	assert_eq(bool(successor["retired"]), false, "the successor is not retired")
	assert_eq(
		int(successor["counts"].get("rebuilt_realm_founded", 0)),
		1,
		"the successor reads clean: its own founding is what applies"
	)
	assert_eq(
		int(successor["counts"].get("lower_realm_founded", 0)),
		1,
		"and the predecessor's founding is one of its own true things, not a second temple"
	)
	assert_eq(
		int(successor["counts"].get("lower_realm_destroyed", 0)),
		1,
		"the destruction happened to this world too, so it carries forward rather than vanishing"
	)
	# THE MONOTONE HALF, asserted on the ledger itself rather than on the overlay.
	assert_eq(
		WorldFact.count(hero, &"lower_realm_founded"),
		1,
		"the retired world's founding is still recorded"
	)
	assert_eq(WorldFact.count(hero, &"lower_realm_destroyed"), 1, "its destruction too")
	assert_eq(WorldFact.count(hero, &"rebuilt_realm_founded"), 1, "and the successor's")
	assert_eq(
		WorldFact.count(hero, &"lower_realm_destroyed") > 0,
		true,
		"nothing was un-recorded by the rebuild"
	)


## No verb in either file can LOWER a count — read from source, for the reason
## `test_realm_rate.gd:208-224` gives: a numerically identical private copy stays green
## under every value assertion, so the shape has to be checked where the defect is.
##
## The census is exact. `reconcile_stamp.gd` has one refusal (a non-numeric or foreign
## payload) and NO truncation word; `world_epoch.gd` has none at all, because its only
## unfillable input routes through `TimeLadder.exceeds_budget`, which pushes its own.
func test_neither_the_stamp_nor_the_epoch_declares_a_decrement_verb() -> void:
	var stamp_code := _code_only(FileAccess.get_file_as_string(STAMP_SRC))
	var epoch_code := _code_only(FileAccess.get_file_as_string(EPOCH_SRC))
	assert_ne(stamp_code, "", "the stamp source is readable")
	assert_ne(epoch_code, "", "the epoch source is readable")
	for code in [stamp_code, epoch_code]:
		assert_eq(code.contains("-="), false, "nothing here subtracts from a count")
		assert_eq(code.contains("truncate"), false, "nothing here truncates to fit a cap")
		assert_eq(code.contains(".slice("), false, "and no span is cut down to a shorter one")
	# The ONE overflow refusal is the reconcile pass's, and it names the count and the cap.
	var pass_code := _code_only(FileAccess.get_file_as_string(RECONCILE_SRC))
	assert_eq(pass_code.count("push_error("), 1, "exactly one loud refusal: the over-cap pass")
	assert_eq(
		pass_code.contains("% [asked, MAX_PLACES]"), true, "and it names the count and the cap"
	)


# --- 4. Overflow refuses loudly rather than truncating --------------------------


## A pass over more places than the cap holds returns REFUSED, writes NO stamp, and
## names the count. The message is asserted from SOURCE rather than by driving the
## refusing branch, for the reason `test_time_ladder.gd:386-401` gives: `TestCase`
## shadows `push_error` and latches it (`tests/framework.gd:196-200`), so a case that
## drove the refusal would go red for being correct.
##
## What IS asserted behaviourally is the part that matters most: a refused pass leaves
## the stamp set byte-for-byte as it found it, so no place is half-folded.
func test_overflow_refuses_rather_than_truncating() -> void:
	var stamps := _empty_stamps()
	# `asked` is measured, not typed: the property is "one over the cap", and pinning the
	# numeral would break the moment the cap moves for a legitimate reason.
	var places: Array[StringName] = []
	for index in WorldReconcile.MAX_PLACES + 1:
		places.append(StringName("place_%d" % index))
	assert_eq(
		places.size() > WorldReconcile.MAX_PLACES, true, "the worklist really is over the cap"
	)
	var refused := WorldReconcile.reconcile(stamps, places, _month_span())
	assert_eq(bool(refused["ok"]), false, "an over-cap pass is refused, not truncated")
	assert_eq(String(refused["reason"]), WorldReconcile.REASON_OVERFLOW, "and it says why, by name")
	assert_eq(int(refused["places_folded"]), 0, "not one place was folded")
	assert_eq(
		int(refused["places_asked"]),
		WorldReconcile.MAX_PLACES + 1,
		"the count it refused is reported"
	)
	assert_eq(ReconcileStamp.place_count(refused["stamps"]), 0, "and the stamp set is untouched")
	# The refusal names the numbers, read from source so no test drives the push.
	var code := _code_only(FileAccess.get_file_as_string(RECONCILE_SRC))
	assert_eq(
		code.contains("% [asked, MAX_PLACES]"), true, "the message names the count and the cap"
	)
	assert_eq(code.contains("No stamp was written"), true, "and says the pass wrote nothing")


## At the cap the pass succeeds, and folds every place asked about. A cap that refused
## at the boundary would be a different constant wearing the same name, and a pass that
## succeeded above it would be the truncation this ADR refuses.
func test_a_pass_at_the_cap_succeeds_and_folds_every_place() -> void:
	var places: Array[StringName] = []
	for index in WorldReconcile.MAX_PLACES:
		places.append(StringName("place_%d" % index))
	var done := WorldReconcile.reconcile(_empty_stamps(), places, _month_span())
	assert_eq(bool(done["ok"]), true, "a pass at exactly the cap succeeds")
	assert_eq(int(done["places_folded"]), WorldReconcile.MAX_PLACES, "every place folded")
	assert_eq(
		ReconcileStamp.place_count(done["stamps"]),
		WorldReconcile.MAX_PLACES,
		"and every one carries a stamp"
	)
	assert_eq(
		ReconcileStamp.folded(done["stamps"], places[0], &"month"),
		1,
		"each folded the month it crossed"
	)


## A span of nothing is refused rather than reported as a pass that folded nothing: an
## `ok: true` with zero places folded is exactly the shape a reader mistakes for "the
## world did not move" when the real cause is that nobody handed a span down.
func test_a_pass_with_no_span_is_refused_by_name() -> void:
	var refused := WorldReconcile.reconcile(_empty_stamps(), [MORTAL_PLAINS], 0)
	assert_eq(bool(refused["ok"]), false, "a zero span is not a pass")
	assert_eq(String(refused["reason"]), WorldReconcile.REASON_NO_SPAN, "and it names the reason")
	assert_eq(ReconcileStamp.place_count(refused["stamps"]), 0, "nothing was written")


# --- 5. Discarding a stamp is safe: the next reconcile is a FULL PASS ------------


## ## THE WHOLE ARGUMENT FOR THE FILE
##
## "Delete the stamp and the next reconcile is simply a full pass. A ledger that can be
## wrong forever is a hazard; a stamp that is wrong only until the next reconcile is a
## cache" (ADR 0170).
##
## Discarding a stamp after a fold must therefore produce EXACTLY what a first
## observation produces, and must cost nothing but the fold itself. Every key of the two
## reports is compared, because a partial equality would pass while the crossed map or
## the span answer drifted.
func test_discarding_a_stamp_makes_the_next_reconcile_equal_a_full_pass() -> void:
	var span := _month_span()
	var folded_first := WorldReconcile.observe(_empty_stamps(), MORTAL_PLAINS, span)
	# Forget the place outright — the payload is discarded, not zeroed.
	var discarded: Dictionary = ReconcileStamp.forget(folded_first["stamps"], MORTAL_PLAINS)
	assert_eq(ReconcileStamp.place_count(discarded), 0, "the stamp set is empty again")
	assert_eq(
		ReconcileStamp.knows_place(discarded, MORTAL_PLAINS), false, "the place is unvisited again"
	)

	var fresh := WorldReconcile.observe(_empty_stamps(), MORTAL_PLAINS, span)
	var again := WorldReconcile.observe(discarded, MORTAL_PLAINS, span)
	for key in ["location_id", "span_periods", "stamped_before", "elapsed_periods", "advanced"]:
		assert_eq(again[key], fresh[key], "a discarded stamp reads as a full pass: %s" % key)
	assert_eq(again["crossed"], fresh["crossed"], "and it crosses the same magnitudes")
	assert_eq(
		ReconcileStamp.folds_for(again["stamps"], MORTAL_PLAINS),
		ReconcileStamp.folds_for(fresh["stamps"], MORTAL_PLAINS),
		"and the rebuilt stamp is identical, not merely equivalent"
	)


## Discarding one place's stamp moves NO other place, so the cache is discardable
## per-place and not merely as a whole set.
func test_discarding_one_places_stamp_moves_no_other() -> void:
	var span := _month_span()
	var both := WorldReconcile.reconcile(_empty_stamps(), [MORTAL_PLAINS, SPIRIT_PEAKS], span)
	assert_eq(ReconcileStamp.place_count(both["stamps"]), 2, "both places folded")
	var one_gone: Dictionary = ReconcileStamp.forget(both["stamps"], MORTAL_PLAINS)
	assert_eq(ReconcileStamp.place_count(one_gone), 1, "one place is gone")
	assert_eq(
		ReconcileStamp.folded(one_gone, SPIRIT_PEAKS, &"month"),
		1,
		"and the other still holds exactly what it folded"
	)
	var rediscovered := WorldReconcile.observe(one_gone, MORTAL_PLAINS, span)
	assert_eq(
		int(rediscovered["elapsed_periods"]), span, "the discarded place reads as a full pass again"
	)


## A stamp is derived and therefore REPAIRED, not trusted: a corrupt or foreign payload
## is diagnosed rather than partially applied, because half a stamp table is worse than
## none — it would leave places silently stale with nothing reporting it.
func test_a_corrupt_stamp_payload_is_repaired_rather_than_partially_applied() -> void:
	var foreign := {
		"stamps": {"mortal_plains": "not a table", "": {"month": 1}, "ok": {"month": -5}}
	}
	var repaired: Dictionary = ReconcileStamp.normalize(foreign)
	# The row that is not a table and the row that names nothing are DROPPED outright.
	assert_eq(
		(repaired["stamps"] as Dictionary).has("mortal_plains"),
		false,
		"an unreadable row is dropped"
	)
	assert_eq((repaired["stamps"] as Dictionary).has(""), false, "an unnamed row is dropped")
	# The readable row survives with its count CLAMPED, not with the negative stored — a
	# negative fold would make the next span compute as a longer one ("silently stale").
	assert_eq(
		int((repaired["stamps"] as Dictionary).get("ok", {}).get("month", -1)),
		0,
		"a negative fold is clamped on the way in"
	)
	assert_eq(
		ReconcileStamp.normalize("not a payload"),
		ReconcileStamp.empty(),
		"and a non-dictionary is empty"
	)
	assert_eq(
		ReconcileStamp.place_count(ReconcileStamp.empty()), 0, "the empty set is a valid answer"
	)
	# And the same clamp on the write path.
	var clamped: Dictionary = ReconcileStamp.fold(
		ReconcileStamp.empty(), MORTAL_PLAINS, &"month", -9
	)
	assert_eq(
		ReconcileStamp.folded(clamped, MORTAL_PLAINS, &"month"),
		0,
		"a negative fold reads as zero folds"
	)
	# A place folded AT ZERO still reads as VISITED, which is what stops the next reconcile
	# treating a short span as a never-seen place and re-folding the world.
	assert_eq(
		ReconcileStamp.knows_place(clamped, MORTAL_PLAINS), true, "zero folds is still a visit"
	)
	# And the answer is a COPY: a caller editing it edits no stamp, so `fold` is the only
	# way in — which is what makes "raises only" a property rather than a convention.
	var answer: Dictionary = ReconcileStamp.folds_for(clamped, MORTAL_PLAINS)
	answer[&"month"] = 99
	assert_eq(
		ReconcileStamp.folded(clamped, MORTAL_PLAINS, &"month"),
		0,
		"the answer is a copy, not a view"
	)


## `summary()` is primitives only, so `tools ui drive` can print a world's date with no
## display. Asserted on the TYPE of every leaf rather than on a pin, because a
## `StringName` in a read model is what a UI panel trips over (`WorldSpawnState._text`
## documents the same trap).
func test_the_summary_is_primitives_only() -> void:
	var stamps: Dictionary = (
		WorldReconcile
		. reconcile(_empty_stamps(), [MORTAL_PLAINS, SPIRIT_PEAKS], _month_span())["stamps"]
	)
	var epochs: Dictionary = WorldEpoch.successor(WorldEpoch.empty(), LOWER_REALM, REBUILT_REALM)
	var shape := WorldReconcile.summary(stamps, epochs)
	assert_eq(_has_non_primitive(shape), false, "every leaf of the summary is a primitive")
	assert_eq(int(shape["places"]), 2, "the summary names how many places carry a stamp")
	assert_eq(int(shape["cap"]), WorldReconcile.MAX_PLACES, "and the cap a pass folds against")
	assert_eq(
		int(shape["event_budget"]), TimeLadder.EVENT_BUDGET, "and the budget an advance spends"
	)
	assert_eq(
		int(shape["epoch"]["current"][0]) >= WorldEpoch.FIRST,
		true,
		"the epoch summary is nested, not dropped"
	)
	# A date a headless drive can print with no display at all.
	assert_eq(
		int(shape["total_periods_folded"]) > 0,
		true,
		"the summary carries a date, which is the whole reason it exists"
	)


## The pass folds O(1) per place: `buckets` is the authored magnitude count times the
## places asked about, and is the SAME for one period and for 10^9 years. This is the
## cost claim ADR 0170 makes, asserted as a work count rather than as an answer.
func test_the_work_a_pass_does_is_independent_of_the_span() -> void:
	var one_period := WorldReconcile.reconcile(_empty_stamps(), [MORTAL_PLAINS], 1)
	var billion_years := WorldReconcile.reconcile(
		_empty_stamps(), [MORTAL_PLAINS], 1_000_000_000 * TimeLadder.ratio_for(&"year")
	)
	assert_eq(
		int(billion_years["buckets"]),
		int(one_period["buckets"]),
		"a billion-year pass costs the same buckets"
	)
	assert_eq(
		int(one_period["buckets"]),
		maxi(WorldReconcile.MIN_BUCKETS, TimeLadder.magnitudes().size()),
		"one bucket per authored magnitude per place"
	)
	assert_eq(
		int(billion_years["buckets"]) < 1_000_000_000,
		true,
		"and nothing about it is proportional to the span, which is the claim 0168 could not make"
	)


## The shipped scope identity is `WorldLocationDef.location_id`, read through
## `ContentScan` rather than a local walk. Four locations ship today, one per world tier
## (ADR 0170), and the set is what a caller reconciles against rather than a hand-list.
func test_the_shipped_locations_are_the_authored_location_ids() -> void:
	var authored := WorldReconcile.shipped_locations()
	assert_eq(authored.is_empty(), false, "the authored world ships locations")
	for location_id in authored:
		assert_eq(location_id != &"", true, "an authored location names itself")
	assert_eq(
		authored.size() >= 4,
		true,
		"and there is at least one per world tier (%d)" % authored.size()
	)
	# The scan is the repo's, so its depth cap is the cap this rule can see
	# (`core/content_scan.gd:22`), and a `.tres` that is not a location is skipped rather
	# than refused — a broken content row is a content gap.
	assert_eq(
		WorldReconcile.shipped_locations("res://data/world/locations/nope").size(),
		0,
		"a root that does not exist yields nothing"
	)


## Every source file here is a `core/` layer member, so none of them adds an arch edge
## (`tools/arch/rules.py:29`). Read from source because `BARE_REF_UNITS` excludes `core/`
## and `tools arch` cannot see a bare reference out of this layer — the file that
## documents that limitation is `rules.py:51-59`.
func test_the_three_files_add_no_arch_edge_out_of_core() -> void:
	for path in [STAMP_SRC, EPOCH_SRC, RECONCILE_SRC]:
		var code := _code_only(FileAccess.get_file_as_string(path))
		assert_ne(code, "", "%s is readable" % path)
		assert_eq(code.contains("res://src/modules/"), false, "%s names no module" % path)
		assert_eq(code.contains("res://src/app/"), false, "%s names no composition root" % path)
		assert_eq(code.contains("get_tree()"), false, "%s reads no scene tree (ADR 0089)" % path)
		assert_eq(
			code.contains("Time.get_ticks"), false, "%s reads no wall clock (DEF-0111)" % path
		)
		assert_eq(code.contains("while "), false, "%s has no `while` for the guard to judge" % path)


## Whether `state_of` holds up against a hand-built row the caller did not author here.
## A `WorldBeat` is accepted because it is the repo's own claim object (ADR 0114) and a
## caller reaching for it must not have to build a dictionary instead — `WorldBeat.coerce`
## documents that exact duplication for the same reason.
func test_a_beat_is_readable_as_an_occurrence_and_a_malformed_row_is_not() -> void:
	var epochs: Dictionary = WorldEpoch.advance_to(WorldEpoch.empty(), LOWER_REALM, 2)
	var beat := WorldBeat.make(&"founded_temple@1", &"founded_temple", 1, "test")
	var from_beat := WorldEpoch.state_of(epochs, LOWER_REALM, [beat])
	assert_eq(
		int(from_beat["counts"].get("founded_temple", 0)),
		1,
		"a beat at the default epoch applies to a world past it"
	)
	var junk := WorldEpoch.state_of(epochs, LOWER_REALM, ["not a row", {}, {"id": "", "epoch": 1}])
	assert_eq((junk["applied"] as Array).size(), 0, "a row naming nothing is dropped, not stored")


## `_code_only`, borrowed in the shape `test_time_ladder_single_source.gd:869` documents:
## whole-line comments, trailing comments and `"""` blocks are removed before a scan, so
## a guard reading these files cannot fire on their own prose — which is what the source
## assertions above above depend on.
func _code_only(source: String) -> String:
	var kept: Array[String] = []
	for raw in source.split("\n"):
		var line := String(raw)
		if line.strip_edges().begins_with("#"):
			continue
		kept.append(line.substr(0, maxi(0, line.find("#"))))
	return "\n".join(kept)


## Whether any leaf of `payload` is a `StringName`, an `Array` of them, or anything else
## that is not a primitive — recursively, over the fixed shape `summary()` publishes.
##
## ## Why one return and not one per branch
##
## The `match` below assigns its verdict and the walk reads it once at the end. Every
## branch answers exactly what it answered as a `return`, and the depth cap is still a
## hard stop: a payload nested past `depth > 6` is refused as non-primitive rather than
## being walked, which is the bound that keeps a self-referential structure from
## recursing forever. The container arms keep the same short-circuit too — they break on
## the FIRST offending leaf and answer `true`, rather than collecting every offender.
func _has_non_primitive(value, depth: int = 0) -> bool:
	var offender := false
	if depth > 6:
		offender = true
	else:
		match typeof(value):
			TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
				offender = false
			TYPE_STRING_NAME:
				offender = true
			TYPE_ARRAY:
				offender = false
				for entry in value as Array:
					if _has_non_primitive(entry, depth + 1):
						offender = true
						break
			TYPE_DICTIONARY:
				offender = false
				for entry in (value as Dictionary).values():
					if _has_non_primitive(entry, depth + 1):
						offender = true
						break
			_:
				offender = true
	return offender
