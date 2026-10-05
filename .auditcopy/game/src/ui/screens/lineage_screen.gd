class_name LineageScreen
extends UiScreen

## ONE screen for the whole lineage: the body you were born into, the bloodlines
## you carry, and the house you belong to. A pure consumer of three facades and
## nothing else — `RaceApi.summary`, `BloodlineApi.summary`, `ClanApi.summary`
## (ADR 0030, 0062, 0063, 0064, 0064).
##
## ## ONE contract-driven screen, not three near-duplicate ones
##
## The three modules answer three questions about the same fact — what this body
## IS, what it INHERITED, and who it BELONGS to — and each already publishes a
## single `summary(actor)` that answers its half in primitives. Three bespoke
## screens would have been three copies of this file's plumbing with one section
## each, and three routes a player has to learn to get one answer. So there is one
## route and three sections, and the screen names a player in the route label
## (`Lineage`) rather than in a module.
##
## ## Three facade calls, one per refresh, and nothing else
##
## Each facade is read exactly once per refresh and cached, so asking for
## `summary()` a dozen times still costs three calls, and nothing after a refresh
## re-enters a module. This is the rule `test_sect_screen` enforces by source read
## for `sect`; the same rule holds here for three modules at once.
##
## ## THE DORMANT CASE, and why this screen is shaped around it
##
## Purity decays within a life and is never raised (ADR 0063), and
## `BloodlineProjection` deliberately keeps the `bloodline:<id>` trait mirror on
## **while dormant**, so a sleeping lineage is never the same as no lineage. The
## screen therefore renders **every carried lineage, awake or not**, in a single
## list ordered awake-first — and reports `dormant_lineages` and `dormant_lineage_ids`
## on the testable surface so the claim is assertable rather than merely intended.
## A row that filtered on `awake` would leave a live trait with no visible cause.
##
## ## A house you do not belong to is a sentence, not an empty card
##
## Belonging to no clan is the normal starting state (ADR 0064), so the house row
## renders `ClanApi`'s empty membership block and says so. Only a SPARE pool row
## renders `{}` and hides — the two are different claims and never collapsed.
##
## ## Read-only by design
##
## Every verb the three modules publish that would CHANGE a lineage is a write the
## player performs through birth, admission and recognition, not through a codex. A
## button here would either lie about what it can do or open a conversation the
## module does not have. So `on_stack_input` consumes nothing and `ui_cancel` pops
## this screen exactly as it pops every other read-only one.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` with no
## actor, and each child's own summary nested under the child's key.

## Rows the scene mounts. Pools GROW to fit the data rather than truncating: a
## bloodline that silently vanished would read as a lineage the hero does not carry,
## which is the one thing this screen exists to prevent.
const BODY_ROWS := 1
const BLOOD_ROWS := 8
const HOUSE_ROWS := 1
const BODY_SCENE := "res://src/ui/panels/lineage_body_row.tscn"
const BLOOD_SCENE := "res://src/ui/panels/lineage_blood_row.tscn"
const HOUSE_SCENE := "res://src/ui/panels/lineage_house_row.tscn"

const HEADER_TEXT := "What you are, what you carry, and who you belong to."
const NO_ACTOR_TEXT := "No hero bound."
const NO_ACTOR_FOOTER := ""
const FOOTER_TEXT := (
	"Read-only. A body is what it refuses, a bloodline is what it carries, a house is what it owes and asks."
)
const DORMANT_COUNT := "carried and dormant"
const AWAKE_COUNT := "awake"

var _race: Dictionary = {}
var _bloodline: Dictionary = {}
var _clan: Dictionary = {}
var _header: Label = null
var _footer: Label = null
var _body_box: VBoxContainer = null
var _blood_box: VBoxContainer = null
var _house_box: VBoxContainer = null
var _bound: bool = false
var _body_rows: Array = []
var _blood_rows: Array = []
var _house_rows: Array = []


