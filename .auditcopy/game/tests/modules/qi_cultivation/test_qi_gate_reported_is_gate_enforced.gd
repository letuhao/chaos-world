extends TestCase

## The qi screen's Train Channel button must reach the DEPTH half of the gate, and
## the gate it reports must be the gate that is enforced.
##
## Two defects, one cause. `QiCultivationApi.panel_state` reported the STANDING
## realm's channel gate (`api.gd`, `QiRealmSeed.for_realm(state.rank_id)`) while
## `QiBreakthroughCondition.can_breakthrough` enforces the NEXT realm's
## (`breakthrough_condition.gd:10-11`). So the read model described a gate nothing
## checks — in the same dictionary whose `target`, `can_attempt` and `unmet` all
## described the next realm's.
##
## The screen then acted on that stale gate: it selected its channel on
## `channel.meets(required_channel_state)`, which is state-only BY DESIGN
## (`MeridianState.meets` is a rank comparison plus the injury flag). From the first
## realm whose demand is pure depth every channel already met the state, every
## candidate was skipped, every press did nothing, and `QiTraining.refine_meridian`
## was never reached. ADR 0158 fixed the selection in the facade and left the screen
## holding its own loop; until now the depth half was reachable in tests and dead in
## play.
##
## The red here is BEHAVIOURAL, not textual: it drives the real handler on a real
## screen and reads the channel's depth. Restoring the old loop turns it red again.

const SCREEN := "res://src/ui/screens/qi_cultivation_screen.tscn"

## Not a suite: the runner only collects `test_*.gd`. Shared fixtures, so this file
## resolves items the way production does instead of minting a stub def.
const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

const PATH := QiPath.PATH_ID

## Elixirs one channel needs to climb closed -> open -> expanded -> strengthened.
## Three, plus slack; a fixed bound, so a channel that will not climb reports a
## named shortfall instead of pressing forever.
const CLIMB_BOUND := 6

## `spirit_transformation` is the first realm whose OWN gate asks for depth, so its
## gate's state half (`strengthened`) is satisfiable while the depth half is not —
## which is exactly the state a state-only skip mishandles. Its successor
## `void_refinement` asks for depth 2, and the standing realm's cap of 5 can pay it.
const REALM := &"spirit_transformation"


func _screen() -> QiCultivationScreen:
	return (load(SCREEN) as PackedScene).instantiate() as QiCultivationScreen


## An actor on the qi path built the way the app builds one. `meridians` is left
## empty on purpose — `attach` does not unlock channels and production unlocks them
## in `QiTraining.synchronize`, so a suite calling `unlock_for_realm` itself would
## measure a state it wrote rather than one the path earned.
func _joined(rank_id: StringName) -> Actor:
	var actor := Actor.new(
		&"qi_depth_hero", {Stat.COMPREHENSION: 0.0, QiStats.DANTIAN_CAPACITY: 100.0}
	)
	actor.set_path(PathState.new(PATH, rank_id))
	QiCultivationApi.attach(actor)
	ItemsApi.attach(actor, 512)
	assert_eq(QiCultivationApi.cultivate(actor, 1.0), true, "cultivate drives synchronization")
	return actor


## Climb every channel on the network to `strengthened` and stop there, depth 0.
##
## Every transition goes through the public verb, so the state measured below is one
## the path earned. Two bounded loops: an outer `for` over `MeridianDefaults.all()`
## (a fixed content list this does not grow) and an inner one on a FIXED count that
## names the condition which failed to converge.
func _all_channels_strengthened(actor: Actor) -> void:
	var seed := QiRealmSeed.for_realm(REALM)
	assert_ne(seed, null, "the authored seed exists")
	assert_eq(Probe.stock(actor, seed.training_item, 256), true, "the authored elixir exists")
	for definition in MeridianDefaults.all():
		var pressed := 0
		while pressed < CLIMB_BOUND:
			var channel := actor.meridians.get_meridian(definition.id)
			if channel == null or channel.meets(&"strengthened"):
				break
			pressed += 1
			if not QiCultivationApi.train_channel(actor, definition.id):
				break


## Empty the pack of the realm's channel elixir, so a refusal is a refusal and not a
## leftover. The climb above stocks far more than it spends, which is what makes the
## empty-pack state here something the fixture has to establish rather than assume.
func _spend_every_elixir(actor: Actor) -> void:
	var seed := QiRealmSeed.for_realm(REALM)
	var inventory := ItemsApi.inventory(actor)
	var held := inventory.count(seed.training_item)
	if held > 0:
		inventory.remove(seed.training_item, held)
	assert_eq(inventory.has(seed.training_item), false, "the pack is empty of elixirs")


# --- Gap 1: the screen reaches the depth half -----------------------------------


