class_name InventoryPanel
extends VBoxContainer

## Inventory listing for the item workbench. A read-only view of the facade's
## inventory: one row per stackable batch, one row per distinct instance, plus
## the actor's slot usage. It never mutates item state — the screen owns every
## action.
##
## Widgets live in `inventory_panel.tscn`; only the data rows are built here,
## because their number follows the actor's contents.

signal selection_changed(row: Dictionary)

const KIND_INSTANCE := "instance"
const KIND_STACK := "stack"
## Rarity display names. Presentation vocabulary only; gameplay reads the id.
const RARITY_LABELS := {
	&"common": "Common",
	&"magic": "Magic",
	&"rare": "Rare",
	&"legendary": "Legendary",
}

var _actor: Actor
var _rows: Array[Dictionary] = []
var _suppress: bool = false
var _focus_target: String = ""
var _inventory_source: RefCounted = null
var _equipment_source: RefCounted = null
var _header: Label = null
var _list: ItemList = null


func _ready() -> void:
	_bind_nodes()
	refresh()


## Point the listing at `actor` and follow its inventory/equipment signals.
## Safe to call again: the previous sources are disconnected first.
func bind(actor: Actor) -> void:
	_bind_nodes()
	_disconnect()
	_actor = actor
	if _actor == null:
		return
	var inventory := ItemsApi.inventory(_actor)
	if inventory != null:
		_inventory_source = inventory
		inventory.changed.connect(_on_inventory_changed)
	var equipment := ItemsApi.equipment(_actor)
	if equipment != null:
		_equipment_source = equipment
		equipment.changed.connect(_on_inventory_changed)
	refresh()


## Rebuild every row from the facade, keeping the current selection when its row
## still exists and falling back to the first row otherwise.
func refresh() -> void:
	_bind_nodes()
	if _list == null:
		return
	var keep := selection_key()
	_rows = _build_rows()
	_suppress = true
	_list.clear()
	for row in _rows:
		_list.add_item(_row_text(row))
		_list.set_item_metadata(_list.get_item_count() - 1, row)
	_select_key(keep)
	_suppress = false
	if _header != null:
		_header.text = _header_text()


## The selected row, or an empty dictionary when nothing is selected. Carries
## the authored definition and the realized rolls the detail panel renders; it is
## an internal handoff, so `summary()` exposes primitives instead.
func selected_row() -> Dictionary:
	_bind_nodes()
	if _list == null:
		return {}
	var picked := _list.get_selected_items()
	if picked.is_empty():
		return {}
	var index: int = picked[0]
	if index < 0 or index >= _rows.size():
		return {}
	return _rows[index]


## Stable key of the current selection, or "" when nothing is selected.
func selection_key() -> String:
	return String(selected_row().get("key", ""))


## Select the row whose key is `key`. Returns false when no such row exists.
func select_key(key: String) -> bool:
	refresh()
	return _select_key(key)


## What the listing currently shows: row counts, the selected row, and the rows
## themselves as plain ids. Headless tests assert this instead of pixels.
func summary() -> Dictionary:
	_bind_nodes()
	var row := selected_row()
	var keys: Array = []
	var def_ids: Array = []
	for entry in _rows:
		keys.append(entry["key"])
		def_ids.append(entry["def_id"])
	return {
		"rows": _rows.size(),
		"stacks": _count_of(KIND_STACK),
		"instances": _count_of(KIND_INSTANCE),
		"used": _used_slots(),
		"capacity": _capacity(),
		"empty": _rows.is_empty(),
		"has_selection": not row.is_empty(),
		"selected_key": String(row.get("key", "")),
		"selected_def_id": String(row.get("def_id", "")),
		"selected_kind": String(row.get("kind", "")),
		"selected_quantity": int(row.get("quantity", 0)),
		"row_keys": keys,
		"row_def_ids": def_ids,
		"header": "" if _header == null else _header.text,
		"focus_target": _focus_target,
	}


## Give the keyboard and pad a landing spot inside this panel. The target is
## recorded first: focus routing is the contract, and a node outside a viewport
## has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	_focus_target = "" if _list == null else String(_list.name)
	if _list != null and _list.is_inside_tree():
		_list.grab_focus()


