class_name SocketSlotRow
extends PanelContainer

## One socket slot, rendered from the read model a screen hands over.
##
## The row keeps the slot's own modifiers visibly separate from the socket item
## seated in it, because they behave differently: the slot's survive the item,
## the item's do not. It owns every `%d` and `%.2f` — a screen passes raw values.
##
## Contract: `summary()` is the testable surface.

const UNIT_PRECISION := {"magnitude": 2, "rate": 2, "fraction": 2}

var _state: Dictionary = {}
var _head_label: Label = null
var _kind_label: Label = null
var _imprint_title: Label = null
var _imprint_rows: VBoxContainer = null
var _gem_title: Label = null
var _gem_rows: VBoxContainer = null
var _gem_enchant_title: Label = null
var _gem_enchant_label: Label = null
var _empty_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one slot. An empty dictionary renders the row as absent, which is what
## a socket-less item shows.
func show_slot(slot: Dictionary) -> void:
	_bind_nodes()
	if slot.is_empty():
		_state = _empty_state()
	else:
		_state = _filled_state(slot)
	_render()


## What this row currently shows. Primitives only.
func summary() -> Dictionary:
	return _state.duplicate(true)


## Resolve the scene's widgets on first use rather than in `@onready`: the
## headless suite runner drives this panel before a scene tree exists, so
## `_ready()` is not a dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_kind_label = get_node_or_null("%KindLabel") as Label
	_imprint_title = get_node_or_null("%ImprintTitle") as Label
	_imprint_rows = get_node_or_null("%ImprintRows") as VBoxContainer
	_gem_title = get_node_or_null("%GemTitle") as Label
	_gem_rows = get_node_or_null("%GemRows") as VBoxContainer
	_gem_enchant_title = get_node_or_null("%GemEnchantTitle") as Label
	_gem_enchant_label = get_node_or_null("%GemEnchantLabel") as Label
	_empty_label = get_node_or_null("%EmptyLabel") as Label


func _empty_state() -> Dictionary:
	return {
		"has_slot": false,
		"index": -1,
		"kind": "",
		"occupied": false,
		"imputed_count": 0,
		"imputed_lines": [],
		"gem_def_id": "",
		"gem_display_name": "",
		"gem_rarity": "",
		"gem_effect_count": 0,
		"gem_lines": [],
		"gem_enchantment_line": "",
		"effect_line_count": 0,
		"head": "",
		"kind_line": "",
	}


func _filled_state(slot: Dictionary) -> Dictionary:
	var imputed := _lines(slot.get("imputed", []))
	var gem_effects := _lines(slot.get("gem_effects", []))
	var gem_enchant := _line(slot.get("gem_enchantment", {}))
	var index := int(slot.get("index", 0))
	var kind := String(slot.get("kind", ""))
	var gem_name := String(slot.get("gem_display_name", ""))
	return {
		"has_slot": true,
		"index": index,
		"kind": kind,
		"occupied": bool(slot.get("occupied", false)),
		"imputed_count": imputed.size(),
		"imputed_lines": imputed,
		"gem_def_id": String(slot.get("gem_def_id", "")),
		"gem_display_name": gem_name,
		"gem_rarity": String(slot.get("gem_rarity", "")),
		"gem_effect_count": gem_effects.size(),
		"gem_lines": gem_effects,
		"gem_enchantment_line": gem_enchant,
		"effect_line_count": imputed.size() + gem_effects.size() + (1 if gem_enchant != "" else 0),
		"head": "Socket slot %d of %d" % [index + 1, 2],
		"kind_line": "Kind: %s — %s" % [kind, _occupancy_text(slot)],
	}


func _occupancy_text(slot: Dictionary) -> String:
	if not bool(slot.get("occupied", false)):
		return "empty"
	return (
		"holds %s (%s)"
		% [
			String(slot.get("gem_display_name", "")),
			String(slot.get("gem_rarity", "")),
		]
	)


## One readable line per effect. The value window travels on the effect itself,
## so this row never restates the magnitude policy.
func _lines(effects: Array) -> Array:
	var out: Array = []
	for effect in effects:
		var line := _line(effect)
		if line != "":
			out.append(line)
	return out


func _line(effect: Variant) -> String:
	if not effect is Dictionary:
		return ""
	var source: Dictionary = effect
	if source.is_empty():
		return ""
	var unit := String(source.get("unit", "magnitude"))
	var shown := _value(float(source.get("value", 0.0)), unit)
	var rendered := "%s  %s" % [String(source.get("label", source.get("option_id", ""))), shown]
	if not source.has("value_min") or not source.has("value_max"):
		return rendered
	return (
		"%s  (%s - %s)"
		% [
			rendered,
			_value(float(source["value_min"]), unit),
			_value(float(source["value_max"]), unit),
		]
	)


func _value(value: float, unit: String) -> String:
	return "%.2f" % value if int(UNIT_PRECISION.get(unit, 2)) > 0 else "%d" % int(value)


func _render() -> void:
	if _head_label == null:
		return
	var present := bool(_state["has_slot"])
	visible = present
	if not present:
		return
	_head_label.text = String(_state["head"])
	_kind_label.text = String(_state["kind_line"])
	_imprint_title.text = "Slot modifiers (%d)" % int(_state["imputed_count"])
	_fill(_imprint_rows, _state["imputed_lines"])
	_gem_title.text = "Socket item modifiers (%d)" % int(_state["gem_effect_count"])
	_fill(_gem_rows, _state["gem_lines"])
	_gem_enchant_label.text = String(_state["gem_enchantment_line"])
	_gem_enchant_title.visible = String(_state["gem_enchantment_line"]) != ""
	_gem_enchant_label.visible = String(_state["gem_enchantment_line"]) != ""
	_empty_label.visible = not bool(_state["occupied"])


func _fill(box: VBoxContainer, lines: Array) -> void:
	if box == null:
		return
	for child in box.get_children():
		box.remove_child(child)
		child.free()
	for line in lines:
		var label := Label.new()
		label.text = String(line)
		label.theme_type_variation = &"EffectLabel"
		box.add_child(label)
