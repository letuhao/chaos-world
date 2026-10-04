extends TestCase

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

## ADR 0201: the qi catalyst family is RESTORED over ADR 0096's deletion, and this
## suite is the reversal made executable.
##
## ADR 0096 deleted 90 catalyst items for two reasons that both still stand, and the
## owner's answer to its own `DEF-0036` ("if yes add the seed field and consume it in
## qi training") is yes. So the family is back and the two reasons are met rather than
## argued away:
##
## 1. **Nothing consumes them** — the orphan that got them deleted. Both roles now
##    have exactly one consumer each, and a catalog item that resolves while nothing
##    spends it is precisely what `DEF-0040` tracked for 120 files.
## 2. **A mandatory item in a gate position removes the player's only lever** — the
##    objection the deletion was really about. So NEITHER catalyst is a gate, and that
##    is asserted here per boundary with an EMPTY inventory: a gate that needed an item
##    would refuse an actor holding none.
##
## The two roles are a pair of decisions, not two taxes, and the pair is the point:
## both are per-realm and neither banks, so the player chooses WHICH of the two things
## a realm can be prepared for to spend on — and pays nothing by choosing neither.

const PATH := QiPath.PATH_ID


## ADR 0096's objection, executed: every one of the 29 boundaries closes on an actor
## holding no catalyst at all. A gate that read a catalyst would report unmet here for
## 29 realms, and the family would be the tax ADR 0096 refused to author.
func test_no_gate_needs_a_catalyst() -> void:
	var ladder := RealmDefaults.ladder()
	var checked := 0
	# Bounded by the ladder's own length, and the body appends nothing to the
	# container it walks (INC-0002).
	for realm in ladder.realms():
		var target := ladder.next(realm.id)
		if target == null:
			break
		var target_seed := QiRealmSeed.for_realm(target.id)
		assert_ne(target_seed, null, "seed for %s" % target.id)
		if target_seed == null:
			continue
		var actor := Probe.prepared(realm.id, target_seed)
		assert_ne(actor, null, "a catalyst-free actor prepared for %s" % target.id)
		if actor == null:
			continue
		# `prepared` stocks the pill and the elixirs and fights and walks the ascent,
		# and nothing else — so any consumable unmet here would be a catalyst.
		var preview := Probe.preview(actor)
		if target.index >= Breakthrough.IMMORTAL_REALM_THRESHOLD:
			# A FRESH actor has never committed the world systems the high tier gates
			# on, which `Probe.prepared` says of itself, so readiness is unprovable at
			# a single boundary there. The claim is narrowed to what IS provable and
			# stated: nothing this gate still wants is a consumable.
			for reason in preview["unmet_conditions"]:
				assert_eq(
					_is_world_system(reason),
					true,
					(
						"%s is unmet by %s, which is a world system and not an item"
						% [target.id, reason]
					)
				)
		else:
			assert_eq(
				bool(preview["can_attempt"]),
				true,
				"%s is enterable with no catalyst: %s" % [target.id, preview["unmet_conditions"]]
			)
		checked += 1
	assert_eq(checked, 29, "and it graded all 29 boundaries")


## The only unmet conditions a fresh actor may carry at the high tier are the ones a
## previous breakthrough commits: the inside world, the world, and the ascent.
func _is_world_system(reason: String) -> bool:
	return reason.contains("world") or reason.contains("ascension")


## Below the cap the elixir is the price, and the catalyst must refuse — otherwise it
## is a cheaper route to a gate and `training_item` stops meaning anything.
func test_the_meridian_catalyst_refuses_below_the_cap() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	var inventory := ItemsApi.inventory(actor)
	assert_eq(Probe.stock(actor, seed.meridian_catalyst, 1), true, "one catalyst in hand")
	assert_eq(Probe.stock(actor, seed.training_item, 8), true, "the channel elixir too")
	var channel := _first_channel(actor)
	assert_ne(channel, &"", "an unlocked channel")

	assert_eq(QiCultivationApi.deepen_past_cap(actor, channel), false, "a fresh channel is refused")
	assert_eq(inventory.count(seed.meridian_catalyst), 1, "without spending anything")
	assert_eq(QiCultivationApi.train_channel(actor, channel), true, "and the elixir still walks it")


