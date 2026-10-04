class_name CustodyScreen
extends UiScreen

## The custody page: the claims this hero holds, and the verbs that move them.
##
## ## ## Why this screen exists at all
##
## `forage_screen` closed the audit's other half. The same audit that found
## `HoldingsApi.claim` with no production caller found `CustodyApi.capture` with
## none either: the brief asked that captured actors and mobs be reachable, ADR
## 0094 refused a captive as a tradeable thing because it has no `ItemDef`, and ADR
## 0104 answered "then what IS one" — a custody CLAIM. `CustodyApi.capture`,
## `transfer`, `release`, `settle_term` and `subject` all shipped, green in every
## suite, and **nothing a player can press called any of them**. A claim could be
## opened by a test and by nothing else, so a captive was a ledger row and no
## surface. This is the route that reaches it.
##
## ## ## It is PURELY a consumer of one facade, with no injected seam
##
## `custody` is declared in `rules.UI_MODULES` with **no** module dependency, which
## is why this screen may name `CustodyApi` bare, with no `preload` and no
## `extends`: the holder, the term, the periods and the status are already keys
## inside `summary()`, and `subject` is the facade's own read. **Nothing here arrives
## as an injected `Callable`.** `ForageScreen` needs `bind_harvest` because
## `ForageAction` is an `app/` type and `app` is a `PRIVATE_UNIT`; custody has no
## such program — every verb takes primitives plus an `Actor` the screen already
## holds, and the coin leg is `CustodyApi.transfer`'s own business behind the
## facade. So the route's binding arm is the plain default `setup(actor)`, and this
## screen is the proof that a granted facade reach is enough on its own.
##
## ## ## `capture` is a CALLER verb, and this screen says so
##
## ADR 0104 puts capture *conditions* out of scope: "the caller decides and calls
## `capture`; no combat check, no roll, no rng". So the capture beat here does NOT
## decide that anybody may be taken. It forwards the subject id, the kind, the term
## and the periods the CALLER staged, and renders whatever `CustodyApi.capture` said,
## every refusal by its own name. Inventing a gate here would be a second authority
## on combat, which is the thing ADR 0104 refused.
##
## ## ## The settlement is staged, and the module still computes no price
##
## `transfer`'s `coins` is a negotiated settlement the caller supplies, and the coin
## leg needs TWO `Actor`s — a single player has one purse, so a screen that minted a
## counterparty would be inventing a wallet (ADR 0104: a term is a COUNT of periods
## and never an amount). So `coins` and the two parties are staged by the caller and
## forwarded verbatim; `coins == 0` skips the exchange entirely, which ADR 0104 calls
## a legal hand-off. The screen names a figure it was told and computes nothing.
##
## ## ## No prose field is invented anywhere on this page
##
## A custody record has no `description`, no `flavor` and no `display_name`
## (ADR 0104). Vocabulary is exactly: holder, claim, term, periods, transferred,
## released. This screen composes no sentence about a subject and names a subject by
## nothing but the def id the claim carries. The machine check for that is
## `tests/ui/test_custody_surface.gd`, which reads the shipped source of both files
## and fails on any prose key either grows.
##
## Contract: `summary()` is the testable surface, primitives only, each row's own
## summary nested under `rows`, `{}` with no actor.

## The claim rows the scene mounts and this screen tops up to. The pool is grown
## through `RowBudget.cap` rather than truncated — the same shape `ForageScreen`
## uses for nodes — so an authored claim can never fall off the end of the list
## because the scene happened to mount fewer rows than the ledger holds.
const CLAIM_ROWS := 6
const CLAIM_SCENE := "res://src/ui/panels/custody_claim_row.tscn"
const HEADER_TEXT := "The claims you hold, and the terms they carry."
const NO_ACTOR_TEXT := "No hero bound."
const NO_ACTOR_FOOTER := ""
const FOOTER_TEXT := (
	"Up / Down picks a claim, Accept releases the picked one you hold. " + "Cancel returns."
)

