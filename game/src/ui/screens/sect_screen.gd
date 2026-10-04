class_name SectScreen
extends UiScreen

## The sect a hero is sworn to: the member's own claim, its office and its authored
## duties, the offices of the sworn sect and their live seat state, and every
## authored sect for comparison. A pure consumer of the `sect` facade — it renders
## the facade's `summary(actor)` read model and names NOTHING else in the module
## (ADR 0083/0084).
##
## ## Position and standing are TWO lines, never one rank
##
## The member's own claim is a `SectClaimRow`, and that row prints the office and the
## standing separately. This screen never divides one by the other to make a single
## number: ADR 0064's split (a high position on thin standing is possible, and thick
## standing in no position is also possible) IS the politics layer, so collapsing it
## into a rank would throw the design away at the last step.
##
## ## A refusal is a rendered state, not a blank page
##
## The member row publishes either the claim or the facade's named refusal reason.
## An unaffiliated hero gets an explicit `not_a_member` row rather than an empty
## screen, because "the three tiers are peers" (ADR 0083) means "no institution" is
## the ordinary starting state and deserves a sentence, not a void.
##
## ## This screen ACTS, and the audit that found it read-only was right to
##
## It rendered thirteen mutating verbs' worth of state and could fire none of them, so
## a player could LOOK at a sect and never join, leave or take a seat. It now calls
## three of them by name — `SectApi.join`, `SectApi.leave`, `SectApi.promote` — through
## the facade, and nothing else out of the module. The three it calls are the three a
## member's own hand is responsible for; `found`, `teach`, `declare_schism`,
## `advance_succession` and `move_standing` are council and world acts, and a button
## that fired any of them from a member's codex would make an inquisition a two-click
## accident exactly as the original comment said.
##
## ## What is NOT refused here, and why
##
## `leave` refuses on nothing but `not_a_member` (ADR 0084), so its button stays live
## for every sworn member and the refusal is RENDERED rather than the control being
## greyed out: a player who is told nothing may still be told why nothing happened. The
## same is true of a promotion below its standing floor — the floor is a ROUTE, not a
## wall, and `act_promote(office, force)` is that route. `act_promote` with `force`
## overrules the floor AND the occupied seat, because `SectApi.promote` reads those
## two refusals as one decision, and a screen that overruled only one of them would
## publish a verb that cannot do what its name says.
##
## ## The refusal is `reason` VERBATIM, never prose this screen composed
##
## Every verb answers `{ok, reason}` with an authored constant
## (`already_sworn`, `not_a_member`, `standing_below_floor`, `seat_occupied`,
## `capacity_full`, `unknown_sect`). A refused action is handed to
## `SectClaimRow.show_refusal` untouched, which is the third of ADR 0083's three states
## and renders in its own card tone. An unaffiliated hero keeps `show_claim({})`,
## which is the FIRST state, so `{}` and a refusal never read alike.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` with no
## actor, and each child's own summary nested under that child's key.

## Rows the scene mounts and this screen tops up to. The claim pool is exactly one
## row — a member holds one claim, and a spare claim row would be a second thing to
## hide — while the office pool grows, because a sect may author more offices than a
## scene can enumerate and a pool that dropped one would read as dead content.
const CLAIM_SPARE_ROWS := 0
const OFFICE_ROWS := 8
const CLAIM_SCENE := "res://src/ui/panels/sect_claim_row.tscn"
const OFFICE_SCENE := "res://src/ui/panels/nation_office_row.tscn"
const ACTIONS_SCENE := "res://src/ui/panels/action_set.tscn"
const HEADER_TEXT := "The institution you are sworn to, and what the office obliges."
const NO_ACTOR_TEXT := "No hero bound."
const FOOTER_TEXT := (
	"Up / Down picks an entry, Accept joins or is seated. Cancel returns."
	+ " An institution grants recognition and access, and never power."
)
## The footer while nothing is bound, and while there is nothing to act on. A read-only
## sentence was published here for a screen that could do nothing; a screen that can
## now act says what its controls are instead.
const NO_ACTOR_FOOTER := ""
## What the action bar offers a hero sworn to nothing: the catalog, one entry at a time.
const OFFERED_TEXT := "Offered"
## The refusals this screen itself raises, before a verb is called. Authored constants
## rather than prose, for the same reason the module's are: a panel renders a reason it
## did not have to invent.
const NO_ACTOR := "no_actor"
## The row names a sect the catalog does not ship, so nothing was called.
const UNKNOWN_SECT := "unknown_sect"
## The row names an office the sworn sect does not author.
const UNKNOWN_POSITION := "unknown_position"
## A `join` was asked for with no sect picked. A refusal of the SCREEN's own seam,
## authored here for the same reason the module authors its own: a panel renders a
## reason it did not have to invent, and a silent no-op is not a refusal.
const NO_SECT_PICKED := "no_sect_picked"
## The same for a promotion with no office picked.
const NO_OFFICE_PICKED := "no_office_picked"
## The action ids this screen publishes, in the order the bar shows them. Declared as
## constants rather than built per call so the order a test reads is the order the
## player sees — four verbs, never a growing set.
const ACTION_JOIN := &"join"
const ACTION_LEAVE := &"leave"
const ACTION_PROMOTE := &"promote"
const ACTION_PROMOTE_FORCED := &"promote_forced"

