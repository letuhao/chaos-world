class_name WorldMapScreen
extends UiScreen

## World map screen. Renders a spatial node graph of world locations grouped
## by tier, with faction-colored nodes, danger indicators, and click-to-teleport.
## A pure consumer of the `world` facade: it reads state and emits signals.
##
## It also shows the world's CLOCK, which is reachable from no other layer: `app` is a
## private unit and `event` is not in `rules.UI_MODULES`, so this screen can neither
## reference the pulse nor call `EventApi.advance`. It holds a [WorldPulseBridge] of
## plain callables the root fills instead — the way the `loot` screen receives its
## module. The world's MEMORY is on the actor and `WorldFact` is `core/`, which `ui/` may
## reference, so the news is readable with nothing wired; the period count and cadence
## are the pulse's own constants in `app/`, and a second copy here is the private-copy
## failure `tests/core/test_realm_rate.gd` exists to catch. `WorldPulseReader` does the
## reading; this screen binds it, forwards the raw view, nests the panel's summary.
##
## ## The two clock verbs, and why they are shaped differently
##
## [method act_wait_season] pays one period and takes nothing, because a button and a
## headless driver should both be able to say "one period" without knowing the cadence.
## [method act_retreat_periods] is ADR 0167's season-scale class: the player CHOOSES how
## long to sit, so the argument IS the cost. The choice itself lives in the panel's
## selector and the periods come from the panel's summary, so there is exactly one
## answer to "how long is this" on the screen and it is the one a player is looking at.
##
## ## And a READ slot, which is not a verb
##
## The bridge also carries the world's OPEN EVENTS as rows (BL-0906). The screen reads them
## on every repaint and forwards them raw under `events_wired` / `open_events`; it formats
## nothing and decides nothing. It holds the bridge reference itself rather than reaching
## through the reader, because the reader answers counts — and a count cannot say which
## event is open, what stage it has reached, how long it has held, or what it pays.
##
## Contract: `summary()` is the testable surface with node and edge data.
signal location_selected(location_id: StringName)

const FACTION_VARIATIONS := {
	&"qi_dao": &"FactionQi",
	&"body_dao": &"FactionBody",
	&"mind_dao": &"FactionMind",
}

const TIER_ORDER: Array[StringName] = [
	&"mortal_world",
	&"spirit_world",
	&"immortal_world",
	&"transcendent_world",
]

const TIER_LABELS := {
	&"mortal_world": "LOC_UI_SCREENS_CBD16751AF",
	&"spirit_world": "LOC_UI_SCREENS_7EC5AE4A94",
	&"immortal_world": "LOC_UI_SCREENS_3150F92782",
	&"transcendent_world": "LOC_UI_SCREENS_B0FA565FE9",
}

const NODE_WIDTH := 160.0
const NODE_HEIGHT := 40.0
const DANGER_BAR_HEIGHT := 6.0
const DANGER_BAR_WIDTH := 160.0
const MIN_MAP_SIZE := Vector2(640, 400)

var _map_area: Control = null
var _map_graph: Control = null
var _info_name: Label = null
var _info_tier: Label = null
var _info_faction: Label = null
var _info_danger: Label = null
var _info_resources: Label = null
var _info_inhabitants: Label = null
var _message_line: Label = null
var _node_buttons: Dictionary = {}
var _node_positions: Dictionary = {}
var _edges: Array[Dictionary] = []
var _current_location: StringName = &""
var _locations: Array[Dictionary] = []
var _selected_location: StringName = &""
## Resolves the world's clock through the root's callables. Its own file because
## drawing a graph and reading a clock are two reasons to change this screen.
var _world: WorldPulseReader = WorldPulseReader.new()
## The bridge itself, kept beside the reader that calls it. The reader answers COUNTS; the
## event ROWS are a roster rather than a report, so they are read through the bridge's own
## `open_event_rows()` and handed to the panel as a separate pair of keys. Held here rather
## than added to the reader because this seam is the ONE legal edge from `ui/` to `app/`
## (ADR 0143), and a screen holding a reference to the edge it was given is not a second
## path — it is the same path, named.
var _world_bridge: WorldPulseBridge = null
var _world_panel: WorldPulsePanel = null
## The panel's last line, so `summary()` reports what the player read about their last
## action on the clock. The map's own `MessageLine` is a different subject.
var _world_message: String = ""
var _world_tone: StringName = &""