## The action ids this screen publishes, in the order the bar shows them. Declared
## as constants rather than built per call so the order a test reads is the order
## the player sees.
const ACTION_CAPTURE := &"capture"
const ACTION_TRANSFER := &"transfer"
const ACTION_RELEASE := &"release"
const ACTION_SETTLE := &"settle"

## The refusals this screen raises ITSELF, before a verb is called. Authored
## constants rather than prose, for the same reason the modules author their own: a
## panel renders a reason it did not have to invent. The two that name a module rule
## are the module's OWN constant, so one id covers the whole path whichever layer
## raised it.
const NO_ACTOR := CustodyApi.NO_ACTOR
const NO_CLAIM_PICKED := "no_claim_picked"
## The caller staged no subject for the capture beat. Distinct from every module
## refusal: nothing was attempted, so there is nothing to report about the world.
const NO_SUBJECT := "no_subject"
## `periods <= 0` or an empty term was staged. The module refuses a termless capture
## `no_terms`; this screen refuses the same PATH by its own id before the call,
## because a staged beat of zero periods is a caller mistake rather than a world state
## a panel should be rendering.
const NO_PERIODS := CustodyApi.NO_PERIODS
## A negative settlement was staged. Zero is a legal hand-off and must not be forced
## to invent a coin leg, so this is a refusal about the FIGURE, not the exchange.
const NO_COINS := "no_coins"
## The transfer verb was called with no target holder staged. An invented holder is a
## claim handed to somebody nobody agreed to, so this declines by name rather than
## guessing.
const NO_TRANSFER_TARGET := "no_transfer_target"

## The periods one press of the settle action settles against a term. A single
## period, declared here rather than defaulted at the verb: a press says how much of
## the term the holder is paying down, and a defaulted period is an invented tick
## wearing a button's clothes (DEF-0111).
const SETTLE_PERIODS := 1

## The one `OwnerRef` kind this screen derives for itself. `OwnerRef.KINDS` is the
## closed set — actor, clan, sect, nation — and a single player is an `actor`, so
## this is the only kind a page press can speak for. Every other kind is a holder
## some caller names.
const OWNER_KIND := "actor"
## `CustodyState.SUBJECT_KINDS` ships `npc`, and `player` is a closed value reserved
## for a `PlayerDef` that does not exist yet. Spelled here rather than read off
## `CustodyState`, because that is a module INTERIOR and `ui/` may name only a
## facade.
const DEFAULT_SUBJECT_KIND := "npc"
## The claim status this screen orders and counts by. The same word the row renders,
## declared on both sides rather than taken from `CustodyState`, which is an interior.
const STATUS_RELEASED := "released"

var _header: Label = null
var _footer: Label = null
var _claim_box: VBoxContainer = null
var _actions: ActionSet = null
var _bound: bool = false
var _claim_rows: Array = []
## The claim `act_transfer` / `act_release` / `act_settle` would act on. `""` picks
## nothing, and each verb then refuses `no_claim_picked` by name rather than
## silently acting on the first row.
var _selected_claim: String = ""
## The last verb's verdict, carried through verbatim. `{}` before any action, so a
## test reads "no action yet" rather than a refusal that never happened.
var _last_result: Dictionary = {}
## The facade's read model for the bound actor, cached from the last refresh, so a
## refresh costs exactly one facade call however many times `summary()` is asked.
var _views: Array = []
## What the facade reported about its own seams at the last refresh. Published so a
## probe can tell "this hero holds nothing" from "the ledger is not installed", which
## are different sentences and both reachable.
var _store_installed: bool = false
var _resolver_installed: bool = false
## The staged capture beat. Four fields and no widgets, because `ui/` builds no form
## controls and a headless driver stages a beat the same way a future combat outcome
## would.
var _capture_subject: String = ""
var _capture_kind: String = ""
var _capture_term: String = ""
var _capture_periods: int = 0
## The staged transfer. `to_holder` is an `OwnerRef` over the module's closed
## `KINDS`, so only a caller can name one; the two parties are the wallets the
## caller agreed, forwarded verbatim and never derived here.
var _transfer_target: Dictionary = {}
var _transfer_coins: int = 0
var _transfer_payer: Actor = null
var _transfer_receiver: Actor = null


