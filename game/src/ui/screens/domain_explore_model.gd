class_name DomainExploreModel
extends DomainExploreState

## The domain explore screen's STATE and every READ it makes of the domain module.
##
## [DomainExploreScreen] answers two questions a player can see: where am I standing, and
## what does this place hold. Both are the MODULE's to answer — through [DomainBridge],
## never through a private copy — and both are "what is true right now", which is a
## different reason to change from the screen's own: the screen owns the node tree, the
## six verbs, the refusals it publishes and `summary()`; a new figure the module
## publishes, a new field a room row carries or a new fixture kind touches this file and
## not that one. Same split `world_pulse_reader.gd` makes beside the world map, and
## `item_action_rules.gd` makes inside `ui/`.
##
## ## What this file holds, and what [DomainExploreState] holds
##
## The read helpers and the selection bookkeeping live in the base class. Inheritance
## keeps every public door below at the same name on the same object, so this split moves
## code without moving a single call site: `DomainExploreScreen` cannot tell which half a
## method came from, and no test can either.
##
## ## What it deliberately does not hold
##
## The actor is PUSHED on every refresh rather than bound once, for the reason
## [method WorldPulseReader.view] takes one per call: the app mounts a screen before it
## hands that screen an actor, and the headless tests drive both orders. A bridge nobody
## filled is "nothing to show", never a crash.
##
## ## The gates stay on the screen
##
## The six `_can_*` gates and the reasons they name are NOT here. A gate states its own
## refusal in the PLAYER's terms — `no_map`, `authors_no_status_id`, `missing_key` — and
## reads [constant DomainExploreScreen.FIXTURE_VERB], which is the ACTION ROW's table. That
## is a decision about what the screen offers, not a read of the world, so the two stay
## together on [DomainExploreScreen] and this file answers only what is true.

## The fields a room row publishes, and the fields a zone row does, live on the
## base (`DomainExploreState`, beside `_subset` which reads them) and are
## inherited here -- declared once, on the side that can resolve them.
var _templates: Array = []
var _template_index: int = -1


## Adopt the gameplay side. Safe to call again, and safe before any actor is bound: the
## screen re-reads and repaints after it, which is the point rather than a convenience —
## a surface bound after its first paint would otherwise show the state it had BEFORE the
## binding.
func bind(bridge: DomainBridge) -> void:
	_bridge = bridge
	_templates = _read_templates()


## Re-read the world and keep the selection honest. The screen calls this once per
## repaint and BEFORE it fills any selector, so the rows a selector offers and the state
## the gates read are the same read rather than two that can disagree.
func refresh(actor: Actor) -> void:
	_actor = actor
	_view = _read_active()
	_templates = _read_templates()
	_reconcile_selection()


## Everything this screen DISPLAYS about the domain, as primitives only. This is the
## screen's half of `summary()` that is the MODULE's answer rather than the widget's, so
## a test reads one dictionary instead of a screen field and a label.
##
## The shapes are the module's own, verbatim: DISPLAYED, never re-derived, because a
## screen that kept a private copy of the map shape is a second thing that can be wrong
## and it would be wrong silently. The minimap payload goes in WHOLE, so this screen and
## the headless driver read one dictionary (ADR 0073's tier legibility and its fog both
## live inside it).
func summary() -> Dictionary:
	var minimap := _minimap()
	var map: Dictionary = _view.get("map", {})
	return {
		"template_count": _templates.size(),
		"template_id": template_id(),
		"in_domain": not _view.is_empty(),
		"map": map,
		"room_count": int(_view.get("rooms", 0)),
		"zone_count": int(_view.get("zones", 0)),
		"population_count": int(_view.get("population", 0)),
		"discovered_count": int(_view.get("discovered", 0)),
		"fixture_count": int((_view.get("fixtures", {}) as Dictionary).get("count", 0)),
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
	}


