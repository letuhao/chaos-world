class_name SoulHearthScreen
extends UiScreen

## The soul and hearth page: what this soul is, what a death costs it, what this run
## is played under, what an anchor costs to raise, and what the save is doing.
##
## ## Why ONE screen and not four
##
## The soul, the difficulty dial, the construction works and the save's status are
## four questions a player asks together about one body. Four screens would mean
## four routes, four nav slots and four back-presses for a single condition, and the
## save half has no verb at all — it could never justify a route of its own. So it
## is one page, and every half is a panel with its own `summary()`.
##
## ## Where each answer comes from, and why
##
##   - **difficulty** and **anchor** are pure reads of their facades plus the
##     `select` / `raise` verbs those facades already own. Both are now in
##     `rules.UI_MODULES`, so this screen names `DifficultyApi` and `AnchorApi` by
##     name — the same shape `SectScreen` and `QuestScreen` use.
##   - **the soul** and **the save** are NOT named. `soul` is absent from
##     `rules.UI_MODULES` and `save` is barred from ever being in it (ADR 0128:
##     `ui/` may not reach `save`). So both arrive as injected Callables, exactly
##     as ADR 0143 prescribes — and for `save` that is not a preference: it is the
##     only shape in which the "the player cannot load the backup" rule can be kept,
##     because the panel this screen hands them to publishes no verb that reaches
##     the backup slot at all.
##
## ## The three seams
##
## [method bind_soul] carries `read_soul` and `read_save`; [method bind_hearth]
## carries `raise_anchor` and `select_difficulty`. Unwired, each half refuses BY
## NAME (`no_soul_seam`, `no_save_seam`, `no_anchor_seam`, `no_difficulty_seam`)
## rather than quietly doing nothing — the shape that made the quest journal read as
## shipped while nothing reached it.
##
## Contract: `summary()` is the testable surface, primitives only, each panel's own
## summary nested under that panel's key, and `{}` when nothing is bound.

## Rows the scene mounts, and the extra the pool may grow. The counts are authored
## CONTENT counts, so every grow is clamped through `RowBudget` before the loop —
## a pool that grows to fit a data-derived count without a bound parents live
## Controls until the machine stops.
const PRESET_SPARE_ROWS := 2
const ANCHOR_SPARE_ROWS := 2
const PRESET_SCENE := "res://src/ui/panels/difficulty_preset_row.tscn"
const ANCHOR_SCENE := "res://src/ui/panels/anchor_construction_row.tscn"
const PRESET_PREFIX := "LOC_UI_SCREENS_BCA788763D"
const ANCHOR_PREFIX := "LOC_UI_SCREENS_8F8C77E740"

const HEADER_TEXT := "LOC_UI_SCREENS_2F80BB6A2E"
const NO_ACTOR_TEXT := "LOC_UI_SCREENS_6E9BC19A74"
const FOOTER_TEXT := "LOC_UI_SCREENS_EB10DBD224" + "undone."
## The refusal this screen raises ITSELF, before any verb is called, in the same
## `{ok, reason}` vocabulary the modules use so one renderer covers both.
const NO_SOUL_SEAM := "no_soul_seam"
const NO_SAVE_SEAM := "no_save_seam"
const NO_ANCHOR_SEAM := "no_anchor_seam"
const NO_DIFFICULTY_SEAM := "no_difficulty_seam"
const NO_ACTOR := "no_actor"

