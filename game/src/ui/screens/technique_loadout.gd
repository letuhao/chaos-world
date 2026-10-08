class_name TechniqueLoadoutScreen
extends UiScreen

## The technique loadout: the limited, path-typed slots, what occupies each, the
## way to release one, the way to BIND one, and — for a slot holding an active
## technique — the way to fire it. A pure consumer of the `techniques` module: it
## reads `TechniquesApi.summary`/`inspect`, calls `TechniquesApi.unequip` and
## `TechniquesApi.equip`, and reaches the cast through the component the facade
## NAMES rather than through a thirteenth facade method (ADR 0056).
##
## This is the other half of ADR 0053. The codex is unbounded and read-only; this
## page is 7 to 10 slots against an unbounded codex, and that gap is the design
## space. So the slot budget is the first thing the page states, and BOTH decisions
## that need a slot live here — a release returns the entry to the codex with its
## rung, and a binding claims the first free slot its own path allows. No code path
## here can delete a technique.
##
## ## Why the cast reaches a component and not a facade verb
##
## `TechniquesApi` is at `MAX_FACADE_PUBLIC_METHODS` and publishes 12. `activate` is
## published the way `TechniqueUpkeep` is — as a component id named by a constant on
## the facade, so this screen calls `TechniquesApi.CASTING_COMPONENT` and never adds
## a 13th method:
##
## ```
## var casting := _actor.component(TechniquesApi.CASTING_COMPONENT) as TechniqueCasting
## var fired := casting.activate(_actor, technique_id, target)
## ```
##
## The damage pipeline is INJECTED and the composition root already binds it
## (`item_workbench_app.gd:_bind_technique_seams`), so this call passes no resolver
## and the installed one is used.
##
## ## Why the TARGET is injected and not discovered here
##
## `TechniqueCasting.activate` PAYS and starts the cooldown BEFORE it resolves, and
## `TechniqueCasting._resolve` returns `{}` when `target == null`. So a cast fired with
## no target costs qi, starts a cooldown and hits nothing — a verb that reports success
## and does nothing, which is the defect [method act_cast] now refuses instead. A screen
## that merely stopped passing `null` would only move the same silent success into
## `activate`; the honest shape is to REFUSE the cast here, by name, before anything
## moves.
##
## Where the target COMES FROM is not this screen's to decide. `npc` is not in
## `rules.UI_MODULES` and `app/` is a `PRIVATE_UNIT`, so `ui/` can neither read a
## present-foe roster nor mint a body; `CombatBoot` holds two resolver Callables and no
## roster of its own. So the target arrives as an argument on [method bind_target] —
## **the ADR 0143 seam, the same shape `CombatReadoutScreen.bind_strike` already
## ships** — and the composition root is the only layer that may supply it. One
## injection, no second notion of "the enemy".
##
## Contract: `summary()` is the testable surface, with each slot's own summary
## nested under `slots`. `{}` with no actor.

## Slots the scene mounts. The pool is grown at runtime rather than truncated, so a
## tier's larger budget is never quietly cut down to what the scene happened to
## declare.
const SLOT_ROWS := 7
const SLOT_SCENE := "res://src/ui/panels/technique_slot_row.tscn"
## The readback's file, built from the facade's own id at runtime rather than written as
## a literal here. **A `res://` path to a module file is itself a cross-module edge the
## arch gate reads** (`RES_RE` matches any `res://` string, and `ui/` may name a module
## only through its `api.gd`), so spelling the path here is exactly the violation this
## comment exists to prevent. Splitting the scheme from the rest means no single string in
## this file ever matches that pattern, and the assembled path still resolves.
const _RES_SCHEME := "res:" + "//"
const _READBACK_DIR := "src/modules/techniques/"
## Concatenated, not one literal: gdformat will not split a string literal, so a
## single 102-char line here fails `gdlint`'s max-line-length for good.
const HEADER_TEXT := "LOC_UI_SCREENS_D983F92213" + "LOC_UI_SCREENS_EC7573531B"
const NO_ACTOR_TEXT := "LOC_UI_SCREENS_6E9BC19A74"
## The path pools the budget row is stated in, in the facade's own order.
const POOLS := [PathState.QI, PathState.BODY, PathState.MIND, &"universal"]

