class_name DestinyScreen
extends UiScreen

## The fate and destiny codex: what this hero has earned, and what is still out of
## reach. A pure consumer of the `destiny` facade — it renders
## `DestinyApi.summary(actor)` and names nothing else in the module (ADR 0065).
##
## **Read-only by design.** Fate is earned, never chosen and never equipped, so
## this screen publishes no picker, no equip action and no selection: a widget
## that let the player choose a destiny would contradict the one invariant the
## module exists to keep. It therefore mounts a fixed row pool in the scene and
## fills it, and `on_stack_input` consumes nothing, so `ui_cancel` pops the screen
## the way it pops every other read-only one.
##
## ## It listens, so fate earned is never silent
##
## The module announces every earn on `DestinyApi.events()`. Until
## something connected, this codex only learned about a fate when a player
## navigated to it — a stat change with no narrative explanation, and a page
## that was already stale while it was open. So this screen is that
## subscriber: `fate_earned` and `destiny_earned` re-read the facade and
## repaint, and the announcement becomes the screen's own message line.
##
## **Still read-only.** A repaint reads `summary()`; it grants nothing, revokes
## nothing and selects nothing. There is no button anywhere on this surface, and
## a handler that re-reads the codex is the whole of what an earn can make it do.
##
## Contract: `summary()` is the testable surface, with each row's own summary
## nested under `destinies` / `fates`. `{}` with no actor.

## Rows the scene mounts. The pools are grown at runtime rather than truncated:
## a codex that quietly dropped a fate would read as content the hero does not
## have, which is the opposite of what it is for.
const BRANCH_ROWS := 8
const FATE_ROWS := 24
const BRANCH_SCENE := "res://src/ui/panels/destiny_branch_row.tscn"
const FATE_SCENE := "res://src/ui/panels/fate_row.tscn"
var HEADER_TEXT := L.t("LOC_UI_SCREENS_328078C42D")
var NO_ACTOR_TEXT := L.t("LOC_UI_SCREENS_6E9BC19A74")
## The notice shown when fate or destiny is earned. The wording is a constant
## because the screen owns no vocabulary of its own: the NARRATIVE is the row's
## (`FateRow` prints the authored description and meta line, `DestinyBranchRow`
## the authored bearing), and this only says the thing happened.
var FATE_EARNED_NOTICE := L.t("LOC_UI_SCREENS_E8AB972321")
var DESTINY_EARNED_NOTICE := L.t("LOC_UI_SCREENS_43B2043F11")
## An earn the codex cannot attribute to the hero it is rendering. The bus
## carries an `actor_id`, not an `Actor`, so a second hero earning a fate while
## this page is open is a real possibility and is counted rather than painted
## onto the wrong ledger.
var FOREIGN_EARN_NOTE := L.t("LOC_UI_SCREENS_41A5FB5302") + L.t("LOC_UI_SCREENS_9F67364101")

var _codex: Dictionary = {}
var _header: Label = null
var _footer: Label = null
var _branch_box: VBoxContainer = null
var _fate_box: VBoxContainer = null
var _bound: bool = false
var _branch_rows: Array = []
var _fate_rows: Array = []
var _earned_ids: Array = []
var _foreign_earns: int = 0


## Adopt a facade snapshot for the bound actor (`DestinyApi.summary(actor)`
## shaped). `setup(actor)` takes the same path; this exists so a headless test or
## a driver can render the codex with no actor at all. An empty snapshot clears it.
func apply_snapshot(snapshot: Dictionary) -> void:
	_bind_nodes()
	_codex = snapshot.duplicate(true)
	_refresh_view()
	_render()


## The ids the codex is showing, in display order: every held destiny first, then
## the earned fates, then the locked ones. A report, not a menu — there is no
## selection for a caller to make.
func row_ids() -> Array:
	var out: Array = []
	for row in _branch_rows:
		out.append(String((row as DestinyBranchRow).destiny_id()))
	for row in _fate_rows:
		out.append(String((row as FateRow).row_id()))
	return out


## Every entry the screen is holding in its notice line, oldest first.
##
## A report, not a menu, and a REPORT of what has already happened: nothing here
## can be acted on, chosen or dismissed. `{}` with no actor, because the screen
## contract says a screen reports nothing rather than keys when nothing is bound.
##
## The notice carries ids rather than sentences, because the screen formats no
## number and invents no copy — the row that owns an entry is what renders it.
func earned_notices() -> Array:
	_bind_nodes()
	if _actor == null:
		return []
	return _earned_ids.duplicate()


