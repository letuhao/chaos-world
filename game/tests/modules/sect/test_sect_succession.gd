extends TestCase

## **A succession is WALKED, never rolled** (ADR 0084, taking ADR 0058's ascension
## shape). One authored stage per call, a period between stages, and no `rng`
## anywhere in the path.
##
## Three ideas, in this order: the walk advances exactly one stage and refuses
## `walk_complete` on a second immediate call; the SAME walk produces the SAME result
## across a hundred fresh actors, which is the measurement that proves there is no
## generator behind it; and a method this module does not walk is refused by name
## rather than treated as an instantly-completed walk.

const FOUNDRY := &"t_foundry"
const HOUSE := &"t_house"
const STEWARD := &"t_steward"
const READER := &"t_reader"
const MEMBER := &"t_member"
const DOCTRINE := &"t_foundry_doctrine"
const SEAL := &"t_seal"
## How many fresh actors the determinism case walks. One hundred is two orders of
## magnitude past what an rng needs to differ, and it returns in milliseconds — a
## repetition count, not a proof.
const WALK_COUNT := 100


func setup() -> void:
	var board := SectFixtureCatalog.foundable_sect(FOUNDRY)
	# A second board whose top seat is filled by an appointment no walk reaches, so
	# the "not walkable" refusal has authored content to refuse.
	board.positions.append(
		SectFixtureCatalog.unwalkable_position(SEAL, SectPositionDef.SUCCESSION_INHERITED, 80)
	)
	SectFixtureCatalog.install([board, SectFixtureCatalog.rival_sect()])
	SectFixtureCatalog.install_doctrine([SectFixtureCatalog.doctrine(DOCTRINE)])


func teardown() -> void:
	SectFixtureCatalog.teardown()


## A member of the sect as a succession case needs one: sworn, at the cap, and
## holding the seat whose walk is under test.
func _member(actor_id: StringName) -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	SectApi.attach(actor)
	SectApi.join(actor, FOUNDRY)
	SectApi.move_standing(actor, 100)
	SectApi.promote(actor, STEWARD, true)
	return actor


func _def() -> SectDef:
	return SectCatalog.instance().sect_definition(FOUNDRY)


## The walk as a fingerprint: everything about it that a caller could observe.
func _walk_of(actor: Actor, position_id: StringName = STEWARD) -> Dictionary:
	var office := _def().position(position_id)
	var row := SectSuccession.walk(SectApi.state(actor), position_id)
	return {
		"side": String(row.get("side", "")),
		"stage": SectSuccession.walked_of(SectApi.state(actor), office),
		"complete": bool(row.get("complete", false)),
		"periods": int(row.get("held_periods", 0)),
	}


# --- The authored content wave: three walks and nothing else -----------------


## The content wave authors exactly `heir`, `trial` and `appointed`, and the set of
## walks is a MEMBERSHIP test rather than a "not one of the refusals" test — so a
## method nobody authored cannot become an instantly-completed walk by omission.
##
## `contest` is deliberately absent: nothing can call it until a tournament exists, and
## an authored-but-unreachable method is dead content.
func test_the_authored_walks_are_heir_trial_and_appointed_and_contest_is_not_one() -> void:
	# Sorted as TEXT, and deliberately so: `SUCCESSION_STAGES` is authored content
	# whose declaration order is the author's, so the set of walks is compared as the
	# canonically-ordered list every other `*_ids()` in this repo returns rather than
	# as a dictionary's key order. `Array[StringName].sort()` sorts on the interned
	# pointer, not the text, so the ids are converted before sorting — otherwise the
	# order is whatever the string table happened to intern them in.
	var authored: Array[String] = []
	for method in SectPositionDef.SUCCESSION_STAGES.keys():
		authored.append(String(method))
	authored.sort()
	assert_eq(
		authored,
		[
			String(SectPositionDef.SUCCESSION_APPOINTED),
			String(SectPositionDef.SUCCESSION_HEIR),
			String(SectPositionDef.SUCCESSION_TRIAL),
		],
		"three walks, named exactly"
	)
	assert_eq(
		SectPositionDef.SUCCESSION_STAGES.has(&"contest"),
		false,
		"and `contest` is not one of them, because nothing can call it yet"
	)
	for method in [
		SectPositionDef.SUCCESSION_HEIR,
		SectPositionDef.SUCCESSION_TRIAL,
		SectPositionDef.SUCCESSION_APPOINTED,
	]:
		var office := SectFixtureCatalog.walkable_position(STEWARD, method)
		assert_eq(office.is_walkable_method(), true, "'%s' is a walk" % method)
		assert_eq(
			office.walk_length(), int(SectPositionDef.SUCCESSION_STAGES[method]), "of its length"
		)
		assert_eq(office.stages().size(), office.walk_length(), "and every stage is named")
	# The older authored values are refused by name rather than walked.
	for method in [
		SectPositionDef.SUCCESSION_SENIORITY,
		SectPositionDef.SUCCESSION_NAMED,
		SectPositionDef.SUCCESSION_INHERITED,
	]:
		var office := SectFixtureCatalog.unwalkable_position(STEWARD, method)
		assert_eq(office.is_walkable_method(), false, "'%s' is not a walk" % method)
		assert_eq(office.walk_length(), 0, "and has no length at all")
		assert_eq(office.stages().size(), 0, "and names no stage")
	# An office with no method at all is likewise not a walk. This is the case a
	# "not empty and not one of the refusals" check would let through.
	var blank := SectFixtureCatalog.walkable_position(STEWARD, SectPositionDef.SUCCESSION_TRIAL)
	blank.succession_method = &""
	assert_eq(blank.is_walkable_method(), false, "and so is an office that names no method")
	assert_eq(blank.succeeds_by_walk(), false, "which also cannot be a founder's seat")


