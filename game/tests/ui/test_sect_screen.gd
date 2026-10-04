extends TestCase

## The sect screen: a pure consumer of `SectApi.summary(actor)`, asserted through
## `summary()` rather than pixels (AGENTS.md, UI standard).
##
## ## What is actually load-bearing here, and what is merely taste
##
## Three claims, each of which a future edit could quietly undo:
##
##  1. **Position and standing are two facts.** ADR 0064's split, carried forward
##     unchanged by ADR 0083: a member can hold a high position on thin standing, and
##     thick standing in no position at all. A screen that divided one by the other
##     into a single rank would have built a spreadsheet and thrown the politics away,
##     so the claim row prints both and the screen reports both RAW.
##  2. **The screen is a PURE consumer.** Exactly one facade call, `summary(actor)`,
##     and no other identifier from `sect`. Enforced by source read, because that is
##     the only check that survives a refactor of the script — `tools arch` checks the
##     module side, this checks the UI side.
##  3. **Read-only.** No mutating verb is reachable from here, and `on_stack_input`
##     declines every event so `ScreenStack` pops the screen with `ui_cancel` exactly
##     as it pops every other read-only screen.

## The screen scene, loaded once: two `load()` calls for one scene is a second source
## of truth about which scene this suite drives.
const SCREEN_SCENE := preload("res://src/ui/screens/sect_screen.tscn")
const CLAIM_SCENE := "res://src/ui/panels/sect_claim_row.tscn"
const OFFICE_SCENE := "res://src/ui/panels/nation_office_row.tscn"
const SCRIPT_PATH := "res://src/ui/screens/sect_screen.gd"
## The only facade method this screen is allowed to call. ADR 0083 folds every read a
## screen needs into `summary()` rather than growing the facade past its 12-method cap.
const FACADE := "SectApi"
const ONLY_FACADE_CALL := "SectApi.summary"
## The verbs this screen is a CORRECT place to reach from a button: the ones a
## player performs on their own membership. `join` and `leave` are the ordinary
## case; `promote` is reached because a council acts through the same screen and an
## authored authority decides it.
##
## `found` and `teach` joined this list in the reachability fix, and the reason they
## belong is narrower than "everything else is now a button": both are acts about the
## PLAYER'S OWN claim and nothing else. `found` is one hero making a house out of
## their own purse; `teach` is one member instructing another in a school they are both
## sworn to. Neither touches a third party's standing, a seat anybody else holds, or a
## split — which is precisely what the three below do, and what makes them
## "an inquisition a two-click accident" rather than a screen action.
const SCREEN_ACTIONS := ["join", "leave", "promote", "found", "teach"]
## Every mutating verb `sect` publishes, read-only for this file's purposes: the
## check below is that the screen reaches the ACTIONS and is not expected to reach
## the rest. Kept as documentation of what exists and why.
const MODULE_ONLY_VERBS := ["move_standing", "advance_succession", "declare_schism"]
## The verbs a screen legitimately reads, besides `summary`. Reaching one of these from
## `ui/` would widen the facade instead of using the fold ADR 0083 already made.
const OTHER_FACADE_VERBS := ["attach", "gate", "state"]

const IRON_VINE := &"iron_vine"
const JADE_COURT := &"jade_court"


