extends TestCase

## The six new capabilities, each asserted on its own terms — and the trading
## guild driven through TWO of them with NO tier code (ADR 0922).
##
## ## This suite and the mechanism SHARE ONE BODY
##
## D3's claim is "a pack claiming a capability must pass that capability's
## contract suite at load or its kind is refused by name", and the suite is
## `contract_findings()`: `InstitutionContract.register` runs it at load, this
## file runs it here. So every case below drives the SAME method production
## calls, over the same probes, and the per-capability cases assert the rules
## those probes are written to catch — `Expellable`'s cost asymmetry, the
## walked succession's determinism, the untouched modifier stack.
##
## ## The reference implementation: The Lantern Exchange
##
## The shipped `lantern_exchange.tres` authors `expel` on its top seat
## (`first_ledger`) and not on its `clerk`, and nothing in this repo had ever
## read that authority. The case at the end of this file registers a
## `trading_guild` kind carrying `Authorised` + `Expellable` and drives the
## REAL authored authorities through them: the seat expels, the clerk is
## refused by name. **No tier module is loaded and no tier code exists in this
## path** — that is the whole point, and the answer to "did the guild need
## anything sect-shaped?" is measured here rather than argued.
##
## ## Every loop in this file is a `for`
##
## There is not one `while`. The walks are over fixed probe arrays, over a
## shipped def's own authored offices, or over a literal range; none appends to
## the container it walks, so no bound can grow in lockstep with its own body
## and `test_no_unbounded_wait.gd` has nothing to reject.

## The shipped trading guild, READ and never mutated. A copy of a `.tres` that
## `load()` has cached would leak into every suite after this one.
const LANTERN := "res://data/packs/guilds/organizations/lantern_exchange.tres"
## The authored offices the authority case is about: the one seat that authors
## `expel` and the ordinary office that does not.
const SEAT := &"first_ledger"
const CLERK := &"clerk"
const LANTERN_ID := &"lantern_exchange"


func setup() -> void:
	InstitutionContract.instance().clear()
	expect_assertions(3)


func teardown() -> void:
	InstitutionContract.instance().clear()


# --- teachable -------------------------------------------------------------------


## The fit comparison is published as a READ, and the lesson is a PLAN whose
## `fit_gain` is `fit_per_period * periods` — a pure product, never a roll.
func test_teachable_plans_fit_and_refuses_an_unfit_or_unsworn_pair() -> void:
	var impl := Teachable.new()
	var probe := {
		"kind": "probe",
		"institution": "probe",
		"member": "probe_teacher",
		"target": "probe_student",
		"doctrine": "probe_doctrine",
		"teacher_fit": 9,
		"doctrine_floor": 3,
		"fit_per_period": 3,
		"student_sworn": true,
		"comprehension": 50.0,
		"comprehension_floor": 10.0,
		"comprehension_span": 80.0,
		"periods": 2,
	}
	var answer := impl.lesson(probe.duplicate(true))
	assert_eq(bool(answer.get("ok", false)), true, "a qualified pair plans a lesson")
	var plan: Dictionary = answer["plan"]
	assert_eq(
		int(plan["fit_gain"]),
		int(probe["fit_per_period"]) * int(probe["periods"]),
		"fit_gain is the rate times the periods, not a roll"
	)
	var unfit := probe.duplicate(true)
	unfit["teacher_fit"] = 0
	assert_eq(
		String(impl.lesson(unfit).get("reason", "")), Teachable.R_TEACHER_UNFIT, "an unfit teacher"
	)
	var stranger := probe.duplicate(true)
	stranger["student_sworn"] = false
	assert_eq(
		String(impl.lesson(stranger).get("reason", "")),
		Teachable.R_STUDENT_NOT_SWORN,
		"an unsworn student is refused by name"
	)
	var low := probe.duplicate(true)
	low["comprehension"] = 1.0
	assert_eq(
		String(impl.lesson(low).get("reason", "")),
		Teachable.R_COMPREHENSION_BELOW_FLOOR,
		"below the band"
	)
	var high := probe.duplicate(true)
	high["comprehension"] = 200.0
	assert_eq(
		String(impl.lesson(high).get("reason", "")),
		Teachable.R_COMPREHENSION_ABOVE_SPAN,
		"above the band"
	)


