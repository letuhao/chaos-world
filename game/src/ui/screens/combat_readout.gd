class_name CombatReadoutScreen
extends UiScreen

## The readout surface: fire one blow and read what the damage spine did to it
## (ADR 0174).
##
## ## Why this screen exists at all
##
## The engine is complete and green and NOTHING rendered it. `CombatOutcome.to_dict()`
## is a primitives-only read model written for exactly this consumer (ADR 0038) and no
## screen in `ui/` consumed it, so a wound, a necrosis, a sea erosion, a reflected hit, a
## crit and a parry were all computed and all invisible. This is the smallest surface
## that makes a fight legible: one strike, one panel of figures.
##
## ## The division of labour, exactly
##
## The screen owns NO rule and NO number. It hands the module's payload verbatim to
## [CombatReadoutPanel], which owns every `%d`, every decimal and every verdict word
## (AGENTS.md, ADR 0030, ADR 0038). A second place to format one figure is the defect
## the standard names.
##
## ## Why the strike arrives as a CALLABLE and not as a module call
##
## `CombatEngineApi.resolve_hit` takes a `TechniqueDef`, and `TechniqueDef` is a class in
## `modules/techniques/` — a module a `ui/` screen may reach only through its facade.
## Holding one in a typed field is a bare cross-module edge the arch gate refuses, the
## same constraint `TechniqueLoadoutScreen._casting` already works under. So this screen
## does not hold a technique at all: it calls an injected
## `Callable(actor, target) -> Dictionary`, and the composition root supplies the one
## that knows how to resolve a blow. **That is ADR 0143's seam, the same shape the quest
## screen's accept verb and the soul screen's save status use**, and it is the reason
## this screen needs no `techniques` grant and no authored technique of its own.
##
## ## And the fight is the READER'S, not an invented mechanic
##
## Unwired, every verb refuses by name and the screen says so on its own line. There is
## no dummy opponent minted here — `ui/` may not name `ActorFactory` (`app/` is a
## `PRIVATE_UNIT`), so a practice body arrives as part of the same seam.
##
## Contract: `summary()` is the testable surface, primitives only, with the panel's
## summary nested under `readout`. `{}` with no actor.

## Every refusal, named. A verb that quietly does nothing is the shape a player cannot
## act on (ADR 0150), so each of these is a distinct reason rather than a bare false.
const REASON_NO_HERO := "no_hero"
const REASON_NO_STRIKE := "no_strike_seam"
const REASON_NO_TARGET := "no_target"
const REASON_REFUSED := "refused"
## The panel's own line when no blow has been struck is the panel's, not this screen's.
const NO_HERO := "No hero bound."
const NO_SEAM := "Nothing on this screen can strike yet, so there is nothing to read."
const HEADER_TEXT := "One blow, read to the last stage."

var _readout: CombatReadoutPanel = null
var _strike_button: Button = null
var _clear_button: Button = null
var _header: Label = null
var _target_label: Label = null
## The injected strike seam: `func(attacker: Actor, defender: Actor) -> Dictionary`
## answering a primitives-only payload. Supplied by the composition root.
var _strike: Callable = Callable()
## The drill opponent. Injected beside the strike, for the same reason: `ui/` may not
## mint an `Actor`.
var _target: RefCounted = null
## The companion read: `func() -> Dictionary` answering `{band, actor, wounds}`. The
## three facts `to_dict()` does not carry — the roll that was NOT taken, the thrower's
## own stat line, and the ledger that outlives the blow.
var _read: Callable = Callable()
## The last blow, verbatim. Held so `summary()` reports the SAME dictionary the panel
## rendered — a readout that re-derived its own copy would be a second opinion.
var _last: Dictionary = {}
var _last_ok: bool = false
var _last_reason: String = ""
var _hits: int = 0
var _bound: bool = false