var _ledger: SoulLedgerPanel = null
var _portrait: PortraitPanel = null
var _header: Label = null
var _footer: Label = null
var _preset_box: VBoxContainer = null
var _anchor_box: VBoxContainer = null
var _preset_rows: Array = []
var _anchor_rows: Array = []
var _bound: bool = false
## The soul and the save, as Callables the composition root hands over. Neither is a
## module this screen may name: `soul` is not in `rules.UI_MODULES` and `save` must
## never be (ADR 0128), so this is the only seam either can arrive through.
var _read_soul: Callable = Callable()
var _read_save: Callable = Callable()
## `raise_anchor(anchor_id) -> Dictionary` and `select_difficulty(id) -> Dictionary`,
## taken off the composition root because the root owns the actor and the root is
## the one place those two verbs are wired (ADR 0146, ADR 0129).
var _raise_anchor: Callable = Callable()
var _select_difficulty: Callable = Callable()
## The verdicts of the last two verbs, carried through verbatim. `{}` before any
## press, so a caller reads "no action yet" rather than a refusal that never
## happened. A report, never a selection.
var _last_raise: Dictionary = {}
var _last_select: Dictionary = {}


## Inject the soul and the save reads. `soul` is called as `soul() -> Dictionary` and
## `save` as `save() -> Dictionary`; both take no argument because the root holds
## the actor and a screen that passed one could be bound to a body that has fallen.
func bind_soul(read_soul: Callable, read_save: Callable) -> void:
	_read_soul = read_soul
	_read_save = read_save
	_bind_nodes()
	refresh()


## Inject the two construction verbs. `raise` is called as
## `raise(anchor_id) -> Dictionary` and `select` as `select(difficulty_id) ->
## Dictionary`, each answering the module's own `{ok, reason, ...}` verdict verbatim.
func bind_hearth(raise_anchor: Callable, select_difficulty: Callable) -> void:
	_raise_anchor = raise_anchor
	_select_difficulty = select_difficulty
	_bind_nodes()
	refresh()


## Whether the soul half is wired at all. A screen with no seam names it rather than
## painting zeros a player would read as "a soul at nothing".
func can_read_soul() -> bool:
	return _read_soul.is_valid()


## Whether the save half is wired. Separate from [method can_read_soul] because the
## two seams are filled by the same arm and a partial bind is a real state.
func can_read_save() -> bool:
	return _read_save.is_valid()


## Whether an anchor can be raised from here right now.
func can_raise_anchor() -> bool:
	return _actor != null and _raise_anchor.is_valid()


## Whether a difficulty can be selected from here right now.
func can_select_difficulty() -> bool:
	return _actor != null and _select_difficulty.is_valid()


## Raise `anchor_id` where this hero stands: press a row's button, and this is what
## happens. Returns the module's verdict verbatim, and paints the row with the
## module's OWN reason — never prose this screen composed about it.
func act_raise_anchor(anchor_id: StringName) -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _settle_raise(_refuse(NO_ACTOR), anchor_id)
	if not _raise_anchor.is_valid():
		return _settle_raise(_refuse(NO_ANCHOR_SEAM), anchor_id)
	var outcome := _raise_anchor.call(anchor_id) as Dictionary
	return _settle_raise(outcome, anchor_id)


## Select `difficulty_id` for this run: press a preset's button, and this is what
## happens. Returns the facade's verdict verbatim, then repaints from the facade —
## so what the player sees afterwards is the module's state and not this screen's
## memory of what it asked for.
func act_select_difficulty(difficulty_id: StringName) -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _settle_select(_refuse(NO_ACTOR))
	if not _select_difficulty.is_valid():
		return _settle_select(_refuse(NO_DIFFICULTY_SEAM))
	var outcome := _select_difficulty.call(difficulty_id) as Dictionary
	_settle_select(outcome)
	return _last_select.duplicate(true)


## The verdict of the last raise, or `{}`. A report, never a selection.
func last_raise() -> Dictionary:
	return _last_raise.duplicate(true)


## The verdict of the last selection, or `{}`.
func last_select() -> Dictionary:
	return _last_select.duplicate(true)


## The preset ids on the page, in display order. A report, not a menu: `select` is
## the only write and it is the module's.
func preset_ids() -> Array:
	var out: Array = []
	for row in _preset_rows:
		var id := String((row as DifficultyPresetRow).difficulty_id())
		if not id.is_empty():
			out.append(id)
	return out


