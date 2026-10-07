class_name TechniqueEquipRow
extends PanelContainer

## One learned-but-unbound technique, with the button that binds it.
##
## The row owns every format it shows — the pool a binding would draw from, the
## slot count it would claim, the "no free slot" gate — so a screen never renders a
## number and the module keeps every rule. A refused bind changes nothing at all
## here: the row repaints from the same `TechniquesApi` values and the gate text is
## the module's own `equip_unmet` wording.
##
## Contract: `summary()` is the testable surface. `{}` when the row carries nothing.

signal equip_requested(technique_id: StringName)

const EMPTY_TEXT := "Empty"
const ALREADY_BOUND := "Already bound"
const NO_SLOT_TEXT := "No free slot in its pool"
const POOL_UNKNOWN := "untyped"

var _view: Dictionary = {}
var _head: String = ""
var _body: String = ""
var _gate: String = ""
var _head_label: Label = null
var _body_label: Label = null
var _gate_label: Label = null
var _equip_button: Button = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one offer as `TechniquesApi.inspect` publishes it: identity, path, and
## `claimable_slots` — the module's own answer to "could this be bound right now".
## An empty dictionary clears the row, which is what a spare row shows.
func show_entry(view: Dictionary) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_head = _head_text(_view)
	_body = _body_text(_view)
	_gate = _gate_text(_view)
	_render()


func clear() -> void:
	show_entry({})


## Everything the row shows, primitives only. `{}` when the row carries nothing.
func summary() -> Dictionary:
	_bind_nodes()
	if _view.is_empty():
		return {}
	var slots := _string_list(_view.get("claimable_slots", []))
	var equipped := bool(_view.get("equipped", false))
	return {
		"id": String(_view.get("id", "")),
		"display_name": String(_view.get("display_name", "")),
		"path": String(_view.get("path", "")),
		"grade": String(_view.get("grade", "")),
		"active": bool(_view.get("active", false)),
		"equipped": equipped,
		"suspended": bool(_view.get("suspended", false)),
		"known": bool(_view.get("known", true)),
		"claimable_slots": slots,
		"claimable_count": slots.size(),
		"blocked_by": _string_list(_view.get("equip_unmet", [])),
		"offered": not equipped,
		"can_equip": not equipped and not slots.is_empty(),
		"head": _head,
		"body": _body,
		"gate": _gate,
		"empty": false,
	}


## Whether the row carries anything worth taking space for.
func is_filled() -> bool:
	return not _view.is_empty()


## The id the bind button would act on, or `""` when there is nothing to bind.
func technique_id() -> StringName:
	return StringName(String(_view.get("id", "")))


## Give the keyboard and pad a landing spot. Recorded before the grab, because a node
## outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if _equip_button != null and _equip_button.is_inside_tree():
		_equip_button.grab_focus()


# --- Plumbing ---------------------------------------------------------------


## Resolve the scene's widgets on first use rather than in `@onready`: the headless
## suite drives this row before a scene tree exists, so `_ready()` is not a
## dependable place to bind them. Idempotent, and the connect is guarded so a
## reused row never accumulates a second handler.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_body_label = get_node_or_null("%BodyLabel") as Label
	_gate_label = get_node_or_null("%GateLabel") as Label
	_equip_button = get_node_or_null("%EquipButton") as Button
	if _equip_button != null and not _equip_button.pressed.is_connected(_on_equip):
		_equip_button.pressed.connect(_on_equip)


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	if not visible:
		return
	_head_label.text = _head
	_head_label.theme_type_variation = _head_variation()
	_body_label.text = _body
	_gate_label.text = _gate
	if _equip_button != null:
		# Disabled rather than hidden: a player can see a technique exists and learn
		# WHY it will not bind, which is the half a hidden button takes away.
		_equip_button.disabled = not bool(summary().get("can_equip", false))


## The technique's name, or the empty wording for a spare row. An unresolvable id
## is never printed as a name.
func _head_text(view: Dictionary) -> String:
	var name := String(view.get("display_name", ""))
	if not name.is_empty():
		return name
	return "Unnamed technique" if view.has("id") else EMPTY_TEXT


## `qi_cultivation · mortal · active` — the facts the offer is scanned for, with no
## number in it. The slot count and the gate have lines of their own.
func _body_text(view: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append(_pool_text(view))
	var grade := String(view.get("grade", ""))
	if not grade.is_empty():
		parts.append(grade)
	parts.append("active" if bool(view.get("active", false)) else "passive")
	return " · ".join(parts)


## What a bind would cost in slots, or why it cannot happen. The blockers are the
## module's own `equip_unmet` labels, so this panel never restates a rule.
func _gate_text(view: Dictionary) -> String:
	if bool(view.get("equipped", false)):
		return ALREADY_BOUND
	var slots := _string_list(view.get("claimable_slots", []))
	if slots.is_empty():
		var blocked := _string_list(view.get("equip_unmet", []))
		return " · ".join(blocked) if not blocked.is_empty() else NO_SLOT_TEXT
	var pools := _string_list(view.get("paths", []))
	var where := "" if pools.is_empty() else " (%s)" % " + ".join(pools)
	if slots.size() == 1:
		return "%s%s" % [slots[0], where]
	return "%d slots%s" % [slots.size(), where]


## The pool this technique draws from, in the module's vocabulary: `ui/` names the
## path id the facade publishes and does not restate what a pool is.
func _pool_text(view: Dictionary) -> String:
	var authored := String(view.get("path", ""))
	var listed := _string_list(view.get("paths", []))
	if not listed.is_empty():
		return " + ".join(listed)
	return authored if authored != "" else POOL_UNKNOWN


## A suspended technique is never painted in the ink of a bindable one: it is bound
## to nothing and contributing nothing, which is a different state.
func _head_variation() -> StringName:
	if bool(_view.get("suspended", false)):
		return &"WarnLabel"
	return &"SectionTitle" if is_filled() else &"MetaLabel"


func _on_equip() -> void:
	var id := technique_id()
	if id.is_empty():
		return
	equip_requested.emit(id)


func _string_list(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
