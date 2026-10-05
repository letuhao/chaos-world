class_name NationScreen
extends UiScreen

## The nation a hero lives under: the board of offices, the claims over places, the
## stances and the standoffs. A pure consumer of the `nation` facade — it renders the
## facade's `summary(actor)` read model and names NOTHING else in the module
## (ADR 0083/0085).
##
## ## The board is the screen, and a vacancy is a seat
##
## This screen exists to make one fact legible: **a polity outlives the people who
## hold its offices, and an unfilled office is a live, visible row rather than a
## zero, a dash, or a gap.** So every AUTHORED office is always present — `vacant`
## seats render in their own card and their own tone, and the spare rows the scene
## mounts beyond the authored board render `{}` and hide themselves.
##
## The distinction the whole succession design rests on is therefore a **structural**
## one, not a styling preference: a vacant office answers `is_filled() == true`,
## carries `vacant: true`, and reports a `holder_line` of `"Vacant"`; a spare pool
## row renders `{}` from `summary()` and answers `is_filled() == false`. There is no
## third way for a row to be neither, so the two cannot drift into looking alike.
##
## **Read-only by design.** This screen publishes no claim, no declare and no
## resolve. Every mutating nation verb is a political act that opens a standoff, and
## a button that fired one from a screen would make a declaration a two-click
## accident. It therefore mounts fixed row pools and fills them, and
## `on_stack_input` consumes nothing so `ui_cancel` pops it like every other
## read-only screen.
##
## ## The three-state vocabulary, end to end
##
##   - `{}` — a spare pool row, or a territory nobody claims. Hidden.
##   - `"vacant": true` — an authored seat nobody holds. **Visible**, its own tone.
##   - `{"ok": false, "reason": R}` — a refused action. Renders `R`, never prose.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` with no
## actor, and each child's own summary nested under that child's key.

## Rows the scene mounts. The pools GROW at runtime rather than truncating: a board
## that quietly dropped a seat would read as a polity with fewer offices than it
## actually authors, which is the exact legibility failure this screen exists to
## prevent.
const OFFICE_ROWS := 8
const CLAIM_ROWS := 8
const STANCE_ROWS := 8
const STANDOFF_ROWS := 6
const OFFICE_SCENE := "res://src/ui/panels/nation_office_row.tscn"
const CLAIM_SCENE := "res://src/ui/panels/nation_territory_row.tscn"
const STANCE_SCENE := "res://src/ui/panels/nation_stance_row.tscn"
const STANDOFF_SCENE := "res://src/ui/panels/nation_standoff_row.tscn"
const HEADER_TEXT := "The polity whose law you live under, and who holds its seats."
const NO_ACTOR_TEXT := "No hero bound."
const FOUNDED_PREFIX := "Under"
const UNFOUNDED_TEXT := "You live under no nation."
const FOOTER_TEXT := (
	"Read-only: a claim, a war and a prize are declared elsewhere. An unfilled seat" + " is a seat."
)

var _board: Dictionary = {}
var _header: Label = null
var _footer: Label = null
var _office_box: VBoxContainer = null
var _claim_box: VBoxContainer = null
var _stance_box: VBoxContainer = null
var _standoff_box: VBoxContainer = null
var _bound: bool = false
var _office_rows: Array = []
var _claim_rows: Array = []
var _stance_rows: Array = []
var _standoff_rows: Array = []


## Adopt a facade snapshot for the bound actor (the `summary(actor)` shape).
## `setup(actor)` takes the facade path inside `_refresh_view`; this exists so a
## headless test or a driver can render a board from a snapshot with no actor at all,
## and — importantly — so adopting a snapshot does NOT re-enter the facade. An empty
## snapshot clears it.
func apply_snapshot(snapshot: Dictionary) -> void:
	_bind_nodes()
	_board = snapshot.duplicate(true)
	_fill_from_board()
	_render()


