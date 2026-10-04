class_name DomainExploreScreen
extends UiScreen

## The domain explore screen: where you are standing, what the domain promises, and the
## verbs you can take on the place you are standing in.
##
## ## The seam this screen is built around
##
## It is a pure consumer, like every screen in this program, but the `domain` module is
## not reachable the way `loot` or `world` are: `domain` is not in `rules.UI_MODULES`
## and `app/` is a private unit, so this screen names no domain type at all — not
## `DomainApi`, not `DomainMinimap`, not `DomainMap`. Everything arrives through
## [DomainBridge], the `Callable` seam `DomainBoot.bridge()` fills, which is the same
## shape ADR 0143 settled for loot and for the world clock. [method bind_bridge] is the
## only way the gameplay side arrives, and a screen that has not been bound reports `{}`
## rather than rendering a facade nobody installed.
##
## ## What it shows, and what it deliberately does not draw a second time
##
## The floor plan is [DomainMinimap]'s payload, handed over WHOLE: the same dictionary
## the headless driver renders, so the screen and the probe cannot disagree about where
## a room is or what it promises. Fog is `DomainApi.discovered` and is the module's to
## decide, not this screen's. The room list, the population and the severe zones are all
## read from that payload or from the facade's own reads, and the fixture verbs are the
## module's, routed through the bridge.
##
## No shape is re-derived. The map's room count, the tier a room promises, the severity of
## a zone and the population of a room all come out of the module's own read. The tier in
## particular is the MINIMAP's, because ADR 0073 forbids deriving a promise from a room's
## depth or size, and re-deriving it here would put exactly that forbidden heuristic back.
##
## ## Why it generates rather than only exploring
##
## A screen that could only look at a run somebody else started would be reachable and
## useless: nothing in the shipped program ever entered a domain. So `Enter` calls the
## one production entry point the module publishes, through the bridge, and that is what
## makes the chain template -> map -> contract -> active run startable from a button.
##
## ## The tone rules, stated once
##
## Every refusal repaints from the untouched actor and reports the reason the MODULE
## gave, never one this file invented. A trap that has already fired, a treasure whose
## key you do not carry, a room that is not in this map: each is named by the module's
## own reason id and worded by [member DomainBridge.REASON_TEXT]. Nothing is swallowed,
## and nothing silently truncates: a row that vanishes reads to a player as "the actor
## does not have this", which is a different and wrong statement.
##
## Contract: `summary()` is the testable surface, primitives only, and `{}` with no actor.

## The seed `Enter` generates from. A SEED and not a roll: two presses of one button
## should be the same domain, or "what is in there" is unreadable between two visits.
##
## It is `test_domain_content.gd`'s `CONTENT_SEED`, and that is the whole reason: the
## generator partitions a template's extent into leaves and REFUSES a map below the
## template's `min_rooms`, so a seed that is not known-good is not a slightly different
## domain but no domain at all. That suite asserts every authored template generates at
## this seed, so `Enter` cannot press a button the content cannot answer. (A previous
## seed produced two rooms against `ember_grotto`'s `min_rooms 6` and every downstream
## assertion about an active run failed for want of one.)
const DEFAULT_SEED := 20261003

## The six actions this screen offers, in the order a player meets them. Declared as data
## so the button row, the summary and the enabled map cannot disagree about the set.
const ACTION_IDS: Array[StringName] = [
	&"enter",
	&"visit",
	&"arm",
	&"attempt",
	&"claim",
	&"leave",
]

const ACTION_LABELS := {
	&"enter": "Enter domain",
	&"visit": "Visit room",
	&"arm": "Arm trap",
	&"attempt": "Strike node",
	&"claim": "Open treasure",
	&"leave": "Leave",
}

## The three fixture kinds, as the MODULE publishes them, paired with the verb that acts
## on each. A trap is armed, a puzzle is struck, a treasure is opened: a button that
## offered the wrong verb for a fixture would push the player into a refusal to learn
## something the authored content already said.
const FIXTURE_VERB := {
	"trap": &"arm",
	"puzzle": &"attempt",
	"treasure": &"claim",
}

## Seconds one `Arm` press advances a trap's telegraph by. Small and stated: the FIRST
## press always arms whatever this says, so the window is visible before the second press
## crosses it. Never a clock read — the module keeps no clock (ADR 0089), and a screen
## that invented one would be a second cadence for one status.
##
## Sized to CROSS the authored window in one step, not merely to nudge it. The authored
## traps telegraph for 0.9s to 1.6s (`src/data/domains/rooms/*.tres`), and
## `DomainFixtures.arm` fires only once `elapsed >= telegraph_s`; a tick below the
## shortest window meant a second press re-armed the same trap and no press count ever
## fired one, so the whole armed/spent ledger was unreachable from a button. Two presses
## is the interaction this screen offers, so two presses must arm and then fire.
const ARM_TICK := 2.0

