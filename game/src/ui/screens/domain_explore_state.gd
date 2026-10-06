class_name DomainExploreState
extends RefCounted

## The READ half of [DomainExploreModel], split out for one reason: `max-public-methods`
## caps a class at 20 and the whole model publishes 21. Inheritance is what makes the
## split free — `DomainExploreModel` keeps every one of those 21 doors at the same name,
## on the same object, with the same behaviour, so no caller and no test changes.
##
## ## Why reads, and not wording
##
## This half is the model's data and the reads it makes of the domain module. It is the
## half a caller cannot live without: every method below is called from
## `DomainExploreScreen`, and none of them is a one-line view of a field the screen
## could get from `summary()` instead. The wording half stayed put because it is all
## private already — `_header_text()`, `_rooms_text()` and the rest are `_`-prefixed and
## never counted against the cap.
##
## ## Why the state accessors live here and not on the model
##
## `max-public-methods` counts a class's OWN public functions, so a base class is the only
## move that lowers the count without changing a single door: a method declared here is
## inherited, and `DomainExploreModel.new().bridge()` resolves to it exactly as it did
## before the split. That is why three accessors — and not a helper — crossed the line.
##
## The 22 read helpers that moved with them are all `_`-prefixed and were never counted;
## they came along because they are the accessors' own bodies and splitting a method from
## its helper would have left a base reading state it no longer owns.
##
## ## The guards below are load-bearing, not defensive noise
##
## Every read is guarded because `_ready()` runs long before `bind_bridge` has ever been
## called, so a screen the shell has not wired yet reaches all of them. A reader that
## dereferenced `_bridge` directly aborted the whole refresh, and an unbound screen
## reported no rooms, no population and no fixtures instead of reporting an empty domain.
##
## The selection moves on the AUTHORED room list, never the fogged drawn one: the fog is
## what the module has DISCOVERED, so gating on it made an undiscovered room
## unselectable and the domain could only ever be one room deep (ADR 0207).

## The fields a room row publishes, and the fields a zone row does. They live on
## the BASE rather than on `DomainExploreModel` because `_subset` below is what
## reads them, and a base cannot resolve a derived class's constants -- declaring
## them on the model is what failed this file's parse with "not declared in the
## current scope" (split repair). Inherited, so the model keeps the same doors.
const ROOM_KEYS := [
	"room_id",
	"kind",
	"tier",
	"hostile",
	"is_entry",
	"is_core",
]

const ZONE_KEYS := [
	"room_id",
	"zone_id",
	"kind",
	"severity",
	"mitigation_tags",
]

var _bridge: DomainBridge = null
## The actor as of the last refresh, and the active run as the module last reported it, so
## `summary()` answers with what the module said rather than re-asking three facades and
## hoping they agree.
var _actor: Actor = null
var _view: Dictionary = {}
## The room being looked at and the fixture being acted on within it. Both are IDS and
## never indices, so a run that regenerates cannot leave an action aimed at the wrong row.
var _selected_room: StringName = &""
var _selected_fixture: StringName = &""
var _puzzle_node: StringName = &""
## A room a caller NAMED that the module refused, held only until the next selection
## moves. Set by `select_room`'s refusal and read by the `Visit` gate: without it a
## rejected selection silently fell back to the previous room and the verb walked
## somewhere the caller never asked for. `{}` is "nothing pending" and it is the state
## every other selection path leaves behind.
var _pending_room: StringName = &""


## The bridge the screen was handed, or null before `bind_bridge`. The gates and the
## reason table read it through here, so no caller has to null-check it twice.
func bridge() -> DomainBridge:
	return _bridge


## What the MODULE reports is active, or `{}` outside a run. `{}` is the repo's
## does-not-exist vocabulary — not an error, and never a fabricated zeroed view.
func active() -> Dictionary:
	return _view


## Where the player is looking, as plain strings: the room, the fixture within it, the
## puzzle node, and the room a caller NAMED that the module refused. Four ids rather than
## four accessors because they are always read together — a gate reads two of them, the
## summary publishes three, and a selection that could be half-read is the drift the
## screen's `_can_*` pair of checks exists to prevent.
func selection() -> Dictionary:
	return {
		"room": String(_selected_room),
		"fixture": String(_selected_fixture),
		"node": String(_puzzle_node),
		"pending": String(_pending_room),
	}


