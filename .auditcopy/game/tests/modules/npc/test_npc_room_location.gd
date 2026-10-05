extends TestCase

## **A spawned row records the location it was minted for** (BL-0715, F1).
##
## `NpcBoot.populate_room` took a `location_id`, passed it to `presence_here`, and
## never passed it to `NpcApi.populate` — so every row it created recorded
## `location_id: ""` and the very next line filtered all of them out. The
## production caller (`app/item_workbench_app.gd`) passes `&"mortal_plains"`, so
## the starting settlement answered `spawned: 4, npcs: []` while four bodies
## stood in it.
##
## Nothing caught it because `populate_room`'s only test omitted the location:
## with `""` on both sides the filter is a tautology and the shape of the bug is
## invisible. The tests below call the PRODUCTION shape — the one the boot calls —
## so a write that never reaches the row has nowhere to hide.
##
## `read_model` hid the same bug by asking `presence_here()` with no location, so
## the "is anything here at all" question was the only one on offer.

## The location the boot really passes (`item_workbench_app.gd`, `STARTING_CAST`).
const ROOM := &"mortal_plains"
## A place nobody was stocked into. Two bodies standing in `ROOM` are NOT here.
const NOWHERE := &"cloud_reach"
## One tracked (major) and one untracked (transient) member, so a fix that only
## records a place on a roster row — the one place a transient npc has none — is
## caught as well as one that fixes neither.
const ROOM_NPCS: Array[StringName] = [&"drifter", &"smith_bearcutter"]

var _player: Actor


func setup() -> void:
	_player = ActorFactory.build(&"room_locator")
	# `install` is what a room load does first, and it is also what reads the
	# authored cast off disk — so these ids are the SHIPPED ones rather than a
	# fixture another suite happened to install.
	NpcBoot.install(_player)
	expect_assertions(2)


func teardown() -> void:
	# Process-wide. The runner calls this after every test and reuses the process,
	# so a live actor left standing here would show up in whichever suite runs next.
	NpcRegistry.instance().reset()


# --- The defect (F1) -------------------------------------------------------------


## The settlement panel's whole content. `spawned` counted what it stood up and
## `npcs` listed nobody, because the read filtered by a place the write never
## recorded — and every row is checked, not just the first, because a fix that
## threads the location to the TRACKED spawn alone still loses the drifter.
func test_populate_room_lists_the_cast_it_just_stood_up() -> void:
	var room := NpcBoot.populate_room(_player, ROOM_NPCS, &"npc", ROOM)
	assert_eq(int(room.get("spawned", 0)), ROOM_NPCS.size(), "it says how many bodies stood up")
	var rows: Array = room.get("npcs", []) as Array
	assert_eq(rows.size(), ROOM_NPCS.size(), "and it lists exactly those bodies")
	for entry in rows:
		var row := entry as Dictionary
		assert_eq(
			String(row.get("location_id", "")),
			String(ROOM),
			"every row records the room it was minted for"
		)


## The filter's own contract, measured from both sides. A read of an empty place
## returns nothing ONLY if the two bodies really were recorded somewhere else —
## which is why the second assertion is here and not in its own test: without it
## this suite would stay green against a read model that returned nobody for
## everywhere.
func test_a_place_with_nobody_in_it_reports_nobody_and_does_not_borrow_the_neighbours() -> void:
	NpcBoot.populate_room(_player, ROOM_NPCS, &"npc", ROOM)
	var empty := NpcApi.presence_here(NOWHERE)
	assert_eq(int(empty.get("count", -1)), 0, "an empty place lists nobody")
	assert_eq((empty.get("npcs", []) as Array).size(), 0, "and names nobody")
	assert_ne(
		(NpcApi.presence_here(ROOM).get("npcs", []) as Array).size(),
		0,
		"the two bodies really are in the place they were stocked into"
	)


## The bound survives threading a fourth argument through `populate`. A room list
## longer than the cap is served up to the cap and no further, and the panel's
## `npcs` count agrees with `spawned` rather than exceeding it.
func test_over_populating_a_room_is_still_bounded_by_the_named_cap() -> void:
	var ids: Array[StringName] = []
	for _index in range(NpcApi.MAX_ROOM_POPULATION + 12):
		ids.append(&"drifter")
	var room := NpcBoot.populate_room(_player, ids, &"npc", ROOM)
	assert_eq(int(room.get("spawned", 0)), NpcApi.MAX_ROOM_POPULATION, "capped at the named bound")
	assert_eq(
		(room.get("npcs", []) as Array).size(),
		NpcApi.MAX_ROOM_POPULATION,
		"and the panel is shown exactly what was stood up"
	)