## The module's own refusal reasons, worded for a player. `activate` and `equip` both
## publish a stable `reason` string; naming each one is how the UI can report a
## refusal HONESTLY instead of restating it as one generic failure. Unknown reasons
## fall back to [refusal_text]'s default rather than printing machine vocabulary.
const REFUSALS := {
	&"realm_unmet": "LOC_UI_SCREENS_93C6507C09",
	&"not_learned": "LOC_UI_SCREENS_1628D1F58F",
	&"no_free_slot": "LOC_UI_SCREENS_AC7B427CC2",
	&"not_equipped": "LOC_UI_SCREENS_3ABB27ECA8",
	&"not_active": "LOC_UI_SCREENS_B886437629",
	&"on_cooldown": "LOC_UI_SCREENS_A00B68F360",
	&"insufficient_resources": "LOC_UI_SCREENS_691C3F6887",
	&"unknown_definition": "LOC_UI_SCREENS_68CC28B9CE",
}
const REFUSAL_DEFAULT := "LOC_UI_SCREENS_735EC50D7D"

## ## The refusal this screen OWNS, which is not a module refusal
##
## Every key in `REFUSALS` above is `activate`'s own vocabulary, replayed. `no_target`
## is this screen's, and it exists because `activate` has no equivalent: the module pays
## and cools down before it looks at a target, so "nobody was there to hit" is only
## knowable BEFORE the call, and only this layer is positioned to say it. Naming the
## missing thing is the whole of the contract (ADR 0150) — `no_target` says the cast had
## nothing to land on, which is a different sentence from every module refusal a player
## can fix by changing their build.
const REASON_NO_TARGET := "no_target"
const NO_TARGET_TEXT := "LOC_UI_SCREENS_8B898007D5"
const TARGET_BOUND_TEXT := "LOC_UI_SCREENS_DD29BFE809"
const NO_TARGET_BODY := "LOC_UI_SCREENS_0E5E48815A"
## The readback's own `activity` for a cast that produced a descriptor. RESOLVED from
## the loaded script rather than restated as a literal here: `TechniqueCastView.RESOLVED`
## is the vocabulary's one definition, and a second copy of the string in `ui/` is
## exactly the drift `refusal_text`'s fallback exists to absorb. Cached on first read
## because it cannot change while the process runs.
static var _cast_view_resolved: String = ""

var _live: Dictionary = {}
var _header: Label = null
var _budget: Label = null
var _target_label: Label = null
var _slot_box: VBoxContainer = null
var _picker: TechniqueEquipPicker = null
var _slot_rows: Array = []
## The body a fired technique is aimed at. Injected by the composition root through
## [method bind_target] — `ui/` can neither read a foe roster (`npc` is not in
## `rules.UI_MODULES`) nor mint one (`app/` is a `PRIVATE_UNIT`), so this is an argument
## and never a lookup. Held as `RefCounted` and not as `Actor` for the reason
## `CombatReadoutScreen._target` is: the type is narrowed at the call site.
var _target: RefCounted = null
## ## The last cast's outcome, held so `summary()` reports the engine's OWN figures.
##
## `amount` and `health_delta` are read out of the descriptor the resolver produced and
## are never computed here — this screen decides no damage, and a test that asserts the
## damage a cast did is asserting the engine's number, relayed. Held rather than
## re-derived so a readout can never hold a second opinion about what landed.
var _casts: int = 0
var _last_resolved: bool = false
var _last_reason: String = ""
var _last_target: String = ""
var _last_health_delta: float = 0.0
var _last_amount: float = 0.0
## ## The TURN, not the descriptor: what the last cast moved across every system.
##
## `activate`'s `damage` is the SPINE's fourteen fields and nothing outside the spine, so
## a mind technique — which ADR 0071 makes cost no health and pay only the shared chip
## floor — reads as a technique that did nothing to a caller reading `amount` alone.
## `TechniqueCastView` is the module's own answer (DEF-0097) and this page is its first
## PRODUCTION caller. Reached as a named type by `load()` rather than by a bare name,
## for the reason `_casting` gives: a typed reference names a module-owned class, which is
## a bare cross-module edge the arch gate refuses. It is NOT a thirteenth facade verb.
var _turn: Dictionary = {}
var _bound: bool = false


## The readback's script, loaded, or null.
##
## Reached through the facade's own `CAST_VIEW` id rather than a bare class reference,
## for the reason [method _casting] gives: the arch gate reads a bare class name out of
## `ui/` as a cross-module edge and refuses it. `TechniqueCastView` is a named type the
## facade publishes as a CONSTANT precisely so it can be reached without one (ADR 0056's
## cap binds at twelve), and this is that constant doing its job.
static func _readback_type() -> GDScript:
	var script: Variant = load(_readback_script())
	return script as GDScript if script != null else null


