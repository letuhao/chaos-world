extends TestCase

## ADR 0088's potency is a REUSE of `element_power_<e>` — and this suite is the proof
## that the reuse is CONNECTED, which it was not.
##
## ## The defect, stated as arithmetic
##
## `combat_damage.tres` shipped `status_potency_floor = 1.0` over
## `status_potency_scale = 0.25`, so `potency = maxf(1.0, element_power_<e> * 0.25)`.
## `element_power_<e>` is `affinity * (1 + mastery * 0.1 / tier_divisor)`
## (`ElementProvider`), which spans **0.10 .. 1.20** across every realistic build — the
## shipped `commonborn` race at 2.0 affinity and zero mastery reads 0.20, and affinity 1.0
## at mastery 10 reads 2.00. That whole band maps to 0.025 .. 0.30, all of it under the
## floor, so EVERY status in the game landed at magnitude exactly 1.0 and two different
## builds dealt identical status damage. The audit measured the crossover: potency needed
## `element_power > 4.0` to leave the floor, which no shipped build reaches.
##
## ## What is TUNING and what is LOGIC
##
## The fix is DATA, because ADR 0087 records these numbers as provisional and
## `StatusApply.potency_of`'s shape is not this module's to change. So this suite asserts
## RELATIONSHIPS between two actors and between two tiers, and reads every number out of
## the `.tres`. The one assertion that names a figure is the floor test, and it reads the
## figure rather than restating it — so a balance pass that moves either constant has to
## move this file's expectations, which is the correct direction of travel.

## The element every case resolves power for. Fire is tier 1, so its mastery divisor is
## exactly 1.0 and the tier-2 tax below cannot leak into the tier-1 rows.
const FIRE := ElementStats.FIRE
## A tier-2 element, for the divisor row. `lightning` is `ElementDefaults.advanced()`'s
## first entry and is tier 2 in the shipped rules.
const LIGHTNING := ElementStats.LIGHTNING

## The affinity ladder. Authored-content-shaped rather than tuned: two orders of magnitude
## apart, so "a low-affinity actor" and "a high-affinity actor" cannot be the same body
## under any retune of the `.tres`.
const LOW_AFFINITY := 0.2
const HIGH_AFFINITY := 2.0

## The status id this suite applies. Module-local on purpose — see the file header.
const _STATUS := &"test_potency_probe"

## The mastery the top of the realistic band is measured at. Not a tuned figure: any value
## inside the shipped ladder works, and the relationship assertions do not depend on it.
const _MASTERY_TOP := 10.0

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


# --- the assertion that was impossible before --------------------------------------


## THE case. Two actors with DIFFERENT authored affinity, same element, same tuning, same
## status — and they land it at different potency.
##
## Before the retune both read `status_potency_floor` and returned an identical number, so
## this could not have been asserted at any affinity: the comparison was vacuous rather
## than wrong. Asserted as a strict inequality AND against the exact authored arithmetic,
## so it fails both if the channel goes dead again and if the two sides drift apart.
func test_two_actors_with_different_affinity_land_the_same_status_at_different_potency() -> void:
	var low := _elemental(&"low", LOW_AFFINITY)
	var high := _elemental(&"high", HIGH_AFFINITY)
	var low_potency := StatusApply.potency_of(low, _tuning, FIRE)
	var high_potency := StatusApply.potency_of(high, _tuning, FIRE)
	# The control that makes the case above non-vacuous: the two bodies really do derive
	# different elemental power, so a failure here is the CONTENT and a failure above is
	# the potency channel.
	var low_power := low.stats.derived(ElementStats.power_id(FIRE))
	var high_power := high.stats.derived(ElementStats.power_id(FIRE))
	assert_eq(
		high_power > low_power,
		true,
		"the fixture really does produce two different powers: %s and %s" % [low_power, high_power]
	)
	assert_eq(
		high_potency > low_potency,
		true,
		(
			"and potency must follow: low affinity read %s, high affinity read %s"
			% [low_potency, high_potency]
		)
	)
	assert_almost_eq(
		high_potency - low_potency,
		(high_power - low_power) * _tuning.status_potency_scale,
		"the gap is exactly the power gap times the authored scale",
		1e-9
	)


