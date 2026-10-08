extends TestCase

## BL-0938's ruling proof: the x4 mastery ceiling is only sound if a defender has a real
## answer (AGENTS.md's yin-yang rule — an advantage with no counterpart is a bug). This
## suite measures ONE fire attack in the same units across three defenders:
##
## - an UNPREPARED (neutral) defender against an untrained attacker,
## - the same neutral defender against the FULL-mastery attacker,
## - a PREPARED defender at the reachable maximum: a nature the attack is WEAK against
##   (water), the resistance root at the attunement cap, top-of-ladder `will`, and the
##   authored ward (read from the shipped content, not typed in).
##
## The assertions are BOUNDS with the arithmetic in the comments, not a fitted table:
## the mastery advantage cannot exceed the ceiling the provider declares, a prepared
## defender strictly beats an unprepared one, and the whole relationship is
## realm-invariant — the attacker's x4 and the defender's answer ride the same ladder.

const FIRE := ElementStats.FIRE
const WATER := ElementStats.WATER
const ATTACKER_AFFINITY := 10.0
## ADR 0924's attunement cap at element tier 3 — the most resistance root a body can hold.
const DEFENDER_ROOT_CAP := 18.0
## The authored base `will` tops out at 54.9 (DEF-0262), so 55 is the reachable crown.
const DEFENDER_WILL_TOP := 55.0
const WARD_PATH := "res://data/items/equipment/ward_fire_ward.tres"
## The share the measurement authors: pure elemental, so the column IS the elemental path
## rather than a blend that would dilute the ratio with the raw term.
const FULL_SHARE := 1.0


func test_a_full_mastery_attack_is_bounded_and_a_prepared_defender_answers() -> void:
	var ward := _ward_value()
	assert_eq(
		ward > 0.0, true, "the authored fire ward carries element_defense_fire (content contract)"
	)
	var growth_ratios: Array[float] = []
	var answer_ratios: Array[float] = []
	for rank_id in [&"qi_refining", &"primordial_origin"]:
		var cap := ElementMastery.cap_at_rank(rank_id)
		var bare := _hit(0.0, rank_id, &"", 0.0, 0.0, 0.0)
		var trained := _hit(cap, rank_id, &"", 0.0, 0.0, 0.0)
		var answered := _hit(cap, rank_id, WATER, DEFENDER_ROOT_CAP, DEFENDER_WILL_TOP, ward)
		var growth := float(trained["elemental_term"]) / float(bare["elemental_term"])
		var answer := float(answered["elemental_term"]) / float(trained["elemental_term"])
		growth_ratios.append(growth)
		answer_ratios.append(answer)
		_print_row(rank_id, cap, bare, trained, answered, growth, answer)
		# 1. Full mastery is a REAL advantage, and it cannot exceed the provider's ceiling:
		# the elemental term is proportional to `element_power`, so the ratio is the power
		# ratio, bounded by `1 + POWER_CEILING` at saturation 1.0.
		assert_eq(growth > 1.0, true, "full mastery buys more than nothing at %s" % rank_id)
		assert_eq(
			growth <= 1.0 + ElementProvider.POWER_CEILING + 1e-9,
			true,
			"and is bounded by the x4 ceiling at %s (read %s)" % [rank_id, growth]
		)
		# 2. The prepared defender's answer is REAL: the matchup halves the term, and the
		# ward/root/will defence moves the mitigation contest off zero.
		assert_eq(
			answer < 0.55,
			true,
			(
				"a prepared defender at least halves a full-mastery blow at %s (read %s)"
				% [rank_id, answer]
			)
		)
		assert_eq(
			float(answered["mitigation_rate"]) > 0.0,
			true,
			"and the authored resistance moved the contest off zero at %s" % rank_id
		)
		assert_eq(
			float(answered["mitigation_rate"]) < CombatTuning.shipped().mitigation_ceiling,
			true,
			"while never reaching the ceiling — no build is immune at %s" % rank_id
		)
	# 3. Both halves are realm-invariant at a FIXED mastery: the attacker's power MULT and
	# the defender's answer are written from ONE `realm.power`, so the relationship is the
	# same number at R1 and at the top of the ladder (ADR 0069/0200's whole claim).
	for mastery in [600.0]:
		var neutral_first := _hit(mastery, &"qi_refining", &"", 0.0, 0.0, 0.0)
		var neutral_last := _hit(mastery, &"primordial_origin", &"", 0.0, 0.0, 0.0)
		var resisted_first := _hit(
			mastery, &"qi_refining", WATER, DEFENDER_ROOT_CAP, DEFENDER_WILL_TOP, ward
		)
		var resisted_last := _hit(
			mastery, &"primordial_origin", WATER, DEFENDER_ROOT_CAP, DEFENDER_WILL_TOP, ward
		)
		var first := (
			float(resisted_first["elemental_term"]) / float(neutral_first["elemental_term"])
		)
		var last := float(resisted_last["elemental_term"]) / float(neutral_last["elemental_term"])
		assert_almost_eq(
			last,
			first,
			(
				"the prepared answer is realm-invariant at a fixed mastery (R1 %s vs R30 %s)"
				% [first, last]
			),
			1e-9
		)