## Adopt three facade snapshots for the bound actor. `setup(actor)` takes the
## facade path inside `_refresh_view`; this exists so a headless test or a driver
## can render the page from snapshots with no actor at all, and — importantly — so
## adopting snapshots does NOT re-enter any module. Empty dictionaries clear.
func apply_snapshot(race: Dictionary, bloodline: Dictionary, clan: Dictionary) -> void:
	_bind_nodes()
	_race = race.duplicate(true)
	_bloodline = bloodline.duplicate(true)
	_clan = clan.duplicate(true)
	_fill()
	_render()


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var blood := _blood_summaries()
	var body := _body_summaries()
	var house := _house_summaries()
	return {
		"actor": String(_actor.id),
		"read_only": true,
		# --- Body: the race, as the facade published it -----------------------
		"race_id": String(_race.get("race", "")),
		"closed_paths": _string_list(_race.get("closed_paths", [])),
		"closed_path_count": _string_list(_race.get("closed_paths", [])).size(),
		"open_path_count": int(_race.get("open_path_count", 0)),
		"realm_ceiling": int(_race.get("realm_ceiling", 0)),
		"realm_reached": int(_race.get("realm_reached", 0)),
		"lifespan": float(_race.get("lifespan", 0.0)),
		"affinities": _affinity_map(_race.get("affinities", {})),
		"is_baseline": bool(_race.get("is_baseline", false)),
		# --- Inheritance: every carried lineage, awake or not ------------------
		"lineage_count": int(_bloodline.get("lineage_count", 0)),
		"awakened": _string_list(_bloodline.get("awakened", [])),
		"awakened_count": int(_bloodline.get("awakened_count", 0)),
		"peak_purity": float(_bloodline.get("peak_purity", 0.0)),
		"mean_purity": float(_bloodline.get("mean_purity", 0.0)),
		"tier": String(_bloodline.get("tier", "")),
		# The dormant half, named as its own pair of facts. This is the case the
		# screen exists to keep visible: the trait mirror is still on the actor.
		"dormant_lineage_ids": _ids_where(blood, "dormant", true),
		"dormant_count": _count_where(blood, "dormant", true),
		"awake_lineage_ids": _ids_where(blood, "awake", true),
		# --- House: the clan, and the terms on both sides of its ledger --------
		"clan_id": String(_clan.get("clan", "")),
		"clan_name": String(_clan.get("display_name", "")),
		"is_member": String(_clan.get("clan", "")) != "",
		"rank": String(_clan.get("rank", "")),
		"standing": int(_clan.get("standing", 0)),
		"recognition": float(_clan.get("recognition", 0.0)),
		"recognition_scale": float(_clan.get("recognition_scale", 1.0)),
		"patronage": _string_list(_clan.get("patronage", [])),
		"duty": _string_list(_clan.get("duty", [])),
		"patronage_count": _string_list(_clan.get("patronage", [])).size(),
		"duty_count": _string_list(_clan.get("duty", [])).size(),
		# --- The children's own summaries, each under its own key --------------
		"body": body,
		"bloodlines": blood,
		"house": house,
		"row_ids": row_ids(),
	}


## Re-read the three facades — the ONLY module calls on this screen — and hand raw
## values down. Every later read is of the cached snapshots, so a refresh costs
## three calls however many times `summary()` is asked. The rows own every format.
func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	if _actor == null:
		return
	var race := RaceApi.summary(_actor)
	if not race.is_empty():
		_race = race
	var bloodline := BloodlineApi.summary(_actor)
	if not bloodline.is_empty():
		_bloodline = bloodline
	var clan := ClanApi.summary(_actor)
	if not clan.is_empty():
		_clan = clan
	_fill()


## Push the cached snapshots into the row pools. Split out of `_refresh_view` so
## adopting snapshots renders them without a second facade read.
func _fill() -> void:
	_fill_body()
	_fill_blood()
	_fill_house()