## The anchor ids on the page, in display order.
func anchor_ids() -> Array:
	var out: Array = []
	for row in _anchor_rows:
		var id := String((row as AnchorConstructionRow).anchor_id())
		if not id.is_empty():
			out.append(id)
	return out


func _summary() -> Dictionary:
	_bind_nodes()
	# `{}` with no actor is the contract every screen here keeps: there is no soul,
	# no difficulty and no save belonging to nobody.
	if _actor == null:
		return {}
	var presets := _row_summaries(_preset_rows)
	var anchors := _row_summaries(_anchor_rows)
	return {
		"actor": String(_actor.id),
		# The soul's own read model, as the facade published it. Nested verbatim so a
		# caller can compare it against `SoulApi.summary` key for key.
		"soul": _soul_state(),
		"difficulty_id": String(DifficultyApi.current_id(_actor)),
		"scalars": DifficultyApi.scalars(_actor),
		"difficulty_seam": can_select_difficulty(),
		"anchor_seam": can_raise_anchor(),
		"soul_seam": can_read_soul(),
		"save_seam": can_read_save(),
		# The last death, read out of the same envelope as the soul. Published here
		# as well as on the panel so a caller can assert what a death did without
		# walking to a child, beside the soul figures it moved.
		"last_death": _death_state(),
		"last_raise_reason": String(_last_raise.get("reason", "")),
		"last_raise_ok": bool(_last_raise.get("ok", false)),
		"last_select_reason": String(_last_select.get("reason", "")),
		"last_select_ok": bool(_last_select.get("ok", false)),
		# Child summaries nested under the child's own key, per the screen contract.
		"ledger": _ledger.summary() if _ledger != null else {},
		"portrait": _portrait.summary() if _portrait != null else {},
		"presets": presets,
		"preset_ids": _ids_of(presets),
		"selected_preset_ids": _ids_where(presets, "selected"),
		"selectable_preset_ids": _ids_where(presets, "can_select"),
		"anchors": anchors,
		"anchor_ids": _ids_of(anchors),
		"raised_anchor_ids": _ids_where(anchors, "raised"),
		# The five save figures are read here rather than only on the panel, so a
		# caller can assert the condition without walking to a child. There is no
		# restore verb anywhere in that block, by construction.
		"save": _save_state(),
	}


# --- Reading ---------------------------------------------------------------


## What the root's soul bridge hands over: the soul and the death it caused in ONE
## envelope. `{}` when unwired, so a caller reads "nothing is wired" rather than a
## soul at zero integrity.
func _soul_envelope() -> Dictionary:
	if _actor == null or not _read_soul.is_valid():
		return {}
	var view = _read_soul.call()
	return view as Dictionary if view is Dictionary else {}


## The soul's OWN numbers, key for key with `SoulApi.soul`, which is what
## [method _summary] publishes under `"soul"` and what the panel's figures are read
## from.
##
## ## Why this unwraps `soul` instead of handing the envelope down
##
## The bridge answers two questions in one dictionary (`{"soul", "last_death"}`), so
## a screen that passed the ENVELOPE where a soul was expected read `integrity_max`
## off a dictionary that does not hold it. Every figure came back zero, the panel
## printed "Integrity is not measured." with a soul standing right there, and
## `"soul"` nested a soul under `"soul"` so a caller comparing it key for key
## against `SoulApi.soul` compared a shape against a different shape.
func _soul_state() -> Dictionary:
	return _sub_state(_soul_envelope(), "soul")


## The last resolved death, beside the soul in that same envelope. `{}` before
## anything has fallen — which is the state the panel's own "has never fallen" line
## is for, so an unwired half is distinguishable from an untouched one.
func _death_state() -> Dictionary:
	return _sub_state(_soul_envelope(), "last_death")