## Inject the world's clock. Repaints rather than only storing the bridge: a surface
## bound after its first paint would otherwise show the state it had before the binding.
func bind_world(bridge: WorldPulseBridge) -> void:
	_bind_nodes()
	_world_bridge = bridge
	_world.bind(bridge)
	refresh()


## Advance the world by exactly one period. The verb behind the panel's button, and
## reachable by `tools ui drive --cmd act_wait_season` with no arguments on purpose:
## neither a button nor a driver should have to know the cadence to ask for a period.
func act_wait_season() -> bool:
	_bind_nodes()
	if _actor == null:
		return _refuse_world("no_actor")
	var result := _world.request_advance()
	if not bool(result.get("ok", false)):
		return _refuse_world(String(result.get("reason", "")))
	_world_message = "" if _world_panel == null else _world_panel.reason_text("")
	_world_tone = TONE_OK
	refresh()
	return true


## Sit for the length the panel's selector is showing. The season-scale half of ADR
## 0167, and the only verb in this program whose ARGUMENT is the price: the chosen
## duration is the cost, so it reaches the clock as a period count and the clock is the
## only thing allowed to say whether it can be paid.
##
## **Drivable with `call:` and no argument, so a probe's answer does not depend on a
## click.** `tools ui drive --cmd call:act_retreat_periods` takes whatever the selector
## currently holds, which is what a headless probe wants to measure; a caller who wants a
## specific length passes it (`call:act_retreat_periods=360`) and the panel follows. Also
## reachable under `--cmd retreat`, which pays the selected length.
func act_retreat_periods(periods: int = 0) -> bool:
	_bind_nodes()
	if _actor == null:
		return _refuse_world("no_actor")
	var asked := int(periods) if int(periods) > 0 else _selected_retreat_periods()
	if asked <= 0:
		return _refuse_world("no_retreat")
	var result := _world.request_retreat(asked)
	if not bool(result.get("ok", false)):
		return _refuse_world(String(result.get("reason", "")))
	# A retreat the world interrupted paid in part, and a player who was cut short has to
	# be able to tell that from a cost they paid in full — so the wording names what was
	# PAID beside what was asked, never the ask alone.
	_world_message = _retreat_text(result)
	_world_tone = TONE_OK
	refresh()
	return true


## The selector's current period count, or `0` when the panel publishes none. Asked of the
## PANEL's own summary rather than of the widget, so the driver's answer and the player's
## are one number rather than two reads of a dropdown.
func _selected_retreat_periods() -> int:
	if _world_panel == null:
		return 0
	return int((_world_panel.summary() as Dictionary).get("retreat_declared_periods", 0))


## ## What the retreat actually cost, on the clock's own message line
##
## `declared`, `paid` and `unpaid` are the clock's own primitives, so this words them
## rather than computing them: a fully-paid sit and an interrupted one are different
## sentences because they are different costs (ADR 0167 — gain is proportional to the
## periods PAID, not the periods declared).
func _retreat_text(result: Dictionary) -> String:
	var unpaid := int(result.get("unpaid", 0))
	var paid := int(result.get("paid", 0))
	if unpaid <= 0:
		return L.t("LOC_UI_SCREENS_5895039F8F") % paid
	return (
		"You sat %d of the %d periods you chose - %d were not paid for."
		% [paid, int(result.get("declared", 0)), unpaid]
	)


## Everything this screen displays. Primitives only; `{}` with no actor.
func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	return {
		"current_location": _current_location,
		"selected_location": _selected_location,
		"nodes": _nodes_summary(),
		"edges": _edges_summary(),
		# The panel's own summary, nested under its key: it already reports the outcome
		# of the last clock action as `message_text`/`tone`, so mirroring those two here
		# would be a second copy of one fact.
		"world": _world_panel.summary() if _world_panel != null else {},
	}