## What a fixture verb that SUCCEEDED did. The module's own reason ids are the whole
## vocabulary — `telegraphing`, `fired`, `advanced`, `wrong_node`, `claimed` — and each
## names the state it left behind, so an acceptance that changed nothing is visibly
## different from one that paid out.
const OUTCOME_TEXT := {
	"telegraphing": "telegraphing — step on it again to be hit",
	"fired": "fired",
	"advanced": "advanced",
	"wrong_node": "wrong node — the sequence resets",
	"claimed": "claimed",
}

## The fields a room row publishes, and the fields a zone row does. Named as data so a
## row shape is declared once and [method _subset] can guarantee both are primitives
## without either writer repeating the coercion.
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
## The authored catalogue, as the bridge answered it. Not restated from content: a screen
## that invented a domain id would be a second source of truth about what is authored.
var _templates: Array = []
var _template_index: int = -1
## The room being looked at and the fixture being acted on within it. Both are IDS and
## never indices, so a run that regenerates cannot leave an action aimed at the wrong row.
var _selected_room: StringName = &""
var _selected_fixture: StringName = &""
var _puzzle_node: StringName = &""
## A room a caller NAMED that the module refused, held only until the next selection
## moves. Set by [method select_room]'s refusal and read by the `Visit` gate: without it
## a rejected selection silently fell back to the previous room and the verb walked
## somewhere the caller never asked for. `{}` is "nothing pending" and it is the state
## every other selection path leaves behind.
var _pending_room: StringName = &""
## The last outcome of a fixture verb, kept separately from `UiScreen`'s message because
## the fixture line names the FIXTURE and the message line names the screen's own verb.
var _fixture_message: String = ""
var _fixture_tone: StringName = &""
## The active run, as the module last reported it, so `summary()` answers with what the
## module said rather than re-asking three facades and hoping they agree.
var _view: Dictionary = {}

var _header_label: Label = null
var _status_label: Label = null
var _template_option: OptionButton = null
var _enter_button: Button = null
var _leave_button: Button = null
var _room_option: OptionButton = null
var _visit_button: Button = null
var _map_label: Label = null
var _rooms_label: Label = null
var _population_label: Label = null
var _zones_label: Label = null
var _fixture_option: OptionButton = null
var _node_option: OptionButton = null
var _arm_button: Button = null
var _attempt_button: Button = null
var _claim_button: Button = null
var _fixture_label: Label = null
var _message_label: Label = null
var _actions: ActionSet = null


func _ready() -> void:
	_bind_nodes()
	refresh()


func on_screen_shown() -> void:
	refresh()


func on_screen_hidden() -> void:
	pass


## Inject the gameplay side. Safe to call again; the screen re-reads and repaints, which
## is the point rather than a convenience — a surface bound after its first paint would
## otherwise show the state it had BEFORE the binding.
func bind_bridge(bridge: DomainBridge) -> void:
	_bind_nodes()
	_bridge = bridge
	_templates = _read_templates()
	refresh()


## The keyboard and pad land on the first live action, so a screen with nothing to do
## offers nothing to focus and one with something to do never lands on a dead control.
func focus_initial() -> void:
	_bind_nodes()
	if _actions != null and not _enabled().is_empty():
		_actions.focus_initial()
		return
	for control in [_enter_button, _visit_button, _arm_button]:
		var target := control as Control
		if target == null or target.disabled:
			continue
		_focus_target = String(target.name)
		if target.is_inside_tree():
			target.grab_focus()
		return


## Everything this screen shows, as primitives only. `{}` with no actor or no bridge, per
## the screen contract, so a test never reads a half-initialised screen.
func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null or _bridge == null:
		return {}
	var minimap := _minimap()
	var map: Dictionary = _view.get("map", {})
	return {
		"has_actor": _actor != null,
		"actor_id": String(_actor.id),
		# The bridge's own view of itself, so a test can assert the WIRING rather than
		# infer it from a verb that quietly did nothing.
		"bridge": _bridge.summary(),
		"template_count": _templates.size(),
		"template_id": _selected_template_id(),
		"in_domain": not _view.is_empty(),
		# The module's own shapes, verbatim. DISPLAYED, never re-derived: a screen that
		# kept a private copy of the map shape is a second thing that can be wrong, and
		# it would be wrong silently.
		"map": map,
		"room_count": int(_view.get("rooms", 0)),
		"zone_count": int(_view.get("zones", 0)),
		"population_count": int(_view.get("population", 0)),
		"discovered_count": int(_view.get("discovered", 0)),
		"fixture_count": int((_view.get("fixtures", {}) as Dictionary).get("count", 0)),
		# The minimap payload WHOLE, so this screen and the headless driver read one
		# dictionary (ADR 0073's tier legibility and its fog both live inside it).
		"minimap": minimap,
		"drawn_rooms": _drawn_rooms(minimap),
		"room_rows": _room_rows(minimap),
		"poi_count": (minimap.get("pois", []) as Array).size(),
		"route_count": (minimap.get("routes", []) as Array).size(),
		"zone_rows": _zone_rows(minimap),
		"weather": String(minimap.get("weather", map.get("weather", ""))),
		"population": _population_rows(),
		"selected_room": String(_selected_room),
		"selected_fixture": String(_selected_fixture),
		"selected_node": String(_puzzle_node),
		"fixture_message": _fixture_message,
		"fixture_tone": String(_fixture_tone),
		"header": _text_of(_header_label),
		"status": _text_of(_status_label),
		"map_text": _text_of(_map_label),
		"rooms_text": _text_of(_rooms_label),
		"population_text": _text_of(_population_label),
		"zones_text": _text_of(_zones_label),
		"fixture_text": _text_of(_fixture_label),
		"enabled": _enabled(),
		"actions": _actions.summary() if _actions != null else {},
	}