func _summary() -> Dictionary:
	_bind_nodes()
	var hero := actor()
	if hero == null:
		return {}
	return {
		"hero": String(hero.id),
		"strike_wired": _strike.is_valid(),
		"has_target": _target != null,
		"hits": _hits,
		"fired": _hits > 0,
		"last_ok": _last_ok,
		"last_reason": _last_reason,
		"readout": _readout.summary() if _readout != null else {},
		"enabled":
		{
			"strike": _strike.is_valid() and _target != null,
		},
	}


## Inject the strike seam, the body it strikes, and the read of what the strike left.
## All three are Callables/Actor from the composition root, for the reason above.
##
## `strike` is `func(attacker: Actor, defender: Actor) -> Dictionary` answering
## `CombatOutcome.to_dict()` VERBATIM, and `readout` is `func() -> Dictionary` answering
## `{band, actor, wounds}` — the two facts `to_dict()` deliberately does NOT carry. The
## screen never edits either payload, so what the panel renders and what a test reads are
## the objects the engine produced.
##
## `readout` is separate rather than folded into `strike` because a BAND ROLL IS NOT A
## STAGE OF THE HIT: `to_dict` decomposes one resolved blow, and a roll the strike did
## not consume is a different fact from a number the engine produced. Folding it in
## would make a readout show a draw the blow never saw. So the root reads it separately
## and this screen labels it for what it is.
##
## Safe to call again; the panel repaints from whatever the last strike said.
func bind_strike(strike: Callable, target: Variant = null, readout: Callable = Callable()) -> void:
	_strike = strike
	_target = target as RefCounted
	_read = readout
	refresh()


## Whether the strike seam is wired. Published by `summary()` so a probe can tell "the
## screen refused because nothing can strike" from "the module refused the blow" — the
## two read as an empty line otherwise.
func strike_wired() -> bool:
	return _strike.is_valid()


## The body this screen strikes, or null.
func target() -> Actor:
	return _target as Actor


## Fire one blow and read it. Returns the engine's own `ok`.
##
## ## The payload is passed through UNCHANGED
##
## `to_dict()` returns `{}` for a miss, and that is the screen's "missed" answer rather
## than a fabricated zero-row: a panel that rendered `0` for a swing that never landed
## would teach the reader that a whiff and a gut-punch are the same event, which is the
## whole reason the empty dict exists.
func act_strike() -> bool:
	_bind_nodes()
	var hero := actor()
	if hero == null:
		return _reject(REASON_NO_HERO)
	if not _strike.is_valid():
		return _reject(REASON_NO_STRIKE)
	if _target == null:
		return _reject(REASON_NO_TARGET)
	var produced: Variant = _strike.call(hero, _target as Actor)
	_last = produced if produced is Dictionary else {}
	_hits += 1
	_last_ok = not _last.is_empty()
	_last_reason = "" if _last_ok else "missed"
	_feed()
	set_message("Blow resolved", TONE_OK if _last_ok else TONE_ERROR)
	refresh()
	return _last_ok


## Forget the last blow. A readout that keeps painting a stale blow after the player has
## walked away from it teaches them the fight never ended.
func act_clear() -> bool:
	_bind_nodes()
	_last = {}
	_last_ok = false
	_last_reason = ""
	_hits = 0
	_feed()
	refresh()
	return true


# --- ScreenStack hooks ------------------------------------------------------


func focus_initial() -> void:
	_bind_nodes()
	if _strike_button == null:
		return
	_focus_target = String(_strike_button.name)
	if _strike_button.is_inside_tree():
		_strike_button.grab_focus()


func on_stack_input(_event: InputEvent) -> bool:
	return false


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	super()
	if _bound:
		return
	_bound = true
	_header = get_node_or_null("%ReadoutHeader") as Label
	_target_label = get_node_or_null("%TargetLabel") as Label
	_readout = get_node_or_null("%ReadoutPanel") as CombatReadoutPanel
	_strike_button = get_node_or_null("%StrikeButton") as Button
	_clear_button = get_node_or_null("%ClearButton") as Button
	if _strike_button != null and not _strike_button.pressed.is_connected(act_strike):
		_strike_button.pressed.connect(act_strike)
	if _clear_button != null and not _clear_button.pressed.is_connected(act_clear):
		_clear_button.pressed.connect(act_clear)