## Stage the fields [method act_capture] will commit: `subject_id` is a subject DEF
## id (never an `Actor`), `term_id` an authored term, `periods` a count.
##
## Nothing here decides that the capture MAY happen — ADR 0104 leaves that condition
## in the caller — and nothing here is stored: a refresh that found no staged subject
## reports `no_subject` rather than inventing one, which is what keeps this from
## being a grab button with no cause. Assigned exactly as given, so staging one
## subject and staging none are the same shape and a deliberate empty string CLEARS
## the staging rather than leaving a stale subject for the next press to commit.
func stage_capture(
	subject_id: String,
	subject_kind: String = DEFAULT_SUBJECT_KIND,
	term_id: String = "custody",
	periods: int = 1
) -> void:
	_bind_nodes()
	_capture_subject = subject_id
	_capture_kind = subject_kind if subject_kind != "" else DEFAULT_SUBJECT_KIND
	_capture_term = term_id
	_capture_periods = periods
	_render()


## The staged capture beat as the summary publishes it: four primitives, so a test
## asserts what a press WOULD commit without reading it back off a widget.
func staged_capture() -> Dictionary:
	return {
		"subject_id": _capture_subject,
		"subject_kind": _capture_kind,
		"term_id": _capture_term,
		"periods": _capture_periods,
	}


## Stage the transfer [method act_transfer] will commit. `to_holder` is an `OwnerRef`
## — `{kind, id}` over the module's closed `KINDS`. `coins` is the AGREED settlement
## and both parties are the wallets it runs between; `coins == 0` is a legal hand-off
## that skips the exchange entirely (ADR 0104), and the module refuses
## `no_settlement_party` itself when coins are named and a party is not.
##
## Assigned exactly as given: staging a transfer and clearing it are the same shape,
## so a deliberate `{}` disarms the button rather than leaving the last target
## standing for the next press.
func stage_transfer(
	to_holder: Dictionary, coins: int = 0, coin_payer: Actor = null, coin_receiver: Actor = null
) -> void:
	_bind_nodes()
	_transfer_target = to_holder.duplicate(true)
	_transfer_coins = coins
	_transfer_payer = coin_payer
	_transfer_receiver = coin_receiver
	_render()


## The staged transfer, as the summary publishes it. The holder is nested rather than
## flattened because it is a ref, and a ref with its kind dropped is not a ref.
func staged_transfer() -> Dictionary:
	return {
		"staged": not _transfer_target.is_empty(),
		"to_kind": String(_transfer_target.get("kind", "")),
		"to_id": String(_transfer_target.get("id", "")),
		"coins": _transfer_coins,
		"payer": String(_transfer_payer.id) if _transfer_payer != null else "",
		"receiver": String(_transfer_receiver.id) if _transfer_receiver != null else "",
	}


## Clear the staged capture beat, so the next press refuses `no_subject` rather than
## recommitting the last one.
func clear_capture() -> void:
	stage_capture("", DEFAULT_SUBJECT_KIND, "", 0)