var _codex: Dictionary = {}
var _header: Label = null
var _footer: Label = null
var _claim_box: VBoxContainer = null
var _office_box: VBoxContainer = null
var _actions: ActionSet = null
var _bound: bool = false
var _claim_rows: Array = []
var _office_rows: Array = []
## The catalog row `act_join` would swear the hero to. `""` means nothing is picked, and
## a `join` with nothing picked is refused by `NO_SECT_PICKED` rather than silently
## swearing them to the first house in the list.
var _selected_sect: String = ""
## The office row `act_promote` would seat the hero in. Same rule: `""` picks nothing.
var _selected_office: String = ""
## The last verb's verdict, carried through verbatim. `{}` before any action, so a test
## reads "no action yet" rather than a refusal that never happened.
var _last_result: Dictionary = {}
## The refusal currently painted on the claim row, or `{}`. Kept so a repaint from the
## facade cannot silently erase a refusal the player has not read yet — the row shows
## the CLAIM after every successful verb, and only a refusal survives a refresh.
var _refusal: Dictionary = {}


## Adopt a facade snapshot for the bound actor (the `summary(actor)` shape).
## `setup(actor)` takes the facade path inside `_refresh_view`; this exists so a
## headless test or a driver can render from a snapshot with no actor at all, and —
## importantly — so adopting a snapshot does NOT re-enter the facade. An empty
## snapshot clears it.
func apply_snapshot(snapshot: Dictionary) -> void:
	_bind_nodes()
	_codex = snapshot.duplicate(true)
	_fill_from_codex()
	_render()


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var promotions := _promotion_summaries()
	var sects := _sect_summaries()
	return {
		"actor": String(_actor.id),
		# `read_only` is now FALSE, and it is reported rather than deleted: a caller
		# reading `true` is reading a claim this screen no longer makes. The key stays
		# so the vocabulary does not drift under a test that already asks for it.
		"read_only": false,
		"is_member": bool(_codex.get("is_member", false)),
		"sect_id": String(_codex.get("sect_id", "")),
		"sect_name": String(_codex.get("sect_name", "")),
		"doctrine_id": String(_codex.get("doctrine_id", "")),
		"position_id": String(_codex.get("position_id", "")),
		"position_name": String(_codex.get("position_name", "")),
		"standing": int(_codex.get("standing", 0)),
		"standing_cap": int(_codex.get("standing_cap", 0)),
		"standing_ratio": float(_codex.get("standing_ratio", 0.0)),
		"standing_percent": float(_codex.get("standing_percent", 0.0)),
		"teaches": bool(_codex.get("teaches", false)),
		"duties": _string_list(_codex.get("duties", [])),
		"authorities": _string_list(_codex.get("authorities", [])),
		"claim": _claim_summary(),
		# ADR 0083's three states, reported as three DISTINCT facts rather than
		# collapsed: the claim, the refusal the last verb returned, and the offered
		# catalog. A screen that renders all three cannot make them read alike.
		"refused": bool(_last_result.get("ok", true) == false),
		"refusal_reason": String(_last_result.get("reason", "")),
		"last_reason": String(_last_result.get("reason", "")),
		"last_ok": bool(_last_result.get("ok", false)),
		"can_join": can_join(),
		"can_leave": can_leave(),
		"can_promote": promotions,
		"can_promote_count": promotions.size(),
		"selected_sect": _selected_sect,
		"selected_office": _selected_office,
		"actions": _action_ids(),
		"enabled": _enabled_actions(),
		"sects": sects,
		"sect_count": sects.size(),
		"offered_ids": offered_ids(),
		"office_ids": row_ids(),
	}


