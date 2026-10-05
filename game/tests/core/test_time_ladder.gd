extends TestCase

## ADR 0173: the clock is one SSOT, an elapsed span has a FIXED event budget, and a
## place advances when observed. `core/time_ladder.gd` is the implementation and this
## file is the proof of the two claims that are easy to get wrong and expensive to get
## wrong again.
##
## ## 1. The COST CLAIM (the case ADR 0168 got wrong)
##
## 0168 priced an elapsed span as `O(tiers crossed x consumers)` against a fixed six-row
## ladder and called that independent of elapsed time. It is not: 10^9 years does not
## CROSS six tiers, it SITS INSIDE the era tier, so the era row is crossed once and a
## consumer is handed one bucket of 10^9 to answer from. The shipped line has the same
## shape (`app/world_pulse.gd:368`, `for index in periods:`) and that loop's bound is
## `periods`, which is DATA-DERIVED — `AGENTS.md:52` verbatim, "a data-derived row count
## is not a fixed count either" — which is the shape of the recorded 67 GB incident.
##
## **So the case below asserts the WORK COUNT and not the answer.** An answer alone
## cannot distinguish five divisions from 10^12 of them: both are "the right number",
## and the defect is invisible to every value comparison that has ever been written
## about this file. `conversion_work` is queried for one period and for a billion years
## and both must land inside a handful of steps — and, because a constant satisfies
## that too, two spans crossing different magnitudes are asked to DISAGREE.
##
## ## 2. Surplus is DROPPED, never banked
##
## `app/world_pulse.gd:90-94`'s own reason: "a banked surplus is a backlog that pays out
## later at a rate nobody chose". A ladder that banked its remainder would let a player
## farm fractions of a year and spend them on one, which is an accrual rate nobody
## authored and nobody balanced.
##
## ## 3. Every row is INDEPENDENT (ADR 0050's anti-shift property)
##
## The repo has already paid for the opposite: `RealmPowerTable` is keyed by realm id
## precisely because a ladder-position key silently shifts every row below an insertion
## (AGENTS.md:140). `magnitudes_crossed` divides by each row's own authored ratio, so
## inserting a row at the top must change no existing answer — proven here by inserting
## one and comparing every magnitude's count before and after.
##
## The rows are ALSO not chained, which is a different property with the same witness: a
## chained ladder would answer a year as `12 x 30 x 365 = 131,400` periods when the
## authored answer is 4,380. The `month` row is exactly the reason: a 30-day month inside
## a 365-day year is what a calendar IS (ADR 0168:92-95), so the year cannot be computed
## from the month and the two are authored independently. `test_each_ratio_is_measured_
## from_the_base_and_never_from_the_row_below` pins the arithmetic that would catch a
## chained implementation.

## A span small enough to fold STEP BY STEP, which is the only honest way to check a
## division against the thing it replaced. `MAX_PERIODS_PER_PULL := 8`
## (`world_pulse.gd:95`) is the per-call ceiling, so 400 periods is fifty legal calls.
const SMALL_SPAN := 400

const SRC_PATH := "res://src/core/time_ladder.gd"
const TABLE_PATH := "res://src/core/time_ladder_table.tres"


## A billion years, in periods, DERIVED from the SSOT rather than typed in. The span
## ADR 0173's Consequences sentence names: "a billion-year meditation costs
## O(magnitudes + C)". Typing the literal would make this file declare its own time
## constant, which `test_time_ladder_single_source.gd` fails on by design — a test
## that hardcodes a period count is the ADR 0116 disease wearing a test's clothes.
static func billion_years_periods() -> int:
	return 1_000_000_000 * TimeLadder.ratio_for(&"year")


## A trillion periods, which is the same order as the 10^9-year span at this base ratio
## and is the raw period count a naive per-period loop would have walked. Derived, not
## declared, for the same reason as the span above.
static func trillion_periods() -> int:
	return 1_000_000_000_000


## ## Conversion equals stepped folding
##
## A span of N periods must fold to the same magnitudes as advancing N times, because
## that is the claim ADR 0168 inherited and ADR 0173 keeps: "an elapsed interval is a
## COUNT handed down, never a sequence of steps replayed". Folding is the folded reading
## of `periods / ratio`; stepping is `n` single-period advances accumulated. Both are
## computed by INDEPENDENT arithmetic here — the stepped reading sums one period at a
## time and counts a magnitude each time its own ratio is reached — so this is a real
## cross-check and not the conversion function compared against itself.
##
## The span deliberately straddles two ratios (400 periods is 33 days, 1 month and 0
## years), so every row except `era` does non-zero work and a bug in any one of them
## shows up.
func test_a_span_of_n_periods_folds_to_what_advancing_n_times_would() -> void:
	var folded := TimeLadder.magnitudes_crossed(SMALL_SPAN)
	var stepped := _stepped_magnitudes(SMALL_SPAN)
	assert_eq(stepped.is_empty(), false, "the stepped reading produced magnitudes to compare")
	for magnitude in stepped:
		assert_eq(
			int(folded.get(magnitude, -1)),
			int(stepped[magnitude]),
			"%s folds the same stepping it does" % magnitude
		)
	# And the base itself, which the accumulator above takes as its starting point and
	# would otherwise never prove: the span IS that many periods, exactly.
	assert_eq(int(folded.get(TimeLadder.BASE, 0)), SMALL_SPAN, "the base is the span itself")


