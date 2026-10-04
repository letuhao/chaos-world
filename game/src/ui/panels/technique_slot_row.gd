class_name TechniqueSlotRow
extends PanelContainer

## One path-typed slot in the loadout: which pool it belongs to, what fills it,
## the button that releases it, and — when the technique it holds is ACTIVE — the
## button that fires it.
##
## ## Why casting lives on the slot row
##
## A technique that can be fired must be bound, so the loadout is the only page that
## can offer the verb at all; and the slot already knows what it holds, so the row is
## where "this one can be cast, and it is ready" is legible without a second list.
## The row owns no rule: `cast_requested` carries the technique id and the screen
## asks `TechniqueCasting.activate` through the resolver the composition root bound,
## which is what keeps using a technique from ever being an acquisition or a build
## choice (ADR 0053).
##
## The row owns every format it shows — the pool name, the "empty" wording, the
## suspension mark, the cooldown line — so a screen never renders a number.
##
## Contract: `summary()` is the testable surface. `{}` when the row carries nothing.

signal unequip_requested(technique_id: StringName)
signal cast_requested(technique_id: StringName)

const EMPTY_TEXT := "Empty"
const SUSPENDED_TEXT := "SUSPENDED"
const POOL_UNKNOWN := "untyped"
const READY_TEXT := "Ready"

var _view: Dictionary = {}
var _head: String = ""
var _body: String = ""
var _pool: String = ""
var _readiness: String = ""
var _head_label: Label = null
var _body_label: Label = null
var _pool_label: Label = null
var _ready_label: Label = null
var _unequip_button: Button = null
var _cast_button: Button = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one slot as the technique facade publishes it: the `slot_view` row
## `TechniquesApi.summary` lists — `{slot, kind, technique_id, display_name,
## filled, suspended}` — plus the two casting fields the screen resolves through
## `TechniquesApi.inspect`: `active`, and `cooldown_remaining` from the casting
## table. An empty dictionary clears the row, which is what a spare row shows.
func show_slot(view: Dictionary) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_pool = _pool_text(_view)
	_head = _head_text(_view)
	_body = _body_text(_view)
	_readiness = _ready_text(_view)
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
		"active": _castable(),
		"can_cast": _castable() and not _cooling(),
		"cooldown_remaining": _cooldown(),
		"ready": _readiness,
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


## Whether a cast is even OFFERED here: a filled slot whose technique is active. A
## passive is never offerable — `activate` refuses it as `not_active`, and a button
## that can only ever be refused is worse than no button.
func can_cast() -> bool:
	return _castable()


## Give the keyboard and pad a landing spot. Recorded before the grab, because a node
## outside a viewport has nothing to focus yet. The cast button is the landing spot
## when the slot holds something fireable: it is the action, and the release is not.
func focus_initial() -> void:
	_bind_nodes()
	var target := _cast_button if can_cast() else _unequip_button
	if target != null and target.is_inside_tree():
		target.grab_focus()


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
	_ready_label = get_node_or_null("%ReadyLabel") as Label
	_unequip_button = get_node_or_null("%UnequipButton") as Button
	_cast_button = get_node_or_null("%CastButton") as Button
	if _unequip_button != null and not _unequip_button.pressed.is_connected(_on_unequip):
		_unequip_button.pressed.connect(_on_unequip)
	if _cast_button != null and not _cast_button.pressed.is_connected(_on_cast):
		_cast_button.pressed.connect(_on_cast)


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
	if _ready_label != null:
		_ready_label.text = _readiness
		# A bound technique on cooldown is a fact about this moment, not an error:
		# `WarnLabel` would paint a technique that is simply resting as a refusal.
		_ready_label.theme_type_variation = _ready_variation()
		_ready_label.visible = _castable()
	if _unequip_button != null:
		_unequip_button.visible = bool(_view.get("filled", false))
		_unequip_button.disabled = not bool(_view.get("filled", false))
	if _cast_button != null:
		_cast_button.visible = _castable()
		_cast_button.disabled = not bool(summary().get("can_cast", false))
		if _castable():
			_cast_button.tooltip_text = _readiness


## `Ready`, or `Ready in 7s`. Absent for a passive, which has no cooldown to wait
## out — `activate` refuses it, so a countdown would promise a cast that can never
## happen. The rounding is the panel's: a screen passes the raw remainder down.
func _ready_text(view: Dictionary) -> String:
	if not _castable():
		return ""
	var left := _cooldown()
	if left <= 0.0:
		return READY_TEXT
	return "%s in %ds" % [READY_TEXT, int(ceil(left))]


func _ready_variation() -> StringName:
	return &"EffectLabel" if _cooldown() <= 0.0 else &"WarnLabel"


## Seconds still owed on this slot's technique. The screen reads it off the casting
## table and hands it down raw; nothing here re-derives a cooldown.
func _cooldown() -> float:
	return maxf(0.0, float(_view.get("cooldown_remaining", 0.0)))


func _cooling() -> bool:
	return _cooldown() > 0.0


func _castable() -> bool:
	return bool(_view.get("filled", false)) and bool(_view.get("active", false))


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


func _on_cast() -> void:
	# The button is already gated on `can_cast`, but the signal is a public one and a
	# caller may emit it directly; re-checking here keeps a cooldown unreachable from
	# this row whatever the caller does.
	if not can_cast() or technique_id().is_empty():
		return
	cast_requested.emit(technique_id())
