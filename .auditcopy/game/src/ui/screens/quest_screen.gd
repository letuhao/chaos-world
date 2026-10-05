class_name QuestScreen
extends UiScreen

## The quest journal: what the world is offering, what this hero is already
## running, and what has been finished. Every row is a read of `QuestApi` and
## nothing else.
##
## ## The gap this screen closes
##
## `QuestApi` shipped twelve verbs, 476 green assertions and **no caller in
## `game/src/`** — BL-0663. `QuestBeatHandler` asks "does an ACTIVE quest watch
## this fact?", the active set was always empty, so the beat pipeline burnt a
## period every two minutes into a ledger nobody read and
## `QuestGrants.pay -> DestinyApi.earn_fate(actor, id, "quest:<id>")` was dead
## code (BL-0664). A quest was never anything a player could SEE, ACCEPT or
## PROGRESS. This screen is the whole of that.
##
## ## The read model is the module's, not this file's
##
## `offered`, `active`, `steps`, `gates_for` and `summary` are all reads. A step
## is satisfied by a fact in the shared `WorldFact` ledger and **this screen
## counts nothing itself** — there is no progress counter here to drift from the
## world's memory (ADR 0113). `kind` decides only whether a quest is OFFERED:
## `offered` publishes `authored` quests only, and `systemic` / `emergent`
## quests are still accepted, advanced and completed, they are simply not things
## an NPC puts in front of you (BL-0053).
##
## ## The accept seam is a bridge of Callables, never a facade call
##
## `ui/` may reach a module only through that module's `api.gd`, and only if the
## dependency is registered in `rules.UI_MODULES` — which now names `quest`. It
## may never reference `app/` (`PRIVATE_UNITS`), so this screen cannot name
## `QuestProgram`. The composition root injects `bind_quests(accept)` — the ADR
## 0143 shape, the same one `LootBridge` and `WorldPulseBridge` use — and
## [method act_accept] is a REQUEST through it.
##
## ## Nothing is accepted at mount
##
## A poller that takes quests on for the player is not a player action, and
## `QuestApi.accept` is the once-guard for a commitment. A quest is taken on
## because a player pressed the row's button.
##
## Contract: `summary()` is the testable surface, primitives only, each row's own
## summary nested under `rows`, and `{}` when nothing has been committed.

const ROW_SCENE := "res://src/ui/panels/quest_row.tscn"
## Rows the pool starts at. The catalog ships nine authored quests; the pool
## grows through `RowBudget` if an author adds more.
const BASE_ROWS := 6
## The extra rows the pool is allowed to build when the catalog grows.
const MAX_EXTRA_ROWS := 9
const ROW_PREFIX := "QuestRow"
## One line, and the whole of this screen's argument.
const HEADER_TEXT := "What the world is offering, and what you are carrying."
const OFFERED_TITLE := "Offered"
const ACTIVE_TITLE := "In flight"
const DONE_TITLE := "Finished"
const NONE_TEXT := "Nothing here yet. The world has not offered you anything."
const ACCEPT_OK := "Quest taken on. Its steps read from the world's memory."
const COMMIT_OK := "quest_accepted"

## The three states a row can be in. Published here because the row asks the
## screen which one it is rather than carrying a vocabulary of its own.
const ROW_STATE_OFFERED := "offered"
const ROW_STATE_ACTIVE := "active"
const ROW_STATE_DONE := "done"

var _header: Label = null
var _offered_title: Label = null
var _active_title: Label = null
var _done_title: Label = null
var _empty_label: Label = null
var _footer: Label = null
var _offered_box: VBoxContainer = null
var _active_box: VBoxContainer = null
var _done_box: VBoxContainer = null
var _offered_rows: Array = []
var _active_rows: Array = []
var _done_rows: Array = []
var _bound: bool = false
## The ONE commit verb. A `Callable` the composition root injects, called as
## `accept(quest_id) -> Dictionary` and answering the module's own verdict
## (`{ok, reason, unmet, quest_id, source}`) verbatim. Unwired, the screen
## refuses `no_quest_seam` rather than quietly doing nothing.
var _accept_requested: Callable = Callable()
## The last commit's verdict, carried through verbatim from the program. A
## report, never a selection: `accept` is the once-guard, so this screen never
## decides anything about whether a quest may be taken on.
var _result: Dictionary = {}


func _ready() -> void:
	_bind_nodes()
	_refresh_view()
	_render()


## Hand the screen the one verb that commits. `accept` is called as
## `accept(quest_id) -> Dictionary`; a refusal carries its reason through
## untouched, so this screen renders the module's answer rather than an opinion
## of its own.
func bind_quests(accept: Callable) -> void:
	_accept_requested = accept
	_bind_nodes()
	refresh()


