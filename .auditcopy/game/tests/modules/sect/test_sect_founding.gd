extends TestCase

## **Founding is priced, is a first entry in a ledger rather than a special case,
## and every refusal writes nothing at all** (BL-0174, BL-0190, BL-0191).
##
## The whole case list is four ideas: the authored cost is consumed, the founder is
## seated in the top office and recorded as a plain actor-id string, the treasury is
## a ledger of obligation lines rather than a pile of items, and each named refusal
## leaves `actor.module_data` byte-for-byte as found.

const FOUNDRY := &"t_foundry"
const HOUSE := &"t_house"
const STEWARD := &"t_steward"
const READER := &"t_reader"
const DOCTRINE := &"t_foundry_doctrine"
## The authored `founding_cost` of `t_foundry`, read off the definition rather than
## written down here. A case that asserted "25 of silver" against a number the
## content owns would be asserting the fixture, not the rule.
const COST := 25
## What one office of `t_foundry` publishes per period into the treasury, again read
## off the def where the assertions need it.
const STEWARD_DUTY := 1


func setup() -> void:
	var board := SectFixtureCatalog.foundable_sect(FOUNDRY)
	SectFixtureCatalog.install([board])
	SectFixtureCatalog.install_doctrine([SectFixtureCatalog.doctrine(DOCTRINE)])


func teardown() -> void:
	SectFixtureCatalog.teardown()


## A founder as a founder is: a member of the sect, sitting in the top office, and
## holding enough in the founding pool to pay for the institution.
func _founder(actor_id: StringName = &"keeper", funds: float = 1000.0) -> Actor:
	var actor := _member(actor_id)
	actor.add_resource(ResourcePool.new(SectFounding.FUNDING_POOL, funds))
	return actor


## An ordinary actor with the pools a lesson spends, because founding itself needs
## none and a case that handed one anyway would not prove the price was real.
func _member(actor_id: StringName) -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	actor.add_resource(ResourcePool.new(&"stamina", 100.0))
	SectApi.attach(actor)
	return actor


func _def() -> SectDef:
	return SectCatalog.instance().sect_definition(FOUNDRY)


func _cost() -> int:
	return int(SectFounding.cost(_def())["outstanding"])


# --- The refusal set ---------------------------------------------------------


## Every refusal names itself and writes NOTHING. Each case re-reads the ledger and
## the pool afterwards and compares both to what was found — ADR 0084's "a refused
## verb leaves the ledger byte-for-byte as found" is the guarantee, and a refusal
## that quietly charged the founder would be the failure this whole list exists for.
func test_every_founding_refusal_is_named_and_writes_nothing() -> void:
	# `no_actor`: there is nobody to found anything for.
	assert_eq(
		String(SectApi.found(null, FOUNDRY, DOCTRINE, "nobody")["reason"]),
		SectApi.NO_ACTOR,
		"a null actor"
	)

	var pauper := _founder(&"pauper", 0.0)
	var pauper_before := SectApi.state(pauper)
	var unaffordable := SectApi.found(pauper, FOUNDRY, DOCTRINE, "pauper")
	assert_eq(
		String(unaffordable["reason"]),
		SectApi.FOUNDING_COST_UNMET,
		"an empty founding fund is refused by name"
	)
	assert_eq(int(unaffordable["required"]), _cost(), "reporting what founding costs")
	assert_eq(int(unaffordable["actual"]), _cost(), "and what was in hand")
	assert_eq(SectApi.state(pauper), pauper_before, "and not one point was taken")
	assert_eq(SectFounding.funds(pauper), 0.0, "the pool is exactly as it was")

	var actor := _founder()
	var before := SectApi.state(actor)
	# `unknown_sect`: a sect nothing defines teaches nothing and grants nothing.
	assert_eq(
		String(SectApi.found(actor, &"t_no_such_house", DOCTRINE, "keeper")["reason"]),
		SectApi.UNKNOWN_SECT,
		"a sect this build does not ship"
	)
	# `unknown_doctrine`: a doctrine nothing defines teaches nothing either.
	assert_eq(
		String(SectApi.found(actor, FOUNDRY, &"t_no_such_doctrine", "keeper")["reason"]),
		SectApi.UNKNOWN_DOCTRINE,
		"a doctrine this build does not ship"
	)
	assert_eq(SectApi.state(actor), before, "neither refusal wrote a thing")
	assert_eq(SectFounding.funds(actor), 1000.0, "and neither charged for asking")

	# The cost is met, so this is the founding that works — and a second one is the
	# last refusal. The tiers are peers (ADR 0083), so an actor founds one sect.
	assert_eq(bool(SectApi.found(actor, FOUNDRY, DOCTRINE, "keeper")["ok"]), true, "founded")
	var sworn := SectApi.state(actor)
	assert_eq(
		String(SectApi.found(actor, FOUNDRY, DOCTRINE, "keeper")["reason"]),
		SectApi.ALREADY_FOUNDED,
		"a second founding is refused by name"
	)
	assert_eq(SectApi.state(actor), sworn, "and wrote nothing")
	assert_eq(
		SectFounding.funds(actor), 1000.0 - float(_cost()), "and charged nothing for the refusal"
	)


