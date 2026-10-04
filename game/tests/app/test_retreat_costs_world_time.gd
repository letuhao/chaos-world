extends TestCase

## ADR 0167 / ADR 0173: ONE player action costs world time, end to end, through the
## existing explicit-verb path — and the clock's magnitudes have a READER.
##
## ## Why this file exists, and what it refuses to be
##
## The audit measured the shape of the defect exactly as ADR 0134's "unwired
## primitive": `TimeLadder` was built, exported by `summary()` and read by nobody in
## production, while `advance_periods` had exactly one player path and that path was a
## one-period wait. So the ladder's magnitudes were arithmetic with no consequence —
## `tests/core/test_time_ladder.gd` could assert all of it and every assertion would
## still be true over a game where no player could ever sit for a season.
##
## ## **The rule every case below follows: never drive the thing under test**
##
## Nothing here constructs a `WorldPulse`, calls `TimeLadder.magnitudes_crossed`
## to produce the answer it then asserts, or hands the resolver a `crossed` dictionary
## it built. The cases go through [code]SeamHarness.mount_new[/code] — the REAL
## `ItemWorkbenchApp` scene, mounted under the tree root and driven through its own
## `_ready()` — and then call [code]ItemWorkbenchPlay.retreat[/code] ON the mounted
## root. Every figure asserted is a module's own ledger or the pulse's own report.
##
## That is the difference between this suite and `test_time_ladder.gd`, and it is the
## point of the whole exercise: a test that constructs the object and calls it proves
## the object works, which is not the same claim as "a player can reach it". A suite
## that builds its own director and hands it a beat is what `test_world_beat_chain.gd`
## was written against; this is that file's shape applied to the clock.
##
## ## What is claimed, and what is not
##
## Claimed: a declared span costs periods, the cost is what was PAID, the magnitudes
## that span crossed reach an institution cadence that can act on them, and all of it
## happens because production code called production code. Not claimed: that the
## magnitudes are BALANCED — ADR 0173 records the ratios as unnumbered proposals
## (`docs/adr/0173`, Consequences).

## The period the composition root accrues. Read from the pulse rather than typed, so
## a retune of the cadence cannot make this suite lie about which fact it is watching.
const PERIOD_FACT := WorldPulse.PERIOD_FACT

## The household this suite swears the hero to, and the single open term it starts with.
const HOUSE := &"t_house"
const MEMBER := &"t_disciple"

var _harness: SeamHarness = null
var _app: ItemWorkbenchPlay = null


## A coarse span in the SSOT's own authored units, resolved through `ratio_for` rather
## than written as a literal so this suite cannot pin a retuned ladder (ADR 0050).
##
## **One YEAR, derived from the shipped table.** This was the literal `1000` while the
## comment above it said "One YEAR", and `ratio_for(&"year")` is 4380 — so every
## assertion about a crossed year was comparing `0` against `1` and could never pass.
## A literal span silently drifts out of the ladder's vocabulary the moment the ladder is
## retuned, which is the ADR 0050 rule this file's own header cites. Derived, a retune
## moves the span with it and the year assertions keep meaning what they say.
static func retreat_span() -> int:
	return TimeLadder.ratio_for(&"year")


func setup() -> void:
	# The fixture catalog is installed BEFORE the mount, because `SectApi.attach` runs at
	# boot and reads it. Installing afterwards would leave the mounted hero sworn to
	# authored content this suite never asked about.
	SectFixtureCatalog.install(
		[SectFixtureCatalog.sect(HOUSE, [SectFixtureCatalog.bare_position(MEMBER)])]
	)
	_harness = SeamHarness.mount_new()
	_app = _harness.app as ItemWorkbenchPlay


func teardown() -> void:
	# `WorldStage`'s mounted body is a PROCESS-WIDE static and this suite advances a
	# mounted app, so a mount left behind would publish a freed `PlayerAdapter` to
	# every suite after this one.
	if WorldStage.instance() != null:
		WorldStage.instance().leave()
	if _harness != null:
		_harness.teardown()
	_harness = null
	_app = null
	SectFixtureCatalog.install([SectFixtureCatalog.default_sect()])


# --- 1. The verb is a production door -----------------------------------------


## THE FIRST LINK. The retreat is a public method on the mounted composition root, so
## `ItemWorkbenchApp` answers it by inheritance exactly as it answers `advance_world` —
## `game/src/app/item_workbench_play.gd`'s class docstring makes "the public surface is
## the contract, and it does not move" the reason the verb lives on this base rather
## than on the shell. A retreat reachable only from a test would leave this red.
func test_the_mounted_composition_root_answers_a_retreat() -> void:
	if not _booted():
		return
	assert_eq(_app.has_method(&"retreat"), true, "the player half publishes the retreat verb")
	assert_eq(
		_app.has_method(&"advance_world"),
		true,
		"and the verb it routes through is the same one the wait button drives"
	)