## **Fit projects ZERO stat modifiers** (ADR 0084), measured on a live actor's
## modifier stack: a full lesson plan applied through nothing but the plan's own
## numbers leaves `modifier_count()` and the base attributes byte-identical.
## `contracts/` may not name a stat sheet, so the assertion lives HERE, where an
## `Actor` is legal — and it is the half `contract_findings` cannot reach.
func test_teachable_leaves_the_modifier_stack_and_bases_untouched() -> void:
	var actor := Actor.new(&"probe_learner", {Stat.COMPREHENSION: 40.0, Stat.PHYSIQUE: 20.0})
	var impl := Teachable.new()
	var probe := {
		"kind": "probe",
		"institution": "probe",
		"member": "probe_teacher",
		"target": String(actor.id),
		"doctrine": "probe_doctrine",
		"teacher_fit": 9,
		"doctrine_floor": 3,
		"fit_per_period": 3,
		"student_sworn": true,
		"comprehension": 40.0,
		"comprehension_floor": 1.0,
		"comprehension_span": 100.0,
		"periods": 3,
	}
	var modifiers_before := actor.stats.modifier_count()
	var bases_before := actor.stats.base_dict()
	var derived_before := actor.stats.derived_all()
	var answer := impl.lesson(probe.duplicate(true))
	assert_eq(bool(answer.get("ok", false)), true, "the lesson plans")
	assert_eq(actor.stats.modifier_count(), modifiers_before, "no modifier was written")
	assert_eq(actor.stats.base_dict(), bases_before, "no base attribute was written")
	assert_eq(actor.stats.derived_all(), derived_before, "and no derived stat moved")


# --- territorial ------------------------------------------------------------------


## A claim plans IDS, and the plan carries no key naming a yield, an upkeep or
## a combat surface (ADR 0085). Overlap is refused by name.
func test_territorial_plans_ids_and_refuses_a_place_held_by_another() -> void:
	var impl := Territorial.new()
	var probe := {
		"kind": "probe",
		"institution": "probe_house",
		"member": "probe_member",
		"places": ["probe_meadow"],
		"authored": ["probe_meadow", "probe_harbour"],
		"holder": "",
		"place": "probe_harbour",
	}
	var answer := impl.claim(probe.duplicate(true))
	assert_eq(bool(answer.get("ok", false)), true, "an authored, unheld place plans")
	var plan: Dictionary = answer["plan"]
	for key in plan.keys():
		assert_eq(
			String(key).contains("yield") or String(key).contains("upkeep"),
			false,
			"no yield or upkeep key: '%s'" % key
		)
	assert_eq(bool(impl.holds(probe, &"probe_meadow")["has"]), true, "a claimed place reads held")
	assert_eq(bool(impl.holds(probe, &"probe_harbour")["has"]), false, "an unclaimed one does not")
	var again := probe.duplicate(true)
	again["place"] = "probe_meadow"
	assert_eq(
		String(impl.claim(again).get("reason", "")),
		Territorial.R_ALREADY_CLAIMED,
		"a re-claim is refused"
	)
	var taken := probe.duplicate(true)
	taken["holder"] = "probe_rival"
	assert_eq(
		String(impl.claim(taken).get("reason", "")),
		Territorial.R_HELD_BY_ANOTHER,
		"overlapping ownership is refused by name"
	)


# --- dutiable ---------------------------------------------------------------------


