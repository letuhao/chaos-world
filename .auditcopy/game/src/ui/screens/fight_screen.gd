class_name FightScreen
extends UiScreen

## The fight surface (ADR 0197): enter a fight, throw blows, watch it resolve, and see
## the verdict. This is the page that makes the engine's work a GAME rather than a
## readout — the readout (`CombatReadoutScreen`) answers "what did the spine do to one
## blow", and this answers "who won".
##
## ## It is a PURE CONSUMER, and every verb arrives as a Callable
##
## `app/` is a `PRIVATE_UNIT` (`tools/arch/rules.py`) and `FightLoop` is an `app/` type,
## so this screen may neither hold one nor name `ActorFactory` to mint an opponent. Every
## verb is therefore injected at the route mount, which is ADR 0143's bridge — the same
## seam the quest screen's accept verb, the soul screen's save status and the readout's
## strike all use. Unwired, the screen says so on its own line rather than presenting a
## dead button.
##
## ## And it owns NO number
##
## [FightPanel] owns every `%d`, every decimal and every verdict word (ADR 0030, 0038).
## This screen routes the loop's primitives into the panel and publishes them under
## `summary()`. A screen that formatted its own figures would give one number two places
## to change.
##
## Contract: `summary()` is the testable surface, primitives only, with the panel's
## summary nested under `fight`. `{}` with no actor.

## Every refusal, named. A verb that quietly does nothing is the shape a player cannot
## act on (ADR 0150), so each of these is a distinct reason rather than a bare false.
const REASON_NO_HERO := "no_hero"
const REASON_NO_FIGHT_SEAM := "no_fight_seam"
const REASON_NO_PURGE_SEAM := "no_purge_seam"
## The purge is an app/-owned verb, so a screen bound without it can still FIGHT; it just
## cannot clear the combat-scope statuses a fight inflicted. Reported rather than hidden.
const PURGE_UNWIRED := ""

const HEADER_TEXT := "Fight"

## The tone map: `FightLoop`'s outcome words to the message tone a player reads.
##
## ## Why this exists at all
##
## There was no map. `_settle` styled every message by whether the VERB's result
## carried `ok`, so the moment the loop DECIDED a fight `ok` went false (the exchange
## that ends a fight reports `ok: true`, but any press after it is refused by
## `R_FIGHT_OVER` with `ok: false`) -- and the second press on a fight already won
## rendered `tone: "error"` under the words "The fight is won." A victory styled as a
## failure is worse than an unstyled one: it teaches a player that their win is a
## mistake.
##
## ## Why an OUTCOME and not a success flag
##
## The three states a player reads differently are `ongoing` (a fight in progress),
## `hero_won` and `hero_lost` -- and only the first two of those are a successful
## ACTION. Mapping the OUTCOME is what makes the map testable: every word the loop
## can publish has one tone, stated in one table, rather than each verb guessing.
##
## ## And a refusal is not a loss
##
## An unwired seam or a missing hero is a neutral report about this screen, never the
## error tone a lost fight wears -- a player who pressed a dead button is not a player
## who has been beaten. Only `hero_lost` takes the error tone.
const TONE_BY_OUTCOME := {
	"ongoing": TONE_OK,
	"hero_won": TONE_OK,
	"hero_lost": TONE_ERROR,
}
## A word the map does not name. Neutral rather than `TONE_ERROR`: an outcome this
## screen cannot read is not a failure, and defaulting to the error tone is exactly
## how a win came to be styled as one.
const TONE_UNREAD := &""

## The fight's own verbs, all injected. `begin() -> Dictionary` opens a fight,
## `exchange() -> Dictionary` throws one blow and takes the answer, `age(delta) ->
## Dictionary` advances the rate gate, `disengage() -> Dictionary` walks away, and
## `read() -> Dictionary` is `FightLoop.summary()` for the panel and for `summary()`.
var _begin: Callable = Callable()
var _exchange: Callable = Callable()
var _age: Callable = Callable()
var _disengage: Callable = Callable()
var _read: Callable = Callable()
## ADR 0089's combat-exit purge, injected from the root exactly as `LootEncounterScreen`
## receives it. A fight that ends clears the COMBAT-scope statuses it inflicted, and that
## rule is a fact about WHEN a fight is over — which is what this screen knows.
var _purge: Callable = Callable()
var _panel: FightPanel = null
var _start_button: Button = null
var _strike_button: Button = null
var _leave_button: Button = null
var _header_label: Label = null
var _bound: bool = false
## The ids the last purge cleared, as primitives, so a probe can tell a fight that ended
## and burned nothing from a purge that was never wired.
var _cleared: Array = []