## The office ids the board is showing, in display order. Reported, not selectable:
## there is nothing here to choose.
##
## A SPARE pool row is not a seat and is not reported. It renders `{}` and answers
## `is_filled() == false`, so its id reads as `""` and is dropped here. That is what
## keeps the reported list equal to the authored board: a count that included the
## spare rows would make a polity look like it authors offices its catalog never
## defined — the exact legibility failure this screen exists to prevent.
func office_ids() -> Array:
	var out: Array = []
	for row in _office_rows:
		var office_id := String((row as NationOfficeRow).office_id())
		if office_id != "":
			out.append(office_id)
	return out


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var offices := _office_summaries()
	var claims := _claim_summaries()
	var stances := _stance_summaries()
	var standoffs := _standoff_summaries()
	return {
		"actor": String(_actor.id),
		"read_only": true,
		"founded": bool(_board.get("founded", false)),
		"nation_id": String(_board.get("nation_id", "")),
		"nation_name": String(_board.get("nation_name", "")),
		"standing": int(_board.get("standing", 0)),
		"standing_cap": int(_board.get("standing_cap", 0)),
		"recognized_percent": float(_board.get("recognized_percent", 0.0)),
		# The two counts the board is FOR. A screen that hid a vacancy would still
		# render "2 offices"; these are what make the gap countable.
		"vacant_offices": _count(offices, "vacant", true),
		"filled_offices": _count(offices, "vacant", false),
		"office_count": offices.size(),
		"open_standoffs": _open_standoffs(standoffs),
		"claim_count": claims.size(),
		"contested_claims": _contested(claims),
		"stance_count": stances.size(),
		"standoff_count": standoffs.size(),
		"offices": offices,
		"claims": claims,
		"stances": stances,
		"standoffs": standoffs,
		"vacant_office_ids": _ids_where(offices, "vacant", true),
		"office_ids": office_ids(),
		"row_ids": row_ids(),
	}


## Re-read the facade — the ONE call this screen makes — and hand raw values down.
## Every later read is of the cached `_board`, never of the facade, so a refresh
## costs exactly one call however many times `summary()` is asked. The rows own
## every format.
func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	var live := NationApi.summary(_actor) if _actor != null else {}
	if not live.is_empty():
		_board = live
	_fill_from_board()


## Push the cached board into the row pools. Split out from `_refresh_view` so that
## adopting a snapshot renders it without a second facade read.
func _fill_from_board() -> void:
	_fill_offices()
	_fill_claims()
	_fill_stances()
	_fill_standoffs()


## Repaint this screen's own labels. Each row repaints itself, and the screen
## formats no number: it hands raw values down and the rows word them.
func _render() -> void:
	if _header == null:
		return
	if _actor == null:
		_header.text = NO_ACTOR_TEXT
		_footer.text = ""
		return
	_header.text = HEADER_TEXT if bool(_board.get("founded", false)) else UNFOUNDED_TEXT
	_footer.text = FOOTER_TEXT


# --- ScreenStack hooks ------------------------------------------------------


## Nothing here is pressable, so the landing spot is the first seat that EXISTS —
## which deliberately includes a vacant one, because the vacancy is the thing a
## player opening this screen most needs to see. Recorded first, because a node
## outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	var target := _first_filled(_office_rows)
	if target == null:
		target = _first_filled(_standoff_rows)
	if target == null:
		target = _first_filled(_claim_rows)
	if target == null:
		target = _first_filled(_stance_rows)
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
	_header = get_node_or_null("%BoardHeader") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_office_box = get_node_or_null("Layout/Scroll/Board/Offices") as VBoxContainer
	_claim_box = get_node_or_null("Layout/Scroll/Board/Claims") as VBoxContainer
	_stance_box = get_node_or_null("Layout/Scroll/Board/Stances") as VBoxContainer
	_standoff_box = get_node_or_null("Layout/Scroll/Board/Standoffs") as VBoxContainer
	_bound = (
		_header != null
		and _footer != null
		and _office_box != null
		and _claim_box != null
		and _stance_box != null
		and _standoff_box != null
	)
	if not _bound:
		return
	_office_rows = _rows_in(_office_box, OFFICE_SCENE, "Office", OFFICE_ROWS)
	_claim_rows = _rows_in(_claim_box, CLAIM_SCENE, "Claim", CLAIM_ROWS)
	_stance_rows = _rows_in(_stance_box, STANCE_SCENE, "Stance", STANCE_ROWS)
	_standoff_rows = _rows_in(_standoff_box, STANDOFF_SCENE, "Standoff", STANDOFF_ROWS)


