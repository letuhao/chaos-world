class_name DialogueScreen
extends UiScreen

## The conversation screen (ADR 0862, DEF-0014). A pure consumer of the `dialogue`
## facade: it renders `DialogueApi.current` and drives `DialogueApi.start` / `.choose`.
##
## ## Every word on it comes from the MODULE
##
## The speaker, the lines and every choice label are authored content the facade
## publishes; a refusal is the module's own named reason. The screen authors no prose of
## its own, so a conversation reads from ONE source — its `.tres` (or its `.yarn` before
## compilation) — and the page adds no catalog key of its own.
##
## ## Leaving the page ends the conversation
##
## There is no `stop` button to label: `on_screen_hidden` calls `DialogueApi.stop`, so
## walking away from the page IS the act of ending the conversation. That also keeps the
## screen's action list entirely content-derived.
##
## ## The entry list is the catalog
##
## Pressing a conversation calls `DialogueApi.start(actor, npc_id)`, so there is no
## second list of "who can talk" to keep in sync with the authored tree.
##
## Contract: `summary()` is the testable surface, primitives only, the action set's own
## summary nested under `actions`, and `{}` with no actor.

## The ActionSet action for one authored conversation, and for one choice of the open
## node. A prefix rather than the bare id, so an npc called `leave` cannot collide with a
## choice called `leave`.
const START_PREFIX := "talk:"
const CHOOSE_PREFIX := "choose:"

var _speaker: Label = null
var _lines: Label = null
var _actions: ActionSet = null


func act_start(npc_id: StringName) -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {"ok": false, "reason": "no_actor"}
	var outcome := DialogueApi.start(_actor, npc_id)
	set_message(String(outcome.get("reason", "")), TONE_OK if bool(outcome.get("ok", false)) else TONE_ERROR)
	refresh()
	return outcome


func act_choose(choice_id: StringName) -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {"ok": false, "reason": "no_actor"}
	var outcome := DialogueApi.choose(_actor, choice_id)
	set_message(String(outcome.get("reason", "")), TONE_OK if bool(outcome.get("ok", false)) else TONE_ERROR)
	refresh()
	return outcome


## Walk away: the conversation ends with the page.
func on_screen_hidden() -> void:
	if _actor != null:
		DialogueApi.stop(_actor)


# --- the screen contract -----------------------------------------------------


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var live := DialogueApi.current(_actor)
	var rows: Array = []
	for entry in _conversations():
		rows.append(entry)
	return {
		"talking": bool(live.get("ok", false)),
		"dialog_id": String(live.get("dialog_id", "")),
		"node_id": String(live.get("node_id", "")),
		"speaker": String(live.get("speaker", "")),
		"lines": live.get("lines", []),
		"conversations": rows,
		"actions": _actions.summary() if _actions != null else {},
	}


func _refresh_view() -> void:
	_bind_nodes()
	_render_text()
	_render_actions()


# --- rendering ---------------------------------------------------------------


func _render_text() -> void:
	if _speaker == null or _lines == null:
		return
	var live := DialogueApi.current(_actor) if _actor != null else {}
	if not bool(live.get("ok", false)):
		_speaker.text = ""
		_lines.text = ""
		return
	_speaker.text = L.t(String(live.get("speaker", "")))
	var spoken: Array[String] = []
	for line in live.get("lines", []) as Array:
		spoken.append(String(line))
	_lines.text = L.t("\n".join(spoken))


## The choices of the open node, or the authored conversations when nobody is talking.
## A LOCKED choice is PUBLISHED and disabled rather than hidden, so "not yet" and "never"
## stay different sentences (the module's own rule).
func _render_actions() -> void:
	if _actions == null or _actor == null:
		return
	var live := DialogueApi.current(_actor)
	var actions: Array = []
	var labels := {}
	var enabled := {}
	if bool(live.get("ok", false)):
		for row in live.get("choices", []) as Array:
			var choice := row as Dictionary
			var action := CHOOSE_PREFIX + String(choice.get("choice_id", ""))
			actions.append(StringName(action))
			labels[action] = String(choice.get("label", ""))
			enabled[action] = not bool(choice.get("locked", false))
	else:
		for entry in _conversations():
			var npc_id := String((entry as Dictionary).get("npc_id", ""))
			var action := START_PREFIX + npc_id
			actions.append(StringName(action))
			labels[action] = npc_id
			enabled[action] = true
	(
		_actions
		. set_state(
			{
				"actions": actions,
				"labels": labels,
				"enabled": enabled,
				"message": _message,
				"tone": _tone,
			}
		)
	)


## Every authored conversation as `{dialog_id, npc_id}`, sorted so two runs agree.
## Read from the facade's catalog rather than walked here.
func _conversations() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dialog_id in DialogueApi.catalog().keys():
		var def := DialogueApi.catalog()[dialog_id] as Dictionary
		var npc_id := String(def.get("npc_id", ""))
		if npc_id == "":
			continue
		out.append({"dialog_id": String(dialog_id), "npc_id": npc_id})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["dialog_id"]) < String(b["dialog_id"]))
	return out


# --- plumbing ----------------------------------------------------------------


func _bind_nodes() -> void:
	super()
	if _actions != null:
		return
	_actions = get_node_or_null("%Actions") as ActionSet
	_speaker = get_node_or_null("%SpeakerLabel") as Label
	_lines = get_node_or_null("%LinesLabel") as Label
	if _actions != null and not _actions.action_requested.is_connected(_on_action):
		_actions.action_requested.connect(_on_action)


func _on_action(action: StringName) -> void:
	var text := String(action)
	if text.begins_with(CHOOSE_PREFIX):
		act_choose(StringName(text.substr(CHOOSE_PREFIX.length())))
	elif text.begins_with(START_PREFIX):
		act_start(StringName(text.substr(START_PREFIX.length())))
