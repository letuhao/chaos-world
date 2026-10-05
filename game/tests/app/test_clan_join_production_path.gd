extends TestCase

## ## `ClanApi.join` HAS A PRODUCTION CALLER, proved by driving the page
##
## Before this slice, `ClanApi.join` shipped with zero production callers: no player was
## ever a member of a house, `ClanRegistry.available` (`clan_registry.gd:138`) refused
## `not_a_member` for every real actor, and THREE authored quests watching
## `household_heir_registered` (`the_account_left_open`, `the_station_you_held`,
## `the_severed_calling`) plus TWO fates and ONE destiny were permanently unreachable.
## ADR 0239 §Consequences named the join as **owed**, ten ADRs later, and shipped a
## route to a page whose only action refused by construction.
##
## ## WHY THIS SUITE DRIVES THE APP AND NOT THE MODULE
##
## The audit's own standard, applied here: **a suite that wires up the thing it tests
## cannot fail when the wiring is absent.** So nothing in this file calls
## `ClanRegistry.install()` or constructs a `ClanScreen` of its own. Every test here
## mounts the REAL `ItemWorkbenchApp.tscn` through [SeamHarness], navigates to the clan
## route the shipped route table publishes, and presses the join through the MOUNTED
## screen — the same nodes a player's `h` key reaches.
##
## The one thing the test does set up is the hero's LINEAGE, and that is not the thing
## under test: a house's `min_purity` gate is authored content that a hero earns by
## being born a certain way, so a fixture that gives the app's own hero the lineage a
## house admits is stating the game's own precondition, not building the seam.
##
## ## What this proves
##
##  1. `ClanScreen.act_join` is reachable from the shipped route and lands a MEMBERSHIP.
##  2. The membership is what `ClanRegistry.available` stops refusing — so the register
##     press is now offered, and pressing it lands `household_heir_registered`.
##  3. The join **GATES** on the house's own authored `min_purity` and charges nothing
##     this slice invented: no new currency, no new stat, no new tax.
##  4. A source scan holds the caller count at ONE file, so a later refactor cannot
##     quietly delete the only line in the program that admits anybody to a house.

const SCREEN_SCENE_PATH := "res://src/ui/screens/clan_screen.tscn"
const SCREEN_SCRIPT := "res://src/ui/screens/clan_screen.gd"
const CLAN_ROUTE := &"clan"

## ## The house under test, read from the SHIPPED catalog rather than restated.
##
## `saltledger` claims `hearthborn` and opens admission at `min_purity = 0.42`
## (`game/data/clans/saltledger.tres`). Read here rather than typed so a retune of the
## authored content cannot silently invalidate the fixture — and the line itself is
## asserted against the shipped `.tres` by `test_clan_content.gd`, which is the module's
## own suite. This file only needs a house that SHIPS.
const HOUSE := &"saltledger"
## Above `saltledger`'s authored 0.42 bar, and below the `hearthborn` awaken threshold's
## reach: carried AND admitted, which is the state a hero of that line is actually in.
const ADMITTED_PURITY := 0.9
## Below the same bar: a hero carrying the right line but not enough of it. The house
## must still be REACHABLE to press at, and must refuse by name when it is.
const BELOW_BAR_PURITY := 0.1


func setup() -> void:
	pass


func teardown() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


# --- 1. The join is reachable from the shipped route, and it admits -------------


## THE CLAIM. Mount the real app, take the shipped route to the clan page, press the
## join the page publishes, and read the MEMBERSHIP off the app's own hero afterwards.
func test_pressing_the_clan_page_admits_the_app_s_hero_to_a_house() -> void:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp boots, or nothing below is proven")
	if harness.boot_error != "":
		return
	var hero := harness.actor
	assert_eq(ClanApi.clan_of(hero), &"", "the boot hero starts belonging to no house")
	carry_lineage(harness, HOUSE, ADMITTED_PURITY)

	var moved := harness.navigate(CLAN_ROUTE)
	assert_eq(bool(moved["ok"]), true, "route '%s' mounts: %s" % [CLAN_ROUTE, moved["note"]])
	if not bool(moved["ok"]):
		return
	var live := harness.live_screen()
	assert_eq(live.scene_file_path, SCREEN_SCENE_PATH, "and it is the clan screen the route claims")
	assert_eq(harness.bound_actor(live), hero, "bound to the app's own hero")

	# The pick, through the page's own published catalog — never an id invented here.
	assert_eq(bool(live.call(&"select_clan", String(HOUSE))), true, "the shipped house is selectable")
	# The press, through the ActionSet the way a player's button press arrives.
	assert_eq(harness.action(live, &"join"), true, "the join control is live and accepts a press")

	assert_eq(
		ClanApi.clan_of(hero),
		HOUSE,
		(
			"so the app's own hero is now a MEMBER — the gap this slice closes, read off "
			+ "the ledger rather than off a screen's own report of itself"
		)
	)
	var def := ClanCatalog.instance().clan_definition(HOUSE)
	assert_eq(
		String(ClanApi.rank_of(hero)),
		String(def.entry_rank()),
		"at the house's own entry rung"
	)
	assert_eq(ClanApi.standing_of(hero), 0, "and at no standing — joining is not earning (ADR 0064)")


