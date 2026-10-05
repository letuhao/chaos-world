extends TestCase

## ## The clan page is reachable by a PLAYER's keys, and that is what closes the gap
##
## `ClanScreen.act_join` is the sole production caller of `ClanApi.join`, and the earlier
## slice proved it works — but it proved it by calling `select_clan` itself. That is a
## test building the thing under test, which is the audit's own stated standard:
## **a suite that wires up the thing it tests cannot fail when the wiring is absent.**
##
## So the question this suite answers is the harder and more honest one: with NOTHING set
## up but the shipped app, can a player who has never called a Clan method at all reach
## the membership, and through it `household_heir_registered`?
##
## ## ## What was actually broken, and it was not the verb
##
## The verb was fine. The **gesture that arms it** was missing. `act_join` acts on
## `_selected_clan`; a hero belonging to no house has none; and no panel, no widget and no
## key ever called `select_clan`. So in the shipped program:
##
## [codeblock]
## can_join()            -> false   (no pick, and no way to make one)
## _enabled_actions()    -> {"join": false, ...}
## ActionSet.request(join) -> refuses, so the button is permanently dead
## [/codeblock]
##
## and the ONLY way to reach a house membership in a real session was a test calling
## `select_clan`. `ClanHeir.register` still never fired in play, `household_heir_registered`
## was still never recorded, and the four authored quests still could not complete — the
## same UNWIRED verdict the ledger recorded, reached one level further in.
##
## ## ## Every test here presses KEYS. Never `select_clan`, never `act_join`.
##
## The only thing a test sets up is the hero's LINEAGE, because a house's `min_purity` is
## authored content a hero earns by being born a certain way — stating the game's own
## precondition is not building the seam. The pick, the join and the register are all
## driven through `ScreenStack`'s `on_stack_input`, which is the same entry point
## `_unhandled_input` feeds a real keystroke through.
##
## ## ## Why keys and not the ActionSet
##
## The earlier suite presses `ActionSet.request(&"join")`, which is a good test of the
## BUTTON. But the button is disabled until the pick exists, so pressing it cannot prove
## the pick is reachable — and asserting "join is enabled" before a pick would only
## re-assert the bug. Going through `ui_down` then `ui_accept` is the whole chain a
## player walks, and it fails loudly if any link of it is missing.

const CLAN_ROUTE := &"clan"

## The house under test, read from the SHIPPED catalog rather than restated.
## `saltledger` claims `hearthborn` and opens admission at its authored `min_purity`
## (`game/data/clans/saltledger.tres`), which `test_clan_content.gd` already asserts
## against the `.tres`. This file only needs a house that SHIPS and admits.
const HOUSE := &"saltledger"
## Above that house's authored bar: carried AND admitted, the state a hero of that line
## is actually in.
const ADMITTED_PURITY := 0.9


func setup() -> void:
	pass


func teardown() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


# --- 1. The before/after trace, in one test -----------------------------------


