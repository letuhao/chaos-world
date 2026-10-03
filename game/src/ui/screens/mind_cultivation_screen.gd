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
## The ONE action that is not a facade call is `act_ascend`, for the reason body
## gives and in the same shape (ADR 0041): the ascent belongs to no single path —
## every path carries the same `AscensionState` — so no facade serves it and `ui`
## may call `core` directly. Its read model is this path's own `gates.ascent`
## block, so nothing here restates the gate: the wording the conditions line
## already shows is `WorldAnchor.ascension_unmet`'s, verbatim (ADR 0034). Without
## this verb that clause was a gate a player could read and never satisfy.
##
## Contract: `summary()` is the testable surface, with child panel summaries
## nested under their own key.

const ROWS := [&"mind_power", &"clarity", &"purity", &"turbulence", &"trained_stage"]

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
	view["ascent"] = _ascent_view(preview)
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


## The trained-stage row names the anchor milestone the actor has reached. Below
## the Immortal tier there is no anchor, so the row says the sea's stage instead.
##
## The NOUN only: the screen hands `trained_stage` down as `current` and
## `StatRow.value_text` formats it. Printing the figure here too showed the stage
## twice, and only the panel's copy went through the one formatting rule.
func _stage_label() -> String:
	return "Anchor stage" if _at_immortal_tier() else "Sea stage"


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
	# `trained_stage` is what `strengthen_anchor` advances and what the anchor gate
	# reads, so a row shows it; without one the button's effect is invisible. The
	# name carries the noun; the row formats the figure.
	_set_row(
		&"trained_stage",
		{
			"name": _stage_label(),
			"current": live.get("trained_stage", 0),
			"maximum": 0.0,
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
						&"recover",
						&"strengthen_sea",
						&"strengthen_anchor",
						&"ascend",
						&"breakthrough",
					],
					"labels":
					{
						"cultivate": "Cultivate",
						"meditate": "Meditate",
						"train_channel": "Train Channel",
						# Qi's own wording, so the two screens offering the same verb
						# name it identically.
						"recover": "Recover",
						"strengthen_sea": "Strengthen Sea",
						"strengthen_anchor": "Strengthen Anchor",
						# Body's own wording, so the two screens offering the same
						# action name it identically.
						"ascend": "Walk Ascent",
						"breakthrough": "Breakthrough",
					},
					"enabled":
					{
						"cultivate": on_path,
						"meditate": on_path,
						# The gate demands channels at `required_channel_state`; without this
						# button the mind path cannot satisfy its own entry rule (ADR 0043).
						"train_channel": on_path,
						# Live on every realm, not only a wounded one. The burn is priced by
						# the realm's recovery elixir (ADR 0031), so the commonest refusal is
						# "you have not bought it" -- and a control that is greyed out until
						# the burn exists cannot say so (ADR 0043: a verb that returns false
						# and says nothing is indistinguishable from a button wired to
						# nothing). Qi's recover is keyed the same way.
						"recover": on_path,
						"strengthen_sea": on_path,
						# Anchors only exist at the Immortal tier, so the button is offered
						# from there up rather than dead on every early realm.
						"strengthen_anchor": on_path and _at_immortal_tier(),
						# The ascent the tier gate is owed. Declared on every realm and
						# live only while one is owed and unwalked, which is the same
						# conjunction body offers it under: a control that appears out of
						# nowhere when the gate opens is a gate the player never saw
						# arriving.
						"ascend": on_path and _ascend_offered(preview),
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


# --- The ascent ---------------------------------------------------------------
#
# Read from the facade's `gates.ascent` block, which is DATA and not a verb: the
# ascent itself is `WorldAnchor.ascend`, a core entry point `ui/` may call directly
# (ADR 0041), so nothing here grows the mind facade's twelve-method surface.


## A player may walk the ascent only while one is owed AND unfinished — the same
## conjunction `BodyCultivationPanel._ascend_offered` applies, so the two screens
## cannot disagree about when the control is live.
##
## `required` is core's own answer to "is the ascent this realm's gate at all", and
## `steps_remaining` is what is left to walk, so the pair is the rule without this
## screen re-deriving it. An actor below the Transcendent tier fails `required`
## because `ascension_ok` is true for every target at or below
## `WorldAnchor.COMMIT_MICRO`, so nothing here is conditional on the tier.
func _ascend_offered(preview: Dictionary) -> bool:
	if preview.is_empty():
		return false
	var gates: Dictionary = preview.get("gates", {})
	var ascent: Dictionary = gates.get("ascent", {})
	return bool(ascent.get("required", false)) and int(ascent.get("steps_remaining", 0)) > 0


## The ascent as this screen reports it, under the key body publishes it under so
## one question is answered one way across both screens.
##
## `steps` is the walk still TO DO, which is the quantity core's own `outstanding`
## sentence counts, and `outstanding` is that sentence verbatim rather than a
## restatement of the rule it names (ADR 0034). There is no `steps_total` here on
## purpose: body reads the whole walk's length off its facade, and naming core's
## constant a second time on the UI side is a number two places can drift. The
## total is inside `outstanding` either way.
##
## `outstanding` is published as core states it, including `WorldAnchor.NO_ASCENT`.
## That sentinel is core declining to state a requirement — there is no
## `AscensionState` yet, so there is nothing to walk — and the screen keeps it in
## its read model rather than filtering it, so the two screens agree on the raw
## value and neither hides data a caller reads. `offered` is what the button is
## keyed on, and it is false for the sentinel, so neither screen renders it as a
## gate a player must satisfy.
func _ascent_view(preview: Dictionary) -> Dictionary:
	var gates: Dictionary = preview.get("gates", {})
	var ascent: Dictionary = gates.get("ascent", {})
	return {
		"required": bool(ascent.get("required", false)),
		"steps": int(ascent.get("steps_remaining", 0)),
		"met": bool(ascent.get("value", false)),
		"outstanding": String(ascent.get("outstanding", "")),
		"offered": _ascend_offered(preview),
	}


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
	# `anchor_stage` is published by the facade for exactly this case: at the
	# Immortal tier the gate is an anchor, and a player told only "not ready"
	# cannot tell an anchor they owe from one they have already earned.
	var anchor_line := ""
	var stage := String(preview.get("anchor_stage", ""))
	if not stage.is_empty():
		anchor_line = " | Anchor: %s" % stage
	_conditions_label.text = "Conditions: %s%s%s" % [", ".join(unmet), cost_line, anchor_line]
	_conditions_label.theme_type_variation = &"MetaLabel"


## The realm line, using the realm's display name when the facade publishes one:
## `qi_refining` is a machine id and `Qi Refining` is what a player reads.
func _render_realm(live: Dictionary, preview: Dictionary, on_path: bool) -> void:
	if _realm_label == null:
		return
	if not on_path:
		_realm_label.text = "Realm: none"
		return
	var current := String(live.get("display_name", ""))
	if current.is_empty():
		current = String(live.get("rank", ""))
	var target := String(preview.get("target", ""))
	_realm_label.text = (
		"Realm: %s" % current if target.is_empty() else "Realm: %s -> %s" % [current, target]
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
##
## The refusal names the PRICE. Every verb on this path is priced by a
## realm-authored consumable, so a player who has spent them reaches the bottom of
## this loop having done nothing, and the old terminal message told them there was
## no channel left to train. That is the one answer that cannot be true: the loop
## got here because a channel did NOT meet `required_channel_state`, so there IS one
## left. What is missing is the elixir that pays for it, and a screen that says
## "nothing to do" sends the player looking for content that exists.
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
	# Read BEFORE the call: `train_channel` on a burn spends the recovery elixir and
	# repairs the channel, so an injured flag read afterwards would be the answer to
	# a question about a different actor state. `injured` is the discriminator between
	# the two prices (ADR 0141): `training_item` walks a healthy channel,
	# `recovery_item` undoes a burned one.
	var owed := 0
	var price := ""
	for meridian_id in candidates:
		var channel := _actor.meridians.get_meridian(meridian_id)
		if channel == null or channel.meets(target_state):
			continue
		owed += 1
		var burned := channel.is_injured()
		if MindCultivationApi.train_channel(_actor, meridian_id):
			set_message("Trained %s" % meridian_id, TONE_OK)
			refresh()
			return true
		if price.is_empty():
			price = "recovery elixir" if burned else "channel elixir"
	if price.is_empty():
		set_message("No channel left to train", TONE_ERROR)
	else:
		# The elixir's ID is authored in the realm seed, which is a module internal
		# this screen may not read (ADR 0043), so the price is named by its ROLE --
		# the word the authored content and its acquisition are indexed by -- and not
		# by an id restated here and free to drift out of step with the seeds.
		set_message("%s absent; %d channel(s) still owed" % [price, owed], TONE_ERROR)
	refresh()
	return false


## Close the first burned channel with the realm's recovery elixir.
##
## This is the verb every realm authors a `recovery_item` for (ADR 0031) and the
## only one that spends it. `meditate` calms the sea and `train_channel` hands a
## burn to `recover` (ADR 0141), so the burn WAS repairable -- but through a verb
## whose own price is a different elixir, and with no control on this screen a
## player could not spend the authored one at all. Thirty authored elixirs had no
## way to leave the inventory, and the sea's clarity gate a burn blocks had no way
## to be reopened.
##
## The refusal separates the two things `recover_next` reports with one bool. "There
## is no burn" sends the player elsewhere; "you owe the realm's recovery elixir" is
## a purchase to make. Reporting both as one line (ADR 0043 -- a verb that returns
## false and says nothing is indistinguishable from a button wired to nothing) sent
## the player hunting for a wound that did not exist.
func act_recover() -> bool:
	if _actor == null:
		return false
	var repaired := MindCultivationApi.recover_next(_actor)
	set_message(
		"Repaired a burned channel" if repaired else _recovery_refusal(),
		TONE_OK if repaired else TONE_ERROR
	)
	refresh()
	return repaired


## What a refused recovery means, read from the same scan `recover_next` performs:
## a burned channel on the network is a wound the elixir would close, so its
## absence is the price. A channel that is merely not yet unlocked is not a wound,
## which is why this counts through the network rather than off the facade's
## `channels` list -- that list reports an un-unlocked channel as injured, so it
## would answer "you owe an elixir" to a hero who has never been burned.
func _recovery_refusal() -> String:
	return "Recovery elixir absent" if _burned_channels() > 0 else "No burned channel to repair"


func _burned_channels() -> int:
	var burned := 0
	if _actor == null:
		return burned
	for definition in MeridianDefaults.all():
		var channel := _actor.meridians.get_meridian(definition.id)
		if channel != null and channel.is_injured():
			burned += 1
	return burned


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


## Walk ONE step of the Transcendent ascent.
##
## The only action here that is not a facade call, and deliberately so, for the
## reason body gives: the ascent belongs to no single path — every path carries the
## same `AscensionState` — so no facade serves it and `core` is where the entry
## point lives (ADR 0041). Its gate is read from this path's facade rather than
## re-derived here, so this screen can never open a gate `Breakthrough.ascension_ok`
## would refuse.
##
## Both refusals read exactly as body's do, because they are the same action: a
## player who has learned one screen's wording meets the other (ADR 0043 — a verb
## that returns false and says nothing is indistinguishable from a button wired to
## nothing at all).
func act_ascend() -> bool:
	if _actor == null:
		return false
	if not _ascend_offered(MindCultivationApi.preview(_actor)):
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


## Meditation is the mind path's first move: it clears the turbulence that blocks
## every other action, so it is the landing spot. An owed ascent overrides it, for
## body's reason: once a tier gate has opened an ascent, walking it is the only
## thing left to do, and the screen already says so in its conditions line.
func focus_initial() -> void:
	_bind_nodes()
	var target := ""
	if _actor != null:
		var preview := MindCultivationApi.preview(_actor)
		target = _button_name(&"ascend") if _ascend_offered(preview) else _button_name(&"meditate")
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
		&"recover":
			act_recover()
		&"strengthen_anchor":
			act_strengthen_anchor()
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
