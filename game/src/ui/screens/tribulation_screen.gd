class_name TribulationScreen
extends UiScreen

## Heavenly-tribulation screen. A pure consumer of the `heavenly_tribulation`
## facade: it renders `HeavenlyTribulationApi.state()` and calls facade verbs,
## never module internals.
##
## It holds no game rule and no number format. The panel below owns every
## `%d/%d` and percentage, and the facade owns which realm is owed and how much
## of a fight this actor survives; this screen decides only which controls the
## player is offered, and reports what each one did.
##
## The one thing it words itself is the outcome line, because that is a screen's
## own report of its own action rather than a rendered value — and it now names the
## BLESSING a survived fight paid (F-7), because the panel's reward row and this
## line are the only two places a player ever hears what they earned.
##
## Why a screen of its own and not a panel on the body screen: the tribulation
## gate is on the shared ladder, so it belongs to whichever path is standing at
## the Immortal tier, not to the body path that happens to be first in the
## nav bar. A player who reaches R19 on qi must be able to fight the same fight.
##
## Contract: `summary()` is the testable surface, with the panel's summary nested
## under `tribulation`.

var _panel: TribulationPanel = null
var _begin_button: Button = null
var _fight_button: Button = null
var _verdict_button: Button = null
var _withdraw_button: Button = null
var _message_label: Label = null

# --- Read model ---------------------------------------------------------------


## Everything this screen displays. Primitives only; `{}` when no actor.
func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var live := HeavenlyTribulationApi.state(_actor)
	if live.is_empty():
		return {}
	var offered := _offered(live)
	var view := {
		"owed": bool(live.get("owed", false)),
		"target": String(live.get("target", "")),
		"target_name": String(live.get("target_name", "")),
		"bound": String(live.get("bound", "")),
		"has_record": bool(live.get("has_record", false)),
		"active": bool(live.get("active", false)),
		"decided": bool(live.get("decided", false)),
		"type": String(live.get("type", "")),
		"phase": String(live.get("phase", "")),
		"wave": int(live.get("wave", 0)),
		"max_waves": int(live.get("max_waves", 0)),
		"difficulty": float(live.get("difficulty", 0.0)),
		"outcome": String(live.get("outcome", "")),
		"chance": float(live.get("chance", 0.0)),
		"gate_open": bool(live.get("gate_open", false)),
	}
	view["actions"] = offered
	view["tribulation"] = _panel.summary() if _panel != null else {}
	return view


## Which of the four verbs the player is offered, read off the facade's state
## rather than off this screen's opinion of it.
##
## Begin is offered when a realm is owed and no fight is in the air — including
## after one was decided, because `Breakthrough.begin_tribulation` replaces a
## decided record so a survivor of R19 can never stand in for R20's fight.
func _offered(live: Dictionary) -> Dictionary:
	var owed := bool(live.get("owed", false))
	var active := bool(live.get("active", false))
	return {
		"begin": owed and not active,
		"fight": active,
		"verdict": active,
		"withdraw": active,
	}


# --- Render -------------------------------------------------------------------


## Re-read the facade and hand raw values down. The panel formats them.
func _refresh_view() -> void:
	_bind_nodes()
	if _panel == null:
		push_error("TribulationScreen: the scene must carry a panel named %TribulationPanel")
		return
	var live := HeavenlyTribulationApi.state(_actor) if _actor != null else {}
	_panel.set_state(live)
	var offered := _offered(live)
	_set_enabled(_begin_button, bool(offered["begin"]))
	_set_enabled(_fight_button, bool(offered["fight"]))
	_set_enabled(_verdict_button, bool(offered["verdict"]))
	_set_enabled(_withdraw_button, bool(offered["withdraw"]))
	_render_message()


## The outcome line. Styled by variation, never by a `theme_override_*`, and it
## reads the base's recorded message so there is one message and one style rule
## for the whole screen.
func _render_message() -> void:
	if _message_label == null:
		return
	_message_label.text = L.t(_message)
	match _tone:
		TONE_ERROR:
			_message_label.theme_type_variation = &"WarnLabel"
		TONE_OK:
			_message_label.theme_type_variation = &"OkLabel"
		_:
			_message_label.theme_type_variation = &"MetaLabel"


## A control no player can press is a dead control, so every button's enabled
## state is the facade's answer and never a default.
func _set_enabled(button: Button, offered: bool) -> void:
	if button != null:
		button.disabled = not offered


func _bind_nodes() -> void:
	super()
	if _begin_button != null:
		return
	_panel = get_node_or_null("%TribulationPanel") as TribulationPanel
	_begin_button = get_node_or_null("%BeginButton") as Button
	if _begin_button == null:
		return
	_fight_button = get_node_or_null("%FightButton") as Button
	_verdict_button = get_node_or_null("%VerdictButton") as Button
	_withdraw_button = get_node_or_null("%WithdrawButton") as Button
	_message_label = get_node_or_null("%MessageLabel") as Label
	_begin_button.pressed.connect(act_begin)
	_fight_button.pressed.connect(act_fight_wave)
	_verdict_button.pressed.connect(act_fight_to_verdict)
	_withdraw_button.pressed.connect(act_withdraw)