# --- The walk: one stage per call --------------------------------------------


## **One call, one stage.** `trial` is the walk under test: three authored stages, so
## three `step` calls finish it and a fourth is refused `walk_complete`. Each call is
## asserted to have moved the walk by exactly one, which is the property ADR 0058's
## `ascend` has and a succession that jumped two stages would not.
func test_a_succession_is_walked_one_authored_stage_per_call() -> void:
	var actor := _member(&"keeper")
	var office := _def().position(STEWARD)
	assert_eq(office.succession_method, SectPositionDef.SUCCESSION_TRIAL, "the seat walks by trial")
	var length := office.walk_length()
	assert_eq(length, 3, "a trial is three authored stages")
	assert_eq(_walk_of(actor)["stage"], 0, "and nothing has been walked yet")

	# `open` is a stage of its own: there is no hidden starter verb, because one
	# would be an action that is not a stage (ADR 0058's `commit` has no counterpart).
	assert_eq(
		bool(SectApi.advance_succession(actor, STEWARD, &"open")["ok"]),
		true,
		"the seat goes vacant"
	)
	assert_eq(String(_walk_of(actor)["side"]), SectDef.SUCCESSION_VACANT, "and is recorded vacant")
	assert_eq(_walk_of(actor)["stage"], 0, "which is not yet a stage taken")

	for stage in length:
		# One `wait` per stage: a step reads the vacancy clock and may not hand in its
		# own waiting, so the period that admits the next stage is a separate action.
		# Passing `periods` to the `step` itself is exactly the walk-around the gate
		# `test_a_step_cannot_pay_for_its_own_waiting` exists to refuse.
		assert_eq(
			bool(SectApi.advance_succession(actor, STEWARD, &"wait", 1)["ok"]),
			true,
			"period %d passes" % stage
		)
		assert_eq(
			bool(SectApi.advance_succession(actor, STEWARD, &"step")["ok"]),
			true,
			"stage %d lands" % stage
		)
		assert_eq(_walk_of(actor)["stage"], stage + 1, "having walked exactly one more")
	assert_eq(bool(_walk_of(actor)["complete"]), true, "the walk is finished")
	assert_eq(String(_walk_of(actor)["side"]), SectDef.SUCCESSION_SEATED, "and the seat is seated")


