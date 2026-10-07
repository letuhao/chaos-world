extends TestCase

## DEF-0261: the settlement roster a PLAYER can see, and the panel that keys on the
## room the player is actually standing in rather than on a boot-time cast.
##
## ## What this suite is really guarding
##
## `ItemWorkbenchPlay.npc_presence()` publishes a boot-time settlement — minted once by
## `NpcBoot.populate_room` into `mortal_plains`, never restocked — and for a whole
## cycle nothing in `ui/` read it, so a probe could see the cast and a player could not.
## The obvious fix was to mount a panel on that payload. That fix LIES: the payload never
## moves, so the panel would show the same four people for the whole session in whatever
## room the player walked into.
##
## So the rule this suite pins is narrower and sharper than "a roster panel exists":
## **the roster a player sees is the roster of the player's CURRENT location, and an
## unoccupied location shows nothing rather than a neighbour's cast.** Each of those is
## asserted by MOVING the hero and re-reading, not by inspecting a payload.

## The room the boot cast is stocked into. Named here so the "did the panel just show the
## boot room again?" assertions below can say it rather than hardcode a bare string.
const BOOT_ROOM := "mortal_plains"
## A room the authored content ships and the boot cast was never stocked into, so a panel
## showing this room's roster cannot be showing the boot cast.
const OTHER_ROOM := "spirit_peaks"
## The route a player takes to reach the place they are standing in, and so the screen
## the roster panel is mounted under. The app BOOTS on the workbench, so a mounted test
## has to navigate here to see the panel a player sees.
const EXPLORE_ROUTE := &"domain_explore"

var _born: Array = []


func setup() -> void:
	_born.clear()
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


func teardown() -> void:
	# Detach then `free()`, never `queue_free()`: the runner drives suites from
	# `SceneTree._initialize()` and never processes a frame, so a deferred free leaks for
	# the life of the process. That is the shape that took a run to 67 GB resident.
	for node in _born:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	_born.clear()
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


# ── The contract: summary() is primitives only ───────────────────────────────


## The panel publishes `summary()` and it holds nothing but primitives at any depth, so
## a headless test can assert it. Asserted on the scene as SHIPPED, before any payload,
## because a panel whose empty state is already dirty is a panel whose full state is too.
func test_the_shipped_panel_publishes_a_primitives_only_summary() -> void:
	var panel := _new_panel()
	var summary := panel.summary()
	assert_eq(summary.has("wired"), true, "the panel publishes its own binding state")
	assert_eq(_non_primitives(summary).is_empty(), true, "and nothing but primitives")


## With no room handed to it, the panel reports that it was not wired — NOT an empty
## room. "Nobody is here" and "this panel cannot ask" are different facts, and a panel
## that collapses them tells a player a room is empty when the truth is that it is mute.
##
## The `room_line` is the seam note, so it is deliberately NON-EMPTY while
## `roster_line` is deliberately EMPTY — see `test_the_unwired_line_names_the_missing_seam`,
## which pins both halves of that split. A player reads the line beside the list, so
## which of the two carries the sentence is a layout choice, not a contract; the
## contract is that ONE of them says the seam is missing and neither says the room is
## empty. Asserted here on the half that carries it, and not duplicated on both.
func test_an_unwired_panel_says_so_rather_than_claiming_an_empty_room() -> void:
	var panel := _new_panel()
	panel.show_room({})
	var summary := panel.summary()
	assert_eq(summary["wired"], false, "the panel knows nothing was wired to it")
	assert_eq(summary["count"], 0, "so it names nobody")
	assert_eq(
		String(summary["room_line"]) == NpcRosterPanel.EMPTY_ROOM_TEXT,
		false,
		"a muted panel must not read as an empty room"
	)
	assert_ne(
		String(summary["room_line"]).is_empty(),
		true,
		"and it must say something a player can act on"
	)


## The exact words a muted panel paints. Asserted rather than left to prose, because
## "nothing is wired" and "nobody is here" are the two halves of the honesty rule and
## one of them is the defect.
func test_the_unwired_line_names_the_missing_seam() -> void:
	var panel := _new_panel()
	panel.show_room({})
	var summary := panel.summary()
	assert_eq(String(summary["roster_line"]), "", "an unbound panel paints no roster line")
	assert_eq(String(summary["room_line"]), L.t(NpcRosterPanel.UNWIRED_TEXT), "and names why")