## Clear the staged transfer, so the transfer button goes dead rather than naming the
## last holder the player agreed to.
func clear_transfer() -> void:
	stage_transfer({})


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var rows := _claim_summaries()
	var picked := _picked_view()
	return {
		"actor": String(_actor.id),
		"read_only": false,
		# The custody states as DISTINCT counts rather than one "available": a claim this
		# hero holds, a claim that was released and a claim held by somebody else are
		# three different situations and the row reads differently on each (ADR 0083).
		"held_count": _count_where(rows, "held"),
		"released_count": _count_where(rows, "released"),
		"vacant_count": _count_where(rows, "holder_vacant"),
		"mine_count": _mine_count(rows),
		"claim_count": rows.size(),
		"claim_ids": _claim_ids(rows),
		"selected_claim": _selected_claim,
		"selected_held": bool(picked.get("held", false)),
		"selected_released": bool(picked.get("released", false)),
		"selected_vacant": bool(picked.get("holder_vacant", false)),
		"selected_holder_kind": String(picked.get("holder_kind", "")),
		"selected_holder_id": String(picked.get("holder_id", "")),
		"selected_subject_id": String(picked.get("subject_id", "")),
		"selected_subject_kind": String(picked.get("subject_kind", "")),
		"selected_term_id": String(picked.get("term_id", "")),
		"selected_periods": int(picked.get("periods", 0)),
		"selected_opened_period": int(picked.get("opened_period", 0)),
		"selected_mine": _holder_is_mine(picked),
		"store_installed": _store_installed,
		"resolver_installed": _resolver_installed,
		# The last verb's verdict as primitives. `last_reason` is the module's own named
		# constant, so one run tells a captured subject from a released one from a
		# refused transfer — the outcomes that would otherwise all read as "nothing
		# happened".
		"refused": bool(_last_result.get("ok", true) == false),
		"refusal_reason": String(_last_result.get("reason", "")),
		"last_ok": bool(_last_result.get("ok", false)),
		"last_reason": String(_last_result.get("reason", "")),
		"last_claim": String(_last_result.get("claim_id", "")),
		"last_coins": int(_last_result.get("coins", 0)),
		# `settled` is `CustodyApi.settle_term`'s own key for the periods paid down. Read
		# by that name rather than as `periods`, which is the term's OWED count and would
		# make a test read a settlement as if it had opened the claim.
		"last_settled": int(_last_result.get("settled", 0)),
		"last_periods_left": int(_last_result.get("periods_left", 0)),
		"staged_capture": staged_capture(),
		"staged_transfer": staged_transfer(),
		"actions": _action_ids(),
		"enabled": _enabled_actions(),
		# Each row's own summary, nested under that row's key so a test reads the claim
		# without walking the widget tree.
		"rows": rows,
	}


# --- Actions. Each calls the facade by name, and reports what came back ---


## Take custody of the staged subject for this hero, on the staged term.
##
## Returns `CustodyApi.capture`'s verdict unchanged, so a caller never has to read
## the message line to learn what happened. The holder is DERIVED from the bound actor
## rather than passed in, for the reason `ForageAction.gather` derives its own owner
## ref: a caller that could name somebody else's holder could open a claim in their
## name, which is a custody bug and not a convenience.
func act_capture() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _verdict(NO_ACTOR)
	if _capture_subject == "":
		return _verdict(NO_SUBJECT)
	if _capture_periods <= 0 or _capture_term == "":
		return _verdict(NO_PERIODS)
	return _settle(
		CustodyApi.capture(
			_actor,
			StringName(_capture_subject),
			StringName(_capture_kind),
			_owner(),
			StringName(_capture_term),
			_capture_periods
		)
	)


## Move the picked claim to the staged holder for the staged settlement. Returns
## `CustodyApi.transfer`'s verdict.
##
## The coin leg is the MODULE's, in the module's order: it settles first and the claim
## moves only on `ok`, so a refused settlement has written nothing and the holder is
## unchanged (ADR 0104). The screen forwards and never re-orders it.
func act_transfer() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _verdict(NO_ACTOR)
	if _selected_claim == "":
		return _verdict(NO_CLAIM_PICKED)
	if _transfer_target.is_empty():
		return _verdict(NO_TRANSFER_TARGET)
	if _transfer_coins < 0:
		return _verdict(NO_COINS)
	return _settle(
		CustodyApi.transfer(
			_actor,
			StringName(_selected_claim),
			_owner(),
			_transfer_target,
			_transfer_coins,
			_transfer_payer,
			_transfer_receiver
		)
	)