## One key of the envelope, as a dictionary. `{}` for a missing key or a
## non-dictionary value, never a typed cast that would raise.
func _sub_state(envelope: Dictionary, key: String) -> Dictionary:
	var value: Variant = envelope.get(key, {})
	return value as Dictionary if value is Dictionary else {}


## The save's condition, through the seam. `SaveApi.summary` publishes the figures
## and names no slot a caller could load; this screen keeps that verbatim and adds
## nothing, which is what ADR 0128 asks of its one player-facing surface.
func _save_state() -> Dictionary:
	if not _read_save.is_valid():
		return {}
	var view = _read_save.call()
	return view as Dictionary if view is Dictionary else {}


## The soul ledger the module publishes for this actor, enriched with the gate's
## own verdict and the anchored repairs. Read through the same seam as [method
## _soul_state], so nothing here reaches a module the UI is not granted.
func _ledger_state() -> Dictionary:
	var state := _soul_state().duplicate(true)
	if state.is_empty():
		return state
	state["shelters"] = AnchorApi.shelters(_actor)
	return state


# --- Plumbing ---------------------------------------------------------------


func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	_fill_presets()
	_fill_anchors()
	if _ledger != null:
		_ledger.show_soul(_ledger_state(), _death_state())
		_ledger.show_save(_save_state())
	_paint_portrait()


func _render() -> void:
	if _header == null:
		return
	if _actor == null:
		_header.text = L.t(NO_ACTOR_TEXT)
		_footer.text = ""
		return
	_header.text = L.t(HEADER_TEXT)
	_footer.text = L.t(FOOTER_TEXT)


## Resolved lazily, never in `@onready`: the headless runner drives every screen
## from `SceneTree._initialize()`, where `_ready()` is never delivered and a panel
## bound there is never bound at all. Idempotent, and every connect guarded —
## an unguarded one is one handler per press, so a re-bound screen would fire the
## same verb N times.
func _bind_nodes() -> void:
	if _bound:
		return
	_header = get_node_or_null("%SoulHeader") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_ledger = get_node_or_null("%SoulLedgerPanel") as SoulLedgerPanel
	_portrait = get_node_or_null("%PortraitPanel") as PortraitPanel
	_preset_box = get_node_or_null("Layout/Scroll/Page/Difficulty/Presets") as VBoxContainer
	_anchor_box = get_node_or_null("Layout/Scroll/Page/Hearth/Anchors") as VBoxContainer
	_bound = (_header != null and _footer != null and _preset_box != null and _anchor_box != null)
	if not _bound:
		return
	_preset_rows = _rows_in(_preset_box, PRESET_SCENE, PRESET_PREFIX, PRESET_SPARE_ROWS)
	_anchor_rows = _rows_in(_anchor_box, ANCHOR_SCENE, ANCHOR_PREFIX, ANCHOR_SPARE_ROWS)
	for row in _preset_rows:
		var signal_ref: Signal = row.get(&"select_requested")
		if not signal_ref.is_connected(act_select_difficulty):
			signal_ref.connect(act_select_difficulty)
	for row in _anchor_rows:
		var signal_ref: Signal = row.get(&"raise_requested")
		if not signal_ref.is_connected(act_raise_anchor):
			signal_ref.connect(act_raise_anchor)


# --- ScreenStack hooks ------------------------------------------------------


## The landing spot is the first control a player can act on: the first preset that
## is not the live one, and failing that the first anchor row. Recorded first,
## because a node outside a viewport has nothing to focus yet, and never
## `grab_focus()`ed from `_ready()`.
func focus_initial() -> void:
	_bind_nodes()
	var target := _first_selectable(_preset_rows)
	if target == null:
		target = _first_filled(_anchor_rows)
	if target == null:
		return
	_focus_target = String(target.name)
	if target.is_inside_tree():
		target.call(&"focus_initial")


## Nothing here is consumed, so `ui_cancel` stays free for `ScreenStack` to pop,
## exactly as it pops every other screen. A screen that could commit a difficulty
## and also swallowed the cancel would trap a player inside it.
func on_stack_input(_event: InputEvent) -> bool:
	return false