func _refresh_view() -> void:
	_bind_nodes()
	if _actor == null:
		return
	_locations = WorldApi.locations(_actor)
	_current_location = (
		_locations[0].get("location_id", &"") if not _locations.is_empty() else &""
	)
	_rebuild_graph()
	_update_info_panel()
	if _world_panel != null:
		var view := _world.view(_actor)
		view["message"] = _world_message
		view["tone"] = String(_world_tone)
		# ## The open-event rows, forwarded RAW (BL-0906)
		#
		# Two keys and no formatting: `events_wired` says the root published the seam at
		# all, `open_events` carries one row per open event. This screen does not build
		# either — the panel owns every `%d` and every sentence (AGENTS.md / ADR 0038), and a
		# screen that formatted an event would put a `%d` in `ui/` a second place to get
		# wrong. The count the reader already forwarded (`active_events`) is left beside
		# them: the pulse tally still reads "live now 1", and now the row under it says
		# which one.
		view["events_wired"] = _world_bridge != null and _world_bridge.has_events()
		view["open_events"] = _world_bridge.open_event_rows() if _world_bridge != null else []
		# The panel's selector is the player's CHOSEN sit length, and this screen feeds
		# it a freshly published list on every repaint. Without the key the panel has no
		# way to tell "the player picked this" from "this row is still there", and
		# `_resolve_selection` then falls back to the shortest — so a player who chose a
		# year was shown a season after any refresh, and the cost line they read was no
		# longer the price the button would pay. Published here, beside the payload the
		# screen already forwards, rather than set imperatively on the widget afterwards.
		view["retreat_index"] = _retreat_index_of()
		_world_panel.show_world(view)


## The player's chosen sit length, as an index into the panel's published rows. `-1`
## until one has been chosen, so the panel applies its own default on the first repaint
## rather than this screen inventing a row the clock never offered.
func _retreat_index_of() -> int:
	if _world_panel == null:
		return -1
	return int((_world_panel.summary() as Dictionary).get("retreat_index", -1))


func _render() -> void:
	pass


# --- The world's clock ------------------------------------------------------


## A refusal, reported through the panel's own vocabulary and repainted from the
## untouched actor, so nothing on the clock can drift from the world.
func _refuse_world(reason: String) -> bool:
	_world_message = "" if _world_panel == null else _world_panel.reason_text(reason)
	_world_tone = TONE_ERROR
	refresh()
	return false


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _map_area != null:
		return
	_world_panel = get_node_or_null("%WorldPulsePanel") as WorldPulsePanel
	if _world_panel != null and not _world_panel.advance_requested.is_connected(act_wait_season):
		_world_panel.advance_requested.connect(act_wait_season)
	# Bound beside the wait, behind the same null guard, so a panel nobody wired still
	# reads as unwired rather than raising while connecting a signal.
	if (
		_world_panel != null
		and not _world_panel.retreat_requested.is_connected(act_retreat_periods)
	):
		_world_panel.retreat_requested.connect(act_retreat_periods)
	_map_area = get_node_or_null("Layout/MapArea") as Control
	_map_graph = get_node_or_null("Layout/MapArea/MapGraph") as Control
	_info_name = get_node_or_null("Layout/InfoPanel/InfoVBox/InfoName") as Label
	_info_tier = get_node_or_null("Layout/InfoPanel/InfoVBox/InfoTier") as Label
	_info_faction = get_node_or_null("Layout/InfoPanel/InfoVBox/InfoFaction") as Label
	_info_danger = get_node_or_null("Layout/InfoPanel/InfoVBox/InfoDanger") as Label
	_info_resources = get_node_or_null("Layout/InfoPanel/InfoVBox/InfoResources") as Label
	_info_inhabitants = get_node_or_null("Layout/InfoPanel/InfoVBox/InfoInhabitants") as Label
	_message_line = get_node_or_null("Layout/MessageLine") as Label
	if _map_area != null and not _map_area.resized.is_connected(_on_map_resized):
		_map_area.resized.connect(_on_map_resized)


func _on_map_resized() -> void:
	_rebuild_graph()


# --- Graph building ---------------------------------------------------------


func _rebuild_graph() -> void:
	if _map_area == null:
		return
	_clear_graph()
	var map_size := _map_area.size
	if map_size.x < 1.0 or map_size.y < 1.0:
		map_size = MIN_MAP_SIZE
	var tier_locations := _group_by_tier()
	_build_tier_backdrops(tier_locations, map_size)
	_build_nodes(tier_locations, map_size)
	_build_edges()
	_update_map_graph()