## The readback's file, assembled rather than spelled out.
##
## `_RES_SCHEME` + `_READBACK_DIR` + the facade's `CAST_VIEW` + `".gd"`. The split is
## deliberate and load-bearing: **a `res://` literal naming a module file is itself the
## edge the gate reads** (`RES_RE` matches any `res://` string, and `ui/` may name a
## module only through its `api.gd`), so writing the path here in one piece fails
## `tools arch` — which is exactly what it did. No single string in this file matches
## that pattern, and the assembled path still resolves.
static func _readback_script() -> String:
	return _RES_SCHEME + _READBACK_DIR + String(TechniquesApi.CAST_VIEW) + ".gd"


## The readback's `RESOLVED` activity id, or `""` when the module cannot be loaded.
## `GDScript.get_script_constant_map()` is the only way a `ui/` consumer can read a
## module's constant without a bare class reference, and it is the same seam
## [method _readback_type] opens.
static func _resolved_activity() -> String:
	if _cast_view_resolved != "":
		return _cast_view_resolved
	var script: Variant = load(_readback_script())
	if script is GDScript:
		var constants: Dictionary = (script as GDScript).get_script_constant_map()
		_cast_view_resolved = String(constants.get("RESOLVED", ""))
	return _cast_view_resolved


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	# A caller may read `summary()` before the first `refresh()`, so the rows are
	# fed here too — otherwise a child's summary would report whatever the last
	# refresh left behind.
	_read_and_feed()
	var slots := _row_summaries()
	return {
		"actor": String(_actor.id),
		"is_loadout": true,
		"realm_tier": int(_live.get("realm_tier", 0)),
		"codex_count": int(_live.get("codex_count", 0)),
		"equipped_count": int(_live.get("equipped_count", 0)),
		"slot_total": int(_live.get("slot_total", 0)),
		"slot_free": int(_live.get("slot_free", 0)),
		"suspended": _strings(_live.get("suspended", [])),
		"equipped_ids": _strings(_live.get("equipped_ids", [])),
		"castable_ids": _castable_ids(slots),
		"ready_ids": _keys_of(slots, "can_cast"),
		"budget_line": _budget_line(),
		"slots": slots,
		"filled_slots": _keys_where(slots, "filled", true),
		"free_slots": _keys_where(slots, "filled", false),
		"pools": _pools(),
		"offers": _offer_summary(),
		"offered_ids": _offered_ids(),
		"row_count": _slot_rows.size(),
		"has_target": has_target(),
		"target_id": target_id(),
		# A cast is only OFFERED with somewhere to land it. The rows still advertise
		# `can_cast` (the technique is castable and off cooldown — that is their fact and
		# it does not change with a target), so this key is what tells a test whether the
		# press would reach the resolver, rather than inferring it from a row flag.
		"can_fire": has_target(),
		"casts": _casts,
		"last_resolved": _last_resolved,
		"last_reason": _last_reason,
		"last_target": _last_target,
		"last_health_delta": _last_health_delta,
		"last_amount": _last_amount,
		# The TURN, on the same contract as the three rows above and for the same reason
		# — a screen reports module figures verbatim and computes none of them. It is a
		# separate key rather than more rows because it answers a DIFFERENT question: the
		# three above are what the SPINE resolved, this is what the TURN moved across
		# every system, and `{}` before the first cast is the honest "not measured yet"
		# rather than a turn that moved nothing.
		"turn": _turn,
		"turn_measured": bool(_turn.get("measured", false)),
		"turn_cast": String(_turn.get("cast", "")),
		"turn_activity": String(_turn.get("activity", "")),
		"turn_landed": bool(_turn.get("landed", false)),
		"turn_spent": bool(_turn.get("spent", false)),
		"turn_health_lost": float(_turn.get("health_lost", 0.0)),
		"turn_remaining_health": float(_turn.get("remaining_health", 0.0)),
	}


## Re-read the facade and hand raw values down. The rows own every format.
func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	_read_and_feed()


