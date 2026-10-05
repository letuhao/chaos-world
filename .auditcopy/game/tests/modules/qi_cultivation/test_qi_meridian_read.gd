extends TestCase

## ADR 0057, measured rather than assumed: the meridian network is core state on
## the Actor and reaches `QiProvider` through `StatContext.meridian_network()`.
##
## Every assertion here is against the RUNTIME VALUE a stat came out as. A test
## that asserted `has_method("meridian_network")` would pass against the broken
## code — the accessor existed and the provider still answered 0.0 — which is the
## proof gap that let a trained network pay nothing on two of three paths.

const LUNG := &"lung"


func _actor() -> Actor:
	var actor := (
		Actor
		. new(
			&"qi_cultivator",
			{
				Stat.SPIRIT: 10.0,
				Stat.APTITUDE: 10.0,
				QiStats.QI_AFFINITY: 20.0,
				QiStats.QI_CONTROL: 15.0,
				QiStats.DANTIAN_CAPACITY: 30.0,
			}
		)
	)
	QiCultivationApi.attach(actor)
	return actor


## `closed -> open -> expanded -> strengthened`, then three refinement steps.
func _train(network: MeridianNetwork) -> void:
	network.unlock_for_realm(&"qi_refining")
	network.open_meridian(LUNG)
	network.expand_meridian(LUNG)
	network.strengthen_meridian(LUNG)
	network.refine_meridian(LUNG, 3)


## The trained network must MOVE THE NUMBER. Read off the network's own
## aggregate, so the test states the provider's formula rather than a copied
## constant that would drift with the data.
func test_a_trained_network_raises_regen_by_its_flow_bonus() -> void:
	var actor := _actor()
	_train(actor.meridians)
	actor.mark_stats_dirty()
	var bonus := actor.meridians.get_flow_bonus()
	assert_ne(bonus, 0.0, "the probe network is genuinely trained")
	# (20 * 0.3 + 10 * 0.1) * 1.0 * (1 + bonus)
	assert_almost_eq(
		actor.stats.derived(QiStats.QI_REGEN_RATE), 7.0 * (1.0 + bonus), "regen carries the bonus"
	)


func test_a_trained_network_raises_absorption_by_its_flow_bonus() -> void:
	var actor := _actor()
	_train(actor.meridians)
	actor.mark_stats_dirty()
	var bonus := actor.meridians.get_flow_bonus()
	# (20 * 0.5 + 10 * 0.2) * (1 + bonus)
	assert_almost_eq(
		actor.stats.derived(QiStats.QI_ABSORPTION),
		12.0 * (1.0 + bonus),
		"absorption carries the bonus"
	)


## The other half of the term. An UNLOCKED channel that was never opened is a
## real network answering a real 0.0, so this pins that the term is read rather
## than merely non-null: the same actor, the same context, a weaker network.
func test_an_untrained_network_pays_nothing() -> void:
	var actor := _actor()
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.mark_stats_dirty()
	assert_almost_eq(
		actor.stats.derived(QiStats.QI_REGEN_RATE), 7.0, "unopened channels are worth nothing"
	)
	assert_almost_eq(actor.stats.derived(QiStats.QI_ABSORPTION), 12.0, "nor absorption")


## The comparison that makes the first two meaningful: identical actor, identical
## provider, one variable changed.
func test_training_the_network_is_what_changes_the_stat() -> void:
	var plain := _actor()
	var trained := _actor()
	_train(trained.meridians)
	trained.mark_stats_dirty()
	var gain: float = (
		trained.stats.derived(QiStats.QI_REGEN_RATE) - plain.stats.derived(QiStats.QI_REGEN_RATE)
	)
	assert_ne(gain, 0.0, "training moved regen")
	assert_almost_eq(gain, 7.0 * trained.meridians.get_flow_bonus(), "by exactly the flow bonus")


## ADR 0057 §Decision bullet 4: no module registers the network as a component.
## `attach` used to plant it, which is the only reason the forbidden read
## answered a network at all — the wrong read was kept working by a line that
## should not have existed. Both halves are asserted together: the bag is empty
## AND the stat still pays, so this cannot be satisfied by re-planting the copy.
func test_attach_leaves_the_network_out_of_the_component_bag() -> void:
	var actor := _actor()
	_train(actor.meridians)
	actor.mark_stats_dirty()
	assert_eq(actor.component(&"meridians"), null, "no module owns a meridians component")
	assert_ne(actor.component(&"meridians"), actor.meridians, "and it is not an alias either")
	assert_ne(
		actor.stats.derived(QiStats.QI_REGEN_RATE),
		7.0,
		"the stat still pays with the component bag empty"
	)


## A context built with no network is the honest ABSENT case ADR 0057's accessor
## documents. It must answer the untrained number, not a phantom bonus and not a
## crash — and it must be indistinguishable from "trained nothing", because that
## is the only correct value for an owner that has no network to consult.
func test_a_context_with_no_network_answers_the_untrained_number() -> void:
	var actor := Actor.new(&"bare", {QiStats.QI_AFFINITY: 20.0, Stat.APTITUDE: 10.0})
	var context := StatContext.new(
		actor.stats.base_ref(),
		actor.resources,
		actor.traits,
		actor.affinities,
		actor.paths,
		actor.components
	)
	assert_eq(context.meridian_network(), null, "a bare context states the absence")
	var values := QiProvider.new().contribute(context)
	assert_almost_eq(float(values[QiStats.QI_REGEN_RATE]), 7.0, "and contributes no meridian bonus")


## The accessor's own contract from the provider's side: what `contribute` reads
## is the network `StatContext` carries, which is the actor's live field. A
## captured or re-boxed network would fail this.
func test_the_provider_reads_the_actors_own_network() -> void:
	var actor := _actor()
	var context: StatContext = actor.stats._context
	assert_eq(context.meridian_network(), actor.meridians, "the context carries the live network")
	assert_ne(context.meridian_network(), null, "and it is not a placeholder")