## A refusal must not be able to be bought. `force` is deliberately absent from
## `found` — there is no override that lets an actor found a sect they cannot afford,
## because BL-0174 prices an institution's existence and an override would make the
## price decorative. Pinned structurally, like the "grants no power" verb list.
func test_founding_publishes_no_override_and_the_cost_has_no_escape_hatch() -> void:
	var published: Array[String] = []
	for method in (load("res://src/modules/sect/api.gd") as GDScript).get_script_method_list():
		var name: String = method["name"]
		if not name.begins_with("_") and not published.has(name):
			published.append(name)
	assert_eq(published.has("force_found"), false, "there is no forced founding")
	# And the refusal reports a currency rather than a raw number, so a panel renders
	# the price in the coin the author wrote.
	var actor := _founder(&"pauper", 1.0)
	var verdict := SectApi.found(actor, FOUNDRY, DOCTRINE, "pauper")
	assert_eq(String(verdict["currency"]), "silver", "the authored currency is carried through")
	assert_eq(verdict.has("force"), false, "and no override is offered with it")


# --- The founder is the first entry in the sect's own ledger -----------------


## The founder is a plain actor-id STRING in the ledger and the first row of the
## roster — not a special case, and emphatically not an `Actor`. An `Actor` in a
## ledger reaches the save untouched: `Actor.to_dict` copies `module_data` verbatim
## with a hook only for items, so an object here would break every round trip with no
## checker in this repo able to see it.
func test_the_founder_is_a_plain_actor_id_string_and_the_first_entry_in_the_roster() -> void:
	var actor := _founder()
	SectApi.found(actor, FOUNDRY, DOCTRINE, "keeper")
	var ledger := SectApi.state(actor)
	assert_eq(
		SectApi.state(actor)[SectState.FOUNDER_KEY] as String, "keeper", "the founder is a string"
	)
	assert_eq(
		typeof(ledger[SectState.FOUNDER_KEY]), TYPE_STRING, "and it is a String, not an id object"
	)
	assert_eq(
		SectState.roster(ledger)[String(STEWARD)] as Array,
		["keeper"],
		"the founder is the first and only entry in the top office's roster"
	)
	assert_eq(SectState.founder(ledger), "keeper", "and the accessor reads it back")
	# The whole ledger survives `Actor.to_dict` / `from_dict` verbatim, which is the
	# test an `Actor` reference could not pass.
	var restored := Actor.from_dict(actor.to_dict())
	assert_eq(
		SectState.founder(restored.get_module_data(SectState.MODULE_KEY)),
		"keeper",
		"and it survives a payload round trip as a string"
	)


