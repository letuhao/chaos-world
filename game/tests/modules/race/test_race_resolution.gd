extends TestCase

## **A race is one value, never a blend** (ADR 0062). These hold that line: two parents
## of the same race produce it without consulting the roll, a mixed conception resolves
## to exactly one of the two, a race that cannot clear its own threshold never manifests,
## and a conception where neither can falls back to the catalog baseline. The roll is
## supplied rather than drawn, so every case here is deterministic.

const STONE := &"t_stone"
const TIDE := &"t_tide"
const BASE := &"t_base"
const MUTE := &"t_mute"
const UNKNOWN := &"t_retired"


func setup() -> void:
	(
		RaceFixtureCatalog
		. install(
			[
				RaceFixtureCatalog.capped(STONE, &"mind_cultivation", 8, Stat.PHYSIQUE, 0.8),
				RaceFixtureCatalog.closed(TIDE, &"body_cultivation", 0.6),
				RaceFixtureCatalog.closed(BASE, &"mind_cultivation", 0.2),
				RaceFixtureCatalog.mute(MUTE, &"mind_cultivation", &"body_cultivation"),
			],
			BASE
		)
	)


func teardown() -> void:
	RaceFixtureCatalog.teardown()


## An actor already born into `race_id`, as a parent would be.
func _parent(race_id: StringName, actor_id: StringName = &"parent") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0})
	RaceApi.attach(actor)
	RaceApi.set_race(actor, race_id)
	return actor


func _resolve(a: Actor, b: Actor, roll: float) -> StringName:
	return RaceApi.resolve_race(a, b, roll)


# --- Two parents, one race ---------------------------------------------------


func test_two_parents_of_the_same_race_produce_that_race_and_never_consult_the_roll() -> void:
	var a := _parent(STONE, &"a")
	var b := _parent(STONE, &"b")
	for roll in [0.0, 0.25, 0.5, 0.75, 0.999]:
		assert_eq(_resolve(a, b, roll), STONE, "roll %f is irrelevant to a like pairing" % roll)
	assert_eq(_resolve(b, a, 0.0), STONE, "and the parents are order-independent")


func test_a_parent_with_no_race_leaves_the_survivors_race_the_only_contender() -> void:
	# With one parent holding nothing there is no contest, so the survivor's race is
	# the only candidate — but `roll` still decides how much share it is offered. A
	# roll of 0.0 hands it nothing, and a race offered nothing cannot clear its own
	# threshold, so the conception falls back to the baseline. That is the rule the
	# resolver states, and it holds in both seats: one pair, one answer.
	var bare := Actor.new(&"bare")
	RaceApi.attach(bare)
	var known := _parent(TIDE)
	for roll in [0.0, 0.5, 1.0]:
		var forward := _resolve(bare, known, roll)
		var reversed := _resolve(known, bare, roll)
		assert_eq(forward, reversed, "roll %f answers the same in either seat" % roll)
		if roll > 0.0:
			assert_eq(forward, TIDE, "roll %f hands the survivor its share" % roll)
		else:
			assert_eq(forward, BASE, "a roll of zero hands it nothing at all")


# --- Two parents, two races: exactly one wins --------------------------------


func test_a_mixed_conception_always_resolves_to_one_of_the_two_races_never_a_blend() -> void:
	var stone := _parent(STONE, &"stone")
	var tide := _parent(TIDE, &"tide")
	for step in 20:
		var roll := float(step) / 20.0
		var child := _resolve(stone, tide, roll)
		assert_eq([STONE, TIDE].has(child), true, "roll %f produced '%s'" % [roll, child])
	# And every roll lands on exactly one of them, with no third value anywhere.
	var seen := {}
	for step in 100:
		seen[String(_resolve(stone, tide, float(step) / 100.0))] = true
	assert_eq(seen.size(), 2, "exactly two outcomes across the whole roll range")


func test_the_higher_dominant_parent_wins_the_contested_middle_and_the_order_is_swapped() -> void:
	var stone := _parent(STONE, &"stone")
	var tide := _parent(TIDE, &"tide")
	# Stoneborn dominance 0.8, tidecaller 0.6. At roll 0.5 the shares are 0.4 and 0.3.
	assert_eq(_resolve(stone, tide, 0.5), STONE, "the stronger body takes the middle")
	assert_eq(_resolve(tide, stone, 0.5), STONE, "and it does not matter which seat it sat in")