## The refusal a second immediate call gets. `walk_complete` is the one reason for a
## finished walk, a seat that was never vacant and a method this module does not walk
## — they are one sentence to a player, and the ledger is byte-for-byte as found.
func test_a_second_immediate_call_is_refused_walk_complete_and_writes_nothing() -> void:
	var actor := _member(&"keeper")
	SectApi.advance_succession(actor, STEWARD, &"open")
	for _stage in _def().position(STEWARD).walk_length():
		SectApi.advance_succession(actor, STEWARD, &"wait", 1)
		SectApi.advance_succession(actor, STEWARD, &"step")
	var before := SectApi.state(actor)
	for attempt in 3:
		var refused := SectApi.advance_succession(actor, STEWARD, &"step", 9)
		assert_eq(bool(refused["ok"]), false, "attempt %d is refused" % attempt)
		assert_eq(
			String(refused["reason"]), SectApi.WALK_COMPLETE, "attempt %d names itself" % attempt
		)
		assert_eq(SectApi.state(actor), before, "attempt %d wrote nothing" % attempt)
	# A walk on a seat nobody vacated is the same sentence, and `no_such_walk` is
	# different: nothing has started, which is a caller mistake rather than a
	# finished thing.
	var fresh := _member(&"fresh")
	var idle := SectApi.state(fresh)
	var unopened := SectApi.advance_succession(fresh, STEWARD, &"step")
	assert_eq(String(unopened["reason"]), SectApi.NO_SUCH_WALK, "no walk has started")
	assert_eq(SectApi.state(fresh), idle, "and nothing was written")


## **Refuses a further step until a period elapses** (ADR 0084). `wait` is where the
## period lands — nothing here reads `Time`, because nothing in this module owns a
## clock (DEF-0111), and a ledger counting periods from a timestamp would make a
## save's contents depend on when it was written.
func test_a_walk_refuses_a_further_step_until_a_period_elapses() -> void:
	var actor := _member(&"keeper")
	var office := _def().position(STEWARD)
	assert_eq(office.succession_periods, 1, "the seat waits one period")
	SectApi.advance_succession(actor, STEWARD, &"open")
	# A step asked for in the same breath as the opening is refused, and the refusal
	# reports both counts so a panel can render the wait rather than just name it.
	var too_soon := SectApi.advance_succession(actor, STEWARD, &"step")
	assert_eq(bool(too_soon["ok"]), false, "the vacancy has not aged")
	assert_eq(String(too_soon["reason"]), SectApi.PERIOD_NOT_ELAPSED, "and it names the rule")
	assert_eq(int(too_soon["required"]), 1, "reporting what a period costs")
	assert_eq(int(too_soon["actual"]), 0, "and how long it has waited")
	assert_eq(_walk_of(actor)["stage"], 0, "so nothing was walked")
	assert_eq(int(_walk_of(actor)["periods"]), 0, "and no period elapsed either")
	# A period, handed in by the caller that owns time.
	assert_eq(
		bool(SectApi.advance_succession(actor, STEWARD, &"wait", 1)["ok"]), true, "a period passes"
	)
	assert_eq(int(_walk_of(actor)["periods"]), 1, "and the vacancy has aged by one")
	var landed := SectApi.advance_succession(actor, STEWARD, &"step")
	assert_eq(bool(landed["ok"]), true, "so the stage lands")
	assert_eq(_walk_of(actor)["stage"], 1, "having walked exactly one")
	# And it refuses again straight away, which is the whole rule: a succession is
	# walked one stage per PERIOD, not one stage per second.
	var again := SectApi.advance_succession(actor, STEWARD, &"step")
	assert_eq(String(again["reason"]), SectApi.PERIOD_NOT_ELAPSED, "the next stage waits too")
	assert_eq(_walk_of(actor)["stage"], 1, "and still nothing walked")


## A seat authored to wait two periods waits two. The clock is authored content, not
## a constant buried in the verb, so a culture that refuses to fill an empty seat in
## a hurry gets to say so in a `.tres`.
func test_the_vacancy_periods_are_authored_on_the_office_and_read_from_there() -> void:
	var board := SectFixtureCatalog.foundable_sect(FOUNDRY)
	var slow := SectFixtureCatalog.walkable_position(
		STEWARD, SectPositionDef.SUCCESSION_HEIR, 60, 1, 2, 0.0
	)
	board.positions[2] = slow
	SectFixtureCatalog.install([board])
	SectFixtureCatalog.install_doctrine([SectFixtureCatalog.doctrine(DOCTRINE)])
	var actor := _member(&"keeper")
	SectApi.advance_succession(actor, STEWARD, &"open")
	var first := SectApi.advance_succession(actor, STEWARD, &"step")
	assert_eq(String(first["reason"]), SectApi.PERIOD_NOT_ELAPSED, "one period is not two")
	assert_eq(int(first["required"]), 2, "reporting the authored wait")
	SectApi.advance_succession(actor, STEWARD, &"wait", 1)
	var still_soon := SectApi.advance_succession(actor, STEWARD, &"step")
	assert_eq(
		String(still_soon["reason"]),
		SectApi.PERIOD_NOT_ELAPSED,
		"and one period of two still waits"
	)
	SectApi.advance_succession(actor, STEWARD, &"wait", 1)
	assert_eq(bool(SectApi.advance_succession(actor, STEWARD, &"step")["ok"]), true, "two is")


