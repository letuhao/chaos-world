extends TestCase

## ADR 0137's five facts that had a real owner, for the two `sect` owns:
## `sect_post_held` and `oaths_discharged`. Before this, `SectApi.promote` wrote a
## position and nothing recorded that a post was HELD, and `InstitutionClaim.owe` /
## `.settle` had zero production callers — so `summary()["settled"]` was permanently
## false for every member in the game and no `duty_owed` gate could ever be described
## as anything but shut.
##
## ## What these hold
##
##   - a fact is recorded when the action SUCCEEDS, and not at all when it is refused;
##   - a fact is recorded ONCE per occurrence, so a re-read, a re-promotion into the
##     seat already held, and a second settlement of a cleared line all record nothing;
##   - the writer takes its id from a same-file `const` named AT the call, which is the
##     only spelling `tools gate_reach.py` resolves (see `SectFacts`).
##
## ## What they do NOT hold
##
## No test here asserts a fact is AMBIENT. These ids are produced by the act and by
## nothing else; a world roster reporting them would be the gate's demand echoed back
## (ADR 0137) and would falsify
## `tests/app/test_world_ambient_facts.gd`'s
## `test_a_fact_the_world_never_reports_is_still_outstanding`.

const HOUSE := &"t_house"
const MEMBER := &"t_member"
const STEWARD := &"t_steward"
const ARCHIVIST := &"t_archivist"


func setup() -> void:
	(
		SectFixtureCatalog
		. install(
			[
				(
					SectFixtureCatalog
					. sect(
						HOUSE,
						[
							SectFixtureCatalog.bare_position(MEMBER),
							SectFixtureCatalog.seat(STEWARD, 60),
							SectFixtureCatalog.wide_position(ARCHIVIST, 2, 40),
						],
						100,
						0
					)
				)
			]
		)
	)


func teardown() -> void:
	SectFixtureCatalog.teardown()


func _member(actor_id: StringName = &"keeper") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	SectApi.attach(actor)
	return actor


## A sworn member with enough standing to sit the steward seat, which is the act under
## test here — a promotion that refuses records nothing, which is half of what the
## `sect_post_held` cases below are measuring.
func _seated(actor_id: StringName = &"keeper") -> Actor:
	var actor := _member(actor_id)
	SectApi.join(actor, HOUSE)
	SectApi.move_standing(actor, 100)
	return actor


# --- sect_post_held ------------------------------------------------------------


func test_seating_somebody_records_that_a_post_was_held() -> void:
	var actor := _seated()
	assert_eq(WorldFact.count(actor, SectFacts.FACT_POST_HELD), 0, "nothing held yet")

	var promoted := SectApi.promote(actor, STEWARD)

	assert_eq(bool(promoted["ok"]), true, "the promotion landed")
	assert_eq(
		WorldFact.count(actor, SectFacts.FACT_POST_HELD),
		1,
		"and the world was told a post was held, exactly once"
	)


func test_a_refused_promotion_records_no_post_held() -> void:
	var actor := _member()
	SectApi.join(actor, HOUSE)
	# Standing zero against the steward's authored floor of 60: `standing_below_floor`,
	# and the actor does not exist as a member of any office yet.
	var refused := SectApi.promote(actor, STEWARD)

	assert_eq(String(refused["reason"]), SectApi.STANDING_BELOW_FLOOR, "the floor refused it")
	assert_eq(
		WorldFact.count(actor, SectFacts.FACT_POST_HELD),
		0,
		"a refused verb writes nothing at all, the ledger of the world included (ADR 0084)"
	)


func test_a_forced_promotion_records_the_post_held_too() -> void:
	# `force` opens BOTH halves of the override, so a political admit is still a seat
	# taken — the world does not know which promotions were earned.
	var actor := _member()
	SectApi.join(actor, HOUSE)
	var forced := SectApi.promote(actor, STEWARD, true)

	assert_eq(bool(forced["ok"]), true, "the council overruled the room")
	assert_eq(WorldFact.count(actor, SectFacts.FACT_POST_HELD), 1, "and the seat is still a seat")


func test_repromoting_into_the_seat_already_held_records_nothing_a_second_time() -> void:
	# "You held a post" is a TRANSITION. A monotone ledger that recorded the no-op would
	# answer "how many posts have you held" with "how many times were you told again".
	var actor := _seated()
	SectApi.promote(actor, STEWARD)
	assert_eq(WorldFact.count(actor, SectFacts.FACT_POST_HELD), 1, "the seat was taken once")

	for repeat in 3:
		SectApi.promote(actor, STEWARD)
		assert_eq(
			WorldFact.count(actor, SectFacts.FACT_POST_HELD),
			1,
			"repeat %d told the actor again and recorded nothing" % repeat
		)