# ── Honesty: the roster is the CURRENT room's ─────────────────────────────────


## THE LOAD-BEARING CASE. A room with a cast in it paints that cast — and then the hero
## is MOVED to a room the boot cast was never stocked into, and the panel must change.
##
## This is the deliberate-move test. A panel keyed on `npc_presence()` passes the first
## assertion and fails the second, which is exactly why the second exists.
func test_the_panel_shows_the_cast_of_the_room_the_player_stands_in() -> void:
	var harness := _mount()
	var actor := harness.actor
	assert_ne(actor, null, "the composition root built a hero")
	if actor == null:
		return

	_stock(actor, BOOT_ROOM)
	var panel := _panel_of(_explore_of(harness))
	panel.show_room(NpcBoot.where_is(actor))
	var stocked := panel.summary()
	assert_eq(stocked["wired"], true, "the tracked room fact reached the panel")
	assert_eq(String(stocked["location_id"]), BOOT_ROOM, "so it names the room it read")
	assert_ne(int(stocked["count"]), 0, "and the cast standing there is named")

	# **Move the player.** Same actor, different room, through the production verb a
	# journey uses — `WorldSpawnApi.selected`, which is what `WorldStage.mount` writes.
	WorldSpawnApi.selected(actor, StringName(OTHER_ROOM))
	panel.show_room(NpcBoot.where_is(actor))
	var moved := panel.summary()
	assert_eq(String(moved["location_id"]), OTHER_ROOM, "the panel followed the hero")
	assert_eq(int(moved["count"]), 0, "and the room nobody is standing in shows nobody")
	assert_eq(
		String(moved["roster_line"]),
		L.t(NpcRosterPanel.EMPTY_ROOM_TEXT),
		"rather than the room the hero just left"
	)


## The half of the move test stated as its own failure: after moving, NONE of the boot
## cast survives on the panel. Names are compared one by one so a failure says whose
## name leaked rather than only that the list differs.
func test_no_name_from_the_room_the_player_left_survives_the_move() -> void:
	var harness := _mount()
	var actor := harness.actor
	if actor == null:
		return
	_stock(actor, BOOT_ROOM)
	var panel := _panel_of(_explore_of(harness))
	panel.show_room(NpcBoot.where_is(actor))
	var before := _names(panel.summary())

	WorldSpawnApi.selected(actor, StringName(OTHER_ROOM))
	panel.show_room(NpcBoot.where_is(actor))
	var after := _names(panel.summary())

	assert_eq(before.is_empty(), false, "the stocked room named somebody to begin with")
	for name in before:
		assert_eq(
			after.has(name),
			false,
			"'%s' stood in the room the hero LEFT, so it must not stand in the new one" % name
		)


## An empty location must not borrow a neighbour's cast, and must not fall back to
## "everywhere". `NpcApi.presence_here("")` is the everywhere answer and is the exact
## shape a lazy panel would show; this asserts the panel never receives one.
##
## ## Why the neighbour's room reads 4 and not 0
##
## The last assertion used to expect `0` for the hero that really is standing in a
## stocked room, and it failed with 4 — correctly. Two different actors occupy two
## different rooms, and the neighbour is standing in [constant BOOT_ROOM] with four
## people in it; filtering by the ROOM a hero stands in does not empty the room that
## hero is standing in. The assertion this case is really about is the one above it:
## the hero who is NOWHERE gets an explicit `0`, never the neighbours' four. The
## neighbour's own roster is asserted to be intact here, because a panel that reached
## into a neighbouring room to fill an empty one would leave it emptied.
func test_an_empty_location_shows_an_empty_roster_and_never_the_neighbours_cast() -> void:
	var harness := _mount()
	var actor := harness.actor
	if actor == null:
		return
	_stock(actor, BOOT_ROOM)

	# A hero who has never been placed is "nowhere", and "nowhere" is a representable
	# state rather than a failure (ADR 0113's `located: false`).
	var nowhere := _hero()
	var panel := _new_panel()
	panel.show_room(NpcBoot.where_is(nowhere))
	var summary := panel.summary()
	assert_eq(summary["located"], false, "a hero nobody placed is nowhere")
	assert_eq(String(summary["location_id"]), "", "with no room named")
	assert_eq(int(summary["count"]), 0, "so nobody is named")
	assert_eq(
		int((NpcBoot.where_is(nowhere)["here"] as Dictionary).get("count", -1)),
		0,
		"and the empty room is an explicit zero, not a borrowed list"
	)
	# And the stocked neighbour is still standing in its own room, untouched — the cast
	# in [constant BOOT_ROOM] is filtered BY that room, not merged into nowhere, and not
	# drained by nowhere having a reader.
	assert_ne(
		int((NpcBoot.where_is(actor)["here"] as Dictionary).get("count", 0)),
		0,
		"the neighbour's own roster is filtered by its own room, not merged into nowhere"
	)


