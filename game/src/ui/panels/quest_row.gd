class_name QuestRow
extends PanelContainer

## One quest on the journal board: its name, its kind, every step with what the
## world's memory already holds against what that step wants, and whether the
## gate holding it back is met.
##
## ## This row owns every format it shows
##
## The `%d/%d` on a step, the tier, the joined list of what a gate is waiting
## on, the "optional" mark — all of it is here, not in `QuestScreen`. The screen
## hands raw values down and never renders a number, which is the same split
## `CreationBranchRow` and `DestinyBranchRow` make.
##
## ## The button is a REQUEST, never a grant
##
## It emits the quest id it was built with and the screen asks the composition
## root's program, so the one place a quest is taken on is the program that
## calls `QuestApi.accept` — never a UI file. ADR 0065 is untouched: nothing
## here grants fate, destiny or an item; those are paid by `QuestGrants` at the
## one place completion is decided.
##
## `summary()` is the testable surface, and `{}` when the row carries nothing.

## The press. Carries the quest id ONLY.
signal accept_requested(quest_id: StringName)

const ACCEPT_TEXT := "Take this quest"
const ACTIVE_TEXT := "In flight"
const DONE_TEXT := "Finished"
const LOCKED_TEXT := "Closed to you"
const GATE_OK_TEXT := "The gate is open."
const GATE_SHUT_TEXT := "Waiting on: %s"
const STEP_DONE_MARK := " [done]"

var _view: Dictionary = {}
var _head: String = ""
var _description: String = ""
var _kind_line: String = ""
var _state_line: String = ""
var _steps_line: String = ""
var _gate_line: String = ""
var _head_label: Label = null
var _description_label: Label = null
var _kind_label: Label = null
var _state_label: Label = null
var _steps_label: Label = null
var _gate_label: Label = null
var _accept_button: Button = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one quest exactly as `QuestScreen` publishes it: the `_quest_view`
## primitive row (`id`, `display_name`, `description`, `kind`, `tier`,
## `gated`, `steps`, `grants`) plus the screen's own `state`, the live step
## tally read from the shared ledger, and the gate verdict. An empty dictionary
## clears the row, which is what a spare row in the pool shows.
func show_quest(view: Dictionary) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_head = String(_view.get("display_name", ""))
	_description = String(_view.get("description", ""))
	_kind_line = _kind_text(_view)
	_state_line = _state_text(_view)
	_steps_line = _steps_text(_view)
	_gate_line = _gate_text(_view)
	_render()


func clear() -> void:
	show_quest({})


## Everything the row shows, primitives only. `{}` when the row carries nothing.
func summary() -> Dictionary:
	_bind_nodes()
	if _view.is_empty():
		return {}
	return {
		"id": quest_id(),
		"display_name": String(_view.get("display_name", "")),
		"kind": String(_view.get("kind", "")),
		"tier": int(_view.get("tier", 0)),
		"gated": bool(_view.get("gated", false)),
		"state": String(_view.get("state", "")),
		"step_count": (_view.get("steps", []) as Array).size(),
		"steps_done": int(_view.get("steps_done", 0)),
		"steps_total": int(_view.get("steps_total", 0)),
		"ready": bool(_view.get("ready", false)),
		"can_accept": can_accept(),
		"gate_ok": bool(_view.get("gate_ok", true)),
		"gate_unmet": _strings(_view.get("gate_unmet", [])),
		"head": _head,
		"description": _description,
		"kind_line": _kind_line,
		"state_line": _state_line,
		"steps_line": _steps_line,
		"gate_line": _gate_line,
		"focus_target": "QuestRow",
	}


## Whether the row carries anything worth taking space for.
func is_filled() -> bool:
	return not _view.is_empty()


## The quest this row offers, or `""` when the row is empty.
func quest_id() -> String:
	return String(_view.get("id", ""))


## Whether the confirm button on this row is a live control. Carried down from
## the screen's own read model rather than re-derived: a row nobody can take on
## is shown greyed out, and a test can tell "closed to you" from "no button".
func can_accept() -> bool:
	return is_filled() and String(_view.get("state", "")) == QuestScreen.ROW_STATE_OFFERED


## Give the keyboard and pad a landing spot. The button when this quest can be
## taken on, so focus lands where a player would act. Recorded first, because a
## node outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if _accept_button != null and _accept_button.is_inside_tree():
		_accept_button.grab_focus()


# --- Plumbing ---------------------------------------------------------------