## Every sentence this screen shows, keyed by the label it lands in. Composed in one
## place so the header line, the status line and the four readout lines can never quote a
## figure the module did not publish, and so the screen holds no formatting of its own.
func lines() -> Dictionary:
	return {
		"header": _header_text(),
		"status": _status_text(),
		"map": _map_text(),
		"rooms": _rooms_text(),
		"population": _population_text(),
		"zones": _zones_text(),
		"fixture": _fixture_text(),
	}


## The selected authored template's id, or `""` when none is selected. Matched on the
## stable id rather than the label, because a label is presentation and a domain may be
## renamed without its id moving.
func template_id() -> String:
	if _template_index < 0 or _template_index >= _templates.size():
		return ""
	return String((_templates[_template_index] as Dictionary).get("template_id", ""))


## The authored catalogue as the four selectors' rows, presentation included. The DISPLAY
## name is paired with the id because a row a player reads and a row a driver aims at are
## the same row, and a label alone cannot be matched reliably by either.
##
## Presentation lives here rather than in the screen because the id and the label are ONE
## choice about a row: a screen that wrote the pair itself would be able to drift from
## the catalogue this file reads.
func template_options() -> Array:
	var out: Array = []
	for entry in _templates:
		var row := entry as Dictionary
		var template_id := String(row.get("template_id", ""))
		out.append("%s (%s)" % [String(row.get("display_name", template_id)), template_id])
	return out


## One row per room the run AUTHORED, fog notwithstanding, so every room is reachable and
## not only the ones the floor plan has already drawn. The TIER is the minimap's own
## verdict where the minimap has drawn the room, and the row says `unmapped` when it has
## not — ADR 0073 forbids re-deriving a promise from a room's depth or size, so an
## undrawn room shows its kind and its discovery state rather than a guessed tier.
func room_options() -> Array:
	var tiers := _drawn_tiers()
	var out: Array = []
	for row in _authored_rooms():
		var room := row as Dictionary
		var room_id := String(room.get("room_id", ""))
		var tier := String(tiers.get(room_id, ""))
		out.append(
			(
				"%s  %s  [%s]"
				% [
					room_id,
					String(room.get("kind", "")),
					tier if not tier.is_empty() else "unmapped"
				]
			)
		)
	return out


## The fixtures the SELECTED room holds, and the nodes the SELECTED fixture can be struck
## at. A room is the only place a fixture exists — `DomainFixtures._resolve` refuses by
## name outside one — so the list empties rather than offering buttons aimed at another
## room. Empty nodes are honest: a trap and a treasure have none to strike.
func fixture_options() -> Array:
	var out: Array = []
	for fixture in _fixtures_of(_selected_room):
		var row := fixture as Dictionary
		out.append("%s (%s)" % [String(row.get("fixture_id", "")), String(row.get("kind", ""))])
	return out


## The selected fixture's strikeable nodes, or `[]` for a trap or a treasure.
func node_options() -> Array[StringName]:
	return _puzzle_nodes()


## Which of the four selectors the selection currently sits in — `[template, room,
## fixture, node]` — or -1 in each slot it is in none of. Read in ONE call so a repaint
## cannot repoint one dropdown against a different read than another.
func selection_indices() -> Array:
	return [
		_template_index,
		_index_of_room(_authored_rooms(), _selected_room),
		_index_of_fixture(_fixtures_of(_selected_room), _selected_fixture),
		_puzzle_nodes().find(_puzzle_node),
	]


## The kind of the selected fixture, or `""`. One key out of the selected fixture's
## AUTHORED row, which is what the screen's `_can_fixture` gate compares against the verb
## a kind answers to. Read for its STRING only: an authored fixture carries `Vector2i` /
## `Rect2i` positions, and an engine type in a summary is what makes a testable surface
## untestable.
func fixture_kind() -> String:
	return String(_selected_fixture_row().get("kind", ""))