## Whether a player may commit a quest from this screen right now. A bridge
## nobody filled cannot be pressed, so the rows render greyed out rather than
## publishing a button that goes nowhere.
func can_accept() -> bool:
	return _accept_requested.is_valid()


## Take `quest_id` on: press the row's button, and this is what happens.
##
## Delegates the whole commit through the injected seam and never touches a
## module itself. Returns the module's verdict verbatim so a caller never has to
## infer an outcome from this screen's message line.
func act_accept(quest_id: StringName) -> Dictionary:
	_bind_nodes()
	if not _accept_requested.is_valid():
		_result = {"ok": false, "reason": "no_quest_seam", "unmet": []}
		set_message(String(_result["reason"]), TONE_ERROR)
		refresh()
		return _result
	var outcome := _accept_requested.call(quest_id) as Dictionary
	_result = outcome
	if bool(outcome.get("ok", false)):
		set_message(ACCEPT_OK, COMMIT_OK)
	else:
		set_message(String(outcome.get("reason", "")), TONE_ERROR)
	refresh()
	return outcome


## The verdict of the last commit, or `{}`. A report, never a selection.
func last_result() -> Dictionary:
	return _result.duplicate(true)


func _summary() -> Dictionary:
	_bind_nodes()
	# `{}` with no actor is the contract every screen here keeps (ADR 0038): there
	# is no quest state to read until there is a hero whose ledger holds it.
	if _actor == null:
		return {}
	var state := QuestApi.summary(_actor)
	var offered := _offered_views()
	var active := _active_views()
	var done := _done_views()
	var rows := _row_summaries()
	return {
		"actor": String(_actor.id),
		"ledger_available": bool(state.get("ledger_available", false)),
		"offered_ids": _ids_of(offered),
		"active_ids": _ids_of(active),
		"completed_ids": _strings(state.get("completed", [])),
		"offered_count": offered.size(),
		"active_count": active.size(),
		"completed_count": (state.get("completed", []) as Array).size(),
		"accept_seam": can_accept(),
		"last_reason": String(_result.get("reason", "")),
		"rows": rows,
		"row_ids": _ids_of(rows),
		"accepting_ids": _accepting_ids(rows),
	}


## Repaint from the module. Each row repaints itself, and this screen renders
## no number: `QuestRow` owns every `%d/%d`, every tier and every joined list.
##
## PUBLIC, and named `refresh` because three call sites already say so: the
## screen's own `bind_quests` and `act_accept`, and `QuestProgram.bind`. The
## repaint body is `_refresh_view`; this is the name the bridge calls, so it is
## the name that exists. A screen that repaints only under a private name is one
## nobody outside can ask to repaint, which is how a live seam ends up paired
## with stale rows.
func refresh() -> void:
	_refresh_view()


func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	var offered := _offered_views()
	var active := _active_views()
	var done := _done_views()
	_feed(_offered_rows, offered)
	_feed(_active_rows, active)
	_feed(_done_rows, done)
	_offered_title.visible = not offered.is_empty()
	_active_title.visible = not active.is_empty()
	_done_title.visible = not done.is_empty()
	_empty_label.visible = offered.is_empty() and active.is_empty() and done.is_empty()


func _render() -> void:
	if _header == null:
		return
	_header.text = HEADER_TEXT
	_footer.text = _footer_text()


func _footer_text() -> String:
	if not can_accept():
		return "No commit seam is wired, so nothing here can be taken on."
	return "A step is satisfied by what the world has already recorded, never by a counter here."


# --- ScreenStack hooks ------------------------------------------------------


## The landing spot is the first quest still offered to the player — the thing a
## player would act on. Recorded first, because a node outside a viewport has
## nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	for row in _offered_rows:
		if bool(row.call(&"can_accept")):
			_focus_target = String(row.name)
			if row.is_inside_tree():
				row.call(&"focus_initial")
			return
	super()


func on_stack_input(_event: InputEvent) -> bool:
	return false


func on_screen_hidden() -> void:
	pass


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _header != null:
		return
	_header = get_node_or_null("%QuestHeader") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_empty_label = get_node_or_null("%EmptyLabel") as Label
	_offered_title = get_node_or_null("%OfferedTitle") as Label
	_active_title = get_node_or_null("%ActiveTitle") as Label
	_done_title = get_node_or_null("%DoneTitle") as Label
	_offered_box = get_node_or_null("Layout/Scroll/Board/OfferedBox") as VBoxContainer
	_active_box = get_node_or_null("Layout/Scroll/Board/ActiveBox") as VBoxContainer
	_done_box = get_node_or_null("Layout/Scroll/Board/DoneBox") as VBoxContainer
	_bound = _header != null and _offered_box != null and _active_box != null
	if not _bound:
		return
	_offered_rows = _rows_in(_offered_box, MAX_EXTRA_ROWS)
	_active_rows = _rows_in(_active_box, MAX_EXTRA_ROWS)
	_done_rows = _rows_in(_done_box, MAX_EXTRA_ROWS)
	for row in _offered_rows + _active_rows + _done_rows:
		var signal_ref: Signal = row.get(&"accept_requested")
		if not signal_ref.is_connected(_on_accept_requested):
			signal_ref.connect(_on_accept_requested)


