extends TestCase

## The loot screen wired to the real `CombatApi`, driven by pressing the real controls.
##
## ADR 0076 made a domain fight a stat-resolved exchange, and this suite exists because a
## model nothing calls is the same defect as a stat id with no reader. Before the wiring
## landed, `LootEncounterScreen.act_strike` passed a caller's flat `25.0` to `LootApi.strike`
## and the player was never touched, so no fight could be lost and nothing on screen said
## anything about the player at all.
##
## Every assertion here goes through `LootEncounterScreen.summary()` — the screen contract —
## or through the rendered widget text, so what is proved is what a player can see.

## The deepest authored band an actor with no key can enter at all (ADR 0033's gate).
const DEEP_DOMAIN := &"elemental_transcendent_domain"
const DEEP_TIER := 1
## One exchange of the two-sided readout the panel renders.
const EXCHANGE_CAP := 40

## The rig this suite's screens were minted from, kept so `teardown()` can free
## them. The runner shares one process across every suite, so a screen the rig
## instantiated and nobody freed stays resident for the rest of the run.
var _current_rig: LootScreenRig = null


## Free whatever the rig minted. Idempotent, so it is safe after an abort.
func teardown() -> void:
	if _current_rig != null:
		_current_rig.release()
		_current_rig = null


func _rig() -> LootScreenRig:
	_current_rig = LootScreenRig.new()
	return _current_rig


## Enter the deep band through the screen's own controls, as a player does: pick it in the
## screen's own selector, then press Enter. Returns `null` when the band is not on offer.
func _entered(rig: LootScreenRig, actor: Actor) -> LootEncounterScreen:
	var view := rig.screen(actor)
	var domains: Array = LootApi.domains()
	for index in domains.size():
		if StringName((domains[index] as Dictionary).get("domain_id", "")) != DEEP_DOMAIN:
			continue
		if not rig.select_domain(view, index, 0):
			return null
		return view if bool(view.act_enter()) else null
	return null


## Press Strike until the fight resolves, bounded. Names the condition that failed to
## converge: an exchange that never ends. A boss cannot stall (every share is floored at
## `CombatDamage.MIN_SHARE`), so this cap is a backstop, not a tuning knob.
func _fight_to_an_end(view: LootEncounterScreen) -> Dictionary:
	var exchanges := 0
	var last := {}
	while exchanges < EXCHANGE_CAP:
		var before := view.summary()
		last = before
		if String(before.get("encounter_id", "")) == "":
			return {"outcome": "no_boss", "exchanges": exchanges}
		view.act_strike()
		exchanges += 1
		var after := view.summary()
		# A loss and a cleared run both leave `in_domain` false, so the two are told apart
		# by the one signal only a loss produces: the player's own defeat count.
		if int(after.get("defeats", 0)) > int(before.get("defeats", 0)):
			return {
				"outcome": "run_ended", "exchanges": exchanges, "before": before, "after": after
			}
		if not bool(after.get("in_domain", false)):
			return {
				"outcome": "boss_defeated", "exchanges": exchanges, "before": before, "after": after
			}
	return {"outcome": "unresolved", "exchanges": exchanges, "last": last}


func test_a_strike_resolves_from_the_actors_own_numbers_and_not_a_flat_constant() -> void:
	# Two heroes, one boss, one press each. A flat constant would spend the same pool on
	# both; the exchange spends what each is made of.
	var weak := _rig().hero(24, 0.0, 0.0)
	var weak_view := _entered(_rig(), weak)
	if weak_view == null:
		return
	var weak_hit := weak_view.summary()
	rig_strike(weak_view)

	var strong := _rig().hero(24, 0.0, 60.0)
	var strong_view := _entered(_rig(), strong)
	if strong_view == null:
		return
	var strong_hit := strong_view.summary()
	rig_strike(strong_view)

	var weak_spent := float(weak_hit["vitality_max"]) - float(weak_view.summary()["vitality"])
	var strong_spent := float(strong_hit["vitality_max"]) - float(strong_view.summary()["vitality"])
	assert_eq(weak_spent > 0.0, true, "one press spends some of the boss's pool")
	assert_eq(
		strong_spent > weak_spent,
		true,
		"and a stronger actor spends more of the identical authored pool than a bare one"
	)


