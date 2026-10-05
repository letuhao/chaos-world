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
## `extends`, no second accessor. `ClanApi.join` and `ClanApi.admission_unmet` are
## reached the same way `SectScreen` reaches `SectApi.join`: both are PUBLISHED verbs on
## a GRANTED module, so naming them by bare name is the whole of the seam and a Callable
## wrapping a facade call the screen may already make would be ceremony (the
## `ROUTE_FLOOR` arm's argument).
##
## **The registration is the one thing this screen may NOT name.** `ClanHeir` is a
## module interior, `clan` publishes twelve verbs and `rules.MAX_FACADE_PUBLIC_METHODS`
## is twelve, and `app/` is a `PRIVATE_UNIT`. So the verb arrives as a `Callable` bound by
## the composition root at route mount — ADR 0143's seam, the same one `ROUTE_FORAGE`,
## `ROUTE_QUEST` and `ROUTE_SOUL_HEARTH` use, and the exact seam `app/clan_registry.gd`
## was written for. A screen mounted without it refuses `no_register_seam` rather than
## pretending the house spoke.
##
## ## ## THE JOIN LIVES HERE, and ADR 0239 named this slice as owed
##
## `ClanApi.join` shipped with ZERO production callers, so no player was ever a member
## of a house and `ClanRegistry.available` refused `not_a_member` for every real actor.
## The page the same ADR built was therefore a route to a page whose only action
## refused by construction. **This is the owner of that moment.**
##
## Why the page and not somewhere else, in the ADR's own terms: joining a house is
## something a player DOES, with a house they have chosen, at a place the game asks them
## about it. ADR 0113's rule is that the owner of the moment writes and never a poller —
## and a timer that admitted somebody would be the political layer deciding its own
## outcomes, which is the reading ADR 0239 rejected in writing. So the press is a
## control, and this page is where the control lives, beside `SectScreen.act_join` and
## `NationScreen`'s own entry verb.
##
## ## ## And the JOIN costs nothing but what the house already publishes
##
## **There is no economy here, deliberately.** A house's price for admitting somebody is
## authored on the house itself — `min_purity` against its own founding bloodline, plus
## `required_race` / `min_realm` — and `ClanGate.admission_unmet` already reads all three
## and returns the complaints by name. So joining **GATES** on an authored requirement the
## game already models and **COSTS** nothing this slice had to invent: no currency, no
## stat, no tax, no new field on `ClanDef`. A member arrives at the house's own
## `entry_rank` and at standing 0, which is ADR 0064's split stated as a fact — joining
## is being RECOGNISED, not being RESPECTED.
##
## `join` itself re-runs the same gate before it writes, so a screen that pre-judged it
## would be guessing at a rule the module owns. This page asks the gate only to decide
## whether to OFFER the press, and renders the module's own refusal when it does — the
## same "`sect_screen` leaves the button live and lets the module say `already_sworn`"
## argument, read one level down: the player is told WHICH lineage a house wants.
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

## ## The action that ADDS a hero to a house, and the one that takes them out again.
##
## Both are here rather than in a second screen because a clan is a STANDING with
## obligations (ADR 0064): you have to be able to walk out of it from the same page you
## walked into, or `leave` is a verb no player can reach — the mirror of the gap this
## slice closes. `SectScreen` publishes the same pair.
const ACTION_JOIN := &"join"
const ACTION_LEAVE := &"leave"

## The refusals this screen raises ITSELF, before the seam is asked. One is a wiring gap
## and one is a player outcome; both are named rather than silently doing nothing, and
## they are the screen's OWN words because no module publishes them.
## No hero is bound, so there is nobody a house could enter in its register.
const NO_ACTOR := "no_actor"
## The route mounted this screen without the registration seam. A wiring fault, reported
## rather than guessed around — the same `no_register_seam` the quest and soul screens
## refuse, so one renderer covers all of them.
const NO_REGISTER_SEAM := "no_register_seam"
## A `join` was asked for with no house picked. The refusal of the SCREEN's own seam,
## authored here for the reason `sect_screen` authors its own two: a silent no-op is not
## a refusal, and a screen that fell back to the first house in the list would admit
## somebody to a house nobody chose.
const NO_HOUSE_PICKED := "no_house_picked"