func _refresh_view() -> void:
	_bind_nodes()
	_view = _active()
	_templates = _read_templates()
	_reconcile_selection()
	_fill_templates()
	_fill_rooms()
	_fill_fixtures()


func _render() -> void:
	_bind_nodes()
	_header_label.text = _header_text()
	_status_label.text = _status_text()
	_map_label.text = _map_text()
	_rooms_label.text = _rooms_text()
	_population_label.text = _population_text()
	_zones_label.text = _zones_text()
	_fixture_label.text = _fixture_text()
	_enter_button.disabled = not _can_enter()
	_leave_button.disabled = not _can_leave()
	_visit_button.disabled = not _can_visit()
	_arm_button.disabled = not _can_arm()
	_attempt_button.disabled = not _can_attempt()
	_claim_button.disabled = not _can_claim()
	_publish_actions()
	_publish_message()
	_sync_selections()


## Resolve scene nodes, then connect every signal ONCE. Guarded like every other connect
## in this program (ADR/AGENTS.md): an unguarded connect is one handler per call, and a
## reused screen then fires N times for one press.
func _bind_nodes() -> void:
	if _header_label != null:
		return
	_header_label = get_node_or_null("%HeaderLabel") as Label
	_status_label = get_node_or_null("%StatusLabel") as Label
	_template_option = get_node_or_null("%TemplateOption") as OptionButton
	_enter_button = get_node_or_null("%EnterButton") as Button
	_leave_button = get_node_or_null("%LeaveButton") as Button
	_room_option = get_node_or_null("%RoomOption") as OptionButton
	_visit_button = get_node_or_null("%VisitButton") as Button
	_map_label = get_node_or_null("%MapLabel") as Label
	_rooms_label = get_node_or_null("%RoomsLabel") as Label
	_population_label = get_node_or_null("%PopulationLabel") as Label
	_zones_label = get_node_or_null("%ZonesLabel") as Label
	_fixture_option = get_node_or_null("%FixtureOption") as OptionButton
	_node_option = get_node_or_null("%NodeOption") as OptionButton
	_arm_button = get_node_or_null("%ArmButton") as Button
	_attempt_button = get_node_or_null("%AttemptButton") as Button
	_claim_button = get_node_or_null("%ClaimButton") as Button
	_fixture_label = get_node_or_null("%FixtureLabel") as Label
	_message_label = get_node_or_null("%MessageLabel") as Label
	_actions = get_node_or_null("%Actions") as ActionSet
	if _actions != null and not _actions.action_requested.is_connected(_on_action_requested):
		_actions.action_requested.connect(_on_action_requested)
	_connect_select(_template_option, _on_template_selected)
	_connect_select(_room_option, _on_room_selected)
	_connect_select(_fixture_option, _on_fixture_selected)
	_connect_select(_node_option, _on_node_selected)
	_connect_pressed(_enter_button, act_enter)
	_connect_pressed(_leave_button, act_leave)
	_connect_pressed(_visit_button, act_visit)
	_connect_pressed(_arm_button, act_arm)
	_connect_pressed(_attempt_button, act_attempt)
	_connect_pressed(_claim_button, act_claim)


# ── Actions. Each asks the bridge, then repaints from the untouched actor ─────────


## Generate and enter the selected authored template. The ONE production entry point
## into a domain, and calling it from a button is what makes the module reachable from
## the shipped program at all.
func act_enter() -> bool:
	_bind_nodes()
	if not _can_enter():
		return _reject(_enter_reason())
	var template_id := _selected_template_id()
	var entered := _bridge.call_action(&"enter", [_actor, StringName(template_id), DEFAULT_SEED])
	return _settle(entered, "Entered %s" % template_id)