# --- Actions. Each returns the facade's own verdict, verbatim ----------------


## Whether a hero may be sworn to a sect from here right now. Only the seam being
## wired and a sect actually being picked gate the control; whether the CATALOG has
## this house is the facade's refusal to name, not a reason to grey out a button.
func can_join() -> bool:
	return _actor != null and _selected_sect != ""


## Whether a hero may leave from here. True for every sworn member, always: leaving is
## always permitted and always costs (ADR 0084), and `not_a_member` is the ONLY thing
## `leave` refuses on — which is a refusal a panel RENDERS, not a reason to hide the
## control.
func can_leave() -> bool:
	return _actor != null and bool(_codex.get("is_member", false))


## Swear the bound actor to the picked sect. Returns `SectApi.join`'s verdict
## unchanged, so a caller never has to read the message line to learn what happened.
##
## `SectApi.join` is called for its rule, not for its opinion: the three tiers are
## peers (ADR 0083), so a hero already sworn is refused `already_sworn` and must leave
## first. That refusal is RENDERED through `show_refusal` and is a distinct visual
## state from "sworn to nothing", which is `show_claim({})`.
func act_join(sect_id: String = "") -> Dictionary:
	_bind_nodes()
	var wanted := sect_id if sect_id != "" else _selected_sect
	if _actor == null:
		return _verdict({NO_ACTOR: true})
	if wanted == "":
		return _verdict({NO_SECT_PICKED: true})
	var result := SectApi.join(_actor, StringName(wanted))
	return _settle(result)


## Walk out of the sect the bound actor is sworn to. Returns `SectApi.leave`'s
## verdict. The standing the sect gave is settled against it rather than refunded,
## which is what makes a demotion a real cost.
func act_leave() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _verdict({NO_ACTOR: true})
	var result := SectApi.leave(_actor)
	return _settle(result)


## Take `office_id` in the sect the bound actor is sworn to. `force` is ADR 0064's
## route: the floor is a route, not a wall, and the trail records a forced promotion
## as `promote_forced` so a later reader can tell an earned seat from a political one.
##
## `held` is NOT passed. The module counts the room from the ledger's OWN roster and
## reads the office's cap from its authored def, so a screen that passed a number would
## be passing a claim the module then treats as a question.
func act_promote(office_id: String = "", force: bool = false) -> Dictionary:
	_bind_nodes()
	var wanted := office_id if office_id != "" else _selected_office
	if _actor == null:
		return _verdict({NO_ACTOR: true})
	if wanted == "":
		return _verdict({NO_OFFICE_PICKED: true})
	var result := SectApi.promote(_actor, StringName(wanted), force)
	return _settle(result)


## Pick the sect `act_join` would swear the hero to. Returns false for an id the
## facade's catalog does not carry, so a caller never "selects" a house that does not
## exist — and clears the selection rather than leaving a stale one behind.
func select_sect(sect_id: String) -> bool:
	_bind_nodes()
	if sect_id == "":
		_selected_sect = ""
	elif (_codex.get("sects", {}) as Dictionary).has(sect_id):
		_selected_sect = sect_id
	else:
		return false
	_render()
	return true


## Pick the office `act_promote` would seat the hero in. Same rule: an office this
## board does not show is not selectable, and `""` clears.
func select_office(office_id: String) -> bool:
	_bind_nodes()
	if office_id == "":
		_selected_office = ""
	elif _office_ids().has(office_id):
		_selected_office = office_id
	else:
		return false
	_render()
	return true


## The sect the next `act_join` would use, or `""`.
func selected_sect() -> String:
	return _selected_sect


## The office the next `act_promote` would use, or `""`.
func selected_office() -> String:
	return _selected_office


## The last verb's verdict, verbatim. `{}` before any action has been taken.
func last_result() -> Dictionary:
	return _last_result.duplicate(true)


## The sect ids this screen is offering to be sworn to, in canonical order. A member
## is offered the whole catalog too — leaving is a `leave`, and re-swearing is the two
## in order — so this is the same list whatever the membership is.
func offered_ids() -> Array:
	var out: Array = []
	var catalog: Dictionary = _codex.get("sects", {}) as Dictionary
	var ids := catalog.keys()
	ids.sort()
	for sect_id in ids:
		out.append(String(sect_id))
	return out


