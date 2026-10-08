extends TestCase

## DEF-0173's read-back half, pinned from the social side.
##
## The writer itself already exists and is `SocialApi.apply_cause`: `sect/`, `nation/`
## and `clan/` each reach it with their own named membership causes
## (`sworn_to_sect` / `left_a_sect` / `expelled_from_sect` and kin), and
## `SocialState.regard` is the projection of the institutional bonds, rebuilt on every
## mutation — not a second number anyone assigns. So this suite does NOT invent a new
## verb: the facade already publishes twelve methods and a thirteenth would buy width
## with no new capability. What was missing was the social-side proof that joining,
## leaving and expulsion each move regard through a NAMED cause, that the causes read
## back, and that regard and standing never derive from each other.
##
## ## The D8 gate for regard movement, in one sentence
##
## Regard costs nothing to earn and everything to keep badly: leaving and expulsion are
## TRANSIENT wounds that `tick` decays toward the persistent oath floor, while expulsion
## itself is bounded (-6.0 per act, clamped to [-100, 100]), so no chain of verdicts can
## drive a bond past the floor the world stops at.

const SECT := &"iron_compound"
const MERCHANT := &"merchant_grampa"
const MONTH := 24.0 * 60.0 * 60.0 * 30.0


## The catalog is a process-wide singleton, so every test starts from the shipped set.
## Without this a test running after one that called `reset` would find the membership
## causes missing and silently assert nothing.
func setup() -> void:
	SocialCauseCatalog.instance().install_defaults()


func _actor() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	SocialApi.attach(actor)
	return actor


func test_a_stranger_has_no_regard_row() -> void:
	var actor := _actor()
	assert_eq(
		SocialApi.summary(actor).get("regard", {"unreachable": true}),
		{},
		"no institution history is ADR 0083's first state, not a zero"
	)
	assert_eq(SocialApi.bond_entry(actor, SECT)["present"], false, "and they were never met")


func test_join_leave_and_expel_each_move_regard_through_its_named_cause() -> void:
	var actor := _actor()
	var joined := SocialApi.apply_cause(actor, SECT, &"sworn_to_sect")
	assert_eq(bool(joined.get("ok", false)), true, "joining is accepted")
	assert_almost_eq(
		float(SocialApi.summary(actor)["regard"].get(String(SECT), 999.0)),
		2.0,
		"the oath is remembered, modestly"
	)
	var left := SocialApi.apply_cause(actor, SECT, &"left_a_sect")
	assert_eq(bool(left.get("ok", false)), true, "leaving is accepted too")
	assert_almost_eq(
		float(SocialApi.summary(actor)["regard"].get(String(SECT), 999.0)),
		1.0,
		"walking out costs standing, not disgrace"
	)
	var expelled := SocialApi.apply_cause(actor, SECT, &"expelled_from_sect")
	assert_eq(bool(expelled.get("ok", false)), true, "expulsion lands")
	assert_almost_eq(
		float(SocialApi.summary(actor)["regard"].get(String(SECT), 999.0)),
		-5.0,
		"being cast out is the harsh verdict, and it is someone else's act"
	)


func test_the_membership_causes_read_back() -> void:
	var actor := _actor()
	SocialApi.apply_cause(actor, SECT, &"sworn_to_sect")
	SocialApi.apply_cause(actor, SECT, &"left_a_sect")
	SocialApi.apply_cause(actor, SECT, &"expelled_from_sect")
	var entry := SocialApi.bond_entry(actor, SECT)
	assert_eq(entry["present"], true, "the institution row exists")
	assert_eq(
		entry["causes"],
		["expelled_from_sect", "left_a_sect", "sworn_to_sect"],
		"every act that moved regard is named, sorted, none write-only"
	)
	assert_eq(String(entry["last_cause"]), "expelled_from_sect", "the latest verdict is named")
	var bond := SocialApi.social_state(actor).bond(SECT)
	assert_eq(int(bond.causes.get("sworn_to_sect", 0)), 1, "the oath was recorded once")
	assert_eq(int(bond.causes.get("left_a_sect", 0)), 1, "the exit was recorded once")
	assert_eq(int(bond.causes.get("expelled_from_sect", 0)), 1, "the expulsion was recorded once")