## End the picked claim. Always permitted for the holder and never free — the periods
## left are reported and the claim STAYS in the ledger as released, because a holder
## who walks away from a claim has not un-paid it, and because the history has to read
## as history. Returns `CustodyApi.release`'s verdict.
func act_release() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _verdict(NO_ACTOR)
	if _selected_claim == "":
		return _verdict(NO_CLAIM_PICKED)
	return _settle(CustodyApi.release(_actor, StringName(_selected_claim), _owner()))


## Settle `periods` against the picked claim's term. All-or-nothing, and never
## over-settled: the module refuses `term_exceeds` with the periods left rather than
## forgiving the remainder, so a holder is never left owing less than it claimed to
## owe. Returns `CustodyApi.settle_term`'s verdict.
func act_settle(periods: int = SETTLE_PERIODS) -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _verdict(NO_ACTOR)
	if _selected_claim == "":
		return _verdict(NO_CLAIM_PICKED)
	if periods <= 0:
		return _verdict(NO_PERIODS)
	return _settle(CustodyApi.settle_term(_actor, StringName(_selected_claim), periods))


## The live subject behind the picked claim, or null.
##
## `CustodyApi.subject` is the facade's own read: it mints a body through the
## composition root's injected minter and never writes a row, so asking every refresh
## costs nothing and stores nothing (ADR 0104). It is null for an unknown claim, for a
## RELEASED one — minting that body would put a free prisoner back on the map — and
## for an unwired minter, which [method subject_wired] reports separately rather than
## folding "no claim" and "no constructor" into one null.
func act_subject() -> Actor:
	_bind_nodes()
	if _actor == null or _selected_claim == "":
		return null
	return CustodyApi.subject(StringName(_selected_claim))


## Whether a constructor is installed, so a caller can say "no claim" and "no
## constructor" as two different messages rather than one null.
func subject_wired() -> bool:
	return CustodyApi.has_minter()


## Pick the claim the verbs would act on. Returns false for an id this screen is not
## showing, so a caller never "selects" a claim that does not exist here, and clears
## the selection rather than leaving a stale one behind.
func select_claim(claim_id: String) -> bool:
	_bind_nodes()
	if claim_id == "":
		_selected_claim = ""
	elif _claim_ids(_claim_summaries()).has(claim_id):
		_selected_claim = claim_id
	else:
		return false
	_render()
	return true


## The claim ids this screen is showing, in display order — the list `ui_up` / `ui_down`
## walk. Read off the rows rather than off the facade, so what the player can pick is
## exactly what they can see.
func claim_ids() -> Array:
	_bind_nodes()
	return _claim_ids(_claim_summaries())


# --- ScreenStack hooks ------------------------------------------------------


## The landing spot is the first LIVE control in the action row, because this screen
## does something and the control a player can press is the one the keyboard must land
## on. Recorded first, because a node outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if _actions != null:
		var before := String(_focus_target)
		_actions.focus_initial()
		if String(_actions.summary().get("focus_target", "")) != "":
			_focus_target = String(_actions.summary()["focus_target"])
			return
		_focus_target = before


## `ui_accept` fires the one verb the picked claim's own state makes primary — release
## a claim THIS HERO holds, and decline otherwise — and `ui_up` / `ui_down` walk the
## picked list. Each is CONSUMED only when it did something, so `ui_cancel` stays free
## for `ScreenStack` to pop exactly as it pops every other screen: a screen that could
## release a claim and also swallowed the cancel would trap a player inside it.
##
## The guards are merged into one clause on purpose rather than stacked, for the reason
## `SectScreen.on_stack_input` gives: a screen that declines an unbound event by
## DECLARING it declined is exactly the contract `ScreenStack` relies on.
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


# --- Plumbing ---------------------------------------------------------------


## Re-read the facade — the ONE call this screen makes per refresh — and hand raw
## values down. Every later read is of the cached `_views`, never of the facade, so a
## refresh costs exactly one call however many times `summary()` is asked. The rows
## own every format.
func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	var model := CustodyApi.summary(_actor) if _actor != null else {}
	_store_installed = bool(model.get("store_installed", false))
	_resolver_installed = bool(model.get("resolver_installed", false))
	_views = _sorted_views(model.get("claims", {}) as Dictionary)
	_fill_from_views()