## THE test. Every channel on this actor already meets the gate's STATE, so a
## state-only skip leaves the button with nothing to do — and the depth the real
## gate demands is one elixir away. Pressing must spend it.
##
## Before the fix this returned false and left `lung` at depth 0 forever: the press
## skipped every candidate, the terminal message read "No channel left to train",
## and no amount of elixirs moved the ladder.
func test_the_screen_deepens_a_channel_whose_state_already_meets_the_gate() -> void:
	var screen := _screen()
	var actor := _joined(REALM)
	screen.setup(actor)
	_all_channels_strengthened(actor)

	var lung := actor.meridians.get_meridian(&"lung")
	assert_eq(lung.state, &"strengthened", "the state half is met, which is the trap")
	assert_eq(lung.refinement, 0, "and no depth has been paid for yet")

	assert_eq(
		screen.act_train_next_channel(),
		true,
		"a press must still find work: the gate's DEPTH half is owed"
	)
	var after := actor.meridians.get_meridian(&"lung")
	assert_eq(after.refinement, 1, "the elixir went into depth, not into a skipped channel")
	var message := String(screen.summary().get("message", ""))
	assert_eq(message, "Trained lung", "and the screen names the channel it trained (%s)" % message)
	screen.free()


## The refusal must still name the PRICE, not collapse to "nothing to do": the same
## two sentences ADR 0150 required, now assembled from the facade's published
## `owed_channels` / `training_price` instead of a loop this screen ran itself.
func test_a_refused_press_still_names_the_price_it_could_not_pay() -> void:
	var screen := _screen()
	var actor := _joined(REALM)
	screen.setup(actor)
	_all_channels_strengthened(actor)
	_spend_every_elixir(actor)

	assert_eq(screen.act_train_next_channel(), false, "an empty pack trains nothing")
	var message := String(screen.summary().get("message", ""))
	assert_eq(
		message.contains("elixir absent") and message.contains("still owed"),
		true,
		"the outstanding work and its price are both named (%s)" % message
	)
	assert_eq(
		message.contains("No channel left"),
		false,
		"and never the one answer that cannot be true while depth is owed"
	)
	screen.free()


# --- Gap 3: the reported gate is the enforced gate -------------------------------


## The reported gate must be the gate `QiBreakthroughCondition` enforces, at EVERY
## boundary — not merely at the one realm where the two happen to agree.
##
## The demand rises one step of depth per realm from `spirit_transformation` on, so
## reading the standing realm's seed made the panel under-report by one whole step
## at 26 of the 29 boundaries: a player was shown a requirement already satisfied
## while the realm they were trying to enter wanted another elixir.
func test_the_reported_channel_gate_is_the_next_realms_gate_at_every_boundary() -> void:
	var realms := RealmDefaults.ladder().realms()
	var mismatched := 0
	var checked := 0
	# Bounded by the ladder's own fixed length, and the body appends nothing.
	for index in range(realms.size() - 1):
		var target := QiRealmSeed.for_realm(realms[index + 1].id)
		if target == null:
			continue
		var live := QiCultivationApi.panel_state(_joined(realms[index].id))
		checked += 1
		if (
			String(live.get("required_channel_state", "")) != String(target.required_channel_state)
			or int(live.get("required_channel_depth", 0)) != target.required_channel_refinement
		):
			mismatched += 1
	assert_eq(checked > 20, true, "the ladder's boundaries were walked (%d)" % checked)
	assert_eq(
		mismatched, 0, "every boundary must report the gate that is enforced, not the one behind it"
	)


## The realm the panel names as its target and the realm whose gate it reports must
## be the same realm. One dictionary describing two realms is the defect; this is
## the invariant that names it.
func test_the_reported_gate_and_the_reported_target_are_the_same_realm() -> void:
	var realms := RealmDefaults.ladder().realms()
	# Bounded by the ladder's fixed length; the body appends nothing.
	for index in range(realms.size() - 1):
		var target_id := String(realms[index + 1].id)
		var target := QiRealmSeed.for_realm(realms[index + 1].id)
		if target == null:
			continue
		var live := QiCultivationApi.panel_state(_joined(realms[index].id))
		assert_eq(
			String(live.get("target", "")),
			target_id,
			"%s reports the realm it is trying to enter" % realms[index].id
		)
		assert_eq(
			int(live.get("required_channel_depth", 0)),
			target.required_channel_refinement,
			"and reports THAT realm's depth, not its own (%s)" % realms[index].id
		)


## At the top of the ladder there is no realm to enter, so no gate is owed. The
## button that trains toward a gate must go dead rather than train toward the gate
## behind the player.
func test_the_terminal_realm_reports_no_gate() -> void:
	var top := RealmDefaults.ladder().size() - 1
	var live := QiCultivationApi.panel_state(_joined(realms_id(top)))
	assert_eq(String(live.get("target", "")), "", "the top realm has no target")
	assert_eq(
		String(live.get("required_channel_state", "")),
		"",
		"so no channel gate is owed, and the training button is not offered work"
	)


func realms_id(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id