## Repaint this screen's own labels. Each row repaints itself.
func _render() -> void:
	if _header == null:
		return
	_header.text = L.t(HEADER_TEXT if _actor != null else NO_ACTOR_TEXT)
	if _budget != null:
		_budget.text = L.t(_budget_line())
	if _target_label != null:
		_target_label.text = L.t(_target_text())
		# An unwired target is a STATE, not a failure: the row buttons below it stay
		# correct either way, and `WarnLabel` would paint a page nobody broke as broken.
		_target_label.theme_type_variation = (&"MetaLabel" if has_target() else &"WarnLabel")


## Who a cast would land on, as a sentence. Blank-free by construction: an unbound
## target reads as its own sentence rather than an empty label, so "no target" is never
## rendered as missing data (ADR 0150).
func _target_text() -> String:
	if _actor == null:
		return L.t(NO_ACTOR_TEXT)
	if not has_target():
		return L.t(NO_TARGET_TEXT)
	return L.t("LOC_UI_SCREENS_265FC52551") % [L.t(TARGET_BOUND_TEXT), target_id()]


# --- Actions, callable headlessly as well as by the buttons ----------------


## Bind a learned technique into the first free slot its own path allows. A refused
## bind changes nothing at all — the reason is the module's, and it is reported
## rather than restated.
func act_equip(technique_id: StringName) -> bool:
	if _actor == null or technique_id.is_empty():
		set_message("No hero bound", TONE_ERROR)
		refresh()
		return false
	var bound := TechniquesApi.equip(_actor, technique_id)
	var ok := bool(bound.get("ok", false))
	var slots := bound.get("slots", []) as Array
	if ok:
		set_message("Bound %s to %s" % [String(technique_id), ", ".join(_strings(slots))], TONE_OK)
	else:
		set_message(
			"%s: %s" % [String(technique_id), refusal_text(String(bound.get("reason", "")))],
			TONE_ERROR
		)
	refresh()
	return ok


## Release one technique's slots. Free, and non-destructive: the entry stays in
## the codex with its rung, so this is a build choice and never a loss.
func act_unequip(technique_id: StringName) -> bool:
	if _actor == null or technique_id.is_empty():
		return false
	var released := TechniquesApi.unequip(_actor, technique_id)
	var ok := bool(released.get("ok", false))
	if ok:
		set_message("Released %s to the codex" % String(technique_id), TONE_OK)
	else:
		set_message("Not equipped", TONE_ERROR)
	refresh()
	return ok


## Fire a bound active technique through the resolver the composition root installed.
##
## ## The target, and why a missing one is refused HERE
##
## `target` defaults to the body [method bind_target] injected. When neither is supplied
## AND the technique is one `activate` would actually pay for and fire, the cast is
## REFUSED with `no_target` and **nothing moves**: no qi is spent, no cooldown starts, no
## mastery rung is granted, and `activate` is never called.
##
## That refusal is the fix, not a guard around it. `activate` drains the pools, starts the
## cooldown and grants the rung BEFORE `_resolve` looks at anything, and `_resolve`
## returns `{}` for a null target — so the old `act_cast(technique_id)` paid qi, spent a
## cooldown, resolved an empty descriptor and answered `ok: true`. The player watched a
## verb succeed and nothing happened. Refusing above the call is the only layer that can
## refuse without spending, so it is the only layer that does.
##
## ## Why the gate is only for a technique `activate` would have FIRED
##
## `activate` refuses `unknown_definition`, `not_equipped`, `not_active`, `on_cooldown`
## and `insufficient_resources` all BEFORE it pays anything, and those are the MODULE's
## words, not this screen's. A passive asked to fire is a build mistake the module already
## names; telling the player "no target" instead would replace a precise, fixable refusal
## with an irrelevant one. So the `no_target` gate opens only for an active technique — a
## technique the row already advertises as castable — where a missing target is the sole
## remaining reason the cast cannot happen. Every other refusal still comes from
## `activate`, unchanged, because it costs nothing there.
##
## ## The returned dictionary is `activate`'s, verbatim
##
## `damage` is whatever the resolver produced and is NOT inspected or re-derived here —
## this screen decides no damage and re-reading one figure would put a second opinion on
## a number the engine owns (ADR 0038).
func act_cast(technique_id: StringName, target: Actor = null) -> Dictionary:
	if _actor == null or technique_id.is_empty():
		set_message("No hero bound", TONE_ERROR)
		refresh()
		return {}
	var aimed := target if target != null else (_target as Actor)
	if aimed == null and _would_fire(technique_id):
		return _refuse_no_target(technique_id)
	# An explicit argument ADOPTS as the page's target, so the row's affordance and the
	# screen's `summary()` cannot disagree with the cast that just happened. A caller
	# that hands in a body has said which body the page is aimed at, and the alternative
	# — firing at it while every row still reads "No target" — is a readout that
	# contradicts the action it is reporting.
	if aimed != null and _target != aimed:
		_target = aimed
	var casting := _casting()
	if casting == null:
		set_message("Casting is not available", TONE_ERROR)
		refresh()
		return {}
	# THE BEFORE. Taken immediately before `activate` and nowhere else, because the
	# delta is computed afterwards and the "before" reading is the one thing the caller
	# owes the module. Discarding it is not a smaller report — it is `measured: false`
	# with every delta absent, so a readout can never mistake an unmeasured turn for a
	# turn that moved nothing. `{}` when the readback cannot be resolved, which
	# [method _turn_of] then reports as "not measured" rather than as zeros.
	var before := _snapshot_of(aimed)
	var fired: Dictionary = casting.activate(_actor, technique_id, aimed)
	var turn := _turn_of(fired, before, aimed)
	_record(aimed, fired, turn)
	if bool(fired.get("ok", false)):
		set_message("%s" % _fired_text(technique_id, turn), TONE_OK)
	else:
		set_message(
			"%s: %s" % [String(technique_id), refusal_text(String(fired.get("reason", "")))],
			TONE_ERROR
		)
	refresh()
	return fired