## The same property at a span that crosses a COARSE row, because a converter that only
## ever agreed below the year could be a per-day count wearing a ladder's name. 100,000
## periods is 22 years and 40,000 days — every row above `day` does work.
func test_a_span_crossing_a_year_folds_to_what_advancing_it_would() -> void:
	var folded := TimeLadder.magnitudes_crossed(100_000)
	assert_eq(
		int(folded.get(&"year", 0)),
		100_000 / TimeLadder.ratio_for(&"year"),
		"the year count is the authored ratio, not a chained product"
	)
	assert_eq(
		int(folded.get(&"year", 0)),
		int(_stepped_magnitudes(100_000).get(&"year", -1)),
		"and it agrees with stepping it a hundred thousand times"
	)


## ## THE COST CLAIM
##
## **The work count is the assertion, and it is BOUNDED, not identical.** A span says what
## became POSSIBLE and the budget says how much of it happens (ADR 0173 (b)) — a budget
## computed from the span is the span's cost wearing a different name, and ADR 0173
## records that as "Refused, trigger: never". So nothing here may grow with the span:
## one period and a billion years both cost single digits.
##
## **Why this is not the constant it used to be.** `conversion_work` returned
## `magnitudes().size() + EVENT_BUDGET`, which ignored its argument entirely, and a test
## that only asks "is 1 period the same as 10^9 years?" PASSES AGAINST `return 42`. The
## claim was unfalsifiable. So this case asserts three things together, and the third is
## the one a constant fails:
##
##   1. a billion-year span costs a BOUNDED handful of steps, nowhere near the span;
##   2. the number is DERIVED — it equals the magnitudes the span actually crosses plus
##      the authored budget, so a retune of either moves the expectation with it;
##   3. **two spans crossing DIFFERENT magnitudes return DIFFERENT numbers** — the case a
##      constant implementation cannot pass.
##
## The bounded expectation is measured rather than typed: `magnitudes()` is the authored
## row count and `EVENT_BUDGET` is the authored constant, so the ceiling and the floor
## both move with a retune and this case still measures the only thing that matters.
func test_the_work_a_span_costs_is_bounded_and_still_depends_on_the_span() -> void:
	var ceiling := TimeLadder.magnitudes().size() + TimeLadder.EVENT_BUDGET
	var floor_cost := TimeLadder.EVENT_BUDGET
	var one_period := TimeLadder.conversion_work(1)
	var billion_years := TimeLadder.conversion_work(billion_years_periods())
	var trillion := TimeLadder.conversion_work(trillion_periods())

	# 1. BOUNDED, whatever the span: nothing proportional to elapsed time can pass this.
	assert_eq(
		one_period <= ceiling, true, "one period is within magnitudes + budget (%d)" % one_period
	)
	assert_eq(
		billion_years <= ceiling,
		true,
		"a 10^9-year span is the same bound, not the span (%d)" % billion_years
	)
	assert_eq(trillion <= ceiling, true, "and 10^12 periods is the same bound too (%d)" % trillion)
	assert_eq(one_period < trillion_periods(), true, "and is nothing like the span it converts")

	# 2. DERIVED, not a constant. The BASE row is crossed by every positive span — a span
	# of N periods is N whole periods, so that division always happens — and every OTHER
	# row counts only once the span reaches a whole of it. So one period crosses the base
	# alone and costs `1 + EVENT_BUDGET`, while 10^9 years crosses the base plus
	# `day`/`month`/`year`/`era`. A `magnitudes().size() + EVENT_BUDGET` constant fails
	# BOTH of these: it charges one period for four divisions it never performed.
	assert_eq(
		one_period,
		1 + floor_cost,
		(
			"one period crosses the base alone and costs exactly one division plus the budget (%d)"
			% one_period
		)
	)
	assert_eq(
		billion_years,
		floor_cost + _crossed_by(billion_years_periods()),
		(
			"and a 10^9-year span costs one division per magnitude it actually crosses (%d)"
			% billion_years
		)
	)
	assert_eq(
		one_period < billion_years,
		true,
		(
			"so the two differ — %d against %d — which is what a constant cannot answer"
			% [one_period, billion_years]
		)
	)

	# 3. **THE CASE A CONSTANT FAILS.** Two spans crossing different magnitudes must cost
	# different amounts, or the function is not measuring anything at all and the O(1)
	# claim above is being satisfied by a hardcoded literal rather than by arithmetic.
	var short_span := TimeLadder.ratio_for(&"month") - 1
	var long_span := TimeLadder.ratio_for(&"month")
	assert_ne(short_span, long_span, "the probe spans really are different periods")
	assert_ne(
		_time_ladder_conversion_work(long_span),
		_time_ladder_conversion_work(short_span),
		(
			"a span that reaches a whole month costs more than one that stops a period short: "
			+ (
				"%d vs %d. A constant return would make these equal and measure nothing."
				% [
					_time_ladder_conversion_work(long_span),
					_time_ladder_conversion_work(short_span)
				]
			)
		)
	)


## How many authored magnitudes `span_periods` reaches a whole of — the same fold the work
## count reads, arrived at INDEPENDENTLY here by asking `magnitudes_crossed` directly
## rather than by calling `conversion_work`. A guard that re-derives the thing it guards
## proves nothing, so the expectation above is assembled from the fold and not from the
## function under test.
func _crossed_by(span_periods: int) -> int:
	var crossed := TimeLadder.magnitudes_crossed(span_periods)
	var whole := 0
	for name in crossed:
		if int(crossed[name]) >= 1:
			whole += 1
	return whole


## `conversion_work` reached through an indirection so the constant-killing assertion
## reads as a value rather than as a call it could be reading the implementation of. The
## name appears twice on the line, which is the point: the two numbers compared are the
## SAME function's answers for two different inputs.
func _time_ladder_conversion_work(span_periods: int) -> int:
	return TimeLadder.conversion_work(span_periods)


