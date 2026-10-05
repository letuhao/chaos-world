extends TestCase

## The domain entry gate, proved in both directions and independently, because they
## fail independently.
##
## **Non-trivial.** A bare actor must NOT pass a gated domain. If it did, the gate
## would be decoration and `key_reach` would mean nothing.
##
## **Satisfiable from a legal prior state.** The gate must be openable by a state the
## game can actually put a player into. Here that is a crafted keystone: ordinary
## materials in, a key item out, through the items module's own crafting facade — not
## a hand-written module_data entry.

const KEYSTONE := &"keystone_iron"
const KEYSTONE_RECIPE_PATH := "res://data/recipes/keystone_iron_recipe.tres"
const KEYSTONE_INPUTS: Array[StringName] = [&"ore_iron_vein", &"wood_iron_bark"]

var _rig: LootScreenRig = null


func setup() -> void:
	_rig = LootScreenRig.new()


## The gate the encounter declares, read through the facade's domain list so this test
## cannot drift from the authored content.
func _required_reach(domain_id: String) -> float:
	for domain in LootApi.domains():
		if String((domain as Dictionary).get("domain_id", "")) == domain_id:
			return float((domain as Dictionary).get("key_reach", 0.0))
	return 0.0


func _carried_reach(actor: Actor) -> float:
	return float(LootApi.summary(actor)["key_reach"])


## Craft the keystone through the items module's facade. Returns false rather than
## asserting, so a caller can prove a gate is unreachable when it truly is.
func _craft_keystone(actor: Actor) -> bool:
	var recipe := load(KEYSTONE_RECIPE_PATH) as RecipeDef
	if recipe == null:
		return false
	var inventory := ItemsApi.inventory(actor)
	for input_id in KEYSTONE_INPUTS:
		var def := Crafting.resolve(input_id)
		if def == null:
			return false
		if not inventory.has(input_id, 1):
			inventory.add(def, 1)
	return ItemsApi.craft(recipe, inventory)


## Craft keystone after keystone until the actor's carried reach is at least `reach`.
func _grant_key_reach(actor: Actor, reach: float) -> bool:
	var guard := 0
	while _carried_reach(actor) < reach and guard < 12:
		if not _craft_keystone(actor):
			return false
		guard += 1
	return _carried_reach(actor) >= reach


## Direction one: a bare actor cannot pass a gated domain, and the screen says exactly
## what is missing instead of failing silently.
func test_the_gate_is_non_trivial_a_bare_actor_cannot_pass_it() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	var required := _required_reach(&"loot_storm_crypt_domain")
	assert_eq(required > 0.0, true, "the storm crypt declares a gate in authored content")
	assert_eq(_rig.domain_row(&"loot_storm_crypt_domain") >= 0, true, "and the screen offers it")

	assert_eq(
		_rig.enter_domain(view, LootScreenRig.STORM_DOMAIN, LootScreenRig.STORM_TIER),
		true,
		"the domain selector moved and Enter ran"
	)
	assert_eq(float(view.summary()["key_reach"]), 0.0, "and a bare actor carries no reach at all")
	assert_eq(
		String(view.summary()["gate"]),
		"Needs key reach %d, carrying 0" % int(required),
		"and the gate line says exactly what is missing"
	)

	var refused := view.summary()
	assert_eq(
		String(refused["message"]),
		"Rejected: key_reach_too_low",
		"Enter is refused and names the reason"
	)
	assert_eq(String(refused["tone"]), "error", "with the error tone")
	assert_eq(bool(refused["in_domain"]), false, "and nobody is put inside the domain")
	assert_eq(int(LootApi.summary(actor)["reward_count"]), 0, "a refused entry mints no payload")
	assert_eq(String(refused["reward_encounter_id"]), "", "and nothing is waiting to be taken")


## Direction one again, from the other side: another player axis must not stand in for
## the key. Fortune drives `loot_bonus`; it opens no gate.
func test_another_axis_does_not_stand_in_for_the_key() -> void:
	var actor := _rig.hero(24, 4000.0)
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.STORM_DOMAIN, LootScreenRig.STORM_TIER)
	var state := view.summary()
	assert_eq(float(state["loot_bonus"]) > 1.0, true, "the fortune axis is at its clamp")
	assert_eq(float(state["key_reach"]), 0.0, "but it carries no key reach")
	assert_eq(
		String(state["gate"]).begins_with("Needs key reach"),
		true,
		"so the gate still holds and says what it wants"
	)
	assert_eq(
		String(view.summary()["message"]),
		"Rejected: key_reach_too_low",
		"and the gated domain is still refused"
	)