## Hand the panel exactly what the panel should show. The screen reads no figure off the
## payload — it does not even look inside it — which is what makes "the panel owns every
## number" a property rather than a convention.
##
## ## The four reads, and why they are four reads and not one
##
## 1. the outcome, verbatim from the strike;
## 2. the CONTEXT the composition root folds together — the band roll, the thrower's own
##    stat line, and the mechanism this hit was resolved through. None of the three is a
##    field of `to_dict()`, because `to_dict` decomposes ONE resolved blow and carries
##    nothing about the roll that was NOT taken, nothing about the attacker, and nothing
##    about which mechanism produced the number. `CombatBoot` is the only layer that knows
##    all three — it is the composition root and it chose the mechanism at S4 — so this
##    screen asks it as ONE call rather than re-deriving any of it.
## 3. the wound ledger the last blow earned, read through the module's own facade.
##
## The panel is never handed a partial payload for shape's sake: each of these three is a
## separate fact about a fight, and folding them into the outcome dictionary would have
## meant the engine's read model carried things the engine did not produce.
##
## `CombatOutcome.describe()` exists for the same reason and is deliberately NOT used: it
## is a sentence, and the panel owns sentences.
func _feed() -> void:
	if _readout == null:
		return
	var context: Dictionary = _read_context()
	_readout.show_hit(_last, context["band"], context["actor"], context["mechanism"])
	# The ledger is read AFTER the hit, never before: `show_wounds` is the same verb the
	# panel would answer for a reader who never struck anything, so a wound earned this
	# blow and a wound carried in from earlier are the same row.
	_readout.show_wounds(_wounds_payload())


## The composition root's one answer: `{band, actor, mechanism}`, all primitives. A root
## that injected no `readout` callable yields three empties, which the panel renders as
## blanks rather than as zeros — the same rule as the outcome payload.
func _read_context() -> Dictionary:
	var answer: Dictionary = {}
	if _read.is_valid():
		var produced: Variant = _read.call()
		if produced is Dictionary:
			answer = produced as Dictionary
	var band: Variant = answer.get("band", {})
	var actor_view: Variant = answer.get("actor", {})
	return {
		"band": band if band is Dictionary else {},
		"actor": actor_view if actor_view is Dictionary else {},
		"mechanism": StringName(answer.get("mechanism", &"")),
	}


## The wound ledger the last blow earned, as the primitives the panel renders: read
## through `CombatEngineApi.wounds_of` and flattened by `to_dict()`, so the panel sees
## the same two dictionaries a save carries and never a module object. A body that was
## never struck and a body that was struck and healed read the same empty ledger, and the
## panel says so on its own line rather than the screen inventing a "none" verdict.
func show_wounds() -> void:
	if _readout == null:
		return
	_readout.show_wounds(_wounds_payload())


func _wounds_payload() -> Dictionary:
	var ledger := CombatEngineApi.wounds_of(target())
	if ledger == null:
		return {}
	return ledger.to_dict()


func _refresh_view() -> void:
	_bind_nodes()
	if _header == null:
		return
	_header.text = HEADER_TEXT if actor() != null else NO_HERO
	if _target_label != null:
		_target_label.text = _target_text()
	if _strike_button != null:
		_strike_button.disabled = not (strike_wired() and _target != null)


## The seam's own state as a sentence, so "nothing can strike" is never drawn as zeros.
func _target_text() -> String:
	if _target == null:
		return NO_SEAM
	return "Striking %s" % String(_target.id)


func _reject(reason: String) -> bool:
	_last_ok = false
	_last_reason = reason
	set_message("Rejected: %s" % reason, TONE_ERROR)
	refresh()
	return false