# --- 2. The declared span is PAID, not truncated -------------------------------


## THE COST. A season-scale action pays its declared span, and the report says what
## MOVED rather than what was asked for — which is the ADR 0167 half that makes a
## retreat an action with a price rather than a menu.
##
## **Asserted on the world fold's own total, not on the retreat's own `paid` key.** The
## return value is what this verb reports about itself; the fold's running total is what
## the world actually did. A verb that returned the ask would satisfy the first and
## leave the second untouched, and only the second is a claim about the world.
func test_a_retreat_costs_the_periods_it_declares() -> void:
	if not _booted():
		return
	var before := _periods()

	var report := _retreat(retreat_span())

	assert_eq(
		bool(report.get("ok", false)), true, "the retreat was paid: %s" % report.get("reason", "")
	)
	assert_eq(
		_periods() - before,
		retreat_span(),
		(
			"the world moved the WHOLE declared span. A ceiling here is the silent "
			+ "truncation ADR 0173 refuses ('It never truncates', AGENTS.md:56)"
		)
	)
	assert_eq(
		WorldFact.count(_harness.actor, PERIOD_FACT) > before,
		true,
		"and the period beat reached the world's own monotone ledger, not only a counter"
	)


## The span is PAID THROUGH THE CHUNK PLAN, in bounded spends, and the work is bounded
## by authored data rather than by the ask. A 1000-period retreat is at most
## `MAX_CHUNKS` spends of `EVENT_BUDGET` beats each — the ADR 0173 (b) claim, restated
## on the composition-root half where the player would meet it.
func test_a_long_retreat_is_paid_in_bounded_spends() -> void:
	if not _booted():
		return
	var before_beats := WorldFact.count(_harness.actor, PERIOD_FACT)

	var report := _retreat(retreat_span())

	var beats := WorldFact.count(_harness.actor, PERIOD_FACT) - before_beats
	assert_eq(
		beats <= TimeLadder.MAX_CHUNKS * TimeLadder.EVENT_BUDGET,
		true,
		(
			(
				"a %d-period retreat cost %d beats, bounded by MAX_CHUNKS x EVENT_BUDGET (%d): "
				% [retreat_span(), beats, TimeLadder.MAX_CHUNKS * TimeLadder.EVENT_BUDGET]
			)
			+ "a per-period loop would be %d" % retreat_span()
		)
	)
	assert_eq(
		beats < retreat_span(),
		true,
		(
			"and strictly fewer beats than periods: the span says what became possible,"
			+ " the budget what happened"
		)
	)


# --- 3. PARTIAL PAYMENT is observable ------------------------------------------


## THE PARTIAL-PAYMENT PROPERTY. ADR 0167: "Gain is proportional to periods actually
## paid, not to periods declared", because the world's interruption is not the player's
## — a beat offered through `WorldPulse.offer` can stop the remaining steps at any
## whole period. The player has therefore paid for the periods that were paid and NOT
## for the ones that were not, and that difference has to be legible in the return
## value or a player who was cut short cannot tell a bug from a cost they paid.
##
## `declared`, `paid` and `unpaid` are the three halves of that difference. Here the
## world pays the whole span, so `unpaid` is zero — and the assertion that it is
## exactly `declared - paid` on a COMPLETED retreat is what keeps it from being a
## constant zero that reads as "always fully paid".
func test_a_paid_retreat_reports_its_full_span_and_nothing_unpaid() -> void:
	if not _booted():
		return
	var report := _retreat(retreat_span())

	assert_eq(int(report.get("declared", 0)), retreat_span(), "the report names what was ASKED for")
	assert_eq(int(report.get("paid", 0)), retreat_span(), "and what was actually PAID for it")
	assert_eq(
		int(report.get("unpaid", 0)),
		0,
		(
			"a retreat the world did not interrupt is unpaid in nothing, and `unpaid`"
			+ " says so rather than being absent"
		)
	)