## Re-read the facade — the ONE call this screen makes — and hand raw values down.
## Every later read is of the cached `_codex`, never of the facade, so a refresh
## costs exactly one call however many times `summary()` is asked. The rows own
## every format.
func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	var live := SectApi.summary(_actor) if _actor != null else {}
	if not live.is_empty():
		_codex = live
	_fill_from_codex()


## Push the cached codex into the row pools. Split out from `_refresh_view` so that
## adopting a snapshot renders it without a second facade read.
func _fill_from_codex() -> void:
	_fill_claims()
	_fill_offices()


## Repaint this screen's own labels and the action row. The claim and office rows
## repaint themselves; `ActionSet` owns every button's label and its result line, so
## this screen formats nothing — it hands ids and the facade's own reason string down.
##
## The claim row shows the REFUSAL when one is outstanding, and the CLAIM otherwise.
## Those are deliberately not the same call: `show_claim({})` is ADR 0083's first
## state ("you belong to nothing"), while `show_refusal({"reason": R})` is the third
## ("you asked and were refused, here is the named rule"). Collapsing them would make
## a hero who is NOT sworn read exactly like a hero whose `join` was refused — which is
## the one distinction this screen exists to keep legible.
func _render() -> void:
	if _header == null:
		return
	if _actor == null:
		_header.text = NO_ACTOR_TEXT
		_footer.text = NO_ACTOR_FOOTER
		_publish_actions()
		return
	_header.text = HEADER_TEXT if bool(_codex.get("is_member", false)) else OFFERED_TEXT
	_footer.text = FOOTER_TEXT
	_publish_actions()


# --- ScreenStack hooks ------------------------------------------------------


## The landing spot is the member's own claim row — the thing the screen is read for —
## and failing that the first office with room. The action row's first LIVE control
## wins over both, because this screen now does something and the control a player can
## press is the one the keyboard must land on. Recorded first, because a node outside a
## viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if _actions != null:
		var before := String(_focus_target)
		_actions.focus_initial()
		if String(_actions.summary().get("focus_target", "")) != "":
			_focus_target = String(_actions.summary()["focus_target"])
			return
		_focus_target = before
	var target := _first_filled(_claim_rows)
	if target == null:
		target = _first_filled(_office_rows)
	if target == null:
		return
	_focus_target = String(target.name)
	if target.is_inside_tree():
		target.call(&"focus_initial")


## `ui_accept` fires whatever is picked — a `join` when a sect is selected, a
## promotion when an office is — and `ui_up` / `ui_down` walk the picked list. Each is
## CONSUMED only when it did something, so `ui_cancel` stays free for `ScreenStack` to
## pop exactly as it pops every other screen: a screen that could commit an oath and
## also swallowed the cancel would trap a player inside it.
##
## The guards are merged into one clause on purpose rather than stacked: a screen that
## declines an unbound or unbound-input event by DECLARING it declined is exactly the
## contract `ScreenStack` relies on, and one decision says it once.
func on_stack_input(event: InputEvent) -> bool:
	if _actor == null or event == null or not _bound:
		return false
	if not event.is_pressed() or event.is_echo() or event.is_action_pressed(&"ui_cancel"):
		return false
	if event.is_action_pressed(&"ui_accept"):
		return _accept()
	if event.is_action_pressed(&"ui_down"):
		return _step(1)
	if event.is_action_pressed(&"ui_up"):
		return _step(-1)
	return false


func on_screen_hidden() -> void:
	pass


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _header != null:
		return
	_header = get_node_or_null("%ClaimHeader") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_claim_box = get_node_or_null("Layout/Scroll/Codex/Claims") as VBoxContainer
	_office_box = get_node_or_null("Layout/Scroll/Codex/Offices") as VBoxContainer
	_actions = get_node_or_null("%Actions") as ActionSet
	_bound = _header != null and _footer != null and _claim_box != null and _office_box != null
	if not _bound:
		return
	_claim_rows = _rows_in(_claim_box, CLAIM_SCENE, "Claim", CLAIM_SPARE_ROWS)
	_office_rows = _rows_in(_office_box, OFFICE_SCENE, "Office", OFFICE_ROWS)
	_connect_actions()