## How many earns this screen heard and ignored because they belonged to a
## different hero — or to no hero at all, which is the same case from here: there
## is no ledger to paint. Reported so the filter is visible rather than silent,
## and asserted by the suite: a codex that silently dropped a notification is the
## failure mode a counter makes testable.
func foreign_earns() -> int:
	_bind_nodes()
	return _foreign_earns


## Drop the notice history. The only thing a caller can do with a notice, and it
## changes no fate: an announcement is a fact that has already happened.
func clear_earned_notices() -> void:
	_bind_nodes()
	_earned_ids.clear()


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var branches := _branch_summaries()
	var fates := _fate_summaries()
	return {
		"actor": String(_actor.id),
		"read_only": true,
		"fate_count": int(_codex.get("fate_count", 0)),
		"destiny_count": int(_codex.get("destiny_count", 0)),
		"hidden_fate_count": int(_codex.get("hidden_fate_count", 0)),
		"hidden_destiny_count": int(_codex.get("hidden_destiny_count", 0)),
		"counters": (_codex.get("counters", {}) as Dictionary).duplicate(),
		"destinies": branches,
		"fates": fates,
		"held_destinies": _ids_of(branches, true),
		"locked_destinies": _ids_of(branches, false),
		"held_fates": _ids_of(fates, true),
		"locked_fates": _ids_of(fates, false),
		"catalog_destinies": _catalog_ids("destinies"),
		"catalog_fates": _catalog_ids("fates"),
		"row_ids": row_ids(),
		# The listener half of the surface, reported the same way as the rest: raw
		# ids, counted, never acted on. `announces` is what proves the codex is
		# subscribed to the bus rather than only re-reading on navigation.
		"earned_notices": earned_notices(),
		"earned_notice_count": _earned_ids.size(),
		"foreign_earns": _foreign_earns,
		# Fate choice at earn time (ADR 0389). The choice is a UI presentation of
		# implicit eligibility: when multiple fates in a choice group are eligible,
		# the UI presents them as a choice. The backend resolves it through existing
		# earn logic.
		"choice_groups": _choice_groups(),
	}


## The fate choice groups for this actor (ADR 0389). A choice group is a set of
## fates that can be offered together when one of their triggers fires. The UI
## presents the choice when multiple fates in the group are eligible.
##
## Returns a dictionary mapping each fate id in a choice group to the list of
## eligible fates in that group. Only groups with multiple eligible fates are
## included.
func _choice_groups() -> Dictionary:
	var out := {}
	if _actor == null:
		return out
	var fates: Dictionary = _codex.get("fates", {})
	for fate_id in fates.keys():
		var view: Dictionary = fates[fate_id]
		var choices: Array = view.get("eligible_choices", [])
		if choices.is_empty():
			continue
		var eligible: Array = DestinyApi.eligible_choices(_actor, StringName(fate_id))
		if eligible.size() > 1:
			var names: Array = []
			for c in eligible:
				names.append(String(c))
			out[String(fate_id)] = names
	return out


## Re-read the facade and hand raw values down. The rows own every format.
func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	var live := DestinyApi.summary(_actor) if _actor != null else {}
	if not live.is_empty():
		_codex = live
	_fill_branches()
	_fill_fates()


## Repaint this screen's own labels. Each row repaints itself.
func _render() -> void:
	if _header == null:
		return
	_header.text = L.t(HEADER_TEXT if _actor != null else NO_ACTOR_TEXT)
	_footer.text = L.t("LOC_UI_SCREENS_D42CA15044")


# --- Hearing the bus ---------------------------------------------------------
##
## ADR 0065 makes fate earned and never choosable, so the whole of what an earn
## may make this screen do is **show that it happened**: re-read the facade,
## repaint, and say so. Both handlers are that and nothing else — no earn call,
## no selection, no state a player could change. The notice is appended rather
## than REPLACED so two fates earned in the same beat (a destiny carries its own
## `grants_fates`) are both reported instead of one overwriting the other.
##
## `source` is accepted and deliberately unused: it names the system that earned
## the fate, which is for a log or an audio cue, and this screen formats nothing.
func _on_fate_earned(actor_id: String, fate_id: StringName, _source: String) -> void:
	_record_announcement(actor_id, &"fate", fate_id)