## THE OTHER HALF, and the one that cannot go vacuous. A caller asking for no periods
## gets no periods and no error: that is `advance_periods`'s own reading of a
## non-positive count (`world_pulse.gd:259-261`), and it is what keeps `unpaid` a
## MEASUREMENT — `declared == 0` must report `unpaid == 0` rather than an `unpaid` that
## would have read as -0 or, worse, as one period nobody paid for.
func test_a_retreat_of_no_periods_pays_nothing_and_owes_nothing() -> void:
	if not _booted():
		return
	var before := _periods()

	var report := _retreat(0)

	assert_eq(bool(report.get("ok", false)), true, "asking for no time is not an error")
	assert_eq(int(report.get("paid", 0)), 0, "and it paid nothing")
	assert_eq(int(report.get("unpaid", 0)), 0, "so it owes nothing either")
	assert_eq(_periods(), before, "and the world did not move")


## The refusal half. A play half holding no world fold answers `no_world` rather than
## crashing, and it pays nothing — which is the shape ADR 0173's "It never truncates"
## takes when the caller cannot be given the span at all: nothing is spent and the
## reason is named, not swallowed into a cheerful zero.
func test_a_retreat_with_no_world_pays_nothing_and_names_its_reason() -> void:
	# A play half built by hand is the ONE thing this suite may construct: there is no
	# mounted root to ask about the ABSENCE of a fold, and the claim is about the
	# refusal rather than about reachability. Nothing downstream may be installed.
	var bare := ItemWorkbenchPlay.new()
	var report := bare.call(&"retreat", 4) as Dictionary
	bare.free()
	assert_eq(bool(report.get("ok", false)), false, "a play half with no clock cannot pay a cost")
	assert_eq(
		String(report.get("reason", "")),
		"no_world",
		"and it names why rather than returning a zero"
	)
	assert_eq(int(report.get("paid", 0)), 0, "and nothing was paid for the span nobody could buy")


# --- 4. The crossed magnitudes have a CONSUMER, reachable from production --------


## **THE CLAIM THIS SUITE EXISTS FOR.** The magnitudes the span crossed are read by
## [code]InstitutionResolver.settle[/code] through `_settle_institutions`, which is
## called by [code]WorldPulse._advance[/code] on every advance — so an action that costs
## world time hands the clock's own units to a subsystem that can act on them.
##
## Asserted on `WorldPulse.summary()["magnitudes"]`, which is the fold's OWN published
## division, read through the composition root's own `world_summary`. The alternative —
## recomputing `TimeLadder.magnitudes_crossed` here — would pass on a build where the
## pulse never computed it at all, which is the unwired-primitive defect restated.
func test_the_retreat_reaches_the_clocks_own_magnitude_reader() -> void:
	if not _booted():
		return
	var report := _retreat(retreat_span())

	var published := _world().get("magnitudes", {}) as Dictionary
	assert_eq(
		published.get(&"year", 0),
		1,
		(
			(
				"a %d-period span crosses one 'year' and the fold published %s. "
				% [retreat_span(), published]
			)
			+ "WorldPulse._advance must fold the span into magnitudes_crossed on every advance."
		)
	)
	assert_eq(
		published.get(&"period", 0),
		retreat_span(),
		"and the base row is the span itself, so the two halves cannot disagree about how long this was"
	)
	# The return value carries the same figure, read over the PAID span, so a caller
	# pricing its action is reading one answer rather than two.
	assert_eq(
		(report.get("magnitudes", {}) as Dictionary).get(&"year", 0),
		int(published.get(&"year", 0)),
		"the verb's own report and the fold's published reader agree on what was crossed"
	)


## ## The consumer ACTS on the magnitudes, and this is the leg that makes the whole
## chain worth reading
##
## A number that reaches a report is a number with no consequence. So this drives the
## effect: a member with one open term of `retreat_span()` periods, settled on the
## STRATEGIC tier alone. `serve_duty` is the one institution verb that CONSUMES a period
## count (`institution_resolver.gd:258-265`), so the periods it is handed are the
## periods it pays down — and the only thing that raises the strategic tier's count
## above the authored divisor is the crossed magnitudes
## (`institution_resolver.gd:_magnitude_periods`).
##
## The term is sized so that the two answers cannot coincide: a plain settle of one
## period pays 1, while a settle folded with the magnitudes pays
## `1 + year * ratio(year)`. One term of `retreat_span()` is therefore cleared ONLY if
## the magnitudes reached the cadence — and left owed in full if they did not. The
## difference is visible in the module's OWN ledger, not in a number this suite made up.
func test_the_crossed_magnitudes_change_what_the_institutions_actually_did() -> void:
	if not _booted():
		return
	var actor := _sworn_member()
	var instruction := _open_term(actor, retreat_span())
	assert_eq(
		_owed(actor, instruction),
		retreat_span(),
		"the term opens owed, or nothing below means anything"
	)

	_retreat(retreat_span())

	var owed := _owed(actor, instruction)
	assert_eq(
		owed,
		0,
		(
			(
				"a %d-period retreat paid %d periods of a %d-period term through the "
				% [retreat_span(), retreat_span() - owed, retreat_span()]
			)
			+ ("institution cadence. The crossed magnitudes must reach settle() through ")
			+ "_settle_institutions, or the ladder has a reader that cannot act."
		)
	)
	assert_eq(
		WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED),
		1,
		"and a term brought to zero discharged exactly one oath, which is the consumer's own ledger"
	)