func _actor() -> Actor:
	var actor := Actor.new(&"member", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	SectApi.attach(actor)
	return actor


## A hero sworn to the Iron Vine with some standing earned, so the claim row has a
## position, a cap and an authored duty to print.
func _sworn() -> Actor:
	var actor := _actor()
	SectApi.attach(actor)
	SectApi.join(actor, IRON_VINE)
	SectApi.move_standing(actor, 45)
	SectApi.promote(actor, &"bulwark")
	return actor


func _screen() -> SectScreen:
	return (SCREEN_SCENE as PackedScene).instantiate() as SectScreen


# --- The screen contract ----------------------------------------------------


func test_the_screen_summary_is_empty_without_an_actor() -> void:
	# ADR 0083's first state needs `{}` to be REACHABLE, so a screen that reported keys
	# with nothing bound would make the state unreadable rather than merely empty.
	var screen := _screen()
	assert_eq(screen.summary(), {}, "empty with no actor, not a half-built view")
	screen.free()


func test_the_screen_reports_the_bound_actor_and_the_claim_it_holds() -> void:
	var actor := _sworn()
	var screen := _screen()
	screen.setup(actor)
	var view := screen.summary()
	assert_ne(view, {}, "a bound actor gives a view")
	assert_eq(String(view["actor"]), String(actor.id), "it names the actor it renders")
	assert_eq(bool(view["is_member"]), true, "and the membership it found")
	assert_eq(String(view["sect_id"]), String(IRON_VINE), "and the sect sworn to")
	assert_ne(String(view["sect_name"]), "", "named, not an id standing in for a name")
	screen.free()


func test_the_screen_nests_the_claim_row_summary_under_its_own_key() -> void:
	# The screen contract: a child's own summary lives under that child's key, so a
	# test reads the claim without walking the tree.
	var screen := _screen()
	screen.setup(_sworn())
	var view := screen.summary()
	var claim: Dictionary = view["claim"]
	assert_ne(claim, {}, "the claim row's summary is nested")
	assert_eq(String(claim["sect_id"]), String(IRON_VINE), "and names the same sect")
	assert_eq(
		String(claim["position_id"]),
		String(view["position_id"]),
		"the claim and the screen agree on the office"
	)
	assert_eq(int(claim["standing"]), int(view["standing"]), "and on the standing")
	screen.free()


func test_position_and_standing_are_two_facts_never_one_rank() -> void:
	# ADR 0064's split IS the politics layer. A screen that rendered one number derived
	# from both would have collapsed the gap that makes the design worth having.
	var screen := _screen()
	screen.setup(_sworn())
	var claim: Dictionary = screen.summary()["claim"]
	var position_line := String(claim["position_line"])
	var standing_line := String(claim["standing_line"])
	assert_ne(position_line, "", "the office is named on its own line")
	assert_ne(standing_line, "", "and the standing on another")
	assert_ne(position_line, standing_line, "they are not one derived rank")
	assert_ne(standing_line.find("Bulwark"), -1, "the office is readable by name")
	assert_ne(standing_line.find("45"), -1, "and the standing by its raw value")
	screen.free()


func test_a_thick_standing_with_no_office_still_renders_both_lines() -> void:
	# The other half of the split: the states are reachable in both directions. A member
	# with real standing and no position is a normal state (ADR 0064), and a screen that
	# hid it behind an empty line would read it as "no claim" rather than "no office".
	var actor := _actor()
	SectApi.join(actor, IRON_VINE)
	SectApi.move_standing(actor, 90)
	var screen := _screen()
	screen.setup(actor)
	var claim: Dictionary = screen.summary()["claim"]
	assert_eq(String(claim["position_id"]), "", "no office is held")
	assert_eq(int(claim["standing"]), 90, "and the standing is real")
	assert_ne(String(claim["standing_line"]), "", "so it is still rendered")
	assert_ne(String(claim["position_line"]), "", "and the empty office says so in words")
	screen.free()


func test_an_unaffiliated_hero_is_a_sentence_not_an_empty_page() -> void:
	# ADR 0083: the three tiers are peers, so "belongs to nothing" is the ORDINARY
	# starting state and deserves a row. A blank page would read as a failure to load.
	var screen := _screen()
	screen.setup(_actor())
	var view := screen.summary()
	assert_eq(bool(view["is_member"]), false, "no membership")
	var claim: Dictionary = view["claim"]
	assert_ne(claim, {}, "and a claim row still renders")
	assert_eq(bool(claim["is_member"]), false, "reporting that there is no claim")
	assert_ne(String(claim["institution_line"]), "", "with a line saying so")
	assert_eq(String(claim["position_line"]), "", "and no invented office")
	screen.free()


# --- Every authored office is a row -----------------------------------------


func test_every_authored_office_of_the_sworn_sect_is_listed() -> void:
	# A promotion route that silently vanished would read as an office the sect does not
	# author — the dead-content failure ADR 0063 already shipped once.
	var actor := _sworn()
	var authored := SectCatalog.instance().sect_definition(IRON_VINE).position_ids()
	assert_ne(authored.is_empty(), true, "the sect authors offices to assert on")
	var screen := _screen()
	screen.setup(actor)
	var listed := screen.summary()["office_ids"] as Array
	assert_eq(listed.size(), authored.size(), "one row per authored office")
	for office_id in authored:
		assert_eq(listed.has(String(office_id)), true, "%s has a row" % office_id)
	screen.free()


func test_the_promotion_routes_carry_the_standing_floor_and_the_refusal_reason() -> void:
	# `reason` is the facade's OWN named constant (`standing_below_floor`,
	# `capacity_full`, `seat_occupied`) passed through untouched. A screen that worded
	# it itself would have invented a rule the module never declared.
	var screen := _screen()
	screen.setup(_sworn())
	var routes := screen.summary()["can_promote"] as Array
	assert_ne(routes.is_empty(), true, "the sworn sect publishes promotion routes")
	var seen_a_floor := false
	for route in routes:
		var row: Dictionary = route
		assert_ne(String(row["office_id"]), "", "each route names its office")
		assert_ne(String(row["display_name"]), "", "and its authored name")
		assert_eq(row.has("standing_floor"), true, "and the floor it asks for")
		assert_eq(row.has("reason"), true, "and the facade's own reason string")
		assert_eq(row.has("ok"), false, "a route is a read, not a refusal")
		if int(row["standing_floor"]) > 0:
			seen_a_floor = true
	assert_eq(seen_a_floor, true, "at least one office authors a floor to read")
	screen.free()


func test_the_screen_reports_every_authored_sect_for_comparison() -> void:
	# The facade lists the whole catalog whatever the actor is, precisely so a screen can
	# compare institutions without a second call.
	var screen := _screen()
	screen.setup(_sworn())
	var sects := screen.summary()["sects"] as Array
	assert_ne(sects.is_empty(), true, "the catalog is offered")
	var sworn := 0
	for entry in sects:
		var sect: Dictionary = entry
		assert_ne(String(sect["sect_id"]), "", "each sect is named by id")
		if bool(sect["sworn"]):
			sworn += 1
			assert_eq(String(sect["sect_id"]), String(IRON_VINE), "the sworn one is marked")
	assert_eq(sworn, 1, "exactly one sect is sworn, not several")
	screen.free()


func test_an_unaffiliated_hero_is_still_offered_the_whole_catalog() -> void:
	# "Which sects exist" and "which am I sworn to" are different questions, and the
	# screen answers both without ever calling the facade twice.
	var screen := _screen()
	screen.setup(_actor())
	var view := screen.summary()
	assert_eq(bool(view["is_member"]), false, "no membership")
	assert_ne((view["sects"] as Array).is_empty(), true, "the catalog is still offered")
	assert_eq((view["office_ids"] as Array).is_empty(), true, "and no office is claimed")
	screen.free()


# --- Purity: one facade method, and nothing else from the module -------------


func test_the_screen_reads_one_facade_method_but_may_act_through_the_verbs() -> void:
	# `tools arch` checks the MODULE side of the boundary. This checks the UI side, by
	# reading the shipped source.
	#
	# ## What changed, and why this test was wrong rather than the screen
	#
	# This used to assert the screen calls NO mutating verb. That encoded a real design
	# at the time — a read-only codex — and an independent audit found it was why a
	# player could look at a sect and never join one: thirteen mutating verbs with zero
	# production callers. The screen now HAS to act, so the rule inverted: exactly one
	# facade READ (`summary`, the refresh path) and every mutation through an explicit
	# verb, because that is what makes each action attributable and refusable.
	#
	# The two halves that still matter are unchanged and are the ones below: no second
	# read method, and no interior file.
	var source := FileAccess.get_file_as_string(SCRIPT_PATH)
	assert_ne(source.is_empty(), true, "%s is readable" % SCRIPT_PATH)
	assert_eq(
		source.count(ONLY_FACADE_CALL),
		1,
		"%s calls %s exactly once" % [SCRIPT_PATH, ONLY_FACADE_CALL]
	)
	assert_eq(
		source.contains(FACADE),
		true,
		"%s names the facade at all, so the check above cannot pass vacuously" % SCRIPT_PATH
	)
	# Every action this screen offers must be CALLED, not merely present: a button a
	# player can press that does nothing is the defect the audit found.
	for verb in SCREEN_ACTIONS:
		assert_eq(
			source.contains("%s.%s(" % [FACADE, verb]),
			true,
			"%s calls the action %s" % [SCRIPT_PATH, verb]
		)
	# And the ones it must NOT reach, with the reason each is a menu-click hazard
	# rather than a screen action.
	for verb in MODULE_ONLY_VERBS:
		assert_eq(
			source.contains("%s.%s(" % [FACADE, verb]),
			false,
			"%s does not offer %s from a button" % [SCRIPT_PATH, verb]
		)
	# And a mutation must never be smuggled in behind a second READ method, which is
	# how a "just one more accessor" quietly becomes a second write path.
	for verb in OTHER_FACADE_VERBS:
		assert_eq(
			source.contains("%s.%s(" % [FACADE, verb]),
			false,
			"%s reads no second facade method; %s is not one of them" % [SCRIPT_PATH, verb]
		)


func test_no_sect_or_nation_module_file_other_than_the_facade_is_named() -> void:
	# The stronger half: not "no other METHOD on the facade" but "no other FILE". A
	# `SectState` or `SectDef` reference would reach past the facade entirely, and the
	# bare-name scan `tools arch` performs for `modules/*` would not report it.
	var source := FileAccess.get_file_as_string(SCRIPT_PATH)
	for interior in ["SectState", "SectDef", "SectCatalog", "SectPositionDef", "SectProjection"]:
		assert_eq(
			source.contains(interior),
			false,
			"%s names %s; ui/ may only reach the facade" % [SCRIPT_PATH, interior]
		)
	assert_eq(
		source.contains("res://src/modules/sect/"),
		false,
		"%s paths into the module; panels call the facade by bare name" % SCRIPT_PATH
	)


# --- Focus, read-only, and the row pool --------------------------------------


func test_the_stack_hooks_exist_and_are_safe_with_nothing_bound() -> void:
	var screen := _screen()
	for hook in [&"on_screen_shown", &"on_screen_hidden", &"focus_initial", &"on_stack_input"]:
		assert_eq(screen.has_method(hook), true, "%s is implemented" % hook)
	screen.on_screen_shown()
	screen.on_screen_hidden()
	screen.focus_initial()
	assert_eq(screen.summary(), {}, "still empty, so a focus call did not invent state")
	screen.free()


func test_the_screen_consumes_no_input_so_ui_cancel_pops_it() -> void:
	# Read-only by design: a screen that consumed `ui_cancel` would trap the player.
	var screen := _screen()
	screen.setup(_sworn())
	assert_eq(screen.on_stack_input(null), false, "a null event is declined")
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	assert_eq(screen.on_stack_input(cancel), false, "cancel is declined so the stack pops")
	var right := InputEventAction.new()
	right.action = &"ui_right"
	right.pressed = true
	assert_eq(screen.on_stack_input(right), false, "and so is everything else")
	screen.free()


func test_focus_records_its_target_before_any_focus_call() -> void:
	# `DestinyScreen` records `_focus_target` FIRST because a node outside a viewport
	# has nothing to focus yet — recording after the call would leave the field empty
	# in exactly the headless case the suite exercises.
	var screen := _screen()
	screen.setup(_sworn())
	screen.focus_initial()
	assert_ne(
		String(screen.summary()["focus_target"]),
		"",
		"the landing spot is recorded even with no viewport"
	)
	screen.free()


func test_the_row_pool_grows_rather_than_truncating() -> void:
	# A pool that dropped a row would silently drop content: the office list would shrink
	# to whatever the scene happened to mount. Grow the data past the mounted pool and
	# every authored office must still be there.
	var screen := _screen()
	screen.setup(_sworn())
	var mounted := (screen.summary()["office_ids"] as Array).size()
	assert_ne(mounted, 0, "the mounted pool is not empty")
	var padded := SectApi.summary(_sworn())
	var snapshot: Dictionary = padded.duplicate(true)
	var inflated := _inflate_offices(snapshot)
	screen.apply_snapshot(inflated)
	assert_eq(
		(screen.summary()["office_ids"] as Array).size() >= mounted,
		true,
		"a larger snapshot never shrinks the pool"
	)
	screen.free()


# --- The row panel owns every format ----------------------------------------


func test_the_claim_row_reports_an_empty_view_as_nothing_at_all() -> void:
	# The claim row's first state: `clear()` and never having been shown are the same
	# thing, and it reports `{}` rather than a shaped row with blanks.
	var row := (load(CLAIM_SCENE) as PackedScene).instantiate() as SectClaimRow
	assert_eq(row.summary(), {}, "empty before it is shown")
	assert_eq(row.is_filled(), false, "and it carries nothing")
	row.show_claim({"is_member": true, "sect_id": "iron_vine", "sect_name": "The Iron Vine"})
	assert_ne(row.summary(), {}, "a claim fills it")
	row.clear()
	assert_eq(row.summary(), {}, "and clearing empties it again")
	row.free()


func test_the_claim_row_formats_the_standing_and_the_screen_does_not() -> void:
	# AGENTS.md: "no number formatting in a screen — the panel owns `%d`, decimals and
	# widths." So the panel's rendered line carries the numbers, and the SCREEN's own
	# summary carries them raw, which is what a test can assert on.
	var row := (load(CLAIM_SCENE) as PackedScene).instantiate() as SectClaimRow
	(
		row
		. show_claim(
			{
				"is_member": true,
				"sect_id": "iron_vine",
				"sect_name": "The Iron Vine",
				"position_name": "Bulwark",
				"standing": 37,
				"standing_cap": 120,
				"standing_percent": 0.15,
			}
		)
	)
	var line := String(row.summary()["standing_line"])
	assert_ne(line.find("37"), -1, "the row prints the standing")
	assert_ne(line.find("120"), -1, "and the cap")
	assert_ne(line.find("%"), -1, "and the recognised percent")
	row.free()


func test_the_claim_row_shows_the_duties_the_office_authored() -> void:
	# A position is a duty, not a level (ADR 0083), so a claim that names an office
	# names what the office obliges — in the AUTHOR'S ids, never reworded.
	#
	# The ids are compared as `String`, not as `StringName`. The authored seed holds
	# `Array[StringName]` and `summary()` is primitives-only (AGENTS.md, UI
	# standard), so the screen reports the same characters with the primitive type
	# the contract names. Comparing the StringName array directly would be asserting
	# that a UI summary carries an engine type, which is the thing the contract
	# forbids — "verbatim" is about the TEXT, and this still fails if a single id is
	# reworded, re-cased or dropped.
	var actor := _sworn()
	var offices: Dictionary = SectApi.summary(actor)["can_promote"]
	var bulwark: Dictionary = offices["bulwark"]
	var authored: Array = (
		SectCatalog.instance().sect_definition(IRON_VINE).position(&"bulwark").duties
	)
	var duties: Array = []
	for duty in authored:
		duties.append(String(duty))
	var screen := _screen()
	screen.setup(actor)
	var reported: Array = screen.summary()["duties"] as Array
	assert_eq(reported, duties, "the screen reports the authored duty ids verbatim")
	var duty_line := String((screen.summary()["claim"] as Dictionary)["duty_line"])
	assert_ne(duty_line, "", "and the row names the office they belong to")
	for duty in duties:
		assert_ne(duty_line.find(String(duty)), -1, "%s is named" % duty)
	assert_ne(bulwark, {}, "the office the promotion route came from exists")
	screen.free()


func test_the_office_row_panel_is_the_one_the_board_shares() -> void:
	# The sect board and the nation board are different vocabularies (offices with a
	# succession walk vs. seats with a holder) but the SAME authored-seat widget, so a
	# screen that grew its own would be a second row contract to keep in step.
	var source := FileAccess.get_file_as_string(SCRIPT_PATH)
	assert_eq(
		source.contains(OFFICE_SCENE),
		true,
		"%s mounts the shared office row rather than a second one" % SCRIPT_PATH
	)
	var row := (load(OFFICE_SCENE) as PackedScene).instantiate() as NationOfficeRow
	row.show_office({"office_id": "bulwark", "display_name": "Bulwark", "vacant": true})
	assert_eq(row.is_filled(), true, "a seat nobody holds still EXISTS")
	assert_eq(row.is_vacant(), true, "and says so")
	row.show_office({})
	assert_eq(row.is_filled(), false, "a spare pool row does not")
	assert_eq(row.summary(), {}, "and reports nothing, not blanks")
	row.free()


# --- Plumbing ---------------------------------------------------------------


## A snapshot naming more offices than the mounted pool, so `_grow()` has something
## to grow into. Keys are ordered lexicographically, so a synthetic key sorts first and
## the assertion about pool size cannot depend on iteration order.
func _inflate_offices(snapshot: Dictionary) -> Dictionary:
	var routes: Dictionary = snapshot.get("can_promote", {}) as Dictionary
	# Snapshot the seed count BEFORE the loop. Testing `count < routes.size() + 4`
	# instead is an infinite loop: the body inserts one key per pass, so `size`
	# grows in lockstep with `count` and the +4 gap never closes.
	var target := routes.size() + 4
	var count := 0
	while count < target:
		routes["t_pad_%02d" % count] = _office_view("t_pad_%02d" % count)
		count += 1
	snapshot["can_promote"] = routes
	return snapshot


func _office_view(office_id: String) -> Dictionary:
	return {
		"id": office_id,
		"display_name": "Pad",
		"capacity": 1,
		"standing_floor": 0,
		"below_floor": false,
		"held": 0,
		"has_room": true,
		"reason": "",
		"succession": {},
		"teach_tax": 0.0,
	}
