class_name ItemDetailPanel
extends PanelContainer

## Detail view for the inventory row the player selected: identity, grade,
## rarity, realm requirement, the item's fixed options, the instance's rolled
## affixes with their effective bound ranges, and what using it would do.
##
## Everything rendered here comes from the entry dictionary the screen hands over
## — a read-only projection built from the facade. `summary()` is the testable
## surface; headless tests assert it instead of pixels.

const SCOPE_CURRENT := &"current"
const TARGET_PROPERTY := &"property"
const TARGET_RESOURCE := &"resource"
## Rarity display vocabulary. Presentation only; gameplay reads the rarity id.
const RARITY_LABELS := {
	&"common": "LOC_UI_PANELS_7DE90A6524",
	&"magic": "LOC_UI_PANELS_E6791BE7EE",
	&"rare": "LOC_UI_PANELS_CCE370D2F9",
	&"legendary": "LOC_UI_PANELS_B7E8916505",
}

var _fixed_lines: Array = []
var _rolled_lines: Array = []
var _restores: Dictionary = {}
var _properties: Dictionary = {}
var _header: String = ""
var _meta: String = ""
var _state: Dictionary = {}
var _name_label: Label = null
var _meta_label: Label = null
var _instance_label: Label = null
var _fixed_title: Label = null
var _fixed_rows: VBoxContainer = null
var _rolled_title: Label = null
var _rolled_rows: VBoxContainer = null
var _use_title: Label = null
var _use_label: Label = null


func _init() -> void:
	_state = _empty_state()


func _ready() -> void:
	_bind_nodes()
	clear()


## Render `entry`, the selected inventory row. An empty dictionary clears the
## panel, which is what an empty inventory shows.
func show_entry(entry: Dictionary) -> void:
	_bind_nodes()
	if entry.is_empty() or entry.get("def") == null:
		clear()
		return
	var def: Resource = entry["def"]
	_fixed_lines = _fixed_lines_for(def)
	_rolled_lines = _rolled_lines_for(entry)
	_restores = {}
	_properties = {}
	_accumulate(def.effects(null), entry.get("rolled", []))
	_header = String(entry.get("display_name", def.id))
	_meta = _meta_text(def, entry)
	_state = _filled_state(def, entry)
	_render()


## Empty the panel and reset the snapshot, so a caller never reads a stale item.
func clear() -> void:
	_bind_nodes()
	_fixed_lines = []
	_rolled_lines = []
	_restores = {}
	_properties = {}
	_header = ""
	_meta = ""
	_state = _empty_state()
	_render()


## What the detail panel currently shows. Values are primitives only.
func summary() -> Dictionary:
	return _state.duplicate()


## Give the keyboard and pad a landing spot inside this panel. The name label is
## not focusable, so the rolled affix rows own the keyboard here.
func focus_initial() -> void:
	_bind_nodes()
	if _rolled_rows != null:
		_rolled_rows.grab_focus()


