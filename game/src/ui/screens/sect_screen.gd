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
## **Read-only by design.** Promotion, standing and leaving are all political acts
## with standing consequences; a button that fired one from a screen would make an
## inquisition a two-click accident. So this screen mounts fixed pools, fills them,
## and `on_stack_input` consumes nothing so `ui_cancel` pops it like every other
## read-only screen.
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
const HEADER_TEXT := "The institution you are sworn to, and what the office obliges."
const NO_ACTOR_TEXT := "No hero bound."
const FOOTER_TEXT := "Read-only: an institution grants recognition and access, and never power."

var _codex: Dictionary = {}
var _header: Label = null
var _footer: Label = null
var _claim_box: VBoxContainer = null
var _office_box: VBoxContainer = null
var _bound: bool = false
var _claim_rows: Array = []
var _office_rows: Array = []


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
		"read_only": true,
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
		"can_promote": promotions,
		"can_promote_count": promotions.size(),
		"sects": sects,
		"sect_count": sects.size(),
		"office_ids": row_ids(),
	}


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


## Repaint this screen's own labels. The rows repaint themselves.
func _render() -> void:
	if _header == null:
		return
	if _actor == null:
		_header.text = NO_ACTOR_TEXT
		_footer.text = ""
		return
	_header.text = HEADER_TEXT if bool(_codex.get("is_member", false)) else NO_ACTOR_TEXT
	_footer.text = FOOTER_TEXT


# --- ScreenStack hooks ------------------------------------------------------


## Nothing here is pressable, so the landing spot is the member's own claim row —
## the thing the screen is read for — and failing that the first office with room.
## Recorded first, because a node outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	var target := _first_filled(_claim_rows)
	if target == null:
		target = _first_filled(_office_rows)
	if target == null:
		return
	_focus_target = String(target.name)
	if target.is_inside_tree():
		target.call(&"focus_initial")


## Nothing here is actionable, so nothing is consumed: `ui_cancel` stays free for
## `ScreenStack` to pop.
func on_stack_input(_event: InputEvent) -> bool:
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
	_bound = _header != null and _footer != null and _claim_box != null and _office_box != null
	if not _bound:
		return
	_claim_rows = _rows_in(_claim_box, CLAIM_SCENE, "Claim", CLAIM_SPARE_ROWS)
	_office_rows = _rows_in(_office_box, OFFICE_SCENE, "Office", OFFICE_ROWS)


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


## Exactly one claim row: a member has one claim, and a second row would be a spare
## that had to hide itself. The claim is passed through RAW — the row owns every
## word and every number, and the screen renders none.
func _fill_claims() -> void:
	var view: Dictionary = _codex.duplicate(true)
	if _claim_rows.is_empty():
		return
	(_claim_rows[0] as SectClaimRow).show_claim(view)
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