const NO_ACTOR_TEXT := "No hero bound."
const NO_ACTOR_FOOTER := ""
const FOOTER_TEXT := "Enter names the member in the house's register as its heir."
const TERMS_EMPTY := "This house publishes no terms."
const NO_HOUSE_TEXT := "You belong to no house."
## What a hero who has not yet been admitted is told instead of a silently dead bar.
const JOIN_HINT_TEXT := "Pick a house you are admitted to, and press Ask."

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
## The catalog row [method act_join] would ask this hero to enter. `""` means nothing is
## picked, and a `join` with nothing picked is refused [constant NO_HOUSE_PICKED] rather
## than silently admitting them to the first house in the list.
##
## Picked by the CALLER (a panel, a row, a probe) rather than by a screen-internal widget:
## `ClanScreen` has no roster scene of its own and a screen that grew its own would be a
## second house list beside the catalog the facade already publishes in `summary`.
var _selected_clan: String = ""
## Every read model this screen PUBLISHES that is computed from the facade's snapshot
## rather than from the widget tree. Adopted in `_render` and `_summary` so
## [method select_clan] reads the SAME catalog the page paints and cannot accept an id
## the facade does not publish. `{}` before the first read.
var _codex: Dictionary = {}
## The last verb's verdict, carried through verbatim. `{}` before any action, so a test
## reads "no action yet" rather than a refusal that never happened.
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
	# Adopted here rather than in `_bind_nodes`, so `select_clan` reads the SAME catalog
	# the page renders and cannot pass an id the facade does not publish.
	_codex = codex.duplicate(true)
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
		# The membership half, published as the FACADE's own two numbers so a probe can
		# read "is this hero a member" without reaching into `actor.module_data`, and so
		# the join is observable at both ends: the ledger before and after a press.
		"is_member": String(codex.get("clan", "")) != "",
		# Which house the next `act_join` would use, and whether the control is live.
		"selected_clan": _selected_clan,
		"can_join": can_join(),
		"can_leave": can_leave(),
		# What the MODULE's gate says about the picked house. Kept as a count plus the
		# authored complaints, never a boolean, so a hero turned away is told WHICH
		# lineage the house wants rather than merely that a press failed.
		"join_unmet_count": join_unmet().size(),
		"join_unmet": _complaint_list(join_unmet()),
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


## ## ## THE ONLY CALLER OF `ClanApi.join` IN THE SHIPPED PROGRAM
##
## Before this method, `ClanApi.join` had zero production callers: every player belonged
## to no house, `ClanRegistry.available` refused `not_a_member` for every real actor, and
## the three authored quests watching `household_heir_registered` were permanently
## unfinishable. This press is what closes that, and it is here because a house admits a
## person in response to the person CHOOSING it — not on a timer (ADR 0113).
##
## Returns `ClanApi.join`'s own verdict `{ok, reason, unmet}` unchanged, so a caller
## reads the module's refusal (`unmet` with the authored `{kind, id, required, actual,
## label}` entries) rather than a sentence this screen composed about it.
##
## **`standing` is deliberately NOT passed.** `join` defaults it to 0 and a member who
## has just been admitted has earned nothing yet — ADR 0064's split, and passing a
## number from a button would let a screen hand out standing by typing a literal.
func act_join(clan_id: String = "") -> Dictionary:
	_bind_nodes()
	var wanted := clan_id if clan_id != "" else _selected_clan
	if _actor == null:
		return _verdict(NO_ACTOR)
	if wanted == "":
		return _verdict(NO_HOUSE_PICKED)
	# The gate is asked once more here than the button needs, and that is the point:
	# `join` re-runs it itself, so a press on a house this hero is not admitted to is
	# REFUSED BY NAME and writes nothing, rather than the button being the only thing
	# stopping it. The module decides; this screen only reports.
	return _settle(ClanApi.join(_actor, StringName(wanted)))