# --- builders ------------------------------------------------------------------------


func _hit(
	mastery: float,
	rank_id: StringName,
	defender_element: StringName,
	fire_affinity: float,
	will: float,
	ward: float
) -> Dictionary:
	var tuning := CombatTuning.shipped()
	var attacker := _attacker(mastery, rank_id)
	var target := _defender(rank_id, fire_affinity, will, ward)
	var ctx := AttackContext.new(attacker, target, null, tuning, 100.0)
	ctx.set_data(QiDamage.ELEMENT_RULES_KEY, ElementsApi.default_rules())
	ctx.set_data(QiDamage.ELEMENT_KEY, FIRE)
	ctx.set_data(QiDamage.ELEMENT_SHARE_KEY, FULL_SHARE)
	if defender_element != &"":
		ctx.set_data(QiDamage.DEFENDER_ELEMENT_KEY, defender_element)
	var mechanism := QiDamage.new()
	mechanism.tuning = tuning
	return mechanism.breakdown(ctx)


func _attacker(mastery: float, rank_id: StringName) -> Actor:
	var actor := (
		Actor
		. new(
			&"answer_attacker",
			{
				Stat.SPIRIT: 10.0,
				Stat.APTITUDE: 10.0,
				Stat.PHYSIQUE: 10.0,
				Stat.COMPREHENSION: 10.0,
				ElementStats.mastery_id(FIRE): mastery,
			}
		)
	)
	actor.add_resource(ResourcePool.new(&"health", 1000.0))
	actor.set_path(PathState.new(PathState.QI, rank_id))
	actor.set_affinity(FIRE, ATTACKER_AFFINITY)
	ElementsApi.attach(actor)
	return actor


## The defender's FIRE affinity is the resistance root (`element_defense_<e>` reads the
## defender's own affinity in that element), while the matchup reads the defender's
## NATURE, which the context carries explicitly — the fixture's documented split, because
## a body resists with its training and answers with its nature.
func _defender(rank_id: StringName, fire_affinity: float, will: float, ward: float) -> Actor:
	var actor := Actor.new(
		&"answer_defender", {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 10.0, Stat.WILL: will}
	)
	actor.add_resource(ResourcePool.new(&"health", 5000.0))
	actor.set_path(PathState.new(PathState.QI, rank_id))
	if fire_affinity > 0.0:
		actor.set_affinity(FIRE, fire_affinity)
	ElementsApi.attach(actor)
	if ward > 0.0:
		actor.stats.add_modifier(
			StatModifier.new(
				ElementStats.defense_id(FIRE), Stat.Op.FLAT, ward, &"answer_fixture_ward"
			)
		)
	return actor


## The authored ward's `element_defense_fire`, read from the shipped item. A content edit
## that removes or re-elements the ward fails the content-contract assertion rather than
## silently measuring a weaker defender.
func _ward_value() -> float:
	var item := load(WARD_PATH) as ItemDef
	if item == null:
		return 0.0
	for entry in item.fixed_modifiers:
		if StringName(entry.get("option_id", &"")) == ElementStats.defense_id(FIRE):
			return float(entry.get("value", 0.0))
	return 0.0


func _print_row(
	rank_id: StringName,
	cap: float,
	bare: Dictionary,
	trained: Dictionary,
	answered: Dictionary,
	growth: float,
	answer: float
) -> void:
	print(
		(
			"%-20s cap %6.0f | power %7.3f -> %7.3f (x%.3f) | answered x%.3f | m %.4f"
			% [
				rank_id,
				cap,
				float(bare["elemental_power"]),
				float(trained["elemental_power"]),
				growth,
				answer,
				float(answered["mitigation_rate"])
			]
		)
	)