func _clear_graph() -> void:
	if _map_area == null:
		return
	# Freed immediately, not queued. `queue_free()` defers to the end of the frame
	# and the headless test runner never processes a frame, so every deferred node
	# stayed parented to `_map_area` while the next `_rebuild_graph()` added a fresh
	# set on top — an unbounded per-refresh accumulation, and the only surviving
	# `queue_free()` in `src/ui/`. Same rationale as `ScreenStack.pop()`.
	for child in _map_area.get_children():
		if child != _map_graph:
			_map_area.remove_child(child)
			child.free()
	_node_buttons.clear()
	_node_positions.clear()
	_edges.clear()


func _group_by_tier() -> Dictionary:
	var out := {}
	for tier in TIER_ORDER:
		out[tier] = []
	for loc in _locations:
		var tier := StringName(loc.get("tier", &""))
		if not out.has(tier):
			out[tier] = []
		out[tier].append(loc)
	return out


func _build_tier_backdrops(tier_locations: Dictionary, map_size: Vector2) -> void:
	var band_height := map_size.y / TIER_ORDER.size()
	for i in range(TIER_ORDER.size()):
		var tier: StringName = TIER_ORDER[i]
		var locs: Array = tier_locations.get(tier, [])
		if locs.is_empty():
			continue
		var y := i * band_height
		var panel := PanelContainer.new()
		panel.name = "Tier%s" % String(tier).capitalize()
		panel.position = Vector2(0, y)
		panel.size = Vector2(map_size.x, band_height)
		panel.theme_type_variation = &"TierPanel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_map_area.add_child(panel)
		var label := Label.new()
		label.name = "TierLabel"
		label.text = L.t(TIER_LABELS.get(tier, String(tier)))
		label.theme_type_variation = &"SectionTitle"
		label.position = Vector2(12, y + 8)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_map_area.add_child(label)


func _build_nodes(tier_locations: Dictionary, map_size: Vector2) -> void:
	var band_height := map_size.y / TIER_ORDER.size()
	for i in range(TIER_ORDER.size()):
		var tier: StringName = TIER_ORDER[i]
		var locs: Array = tier_locations.get(tier, [])
		if locs.is_empty():
			continue
		var y := i * band_height
		var count := locs.size()
		var spacing := map_size.x / (count + 1)
		for j in range(count):
			var loc: Dictionary = locs[j]
			var x := spacing * (j + 1) - NODE_WIDTH / 2.0
			var node_y := y + (band_height - NODE_HEIGHT - DANGER_BAR_HEIGHT) / 2.0
			_add_node(loc, Vector2(x, node_y))


func _add_node(loc: Dictionary, pos: Vector2) -> void:
	var location_id := StringName(loc.get("location_id", &""))
	if location_id == &"":
		return
	var display_name: String = loc.get("display_name", "")
	var faction_id := StringName(loc.get("faction_id", &""))
	var danger_level: int = loc.get("danger_level", 1)
	var is_current: bool = location_id == _current_location
	var button := Button.new()
	button.name = display_name
	button.text = L.t(display_name)
	# The location's authored faction, named on hover. The row carries the LOC key
	# (`faction_name`, resolved here like every other display field) because the
	# authored faction catalog had no production reader before this tooltip
	# (BL-0227): the id alone coloured the node and named nothing.
	var faction_name := String(loc.get("faction_name", ""))
	if faction_name != "":
		button.tooltip_text = L.t(faction_name)
	button.position = pos
	button.size = Vector2(NODE_WIDTH, NODE_HEIGHT)
	button.focus_mode = Control.FOCUS_ALL
	if is_current:
		button.theme_type_variation = &"MapNodeCurrent"
	else:
		var faction_var: StringName = FACTION_VARIATIONS.get(faction_id, &"")
		if faction_var != &"":
			button.theme_type_variation = faction_var
	button.pressed.connect(_on_node_pressed.bind(location_id))
	button.mouse_entered.connect(_on_node_hovered.bind(location_id))
	_map_area.add_child(button)
	_node_buttons[location_id] = button
	_node_positions[location_id] = pos + Vector2(NODE_WIDTH / 2.0, NODE_HEIGHT / 2.0)
	var danger_bar := PanelContainer.new()
	danger_bar.name = "DangerBar"
	danger_bar.position = Vector2(pos.x, pos.y + NODE_HEIGHT + 2.0)
	danger_bar.size = Vector2(DANGER_BAR_WIDTH, DANGER_BAR_HEIGHT)
	if danger_level <= 3:
		danger_bar.theme_type_variation = &"DangerLow"
	elif danger_level <= 6:
		danger_bar.theme_type_variation = &"DangerMedium"
	else:
		danger_bar.theme_type_variation = &"DangerHigh"
	danger_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_area.add_child(danger_bar)