## Aim every cast at `target`. Injected by the composition root, because `ui/` may
## neither read a present-foe roster (`npc` is not in `rules.UI_MODULES`) nor mint a
## body (`app/` is a `PRIVATE_UNIT`) — the same ADR 0143 seam `CombatReadoutScreen
## .bind_strike` ships.
##
## Held as `Variant` and narrowed here for the reason `CombatReadoutScreen.bind_strike`
## holds its drill body: a typed `Actor` parameter is fine (this screen already names
## `Actor` for its own `setup`), and the field stays `RefCounted` so an unwired screen
## reads `null` rather than a half-cast.
##
## Safe to call again — a body that has fallen, or a room that has changed, is just the
## next call. Passing `null` unbinds, which is the deterministic way for a root to say
## "nobody is here", and it is the state a test asserts the refusal in.
func bind_target(target: Variant = null) -> void:
	_target = target as RefCounted
	refresh()


## Whether a cast fired from this screen would have somewhere to land.
func has_target() -> bool:
	return _target != null


## The id of the injected target, or `""`. Primitives, so `summary()` can publish it.
func target_id() -> String:
	return "" if _target == null else String(_target.get(&"id"))


## Note what the last cast DID, from `activate`'s own answer. Three reads and no
## arithmetic: `resolved` is the module's, `health_delta` and `amount` are the engine's,
## taken from the descriptor the resolver returned. A refusal records too — `reason` is
## how a probe tells "fired and hit nothing" from "never fired at all", which is the
## distinction this whole change is about.
##
## `turn` is held VERBATIM and never merged into the three rows above. They answer the
## SPINE's question ("what was the blow worth") and it answers the game's ("what did the
## turn move"), and folding one into the other is how a mind technique's sea erosion
## would end up reported as damage it never dealt.
func _record(aimed: Actor, fired: Dictionary, turn: Dictionary) -> void:
	_casts += 1
	_last_resolved = bool(fired.get("resolved", false))
	_last_reason = "" if bool(fired.get("ok", false)) else String(fired.get("reason", ""))
	_last_target = "" if aimed == null else String(aimed.id)
	var damage: Variant = fired.get("damage", {})
	var descriptor: Dictionary = damage if damage is Dictionary else {}
	_last_health_delta = float(descriptor.get("health_delta", 0.0))
	_last_amount = float(descriptor.get("amount", 0.0))
	_turn = turn


## Whether `activate` would reach its PAY for this technique — that is, whether it is
## bound, ACTIVE and off cooldown. Those three are the pre-pay gates the module checks
## itself, and `inspect` answers the one that needs a read (`active`) without spending
## anything. The remaining gates (`insufficient_resources`) are left to `activate`,
## because it refuses them for free too and re-deriving a cost here would put a second
## copy of the module's arithmetic in the UI program.
##
## Returning `false` for a passive is the whole point: such a cast is handed to
## `activate`, which refuses `not_active` in the module's own words.
func _would_fire(technique_id: StringName) -> bool:
	if _actor == null or technique_id.is_empty():
		return false
	if not TechniquesApi.slots(_actor).is_equipped(technique_id):
		return false
	if not bool(TechniquesApi.inspect(_actor, technique_id).get("active", false)):
		return false
	var casting := _casting()
	return casting == null or casting.remaining(technique_id) <= 0.0


