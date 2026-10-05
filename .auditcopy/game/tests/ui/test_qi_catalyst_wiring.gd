extends TestCase

## ADR 0201/ADR 0202: `deepen_past_cap` and `meridian_catalyst` were published with
## NO screen caller and NOTHING showing a player the catalyst — a dead verb and an
## invisible price. The owner's ruling is that a published verb is WIRED, not deleted,
## so this suite holds the wiring shut.
##
## The defect this must not reproduce is the one ADR 0158 already recorded on this
## path: `act_train_next_channel` used to walk the channels itself and skip on a
## state-only test, so the DEPTH half of the gate was reachable in tests and dead in
## play. A screen that filtered `deepen_past_cap`'s candidates itself would be that
## same divergence a second time — so the candidate list is the FACADE's, and these
## tests assert that by checking the screen offers nothing the verb would refuse.
##
## Driven as a player drives them: `act_deepen_past_cap()` on the instantiated
## screen, reading `summary()`. The assertion is the CONTRACT — the verb fires, the
## price is spent, the refusal names the price — not one exact sentence (ADR 0150).

const SCREEN := "res://src/ui/screens/qi_cultivation_screen.tscn"
const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

const PATH := QiPath.PATH_ID


func _screen() -> QiCultivationScreen:
	return (load(SCREEN) as PackedScene).instantiate() as QiCultivationScreen


func _actor() -> Actor:
	var actor := Actor.new(
		&"qi_catalyst_hero", {Stat.COMPREHENSION: 10.0, QiStats.DANTIAN_CAPACITY: 100.0}
	)
	ItemsApi.attach(actor, 64)
	actor.set_path(PathState.new(PATH, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	QiCultivationApi.attach(actor)
	QiTraining.synchronize(actor)
	return actor


func _seed(actor: Actor) -> QiRealmSeed:
	return QiRealmSeed.for_realm(actor.path(PATH).rank_id)


func _first_channel(actor: Actor) -> StringName:
	## Bounded by the network's own list with an immediate return (INC-0002).
	for channel in actor.meridians.get_all_meridians():
		return channel.id
	return &""


func _train_to_cap(actor: Actor, channel: StringName, seed: QiRealmSeed) -> void:
	## Press the elixir verb until it refuses, which is exactly the cap. Bounded by a
	## fixed budget taken BEFORE the loop, and the body breaks on the refusal it is
	## waiting for — so it cannot grow its own bound (INC-0002).
	var budget := seed.channel_refinement_cap + 5
	var pressed := 0
	while pressed < budget and QiCultivationApi.train_channel(actor, channel):
		pressed += 1


func _walk_to_cap(actor: Actor) -> StringName:
	## Stock the ELIXIR as well as the catalyst: without it `train_channel` refuses
	## immediately and the channel never reaches the cap, which would leave every
	## assertion below vacuously true about a channel sitting at depth 0. The walk is
	## asserted, not assumed, precisely so that cannot pass quietly.
	var seed := _seed(actor)
	var channel := _first_channel(actor)
	assert_ne(channel, &"", "an unlocked channel")
	assert_eq(Probe.stock(actor, seed.training_item, 16), true, "elixirs for the walk")
	_train_to_cap(actor, channel, seed)
	assert_eq(
		actor.meridians.get_meridian(channel).refinement,
		seed.channel_refinement_cap,
		"the elixir walked it to exactly the standing realm's cap"
	)
	return channel


func _message(screen: QiCultivationScreen) -> String:
	return String(screen.summary().get("message", ""))


# --- the facade publishes the candidates ---------------------------------------


## Below the cap the elixir is the price, so the screen must be given NOTHING to
## offer: a candidate here would be a channel `deepen_past_cap` refuses, which is the
## ADR 0158 divergence in its second coat.
func test_nothing_is_offered_below_the_cap() -> void:
	var actor := _actor()
	var seed := _seed(actor)
	assert_eq(Probe.stock(actor, seed.meridian_catalyst, 1), true, "a catalyst in hand")
	var channel := _first_channel(actor)
	assert_ne(channel, &"", "an unlocked channel")
	# Walk to ONE step below the cap and stop there, so "below the cap" is a state this
	# actor was really in rather than a fresh channel that never moved. The bound is
	# snapshotted BEFORE the loop and the body only advances the pressed count, so it
	# cannot grow its own bound (INC-0002).
	assert_eq(Probe.stock(actor, seed.training_item, 16), true, "elixirs for the walk")
	var presses := 0
	var below := seed.channel_refinement_cap - 1
	while presses < below and QiCultivationApi.train_channel(actor, channel):
		presses += 1
	assert_eq(
		actor.meridians.get_meridian(channel).refinement < seed.channel_refinement_cap,
		true,
		"and it really is below the cap"
	)

	var live := QiCultivationApi.panel_state(actor)
	assert_eq(live.get("deepen_channels", []).size(), 0, "no work past the cap yet")
	assert_eq(live.get("deepen_price", ""), "meridian_catalyst", "and the price is still named")


## At the cap the facade names the channel, so the screen never has to decide which
## one a player means.
func test_the_facade_names_the_channel_past_the_cap() -> void:
	var actor := _actor()
	var channel := _walk_to_cap(actor)

	var live := QiCultivationApi.panel_state(actor)
	var offered: Array = live.get("deepen_channels", [])
	assert_eq(offered.has(String(channel)), true, "the capped channel is offered (%s)" % offered)


# --- the screen drives the verb -------------------------------------------------


## The dead verb is now reachable, and the whole point of the catalyst: the step no
## elixir can buy.
func test_the_screen_spends_the_catalyst_past_the_cap() -> void:
	var screen := _screen()
	var actor := _actor()
	screen.setup(actor)
	var seed := _seed(actor)
	var inventory := ItemsApi.inventory(actor)
	assert_eq(Probe.stock(actor, seed.meridian_catalyst, 1), true, "one catalyst in hand")
	var channel := _walk_to_cap(actor)

	assert_eq(screen.act_deepen_past_cap(), true, "the screen deepened it")
	assert_eq(inventory.count(seed.meridian_catalyst), 0, "and it cost one catalyst")
	assert_eq(
		actor.meridians.get_meridian(channel).refinement,
		seed.channel_refinement_cap + QiTraining.CATALYST_DEPTH_STEP,
		"exactly one step past the cap"
	)
	screen.free()


## The refusal names the PRICE, never "no work left" — the work IS there and the
## catalyst is what is missing (ADR 0150).
func test_a_refused_catalyst_names_the_price() -> void:
	var screen := _screen()
	var actor := _actor()
	screen.setup(actor)
	var seed := _seed(actor)
	_walk_to_cap(actor)
	assert_eq(Probe.stock(actor, seed.meridian_catalyst, 0), true, "and no catalyst in hand")

	assert_eq(screen.act_deepen_past_cap(), false, "no catalyst, no step")
	var said := _message(screen)
	assert_eq(said.to_lower().contains("catalyst"), true, "the price is named (%s)" % said)
	assert_eq(
		said.to_lower().contains("no channel is past"),
		false,
		"and the work is not denied, because there is some (%s)" % said
	)
	screen.free()


## A burned channel is `recover`'s priced job (ADR 0141), so it must not appear as a
## catalyst candidate — two prices for one repair is how they drifted apart.
func test_a_burned_channel_is_never_offered() -> void:
	var actor := _actor()
	var channel := _walk_to_cap(actor)
	actor.meridians.damage_meridian(channel)

	var offered: Array = QiCultivationApi.panel_state(actor).get("deepen_channels", [])
	assert_eq(offered.has(String(channel)), false, "a burn is repaired, not deepened")