## Inject the fight's verbs. Safe to call again; the panel repaints from whatever the
## last read said.
func bind_fight(verbs: Dictionary) -> void:
	_bind_nodes()
	_begin = _callable_of(verbs, "begin")
	_exchange = _callable_of(verbs, "exchange")
	_age = _callable_of(verbs, "age")
	_disengage = _callable_of(verbs, "disengage")
	_read = _callable_of(verbs, "read")
	refresh()


## Inject ADR 0089's purge. Separate from [method bind_fight] because it is a
## different OWNER (`StatusLoop`, over the status facade) rather than another verb of the
## fight, and one seam per owner is the rule the quest and loot screens already follow.
func bind_combat_exit(purge: Callable) -> void:
	_purge = purge
	_bind_nodes()
	refresh()


## Whether the fight's verbs are wired. Published by `summary()` so a probe can tell "the
## screen refused because nothing can fight" from "the loop refused the blow" — the two
## read as the same empty line otherwise.
func fight_wired() -> bool:
	return _exchange.is_valid() and _read.is_valid()


func _summary() -> Dictionary:
	_bind_nodes()
	if actor() == null:
		return {}
	var fight := _current()
	var was_live := bool(fight.get("fighting", false))
	return {
		"hero": String(actor().id),
		"fight_wired": fight_wired(),
		"purge_wired": _purge.is_valid(),
		"begin_wired": _begin.is_valid(),
		"leave_wired": _disengage.is_valid(),
		"fighting": was_live,
		"outcome": String(fight.get("outcome", "")),
		"opponent_id": String(fight.get("opponent_id", "")),
		"hero_blows": int(fight.get("hero_blows", 0)),
		"opponent_blows": int(fight.get("opponent_blows", 0)),
		"blows_remaining": float(fight.get("blows_remaining", 0.0)),
		"elapsed": float(fight.get("elapsed", 0.0)),
		"wound_count": int(fight.get("wound_count", 0)),
		"last_cleared": _cleared.duplicate(true),
		"fight": _panel.summary() if _panel != null else {},
		"enabled": _enabled(was_live),
	}


# --- Actions ----------------------------------------------------------------


## Open a fight. The verb a player presses when they have decided to fight, and the
## only one that can name an opponent — the loop mints it, because `ui/` may not.
func act_start() -> bool:
	_bind_nodes()
	if actor() == null:
		return _reject(REASON_NO_HERO)
	if not _begin.is_valid():
		return _reject(REASON_NO_FIGHT_SEAM)
	# Typed as `Variant` and narrowed on the next line, because a `Callable.call` returns
	# `Variant` and `:=` would infer `Variant` -- which this project treats as a warning,
	# and warnings are errors. The three verbs below each say so on their own line rather
	# than a shared helper, because the shape of the report differs: `act_strike` needs the
	# verdict and the other two only need `ok`.
	var result: Variant = _begin.call()
	var report := result as Dictionary if result is Dictionary else {}
	return _settle(report, "The fight is on.")


## Throw one blow and take the answer.
##
## ## The purge runs on the VERDICT, never on a blow still going
##
## A burn or a root is supposed to survive until the fight that inflicted it is over, so
## purging on every exchange would make the statuses the enemy applied meaningless. The
## purge is therefore driven by the loop's OWN `outcome`, which is the only thing that
## knows a fight has been decided — the same rule `LootEncounterScreen.act_strike`
## follows, for the same reason.
func act_strike() -> bool:
	_bind_nodes()
	if actor() == null:
		return _reject(REASON_NO_HERO)
	if not _exchange.is_valid():
		return _reject(REASON_NO_FIGHT_SEAM)
	var result: Variant = _exchange.call()
	var report := result as Dictionary if result is Dictionary else {}
	# `_is_decided` asks the SAME table the tone does, so the purge can never fire on an
	# outcome the screen would not also render as a verdict.
	var decided := _is_decided(report) and String(report.get("outcome", "")) != "ongoing"
	if decided:
		_purge_combat_scope()
	return _settle(
		report,
		(
			(
				"The fight is won."
				if String(report.get("outcome", "")) == "hero_won"
				else "The fight is lost."
			)
			if decided
			else "Blows exchanged."
		)
	)


