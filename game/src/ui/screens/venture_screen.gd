class_name VentureScreen
extends UiScreen

## The venture screen: open a generated place, walk it cell by cell, break
## ground, and read what the streaming state is — all through Callables the
## composition root installs. It names no gameplay type: the verbs arrive as
## four seams (`open`, `step`, `destroy`, `read`), and an unbound screen
## reports its nodes with `open: false` rather than rendering a seam nobody
## installed.
##
## ## Why the verbs are one cell, not one press-and-hold
##
## Movement is the scene's own grid step, and this screen is its remote: each
## button is one `step` call, so a headless driver, a gamepad repeat and a
## held key all meet the same verb. A press that moved until blocked would be
## a second movement rule disagreeing with the first.
##
## Contract: `summary()` is the testable surface, primitives only, and `{}` with no actor.

## The six actions this screen offers, in the order a player meets them.
const ACTION_IDS: Array[StringName] = [&"open", &"close", &"destroy"]

var _open_call: Callable = Callable()
var _close_call: Callable = Callable()
var _step_call: Callable = Callable()
var _destroy_call: Callable = Callable()
var _read_call: Callable = Callable()
var _return_call: Callable = Callable()
var _debug_call: Callable = Callable()
var _debug := false

var _header_label: Label = null
var _status_label: Label = null
var _node_option: OptionButton = null
var _open_button: Button = null
var _message_label: Label = null
var _debug_label: Label = null


func _ready() -> void:
	_bind_nodes()
	refresh()


func on_screen_shown() -> void:
	refresh()


func on_screen_hidden() -> void:
	pass


## Inject the six seams. Safe to call again; the screen re-reads and repaints.
func bind_venture(
	open_call: Callable,
	close_call: Callable,
	step_call: Callable,
	destroy_call: Callable,
	read_call: Callable,
	return_call: Callable,
	debug_call: Callable
) -> void:
	_open_call = open_call
	_close_call = close_call
	_step_call = step_call
	_destroy_call = destroy_call
	_read_call = read_call
	_return_call = return_call
	_debug_call = debug_call
	_bind_nodes()
	refresh()


## The keyboard and pad land on Open, so a fresh screen offers its one verb
## that changes nothing yet — walking starts after a place is standing.
func focus_initial() -> void:
	_bind_nodes()
	if _open_button != null and not _open_button.disabled:
		_focus_target = String(_open_button.name)
		if _open_button.is_inside_tree():
			_open_button.grab_focus()


## Open the selected place. Answers true only when a world stands afterwards.
func act_open() -> bool:
	_bind_nodes()
	if not _open_call.is_valid():
		set_message("No venture seam is bound.", TONE_ERROR)
		return false
	var outcome := _open_call.call(self, _selected_node()) as Dictionary
	refresh()
	if not bool(outcome.get("ok", false)):
		set_message("Open refused: %s." % String(outcome.get("reason", "")), TONE_ERROR)
		return false
	set_message("Standing in %s." % String(outcome.get("node", "")), TONE_OK)
	return true


## Close the standing world. Idempotent: closing nothing still answers true.
func act_close() -> bool:
	_bind_nodes()
	if _close_call.is_valid():
		_close_call.call(self)
	refresh()
	set_message("The venture is closed.", TONE_OK)
	return true


## Break whatever the player's cell masks. Answers what the seam freed.
func act_destroy() -> bool:
	_bind_nodes()
	if not _destroy_call.is_valid():
		set_message("No venture seam is bound.", TONE_ERROR)
		return false
	var outcome := _destroy_call.call(self) as Dictionary
	refresh()
	if not bool(outcome.get("ok", false)):
		set_message("Nothing here breaks: %s." % String(outcome.get("reason", "")), TONE_ERROR)
		return false
	set_message("Broke %d cell(s) open." % int(outcome.get("freed", 0)), TONE_OK)
	return true


## Leave the domain node and stand back where the descent began. Above
## ground this refuses rather than moving: return is the way back, not a step.
func act_return() -> bool:
	_bind_nodes()
	if not _return_call.is_valid():
		set_message("No venture seam is bound.", TONE_ERROR)
		return false
	var outcome := _return_call.call(self) as Dictionary
	refresh()
	if not bool(outcome.get("ok", false)):
		set_message("No way back: %s." % String(outcome.get("reason", "")), TONE_ERROR)
		return false
	set_message("Back where the descent began.", TONE_OK)
	return true


## Flip the debug painting. Answers the flag it set, so a driver asserts the
## toggle rather than pixels.
func act_debug() -> bool:
	_bind_nodes()
	if not _debug_call.is_valid():
		set_message("No venture seam is bound.", TONE_ERROR)
		return false
	_debug = not _debug
	var outcome := _debug_call.call(self, _debug) as Dictionary
	refresh()
	if not bool(outcome.get("ok", false)):
		_debug = not _debug
		set_message("Debug refused: %s." % String(outcome.get("reason", "")), TONE_ERROR)
		return false
	set_message("Debug painting %s." % ("on" if _debug else "off"), TONE_OK)
	return true


func act_north() -> bool:
	return _act_step(0, -1)


func act_south() -> bool:
	return _act_step(0, 1)


func act_west() -> bool:
	return _act_step(-1, 0)


func act_east() -> bool:
	return _act_step(1, 0)


func _act_step(dx: int, dy: int) -> bool:
	_bind_nodes()
	if not _step_call.is_valid():
		set_message("No venture seam is bound.", TONE_ERROR)
		return false
	var outcome := _step_call.call(self, dx, dy) as Dictionary
	refresh()
	if not bool(outcome.get("moved", false)):
		set_message("No ground that way.", TONE_ERROR)
		return false
	if bool(outcome.get("traveled", false)):
		set_message("The way carried you elsewhere.", TONE_OK)
	return true


