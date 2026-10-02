class_name SetBonusPanel
extends PanelContainer

## Inspection panel for the authored sets: which set is selected, who its
## members are and which of them are worn, every threshold with its granted
## options marked active or not, and the unique members' locked signatures.
##
## A pure renderer of the snapshot the `set_bonus` facade publishes. It never
## reaches into a module, never resolves a definition, and owns every number
## format the row does not. `summary()` is the testable surface.

const NO_SET_TEXT := "No set selected"
const ROW_SCENE := "res://src/ui/panels/set_threshold_row.tscn"

var _snapshot: Dictionary = {}
var _selected_set: String = ""
var _view: Dictionary = {}
var _member_lines: Array = []
var _unique_lines: Array = []
var _header: String = NO_SET_TEXT
var _meta: String = ""
var _header_label: Label = null
var _meta_label: Label = null
var _member_title: Label = null
var _member_rows: VBoxContainer = null
var _threshold_title: Label = null
var _threshold_rows: VBoxContainer = null
var _unique_title: Label = null
var _unique_label: Label = null


func _init() -> void:
	_view = _empty_view()


func _ready() -> void:
	_bind_nodes()
	_render()


## Adopt a facade snapshot (`SetBonusApi.inspect(actor)` shaped) and show the
## first authored set, so the panel is never blank while the module has content.
func set_snapshot(snapshot: Dictionary) -> void:
	_bind_nodes()
	_snapshot = snapshot.duplicate(true)
	_selected_set = _first_set_id()
	select_set(_selected_set)


## Show one set from the adopted snapshot. Returns false for an unknown id, so a
## caller never reads a stale set back.
func select_set(set_id: String) -> bool:
	_bind_nodes()
	var sets: Dictionary = _snapshot.get("sets", {})
	if not sets.has(set_id):
		return false
	_selected_set = set_id
	_view = sets[set_id]
	_header = String(_view.get("display_name", set_id))
	_meta = _meta_line(_view)
	_member_lines = _member_lines_for(_view)
	_unique_lines = _unique_lines_for(_view)
	_render()
	return true


func selected_set() -> String:
	return _selected_set


## Every set id the snapshot carries, canonically ordered. Sorted from the same
## source `set_snapshot` picks its first set from, so the list a screen cycles and
## the set it opens on can never disagree.
func set_ids() -> Array:
	var out: Array = []
	for set_id in snapshot_sets().keys():
		out.append(String(set_id))
	out.sort()
	return out


## The state the module reports, echoed so a caller can read the persisted
## numbers without a second lookup.
func state() -> Dictionary:
	return _snapshot.get("state", {}).duplicate(true)


func clear() -> void:
	_bind_nodes()
	_snapshot = {}
	_selected_set = ""
	_view = _empty_view()
	_member_lines = []
	_unique_lines = []
	_header = NO_SET_TEXT
	_meta = ""
	_render()


## Everything the panel shows, primitives only, with each threshold row's own
## summary nested under `thresholds`. Empty with no snapshot.
func summary() -> Dictionary:
	_bind_nodes()
	if _snapshot.is_empty() or _view.is_empty():
		return {}
	var rows: Array = []
	for child in _rows(_threshold_rows):
		var summary: Dictionary = child.call("summary")
		if not summary.is_empty():
			rows.append(summary)
	var out := _empty_view()
	out["set_id"] = _selected_set
	out["display_name"] = _header
	# Every scalar `_meta_line` is built from is published raw next to the line it
	# renders, so a test checks the numbers the panel shows instead of parsing the
	# string it formatted them into.
	out["rarity"] = String(_view.get("rarity", ""))
	out["counting"] = String(_view.get("counting", ""))
	out["realm"] = String(_view.get("realm", ""))
	out["member_count"] = int(_view.get("member_count", 0))
	out["equipped_count"] = int(_view.get("equipped_count", 0))
	out["meta"] = _meta
	out["member_lines"] = _member_lines.duplicate()
	out["unique_lines"] = _unique_lines.duplicate()
	out["thresholds"] = rows
	out["threshold_count"] = rows.size()
	out["active_threshold_count"] = _active_rows(rows)
	out["set_ids"] = set_ids()
	out["available_sets"] = out["set_ids"]
	out["unique_total"] = int(_snapshot.get("unique_total", 0))
	return out


## Give the keyboard and pad a landing spot inside this panel: the first
## threshold row, because that is what the panel is read for.
func focus_initial() -> void:
	_bind_nodes()
	for child in _rows(_threshold_rows):
		if child.has_method("focus_initial"):
			child.call("focus_initial")
			return


