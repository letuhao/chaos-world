class_name QiCultivationScreen
extends UiScreen

## Qi-cultivation screen (ADR 0038/0039). A pure consumer of the
## `qi_cultivation` facade: it renders `QiCultivationApi.panel_state()` and calls
## facade actions, never module internals.
##
## The facade calls its gate `can_attempt`/`unmet_conditions`; the shared screen
## vocabulary is `can_act`/`unmet`, so this screen normalizes on the way in. One
## vocabulary means two screens can never disagree about what a key means.
##
## Contract: `summary()` is the testable surface, with child panel summaries
## nested under their own key.

const STEPS := {"cultivate": 25.0, "meditate": 1.0}

var _vitals: VBoxContainer = null
var _rows: Dictionary = {}
var _actions: ActionSet = null
var _conditions_label: Label = null
var _realm_label: Label = null
var _channels: ChannelList = null


## Everything this screen displays, normalized to the shared vocabulary.
## Primitives only; `{}` when no actor.
func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var live := QiCultivationApi.panel_state(_actor)
	if live.is_empty():
		return {}
	# `summary()` may be the first thing a caller runs (the headless CLI does), so
	# the child panels are fed here too — otherwise a child's summary would report
	# whatever the last refresh left behind.
	_feed_children(live)
	var view := {
		"realm": live.get("realm", ""),
		"target": live.get("target", ""),
		"progress": live.get("progress", 0.0),
		"qi": live.get("qi", 0.0),
		"qi_maximum": live.get("qi_maximum", 0.0),
		"dantian_tier": live.get("dantian_tier", ""),
		"dantian_quality": live.get("dantian_quality", 0.0),
		"dantian_injured": live.get("dantian_injured", false),
		"channels": _channel_entries(live),
		"can_act": live.get("can_attempt", false),
		"chance": live.get("chance", 0.0),
		"unmet": live.get("unmet", []),
		"costs": live.get("costs", {}),
		"steps": STEPS,
	}
	view["vitals"] = _vitals_summary()
	view["actions"] = _actions.summary() if _actions != null else {}
	if _channels != null:
		view["channel_list"] = _channels.summary()
	return view


## The facade reports channels as pre-formatted strings (`"lung:open/1"`). The UI
## needs the fields, not the string, so the row can show name, state, refinement
## and injury separately and mark the ones the gate requires. The gate itself is
## read from the facade's `required_channels`, never from the realm seed, which is
## a module internal (ADR 0043).
func _channel_entries(live: Dictionary) -> Array:
	var required: Array[StringName] = []
	for meridian_id in live.get("required_channels", []):
		required.append(StringName(meridian_id))
	var out: Array = []
	for raw in live.get("channels", []):
		var text := String(raw)
		# Format is "<id>:<state>/<refinement>" plus "!" when injured.
		var injured := text.ends_with("!")
		if injured:
			text = text.substr(0, text.length() - 1)
		var parts := text.split(":")
		if parts.size() < 2:
			continue
		var detail := parts[1].split("/")
		var meridian_id := parts[0]
		var definition := _definition_for(meridian_id)
		(
			out
			. append(
				{
					"id": meridian_id,
					"name": meridian_id if definition == null else definition.display_name,
					"state": detail[0] if not detail.is_empty() else "unknown",
					"refinement": int(detail[1]) if detail.size() > 1 else 0,
					"injured": injured,
					"required": required.has(StringName(meridian_id)),
				}
			)
		)
	return out


func _definition_for(meridian_id: String) -> MeridianDef:
	for definition in MeridianDefaults.all():
		if String(definition.id) == meridian_id:
			return definition
	return null