# --- Focus --------------------------------------------------------------------


## Focusing follows the fight: beginning it is the first thing to do, fighting the
## next wave is the first thing once it is under way, and withdrawing is the last
## resort. Records the target before grabbing, so a headless call still reports
## one.
func focus_initial() -> void:
	_bind_nodes()
	var live := HeavenlyTribulationApi.state(_actor) if _actor != null else {}
	var offered := _offered(live)
	var name := "BeginButton"
	if bool(offered["fight"]):
		name = "FightButton"
	elif not bool(offered["begin"]):
		name = "WithdrawButton"
	_focus_target = name
	var target := get_node_or_null("%%%s" % name) as Button
	if target != null and target.is_inside_tree():
		target.grab_focus()


## `ui_cancel` is left alone so `ScreenStack` pops; the fight is not something a
## stray key press should abandon.
func on_stack_input(_event: InputEvent) -> bool:
	return false


# --- Actions, callable headlessly as well as by the buttons -------------------


func act_begin() -> bool:
	if _actor == null:
		return false
	var result := HeavenlyTribulationApi.begin(_actor)
	_report(result, "The tribulation gathers", TONE_OK)
	return bool(result.get("ok", false))


func act_fight_wave() -> bool:
	if _actor == null:
		return false
	var result := HeavenlyTribulationApi.fight_wave(_actor)
	_report(result, "", TONE_OK)
	return bool(result.get("ok", false))


## Fight the whole tribulation in one press. The same `fight_wave` the button
## calls, driven to its verdict — so the one-wave screen and the one-press
## shortcut cannot diverge.
func act_fight_to_verdict() -> bool:
	if _actor == null:
		return false
	var result := HeavenlyTribulationApi.fight_to_verdict(_actor)
	_report(result, "", TONE_OK)
	return bool(result.get("ok", false))


func act_withdraw() -> bool:
	if _actor == null:
		return false
	var withdrawn := HeavenlyTribulationApi.withdraw(_actor)
	set_message(
		"Withdrew; the waves fought are forfeited" if withdrawn else "Nothing to withdraw from",
		TONE_OK if withdrawn else TONE_ERROR
	)
	refresh()
	return withdrawn


## Say what the fight did, not merely that a button was pressed. A refused verb
## names its reason rather than failing silently (ADR 0043).
##
## ## Why the BLESSING is handed down and not re-read
##
## `TribulationFight.fight_wave` returns `blessing` on every DECIDED result — the
## `TribulationBlessing.award` answer — and this function used to branch only on `ok` /
## `decided` / `survived`, so a survived fight told the player they survived and nothing
## about the permanent status they had just earned (F-7). It is rendered from HERE, on the
## action result, because that is the only place the award is observable: the award is
## once-guarded on the actor, so re-reading it later answers `already_rewarded` and a
## player who reopened this screen would watch their own reward turn into a refusal.
##
## `refresh()` repaints the panel from `state()`, which carries no blessing, so the
## hand-down happens BEFORE it — otherwise every repaint would silently erase the line it
## had just written.
func _report(result: Dictionary, ok_message: String, ok_tone: StringName) -> void:
	if not bool(result.get("ok", false)):
		set_message(String(result.get("reason", "refused")), TONE_ERROR)
		refresh()
		return
	if bool(result.get("decided", false)):
		_show_blessing(result)
		if bool(result.get("survived", false)):
			set_message(_survived_message(), TONE_OK)
		else:
			set_message("The tribulation broke you; repair the body and fight again", TONE_ERROR)
		refresh()
		return
	set_message(ok_message, ok_tone)
	refresh()


## Hand the panel the award, or clear the line when there is none to report.
##
## The key is ABSENT while a fight is still in the air (that is the refusal shape
## `_refused` returns) and PRESENT on every decided result, so "no key" is a real answer
## rather than a missing field. Both are routed through the panel, which owns the wording.
func _show_blessing(result: Dictionary) -> void:
	if _panel == null:
		return
	if not result.has("blessing"):
		_panel.show_blessing({})
		return
	_panel.show_blessing(result["blessing"] as Dictionary)


## The survival line, with the blessing named when one was paid.
##
## "Survived the tribulation" alone was the defect: the gate opening is a fact the player
## can see on the panel, and the thing they cannot see anywhere else is WHICH blessing
## they now carry. The id is appended rather than replacing the sentence, so the existing
## wording — and any test reading it — keeps working.
func _survived_message() -> String:
	var blessing := _panel.blessing_summary() if _panel != null else {}
	var status_id := String(blessing.get("id", ""))
	if not bool(blessing.get("paid", false)) or status_id.is_empty():
		return L.t("LOC_UI_SCREENS_E1D46249B9")
	return L.t("LOC_UI_SCREENS_1276CDB5BA") % status_id.replace("_", " ")
