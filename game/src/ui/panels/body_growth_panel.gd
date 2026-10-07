class_name BodyGrowthPanel
extends PanelContainer

## What the body has BECOME: the derived stat surface that training and a
## breakthrough reward actually move. `BodyVitalsPanel` above it answers "what
## condition is the body in right now"; this answers "what has the body grown
## into", which is the reward the training verbs pay and the only part of it a
## player could previously not see.
##
## The ids are spelled here as literals on purpose. `ui/` may reach a module only
## through its facade, so `BodyStats` is not nameable from this layer, and the stat
## ids are not re-exported through `contracts/`. The screen therefore hands over
## the actor's whole stat surface and this panel selects from it. That duplication
## is held honest from the outside: `tests/ui/test_body_growth_observability.gd`
## reconciles these literals against `BodyStats` itself and fails by name if one
## drifts, so a renamed id cannot leave a row silently empty forever.
##
## A stat the surface does not carry is NOT shown as zero. `bone_density`,
## `muscle_fiber` and `organ_vitality` have no base on a fresh hero at all — they
## arrive as a breakthrough reward (`BodyAdvancement` pays `seed.rewards`) — so a
## zero there would be a number the body never had. The row says so instead.
##
## Owns every number format in this panel: the wording, the decimals and the width.
## The screen hands over raw floats and holds none of it.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` when empty.

## One row per stat, in reading order: the three attributes a breakthrough pays,
## then the two magnitudes they compose into.
const ROWS: Array = [
	{"id": &"bone_density", "label": "LOC_UI_PANELS_86D9C2A21A", "decimals": 1},
	{"id": &"muscle_fiber", "label": "LOC_UI_PANELS_38D4D0B298", "decimals": 1},
	{"id": &"organ_vitality", "label": "LOC_UI_PANELS_3B9662A9C6", "decimals": 1},
	{"id": &"carry_capacity", "label": "LOC_UI_PANELS_1D9FA56700", "decimals": 0},
	{"id": &"body_cultivation_power", "label": "LOC_UI_PANELS_C06C5596E2", "decimals": 2},
	{"id": &"regeneration", "label": "LOC_UI_PANELS_506EB98F49", "decimals": 2},
]

## What a row says when the body does not carry the stat at all. Distinct from a
## rendered zero on purpose: one is a measurement, the other is an absence.
const UNEARNED := "LOC_UI_PANELS_2A4101BA47"

const _TITLE := "LOC_UI_PANELS_071D25A1CB"
const _NO_BODY := "LOC_UI_PANELS_356CFE27B0"
## Row labels are numbered after this prefix, one per entry in `ROWS`. Built with
## `%s` rather than inlined into the format string: `"%GrowthLabel%d"` is a `%G`
## conversion, which GDScript rejects — and it rejects it by leaving every label
## null, which reads as a scene that merely has no rows.
const _LABEL_PREFIX := "GrowthLabel"

var _title_label: Label = null
var _row_labels: Array[Label] = []
var _surface: Dictionary = {}


func _ready() -> void:
	_bind_nodes()
	_render()


## Render `surface`, the actor's derived stat map (`ActorStats.derived_all()`).
## Unknown keys are ignored: this panel shows the body path's own magnitudes, not
## every stat the hero carries.
func set_state(surface: Dictionary) -> void:
	_bind_nodes()
	_surface = surface.duplicate()
	_render()


## Every row this panel declares, and what it rendered. `ids` is the row set a test
## reconciles against `BodyStats`, so a row that stops being declared is a failure
## rather than a silently shorter panel.
func summary() -> Dictionary:
	_bind_nodes()
	if _surface.is_empty():
		return {}
	var rows: Array = []
	var earned := 0
	for index in ROWS.size():
		var spec: Dictionary = ROWS[index]
		var id := StringName(spec["id"])
		var present := _surface.has(String(id))
		if present:
			earned += 1
		(
			rows
			. append(
				{
					"id": String(id),
					"label": String(spec["label"]),
					"decimals": int(spec["decimals"]),
					"earned": present,
					"value": float(_surface.get(String(id), 0.0)),
					"text": _row_text(index),
				}
			)
		)
	return {
		"bound": _title_label != null,
		"title": _title_label.text if _title_label != null else "",
		"ids": _row_ids(),
		"rows": rows,
		"earned": earned,
		"total": ROWS.size(),
	}


## The declared row ids, in order.
func row_ids() -> Array:
	_bind_nodes()
	return _row_ids()


## What one row renders, by row index. Exposed so a test can compare the panel's
## own text against the stat the module derives, not against a second copy of it.
func row_text(index: int) -> String:
	_bind_nodes()
	return _row_text(index)


## Resolve the scene's widgets on first use rather than in `@onready`: the headless
## suite drives this panel before a scene tree exists. Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _title_label != null:
		return
	_title_label = get_node_or_null("%TitleLabel") as Label
	_row_labels.clear()
	for index in ROWS.size():
		_row_labels.append(get_node_or_null("%s%d" % [_LABEL_PREFIX, index]) as Label)


func _render() -> void:
	if _title_label == null:
		return
	if _surface.is_empty():
		_title_label.theme_type_variation = &"MetaLabel"
		_title_label.text = L.t(_NO_BODY)
		for index in ROWS.size():
			_set_label(index, "")
		return
	_title_label.theme_type_variation = &"SectionTitle"
	_title_label.text = L.t(_TITLE)
	for index in ROWS.size():
		_set_label(index, _row_text(index))


func _set_label(index: int, text: String) -> void:
	if index < 0 or index >= _row_labels.size():
		return
	var label := _row_labels[index]
	if label != null:
		label.text = L.t(text)


## One row's line. A stat the surface does not carry says so; anything else is
## formatted here, because no other layer in `ui/` is allowed to format a number.
func _row_text(index: int) -> String:
	var spec: Dictionary = ROWS[index]
	var id := StringName(spec["id"])
	# `ROWS` holds KEYS and so does `UNEARNED`, so both resolve here — the row's line is the
	# one place the pair becomes text, and `summary()` publishes what this returns.
	var label := L.t(String(spec["label"]))
	if not _surface.has(String(id)):
		return L.t("LOC_UI_PANELS_9BDA272DBC") % [label, L.t(UNEARNED)]
	return (
		L.t("LOC_UI_PANELS_265FC52551")
		% [label, _number(float(_surface[String(id)]), int(spec["decimals"]))]
	)


func _number(value: float, decimals: int) -> String:
	if decimals > 0:
		return "%.*f" % [decimals, value]
	return "%d" % int(round(value))


func _row_ids() -> Array:
	var out: Array = []
	for spec in ROWS:
		out.append(String(spec["id"]))
	return out