## Walk out of the house this hero belongs to. Returns `ClanApi.leave`'s verdict.
##
## Live for every member, always: leaving is always permitted and always costs, and the
## cost is the standing, which does not survive the membership (ADR 0064). A page that
## could only admit you would be a house with no door.
func act_leave() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _verdict(NO_ACTOR)
	return _settle({"ok": ClanApi.leave(_actor), "reason": ""})


## Pick the house [method act_join] would ask this hero to enter. Returns false for an
## id the facade's catalog does not carry, so a caller can never "select" a house that
## does not exist; `""` clears the selection rather than leaving a stale one behind.
##
## **The catalog is the facade's, read out of `summary()["clans"]`** — the same dict the
## module already publishes for a screen to compare houses with, so this is not a second
## roster and not a list this file could drift from.
func select_clan(clan_id: String) -> bool:
	_bind_nodes()
	if clan_id == "":
		_selected_clan = ""
	elif (_codex.get("clans", {}) as Dictionary).has(clan_id):
		_selected_clan = clan_id
	else:
		return false
	_render()
	return true


## The house the next [method act_join] would use, or `""`. Published in `summary()` so a
## caller reads the same fact the button acts on rather than a second accessor that can
## go stale against the pick.
func selected_clan() -> String:
	return _selected_clan


## Whether a hero may ask to be admitted to a house from here right now. **Only** an
## actor and a house being picked gate the control: whether this hero is ADMITTED is the
## module's refusal to name (`ClanApi.admission_unmet`), not a reason to grey out a
## button — a hero turned away should be told WHICH lineage a house wants by pressing,
## not by a control that silently does nothing. The same argument `sect_screen` makes
## about `already_sworn`.
func can_join() -> bool:
	return _actor != null and _selected_clan != ""


## Whether a hero may walk out of their house from here.
func can_leave() -> bool:
	return _actor != null and ClanApi.clan_of(_actor) != &""


## What the module's OWN admission gate says about the picked house, as the
## `{kind, id, required, actual, label}` complaints `ClanGate` produces. `[]` means the
## admission is open; a screen that re-derived any of it would be a second copy of the
## house's policy, which is the exact thing ADR 0064's refusals exist to prevent.
func join_unmet() -> Array:
	if _actor == null or _selected_clan == "":
		return []
	return ClanApi.admission_unmet(_actor, StringName(_selected_clan)) as Array


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
	_standing_before = str(ClanApi.standing_of(_actor))
	var called: Variant = _register.call(_actor)
	var answer: Dictionary = called if called is Dictionary else {}
	_standing_after = str(ClanApi.standing_of(_actor))
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


## `ui_accept` on the screen: the action this page's primary button runs. Declared in
## one place because two consumers (`on_stack_input` and the action bar) must agree on
## what a press means.
##
## Which verb `ui_accept` runs is read off the SAME [method _primary_action] the action bar
## publishes, so the keyboard and the button can never mean different things — the bug
## that `sect_screen` avoids by matching its bar's `primary` to `can_join()`.
func _accept() -> bool:
	var verb := _primary_action()
	if _actor == null or verb == &"":
		return false
	match verb:
		ACTION_JOIN:
			act_join()
		ACTION_LEAVE:
			act_leave()
		ACTION_REGISTER:
			act_register_heir()
		_:
			return false
	return true


