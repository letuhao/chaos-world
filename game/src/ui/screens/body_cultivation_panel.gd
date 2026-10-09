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
##
## **A REFUSAL IS RENDERED, NEVER INFERRED (ADR 0150).** Every message below is either a fact
## this screen observed or a `label` the module published on `panel_state`'s `unavailable` /
## `attempt_outcome`. This file used to decide the prices itself by walking `core`'s meridian
## network, which is how a hero with a torn channel and no elixir was told nothing was damaged
## while the gate line above said the opposite.
##
## **THE BREAKTHROUGH IS TWO PRESSES, AND THE SECOND ONE SURVIVES A QUIT.** This control
## commits a durable attempt and then resolves it, which is the facade's documented lifecycle
## and the only shape in which an attempt a player committed can outlive the session that
## committed it. ADR 0150 recorded the durable half as unwired and left the fork open; it is
## taken here, and the reasoning lives on `act_breakthrough`.

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
## The label the SCENE authored for the breakthrough button, captured so the resolve
## affordance can hand it back. The scene owns the wording; this screen only borrows
## the same control for the other half of one lifecycle, and hardcoding a second
## string here would let the two drift from the scene nobody can compile against.
var _breakthrough_label: String = ""


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
		_message_label.text = L.t(_message)
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
	var view := _view()
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
	var live := _view()
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
	# Recover and strengthen stay LIVE when the module says they cannot act, because the
	# refusal IS the message a player needs: disabling a control on a named refusal is the
	# tribulation screen's defect (ADR 0150), and it would make every refusal here unreachable.
	_recover_button.disabled = live.is_empty()
	_render_attempt_button(live, ready)
	_ascend_button.disabled = not _ascend_offered(live)
	_render_ascent(live)
	_render_tier_gates(live)


## THE DURABLE ATTEMPT AFFORDANCE (ADR 0150 §Consequences, recorded as a finding there).
##
## One control, two jobs, chosen by the module's own answer rather than by anything this
## screen decides: while `panel_state`'s `attempt` names an attempt in flight, the button
## RESOLVES it; with none in flight it offers a fresh attempt and stays gated on `ready`
## exactly as before.
##
## `attempt` is the whole contract, and it is the module's: `BodyAdvancement.preview`
## documents it as "the active attempt's id, empty when none is in flight". A screen
## reading a non-empty id is reading a published decision, not re-deriving one — which is
## the ADR 0034 rule the ascent row already follows. There is deliberately no second
## `committed` boolean here to drift out of step with it.
##
## **Why one button and not two.** The scene declares the widgets (`.tscn`), this screen
## never builds one, and a second node is a scene edit rather than a screen edit. It is
## also the better control: the two halves are mutually exclusive by construction — an
## attempt in flight is exactly what forbids a fresh one, named as
## `BodyRefusal.KIND_ATTEMPT_IN_FLIGHT` — so a player can never be offered both.
func _render_attempt_button(view: Dictionary, ready: bool) -> void:
	if _breakthrough_button == null:
		return
	var committed := _attempt_committed(view)
	if committed:
		_breakthrough_button.disabled = false
		_breakthrough_button.text = L.t("LOC_UI_SCREENS_0CDCCA9915") % _attempt_target(view)
		return
	_breakthrough_button.disabled = not ready
	_breakthrough_button.text = L.t(_breakthrough_label)


## Whether an attempt is committed and awaiting its roll.
##
## The facade publishes this as an id on purpose: it is the same value
## `attempt_outcome.id` carries, so a screen can name the attempt it is resolving and a
## test can assert the two agree without either being a second source of truth.
func _attempt_committed(view: Dictionary) -> bool:
	return not String(view.get("attempt", "")).is_empty()


## The realm a committed attempt is fighting for, read off the record the module
## published. Empty when there is none, which the button only asks for when one is.
func _attempt_target(view: Dictionary) -> String:
	var outcome: Dictionary = view.get("attempt_outcome", {})
	var target := String(outcome.get("target", ""))
	if not target.is_empty():
		return target
	return String(view.get("target", ""))


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
	var view := _view()
	var live := not view.is_empty()
	# Cultivate is always the first thing a body cultivator does; breakthrough is
	# only reachable once everything else is prepared, and an owed ascent is the
	# only thing left to do once the tier gate has opened it.
	var name := "CultivateButton" if live else "MeditateButton"
	if live and _ascend_offered(view):
		name = "AscendButton"
	# A committed attempt outranks all of them, and it is the same control either way:
	# the button resolves what is already spent, so focus lands there rather than on a
	# verb the module would refuse. Naming it through `_button`'s fall-through keeps one
	# control, one name, instead of a second name for a widget that only changes label.
	if _attempt_committed(view):
		name = "BreakthroughButton"
	_focus_target = name
	var target := _button(name)
	if target != null and target.is_inside_tree():
		target.grab_focus()