## The founder is seated in the TOP office — the one a succession can actually
## reach — and nowhere else. This is the whole of BL-0174's "one founder at the top
## position", and the office is found by CONTENT (the highest walkable floor) rather
## than by an array index, because ADR 0083 says a position is an id and never a
## ladder position.
func test_founding_seats_the_founder_in_the_top_office_and_the_price_is_consumed() -> void:
	var actor := _founder(&"rich", 500.0)
	var verdict := SectApi.found(actor, FOUNDRY, DOCTRINE, "rich")
	assert_eq(bool(verdict["ok"]), true, "the founding landed")
	var ledger := SectApi.state(actor)
	assert_eq(String(ledger["institution"]), String(FOUNDRY), "sworn to the sect they founded")
	assert_eq(String(ledger["position"]), String(STEWARD), "seated in the top office")
	assert_eq(String(ledger["doctrine"]), String(DOCTRINE), "teaching the named doctrine")
	assert_eq(SectFounding.funds(actor), 500.0 - float(_cost()), "and the cost came off the fund")
	# The founder is a plain claim: no award of standing out of thin air, and no
	# position inferred from standing. `FOUNDER_REFUND_STANDING` is a named constant
	# because charging the founder again for standing inside their own sect would
	# make the price of existing an infinite regress.
	assert_eq(int(ledger["standing"]), SectState.FOUNDER_REFUND_STANDING, "standing is the refund")
	assert_eq(
		int(ledger["standing"]),
		int(ledger["standing_cap"]),
		"and it is the whole authored cap, never a percent of one"
	)
	assert_eq(_def().top_position().id, STEWARD, "the top office is the walkable one")
	# The projection follows: the top office carries an allowlist, so the founder is
	# granted the bounded percent and nothing else (ADR 0084).
	assert_almost_eq(
		SectProjection.contribution(actor, Stat.INSIGHT_GAIN),
		InstitutionClaim.standing_percent(int(ledger["standing"])),
		"the founder is granted exactly the recognition their standing earned"
	)


## A sect whose only offices name appointments a succession never walks cannot be
## founded, because seating a founder in such a seat is not a thing its culture
## does. That is `no_top_position`: a content answer, named as one.
func test_a_sect_with_no_walkable_office_refuses_founding_with_no_top_position() -> void:
	var closed := SectFixtureCatalog.sect(
		&"t_closed_house",
		[SectFixtureCatalog.unwalkable_position(&"t_holder", SectPositionDef.SUCCESSION_NAMED)]
	)
	SectFixtureCatalog.install([closed])
	SectFixtureCatalog.install_doctrine([SectFixtureCatalog.doctrine(&"t_closed_doctrine")])
	assert_eq(closed.has_top_position(), false, "the sect authors no walkable top")
	var actor := _founder()
	var before := SectApi.state(actor)
	var verdict := SectApi.found(actor, &"t_closed_house", &"t_closed_doctrine", "keeper")
	assert_eq(String(verdict["reason"]), SectApi.NO_TOP_POSITION, "so founding is refused by name")
	assert_eq(SectApi.state(actor), before, "and writes nothing")
	assert_eq(SectFounding.funds(actor), 1000.0, "and charges nothing")


# --- The treasury is a ledger of obligation lines ----------------------------


## **A treasury is a ledger, never a pile of items** (BL-0191). Every line is a
## plain id and a count — so retuning a rate never rewrites a save — and every line
## is namespaced through the sect id, because the ledger belongs to a person and two
## sects may both owe the same actor's save.
func test_the_treasury_is_a_ledger_of_obligation_lines_and_never_a_pile_of_items() -> void:
	var actor := _founder()
	SectApi.found(actor, FOUNDRY, DOCTRINE, "keeper")
	var treasury := SectApi.state(actor)["treasury"] as Dictionary
	# `assert_eq(actual, expected)` in this framework — and an "is it there" check is
	# an equality against false, not `assert_ne(x.is_empty(), false)`, which reads as
	# "an empty treasury is the surprising answer". Written the plain way so the
	# assertion and its label say the same thing.
	assert_eq(treasury.is_empty(), false, "founding opens a treasury")
	var expected := SectFounding.treasury_lines(_def())
	assert_eq(treasury, expected, "every line is authored, and only those lines")
	for line_id in treasury.keys():
		assert_eq(typeof(line_id), TYPE_STRING, "a treasury line id is a String key")
		assert_eq(typeof(treasury[line_id]), TYPE_INT, "and holds a count, never an amount")
		assert_eq(int(treasury[line_id]) > 0, true, "and only a positive one is stored")
	# The lines the vault of each office opens are the office's OWN authored rates,
	# read off the def — a case asserting a hard-coded count would be asserting the
	# fixture rather than the rule.
	assert_eq(
		int(treasury["treasury_%s_duty_%s" % [String(FOUNDRY), String(STEWARD)]]),
		_def().position(STEWARD).duty_per_period,
		"the top office's duty line carries its own authored rate"
	)
	assert_eq(int(treasury["treasury_%s_hall" % String(FOUNDRY)]), 1, "and the hall opens one line")
	# Nothing in here is an item, a stat, or a quantity of anything a `ResourcePool`
	# would have been the right home for.
	for line_id in treasury.keys():
		assert_eq(
			(treasury[line_id] is Dictionary) or (treasury[line_id] is Array),
			false,
			"'%s' is a count on a line, never a nested store" % line_id
		)