## Leave the domain. The discovered set survives, so nothing the player found is lost.
func act_leave() -> bool:
	_bind_nodes()
	if not _can_leave():
		return _reject("no_map")
	return _settle(_bridge.call_action(&"leave", [_actor]), "Left the domain")


## Walk into the selected room, recording it as discovered so the floor plan draws it. A
## room the map does not hold is REFUSED BY NAME and changes nothing at all.
##
## The gate is the MODULE's room list, not the fogged minimap and not the previous
## selection: a caller that aims the screen at a room the run does not hold must be told
## `unknown_room` when it presses the verb, not have the verb quietly walk into whatever
## room happened to be selected before.
func act_visit() -> bool:
	_bind_nodes()
	if not _can_visit():
		return _reject(_visit_reason())
	var reached := _bridge.call_action(&"visit", [_actor, _selected_room, &""])
	return _settle(reached, "Reached %s" % String(_selected_room))


## Arm a trap's telegraph, or fire it when the authored window has already elapsed.
func act_arm(delta: float = ARM_TICK) -> bool:
	_bind_nodes()
	if not _can_arm():
		return _reject(_arm_reason())
	var armed := _bridge.call_action(
		&"arm_fixture", [_actor, _selected_room, _selected_fixture, delta]
	)
	return _settle_fixture(armed)


## Strike one node of a formation puzzle. A wrong node costs the ATTEMPT and never
## health, and the module names the node it expected — which is shown, not swallowed.
func act_attempt() -> bool:
	_bind_nodes()
	if not _can_attempt():
		return _reject(_attempt_reason())
	var struck := _bridge.call_action(
		&"attempt_fixture", [_actor, _selected_room, _selected_fixture, _puzzle_node]
	)
	return _settle_fixture(struck)


## Open a treasure. Refused by name at every gate, in the order a player meets them.
func act_claim() -> bool:
	_bind_nodes()
	if not _can_claim():
		return _reject(_claim_reason())
	return _settle_fixture(
		_bridge.call_action(&"claim_fixture", [_actor, _selected_room, _selected_fixture])
	)


## Drive any action by id, so `tools ui drive --cmd` and a headless probe reach the same
## code path a button press does.
##
## A TABLE rather than a chain of `match` arms, because this file already holds a hundred
## lines of prose and a dispatch is the least interesting thing in it. An id this screen
## does not offer is refused BY NAME rather than ignored, so a driver learns it asked
## wrongly instead of seeing a silent no-op.
const ACTION_HANDLERS := {
	&"enter": "act_enter",
	&"leave": "act_leave",
	&"visit": "act_visit",
	&"arm": "act_arm",
	&"attempt": "act_attempt",
	&"claim": "act_claim",
}


func act(action: StringName) -> bool:
	_bind_nodes()
	var handler := String(ACTION_HANDLERS.get(action, ""))
	if handler.is_empty():
		return _reject("unknown_action")
	return bool(call(handler))


## Look at one room, the way picking it from the room selector does. Public because a
## test and a driver both need to aim at a specific room, and reaching into `_selected_room`
## would make the selection a private field with a public back door.
##
## Gated on the AUTHORED room list, not on the minimap's drawn rooms. Those are not the
## same set and the difference is the whole point of the screen: the fog is what the
## module has DISCOVERED, so gating on it made an undiscovered room unselectable — a
## player could never walk toward one, and the domain could only ever be one room deep.
##
## A room the MODULE does not hold is still refused, and the refusal is RECORDED in
## [member _pending_room] rather than discarded. The caller is told false, so it knows,
## and the next `Visit` reports `unknown_room` by name instead of walking into whatever
## room was selected before — a verb aimed at a room nobody holds must refuse rather than
## silently succeed somewhere else. The pending id is dropped the moment anything else
## moves the selection, so it can never outlive the press that set it.
func select_room(room_id: StringName) -> bool:
	_bind_nodes()
	if not _contains_room(_authored_rooms(), room_id):
		_pending_room = room_id
		return false
	_pending_room = &""
	_selected_room = room_id
	_reconcile_fixture()
	_reconcile_node()
	refresh()
	return true


## Look at one fixture of the selected room. Same reasoning as [method select_room].
func select_fixture(fixture_id: StringName) -> bool:
	_bind_nodes()
	if not _contains_fixture(_fixtures_of(_selected_room), fixture_id):
		return false
	_selected_fixture = fixture_id
	_reconcile_node()
	refresh()
	return true


## Choose the puzzle node to strike, for a formation the player is solving. False when the
## selected fixture authors no such node, so a caller learns the node is not a real choice.
func select_node(node_id: StringName) -> bool:
	_bind_nodes()
	if not _puzzle_nodes().has(node_id):
		return false
	_puzzle_node = node_id
	refresh()
	return true


# ── Reads. Every one of them through the bridge, never a private copy ────────────