# --- Actions, callable headlessly as well as by the buttons ----------------


## One cultivation step, at the size the facade publishes.
func act_cultivate() -> void:
	if _actor == null:
		return
	var before := _view()
	var moved := BodyCultivationApi.cultivate(_actor, float(_steps().get("cultivate", 25.0)))
	set_message(
		"Cultivated the body" if moved else _refusal(before, "cultivate"),
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


## One channel step, at the realm's `strengthening_item` — or the repair of a torn channel,
## which is priced by the realm's `recovery_item` (ADR 0141).
##
## The refusal is the module's own clause, joined. This screen used to decide the PRICE
## itself: it walked `core`'s meridian network counting torn channels and picked a sentence
## from the count, which meant the price lived in the UI program and the two could disagree —
## and a capped channel read as a missing elixir, because a `false` cannot say which of the
## three causes fired (ADR 0150, ADR 0034).
func act_strengthen() -> bool:
	if _actor == null:
		return false
	var before := _view()
	var trained := BodyCultivationApi.strengthen_next(_actor)
	set_message(
		"Channel trained" if trained else _refusal(before, "strengthen"),
		TONE_OK if trained else TONE_ERROR
	)
	refresh()
	return trained


## The breakthrough control, which resolves a committed attempt and otherwise commits
## a fresh one.
##
## **TWO HALVES, TWO CALLS, TWO ANSWERS, and the return cannot mean one thing.** It
## reports whether the hero ADVANCED, so a commit answers `false` while having succeeded
## — which is why the commit reports its own tone rather than falling into the refusal
## branch below. Conflating them is what made "an attempt was committed" indistinguishable
## from "the press was refused", and a player who cannot tell those apart cannot tell
## whether their pill was spent.
##
## Read BEFORE the press, and that ordering is load-bearing for the resolve half too: a
## resolve rolls, and a roll mutates. Read afterwards, the report would describe the roll's
## outcome as though it had blocked the attempt, and a deviation's own aftermath would
## come back as its cause.
func act_breakthrough() -> bool:
	if _actor == null:
		return false
	var before := _view()
	if _attempt_committed(before):
		return _resolve_attempt()
	return _commit_attempt(before)


## The first half: spend the realm pill and leave a durable record. Reports the module's
## committed view, so the sentence names the realm actually fought for rather than one
## this screen re-derives from the ladder.
func _commit_attempt(before: Dictionary) -> bool:
	var committed := BodyCultivationApi.begin_breakthrough(_actor)
	if committed.is_empty():
		set_message(_breakthrough_refusal(before), TONE_ERROR)
		refresh()
		return false
	set_message(
		(
			"An attempt into %s is committed; resolve it when you are ready"
			% String(committed.get("target", ""))
		),
		TONE_OK
	)
	refresh()
	return false


## The second half: roll the committed attempt, on whichever session it rides out on.
##
## No pre-press read is needed here, and that asymmetry is the point: a resolve is only
## offered once something is committed, so nothing could have blocked the press, and the
## only thing that can report the outcome is the record the roll just wrote.
##
## The `false` is that record's own verdict, published as `attempt_outcome`, exactly as
## the one-press verb reports it — a deviation owes a wound to repair and a cancellation
## owes nothing, and a `false` that read as "deviated" for both is the defect ADR 0150
## removed from the sibling press.
func _resolve_attempt() -> bool:
	var granted := BodyCultivationApi.resolve_breakthrough(_actor)
	if granted:
		set_message("Broke through", TONE_OK)
	else:
		set_message(_resolve_refusal(), TONE_ERROR)
	refresh()
	return granted


## Why a resolve did not grant.
##
## **THE RECORD ONLY, AND JOINING `unavailable` HERE IS A LIE.** The obvious version of this
## reads `_refusal(view, "breakthrough")` first, and it is wrong in a way that always looks
## right: after a resolve the clause list is NON-EMPTY — the gates the deviation just broke
## are published on it — so the join produces a sentence every time. It is the wrong
## sentence. A hero whose trial deviated into `foundation` would be told to repair a
## channel, which is a different debt from "that attempt deviated", and it reads as a lie
## about what just happened. A refusal that always has an answer is how the four-cause
## collapse ADR 0150 removed comes back, wearing the sentence that was supposed to fix it.
##
## (The mechanism is worth stating because it is not the obvious one. Before the resolve,
## the in-flight clause is what makes the list non-empty; after it, the record is terminal
## and it is the *gate* clauses that fill it. So a mutation reintroducing the join was
## caught only by comparing the message to the record's verdict — an assertion that it
## "does not contain the wrong sentence" passed it, because the gate clauses are full of
## real, true, unrelated text.)
##
## Nothing blocked the press — the panel only offers resolve once something is committed —
## so every `false` here was decided by the roll, which is not knowable before it happens.
## The record is the only thing that can name it, which is why `attempt_outcome` exists as
## a separate key from `unavailable` rather than folded into it.
func _resolve_refusal() -> String:
	var outcome: Dictionary = _view().get("attempt_outcome", {})
	return String(outcome.get("reason", ""))


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
	var before := _view().get("ascent", {}) as Dictionary
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


## Repair a deviation: frees a jammed acupoint or heals a torn channel using the realm's recovery
## item.
##
## The two causes are DISJOINT BY CONSTRUCTION in the module's report, which is what this screen
## used to assume and could not know: `KIND_NO_DAMAGE` is published only when no wound is
## pending, and the elixir's price only when one is. So the same sentence is printed only where
## it is true — which is the whole of the fix.
func act_recover() -> bool:
	if _actor == null:
		return false
	var before := _view()
	var repaired := BodyCultivationApi.recover_next(_actor)
	set_message(
		"Repaired" if repaired else _refusal(before, "recover"), TONE_OK if repaired else TONE_ERROR
	)
	refresh()
	return repaired


## Why a refused action refused, from the names the module published. The module owns the
## wording; this joins it and adds nothing, so a screen cannot report a cause the module never
## named. **A `false` WITH AN EMPTY LIST IS A FINDING, NOT A MESSAGE TO INVENT** (ADR 0150), so
## the join may answer "". `tests/modules/body_cultivation/test_refusal_naming.gd` is the guard
## that such a state is unreachable — the check that would have caught this screen's own lie.
func _refusal(view: Dictionary, verb: String) -> String:
	# `PackedStringArray`, not `Array`: `String.join` takes the packed type, and an
	# `Array` argument converts to it at the call while a TYPED `Array[String]` does not
	# — which returned "" for every refusal on screen, in silence, with no error. A join
	# that quietly produces nothing is the same defect as the one this screen just lost.
	var parts := PackedStringArray()
	var clauses: Array = (view.get("unavailable", {}) as Dictionary).get(verb, [])
	for clause in clauses:
		# The module publishes a KEY per clause (`Refusal.BUSY_LABEL`), so it resolves here —
		# this join is what the message line shows.
		var label := L.t(String((clause as Dictionary).get("label", "")))
		if not label.is_empty() and not parts.has(label):
			parts.append(label)
	return "; ".join(parts)


## Why a refused breakthrough refused. TWO QUESTIONS, TWO READS, and neither is a guess:
## what BLOCKED the press (the pre-press report — the roll is not knowable before it happens,
## so nothing blocking it means the roll ran), and what the roll BECAME (the record, published
## as `attempt_outcome`, because a deviation and a cancellation are different debts — one owes
## a wound to repair, the other owes nothing because nothing was ever rolled — and every
## refusal used to read as a deviation).
func _breakthrough_refusal(before: Dictionary) -> String:
	var named := _refusal(before, "breakthrough")
	if not named.is_empty():
		return named
	var outcome: Dictionary = _view().get("attempt_outcome", {})
	return String(outcome.get("reason", ""))


## The facade's read model for this screen's actor. One definition, so the pre-press read a
## refusal is reported from and the repaint after it cannot disagree about what they saw.
func _view() -> Dictionary:
	return BodyCultivationApi.panel_state(_actor) if _actor != null else {}


func _steps() -> Dictionary:
	return _view().get("steps", {})


## Which actions the screen offers, given the facade view the screen is rendering.
## Breakthrough needs the gate; the training verbs need only an actor.
##
## `breakthrough` and `resolve` are MUTUALLY EXCLUSIVE and are reported separately, so a
## test can tell "a fresh attempt is offered" from "an attempt is waiting to be rolled".
## Keying the first on `ready` alone would report both true at once — a hero stays
## prepared while its attempt is committed — which is the state the affordance exists to
## make visible rather than hide behind an unchanged button.
func _action_state(view: Dictionary) -> Dictionary:
	var live := not view.is_empty()
	var committed := _attempt_committed(view)
	return {
		"cultivate": live,
		"meditate": live,
		"strengthen": live,
		"recover": live,
		"breakthrough": bool(view.get("ready", false)) and not committed,
		"resolve": committed,
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
	if _breakthrough_button != null:
		_breakthrough_label = _breakthrough_button.text
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