## Walk away from a live fight. The purge rides it for the reason it rides a verdict: the
## fight is over the moment the player stops trading blows, whatever the reason.
func act_leave() -> bool:
	_bind_nodes()
	if actor() == null:
		return _reject(REASON_NO_HERO)
	if not _disengage.is_valid():
		return _reject(REASON_NO_FIGHT_SEAM)
	var result: Variant = _disengage.call()
	_purge_combat_scope()
	return _settle(result as Dictionary if result is Dictionary else {}, "You break off.")


## Advance the fight's clock by `seconds` and report whether the next blow is ready.
##
## Exposed as a verb rather than driven by a frame callback on purpose, for two reasons.
## ADR 0106 gives the game exactly ONE clock and `tests/app/test_status_clock.gd` pins
## the frame drivers in `res://src` to an exact allowlist — a screen is not allowed to
## add one. And the anchor is a statement about how many blows sixty seconds buys, which
## is checkable headlessly: a probe ages by sixty and counts, rather than trusting a
## frame rate it does not control.
func act_age(seconds: String = "") -> bool:
	_bind_nodes()
	if actor() == null:
		return _reject(REASON_NO_HERO)
	if not _age.is_valid():
		return _reject(REASON_NO_FIGHT_SEAM)
	var span := seconds.to_float() if not seconds.is_empty() else 1.0
	var result: Variant = _age.call(span)
	return _settle(result as Dictionary if result is Dictionary else {}, "")


func focus_initial() -> void:
	_bind_nodes()
	if _start_button == null:
		return
	_focus_target = String(_start_button.name)
	if _start_button.is_inside_tree():
		_start_button.grab_focus()


func on_stack_input(_event: InputEvent) -> bool:
	return false


# --- Plumbing ---------------------------------------------------------------


## The fight as `FightLoop.summary()` publishes it, or `{}`. **Read fresh on every
## call**, never cached: the loop is reachable from outside this screen — a probe, the
## composition root, the next drive — and a panel assembled from a stale payload beside a
## live number is a screen describing two fights at once. This is
## `LootEncounterScreen.summary()`'s rule, restated because a fight is the one surface
## where a stale read is most legible as a lie.
func _current() -> Dictionary:
	if not _read.is_valid():
		return {}
	var produced: Variant = _read.call()
	return produced as Dictionary if produced is Dictionary else {}


## The rate gate as the buttons read it: a blow is offered whenever the fight is live and
## the hand is ready. **The gate is published, not hidden** — a player who cannot see why
## the strike button is greyed cannot act on it (ADR 0150).
func _enabled(fighting: bool) -> Dictionary:
	var fight := _current()
	return {
		"start": actor() != null and _begin.is_valid() and not fighting,
		"strike": actor() != null and _exchange.is_valid() and fighting,
		"leave": actor() != null and _disengage.is_valid() and fighting,
	}


func _bind_nodes() -> void:
	if _bound:
		return
	_bound = true
	_header_label = get_node_or_null("%FightHeader") as Label
	_start_button = get_node_or_null("%StartButton") as Button
	_strike_button = get_node_or_null("%StrikeButton") as Button
	_leave_button = get_node_or_null("%LeaveButton") as Button
	_panel = get_node_or_null("%FightPanel") as FightPanel
	if _start_button != null and not _start_button.pressed.is_connected(act_start):
		_start_button.pressed.connect(act_start)
	if _strike_button != null and not _strike_button.pressed.is_connected(act_strike):
		_strike_button.pressed.connect(act_strike)
	if _leave_button != null and not _leave_button.pressed.is_connected(act_leave):
		_leave_button.pressed.connect(act_leave)