## The destiny half, identical in kind. Separate only because the bus declares
## it separately, and a subscriber that cared about the difference would be
## filtering on `kind` rather than branching in two functions.
func _on_destiny_earned(actor_id: String, destiny_id: StringName, _source: String) -> void:
	_record_announcement(actor_id, &"destiny", destiny_id)


## Repaint if the announcement is this screen's hero's, and say so if it is not.
##
## The bus carries an `actor_id` STRING rather than an `Actor` (ADR 0136), so a
## subscriber holding a stale reference cannot detect the swap by itself. With no
## hero bound there is no ledger to paint, so the earn is dropped either way —
## a codex mounted with no actor must not grow a notice it cannot render.
func _record_announcement(actor_id: String, kind: StringName, entry_id: StringName) -> void:
	_bind_nodes()
	if _actor == null or String(_actor.id) != actor_id:
		_foreign_earns += 1
		return
	_earned_ids.append({"kind": String(kind), "id": String(entry_id), "actor": actor_id})
	# The facade is the only truth, and it has already been written by the time
	# this fires — so the repaint costs one `summary()` call and cannot disagree
	# with the ledger it is reporting.
	refresh()
	set_message(FATE_EARNED_NOTICE if kind == &"fate" else DESTINY_EARNED_NOTICE, TONE_OK)


# --- ScreenStack hooks ------------------------------------------------------


## Nothing here is pressable, so the landing spot is the first held destiny —
## the thing the codex is read for — and failing that the first fate. Recorded
## first, because a node outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	var target: Node = _first_filled(_branch_rows)
	if target == null:
		target = _first_filled(_fate_rows)
	if target == null:
		return
	_focus_target = String(target.name)
	if target.is_inside_tree():
		target.call(&"focus_initial")


## Nothing here is actionable, so nothing is consumed: `ui_cancel` stays free for
## `ScreenStack` to pop, exactly as on every other read-only screen.
func on_stack_input(_event: InputEvent) -> bool:
	return false


func on_screen_hidden() -> void:
	pass


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _header != null:
		return
	_header = get_node_or_null("%CodexHeader") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_branch_box = get_node_or_null("Layout/Scroll/Codex/Destinies") as VBoxContainer
	_fate_box = get_node_or_null("Layout/Scroll/Codex/Fates") as VBoxContainer
	_bound = _header != null and _branch_box != null and _fate_box != null
	if not _bound:
		return
	_branch_rows = _rows_in(_branch_box, BRANCH_SCENE, "Branch", BRANCH_ROWS)
	# One row past the mounted pool: the heading between earned and locked.
	_fate_rows = _rows_in(_fate_box, FATE_SCENE, "Fate", FATE_ROWS + 1)
	_connect_events()


## Subscribe to the two earn announcements, guarded so binding twice is not a
## second handler per earn.
##
## `_bind_nodes()` is idempotent and returns early once `_header` is bound, so
## the guard is what makes "one handler per connection" a fact rather than an
## accident of the early return — the moment anything calls this a second time,
## an unguarded connect would duplicate silently. `counter_changed` and
## `gate_failed` are deliberately NOT connected: ADR 0136 records `gate_failed`
## as telemetry that fires once per EVALUATION, so a consumer that rendered it
## would spam, and a counter move is not a narrative event worth interrupting for.
func _connect_events() -> void:
	var events := DestinyApi.events()
	if not events.fate_earned.is_connected(_on_fate_earned):
		events.fate_earned.connect(_on_fate_earned)
	if not events.destiny_earned.is_connected(_on_destiny_earned):
		events.destiny_earned.connect(_on_destiny_earned)