## The defect this very function is easiest to get wrong, pinned as its own case: an
## UNLOCATED hero must not receive the everywhere roster.
##
## `NpcApi.presence_here("")` means "everywhere", so the one-line version of
## `where_is` — pass the empty id straight through — hands a hero standing nowhere the
## cast of every populated room. That is the borrowed-neighbour bug wearing a location
## filter as a disguise, and it is invisible at a glance because the payload looks right.
func test_a_hero_standing_nowhere_is_never_handed_the_everywhere_roster() -> void:
	# Stock a room for real, so "everywhere" would genuinely have bodies in it.
	var stocked := _hero()
	_stock(stocked, BOOT_ROOM)
	assert_ne(
		int((NpcBoot.where_is(stocked)["here"] as Dictionary).get("count", 0)),
		0,
		"the stocked room really does have a cast, so everywhere would be non-empty"
	)

	# A hero nobody placed.
	var nowhere := _hero()
	var answer := NpcBoot.where_is(nowhere)
	assert_eq(answer["located"], false, "this hero is nowhere")
	assert_eq(
		int((answer["here"] as Dictionary).get("count", -1)),
		0,
		"so its roster is an explicit zero, NOT the everywhere answer"
	)
	assert_eq(
		((answer["here"] as Dictionary).get("npcs", []) as Array).is_empty(),
		true,
		"and it borrows nobody's cast"
	)


# ── The panel keys on the location, not on the boot settlement ────────────────


## The anti-regression for DEF-0261 itself: the panel has no door through which the
## boot settlement could be handed to it. Asserted against the SHIPPED SCRIPT, because a
## panel that accepts an arbitrary cast array can be told a lie by any caller.
##
## ## Why this is the assertion the ruling asked for
##
## The repo owner ruled "build the feature properly — first a tracked current-room fact,
## then an honest read-only roster panel. Do not mount a panel over stale data." The only
## mechanical way to keep that true is to leave the panel exactly ONE way in, and
## [method NpcRosterPanel.show_room] is it.
func test_the_panel_has_no_door_that_could_be_handed_the_boot_settlement() -> void:
	var text := _read("res://src/ui/panels/npc_roster_panel.gd")
	var panel := _new_panel()
	assert_ne(panel, null, "the panel loads, so its method surface can be read")
	if panel == null:
		return
	var mutators: Array[String] = []
	# **Read off the SCRIPT, not off the instance.** `get_script_method_list()` is a
	# method of `Script`/`GDScript`; a `Node` has no such method, so calling it on the
	# panel is an `Invalid call` that aborts the test before it asserts anything. The
	# guard below is what turns a lost script into a counted failure instead.
	var script: GDScript = panel.get_script() as GDScript
	assert_ne(script, null, "the shipped panel has its script, so the surface can be read")
	if script == null:
		return
	for method in script.get_script_method_list():
		var name := String(method.name)
		if name.begins_with("_") or name in ["summary", "has_roster"]:
			continue
		mutators.append(name)
	assert_eq(
		mutators.size() == 1 and mutators[0] == "show_room",
		true,
		(
			(
				"the panel's only public mutator is show_room (found %s). A second door - "
				% str(mutators)
			)
			+ (
				"`show_npcs`, a `cast` setter, anything taking an array - is the seam the "
				+ "stale-cast panel would be written through."
			)
		)
	)
	assert_eq(
		text.contains("func show_room("),
		true,
		"and that one door takes the tracked room, place and cast together"
	)


