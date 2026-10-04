extends TestCase

## The claim, driven through the control a player presses, on the cells the boot probe
## walks: the FIRST authored band of an arbitrary domain, with a bag that has room, and
## with a second payload already outstanding.
##
## `test_loot_acquisition` proves one payload of one domain claims through the row's own
## control. What it cannot see is what a press does to the payload AFTER the first one,
## because every assertion there lands before the rebuild. The boot probe presses up to
## eight times and needs the pending count to fall; that loop could not run, and the
## reason was a control rather than a rule.
##
## Every failure label carries the refusal the screen published, because "the drop did
## not arrive" is a symptom and the reason id is the diagnosis.

## How many authored domains this suite samples, and how many presses it allows per
## reward -- the probe's own bound. Both are bounds on a walk over content, never "until
## it works": each loop moves a counter it read before the loop and asserts inside it.
const DOMAIN_SAMPLE := 6
const PRESSES := 8
## Depth cap for the name walk: reward list -> rows -> layout -> header -> button is
## five levels, so this is slack rather than a tuned number. A walk with no cap is an
## unbounded loop the moment the tree turns out to contain a cycle.
const MAX_WALK_DEPTH := 12

var _rig: LootScreenRig = null


func setup() -> void:
	_rig = LootScreenRig.new()


## Free whatever the rig minted. Idempotent, so a suite that aborted mid-sample is
## still safe to tear down; the runner shares one process across every suite.
func teardown() -> void:
	if _rig != null:
		_rig.release()
		_rig = null


## The row's own `Pick up` control takes a drop, on the first authored band of a spread
## of domains. The control is resolved the way the boot probe resolves it -- the first
## `DropAction` node the reward list holds -- so this proves the seam a player presses,
## not a lookup the suite trusts.
func test_the_row_control_takes_a_drop_from_the_first_band_of_a_spread_of_domains() -> void:
	var domains := LootApi.domains()
	var sample := mini(DOMAIN_SAMPLE, domains.size())
	assert_ne(sample, 0, "the content offers domains to fight")
	var fought := 0
	var index := 0
	while index < sample and fought < sample:
		var descriptor := domains[index] as Dictionary
		index += 1
		var bands := descriptor.get("tiers", []) as Array
		if bands.is_empty():
			continue
		var domain_id := StringName(descriptor.get("domain_id", ""))
		var tier := int((bands[0] as Dictionary).get("tier", 0))
		# A band the entry gate refuses is a gate working, not a cell to fail on: the
		# rig's hero carries no key, so only an ungated band is fightable here.
		var actor := _rig.hero()
		var view := _rig.screen(actor)
		if not _rig.enter_domain(view, domain_id, tier):
			continue
		if _rig.defeat_boss(view).is_empty():
			continue
		fought += 1
		var before := int(view.summary()["pending_drops"])
		assert_eq(
			_press_first_drop_action(view), true, "%s: a Pick up control is offered" % domain_id
		)
		_press_until_stalled(view, PRESSES)
		var after := _claim_state(view)
		assert_eq(
			int(after["pending_drops"]),
			before - 1,
			(
				"%s band %d: the row's Pick up control took its drop (%s)"
				% [domain_id, tier, String(after["why"])]
			)
		)
	assert_eq(fought > 0, true, "at least one authored band was fightable and paid something")


## Pressing the top control again and again empties the payload. This is the loop the
## boot probe runs, and the assertion is the one it makes: the count the player owes has
## to FALL. It fell by one and stopped, because the rebuild put the drop just taken back
## on top with its control still enabled, so every later press was refused
## `drop_already_claimed` and the payload stayed on screen looking untouched.
func test_pressing_the_top_control_repeatedly_empties_the_payload() -> void:
	var view := _rig.screen(_rig.hero())
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	assert_ne(_rig.defeat_boss(view), "", "the first boss was defeated")
	var owed := int(view.summary()["pending_drops"])
	var listed := int((view.summary()["reward"] as Dictionary)["pending_count"])
	assert_eq(owed, listed, "and the listed payload is all of what is owed")

	var passes := 0
	while int(view.summary()["pending_drops"]) > 0 and passes < PRESSES:
		passes += 1
		assert_eq(
			_press_first_drop_action(view),
			true,
			(
				"press %d found a live Pick up control (%s)"
				% [passes, String(_claim_state(view)["why"])]
			)
		)
	assert_eq(
		passes < PRESSES,
		true,
		"a control that refuses never empties the payload, so the drain must not hit the bound"
	)
	var after := _claim_state(view)
	assert_eq(
		int(after["pending_drops"]),
		0,
		"so repeated presses on the top control drained the payload (%s)" % String(after["why"])
	)
	assert_eq(int(view.summary()["reward_count"]), 0, "and the claim settled")