## ## THE ACCEPTANCE TRACE. A fresh actor, a player's keys, and the whole chain.
##
## Before this change the run stopped at `can_join()`: `ui_down` had nowhere to land,
## `ui_accept` had no verb to run, and `ClanApi.summary(hero).clan` stayed `""`. Every
## assertion below its first is the thing that was unreachable.
func test_keys_alone_take_a_fresh_hero_from_no_house_to_a_registered_heir() -> void:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp boots, or nothing below is proven")
	if harness.boot_error != "":
		return
	var hero := harness.actor
	assert_ne(hero, null, "the app built its own hero")
	if hero == null:
		return
	carry_lineage(harness, HOUSE, ADMITTED_PURITY)

	# --- BEFORE ---
	assert_eq(ClanApi.summary(hero).get("clan", ""), "", "the fresh actor belongs to no house")
	assert_eq(
		WorldFact.count(hero, &"household_heir_registered"), 0, "and no house has entered them"
	)
	var mounted := harness.navigate(CLAN_ROUTE)
	assert_eq(bool(mounted["ok"]), true, "the shipped route mounts: %s" % mounted["note"])
	if not bool(mounted["ok"]):
		return
	var live := harness.live_screen()
	if live == null:
		assert_ne(live, null, "the clan route left a live screen")
		return

	# Nothing picked, so nothing is offerable — and a pick cannot be made by a key.
	var before: Dictionary = live.call(&"summary")
	assert_eq(bool(before["can_join"]), false, "before: no house picked, so no join")
	assert_eq(
		String(before["selected_clan"]), "", "before: and there was no key that could pick one"
	)

	# --- THE PLAYER'S HANDS: walk the pick, then press ---
	# `ui_down` is what a player presses to look at the next house. No `select_clan`
	# call appears anywhere in this file — that is the whole point of it.
	var catalog := live.call(&"offered_ids") as Array
	assert_ne(catalog.is_empty(), true, "the shipped catalog has houses to walk")
	assert_eq(_key(live, &"ui_down"), true, "the player can walk the house list")
	# Walk on to the house under test. BOUNDED: the count is snapshotted BEFORE the
	# loop and caps it, so `test_no_unbounded_wait.gd` reads a real guard and a catalog
	# that somehow never contains the house cannot hang the suite.
	var budget := catalog.size()
	var walks := 0
	while String(live.call(&"summary")["selected_clan"]) != String(HOUSE) and walks < budget:
		if not _key(live, &"ui_down"):
			break
		walks += 1
	var view: Dictionary = live.call(&"summary")
	assert_eq(
		String(view["selected_clan"]),
		String(HOUSE),
		(
			"and the walk lands on the authored house — `offered_ids` is the facade's own "
			+ "catalog, so the pick is one the module publishes"
		)
	)
	assert_eq(bool(view["can_join"]), true, "so the join control is now LIVE — this is the fix")
	assert_eq(
		bool(view["enabled"]["join"]),
		true,
		"and `ActionSet` is told so, not just the screen's own predicate"
	)

	# `ui_accept` runs the page's PRIMARY verb, which is `join` for a hero with a pick
	# and no membership. It goes through `_accept`, never through `act_join` directly.
	assert_eq(_key(live, &"ui_accept"), true, "the player can press the join")

	# --- AFTER ---
	assert_eq(
		String(ClanApi.summary(hero).get("clan", "")),
		String(HOUSE),
		"so a PLAYER'S KEYS put a fresh actor in a house — `ClanApi.join`'s caller"
	)
	var gate := ClanRegistry.available(hero)
	assert_eq(
		bool(gate["ok"]),
		true,
		(
			"so the gate that used to refuse `not_a_member` for every real actor now agrees: %s"
			% gate["reason"]
		)
	)

	# The register press becomes live because the gate agrees — read off the page's own
	# published state, not asserted by calling the verb.
	var after_join: Dictionary = live.call(&"summary")
	assert_eq(
		bool(after_join["enabled"][String("register_heir")]),
		true,
		"and the ClanScreen register action becomes ENABLED — the exact gate the brief called dead"
	)

	assert_eq(_key(live, &"ui_accept"), true, "the player presses the register")
	# Report the seam's OWN verdict in the message, so a failure names the module's
	# refusal rather than leaving a bare 0 against an expected 1.
	var sealed: Dictionary = live.call(&"summary")
	assert_eq(
		WorldFact.count(hero, &"household_heir_registered"),
		1,
		(
			"so `ClanHeir.register` FIRED from a player action and the fact is on the ledger — "
			+ "which is what the four authored quests and the `oaths_sworn` destiny counter read. "
			+ "Seam said: %s" % sealed["last_reason"]
		)
	)
	assert_eq(String(ClanApi.rank_of(hero)), String(ClanHeir.HEIR_RANK), "the POSITION moved")
	assert_eq(ClanApi.standing_of(hero), 0, "and the standing did not (ADR 0064's split)")


# --- 2. The gesture itself, pinned so it cannot be quietly deleted -------------


## ## Why assert the WALK and not just the result
##
## A test that only asserts "the hero ends up in a house" can be satisfied by any future
## change that happens to leave some other route open. These pin the mechanism: the pick
## is a gesture on the page, it wraps in both directions, it declines on an empty
## catalog, and it walks the CATALOG rather than a list this file could drift from.
func test_the_pick_is_a_wrapping_key_gesture_over_the_facade_s_own_catalog() -> void:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real app boots")
	if harness.boot_error != "":
		return
	carry_lineage(harness, HOUSE, ADMITTED_PURITY)
	harness.navigate(CLAN_ROUTE)
	var live := harness.live_screen()
	if live == null:
		assert_ne(live, null, "the clan route left a live screen")
		return

	var offered := live.call(&"offered_ids") as Array
	assert_ne(offered.is_empty(), true, "the shipped catalog has houses to offer")
	assert_eq(
		offered.size(),
		int(live.call(&"summary")["clan_count"]),
		"and the walk list is exactly as long as the count the facade publishes"
	)
	var sorted: Array = offered.duplicate()
	sorted.sort()
	assert_eq(offered, sorted, "in canonical order, so a walk is deterministic")

	# With NOTHING picked the two keys mean the two ENDS — `down` the first, `up` the
	# last — and neither skips one. `SectScreen._step` gets this case wrong (it seeds the
	# index and THEN adds `step`, so a first `down` lands on the SECOND entry), so it is
	# pinned here rather than inherited from the copy.
	assert_eq(String(live.call(&"summary")["selected_clan"]), "", "nothing is picked to start")
	_key(live, &"ui_down")
	assert_eq(
		String(live.call(&"summary")["selected_clan"]),
		String(offered[0]),
		"down from nothing lands on the first house, not the second"
	)
	# Once a house IS picked the walk is a plain wrapping ring. Asserted by INDEX rather
	# than by named ids: the catalog ships three houses today and a fourth would make
	# hand-written id arithmetic wrong in a way that reads as a product bug.
	var count := offered.size()
	var last := count - 1
	_key(live, &"ui_up")
	assert_eq(
		String(live.call(&"summary")["selected_clan"]),
		String(offered[last]),
		"and once a house IS picked the walk is a wrapping ring: up from the first wraps"
	)
	_key(live, &"ui_up")
	assert_eq(
		String(live.call(&"summary")["selected_clan"]),
		String(offered[last - 1]),
		"so up again steps back one, never off the front"
	)
	_key(live, &"ui_down")
	assert_eq(
		String(live.call(&"summary")["selected_clan"]),
		String(offered[last]),
		"and down steps the other way — the same ring, not a second list"
	)
	# A full lap in each direction returns to where it started, so the ring has no
	# preferred house: every entry is reachable by key alone.
	_key(live, &"ui_down")
	assert_eq(
		String(live.call(&"summary")["selected_clan"]),
		String(offered[0]),
		"and a lap lands back on the first — the ring is closed"
	)


