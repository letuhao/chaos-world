class_name TimeLadder
extends Resource

## The one clock's shape: AUTHORED, NAMED MAGNITUDES, and the fixed event budget an
## elapsed span may spend (ADR 0173). Time is a set of named magnitudes with authored
## whole-number ratios, in ONE file, beside `RealmRate` and `InstitutionBudget`.
##
## `core` is a LAYER, not a module (`tools/arch/rules.py:29`), so this costs ZERO new
## arch edges — the `RealmRate` argument (ADR 0066), unchanged by the numbers in it.
##
## ## What it replaces, and why 0168 could not hold the claim
##
## ADR 0168 priced an elapsed span as `O(tiers crossed x consumers)` against a fixed
## six-row ladder and called that independent of elapsed time. It is not: 10^9 years
## does not CROSS six tiers, it SITS INSIDE the era tier, so the era row is crossed
## once and a consumer is handed one bucket of 10^9 to answer from. The shipped line
## has the same shape (`app/world_pulse.gd:353-354`, `for index in periods:`), and
## that loop's bound is `periods`, which is DATA-DERIVED — `AGENTS.md:52` verbatim,
## "a data-derived row count is not a fixed count either" — which is the shape of the
## recorded 67 GB incident.
##
## **So conversion here is DIVISION, and only division.** `magnitudes_crossed` does one
## integer division per authored magnitude and returns. No loop is bounded by elapsed
## time, no row index is walked to "descend", and the finer steps inside a coarser
## bucket are NEVER emitted — an elapsed interval is a COUNT handed down, never a
## sequence of steps replayed (ADR 0168's surviving rule).
##
## ## Each ratio is measured from the BASE, never from the row below
##
## `ratio_periods` answers "how many whole periods make ONE of this magnitude", and
## every row carries that number ITSELF. A chained product would be WRONG, not merely
## inelegant: the ladder is deliberately not self-consistent, because a 30-day month
## inside a 365-day year is what a calendar IS (ADR 0168:92-95). Chaining a month of
## 30 days onto a day of 12 periods yields 360, and then a year of 365 days reads as
## 131,400 periods when it is 4,380 — the shape ADR 0173 (a) refuses outright, "a
## ratio derived from a ratio: trigger never". So the author writes 4,380, and moving
## one ratio never moves another. That is ADR 0050: authored data, keyed by name.
##
## ## One division per row is also the anti-shift property
##
## Because no row is derived from any other, INSERTING a row changes no existing row's
## value — `tests/core/test_time_ladder.gd` proves it by inserting one and comparing
## every count before and after. A chained ladder could not do that: a new row at the
## top would rebase everything below it, which is the `RealmPowerTable` failure this
## repo already paid for (AGENTS.md:140, "an inserted realm would silently shift every
## realm below it").
##
## ## Surplus is DROPPED, never banked
##
## Each magnitude truncates independently and the remainder is discarded, which is
## `app/world_pulse.gd:90-94`'s own reason restated: "a banked surplus is a backlog
## that pays out later at a rate nobody chose". Two half-months are not one month.
##
## ## The event budget is a CONSTANT, and that is the whole of it
##
## An elapsed span of ANY length declares `EVENT_BUDGET` world events. It is not a
## formula, not a function of the span, and not a function of the magnitudes crossed —
## a budget computed from the span is the span's cost wearing a different name
## (ADR 0173 (b), "Refused, trigger: never"). **The span says what became POSSIBLE; the
## budget says how much of it happens.** Precedent at the smallest scale is
## `WorldPulse.MAX_OPENS_PER_PULL := 1` (`world_pulse.gd:100`) and the deliberate
## `WorldAmbient.ROSTER` stagger at periods 1, 2, 3, 4 (`world_ambient.gd:60-65`), whose
## comment at `:44-46` names the cap as the reason one pull cannot open four events.
##
## Exceeding it FAILS LOUDLY and never truncates (`AGENTS.md:56`, `:75`): `RowBudget`
## truncates a *screen* and reports "N of M" (`core/row_budget.gd:14-16`), the right
## trade there. World history has no "N of M", a silently truncated history is worse
## than a refusal, and the player cannot see a truncation they were never told about.
##
## ## Cost
##
## One advance costs `conversion_work()` — one integer division per authored magnitude
## plus the budget — and that number is IDENTICAL for one period and for 10^9 years.
## That is the claim ADR 0168 could not make, and
## `tests/core/test_time_ladder.gd` asserts the WORK COUNT rather than the answer,
## because an answer alone cannot distinguish 5 divisions from 10^12 of them.
##
## ## ## No clock, no driver, no loop this file cannot bound
##
## There is no `Time.get_ticks*`, no frame callback and no `get_tree()` here
## (ADR 0089 / DEF-0111): a span is handed DOWN by the caller that owns time, exactly
## as every accrual verb in the tree already takes an explicit period count. Every loop
## in this file walks the AUTHORED row array or a cap declared beside it, so
## `tests/arch_rules/test_no_unbounded_wait.gd` has nothing here to refuse — and there
## is no `while` at all. **Integer arithmetic only, never a float**, for the same
## reason `app/institution_resolver.gd:_every` is (`:155-158`): a ratio is an authored
## divisor and a period count must be exact.
##
## ## ## The calendar is a reading convention, not a decided schema
##
## 365 d/y is an authored number like any other here, and ADR 0173 leaves the calendar
## schema open. `PERIOD_SECONDS` is the BASE RATIO and the canonical home of the value
## that lived at `app/world_pulse.gd:88`; it is NOT deleted from there by this file, so
## the call-site migration can happen on its own change rather than inside this one.
## `save_clock.gd:34` is a second, numerically identical copy that ADR 0173 names as
## the pending half of its fix — the same class of defect as the three `RealmProfile`
## curves, and `test_realm_rate.gd:208-224` is why it needs a source-reading guard
## rather than a value comparison.