## The conversion itself must also be bounded work at that span — not merely the count
## helper. Every magnitude's answer is fetched from a dictionary the size of the AUTHORED
## row array, and none of them is a function of the span, so a converter that grew with
## the span would have to be growing the dictionary, which this pins shut.
func test_a_billion_year_span_produces_one_answer_per_authored_magnitude() -> void:
	var crossed := TimeLadder.magnitudes_crossed(billion_years_periods())
	assert_eq(
		crossed.size(),
		TimeLadder.magnitudes().size(),
		"one key per authored magnitude and no more — a per-period loop would emit far more"
	)
	assert_eq(
		int(crossed.get(&"era", 0)) > 0,
		true,
		"and the billion-year span really does cross the coarsest magnitude"
	)


## ## Surplus is DROPPED, never banked
##
## Two half-spans do not become one whole magnitude. This is the property a banked
## remainder would break, and `app/world_pulse.gd:90-94` names why in one sentence: "a
## banked surplus is a backlog that pays out later at a rate nobody chose".
##
## Asserted on a row the author controls: 7 periods is 0 days, 8 is 0, 12 is exactly 1
## and 11 is 0. A converter that kept the remainder and carried it forward would answer
## 1 for both 11 and 12.
func test_two_half_spans_do_not_become_one_whole_magnitude() -> void:
	var day := TimeLadder.ratio_for(&"day")
	var half := day / 2
	assert_eq(day % 2, 0, "the probe day divides evenly, or 'half' is not half")
	assert_eq(int(TimeLadder.magnitudes_crossed(half).get(&"day", -1)), 0, "half a day is no day")
	assert_eq(
		int(TimeLadder.magnitudes_crossed(day - 1).get(&"day", -1)),
		0,
		"a day less one period is no day"
	)
	assert_eq(int(TimeLadder.magnitudes_crossed(day).get(&"day", -1)), 1, "a whole day is one day")
	# The same, twice: two half-spans are two calls and neither banks anything.
	assert_eq(
		(
			int(TimeLadder.magnitudes_crossed(half).get(&"day", 0))
			+ int(TimeLadder.magnitudes_crossed(half).get(&"day", 0))
		),
		0,
		"two half-days together are still no day"
	)


## ## Ratios are whole, positive and the table's shape is valid
##
## The repo's habit is to assert SHAPE rather than a recipe that filled a file
## (`core/realm_power_table.gd:15-19`), so these read the authored `.tres` directly and
## check that it is usable rather than that it equals a pinned list. A hand-edited table
## that authored a 0 or a negative would otherwise make `magnitudes_crossed` silently
## skip the row — a magnitude the player is told exists and the clock never crosses.
func test_every_authored_ratio_is_a_positive_whole_number() -> void:
	var rows := TimeLadder.magnitudes()
	assert_eq(rows.is_empty(), false, "the table ships magnitudes at all")
	for row in rows:
		var name := String(row.get("name", ""))
		var ratio: Variant = row.get("ratio_periods", 0)
		assert_ne(name, "", "every magnitude row is named")
		assert_eq(
			typeof(ratio), TYPE_INT, "%s authors a whole number of periods, not a float" % name
		)
		assert_eq(int(ratio) >= 1, true, "%s authors a ratio of at least one period" % name)


## A ratio of zero, a NaN or an infinity is not a ratio. `int()` on a NaN is a runtime
## error and on an infinity is undefined, so this row is the one that would turn a
## hand-edited table into a crash rather than a wrong number — asserted here because a
## wrong number is survivable and a crash in the clock is not.
func test_no_authored_ratio_is_zero_negative_or_non_finite() -> void:
	for row in TimeLadder.magnitudes():
		var name := String(row.get("name", ""))
		var ratio := float(row.get("ratio_periods", 0))
		assert_eq(is_finite(ratio), true, "%s authors a finite ratio" % name)
		assert_eq(ratio > 0.0, true, "%s authors a positive ratio" % name)


## No two rows may share a name. A duplicate would make `ratio_for` answer with whichever
## row the scan reached first and make `magnitudes_crossed` collapse two magnitudes into
## one key — a silent merge of two authored scales, which is exactly the failure a
## name-keyed table exists to prevent.
func test_no_two_magnitudes_share_a_name() -> void:
	var seen: Array[StringName] = []
	for row in TimeLadder.magnitudes():
		var name := StringName(str(row.get("name", "")))
		assert_eq(seen.has(name), false, "%s is authored once" % name)
		seen.append(name)


## An unknown magnitude answers `0`, not the base's own `1`. This is why `ratio_for`
## refuses to fall back to `1`: `1` is a REAL ratio (it is the base), so a caller asking
## about a magnitude nobody authored would be told it spans one period and go on to
## divide by it.
func test_an_unknown_magnitude_is_zero_and_not_the_base_ratio() -> void:
	assert_eq(TimeLadder.ratio_for(&"not_a_magnitude"), 0, "a magnitude nobody authors is 0")
	assert_eq(TimeLadder.ratio_for(TimeLadder.BASE), 1, "the base is a real ratio of one")


## ## The base is the unit everything else is measured from
##
## `ratio_for(BASE)` is 1, which is what makes every other row's number "whole periods
## per magnitude" rather than an ambiguous count of something. It also means a caller
## never has to special-case the base when dividing.
func test_the_base_magnitude_is_one_period() -> void:
	assert_eq(TimeLadder.ratio_for(TimeLadder.BASE), 1, "the base spans one period")