func test_a_second_office_is_a_second_post_held() -> void:
	var actor := _seated()
	SectApi.promote(actor, STEWARD)
	SectApi.promote(actor, ARCHIVIST)
	assert_eq(
		WorldFact.count(actor, SectFacts.FACT_POST_HELD),
		2,
		"two posts really were held, and two is the honest count"
	)


func test_founding_seats_the_founder_and_records_the_post_held() -> void:
	# `found` puts the founder in the top office, so a gate asking whether the post was
	# held and answering "yes for everybody the house promoted, no for the one who made
	# it" would be reporting politics rather than fact.
	SectFixtureCatalog.install_doctrine()
	var actor := _member(&"founder")
	actor.add_resource(ResourcePool.new(SectFounding.FUNDING_POOL, 100.0))
	var founded := SectApi.found(
		actor, HOUSE, SectFixtureCatalog.default_sect().doctrine_id, "founder"
	)

	assert_eq(bool(founded["ok"]), true, "the sect came into being")
	assert_eq(
		String(SectApi.state(actor)["position"]),
		String(SectFixtureCatalog.default_sect().top_position().id),
		"and the founder is seated in its top office"
	)
	assert_eq(WorldFact.count(actor, SectFacts.FACT_POST_HELD), 1, "so a post was held, once")


func test_a_refused_founding_records_no_post_held() -> void:
	SectFixtureCatalog.install_doctrine()
	var actor := _member(&"founder")
	# No funding pool at all, so `founding_cost_unmet`: a refused founding must leave the
	# world's memory exactly as found.
	var refused := SectApi.found(
		actor, HOUSE, SectFixtureCatalog.default_sect().doctrine_id, "founder"
	)

	assert_eq(bool(refused["ok"]), false, "the price was not met")
	assert_eq(WorldFact.count(actor, SectFacts.FACT_POST_HELD), 0, "and no seat was taken")


func test_reading_the_claim_never_records_a_post_held() -> void:
	# The acceptance case for "recorded once, not per-read": a summary is the read every
	# panel makes on every frame, and a producer on that path would inflate forever.
	var actor := _seated()
	SectApi.promote(actor, STEWARD)
	var before := WorldFact.count(actor, SectFacts.FACT_POST_HELD)
	for cycle in 5:
		SectApi.summary(actor)
		SectApi.state(actor)
		SectApi.attach(actor)
		SectApi.gate(actor, {"verb": &"holds_position", "position": STEWARD})
	assert_eq(
		WorldFact.count(actor, SectFacts.FACT_POST_HELD),
		before,
		"cycle 0..4 of reading and re-attaching records nothing"
	)


# --- oaths_discharged ----------------------------------------------------------


func test_serving_clears_the_membership_duty_and_records_one_oath() -> void:
	var actor := _member()
	SectApi.join(actor, HOUSE)
	var claim := SectState.claim(SectApi.state(actor))
	assert_eq(claim.settled(), false, "a fresh member owes the membership duty")
	var duty_term := StringName("duty_%s" % String(HOUSE))

	var served := SectDuty.serve(actor, 1)

	assert_eq(bool(served["ok"]), true, "a period of service landed")
	assert_eq(int(served["discharged"]), 1, "and one sworn term was discharged in full")
	assert_eq(SectState.claim(SectApi.state(actor)).owed(duty_term), 0, "the line is clear")
	assert_eq(WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED), 1, "recorded once")


func test_the_summary_settles_only_because_something_discharges_it() -> void:
	# The live balance bug, stated as an assertion: before `SectDuty` existed this read
	# `false` for every member of every sect in the game, permanently.
	var actor := _member()
	SectApi.join(actor, HOUSE)
	assert_eq(
		bool(SectApi.summary(actor)["settled"]), false, "a member with an open line is not settled"
	)
	SectDuty.serve(actor, 32)
	assert_eq(
		bool(SectApi.summary(actor)["settled"]),
		true,
		"and serving the institution in full is what makes it so"
	)


func test_serving_again_records_nothing_when_nothing_is_owed() -> void:
	var actor := _member()
	SectApi.join(actor, HOUSE)
	SectDuty.serve(actor, 32)
	var before := WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED)
	assert_ne(before, 0, "the first service discharged something")

	for cycle in 3:
		var refused := SectDuty.serve(actor, 4)
		assert_eq(
			String(refused["reason"]), SectDuty.R_NOTHING_OWED, "cycle %d owes nothing" % cycle
		)
		assert_eq(
			WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED),
			before,
			"and records nothing: a line that is already clear is not an oath discharged"
		)


