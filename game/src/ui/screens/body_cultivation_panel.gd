class_name BodyCultivationPanel
extends PanelContainer

## Body-cultivation screen (ADR 0028). A pure consumer of the
## `body_cultivation` facade: it renders `BodyCultivationApi.panel_state()` and
## calls facade actions, never module internals. Widgets are declared in
## `body_cultivation_panel.tscn`, not built here.
##
## The screen holds no formatting of its own: every number is rendered by the
## `BodyVitalsPanel` row above it and the `BodyGrowthPanel` row below it, and the
## step sizes come from the facade's `steps`. That keeps the headless contract in
## one place.
##
## The ONE action that is not a facade call is `act_ascend`. The ascent belongs to
## no single path — every path carries the same `AscensionState` — so no facade
## serves it and `ui` may call `core` directly (ADR 0041). Its read model is still
## the facade's `ascent` block, so nothing here restates the gate: the wording on
## screen is `WorldAnchor.ascension_unmet`'s, verbatim (ADR 0034).
##
## Contract: `summary()` is the testable surface, with the child panel's summary
## nested under `vitals`, `growth` and `ascent`. Headless tests assert it instead
## of pixels.

signal world_map_requested

const TONE_ERROR := &"error"
const TONE_OK := &"ok"

var _actor: Actor
var _vitals: BodyVitalsPanel = null
var _growth: BodyGrowthPanel = null
var _ascent_row: StatRow = null
var _tier_gates_label: Label = null
var _world_map_button: Button = null
var _cultivate_button: Button = null
var _meditate_button: Button = null
var _strengthen_button: Button = null
var _recover_button: Button = null
var _breakthrough_button: Button = null
var _ascend_button: Button = null
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
	view["growth"] = _growth.summary() if _growth != null else {}
	view["ascent"] = _ascent_view(view)
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
	if _growth == null:
		push_error("BodyCultivationPanel: scene is missing %GrowthPanel")
		return
	var live := BodyCultivationApi.panel_state(_actor) if _actor != null else {}
	_vitals.set_state(live)
	# The stat surface is core's, read the same way the character sheet reads it, so
	# the two can never disagree about what the body is worth. Handing it over whole
	# and letting the panel select is deliberate: `ui/` may not name `BodyStats`, so
	# the ids live in `BodyGrowthPanel` and are reconciled against the module by
	# `tests/ui/test_body_growth_observability.gd`.
	_growth.set_state(_stat_surface() if _actor != null else {})
	var ready: bool = bool(live.get("ready", false))
	_cultivate_button.disabled = live.is_empty()
	_meditate_button.disabled = live.is_empty()
	_strengthen_button.disabled = live.is_empty()
	_recover_button.disabled = live.is_empty()
	_breakthrough_button.disabled = not ready
	_ascend_button.disabled = not _ascend_offered(live)
	_render_ascent(live)
	_render_tier_gates(live)


## Every stat this actor carries, provider contributions included. Core, not a
## module: `ActorStats` is the single source of truth for a stat's value, and this
## is the same read `CharacterScreen` makes.
func _stat_surface() -> Dictionary:
	return _actor.stats.derived_all()


# --- The ascent ---------------------------------------------------------------
#
# Read from the facade's `ascent` block, which is DATA and not a verb: the ascent
# itself is `WorldAnchor.ascend`, a core entry point `ui/` may call directly
# (ADR 0041), so nothing here grows the body's facade.


## The ascent block as this screen reports it, with the row's own summary nested
## under `row` and whether a player is offered the control.
##
## `row` is `{}` whenever the row takes no space, so "no ascent to show" and "an
## ascent shown with no wording" are distinguishable: the first has no row summary
## at all.
func _ascent_view(view: Dictionary) -> Dictionary:
	var ascent: Dictionary = view.get("ascent", {})
	var shown := "" if _ascent_row == null else String(_ascent_row.summary().get("name", ""))
	return {
		"required": bool(ascent.get("required", false)),
		"steps": int(ascent.get("steps", 0)),
		"steps_total": int(ascent.get("steps_total", 0)),
		"met": bool(ascent.get("met", false)),
		"outstanding": String(ascent.get("outstanding", "")),
		"offered": _ascend_offered(view),
		"shown": shown,
		"row": _ascent_row.summary() if _ascent_row != null else {},
	}