## Direction two: the gate is openable from a legal prior state. Craft the keystone out
## of ordinary materials, and the very control that refused a moment ago walks in.
func test_the_gate_is_satisfiable_by_crafting_the_key_it_asks_for() -> void:
	var actor := _rig.hero()
	var required := _required_reach(&"loot_storm_crypt_domain")
	assert_eq(_grant_key_reach(actor, required), true, "a keystone can be crafted from materials")
	assert_eq(bool(ItemsApi.has_item(actor, KEYSTONE)), true, "and the actor carries it")

	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.STORM_DOMAIN, LootScreenRig.STORM_TIER)
	var carried := float(view.summary()["key_reach"])
	assert_eq(carried >= required, true, "the carried reach meets the gate")
	assert_eq(String(view.summary()["gate"]), "Open domain", "and the gate line reads as open")

	var inside := view.summary()
	assert_eq(bool(inside["in_domain"]), true, "Enter now opens the domain")
	assert_eq(str(inside["domain_id"]), "loot_storm_crypt_domain", "and it is the gated one")
	assert_ne(str(inside["boss_id"]), "", "with its own authored boss live")
	assert_eq(str(inside["tier"]), "3", "at the lowest authored band of that encounter")


## The threshold is a threshold: carried reach brackets it from both sides — zero
## below the gate is refused, enough at or above it is accepted.
func test_the_gate_is_a_threshold_bracketed_from_both_sides() -> void:
	var required := _required_reach(&"loot_storm_crypt_domain")
	assert_eq(required > 0.0, true, "the gate is a positive number")

	var poor := _rig.hero()
	assert_eq(float(_rig.screen(poor).summary()["key_reach"]) < required, true, "below the gate")
	assert_eq(
		bool(
			(
				LootApi
				. enter_domain(poor, &"loot_storm_crypt_domain", LootScreenRig.STORM_TIER, 7)["ok"]
			)
		),
		false,
		"so the facade refuses it too"
	)

	var rich := _rig.hero()
	assert_eq(_grant_key_reach(rich, required), true, "the same actor, given the key")
	assert_eq(float(_rig.screen(rich).summary()["key_reach"]) >= required, true, "at the gate")
	assert_eq(
		bool(
			(
				LootApi
				. enter_domain(rich, &"loot_storm_crypt_domain", LootScreenRig.STORM_TIER, 7)["ok"]
			)
		),
		true,
		"so the facade accepts it"
	)


## The gate closes again when the key is spent: it reads what the player carries right
## now, so it is a rule and not a one-way unlock.
func test_the_gate_closes_again_when_the_key_is_spent() -> void:
	var actor := _rig.hero()
	var required := _required_reach(&"loot_storm_crypt_domain")
	assert_eq(_grant_key_reach(actor, required), true, "the key is carried")
	var view := _rig.screen(actor)
	# Read the gate without pressing Enter: the rule is about what the player carries,
	# and Enter would refuse and overwrite the line this test is about to read.
	assert_eq(
		_rig.select_domain(
			view,
			_rig.domain_row(LootScreenRig.STORM_DOMAIN),
			_rig.tier_row(LootScreenRig.STORM_DOMAIN, LootScreenRig.STORM_TIER)
		),
		true,
		"the storm crypt was selected"
	)
	view.refresh()
	assert_eq(
		float(view.summary()["key_reach"]) >= required, true, "and its gate is the one in force"
	)
	assert_eq(String(view.summary()["gate"]), "Open domain", "the gate is open")

	# Spend every key: crafting can yield more than one, so the loop is bounded by
	# what the actor actually holds rather than by a guess.
	var spent_keys := 0
	while bool(ItemsApi.consume_item(actor, KEYSTONE)) and spent_keys < 8:
		spent_keys += 1
	assert_eq(spent_keys > 0, true, "at least one key was spent")
	assert_eq(bool(ItemsApi.has_item(actor, KEYSTONE)), false, "and none is left to carry")
	assert_eq(float(view.summary()["key_reach"]), 0.0, "so the reach the facade reads is gone")
	# Spending an item is a change the screen was never told about, so repaint the
	# way the composition root does before reading what the panel now shows.
	view.refresh()
	var spent := view.summary()
	assert_eq(float(spent["key_reach"]), 0.0, "the screen read it too")
	assert_eq(String(spent["gate"]).begins_with("Needs key reach"), true, "and the gate closes")
	_rig.press(view, "%EnterButton")
	assert_eq(
		String(view.summary()["message"]),
		"Rejected: key_reach_too_low",
		"so the domain is refused again"
	)


## The gate belongs to the domain, not to the screen: an ungated domain stays open for
## the very actor the gated one refused, so the refusal was the gate and not the
## selector being stuck.
func test_an_ungated_domain_stays_open_for_the_actor_the_gated_one_refused() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.STORM_DOMAIN, LootScreenRig.STORM_TIER)
	assert_eq(
		String(view.summary()["message"]),
		"Rejected: key_reach_too_low",
		"the gated domain refuses a bare actor"
	)

	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	assert_eq(
		_required_reach(String(LootScreenRig.EMBER_DOMAIN)), 0.0, "the ember vault declares no gate"
	)
	assert_eq(bool(view.summary()["in_domain"]), true, "and the same actor walks straight in")