## Hand the facade's raw values to every child panel. Shared by `refresh()` and
## `summary()` so a child's reported state is never one refresh stale.
func _feed_children(live: Dictionary) -> void:
	_set_row(
		&"qi",
		{
			"name": "Qi",
			"current": live.get("qi", 0.0),
			"maximum": live.get("qi_maximum", 0.0),
			"mode": StatRow.MODE_BAR,
		}
	)
	_set_row(
		&"dantian",
		{
			"name": "Dantian quality",
			"current": live.get("dantian_quality", 0.0),
			"maximum": 1.0,
			"decimals": 2,
			"mode": StatRow.MODE_BAR,
		}
	)
	_set_row(
		&"progress",
		{
			"name": "Progress",
			"current": live.get("progress", 0.0),
			"maximum": 1.0,
		}
	)
	if _channels != null:
		(
			_channels
			. set_state(
				{
					"channels": _channel_entries(live),
					"required": live.get("required_channels", []),
					"show_all": false,
				}
			)
		)


## Re-read the facade and hand raw values down. The panels own every format.
func _refresh_view() -> void:
	_bind_nodes()
	var live := QiCultivationApi.panel_state(_actor) if _actor != null else {}
	_feed_children(live)
	if _actions != null:
		var ready := bool(live.get("can_attempt", false))
		var has_gate := not String(live.get("required_channel_state", "")).is_empty()
		(
			_actions
			. set_state(
				{
					"actions":
					[
						&"cultivate",
						&"meditate",
						&"train_channel",
						&"recover",
						&"breakthrough",
					],
					"labels":
					{
						"cultivate": "Cultivate",
						"meditate": "Meditate",
						"train_channel": "Train Channel",
						"recover": "Recover",
						"breakthrough": "Breakthrough",
					},
					"enabled":
					{
						"cultivate": not live.is_empty(),
						"meditate": not live.is_empty(),
						"train_channel": not live.is_empty() and has_gate,
						"recover": not live.is_empty(),
						"breakthrough": ready,
					},
					"primary": &"breakthrough",
					"message": _message,
					"tone": _tone,
				}
			)
		)
	_render_conditions(live)
	_render_realm(live)
	if _channels != null:
		(
			_channels
			. set_state(
				{
					"channels": _channel_entries(live),
					"required": live.get("required_channels", []),
					"show_all": false,
				}
			)
		)


## The realm line the scene declares but used to leave at its placeholder text.
func _render_realm(live: Dictionary) -> void:
	if _realm_label == null:
		return
	if live.is_empty():
		_realm_label.text = "Realm: none"
		return
	_realm_label.text = (
		"Realm: %s -> %s"
		% [
			live.get("realm", ""),
			live.get("target", ""),
		]
	)


## The unmet list is the one thing a player reads to know what to do next, so it
## is rendered as plainly as the stats. Both screens used to compute this and drop
## it on the floor (ADR 0043 audit).
func _render_conditions(live: Dictionary) -> void:
	if _conditions_label == null:
		return
	if live.is_empty():
		_conditions_label.text = ""
		return
	var unmet: Array = live.get("unmet", [])
	if unmet.is_empty():
		_conditions_label.text = "Conditions: READY"
		_conditions_label.theme_type_variation = &"OkLabel"
		return
	var costs: Dictionary = live.get("costs", {})
	var cost_line := ""
	if not costs.is_empty():
		var ids: Array[String] = []
		for key in costs:
			ids.append("%s x%d" % [key, int(costs[key])])
		cost_line = " | Needs: %s" % ", ".join(ids)
	_conditions_label.text = "Conditions: %s%s" % [", ".join(unmet), cost_line]
	_conditions_label.theme_type_variation = &"MetaLabel"


# --- Actions, callable headlessly as well as by the buttons ----------------


func act_cultivate() -> void:
	if _actor == null:
		return
	QiCultivationApi.cultivate(_actor, float(STEPS["cultivate"]))
	set_message("Cultivated qi", TONE_OK)
	refresh()


func act_meditate() -> void:
	if _actor == null:
		return
	QiCultivationApi.meditate(_actor, float(STEPS["meditate"]))
	set_message("Meditated", TONE_OK)
	refresh()


func act_breakthrough() -> bool:
	if _actor == null:
		return false
	var advanced := QiCultivationApi.attempt_breakthrough(_actor)
	if advanced:
		set_message("Broke through", TONE_OK)
	else:
		set_message("The attempt deviated; recover and try again", TONE_ERROR)
	refresh()
	return advanced