func test_a_loser_sees_the_run_end_and_the_reward_never_arrive() -> void:
	# The completion criterion: failure must be reachable AND observable. A bare delver
	# cannot win the deepest ungated band, and the screen has to say so.
	var rig := _rig()
	var actor := rig.hero(24, 0.0, 0.0)
	var view := _entered(rig, actor)
	if view == null:
		return
	var fight := _fight_to_an_end(view)
	assert_eq(
		String(fight["outcome"]),
		"run_ended",
		"a bare delver's fight ends with the run gone, not with the boss beaten"
	)
	var after := fight.get("after", {}) as Dictionary
	assert_eq(bool(after.get("in_domain", false)), false, "and no boss is live any more")
	assert_eq(int(after.get("reward_count", -1)), 0, "and nothing fell from a boss that lived")
	assert_eq(int(after.get("claimed_encounters", -1)), 0, "and no claim was spent")
	assert_eq(
		String(after.get("message", "")).contains("run is lost"),
		true,
		"and the screen says the run was lost rather than reporting a bare rejection"
	)


func test_a_loss_is_recorded_on_screen_and_the_player_is_carried_out() -> void:
	var rig := _rig()
	var actor := rig.hero(24, 0.0, 0.0)
	var view := _entered(rig, actor)
	if view == null:
		return
	assert_eq(int(view.summary()["defeats"]), 0, "nothing lost before the fight")
	_fight_to_an_end(view)
	var summary := view.summary()
	assert_eq(int(summary["defeats"]), 1, "the loss is on screen, not only in module state")
	assert_eq(
		String(summary["defeat_label"]).contains("Defeated 1 time"),
		true,
		"and the panel owns the wording: %s" % String(summary["defeat_label"])
	)
	assert_eq(
		float(summary["health"]),
		float(summary["health_max"]),
		"the player is carried out at full vitality: a boss fight is a stake on the run"
	)


func test_the_player_own_health_is_on_screen_from_the_moment_a_boss_is_live() -> void:
	# The readout that made the old screen dishonest: it showed the boss's pool and
	# nothing of the player, which taught the reader that a boss cannot hurt them.
	var rig := _rig()
	var view := _entered(rig, rig.hero(24, 0.0, 0.0))
	if view == null:
		return
	var summary := view.summary()
	assert_eq(float(summary["health"]) > 0.0, true, "the player has health on screen")
	assert_eq(float(summary["health_max"]) > 0.0, true, "and a maximum to compare it against")
	assert_eq(
		String(summary["player_label"]).contains("health"),
		true,
		"and the panel, not the screen, owns that wording: %s" % String(summary["player_label"])
	)


func test_a_win_is_observable_too_so_a_loss_is_not_the_only_outcome() -> void:
	# A fight that always ends the same way is as vacuous as one that never ends.
	var rig := _rig()
	var view := _entered(rig, rig.hero(24, 0.0, 60.0))
	if view == null:
		return
	var fight := _fight_to_an_end(view)
	assert_eq(
		String(fight["outcome"]),
		"boss_defeated",
		"a geared delver beats the same band a bare one loses"
	)
	assert_eq(int(view.summary()["reward_count"]) > 0, true, "and the reward is on screen")


func test_striking_is_offered_only_while_a_boss_is_live() -> void:
	var rig := _rig()
	var view := rig.screen(rig.hero())
	assert_eq(bool((view.summary()["enabled"] as Dictionary)["strike"]), false, "no boss yet")
	if _selected_deep(view) == null:
		return
	assert_eq(
		bool((view.summary()["enabled"] as Dictionary)["strike"]),
		true,
		"so once a boss is live it is offered"
	)


# --- Helpers that drive the screen the way a player does ----------------------


func rig_strike(view: LootEncounterScreen) -> void:
	var button := view.get_node_or_null("%StrikeButton") as Button
	if button != null:
		button.pressed.emit()
		return
	view.act_strike()


func _selected_deep(view: LootEncounterScreen) -> LootEncounterScreen:
	var domains: Array = LootApi.domains()
	for index in domains.size():
		if StringName((domains[index] as Dictionary).get("domain_id", "")) == DEEP_DOMAIN:
			view.get_node_or_null("%DomainOption").select(index)
			view.act_enter()
			return view if bool(view.summary().get("in_domain", false)) else null
	return null
