class_name BodyCultivationPanel
extends PanelContainer

## Body-cultivation screen (ADR 0028). A pure consumer of the
## `body_cultivation` facade: it renders `BodyCultivationApi.panel_state()` and
## calls facade actions, never module internals. Widgets are declared in
## `body_cultivation_panel.tscn`, not built here.
##
## The screen holds no formatting of its own: every number is rendered by the
## `BodyVitalsPanel` row below it, and the step sizes come from the facade's
## `steps`. That keeps the headless contract in one place.
##
## Contract: `summary()` is the testable surface, with the child panel's summary
## nested under `vitals`. Headless tests assert it instead of pixels.

signal world_map_requested

const TONE_ERROR := &"error"
const TONE_OK := &"ok"

var _actor: Actor
var _vitals: BodyVitalsPanel = null
var _world_map_button: Button = null
var _cultivate_button: Button = null
var _meditate_button: Button = null
var _strengthen_button: Button = null
var _recover_button: Button = null
var _breakthrough_button: Button = null
var _message_label: Label = null
var _message: String = ""
var _tone: StringName = &""
var _focus_target: String = ""


func _ready() -> void:
	_bind_nodes()
	refresh()


func setup(actor: Actor) -> void:
	_actor = actor
	refresh()


## Report an action's outcome. This screen predates `UiScreen`, so it carries its
## own message line rather than inheriting one; without it a refused `strengthen`
## or `recover` returned false and the player saw nothing at all (ADR 0043).
func set_message(message: String, tone: StringName = &"") -> void:
	_message = message
	_tone = tone
	if _message_label != null:
		_message_label.text = _message
		_message_label.theme_type_variation = _tone_variation()


func _tone_variation() -> StringName:
	match _tone:
		TONE_ERROR:
			return &"WarnLabel"
		TONE_OK:
			return &"OkLabel"
		_:
			return &"MetaLabel"


## Everything this screen displays. Primitives only; `{}` when no actor.
func summary() -> Dictionary:
	if _actor == null:
		return {}
	var view := BodyCultivationApi.panel_state(_actor)
	if view.is_empty():
		return {}
	view["vitals"] = _vitals.summary() if _vitals != null else {}
	view["focus_target"] = _focus_target
	view["actions"] = _action_state(view)
	view["message"] = _message
	view["tone"] = String(_tone)
	return view


func refresh() -> void:
	_bind_nodes()
	if _vitals == null or _cultivate_button == null:
		# A screen missing a widget is a scene wiring error, not a state to render.
		push_error("BodyCultivationPanel: scene is missing %VitalsPanel or %CultivateButton")
		return
	var live := BodyCultivationApi.panel_state(_actor) if _actor != null else {}
	_vitals.set_state(live)
	var ready: bool = bool(live.get("ready", false))
	_cultivate_button.disabled = live.is_empty()
	_meditate_button.disabled = live.is_empty()
	_strengthen_button.disabled = live.is_empty()
	_recover_button.disabled = live.is_empty()
	_breakthrough_button.disabled = not ready


## ScreenStack lifecycle: focus belongs to the stack, never to `_ready()`.
func on_screen_shown() -> void:
	focus_initial()


func focus_initial() -> void:
	_bind_nodes()
	var view := BodyCultivationApi.panel_state(_actor) if _actor != null else {}
	var live := not view.is_empty()
	# Cultivate is always the first thing a body cultivator does; breakthrough is
	# only reachable once everything else is prepared.
	var name := "CultivateButton" if live else "MeditateButton"
	_focus_target = name
	var target := _button(name)
	if target != null and target.is_inside_tree():
		target.grab_focus()


# --- Actions, callable headlessly as well as by the buttons ----------------


## One cultivation step, at the size the facade publishes.
func act_cultivate() -> void:
	if _actor == null:
		return
	var moved := BodyCultivationApi.cultivate(_actor, float(_steps().get("cultivate", 25.0)))
	set_message(
		"Cultivated the body" if moved else "The body will not take more",
		TONE_OK if moved else TONE_ERROR
	)
	refresh()


func act_meditate() -> void:
	if _actor == null:
		return
	var raised := BodyCultivationApi.meditate(_actor, float(_steps().get("meditate", 1.0)))
	set_message(
		"Meditated" if raised else "Meditation had no effect", TONE_OK if raised else TONE_ERROR
	)
	refresh()


func act_strengthen() -> bool:
	if _actor == null:
		return false
	var trained := BodyCultivationApi.strengthen_next(_actor)
	set_message(
		"Channel trained" if trained else "No channel elixir to spend",
		TONE_OK if trained else TONE_ERROR
	)
	refresh()
	return trained


func act_breakthrough() -> bool:
	if _actor == null:
		return false
	var advanced := BodyCultivationApi.attempt_breakthrough(_actor)
	if advanced:
		set_message("Broke through", TONE_OK)
	else:
		set_message("The attempt deviated; recover and try again", TONE_ERROR)
	refresh()
	return advanced


## Repair a deviation: clears a jammed huyệt or heals a torn channel using the
## realm's recovery item. False means nothing was damaged, or the item was absent.
func act_recover() -> bool:
	if _actor == null:
		return false
	var repaired := BodyCultivationApi.recover_next(_actor)
	set_message(
		"Repaired" if repaired else "Nothing damaged to repair", TONE_OK if repaired else TONE_ERROR
	)
	refresh()
	return repaired


func _steps() -> Dictionary:
	var view := BodyCultivationApi.panel_state(_actor) if _actor != null else {}
	return view.get("steps", {})


## Which actions the screen offers, given the facade view the screen is rendering.
## Breakthrough needs the gate; the training verbs need only an actor.
func _action_state(view: Dictionary) -> Dictionary:
	var live := not view.is_empty()
	return {
		"cultivate": live,
		"meditate": live,
		"strengthen": live,
		"recover": live,
		"breakthrough": bool(view.get("ready", false)),
	}


## Resolve the scene's widgets on first use rather than in `@onready`: the
## headless suite drives this screen before a scene tree exists, so `_ready()` is
## not a dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	if _cultivate_button != null:
		return
	_vitals = get_node_or_null("%VitalsPanel") as BodyVitalsPanel
	_message_label = get_node_or_null("%MessageLabel") as Label
	_cultivate_button = get_node_or_null("%CultivateButton") as Button
	if _cultivate_button == null:
		return
	_meditate_button = get_node_or_null("%MeditateButton") as Button
	_strengthen_button = get_node_or_null("%StrengthenButton") as Button
	_recover_button = get_node_or_null("%RecoverButton") as Button
	_breakthrough_button = get_node_or_null("%BreakthroughButton") as Button
	_world_map_button = get_node_or_null("%WorldMapButton") as Button
	_cultivate_button.pressed.connect(act_cultivate)
	_meditate_button.pressed.connect(act_meditate)
	_strengthen_button.pressed.connect(_on_strengthen)
	_recover_button.pressed.connect(_on_recover)
	_breakthrough_button.pressed.connect(_on_breakthrough)
	if _world_map_button != null:
		_world_map_button.pressed.connect(act_world_map)


func _button(name: String) -> Button:
	match name:
		"CultivateButton":
			return _cultivate_button
		"MeditateButton":
			return _meditate_button
		"StrengthenButton":
			return _strengthen_button
		"RecoverButton":
			return _recover_button
		_:
			return _breakthrough_button


func _on_strengthen() -> void:
	act_strengthen()


func _on_recover() -> void:
	act_recover()


func _on_breakthrough() -> void:
	act_breakthrough()


func act_world_map() -> void:
	world_map_requested.emit()