## Resolve the scene's widgets on first use rather than in `@onready`: the
## headless suite runner drives this panel before a scene tree exists, so
## `_ready()` is not a dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	if _list != null:
		return
	_list = get_node_or_null("%ItemList") as ItemList
	_header = get_node_or_null("%HeaderLabel") as Label
	if _list != null and not _list.item_selected.is_connected(_on_item_selected):
		_list.item_selected.connect(_on_item_selected)


func _build_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _actor == null:
		return out
	var inventory := ItemsApi.inventory(_actor)
	if inventory == null:
		return out
	for batch in inventory.stacks():
		# A roll-bearing definition can hold several batches under one id, so the
		# selection key is the stacking signature: distinct rolls, distinct rows.
		out.append(
			_row(
				KIND_STACK,
				String(batch.signature()),
				batch.def_id,
				batch.def_ref,
				batch.quantity,
				batch.rarity,
				batch.realm,
				""
			)
		)
	for instance in inventory.instances():
		out.append(
			_row(
				KIND_INSTANCE,
				String(instance.instance_id),
				instance.def_id,
				instance.def_ref,
				1,
				instance.rarity,
				instance.realm,
				_slot_of(instance.instance_id),
				instance
			)
		)
	return out


func _row(
	kind: String,
	key: String,
	def_id: StringName,
	def: Resource,
	quantity: int,
	rarity: StringName,
	realm: StringName,
	slot: String,
	instance: RefCounted = null
) -> Dictionary:
	var name := String(def_id)
	var subtype := ""
	if def != null:
		if def.display_name != "":
			name = def.display_name
		subtype = String(def.subcategory)
	var row := {
		"key": key,
		"kind": kind,
		"def_id": String(def_id),
		"instance_id": "" if instance == null else String(instance.instance_id),
		"def": def,
		"quantity": quantity,
		"rarity": rarity,
		"realm": realm,
		"display_name": name,
		"rolled": [],
		"durability": 1.0,
		"refinement": 0,
		"bound_to": "",
		"subtype": subtype,
		"slot": slot,
	}
	if instance == null:
		return row
	row["rolled"] = instance.rolled
	row["durability"] = instance.durability
	row["refinement"] = instance.refinement
	row["bound_to"] = String(instance.bound_to)
	return row


func _row_text(row: Dictionary) -> String:
	var rarity := String(RARITY_LABELS.get(StringName(row["rarity"]), "Common"))
	return "%-26s x%-4d %s" % [row["display_name"], int(row["quantity"]), rarity]


func _header_text() -> String:
	return "Inventory  %d / %d slots" % [_used_slots(), _capacity()]


func _slot_of(instance_id: StringName) -> String:
	if _actor == null or instance_id == &"":
		return ""
	var equipment := ItemsApi.equipment(_actor)
	if equipment == null:
		return ""
	var slots: Dictionary = equipment.all()
	for slot in slots.keys():
		var equipped: RefCounted = slots[slot]
		if equipped != null and equipped.instance_id == instance_id:
			return String(slot)
	return ""


func _select_key(key: String) -> bool:
	if _rows.is_empty():
		return false
	var index := _index_of(key)
	if index < 0:
		index = 0
	if _list.get_selected_items().size() == 1 and int(_list.get_selected_items()[0]) == index:
		return true
	_list.select(index)
	_list.ensure_current_is_visible()
	return true


func _index_of(key: String) -> int:
	for index in _rows.size():
		if String(_rows[index]["key"]) == key:
			return index
	return -1


func _count_of(kind: String) -> int:
	var total := 0
	for row in _rows:
		if String(row["kind"]) == kind:
			total += 1
	return total


func _used_slots() -> int:
	if _actor == null:
		return 0
	var inventory := ItemsApi.inventory(_actor)
	return 0 if inventory == null else inventory.used_slots()


func _capacity() -> int:
	if _actor == null:
		return 0
	var inventory := ItemsApi.inventory(_actor)
	return 0 if inventory == null else inventory.capacity


func _disconnect() -> void:
	for source in [_inventory_source, _equipment_source]:
		if source != null and source.changed.is_connected(_on_inventory_changed):
			source.changed.disconnect(_on_inventory_changed)
	_inventory_source = null
	_equipment_source = null


func _on_inventory_changed() -> void:
	refresh()


func _on_item_selected(_index: int) -> void:
	if _suppress:
		return
	selection_changed.emit(selected_row())
