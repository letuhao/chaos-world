class_name TechniqueSlotRow
extends PanelContainer

## One path-typed slot in the loadout: which pool it belongs to, what fills it,
## and the button that releases it.
##
## The row owns every format it shows — the pool name, the "empty" wording, the
## suspension mark — so a screen never renders a number. It publishes no rule
## either: `unequip_requested` carries the technique id and the screen asks the
## facade, which is what keeps a slot loss from ever being a technique loss
## (ADR 0053).
##
## Contract: `summary()` is the testable surface. `{}` when the row carries nothing.

signal unequip_requested(technique_id: StringName)

const EMPTY_TEXT := "Empty"
const SUSPENDED_TEXT := "SUSPENDED"
const POOL_UNKNOWN := "untyped"

var _view: Dictionary = {}
var _head: String = ""
var _body: String = ""
var _pool: String = ""
var _head_label: Label = null
var _body_label: Label = null
var _pool_label: Label = null
var _unequip_button: Button = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one slot as the technique facade publishes it: the `slot_view` row
## `TechniquesApi.summary` lists — `{slot, kind, technique_id, display_name,
## filled, suspended}`. An empty dictionary clears the row, which is what a spare
## row in the pool shows.
func show_slot(view: Dictionary) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_pool = _pool_text(_view)
	_head = _head_text(_view)
	_body = _body_text(_view)
	_render()


func clear() -> void:
	show_slot({})


## Everything the row shows, primitives only. `{}` when it carries nothing.
func summary() -> Dictionary:
	_bind_nodes()
	if _view.is_empty():
		return {}
	return {
		"slot": String(_view.get("slot", "")),
		"kind": String(_view.get("kind", "")),
		"pool": _pool,
		"technique_id": String(_view.get("technique_id", "")),
		"display_name": String(_view.get("display_name", "")),
		"filled": bool(_view.get("filled", false)),
		"suspended": bool(_view.get("suspended", false)),
		"can_unequip": bool(_view.get("filled", false)),
		"head": _head,
		"body": _body,
		"empty": false,
	}


## Whether the row carries anything worth taking space for.
func is_filled() -> bool:
	return not _view.is_empty()


func slot_key() -> String:
	return String(_view.get("slot", ""))


## The id the release button would act on, or `""` when the slot is empty.
func technique_id() -> StringName:
	return StringName(String(_view.get("technique_id", "")))


## Give the keyboard and pad a landing spot. The target is recorded first,
## because a node outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if _unequip_button != null and _unequip_button.is_inside_tree():
		_unequip_button.grab_focus()


# --- Plumbing ---------------------------------------------------------------


## Resolve the scene's widgets on first use rather than in `@onready`: the
## headless suite runner drives this row before a scene tree exists, so
## `_ready()` is not a dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_body_label = get_node_or_null("%BodyLabel") as Label
	_pool_label = get_node_or_null("%PoolLabel") as Label
	_unequip_button = get_node_or_null("%UnequipButton") as Button
	if _unequip_button != null and not _unequip_button.pressed.is_connected(_on_unequip):
		_unequip_button.pressed.connect(_on_unequip)


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	if not visible:
		return
	_pool_label.text = _pool
	_head_label.text = _head
	_head_label.theme_type_variation = _head_variation()
	_body_label.text = _body
	if _unequip_button != null:
		_unequip_button.visible = bool(_view.get("filled", false))
		_unequip_button.disabled = not bool(_view.get("filled", false))


## The pool this slot draws from, as a player would name it. `kind` is the
## facade's pool id — `qi_cultivation`, `body_cultivation`, `mind_cultivation` or
## `universal` — which is machine vocabulary, so the row words it.
func _pool_text(view: Dictionary) -> String:
	match String(view.get("kind", "")):
		PathState.QI:
			return "Qi path pool"
		PathState.BODY:
			return "Body path pool"
		PathState.MIND:
			return "Mind path pool"
		&"universal":
			return "Universal pool"
	return POOL_UNKNOWN


## The slot's own key, with the machine prefix stripped: `slot_path_qi_cultivation2`
## is the third qi slot, and `qi slot 3` is what a player reads.
func _head_text(view: Dictionary) -> String:
	var key := String(view.get("slot", ""))
	var tail := key.get_slice("_", 2) if key.begins_with("slot_") else key
	return "%s slot %s" % [_pool_short(view), tail]


func _pool_short(view: Dictionary) -> String:
	match String(view.get("kind", "")):
		PathState.QI:
			return "qi"
		PathState.BODY:
			return "body"
		PathState.MIND:
			return "mind"
		&"universal":
			return "universal"
	return "slot"


## What the slot holds: the technique's name, or the empty wording, with a
## suspension mark when the slot is filled but the technique cannot pay upkeep.
func _body_text(view: Dictionary) -> String:
	if not bool(view.get("filled", false)):
		return EMPTY_TEXT
	var name := String(view.get("display_name", ""))
	var text := name if not name.is_empty() else String(view.get("technique_id", ""))
	if bool(view.get("suspended", false)):
		text += " (%s)" % SUSPENDED_TEXT
	return text


func _head_variation() -> StringName:
	if bool(_view.get("suspended", false)):
		return &"WarnLabel"
	return &"SectionTitle" if bool(_view.get("filled", false)) else &"MetaLabel"


func _on_unequip() -> void:
	var id := technique_id()
	if id.is_empty():
		return
	unequip_requested.emit(id)