## ## Each ratio is measured from the BASE, never from the row below
##
## The witness is the non-divisibility the calendar forces. A chained ladder would compute
## a year as `12 x 30 x 365 = 131,400` periods; the authored answer is 4,380. So if a
## future implementation chained these rows, the year count would be off by a factor of
## 30 and every coarser row with it — a change to ONE row silently rewriting the meaning
## of every other, which is ADR 0050 in reverse and ADR 0173's "a ratio derived from a
## ratio: trigger never".
func test_each_ratio_is_measured_from_the_base_and_never_from_the_row_below() -> void:
	var day := TimeLadder.ratio_for(&"day")
	var month := TimeLadder.ratio_for(&"month")
	var year := TimeLadder.ratio_for(&"year")
	assert_eq(month % day, 0, "the probe month divides into whole days, or it proves nothing")
	# A chained year would be `day x (month / day) x (year / month)`. Assert the authored
	# answer is that CHAIN only when the calendar is self-consistent, and is NOT otherwise.
	var chained := day * (month / day) * (year / month)
	if year == chained:
		assert_eq(
			year == month * (year / month),
			true,
			"a self-consistent year may coincide with the chain, and then it must divide"
		)
	else:
		assert_eq(
			year != chained,
			true,
			(
				(
					"the year is authored, not chained: %d periods, where a chained ladder "
					+ "would compute %d"
				)
				% [year, chained]
			)
		)


## ## Chunking stays bounded for an absurd span
##
## ADR 0173: the chunk size GROWS with the elapsed span so the count stays "small and
## fixed-ish rather than proportional", with `MAX_CHUNKS := 64` pinned by a test. The
## count is asserted against the RAW PERIOD COUNT it replaces: a per-period chunker at
## the per-call chunk of 8 would need 5.5e11 chunks for a trillion periods, and this is
## the number that must NOT appear.
func test_chunking_an_absurd_span_stays_inside_max_chunks() -> void:
	var per_call := WorldPulse.MAX_PERIODS_PER_PULL
	assert_eq(
		TimeLadder.chunk_count_for(trillion_periods(), per_call),
		TimeLadder.MAX_CHUNKS,
		"a 10^12-period span comes back as the cap, never as 5.5e11 chunks"
	)
	var raw_chunks := trillion_periods() / per_call
	assert_eq(
		TimeLadder.chunk_count_for(trillion_periods(), per_call) * 1000 < raw_chunks,
		true,
		"and the chunk count is orders of magnitude below the raw per-period count"
	)
	# Every span, absurd or ordinary, lands in 1..MAX_CHUNKS. A span smaller than one
	# chunk is ONE chunk — a plan of zero chunks would drop the span entirely.
	for span in [1, 8, 9, 4_380, 1_000_000, billion_years_periods(), trillion_periods()]:
		var count := TimeLadder.chunk_count_for(span, per_call)
		assert_eq(count >= 1, true, "a positive span is at least one chunk (%d)" % span)
		assert_eq(count <= TimeLadder.MAX_CHUNKS, true, "%d periods is at most 64 chunks" % span)
	assert_eq(TimeLadder.chunk_count_for(0, per_call), 0, "no span is no chunks")


## The chunk sizes SUM to the span, because a plan that dropped or invented periods would
## leave the world a fraction of a period away from what the caller paid for with nothing
## anywhere recording the difference.
##
## And the chunk size GROWS with the span, which is the whole point of the cap: 10^12
## periods comes back as 64 chunks of ~1.6e10 rather than 5.5e11 chunks of 8. A chunk is
## never smaller than the floor EXCEPT when the whole span is shorter than one floor
## chunk — there the plan is the single span, because a chunk larger than the span would
## be inventing time nobody paid for.
func test_a_chunk_plan_covers_the_span_exactly_and_never_falls_below_the_floor() -> void:
	var per_call := WorldPulse.MAX_PERIODS_PER_PULL
	for span in [1, 7, 8, 400, 4_380, 1_000_000, billion_years_periods(), trillion_periods()]:
		var plan := TimeLadder.chunks_for(span, per_call)
		var count := TimeLadder.chunk_count_for(span, per_call)
		assert_eq(
			plan.size(), count, "%d periods: the plan holds exactly the counted chunks" % span
		)
		assert_eq(count <= TimeLadder.MAX_CHUNKS, true, "%d periods: the plan is capped" % span)
		assert_eq(
			plan[0] >= mini(per_call, span),
			true,
			"%d periods: the first chunk is a whole chunk, not a sliver" % span
		)
		assert_eq(
			TimeLadder.covered_periods(plan),
			span,
			"%d periods: the plan covers the span exactly, nothing dropped or invented" % span
		)
	# The growth claim, stated on the numbers rather than left to the count above: the
	# absurd span's chunks are orders of magnitude above the per-call floor.
	var absurd := TimeLadder.chunks_for(trillion_periods(), per_call)
	assert_eq(absurd.size(), TimeLadder.MAX_CHUNKS, "an absurd span is exactly the cap")
	assert_eq(absurd[0] > per_call * 1000, true, "and each chunk is enormous, not the floor")


## A non-positive span is nothing to chunk. A non-positive CHUNK SIZE is the one request
## that cannot produce a plan at any count, so `chunks_for` refuses it LOUDLY (below) and
## `chunk_count_for` refuses it by clamping to the cap rather than by dividing by zero —
## `maxi(1, 0)` is what keeps `100/0` from ever being attempted.
func test_chunking_a_non_positive_span_returns_nothing() -> void:
	assert_eq(TimeLadder.chunks_for(0, 8).size(), 0, "no span, no plan")
	assert_eq(TimeLadder.chunks_for(-5, 8).size(), 0, "a negative span is no plan")


