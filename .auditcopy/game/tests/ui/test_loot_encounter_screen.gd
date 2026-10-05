extends TestCase

## The loot screen driven through the real `LootApi` behind a bridge, exactly as
## the composition root wires it: enter, fight, take the reward, and be told why a
## pickup was refused.

const SCREEN_SCENE := "res://src/ui/screens/loot_encounter.tscn"
const SCREEN_SCRIPT := "res://src/ui/screens/loot_encounter.gd"

## Every screen this suite instantiated. The runner shares one process across every
## suite, so an unfreed screen stays resident for the rest of the run — and this is
## the heaviest screen in the program, each instance carrying a domain list, tier
## bands, a fight readout and reward rows. Freed centrally because the call sites
## are interleaved and a test returning early would skip a free at its end.
var _born: Array[Node] = []


## The first authored domain that needs no key item, and the first authored tier it
## declares. Discovered rather than declared: the domain table grows as trials and
## wardens are authored, and domains sort by id, so a hard-coded id is a test that
## fails the next time one is added ahead of it. "" when the screen offers none.
func _open_domain() -> Dictionary:
	for entry in LootApi.domains():
		var descriptor := entry as Dictionary
		if int(descriptor.get("key_reach", 0)) != 0:
			continue
		var tiers: Array = descriptor.get("tiers", [])
		return {} if tiers.is_empty() else descriptor
	return {}


## A domain that *is* gated, so the gate line has a real requirement to report. "" when
## every authored domain is open.
func _gated_domain_id() -> String:
	for entry in LootApi.domains():
		if int((entry as Dictionary).get("key_reach", 0)) > 0:
			return String((entry as Dictionary)["domain_id"])
	return ""