## The same claim end to end through the SPINE, so it is a landed status rather than a
## function call: two attackers of different affinity resolve the same clean hit on the
## same kind of defender and the statuses they write carry different magnitudes.
##
## The status id is module-local for the reason `test_status_application.gd` gives: a
## suite that reused a real status id would collide with whatever the other combat_engine
## suites put on the same fixture actors.
func test_the_spine_writes_a_different_magnitude_for_two_different_attackers() -> void:
	var weak_target := CombatTestKit.actor(&"weak_target")
	var strong_target := CombatTestKit.actor(&"strong_target")
	var weak_result := _resolve(&"weak_hero", LOW_AFFINITY, weak_target, 90210)
	var strong_result := _resolve(&"strong_hero", HIGH_AFFINITY, strong_target, 90210)
	assert_eq(bool(weak_result[StatusApply.APPLIED]), true, "the weak attacker lands its status")
	assert_eq(bool(strong_result[StatusApply.APPLIED]), true, "so does the strong one")
	assert_eq(
		float(strong_result[&"potency"]) > float(weak_result[&"potency"]),
		true,
		(
			"and the applied magnitudes differ: %s vs %s"
			% [weak_result[&"potency"], strong_result[&"potency"]]
		)
	)


## A low-affinity actor still inflicts a REAL, NON-ZERO potency — and it respects the
## floor rather than collapsing through it.
##
## Two properties, and the second is the one the retune had to preserve: ADR 0088's floor
## exists so an actor with no elemental power at all still lands a visible status, so the
## answer must never read below the authored floor. A potency of exactly 0.0 would be a
## debuff that applies and does nothing, which is the silent shape the floor was written
## to prevent.
func test_a_low_affinity_actor_still_lands_a_non_zero_floor_respecting_potency() -> void:
	var floor_value := _tuning.status_potency_floor
	assert_eq(floor_value > 0.0, true, "the shipped floor is still a positive number")
	# An actor with NO affinity at all: the floor case ADR 0088 actually wrote down.
	var bare := _elemental(&"bare", 0.0)
	assert_almost_eq(
		bare.stats.derived(ElementStats.power_id(FIRE)),
		0.0,
		"an untrained element derives no power, which is the case the floor is for",
		1e-12
	)
	assert_almost_eq(
		StatusApply.potency_of(bare, _tuning, FIRE),
		floor_value,
		"and its potency is exactly the authored floor",
		1e-12
	)
	# The low-affinity actor is above that floor and still low — the realistic band, not a
	# degenerate corner. Read against the authored scale so a retune cannot pass this by
	# moving both numbers together.
	var low := _elemental(&"low", LOW_AFFINITY)
	var low_power := low.stats.derived(ElementStats.power_id(FIRE))
	assert_eq(
		low_power * _tuning.status_potency_scale > floor_value,
		true,
		(
			"the low build's potency (%s) clears the floor (%s), so the channel is live"
			% [low_power * _tuning.status_potency_scale, floor_value]
		)
	)
	var potency := StatusApply.potency_of(low, _tuning, FIRE)
	assert_eq(potency > 0.0, true, "a low-affinity actor still lands a real status")
	assert_eq(potency >= floor_value, true, "and its potency never dips below the authored floor")
	assert_almost_eq(
		potency,
		low_power * _tuning.status_potency_scale,
		"which is the authored scale over the power it actually derives",
		1e-9
	)


## ## ADR 0069's tier-2 tax survives
##
## `ElementProvider` divides the MASTERY term by `1 + (tier - 1) * TIER_MASTERY_STEP`, so
## at equal affinity and equal mastery a tier-2 element derives strictly LESS power than
## a tier-1 one. Potency reads that same scalar (ADR 0088's reuse), so the tax has to
## reach potency — asserted here rather than inferred, because the retune moved the scale
## the tax is expressed through.
func test_tier_two_remains_taxed_against_tier_one_at_equal_mastery() -> void:
	var mastery := 5.0
	var tier_one := _elemental(&"t1", HIGH_AFFINITY, mastery, FIRE)
	var tier_two := _elemental(&"t2", HIGH_AFFINITY, mastery, LIGHTNING)
	var one_power := tier_one.stats.derived(ElementStats.power_id(FIRE))
	var two_power := tier_two.stats.derived(ElementStats.power_id(LIGHTNING))
	var one_potency := StatusApply.potency_of(tier_one, _tuning, FIRE)
	var two_potency := StatusApply.potency_of(tier_two, _tuning, LIGHTNING)
	# Equal affinity and equal mastery is the whole premise, so the only thing left to
	# check is that the tier really is what differs. Asserted on the RULES rather than on
	# the two bodies' fire/lightning powers: shipped races carry different authored
	# affinities per element, so comparing a body's fire power to its lightning power
	# compares two affinities and says nothing about the divisor.
	var rules := ElementsApi.default_rules()
	assert_eq(rules.element(FIRE).tier, 1, "fire is a tier-1 element in the shipped rules")
	assert_eq(
		rules.element(LIGHTNING).tier, 2, "lightning is a tier-2 element in the shipped rules"
	)
	assert_eq(
		two_power < one_power,
		true,
		"tier 2 pays the mastery tax: power %s against tier 1's %s" % [two_power, one_power]
	)
	assert_eq(
		two_potency < one_potency,
		true,
		"and potency must still be taxed: %s against %s" % [two_potency, one_potency]
	)
	# The tax is the authored divisor, restated from the provider's own vocabulary rather
	# than as a tuned figure, so a retune of `TIER_MASTERY_STEP` moves this with it. Tier
	# 1's divisor is exactly 1.0, which is why its figure above is the un-taxed one.
	var tier_one_divisor := 1.0 + float(1 - 1) * ElementProvider.TIER_MASTERY_STEP
	var tier_two_divisor := 1.0 + float(2 - 1) * ElementProvider.TIER_MASTERY_STEP
	assert_almost_eq(
		one_power,
		HIGH_AFFINITY * (1.0 + 0.1 / tier_one_divisor * mastery),
		"tier 1's divisor is exactly 1.0, so its power is the un-taxed figure",
		1e-9
	)
	assert_almost_eq(
		two_power,
		HIGH_AFFINITY * (1.0 + 0.1 / tier_two_divisor * mastery),
		"and tier 2's is the same body through the authored divisor",
		1e-9
	)
	assert_eq(
		tier_two_divisor > tier_one_divisor, true, "so the tax is a reduction rather than a bonus"
	)