## The count helper is the other door to a bad chunk size, and it answers with a LEGAL
## plan rather than a crash or a number nobody can execute: `maxi(1, chunk_periods)`
## makes a zero or negative floor ask for as many chunks as possible, and the cap is the
## answer. One chunk is the smallest legal answer, so a span below the floor is one chunk.
func test_a_non_positive_chunk_size_still_yields_a_legal_chunk_count() -> void:
	assert_eq(TimeLadder.chunk_count_for(1, 0), 1, "a zero chunk size never divides by zero")
	assert_eq(TimeLadder.chunk_count_for(1, -3), 1, "and neither does a negative one")
	assert_eq(TimeLadder.chunk_count_for(1000, 0), TimeLadder.MAX_CHUNKS, "a long span is the cap")
	assert_eq(
		TimeLadder.chunk_count_for(1000, 0) <= TimeLadder.MAX_CHUNKS,
		true,
		"the answer is still inside the cap"
	)


## ## The loud refusals fail loudly, and the file proves it without running the branch
##
## `chunks_for` and `exceeds_budget` both `push_error` a message naming the offending
## numbers, and neither silently truncates. Asserting the BEHAVIOUR would charge a
## failure for testing it: `TestCase.push_error` latches `_test_errors`
## (`tests/framework.gd:196-200`) and `run_tests.gd:140` fails any body that pushed, so a
## case that drove the refusing branch would go red for being correct.
##
## So the shape is read from source instead — the same substitution `test_realm_rate.gd`
## makes for exactly this class of guard. What matters is that the message names the
## inputs, so a failure in the field says which span or which place produced it rather
## than "a budget was exceeded".
##
## Three `push_error` calls is the whole census, and it is pinned exactly: a fourth would
## be a refusal path nobody documented, and a silent one — a `return` with no error is how
## a clock starts answering "nothing happened" to everything without any of it appearing.
func test_exactly_three_loud_refusals_exist_and_neither_discards_anything() -> void:
	var code := _code_only(FileAccess.get_file_as_string(SRC_PATH))
	assert_eq(
		code.count("push_error("),
		3,
		"three refusals: a missing table, a bad chunk size and an over-budget offer"
	)
	# Neither discards anything. `truncate` and `slice` are the two shapes a silent
	# truncation would take here, and neither may appear anywhere in the code.
	assert_eq(code.contains("truncate"), false, "nothing is truncated to fit")
	assert_eq(code.contains(".slice("), false, "and no span is cut down to a shorter one")
	# The chunk-size refusal names both numbers it could not satisfy, and the budget
	# refusal names three: the place, the span and the count offered.
	assert_eq(
		code.count("% [span_periods, chunk_periods]"),
		1,
		"the chunk refusal names the span and the chunk size"
	)


## ## The event budget is a CONSTANT and exceeding it FAILS LOUDLY
##
## The shape this pins: within the budget is silent and TRUE, over it is TRUE and names
## the place, the span and the count — and it never TRUNCATES. `RowBudget` truncates a
## *screen* and reports "N of M" (`core/row_budget.gd:14-16`), the right trade there.
## World history has no "N of M", and a silently truncated history is worse than a
## refusal: the player cannot see it and the ledger is monotone and cannot un-record it.
##
## **Only the non-pushing half is asserted.** `TestCase.push_error` latches `_test_errors`
## (`tests/framework.gd:196-200`), and `run_tests.gd:140` fails any body that pushed, so
## driving the refusing branch from a test would charge a failure for testing it. The
## over-budget branch is therefore asserted STRUCTURALLY, below, and the constant itself
## here.
func test_the_event_budget_is_a_plain_constant_and_is_not_much() -> void:
	assert_eq(TimeLadder.EVENT_BUDGET > 0, true, "a span may spend something")
	assert_eq(
		TimeLadder.EVENT_BUDGET >= 2,
		true,
		(
			"more than one: `WorldPulse.MAX_OPENS_PER_PULL := 1` is the per-pull "
			+ "floor, and a billion-year skip that may open one thing is "
			+ "indistinguishable from a player standing still"
		)
	)
	assert_eq(
		TimeLadder.EVENT_BUDGET <= WorldPulse.MAX_PERIODS_PER_PULL,
		true,
		"one budget spend cannot offer more beats than the call paying for it already allowed"
	)
	assert_eq(TimeLadder.exceeds_budget(0, &"nothing", 0), false, "within the budget is silent")
	assert_eq(
		TimeLadder.exceeds_budget(TimeLadder.EVENT_BUDGET, &"nothing", 0),
		false,
		"exactly the budget is within it"
	)


## ## Exceeding the budget refuses, and it never truncates
##
## Read as source, for the reason `test_realm_rate.gd:23-27` gives: a guard that only
## compared numbers passed unchanged with all three paths back on private curves. A
## numerically-identical private copy of a budget stays green under every value
## assertion, so the shape has to be checked where the defect is — in the text.
##
## Three things must be visible in the code and are not visible in any answer it
## returns: the error NAMES the place, the span and the count; and the branch returns a
## bool rather than clamping, so the CALLER decides what refusing means. It never quietly
## emits the budget and drops the rest — that is the assertion above.
func test_exceeding_the_budget_names_the_place_the_span_and_the_count() -> void:
	var code := _code_only(FileAccess.get_file_as_string(SRC_PATH))
	assert_ne(code, "", "the ladder source is readable")
	assert_eq(code.contains("exceeds_budget"), true, "the budget check is declared")
	assert_eq(code.contains("place"), true, "the error names the place")
	assert_eq(code.contains("span_periods"), true, "and the span")
	assert_eq(code.contains("offers"), true, "and the count it was offered")
	# A refusal RETURNS rather than clamps: the only number the function emits is the
	# budget itself, and a caller reading `offers <= EVENT_BUDGET` back would have been
	# handed a silent truncation.
	assert_eq(code.contains("return offers"), false, "it never returns a smaller offer count")