func on_screen_hidden() -> void:
	pass


# --- Filling ----------------------------------------------------------------


## One row per authored preset, marked with the one this run is under. The preset
## list is `DifficultyApi.views()` verbatim: an authored table keyed by a stable id
## (ADR 0129), so a screen that sorted it by a scalar would put an inserted preset
## on the wrong row.
func _fill_presets() -> void:
	var current := String(DifficultyApi.current_id(_actor))
	var views: Array = []
	for view in DifficultyApi.views():
		var row: Dictionary = (view as Dictionary).duplicate(true)
		row["selected"] = String(row.get("difficulty_id", "")) == current
		views.append(row)
	_feed(_preset_box, _preset_rows, PRESET_SCENE, PRESET_PREFIX, views)


## One row per authored anchor, with the authored cost attached. `cost_of` is asked
## of the facade so the price on the page is the price `raise_anchor` gates on, and
## so a retuned def never has to be re-typed into a panel.
func _fill_anchors() -> void:
	var views: Array = []
	for row in AnchorApi.summary(_actor).get("anchors", []) as Array:
		var view: Dictionary = (row as Dictionary).duplicate(true)
		var anchor_id := StringName(String(view.get("id", "")))
		view["cost"] = AnchorApi.cost_of(anchor_id)
		view["seam"] = can_raise_anchor()
		views.append(view)
	_feed(_anchor_box, _anchor_rows, ANCHOR_SCENE, ANCHOR_PREFIX, views)


## Push the data into the pool, one row per view, clearing any spare. A blank row
## would read as an authored preset or an authored anchor that the player cannot
## see, which is the dead-content failure in its purest form.
func _feed(
	box: VBoxContainer, rows: Array, scene_path: String, prefix: String, views: Array
) -> void:
	_grow(box, rows, scene_path, prefix, views.size())
	var index := 0
	while index < rows.size():
		var view: Dictionary = {}
		if index < views.size():
			view = (views[index] as Dictionary).duplicate(true)
		var row: Variant = rows[index]
		if row is DifficultyPresetRow:
			(row as DifficultyPresetRow).show_preset(view)
		elif row is AnchorConstructionRow:
			(row as AnchorConstructionRow).show_anchor(view)
		index += 1


## Grow the pool to fit the data, so the page scrolls rather than truncates.
##
## The bound is `RowBudget.cap(needed)`, taken BEFORE the loop and never re-read
## inside it: `needed` is a data-derived count and nothing here grows `views`, so
## the loop has a fixed ceiling rather than a condition that could chase itself.
## Each row is instantiated ONCE here and kept for the life of the screen — a row
## built per repaint would accumulate a fresh subtree every refresh, which is the
## leak shape `ScreenStack.pop()` exists to avoid.
func _grow(
	box: VBoxContainer, rows: Array, scene_path: String, prefix: String, needed: int
) -> void:
	var target := RowBudget.cap(needed)
	while rows.size() < target:
		var grown := load(scene_path).instantiate() as Control
		grown.name = "%s%d" % [prefix, rows.size()]
		box.add_child(grown)
		rows.append(grown)


# --- Reporting --------------------------------------------------------------