## A player may walk the ascent only while one is owed AND unfinished. An actor
## below the Transcendent tier is offered nothing: `ascension_ok` is true for every
## target at or below `WorldAnchor.COMMIT_MICRO`, so `required` is false there and
## the button is a dead control that would only invite a press.
func _ascend_offered(view: Dictionary) -> bool:
	var ascent: Dictionary = view.get("ascent", {})
	if view.is_empty():
		return false
	return bool(ascent.get("required", false)) and int(ascent.get("steps", 0)) > 0


## Render the ascent bar. The label is core's own wording — `outstanding` is
## `WorldAnchor.ascension_unmet` verbatim and is never restated here (ADR 0034) —
## and the bar counts the same quantity the label does: the steps still to walk. So
## walking the ascent drains the bar, and the button goes dead the moment there is
## nothing left to walk.
##
## Three states, told apart by `outstanding` and never by `met`. `met` is
## `Breakthrough.ascension_ok`, which is true for EVERY target at or below
## `WorldAnchor.COMMIT_MICRO`, so an R1 hero "meets" an ascent gate that does not
## exist yet; keying the render off it printed "The ascent is walked" on a hero who
## had walked nothing. `ascension_unmet` answers "" in exactly one case — an existing
## ascent with no steps left — so it is the only unambiguous signal here.
##
## Nothing is drawn when core has nothing to state.
##
## Three states, told apart by `outstanding` and never by `met`. `met` is
## `Breakthrough.ascension_ok`, which is true for EVERY target at or below
## `WorldAnchor.COMMIT_MICRO`, so an R1 hero "meets" an ascent gate that does not
## exist yet; keying the render off it printed "The ascent is walked" on a hero who
## had walked nothing. `ascension_unmet` answers "" in exactly one case — an existing
## ascent with no steps left — so it is the only unambiguous signal here.
##
## ## The sentinel is NOT a requirement, at any tier
##
## This used to suppress `WorldAnchor.NO_ASCENT` ("No ascent begun") only below the
## Transcendent tier, on the reasoning that a low hero must not be shown a gate they
## cannot have. Driven at `realm:transcendent` + `commit:28`, the same string was
## printed as the ascent row's label with `required: true` and `offered: false` —
## because `ascension_unmet` returns NO_ASCENT whenever the actor has no
## `AscensionState` yet, which is true at the top realm too until one is created.
## The player was told an ascent existed, shown a `0/4` bar for it, and offered no
## button. The guard's intent was right and its condition was too narrow, so it is
## now keyed on the meaning of the string rather than on the player's tier.
##
## On the duplication with the vitals line: `unmet` also ends with "No ascent begun",
## so the phrase appears twice. That overlap is deliberate and stays. The vitals line
## answers "what is blocking my breakthrough?" with a checklist of eleven items; the
## ascent row answers "how far along the ascent am I?" with a bar and a count.
## Neither is derivable from the other, and the UI quotes both verbatim rather than
## restating either (ADR 0034), so there is no wording to drift. Once NO_ASCENT is
## suppressed here, the only place it appears is the checklist, where it correctly
## reads as one more unmet item.
func _render_ascent(view: Dictionary) -> void:
	if _ascent_row == null:
		return
	# An empty name is how `StatRow` is told to take no space.
	var ascent: Dictionary = view.get("ascent", {})
	var label := ""
	if not view.is_empty():
		var outstanding := String(ascent.get("outstanding", ""))
		if outstanding == WorldAnchor.NO_ASCENT:
			# Core declining to state a requirement. Not a gate to advertise.
			label = ""
		elif bool(ascent.get("required", false)):
			# Core declining to state a requirement. Not a gate to advertise.
			label = ""
		elif bool(ascent.get("required", false)):
			# An ascent is genuinely owed, so core is stating the requirement.
			label = outstanding
		elif outstanding.is_empty():
			# Core has nothing outstanding, which means the walk is done. That is a
			# state, not a rule, so it needs no wording of its own.
			label = "The ascent is walked"
	(
		_ascent_row
		. set_state(
			{
				"name": label,
				"current": int(ascent.get("steps", 0)),
				"maximum": int(ascent.get("steps_total", 0)),
				"mode": StatRow.MODE_BAR if not label.is_empty() else StatRow.MODE_TEXT,
			}
		)
	)