## The composition root's tracked fact is a SEPARATE verb from the boot settlement, so a
## reader can see at the call site which one a screen is being handed.
func test_the_tracked_room_verb_is_distinct_from_the_boot_settlement_verb() -> void:
	# **Read the CLASS's script, not an instance's.** `where_is` is a STATIC verb, and
	# `NpcBoot` is a `RefCounted` — there is no instance of it to hand, so `NpcBoot.new()`
	# would be the wrong shape and reading an unrelated object's script would enumerate
	# THAT object's methods and answer `false` for ever. This case used to read the
	# surface off a probe `Actor`, which is why it asserted `where_is` was absent from a
	# list that never held it and from a class that has always declared it. This is the
	# same class-vs-instance correction BL-0871 (3) made to
	# `test_the_panel_has_no_door_that_could_be_handed_the_boot_settlement`, which reads
	# `panel.get_script() as GDScript` because a panel IS an instance.
	var declared: Array[String] = []
	for method in (NpcBoot as GDScript).get_script_method_list():
		declared.append(String(method.name))
	assert_eq(
		declared.has("where_is"), true, "NpcBoot declares where_is(): the tracked current-room fact"
	)
	# And it is not an alias of the boot settlement: the settlement is minted by
	# `populate_room` and reported by `ItemWorkbenchPlay.npc_presence`, so a caller that
	# reached for `npc_presence` by mistake would get a different dictionary shape.
	var actor := _hero()
	_stock(actor, BOOT_ROOM)
	var tracked := NpcBoot.where_is(actor)
	assert_eq(tracked.has("here"), true, "the tracked fact carries the cast for that room")
	assert_eq(tracked.has("npcs"), false, "and is not the settlement payload")


# ── The panel is mounted and driven through the seam ─────────────────────────


## The panel is a CHILD of the screen that renders the place you stand in, so it is
## reachable by a player without a route of its own. The panel test drives THAT screen
## — which is what makes the two mounted cases below prove the panel is reachable
## rather than merely present in a scene file.
func test_the_panel_is_mounted_in_the_screen_that_shows_the_place_you_stand_in() -> void:
	var text := _read("res://src/ui/screens/domain_explore.tscn")
	assert_eq(
		text.contains("npc_roster_panel.tscn"),
		true,
		"the roster panel is instanced by the domain explore scene"
	)
	assert_eq(
		text.contains('[node name="Roster"'), true, "as a named child a headless test can resolve"
	)


## The headless mount. The real composition root, the real screen, the real panel — and
## the panel's `summary()` read off the mounted tree rather than off an instance a test
## built for itself.
##
## Everything instantiated here is freed by `teardown()`: the runner shares ONE process
## across every suite, so a leak here is a leak everywhere.
func test_the_panel_mounts_headless_through_the_seam_harness_and_reports_a_summary() -> void:
	var harness := _mount()
	var screen := _explore_of(harness)
	assert_ne(screen, null, "a screen is mounted")
	if screen == null:
		return
	var panel := _panel_of(screen)
	assert_ne(panel, null, "and the roster panel is mounted under it")
	if panel == null:
		return
	var summary := panel.summary()
	assert_eq(summary.has("count"), true, "the mounted panel publishes a count")
	assert_eq(summary.has("location_id"), true, "and the room it is reporting")
	assert_eq(
		_non_primitives(summary).is_empty(), true, "and holds nothing but primitives at any depth"
	)


## The screen nests the panel's summary under the panel's own key rather than merging
## it, so the roster is one addressable fact instead of a dozen keys spread across a
## larger dictionary.
func test_the_screen_nests_the_roster_under_the_panel_key() -> void:
	var harness := _mount()
	var screen := _explore_of(harness)
	if screen == null or not screen.has_method(&"summary"):
		return
	var summary := screen.call(&"summary") as Dictionary
	assert_eq(summary.has("roster"), true, "the screen publishes the roster under `roster`")
	var roster := summary.get("roster", {}) as Dictionary
	assert_eq(roster.has("count"), true, "holding the panel's own count")
	assert_eq(
		_non_primitives(summary).is_empty(),
		true,
		"and the whole screen summary is still primitives only"
	)


# ── Plumbing ─────────────────────────────────────────────────────────────────