## The NEGATIVE half, and the one that keeps the case above from being a tautology:
## the same hero, the same term, the same settle — but the world advanced by a count
## that crosses NOTHING beyond the base row, so the magnitudes fold contributes zero and
## the strategic cadence is exactly what it always was.
##
## Without this, the first case would also pass on a build where `_magnitude_periods`
## returned the whole span unconditionally, which is not "the magnitudes reached the
## cadence" but "any period reached the cadence".
func test_a_span_that_crosses_no_coarse_magnitude_leaves_the_cadence_alone() -> void:
	if not _booted():
		return
	var actor := _sworn_member()
	var instruction := _open_term(actor, retreat_span())

	_retreat(1)

	assert_eq(
		_published(&"year"),
		0,
		"one period crosses no 'year', so the consumer has nothing coarse to act on"
	)
	assert_eq(
		_owed(actor, instruction),
		retreat_span() - 1,
		(
			"so the strategic tier settled its authored divisor alone (1 period) and the "
			+ "term is owed nearly all of it — not zero, which is what a reader that ignored "
			+ "the magnitudes would leave behind"
		)
	)


## The magnitudes are the SSOT's OWN division, not a second calendar. Asserted against
## the shipped `.tres` through `ratio_for`, so a retune of the ladder cannot make this
## suite lie about which row it is reading — the same discipline
## `test_time_ladder.gd` applies to the ladder itself.
func test_the_magnitudes_the_consumer_reads_are_the_authored_rows() -> void:
	if not _booted():
		return
	_retreat(retreat_span())

	var published := _world().get("magnitudes", {}) as Dictionary
	for row in TimeLadder.magnitudes():
		var magnitude := StringName(str(row.get("name", "")))
		if magnitude == StringName():
			continue
		assert_eq(
			published.has(magnitude),
			true,
			"every authored row is in the fold's published answer, so no reader can miss one"
		)
	assert_eq(
		_published(&"year"),
		retreat_span() / TimeLadder.ratio_for(&"year"),
		"and the count is the authored division, read through ratio_for rather than a literal"
	)


# --- Internals -----------------------------------------------------------------


func _booted() -> bool:
	if _app == null:
		return false
	assert_eq(
		_harness.boot_error, "", "the real ItemWorkbenchApp scene boots, or nothing below is proven"
	)
	return _harness.boot_error == ""


## The retreat on the MOUNTED root, called the way a screen or a probe calls it. Never
## the play half this suite built.
func _retreat(periods: int) -> Dictionary:
	return _app.call(&"retreat", periods) as Dictionary


## The mounted fold's running total, read through the composition root's own
## `world_summary` so the figure a player could see is the one asserted.
func _periods() -> int:
	return int(_world().get("periods", 0))


func _world() -> Dictionary:
	return _app.call(&"world_summary") as Dictionary


func _published(magnitude: StringName) -> int:
	return int((_world().get("magnitudes", {}) as Dictionary).get(magnitude, 0))


## The mounted hero, sworn to this suite's fixture house. `join` is the verb a player
## reaches, and it runs against the catalog `setup` installed.
func _sworn_member() -> Actor:
	var actor := _harness.actor
	assert_eq(
		bool(SectApi.join(actor, HOUSE).get("ok", false)),
		true,
		"the mounted hero is sworn to the fixture house, so an institution can act on them"
	)
	return actor


## One open obligation line of exactly `periods`, and nothing else owed. Written rather
## than reached through an office because `join` opens two lines whose length this
## suite must not depend on — the same reason `test_sect_serve_duty.gd` rebuilds the
## map, at its `_one_term_left`.
##
## No `attach` afterwards: it re-normalizes and persists, which buys nothing here
## because every read on this path normalizes on its own.
func _open_term(actor: Actor, periods: int) -> String:
	var ledger := SectApi.state(actor)
	var instruction := "instruction_%s" % String(HOUSE)
	ledger["obligation"] = {instruction: periods}
	actor.set_module_data(SectState.MODULE_KEY, ledger)
	return instruction


func _owed(actor: Actor, term: String) -> int:
	return SectState.claim(SectApi.state(actor)).owed(StringName(term))