## The shipped magnitudes. Loaded, not preloaded: a `preload` of a `.tres` that binds
## THIS script is a load cycle, and `core/realm_power_table.tres` is read the other way
## round for exactly that reason — `RealmDefaults.POWER` preloads the table, and the
## table's script preloads nothing. One cached read, `InstitutionBudget.shipped()`'s
## shape (`core/institution_budget.gd:63-64`).
const TABLE_PATH := "res://src/core/time_ladder_table.tres"

## The AUTHORED rows, in the shipped `.tres` and nowhere else. Ordered finest first so
## `period` — the base the other ratios are measured from — is row zero; the ORDER is
## what a reader scans, and no function depends on it, because nothing indexes into this
## array. Keyed by NAME (`ratio_periods` is looked up by magnitude id, never by row),
## which is the ADR 0050 rule and the anti-shift guarantee above.
@export var magnitude_rows: Array[Dictionary] = []

## Seconds of elapsed time in one world period: the BASE RATIO, and the one cadence
## number (ADR 0173 "time-shaped constants migrate to it"). 120.0 is the value that
## shipped at `app/world_pulse.gd:88`, moved here without being edited.
const PERIOD_SECONDS := 120.0

## How many world events an elapsed span of ANY length may spend. The single number a
## reviewer tunes, and deliberately the smallest one that is still a plural: one event
## per advance is `WorldPulse.MAX_OPENS_PER_PULL`, and a billion-year skip that may open
## only one thing is indistinguishable from a player standing still. Four stays UNDER
## `MAX_PERIODS_PER_PULL := 8` (`world_pulse.gd:95`), which is the per-call ceiling on
## whole periods one advance hands down — so one budget spend can never offer more beats
## than the call that pays for it already allowed. The number is a CONSTANT on purpose;
## see the class docstring.
const EVENT_BUDGET := 4

## The most chunked spends a long skip may be split into. The chunk size GROWS with the
## elapsed span rather than the skip being cut into a number of pieces proportional to
## it, so the count stays bounded and small: a 10^9-year skip is at most this many
## spends, not 10^9 (ADR 0173 "Chunking and interruption are bounded"). Pinned by
## `tests/core/test_time_ladder.gd` because a constant nothing tests is a number that
## moves silently.
const MAX_CHUNKS := 64

## The base every ratio is measured from. Named rather than hard-written as row zero, so
## a caller naming a magnitude cannot depend on its position in the array.
const BASE := &"period"

## Loaded once and cached, on the same argument `RealmDefaults.POWER` is a `const` for:
## reading a file calls nothing here, which is the whole point of keeping the numbers in
## data (ADR 0050). `null` on a broken install is a loud failure rather than a silent
## zero — a ladder that answers "nothing happened" to everything is the silent-freeze
## hazard ADR 0173 (c) names.
static var _table: TimeLadder = null


