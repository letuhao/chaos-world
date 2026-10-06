class_name SettingsScreen
extends UiScreen

## The settings screen: the difficulty the run is played under.
##
## ## Why difficulty only
##
## `DifficultyApi.views()` publishes preset rows "for a settings screen" and
## `select(actor, id)` is the one setter — the whole read model and the whole
## verb already exist with nowhere to press them except the soul page's hearth
## half. This screen is that press, standing alone. Volume, display and other
## settings have no module behind them; a control for one would be a control
## with nothing behind it, so they are absent rather than decorative.
##
## ## Where the verb comes from
##
## The screen reads `DifficultyApi` by bare name (`difficulty` is a granted
## `UI_MODULES` reach, the same reach `SoulHearthScreen` uses) and takes the
## setter as an injected Callable off the composition root (ADR 0143), because
## `select` takes the bound actor and `ui/` may not mint one.
##
## Contract: `summary()` is the testable surface, primitives only, and `{}`

const NO_SELECT_SEAM := "no_select_seam"
const PRESET_SCENE := "res://src/ui/panels/difficulty_preset_row.tscn"

var _rows_box: VBoxContainer = null
## `select(difficulty_id) -> Dictionary`, answering the module's own verdict
## verbatim. Unwired, every press refuses by name.
var _select_difficulty: Callable = Callable()
var _last_select: Dictionary = {}


## Inject the setter. Repaints immediately so a screen bound after its first
## paint does not show the state it had before the binding.
func bind_difficulty(select_difficulty: Callable) -> void:
	_select_difficulty = select_difficulty
	_bind_nodes()
	refresh()


## Whether a press can reach the module right now.
func can_select() -> bool:
	return _actor != null and _select_difficulty.is_valid()


## The preset ids on the page, in display order.
func preset_ids() -> Array:
	var out: Array = []
	for row in _preset_rows():
		var preset_id := String((row as DifficultyPresetRow).difficulty_id())
		if not preset_id.is_empty():
			out.append(preset_id)
	return out


## Choose `difficulty_id` for this run: press a row's button, and this is what
## happens. Returns the module's verdict verbatim, then repaints from the
## module — so what the player sees afterwards is the module's state and not
## this screen's memory of what it asked for.
func act_select(difficulty_id: StringName) -> Dictionary:
	_bind_nodes()
	if _actor == null or not _select_difficulty.is_valid():
		_last_select = {"ok": false, "reason": NO_SELECT_SEAM}
		set_message(NO_SELECT_SEAM, TONE_ERROR)
		refresh()
		return _last_select.duplicate(true)
	_last_select = (_select_difficulty.call(difficulty_id) as Dictionary).duplicate(true)
	if not bool(_last_select.get("ok", false)):
		set_message(String(_last_select.get("reason", NO_SELECT_SEAM)), TONE_ERROR)
	else:
		set_message("", TONE_OK)
	refresh()
	return _last_select.duplicate(true)


## The verdict of the last press, or `{}`. A report, never a selection.
func last_select() -> Dictionary:
	return _last_select.duplicate(true)


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var current := String(DifficultyApi.current_id(_actor))
	var presets: Array = []
	for row in _preset_rows():
		var view := (row as DifficultyPresetRow).summary()
		if view.is_empty():
			continue
		view["selected"] = String(view.get("difficulty_id", "")) == current
		presets.append(view)
	return {
		"current_id": current,
		"difficulty_seam": can_select(),
		"presets": presets,
		"preset_ids": preset_ids(),
		"total_presets": DifficultyApi.views().size(),
		"last_select_ok": bool(_last_select.get("ok", false)),
		"last_select_reason": String(_last_select.get("reason", "")),
	}


func _refresh_view() -> void:
	_bind_nodes()
	if _actor == null or _rows_box == null:
		return
	var views := DifficultyApi.views()
	var rows := _preset_rows()
	for i in rows.size():
		var row := rows[i] as DifficultyPresetRow
		if row == null:
			continue
		if i < views.size():
			var view := (views[i] as Dictionary).duplicate(true)
			view["selected"] = (
				String(view.get("difficulty_id", "")) == String(DifficultyApi.current_id(_actor))
			)
			row.show_preset(view)
		else:
			row.show_preset({})


func _render() -> void:
	pass


func _bind_nodes() -> void:
	super()
	_rows_box = get_node_or_null("%PresetRows") as VBoxContainer
	for row in _preset_rows():
		var typed := row as DifficultyPresetRow
		if typed == null:
			continue
		if not typed.select_requested.is_connected(_on_row_select_requested):
			typed.select_requested.connect(_on_row_select_requested)


## Every preset row under the pool, in display order.
func _preset_rows() -> Array:
	if _rows_box == null:
		return []
	var out: Array = []
	for child in _rows_box.get_children():
		if child is DifficultyPresetRow:
			out.append(child)
	return out


func _on_row_select_requested(difficulty_id: StringName) -> void:
	act_select(difficulty_id)
