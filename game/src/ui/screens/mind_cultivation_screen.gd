class_name MindCultivationScreen
extends UiScreen

## Mind-cultivation screen (ADR 0038/0042). A pure consumer of the
## `mind_cultivation` facade: it renders `MindCultivationApi.summary()` +
## `preview()` and calls facade actions, never module internals.
##
## The facade names the realm `rank`; the shared screen vocabulary is `realm`, so
## this screen normalizes on the way in. The sea of consciousness gets its own
## rows because clarity, purity and turbulence are the mind path's vitals.
##
## Contract: `summary()` is the testable surface, with child panel summaries
## nested under their own key.

const ROWS := [&"mind_power", &"clarity", &"purity", &"turbulence"]

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
	var live := MindCultivationApi.summary(_actor)
	if live.is_empty() or not bool(live.get("has_path", false)):
		return {}
	var preview := MindCultivationApi.preview(_actor)
	var view := {
		"realm": live.get("rank", ""),
		"display_name": live.get("display_name", ""),
		"progress": live.get("progress", 0.0),
		"comprehension": live.get("comprehension", 0.0),
		"mind_power": live.get("mind_power", 0.0),
		"mind_power_max": live.get("mind_power_max", 0.0),
		"sea_tier": live.get("sea_tier", ""),
		"clarity": live.get("clarity", 0.0),
		"purity": live.get("purity", 0.0),
		"turbulence": live.get("turbulence", 0.0),
		"trained_stage": live.get("trained_stage", 0),
		"channels": _channel_entries(live),
		"target": preview.get("target", ""),
		"can_act": bool(preview.get("ready", false)),
		"chance": preview.get("chance", 0.0),
		"unmet": preview.get("conditions", []),
		"costs": preview.get("costs", {}),
		"steps": _steps(),
	}
	view["vitals"] = _vitals_summary()
	view["actions"] = _actions.summary() if _actions != null else {}
	if _channels != null:
		view["channel_list"] = _channels.summary()
	return view