## The room list, or `[]` outside a run AND before the seam is filled.
func _rooms() -> Array:
	if _bridge == null or not _bridge.has(&"rooms"):
		return []
	return _bridge.call_list(&"rooms", [_actor])


func _read_templates() -> Array:
	if _bridge == null or not _bridge.has(&"list_templates"):
		return []
	return _bridge.call_list(&"list_templates")


## What the MODULE reports is active, or `{}` outside a run.
##
## Unwraps the `active` key the seam publishes rather than storing the whole envelope:
## the model's `_view` is the run itself, and every reader wants the run and not
## `{has_actor, templates, active}`.
##
## This is the read a past refactor renamed to `_active()`, a function that has never
## existed here. The parse error that raised left this script registering as a bare
## `GDScript` with no `new`, which is what kept `_model` null on every live screen and
## turned each refresh into `Nonexistent function ... in base 'Nil'`. The name is
## `read_`-prefixed to sit beside its twin `_read_templates`.
func _read_active() -> Dictionary:
	if _bridge == null or not _bridge.has(&"read_active"):
		return {}
	var envelope := _bridge.call_action(&"read_active", [_actor])
	return envelope.get("active", {}) as Dictionary


## The floor plan, exactly as the module rendered it. `{}` outside a run, which the
## model's wording reads as "no floor plan" rather than as an empty map.
func _minimap() -> Dictionary:
	if _actor == null or _bridge == null or not _bridge.has(&"minimap"):
		return {}
	return _bridge.call_action(&"minimap", [_actor])


## The minimap's own room layer. `{}` has no `rooms` key, so the empty case is named
## rather than indexed — an absent key and an empty map must not read alike.
func _drawn_rooms(minimap: Dictionary) -> Array:
	var rows: Variant = minimap.get("rooms", [])
	return rows as Array if rows is Array else []


## One row per DISCOVERED room, carrying the kind and the tier it PROMISES. The tier is
## the minimap's own verdict and is passed through untouched.
func _room_rows(minimap: Dictionary) -> Array:
	var rows: Array = []
	for row in _drawn_rooms(minimap):
		var room := row as Dictionary
		rows.append(_subset(room, ROOM_KEYS))
	return rows


## The severe zones, flattened with the room each sits in and the levers that reduce it.
## Deliberately NOT fogged: routing AROUND a hazard needs seeing it before standing in it.
func _zone_rows(minimap: Dictionary) -> Array:
	var rows: Array = []
	for entry in minimap.get("zones", []):
		rows.append(_subset(entry as Dictionary, ZONE_KEYS))
	return rows


## `source` re-keyed down to `keys`, every value coerced to a primitive. The coercion is
## the point, not a convenience: an authored fixture row carries `Vector2i` positions and
## a `Rect2i` boundary, and a `summary()` holding either is a testable surface that
## quietly stops being testable. `String()` and `int()` are the only two coercions used,
## because a row in this program is strings, numbers, booleans and arrays.
func _subset(source: Dictionary, keys: Array) -> Dictionary:
	var out := {}
	for key in keys:
		var value: Variant = source.get(key, null)
		if value is Array:
			out[key] = _strings(value)
		elif value is bool or value is int or value is float:
			out[key] = value
		else:
			out[key] = String(value) if value != null else ""
	return out


func _strings(values: Variant) -> Array:
	var out: Array = []
	if not values is Array:
		return out
	for value in values as Array:
		out.append(String(value))
	return out


## The population grouped by role, because "three mobs and a boss" is a roster and four
## separate rows are not. Roles are TAGS on an actor and never classes (ADR 0074), so the
## grouping is over a string and the module decided what is hostile.
func _population_rows() -> Array:
	var by_role: Dictionary = {}
	for entry in _rooms():
		for ref in (entry as Dictionary).get("actor_spawn_refs", []):
			var row := ref as Dictionary
			var role := String(row.get("role", ""))
			if role.is_empty():
				continue
			by_role[role] = int(by_role.get(role, 0)) + maxi(1, int(row.get("count", 1)))
	var rows: Array = []
	for role in by_role.keys():
		rows.append({"role": String(role), "count": int(by_role[role])})
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return String(a["role"]) < String(b["role"])
	)
	return rows