## The action row, mounted by the scene. Bound lazily and only if the scene declares
## it, because a headless test may instantiate this screen's script against a scene
## that predates the action row; the ACTIONS are then unreachable and every verb
## reports `no_action_row` rather than pretending to have fired.
##
## The guard is what makes "one handler per connection" a fact rather than an
## accident of the `_bind_nodes` early return: the moment anything calls it a second
## time, an unguarded `connect` would duplicate silently.
func _connect_actions() -> void:
	if _actions == null:
		return
	if not _actions.action_requested.is_connected(_on_action_requested):
		_actions.action_requested.connect(_on_action_requested)


## Declare this screen's actions and their live state. Only ids and booleans go down;
## `ActionSet` owns the button text and the result line, so the screen formats no
## number and no sentence.
##
## `leave` and the two promotions stay DISABLED for a hero sworn to nothing rather
## than being live and refused: those refusals are `not_a_member`, which a hero who
## has not joined yet learns from the claim row already. `join` is live the moment a
## sect is picked, and the button stays live for a hero who is ALREADY sworn — because
## `already_sworn` is a rule the player should be told by pressing, not inferred from
## a greyed-out control.
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
					ACTION_JOIN: "Swear to the picked sect",
					ACTION_LEAVE: "Leave the sect",
					ACTION_PROMOTE: "Take the picked office",
					ACTION_PROMOTE_FORCED: "Take it over the objection",
				},
				"enabled": _enabled_actions(),
				"primary": ACTION_JOIN if can_join() else ACTION_LEAVE,
			}
		)
	)


## The action ids, in the order the bar shows them. Read off the constants above so
## the order a test reads is the order the player sees.
func _action_ids() -> Array:
	return [
		String(ACTION_JOIN),
		String(ACTION_LEAVE),
		String(ACTION_PROMOTE),
		String(ACTION_PROMOTE_FORCED)
	]


## Which of the four is live right now. `join` needs a sect picked; `leave` needs a
## membership; both promotions need an office picked AND a membership, because an
## office only exists to somebody who is sworn to the sect that authors it.
func _enabled_actions() -> Dictionary:
	var member := _actor != null and bool(_codex.get("is_member", false))
	return {
		String(ACTION_JOIN): can_join(),
		String(ACTION_LEAVE): member,
		String(ACTION_PROMOTE): member and _selected_office != "",
		String(ACTION_PROMOTE_FORCED): member and _selected_office != "",
	}


## The button press, routed to the verb. `ActionSet.request` refuses a disabled
## action, so this cannot fire a verb the control does not offer.
func _on_action_requested(action: StringName) -> void:
	match action:
		ACTION_JOIN:
			act_join()
		ACTION_LEAVE:
			act_leave()
		ACTION_PROMOTE:
			act_promote()
		ACTION_PROMOTE_FORCED:
			act_promote("", true)


## `ui_accept` on the screen: a join when a sect is picked, otherwise a promotion.
##
## An office ALWAYS belongs to the sect the hero is already sworn to, so a hero who
## has picked both is making two different requests and the screen answers the one the
## ACT row is offering first: the sworn-to relation is the one they are already in, so
## a promotion is the more specific act and a join is the larger one. Declared in one
## place because two consumers (`on_stack_input` and the action bar) must agree.
func _accept() -> bool:
	if can_join():
		act_join()
		return true
	if member() and _selected_office != "":
		act_promote()
		return true
	return false


## The membership this screen is showing, for `_accept`'s own decision. A named
## predicate so the two consumers above read the same fact the same way.
func member() -> bool:
	return bool(_codex.get("is_member", false))


## Move the pick `step` entries along the offered list, wrapping. Returns false when
## there is nothing to pick, so `ui_down` on an empty catalog is declined rather than
## consumed — a screen that swallows a key it cannot honour is a screen that has
## swallowed the player's cancel by association.
##
## The list is the CATALOG while a hero is sworn to nothing and the BOARD once they
## are sworn: "which house may I join" and "which office may I take" are the two
## questions this screen asks, and only one of them has an answer at a time.
func _step(step: int) -> bool:
	var ids: Array = _offered_ids() if not member() else _office_ids()
	if ids.is_empty():
		return false
	var index := ids.find(_selected_sect if not member() else _selected_office)
	if index < 0:
		index = 0 if step > 0 else ids.size() - 1
	var next := posmod(index + step, ids.size())
	var chosen := String(ids[next])
	if member():
		_selected_office = chosen
	else:
		_selected_sect = chosen
	_render()
	return true