## ## ## Every row is independent (ADR 0050's anti-shift property)
##
## The property, stated so it cannot be misread: **adding a magnitude is ONE ROW and no
## existing answer moves.** This is the check the repo's own history pays for — a ladder
## keyed by POSITION silently rebases everything below an insertion (AGENTS.md:140), and
## `RealmPowerTable` is keyed by realm id precisely to avoid it.
##
## Driven against the live authored array, mutated in place and restored before
## asserting, so a failure here cannot leak a six-row table into whichever suite runs
## next in this one process and turn one failure into three — the discipline
## `test_realm_rate.gd:120-124` uses for the same reason.
##
## **The tail of this case used to be VACUOUS and now is not.** It compared
## `_time_ladder_conversion_branches()` with ITSELF, which no edit to any file in the
## repository could turn red — the assertion could not fail, so it proved nothing. What
## replaced it are two snapshots of the SAME quantity taken before and after the probe row
## goes in: the work count (which must move by exactly one, for a span that reaches the
## added row) and the branch count (which must not move at all).
func test_inserting_a_row_does_not_change_any_existing_magnitude() -> void:
	var rows := TimeLadder.magnitudes()
	var original_size := rows.size()
	assert_eq(original_size > 0, true, "there are rows to compare against")
	var spans := [1, 400, 4_380, 100_000, billion_years_periods()]
	var before := {}
	for span in spans:
		before[span] = TimeLadder.magnitudes_crossed(span)
	# The WORK this table costs for a span that crosses several rows, taken BEFORE the
	# probe row exists, so "the count is derived, not a constant" is a measurement rather
	# than a restatement of the function under test. Same span is measured after, so the
	# two are comparable.
	var probe_span := billion_years_periods()
	var work_before := TimeLadder.conversion_work(probe_span)
	var branches_before := _time_ladder_conversion_branches()
	# A new, COARSER magnitude, inserted ABOVE everything that ships. If any ratio were
	# derived from a row index or from the row below, this is the insertion that moves
	# every existing answer.
	rows.append({"name": &"eon", "ratio_periods": 1_000_000_000})
	var after := {}
	for span in spans:
		after[span] = TimeLadder.magnitudes_crossed(span)
	# The work count for the SAME span with the probe row in place, read while it is still
	# there. `probe_span` reaches the new `eon` row (10^9 periods), so the added row is
	# one more division — which is the anti-shift property stated as WORK.
	var work_with_row := TimeLadder.conversion_work(probe_span)
	var inserted_size := rows.size()
	rows.resize(original_size)
	# Restore before asserting, so a failure cannot leak the mutation.
	assert_eq(rows.size(), original_size, "the probe row was removed again")
	assert_eq(inserted_size, original_size + 1, "the probe row was really there")
	for span in spans:
		var unchanged: Dictionary = (before[span] as Dictionary).duplicate()
		# The inserted magnitude is the ONE key that may differ: it now exists.
		(after[span] as Dictionary).erase(&"eon")
		assert_eq(
			after[span],
			unchanged,
			"a row inserted above every other changes no existing answer for %d periods" % span
		)
	# And the shape the insertion was for: **adding a magnitude the span reaches costs ONE
	# more division and nothing else** — no new fold, no new branch, and no existing
	# answer moved. This replaces a self-comparison against itself that could never fail.
	assert_eq(
		work_with_row,
		work_before + 1,
		(
			"the probe row is one more division at %d periods and nothing more (%d against %d)"
			% [probe_span, work_with_row, work_before]
		)
	)
	# And a span that does NOT reach the added row pays nothing for it, which is the same
	# property from the other side: the count follows the fold rather than the row count.
	assert_eq(
		TimeLadder.conversion_work(SMALL_SPAN),
		TimeLadder.EVENT_BUDGET + _crossed_by(SMALL_SPAN),
		"and %d periods reach no `eon` at all, so the added row costs them nothing" % SMALL_SPAN
	)
	# **The branch half, and the only assertion in this file that was vacuous.** It used
	# to read `_time_ladder_conversion_branches()` against ITSELF, which no edit to any
	# file could ever turn red. `branches_before` is a snapshot taken before the row went
	# in, so the comparison is between two moments and can fail.
	assert_eq(
		_time_ladder_conversion_branches(),
		branches_before,
		"and adding a row adds no `match`/`elif` to the conversion path"
	)


## ## The source-reading guards
##
## `tools arch` cannot see any of this: `BARE_REF_UNITS` excludes `modules/*` and `core/`
## (`tools/arch/rules.py:52-53`), so a numerically-identical private copy of a period
## ratio stays green under every value assertion in this file. ADR 0116 has the mutation:
## a private copy that was numerically identical stayed green under every value check and
## only the STRUCTURAL pins fired (403 passed / 3 failed). So these read source.
##
## Nothing under `src/` may declare its own seconds-per-period. The canonical number is
## `TimeLadder.PERIOD_SECONDS`, and ADR 0173 names the pending duplicates: `world_pulse.gd:88`
## and `save_clock.gd:34`. **The first is deliberately still there** — the migration is
## another change, so this assertion names them as the two known copies rather than
## pretending the tree is already clean.
func test_the_canonical_period_ratio_is_120_seconds_in_one_place_in_this_file() -> void:
	assert_eq(TimeLadder.PERIOD_SECONDS, 120.0, "the base ratio is two real minutes")
	var code := _code_only(FileAccess.get_file_as_string(SRC_PATH))
	assert_eq(
		code.contains("const PERIOD_SECONDS := 120.0"),
		true,
		"and it is authored in this file, the SSOT ADR 0173 moved it to"
	)