## A line belonging to some OTHER sect is dropped rather than carried. Two sects
## share one actor's ledger and neither may see the other's dues — an author who
## hand-wrote a foreign line into a save has written a debt nobody here can settle.
func test_a_treasury_line_from_another_sect_is_dropped_rather_than_kept() -> void:
	var actor := _founder()
	SectApi.found(actor, FOUNDRY, DOCTRINE, "keeper")
	var tampered := SectApi.state(actor)
	(tampered["treasury"] as Dictionary)["treasury_t_rival_house_door"] = 4
	actor.set_module_data(SectState.MODULE_KEY, tampered)
	SectApi.attach(actor)
	assert_eq(
		(SectApi.state(actor)["treasury"] as Dictionary).has("treasury_t_rival_house_door"),
		false,
		"a foreign treasury line is dropped"
	)
	assert_eq(
		(SectApi.state(actor)["treasury"] as Dictionary).has("treasury_%s_hall" % String(FOUNDRY)),
		true,
		"and this sect's own line survives"
	)


## The founding obligation is authored by the content, stacked — the membership rate
## plus the top office's own. It is never invented by the verb, because a rate the
## code wrote down is a rate an author cannot retune.
func test_founding_opens_the_authored_member_and_office_obligation_lines() -> void:
	var actor := _founder()
	SectApi.found(actor, FOUNDRY, DOCTRINE, "keeper")
	var obligation := SectApi.state(actor)["obligation"] as Dictionary
	assert_eq(obligation.is_empty(), false, "a founder owes something")
	assert_eq(
		obligation["duty_%s" % String(FOUNDRY)],
		SectDef.MEMBER_DUTY_PERIODS,
		"the membership rate is the sect's own constant"
	)
	assert_eq(
		obligation["duty_%s" % String(STEWARD)],
		_def().position(STEWARD).duty_per_period,
		"and the top office opens its own duty line"
	)
	assert_eq(SectApi.summary(actor)["settled"], false, "so the claim is not settled on day one")


# --- Roster and authored capacity (BL-0176) ---------------------------------


## **An overflow is a REFUSED ADMIT and never a silent trim** (BL-0174, ADR 0084).
## The roster is the founder's ledger, so a case fills it and then asks for one more
## member than the office authors — the answer names the room and the size of the
## roster is byte-for-byte what it was.
func test_a_capacity_overflow_refuses_named_capacity_full_and_leaves_the_roster_unchanged() -> void:
	var actor := _founder()
	SectApi.found(actor, FOUNDRY, DOCTRINE, "keeper")
	var ledger := SectApi.state(actor)
	# `t_reader` is authored at three. Two more members fit; the fourth does not.
	(ledger["roster"] as Dictionary)[String(READER)] = ["second", "third"]
	actor.set_module_data(SectState.MODULE_KEY, ledger)
	SectApi.attach(actor)
	var filled := SectApi.state(actor)
	assert_eq(
		(filled["roster"] as Dictionary)[String(READER)] as Array,
		["second", "third"],
		"three of three"
	)
	assert_eq(_def().position(READER).capacity, 3, "and the office authors exactly three")
	var before := SectApi.state(actor)
	var fourth := "fourth"
	# Nothing on the facade admits a member into a roster — the roster is content
	# this slice writes, not a verb — so the refusal is asked of `seat_state`, which
	# is the ONE place `capacity_full` is decided and every caller must agree with it.
	var seat := _def().seat_state(READER, 3)
	assert_eq(bool(seat["has_room"]), false, "the fourth member does not fit")
	assert_eq(
		String(seat["reason"]), SectApi.CAPACITY_FULL, "and it is a shut room, not a succession"
	)
	assert_eq(SectApi.state(actor), before, "the ledger is byte-for-byte as found")
	assert_eq(
		(SectApi.state(actor)["roster"] as Dictionary)[String(READER)] as Array,
		["second", "third"],
		"and nobody was trimmed to make room"
	)
	assert_eq(
		SectApi.summary(actor)["roster"][String(STEWARD)] as Array,
		["keeper"],
		"the founder kept their seat"
	)


