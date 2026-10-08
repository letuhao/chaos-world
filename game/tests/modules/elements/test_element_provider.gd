extends TestCase

## ADR 0004/0002: the elements module contributes per-element derived stats.


func test_power_from_affinity() -> void:
	var actor := Actor.new(&"mage")
	actor.set_affinity(ElementStats.FIRE, 10.0)
	ElementsApi.attach(actor)
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)), 10.0, "fire power"
	)


func test_mastery_scales_power() -> void:
	var actor := Actor.new(&"mage", {ElementStats.mastery_id(ElementStats.FIRE): 5.0})
	actor.set_affinity(ElementStats.FIRE, 10.0)
	ElementsApi.attach(actor)
	# BL-0938: the mastery term rides the saturating curve `m / (m + 300)` at the
	# owner's x4 ceiling, so five points are worth less than the old linear five.
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)),
		10.0 * (1.0 + 3.0 * 5.0 / 305.0),
		"scaled"
	)


func test_resistance_from_affinity_and_will() -> void:
	var actor := Actor.new(&"mage", {Stat.WILL: 10.0})
	actor.set_affinity(ElementStats.WATER, 10.0)
	ElementsApi.attach(actor)
	assert_almost_eq(
		actor.stats.derived(ElementStats.defense_id(ElementStats.WATER)), 7.0, "defense"
	)


## ADR 0004's pure-qi channel: an ELEMENTLESS attack reads the omni pair, built from the
## SUMMED affinity and the SUMMED mastery. A specialist reads its own element's number in
## the omni channel; breadth pays linearly on both halves.
func test_the_omni_pair_reads_the_summed_affinity_and_mastery() -> void:
	var actor := (
		Actor
		. new(
			&"mage",
			{
				ElementStats.mastery_id(ElementStats.FIRE): 5.0,
				ElementStats.mastery_id(ElementStats.WATER): 2.0,
			}
		)
	)
	actor.set_affinity(ElementStats.FIRE, 10.0)
	actor.set_affinity(ElementStats.WATER, 4.0)
	ElementsApi.attach(actor)
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.OMNI)),
		14.0 * (1.0 + 3.0 * 7.0 / 307.0),
		(
			"the omni power is the summed affinity scaled by the summed mastery on the tier-1"
			+ " saturating curve"
		)
	)
	assert_almost_eq(
		actor.stats.derived(ElementStats.defense_id(ElementStats.OMNI)),
		14.0 * 0.5,
		"and the omni defense is the summed affinity's half, plus will's fifth"
	)


## The invariant that makes pure qi a real CHOICE rather than a tax: a body with one
## affinity and all its mastery in that element reads the SAME number in the omni channel
## as in its own element. What it trades is the matchup (always NEUTRAL), not the number.
func test_a_specialist_reads_the_same_power_in_the_omni_channel() -> void:
	var actor := Actor.new(&"mage", {ElementStats.mastery_id(ElementStats.FIRE): 5.0})
	actor.set_affinity(ElementStats.FIRE, 10.0)
	ElementsApi.attach(actor)
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.OMNI)),
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)),
		"one affinity, all the mastery in it: the omni channel is the same number"
	)