## The rows a box declares, then enough more to reach `extra`. The count is
## clamped through `RowBudget` before the loop rather than inside it, because
## `extra` is an authored constant today and a data-derived one is exactly the
## shape the bound exists for.
func _rows_in(box: VBoxContainer, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as QuestRow
		if row != null:
			out.append(row)
	for index in range(out.size(), RowBudget.cap(extra)):
		var grown := load(ROW_SCENE).instantiate() as Control
		grown.name = "%s%d" % [ROW_PREFIX, index]
		box.add_child(grown)
		out.append(grown)
	return out


func _on_accept_requested(quest_id: StringName) -> void:
	act_accept(quest_id)


# --- Filling ----------------------------------------------------------------


## One row per quest, with any spare row in the pool cleared — a blank row would
## read as a quest the player cannot see.
func _feed(rows: Array, views: Array[Dictionary]) -> void:
	var index := 0
	for row in rows:
		var view: Dictionary = {}
		if index < views.size():
			view = (views[index] as Dictionary).duplicate(true)
		(row as QuestRow).show_quest(view)
		index += 1


# --- The read model ---------------------------------------------------------


## Every offered quest, with its gate verdict and its live step tally.
##
## The steps come from `QuestApi.steps`, which reads the shared ledger, and the
## gate from `QuestApi.gates_for`, which hands back the verdict
## `DestinyApi.gate` produced verbatim. Nothing here re-derives either.
func _offered_views() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _actor == null:
		return out
	for view in QuestApi.offered(_actor):
		out.append(_enrich(view))
	return out


## Every quest in flight, with the tally `QuestApi.active` already counted. The
## live step counts come from `_enrich`, which reads them out of the shared ledger
## rather than from the view's authored `steps`.
func _active_views() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _actor == null:
		return out
	for view in QuestApi.active(_actor):
		out.append(_enrich(view))
	return out


## Every finished quest, from `QuestApi.summary`'s own `quests` map. There is no
## facade verb for "completed rows" and the facade is at its twelve-method cap,
## so the one read that already carries the list is the one used here.
func _done_views() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _actor == null:
		return out
	var state := QuestApi.summary(_actor)
	var quests: Dictionary = state.get("quests", {})
	for quest_id in _strings(state.get("completed", [])):
		var view: Dictionary = quests.get(quest_id, {}) as Dictionary
		if view.is_empty():
			continue
		var enriched := _enrich(view)
		enriched["steps"] = QuestApi.steps(_actor, StringName(quest_id))
		out.append(enriched)
	return out


## One facade row plus the two reads a panel needs and the facade does not fold
## into `_quest_view`: the gate verdict and the ledger's own step counts.
func _enrich(view: Dictionary) -> Dictionary:
	var out := view.duplicate(true)
	var quest_id := StringName(String(out.get("id", "")))
	out["steps"] = QuestApi.steps(_actor, quest_id)
	out["steps_total"] = (out["steps"] as Array).size()
	var done := 0
	for step in out["steps"] as Array:
		if bool((step as Dictionary).get("done", false)):
			done += 1
	out["steps_done"] = done
	var gate := QuestApi.gates_for(_actor, quest_id)
	out["gate_ok"] = bool(gate.get("ok", false))
	out["gate_unmet"] = gate.get("unmet", [])
	out["state"] = ROW_STATE_OFFERED
	return out


# --- Reporting --------------------------------------------------------------


func _row_summaries() -> Array:
	var out: Array = []
	for row in _offered_rows + _active_rows + _done_rows:
		var view: Dictionary = (row as QuestRow).summary()
		if not view.is_empty():
			out.append(view)
	return out


func _accepting_ids(rows: Array) -> Array:
	var out: Array = []
	for entry in rows:
		if bool((entry as Dictionary).get("can_accept", false)):
			out.append(String((entry as Dictionary).get("id", "")))
	return out


func _ids_of(views: Array) -> Array:
	var out: Array = []
	for entry in views:
		out.append(String((entry as Dictionary).get("id", "")))
	return out


func _strings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
