extends TestCase

## ADR 0057, measured rather than assumed: the meridian network is core state on
## the Actor and reaches `MindProvider` through `StatContext.meridian_network()`.
##
## This path was the LIVE defect. `MindProvider` read
## `context.component(&"meridians")`, nothing ever wrote that key for the mind
## path, so a trained network moved `MENTAL_DEFENSE` by 0.000000 — no error, no
## log, no failing test. `test_mind_provider.gd` used to hand-register the
## component itself, which is exactly what hid it.
##
## Every assertion here is against the RUNTIME VALUE a stat came out as. Asserting
## the accessor EXISTS would pass against the broken code.

const LUNG := &"lung"
const RANK := &"qi_refining"
const PERCEPTION := 20.0
const CLARITY := 10.0
const WILL := 10.0
## (clarity * 2.0 + will * 0.5) and (perception * 1.5 + clarity * 1.0), the two
## unfactored shapes the provider multiplies by the rate and then the bonus.
const RAW_DEFENSE := CLARITY * 2.0 + WILL * 0.5
const RAW_TECHNIQUE := PERCEPTION * 1.5 + CLARITY * 1.0


func _actor() -> Actor:
	var actor := (
		Actor
		. new(
			&"mind_cultivator",
			{
				Stat.SPIRIT: 10.0,
				Stat.WILL: WILL,
				Stat.COMPREHENSION: 10.0,
				MindStats.PERCEPTION: PERCEPTION,
				MindStats.MENTAL_CLARITY: CLARITY,
			}
		)
	)
	actor.set_path(PathState.new(MindPath.PATH_ID, RANK))
	MindCultivationApi.attach(actor)
	return actor


## `closed -> open -> expanded -> strengthened`, then three refinement steps.
func _train(network: MeridianNetwork) -> void:
	network.unlock_for_realm(&"qi_refining")
	network.open_meridian(LUNG)
	network.expand_meridian(LUNG)
	network.strengthen_meridian(LUNG)
	network.refine_meridian(LUNG, 3)


func test_a_trained_network_raises_mental_defense_by_its_power_bonus() -> void:
	var actor := _actor()
	_train(actor.meridians)
	actor.mark_stats_dirty()
	var bonus := actor.meridians.get_power_bonus()
	assert_ne(bonus, 0.0, "the probe network is genuinely trained")
	assert_almost_eq(
		actor.stats.derived(MindStats.MENTAL_DEFENSE),
		RAW_DEFENSE * (1.0 + bonus),
		"defense carries the bonus"
	)


func test_a_trained_network_raises_technique_power_by_its_power_bonus() -> void:
	var actor := _actor()
	_train(actor.meridians)
	actor.mark_stats_dirty()
	var bonus := actor.meridians.get_power_bonus()
	assert_almost_eq(
		actor.stats.derived(MindStats.MIND_TECHNIQUE_POWER),
		RAW_TECHNIQUE * (1.0 + bonus),
		"technique power carries the bonus"
	)


## The half that proves the term is READ, not merely non-null: same actor, same
## context, a network that exists and was never strengthened.
func test_an_untrained_network_pays_nothing() -> void:
	var actor := _actor()
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.mark_stats_dirty()
	assert_almost_eq(
		actor.stats.derived(MindStats.MENTAL_DEFENSE), RAW_DEFENSE, "closed channels are worth zero"
	)
	assert_almost_eq(
		actor.stats.derived(MindStats.MIND_TECHNIQUE_POWER),
		RAW_TECHNIQUE,
		"and so is technique power"
	)


## The comparison that makes the two above mean something: one variable changed.
func test_strengthening_the_network_is_what_moves_the_stat() -> void:
	var plain := _actor()
	var trained := _actor()
	_train(trained.meridians)
	trained.mark_stats_dirty()
	var gain: float = (
		trained.stats.derived(MindStats.MENTAL_DEFENSE)
		- plain.stats.derived(MindStats.MENTAL_DEFENSE)
	)
	assert_ne(gain, 0.0, "strengthening moved defense")
	assert_almost_eq(
		gain, RAW_DEFENSE * trained.meridians.get_power_bonus(), "by exactly the power bonus"
	)


## Refinement depth and resonance both ride inside `get_power_bonus`, so a deeper
## training run must pay strictly more than a shallow one. If the provider were
## reading a null network, or a stale copy, these would be equal.
func test_deeper_training_pays_strictly_more() -> void:
	var shallow := _actor()
	shallow.meridians.unlock_for_realm(&"qi_refining")
	shallow.meridians.open_meridian(LUNG)
	shallow.meridians.expand_meridian(LUNG)
	shallow.meridians.strengthen_meridian(LUNG)
	shallow.mark_stats_dirty()
	var deep := _actor()
	deep.meridians.unlock_for_realm(&"qi_refining")
	deep.meridians.open_meridian(LUNG)
	deep.meridians.expand_meridian(LUNG)
	deep.meridians.strengthen_meridian(LUNG)
	deep.meridians.refine_meridian(LUNG, 3)
	deep.meridians.set_resonance_rank(4)
	deep.mark_stats_dirty()
	assert_eq(
		(
			deep.stats.derived(MindStats.MENTAL_DEFENSE)
			> shallow.stats.derived(MindStats.MENTAL_DEFENSE)
		),
		true,
		"refinement and resonance raise defense"
	)
	assert_almost_eq(
		deep.stats.derived(MindStats.MENTAL_DEFENSE),
		RAW_DEFENSE * (1.0 + deep.meridians.get_power_bonus()),
		"and by the deeper network's own aggregate"
	)


## ADR 0057 §Decision bullet 4, on the path that had no copy to begin with. Both
## halves together: the bag is empty AND the stat pays, so re-planting a component
## cannot satisfy this suite.
func test_the_network_is_not_a_module_component() -> void:
	var actor := _actor()
	_train(actor.meridians)
	actor.mark_stats_dirty()
	assert_eq(actor.component(&"meridians"), null, "no module owns a meridians component")
	assert_ne(actor.stats.derived(MindStats.MENTAL_DEFENSE), RAW_DEFENSE, "the stat pays anyway")


## The honest ABSENT case: a context built with no network contributes no bonus
## and does not crash. Its number equals the untrained one, because an owner with
## no network has nothing to train.
func test_a_context_with_no_network_answers_the_untrained_number() -> void:
	var actor := (
		Actor
		. new(
			&"bare",
			{
				Stat.WILL: WILL,
				MindStats.PERCEPTION: PERCEPTION,
				MindStats.MENTAL_CLARITY: CLARITY,
			}
		)
	)
	var context := StatContext.new(
		actor.stats.base_ref(),
		actor.resources,
		actor.traits,
		actor.affinities,
		actor.paths,
		actor.components
	)
	assert_eq(context.meridian_network(), null, "a bare context states the absence")
	var values := MindProvider.new().contribute(context)
	assert_almost_eq(
		float(values[MindStats.MENTAL_DEFENSE]), RAW_DEFENSE, "and contributes no meridian bonus"
	)


## The accessor's own contract from the provider's side: what `contribute` reads is
## the network the context carries, which is the actor's live field.
func test_the_provider_reads_the_actors_own_network() -> void:
	var actor := _actor()
	var context: StatContext = actor.stats._context
	assert_eq(context.meridian_network(), actor.meridians, "the context carries the live network")
	assert_ne(context.meridian_network(), null, "and it is not a placeholder")