## **`periods` cannot buy a `step` its own waiting** (ADR 0084). The argument that
## advances the vacancy clock belongs to `open` and `wait`; on a `step` it was
## accepted as though it were the clock, so `periods=9` satisfied `may_step` outright
## and took a stage in the same breath — a walk with no pacing in it at all, reached
## by one argument. This pins the gate as a gate: the step reads the LEDGER, refuses
## `period_not_elapsed` when the clock is short, and writes nothing when it does.
func test_a_step_cannot_pay_for_its_own_waiting() -> void:
	var actor := _member(&"keeper")
	var office := _def().position(STEWARD)
	SectApi.advance_succession(actor, STEWARD, &"open")
	var before := SectApi.state(actor)
	for periods in [1, 8, 9, 99]:
		var refused := SectApi.advance_succession(actor, STEWARD, &"step", periods)
		assert_eq(bool(refused["ok"]), false, "periods=%d does not open the gate" % periods)
		assert_eq(
			String(refused["reason"]),
			SectApi.PERIOD_NOT_ELAPSED,
			"periods=%d names the rule" % periods
		)
		assert_eq(
			int(refused["required"]),
			maxi(0, office.succession_periods),
			"periods=%d still reports the authored wait" % periods
		)
		assert_eq(
			int(refused["actual"]), 0, "periods=%d is not counted as waiting either" % periods
		)
		assert_eq(SectApi.state(actor), before, "periods=%d wrote nothing" % periods)
	# The wait that DOES open it is `wait`, and only `wait`.
	assert_eq(
		bool(SectApi.advance_succession(actor, STEWARD, &"wait", 1)["ok"]), true, "one period"
	)
	assert_eq(
		bool(SectApi.advance_succession(actor, STEWARD, &"step")["ok"]), true, "and the stage lands"
	)
	assert_eq(_walk_of(actor)["stage"], 1, "having walked exactly one")


# --- No rng, anywhere --------------------------------------------------------


## **There is no `rng` in this path, and the walk is a pure function of the ledger.**
##
## This is the measurement ADR 0084 asks for. The identical walk is run against a
## hundred FRESH actors — new claim, new projection, new trail — and every one of
## them must land on byte-identical results. A single roll anywhere in the chain
## would show up as a difference; a seeded generator reused across actors would show
## up too, because the seed advances per call.
func test_the_walk_is_a_pure_function_of_the_ledger_across_a_hundred_fresh_actors() -> void:
	var expected: Dictionary = {}
	for attempt in WALK_COUNT:
		var actor := _member(StringName("walk_%d" % attempt))
		SectApi.advance_succession(actor, STEWARD, &"open")
		for _stage in _def().position(STEWARD).walk_length():
			SectApi.advance_succession(actor, STEWARD, &"wait", 1)
			SectApi.advance_succession(actor, STEWARD, &"step")
		# Everything a caller can observe about the finished walk, not just the
		# outcome: the seat, the whole persisted ledger, and the granted percent.
		var observed := {
			"walk": _walk_of(actor),
			"position": String(SectApi.state(actor)["position"]),
			"standing": int(SectApi.state(actor)["standing"]),
			"granted": SectProjection.contribution(actor, Stat.INSIGHT_GAIN),
		}
		if attempt == 0:
			expected = observed
			continue
		assert_eq(observed, expected, "actor %d walked identically to actor 0" % attempt)
	assert_eq(expected.is_empty(), false, "the loop really ran")
	assert_eq((expected["walk"] as Dictionary)["complete"], true, "and every one of them finished")
	assert_eq(int((expected["walk"] as Dictionary)["stage"]), 3, "at exactly the authored length")


