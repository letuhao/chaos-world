extends TestCase

## ADR 0902 (P11 / T10): the cross-realm probe of `status_tier_power_weight`. The knob
## ships OFF (0.0) — the realm-invariant reading — and this suite (a) proves parity is
## untouched at the shipped value for every realm pair, (b) pins the formula the knob
## folds (`weight * (attacker realm power - defender realm power)` from the AUTHORED
## table), and (c) PRINTS the candidate numbers so the measurement is recorded in the
## run log, not in a document.
##
## The probe writes `PathState.rank_id` directly — `RealmScaling.highest_realm` reads
## exactly that — so each actor's power is the ladder's authored one, not a fixture
## number restated here.

const WEIGHTS: Array[float] = [0.0, 0.001, 0.01, 0.1]

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


func _realm_actor(id: StringName, realm_id: StringName) -> Actor:
	var actor := CombatTestKit.actor(id)
	actor.paths[PathState.QI] = PathState.new(PathState.QI, realm_id)
	return actor


func _ladder() -> Array[RealmDef]:
	return RealmDefaults.ladder().realms()


func _chance(attacker: Actor, target: Actor, weight: float) -> float:
	var tuning := CombatTestKit.shipped()
	tuning.status_tier_power_weight = weight
	return StatusApply.apply_chance(attacker, target, tuning, 1.0, &"", &"", &"", 0.0)


func test_the_shipped_knob_keeps_parity_for_every_realm_pair() -> void:
	var realms := _ladder()
	assert_eq(realms.size() >= 3, true, "the ladder has realms to probe")
	var first := _realm_actor(&"tier_first", realms[0].id)
	var last := _realm_actor(&"tier_last", realms[realms.size() - 1].id)
	assert_almost_eq(
		_chance(first, last, 0.0),
		0.5,
		"the lowest realm against the highest reads parity at the shipped weight",
		1e-9
	)
	assert_almost_eq(_chance(last, first, 0.0), 0.5, "and the reverse too", 1e-9)


## The formula pin: whatever the ladder's powers are, the knob folds their GAP by the
## weight and nothing else — the same arithmetic the ADR records.
func test_the_knob_folds_the_authored_power_gap() -> void:
	var realms := _ladder()
	var first := _realm_actor(&"tier_first", realms[0].id)
	var last := _realm_actor(&"tier_last", realms[realms.size() - 1].id)
	var gap := realms[realms.size() - 1].power - realms[0].power
	for weight in WEIGHTS:
		var expected := clampf(clampf(0.5 + weight * gap, 0.0, 1.0), _tuning.status_min_apply, 1.0)
		assert_almost_eq(
			_chance(last, first, weight),
			expected,
			"weight %s folds the gap by formula" % str(weight),
			1e-6
		)


## The recorded measurement: four weights across four realm pairs, printed for the run
## log. The knob STAYS OFF — this row only proves the shipped value did not move.
func test_the_measurement_is_recorded_in_the_run() -> void:
	var realms := _ladder()
	var low := _realm_actor(&"tier_low", realms[0].id)
	var high := _realm_actor(&"tier_high", realms[realms.size() - 1].id)
	var mid := _realm_actor(&"tier_mid", realms[mini(9, realms.size() - 1)].id)
	for weight in WEIGHTS:
		print(
			"TIER weight=",
			weight,
			" r1_vs_r1=",
			_chance(low, low, weight),
			" r1_vs_r10=",
			_chance(low, mid, weight),
			" r1_vs_r30=",
			_chance(low, high, weight),
			" r30_vs_r1=",
			_chance(high, low, weight)
		)
	assert_almost_eq(_tuning.status_tier_power_weight, 0.0, "the shipped knob stays OFF", 1e-9)