## Resolve the scene's widgets on first use rather than in `@onready`: the headless
## suite runner drives this row before a scene tree exists, so `_ready()` is not a
## dependable place to bind them. Idempotent, and every connect guarded.
func _bind_nodes() -> void:
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_description_label = get_node_or_null("%DescriptionLabel") as Label
	_kind_label = get_node_or_null("%KindLabel") as Label
	_state_label = get_node_or_null("%StateLabel") as Label
	_steps_label = get_node_or_null("%StepsLabel") as Label
	_gate_label = get_node_or_null("%GateLabel") as Label
	_accept_button = get_node_or_null("%AcceptButton") as Button
	if _accept_button != null and not _accept_button.pressed.is_connected(_on_accept):
		_accept_button.pressed.connect(_on_accept)


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	if not visible:
		return
	_head_label.text = _head
	_description_label.text = _description
	_description_label.visible = not _description.is_empty()
	_kind_label.text = _kind_line
	_state_label.text = _state_line
	_state_label.theme_type_variation = _state_tone()
	_steps_label.text = _steps_line
	_steps_label.visible = not _steps_line.is_empty()
	_gate_label.text = _gate_line
	_gate_label.visible = not _gate_line.is_empty()
	_gate_label.theme_type_variation = (
		&"OkLabel" if bool(_view.get("gate_ok", true)) else &"WarnLabel"
	)
	if _accept_button != null:
		_accept_button.disabled = not can_accept()
		_accept_button.text = _accept_text()


## Which origin this quest came from, in a player's words, with its tier.
func _kind_text(view: Dictionary) -> String:
	var authored := String(view.get("display_name", ""))
	var kind := String(view.get("kind", ""))
	if authored.is_empty():
		return ""
	return "%s quest, tier %d" % [_kind_word(kind), int(view.get("tier", 0))]


## The one word a player reads for the three kinds BL-0053 names. The id is the
## fallback, never the primary, because a player reads "Authored" and never
## "authored".
func _kind_word(kind: String) -> String:
	match kind:
		"systemic":
			return "Systemic"
		"emergent":
			return "Emergent"
		"authored":
			return "Authored"
	return kind.capitalize()


## Where this quest stands: an offer, something already in flight, or a finished
## run. With the live tally on an in-flight row, because `have` against `need`
## is the only progress this module owns (ADR 0113).
func _state_text(view: Dictionary) -> String:
	match String(view.get("state", "")):
		QuestScreen.ROW_STATE_OFFERED:
			return "Offered to you."
		QuestScreen.ROW_STATE_ACTIVE:
			return (
				"In flight: %d of %d steps read from the world's memory."
				% [
					int(view.get("steps_done", 0)),
					int(view.get("steps_total", 0)),
				]
			)
		QuestScreen.ROW_STATE_DONE:
			return "Finished. Its grants were paid once and never again."
	return ""


## Every step on one line, `label (have/need)`, with a done mark and an optional
## mark. The numbers arrive raw and are formatted HERE.
func _steps_text(view: Dictionary) -> String:
	var lines: Array[String] = []
	for entry in view.get("steps", []) as Array:
		var step := entry as Dictionary
		var label := String(step.get("label", String(step.get("step_id", ""))))
		var text := (
			"%s (%d/%d)"
			% [
				label,
				int(step.get("have", 0)),
				int(step.get("need", 0)),
			]
		)
		if bool(step.get("done", false)):
			text += STEP_DONE_MARK
		if bool(step.get("optional", false)):
			text += " (optional)"
		lines.append(text)
	if lines.is_empty():
		return ""
	return "  ".join(lines)


## What the gate is waiting on, named from the verdict the module produced.
## An ungated quest says so rather than printing an empty list.
func _gate_text(view: Dictionary) -> String:
	if not bool(view.get("gated", false)):
		return ""
	if bool(view.get("gate_ok", true)):
		return GATE_OK_TEXT
	var unmet := _strings(view.get("gate_unmet", []))
	if unmet.is_empty():
		return LOCKED_TEXT
	return GATE_SHUT_TEXT % ", ".join(unmet)


func _accept_text() -> String:
	match String(_view.get("state", "")):
		QuestScreen.ROW_STATE_OFFERED:
			return ACCEPT_TEXT if can_accept() else LOCKED_TEXT
		QuestScreen.ROW_STATE_ACTIVE:
			return ACTIVE_TEXT
		QuestScreen.ROW_STATE_DONE:
			return DONE_TEXT
	return ""


func _state_tone() -> StringName:
	match String(_view.get("state", "")):
		QuestScreen.ROW_STATE_DONE:
			return &"OkLabel"
		QuestScreen.ROW_STATE_ACTIVE:
			return &"EffectLabel"
	return &"MetaLabel"


## The press is a REQUEST. The row emits the id it was built with; the screen
## asks the app program, and `QuestApi.accept` is the only thing that answers.
func _on_accept() -> void:
	var id := quest_id()
	if id == "" or not can_accept():
		return
	accept_requested.emit(StringName(id))


func _strings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
