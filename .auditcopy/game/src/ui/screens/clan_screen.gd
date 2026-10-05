class_name ClanScreen
extends UiScreen

## The clan page: whose house this hero belongs to, what it recognises them for, and the
## ONE verb a house has over a member — entering them in its register as its heir.
##
## ## ## Why this screen exists at all (DEF-0229 / DEF-0286)
##
## `ClanHeir.register` shipped with **ZERO production callers**, and it is the sole
## writer of `household_heir_registered`. Four authored quests demand that fact
## (`the_account_left_open`, `the_station_you_held`, `the_severed_calling`,
## `the_terms_you_drafted`), so two fates and one destiny were unobtainable through
## content. The honest owner of the moment is **a house**, and a house had no way to
## speak: `ui/` shipped `sect_screen` and `nation_screen` and no clan screen at all.
## `app/clan_registry.gd` documented the missing seam precisely and had no caller.
## **This is that surface.**
##
## ## ## It is a PURE consumer of the facade, plus ONE injected verb
##
## `clan` is declared in `rules.UI_MODULES`, so this screen may name `ClanApi` bare and
## read everything the page shows — the house, the rank, the standing, the recognised
## standing and both sides of the terms — out of one `summary()` call. No `preload`, no
## `extends`, no second accessor.
##
## **The registration is the one thing this screen may NOT name.** `ClanHeir` is a
## module interior, `clan` publishes twelve verbs and `rules.MAX_FACADE_PUBLIC_METHODS`
## is twelve, and `app/` is a `PRIVATE_UNIT`. So the verb arrives as a `Callable` bound by
## the composition root at route mount — ADR 0143's seam, the same one `ROUTE_FORAGE`,
## `ROUTE_QUEST` and `ROUTE_SOUL_HEARTH` use, and the exact seam `app/clan_registry.gd`
## was written for. A screen mounted without it refuses `no_register_seam` rather than
## pretending the house spoke.
##
## ## ## The verb is a REGISTRATION, and it moves the position and nothing else
##
## ADR 0064's split is the whole contract: `register` writes `rank` and never `standing`.
## The page publishes `last_standing_before` / `last_standing_after` beside the verdict so
## the split is OBSERVABLE on screen rather than merely asserted in a docstring — a house
## that registered its heir and moved no standing is the module's promise, and a test can
## read it off the summary without reaching into the ledger.
##
## ## ## The ladder decides whether the press can mean anything
##
## `ClanRegistry.available` answers the whole question — is this hero a member, does THIS
## house publish an `heir` rung, are they already entered — and refuses by the module's own
## name. The screen asks it, renders the refusal verbatim, and only enables the press when
## it says yes. It never re-derives a house's policy from the rank list.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` with no actor.

## The one action this page publishes. Declared as a constant so the order a test reads is
## the order the player sees.
const ACTION_REGISTER := &"register_heir"

## The refusals this screen raises ITSELF, before the seam is asked. One is a wiring gap
## and one is a player outcome; both are named rather than silently doing nothing, and
## they are the screen's OWN words because no module publishes them.
## No hero is bound, so there is nobody a house could enter in its register.
const NO_ACTOR := "no_actor"
## The route mounted this screen without the registration seam. A wiring fault, reported
## rather than guessed around — the same `no_register_seam` the quest and soul screens
## refuse, so one renderer covers all of them.
const NO_REGISTER_SEAM := "no_register_seam"

const NO_ACTOR_TEXT := "No hero bound."
const NO_ACTOR_FOOTER := ""
const FOOTER_TEXT := "Enter names the member in the house's register as its heir."
const TERMS_EMPTY := "This house publishes no terms."

var _house: Label = null
var _terms: Label = null
var _footer: Label = null
var _actions: ActionSet = null
var _bound: bool = false
## The registration seam, injected by the composition root as a pair: the verb that
## commits and the gate that says whether it could mean anything. Both empty until bound,
## and [method act_register_heir] refuses by name until then.
##
## **Two callables, not one**, because `ClanRegistry` publishes `commit` AND `available`
## and a screen that could only press would have to re-derive the gate to decide whether to
## offer the press. Re-deriving it here would be a SECOND copy of the house's policy — the
## exact thing ADR 0064's `has_rank` refusal exists to refuse.
var _register: Callable = Callable()
var _register_available: Callable = Callable()
## The last verdict, carried through verbatim. `{}` before any action, so a test reads "no
## action yet" rather than a refusal that never happened.
var _last_result: Dictionary = {}
## The standing this hero held before the last registration and after it, so the ADR 0064
## split is readable without a second facade call. `""` until a registration has run.
var _standing_before: String = ""
var _standing_after: String = ""


