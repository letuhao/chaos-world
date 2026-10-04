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
## and the installed one is used. With no target the cast still fires and still pays;
## it simply resolves an empty descriptor, which is the module's own rule.
##
## Contract: `summary()` is the testable surface, with each slot's own summary
## nested under `slots`. `{}` with no actor.

## Slots the scene mounts. The pool is grown at runtime rather than truncated, so a
## tier's larger budget is never quietly cut down to what the scene happened to
## declare.
const SLOT_ROWS := 7
const SLOT_SCENE := "res://src/ui/panels/technique_slot_row.tscn"
## Concatenated, not one literal: gdformat will not split a string literal, so a
## single 102-char line here fails `gdlint`'s max-line-length for good.
const HEADER_TEXT := (
	"Bound for now. The codex keeps everything; " + "this page decides nothing permanent."
)
const NO_ACTOR_TEXT := "No hero bound."
## The path pools the budget row is stated in, in the facade's own order.
const POOLS := [PathState.QI, PathState.BODY, PathState.MIND, &"universal"]

## The module's own refusal reasons, worded for a player. `activate` and `equip` both
## publish a stable `reason` string; naming each one is how the UI can report a
## refusal HONESTLY instead of restating it as one generic failure. Unknown reasons
## fall back to [refusal_text]'s default rather than printing machine vocabulary.
const REFUSALS := {
	&"realm_unmet": "Your realm does not reach it yet",
	&"not_learned": "Not learned yet",
	&"no_free_slot": "No free slot in its pool",
	&"not_equipped": "Not bound right now",
	&"not_active": "That one is a passive, not an action",
	&"on_cooldown": "Still cooling down",
	&"insufficient_resources": "Not enough qi or stamina",
	&"unknown_definition": "No such technique",
}
const REFUSAL_DEFAULT := "Refused"

var _live: Dictionary = {}
var _header: Label = null
var _budget: Label = null
var _slot_box: VBoxContainer = null
var _picker: TechniqueEquipPicker = null
var _slot_rows: Array = []
var _bound: bool = false


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
	_header.text = HEADER_TEXT if _actor != null else NO_ACTOR_TEXT
	if _budget != null:
		_budget.text = _budget_line()


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
## `target` is optional and is the only thing this screen cannot decide: `activate`
## pays and starts the cooldown whether or not a target is supplied, and resolves an
## empty damage descriptor when there is none. That is the module's rule, so this
## screen passes `null` rather than inventing a target it does not own.
func act_cast(technique_id: StringName, target: Actor = null) -> Dictionary:
	if _actor == null or technique_id.is_empty():
		set_message("No hero bound", TONE_ERROR)
		refresh()
		return {}
	var casting := _casting()
	if casting == null:
		set_message("Casting is not available", TONE_ERROR)
		refresh()
		return {}
	var fired: Dictionary = casting.activate(_actor, technique_id, target)
	if bool(fired.get("ok", false)):
		set_message("Fired %s" % String(technique_id), TONE_OK)
	else:
		set_message(
			"%s: %s" % [String(technique_id), refusal_text(String(fired.get("reason", "")))],
			TONE_ERROR
		)
	refresh()
	return fired


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


## The module's reason, in words a player can act on. An unrecognised reason falls
## back rather than printing machine vocabulary at them.
func refusal_text(reason: String) -> String:
	return String(REFUSALS.get(StringName(reason), REFUSAL_DEFAULT))


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
func _cast_view(view: Dictionary) -> void:
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