## The complement: the SOURCE cannot contain a generator, even one that happens to
## produce the same number every time. ADR 0084 says a rolled succession "is a gate
## that can satisfy itself", so this is pinned the way the "grants no power" verb
## list is pinned — by reading the file rather than by trusting the behaviour.
func test_no_module_file_that_walks_a_succession_mentions_a_generator() -> void:
	for rel in [
		"res://src/modules/sect/api.gd",
		"res://src/modules/sect/sect_succession.gd",
		"res://src/modules/sect/sect_state.gd",
		"res://src/modules/sect/sect_position_def.gd",
	]:
		var body := FileAccess.get_file_as_string(rel)
		assert_ne(body, "", "%s is readable" % rel)
		for banned in ["rng", "RandomNumberGenerator", "randi(", "randf(", "randomize("]:
			assert_eq(
				_code_mentions(body, banned),
				false,
				"%s never mentions '%s'" % [rel.get_file(), banned]
			)


## Whether `needle` appears in EXECUTABLE text, ignoring the `##` prose around it.
## These three files each open with a section titled "There is no rng anywhere in this
## path" and then enumerate the very names this case bans — the documentation of the
## invariant is necessarily written in the forbidden vocabulary, so a raw
## `body.contains(...)` fails on the doc comment that PROVES the rule while the code
## beside it stays clean. The ban is about what the module EXECUTES, so comment lines
## are dropped before the scan.
func _code_mentions(body: String, needle: String) -> bool:
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains(needle):
			return true
	return false


## A corrupt save cannot ask for a walk of fifty thousand steps. `stage` is a COUNT
## clamped by `normalize`, and the walk itself clamps it again against the office's
## authored length — so a hand-edited ledger talks this module into nothing rather
## than into a long loop. AGENTS.md treats an unbounded loop as a disk hazard.
func test_a_corrupt_stage_count_is_clamped_and_never_iterated() -> void:
	var actor := _member(&"keeper")
	var tampered := SectApi.state(actor)
	(tampered["succession"] as Dictionary)[String(STEWARD)] = {
		"side": SectDef.SUCCESSION_VACANT,
		"stage": 5_000_000,
		"held_periods": 0,
		"complete": false,
	}
	actor.set_module_data(SectState.MODULE_KEY, tampered)
	SectApi.attach(actor)
	var normalized := SectApi.state(actor)
	var row := normalized["succession"][String(STEWARD)] as Dictionary
	assert_eq(int(row["stage"]), SectState.STAGE_LIMIT, "normalize clamps the count")
	assert_eq(
		SectSuccession.walked_of(normalized, _def().position(STEWARD)),
		_def().position(STEWARD).walk_length(),
		"and the walk clamps it again against the authored length"
	)
	# So the very next call is a finished walk rather than a long one.
	var refused := SectApi.advance_succession(actor, STEWARD, &"wait", 1)
	refused = SectApi.advance_succession(actor, STEWARD, &"step")
	assert_eq(String(refused["reason"]), SectApi.WALK_COMPLETE, "so the walk is over, not long")
	assert_eq(
		SectApi.state(actor)["succession"][String(STEWARD)]["stage"],
		SectState.STAGE_LIMIT,
		"and a refusal wrote nothing"
	)


# --- Every other refusal, named ----------------------------------------------


func test_every_succession_refusal_is_named_and_writes_nothing() -> void:
	var stranger := Actor.new(&"nobody")
	SectApi.attach(stranger)
	var idle := SectApi.state(stranger)
	# Standing needs a membership: a walk is an act of an institution.
	assert_eq(
		String(SectApi.advance_succession(stranger, STEWARD, &"open")["reason"]),
		SectApi.NOT_A_MEMBER,
		"an unaffiliated actor cannot walk anything"
	)
	assert_eq(SectApi.state(stranger), idle, "and writes nothing")
	# A sect this build does not ship, and an office that sect does not author.
	var actor := _member(&"keeper")
	var before := SectApi.state(actor)
	assert_eq(
		String(SectApi.advance_succession(actor, &"t_no_such_office", &"open")["reason"]),
		SectApi.UNKNOWN_POSITION,
		"an unshipped office walks nothing"
	)
	# `unknown_sect` is not the second argument transposed: `advance_succession` takes
	# no sect id at all — it reads the sect off the caller's own ledger. So an unshipped
	# sect is seeded into the ledger the way a save from a wider content build would
	# carry one, and the verb refuses it by name rather than reporting a bad office.
	var unshipped := SectApi.state(actor)
	unshipped["institution"] = "t_no_such_house"
	actor.set_module_data(SectState.MODULE_KEY, unshipped)
	SectApi.attach(actor)
	assert_eq(
		String(SectApi.advance_succession(actor, STEWARD, &"open")["reason"]),
		SectApi.UNKNOWN_SECT,
		"and neither does an unshipped sect"
	)
	# The rest of this case asks about a well-formed claim, so the unshipped sect is
	# put back rather than left in the ledger the remaining assertions read.
	unshipped["institution"] = String(FOUNDRY)
	actor.set_module_data(SectState.MODULE_KEY, unshipped)
	SectApi.attach(actor)
	# A method this module does not walk refuses as `walk_complete`: the seat's
	# succession is finished as far as a walk is concerned, whatever its culture
	# actually does about it. Naming it as anything else would promise a walk that
	# cannot be taken.
	assert_eq(
		String(SectApi.advance_succession(actor, SEAL, &"open")["reason"]),
		SectApi.WALK_COMPLETE,
		"an inherited seat has no walk to take"
	)
	assert_eq(
		String(SectApi.advance_succession(actor, SEAL, &"step", 4)["reason"]),
		SectApi.WALK_COMPLETE,
		"and stepping one is refused the same way"
	)
	assert_eq(SectApi.state(actor), before, "none of the three wrote anything")