## The claims in a stable display order: held first, then released, each block ordered
## by subject id. `summary()` returns a dictionary and a dictionary's iteration order
## is not an order a player can be shown twice, so the screen sorts rather than
## trusting it. The SORTED list is what the rows render, so a second refresh cannot
## reshuffle the board under the pick.
func _sorted_views(claims: Dictionary) -> Array:
	var out: Array = []
	for claim_id in claims:
		var view: Dictionary = (claims[claim_id] as Dictionary).duplicate(true)
		view["claim_id"] = String(claim_id)
		out.append(view)
	out.sort_custom(_view_before)
	return out


## Held before released, then subject id, then claim id — the module's own field names
## read as strings, so this touches no module interior. A method rather than a lambda
## because a typed closure over a script's own members is the access-violation shape
## `EconomyBoot._install_minter` documents.
func _view_before(a: Dictionary, b: Dictionary) -> bool:
	var held_a := String(a.get("status", "")) != STATUS_RELEASED
	var held_b := String(b.get("status", "")) != STATUS_RELEASED
	if held_a != held_b:
		return held_a
	var subject_a := String(a.get("subject_id", ""))
	var subject_b := String(b.get("subject_id", ""))
	if subject_a != subject_b:
		return subject_a < subject_b
	return String(a.get("claim_id", "")) < String(b.get("claim_id", ""))


func _fill_from_views() -> void:
	if _claim_rows.is_empty():
		return
	# Snapshot the bound BEFORE the pool grows: `needed` is a content-derived count and
	# a grow loop that re-reads it is the shape `RowBudget` exists to close.
	var needed: int = _views.size()
	var target := RowBudget.cap(needed)
	while _claim_rows.size() < target:
		var row := load(CLAIM_SCENE).instantiate() as Control
		row.name = "Claim%d" % _claim_rows.size()
		_claim_box.add_child(row)
		_claim_rows.append(row)
	var index := 0
	while index < _claim_rows.size():
		var view: Dictionary = _views[index] as Dictionary if index < _views.size() else {}
		(_claim_rows[index] as CustodyClaimRow).show_claim(view)
		index += 1
	# A selection that fell off the end of the list is CLEARED rather than left stale: a
	# pick naming a claim this screen is no longer showing would act on nothing.
	if not _claim_ids(_claim_summaries()).has(_selected_claim):
		_selected_claim = ""


func _bind_nodes() -> void:
	super()
	if _header != null:
		return
	_header = get_node_or_null("%HeaderLabel") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_claim_box = get_node_or_null("Layout/Scroll/Claims") as VBoxContainer
	_actions = get_node_or_null("%Actions") as ActionSet
	_bound = _header != null and _footer != null and _claim_box != null
	if not _bound:
		return
	_claim_rows = _rows_in(_claim_box, CLAIM_SCENE, "Claim", CLAIM_ROWS)
	_connect_actions()


## The action row, mounted by the scene. Bound lazily and only if the scene declares
## it, because a headless test may instantiate this screen's script against a scene
## that predates the action row; the ACTIONS are then unreachable and every verb reports
## its own `no_*` refusal rather than pretending to have fired.
##
## The guard is what makes "one handler per connection" a fact rather than an accident
## of the `_bind_nodes` early return: the moment anything calls this a second time, an
## unguarded `connect` would duplicate silently.
func _connect_actions() -> void:
	if _actions == null:
		return
	if not _actions.action_requested.is_connected(_on_action_requested):
		_actions.action_requested.connect(_on_action_requested)


## The `OwnerRef` the custody verbs take, as the plain dictionary the facade compares
## against, derived from the bound actor. `ui/` may not mint an `Actor`, but it may
## read one off the screen it is bound to — and this is exactly what
## `ForageAction.owner_ref` builds, spelled out here rather than imported because
## `ForageAction` is an `app/` type this program may not name.
func _owner() -> Dictionary:
	return {"kind": OWNER_KIND, "id": String(_actor.id)}


