extends TestCase

## Every refusal the loot surface can hand back, each one reached from a named input
## state. A refusal that cannot be produced cannot be tested, and an untested refusal
## is a rule nobody knows exists.
##
## The state is named in the test name, so the list of what can go wrong lives in the
## suite rather than in prose.

var _rig: LootScreenRig = null


func setup() -> void:
	_rig = LootScreenRig.new()


## A screen with no gameplay side wired: every action refuses, and the screen renders
## nothing rather than inventing a view. With no bridge there is no state to read, so
## `summary()` is `{}` — which is exactly the refusal a player sees as a dead surface.
func test_a_screen_with_no_gameplay_side_refuses_every_action() -> void:
	var view := _rig.screen(_rig.hero())
	view.call("bind_bridge", LootBridge.new())
	for control in ["%EnterButton", "%LeaveButton", "%StrikeButton"]:
		assert_eq(_rig.press(view, control), true, "%s exists" % control)
		assert_eq(view.summary().is_empty(), true, "%s invents no view" % control)
	assert_eq(bool(view.act_enter()), false, "Enter refuses")
	assert_eq(bool(view.act_strike()), false, "Strike refuses")
	assert_eq(bool(view.act_leave()), false, "Leave refuses")
	assert_eq(view.summary().is_empty(), true, "and no refusal invents a view either")


## No authored domain is offered: Enter has nothing to enter.
func test_no_domains_offered_refuses_to_enter() -> void:
	var view := _rig.screen(_rig.hero())
	view.call("bind_bridge", _rig.bridge_without_domains())
	assert_eq(int(view.summary()["domain_count"]), 0, "no domain is offered")
	_rig.press(view, "%EnterButton")
	assert_eq(String(view.summary()["message"]), "Rejected: no_domain_selected", "Enter refuses")


## No boss is live: Strike and Leave both refuse, and nothing is minted.
func test_no_live_boss_refuses_to_strike_and_to_leave() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.press(view, "%StrikeButton")
	assert_eq(String(view.summary()["message"]), "Rejected: not_in_domain", "Strike refuses")
	_rig.press(view, "%LeaveButton")
	assert_eq(String(view.summary()["message"]), "Rejected: not_in_domain", "Leave refuses")
	assert_eq(int(LootApi.summary(actor)["reward_count"]), 0, "and nothing was minted")


## Wrong key reach: the gated domain, a bare actor. The gate reports itself before
## Enter is even pressed, and Enter refuses by name.
func test_a_gated_domain_refuses_a_bare_actor() -> void:
	var view := _rig.screen(_rig.hero())
	_rig.enter_domain(view, LootScreenRig.STORM_DOMAIN, LootScreenRig.STORM_TIER)
	assert_eq(String(view.summary()["message"]), "Rejected: key_reach_too_low", "the gate refuses")


## Nothing waiting: `Take all` with no reward on screen refuses instead of minting.
func test_no_reward_waiting_refuses_to_take_all() -> void:
	var view := _rig.screen(_rig.hero())
	assert_eq(_rig.take_all_offered(view), false, "with nothing owing the action is not offered")
	_rig.take_all(view)
	assert_eq(
		String(view.summary()["message"]),
		"Rejected: no_reward_selected",
		"and invoked anyway it says there was nothing to take"
	)


## Claim spent: the payload is taken, then taking it again is refused.
func test_a_spent_claim_refuses_a_second_take() -> void:
	var view := _rig.screen(_rig.hero())
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	_rig.defeat_boss(view)
	assert_eq(_rig.take_all(view), true, "the first take moves the world")
	assert_eq(int(view.summary()["claimed_encounters"]), 1, "the claim is spent")
	_rig.take_all(view)
	assert_eq(int(view.summary()["claimed_encounters"]), 1, "and cannot be spent twice")


## A cleared tier: the whole run was fought and paid, and walking back in refuses.
func test_a_cleared_tier_refuses_re_entry() -> void:
	var view := _rig.screen(_rig.hero())
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	for _boss in LootScreenRig.EMBER_BOSS_COUNT:
		_rig.defeat_boss(view)
	_rig.take_everything(view)
	_rig.press(view, "%EnterButton")
	assert_eq(
		String(view.summary()["message"]), "Rejected: domain_cleared", "the cleared tier refuses"
	)


## Full inventory: the pickup refuses and the drop is still listed afterwards.
func test_a_full_inventory_refuses_the_pickup_and_keeps_the_drop() -> void:
	var actor := _rig.hero(1)
	var inventory := ItemsApi.inventory(actor)
	var filler := Crafting.resolve(&"armor_iron_helm")
	if filler != null:
		inventory.add(filler, 1)
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	_rig.defeat_boss(view)
	var owed := int(_rig.listed_reward(view)["row_count"])
	_rig.pick_up_row(view, 0)
	var after := view.summary()
	assert_eq(int(after["world_drop_count"]), 1, "the drop went to the world container")
	assert_eq(
		int((after["reward"] as Dictionary)["row_count"]),
		owed,
		"and it is still listed, so the refusal discarded nothing"
	)
	assert_eq(int(after["claimed_encounters"]), 0, "no claim was spent")


## An unknown encounter, drop or stash: the facade refuses by name rather than
## guessing, and the world is untouched.
func test_unknown_addresses_are_refused_by_name() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	_rig.defeat_boss(view)

	assert_eq(
		String(LootApi.reward(actor, "no/such@0#0")["reason"]),
		LootState.ERR_UNKNOWN_REWARD,
		"an encounter that owes nothing reports unknown_reward"
	)
	assert_eq(
		String(LootApi.pickup(actor, "no/such@0#0", "d0")["reason"]),
		LootState.ERR_UNKNOWN_REWARD,
		"and a pickup against it refuses too"
	)
	var owed := String((view.summary()["reward"] as Dictionary)["rows"][0]["drop_id"])
	assert_eq(
		String(
			LootApi.pickup(actor, String(view.summary()["reward_encounter_id"]), "d-nope")["reason"]
		),
		LootState.ERR_UNKNOWN_DROP,
		"a drop id that is not in the payload reports unknown_drop"
	)
	assert_eq(
		String(LootApi.reclaim(actor, "nope")["reason"]),
		LootState.ERR_UNKNOWN_STASH,
		"a stash id that is not in the world reports unknown_stash"
	)
	assert_eq(
		String(LootApi.enter_domain(actor, &"no_such_domain", 0, 3)["reason"]),
		LootState.ERR_UNKNOWN_DOMAIN,
		"a domain nobody authored reports unknown_domain"
	)
	assert_eq(bool(_rig.listed_reward(view)["row_count"]), true, "and owed is still owed")
	assert_eq(
		bool((view.summary()["reward"] as Dictionary)["rows"][0]["drop_id"] == owed),
		true,
		"the real drop survived every refusal"
	)


## An unknown loot table: the reader is given nothing rather than an empty table that
## would read like a boss with no drops.
func test_an_unknown_loot_table_reads_as_nothing() -> void:
	assert_eq(LootApi.table(&"no_such_table").is_empty(), true, "no table, no view")
	assert_ne(LootApi.table(&"loot_ember_warden_t1").is_empty(), true, "but a real one reads")