## The verb a bare `ui_accept` runs, or `&""` when none is live.
##
## **Join first, then leave, then the register.** A hero who belongs to no house has
## nothing to register in and nothing to leave, so `join` is the only candidate they can
## reach — which is what makes this page the owner of the admission moment rather than a
## page that happens to also admit people. A member gets `leave` and, once the seam's gate
## agrees, `register`.
func _primary_action() -> StringName:
	if can_join():
		return ACTION_JOIN
	if can_leave():
		return ACTION_LEAVE
	if _actor != null and register_seam_bound() and bool(_available().get("ok", false)):
		return ACTION_REGISTER
	return &""


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
	_codex = codex.duplicate(true)
	var footer := _footer_line(codex)
	_house.text = _house_line(codex)
	_terms.text = _terms_line(codex)
	_footer.text = String(footer.get("text", ""))
	_publish_actions()


## The line under the terms. **A hero who belongs to no house is told so and told what to
## do about it**, which is what makes the join reachable rather than merely present: a
## page that showed a dead button and no instruction would leave the one verb that closes
## this gap unpressable in practice.
##
## The refusal text is the MODULE's own `label` on the complaint it raised — a house says
## which lineage it admits, and this screen restates none of it.
func _footer_line(codex: Dictionary) -> Dictionary:
	var held := String(codex.get("clan", ""))
	if held == "":
		var unmet := join_unmet()
		if unmet.is_empty():
			return {"text": JOIN_HINT_TEXT}
		var complaint: Dictionary = unmet[0]
		return {"text": String(complaint.get("label", ""))}
	return {"text": FOOTER_TEXT}


## The one line naming the house. **Every number is the facade's own**, formatted here
## rather than restated: a screen that composed its own standing sentence would be a second
## copy of a number `ClanApi.summary` already published.
func _house_line(codex: Dictionary) -> String:
	var house := String(codex.get("display_name", ""))
	if house == "":
		return NO_HOUSE_TEXT
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


## The module's admission complaints as an `Array[Dictionary]`, left in the facade's own
## `{kind, id, required, actual, label}` shape rather than flattened to strings. A panel
## renders `label`; a test compares `kind` and `required`; neither needs this screen to
## have invented a vocabulary for the same eight failures.
func _complaint_list(unmet: Array) -> Array:
	var out: Array = []
	for entry in unmet as Array:
		out.append(entry as Dictionary)
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
				"labels":
				{
					ACTION_JOIN: "Ask the picked house to admit you",
					ACTION_LEAVE: "Walk out of your house",
					ACTION_REGISTER: "Enter as the house's heir",
				},
				"enabled": _enabled_actions(),
				"primary": _primary_action(),
			}
		)
	)


## The action ids, in the order the bar shows them. Read off the constants above so the
## order a test reads is the order the player sees. **Join and leave LEAD**, because they
## are the acts that put the hero on and off a ladder; the register is third because it is
## only meaningful to somebody already on one.
func _action_ids() -> Array:
	return [String(ACTION_JOIN), String(ACTION_LEAVE), String(ACTION_REGISTER)]


## Which of the three is live right now.
##
## `register` is live only when the seam is bound AND the seam's own gate says this hero
## could honestly be entered: a button that could mean nothing is a button that teaches a
## player that the page does not work.
##
## `join` is live on a hero + a pick and **NOT** on whether the hero is admitted — the
## module owns that verdict and a player turned away deserves to be told WHICH lineage the
## house wants, which only a press can say. `leave` is live for every member, always.
func _enabled_actions() -> Dictionary:
	var gate := _available()
	return {
		String(ACTION_JOIN): can_join(),
		String(ACTION_LEAVE): can_leave(),
		String(ACTION_REGISTER): _actor != null and bool(gate.get("ok", false)),
	}


## The button press, routed to the verb. `ActionSet.request` refuses a disabled action,
## so this cannot fire a verb the control does not offer.
func _on_action_requested(action: StringName) -> void:
	match action:
		ACTION_JOIN:
			act_join()
		ACTION_LEAVE:
			act_leave()
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