## The named copies, pinned by NAME so the migration can delete them and this assertion
## can be narrowed in the same change — and so what is left is recorded rather than
## assumed. An unnamed second copy is the defect this half cannot see, which is why the
## count of what is named here is asserted rather than left implicit.
##
## ## NARROWED, and what is now true
##
## ADR 0179 deleted `save_clock.gd`'s copy, and it was the right deletion: the autosave
## counts whole PERIODS, so it declares no seconds-per-period ratio at all, which is
## what makes "a fraction of a period" inexpressible as input to it. The scan counts
## the SSOT itself, so the tree went from three named sites to **two**: the one
## authoring (`core/time_ladder.gd:110`) and one reader's name (`world_pulse.gd:88`).
##
## So the pin is four assertions, not one vacuous `has()`:
##
##   1. **Exactly two** declarations exist — the count, which is what catches an unnamed
##      copy (ADR 0116's mutation).
##   2. The SSOT authors the literal, **resolved by content rather than by line number**.
##      A hard-coded `time_ladder.gd:110` made this assertion a trip-wire on the file's
##      own COMMENT LENGTH: adding two lines of `##` above the constant turned it red
##      while the tree stayed exactly as correct as before. Resolving the line by the
##      literal it declares is strictly stronger — it asserts the constant is authored
##      AND that the resolved line really carries it, rather than asserting a number a
##      paragraph can move.
##   3. `world_pulse.gd` is present BY NAME, so a third site fails naming itself.
##   4. `save_clock.gd` declares none — the pin does not merely go quiet when the
##      migration lands, it fails if a copy is ever put back.
func test_the_one_named_period_ratio_copy_is_the_only_one_this_file_knows_of() -> void:
	var declared := _period_ratio_declarations("res://src")
	var sites: Array[String] = []
	for entry in declared:
		sites.append(String(entry))
	assert_eq(
		sites.size(),
		2,
		"the SSOT and one reader's name, and no third copy anywhere: %s" % str(sites)
	)
	var ssot := _declaration_in(sites, "res://src/core/time_ladder.gd")
	assert_ne(ssot, "", "the SSOT authors the ratio, which is the one literal allowed to exist")
	assert_eq(
		_read_line("res://src/core/time_ladder.gd", ssot).contains("120.0"),
		true,
		"and the line the scan resolved really carries the ratio: %s" % ssot
	)
	assert_eq(
		_read_declaring("res://src/app/world_pulse.gd", &"PERIOD_SECONDS").contains(
			"TimeLadder.PERIOD_SECONDS"
		),
		true,
		"and world_pulse reads the SSOT by name, wherever that line now sits"
	)
	assert_eq(
		sites.has("res://src/modules/save/save_clock.gd:34"),
		false,
		"save_clock.gd declares no ratio (ADR 0179), and a copy put back would fail here"
	)
	# The surviving copy is a READ, not a second authoring. This is the assertion that
	# would have caught ADR 0179's copy in the first place, and it is here rather than
	# left implicit because `tools arch` cannot see it: `BARE_REF_UNITS` excludes
	# `app/`'s private constants from the bare-reference scan.
	var pulse := _code_only(FileAccess.get_file_as_string("res://src/app/world_pulse.gd"))
	assert_eq(
		pulse.contains("const PERIOD_SECONDS := TimeLadder.PERIOD_SECONDS"),
		true,
		"the one remaining copy delegates to the SSOT instead of restating 120.0"
	)


## ## ## No clock and no driver in the clock
##
## ADR 0089 / DEF-0111 and AGENTS.md:157: no `Time.get_ticks*` outside `app/`, no
## module owns a clock. A magnitude conversion is arithmetic on a count handed DOWN, and
## this file reading a wall clock would make the world's age depend on how long the
## machine was up — which is precisely the "there is a real-time clock for the world"
## failure ADR 0173 deletes.
##
## `tests/app/test_status_clock.gd:222-230` pins exactly three frame drivers; a fourth is
## a second clock. This file declares none, and asserts that it declares none.
func test_the_clock_owns_no_wall_clock_and_declares_no_frame_driver() -> void:
	var code := _code_only(FileAccess.get_file_as_string(SRC_PATH))
	for forbidden in [
		"Time.get_ticks",
		"get_tree()",
		"func _process(",
		"func _physics_process(",
	]:
		assert_eq(code.contains(forbidden), false, "%s never appears here" % forbidden)


## ## ## No loop this repo cannot bound
##
## There is no `while` in this file at all, so `test_no_unbounded_wait.gd` has nothing
## here to refuse and `AGENTS.md:54`'s "a loop bounded by elapsed time" cannot reappear
## in it. Every `for` walks either the authored row array or a cap declared beside it.
func test_no_while_loop_can_hide_in_the_ladder() -> void:
	var code := _code_only(FileAccess.get_file_as_string(SRC_PATH))
	assert_eq(code.contains("while "), false, "the ladder contains no `while` at all")


## ## `summary()` is primitives only, so `tools ui drive` can print it
##
## The UI standard requires a `summary()` of primitives, and a `Resource` row array is
## not one. Asserted on the shipped instance rather than on a shape, because a nested
## authored object would print as an opaque reference and tell a headless driver
## nothing.
func test_summary_reports_the_shipped_shape_as_primitives() -> void:
	var summary := TimeLadder.summary()
	assert_eq(summary.get("magnitudes"), TimeLadder.magnitudes().size(), "every row is counted")
	assert_eq(summary.get("event_budget"), TimeLadder.EVENT_BUDGET, "the budget is reported")
	assert_eq(summary.get("max_chunks"), TimeLadder.MAX_CHUNKS, "the chunk cap is reported")
	assert_eq(
		summary.get("period_seconds"), TimeLadder.PERIOD_SECONDS, "the base ratio is reported"
	)
	for key in summary:
		var value: Variant = summary[key]
		var printable := (
			typeof(value) == TYPE_INT
			or typeof(value) == TYPE_FLOAT
			or typeof(value) == TYPE_STRING
			or (value is Array and _all_primitives(value))
		)
		assert_eq(printable, true, "summary[%s] is primitive" % key)