func test_regard_is_a_projection_not_a_second_number() -> void:
	var actor := _actor()
	SocialApi.apply_cause(actor, SECT, &"sworn_to_sect")
	SocialApi.apply_cause(actor, MERCHANT, &"gifted_item")
	var regard: Dictionary = SocialApi.summary(actor)["regard"]
	var bond := SocialApi.social_state(actor).bond(SECT)
	# Direction one: nothing but the bond feeds regard. A personal gift moves a personal
	# row and never appears in the institutional read model.
	assert_eq(regard.get(String(MERCHANT), null), null, "a person is never a regard row")
	assert_eq(regard.keys(), [String(SECT)], "the oath wrote exactly one row")
	assert_almost_eq(
		float(regard[String(SECT)]),
		bond.standing,
		"regard IS the bond standing, by projection rather than by agreement"
	)
	# Direction two: the institutional act moved no personal row. Were regard derived
	# from standing or standing from regard, one of these rows would have moved.
	assert_eq(
		SocialApi.social_state(actor).bond(MERCHANT).standing,
		1.0,
		"the gift moved only its own row"
	)
	assert_eq(SocialApi.bond_entry(actor, MERCHANT)["present"], true, "which exists independently")


func test_an_institutional_bond_survives_a_json_round_trip() -> void:
	var actor := _actor()
	SocialApi.apply_cause(actor, SECT, &"sworn_to_sect")
	SocialApi.apply_cause(actor, SECT, &"expelled_from_sect")
	# The whole of the save path through the JSON hop: `JSON.parse_string` returns every
	# number as a float, so comparing THROUGH it is what proves save safety.
	var restored := Actor.from_dict(JSON.parse_string(JSON.stringify(actor.to_dict())))
	SocialApi.attach(restored)
	var regard: Dictionary = SocialApi.summary(restored)["regard"]
	assert_almost_eq(
		float(regard.get(String(SECT), 999.0)), -4.0, "the projection rebuilt from bonds"
	)
	var bond := SocialApi.social_state(restored).bond(SECT)
	assert_ne(bond, null, "the row survived")
	assert_eq(int(bond.causes.get("sworn_to_sect", 0)), 1, "the oath survived the hop")
	assert_eq(int(bond.causes.get("expelled_from_sect", 0)), 1, "the verdict survived the hop")
	assert_eq(bond.institutional, true, "the stored flag survived, so the row projects")
	assert_eq(
		String(SocialApi.bond_entry(restored, SECT)["last_cause"]),
		"expelled_from_sect",
		"the latest verdict survived too"
	)


func test_expulsion_is_bounded_and_wounds_decay_toward_the_oath_floor() -> void:
	var actor := _actor()
	# Fixed count, unconditional body: the loop terminates by construction.
	for _i in range(30):
		SocialApi.apply_cause(actor, SECT, &"expelled_from_sect")
	assert_almost_eq(
		float(SocialApi.summary(actor)["regard"].get(String(SECT), 999.0)),
		-100.0,
		"thirty verdicts reach the clamp and stop, never past it"
	)
	# The counterweight: a sworn oath leaves a persistent floor that a transient wound
	# cannot lower, and time moves the bond back toward that promise, not toward a
	# stranger.
	var healed := _actor()
	SocialApi.apply_cause(healed, SECT, &"sworn_to_sect")
	SocialApi.apply_cause(healed, SECT, &"expelled_from_sect")
	var bond := SocialApi.social_state(healed).bond(SECT)
	assert_almost_eq(bond.standing_floor, 2.0, "the oath floor the expulsion could not lower")
	assert_eq(SocialApi.tick(healed, MONTH), 1, "one bond moved, so the tick is bounded")
	assert_almost_eq(
		float(SocialApi.summary(healed)["regard"].get(String(SECT), 999.0)),
		-3.0,
		"a season of silence moves the wound one step toward the promise"
	)


func test_an_unknown_cause_refuses_and_moves_nothing() -> void:
	var actor := _actor()
	var refused := SocialApi.apply_cause(actor, SECT, &"no_such_verdict")
	assert_eq(bool(refused.get("ok", true)), false, "refused")
	assert_eq(String(refused.get("reason", "")), "unknown_cause", "under a named reason")
	assert_eq(
		SocialApi.summary(actor).get("regard", {"unreachable": true}),
		{},
		"a refused act writes no row"
	)


func test_forgetting_dissolves_the_regard_row() -> void:
	var actor := _actor()
	SocialApi.apply_cause(actor, SECT, &"sworn_to_sect")
	assert_eq(SocialApi.forget(actor, SECT), true, "dissolved")
	assert_eq(
		SocialApi.summary(actor).get("regard", {"unreachable": true}),
		{},
		"a dissolved institution is no longer one you are regarded by"
	)
	assert_eq(SocialApi.bond_entry(actor, SECT)["present"], false, "the row is gone, not zeroed")