func test_a_partial_payment_records_nothing_and_keeps_the_line() -> void:
	# `join` opens BOTH authored lines: `duty_<sect>` at
	# `SectDef.MEMBER_DUTY_PERIODS` and `instruction_<sect>` at the sect's
	# `min_purity`. This case is about ONE line of THREE paid with ONE, so the map
	# is REBUILT with only that line — otherwise the `duty` line crosses zero
	# alongside it and the case passes for the wrong reason, measuring "a 1-period
	# line cleared" instead of "a 3-period line did not".
	#
	# Rebuilt, never erased in place: `erase` while walking `keys()` mutates the
	# container being iterated, and the two other fact cases in this file read the
	# same ledger shape, so an in-place edit leaked into them.
	#
	# The ledger is written AFTER `attach`, deliberately. `attach` normalizes what it
	# finds and persists the normalized copy, so an edit made before it is re-derived
	# from the skeleton and the line never opens — which reads as "the fixture did
	# not take" rather than as "the edit was in the wrong place".
	var actor := _member()
	SectApi.join(actor, HOUSE)
	var ledger := SectApi.state(actor)
	ledger["obligation"] = {"instruction_%s" % String(HOUSE): 3}
	actor.set_module_data(SectState.MODULE_KEY, ledger)

	var before := WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED)

	var served := SectDuty.serve(actor, 1)

	assert_eq(bool(served["ok"]), true, "a period of service landed")
	assert_eq(
		WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED),
		before,
		"a term reduced is not a term DISCHARGED, so nothing is recorded"
	)
	assert_eq(
		SectState.claim(SectApi.state(actor)).owed(StringName("instruction_%s" % String(HOUSE))),
		2,
		"and the line still owes what it did not clear"
	)


func test_a_term_is_recorded_exactly_once_on_the_period_that_clears_it() -> void:
	var actor := _member()
	SectApi.join(actor, HOUSE)
	var ledger := SectApi.state(actor)
	# The obligation map is REBUILT with only the line under test, and written AFTER
	# `attach` (which `_member` already did) — see the case above for both reasons.
	ledger["obligation"] = {"instruction_%s" % String(HOUSE): 3}
	actor.set_module_data(SectState.MODULE_KEY, ledger)
	var before := WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED)

	SectDuty.serve(actor, 1)
	SectDuty.serve(actor, 1)
	var cleared := SectDuty.serve(actor, 1)

	assert_eq(int(cleared["discharged"]), 1, "the third period cleared the line")
	assert_eq(
		WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED),
		before + 1,
		"and three payments of one period are ONE oath discharged, not three"
	)


func test_serving_nothing_is_refused_and_records_nothing() -> void:
	var actor := _member()
	SectApi.join(actor, HOUSE)
	var before := WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED)

	for periods in [0, -1]:
		var refused := SectDuty.serve(actor, periods)
		assert_eq(
			String(refused["reason"]), SectDuty.R_NO_PERIODS, "%d periods is a mistake" % periods
		)
	assert_eq(
		WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED),
		before,
		"a settlement that was never asked for records nothing"
	)


func test_serving_is_refused_for_somebody_sworn_to_nothing() -> void:
	var actor := _member()
	assert_eq(
		String(SectDuty.serve(actor, 4)["reason"]),
		SectDuty.R_NOT_A_MEMBER,
		"an unaffiliated member owes nothing to anybody"
	)
	assert_eq(WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED), 0, "and records nothing")


# --- the promotion opens what the seat obliges ---------------------------------


func test_taking_a_seat_opens_the_offices_own_obligation_lines() -> void:
	# `SectGate`'s `duty_owed` verb asks about a term the office itself authors. Founding
	# has always opened them for the founder; a promotion that did not would leave every
	# office holder reading zero debt, which is a gate answering `yes` to everybody.
	var actor := _seated()
	var office := SectCatalog.instance().sect_definition(HOUSE).position(STEWARD)
	# Authored at a rate the fixture does not use anywhere else, so the assertion is about
	# the office's own number rather than about a coincidental one.
	office.duty_per_period = 3
	var term := StringName("duty_%s" % String(STEWARD))

	SectApi.promote(actor, STEWARD)

	assert_eq(
		SectState.claim(SectApi.state(actor)).owed(term),
		3,
		"the seat's own duty is now owed at the office's authored rate"
	)


func test_the_duty_owed_gate_now_has_something_to_refuse() -> void:
	var actor := _seated()
	var office := SectCatalog.instance().sect_definition(HOUSE).position(STEWARD)
	office.duty_per_period = 1
	var term := StringName("duty_%s" % String(STEWARD))

	SectApi.promote(actor, STEWARD)
	var shut := SectApi.gate(actor, {"verb": &"duty_owed", "term": term, "need": 0})
	assert_eq(bool(shut["ok"]), false, "a gate needs a positive bar, so this is malformed")
	SectDuty.serve(actor, 1)
	var open := SectApi.gate(actor, {"verb": &"duty_owed", "term": term, "need": 1})
	assert_eq(bool(open["ok"]), true, "and serving the term is what opens the door the gate names")