## ADR 0088's second bullet, asserted against the retuned numbers rather than against the
## old ones: mastery buys "your status LANDS more often" and never "your status HITS
## harder". Penetration is read once, in `elemental_resist`, and never here — so this
## passes only while that stays true.
func test_penetration_still_never_touches_potency() -> void:
	var plain := _elemental(&"plain", HIGH_AFFINITY)
	var piercing := _elemental(&"piercing", HIGH_AFFINITY)
	piercing.stats.add_modifier(CombatStats.rate_modifier(CombatStats.PENETRATION, 1.0, &"test"))
	assert_almost_eq(
		StatusApply.potency_of(piercing, _tuning, FIRE),
		StatusApply.potency_of(plain, _tuning, FIRE),
		"ADR 0088: penetration is a RESIST lever only, so potency is identical",
		1e-12
	)


## Mastery reaches potency ONCE. The retune moved the scale the channel is expressed
## through, and the failure this guards is making mastery a SECOND potency multiplier —
## potency scaling with mastery directly as well as through `element_power_<e>`. Asserted
## as the exact authored ratio: at equal affinity, potency tracks the provider's single
## contribution and nothing else.
func test_mastery_reaches_potency_exactly_once_and_through_element_power() -> void:
	var novice := _elemental(&"novice", HIGH_AFFINITY, 0.0)
	var adept := _elemental(&"adept", HIGH_AFFINITY, 10.0)
	var novice_power := novice.stats.derived(ElementStats.power_id(FIRE))
	var adept_power := adept.stats.derived(ElementStats.power_id(FIRE))
	var novice_potency := StatusApply.potency_of(novice, _tuning, FIRE)
	var adept_potency := StatusApply.potency_of(adept, _tuning, FIRE)
	assert_eq(
		adept_potency > novice_potency,
		true,
		"mastery must still move potency: novice %s, adept %s" % [novice_potency, adept_potency]
	)
	# The ratio is `power * scale` and NOTHING else, so a potency formula that added a
	# second mastery term would break this while leaving the strict inequality above green.
	assert_almost_eq(
		novice_potency / _tuning.status_potency_scale,
		novice_power,
		"potency divided by the authored scale is exactly the power it derives",
		1e-9
	)
	assert_almost_eq(
		adept_potency / _tuning.status_potency_scale, adept_power, "at mastery too", 1e-9
	)


# --- the numbers are DATA ------------------------------------------------------------