## Everything this screen shows, as primitives only. `{}` with no actor, per
## the screen contract, so a test never reads a half-initialised screen. The
## world's own read arrives WHOLE under `place` rather than key by key.
func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var view := _read_view()
	view["has_actor"] = true
	view["actor_id"] = String(_actor.id)
	view["header"] = _text_of(_header_label)
	view["status"] = _text_of(_status_label)
	view["message_text"] = _text_of(_message_label)
	view["debug_text"] = _text_of(_debug_label)
	view["selected"] = _selected_node()
	return view


func _refresh_view() -> void:
	_fill_nodes()
	var view := _read_view()
	if bool(view.get("open", false)):
		var domain := view.get("domain", {}) as Dictionary
		if not domain.is_empty():
			var back := domain.get("return_cell", [0, 0]) as Array
			_set_text(
				_status_label,
				(
					"Inside %s; return stands at %s (%d, %d)."
					% [
						String(domain.get("template", "")),
						String(domain.get("return_node", "")),
						int(back[0]),
						int(back[1])
					]
				)
			)
		else:
			var cell := view.get("player_cell", [0, 0]) as Array
			_set_text(
				_status_label,
				"In %s at (%d, %d)." % [String(view.get("node", "")), int(cell[0]), int(cell[1])]
			)
	else:
		_set_text(_status_label, "No venture is standing.")
	_render()


func _render() -> void:
	_set_text(_message_label, _message)
	var view := _read_view()
	var can_open := _open_call.is_valid()
	var standing := bool(view.get("open", false))
	_set_disabled(_open_button, not can_open)
	for path in [
		"%NorthButton",
		"%SouthButton",
		"%WestButton",
		"%EastButton",
		"%DestroyButton",
		"%CloseButton"
	]:
		var control := get_node_or_null(path) as Button
		_set_disabled(control, not (standing and _step_call.is_valid()))
	var inside := not (view.get("domain", {}) as Dictionary).is_empty()
	_set_disabled(
		get_node_or_null("%ReturnButton") as Button, not (inside and _return_call.is_valid())
	)
	_set_disabled(
		get_node_or_null("%DebugButton") as Button, not (standing and _debug_call.is_valid())
	)
	_set_text(_debug_label, _debug_text(view))


func _read_view() -> Dictionary:
	if not _read_call.is_valid():
		return {"nodes": [], "open": false}
	return _read_call.call(self) as Dictionary


## The debug overlay as text: node and seed, player cell, holders, loaded and
## simulated sets, ranges, passes, edges and POI counts. Empty when nothing
## stands: no world, nothing to observe.
func _debug_text(view: Dictionary) -> String:
	if not _debug or not bool(view.get("open", false)):
		return ""
	var ranges := view.get("ranges", {}) as Dictionary
	var lines := [
		"node %s seed %d" % [String(view.get("node", "")), int(view.get("seed", 0))],
		(
			"at %s holders %d loaded %d simulated %d"
			% [
				str(view.get("player_cell", [])),
				(view.get("holders", []) as Array).size(),
				(view.get("loaded", []) as Array).size(),
				(view.get("simulated", []) as Array).size(),
			]
		),
		(
			"ranges data %d sim %d scene %d render %d"
			% [
				int(ranges.get("data", 0)),
				int(ranges.get("sim", 0)),
				int(ranges.get("scene", 0)),
				int(ranges.get("render", 0)),
			]
		),
		"passes %s" % [", ".join(view.get("passes", []) as Array)],
		(
			"edges %d pois %d"
			% [
				(view.get("edges", []) as Array).size(),
				(view.get("pois", []) as Array).size(),
			]
		),
	]
	return "\n".join(lines)


func _selected_node() -> String:
	if _node_option == null or _node_option.item_count == 0:
		return ""
	return String(_node_option.get_item_text(_node_option.selected))


func _fill_nodes() -> void:
	if _node_option == null:
		return
	var view := _read_view()
	var names: Array = view.get("nodes", [])
	if _node_option.item_count == names.size():
		return
	_node_option.clear()
	for name in names:
		_node_option.add_item(String(name))


func _bind_nodes() -> void:
	super()
	_header_label = get_node_or_null("%HeaderLabel") as Label
	_status_label = get_node_or_null("%StatusLabel") as Label
	_node_option = get_node_or_null("%NodeOption") as OptionButton
	_open_button = get_node_or_null("%OpenButton") as Button
	_message_label = get_node_or_null("%MessageLabel") as Label
	_debug_label = get_node_or_null("%DebugLabel") as Label
	_connect_once("%NorthButton", "pressed", act_north)
	_connect_once("%SouthButton", "pressed", act_south)
	_connect_once("%WestButton", "pressed", act_west)
	_connect_once("%EastButton", "pressed", act_east)
	_connect_once("%DestroyButton", "pressed", act_destroy)
	_connect_once("%OpenButton", "pressed", act_open)
	_connect_once("%CloseButton", "pressed", act_close)
	_connect_once("%ReturnButton", "pressed", act_return)
	_connect_once("%DebugButton", "pressed", act_debug)


## Guarded like the composition root's own connections: a reused screen that
## connected twice would fire every press N times.
func _connect_once(path: String, signal_name: StringName, handler: Callable) -> void:
	var control := get_node_or_null(path) as Button
	if control == null:
		return
	if not control.is_connected(signal_name, handler):
		control.connect(signal_name, handler)


func _text_of(label: Label) -> String:
	return "" if label == null else label.text


func _set_text(label: Label, text: String) -> void:
	if label != null:
		label.text = text


func _set_disabled(control: Button, disabled: bool) -> void:
	if control != null:
		control.disabled = disabled
