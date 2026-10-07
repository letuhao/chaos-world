class_name PartnerRow
extends PanelContainer

## One partner in the relationship screen: name, bond class, emotional signature,
## standing, trust. Formats all numbers here, not in the screen.
##
## `summary()` is the testable surface. `{}` when the row carries nothing.

const CARD_PARTNER := &"PartnerCard"
const CARD_LOCKED := &"LockedCard"

var _view: Dictionary = {}
var _head_label: Label = null
var _bond_label: Label = null
var _signature_label: Label = null
var _meta_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one partner as `CollectionApi.summary(actor)["partners"]` publishes it.
func show_partner(view: Dictionary) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_render()


func clear() -> void:
	show_partner({})


## Everything the row shows, primitives only. `{}` when the row carries nothing.
func summary() -> Dictionary:
	_bind_nodes()
	if not is_filled():
		return {}
	return {
		"partner_id": String(_view.get("partner_id", "")),
		"display_name": String(_view.get("display_name", "")),
		"bond_class": String(_view.get("bond_class", "")),
		"emotional_signature": String(_view.get("emotional_signature", "")),
		"standing": float(_view.get("standing", 0.0)),
		"trust": float(_view.get("trust", 0.0)),
		"is_active": bool(_view.get("is_active", false)),
		"card_tone": String(_view.get("card_tone", "")),
	}


func is_filled() -> bool:
	return not _view.is_empty()


func focus_initial() -> void:
	_bind_nodes()
	if is_inside_tree():
		grab_focus()


func _bind_nodes() -> void:
	L.localize_tree(self)
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_bond_label = get_node_or_null("%BondLabel") as Label
	_signature_label = get_node_or_null("%SignatureLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	if not visible:
		return
	theme_type_variation = _card_variation()
	_head_label.text = String(_view.get("display_name", ""))
	_bond_label.text = String(_view.get("bond_class", ""))
	_signature_label.text = String(_view.get("emotional_signature", ""))
	_meta_label.text = _meta()


func _card_variation() -> StringName:
	return CARD_PARTNER if is_filled() else CARD_LOCKED


func _meta() -> String:
	return (
		"Standing %.1f · Trust %.2f"
		% [
			float(_view.get("standing", 0.0)),
			float(_view.get("trust", 0.0)),
		]
	)