## Every tuning constant is read from the shipped `.tres` and none of them is a literal in
## logic. Asserted as RELATIONSHIPS rather than as figures, so a balance pass moves the
## `.tres` and this file keeps saying the same things — except for the one claim that IS a
## balance decision: the floor must sit BELOW the bottom of the realistic band, because a
## floor above it is a ceiling and that is the defect this whole file exists for.
func test_the_potency_tuning_is_data_and_the_floor_cannot_ceil_the_band() -> void:
	var scale := _tuning.status_potency_scale
	var floor_value := _tuning.status_potency_floor
	assert_eq(scale > 0.0, true, "status_potency_scale is authored and positive")
	assert_eq(floor_value > 0.0, true, "status_potency_floor is authored and positive")
	assert_eq(
		_tuning.status_min_apply > 0.0, true, "and the neighbouring gate constant is still authored"
	)
	# The band is measured off the shipped CONTENT rather than asserted as a figure: the
	# baseline race's authored affinity is the BOTTOM of the realistic band (at zero
	# mastery it is its own power), and the TOP is the same race trained to the mastery cap,
	# which is the strongest body the shipped content can build.
	var entry := ElementsApi.default_rules().element(FIRE)
	assert_ne(entry, null, "the shipped rules know the element this suite resolves")
	var divisor := 1.0 + float(maxi(1, entry.tier) - 1) * ElementProvider.TIER_MASTERY_STEP
	var affinity := _baseline_race_affinity(FIRE)
	var bottom := affinity
	var top := affinity * (1.0 + 0.1 / divisor * _MASTERY_TOP)
	assert_eq(
		bottom * scale > floor_value,
		true,
		(
			(
				"the shipped baseline race must clear the floor: power %s x scale %s vs floor %s, "
				% [bottom, scale, floor_value]
			)
			+ "at or below it the floor is a CEILING and every build reads the same potency"
		)
	)
	# And the top of the band stays under the authored cap of the shipped DoTs, or a
	# balance pass would need to audit twenty `.tres` files to use its own tuning.
	var checked := 0
	for status_id in StatusApi.status_ids():
		var def := StatusApi.definition(status_id)
		if def == null or def.magnitude_unit != &"element_power":
			continue
		checked += 1
		assert_eq(
			top * scale <= def.magnitude_cap,
			true,
			(
				"%s caps magnitude at %s, which the top of the band (%s) must not overrun"
				% [String(status_id), def.magnitude_cap, top * scale]
			)
		)
	# Measured rather than assumed: a catalogue with no spending defs would satisfy the
	# loop above vacuously.
	assert_eq(checked > 0, true, "the shipped catalogue really does author element_power defs")


## A rebalance is a `.tres` edit and no `.gd` change: a copy with a different scale moves
## the potency, with no code change. This is ADR 0067's "a rebalance is a `.tres` edit and
## no test re-pins a literal" in practice, and it is the assertion that fails if a literal
## creeps into `potency_of`.
func test_editing_the_tuning_moves_potency_without_touching_a_gd_file() -> void:
	var retuned := _tuning.duplicate(true) as CombatTuning
	retuned.status_potency_scale = _tuning.status_potency_scale * 3.0
	var actor := _elemental(&"retuned", HIGH_AFFINITY)
	var power := actor.stats.derived(ElementStats.power_id(FIRE))
	assert_almost_eq(
		StatusApply.potency_of(actor, retuned, FIRE),
		power * _tuning.status_potency_scale * 3.0,
		"the scale alone moved the potency",
		1e-9
	)
	assert_ne(
		StatusApply.potency_of(actor, retuned, FIRE),
		StatusApply.potency_of(actor, _tuning, FIRE),
		"and the shipped tuning still answers its own number"
	)


# --- internals -----------------------------------------------------------------------


## An actor whose ONLY difference is authored affinity in one element, with the element
## provider attached so `element_power_<e>` is derived at all.
##
## `ElementsApi.attach` rather than `ActorFactory.build` for the reason
## `test_element_wiring.gd` documents in reverse: this suite must not depend on the
## composition root to observe the potency channel, or a rebalance of the channel would be
## untestable whenever anything in `app/` was mid-edit.
func _elemental(
	id: StringName, affinity: float, mastery: float = 0.0, element: StringName = FIRE
) -> Actor:
	var actor := Actor.new(id, {ElementStats.mastery_id(element): mastery})
	actor.set_affinity(element, affinity)
	ElementsApi.attach(actor)
	return actor


## The shipped baseline race's authored affinity for an element — the weakest real body
## there is, read from CONTENT rather than restated so a re-roll of the race moves this.
func _baseline_race_affinity(element: StringName) -> float:
	var def := RaceCatalog.instance().race_definition(&"commonborn")
	return 0.0 if def == null else float(def.affinities.get(String(element), 0.0))


## One clean landed blow carrying the probe status, resolved through the real spine with a
## seeded stream. Returns S12's flattened result row off `effects[]`.
func _resolve(
	attacker_id: StringName, affinity: float, target: Actor, seed_value: int
) -> Dictionary:
	var attacker := _elemental(attacker_id, affinity)
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 25.0
	MechanismSlot.bind(attacker, mechanism)
	var request := {
		"id": _STATUS,
		"chance": 1.0,
		"element": FIRE,
		"scope": String(StatusApply.SCOPE_COMBAT),
		"duration": 10.0,
	}
	var outcome := CombatSpine.resolve_hit(
		attacker,
		target,
		CombatTestKit.technique(100.0),
		_tuning,
		CombatTestKit.rng(seed_value),
		func(ctx: AttackContext) -> AttackContext:
			ctx.set_data(StatusApply.REQUEST_KEY, request)
			return ctx
	)
	for entry in outcome.effects():
		var row := entry as Dictionary
		if StringName(row.get(DamageProposal.KIND, &"")) == StatusApply.EFFECT_KIND:
			return row.duplicate(true)
	return {
		StatusApply.APPLIED: false,
		StatusApply.REFUSED: StatusApply.REFUSE_NOT_CLEAN,
	}
