extends TestCase

## A requirement is **data, never code** (ADR 0076, ADR 0062). These assert the
## closed verb set, that a gate reads the ledger and never a derived stat — so an
## institution can never be *bought* past — and that an unknown verb refuses closed
## and names itself rather than quietly opening a door.
##
## The gate is also where `standing_below_floor` is reported as a route: the verdict
## carries both numbers so a caller can see how far short the member fell and decide
## what to do about it, which is the whole of ADR 0084's "a route, not a wall".

const HOUSE := &"t_house"
const STEWARD := &"t_steward"
const READER := &"t_reader"
## The office carrying the authored authorities this suite asks about. A fixture of
## its OWN rather than a second `t_steward`: an office is looked up by id, so two
## definitions of one id leave the answer to whichever the sect shipped last, and
## neither `SectDef.position` nor the catalog can say that a duplicate is a content
## bug. One office per id, everywhere.
const SEAL := &"t_seal"
const DOCTRINE := &"t_house_doctrine"


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
							SectFixtureCatalog.bare_position(&"t_member"),
							SectFixtureCatalog.seat(STEWARD, 60),
							SectFixtureCatalog.room(READER, 3, 20),
							SectFixtureCatalog.office_with_authority(
								SEAL, [&"hold_the_seal"], [&"teach", &"expel"]
							),
						],
						100,
						25
					)
				)
			]
		)
	)


func teardown() -> void:
	SectFixtureCatalog.teardown()