func _actor(capacity: int = 24) -> Actor:
	var actor := Actor.new(&"delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor, capacity)
	LootApi.attach(actor)
	return actor


## Occupy every inventory slot, so the next drop has to overflow into the world.
##
## Uses an AUTHORED definition so the filler is indistinguishable from a real item:
## a fabricated `ItemDef` is exactly what the headless driver documents as making a
## harness lie about what the player is carrying.
func _fill_inventory(actor: Actor) -> void:
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return
	var def := Crafting.resolve(&"alchemy_ash_herb")
	if def == null:
		return
	inventory.add(def, inventory.used_slots() + 1)


## Press Strike until the live boss is gone, and report whether it was. A boss now
## answers every blow (ADR 0076), so one press is one exchange rather than a whole fight,
## and a loss ends the run rather than killing the boss — so "the run ended" is explicitly
## not success. Bounded, so a screen that never resolves a kill fails instead of hanging.
func _defeat_boss(view: LootEncounterScreen, limit: int = 60) -> bool:
	var start := String(view.summary().get("encounter_id", ""))
	if start.is_empty():
		return false
	var exchanges := 0
	while exchanges < limit:
		view.act_strike()
		exchanges += 1
		var state := view.summary()
		if String(state.get("encounter_id", "")) != start:
			return true
		if not bool(state.get("in_domain", false)):
			return false
	return false


func _bridge() -> LootBridge:
	var bridge := LootBridge.new()
	bridge.list_domains = Callable(LootApi, "domains")
	bridge.enter_domain = Callable(LootApi, "enter_domain")
	bridge.leave_domain = Callable(LootApi, "abandon")
	bridge.pickup = Callable(LootApi, "pickup")
	bridge.pickup_all = Callable(LootApi, "pickup_all")
	bridge.reclaim = Callable(LootApi, "reclaim")
	bridge.read_state = Callable(LootApi, "summary")
	return bridge


## Free everything this suite instantiated. Idempotent, so it is safe after an abort.
func teardown() -> void:
	for node in _born:
		if is_instance_valid(node):
			node.free()
	_born.clear()


func _screen(actor: Actor) -> LootEncounterScreen:
	var scene: PackedScene = load(SCREEN_SCENE)
	assert_ne(scene, null, "the loot screen scene loads")
	var screen := scene.instantiate() as LootEncounterScreen
	_born.append(screen)
	screen.call("_ready")
	screen.call("setup", actor)
	screen.call("bind_bridge", _bridge())
	return screen


func test_a_screen_with_no_actor_or_no_bridge_reads_empty() -> void:
	var scene: PackedScene = load(SCREEN_SCENE)
	var bare := scene.instantiate() as LootEncounterScreen
	_born.append(bare)
	bare.call("_ready")
	assert_eq(bare.summary().is_empty(), true, "no actor means no view")
	bare.call("setup", _actor())
	assert_eq(bare.summary().is_empty(), true, "no gameplay side means no view either")


func test_the_screen_lists_the_authored_domains_and_their_entry_gate() -> void:
	var screen := _screen(_actor())
	var summary := screen.summary()
	var expected := _open_domain()
	assert_eq(expected.is_empty(), false, "an ungated authored domain exists to open")
	if expected.is_empty():
		return
	assert_eq(
		int(summary["domain_count"]), LootApi.domains().size(), "every authored domain is offered"
	)
	assert_eq(
		String(summary["domain_id"]),
		String(expected["domain_id"]),
		"the first domain the screen selects is one a fresh actor may enter"
	)
	var first_tier: Dictionary = (expected["tiers"] as Array)[0]
	assert_eq(int(summary["tier"]), int(first_tier["tier"]), "at its lowest authored band")
	assert_eq(
		str(summary["tier_label"]), String(first_tier["label"]), "the band label comes from content"
	)
	assert_eq(str(summary["gate"]), "Open domain", "and its entry gate is shown")
	assert_eq(bool(summary["in_domain"]), false, "nobody is in a domain yet")
	assert_eq(bool((summary["enabled"] as Dictionary)["enter"]), true, "so entering is offered")
	assert_eq(bool((summary["enabled"] as Dictionary)["strike"]), false, "and striking is not")


func test_a_gated_domain_reports_the_key_it_needs() -> void:
	var gated := _gated_domain_id()
	assert_ne(gated, "", "a gated authored domain exists, so the gate has something to report")
	if gated.is_empty():
		return
	var actor := _actor()
	var screen := _screen(actor)
	var option := screen.get_node_or_null("%DomainOption") as OptionButton
	var index := _domain_index(gated)
	assert_ne(index, -1, "the gated domain is offered in the selector")
	if index < 0:
		return
	# Selected the way a player picks one: `select()` alone emits nothing.
	option.select(index)
	option.item_selected.emit(index)
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


## The selector index of `domain_id`, or -1. Matched on the stable id rather than the
## display label, which is presentation.
func _domain_index(domain_id: String) -> int:
	for entry in LootApi.domains():
		if String((entry as Dictionary)["domain_id"]) == domain_id:
			return LootApi.domains().find(entry)
	return -1


## The definition ids the reward listed, i.e. what the pickups were supposed to hand
## over. Read from the reward the screen still reports, so the assertion is "the item
## the drop named is the item the bag holds" rather than "the bag holds a literal".
func _claimed_def_ids(actor: Actor, screen: Node) -> Array[String]:
	var out: Array[String] = []
	for drop in _reward_view(actor, screen).get("drops", []):
		out.append(String((drop as Dictionary).get("def_id", "")))
	return out


## The reward view the facade publishes for the reward the screen is showing.
##
## ## The encounter id comes from the REWARD, not from `active`
##
## `summary()["encounter_id"]` is the live encounter, and a defeated boss clears it.
## Both helpers used to read it that way, so after the fight they asked the facade
## about "" and got `{"reward": {}}` back -- which is why "at least one drop is
## genuinely carried" failed against a reward that had been paid in full.
## `summary()["reward"]["encounter_id"]` is the reward's own id and survives the kill.
##
## This replaces a lookup of `LootApi.table(table_id)["source_id"]`, which raised
## "Invalid access to property or key 'source_id'" on every run and aborted this test
## mid-function: `LootApi.table` publishes id, display_name, realm, rarity, rolls and
## entries -- it has no `source_id`. Because the abort happened mid-function the test
## reported no failure, so the suite stayed green over a test that was not finishing.
func _reward_view(actor: Actor, screen: Node) -> Dictionary:
	var shown := screen.summary() as Dictionary
	var encounter := String((shown.get("reward", {}) as Dictionary).get("encounter_id", ""))
	return LootApi.reward(actor, encounter).get("reward", {}) as Dictionary


func test_the_full_loop_runs_through_the_screen() -> void:
	var actor := _actor()
	var screen := _screen(actor)
	assert_eq(_open_domain().is_empty(), false, "an ungated domain exists to open")
	assert_eq(bool(screen.act_enter()), true, "entered the domain")
	var inside := screen.summary()
	assert_eq(bool(inside["in_domain"]), true, "a boss is live")
	assert_ne(String(inside["boss_id"]), "", "the domain's authored boss is named")
	assert_eq(float(inside["vitality_max"]) > 0.0, true, "it has authored vitality")
	assert_eq(bool((inside["enabled"] as Dictionary)["strike"]), true, "so striking is offered")
	assert_eq(bool((inside["enabled"] as Dictionary)["enter"]), false, "and entering again is not")

	# Partial damage keeps the boss alive and shows the pool it is drawn from.
	var partial := _actor()
	var chipper := _screen(partial)
	chipper.act_enter()
	assert_eq(bool(chipper.act_strike()), true, "a partial hit lands")
	var hurt := chipper.summary()
	assert_eq(float(hurt["vitality"]) < float(hurt["vitality_max"]), true, "the pool shrank")
	assert_eq(
		String(hurt["vitality_label"]).contains("vitality"), true, "the panel owns the wording"
	)

	assert_eq(_defeat_boss(screen), true, "the boss is defeated")
	var after := screen.summary()
	assert_eq(int(after["reward_count"]) > 0, true, "the reward is listed")
	assert_eq(int(after["pending_drops"]) > 0, true, "with drops waiting")
	var listed := after["reward"] as Dictionary
	assert_eq(int(listed["row_count"]) > 0, true, "one row per drop")
	assert_eq(String(listed["encounter_id"]) != "", true, "the reward names its encounter")
	# The boss on screen is the boss that reward is drawn for. Checked HERE and not
	# on entry: a reward is minted when a boss falls, so before the fight there is
	# no reward view to compare against and the comparison was vacuous.
	assert_eq(
		String(inside["boss_id"]),
		_reward_view(actor, screen).get("boss_id", ""),
		"and it is the same boss the encounter's reward is drawn for"
	)

	# What the reward owes, read BEFORE it is spent.
	#
	# `LootApi.reward` answers `{"reward": {}}` once the claim is settled, so asking
	# it after `act_take_all` returns no drops at all and "at least one drop is
	# genuinely carried" fails on a reward that was in fact paid in full. The items
	# are whatever the authored table rolled, so they are read back rather than
	# pinned: a drop-table retune must not fail this assertion.
	var claimed := _claimed_def_ids(actor, screen)
	assert_ne(claimed.is_empty(), true, "the reward names at least one drop")

	# Take every drop the listed reward owes.
	assert_eq(bool(screen.act_take_all()), true, "take all is accepted")
	var emptied := screen.summary()
	assert_eq(int(emptied["pending_drops"]), 0, "nothing is left waiting")
	assert_eq(int(emptied["claimed_encounters"]), 1, "the claim ledger records the spend")
	for def_id in claimed:
		assert_eq(
			bool(ItemsApi.has_item(actor, StringName(def_id))), true, "'%s' is carried" % def_id
		)


func test_a_refused_pickup_says_why_and_keeps_the_drop() -> void:
	var actor := _actor(1)
	# Fill the single slot BEFORE the fight, so the first drop has nowhere to go
	# whatever the boss happens to roll.
	#
	# This used to depend on the selected tier dropping two or more items: with one
	# drop and one slot the pickup simply succeeded, nothing overflowed, and the test
	# failed on authored content rather than on the screen. That left the entire
	# overflow branch unproved — the branch that is the whole reason `Reclaim`
	# exists. Occupying the slot makes the overflow the screen's doing, not the loot
	# table's.
	_fill_inventory(actor)
	var screen := _screen(actor)
	screen.act_enter()
	# One exchange is not a whole fight (ADR 0076): the boss answers, so the pool
	# has to be emptied by fighting rather than by one press.
	_defeat_boss(screen)
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
	# One exchange is not a whole fight (ADR 0076): the boss answers, so the pool
	# has to be emptied by fighting rather than by one press.
	_defeat_boss(screen)
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
	# One exchange is not a whole fight (ADR 0076): the boss answers, so the pool
	# has to be emptied by fighting rather than by one press.
	_defeat_boss(screen)
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


## The screen reaches gameplay through the bridge the composition root injects, so it
## never names the loot facade itself: a bare `LootApi.` call would hard-wire a
## concrete module type into the UI program and take the bridge seam away.
##
## The rule is about CODE, and this used to assert it over the whole file. The arch
## checker that owns the same rule (`tools arch`, the bare-reference scan in
## `tools/arch/enforce.py:_references`) reads `_code_only(text)`, which drops
## comments before it looks for a class name -- so a `##` line NAMING `LootApi` to
## explain why the bridge exists was never a violation to the rule's owner. Scanning
## the raw text made this STRICTER than the rule it exists to enforce, and it reddened
## on the screen's own explanation of the seam. `api.gd`'s `class_name LootApi` is the
## facade declaring itself, which is never this scan's business: it is the facade, not
## a reference to one.
func test_the_screen_never_names_the_loot_module() -> void:
	var text := FileAccess.get_file_as_string(SCREEN_SCENE)
	assert_eq(text.contains("LootApi"), false, "the scene names no module type")
	var script := FileAccess.get_file_as_string(SCREEN_SCRIPT)
	var named := _code_lines_naming(script, "LootApi")
	assert_eq(
		named.is_empty(),
		true,
		"%s names no module type in code; found %s" % [SCREEN_SCRIPT, ", ".join(named)]
	)
	assert_eq(script.contains("ItemDef"), false, "nor any item type")
	assert_eq(script.contains("theme_override"), false, "and no theme override anywhere")


## The cut the guard above rests on, proved on BOTH sides, because a helper that
## dropped everything would satisfy only half of it: a `##` line that NAMES the facade
## to explain the seam is documentation and must NOT be found, and a real CALL is the
## violation and must be. The trailing-comment case is the one a line-prefix test alone
## gets wrong, so it is asserted here rather than assumed.
func test_the_module_type_scan_ignores_prose_and_still_finds_a_call() -> void:
	var prose := "## Every slot is a `LootApi` verb.\nvar bridge: LootBridge = null"
	assert_eq(
		_code_lines_naming(prose, "LootApi").is_empty(),
		true,
		"a doc line naming the facade is documentation, not a reference"
	)
	var trailed := "var held := 0  # see LootApi for the verb it forwards"
	assert_eq(
		_code_lines_naming(trailed, "LootApi").is_empty(),
		true,
		"and so is a mention sitting after code on the same line"
	)
	var call := "func refresh() -> void:\n\tLootApi.strike(actor)"
	var found := _code_lines_naming(call, "LootApi")
	assert_eq(found.size(), 1, "a real call is the violation, and is found exactly once")
	assert_eq(
		String(found[0]),
		"2: LootApi.strike(actor)",
		"reported with the line it is on, so a red names where"
	)


## The CODE lines of `text` naming `token`, as `"<line>: <code>"`, in file order, so a
## failure names the line rather than only the file.
##
## A comment is cut before the token is looked for, exactly as `tools arch` cuts one
## (`COMMENT_RE = #.*$` in `tools/arch/enforce.py`). Detection and the cut are kept
## apart on purpose: a helper that dropped everything would pass this test, and one
## that cut nothing could not be told apart from a raw `contains`.
##
## Bounded by `text.split("\n")` -- a finite snapshot taken BEFORE the loop and never
## appended to, so the loop cannot grow the container it walks. Every branch advances
## `number` by the iterator, so there is no `while` here to bound.
func _code_lines_naming(text: String, token: String) -> Array[String]:
	var out: Array[String] = []
	var lines := text.split("\n")
	for number in lines.size():
		var line := String(lines[number])
		if line.strip_edges().begins_with("#"):
			continue
		var hash := line.find("#")
		var code := line if hash < 0 else line.substr(0, hash)
		if code.contains(token):
			out.append("%d: %s" % [number + 1, code.strip_edges()])
	return out