func test_the_roll_can_hand_a_conception_wholly_to_the_lower_dominant_parent() -> void:
	var stone := _parent(STONE, &"stone")
	var tide := _parent(TIDE, &"tide")
	# The roll belongs to the first contesting parent, so stone holds it. A roll of
	# 0.0 gives stoneborn no share however dominant it is, and the tide caller takes
	# the child whole; a roll of 1.0 does the reverse. Neither seat changes the answer.
	assert_eq(_resolve(stone, tide, 0.0), TIDE, "a roll of 0.0 hands stoneborn nothing")
	assert_eq(_resolve(stone, tide, 1.0), STONE, "and a roll of 1.0 hands it everything")
	assert_eq(_resolve(tide, stone, 0.0), STONE, "the tide caller holds the roll instead")
	assert_eq(_resolve(tide, stone, 1.0), TIDE, "so the pair answers the same both ways")


func test_resolution_is_a_pure_function_of_its_inputs_and_mutates_nothing() -> void:
	var stone := _parent(STONE, &"stone")
	var tide := _parent(TIDE, &"tide")
	var stone_before := RaceApi.state(stone)
	var tide_before := RaceApi.state(tide)
	var first := _resolve(stone, tide, 0.42)
	for step in 5:
		assert_eq(_resolve(stone, tide, 0.42), first, "the same roll always gives the same race")
	assert_eq(RaceApi.state(stone), stone_before, "neither parent was written to")
	assert_eq(RaceApi.state(tide), tide_before, "by either parent")


# --- Below the threshold: the baseline ---------------------------------------


func test_a_race_that_cannot_clear_its_threshold_never_manifests() -> void:
	# `mute` carries dominance 0.9 and threshold 0.5, so its best possible share in a
	# two-way roll is 0.5 * 0.9 = 0.45 — under its own bar at every roll.
	var loud := _parent(MUTE, &"loud")
	var quiet := _parent(BASE, &"quiet")
	for step in 20:
		var roll := float(step) / 20.0
		assert_eq(_resolve(loud, quiet, roll), BASE, "roll %f cannot wake it" % roll)
	assert_eq(RaceApi.resolve_race(loud, quiet, 0.5), BASE, "and not at the midpoint either")


func test_a_conception_with_no_readable_race_at_all_is_born_the_baseline() -> void:
	var a := Actor.new(&"a")
	RaceApi.attach(a)
	var b := Actor.new(&"b")
	RaceApi.attach(b)
	for roll in [0.0, 0.5, 0.999]:
		assert_eq(_resolve(a, b, roll), BASE, "roll %f has nothing to contest" % roll)
	assert_eq(_resolve(null, null, 0.5), BASE, "and a null pair is the baseline too")


func test_a_parent_naming_a_race_the_catalog_no_longer_ships_cannot_choose_the_child() -> void:
	# `set_race` refuses an id the catalog does not ship, so the retired parent is
	# born with no race at all and cannot contest anything — which is the point: a
	# race that no longer exists gets no say in what a child is born as.
	var retired := _parent(UNKNOWN, &"retired")
	var known := _parent(TIDE)
	assert_eq(RaceApi.race_of(retired), &"", "and the retired race was refused at birth")
	for roll in [0.0, 0.5, 1.0]:
		var expected := BASE if roll == 0.0 else TIDE
		assert_eq(
			_resolve(retired, known, roll),
			expected,
			"roll %f cannot be won by an unknown race" % roll
		)


func test_the_baseline_is_the_tagged_one_and_is_the_fallback_for_every_unresolved_pair() -> void:
	assert_eq(RaceCatalog.instance().baseline_race(), BASE, "the tagged race")
	var stone := _parent(STONE, &"stone")
	var tide := _parent(TIDE, &"tide")
	# Whatever the roll, the answer is one of the authored races or the baseline.
	var catalog := RaceCatalog.instance()
	for step in 50:
		var child := _resolve(stone, tide, float(step) / 50.0)
		assert_ne(catalog.race_definition(child), null, "'%s' is authored content" % child)


func test_a_child_can_be_born_and_then_gains_a_path_the_parent_closed() -> void:
	# The point of the whole thing: the answer is a real, gateable body plan. The
	# fixtures make STONE close MIND and TIDE close BODY. Resolution is
	# order-independent and the first contesting parent takes the roll, so at
	# roll 0.0 STONE holds no share and TIDE takes the child entirely — a body that
	# walks BODY, the path the stoneborn parent was denied, and is itself denied MIND
	# for a different reason. The pairing decides the body, not the argument order.
	var stone := _parent(STONE, &"stone")
	var tide := _parent(TIDE, &"tide")
	var child := Actor.new(&"child", {Stat.PHYSIQUE: 10.0})
	RaceApi.attach(child)
	var born := _resolve(stone, tide, 0.0)
	assert_eq(born, TIDE, "a roll of 0.0 hands the conception wholly to tidecaller")
	assert_eq(RaceApi.set_race(child, born), true, "born tidecaller")
	assert_eq(RaceApi.can_take_path(child, PathState.BODY), false, "body is closed to tidecaller")
	assert_eq(RaceApi.can_take_path(child, PathState.MIND), true, "and mind is open to it")