## Every authored sect id, canonically ordered — the list `ui_up` / `ui_down` walk for
## an unsworn hero.
func _offered_ids() -> Array:
	var out: Array = []
	var catalog: Dictionary = _codex.get("sects", {}) as Dictionary
	var ids := catalog.keys()
	ids.sort()
	for sect_id in ids:
		out.append(String(sect_id))
	return out


## Every office id this board is showing, in display order — the list `ui_up` /
## `ui_down` walk for a sworn member. Read off the rows rather than off the facade, so
## what the player can pick is exactly what they can see.
func _office_ids() -> Array:
	var out: Array = []
	for row in _office_rows:
		var office_id := String((row as NationOfficeRow).office_id())
		if office_id != "":
			out.append(office_id)
	return out


## A refusal this screen raises ITSELF, in the facade's own `{ok, reason}` shape.
## Never a silent no-op: an action a player asked for that did not happen is reported
## in the same vocabulary the module uses, so one renderer covers both.
func _verdict(reasons: Dictionary) -> Dictionary:
	var reason := ""
	for key in reasons.keys():
		if reason == "":
			reason = String(key)
	return _settle({"ok": false, "reason": reason})


## Record a verdict, repaint, and hand the caller the module's OWN dictionary. The
## screen never rewrites it, so `last_result` is the facade's answer and a test can
## compare it against `SectApi` directly.
##
## The repaint happens AFTER the verdict is recorded, so the claim row the player sees
## is the one the verdict describes: a refused verb writes nothing (ADR 0084), so the
## claim behind it is byte-for-byte as found, and painting the refusal over it is what
## makes "the world did not change, and here is why" legible in one row.
func _settle(result: Dictionary) -> Dictionary:
	_bind_nodes()
	_last_result = (result as Dictionary).duplicate(true)
	if bool(_last_result.get("ok", false)):
		_refusal = {}
		set_message(String(_last_result.get("reason", "")), TONE_OK)
	else:
		_refusal = {"reason": String(_last_result.get("reason", ""))}
		# The reason VERBATIM. Not "Rejected: already_sworn", not a sentence this
		# screen composed: the module authored the constant and a panel that reworded
		# it would be describing a rule the module never wrote.
		set_message(String(_last_result.get("reason", "")), TONE_ERROR)
	refresh()
	return _last_result.duplicate(true)


