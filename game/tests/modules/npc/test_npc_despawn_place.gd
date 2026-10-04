extends TestCase

## ## `despawn` clears PRESENCE but not PLACE, and that is the decision, not an oversight
##
## ## N1 (LOW-MEDIUM): a despawned npc reports the room you last met them in
##
## `NpcApi.despawn` sets `entry.presence = KNOWN` and leaves `entry.location_id` alone.
## `NpcReadModel.summary` publishes `live_location_id if is_live else entry.location_id`,
## so an off-stage tracked npc's row reads back the place they were last minted in.
## `test_npc_tier.gd` asserted the *presence* half of that transition and never the
## *place*, so a future reader could not tell whether "last met them here" was the design
## or a stale row that escaped a cleanup.
##
## ## The decision: it is CORRECT, and here is why
##
## Two distinct facts, deliberately kept apart (ADR 0092 line 49, BL-0715):
##
##   - **the LIVE place** (`NpcRegistry`) is "where the body is standing right now" and is
##     what a room filter matches;
##   - **the roster's `location_id`** is "where you LAST met them" — a memory of the last
##     encounter, which is exactly what a content author wants for "where do I go to find
##     this person next". It is never distance input (the room owns distance, ADR 0072).
##
## **It cannot leak into a live-room read, and that is the load-bearing half.**
## `presence_here` iterates `NpcRegistry.present_ids()` — LIVE bodies only — and a
## despawned npc is released from the registry on the same call. So the remembered place is
## reachable ONLY through `summary()` for an npc with no live body, and NEVER through the
## `location_id` filter that decides "who is in this room". Clearing `location_id` on
## despawn would actually *lose* the memory the field exists to hold (the whole point of
## ADR 0092's "remembered, not forgotten" contract for tracked npcs) without fixing any
## leak, because there is no leak to fix.
##
## So the pin is not "the place is cleared" — it is: (a) an off-stage npc's summary
## publishes the LAST-MET place, verbatim, and (b) that same remembered place does NOT
## put them back into the room they left. Both halves below, because either one alone is
## the behaviour a wrong future edit could produce while still passing the other.

## The tracked cast member. MAJOR tier, so it takes a roster entry that can hold a place.
const SMITH := &"smith_bearcutter"
## The untracked cast member. TRANSIENT tier, so it has no roster entry at all — the
## contrast case proving the remembered place only ever lives on a tracked row.
const DRIFTER := &"drifter"
## The room the two are stocked into.
const ROOM := &"mortal_plains"
## A second room, used to prove the remembered place does not travel with them.
const OTHER := &"cloud_reach"

var _player: Actor


func setup() -> void:
	_player = ActorFactory.build(&"despawn_place")
	NpcBoot.install(_player)


func teardown() -> void:
	# Process-wide live registry; the runner reuses this process across suites.
	NpcRegistry.instance().reset()


# --- (a) the remembered place is published off-stage, verbatim --------------------


## **The half that pins the CHOICE.** A tracked npc who has left the room still reports the
## place they were last met — NOT an empty string, and NOT the room they never entered.
## This is the assertion that fails if someone "cleans up" `location_id` on despawn, and it
## is the assertion that documents "last met them here" as intended.
func test_an_off_stage_tracked_npc_reports_where_it_was_last_met() -> void:
	NpcApi.spawn(SMITH, NpcApi.ROLE_NPC, ROOM)
	NpcApi.despawn(SMITH)
	var row := NpcApi.summary(SMITH)
	assert_eq(row["known"], true, "the player still knows the smith")
	assert_eq(row["presence"], "Known", "off-stage, not forgotten")
	assert_eq(
		String(row["location_id"]),
		String(ROOM),
		"and the row still names the room they were last met in"
	)


## The remembered place is a MEMORY, so a save round trip must carry it — otherwise a
## tracked npc would forget where they lived every time the game closed. `NpcApi.state`
## is the save payload (`to_dict`), so reading it is reading what the save will contain.
func test_the_remembered_place_survives_a_save_round_trip() -> void:
	NpcApi.spawn(SMITH, NpcApi.ROLE_NPC, ROOM)
	NpcApi.despawn(SMITH)
	var saved := NpcApi.state(_player)
	var entries: Dictionary = saved.get("entries", {}) as Dictionary
	assert_eq(entries.has(String(SMITH)), true, "the smith has a saved roster entry")
	assert_eq(
		String((entries[String(SMITH)] as Dictionary).get("location_id", "")),
		String(ROOM),
		"and the saved entry keeps the last-met place"
	)


## An UNTRACKED npc leaves no roster entry, so there is no remembered place to keep. This
## is the contrast that proves the field's scope: "last met them here" is a property of a
## TRACKED row only, never a global the despawn path writes.
func test_an_untracked_npc_remembers_nothing_because_it_has_no_row() -> void:
	NpcApi.spawn(DRIFTER, NpcApi.ROLE_NPC, ROOM)
	NpcApi.despawn(DRIFTER)
	var entries: Dictionary = NpcApi.state(_player).get("entries", {}) as Dictionary
	assert_eq(entries.has(String(DRIFTER)), false, "a transient leaves no roster entry")
	assert_eq(NpcApi.summary(DRIFTER)["known"], false, "and is a stranger again")


# --- (b) the remembered place does NOT leak into a live-room read ----------------


## **The half that pins that it is not a LEAK.** The place an off-stage npc remembers is
## `ROOM`, and it stays off-stage. Asking "who is in ROOM" after the despawn must not
## resurrect the smith — the remembered place is content-facing metadata, and the room
## filter reads the LIVE registry, not the roster's memory. A change that leaked the
## remembered place into the room filter would make a departed npc haunt a room they left.
func test_a_departed_npc_does_not_appear_in_the_room_they_left() -> void:
	NpcApi.spawn(SMITH, NpcApi.ROLE_NPC, ROOM)
	NpcApi.spawn(DRIFTER, NpcApi.ROLE_NPC, ROOM)
	NpcApi.despawn(SMITH)
	# The smith is gone but still remembers ROOM; only the drifter is really here.
	var here := NpcApi.presence_here(ROOM)
	var names: Array[String] = []
	for entry in here.get("npcs", []) as Array:
		names.append(String((entry as Dictionary).get("npc_id", "")))
	assert_eq(names.has(String(DRIFTER)), true, "the drifter really is still in the room")
	assert_eq(
		names.has(String(SMITH)),
		false,
		"but the departed smith does not haunt the room they left, remembered place or not"
	)
	assert_eq(
		int(here.get("count", -1)), 1, "and the count matches the one body that is actually present"
	)


## The symmetric sanity check: while the smith is LIVE, `presence_here(ROOM)` DOES find
## them via their live place — so the filter is real and is not simply broken to hide the
## leak above. Without this, the previous test could pass against a filter that never
## matches anybody.
func test_the_room_filter_is_real_while_the_npc_is_live() -> void:
	NpcApi.spawn(SMITH, NpcApi.ROLE_NPC, ROOM)
	assert_eq(
		int(NpcApi.presence_here(ROOM).get("count", -1)),
		1,
		"a live smith in the room is found by their live place"
	)
	assert_eq(
		int(NpcApi.presence_here(OTHER).get("count", -1)),
		0,
		"and an empty neighbouring room agrees there is nobody there"
	)
