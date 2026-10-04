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
		"dantian_quality": live.get("dantian_quality", 0.0),
		"dantian_injured": live.get("dantian_injured", false),
		"channels": _channel_entries(live),
		"ascent": _ascent_view(live),
		"can_act": live.get("can_attempt", false),
		"chance": live.get("chance", 0.0),
		"unmet": live.get("unmet", []),
		"costs": live.get("costs", {}),
		"steps": _steps(),
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
			# The tier and the injury are what the `recover` button acts on, so they
			# are rendered rather than left in the summary where no eye sees them
			# (ADR 0043 audit).
			"name": _dantian_label(live),
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


## The dantian row says when the core is scarred. An injury is a hard
## breakthrough blocker, and `recover` is the action that clears it, so the row has
## to say so.
##
## It used to name the dantian's tier here, over a `dantian_tier` key the facade
## published for a ladder nothing read and the realm line already prints (ADR 0180).
func _dantian_label(live: Dictionary) -> String:
	var name := "Dantian quality"
	if bool(live.get("dantian_injured", false)):
		name += " SCARRED"
	return name


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
						&"ascend",
						&"breakthrough",
					],
					"labels":
					{
						"cultivate": "Cultivate",
						"meditate": "Meditate",
						"train_channel": "Train Channel",
						"recover": "Recover",
						"ascend": "Walk Ascent",
						"breakthrough": "Breakthrough",
					},
					"enabled":
					{
						"cultivate": not live.is_empty(),
						"meditate": not live.is_empty(),
						"train_channel": not live.is_empty() and has_gate,
						"recover": not live.is_empty(),
						"ascend": _ascend_offered(live),
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
	QiCultivationApi.cultivate(_actor, float(_steps()["cultivate"]))
	set_message("Cultivated qi", TONE_OK)
	refresh()


func act_meditate() -> void:
	if _actor == null:
		return
	QiCultivationApi.meditate(_actor, float(_steps()["meditate"]))
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


## Train the first channel that still owes the gate — state OR depth — and name the
## one it trained.
##
## SELECTION IS THE FACADE'S, not this screen's. It used to walk the channels here
## and skip on `channel.meets(required_channel_state)`, which is state-only BY
## DESIGN (`MeridianState.meets` is a rank comparison plus the injury flag), so from
## the first realm whose demand is pure depth every channel was skipped, every press
## did nothing, and `QiTraining.refine_meridian` was never reached: the depth half of
## the gate was reachable in tests and dead in play (ADR 0158). `train_next_channel`
## is the one verb that answers "which channel is next", and it reads `channel_met`,
## so this screen cannot hold a second opinion about the gate (ADR 0044).
##
## The gate is read from the facade, never from the realm seed: that is a module
## internal, and every facade here is already at its method cap.
##
## The refusal names the PRICE (ADR 0150): the old terminal message told a player who
## had merely spent their elixirs that there was no channel left to train, and that
## is the one answer that cannot be true — the press got here because a channel still
## owes the gate. `owed_channels` / `training_price` are read BEFORE the call, because
## `train_channel` on a burn hands it to `recover` and repairs the channel, so a burn
## read afterwards would answer a question about a different actor state (ADR 0141).
## They are published rather than recomputed here because counting them means walking
## `channel_met`, and a reassembled gate is the ADR 0044 defect this loop already was.
func act_train_next_channel() -> bool:
	if _actor == null:
		return false
	var live := QiCultivationApi.panel_state(_actor)
	if String(live.get("required_channel_state", "")).is_empty():
		set_message("No qi realm profile", TONE_ERROR)
		refresh()
		return false
	var owed := int(live.get("owed_channels", 0))
	var price := String(live.get("training_price", ""))
	var trained := QiCultivationApi.train_next_channel(_actor)
	if not trained.is_empty():
		set_message("Trained %s" % trained, TONE_OK)
		refresh()
		return true
	if owed <= 0:
		set_message("No channel left to train", TONE_ERROR)
	else:
		# The elixir's ID is authored in the realm seed, which is a module internal
		# this screen may not read (ADR 0043), so the price is named by its ROLE --
		# the word the authored content and its acquisition are indexed by -- and not
		# by an id restated here and free to drift out of step with the seeds.
		set_message("%s absent; %d channel(s) still owed" % [_price_role(price), owed], TONE_ERROR)
	refresh()
	return false


## The facade names the elixir by role; the sentence is the screen's to word.
func _price_role(role: String) -> String:
	return "recovery elixir" if role == "recovery_elixir" else "channel elixir"


# --- The ascent ----------------------------------------------------------------
#
# Read from the facade's `ascent` block, which is DATA and not a verb: the ascent
# itself is `WorldAnchor.ascend`, a core entry point `ui/` may call directly
# (ADR 0041), so nothing here grows the qi facade. Body and mind publish the same
# block under the same keys and walk it the same way, so the three screens cannot
# disagree about when the control is live — or about whether the ascent is reachable
# at all, which on this path it was not: the verb existed, was proven, and had no
# caller here, so `ascension_ok` stayed shut and R29 and R30 were unreachable by play
# (BL-0693).


## A player may walk the ascent only while one is owed AND unfinished — the same
## conjunction body and mind apply, so the three screens cannot disagree. Below the
## Transcendent tier `required` is false, so the control is never a dead button.
func _ascend_offered(live: Dictionary) -> bool:
	if live.is_empty():
		return false
	var ascent: Dictionary = live.get("ascent", {})
	return bool(ascent.get("required", false)) and int(ascent.get("steps", 0)) > 0


## The ascent as this screen reports it, under the key body publishes it under so one
## question is answered one way across all three screens. `outstanding` is core's own
## sentence verbatim rather than a restatement of the rule it names (ADR 0034).
func _ascent_view(live: Dictionary) -> Dictionary:
	var ascent: Dictionary = live.get("ascent", {})
	return {
		"required": bool(ascent.get("required", false)),
		"steps": int(ascent.get("steps", 0)),
		"steps_total": int(ascent.get("steps_total", 0)),
		"met": bool(ascent.get("met", false)),
		"outstanding": String(ascent.get("outstanding", "")),
		"offered": _ascend_offered(live),
	}


## Walk ONE step of the Transcendent ascent.
##
## The only action here that is not a facade call, and deliberately so: the ascent
## belongs to no single path — every path carries the same `AscensionState` — so no
## facade serves it (ADR 0041). Its gate is read from the facade's `ascent` block
## rather than re-derived here, so this screen can never open a gate
## `Breakthrough.ascension_ok` would refuse.
func act_ascend() -> bool:
	if _actor == null:
		return false
	if not _ascend_offered(QiCultivationApi.panel_state(_actor)):
		set_message("No ascent is owed yet", TONE_ERROR)
		refresh()
		return false
	var stepped := WorldAnchor.ascend(_actor)
	set_message(
		"Walked a step of the ascent" if stepped else "The ascent will not open",
		TONE_OK if stepped else TONE_ERROR
	)
	refresh()
	return stepped


## Heal a dantian scar or a burned channel with the realm's recovery item. A
## deviation is otherwise a permanent dead end on this path.
func act_recover() -> bool:
	if _actor == null:
		return false
	var repaired := QiCultivationApi.recover_next(_actor)
	set_message(
		"Repaired" if repaired else _recovery_refusal(), TONE_OK if repaired else TONE_ERROR
	)
	refresh()
	return repaired


## What a refused recovery means, read from the facade's own injury flags rather
## than inferred from the `false` alone (ADR 0150).
##
## The two things a refusal can mean are forced apart here. A scar or a burn is a
## wound the recovery elixir would close, so a refusal with one present has
## exactly one remaining cause — the elixir. A refusal with none is "look
## elsewhere". Collapsing both into one sentence told a hero with a torn channel
## and no recovery elixir that there was "Nothing damaged to repair", which is the
## one answer that cannot be true.
func _recovery_refusal() -> String:
	# The two causes are forced apart. A wound IS pending and no elixir was carried,
	# so the answer is "no elixir" — actionable. Nothing is pending, so the answer is
	# "nothing to repair" — the actor should look elsewhere. Collapsing them into one
	# sentence told a hero with a torn channel and no elixir that there was "Nothing
	# damaged to repair", which is the one answer that cannot be true.
	return "No recovery elixir carried" if _damage_pending() else "Nothing damaged to repair"


## Whether the facade reports a wound the recovery elixir exists to close: the
## dantian scar, or any burned channel.
##
## Read through `panel_state` rather than the network, because the flags are DATA
## and a screen guessing at them would be the ADR 0034 restatement this program
## exists to avoid. `panel_state` lists only channels already on the network, so a
## meridian this realm has not unlocked contributes nothing — the filter Mind's
## own reader needs has no counterpart here.
func _damage_pending() -> bool:
	if _actor == null:
		return false
	var live := QiCultivationApi.panel_state(_actor)
	if live.is_empty():
		return false
	if bool(live.get("dantian_injured", false)):
		return true
	for entry in _channel_entries(live):
		if bool(entry.get("injured", false)):
			return true
	return false


## Cultivate is what a qi cultivator does first, and breakthrough is only
## reachable once the gate is met. An owed ascent is the only thing left to do once
## the tier gate has opened it, so it takes the landing spot — the same precedence
## body and mind give it.
func focus_initial() -> void:
	_bind_nodes()
	var live := QiCultivationApi.panel_state(_actor) if _actor != null else {}
	var target := _button_name(&"cultivate") if _actor != null else ""
	if target.is_empty():
		target = _button_name(&"meditate")
	if _ascend_offered(live):
		target = _button_name(&"ascend")
	_focus_target = target
	var button := _find_button(target)
	if button != null and button.is_inside_tree():
		button.grab_focus()


# --- Plumbing ---------------------------------------------------------------


## The facade owns its step sizes, so the screen reports the facade's numbers
## rather than inventing its own (ADR 0038: steps live in the facade).
func _steps() -> Dictionary:
	return {
		"cultivate": QiCultivationApi.CULTIVATE_STEP,
		"meditate": QiCultivationApi.MEDITATE_STEP,
	}


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
		&"ascend":
			act_ascend()
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