## The four high-tier gates, named and only named. `panel_state` publishes them as
## four booleans precisely so a screen can say WHICH is shut rather than that
## something is; the requirement behind each one stays where it is written.
func _render_tier_gates(view: Dictionary) -> void:
	if _tier_gates_label == null:
		return
	var gates: Dictionary = view.get("tier_gates", {})
	if gates.is_empty():
		_tier_gates_label.text = ""
		return
	var shut: Array = []
	for gate in gates.keys():
		if not bool(gates[gate]):
			shut.append(String(gate))
	shut.sort()
	_tier_gates_label.theme_type_variation = &"WarnLabel" if not shut.is_empty() else &"OkLabel"
	_tier_gates_label.text = (
		"Tier gates shut: %s" % ", ".join(shut)
		if not shut.is_empty()
		else "Every tier gate is open"
	)


## ScreenStack lifecycle: focus belongs to the stack, never to `_ready()`.
func on_screen_shown() -> void:
	focus_initial()


## Nothing to tear down: every widget this screen owns is repainted from the facade
## on `refresh()`, so a covered screen holds no state a reveal could go stale on.
## Declared so all four `ScreenStack` hooks exist here as the standard requires,
## even though `ScreenStack` would skip a missing one without complaint.
func on_screen_hidden() -> void:
	pass


## Consume nothing. `ui_cancel` must stay unclaimed so the stack can pop back to the
## home screen; a screen that ate it would strand the player on this one.
func on_stack_input(_event: InputEvent) -> bool:
	return false


func focus_initial() -> void:
	_bind_nodes()
	var view := BodyCultivationApi.panel_state(_actor) if _actor != null else {}
	var live := not view.is_empty()
	# Cultivate is always the first thing a body cultivator does; breakthrough is
	# only reachable once everything else is prepared, and an owed ascent is the
	# only thing left to do once the tier gate has opened it.
	var name := "CultivateButton" if live else "MeditateButton"
	if live and _ascend_offered(view):
		name = "AscendButton"
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


## Walk ONE step of the Transcendent ascent.
##
## The only action here that is not a facade call, and deliberately so: the ascent
## belongs to no single path — every path carries the same `AscensionState` — so no
## facade serves it and `core` is where the entry point lives (ADR 0041). Its gate
## is read from the facade's `ascent` block rather than re-derived here, so the
## screen can never open a gate `Breakthrough.ascension_ok` would refuse.
func act_ascend() -> bool:
	if _actor == null:
		return false
	var before := BodyCultivationApi.panel_state(_actor).get("ascent", {}) as Dictionary
	if not bool(before.get("required", false)):
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
		"ascend": _ascend_offered(view),
	}


## Resolve the scene's widgets on first use rather than in `@onready`: the
## headless suite drives this screen before a scene tree exists, so `_ready()` is
## not a dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	if _cultivate_button != null:
		return
	_vitals = get_node_or_null("%VitalsPanel") as BodyVitalsPanel
	_growth = get_node_or_null("%GrowthPanel") as BodyGrowthPanel
	_ascent_row = get_node_or_null("%AscentRow") as StatRow
	_tier_gates_label = get_node_or_null("%TierGatesLabel") as Label
	_message_label = get_node_or_null("%MessageLabel") as Label
	_cultivate_button = get_node_or_null("%CultivateButton") as Button
	if _cultivate_button == null:
		return
	_meditate_button = get_node_or_null("%MeditateButton") as Button
	_strengthen_button = get_node_or_null("%StrengthenButton") as Button
	_recover_button = get_node_or_null("%RecoverButton") as Button
	_breakthrough_button = get_node_or_null("%BreakthroughButton") as Button
	_ascend_button = get_node_or_null("%AscendButton") as Button
	_world_map_button = get_node_or_null("%WorldMapButton") as Button
	_cultivate_button.pressed.connect(act_cultivate)
	_meditate_button.pressed.connect(act_meditate)
	_strengthen_button.pressed.connect(_on_strengthen)
	_recover_button.pressed.connect(_on_recover)
	_breakthrough_button.pressed.connect(_on_breakthrough)
	if _ascend_button != null:
		_ascend_button.pressed.connect(_on_ascend)
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
		"AscendButton":
			return _ascend_button
		_:
			return _breakthrough_button


func _on_strengthen() -> void:
	act_strengthen()


func _on_recover() -> void:
	act_recover()


func _on_breakthrough() -> void:
	act_breakthrough()


func _on_ascend() -> void:
	act_ascend()


func act_world_map() -> void:
	world_map_requested.emit()
