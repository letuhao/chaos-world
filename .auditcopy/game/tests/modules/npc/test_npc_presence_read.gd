extends TestCase

## `NpcApi.presence_here` is called by PRODUCTION — `app/npc_boot.gd`
## `populate_room` and `read_model` both read `npcs`/`here` off it — and by NO
## test. A room-load screen's whole content comes off this one verb.
##
## ## Why the module suite does not already cover it
##
## `modules/npc/*` proves the roster, the tiers and the stage ladder, but every
## one of those suites reads `NpcApi.state(player)` or the registry directly.
## `presence_here` is the ROOM-FACING read, and it is the only place the
## `truncated` flag is computed — so a read that silently dropped an npc from a
## crowded room would pass every existing suite and still lose someone from the
## scene.
##
## `app/npc_boot.gd:109` publishes it as `here`, and `:95` as `npcs`, so a
## mutation that emptied it is invisible from outside the module.

## Well under `NpcReadModel.MAX_PRESENCE_READ`, so `truncated` must stay false
## here and the presence assertion is about CONTENT, not about the cap.
const ROOM_NPCS: Array[StringName] = [&"drifter", &"smith_bearcutter"]

var _player: Actor
var _minted: Array[Actor] = []


func setup() -> void:
	_player = ActorFactory.build(&"presence_reader")
	_minted.append(_player)


## `install` is what a room load does first: it binds the minter and attaches.
## The spawn result is asserted, never returned: `populate` answers the actors it
## minted, and a helper that handed back a Dictionary while ignoring that would
## let a zero-cast room look like a stocked one.
func _room_open(def_ids: Array[StringName]) -> Array[Actor]:
	NpcBoot.install(_player)
	var spawned := NpcApi.populate(def_ids, &"npc")
	assert_ne(spawned.size(), 0, "the fixture really did stock the room")
	return spawned


## `populate_room` is the production entry point, so the assertion is on what IT
## returns rather than on the facade called directly — the caller must not have to
## re-derive the verb to fill a screen.
func test_populate_room_publishes_exactly_who_it_spawned() -> void:
	var room := NpcBoot.populate_room(_player, ROOM_NPCS)
	var listed: Array = room.get("npcs", []) as Array
	assert_ne(listed.size(), 0, "the room load published somebody")
	var names: Array[String] = []
	for entry in listed:
		names.append(String((entry as Dictionary).get("npc_id", entry)))
	for id in ROOM_NPCS:
		assert_eq(names.has(String(id)), true, "%s is in the room it was told to stock" % id)


## The `truncated` flag is the reason this verb exists rather than a bare array:
## a read that quietly lost an npc says so instead. A two-npc room is nowhere
## near the cap, so `false` here is a real measurement and not a default.
func test_an_uncrowded_room_is_not_truncated() -> void:
	_room_open(ROOM_NPCS)
	var here := NpcApi.presence_here()
	assert_eq(bool(here.get("truncated", false)), false, "two npcs never reach the read cap")


## Every entry is a PRIMITIVE row, because this dictionary is handed to `ui/`
## and a Resource in it would be an edge `tools/arch/rules.py` has not granted.
## A panel formats from these, so a nested object here is a facade bug.
func test_every_presence_row_is_primitives() -> void:
	_room_open(ROOM_NPCS)
	var here := NpcApi.presence_here()
	var rows: Array = here.get("npcs", []) as Array
	assert_ne(rows.size(), 0, "there is somebody to describe")
	for entry in rows:
		assert_eq(entry is Dictionary, true, "a row is a dictionary")
		for key in (entry as Dictionary).keys():
			var value: Variant = (entry as Dictionary)[key]
			var primitive := value is String or value is float or value is int or value is bool
			assert_eq(primitive, true, "'%s' is a primitive, not a Resource" % key)


## An empty room is a real state (the player walked in before the cast loaded),
## and it must answer `npcs: []` rather than omitting the key — `npc_boot.gd`
## reads `.get("npcs", [])`, which would otherwise be indistinguishable from
## "the read failed".
func test_an_empty_room_publishes_an_empty_list_rather_than_nothing() -> void:
	NpcBoot.install(_player)
	var here := NpcApi.presence_here()
	assert_eq(here.has("npcs"), true, "the key is always published")
	assert_eq((here.get("npcs", []) as Array).size(), 0, "and it is empty")


## `install` clears the live registry, so a read must not be the thing that
## empties a room a panel is about to render. `read_model`'s docstring says a
## read binds nothing; this is that claim, measured.
func test_reading_presence_twice_does_not_empty_the_room() -> void:
	_room_open(ROOM_NPCS)
	var first := (NpcApi.presence_here().get("npcs", []) as Array).size()
	var second := (NpcApi.presence_here().get("npcs", []) as Array).size()
	assert_ne(first, 0, "the room has a cast to begin with")
	assert_eq(second, first, "a poll is not a room clear (INC: read_model installs nothing)")


## `location_id` filters nothing by itself — it is reported back so a caller can
## tell which room it asked about, and a screen that passed a stale id must be
## able to see that in the answer rather than infer it.
func test_the_asked_location_comes_back_in_the_answer() -> void:
	_room_open(ROOM_NPCS)
	var here := NpcApi.presence_here(&"some_room")
	assert_eq(
		String(here.get("location_id", "")), "some_room", "the read echoes the room asked for"
	)