func _build_edges() -> void:
	var sorted := _sorted_locations()
	_edges.clear()
	for i in range(sorted.size() - 1):
		var from_id := StringName(sorted[i].get("location_id", &""))
		var to_id := StringName(sorted[i + 1].get("location_id", &""))
		var to_tier := StringName(sorted[i + 1].get("tier", &"mortal_world"))
		_edges.append({"from": from_id, "to": to_id, "tier": to_tier})


func _sorted_locations() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tier in TIER_ORDER:
		for loc in _locations:
			if StringName(loc.get("tier", &"")) == tier:
				out.append(loc)
	return out


func _update_map_graph() -> void:
	if _map_graph != null and _map_graph.has_method("set_graph"):
		_map_graph.set_graph(_edges, _node_positions)


# --- Info panel -------------------------------------------------------------


func _update_info_panel() -> void:
	if _info_name == null:
		return
	var loc := _find_location(_selected_location)
	if loc.is_empty():
		_info_name.text = L.t("LOC_UI_SCREENS_A48800A1EC")
		_info_tier.text = ""
		_info_faction.text = ""
		_info_danger.text = ""
		_info_resources.text = ""
		_info_inhabitants.text = ""
		return
	_info_name.text = L.t(loc.get("display_name", ""))
	_info_tier.text = (
		"Tier: %s" % TIER_LABELS.get(StringName(loc.get("tier", &"")), loc.get("tier", ""))
	)
	_info_faction.text = L.t("LOC_UI_SCREENS_0A00771715") % loc.get("faction_id", "")
	_info_danger.text = L.t("LOC_UI_SCREENS_8EE9B7DC67") % loc.get("danger_level", 0)
	_info_resources.text = L.t("LOC_UI_SCREENS_42D765F17B") % _join_names(loc.get("resources", []))
	_info_inhabitants.text = (
		L.t("LOC_UI_SCREENS_3640D45383") % _join_names(loc.get("inhabitant_types", []))
	)


func _find_location(location_id: StringName) -> Dictionary:
	for loc in _locations:
		if StringName(loc.get("location_id", &"")) == location_id:
			return loc
	return {}


func _join_names(items: Array) -> String:
	if items.is_empty():
		return "none"
	var names: Array[String] = []
	for item in items:
		names.append(String(item))
	return ", ".join(names)


# --- Summary helpers --------------------------------------------------------


func _nodes_summary() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for loc in _locations:
		var location_id := StringName(loc.get("location_id", &""))
		var pos: Vector2 = _node_positions.get(location_id, Vector2.ZERO)
		(
			out
			. append(
				{
					"location_id": loc.get("location_id", ""),
					"display_name": loc.get("display_name", ""),
					"tier": loc.get("tier", ""),
					"faction_id": loc.get("faction_id", ""),
					"danger_level": loc.get("danger_level", 0),
					"is_current": location_id == _current_location,
					"position": {"x": pos.x, "y": pos.y},
				}
			)
		)
	return out


func _edges_summary() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge in _edges:
		(
			out
			. append(
				{
					"from": edge.get("from", ""),
					"to": edge.get("to", ""),
					"tier": edge.get("tier", ""),
				}
			)
		)
	return out


# --- Input ------------------------------------------------------------------


## A node was pressed: remember the choice, show it, and say where it went.
##
## **The repaint after the emit is load-bearing and was missing.** `location_selected`
## had no production consumer, so nothing below ever changed this screen and the
## omission was invisible; now that the composition root mounts the stage at the chosen
## place, the map would otherwise keep highlighting the node it HAPPENED to pick while
## the hero stood somewhere else — a map that lies about where the player is. The
## repaint is therefore unconditional rather than only on success: a refused journey
## must leave no highlight either, and the stage answers a refusal by naming it.
func _on_node_pressed(location_id: StringName) -> void:
	_selected_location = location_id
	_update_info_panel()
	location_selected.emit(location_id)
	refresh()


func _on_node_hovered(location_id: StringName) -> void:
	_selected_location = location_id
	_update_info_panel()
