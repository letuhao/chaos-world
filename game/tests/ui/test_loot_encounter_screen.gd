extends TestCase

## The loot screen driven through the real `LootApi` behind a bridge, exactly as
## the composition root wires it: enter, fight, take the reward, and be told why a
## pickup was refused.

const SCREEN_SCENE := "res://src/ui/screens/loot_encounter.tscn"
const EMBER_DOMAIN := &"loot_ember_vault_domain"
const EMBER_TIER := 1
const MARK := &"amulet_iron_sage_eye"


func _actor(capacity: int = 24) -> Actor:
	var actor := Actor.new(&"delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor, capacity)
	LootApi.attach(actor)
	return actor


func _bridge() -> LootBridge:
	var bridge := LootBridge.new()
	bridge.strike_damage = 10000.0
	bridge.list_domains = Callable(LootApi, "domains")
	bridge.enter_domain = Callable(LootApi, "enter_domain")
	bridge.strike = Callable(LootApi, "strike")
	bridge.leave_domain = Callable(LootApi, "abandon")
	bridge.pickup = Callable(LootApi, "pickup")
	bridge.pickup_all = Callable(LootApi, "pickup_all")
	bridge.reclaim = Callable(LootApi, "reclaim")
	bridge.read_state = Callable(LootApi, "summary")
	return bridge


func _screen(actor: Actor) -> LootEncounterScreen:
	var scene: PackedScene = load(SCREEN_SCENE)
	assert_ne(scene, null, "the loot screen scene loads")
	var screen := scene.instantiate() as LootEncounterScreen
	screen.call("_ready")
	screen.call("setup", actor)
	screen.call("bind_bridge", _bridge())
	return screen


func test_a_screen_with_no_actor_or_no_bridge_reads_empty() -> void:
	var scene: PackedScene = load(SCREEN_SCENE)
	var bare := scene.instantiate() as LootEncounterScreen
	bare.call("_ready")
	assert_eq(bare.summary().is_empty(), true, "no actor means no view")
	bare.call("setup", _actor())
	assert_eq(bare.summary().is_empty(), true, "no gameplay side means no view either")


func test_the_screen_lists_the_authored_domains_and_their_entry_gate() -> void:
	var screen := _screen(_actor())
	var summary := screen.summary()
	assert_eq(
		int(summary["domain_count"]), LootApi.domains().size(), "every authored domain is offered"
	)
	assert_eq(String(summary["domain_id"]), String(EMBER_DOMAIN), "the first domain is selected")
	assert_eq(int(summary["tier"]), EMBER_TIER, "at its lowest authored band")
	assert_eq(str(summary["tier_label"]), "Warded", "the band label comes from content")
	assert_eq(str(summary["gate"]), "Open domain", "and its entry gate is shown")
	assert_eq(bool(summary["in_domain"]), false, "nobody is in a domain yet")
	assert_eq(bool((summary["enabled"] as Dictionary)["enter"]), true, "so entering is offered")
	assert_eq(bool((summary["enabled"] as Dictionary)["strike"]), false, "and striking is not")


func test_a_gated_domain_reports_the_key_it_needs() -> void:
	var actor := _actor()
	var screen := _screen(actor)
	(screen.get_node_or_null("%DomainOption") as OptionButton).select(1)
	screen.refresh()
	assert_eq(
		str(screen.summary()["gate"]).contains("Needs key reach"), true, "the gate is reported"
	)
	assert_eq(bool(screen.act_enter()), false, "entering without the key is refused")
	assert_eq(
		String(screen.summary()["message"]).contains("key_reach_too_low"),
		true,
		"and the refusal reason is visible"
	)
	assert_eq(String(screen.summary()["tone"]), "error", "with the error tone")


func test_the_full_loop_runs_through_the_screen() -> void:
	var actor := _actor()
	var screen := _screen(actor)
	assert_eq(bool(screen.act_enter()), true, "entered the domain")
	var inside := screen.summary()
	assert_eq(bool(inside["in_domain"]), true, "a boss is live")
	assert_eq(String(inside["boss_id"]), "loot_ember_vault_warden", "the authored first boss")
	assert_eq(float(inside["vitality_max"]) > 0.0, true, "it has authored vitality")
	assert_eq(bool((inside["enabled"] as Dictionary)["strike"]), true, "so striking is offered")
	assert_eq(bool((inside["enabled"] as Dictionary)["enter"]), false, "and entering again is not")

	# Partial damage keeps the boss alive and shows the pool it is drawn from.
	var partial := _actor()
	var chipper := _screen(partial)
	chipper.call("set_strike_damage", 10.0)
	chipper.act_enter()
	assert_eq(bool(chipper.act_strike()), true, "a partial hit lands")
	var hurt := chipper.summary()
	assert_eq(float(hurt["vitality"]) < float(hurt["vitality_max"]), true, "the pool shrank")
	assert_eq(
		String(hurt["vitality_label"]).contains("vitality"), true, "the panel owns the wording"
	)

	assert_eq(bool(screen.act_strike()), true, "the boss is defeated")
	var after := screen.summary()
	assert_eq(int(after["reward_count"]) > 0, true, "the reward is listed")
	assert_eq(int(after["pending_drops"]) > 0, true, "with drops waiting")
	var listed := after["reward"] as Dictionary
	assert_eq(int(listed["row_count"]) > 0, true, "one row per drop")
	assert_eq(String(listed["encounter_id"]) != "", true, "the reward names its encounter")

	# Take every drop the listed reward owes.
	assert_eq(bool(screen.act_take_all()), true, "take all is accepted")
	var emptied := screen.summary()
	assert_eq(int(emptied["pending_drops"]), 0, "nothing is left waiting")
	assert_eq(int(emptied["claimed_encounters"]), 1, "the claim ledger records the spend")
	assert_eq(bool(ItemsApi.has_item(actor, MARK)), true, "and the item is genuinely carried")


func test_a_refused_pickup_says_why_and_keeps_the_drop() -> void:
	var actor := _actor(1)
	var screen := _screen(actor)
	screen.act_enter()
	screen.act_strike()
	var rows := (screen.summary()["reward"] as Dictionary)["rows"] as Array
	assert_eq(rows.is_empty(), false, "the reward is listed")
	var stashed_before := 0
	var overflowed := false
	for row in rows:
		var drop_id := String((row as Dictionary)["drop_id"])
		if not bool(screen.act_pickup(drop_id)):
			continue
		var world := screen.summary()
		var stashed_count := int(world["world_drop_count"])
		if stashed_count <= stashed_before:
			continue
		# This pickup overflowed: the panel must say why, and the drop must be
		# recoverable from the world drop list.
		stashed_before = stashed_count
		overflowed = true
		var message := (screen.get_node("%RewardList") as LootRewardList).message()
		assert_eq(message.contains("Inventory full"), true, "the player is told why")
		assert_eq(str((world["stashed"] as Dictionary)["mode"]), "stashed", "in its stash mode")
		var stashed := (world["stashed"] as Dictionary)["rows"] as Array
		assert_eq(str((stashed[0] as Dictionary)["action"]), "Reclaim", "offered for reclaim")
		assert_eq(
			int((world["reward"] as Dictionary)["row_count"]), rows.size(), "no drop was lost"
		)
	assert_eq(overflowed, true, "a one-slot inventory forced at least one overflow")
	# Nothing was lost: the reward still lists every drop.
	var final := screen.summary()
	assert_eq(
		int((final["reward"] as Dictionary)["row_count"]), rows.size(), "every drop is still listed"
	)


func test_a_spent_claim_is_reported_rather_than_handed_out_again() -> void:
	var actor := _actor()
	var screen := _screen(actor)
	screen.act_enter()
	screen.act_strike()
	var summary := screen.summary()
	var encounter := String((summary["reward"] as Dictionary)["encounter_id"])
	screen.act_take_all()
	assert_eq(
		bool(LootApi.pickup(actor, encounter, "whatever")["ok"]), false, "the facade refuses it too"
	)
	screen.refresh()
	assert_eq(int(screen.summary()["pending_drops"]), 0, "and nothing is waiting")


func test_leaving_keeps_the_reward_and_the_screen_reports_it() -> void:
	var actor := _actor()
	var screen := _screen(actor)
	screen.act_enter()
	screen.act_strike()
	var pending := int(screen.summary()["pending_drops"])
	assert_eq(bool(screen.act_leave()), true, "the domain is left")
	var out := screen.summary()
	assert_eq(bool(out["in_domain"]), false, "nobody is in a domain")
	assert_eq(int(out["pending_drops"]), pending, "the unclaimed reward is still there")
	assert_eq(bool((out["enabled"] as Dictionary)["enter"]), true, "so entering is offered again")


func test_the_screen_reports_the_bounded_loot_bonus() -> void:
	var actor := _actor()
	actor.stats.set_base(Stat.FORTUNE, 400.0)
	var screen := _screen(actor)
	assert_almost_eq(float(screen.summary()["loot_bonus"]), 4.0, "the clamped rate is shown")
	assert_eq(
		String(screen.summary()["bonus"]).contains("Loot bonus"), true, "with the panel's wording"
	)


func test_the_screen_never_names_the_loot_module() -> void:
	var text := FileAccess.get_file_as_string(SCREEN_SCENE)
	assert_eq(text.contains("LootApi"), false, "the scene names no module type")
	var script := FileAccess.get_file_as_string("res://src/ui/screens/loot_encounter.gd")
	assert_eq(script.contains("LootApi"), false, "nor does the script")
	assert_eq(script.contains("ItemDef"), false, "nor any item type")
	assert_eq(script.contains("theme_override"), false, "and no theme override anywhere")