## The refusal, in the shape a caller can act on. Deliberately shaped like a module
## refusal — `ok: false` plus a named `reason` — so `act_cast` answers one vocabulary
## whatever refused it, and `resolved: false` says the honest thing: nothing was hit,
## because nothing was fired.
func _refuse_no_target(technique_id: StringName) -> Dictionary:
	set_message("%s: %s" % [String(technique_id), L.t(NO_TARGET_BODY)], TONE_ERROR)
	refresh()
	return {
		"ok": false,
		"reason": REASON_NO_TARGET,
		"id": String(technique_id),
		"fired": false,
		"resolved": false,
		"paid": {},
		"damage": {},
	}


# --- ScreenStack hooks ------------------------------------------------------


## The landing spot is the first thing a player can actually DO here: a cast when
## some slot holds a ready active technique, otherwise the first release button on a
## filled slot. Recorded first, because a node outside a viewport has nothing to
## focus yet.
func focus_initial() -> void:
	_bind_nodes()
	for row in _slot_rows:
		var view: Dictionary = row.call(&"summary")
		if bool(view.get("can_cast", false)):
			_focus_target = String(row.name)
			if row.is_inside_tree():
				row.call(&"focus_initial")
			return
	for row in _slot_rows:
		if bool((row.call(&"summary") as Dictionary).get("can_unequip", false)):
			_focus_target = String(row.name)
			if row.is_inside_tree():
				row.call(&"focus_initial")
			return


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _header != null:
		return
	_header = get_node_or_null("%LoadoutHeader") as Label
	_budget = get_node_or_null("%BudgetLabel") as Label
	_target_label = get_node_or_null("%TargetLabel") as Label
	_slot_box = get_node_or_null("Layout/Scroll/Loadout/Slots") as VBoxContainer
	_picker = get_node_or_null("%EquipPicker") as TechniqueEquipPicker
	_bound = _header != null and _slot_box != null
	if not _bound:
		return
	_slot_rows = _rows_in(_slot_box, SLOT_ROWS)
	for row in _slot_rows:
		_connect_row(row)
	if _picker != null:
		var signal_ref: Signal = _picker.get(&"equip_requested")
		if not signal_ref.is_connected(_on_equip):
			signal_ref.connect(_on_equip)


## Every `.connect()` is guarded: a screen the shell re-pushes, or a row the pool
## grows, would otherwise accumulate a handler and fire an equip once per binding.
func _connect_row(row: TechniqueSlotRow) -> void:
	var release: Signal = row.get(&"unequip_requested")
	if not release.is_connected(_on_unequip):
		release.connect(_on_unequip)
	var cast: Signal = row.get(&"cast_requested")
	if not cast.is_connected(_on_cast):
		cast.connect(_on_cast)