## The rows the scene declares, in order, then enough grown rows to reach `extra`.
## A pool smaller than `extra` would have to truncate the data the next refresh
## brings, so the mounted rows are topped up here rather than left to `_grow()`.
func _rows_in(box: VBoxContainer, scene_path: String, prefix: String, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as Control
		if row != null and (row.has_method(&"show_claim") or row.has_method(&"show_office")):
			out.append(row)
	for index in range(extra):
		var row := load(scene_path).instantiate() as Control
		row.name = "%s%d" % [prefix, out.size()]
		box.add_child(row)
		out.append(row)
	return out


## Grow a mounted pool to fit the data, so the page scrolls rather than truncates. A
## promotion route that silently vanished would read as an office the sect does not
## author, which is the dead-content failure ADR 0063 shipped once already.
func _grow(
	box: VBoxContainer, rows: Array, scene_path: String, prefix: String, needed: int
) -> void:
	# Bounded, not trusted: `needed` is a data-derived claim/office count, and a
	# pool that grows to fit an unbounded one parents live Controls without limit.
	var target := RowBudget.cap(needed)
	while rows.size() < target:
		var row := load(scene_path).instantiate() as Control
		row.name = "%s%d" % [prefix, rows.size()]
		box.add_child(row)
		rows.append(row)


func _first_filled(rows: Array) -> Node:
	for row in rows:
		if row.has_method(&"is_filled") and bool(row.call(&"is_filled")):
			return row
	return null


# --- Filling ----------------------------------------------------------------


## The member's own claim, or the refusal the last verb returned — ADR 0083's second
## and third states, kept apart.
##
## A refusal paints the row instead of the claim, and it keeps the module's OWN
## `reason` untouched. The claim behind it is still handed to the row as well — a
## refused verb writes nothing at all (ADR 0084), so those two are the same instant
## and showing both is what makes the refusal legible rather than an empty page.
##
## The refusal is cleared the moment a verb SUCCEEDS, and never by a plain repaint: a
## refresh reads the facade, and the facade has no memory of a refusal. So a refusal
## survives exactly as long as the player has not done anything else, which is what
## "you asked, you were refused, here is the named rule" has to mean.
func _fill_claims() -> void:
	if _claim_rows.is_empty():
		return
	if _refusal.is_empty():
		(_claim_rows[0] as SectClaimRow).show_claim(_codex.duplicate(true))
	else:
		var refused: Dictionary = _refusal.duplicate(true)
		refused["is_member"] = bool(_codex.get("is_member", false))
		(_claim_rows[0] as SectClaimRow).show_refusal(refused)
	for index in range(1, _claim_rows.size()):
		(_claim_rows[index] as SectClaimRow).show_claim({})


## Every authored office of the sworn sect, in canonical order. A seat nobody holds
## is a row with `"vacant": true` and renders; the offices a promotion route offers
## are rendered as their own rows too, so the board never hides a seat just because
## nobody is in it right now.
func _fill_offices() -> void:
	var promotion: Dictionary = _codex.get("can_promote", {}) as Dictionary
	var ids := promotion.keys()
	ids.sort()
	var views: Array = []
	for office_id in ids:
		var view: Dictionary = promotion[office_id]
		(
			views
			. append(
				{
					"office_id": String(view.get("id", "")),
					"display_name": String(view.get("display_name", "")),
					# This module holds no roster, so `held` is a count and the seat's
					# state is the authored reason the facade published. A seat with no
					# holder is still a row: `vacant` is exactly `held == 0`.
					"vacant": int(view.get("held", 0)) == 0,
					"holder_id": "",
					"capacity": 1,
					"succession_method": String(view.get("reason", "")),
					"powers": [],
				}
			)
		)
	_grow(_office_box, _office_rows, OFFICE_SCENE, "Office", views.size())
	var index := 0
	while index < _office_rows.size():
		(_office_rows[index] as NationOfficeRow).show_office(
			views[index] as Dictionary if index < views.size() else {}
		)
		index += 1


# --- Reporting --------------------------------------------------------------


## The member's own claim, nested under its own key. `{}` when nothing rendered, so
## a caller reads "no claim row" rather than a half-filled shape.
func _claim_summary() -> Dictionary:
	if _claim_rows.is_empty():
		return {}
	return (_claim_rows[0] as SectClaimRow).summary()


## Every promotion route the facade published, as primitives. The screen formats
## none of it: `reason` is the facade's named string, passed through untouched.
func _promotion_summaries() -> Array:
	var out: Array = []
	var promotion: Dictionary = _codex.get("can_promote", {}) as Dictionary
	var ids := promotion.keys()
	ids.sort()
	for office_id in ids:
		var view: Dictionary = promotion[office_id]
		(
			out
			. append(
				{
					"office_id": String(view.get("id", "")),
					"display_name": String(view.get("display_name", "")),
					"standing_floor": int(view.get("standing_floor", 0)),
					"below_floor": bool(view.get("below_floor", false)),
					"held": int(view.get("held", 0)),
					"has_room": bool(view.get("has_room", false)),
					"reason": String(view.get("reason", "")),
				}
			)
		)
	return out


## Every authored sect the facade listed, as primitives, canonically ordered.
func _sect_summaries() -> Array:
	var out: Array = []
	var sects: Dictionary = _codex.get("sects", {}) as Dictionary
	var ids := sects.keys()
	ids.sort()
	for sect_id in ids:
		var view: Dictionary = sects[sect_id]
		(
			out
			. append(
				{
					"sect_id": String(sect_id),
					"display_name": String(view.get("display_name", "")),
					"doctrine_id": String(view.get("doctrine_id", "")),
					"sworn": String(sect_id) == String(_codex.get("sect_id", "")),
					"position_count": (view.get("positions", {}) as Dictionary).size(),
				}
			)
		)
	return out


## The office ids the board is showing, in display order.
##
## A SPARE pool row is not an office and is not reported: it renders `{}` and its id
## reads as `""`, so it is dropped here. That is what makes the reported count equal
## the sect's AUTHORED board rather than the size of the pool the scene happened to
## mount — a sect that authors four offices and a screen that reports twelve has
## invented eight offices, which is the dead-content failure ADR 0063 already
## shipped once.
func row_ids() -> Array:
	var out: Array = []
	for row in _office_rows:
		var office_id := String((row as NationOfficeRow).office_id())
		if office_id != "":
			out.append(office_id)
	return out


func _string_list(values: Variant) -> Array:
	var out: Array = []
	if not (values is Array):
		return out
	for value in values as Array:
		out.append(String(value))
	return out
