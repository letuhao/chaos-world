extends TestCase

## ADR 0004's "master elements to rise": the qi climb's tier rises gate on ELEMENT
## MASTERY, and the gate a panel reports is the gate the transaction enforces (ADR 0044).
##
## The gate is authored on the realm seed (`QiRealmSeed.element_mastery_required`), the
## comparison lives in ONE predicate (`element_mastery_met`), and the mastery read goes
## through the elements facade — so `QiBreakthroughCondition`, the transaction's
## `execute` and the transaction's `preview` cannot disagree.

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

const PATH := QiPath.PATH_ID

## The realms that carry the gate: the first realm of each tier above mortal.
const RUNGS := [&"spirit_condensation", &"earth_immortal", &"transcendent"]


## The content contract: exactly the tier rises carry a gate, and each asks for its own
## realm's authored labour — the number the elemental climb pays at the same rung, so
## the two ladders share one figure rather than inventing a second.
func test_the_tier_rises_carry_their_own_labour_as_the_element_gate() -> void:
	var gated := 0
	# Bounded by the ladder's own fixed length, and the body appends nothing.
	for realm in RealmDefaults.ladder().realms():
		var seed := QiRealmSeed.for_realm(realm.id)
		if seed == null or seed.element_mastery_required <= 0.0:
			continue
		gated += 1
		assert_eq(RUNGS.has(realm.id), true, "%s is a tier rise" % realm.id)
		assert_almost_eq(
			seed.element_mastery_required,
			seed.progress_required,
			"%s asks for its own realm's labour in element mastery" % realm.id
		)
	assert_eq(gated, RUNGS.size(), "exactly the tier rises carry the gate and nothing else does")


## One point short refuses, and at the rung it opens — while a realm below the first
## rise asks for nothing, so the mortal ladder is untouched.
func test_one_point_short_refuses_and_a_realm_with_no_gate_is_open() -> void:
	for realm_id in RUNGS:
		var seed := QiRealmSeed.for_realm(realm_id)
		assert_ne(seed, null, "%s has a seed" % realm_id)
		assert_eq(
			seed.element_mastery_met(seed.element_mastery_required - 1.0),
			false,
			"%s refuses one point short" % realm_id
		)
		assert_eq(
			seed.element_mastery_met(seed.element_mastery_required),
			true,
			"%s opens at the rung" % realm_id
		)
	var open := QiRealmSeed.for_realm(&"foundation")
	assert_ne(open, null, "foundation has a seed")
	assert_almost_eq(open.element_mastery_required, 0.0, "and no element gate")
	assert_eq(open.element_mastery_met(0.0), true, "so an untrained body stands ready")


## The behavioural half: at a gated boundary the condition and the preview agree, and
## stripping the mastery is what moves BOTH — the reported gate is the enforced gate.
func test_the_reported_element_gate_is_the_enforced_gate() -> void:
	Probe.clear_prepared()
	var target := QiRealmSeed.for_realm(&"spirit_condensation")
	assert_ne(target, null, "the first rise has a seed")
	var actor := Probe.prepared(&"tribulation", target)
	var preview := QiBreakthroughTransaction.preview(actor)
	assert_eq(
		preview["unmet_conditions"].has("insufficient_element_mastery"),
		false,
		"a prepared actor has the mastery the rise asks: %s" % str(preview["unmet_conditions"])
	)
	var condition := QiBreakthroughCondition.new()
	assert_eq(
		condition.can_breakthrough(actor, actor.path(PATH), {}),
		true,
		"and the condition agrees: %s" % str(preview["unmet_conditions"])
	)
	# Strip every element's mastery: the same actor, one gate removed.
	for def in ElementDefaults.all():
		actor.stats.set_base(ElementStats.mastery_id(def.id), 0.0)
	var stripped := QiBreakthroughTransaction.preview(actor)
	assert_eq(
		stripped["unmet_conditions"].has("insufficient_element_mastery"),
		true,
		"the report names the gate it lacks"
	)
	assert_eq(bool(stripped["can_attempt"]), false, "and the attempt is refused")
	assert_eq(
		condition.can_breakthrough(actor, actor.path(PATH), {}),
		false,
		"the condition enforces what the preview reported"
	)
	# Back through the public verbs: one sitting sized to the gate re-opens it. The
	# spark is already there — the probe's own earn opened it — so `practise` accepts.
	assert_eq(
		bool(
			ElementsApi.practise(actor, ElementStats.FIRE, target.element_mastery_required).get(
				"ok", false
			)
		),
		true,
		"one sitting sized to the gate"
	)
	assert_eq(
		condition.can_breakthrough(actor, actor.path(PATH), {}),
		true,
		(
			"and the rise is enterable again: %s"
			% str(QiBreakthroughTransaction.preview(actor)["unmet_conditions"])
		)
	)
	# The cached pre-state was mutated, so it must not outlive this suite.
	Probe.clear_prepared()