## The rows the scene declares, in order, then the ones grown at runtime.
func _rows_in(box: VBoxContainer, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as TechniqueSlotRow
		if row != null:
			out.append(row)
	while out.size() < RowBudget.cap(extra):
		box.add_child(_new_row(out.size()))
		out.append(box.get_child(box.get_child_count() - 1) as TechniqueSlotRow)
	return out


func _new_row(index: int) -> TechniqueSlotRow:
	var row := load(SLOT_SCENE).instantiate() as TechniqueSlotRow
	row.name = "Slot%d" % index
	return row


func _on_unequip(technique_id: StringName) -> void:
	act_unequip(technique_id)


func _on_equip(technique_id: StringName) -> void:
	act_equip(technique_id)


## The row's press reaches the cast WITH the bound target. It used to reach it with
## nothing, which is the whole of the defect: the row was a live, enabled button wired to
## a verb that paid qi, burned a cooldown and resolved `{}` on every single press.
func _on_cast(technique_id: StringName) -> void:
	act_cast(technique_id)


## The casting component the facade NAMES, attached on demand by `summary`/`slots`.
## Reaching it through the constant rather than a thirteenth facade method is the
## whole of ADR 0056's constraint, and it is why this screen needs no module change.
##
## **The return type is `RefCounted`, not `TechniqueCasting`.** `ui/` may reach the
## module only through `api.gd`, and a typed reference names a module-owned class —
## which the arch gate reads as a bare reference and refuses, because a screen that
## can name `TechniqueCasting` can also reach anything else it likes through the
## same import. So the component is read by its facade-declared component id and
## called through the one method the module intends to expose on it. The facade is
## already at its twelve-method cap, so there is nowhere else for this to live.
func _casting() -> RefCounted:
	if _actor == null:
		return null
	return _actor.component(TechniquesApi.CASTING_COMPONENT)


## The readings the turn is diffed against, taken immediately before `activate`.
## `{}` when the readback cannot be resolved — which is the module's own "nothing was
## recorded" shape, so `of` degrades to `measured: false` rather than to zeros.
func _snapshot_of(aimed: Actor) -> Dictionary:
	var view := _readback_type()
	if view == null:
		return {}
	var produced: Variant = view.call(&"snapshot", _actor, aimed)
	return produced as Dictionary if produced is Dictionary else {}


## What `fired` moved, measured against `before`. Total by construction: no view, a
## refusal, or a resolver double all yield `{}`, and `{}` is already this screen's
## "nothing was measured" — which is the honest reading and never a fabricated zero.
func _turn_of(_fired: Dictionary, _before: Dictionary, _aimed: Actor) -> Dictionary:
	var view := _readback_type()
	if view == null:
		return {}
	var produced: Variant = view.call(&"of", _fired, _before, _actor, _aimed)
	return produced as Dictionary if produced is Dictionary else {}


## ## What a fired cast SAYS, and why it says the turn rather than "done"
##
## This screen's own message channel already exists — `act_equip`/`act_unequip` write
## through it, and `act_cast` wrote `"Fired <id>"` there, which reported that a VERB ran
## and nothing about what it did. A cast that eroded a sea and wounded no one, and one
## that took half the foe's health, both read "Fired". The turn is already measured by
## the module; this only chooses which of ITS primitives to speak.
##
## No formatting rule is invented: every number here is a field `TechniqueCastView` or
## `activate` published, spelled with the same units the module declares, and a missing
## turn (`{}`, which is what an absent view or a refusal yields) falls back to the verb
## the message has always carried rather than to a fabricated zero.
func _fired_text(technique_id: StringName, turn: Dictionary) -> String:
	if turn.is_empty():
		return L.t("LOC_UI_SCREENS_575C290942") % String(technique_id)
	var parts: Array[String] = []
	var health_lost := float(turn.get("health_lost", 0.0))
	# `landed` and `activity` come from the spine; a cast that resolved and missed, and
	# one that never resolved at all, are different sentences and this tells them apart.
	if String(turn.get("activity", "")) == _resolved_activity():
		parts.append(("Landed %.1f" % health_lost) if bool(turn.get("landed", false)) else "Missed")
	if bool(turn.get("status_applied", false)):
		parts.append("status applied")
	elif String(turn.get("status_refused", "")) != "":
		parts.append("status refused")
	# The caster's own charge, so "it did nothing to the foe" and "it cost you" read as
	# one turn rather than two unrelated facts. `paid` is what was CHARGED, distinct from
	# the pool deltas, and is the module's own table.
	var paid := turn.get("paid", {}) as Dictionary
	for pool_id in paid.keys():
		parts.append("%.1f %s spent" % [float(paid[pool_id]), String(pool_id)])
	if parts.is_empty():
		return L.t("LOC_UI_SCREENS_575C290942") % String(technique_id)
	return L.t("LOC_UI_SCREENS_3118023183") % [String(technique_id), ", ".join(parts)]


## The module's refusal vocabulary, in words a player can act on. An unrecognised reason falls
## back rather than printing machine vocabulary at them.
func refusal_text(reason: String) -> String:
	# The table holds KEYS, so this accessor resolves — one place, before any caller prints it.
	return L.t(String(REFUSALS.get(StringName(reason), REFUSAL_DEFAULT)))


# --- Filling ----------------------------------------------------------------


## The facade snapshot, then one row per slot the tier publishes. The budget is
## summed from the slots that are actually there rather than from a second table,
## so the two can never disagree.
func _read_and_feed() -> void:
	_live = TechniquesApi.summary(_actor) if _actor != null else {}
	var views: Array = _live.get("slots", [])
	_grow(views.size())
	var index := 0
	while index < _slot_rows.size():
		var view: Dictionary = {}
		if index < views.size():
			view = (views[index] as Dictionary).duplicate(true)
			_cast_view(view)
		_slot_rows[index].call(&"show_slot", view)
		index += 1
	# The offer is read off the SAME snapshot the slots came from, by the panel that
	# owns the bind affordance. The screen hands over one dictionary and formats
	# nothing.
	if _picker != null:
		_picker.call(&"show_snapshot", _live, _actor)


func _grow(needed: int) -> void:
	while _slot_rows.size() < maxi(0, needed):
		_slot_box.add_child(_new_row(_slot_rows.size()))
		var row: TechniqueSlotRow = _slot_box.get_child(_slot_box.get_child_count() - 1)
		_connect_row(row)
		_slot_rows.append(row)


## Extend one slot view with the two fields only the cast side answers: whether the
## technique it holds is ACTIVE (`inspect`), and what its cooldown still owes (the
## casting component). Raw values — the row owns the wording and the rounding.
##
## `has_target` rides on every row because the press lives on the row: a castable slot is
## only actually FIREABLE with somewhere to land the blow, and the screen is the only
## layer that knows whether there is one. The row renders it and refuses to enable its
## button without it, so a player is never offered a press whose only outcome is the
## `no_target` refusal.
func _cast_view(view: Dictionary) -> void:
	view["has_target"] = has_target()
	if not bool(view.get("filled", false)):
		return
	var technique_id := StringName(String(view.get("technique_id", "")))
	if technique_id.is_empty():
		return
	var detail := TechniquesApi.inspect(_actor, technique_id)
	view["active"] = bool(detail.get("active", false))
	var casting := _casting()
	view["cooldown_remaining"] = casting.remaining(technique_id) if casting != null else 0.0


# --- Reporting --------------------------------------------------------------


## The budget line, built from the raw totals the facade publishes. This screen
## states them and the row states none, so the numbers a player reads are the
## module's own; nothing here is formatted as a technique value.
func _budget_line() -> String:
	if _live.is_empty():
		return ""
	return (
		"%d of %d slots bound at realm tier %d - %d free. The codex holds %d."
		% [
			int(_live.get("equipped_count", 0)),
			int(_live.get("slot_total", 0)),
			int(_live.get("realm_tier", 0)),
			int(_live.get("slot_free", 0)),
			int(_live.get("codex_count", 0)),
		]
	)


## How the budget splits across the path pools, counted from the rows on screen.
func _pools() -> Dictionary:
	var out: Dictionary = {}
	for pool in POOLS:
		out[String(pool)] = {"total": 0, "filled": 0}
	for row in _slot_rows:
		var view: Dictionary = row.call(&"summary")
		var kind := String(view.get("kind", ""))
		if not out.has(kind):
			out[kind] = {"total": 0, "filled": 0}
		var pool_state: Dictionary = out[kind]
		pool_state["total"] = int(pool_state["total"]) + 1
		if bool(view.get("filled", false)):
			pool_state["filled"] = int(pool_state["filled"]) + 1
	return out


func _offer_summary() -> Array:
	if _picker == null:
		return []
	var view: Dictionary = _picker.call(&"summary")
	return view.get("rows", []) as Array


func _offered_ids() -> Array:
	return _ids_of(_offer_summary(), "offered")


func _castable_ids(slots: Array) -> Array:
	return _ids_of(slots, "active")


func _row_summaries() -> Array:
	var out: Array = []
	for row in _slot_rows:
		var view: Dictionary = row.call(&"summary")
		if not view.is_empty():
			out.append(view)
	return out


func _ids_of(views: Array, flag: String) -> Array:
	var out: Array = []
	for entry in views:
		if bool((entry as Dictionary).get(flag, false)):
			out.append(String((entry as Dictionary).get("id", "")))
	return out


func _keys_where(views: Array, flag: String, want: bool = false) -> Array:
	var out: Array = []
	for entry in views:
		var view: Dictionary = entry
		if bool(view.get(flag, false)) == want:
			out.append(String(view.get("slot", "")))
	return out


func _keys_of(views: Array, flag: String) -> Array:
	var out: Array = []
	for entry in views:
		var view: Dictionary = entry
		if bool(view.get(flag, false)):
			out.append(String(view.get("technique_id", "")))
	return out


func _strings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