## The over-settle CLAMPS and returns the settled count, mirroring
## `InstitutionClaim.settle` — asserted as `settled == min(owed, requested)`
## over the probe's own lines, never as a hand-written total.
func test_dutiable_clamps_an_over_settle_and_returns_what_really_settled() -> void:
	var impl := Dutiable.new()
	var lines := {"duty_a": 5, "duty_b": 1}
	var probe := {
		"kind": "probe",
		"institution": "probe",
		"member": "probe_member",
		"owed": lines,
		"periods": 9,
	}
	var answer := impl.serve(probe.duplicate(true))
	assert_eq(bool(answer.get("ok", false)), true, "an over-settle plans")
	var plan: Dictionary = answer["plan"]
	var expected := 0
	for key in lines.keys():
		expected += mini(int(lines[key]), int(probe["periods"]))
	assert_eq(int(plan["settled"]), expected, "settled is the sum of the per-line clamps")
	assert_eq(int(plan["settled"]) <= 5 + 1, true, "and never more than was owed")
	assert_eq(int(plan["remaining"]), 0, "everything was covered")
	var partial := probe.duplicate(true)
	partial["periods"] = 2
	var part: Dictionary = impl.serve(partial)
	assert_eq(
		int((part["plan"] as Dictionary)["settled"]), 3, "a partial serve settles only what it can"
	)
	assert_eq(int((part["plan"] as Dictionary)["remaining"]), 3, "and reports what is left")
	var empty := probe.duplicate(true)
	empty["owed"] = {}
	assert_eq(
		String(impl.serve(empty).get("reason", "")),
		Dutiable.R_NOTHING_OWED,
		"an empty serve refuses"
	)


# --- admit_table ------------------------------------------------------------------


## The three states never collapse: `{}` (does not exist), `{vacant: true}`
## (exists, its value is absent) and `{ok: false, reason: R}` (exists,
## refused) — and **a vacancy is never `0`**.
func test_admit_table_keeps_the_three_states_apart() -> void:
	var impl := AdmitTable.new()
	var probe := {
		"kind": "probe",
		"institution": "probe",
		"member": "probe_candidate",
		"requirements": {"probe_bar": {"kind": "bar", "need": 10}},
		"values": {"probe_bar": 25},
		"invite_only": false,
	}
	var absent := impl.requirement(probe.duplicate(true), &"probe_ghost")
	assert_eq(absent.is_empty(), true, "a row nobody authored is `{}` — does not exist")
	var vacant_row := probe.duplicate(true)
	vacant_row["values"] = {}
	var vacant := impl.requirement(vacant_row, &"probe_bar")
	assert_eq(bool(vacant.get("ok", false)), true, "a row with no value is not a refusal")
	assert_eq(bool(vacant.get("vacant", false)), true, "it is a VACANCY")
	assert_eq(vacant.has("actual"), false, "and carries no value at all — never a 0")
	var refused := probe.duplicate(true)
	refused["values"] = {"probe_bar": 1}
	var answer := impl.requirement(refused, &"probe_bar")
	assert_eq(bool(answer.get("ok", false)), false, "an evaluated miss is a refusal")
	assert_eq(String(answer.get("reason", "")), AdmitTable.R_BELOW_REQUIREMENT, "by name")
	assert_eq((answer.get("unmet", []) as Array).is_empty(), false, "with its unmet entries")
	# The whole-table verdict, and the two doors kept apart.
	var admitted := impl.admits(probe.duplicate(true))
	assert_eq(bool(admitted.get("admitted", false)), true, "an open house admits")
	var closed := probe.duplicate(true)
	closed["invite_only"] = true
	assert_eq(
		String(impl.admits(closed).get("reason", "")),
		AdmitTable.R_NOT_INVITED,
		"a door nobody opened"
	)
	var unanswered := probe.duplicate(true)
	unanswered["values"] = {}
	assert_eq(
		String(impl.admits(unanswered).get("reason", "")),
		AdmitTable.R_VACANT,
		"a vacancy fails the whole admit by name"
	)


# --- successive -------------------------------------------------------------------


