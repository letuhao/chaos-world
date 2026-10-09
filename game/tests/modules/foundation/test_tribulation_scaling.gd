extends TestCase

## BL-0951 / ADR 0939, S5: the tribulation prices the past realms through the carried
## foundation, on top of — never instead of — the current realm's preparation.
##
## The term is a pure multiplier of the value (`1 + 0.3 * (1 - foundation)`): a perfect
## record rates EXACTLY the baseline every fight rated before this existed, and a sloppy
## one rates strictly harder. It is realm-invariant by construction — the multiplier
## takes no realm — and it never double-counts BL-0830's depth, which prices THIS realm's
## training while this prices the realms already left.


## `Callable` is not a constant expression, so the installed source is built by one
## helper rather than a `const` — every install in this file is the same object.
static func _source() -> Callable:
	return Callable(FoundationApi, "tribulation_foundation")


func setup() -> void:
	# The seam is a `static var` and the runner shares one process across suites, so this
	# suite installs the real source and clears it — the same discipline
	# `test_tribulation_fight.gd` keeps for the gate kernel.
	Tribulation.set_foundation_source(_source())


func teardown() -> void:
	Tribulation.set_foundation_source(Callable())


func _actor() -> Actor:
	return Actor.new(&"scaling_hero", {Stat.COMPREHENSION: 40.0})


## A history of `value` for every realm below `standing_id`, in ladder order. Bounded by
## the ladder and terminated by the standing rank.
func _history(actor: Actor, standing_id: StringName, value: float) -> void:
	for realm in RealmDefaults.ladder().realms():
		if realm.id == standing_id:
			return
		FoundationApi.snapshot(actor, realm.id, value)


func _started(actor: Actor, realm_id: StringName) -> Tribulation:
	var fight := Tribulation.new()
	fight.start(actor, realm_id)
	return fight


func test_a_perfect_record_rates_the_baseline_exactly() -> void:
	var perfect := _actor()
	_history(perfect, &"earth_immortal", 1.0)
	var naked := _actor()
	Tribulation.set_foundation_source(Callable())
	var baseline := _started(naked, &"earth_immortal").difficulty
	Tribulation.set_foundation_source(_source())
	assert_almost_eq(
		_started(perfect, &"earth_immortal").difficulty, baseline, "a perfect past costs nothing"
	)


func test_a_sloppy_record_rates_strictly_harder_by_the_authored_weight() -> void:
	var sloppy := _actor()
	_history(sloppy, &"earth_immortal", 0.0)
	var perfect := _actor()
	_history(perfect, &"earth_immortal", 1.0)
	var sloppy_rating := _started(sloppy, &"earth_immortal").difficulty
	var perfect_rating := _started(perfect, &"earth_immortal").difficulty
	assert_eq(sloppy_rating > perfect_rating, true, "the past prices the fight")
	assert_almost_eq(
		sloppy_rating,
		perfect_rating * (1.0 + Tribulation.FOUNDATION_PRESSURE),
		"by exactly the authored weight"
	)


func test_the_multiplier_is_a_pure_function_of_the_value() -> void:
	assert_almost_eq(Tribulation.foundation_multiplier(1.0), 1.0, "perfect is the baseline")
	assert_almost_eq(
		Tribulation.foundation_multiplier(0.0),
		1.0 + Tribulation.FOUNDATION_PRESSURE,
		"zero is the full weight"
	)
	assert_almost_eq(
		Tribulation.foundation_multiplier(0.4),
		Tribulation.foundation_multiplier(0.4),
		"the same value is the same term at any realm — it takes no realm"
	)
	assert_almost_eq(Tribulation.foundation_multiplier(9.0), 1.0, "clamped above reads as perfect")
	assert_almost_eq(
		Tribulation.foundation_multiplier(-4.0),
		1.0 + Tribulation.FOUNDATION_PRESSURE,
		"clamped below"
	)


func test_an_empty_record_rates_the_baseline() -> void:
	var fresh := _actor()
	assert_almost_eq(
		_started(fresh, &"earth_immortal").difficulty,
		_started(_actor(), &"earth_immortal").difficulty,
		"no departures is not a sloppy past"
	)


func test_an_uninstalled_source_rates_the_baseline() -> void:
	Tribulation.set_foundation_source(Callable())
	var sloppy := _actor()
	_history(sloppy, &"earth_immortal", 0.0)
	var perfect := _actor()
	_history(perfect, &"earth_immortal", 1.0)
	assert_almost_eq(
		_started(sloppy, &"earth_immortal").difficulty,
		_started(perfect, &"earth_immortal").difficulty,
		"no seam, no term"
	)


func test_a_sloppy_past_is_endured_less_often_within_the_band() -> void:
	var sloppy := _actor()
	_history(sloppy, &"earth_immortal", 0.0)
	var perfect := _actor()
	_history(perfect, &"earth_immortal", 1.0)
	var sloppy_share := TribulationEndurance.endurance(sloppy, _started(sloppy, &"earth_immortal"))
	var perfect_share := TribulationEndurance.endurance(
		perfect, _started(perfect, &"earth_immortal")
	)
	assert_eq(sloppy_share < perfect_share, true, "the harder fight is survived less often")
	for share in [sloppy_share, perfect_share]:
		assert_eq(
			share >= Tribulation.MIN_ENDURANCE and share <= Tribulation.MAX_ENDURANCE,
			true,
			"but never outside the authored band: %f" % share
		)


func test_the_priced_foundation_survives_a_save() -> void:
	var sloppy := _actor()
	_history(sloppy, &"earth_immortal", 0.0)
	var fight := _started(sloppy, &"earth_immortal")
	var restored := Tribulation.from_dict(fight.to_dict())
	assert_almost_eq(restored.foundation, 0.0, "the priced value resumes, not a re-derived one")
	assert_almost_eq(restored.difficulty, fight.difficulty, "and so does the rating")