## The mind facade reports channels as dictionaries and already marks the ones its
## gate applies to, so this only normalizes them for the row. The screen must not
## reach for the realm seed: that is a module internal (ADR 0043).
func _channel_entries(live: Dictionary) -> Array:
	var out: Array = []
	for entry in live.get("channels", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		(
			out
			. append(
				{
					"id": String(entry.get("id", "")),
					"name": String(entry.get("name", entry.get("id", ""))),
					"state": String(entry.get("state", "unknown")),
					"refinement": int(entry.get("refinement", 0)),
					"injured": bool(entry.get("injured", false)),
					"required": bool(entry.get("required", false)),
				}
			)
		)
	return out


## Re-read the facade and hand raw values down. The panels own every format.
func _refresh_view() -> void:
	_bind_nodes()
	var live := MindCultivationApi.summary(_actor) if _actor != null else {}
	var on_path := not live.is_empty() and bool(live.get("has_path", false))
	var preview := MindCultivationApi.preview(_actor) if on_path else {}
	_set_row(
		&"mind_power",
		{
			"name": "Mind power",
			"current": live.get("mind_power", 0.0),
			"maximum": live.get("mind_power_max", 0.0),
			"mode": StatRow.MODE_BAR,
		}
	)
	_set_row(
		&"clarity",
		{
			"name": "Clarity",
			"current": live.get("clarity", 0.0),
			"maximum": 1.0,
			"decimals": 2,
			"mode": StatRow.MODE_BAR,
		}
	)
	_set_row(
		&"purity",
		{
			"name": "Purity",
			"current": live.get("purity", 0.0),
			"maximum": 1.0,
			"decimals": 2,
			"mode": StatRow.MODE_BAR,
		}
	)
	# Turbulence is the mind path's own vitals and gates every other action, so it
	# gets a row rather than living only in `summary()` (ADR 0043 audit).
	_set_row(
		&"turbulence",
		{
			"name": "Turbulence",
			"current": live.get("turbulence", 0.0),
			"maximum": 1.0,
			"decimals": 2,
			"mode": StatRow.MODE_BAR,
		}
	)
	if _actions != null:
		var ready := bool(preview.get("ready", false))
		(
			_actions
			. set_state(
				{
					"actions":
					[
						&"cultivate",
						&"meditate",
						&"train_channel",
						&"strengthen_sea",
						&"strengthen_anchor",
						&"breakthrough",
					],
					"labels":
					{
						"cultivate": "Cultivate",
						"meditate": "Meditate",
						"train_channel": "Train Channel",
						"strengthen_sea": "Strengthen Sea",
						"strengthen_anchor": "Strengthen Anchor",
						"breakthrough": "Breakthrough",
					},
					"enabled":
					{
						"cultivate": on_path,
						"meditate": on_path,
						# The gate demands channels at `required_channel_state`; without this
						# button the mind path cannot satisfy its own entry rule (ADR 0043).
						"train_channel": on_path,
						"strengthen_sea": on_path,
						# Anchors only exist at the Immortal tier, so the button is offered
						# from there up rather than dead on every early realm.
						"strengthen_anchor": on_path and _at_immortal_tier(),
						"breakthrough": ready,
					},
					"primary": &"breakthrough",
					"message": _message,
					"tone": _tone,
				}
			)
		)
	_render_conditions(preview, on_path)
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
	_render_realm(live, preview, on_path)


## True once the actor has reached the Immortal tier, where anchors exist at all.
## The path id comes from `PathState`, not from a module's internal constant, so
## the screen stays a facade-only consumer.
func _at_immortal_tier() -> bool:
	if _actor == null:
		return false
	var state := _actor.path(PathState.MIND)
	if state == null:
		return false
	return RealmDefaults.ladder().index_of(state.rank_id) >= Breakthrough.IMMORTAL_REALM_THRESHOLD


## The unmet list is how a player knows what to do next. It was computed and
## discarded here (ADR 0043 audit).
func _render_conditions(preview: Dictionary, on_path: bool) -> void:
	if _conditions_label == null:
		return
	if not on_path:
		_conditions_label.text = ""
		return
	var unmet: Array = preview.get("conditions", [])
	if unmet.is_empty():
		_conditions_label.text = "Conditions: READY"
		_conditions_label.theme_type_variation = &"OkLabel"
		return
	var costs: Dictionary = preview.get("costs", {})
	var cost_line := ""
	if not costs.is_empty():
		var ids: Array[String] = []
		for key in costs:
			ids.append("%s x%d" % [key, int(costs[key])])
		cost_line = " | Needs: %s" % ", ".join(ids)
	_conditions_label.text = "Conditions: %s%s" % [", ".join(unmet), cost_line]
	_conditions_label.theme_type_variation = &"MetaLabel"


## The realm line the scene declares but used to leave at its placeholder text.
func _render_realm(live: Dictionary, preview: Dictionary, on_path: bool) -> void:
	if _realm_label == null:
		return
	if not on_path:
		_realm_label.text = "Realm: none"
		return
	_realm_label.text = (
		"Realm: %s -> %s"
		% [
			live.get("rank", ""),
			preview.get("target", ""),
		]
	)


# --- Actions, callable headlessly as well as by the buttons ----------------


func act_cultivate() -> void:
	if _actor == null:
		return
	MindCultivationApi.cultivate(_actor)
	set_message("Cultivated the mind", TONE_OK)
	refresh()


func act_meditate() -> void:
	if _actor == null:
		return
	MindCultivationApi.meditate(_actor)
	set_message("Meditated; the sea steadies", TONE_OK)
	refresh()


func act_strengthen_sea() -> bool:
	if _actor == null:
		return false
	var trained := MindCultivationApi.strengthen_sea(_actor)
	set_message(
		"Sea strengthened" if trained else "Sea catalyst absent", TONE_OK if trained else TONE_ERROR
	)
	refresh()
	return trained


func act_breakthrough() -> bool:
	if _actor == null:
		return false
	var advanced := MindCultivationApi.try_breakthrough(_actor)
	if advanced:
		set_message("Broke through", TONE_OK)
	else:
		set_message("The attempt deviated; meditate and try again", TONE_ERROR)
	refresh()
	return advanced


## Train the first channel that has not reached the gate's required state. The
## mind entry rule demands channels at `required_channel_state` and nothing else
## on this path trains them, so without this the path cannot advance (ADR 0043).
## The gate itself is read from the facade's published `required_channels` /
## `required_channel_state`, never from the realm seed, which is a module internal.
func act_train_next_channel() -> bool:
	if _actor == null:
		return false
	var live := MindCultivationApi.summary(_actor)
	var target_state := String(live.get("required_channel_state", ""))
	if target_state.is_empty():
		set_message("No mind realm profile", TONE_ERROR)
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
		if MindCultivationApi.train_channel(_actor, meridian_id):
			set_message("Trained %s" % meridian_id, TONE_OK)
			refresh()
			return true
	set_message("No channel left to train", TONE_ERROR)
	refresh()
	return false


## Reinforce the anchor an earlier high-tier breakthrough committed. Below the
## Immortal tier there is no anchor, so this reports why rather than failing
## silently (ADR 0043).
func act_strengthen_anchor() -> bool:
	if _actor == null:
		return false
	if not _at_immortal_tier():
		set_message("No anchor below the Immortal tier", TONE_ERROR)
		refresh()
		return false
	var strengthened := MindCultivationApi.strengthen_anchor(_actor)
	set_message(
		"Anchor reinforced" if strengthened else "Anchor catalyst absent",
		TONE_OK if strengthened else TONE_ERROR
	)
	refresh()
	return strengthened


## Meditation is the mind path's first move: it clears the turbulence that blocks
## every other action, so it is the landing spot.
func focus_initial() -> void:
	_bind_nodes()
	var target := _button_name(&"meditate") if _actor != null else ""
	_focus_target = target
	var button := _find_button(target)
	if button != null and button.is_inside_tree():
		button.grab_focus()


# --- Plumbing ---------------------------------------------------------------


## The mind facade owns its step sizes, so the screen reports the facade's
## numbers rather than inventing its own (ADR 0038: steps live in the facade).
func _steps() -> Dictionary:
	return {
		"cultivate": MindCultivationApi.CULTIVATE_STEP,
		"meditate": MindCultivationApi.MEDITATE_STEP,
	}


func _bind_nodes() -> void:
	if _actions != null:
		return
	_vitals = get_node_or_null("Layout/Vitals") as VBoxContainer
	_actions = get_node_or_null("%Actions") as ActionSet
	_channels = get_node_or_null("%Channels") as ChannelList
	_conditions_label = get_node_or_null("%ConditionLabel") as Label
	_realm_label = get_node_or_null("%RealmLabel") as Label
	for key in ROWS:
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
		&"strengthen_sea":
			act_strengthen_sea()
		&"train_channel":
			act_train_next_channel()
		&"strengthen_anchor":
			act_strengthen_anchor()
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