## What the MODULE reports is active, or `{}` outside a run. `{}` is the repo's
## does-not-exist vocabulary — not an error, and never a fabricated zeroed view.
func _active() -> Dictionary:
	if _actor == null or _bridge == null or not _bridge.has(&"read_active"):
		return {}
	return _bridge.call_action(&"read_active", [_actor]).get("active", {}) as Dictionary


func _read_templates() -> Array:
	if _bridge == null or not _bridge.has(&"list_templates"):
		return []
	return _bridge.call_list(&"list_templates")


## The room list, or `[]` outside a run AND before the seam is filled.
##
## ONE guarded call rather than a null check at each of its three readers. `_ready()`
## runs before `bind_bridge` has ever been called, so every refresh on a screen the
## shell has not wired yet reaches this: a reader that dereferenced `_bridge` directly
## aborted the whole refresh, and an unbound screen reported no rooms, no population
## and no fixtures instead of reporting an empty domain.
func _rooms() -> Array:
	if _bridge == null or not _bridge.has(&"rooms"):
		return []
	return _bridge.call_list(&"rooms", [_actor])


## The floor plan, exactly as the module rendered it. `{}` outside a run, which the
## text below words as "no floor plan" rather than as an empty map.
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
## A room is the only place a fixture exists — `DomainFixtures._resolve` refuses by name
## outside one — so the list empties rather than offering buttons aimed at another room.
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


# ── Selection ────────────────────────────────────────────────────────────────


## Keep the selection honest across a refresh. A run that regenerated, or a room left
## behind, must not leave a stale id selected — an action aimed at one would refuse for a
## reason the player never caused.
##
## Checked against the AUTHORED rooms for the same reason [method select_room] is: the
## selection is where the player is LOOKING, which is a different question from where the
## floor plan has drawn. Reconciling against the fogged set reset the selection to the
## entry room on every refresh, so a player could not hold a look at an unfound room.
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


func _selected_template_id() -> String:
	if _template_index < 0 or _template_index >= _templates.size():
		return ""
	return String((_templates[_template_index] as Dictionary).get("template_id", ""))


# ── Enabled state. Each verb states its OWN refusal rather than a bare "disabled" ──


func _can_enter() -> bool:
	return (
		_actor != null
		and _bridge != null
		and _bridge.has(&"enter")
		and _view.is_empty()
		and not _selected_template_id().is_empty()
	)


func _can_leave() -> bool:
	return _live() and _bridge.has(&"leave")


## `Visit` needs a run, the verb, and a room the MODULE actually holds.
##
## The pending-room check is what turns a refused [method select_room] into a refusal of
## the verb rather than a silent walk into the previous room: a pending id means the
## caller named a room this run does not have, so the verb must say so by name.
func _can_visit() -> bool:
	if _pending_room != &"":
		return false
	return _live() and _bridge.has(&"visit") and not _selected_room.is_empty()


func _can_arm() -> bool:
	return _can_fixture(&"arm_fixture")


func _can_attempt() -> bool:
	return _can_fixture(&"attempt_fixture") and not _puzzle_nodes().is_empty()


func _can_claim() -> bool:
	return _can_fixture(&"claim_fixture")


## Whether a run is active and the bridge can reach the verb at all.
func _live() -> bool:
	return _actor != null and _bridge != null and not _view.is_empty()


## A fixture verb is offered when the room holds a fixture OF THE KIND THIS VERB acts
## on, and the module can answer. Whether the module will ANSWER YES is its business: a
## treasure whose key you lack must stay pressable, or the refusal — the thing that
## teaches a player why the hoard is sealed — becomes unreachable.
func _can_fixture(action: StringName) -> bool:
	if not _live() or not _bridge.has(action) or _selected_fixture.is_empty():
		return false
	return FIXTURE_VERB.get(String(_selected_fixture_row().get("kind", "")), &"") == action


func _enter_reason() -> String:
	if _actor == null or _bridge == null:
		return "no_actor"
	if not _bridge.has(&"enter"):
		return "no_inventory_bridge"
	if _selected_template_id().is_empty():
		return "no_such_template"
	return "no_map"


func _visit_reason() -> String:
	if not _live():
		return "no_map"
	if not _bridge.has(&"visit"):
		return "no_inventory_bridge"
	return "unknown_room"


func _arm_reason() -> String:
	return _fixture_reason(&"arm_fixture", "authors_no_status_id")


func _attempt_reason() -> String:
	if _puzzle_nodes().is_empty():
		return "authors_nothing_to_grant"
	return _fixture_reason(&"attempt_fixture", "unknown_node")


func _claim_reason() -> String:
	return _fixture_reason(&"claim_fixture", "missing_key")


## Why a fixture verb is refused when it is refused by the SCREEN rather than by the
## module. The fallback names what the authored content says about that fixture, which
## is the gate a player is most likely to be standing at.
func _fixture_reason(action: StringName, authored_reason: String) -> String:
	if not _live():
		return "no_map"
	if not _bridge.has(action):
		return "no_inventory_bridge"
	return authored_reason