## The rows the scene declares, in order, then the ones grown at runtime. Every
## kind is built the same way so no section of this screen can quietly be the one
## that truncates.
func _rows_in(box: VBoxContainer, scene_path: String, prefix: String, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as Control
		if row != null and row.has_method(&"show_office"):
			out.append(row)
			continue
		if row != null and row.has_method(&"show_territory"):
			out.append(row)
			continue
		if row != null and row.has_method(&"show_stance"):
			out.append(row)
			continue
		if row != null and row.has_method(&"show_standoff"):
			out.append(row)
	for index in range(extra):
		var row := load(scene_path).instantiate() as Control
		row.name = "%s%d" % [prefix, out.size()]
		box.add_child(row)
		out.append(row)
	return out


## Grow a mounted pool to fit the data, so the board scrolls rather than truncates.
## A row the scene already mounted is reused; only a shortage is filled.
func _grow(
	box: VBoxContainer, rows: Array, scene_path: String, prefix: String, needed: int
) -> void:
	# Bounded, not trusted: `needed` is a data-derived office/stance count, and a
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


## ## Every AUTHORED office gets a row, in canonical order, vacancies included
##
## This is the load-bearing loop of the screen. It iterates the AUTHORED board — not
## the filled seats, not the non-empty rows — so a seat nobody holds still reaches a
## row, and every row past the authored board is handed `{}` and hides itself. The
## bounded walk is a `for` over a snapshot rather than a `while`, so there is no exit
## condition that could fail to converge.
func _fill_offices() -> void:
	var board: Dictionary = _board.get("offices", {}) as Dictionary
	var ids := board.keys()
	ids.sort()
	var views: Array = []
	for office_id in ids:
		views.append(board[office_id])
	_grow(_office_box, _office_rows, OFFICE_SCENE, "Office", views.size())
	var index := 0
	while index < _office_rows.size():
		(_office_rows[index] as NationOfficeRow).show_office(
			views[index] as Dictionary if index < views.size() else {}
		)
		index += 1


func _fill_claims() -> void:
	var views := _ordered(_board.get("claims", {}), "challenger_id")
	_grow(_claim_box, _claim_rows, CLAIM_SCENE, "Claim", views.size())
	var index := 0
	while index < _claim_rows.size():
		(_claim_rows[index] as NationTerritoryRow).show_territory(
			views[index] as Dictionary if index < views.size() else {}
		)
		index += 1


func _fill_stances() -> void:
	var views := _ordered(_board.get("stances", {}), "")
	_grow(_stance_box, _stance_rows, STANCE_SCENE, "Stance", views.size())
	var index := 0
	while index < _stance_rows.size():
		(_stance_rows[index] as NationStanceRow).show_stance(
			views[index] as Dictionary if index < views.size() else {}
		)
		index += 1


## Open standoffs first, then the closed ones: a live standoff is what a player
## opening this screen came to see, and history below it reads as history.
func _fill_standoffs() -> void:
	var views := _ordered(_board.get("standoffs", {}), "closed")
	_grow(_standoff_box, _standoff_rows, STANDOFF_SCENE, "Standoff", views.size())
	var index := 0
	while index < _standoff_rows.size():
		(_standoff_rows[index] as NationStandoffRow).show_standoff(
			views[index] as Dictionary if index < views.size() else {}
		)
		index += 1


## Every value of `catalog` as an array, canonically ordered by key so two runs
## agree. Rows carrying a truthy `flag` sort first — so a contested claim leads the
## claims section and an open standoff leads the conflicts, which is what a player
## opening this screen came to see. Pass `""` for a flag to keep pure key order.
func _ordered(catalog: Variant, flag: String) -> Array:
	var out: Array = []
	if not (catalog is Dictionary):
		return out
	var entries: Dictionary = catalog
	var ids := entries.keys()
	ids.sort()
	if flag != "":
		var flagged: Array = []
		var plain: Array = []
		for entry_id in ids:
			var view: Dictionary = entries[entry_id]
			if _is_set(view.get(flag, null)):
				flagged.append(view)
			else:
				plain.append(view)
		return flagged + plain
	for entry_id in ids:
		out.append(entries[entry_id])
	return out


## Whether a snapshot key counts as SET. The flag a caller passes is sometimes a
## bool (`closed`) and sometimes a string (`challenger_id`), and the two have to be
## read the way each actually means it: an empty challenger id is nobody contesting,
## while a closed standoff is the opposite of the flag being present. An absent key
## is never set.
func _is_set(value: Variant) -> bool:
	if value == null:
		return false
	if value is bool:
		return bool(value)
	if value is String or value is StringName:
		return String(value) != ""
	return true


# --- Reporting --------------------------------------------------------------


## Every office row that EXISTS, nested under its own key. A spare row contributes
## `{}` and is skipped here, so `offices` counts seats — filled and vacant alike —
## rather than rows.
func _office_summaries() -> Array:
	var out: Array = []
	for row in _office_rows:
		var view: Dictionary = (row as NationOfficeRow).summary()
		if not view.is_empty():
			out.append(view)
	return out


func _claim_summaries() -> Array:
	var out: Array = []
	for row in _claim_rows:
		var view: Dictionary = (row as NationTerritoryRow).summary()
		if not view.is_empty():
			out.append(view)
	return out


func _stance_summaries() -> Array:
	var out: Array = []
	for row in _stance_rows:
		var view: Dictionary = (row as NationStanceRow).summary()
		if not view.is_empty():
			out.append(view)
	return out


func _standoff_summaries() -> Array:
	var out: Array = []
	for row in _standoff_rows:
		var view: Dictionary = (row as NationStandoffRow).summary()
		if not view.is_empty():
			out.append(view)
	return out


## Every row id the screen is showing, in display order, so a test can read the
## board's order without walking the tree. Spare pool rows carry nothing and so
## contribute nothing, for the same reason `office_ids()` drops them.
func row_ids() -> Array:
	var out: Array = []
	out.append_array(office_ids())
	for row in _claim_rows:
		var territory_id := String((row as NationTerritoryRow).territory_id())
		if territory_id != "":
			out.append(territory_id)
	for row in _stance_rows:
		var pair_key := String((row as NationStanceRow).pair_key())
		if pair_key != "":
			out.append(pair_key)
	for row in _standoff_rows:
		var standoff_id := String((row as NationStandoffRow).standoff_id())
		if standoff_id != "":
			out.append(standoff_id)
	return out


func _count(views: Array, key: String, want: bool) -> int:
	var total := 0
	for view in views:
		if bool((view as Dictionary).get(key, false)) == want:
			total += 1
	return total


func _ids_where(views: Array, key: String, want: bool) -> Array:
	var out: Array = []
	for view in views:
		var entry: Dictionary = view
		if bool(entry.get(key, false)) == want:
			out.append(String(entry.get("office_id", "")))
	return out


func _open_standoffs(views: Array) -> int:
	var total := 0
	for view in views:
		if not bool((view as Dictionary).get("closed", true)):
			total += 1
	return total


func _contested(views: Array) -> int:
	var total := 0
	for view in views:
		if bool((view as Dictionary).get("contested", false)):
			total += 1
	return total