## The rows the scene declares, then enough more to reach `extra`. Every row this
## screen adds is a live `Control` parented into the tree, so the count is clamped
## through `RowBudget` before the loop and the rows are created ONCE here — never
## per repaint, which is the accumulation that leaks a screen subtree per refresh.
func _rows_in(box: VBoxContainer, scene_path: String, prefix: String, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as Control
		if row != null:
			out.append(row)
	for index in range(out.size(), maxi(out.size(), RowBudget.cap(extra))):
		var grown := load(scene_path).instantiate() as Control
		grown.name = "%s%d" % [prefix, index]
		box.add_child(grown)
		out.append(grown)
	return out


func _row_summaries(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		if row == null:
			continue
		var view: Dictionary = row.call(&"summary") as Dictionary
		if not view.is_empty():
			out.append(view)
	return out


func _ids_of(views: Array) -> Array:
	var out: Array = []
	for entry in views:
		out.append(
			String((entry as Dictionary).get("id", (entry as Dictionary).get("difficulty_id", "")))
		)
	return out


func _ids_where(views: Array, key: String) -> Array:
	var out: Array = []
	for entry in views:
		var view: Dictionary = entry
		if bool(view.get(key, false)):
			out.append(String(view.get("id", view.get("difficulty_id", ""))))
	return out


func _first_selectable(rows: Array) -> Node:
	for row in rows:
		if row == null or not row.has_method(&"can_select"):
			continue
		if bool(row.call(&"can_select")):
			return row
	return null


func _first_filled(rows: Array) -> Node:
	for row in rows:
		if row != null and row.has_method(&"is_filled") and bool(row.call(&"is_filled")):
			return row
	return null


## The portrait the resolver gives this actor. `core/` is a layer a screen may
## reach, and ADR 0131 says the resolver takes the race id as a PARAMETER precisely
## so `core/` never names a module — so this screen reads the race through
## `RaceApi` (declared in `rules.UI_MODULES`) and asks the resolver for the rest.
func _paint_portrait() -> void:
	if _portrait == null:
		return
	if _actor == null:
		_portrait.show_portrait({})
		return
	_portrait.show_portrait(PortraitResolver.resolve(_actor, RaceApi.race_of(_actor)))


# --- Verdicts ---------------------------------------------------------------


## A refusal this screen raises ITSELF, in the modules' own `{ok, reason}` shape.
## Never a silent no-op: an action a player asked for that did not happen is
## reported in the same vocabulary a module refusal uses.
func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


## Record a raise's verdict, paint it on its own row, and repaint from the facade.
##
## The reason is applied to the row AFTER the facade has been re-read, because the
## facade has no memory of a refusal — so a row showing only the ledger would erase
## the answer the player is still reading.
##
## ## Why the row is chosen from `asked`, not from the verdict's own `anchor_id`
##
## The module refuses with `"anchor_id": ""` — its `_refuse` publishes the id slot
## empty for every refusal that never reached the ledger. So a refusal read its id
## back off its own verdict, found nothing, and painted itself on NO row: the player
## pressed a button, was told `already_raised`, and the row they pressed went on
## reading "Ready to raise where you stand." `asked` is what the caller actually
## asked for, and the refusal belongs on that row. The module's own id wins when it
## carries one, so a future success naming a different row still lands correctly.
func _settle_raise(result: Dictionary, asked: StringName = &"") -> Dictionary:
	_bind_nodes()
	_last_raise = (result as Dictionary).duplicate(true)
	var reason := String(_last_raise.get("reason", ""))
	set_message(reason, TONE_OK if bool(_last_raise.get("ok", false)) else TONE_ERROR)
	refresh()
	var named := String(_last_raise.get("anchor_id", ""))
	if named.is_empty():
		named = String(asked)
	for row in _anchor_rows:
		if row == null:
			continue
		if String((row as AnchorConstructionRow).anchor_id()) == named:
			(row as AnchorConstructionRow).show_refusal(reason)
	return _last_raise.duplicate(true)


## Record a selection's verdict and repaint. The repaint re-reads
## `DifficultyApi.current_id`, so the row marked live is the module's answer and not
## this screen's memory of the id it asked for.
func _settle_select(result: Dictionary) -> Dictionary:
	_bind_nodes()
	_last_select = (result as Dictionary).duplicate(true)
	set_message(
		String(_last_select.get("reason", "")),
		TONE_OK if bool(_last_select.get("ok", false)) else TONE_ERROR
	)
	refresh()
	return _last_select.duplicate(true)