## The one step no elixir can buy: at the standing realm's cap `train_channel` refuses
## BEFORE it spends (ADR 0095), and this is the only route past it. The observable
## effect is `get_power_bonus`, the one live reader of depth.
func test_the_meridian_catalyst_buys_the_one_step_no_elixir_can() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	var inventory := ItemsApi.inventory(actor)
	assert_eq(Probe.stock(actor, seed.meridian_catalyst, 1), true, "one catalyst in hand")
	assert_eq(Probe.stock(actor, seed.training_item, 16), true, "the channel elixir too")
	var channel := _first_channel(actor)
	assert_ne(channel, &"", "an unlocked channel")
	_train_to_cap(actor, channel, seed)
	var state := actor.meridians.get_meridian(channel)
	assert_ne(state, null, "the channel exists")
	assert_eq(state.state, MeridianState.STRENGTHENED, "and is strengthened")
	assert_eq(
		state.refinement,
		seed.channel_refinement_cap,
		"the elixir walked it to exactly the standing realm's cap"
	)
	assert_eq(
		QiTraining.can_train_channel(actor, channel), false, "which is where the elixir stops"
	)
	var power_before := actor.meridians.get_power_bonus()

	assert_eq(
		QiCultivationApi.deepen_past_cap(actor, channel), true, "the catalyst crosses the cap"
	)
	assert_eq(inventory.count(seed.meridian_catalyst), 0, "and it cost one catalyst")
	assert_eq(
		actor.meridians.get_meridian(channel).refinement,
		seed.channel_refinement_cap + QiTraining.CATALYST_DEPTH_STEP,
		"exactly one step past it"
	)
	assert_eq(
		actor.meridians.get_power_bonus() > power_before,
		true,
		"which is what depth is worth here: power, and no reachability at all"
	)
	assert_eq(
		QiTraining.can_train_channel(actor, channel),
		false,
		"and the elixir still cannot follow it there"
	)


## A burned channel is `recover`'s priced job (ADR 0141), so the catalyst must refuse
## it rather than become a second price for one repair.
func test_the_meridian_catalyst_refuses_a_burn() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	var inventory := ItemsApi.inventory(actor)
	assert_eq(Probe.stock(actor, seed.meridian_catalyst, 1), true, "one catalyst in hand")
	assert_eq(Probe.stock(actor, seed.recovery_item, 1), true, "the recovery elixir too")
	var channel := _first_channel(actor)
	assert_ne(channel, &"", "a channel to burn")
	actor.meridians.damage_meridian(channel)

	assert_eq(
		QiCultivationApi.deepen_past_cap(actor, channel),
		false,
		"a burn is not trained, it is repaired"
	)
	assert_eq(inventory.count(seed.meridian_catalyst), 1, "and the catalyst was not spent")
	assert_eq(QiCultivationApi.recover_next(actor), true, "the recovery elixir closes it instead")
	assert_eq(inventory.count(seed.recovery_item), 0, "at recovery_item's price")


## Any unlocked channel. Bounded by the network's own list with an immediate return,
## and the bound is in the head (INC-0002).
func _first_channel(actor: Actor) -> StringName:
	for channel in actor.meridians.get_all_meridians():
		return channel.id
	return &""


## Press the elixir verb until it refuses, which is exactly the cap: `can_train_channel`
## returns false once `refinement == channel_refinement_cap` and `train_channel` then
## returns false without spending. Bounded by the cap plus one climb (three states) and
## two, and the body breaks on the refusal it is waiting for.
func _train_to_cap(actor: Actor, channel: StringName, seed: QiRealmSeed) -> void:
	var budget := seed.channel_refinement_cap + 5
	var pressed := 0
	while pressed < budget and QiCultivationApi.train_channel(actor, channel):
		pressed += 1