## Resolve the scene's widgets on first use rather than in `@onready`: the
## headless suite runner drives this panel before a scene tree exists, so
## `_ready()` is not a dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _name_label != null:
		return
	_name_label = get_node_or_null("%NameLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label
	_instance_label = get_node_or_null("%InstanceLabel") as Label
	_fixed_title = get_node_or_null("%FixedTitle") as Label
	_fixed_rows = get_node_or_null("%FixedRows") as VBoxContainer
	_rolled_title = get_node_or_null("%RolledTitle") as Label
	_rolled_rows = get_node_or_null("%RolledRows") as VBoxContainer
	_use_title = get_node_or_null("%UseTitle") as Label
	_use_label = get_node_or_null("%UseLabel") as Label


func _empty_state() -> Dictionary:
	return {
		"has_selection": false,
		"def_id": "",
		"display_name": "",
		"category": "",
		"subtype": "",
		"grade": "",
		"rarity": "",
		"rarity_label": "",
		"realm": "",
		"required_tier": 0,
		"activation": "",
		"stackable": false,
		"quantity": 0,
		"instance_id": "",
		"equipped_slot": "",
		"durability": 1.0,
		"refinement": 0,
		"bound_to": "",
		"fixed_count": 0,
		"rolled_count": 0,
		"effect_line_count": 0,
		"fixed_lines": [],
		"rolled_lines": [],
		"restores": {},
		"properties": {},
	}


func _filled_state(def: Resource, entry: Dictionary) -> Dictionary:
	return {
		"has_selection": true,
		"def_id": String(def.id),
		"display_name": _header,
		"category": String(def.category),
		"subtype": String(def.subcategory),
		"grade": String(def.grade),
		"rarity": String(def.rarity),
		"rarity_label": _rarity_label(def.rarity),
		"realm": String(def.realm),
		"required_tier": def.required_tier(),
		"activation": String(def.activation()),
		"stackable": bool(def.stackable),
		"quantity": int(entry.get("quantity", 0)),
		"instance_id": String(entry.get("instance_id", "")),
		"equipped_slot": String(entry.get("slot", "")),
		"durability": float(entry.get("durability", 1.0)),
		"refinement": int(entry.get("refinement", 0)),
		"bound_to": String(entry.get("bound_to", "")),
		"fixed_count": _fixed_lines.size(),
		"rolled_count": _rolled_lines.size(),
		"effect_line_count": _fixed_lines.size() + _rolled_lines.size(),
		"fixed_lines": _fixed_lines.duplicate(),
		"rolled_lines": _rolled_lines.duplicate(),
		"restores": _restores.duplicate(),
		"properties": _properties.duplicate(),
	}


## Fixed (item-authored) options, read through the definition's own aggregation
## path so the UI shows exactly the options gameplay would apply.
func _fixed_lines_for(def: Resource) -> Array:
	var lines: Array = []
	for effect in def.effects(null):
		if String(effect.get("channel", "")) != "fixed":
			continue
		lines.append(_line(effect))
	return lines


## Rolled affixes with their realized value and the effective window the roll was
## drawn from.
func _rolled_lines_for(entry: Dictionary) -> Array:
	var lines: Array = []
	for effect in entry.get("rolled", []):
		lines.append(_line(effect))
	return lines


## Renders `label  value  (min - max)`. The window comes from the effect itself:
## the items module annotates every resolved effect with the value range that was
## legal under the item's realm and rarity, so this panel never restates the
## magnitude policy and cannot drift from it.
func _line(effect: Dictionary) -> String:
	var label := String(effect.get("label", effect.get("option_id", "")))
	var rendered := "%s  %.2f" % [label, float(effect.get("value", 0.0))]
	if not effect.has("value_min") or not effect.has("value_max"):
		return rendered
	return (
		L.t("LOC_UI_PANELS_BE5189DF00")
		% [rendered, float(effect["value_min"]), float(effect["value_max"])]
	)


## One-shot restorations and numeric item properties the selection carries. Both
## are reported, never applied — the screen owns every mutation.
func _accumulate(fixed: Array, rolled: Array) -> void:
	for effect in fixed:
		_accumulate_one(effect)
	for effect in rolled:
		_accumulate_one(effect)


func _accumulate_one(effect: Dictionary) -> void:
	var target_type := StringName(effect.get("target_type", &""))
	var target := String(effect.get("target_id", ""))
	var value := float(effect.get("value", 0.0))
	if target_type == TARGET_RESOURCE and StringName(effect.get("scope", &"")) == SCOPE_CURRENT:
		_restores[target] = float(_restores.get(target, 0.0)) + value
	elif target_type == TARGET_PROPERTY:
		_properties[target] = float(_properties.get(target, 0.0)) + value


func _meta_text(def: Resource, entry: Dictionary) -> String:
	var realm: String = "any" if def.realm == &"" else String(def.realm)
	var parts: Array = [
		"%s / %s" % [def.category, def.subcategory],
		"grade %s (tier %d)" % [def.grade, def.required_tier()],
		"%s rarity" % _rarity_label(def.rarity),
		"realm %s" % realm,
		"activates on %s" % def.activation(),
	]
	if String(entry.get("slot", "")) != "":
		parts.append("equipped in %s" % entry["slot"])
	return " | ".join(parts)


func _rarity_label(rarity: StringName) -> String:
	# The vocabulary holds KEYS, so this is where they resolve — one place, before `summary()`.
	return L.t(String(RARITY_LABELS.get(rarity, RARITY_LABELS[&"common"])))


func _render() -> void:
	if _name_label == null:
		return
	_name_label.text = L.t(_header if _header != "" else "No item selected")
	_meta_label.text = L.t(_meta)
	_instance_label.text = L.t(_instance_text())
	_fill(_fixed_rows, _fixed_lines)
	_fill(_rolled_rows, _rolled_lines)
	_fixed_title.text = L.t("LOC_UI_PANELS_DBB9ED6843") % _fixed_lines.size()
	_rolled_title.text = L.t("LOC_UI_PANELS_B7F3769602") % _rolled_lines.size()
	var use_text := _use_text()
	_use_title.visible = not use_text.is_empty()
	_use_label.text = L.t(use_text)


func _instance_text() -> String:
	if not bool(_state.get("has_selection", false)):
		return ""
	var parts: Array = ["x%d" % int(_state["quantity"])]
	if String(_state["instance_id"]) != "":
		parts.append("instance %s" % _state["instance_id"])
	parts.append("durability %.2f" % float(_state["durability"]))
	parts.append("refinement %d" % int(_state["refinement"]))
	if String(_state["bound_to"]) != "":
		parts.append("bound to %s" % _state["bound_to"])
	return " | ".join(parts)


func _use_text() -> String:
	var parts: Array = []
	for pool in _restores.keys():
		parts.append("restores %s %.2f" % [pool, float(_restores[pool])])
	for property_id in _properties.keys():
		parts.append("%s %.2f" % [property_id, float(_properties[property_id])])
	return ", ".join(parts)


func _fill(box: VBoxContainer, lines: Array) -> void:
	if box == null:
		return
	for child in box.get_children():
		box.remove_child(child)
		child.free()
	for line in lines:
		var label := Label.new()
		label.text = L.t(line)
		label.theme_type_variation = &"EffectLabel"
		box.add_child(label)