## The walk is published through `summary()` rather than behind a thirteenth method,
## and it spells ADR 0083's middle state out: an empty seat reads `vacant: true`,
## never `0` and never a hidden row, because a succession that renders an unfilled
## seat as nothing has destroyed the design that made the vacancy legible.
func test_the_walk_is_read_from_summary_and_a_vacancy_is_a_visible_row() -> void:
	var actor := _member(&"keeper")
	var seated := SectApi.summary(actor)["can_promote"][String(STEWARD)] as Dictionary
	assert_eq(String(seated["succession"]["method"]), "trial", "the method is authored content")
	assert_eq(int(seated["succession"]["stages"]), 3, "with its authored length")
	assert_eq(int(seated["succession"]["walked"]), 0, "and how far it has walked")
	assert_eq(bool(seated["succession"]["vacant"]), false, "a filled seat is not vacant")

	SectApi.advance_succession(actor, STEWARD, &"open")
	SectApi.advance_succession(actor, STEWARD, &"wait", 1)
	# `periods_held` is the clock the NEXT stage waits on, so it is read while a
	# stage is still owed. The step below spends the period the walk needed, which is
	# what makes "one stage per period" true for every stage rather than the first.
	var aged := SectApi.summary(actor)["can_promote"][String(STEWARD)]["succession"] as Dictionary
	assert_eq(int(aged["periods_held"]), 1, "and one period has passed")
	SectApi.advance_succession(actor, STEWARD, &"step")
	var vacant := SectApi.summary(actor)["can_promote"][String(STEWARD)]["succession"] as Dictionary
	assert_eq(bool(vacant["vacant"]), true, "an empty seat is visible")
	assert_eq(int(vacant["walked"]), 1, "one stage taken")
	assert_eq(int(vacant["periods_held"]), 0, "and that stage spent the period it was waiting for")
	# The office the ledger knows nothing about is still a visible row, reporting
	# zero of everything rather than being omitted — an authored seat is never a
	# hidden one.
	var unopened := SectApi.summary(actor)["can_promote"][String(READER)] as Dictionary
	assert_eq(unopened.has("succession"), true, "every authored office reports its walk")
	assert_eq(
		bool(unopened["succession"]["vacant"]), false, "an office nobody vacated is not vacant"
	)


## `is_open` marks begun-not-finished: the seam a reported `already_open`
## refusal reads (Slice 8a — the re-open reset lives in `sect/api.gd`, outside
## this slice, so this pins the predicate the one-line edit asks, not the gate
## itself). A finished walk is closed, which is why the contract's `wait` on one
## refuses `walk_complete` rather than ageing a seat that is seated.
func test_is_open_marks_a_begun_unfinished_walk() -> void:
	var actor := _member(&"keeper")
	var idle := SectApi.state(actor)
	assert_eq(SectSuccession.is_open(idle, STEWARD), false, "nothing has started")
	SectApi.advance_succession(actor, STEWARD, &"open")
	assert_eq(SectSuccession.is_open(SectApi.state(actor), STEWARD), true, "the walk is open")
	for _stage in _def().position(STEWARD).walk_length():
		SectApi.advance_succession(actor, STEWARD, &"wait", 1)
		SectApi.advance_succession(actor, STEWARD, &"step")
	assert_eq(
		SectSuccession.is_open(SectApi.state(actor), STEWARD), false, "a finished walk is closed"
	)