## Resolve the scene's widgets on first use rather than in `@onready`: the
## headless suite runner drives this panel before a scene tree exists, so
## `_ready()` is not a dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	if _header_label != null:
		return
	_header_label = get_node_or_null("%HeaderLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label
	_member_title = get_node_or_null("%MemberTitle") as Label
	_member_rows = get_node_or_null("%MemberRows") as VBoxContainer
	_threshold_title = get_node_or_null("%ThresholdTitle") as Label
	_threshold_rows = get_node_or_null("%ThresholdRows") as VBoxContainer
	_unique_title = get_node_or_null("%UniqueTitle") as Label
	_unique_label = get_node_or_null("%UniqueLabel") as Label


func _empty_view() -> Dictionary:
	return {
		"set_id": "",
		"display_name": "",
		"rarity": "",
		"counting": "",
		"realm": "",
		"member_count": 0,
		"equipped_count": 0,
		"meta": "",
		"member_lines": [],
		"unique_lines": [],
		"thresholds": [],
		"threshold_count": 0,
		"active_threshold_count": 0,
		"set_ids": [],
		"available_sets": [],
		"unique_total": 0,
	}


func snapshot_sets() -> Dictionary:
	return _snapshot.get("sets", {})


func _first_set_id() -> String:
	var sets := snapshot_sets()
	var ids: Array = sets.keys()
	ids.sort()
	return "" if ids.is_empty() else String(ids[0])


## "Ironhide Vigil | Rare | realm core_formation | 2 of 5 members | 1 threshold
## active". The panel owns the wording and every number.
func _meta_line(view: Dictionary) -> String:
	return (
		"%s | %s | realm %s | %d of %d members | %d threshold(s) active"
		% [
			String(view.get("rarity", "")),
			String(view.get("counting", "")),
			String(view.get("realm", "")),
			int(view.get("equipped_count", 0)),
			int(view.get("member_count", 0)),
			int(view.get("active_threshold_count", 0)),
		]
	)


## One line per member: worn state, kind, rarity, realm, and the fixed options it
## carries on its own. A unique's line also names its locked signature.
func _member_lines_for(view: Dictionary) -> Array:
	var out: Array = []
	for member in view.get("members", []):
		var entry: Dictionary = member
		out.append(_member_line(entry))
	return out


func _member_line(entry: Dictionary) -> String:
	var state := (
		"worn in %s" % String(entry.get("slot", ""))
		if bool(entry.get("equipped", false))
		else "not worn"
	)
	var line := (
		"%s [%s] %s / %s — %s"
		% [
			String(entry.get("display_name", entry.get("def_id", ""))),
			String(entry.get("kind", "")),
			String(entry.get("rarity", "")),
			String(entry.get("realm", "")),
			state,
		]
	)
	var locked: Array = entry.get("locked_option_ids", [])
	if bool(entry.get("is_unique", false)):
		line += " | locked: %s" % ", ".join(locked)
		line += " | route: %s" % String(entry.get("route_boss_id", ""))
	var options: Array = entry.get("fixed_options", [])
	if not options.is_empty():
		line += " | fixed: %s" % ", ".join(_option_labels(options))
	return line


## Unique members, spelled out separately so a locked signature is never buried
## in a member list.
func _unique_lines_for(view: Dictionary) -> Array:
	var out: Array = []
	for member in view.get("members", []):
		var entry: Dictionary = member
		if not bool(entry.get("is_unique", false)):
			continue
		(
			out
			. append(
				(
					"%s locks %s; drops from %s"
					% [
						String(entry.get("display_name", entry.get("def_id", ""))),
						", ".join(entry.get("locked_option_ids", [])),
						String(entry.get("route_boss_id", "")),
					]
				)
			)
		)
	return out


func _option_labels(options: Array) -> Array:
	var out: Array = []
	for option in options:
		out.append(String((option as Dictionary).get("label", "")))
	return out


func _active_rows(rows: Array) -> int:
	var total := 0
	for row in rows:
		if bool((row as Dictionary).get("active", false)):
			total += 1
	return total


func _rows(box: VBoxContainer) -> Array:
	return [] if box == null else box.get_children()


func _render() -> void:
	if _header_label == null:
		return
	_header_label.text = _header if _header != "" else NO_SET_TEXT
	_meta_label.text = _meta
	_member_title.text = "Members (%d)" % _view.get("members", []).size()
	_threshold_title.text = "Thresholds (%d)" % _view.get("thresholds", []).size()
	_unique_title.text = "Unique signatures"
	_unique_title.visible = not _unique_lines.is_empty()
	_unique_label.text = "\n".join(_unique_lines)
	_unique_label.visible = not _unique_lines.is_empty()
	_fill_labels(_member_rows, _member_lines)
	_fill_rows(_view.get("thresholds", []))


## Member rows are plain labels; the panel fills them the same way every other
## panel in this program does.
func _fill_labels(box: VBoxContainer, lines: Array) -> void:
	if box == null:
		return
	for child in box.get_children():
		box.remove_child(child)
		child.free()
	for line in lines:
		var label := Label.new()
		label.text = String(line)
		label.theme_type_variation = &"EffectLabel"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(label)


## Threshold rows are the reusable row scene, so a set with four thresholds and a
## set with one look the same.
func _fill_rows(thresholds: Array) -> void:
	if _threshold_rows == null:
		return
	for child in _threshold_rows.get_children():
		_threshold_rows.remove_child(child)
		child.free()
	var packed: PackedScene = load(ROW_SCENE)
	for threshold in thresholds:
		var row = packed.instantiate()
		_threshold_rows.add_child(row)
		row.call("show_threshold", threshold)