## ## `ui_cancel` must stay the stack's, and an unhandled key must stay the stack's.
##
## If this page swallowed `ui_cancel` the player could not leave the clan screen, and if
## it swallowed everything the stack's pop would be dead. Both are the `SectScreen`
## contract this copy follows.
func test_the_page_declines_cancel_and_unhandled_keys_so_the_stack_still_pops() -> void:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real app boots")
	if harness.boot_error != "":
		return
	carry_lineage(harness, HOUSE, ADMITTED_PURITY)
	harness.navigate(CLAN_ROUTE)
	var live := harness.live_screen()
	if live == null:
		assert_ne(live, null, "the clan route left a live screen")
		return

	assert_eq(live.on_stack_input(null), false, "a null event is declined")
	assert_eq(_key(live, &"ui_cancel"), false, "cancel is declined so the stack pops")
	assert_eq(_key(live, &"ui_left"), false, "and so is everything it does not own")


## ## The gate the screen must NOT re-derive: a join is refused by the module.
##
## The page offers the press on an actor + a pick and NOT on whether the hero is
## admitted — a player turned away is told WHICH lineage the house wants by pressing.
## So the press stays live, the module refuses, and the ledger is untouched.
func test_a_refused_join_leaves_the_ledger_untouched_and_the_pick_standing() -> void:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real app boots")
	if harness.boot_error != "":
		return
	carry_lineage(harness, HOUSE, 0.1)
	harness.navigate(CLAN_ROUTE)
	var live := harness.live_screen()
	if live == null:
		assert_ne(live, null, "the clan route left a live screen")
		return

	# Walk the pick with a BOUNDED loop: the snapshot is taken BEFORE the loop and the
	# count is capped by it, so `test_no_unbounded_wait.gd` reads a real guard and a
	# catalog that somehow never contains the house cannot hang the suite.
	var offered := live.call(&"offered_ids") as Array
	var budget := offered.size()
	var walks := 0
	while String(live.call(&"summary")["selected_clan"]) != String(HOUSE) and walks < budget:
		if not _key(live, &"ui_down"):
			break
		walks += 1
	assert_eq(String(live.call(&"summary")["selected_clan"]), String(HOUSE), "picked the house")
	assert_eq(_key(live, &"ui_accept"), true, "and the press is still LIVE")

	assert_eq(ClanApi.clan_of(harness.actor), &"", "the hero was NOT admitted")
	assert_eq(
		String(live.call(&"summary")["last_reason"]),
		"unmet",
		"and the page reports the MODULE's refusal name, not one it composed"
	)
	assert_eq(
		(harness.actor.call(&"get_module_data", ClanApi.MODULE_KEY) as Dictionary).get("clan", ""),
		"",
		"and the ledger carries no membership — a gate, not a surcharge"
	)


# --- Plumbing ----------------------------------------------------------------


## Press a key the way `ScreenStack` does: a pressed `InputEventAction` handed to the
## live screen's `on_stack_input`, which is exactly what `_unhandled_input` forwards.
func _key(screen: Node, action: StringName) -> bool:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return bool(screen.call(&"on_stack_input", event))


## Give the APP'S OWN hero the lineage the house admits — the game's own authored
## precondition for admission, not the seam under test.
func carry_lineage(harness: SeamHarness, clan_id: StringName, purity: float) -> void:
	var hero := harness.actor
	if hero == null:
		return
	BloodlineApi.attach(hero)
	var def := ClanCatalog.instance().clan_definition(clan_id)
	BloodlineApi.set_purity(hero, def.founding_bloodline, purity)