## Inject the registration seam the screen may not name: `commit` is the verb a press
## runs and `available` is the gate that says whether it could mean anything. Both are
## `ClanRegistry` statics at every production mount.
##
## Passing empty Callables unbinds, which is how a test reaches `no_register_seam` on
## purpose rather than by forgetting to bind.
func bind_register(register: Callable, available: Callable = Callable()) -> void:
	_bind_nodes()
	_register = register
	_register_available = available
	_render()


## Whether BOTH halves of the seam are bound. One conjunct: `commit` without `available`
## can press but cannot decide whether to offer the press, so a half-bound screen is not a
## bound one.
func register_seam_bound() -> bool:
	return _register.is_valid() and _register_available.is_valid()


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var codex := ClanApi.summary(_actor)
	return {
		"actor": String(_actor.id),
		"read_only": false,
		"has_actor": bool(codex.get("has_actor", false)),
		"clan": String(codex.get("clan", "")),
		"known": bool(codex.get("known", false)),
		"display_name": String(codex.get("display_name", "")),
		"rank": String(codex.get("rank", "")),
		"standing": int(codex.get("standing", 0)),
		"recognition": float(codex.get("recognition", 0.0)),
		"recognition_scale": float(codex.get("recognition_scale", 1.0)),
		"outranks_standing": bool(codex.get("outranks_standing", false)),
		"founding_bloodline": String(codex.get("founding_bloodline", "")),
		"founding_purity": float(codex.get("founding_purity", 0.0)),
		"patronage": _term_list(codex.get("patronage", {})),
		"duty": _term_list(codex.get("duty", {})),
		"clan_count": int(codex.get("clan_count", 0)),
		"register_seam_bound": register_seam_bound(),
		# What the seam says RIGHT NOW, so a test and a probe can assert the gate without
		# pressing it: a member of a house publishing no `heir` rung must read
		# `no_heir_rank` here, never `ok`.
		"register_available": bool(_available().get("ok", false)),
		"register_blocked_reason": String(_available().get("reason", "")),
		"actions": _action_ids(),
		"enabled": _enabled_actions(),
		# The last verdict as primitives, so one run tells a registered heir from a house
		# that declined from a page that was never bound — the three outcomes that would
		# otherwise all read as "nothing happened".
		"refused": bool(_last_result.get("ok", true) == false),
		"last_ok": bool(_last_result.get("ok", false)),
		"last_reason": String(_last_result.get("reason", "")),
		"last_rank": String(_last_result.get("rank", "")),
		# ADR 0064's split, published as two fields rather than asserted in prose: a
		# registration that moved the standing would move the second one.
		"last_standing_before": _standing_before,
		"last_standing_after": _standing_after,
		"last_moved_standing": _moved_standing(),
	}


# --- Actions. Each calls the injected verb, and reports what came back ---------


## Ask the house to enter this hero in its register as its heir. Returns the seam's own
## verdict, unchanged, so a caller never has to read the message line to learn what
## happened.
##
## The standing is read BEFORE the verb and AFTER it, because the one property this page
## exists to make observable is that the registration moved the POSITION and nothing
## else (ADR 0064).
func act_register_heir() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _verdict(NO_ACTOR)
	if not register_seam_bound():
		return _verdict(NO_REGISTER_SEAM)
	_standing_before = String(ClanApi.standing_of(_actor))
	var called: Variant = _register.call(_actor)
	var answer: Dictionary = called if called is Dictionary else {}
	_standing_after = String(ClanApi.standing_of(_actor))
	return _settle(answer)


## Whether the registration would mean anything right now. The seam's own gate, read
## without pressing it, and `{}` when the seam is unbound so a caller can tell "no seam"
## from "a gate refused".
##
## **Delegated whole.** This never inspects the rank ladder, the membership or the house
## list: `ClanRegistry.available` already answers every one of those with the module's own
## refusal names, and a second copy here would be a second authority on who may be heir.
func _available() -> Dictionary:
	if _actor == null or not register_seam_bound():
		return {}
	var called: Variant = _register_available.call(_actor)
	return called if called is Dictionary else {}


## `ui_accept` on the screen: the one action this page has. Declared in one place because
## two consumers (`on_stack_input` and the action bar) must agree on what a press means.
func _accept() -> bool:
	if _actor == null or not register_seam_bound():
		return false
	act_register_heir()
	return true


# --- Internals ---------------------------------------------------------------