## Every authored magnitude, finest first, as `{name, ratio_periods}` rows. The LIVE
## array, not a copy: `conversion_work` and `magnitudes_crossed` read it on every call
## so a playtest retune is a data edit with no cache to invalidate (ADR 0067's
## `.tres`-as-tuning-shape argument, `InstitutionBudget`'s).
static func magnitudes() -> Array[Dictionary]:
	var table := _table_resource()
	if table == null:
		return []
	return table.magnitude_rows


## The authored whole periods ONE of `magnitude` spans, or `0` for a magnitude this
## table does not author. Keyed by NAME so a row inserted anywhere changes no answer
## (ADR 0050), and `0` rather than `1` for an unknown name because `1` is a REAL ratio —
## it is the base — and a caller asking about a magnitude nobody authored must be able
## to tell that apart from a one-period magnitude.
static func ratio_for(magnitude: StringName) -> int:
	for row in magnitudes():
		if StringName(str(row.get("name", ""))) == magnitude:
			return int(row.get("ratio_periods", 0))
	return 0


## How many of EACH magnitude `span_periods` covers, as `{magnitude: whole count}`.
##
## **One integer division per authored row, and that is the entire algorithm.** Cost is
## `O(magnitudes)`: it is identical for one period and for 10^9 years, which is the claim
## ADR 0168 could not make. There is no loop whose bound is elapsed time, no row index
## walked downward, and no finer step emitted inside a coarser bucket — a span is a
## COUNT handed down, never a sequence of steps replayed.
##
## **Each row truncates INDEPENDENTLY and the surplus is DROPPED**, which is what makes
## a month of 179 periods zero months and a month of 181 periods one month. Two
## half-spans therefore never become one whole magnitude, for the reason
## `app/world_pulse.gd:90-94` gives: "a banked surplus is a backlog that pays out later
## at a rate nobody chose". Banked surplus is how a game invents an accrual rate nobody
## authored.
##
## A non-positive span is every-zero rather than an error: a frame in which no time
## elapsed is a frame in which the world did not move, the reading
## `WorldPulse.pull` already gives a zero delta.
static func magnitudes_crossed(span_periods: int) -> Dictionary:
	var crossed := {}
	var whole := maxi(0, span_periods)
	for row in magnitudes():
		var magnitude := StringName(str(row.get("name", "")))
		var ratio := int(row.get("ratio_periods", 0))
		if magnitude == StringName() or ratio < 1:
			continue
		crossed[magnitude] = whole / ratio
	return crossed


## The WORK one advance of `span_periods` costs: one integer division per authored
## magnitude, plus the `EVENT_BUDGET` offer slots the span is allowed to spend.
##
## The span is an argument so that the constant can be MEASURED against it rather than
## asserted in prose: `tests/core/test_time_ladder.gd` calls this for one period and for
## 10^9 years and requires one answer. Published rather than left private because a
## bound nothing can query is a claim, and this is the number ADR 0173's Consequences
## sentence ("a billion-year meditation costs O(magnitudes + C)") actually is.
##
## A non-positive span costs nothing: an advance with no elapsed time converts nothing
## and offers nothing, so there is no row to divide and no event to spend.
static func conversion_work(span_periods: int) -> int:
	if span_periods <= 0:
		return 0
	return magnitudes().size() + EVENT_BUDGET


## How many chunks a span is split into, always within `1..MAX_CHUNKS`, and `0` for a
## non-positive span.
##
## The chunk size GROWS with the span — the count is `ceil(span / chunk_periods)` clamped
## to the cap, so a 10^12-period skip at the per-call chunk of 8 comes back as 64 chunks
## of ~6.8e10 periods each rather than 5.5e11 chunks of 8 (ADR 0173: "chunk size GROWS
## with the elapsed span, so the chunk count stays small and fixed-ish rather than
## proportional"). Clamping the COUNT grows a chunk; it never drops one, so nothing is
## truncated and the plan still sums to the whole span.
##
## `chunk_periods` below 1 is read as 1 rather than refused: it can only ever ask for
## more chunks than the cap allows, and the cap is the answer either way.
static func chunk_count_for(span_periods: int, chunk_periods: int) -> int:
	if span_periods <= 0:
		return 0
	var step := maxi(1, chunk_periods)
	return clampi(_ceil_div(span_periods, step), 1, MAX_CHUNKS)