## Move the selection the way a selector widget does. One entry point for all four rather
## than four, because they are four copies of the same rule — take the index the widget
## gave, refuse one that is out of range, then reconcile what the new selection implies —
## and a fourth copy is a place for them to stop agreeing.
##
## The `template` arm is the exception that proves the rule: it takes whatever index it
## is given, because a template list has no second list to range-check against and a
## repaint already pointed the widget there.
func choose(selector: StringName, index: int) -> void:
	match selector:
		&"template":
			_template_index = index
		&"room":
			var rows := _authored_rooms()
			if index < 0 or index >= rows.size():
				return
			# A real click clears any refused selection: the player has moved on, so the
			# pending refusal must not refuse the room they just chose.
			_pending_room = &""
			_selected_room = StringName(String((rows[index] as Dictionary).get("room_id", "")))
			_reconcile_fixture()
			_reconcile_node()
		&"fixture":
			var fixtures := _fixtures_of(_selected_room)
			if index < 0 or index >= fixtures.size():
				return
			_selected_fixture = StringName(
				String((fixtures[index] as Dictionary).get("fixture_id", ""))
			)
			_reconcile_node()
		&"node":
			var nodes := _puzzle_nodes()
			if index < 0 or index >= nodes.size():
				return
			_puzzle_node = nodes[index]


## Look at one room, the way picking it from the room selector does. False when the run
## does not hold it, and the refusal is RECORDED rather than discarded: the caller is told
## false, and the next `Visit` reports `unknown_room` by name instead of walking into
## whatever room was selected before. The pending id is dropped the moment anything else
## moves the selection, so it can never outlive the press that set it.
##
## Gated on the AUTHORED room list, not on the minimap's drawn rooms. Those are not the
## same set and the difference is the whole point of the screen: the fog is what the
## module has DISCOVERED, so gating on it made an undiscovered room unselectable — a
## player could never walk toward one, and the domain could only ever be one room deep.
func select_room(room_id: StringName) -> bool:
	if not _contains_room(_authored_rooms(), room_id):
		_pending_room = room_id
		return false
	_pending_room = &""
	_selected_room = room_id
	_reconcile_fixture()
	_reconcile_node()
	return true


## Look at one fixture of the selected room. Same reasoning as [method select_room].
func select_fixture(fixture_id: StringName) -> bool:
	if not _contains_fixture(_fixtures_of(_selected_room), fixture_id):
		return false
	_selected_fixture = fixture_id
	_reconcile_node()
	return true


## Choose the puzzle node to strike, for a formation the player is solving. False when the
## selected fixture authors no such node, so a caller learns the node is not a real choice.
func select_node(node_id: StringName) -> bool:
	if not _puzzle_nodes().has(node_id):
		return false
	_puzzle_node = node_id
	return true


## Repoint the template selector at the template it was on before the refill, by id. The
## id and not the index, because a catalogue that grew above the current row moved every
## index after it — and a selector silently repointed at a different domain is the kind of
## surprise that looks like a content bug.
func keep_template(template_id: String) -> void:
	for index in _templates.size():
		if String((_templates[index] as Dictionary).get("template_id", "")) == template_id:
			_template_index = index
			return
	if _template_index < 0:
		_template_index = 0


## The floor plan as the DRAWING panel takes it. Same read as
## [method DomainExploreState._minimap] and deliberately its own door rather than a
## widened [method summary]: the view is handed the payload WHOLE and reads the geometry
## itself, so nothing about the map's shape passes through a second summariser on the way
## to the screen.
func minimap() -> Dictionary:
	return _minimap()


## Every room the run AUTHORED, fog notwithstanding. The same list
## [method DomainExploreState._rooms] returns and the same list
## [method DomainExploreState._authored_rooms] already wraps, published for the map view
## because the payload's `rooms[]` is the DISCOVERED subset — the frontier seam is
## computed against the rooms fog hid, and asking a fogged list for them makes the seam
## permanently empty (ADR 0207).
func authored_rooms() -> Array:
	return _rooms()


# ── Wording. Every figure and every sentence lives here or in a child panel ────


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
