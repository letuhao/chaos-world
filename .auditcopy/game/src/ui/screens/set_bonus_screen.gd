class_name SetBonusScreen
extends UiScreen

## The set/unique inspection screen: every authored set with its membership and
## its thresholds, and the unique members' locked signatures.
##
## A pure consumer of the `set_bonus` facade's published snapshot (ADR 0030/0038).
## It names no module type and resolves no definition: the composition root (or a
## headless test) hands it `SetBonusApi.inspect(actor)` through `apply_snapshot`,
## and the screen renders exactly that. Every number is formatted by the panels.
##
## Contract: `summary()` is the testable surface, with the panel's own summary
## nested under `panel`. `{}` with no actor or no snapshot.

const CYCLE_PREVIOUS := &"ui_left"
const CYCLE_NEXT := &"ui_right"

var _snapshot: Dictionary = {}
var _panel: SetBonusPanel = null
var _set_ids: Array = []
var _footer: Label = null


## Adopt the facade's snapshot for the bound actor. Safe to call repeatedly: the
## panel rebinds and the selection is reset to the first authored set.
func apply_snapshot(snapshot: Dictionary) -> void:
	_bind_nodes()
	_snapshot = snapshot.duplicate(true)
	if _panel != null:
		_panel.set_snapshot(_snapshot)
		_set_ids = _panel.set_ids()
	_refresh_view()


## Show one authored set. Returns false for an id the snapshot does not carry, so
## a caller never reads back a set that was never shown.
func select_set(set_id: String) -> bool:
	_bind_nodes()
	if _panel == null:
		return false
	if not _panel.select_set(set_id):
		return false
	_set_ids = _panel.set_ids()
	_refresh_view()
	return true


## The set currently on screen, or `""` when there is none.
func selected_set() -> String:
	_bind_nodes()
	return "" if _panel == null else _panel.selected_set()


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null or _panel == null or _snapshot.is_empty():
		return {}
	var panel := _panel.summary()
	if panel.is_empty():
		return {}
	return {
		"actor_id": String(_actor.id),
		"set_count": _set_ids.size(),
		"selected_set": panel["set_id"],
		"available_sets": _set_ids.duplicate(),
		"active_sets": _snapshot.get("active_set_ids", []),
		"unique_total": int(_snapshot.get("unique_total", 0)),
		"threshold_count": int(panel["threshold_count"]),
		"active_threshold_count": int(panel["active_threshold_count"]),
		"panel": panel,
	}


func _refresh_view() -> void:
	_bind_nodes()
	if _footer == null:
		return
	_footer.text = (
		"Left / Right cycles the authored sets. Cancel returns." if _actor != null else ""
	)


## `ui_left` / `ui_right` cycle the authored sets and are consumed. Everything
## else is declined so `ScreenStack` can pop on `ui_cancel`.
func on_stack_input(event: InputEvent) -> bool:
	if _actor == null or event == null or _set_ids.is_empty():
		return false
	if not event.is_pressed() or event.is_echo():
		return false
	if event.is_action_pressed(CYCLE_NEXT):
		return _cycle(1)
	if event.is_action_pressed(CYCLE_PREVIOUS):
		return _cycle(-1)
	return false


## One initial focus for the screen, so it is keyboard/gamepad reachable. Only
## the stack calls this, and only when the screen is actually live.
func focus_initial() -> void:
	_bind_nodes()
	if _panel != null:
		_panel.focus_initial()


func _bind_nodes() -> void:
	if _panel != null:
		return
	_panel = get_node_or_null("%SetBonusPanel") as SetBonusPanel
	_footer = get_node_or_null("%FooterLabel") as Label


func _cycle(step: int) -> bool:
	if _set_ids.is_empty():
		return false
	var index := _set_ids.find(selected_set())
	if index < 0:
		index = 0
	var next := posmod(index + step, _set_ids.size())
	return select_set(String(_set_ids[next]))
