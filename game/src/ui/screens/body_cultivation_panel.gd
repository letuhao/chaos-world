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
## Three states, told apart by `outstanding` ALONE, and never by the two booleans:
##
##  - `met` is `Breakthrough.ascension_ok`, which is true for EVERY target at or below
##    `WorldAnchor.COMMIT_MICRO`, so an R1 hero "meets" an ascent gate that does not
##    exist yet. Keying the render off it printed "The ascent is walked" on a hero
##    who had walked nothing.
##  - `required` is a DIFFERENT question — "is this the gate on my next
##    breakthrough" — and it is asked in exactly one place, `_ascend_offered`, which
##    decides the CONTROL. Asking it here too is what made this row blank whenever the
##    requirement was real: two `elif`s tested `required`, the first one won and set
##    the label to `""`, and the branch naming the requirement became dead code. The
##    row answers "how far along the walk am I" from what core states; the button
##    answers "am I owed it" from `required`. One predicate, one job.
##
## The three are disjoint BY CONSTRUCTION, because `ascension_unmet` is a three-way:
## `NO_ASCENT` means there is no `AscensionState` at all, "" means one exists with
## nothing left to walk, and anything else names steps that remain. An ascent with
## steps to walk can never produce the sentinel, so suppressing the sentinel costs a
## player nothing they needed.
##
## The sentinel is NOT a requirement, at any tier. It used to be suppressed only below
## the Transcendent tier, on the reasoning that a low hero must not be shown a gate
## they cannot have — but `ascension_unmet` returns `NO_ASCENT` whenever the actor has
## no `AscensionState` yet, which is true at the TOP realm too until one is created.
## Driven at `realm:transcendent` + `commit:27`, the same string was printed as this
## row's label with `required: true` and `offered: false`: the player was told an
## ascent existed, shown a `0/4` bar for it, and offered no button. The intent was
## right and the condition was too narrow, so it is keyed on the MEANING of the
## string rather than on the player's tier.
##
## On the duplication with the vitals line: `unmet` also ends with "No ascent begun",
## so the phrase appears twice. That overlap is deliberate and stays. The vitals line
## answers "what is blocking my breakthrough?" with a checklist; this row answers
## "how far along the ascent am I?" with a bar and a count. Neither is derivable from
## the other, and the UI quotes both verbatim rather than restating either (ADR
## 0034), so there is no wording to drift.
func _render_ascent(view: Dictionary) -> void:
	if _ascent_row == null:
		return
	# An empty name is how `StatRow` is told to take no space.
	var ascent: Dictionary = view.get("ascent", {})
	var label := ""
	if not view.is_empty():
		var outstanding := String(ascent.get("outstanding", ""))
		if outstanding == WorldAnchor.NO_ASCENT:
			# Core declining to state a requirement: there is no `AscensionState` to
			# walk, so a bar beside this sentence would read 0/4 for a ritual that
			# does not exist. Not a gate to advertise, so the row takes no space.
			label = ""
		elif not outstanding.is_empty():
			# Core IS stating a requirement — steps remain — so state it, verbatim.
			# This is the owed case, and it is the one the duplicated `elif` used to
			# swallow: the player was owed the ascent and this row said nothing at all.
			label = outstanding
		else:
			# Core has nothing outstanding, which means an existing ascent has been
			# walked to its end. That is a state, not a rule, so the wording is the
			# screen's own rather than core's — and it earns its space, because a row
			# that vanishes the moment the walk completes is indistinguishable from one
			# that never existed.
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


## One channel step, at the realm's `strengthening_item` — or the repair of a torn
## channel, which is priced by the realm's `recovery_item` (ADR 0141).
##
## The refusal names the PRICE, and which price it is depends on the state of the
## channel the facade would have trained: `strengthen` hands a burned channel to
## `recover`, so a hero holding only the channel elixir and standing on a torn
## channel is refused for the OTHER elixir, and "No channel elixir to spend" is
## the one answer that cannot be true (ADR 0150).
##
## A refusal with nothing burned still collapses two causes — the elixir missing,
## or every candidate channel already at its cap — because `strengthen_next`
## reports one bool over a walk this screen cannot see. That residual is
## recorded, not papered over: separating it needs the candidate list and the cap
## on the read model, and this facade is already at `rules.MAX_FACADE_PUBLIC_METHODS`.
func act_strengthen() -> bool:
	if _actor == null:
		return false
	var trained := BodyCultivationApi.strengthen_next(_actor)
	set_message(
		"Channel trained" if trained else _strengthen_refusal(), TONE_OK if trained else TONE_ERROR
	)
	refresh()
	return trained


## Why a refused `strengthen_next` refused. The elixir's ID is authored in the
## realm seed, which is a module internal this screen may not read (ADR 0043), so
## the price is named by its ROLE — the word the authored content and its
## acquisition are indexed by — never by an id restated here.
func _strengthen_refusal() -> String:
	return "Recovery elixir absent" if _burned_channels() > 0 else "No channel elixir to spend"


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


## Repair a deviation: frees a jammed huyệt or heals a torn channel using the
## realm's recovery item. False means nothing was damaged, or the item was absent.
func act_recover() -> bool:
	if _actor == null:
		return false
	var repaired := BodyCultivationApi.recover_next(_actor)
	set_message(
		"Repaired" if repaired else _recovery_refusal(), TONE_OK if repaired else TONE_ERROR
	)
	refresh()
	return repaired


## What a refused recovery means, read from the facade's own report rather than
## inferred from the `false` alone (ADR 0150, which names this screen as the worst
## instance of the collapse).
##
## The two things a refusal can mean are forced apart here. A jam or a tear is a
## wound the recovery elixir would close, so a refusal with one present has exactly
## one remaining cause — the elixir. A refusal with none is "look elsewhere".
## Collapsing both into "Nothing damaged to repair" told a hero with a jammed huyệt
## and no recovery elixir that nothing was damaged, while the same screen's
## `unmet` line, rendered from the same `panel_state`, said the opposite — the
## screen contradicting itself on the fail-recoverably leg of the gate.
func _recovery_refusal() -> String:
	return "Recovery elixir absent" if _damage_pending() else "No damage to repair"


## Whether the facade reports a wound the recovery elixir exists to close: a jammed
## huyệt, or any torn channel.
##
## `blocked` is the facade's own count. The channel flag is not on `panel_state`'s
## channel strings — they carry `id:state/refinement` with no injury marker, unlike
## qi's — so it is read from `core`, which `ui/` may use directly (ADR 0041).
## `get_all_meridians` is the network's own survey, bounded by the meridians this
## actor has unlocked, so the walk cannot outlast its own list.
func _damage_pending() -> bool:
	if _actor == null:
		return false
	if int(BodyCultivationApi.panel_state(_actor).get("blocked", 0)) > 0:
		return true
	return _burned_channels() > 0


## How many channels on this actor are torn. Only channels actually on the network
## are reported by `get_all_meridians`, so a meridian this realm has not unlocked
## never counts as a wound the player was told they owed an elixir for.
func _burned_channels() -> int:
	var burned := 0
	if _actor == null:
		return burned
	for channel in _actor.meridians.get_all_meridians():
		if channel.is_injured():
			burned += 1
	return burned


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