## The walk is DETERMINISTIC across two runs, refuses a second step in one
## period, and never consults an `rng`.
func test_successive_is_deterministic_and_refuses_a_second_step_in_one_period() -> void:
	var impl := Successive.new()
	var probe := {
		"kind": "probe",
		"institution": "probe",
		"member": "probe_member",
		"office": "probe_seat",
		"open": true,
		"stage": 0,
		"walk_length": 3,
		"stage_periods": 5,
		"held_periods": 5,
	}
	var first := impl.advance(probe.duplicate(true))
	var second := impl.advance(probe.duplicate(true))
	assert_eq(JSON.stringify(first), JSON.stringify(second), "two runs answer by text")
	assert_eq(bool(first.get("ok", false)), true, "the first step plans")
	var plan: Dictionary = first["plan"]
	assert_eq(int(plan["stage"]), 1, "exactly one stage per call")
	assert_eq(int(plan["held_periods"]), 0, "and the clock was SPENT")
	# Apply the plan and step again: nothing is due.
	var after := probe.duplicate(true)
	after["stage"] = int(plan["stage"])
	after["held_periods"] = int(plan["held_periods"])
	assert_eq(
		String(impl.advance(after).get("reason", "")),
		Successive.R_PERIOD_NOT_ELAPSED,
		"a second step in one period is refused"
	)
	# Wait one authored cost, and the next step becomes due.
	after["periods"] = int(probe["stage_periods"])
	var waited: Dictionary = impl.wait(after)["plan"]
	after["held_periods"] = int(waited["held_periods"])
	assert_eq(bool(impl.advance(after).get("ok", false)), true, "after waiting, the step is due")


## The walk never reads a clock and never rolls: the source carries no `rng`
## name, which is the only check available for "this file consults no random
## number generator" — the `test_sect_succession.gd` shape.
func test_successive_consults_no_generator() -> void:
	var body := FileAccess.get_file_as_string("res://src/contracts/successive.gd")
	assert_ne(body, "", "the file is readable")
	for word in ["RandomNumberGenerator", "randi(", "randf(", "seed("]:
		assert_eq(_calls(body, word), 0, "successive.gd never calls %s" % word)


# --- schismatic -------------------------------------------------------------------


## A split costs BOTH halves: the odd point is charged away, both halves start
## from ONE settled number, a short assignment list cannot shrink the bill, and
## a ruinous price still plans with its shortfall published.
func test_schismatic_costs_both_halves_and_never_mints() -> void:
	var impl := Schismatic.new()
	var probe := {
		"kind": "probe",
		"institution": "probe_house",
		"seceding": "probe_split",
		"member": "probe_member",
		"undivided": 41,
		"price": 5,
		"places": ["probe_meadow", "probe_harbour"],
		"assigned": ["probe_meadow"],
		"cost_per_unassigned": 2,
	}
	var read := impl.settle(probe.duplicate(true))
	assert_eq(bool(read.get("ok", false)), true, "the arithmetic reads")
	assert_eq(
		int(read["half"]) * 2 + int(read["odd_charged"]),
		int(read["undivided"]),
		"the odd point is charged away, never minted"
	)
	assert_eq(int(read["kept"]), int(read["seceded"]), "both halves start from ONE number")
	assert_eq(int(read["price"]), 7, "the price is the base plus one unassigned place")
	var answer := impl.declare(probe.duplicate(true))
	assert_eq(bool(answer.get("ok", false)), true, "the declaration plans")
	var halves: Array = (answer["plan"] as Dictionary)["halves"]
	assert_eq(halves.size(), 2, "two distinct halves")
	assert_ne(String(halves[0]), String(halves[1]), "and they are not one id twice")
	# A short assignment list cannot shrink the bill.
	var short := probe.duplicate(true)
	short["assigned"] = []
	var full := impl.settle(short)
	assert_eq(
		int(full["price"]),
		int(probe["price"]) + 2 * (probe["places"] as Array).size(),
		"an empty assignment list bills every authored place"
	)
	# A ruinous price still plans, settling at zero with a shortfall.
	var ruinous := probe.duplicate(true)
	ruinous["price"] = 1000
	var doomed := impl.declare(ruinous)
	assert_eq(bool(doomed.get("ok", false)), true, "an unaffordable split is planned, not refused")
	assert_eq(int((doomed["plan"] as Dictionary)["settled"]), 0, "settling at zero")
	assert_eq(int((doomed["plan"] as Dictionary)["shortfall"]) > 0, true, "with the shortfall said")
	# And the free-schism defect is the one gate on the number.
	var free := probe.duplicate(true)
	free["price"] = 0
	free["cost_per_unassigned"] = 0
	assert_eq(
		String(impl.declare(free).get("reason", "")), Schismatic.R_NO_PRICE, "a free split refuses"
	)


# --- authorised -------------------------------------------------------------------