## A second outstanding payload does not make the listed one unclaimable. The screen
## lists ONE payload at a time, so a run that owes several is the shape a sweep reaches
## on its second fight -- and the count a reader watches is the whole world's, not the
## listed payload's. Both are asserted, because "the listed payload shrank" and "the
## player owes less" are different claims and only the second is the pipeline.
func test_a_second_outstanding_payload_does_not_block_the_listed_one() -> void:
	var view := _rig.screen(_rig.hero())
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	assert_ne(_rig.defeat_boss(view), "", "the first boss was defeated")
	assert_ne(_rig.defeat_boss(view), "", "a second boss was defeated")
	var owed := view.summary()
	assert_eq(int(owed["reward_count"]), 2, "both payloads are outstanding")
	var owed_total := int(owed["pending_drops"])
	assert_eq(
		owed_total > int((owed["reward"] as Dictionary)["row_count"]),
		true,
		"and the screen is not pretending to show all of them at once"
	)

	# Drain only what is LISTED, through the top control, and stop as soon as it is
	# gone. Bounded by PRESSES and by a pass that moves nothing, so a control that stops
	# working ends the drain instead of spinning.
	var passes := 0
	while int(view.summary()["reward_count"]) > 0 and passes < PRESSES:
		passes += 1
		var listed := String(view.summary()["reward_encounter_id"])
		var before := int(view.summary()["pending_drops"])
		if not _press_first_drop_action(view):
			break
		if int(view.summary()["pending_drops"]) == before:
			break
		if String(view.summary()["reward_encounter_id"]) != listed:
			break
	var after := _claim_state(view)
	assert_eq(
		int(after["pending_drops"]) < owed_total,
		true,
		"taking the listed row's drop reduced what the player owes (%s)" % String(after["why"])
	)
	assert_eq(
		int(view.summary()["pending_drops"]) > 0,
		true,
		"and the payload behind it is still owed rather than lost"
	)


## Press the first drop action until a press moves nothing. Bounded by `limit`, and it
## names the condition that stopped it: a control that never moves anything ends the walk
## on its first pass rather than running the bound.
func _press_until_stalled(view: LootEncounterScreen, limit: int) -> void:
	var presses := 0
	while presses < limit:
		var before := int(view.summary()["pending_drops"])
		if not _press_first_drop_action(view):
			return
		presses += 1
		if int(view.summary()["pending_drops"]) == before:
			return


## The reward list's first `DropAction`, resolved the way the boot probe resolves it: a
## depth-first walk for the node NAME, so a hidden pooled row would still be found --
## which is why the control has to be honest about whether it can act. Returns false
## when the list holds none, or when the one it finds is not pressable.
func _press_first_drop_action(view: LootEncounterScreen) -> bool:
	var button := _first_named(view.get_node_or_null("%RewardList"), "DropAction", 0)
	if not (button is Button):
		return false
	if (button as Button).disabled:
		return false
	(button as Button).pressed.emit()
	return true


func _first_named(node: Node, node_name: String, depth: int) -> Node:
	if node == null or depth > MAX_WALK_DEPTH:
		return null
	if node.name == node_name:
		return node
	for child in node.get_children():
		var found := _first_named(child, node_name, depth + 1)
		if found != null:
			return found
	return null


## What the screen says about the claim, as one string: the screen's own rejection line
## and the reward list's outcome line, which is where the facade's reason id is rendered.
func _claim_state(view: LootEncounterScreen) -> Dictionary:
	var summary := view.summary()
	var reward := summary.get("reward", {}) as Dictionary
	return {
		"pending_drops": int(summary.get("pending_drops", 0)),
		"why": "%s / %s" % [String(summary.get("message", "")), String(reward.get("message", ""))],
	}