## The rows the scene declares, in order, then enough grown rows to reach `extra`. A
## pool smaller than `extra` would have to truncate the data the next refresh brings,
## so the mounted rows are topped up here rather than left to `_fill_from_views`.
func _rows_in(box: VBoxContainer, scene_path: String, prefix: String, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as Control
		if row != null and row.has_method(&"show_claim"):
			out.append(row)
	for index in range(extra):
		var row := load(scene_path).instantiate() as Control
		row.name = "%s%d" % [prefix, out.size()]
		box.add_child(row)
		out.append(row)
	return out


func _render() -> void:
	if _header == null:
		return
	if _actor == null:
		_header.text = NO_ACTOR_TEXT
		_footer.text = NO_ACTOR_FOOTER
		_publish_actions()
		return
	_header.text = HEADER_TEXT
	_footer.text = FOOTER_TEXT
	_publish_actions()


## Declare this screen's actions and their live state. Only ids and booleans go down;
## `ActionSet` owns the button text and the result line, so the screen formats no
## number and no sentence.
##
## `capture` needs a staged subject AND a term, because ADR 0104 leaves the CONDITION
## in the caller and a capture with nothing staged would be a grab with no cause.
## `transfer` needs a claim this hero holds and a staged target holder, which is a
## button's one thing it cannot supply: a holder is an `OwnerRef` over the module's
## closed `KINDS`, and an invented one is a claim handed to somebody nobody agreed to.
## `release` needs a claim this hero holds, because `holder_mismatch` is the refusal a
## player who is told nothing may still be told why. `settle` needs a held claim with
## periods left, because a settled term refuses `claim_settled` and a released claim
## refuses `not_held`.
func _publish_actions() -> void:
	if _actions == null:
		return
	var picked := _picked_view()
	(
		_actions
		. set_state(
			{
				"actions": _action_ids(),
				"labels":
				{
					ACTION_CAPTURE: "Take custody of the staged subject",
					ACTION_TRANSFER: "Transfer the picked claim",
					ACTION_RELEASE: "Release the picked claim",
					ACTION_SETTLE: "Settle a period of the picked term",
				},
				"enabled": _enabled_actions(),
				"primary": ACTION_RELEASE if _holder_is_mine(picked) else ACTION_CAPTURE,
			}
		)
	)


## The action ids, in the order the bar shows them. Read off the constants above so
## the order a test reads is the order the player sees.
func _action_ids() -> Array:
	return [
		String(ACTION_CAPTURE),
		String(ACTION_TRANSFER),
		String(ACTION_RELEASE),
		String(ACTION_SETTLE),
	]


## Which of the four is live right now.
func _enabled_actions() -> Dictionary:
	var picked := _picked_view()
	var mine := _holder_is_mine(picked)
	return {
		String(ACTION_CAPTURE): _actor != null and _capture_subject != "" and _capture_periods > 0,
		String(ACTION_TRANSFER): _actor != null and mine and not _transfer_target.is_empty(),
		String(ACTION_RELEASE): _actor != null and mine,
		String(ACTION_SETTLE): _actor != null and mine and int(picked.get("periods", 0)) > 0,
	}


## The button press, routed to the verb. `ActionSet.request` refuses a disabled action,
## so this cannot fire a verb the control does not offer.
##
## `settle` takes [constant SETTLE_PERIODS] — the authored step — rather than a number a
## button author typed, so a retune of the step is one constant and not a search.
func _on_action_requested(action: StringName) -> void:
	match action:
		ACTION_CAPTURE:
			act_capture()
		ACTION_TRANSFER:
			act_transfer()
		ACTION_RELEASE:
			act_release()
		ACTION_SETTLE:
			act_settle()


## `ui_accept` on the screen: release the picked claim when THIS HERO holds it, and
## decline otherwise. Declared in one place because two consumers (`on_stack_input` and
## the action bar) must agree on what a press means.
func _accept() -> bool:
	if _holder_is_mine(_picked_view()):
		act_release()
		return true
	return false


## Move the pick `step` entries along the shown list, wrapping. Returns false when there
## is nothing to pick, so `ui_down` on an empty board is declined rather than consumed —
## a screen that swallows a key it cannot honour is a screen that has swallowed the
## player's cancel by association.
func _step(step: int) -> bool:
	var ids := _claim_ids(_claim_summaries())
	if ids.is_empty():
		return false
	var index := ids.find(_selected_claim)
	if index < 0:
		index = 0 if step > 0 else ids.size() - 1
	_selected_claim = String(ids[posmod(index + step, ids.size())])
	_render()
	return true


## A refusal this screen raises ITSELF, in the module's own `{ok, reason}` shape. Never a
## silent no-op: an action a player asked for that did not happen is reported in the
## same vocabulary the modules use, so one renderer covers both.
func _verdict(reason: String) -> Dictionary:
	return _settle({"ok": false, "reason": reason})


## Record a verdict, repaint, and hand the caller the verb's OWN dictionary. The screen
## never rewrites it, so the last result is the module's answer and a test can compare it
## against `CustodyApi` directly.
##
## The repaint happens AFTER the verdict is recorded, so the rows the player sees are the
## ones the verdict describes: a refused verb writes nothing anywhere — the coin leg
## precedes the claim write (ADR 0104) — so the custody behind it is byte-for-byte as
## found, and painting the refusal over it is what makes "the world did not change, and
## here is why" legible on one line.
func _settle(result: Dictionary) -> Dictionary:
	_bind_nodes()
	_last_result = result.duplicate(true)
	if bool(_last_result.get("ok", false)):
		set_message(String(_last_result.get("reason", "")), TONE_OK)
	else:
		# The reason VERBATIM. Not "Rejected: holder_mismatch", not a sentence this screen
		# composed: the module authored the constant and a panel that reworded it would be
		# describing a rule the module never wrote.
		set_message(String(_last_result.get("reason", "")), TONE_ERROR)
	refresh()
	return _last_result.duplicate(true)


## Every mounted row's own summary, in display order. A spare pool row reports `{}`,
## which is what makes the reported count the ledger's AUTHORED size rather than the size
## of the pool the scene happened to mount.
func _claim_summaries() -> Array:
	var out: Array = []
	for row in _claim_rows:
		var filled: Dictionary = (row as CustodyClaimRow).summary()
		if filled.is_empty():
			continue
		out.append(filled)
	return out


## The facade row for the current pick, or `{}` when nothing is picked. The picked row's
## OWN summary rather than a facade re-read, so the action bar's enabled state and the
## claim row on screen can never describe two different worlds.
func _picked_view() -> Dictionary:
	if _selected_claim == "":
		return {}
	for filled in _claim_summaries():
		if String((filled as Dictionary).get("claim_id", "")) == _selected_claim:
			return filled as Dictionary
	return {}


func _claim_ids(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		out.append(String((row as Dictionary).get("claim_id", "")))
	return out


func _count_where(rows: Array, key: String) -> int:
	var total := 0
	for row in rows:
		if bool((row as Dictionary).get(key, false)):
			total += 1
	return total


## How many of these rows are held by the actor this screen is bound to.
func _mine_count(rows: Array) -> int:
	var total := 0
	for row in rows:
		if _holder_is_mine(row as Dictionary):
			total += 1
	return total


## Whether a row's claim is held by the actor this screen is bound to — an `actor`
## holder whose id is this actor's. The holder may instead be an institution, and an
## institution is NOT this hero: a sect may hold a claim that no press on this page
## took, so a claim the player can SEE is not automatically a claim the player can
## release.
func _holder_is_mine(picked: Dictionary) -> bool:
	if picked.is_empty() or _actor == null:
		return false
	if not bool(picked.get("held", false)):
		return false
	return (
		String(picked.get("holder_kind", "")) == OWNER_KIND
		and String(picked.get("holder_id", "")) == String(_actor.id)
	)