func _bind_nodes() -> void:
	super()
	if _bound:
		return
	_house = get_node_or_null("%HouseLabel") as Label
	_terms = get_node_or_null("%TermsLabel") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_actions = get_node_or_null("%Actions") as ActionSet
	_bound = true
	_connect_actions()


## Guarded by `is_connected` so a reused or cached screen accumulates exactly one handler.
func _connect_actions() -> void:
	if _actions == null:
		return
	if not _actions.action_requested.is_connected(_on_action_requested):
		_actions.action_requested.connect(_on_action_requested)


func _refresh_view() -> void:
	_render()


func _render() -> void:
	if _house == null:
		return
	if _actor == null:
		_house.text = NO_ACTOR_TEXT
		_terms.text = ""
		_footer.text = NO_ACTOR_FOOTER
		_publish_actions()
		return
	var codex := ClanApi.summary(_actor)
	_house.text = _house_line(codex)
	_terms.text = _terms_line(codex)
	_footer.text = FOOTER_TEXT
	_publish_actions()


## The one line naming the house. **Every number is the facade's own**, formatted here
## rather than restated: a screen that composed its own standing sentence would be a second
## copy of a number `ClanApi.summary` already published.
func _house_line(codex: Dictionary) -> String:
	var house := String(codex.get("display_name", ""))
	if house == "":
		return "You belong to no house."
	return (
		"%s — %s, standing %d (recognised %d)."
		% [
			house,
			String(codex.get("rank", "")),
			int(codex.get("standing", 0)),
			int(codex.get("recognition", 0.0)),
		]
	)


## Both sides of the terms on one line, or a stated absence. `patronage` and `duty` are
## PUBLISHED TERMS the module deliberately does not enforce (ADR 0064), so this page shows
## them and nothing more.
func _terms_line(codex: Dictionary) -> String:
	var owed := _term_list(codex.get("patronage", {}))
	var owed_back := _term_list(codex.get("duty", {}))
	if owed.is_empty() and owed_back.is_empty():
		return TERMS_EMPTY
	return (
		"The house owes: %s. The member owes: %s."
		% [
			", ".join(PackedStringArray(owed)),
			", ".join(PackedStringArray(owed_back)),
		]
	)


## The published terms as a sorted plain array. `summary()` already hands them sorted;
## this only flattens the array-of-strings the module returns into an `Array` a test can
## compare.
func _term_list(source: Variant) -> Array:
	var out: Array = []
	for term in source as Array:
		out.append(String(term))
	return out


## Declare this screen's actions and their live state. Only ids and booleans go down;
## `ActionSet` owns the button text and the result line.
func _publish_actions() -> void:
	if _actions == null:
		return
	(
		_actions
		. set_state(
			{
				"actions": _action_ids(),
				"labels": {ACTION_REGISTER: "Enter as the house's heir"},
				"enabled": _enabled_actions(),
				"primary": ACTION_REGISTER,
			}
		)
	)


func _action_ids() -> Array:
	return [String(ACTION_REGISTER)]


## The press is live only when the seam is bound AND the seam's own gate says this hero
## could honestly be entered. A button that could mean nothing is a button that teaches a
## player that the page does not work.
func _enabled_actions() -> Dictionary:
	var gate := _available()
	return {String(ACTION_REGISTER): _actor != null and bool(gate.get("ok", false))}


func _on_action_requested(action: StringName) -> void:
	match action:
		ACTION_REGISTER:
			act_register_heir()


## A refusal this screen raises ITSELF, in the modules' own `{ok, reason}` shape. Never a
## silent no-op.
func _verdict(reason: String) -> Dictionary:
	return _settle({"ok": false, "reason": reason})


## Record a verdict, repaint, and hand the caller the verb's OWN dictionary. The repaint
## happens AFTER the verdict is recorded, so the page the player sees is the one the
## verdict describes — a refused registration writes nothing anywhere, so painting the
## refusal over unchanged state is what makes "the world did not change, and here is why"
## legible on one line.
func _settle(result: Dictionary) -> Dictionary:
	_bind_nodes()
	_last_result = result.duplicate(true)
	set_message(
		String(_last_result.get("reason", "")),
		TONE_OK if bool(_last_result.get("ok", false)) else TONE_ERROR
	)
	refresh()
	return _last_result.duplicate(true)


## Whether the last registration moved the earned standing. False on every path that never
## ran, so "the split holds" is one readable boolean rather than two strings to compare.
func _moved_standing() -> bool:
	if _standing_before == "" or _standing_after == "":
		return false
	return _standing_before != _standing_after