## ## 2. And the join GATES, on something the game already models
##
## The price is the house's own authored `min_purity` against its own founding
## bloodline, read by the module's existing gate. Nothing here is invented: no currency,
## no new stat, no tax, no new field on `ClanDef`. A hero below the bar is refused BY NAME
## and **the ledger is untouched** — which is what makes this a gate rather than a
## surcharge.
func test_a_hero_below_the_house_s_own_purity_bar_is_refused_and_still_belongs_to_nothing() -> void:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real app boots")
	if harness.boot_error != "":
		return
	var hero := harness.actor
	carry_lineage(harness, HOUSE, BELOW_BAR_PURITY)

	harness.navigate(CLAN_ROUTE)
	var live := harness.live_screen()
	if live == null:
		assert_ne(live, null, "the clan route left a live screen")
		return
	live.call(&"select_clan", String(HOUSE))
	harness.action(live, &"join")

	assert_eq(ClanApi.clan_of(hero), &"", "and the hero was NOT admitted")
	assert_eq(ClanApi.standing_of(hero), 0, "and holds nothing")


# --- 3. The heir door, which only opens for a member --------------------------


## ADR 0239 §Rule 2: the registration needs a MEMBER. Before this slice no player could
## ever be one, so `household_heir_registered` could not be produced at all and the four
## authored quest steps watching it were permanently unfinishable. One join plus one
## register, both through the shipped page, and the fact lands.
func test_joining_then_registering_through_the_page_lands_the_fact_the_quests_watch() -> void:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real app boots")
	if harness.boot_error != "":
		return
	var hero := harness.actor
	carry_lineage(harness, HOUSE, ADMITTED_PURITY)
	assert_eq(
		WorldFact.count(hero, &"household_heir_registered"),
		0,
		"no register yet — so the fact below is the join's doing and nothing else's"
	)

	harness.navigate(CLAN_ROUTE)
	var live := harness.live_screen()
	if live == null:
		assert_ne(live, null, "the clan route left a live screen")
		return
	live.call(&"select_clan", String(HOUSE))
	harness.action(live, &"join")
	assert_eq(ClanApi.clan_of(hero), HOUSE, "the join landed first")

	# The page must now OFFER the register: it is the `available` gate, unchanged, that
	# decides — and it only stops saying `not_a_member` because of the join above.
	var gate := ClanRegistry.available(hero)
	assert_eq(bool(gate["ok"]), true, "the page now offers the register: %s" % gate["reason"])
	assert_eq(harness.action(live, &"register_heir"), true, "and the register press is live")

	assert_eq(
		WorldFact.count(hero, &"household_heir_registered"),
		1,
		(
			"so `household_heir_registered` is on the ledger, and every quest step watching "
			+ "it is now completable through the shipped program"
		)
	)
	assert_eq(String(ClanApi.rank_of(hero)), String(ClanHeir.HEIR_RANK), "and the POSITION moved")
	assert_eq(ClanApi.standing_of(hero), 0, "and the standing did not — ADR 0064's split, held")


# --- 4. The seam assertion: the production call site still exists ------------