## The chunk SIZES, in periods, summing to exactly `span_periods`. `chunk_periods` is
## the caller's floor; these are at least as large, because `chunk_count_for` is what
## decided how many of them fit.
##
## The first `span % count` chunks carry one extra period each, so the plan is exact
## rather than approximate: an off-by-a-few-periods plan would leave the world a
## fraction of a period short of the span the caller paid for, with nothing anywhere
## recording that it happened.
##
## An empty plan is returned, never a truncated one, and a non-positive `chunk_periods`
## is the one request that cannot be met at all — so it is REFUSED LOUDLY, naming the
## span and the count (`AGENTS.md:56`). The other empty case is a non-positive span,
## which genuinely has nothing to chunk.
static func chunks_for(span_periods: int, chunk_periods: int) -> PackedInt64Array:
	var plan := PackedInt64Array()
	if span_periods > 0:
		_fill_chunks(plan, span_periods, chunk_periods)
	return plan


## Whether `offers` events is over the budget for a span of `span_periods` at `place`,
## pushing an error that names all three when it is.
##
## **This is the fail-loudly half of ADR 0173 (b), and it returns rather than raises** so
## the caller can return refused in the same breath. A caller that would rather emit 300
## events than 4 is the defect; a caller that emits 4 and says nothing about the other
## 296 has hidden them from a player and from the ledger, which is monotone and cannot
## un-record what it was not told.
static func exceeds_budget(offers: int, place: StringName, span_periods: int) -> bool:
	if offers <= EVENT_BUDGET:
		return false
	push_error(
		(
			(
				"TimeLadder: %s was offered %d events over a span of %d periods, and the "
				+ "event budget is %d. The span says what became possible; the budget says "
				+ "how much of it happens. Refusing rather than truncating (ADR 0173)."
			)
			% [place, offers, span_periods, EVENT_BUDGET]
		)
	)
	return true


## The shipped shape as primitives only, so `tools ui drive` can print it and a test can
## assert on it without reaching into an authored array. The ratios come out as ints
## because that is how they are authored; a hand-edited float would have been refused by
## `ratio_for`, not quietly printed here.
static func summary() -> Dictionary:
	var names: Array[String] = []
	var ratios: Array[int] = []
	for row in magnitudes():
		names.append(str(row.get("name", "")))
		ratios.append(int(row.get("ratio_periods", 0)))
	return {
		"magnitudes": names.size(),
		"names": names,
		"ratios": ratios,
		"period_seconds": PERIOD_SECONDS,
		"event_budget": EVENT_BUDGET,
		"max_chunks": MAX_CHUNKS,
	}


## The one read of the shipped `.tres`, cached. Resolved by path rather than `preload`ed
## because the `.tres` binds THIS script and a compile-time reference to it from here is
## a load cycle; `RealmPowerTable` is loaded the other way round for the same reason.
static func _table_resource() -> TimeLadder:
	if _table == null:
		_table = load(TABLE_PATH) as TimeLadder
		if _table == null:
			push_error("TimeLadder: no table at %s — the clock has no magnitudes." % TABLE_PATH)
	return _table


## `total` periods split into pieces of at least `step`, counting a partial last piece as
## one whole. Integer arithmetic only: `ceili(total / float(step))` would round a
## 4.38e12-period span through a double and could land a chunk either side of the exact
## span, which is the `%`-on-a-float hazard `app/institution_resolver.gd:155-158` names.
static func _ceil_div(total: int, step: int) -> int:
	var whole := total / step
	return whole + (1 if total % step != 0 else 0)


## Fill `plan` with the chunk sizes for `span_periods`, or push an error naming the span
## and refuse when `chunk_periods` is not a positive count — the one input that cannot
## produce a plan at any count, so it fails rather than guessing one.
static func _fill_chunks(plan: PackedInt64Array, span_periods: int, chunk_periods: int) -> void:
	if chunk_periods <= 0:
		push_error(
			(
				(
					"TimeLadder: asked to chunk %d periods into pieces of %d periods — a "
					+ "chunk size must be a positive count. Refusing rather than guessing."
				)
				% [span_periods, chunk_periods]
			)
		)
		return
	var count := chunk_count_for(span_periods, chunk_periods)
	var whole := span_periods / count
	var remainder := span_periods % count
	for index in count:
		plan.append(whole + (1 if index < remainder else 0))