## Repaint this screen's own labels. Each row repaints itself; the screen formats no
## number — it hands raw values down and the rows word them.
func _render() -> void:
	if _header == null:
		return
	if _actor == null:
		_header.text = NO_ACTOR_TEXT
		_footer.text = NO_ACTOR_FOOTER
		return
	_header.text = HEADER_TEXT
	_footer.text = FOOTER_TEXT


# --- ScreenStack hooks ------------------------------------------------------


## Nothing here is pressable, so the landing spot is the BODY row — the fact a
## player opens this page for — and failing that the first carried lineage, which
## deliberately includes a DORMANT one. Recorded first, because a node outside a
## viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	var target := _first_filled(_body_rows)
	if target == null:
		target = _first_filled(_blood_rows)
	if target == null:
		target = _first_filled(_house_rows)
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
	_header = get_node_or_null("%LineageHeader") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_body_box = get_node_or_null("Layout/Scroll/Page/Body") as VBoxContainer
	_blood_box = get_node_or_null("Layout/Scroll/Page/Bloodlines") as VBoxContainer
	_house_box = get_node_or_null("Layout/Scroll/Page/House") as VBoxContainer
	_bound = (
		_header != null
		and _footer != null
		and _body_box != null
		and _blood_box != null
		and _house_box != null
	)
	if not _bound:
		return
	_body_rows = _rows_in(_body_box, BODY_SCENE, "Body", BODY_ROWS)
	_blood_rows = _rows_in(_blood_box, BLOOD_SCENE, "Blood", BLOOD_ROWS)
	_house_rows = _rows_in(_house_box, HOUSE_SCENE, "House", HOUSE_ROWS)