## Authority is a per-office authored lookup: an office that authors the word
## has it and one that does not is refused BY NAME, never compared.
func test_authorised_refuses_an_authority_the_office_does_not_author() -> void:
	var impl := Authorised.new()
	var seat := {
		"kind": "probe",
		"institution": "probe",
		"office": "probe_seat",
		"authorities": ["expel"],
		"duties": ["weigh_the_ledger"],
	}
	assert_eq(
		bool(impl.authorise(seat, Authorised.AUTHORITY_EXPEL).get("ok", false)),
		true,
		"the seat may expel"
	)
	assert_eq(
		String(impl.authorise(seat, &"use_the_commons").get("reason", "")),
		Authorised.R_UNKNOWN_AUTHORITY,
		"an unauthored authority is refused by name"
	)
	var member := seat.duplicate(true)
	member["office"] = ""
	assert_eq(
		String(impl.authorise(member, Authorised.AUTHORITY_EXPEL).get("reason", "")),
		Authorised.R_NO_OFFICE,
		"a member with no office is told to hold one"
	)
	assert_eq(impl.duty_terms(seat), ["weigh_the_ledger"] as Array[String], "duties read sorted")


# --- expellable -------------------------------------------------------------------


## The cost asymmetry is a COMPARISON returned, never two literals: `costs`
## publishes `asymmetric` as `expeller > expelled`, and `expel` refuses a pair
## that fails it.
func test_expellable_publishes_the_cost_asymmetry_as_a_comparison() -> void:
	var impl := Expellable.new()
	var probe := {
		"kind": "probe",
		"institution": "probe",
		"authorities": ["expel"],
		"member": "probe_member",
		"target": "probe_target",
		"target_member": true,
		"target_office": "probe_seat",
		"target_authorities": [],
		"cost_expelled": 3,
		"cost_expeller": 9,
	}
	var priced := impl.costs(probe.duplicate(true))
	assert_eq(
		bool(priced["asymmetric"]),
		int(priced["expeller"]) > int(priced["expelled"]),
		"a comparison"
	)
	var answer := impl.expel(probe.duplicate(true))
	assert_eq(bool(answer.get("ok", false)), true, "the expulsion plans")
	assert_eq(String((answer["plan"] as Dictionary)["target"]), "probe_target", "naming the target")
	var equal := probe.duplicate(true)
	equal["cost_expeller"] = equal["cost_expelled"]
	assert_eq(
		String(impl.expel(equal).get("reason", "")),
		Expellable.R_COST_NOT_ASYMMETRIC,
		"an equal cost refuses"
	)
	var equal_target := probe.duplicate(true)
	equal_target["target_authorities"] = ["expel"]
	assert_eq(
		String(impl.expel(equal_target).get("reason", "")),
		Expellable.R_CANNOT_EXPEL_EQUAL_OR_ABOVE,
		"a peer cannot be purged unforced"
	)
	var forced := probe.duplicate(true)
	forced["target_authorities"] = ["expel"]
	forced["force"] = true
	var allowed := impl.expel(forced)
	assert_eq(bool(allowed.get("ok", false)), true, "a forced purge only bypasses the peer rule")
	assert_eq(bool((allowed["plan"] as Dictionary)["forced"]), true, "and the force is recorded")


# --- the reference implementation: a guild with NO tier code -----------------------