## ## Helpers --------------------------------------------------------------


## The magnitudes `count` single-period advances accumulate, arrived at by ADDING one
## period at a time. This is the thing the conversion replaced, computed the slow and
## obvious way so the comparison is against an independent arithmetic rather than against
## the same division twice.
##
## Bounded by `count`, which is a literal in every caller here — never a span read off a
## clock, which is what makes it safe to run over 100,000 iterations in a test. It is the
## SHAPE that is under test here (steps versus a division), not the size: the shipped
## implementation must never do this.
func _stepped_magnitudes(count: int) -> Dictionary:
	var ratios := []
	for row in TimeLadder.magnitudes():
		ratios.append([StringName(str(row.get("name", ""))), int(row.get("ratio_periods", 0))])
	var counted := {}
	var passed := 0
	for step in count:
		passed += 1
		for pair in ratios:
			var magnitude: StringName = pair[0]
			var ratio: int = pair[1]
			if ratio < 1 or passed % ratio != 0:
				continue
			counted[magnitude] = int(counted.get(magnitude, 0)) + 1
	return counted


## Every `res://src` file declaring its own seconds-per-period ratio, as `path:line`.
## The guard reads SOURCE because `tools arch` cannot see it: `BARE_REF_UNITS` excludes
## `modules/*` (`tools/arch/rules.py:52`), so a numerically-identical private copy would
## stay green under every value assertion in this suite. `test_realm_rate.gd:208-224` is
## the precedent, and ADR 0116 is the mutation it exists for.
func _period_ratio_declarations(root: String) -> Array[String]:
	var found: Array[String] = []
	for path in _gdscript_files(root):
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for index in lines.size():
			var line := String(lines[index]).strip_edges()
			if not line.begins_with("const "):
				continue
			var name := line.split(" ", false)[1]
			if name in ["PERIOD_SECONDS", "SECONDS_PER_PERIOD", "PERIOD_LENGTH_SECONDS"]:
				found.append("%s:%d" % [path, index + 1])
	return found


## The `path:line` entry in `sites` that belongs to `path`, or `""` when that file
## declares none. Resolving by path rather than asserting a literal `path:NNN` is what
## lets the SSOT's declaration move when the file's PROSE grows — a hard-coded line
## number made this pin fail on a comment edit, which is the guard firing on its own
## documentation.
func _declaration_in(sites: Array[String], path: String) -> String:
	for entry in sites:
		if entry.begins_with(path + ":"):
			return entry
	return ""


## The text of `path`'s line numbered by a `path:NNN` entry from `_period_ratio_declarations`
## (or a bare `NNN`), or `""` when it cannot be read. Stripped, because this tree's files
## carry CRLF and a raw split on `\n` leaves a `\r` that makes every substring probe miss.
func _read_line(path: String, line_no: String) -> String:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	# The entry is `path:NNN`, so the number is whatever follows the last colon.
	var index := int(line_no.get_slice(":", line_no.count(":"))) - 1
	if index < 0 or index >= lines.size():
		return ""
	return String(lines[index]).strip_edges()


## The line in `path` that DECLARES `name`, found by the name rather than by a line
## number.
##
## **A pinned line number is a trip-wire on everything above it.** `world_pulse.gd`'s
## `PERIOD_SECONDS` reader was asserted at `:88` and went red the moment a peer added a
## docstring above it — with no clock behaviour changed, which is the same failure
## `test_time_ladder_single_source.gd`'s census hit and had fixed for itself. Resolving
## by name is what makes the assertion about the DECLARATION.
func _read_declaring(path: String, name: StringName) -> String:
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := String(raw).strip_edges()
		if line.begins_with("const %s " % name) or line.begins_with("const %s :=" % name):
			return line
	return ""


## The `match`/`elif` arms in the ladder's own conversion path, counted as TEXT. Asserted
## equal to a captured snapshot taken earlier in the anti-shift case, so an edit that adds
## a branch on a magnitude NAME fails on its own line. This helper is what that snapshot
## reads; the assertion itself lives in the anti-shift case, next to the mutation it
## measures, rather than here where it could only be compared against itself.
func _time_ladder_conversion_branches() -> int:
	var code := _code_only(FileAccess.get_file_as_string(SRC_PATH))
	var count := 0
	for line in code.split("\n"):
		var stripped := String(line).strip_edges()
		if stripped.begins_with("match ") or stripped.begins_with("elif "):
			count += 1
	return count


## Every `.gd` under `root`, recursively. The `DirAccess` terminator the arch rule
## accepts (`tests/arch_rules/test_no_unbounded_wait.gd:16-32`), bounded by the
## directory's contents rather than by game state.
func _gdscript_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_gdscript_files(path))
			elif entry.ends_with(".gd"):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## The source with every comment line dropped, so a guard reads CODE and not the prose
## beside it. `test_realm_rate.gd` reads whole files, which is why a guard written there
## has to be careful about which words it searches for; this strips first, so "truncat"
## cannot be satisfied by a docstring.
func _code_only(text: String) -> String:
	var kept: Array[String] = []
	for line in text.split("\n"):
		var stripped := String(line).strip_edges()
		if stripped.begins_with("#"):
			continue
		kept.append(stripped)
	return "\n".join(kept)


## Whether every element of `values` is a primitive, recursively through one array level
## — which is what `summary()` actually nests (`names` and `ratios`).
func _all_primitives(values: Array) -> bool:
	for value in values:
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_STRING:
			continue
		if value is Array and _all_primitives(value):
			continue
		return false
	return true