## `summary()` is the read model, so the roster lives there and NOT behind a
## thirteenth facade method (ADR 0083). A member's own count is published per office
## beside the authored capacity and the live seat state, so a board screen renders
## the whole thing in one call.
func test_the_roster_is_published_through_summary_and_not_behind_its_own_method() -> void:
	var actor := _founder()
	SectApi.found(actor, FOUNDRY, DOCTRINE, "keeper")
	var read := SectApi.summary(actor)
	assert_eq(bool(read["founded"]), true, "the summary knows this member founded something")
	assert_eq(String(read["founder_id"]), "keeper", "and names the founder")
	assert_eq(read["roster"][String(STEWARD)] as Array, ["keeper"], "with the roster")
	assert_eq(int(read["roster"]["size"]), 1, "and its size")
	var office := read["can_promote"][String(STEWARD)] as Dictionary
	assert_eq(int(office["held"]), 1, "the top office counts its own holder")
	assert_eq(
		String(office["reason"]),
		SectApi.SEAT_OCCUPIED,
		"and a seat of one that somebody holds is `seat_occupied`, not `capacity_full`"
	)
	# The same office after the founder leaves. `leave` closes the claim, so there is
	# no longer a sect whose offices `summary()` could publish — `can_promote` is
	# built from the SWORN sect's authored positions, and an unaffiliated member has
	# none. A closed claim holds no roster and names no founder, which is the state
	# ADR 0083's first tier is supposed to be able to return to at all.
	SectApi.leave(actor)
	var after_leaving := SectApi.summary(actor)
	assert_eq(bool(after_leaving["is_member"]), false, "a founder who left is sworn to nothing")
	assert_eq(String(after_leaving["founder_id"]), "", "and is no longer a founder")
	assert_eq(int(after_leaving["standing"]), 0, "having lost the standing the sect gave")
	assert_eq(after_leaving["roster"] as Dictionary, {}, "a closed claim holds no roster")
	assert_eq(after_leaving["can_promote"] as Dictionary, {}, "and publishes no board at all")


# --- Persistence -------------------------------------------------------------


## A founding ledger — doctrine, roster, treasury, obligation lines, founder id and
## all — round trips through `Actor.to_dict` and a JSON hop. Every inner key is a
## `String`, because `Actor.to_dict` converts only the OUTER `module_data` key and a
## `StringName` in here would reach the save untouched (ADR 0084).
func test_a_ledger_carrying_doctrine_fit_and_obligation_lines_survives_a_json_hop() -> void:
	var actor := _founder()
	SectApi.found(actor, FOUNDRY, DOCTRINE, "keeper")
	var ledger := SectApi.state(actor)
	# Fit is written directly rather than through `teach`, so this case is about the
	# save shape and nothing else; the teaching suite proves the verb that writes it.
	var with_fit := ledger.duplicate(true)
	(with_fit["fit"] as Dictionary)[String(DOCTRINE)] = 40
	actor.set_module_data(SectState.MODULE_KEY, with_fit)
	SectApi.attach(actor)
	ledger = SectApi.state(actor)

	for container in ["obligation", "fit", "treasury", "roster"]:
		for key in (ledger[container] as Dictionary).keys():
			assert_eq(typeof(key), TYPE_STRING, "%s inner key is a String" % container)
	assert_eq(SectState.fit(ledger, DOCTRINE), 40, "the fit is in the ledger")

	var parsed = JSON.parse_string(JSON.stringify(actor.to_dict()))
	assert_ne(parsed, null, "the payload is JSON-safe")
	var restored := Actor.from_dict(parsed as Dictionary)
	SectApi.attach(restored)
	var after := SectApi.state(restored)
	for field in [
		"version",
		"institution",
		"position",
		"standing",
		"standing_cap",
		"doctrine",
		SectState.FOUNDER_KEY,
	]:
		assert_eq(after[field], ledger[field], "'%s' survives the hop" % field)
	assert_eq(after["obligation"], ledger["obligation"], "and the obligation lines")
	assert_eq(after["treasury"], ledger["treasury"], "and the treasury")
	assert_eq(after["roster"], ledger["roster"], "and the roster")
	assert_eq(SectState.fit(after, DOCTRINE), 40, "and the fit")
	for container in ["obligation", "treasury", "roster"]:
		for key in (after[container] as Dictionary).keys():
			assert_eq(typeof(key), TYPE_STRING, "%s key is a String after the hop" % container)
	assert_eq(String(SectState.founder(after)), "keeper", "and the founder came back as a string")