## The rows the scene declares, in order, then enough grown rows to reach `extra`.
## A pool smaller than `extra` would have to truncate the data the next refresh
## brings, so the mounted rows are topped up here rather than left to `_grow`.
func _rows_in(box: VBoxContainer, scene_path: String, prefix: String, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as Control
		if row != null and row.has_method(&"show_body"):
			out.append(row)
			continue
		if row != null and row.has_method(&"show_bloodline"):
			out.append(row)
			continue
		if row != null and row.has_method(&"show_house"):
			out.append(row)
	for index in range(extra):
		var row := load(scene_path).instantiate() as Control
		row.name = "%s%d" % [prefix, out.size()]
		box.add_child(row)
		out.append(row)
	return out


## Grow a mounted pool to fit the data, so the page scrolls rather than truncates.
## Clamped through `RowBudget` because `needed` comes from the snapshot: a pool that
## grew to fit an unbounded count parents live Controls without limit (INC-0004).
func _grow(
	box: VBoxContainer, rows: Array, scene_path: String, prefix: String, needed: int
) -> void:
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


## The one body row. `{}` when the hero carries no race at all — the row renders
## its own "unnamed" sentence for that, which is a fact; a SPARE row is `{}` and
## hides. `BODY_ROWS` is one because a hero has exactly one body and a second row
## would be a second thing to explain.
func _fill_body() -> void:
	if _body_rows.is_empty():
		return
	var block := _body_block()
	(_body_rows[0] as LineageBodyRow).show_body(block, _catalog(_race, "races"))
	for index in range(1, _body_rows.size()):
		(_body_rows[index] as LineageBodyRow).show_body({})


## Every carried lineage, awake first, then dormant. The ORDER is the design: an
## awakened lineage is what the hero can use and a dormant one is what they carry
## but have not awakened, and the second must still be findable rather than lost
## under the first. Rows past the carried set render `{}` and hide.
func _fill_blood() -> void:
	var views := _ordered_blood()
	_grow(_blood_box, _blood_rows, BLOOD_SCENE, "Blood", views.size())
	var index := 0
	while index < _blood_rows.size():
		var view: Dictionary = views[index] if index < views.size() else {}
		(
			(_blood_rows[index] as LineageBloodRow).show_bloodline(
				view, _catalog(_bloodline, "bloodlines")
			)
		)
		index += 1


## The one house row, handed the empty membership block when the hero belongs to
## none — which the row renders as a sentence, because "no house" is the ordinary
## state (ADR 0064) and not an error.
func _fill_house() -> void:
	if _house_rows.is_empty():
		return
	var block := _clan.duplicate(true)
	block["clan"] = String(_clan.get("clan", ""))
	(_house_rows[0] as LineageHouseRow).show_house(block, _catalog(_clan, "clans"))
	for index in range(1, _house_rows.size()):
		(_house_rows[index] as LineageHouseRow).show_house({})


## The carried-lineage rows, awake first and canonically ordered within each group,
## so two runs agree. NOT filtered on `awake`: see the class note.
func _ordered_blood() -> Array:
	var carried: Dictionary = _bloodline.get("lineages", {}) as Dictionary
	var ids := carried.keys()
	ids.sort()
	var awake: Array = []
	var dormant: Array = []
	for lineage_id in ids:
		var view: Dictionary = carried[lineage_id]
		if bool(view.get("awake", false)):
			awake.append(view)
		else:
			dormant.append(view)
	return awake + dormant


## The actor-level race block: the facade's top level, minus the two keys that are
## catalog rather than actor. Everything else on that level IS the actor's body.
func _body_block() -> Dictionary:
	var block := _race.duplicate(true)
	block.erase("races")
	block.erase("has_actor")
	return block


func _catalog(snapshot: Dictionary, key: String) -> Dictionary:
	var value: Variant = snapshot.get(key, {})
	return value as Dictionary if value is Dictionary else {}


# --- Reporting --------------------------------------------------------------


## The body row's own summary, nested under `body`. One row, so a list of one
## rather than a bare dictionary: the shape cannot change shape when a future
## section grows to more rows.
func _body_summaries() -> Array:
	var out: Array = []
	for row in _body_rows:
		var view: Dictionary = (row as LineageBodyRow).summary()
		if not view.is_empty():
			out.append(view)
	return out


## Every carried lineage row's own summary, nested under `bloodlines`. A DORMANT
## row is included: it is carried, it is rendered, and it is reported here.
func _blood_summaries() -> Array:
	var out: Array = []
	for row in _blood_rows:
		var view: Dictionary = (row as LineageBloodRow).summary()
		if not view.is_empty():
			out.append(view)
	return out


func _house_summaries() -> Array:
	var out: Array = []
	for row in _house_rows:
		var view: Dictionary = (row as LineageHouseRow).summary()
		if not view.is_empty():
			out.append(view)
	return out


## Every row id the screen is showing, in display order, so a test can read the
## page's order without walking the tree. Spare pool rows carry nothing and so
## contribute nothing — the same reason the row ids skip them.
func row_ids() -> Array:
	var out: Array = []
	for row in _body_rows:
		var race_id := String((row as LineageBodyRow).summary().get("race_id", ""))
		if race_id != "":
			out.append(race_id)
	for row in _blood_rows:
		var lineage_id := String((row as LineageBloodRow).summary().get("lineage_id", ""))
		if lineage_id != "":
			out.append(lineage_id)
	for row in _house_rows:
		var clan_id := String((row as LineageHouseRow).summary().get("clan_id", ""))
		if clan_id != "":
			out.append(clan_id)
	return out


func _ids_where(views: Array, key: String, want: bool) -> Array:
	var out: Array = []
	for view in views:
		var entry: Dictionary = view
		if bool(entry.get(key, false)) == want:
			out.append(String(entry.get("lineage_id", "")))
	return out


func _count_where(views: Array, key: String, want: bool) -> int:
	var total := 0
	for view in views:
		if bool((view as Dictionary).get(key, false)) == want:
			total += 1
	return total


func _affinity_map(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (value is Dictionary):
		return out
	for key in (value as Dictionary).keys():
		out[String(key)] = float((value as Dictionary)[key])
	return out


func _string_list(value: Variant) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for entry in value as Array:
		out.append(String(entry))
	return out