## Train the first channel that is not yet at the realm's required state. The gate
## demands specific channels reach that state and `cultivate` never touches
## meridians, so without this button the qi path cannot advance (ADR 0043). The
## gate is read from the facade, never from the realm seed: that is a module
## internal, and every facade here is already at its method cap.
func act_train_next_channel() -> bool:
	if _actor == null:
		return false
	var live := QiCultivationApi.panel_state(_actor)
	var target_state := String(live.get("required_channel_state", ""))
	if target_state.is_empty():
		set_message("No qi realm profile", TONE_ERROR)
		refresh()
		return false
	var candidates: Array[StringName] = []
	for meridian_id in live.get("required_channels", []):
		candidates.append(StringName(meridian_id))
	# The gate names four channels but twenty exist; falling back to the rest keeps
	# the button useful once the required ones are done.
	for definition in MeridianDefaults.all():
		if not candidates.has(definition.id):
			candidates.append(definition.id)
	for meridian_id in candidates:
		var channel := _actor.meridians.get_meridian(meridian_id)
		if channel == null or channel.meets(target_state):
			continue
		if QiCultivationApi.train_channel(_actor, meridian_id):
			set_message("Trained %s" % meridian_id, TONE_OK)
			refresh()
			return true
	set_message("No channel left to train", TONE_ERROR)
	refresh()
	return false


## Heal a dantian scar or a burned channel with the realm's recovery item. A
## deviation is otherwise a permanent dead end on this path.
func act_recover() -> bool:
	if _actor == null:
		return false
	var repaired := QiCultivationApi.recover_next(_actor)
	set_message(
		"Repaired" if repaired else "Nothing damaged to repair", TONE_OK if repaired else TONE_ERROR
	)
	refresh()
	return repaired


## Cultivate is what a qi cultivator does first, and breakthrough is only
## reachable once the gate is met.
func focus_initial() -> void:
	_bind_nodes()
	var target := _button_name(&"cultivate") if _actor != null else ""
	if target.is_empty():
		target = _button_name(&"meditate")
	_focus_target = target
	var button := _find_button(target)
	if button != null and button.is_inside_tree():
		button.grab_focus()


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _actions != null:
		return
	_vitals = get_node_or_null("Layout/Vitals") as VBoxContainer
	_actions = get_node_or_null("%Actions") as ActionSet
	_channels = get_node_or_null("%Channels") as ChannelList
	_conditions_label = get_node_or_null("%ConditionLabel") as Label
	_realm_label = get_node_or_null("%RealmLabel") as Label
	for key in [&"qi", &"dantian", &"progress"]:
		_rows[key] = _find_row(key)
	if _actions != null and not _actions.action_requested.is_connected(_on_action):
		_actions.action_requested.connect(_on_action)


func _find_row(key: StringName) -> StatRow:
	if _vitals == null:
		return null
	var wanted := "%sRow" % String(key).to_pascal_case()
	for child in _vitals.get_children():
		var row := child as StatRow
		if row != null and String(row.name) == wanted:
			return row
	return null


func _set_row(key: StringName, state: Dictionary) -> void:
	var row: StatRow = _rows.get(key)
	if row != null:
		row.set_state(state)


func _vitals_summary() -> Dictionary:
	var out := {}
	for key in _rows:
		var row: StatRow = _rows[key]
		if row != null:
			out[String(key)] = row.summary()
	return out


func _on_action(action: StringName) -> void:
	match action:
		&"cultivate":
			act_cultivate()
		&"meditate":
			act_meditate()
		&"train_channel":
			act_train_next_channel()
		&"recover":
			act_recover()
		_:
			act_breakthrough()


func _button_name(action: StringName) -> String:
	return "%sButton" % String(action).to_pascal_case()


func _find_button(button_name: String) -> Button:
	if _actions == null or button_name.is_empty():
		return null
	for child in _actions.get_children():
		var found := _search_button(child, button_name)
		if found != null:
			return found
	return null


func _search_button(node: Node, button_name: String) -> Button:
	if node is Button and String(node.name) == button_name:
		return node as Button
	for child in node.get_children():
		var found := _search_button(child, button_name)
		if found != null:
			return found
	return null
