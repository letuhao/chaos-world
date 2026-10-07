extends TestCase

## ADR 0902 (P8, BL-0924): the age track's WIRE. `StatusLoop.tick` is the composition
## root's only time wire, so it detects the band transition and calls the projection host;
## a fresh loop installs the pair on its first tick (the age system's own "installed at
## conception"), and a threshold crossing swaps the pair without a second apply.

const YEARS := 100.0

var _loop: StatusLoop = null


func teardown() -> void:
	_loop = null


## An actor whose lifespan is authored by the TEST: a flat on the zero-baseline
## `race_lifespan` stat, so the band thresholds are deterministic and no factory wiring
## decides them. `tracked` attaches the npc roster to the actor (ADR 0092's tiering:
## only the player or a roster entry gets the age track).
func _actor(id: StringName, tracked: bool = true) -> Actor:
	var actor := ActorFactory.build(id, {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
	actor.stats.add_modifier(
		StatModifier.new(&"race_lifespan", Stat.Op.FLAT, YEARS * 365.0, &"test")
	)
	if tracked:
		NpcApi.attach(actor)
	return actor


func test_a_fresh_loop_installs_the_pair_on_its_first_tick() -> void:
	var actor := _actor(&"age_wire_fresh")
	_loop = StatusLoop.new(actor)
	var result := _loop.tick(1.0)
	assert_eq(String(result.get("age_band", "")), "first_ash", "the youngest band is reported")
	assert_eq(
		actor.has_status(AgeBands.wear_id(&"first_ash")),
		true,
		"the debuff half is installed at the first tick"
	)
	assert_eq(
		actor.has_status(AgeBands.clarity_id(&"first_ash")),
		true,
		"and the buff half, in the same change"
	)


func test_crossing_a_threshold_swaps_the_pair() -> void:
	var actor := _actor(&"age_wire_cross")
	_loop = StatusLoop.new(actor)
	_loop.tick(1.0)
	assert_eq(actor.has_status(AgeBands.wear_id(&"first_ash")), true, "the young pair is live")
	# 99% of a 100-year life is the last band by any authored table's shape.
	actor.age_years = YEARS * 0.99
	var result := _loop.tick(1.0)
	var band := String(result.get("age_band", ""))
	assert_ne(band, "first_ash", "the band moved")
	assert_eq(actor.has_status(AgeBands.wear_id(&"first_ash")), false, "the old pair withdrew")
	assert_eq(actor.has_status(AgeBands.wear_id(StringName(band))), true, "the new pair landed")
	assert_eq(actor.has_status(AgeBands.clarity_id(StringName(band))), true, "both halves")


func test_an_unchanged_band_does_not_re_apply() -> void:
	var actor := _actor(&"age_wire_stable")
	_loop = StatusLoop.new(actor)
	_loop.tick(1.0)
	var count := actor.statuses.size()
	var handles: Array[int] = []
	for status in actor.statuses:
		handles.append(status.instance_id)
	_loop.tick(1.0)
	_loop.tick(1.0)
	assert_eq(actor.statuses.size(), count, "no new instance appears")
	var after: Array[int] = []
	for status in actor.statuses:
		after.append(status.instance_id)
	assert_eq(after, handles, "and the same instances are still live, not fresh ones")


## TIERED TRACKING (ADR 0092): a body the roster does not carry gets NO age track —
## the projection's cost stays off the bodies the game forgets.
func test_an_untracked_body_gets_no_age_track() -> void:
	var actor := _actor(&"age_wire_untracked", false)
	_loop = StatusLoop.new(actor)
	var result := _loop.tick(1.0)
	assert_eq(String(result.get("age_band", "")), "first_ash", "the band is still reported")
	assert_eq(actor.statuses.size(), 0, "but no pair is installed on an untracked body")
