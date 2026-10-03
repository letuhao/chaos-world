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
## Contract: `summary()` is the testable surface, with each row's own summary
## nested under `destinies` / `fates`. `{}` with no actor.

## Rows the scene mounts. The pools are grown at runtime rather than truncated:
## a codex that quietly dropped a fate would read as content the hero does not
## have, which is the opposite of what it is for.
const BRANCH_ROWS := 8
const FATE_ROWS := 24
const BRANCH_SCENE := "res://src/ui/panels/destiny_branch_row.tscn"
const FATE_SCENE := "res://src/ui/panels/fate_row.tscn"
const HEADER_TEXT := "Earned, never chosen. Fate and destiny are owed for good."
const NO_ACTOR_TEXT := "No hero bound."

var _codex: Dictionary = {}
var _header: Label = null
var _footer: Label = null
var _branch_box: VBoxContainer = null
var _fate_box: VBoxContainer = null
var _bound: bool = false
var _branch_rows: Array = []
var _fate_rows: Array = []


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
	}


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
	_header.text = HEADER_TEXT if _actor != null else NO_ACTOR_TEXT
	_footer.text = "Read-only: nothing here is chosen, equipped or given up."


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
	while rows.size() < needed:
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