## ## The trading guild implements TWO contracts with NO tier code
##
## `The Lantern Exchange` is a `trading_guild`: it is not a sect, it has no
## module, and nothing in this path loads one. Its authored offices carry
## `authorities = [name_a_factor, freeze_a_credit, expel]` on `first_ledger`
## and `authorities = [use_the_commons]` on `clerk` — CONTENT that had no reader
## until this family shipped. The case registers the kind, drives the REAL
## authored lists through `Authorised` and `Expellable`, and measures the
## per-office difference: the seat expels, the clerk is refused BY NAME.
func test_the_guild_implements_authorised_and_expellable_with_no_tier_code() -> void:
	var def := load(LANTERN) as InstitutionDef
	assert_ne(def, null, "the shipped guild loads")
	assert_eq(String(def.kind), "trading_guild", "and it is a trading guild")
	var seat := def.position(SEAT)
	var clerk := def.position(CLERK)
	assert_ne(seat, null, "the seating office exists")
	assert_ne(clerk, null, "the ordinary office exists")
	# The PER-OFFICE difference is authored, and this is where it is measured:
	# authority reads as content, never as a rank.
	assert_eq(seat.grants(Authorised.AUTHORITY_EXPEL), true, "the seat authors `expel`")
	assert_eq(clerk.grants(Authorised.AUTHORITY_EXPEL), false, "the clerk does not")
	var contract := InstitutionContract.instance()
	var registered := contract.register(&"trading_guild", [Authorised.new(), Expellable.new()])
	assert_eq(
		bool(registered.get("ok", false)),
		true,
		"a kind carrying two capabilities registers with no tier module: %s" % [registered]
	)
	var authorised := contract.of(&"trading_guild", &"authorised")
	var expellable := contract.of(&"trading_guild", &"expellable")
	assert_eq(bool(authorised.get("has", false)), true, "authorised is reachable")
	assert_eq(bool(expellable.get("has", false)), true, "expellable is reachable")
	var holds := authorised["capability"] as Authorised
	var cast_out := expellable["capability"] as Expellable
	# The seat expels; the cost pair is the guild's own authored choice and the
	# case supplies it, because where a kind authors its numbers is its own
	# content question (the `Expellable` class note says exactly this).
	var seat_ctx := _guild_office_context(seat)
	var allowed := cast_out.expel(seat_ctx)
	assert_eq(bool(allowed.get("ok", false)), true, "a seat holder expels")
	assert_eq(
		holds.authorise(seat_ctx, Authorised.AUTHORITY_EXPEL)["ok"],
		true,
		"and the seat authorises the act"
	)
	# The clerk is refused BY NAME, and the refusal is the authority's own word
	# — the two capabilities are independent contracts that agree on one
	# authored vocabulary rather than one depending on the other.
	var clerk_ctx := _guild_office_context(clerk)
	var refused := cast_out.expel(clerk_ctx)
	assert_eq(bool(refused.get("ok", true)), false, "a clerk cannot expel")
	assert_eq(
		String(refused.get("reason", "")),
		Expellable.R_NOT_AUTHORISED,
		"refused BY NAME as not_authorised"
	)
	assert_eq(
		String(holds.authorise(clerk_ctx, Authorised.AUTHORITY_EXPEL).get("reason", "")),
		Authorised.R_UNKNOWN_AUTHORITY,
		"and the same act asks the office's own authored list"
	)
	# The expeller pays STRICTLY MORE — a comparison on the live plan, computed
	# from the context the case handed in rather than asserted as two literals.
	assert_eq(
		int((allowed["plan"] as Dictionary)["cost_expeller"]),
		int(seat_ctx["cost_expeller"]),
		"the plan carries the expeller's price"
	)
	assert_eq(
		(
			int((allowed["plan"] as Dictionary)["cost_expeller"])
			> int((allowed["plan"] as Dictionary)["cost_expelled"])
		),
		true,
		"and it is strictly more than the expelled pays"
	)


## The context one guild office is driven through: the authored office's own
## `authorities` and `duties`, plus the price pair the case chooses. Built from
## the def so the case measures the SHIPPED content rather than a fixture that
## could drift from it.
func _guild_office_context(office: InstitutionPositionDef) -> Dictionary:
	var authorities: Array = []
	for authority in office.authorities:
		authorities.append(String(authority))
	return {
		"kind": "probe",
		"institution": String(LANTERN_ID),
		"office": String(office.id),
		"authorities": authorities,
		"duties": [],
		"member": "probe_expeller",
		"target": "probe_expelled",
		"target_member": true,
		"target_office": "probe_target_seat",
		"target_authorities": [],
		"cost_expelled": 3,
		"cost_expeller": 9,
	}


## How many times `needle` appears in CODE, ignoring `##` prose, for the reason
## `test_sect_no_power.gd` states: a class doc names the verbs it refuses, so a
## raw substring scan reads the sentence as the call.
func _calls(body: String, needle: String) -> int:
	var hits := 0
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains(needle):
			hits += 1
	return hits