## What each action is right now, and what the ActionSet row itself thinks. Both halves
## are published so a test can compare them rather than trust either one.
##
## The panel's own flags are read through ONE explicitly typed local. `summary()` is a
## `Dictionary`, so `get()` answers a `Variant`, and a ternary over a Variant and a
## literal infers Variant for the whole expression — which this project treats as a parse
## error. Coerced here so the ternary below compares two dictionaries.
func _enabled() -> Dictionary:
	var flags: Dictionary = {}
	if _actions != null:
		flags = _actions.summary().get("enabled", {}) as Dictionary
	return {
		"enter": _can_enter(),
		"leave": _can_leave(),
		"visit": _can_visit(),
		"arm": _can_arm(),
		"attempt": _can_attempt(),
		"claim": _can_claim(),
		"panel_enter": bool(flags.get("enter", false)),
		"panel_visit": bool(flags.get("visit", false)),
		"panel_leave": bool(flags.get("leave", false)),
	}


# ── Wording. Every figure and every sentence lives here or in a child panel ──────


func _header_text() -> String:
	if _actor == null:
		return "Domains — no hero"
	if _templates.is_empty():
		return "Domains — none authored"
	return "Domains — %d authored" % _templates.size()


func _status_text() -> String:
	if _view.is_empty():
		return "Not inside a domain"
	var map: Dictionary = _view.get("map", {})
	return (
		"Inside %s — %d room(s), %d discovered"
		% [
			String(map.get("domain_id", "a domain")),
			int(_view.get("rooms", 0)),
			int(_view.get("discovered", 0)),
		]
	)


## The floor plan, as text. The DICTIONARY is the contract; this is its readable echo,
## and it counts what the plan actually draws rather than asserting a number the module
## never published.
func _map_text() -> String:
	var minimap := _minimap()
	if minimap.is_empty():
		return "No floor plan — no domain is active"
	var box: Variant = minimap.get("bounds", [])
	var width := int((box as Array)[2]) if (box as Array).size() == 4 else 0
	var height := int((box as Array)[3]) if (box as Array).size() == 4 else 0
	return (
		"Floor plan — %d room(s) drawn, %d marker(s), %d corridor(s), %dx%d tiles"
		% [
			_drawn_rooms(minimap).size(),
			(minimap.get("pois", []) as Array).size(),
			(minimap.get("routes", []) as Array).size(),
			width,
			height,
		]
	)


## One line per DISCOVERED room, with its kind and the tier it promises. Only discovered
## rooms appear: the minimap's fog is the module's, and a room shown before it is found
## is exactly the spoiler the fog exists to prevent.
func _rooms_text() -> String:
	var rows := _room_rows(_minimap())
	if rows.is_empty():
		return "No rooms known"
	var lines: Array = []
	for row in rows:
		var room := row as Dictionary
		(
			lines
			. append(
				(
					"%s  %s  [%s]%s"
					% [
						room["room_id"],
						room["kind"],
						room["tier"],
						"  entry" if bool(room["is_entry"]) else "",
					]
				)
			)
		)
	return "\n".join(lines)


func _population_text() -> String:
	var rows := _population_rows()
	if rows.is_empty():
		return "Nobody is placed here yet"
	var lines: Array = []
	for row in rows:
		lines.append("%s: %d" % [row["role"], row["count"]])
	return ", ".join(lines)


## The severe zones and the levers that reduce them. An empty list reads "none authored",
## never a silent blank line, because a blank line reads as "the author forgot".
func _zones_text() -> String:
	var rows := _zone_rows(_minimap())
	if rows.is_empty():
		return "No severe environment authored here"
	var lines: Array = []
	for row in rows:
		var zone := row as Dictionary
		var levers := zone["mitigation_tags"] as Array
		(
			lines
			. append(
				(
					"%s in %s (%s) — answered by: %s"
					% [
						zone["kind"],
						zone["room_id"],
						zone["severity"],
						", ".join(levers) if not levers.is_empty() else "nothing you carry",
					]
				)
			)
		)
	return "\n".join(lines)


func _fixture_text() -> String:
	var fixture := _selected_fixture_row()
	if fixture.is_empty():
		return "No fixture in this room"
	return (
		"%s (%s) in %s" % [fixture.get("fixture_id", ""), fixture.get("kind", ""), _selected_room]
	)


# ── Rendering ────────────────────────────────────────────────────────────────