func _member(standing: int = 0, position: StringName = &"") -> Actor:
	var actor := Actor.new(&"keeper", {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	SectApi.attach(actor)
	SectApi.join(actor, HOUSE)
	if position != &"":
		SectApi.promote(actor, position, true)
	if standing > 0:
		SectApi.move_standing(actor, standing)
	return actor


## Every entry the verdict shape promises, so a panel can render a reason it did not
## have to invent — the same contract `ItemRequirement.unmet()` publishes.
func _shape(verdict: Dictionary, label: String) -> void:
	assert_eq(verdict.has("ok"), true, "%s has ok" % label)
	assert_eq(verdict.has("reason"), true, "%s has reason" % label)
	assert_eq(verdict.has("unmet"), true, "%s has unmet" % label)
	for entry in verdict["unmet"] as Array:
		for field in ["kind", "id", "required", "actual", "label"]:
			assert_eq(entry.has(field), true, "%s unmet entry has %s" % [label, field])


# --- The closed verb set -----------------------------------------------------


func test_an_empty_requirement_is_ungated_and_always_open() -> void:
	# "No institution" is representable (ADR 0083), and an actor with no sect at all
	# still answers a panel's ungated question.
	for actor in [null, Actor.new(&"bare")]:
		var verdict := SectApi.gate(actor, {})
		assert_eq(bool(verdict["ok"]), true, "ungated is open for %s" % actor)
		assert_eq(String(verdict["reason"]), "", "with no reason")
		assert_eq(verdict["unmet"] as Array, [], "and nothing unmet")


func test_an_unknown_verb_refuses_closed_and_names_itself() -> void:
	var verdict := SectApi.gate(_member(100, STEWARD), {"verb": &"t_paid_membership"})
	assert_eq(bool(verdict["ok"]), false, "content this module cannot read must not open")
	assert_eq(String(verdict["reason"]), "unknown_verb", "and the reason says why")
	assert_eq(
		String((verdict["unmet"] as Array)[0]["id"]),
		"t_paid_membership",
		"naming the verb rather than failing anonymously"
	)
	# A requirement with no verb at all is malformed rather than unknown, and both
	# refuse closed: refuse-with-cause is the house rule.
	var nameless := SectApi.gate(_member(100, STEWARD), {"sect": "t_house"})
	assert_eq(bool(nameless["ok"]), false, "a verbless requirement opens nothing")
	assert_eq(String(nameless["reason"]), "malformed", "and it is malformed, not unmet")
	_shape(verdict, "an unknown verb")
	_shape(nameless, "a malformed requirement")


func test_a_verb_naming_the_wrong_fields_is_refused_rather_than_guessed() -> void:
	for requirement in [
		{"verb": &"in_sect"},
		{"verb": &"holds_position"},
		{"verb": &"holds_authority"},
		{"verb": &"fit_at_least"},
		{"verb": &"duty_owed"},
		{"verb": &"duty_owed", "term": &"t_dues"},
		{"verb": &"standing_at_least", "need": -1},
		{"verb": &"all_of", "of": []},
		{"verb": &"any_of", "of": "not a list"},
	]:
		var verdict := SectApi.gate(_member(100, STEWARD), requirement)
		assert_eq(bool(verdict["ok"]), false, "refused: %s" % [requirement])
		assert_eq(String(verdict["reason"]), "malformed", "by name, for %s" % [requirement])


# --- The verbs ---------------------------------------------------------------


func test_membership_and_office_verbs_answer_from_the_ledger() -> void:
	var stranger := Actor.new(&"stranger")
	SectApi.attach(stranger)
	assert_eq(bool(SectApi.gate(stranger, {"verb": &"is_member"})["ok"]), false, "a stranger")
	assert_eq(
		bool(SectApi.gate(stranger, {"verb": &"in_sect", "sect": String(HOUSE)})["ok"]),
		false,
		"sworn to nothing in particular"
	)
	var member := _member(0, &"")
	assert_eq(bool(SectApi.gate(member, {"verb": &"is_member"})["ok"]), true, "a member is one")
	assert_eq(
		bool(SectApi.gate(member, {"verb": &"in_sect", "sect": String(HOUSE)})["ok"]),
		true,
		"and sworn to this one"
	)
	assert_eq(
		bool(SectApi.gate(member, {"verb": &"in_sect", "sect": "t_other_house"})["ok"]),
		false,
		"but not to another"
	)
	assert_eq(
		bool(SectApi.gate(member, {"verb": &"holds_position", "position": String(STEWARD)})["ok"]),
		false,
		"and an ordinary member holds no office"
	)
	var seated := _member(0, STEWARD)
	assert_eq(
		bool(SectApi.gate(seated, {"verb": &"holds_position", "position": String(STEWARD)})["ok"]),
		true,
		"a Steward holds the Steward's seat"
	)


func test_the_standing_verb_reports_the_floor_as_a_route_rather_than_as_a_wall() -> void:
	var thin := _member(20)
	var verdict := SectApi.gate(thin, {"verb": &"standing_at_least", "need": 60})
	assert_eq(bool(verdict["ok"]), false, "thin standing is not enough")
	assert_eq(String(verdict["reason"]), SectApi.STANDING_BELOW_FLOOR, "and it names the floor")
	var unmet: Dictionary = (verdict["unmet"] as Array)[0]
	assert_eq(int(unmet["required"]), 60, "reporting what the office needs")
	assert_eq(int(unmet["actual"]), 20, "and how far short the member fell")
	# The numbers are what make it a route: a caller can wait, earn, or authorise the
	# exception, and all three are decisions this gate refuses to make for it.
	assert_eq(
		bool(SectApi.gate(thin, {"verb": &"standing_at_least", "need": 20})["ok"]),
		true,
		"and the boundary is inclusive"
	)
	assert_eq(
		bool(SectApi.gate(_member(60), {"verb": &"standing_at_least", "need": 0})["ok"]),
		true,
		"a need of zero is always met"
	)


func test_the_authority_verb_asks_the_authored_office_and_never_ranks_two_offices() -> void:
	# Authority is authored data (ADR 0084): "may this member expel another" is a
	# `.tres` question, so the gate is a lookup and never `if rank >= 3`.
	var reader := _member(0, READER)
	var sealbearer := _member(0, SEAL)
	assert_eq(
		bool(
			(
				SectApi
				. gate(reader, {"verb": &"holds_authority", "authority": "t_fixture_authority"})["ok"]
			)
		),
		true,
		"an office grants what it authors"
	)
	assert_eq(
		bool(SectApi.gate(reader, {"verb": &"holds_authority", "authority": "teach"})["ok"]),
		false,
		"and only that"
	)
	assert_eq(
		bool(SectApi.gate(sealbearer, {"verb": &"holds_authority", "authority": "teach"})["ok"]),
		true,
		"the office that names it is authored to teach"
	)
	assert_eq(
		bool(SectApi.gate(sealbearer, {"verb": &"holds_authority", "authority": "expel"})["ok"]),
		true,
		"and to expel"
	)
	# A member holding no office at all may exercise nothing, however thick their
	# standing — the two are not related (ADR 0064).
	assert_eq(
		bool(SectApi.gate(_member(100), {"verb": &"holds_authority", "authority": "teach"})["ok"]),
		false,
		"standing alone confers no authority"
	)


func test_fit_is_transmission_and_never_recognition() -> void:
	# The fit ledger is seeded by content in a real game; here it is written straight
	# into `module_data`, which is exactly the shape a restore hands the facade and
	# therefore the shape the gate is proven against.
	var member := _member(0, &"")
	var ledger := SectApi.state(member)
	ledger["fit"][String(DOCTRINE)] = 40
	member.set_module_data(SectApi.MODULE_KEY, ledger)
	SectApi.attach(member)
	assert_eq(
		bool(
			(
				SectApi
				. gate(member, {"verb": &"fit_at_least", "doctrine": String(DOCTRINE), "need": 30})["ok"]
			)
		),
		true,
		"fit opens the teaching"
	)
	assert_eq(
		bool(
			(
				SectApi
				. gate(member, {"verb": &"fit_at_least", "doctrine": String(DOCTRINE), "need": 50})["ok"]
			)
		),
		false,
		"and it is the only thing that does"
	)
	assert_eq(
		bool(
			SectApi.gate(member, {"verb": &"fit_at_least", "doctrine": "t_other", "need": 1})["ok"]
		),
		false,
		"a doctrine the member has no affinity for is closed"
	)
	# The ordinary member has no office, so the recognition a top office would grant
	# is absent even here: transmission and recognition are two different things.
	assert_eq(
		SectProjection.contribution(member, Stat.INSIGHT_GAIN),
		0.0,
		"and fit projects no modifier at all (ADR 0084)"
	)


func test_the_duty_verb_reads_the_obligation_ledger_in_periods() -> void:
	var member := _member(0, &"")
	var ledger := SectApi.state(member)
	ledger["obligation"]["t_dues_outer"] = 4
	member.set_module_data(SectApi.MODULE_KEY, ledger)
	SectApi.attach(member)
	assert_eq(
		bool(SectApi.gate(member, {"verb": &"duty_owed", "term": "t_dues_outer", "need": 4})["ok"]),
		true,
		"a debt of exactly the need is settled enough"
	)
	var verdict := SectApi.gate(member, {"verb": &"duty_owed", "term": "t_dues_outer", "need": 2})
	assert_eq(bool(verdict["ok"]), false, "and a debt above it is not")
	assert_eq(int((verdict["unmet"] as Array)[0]["actual"]), 4, "reporting what is still owed")
	assert_eq(
		bool(SectApi.gate(member, {"verb": &"duty_owed", "term": "t_never_owed", "need": 1})["ok"]),
		true,
		"a debt never opened owes nothing"
	)


## The line a membership actually opens. `SectDef.member_obligation_lines` owes an
## ordinary member `duty_<sect_id>` and `instruction_<sect_id>`, and the gate has to
## read a debt the sect really opened — a `duty_owed` naming a line nothing ever
## writes answers `true` to everybody, which is a gate that is not a gate.
func test_a_membership_owes_the_duty_line_the_sect_opens_against_it() -> void:
	var member := _member(0, &"")
	var owed: Dictionary = SectApi.state(member)["obligation"]
	assert_eq(
		int(owed.get("duty_%s" % String(HOUSE), 0)),
		SectDef.MEMBER_DUTY_PERIODS,
		"joining opens the sect's own duty line"
	)
	assert_eq(
		int(owed.get("instruction_%s" % String(HOUSE), -1)), 25, "and the price of being taught"
	)
	var term := "duty_%s" % String(HOUSE)
	assert_eq(
		bool(SectApi.gate(member, {"verb": &"duty_owed", "term": term, "need": 1})["ok"]),
		true,
		"a debt of one period settles a one-period bar"
	)
	# A second period falls due, which is what makes the bar mean anything: below it
	# the gate refuses and names the debt it is refusing on.
	var ledger := SectApi.state(member)
	(ledger["obligation"] as Dictionary)[term] = 2
	member.set_module_data(SectApi.MODULE_KEY, ledger)
	SectApi.attach(member)
	var verdict := SectApi.gate(member, {"verb": &"duty_owed", "term": term, "need": 1})
	assert_eq(bool(verdict["ok"]), false, "a debt of two is not settled by one")
	assert_eq(
		int((verdict["unmet"] as Array)[0]["actual"]),
		2,
		"and it reports the debt it is refusing on"
	)


func test_the_composite_verbs_compose_and_a_broken_child_poisons_the_whole() -> void:
	var thin := _member(20)
	var thick := _member(60, STEWARD)
	assert_eq(
		bool(
			(
				SectApi
				. gate(
					thick,
					{
						"verb": &"all_of",
						"of": [{"verb": &"is_member"}, {"verb": &"standing_at_least", "need": 50}]
					}
				)["ok"]
			)
		),
		true,
		"all_of opens when every child does"
	)
	assert_eq(
		bool(
			(
				SectApi
				. gate(
					thin,
					{
						"verb": &"all_of",
						"of": [{"verb": &"is_member"}, {"verb": &"standing_at_least", "need": 50}]
					}
				)["ok"]
			)
		),
		false,
		"and stays shut when one does not"
	)
	assert_eq(
		bool(
			(
				SectApi
				. gate(
					thin,
					{
						"verb": &"any_of",
						"of": [{"verb": &"standing_at_least", "need": 50}, {"verb": &"is_member"}]
					}
				)["ok"]
			)
		),
		true,
		"any_of opens on one"
	)
	assert_eq(
		bool(
			(
				SectApi
				. gate(
					thin, {"verb": &"none_of", "of": [{"verb": &"standing_at_least", "need": 50}]}
				)["ok"]
			)
		),
		true,
		"none_of opens only when every child is unmet"
	)
	# Refuse-with-cause: a nested gate this module cannot read is never treated as
	# satisfied, and never treated as absent either. A `none_of` built on a typo must
	# not read as "nothing blocks this".
	var poisoned := SectApi.gate(
		thick, {"verb": &"none_of", "of": [{"verb": &"t_paid_membership"}]}
	)
	assert_eq(bool(poisoned["ok"]), false, "a broken child poisons the composite")
	assert_eq(String(poisoned["reason"]), "unknown_verb", "and names the reason")
	# Nesting is a content edit, not a code change, and it recurses.
	var nested := (
		SectApi
		. gate(
			thick,
			{
				"verb": &"all_of",
				"of":
				[
					{"verb": &"in_sect", "sect": String(HOUSE)},
					{
						"verb": &"any_of",
						"of":
						[
							{"verb": &"holds_position", "position": String(STEWARD)},
							{"verb": &"holds_authority", "authority": "teach"},
						],
					},
				],
			}
		)
	)
	assert_eq(bool(nested["ok"]), true, "and nests")


# --- A gate reads the ledger, never a stat -----------------------------------


## The rule ADR 0076 states for reputation and ADR 0062 for paths, applied here: a
## stat can be satisfied by an item, a pill or another module's grant, so a gate that
## read one would be a gate the player could buy. Recognition must therefore not be
## purchasable, and the only way to prove that is to hand the actor a modifier it did
## not earn and watch the gate stay shut.
func test_a_gate_reads_the_ledger_and_never_a_derived_stat() -> void:
	var thin := _member(20)
	assert_eq(
		bool(SectApi.gate(thin, {"verb": &"standing_at_least", "need": 60})["ok"]),
		false,
		"thin standing is refused"
	)
	# Smuggle in the very stat the gate's subject projects onto, at a magnitude no
	# member could earn. The gate must not notice, because it never read it.
	thin.stats.add_modifier(
		StatModifier.new(Stat.INSIGHT_GAIN, Stat.Op.PERCENT, 5.0, &"set:bought_insight")
	)
	thin.stats.add_modifier(
		StatModifier.new(Stat.MAX_HEALTH, Stat.Op.FLAT, 5000.0, &"set:bought_vigour")
	)
	assert_eq(
		bool(SectApi.gate(thin, {"verb": &"standing_at_least", "need": 60})["ok"]),
		false,
		"still refused: recognition is not a stat the player can buy"
	)
	assert_eq(
		bool(SectApi.gate(thin, {"verb": &"holds_authority", "authority": "teach"})["ok"]),
		false,
		"and authority is authored data, not a threshold a modifier reaches"
	)
	# The office gate agrees for the same reason: an office is an id in the ledger.
	assert_eq(
		bool(SectApi.gate(thin, {"verb": &"holds_position", "position": String(STEWARD)})["ok"]),
		false,
		"no amount of health makes somebody a Steward"
	)


func test_the_verdict_never_contains_an_actor_or_a_resource_so_a_panel_can_hold_it() -> void:
	# The contract a UI panel tests instead of pixels: primitives, arrays and plain
	# dictionaries all the way down.
	var verdict := SectApi.gate(_member(5), {"verb": &"standing_at_least", "need": 60})
	_assert_primitive_tree(verdict, "a refused verdict")
	var passed := SectApi.gate(_member(90), {"verb": &"all_of", "of": [{"verb": &"is_member"}]})
	_assert_primitive_tree(passed, "a passing verdict")


func _assert_primitive_tree(value, label: String) -> void:
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			assert_eq(typeof(key), TYPE_STRING, "%s dictionary key is a String" % label)
			_assert_primitive_tree((value as Dictionary)[key], label)
		return
	if value is Array:
		for entry in value as Array:
			_assert_primitive_tree(entry, label)
		return
	if value == null:
		return
	assert_eq(typeof(value) >= TYPE_OBJECT, false, "%s holds no Object at all" % label)