## The rows the scene declares, in order, then the ones grown at runtime.
func _rows_in(box: VBoxContainer, scene_path: String, prefix: String, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as DestinyBranchRow
		if row != null:
			out.append(row)
			continue
		var fate := child as FateRow
		if fate != null:
			out.append(fate)
	for index in range(extra):
		var row := load(scene_path).instantiate() as Control
		row.name = "%s%d" % [prefix, out.size()]
		box.add_child(row)
		out.append(row)
	return out


func _first_filled(rows: Array) -> Node:
	for row in rows:
		if row.has_method(&"is_filled") and bool(row.call(&"is_filled")):
			return row
	return null


# --- Filling ----------------------------------------------------------------


## The destinies this hero carries, earned ones first: a held destiny is the
## narrative payoff and belongs at the top of the page.
func _fill_branches() -> void:
	var views := _ordered_views("destinies")
	_grow(_branch_box, _branch_rows, BRANCH_SCENE, "Branch", views.size())
	var index := 0
	while index < _branch_rows.size():
		var row: DestinyBranchRow = _branch_rows[index]
		row.show_destiny(views[index] as Dictionary if index < views.size() else {})
		index += 1


## The earned fates first, then a heading, then everything still locked. A fate
## earned is a fact and a fate unearned is a promise the game has already made, so
## the list says which is which rather than sorting them into one flat run.
func _fill_fates() -> void:
	var views := _ordered_views("fates")
	var locked := _locked_count(views)
	# Earned, heading, locked — the heading occupies one row of its own.
	_grow(_fate_box, _fate_rows, FATE_SCENE, "Fate", views.size() + 1)
	var index := 0
	while index < views.size() and bool((views[index] as Dictionary).get("held", false)):
		(_fate_rows[index] as FateRow).show_fate(views[index])
		index += 1
	var heading := index
	if heading < _fate_rows.size():
		# The heading is only worth a row when there is something locked below it.
		if locked > 0:
			(_fate_rows[heading] as FateRow).show_section(locked)
			heading += 1
		else:
			(_fate_rows[heading] as FateRow).show_fate({})
	while heading < _fate_rows.size():
		var row: FateRow = _fate_rows[heading]
		row.show_fate(views[heading] as Dictionary if heading < views.size() else {})
		heading += 1


## Grow the mounted pool to fit the data, so the codex scrolls rather than
## truncates. A row the scene already mounted is reused; only a shortage is
## filled from the row scene.
func _grow(
	box: VBoxContainer, rows: Array, scene_path: String, prefix: String, needed: int
) -> void:
	# `needed` comes from the data, so it is bounded rather than trusted: a pool
	# that grows to fit an unbounded count is the shape that reaches tens of
	# gigabytes of live Controls. See RowBudget.
	var target := RowBudget.cap(needed)
	while rows.size() < target:
		var row := load(scene_path).instantiate() as Control
		row.name = "%s%d" % [prefix, rows.size()]
		box.add_child(row)
		rows.append(row)


## Catalog order, which the facade already sorts, so two runs agree. Only `held`
## reorders: an earned entry leads, and everything else keeps its authored
## position so the locked list stays stable as the hero earns more.
func _ordered_views(key: String) -> Array:
	var catalog: Dictionary = _codex.get(key, {})
	var out: Array = []
	for entry_id in catalog.keys():
		if bool((catalog[entry_id] as Dictionary).get("held", false)):
			out.append(catalog[entry_id])
	for entry_id in catalog.keys():
		if not bool((catalog[entry_id] as Dictionary).get("held", false)):
			out.append(catalog[entry_id])
	return out


func _locked_count(views: Array) -> int:
	var total := 0
	for view in views:
		if not bool((view as Dictionary).get("held", false)):
			total += 1
	return total


# --- Reporting --------------------------------------------------------------


func _branch_summaries() -> Array:
	var out: Array = []
	for row in _branch_rows:
		var view: Dictionary = (row as DestinyBranchRow).summary()
		if not view.is_empty():
			out.append(view)
	return out


func _fate_summaries() -> Array:
	var out: Array = []
	for row in _fate_rows:
		var view: Dictionary = (row as FateRow).summary()
		if not view.is_empty() and bool(view.get("entry", false)):
			out.append(view)
	return out


func _ids_of(views: Array, want_held: bool) -> Array:
	var out: Array = []
	for entry in views:
		var view: Dictionary = entry
		if bool(view.get("held", false)) == want_held:
			out.append(String(view.get("id", "")))
	return out


func _catalog_ids(key: String) -> Array:
	var out: Array = []
	for entry_id in (_codex.get(key, {}) as Dictionary).keys():
		out.append(String(entry_id))
	out.sort()
	return out