## ## WHY A SOURCE SCAN, and not another mount
##
## A mount proves a line works. It does not prove the line is still the ONLY way in — a
## later refactor could leave this page working and add a poller beside it, which is the
## shape ADR 0113 refuses and the shape this whole gap was. So the count of files naming
## `ClanApi.join` in CODE is pinned at exactly one, and that one is this screen.
##
## Read over `_code_only` (comments and string literals blanked first), because
## `clan_registry.gd`, `clan_screen.gd`'s own docstrings and several tests all DISCUSS
## the unwired join by name — asserting over prose would fail this change for documenting
## the gap it closes, which teaches the next author to delete the explanation.
func test_the_only_production_caller_of_the_join_is_this_screen_and_not_a_poller() -> void:
	var callers: Array[String] = []
	for path in _gdscript_files("res://src"):
		if path.ends_with("modules/clan/api.gd"):
			continue
		if _code_only(FileAccess.get_file_as_string(path)).contains("ClanApi.join("):
			callers.append(path)
	assert_eq(
		callers,
		[SCREEN_SCRIPT],
		(
			"exactly one file in src/ calls ClanApi.join, and it is the clan page — a "
			+ "second caller would be a second admission moment (ADR 0113: the owner of the "
			+ "moment writes, never a poller). Found: %s"
		)
		% [", ".join(callers)]
	)


## ## The refusal vocabulary is the module's, so a panel never invents a second one.
##
## `ClanApi.join` returns `reason: "unmet"` plus the authored complaints, and the page
## publishes them rather than composing a sentence. A retune of the house's bar changes
## what the label says and nothing about how many copies of the vocabulary exist.
func test_the_page_publishes_the_module_s_own_admission_complaints_verbatim() -> void:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real app boots")
	if harness.boot_error != "":
		return
	Carry(harness, HOUSE, BELOW_BAR_PURITY)
	harness.navigate(CLAN_ROUTE)
	var live := harness.live_screen()
	if live == null:
		assert_ne(live, null, "the clan route left a live screen")
		return
	live.call(&"select_clan", String(HOUSE))
	var view: Variant = live.call(&"summary")

	var unmet: Array = view["join_unmet"]
	assert_ne(unmet.is_empty(), true, "the page reports the house's own complaint, not a bool")
	assert_eq(
		String(unmet[0]["kind"]),
		String(ClanGate.KIND_PURITY),
		"the authored KIND is the module's"
	)
	var def := ClanCatalog.instance().clan_definition(HOUSE)
	assert_eq(String(unmet[0]["id"]), String(def.founding_bloodline), "against its own founding line")
	assert_eq(
		(view["join_unmet"] as Array),
		ClanApi.admission_unmet(harness.actor, HOUSE),
		"and the list IS the facade's own gate, verbatim — no second authority here"
	)


# --- Plumbing ----------------------------------------------------------------


## Give the APP'S OWN hero a lineage. Not a fixture actor: the actor under test is the
## one the composition root built and every screen is bound to, and a hero the test
## minted would prove a different program than the one a player runs.
##
## The lineage is the game's own authored precondition for admission (`min_purity` on a
## house's `founding_bloodline`), so setting it states that precondition rather than
## building the seam under test. `attach` first, idempotently, exactly as the boot
## pipeline does.
func carry_lineage(harness: SeamHarness, clan_id: StringName, purity: float) -> void:
	var hero := harness.actor
	if hero == null:
		return
	BloodlineApi.attach(hero)
	var def := ClanCatalog.instance().clan_definition(clan_id)
	BloodlineApi.set_purity(hero, def.founding_bloodline, purity)


## `text` with every `#` comment and every double-quoted string literal blanked, so a
## source scan reads CODE and never prose. The repo's own shape, over
## `tools/arch/enforce.py:_code_only` (`COMMENT_RE`, then `STRING_RE`, applied
## strings-first so a `#` inside a literal is not mistaken for a comment).
func _code_only(text: String) -> String:
	var without_strings := ""
	var at := 0
	while true:
		var open := text.find('"', at)
		if open < 0:
			without_strings += text.substr(at)
			break
		var close := text.find('"', open + 1)
		if close < 0:
			without_strings += text.substr(at)
			break
		without_strings += text.substr(at, open - at) + '""'
		at = close + 1
	var out: Array[String] = []
	for line in without_strings.split("\n"):
		var at_hash := line.find("#")
		out.append(line if at_hash < 0 else line.substr(0, at_hash))
	return "\n".join(out)


## Every `.gd` under `root`, recursively. A `while` over `DirAccess` is the one shape
## `tests/arch_rules/test_no_unbounded_wait.gd` accepts as terminating.
func _gdscript_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_gdscript_files(path))
			elif entry.ends_with(".gd"):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found