## Fill the domain selector from the AUTHORED catalogue. Presentation only: the screen
## never invents a domain, and it matches on the stable id rather than the label because
## a label is presentation and a domain may be renamed without its id moving.
func _fill_templates() -> void:
	if _template_option == null:
		return
	var keep := _selected_template_id()
	_template_option.clear()
	for index in _templates.size():
		var entry := _templates[index] as Dictionary
		var template_id := String(entry.get("template_id", ""))
		_template_option.add_item(
			"%s (%s)" % [String(entry.get("display_name", template_id)), template_id]
		)
	for index in _templates.size():
		if String((_templates[index] as Dictionary).get("template_id", "")) == keep:
			_template_index = index
			break
	if _template_index < 0:
		_template_index = 0


## Fill the room selector from the AUTHORED room list, so every room in the run is
## reachable and not only the ones the floor plan has already drawn. The TIER is the
## minimap's own verdict where the minimap has drawn the room, and the row says so when
## it has not — ADR 0073 forbids re-deriving a promise from a room's depth or size, so
## an undrawn room shows its kind and its discovery state rather than a guessed tier.
func _fill_rooms() -> void:
	if _room_option == null:
		return
	var tiers := _drawn_tiers()
	_room_option.clear()
	for row in _authored_rooms():
		var room := row as Dictionary
		var room_id := String(room.get("room_id", ""))
		var tier := String(tiers.get(room_id, ""))
		_room_option.add_item(
			(
				"%s  %s  [%s]"
				% [
					room_id,
					String(room.get("kind", "")),
					tier if not tier.is_empty() else "unmapped"
				]
			)
		)


## `{room_id: tier}` for the rooms the minimap has drawn. `{}` outside a run and for a
## room the fog has not lifted, which is why the row above falls back rather than
## inventing a band of its own.
func _drawn_tiers() -> Dictionary:
	var out: Dictionary = {}
	for row in _drawn_rooms(_minimap()):
		var room := row as Dictionary
		out[String(room.get("room_id", ""))] = String(room.get("tier", ""))
	return out


func _fill_fixtures() -> void:
	if _fixture_option == null or _node_option == null:
		return
	_fixture_option.clear()
	for fixture in _fixtures_of(_selected_room):
		_fixture_option.add_item(
			"%s (%s)" % [String(fixture.get("fixture_id", "")), String(fixture.get("kind", ""))]
		)
	_node_option.clear()
	for node in _puzzle_nodes():
		_node_option.add_item(String(node))
	_node_option.disabled = _puzzle_nodes().is_empty()


## Push the action row's own state, and the outcome line beside it.
func _publish_actions() -> void:
	if _actions == null:
		return
	var enabled := _enabled()
	var flags := {}
	for action in ACTION_IDS:
		flags[String(action)] = bool(enabled.get(String(action), false))
	var state := {
		"actions": ACTION_IDS,
		"labels": ACTION_LABELS,
		"enabled": flags,
		"primary": &"enter" if flags["enter"] else &"visit",
	}
	_actions.set_state(state)


## The outcome line in both places a reader can see it. `WarnLabel` on a refusal and
## `OkLabel` on an acceptance are THEME VARIATIONS rather than per-node colours, so the
## palette stays in the one theme (the UI standard; BL-0084).
func _publish_message() -> void:
	if _actions != null:
		_actions.set_message(_message, _tone)
	if _message_label != null:
		_message_label.text = _message
		_message_label.theme_type_variation = _tone_variation()


func _tone_variation() -> StringName:
	match _tone:
		TONE_ERROR:
			return &"WarnLabel"
		TONE_OK:
			return &"OkLabel"
		_:
			return &"MetaLabel"


## Repaint the four selectors without re-emitting `item_selected`, so a programmatic
## `select()` cannot be mistaken for a click and re-enter the handler that set it.
func _sync_selections() -> void:
	_select(_template_option, _template_index)
	_select(_room_option, _index_of_room(_authored_rooms(), _selected_room))
	_select(_fixture_option, _index_of_fixture(_fixtures_of(_selected_room), _selected_fixture))
	_select(_node_option, _puzzle_nodes().find(_puzzle_node))


# ── Outcomes ─────────────────────────────────────────────────────────────────


## An outcome the MODULE named. Accepted repaints in the accepted tone; refused reports
## the reason it was given and repaints from the untouched actor, so nothing on screen
## can drift away from the world state.
func _settle(result: Dictionary, accepted: String) -> bool:
	if not bool(result.get("ok", false)):
		return _reject(String(result.get("reason", "rejected")))
	_fixture_message = accepted
	_fixture_tone = TONE_OK
	set_message(accepted, TONE_OK)
	refresh()
	return true