func _refresh_view() -> void:
	_bind_nodes()
	if _panel != null:
		_panel.show_fight(_current())
	if _header_label != null:
		_header_label.text = HEADER_TEXT if actor() != null else "Fight — no hero"
	var offered := _enabled(bool(_current().get("fighting", false)))
	if _start_button != null:
		_start_button.disabled = not bool(offered["start"])
	if _strike_button != null:
		_strike_button.disabled = not bool(offered["strike"])
	if _leave_button != null:
		_leave_button.disabled = not bool(offered["leave"])


## Run ADR 0089's purge and record the ids it cleared. A no-op when unwired, because an
## unwired purge is a missing bookkeeping step and never a refusal to let a player leave a
## fight — the same rule `LootEncounterScreen._purge_combat_scope` states.
func _purge_combat_scope() -> void:
	if not _purge.is_valid():
		_cleared = []
		return
	var produced: Variant = _purge.call()
	_cleared = []
	if produced is Array:
		for status_id in produced as Array:
			_cleared.append(String(status_id))


## A refusal repaints from the untouched fight and records itself as the latest verdict,
## so a press that never reached the loop still leaves `last_reason` naming what stopped
## it rather than leaving the previous action's verdict standing as the answer.
##
## It reports the refusal through `_settle` rather than styling the line itself, so the
## verdict this screen shows keeps the tone the OUTCOME map gives it: pressing again on
## a fight that is already won re-publishes `hero_won` and therefore reads as a win, not
## as the error a dead button wears.
func _reject(reason: String) -> bool:
	return _settle(
		{"ok": false, "reason": reason, "outcome": _current_outcome()}, "Rejected: %s" % reason
	)


## The outcome the fight currently stands at, as the page publishes it. Empty when no
## fight has been decided, which the tone map answers as neutral.
func _current_outcome() -> String:
	return String(_current().get("outcome", ""))


## The one place an action's verdict is recorded and the panel repainted. An empty
## `message` is left alone, so a verb that has no sentence to add (the clock) does not
## erase the sentence the last real action set.
##
## The tone is [method _tone_of] the OUTCOME, never the `ok` flag: an `ok` is a
## statement about whether a verb SPENT anything, and a fight that is decided stops
## spending. Routing the tone through the verdict is what stopped a won fight
## reporting `tone: "error"` while the words above it said it was won.
func _settle(result: Dictionary, message: String) -> bool:
	var ok := bool(result.get("ok", false))
	if not message.is_empty():
		set_message(message, _tone_of(result) if _is_decided(result) else _tone_of_ok(ok))
	refresh()
	return ok


## The tone this screen's map gives `result`'s outcome, or the neutral tone when the
## fight is not decided. One lookup, so a word added to `FightLoop` has exactly one
## place to be answered.
func _tone_of(result: Dictionary) -> StringName:
	var outcome := String(result.get("outcome", ""))
	var mapped: Variant = TONE_BY_OUTCOME.get(outcome, TONE_UNREAD)
	return mapped as StringName if mapped is StringName else TONE_UNREAD


## The tone for a verb that has no verdict of its own -- the rate gate, the start, the
## walk-away. `ok` is the honest signal there, because those verbs do not decide
## anything and the only question is whether the press was accepted.
func _tone_of_ok(ok: bool) -> StringName:
	return TONE_OK if ok else TONE_ERROR


## Whether `result` carries a verdict rather than a refusal or a live blow. A refusal
## republishes the decided outcome it refused over, so the map -- not `ok` -- decides
## how a press on a finished fight reads.
func _is_decided(result: Dictionary) -> bool:
	return TONE_BY_OUTCOME.has(String(result.get("outcome", "")))


## One named verb out of the injected bundle, as a `Callable`. A missing key answers an
## EMPTY callable rather than a null one, because `Callable.is_valid()` is false for both
## and a seam that read differently from its own install would be a gate that cannot fail.
func _callable_of(verbs: Dictionary, key: String) -> Callable:
	var produced: Variant = verbs.get(key, null)
	return produced as Callable if produced is Callable else Callable()