## The real composition root, mounted through the harness, WITH THE EXPLORE ROUTE
## DRIVEN. Freed by `teardown()`.
##
## ## Why the route is navigated rather than accepting the boot screen
##
## The app boots on the workbench, so `live_screen()` is the workbench — which is not
## the screen the roster panel lives in. Reading the boot screen here would have proved
## nothing: the mounted panel would be absent because it is genuinely not on that
## screen, and the assertion would have been failing for the wrong reason the whole
## time. So the mounted cases drive the route a player takes to reach the place they
## stand in, and `harness.navigate` REFUSES rather than asserting (a route table that
## stopped naming this screen fails loudly instead of quietly showing the workbench).
func _mount() -> SeamHarness:
	var harness := SeamHarness.mount_new()
	_born.append(harness.app)
	# **The verdict is ASSERTED, not discarded.** `SeamHarness.navigate` answers
	# `{ok, note}` precisely so a caller records a real failure instead of silently
	# reading the wrong screen — dropping the return here would leave every case below
	# pointing at "the panel is missing" when the true cause is "the route no longer
	# reaches this screen", which is the same class of wrong-reason failure this helper
	# exists to end.
	var reached := harness.navigate(EXPLORE_ROUTE)
	var note := String(reached.get("note", ""))
	assert_eq(
		bool(reached.get("ok", false)),
		true,
		note if not note.is_empty() else "the explore route did not answer"
	)
	return harness


## The explore screen the player can actually reach, or null. Fails through
## [method _mount]'s `navigate` when the route is gone, so a null here is a mount that
## never produced a screen rather than a screen this panel is missing from.
func _explore_of(harness: SeamHarness) -> Control:
	return harness.live_screen()


## A panel instantiated the way a headless test may. Detached, and freed by `teardown()`.
func _new_panel() -> NpcRosterPanel:
	var packed := load("res://src/ui/panels/npc_roster_panel.tscn") as PackedScene
	assert_ne(packed, null, "the panel scene loads")
	if packed == null:
		return null
	var panel := packed.instantiate() as NpcRosterPanel
	assert_ne(panel, null, "and instantiates as an NpcRosterPanel")
	_born.append(panel)
	return panel


## The panel off the MOUNTED tree, never one this suite built for itself. A test that
## instantiates its own screen proves the scene parses; it proves nothing about the app a
## player runs.
func _panel_of(screen: Control) -> NpcRosterPanel:
	if screen == null:
		return null
	return screen.get_node_or_null("%Roster") as NpcRosterPanel


## Stock a room with the authored cast, through the production room-load verb, and leave
## the player standing in it. Two production verbs and nothing invented, so the roster
## the panel reads came out of the same machinery a player's session uses.
func _stock(actor: Actor, room: String) -> void:
	WorldSpawnApi.selected(actor, StringName(room))
	NpcBoot.populate_room(
		actor,
		[&"elder_wei", &"gate_keeper_bo", &"smith_bearcutter", &"drifter"],
		NpcApi.ROLE_NPC,
		StringName(room)
	)


## A hero with nothing attached, for the "nowhere" case. Built by the same factory the
## composition root uses rather than by hand, so its `module_data` is the real shape.
func _hero() -> Actor:
	return ActorFactory.build(
		&"player", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0, Stat.APTITUDE: 6.0}
	)


## The names on a panel summary, so a leak can be reported by name.
func _names(summary: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for row in summary.get("rows", []) as Array:
		out.append(String((row as Dictionary).get("display_name", "")))
	return out


## Dotted paths whose value is not a primitive or a dictionary of the same.
func _non_primitives(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Dictionary:
		var entries: Dictionary = value
		for key in entries:
			var child: Variant = entries[key]
			if child is Dictionary or _is_primitive(child):
				out.append_array(_non_primitives(child))
			else:
				out.append(String(key))
		return out
	if value is Array:
		var items: Array = value
		for index in items.size():
			out.append_array(_non_primitives(items[index]))
	return out


func _is_primitive(value: Variant) -> bool:
	if value == null:
		return true
	var kind := typeof(value)
	return (
		kind == TYPE_BOOL
		or kind == TYPE_INT
		or kind == TYPE_FLOAT
		or kind == TYPE_STRING
		or kind == TYPE_STRING_NAME
		or kind == TYPE_ARRAY
	)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)