## As [method _settle], for a fixture verb: the line names the FIXTURE as well, because a
## room can hold three of them and "already claimed" reads as ambiguous while the player
## is looking at a formation.
##
## BOTH lines name the fixture and the reason id. A refusal is the thing that teaches a
## player why a verb cannot be taken, and "You are not carrying its key" on its own is
## ambiguous against two other fixtures in the same room — so the fixture line leads with
## which one it was about and carries the module's own reason id alongside the bridge's
## wording. The id is not decoration: it is the stable handle a driver and a test match
## on, and a worded sentence alone would leave both of them pattern-matching prose.
func _settle_fixture(result: Dictionary) -> bool:
	var reason := String(result.get("reason", ""))
	var accepted := bool(result.get("ok", false))
	var text: String = _outcome_text(reason) if accepted else _reason_text(reason)
	# Both lines carry the reason ID and the wording. The id is the stable handle a
	# driver and a test match on; the wording is what a player reads. A line with only
	# one of them fails half of every consumer.
	_fixture_message = _fixture_sentence("%s — %s" % [reason, text])
	_fixture_tone = TONE_OK if accepted else TONE_ERROR
	set_message(_fixture_message, _fixture_tone)
	refresh()
	return accepted


## A refusal. The reason is the MODULE'S and the sentence is the bridge's table — never
## a wording this file chose, because a screen that invents the reason is a second,
## quietly-wrong account of why a verb was refused.
##
## Named so the line still says WHICH fixture when there is one: `_reject` is reached
## from the fixture verbs as well as from `Enter`/`Leave`/`Visit`, and a room can hold
## three fixtures, so "Rejected: You are not carrying its key" is not an answer a player
## can act on. With no fixture selected the line is the bare reason, which is honest —
## there was no fixture to be about.
func _reject(reason: String) -> bool:
	_fixture_message = _fixture_sentence(_reason_text(reason))
	_fixture_tone = TONE_ERROR
	# Composed ONCE. Re-wrapping `_fixture_message` here would prefix the fixture id a
	# second time, so a repeated refusal read "ash_x: ash_x: ...".
	set_message(_fixture_sentence("Rejected: %s — %s" % [reason, _reason_text(reason)]), TONE_ERROR)
	refresh()
	return false


## `<fixture>: <text>`, or `<text>` alone when no fixture is aimed at. The one place a
## fixture outcome is worded, so the summary line and the message line can never name two
## different fixtures for one press.
func _fixture_sentence(text: String) -> String:
	if _selected_fixture.is_empty():
		return text
	return "%s: %s" % [String(_selected_fixture), text]


func _reason_text(reason: String) -> String:
	return _bridge.reason_text(reason) if _bridge != null else reason


func _outcome_text(reason: String) -> String:
	var text := String(OUTCOME_TEXT.get(reason, reason))
	return text if not text.is_empty() else "done"


# ── Plumbing ─────────────────────────────────────────────────────────────────


## A guarded connect. Every one of them, so a re-bound screen has one handler per press.
## The action row carries `act_*` DIRECTLY rather than routing through `act`, because an
## `ActionSet` button is one specific verb and the panel already knows which; a string
## table would add a lookup to the one path a player presses most.
func _connect_pressed(button: Button, handler: Callable) -> void:
	if button != null and not button.pressed.is_connected(handler):
		button.pressed.connect(handler)


## The four selectors are wired to ONE handler each, and each handler resolves its own
## selector against the list that handler's `_fill_*` writes — so the two cannot drift.
func _connect_select(option: OptionButton, handler: Callable) -> void:
	if option != null and not option.item_selected.is_connected(handler):
		option.item_selected.connect(handler)


func _select(option: OptionButton, index: int) -> void:
	if option != null and index >= 0 and index < option.item_count:
		option.select(index)


func _text_of(label: Label) -> String:
	return "" if label == null else label.text


func _strings(values: Variant) -> Array:
	var out: Array = []
	if not values is Array:
		return out
	for value in values as Array:
		out.append(String(value))
	return out


func _on_action_requested(action: StringName) -> void:
	act(action)


## The room selector. The widget's selection is the truth once it exists; the field only
## carries it across a refill, so a programmatic `select()` is honoured like a click and
## a real click is not second-guessed. All four selectors read that same rule, which is
## why they share one line of prose between them.
func _on_template_selected(index: int) -> void:
	_template_index = index
	refresh()


func _on_room_selected(index: int) -> void:
	var rows := _authored_rooms()
	if index < 0 or index >= rows.size():
		return
	# A real click clears any refused selection: the player has moved on, so the
	# pending refusal must not refuse the room they just chose.
	_pending_room = &""
	_selected_room = StringName(String((rows[index] as Dictionary).get("room_id", "")))
	_reconcile_fixture()
	_reconcile_node()
	refresh()


func _on_fixture_selected(index: int) -> void:
	var fixtures := _fixtures_of(_selected_room)
	if index < 0 or index >= fixtures.size():
		return
	_selected_fixture = StringName(String((fixtures[index] as Dictionary).get("fixture_id", "")))
	_reconcile_node()
	refresh()


func _on_node_selected(index: int) -> void:
	var nodes := _puzzle_nodes()
	if index < 0 or index >= nodes.size():
		return
	_puzzle_node = nodes[index]
	refresh()