## The fixtures the SELECTED room holds, from the facade's own room read.
##
## Scanned over EVERY room rather than stopping at the first miss, because the room list
## is canonical by id and a selection may name any of them: a scan that stopped early
## reported "this room holds no fixtures" for a room three rows further down.
func _fixtures_of(room_id: StringName) -> Array:
	var out: Array = []
	if room_id.is_empty():
		return out
	for entry in _rooms():
		var room := entry as Dictionary
		if StringName(String(room.get("room_id", ""))) != room_id:
			continue
		for fixture in room.get("fixtures", []):
			out.append(fixture as Dictionary)
	return out


## The selected fixture's authored row, or `{}`. Read for its STRINGS only: an authored
## fixture carries `Vector2i` / `Rect2i` positions, and an engine type in a summary is
## what makes a testable surface untestable.
func _selected_fixture_row() -> Dictionary:
	for fixture in _fixtures_of(_selected_room):
		if StringName(String(fixture.get("fixture_id", ""))) == _selected_fixture:
			return fixture
	return {}


## A formation's strikeable nodes, from the AUTHORED fixture. Empty for a trap or a
## treasure, which is honest: neither has a node to strike.
func _puzzle_nodes() -> Array[StringName]:
	var out: Array[StringName] = []
	for node in _selected_fixture_row().get("nodes", []):
		out.append(StringName(String(node)))
	return out


## Every room the active run AUTHORED, fog notwithstanding. The room list is the
## module's, unfiltered; filtering it by discovery here would leave a player able to
## walk only through rooms they had already been in, which is not exploring.
func _authored_rooms() -> Array:
	return _rooms()


## `{room_id: tier}` for the rooms the minimap has drawn. `{}` outside a run and for a
## room the fog has not lifted, which is why a room row falls back rather than inventing
## a band of its own.
func _drawn_tiers() -> Dictionary:
	var out: Dictionary = {}
	for row in _drawn_rooms(_minimap()):
		var room := row as Dictionary
		out[String(room.get("room_id", ""))] = String(room.get("tier", ""))
	return out


## Keep the selection honest across a refresh. A run that regenerated, or a room left
## behind, must not leave a stale id selected — an action aimed at one would refuse for a
## reason the player never caused.
##
## Checked against the AUTHORED rooms for the same reason `select_room` is: the selection
## is where the player is LOOKING, which is a different question from where the floor plan
## has drawn. Reconciling against the fogged set reset the selection to the entry room on
## every refresh, so a player could not hold a look at an unfound room.
func _reconcile_selection() -> void:
	var authored := _authored_rooms()
	if authored.is_empty():
		_selected_room = &""
		_selected_fixture = &""
		_puzzle_node = &""
		_pending_room = &""
		return
	if not _contains_room(authored, _selected_room):
		_selected_room = StringName(String((authored[0] as Dictionary).get("room_id", "")))
	_reconcile_fixture()
	_reconcile_node()


func _reconcile_fixture() -> void:
	var fixtures := _fixtures_of(_selected_room)
	if fixtures.is_empty():
		_selected_fixture = &""
		_puzzle_node = &""
		return
	if not _contains_fixture(fixtures, _selected_fixture):
		_selected_fixture = StringName(String((fixtures[0] as Dictionary).get("fixture_id", "")))


func _reconcile_node() -> void:
	var nodes := _puzzle_nodes()
	if nodes.is_empty():
		_puzzle_node = &""
		return
	if not nodes.has(_puzzle_node):
		_puzzle_node = nodes[0]


func _contains_room(rows: Array, room_id: StringName) -> bool:
	return _index_of_room(rows, room_id) >= 0


func _contains_fixture(fixtures: Array, fixture_id: StringName) -> bool:
	return _index_of_fixture(fixtures, fixture_id) >= 0


func _index_of_room(rows: Array, room_id: StringName) -> int:
	for index in rows.size():
		if StringName(String((rows[index] as Dictionary).get("room_id", ""))) == room_id:
			return index
	return -1


func _index_of_fixture(fixtures: Array, fixture_id: StringName) -> int:
	for index in fixtures.size():
		var id := StringName(String((fixtures[index] as Dictionary).get("fixture_id", "")))
		if id == fixture_id:
			return index
	return -1
