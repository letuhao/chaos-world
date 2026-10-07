class_name InventoryPanel
extends VBoxContainer

## Inventory listing for the item workbench. A read-only view of the facade's
## inventory: one row per stackable batch, one row per distinct instance, plus
## the actor's slot usage. It never mutates item state — the screen owns every
## action.
##
## It also publishes the COMPARISON: for the selected row, the per-stat delta
## against the item already occupying the slot that row would go into. That is
## the answer to "is this better than what I am wearing", which with hundreds of
## competing wearables and five slots was previously only answerable by hand.
##
## ## Why the comparison is honest about having no counterpart
##
## Most selections have no honest delta: an empty slot has nothing to beat, a
## stack cannot be worn at all, a grade gate means the swap cannot happen, and an
## occupant of a different subtype is not a like-for-like item. Each is a NAMED
## `state`, never a zero-filled row that reads like "no change". A zero delta and
## an absent delta are different facts and the contract keeps them apart.
##
## ## Why `direction` is arithmetic and not a judgement
##
## `up`/`down`/`flat` report the sign of `candidate - equipped` and nothing more.
## Whether a higher number is GOOD depends on the stat — more `crit_resist` helps,
## more `crit_resist_damage` hurts — and this panel holds no catalog of that, so
## it does not pretend to. The renderer colours the sign; the sign carries the
## fact, which is also what makes the reading survive without colour.
##
## Widgets live in `inventory_panel.tscn`; only the data rows are built here,
## because their number follows the actor's contents.

signal selection_changed(row: Dictionary)
## The player pressed Lock on the selected row. The panel holds no item state, so
## it asks and the screen owns the write.
signal lock_requested(instance_id: StringName, locked: bool)

const KIND_INSTANCE := "instance"
const KIND_STACK := "stack"
## Rarity display names. Presentation vocabulary only; gameplay reads the id.
const RARITY_LABELS := {
	&"common": "LOC_UI_PANELS_7DE90A6524",
	&"magic": "LOC_UI_PANELS_E6791BE7EE",
	&"rare": "LOC_UI_PANELS_CCE370D2F9",
	&"legendary": "LOC_UI_PANELS_B7E8916505",
}

## The items module's option target vocabulary, spelled out here exactly as
## `item_action_rules.gd` spells out its activations: `ui/` may not name an items
## type directly, and the gate that catches a mismatch is the `not_equippable`
## path rather than a silent success.
const TARGET_STAT := &"stat"

## The comparison states. Each is a distinct fact about whether a delta exists,
## and a test names the one it means. `none` is the empty contract, so a reader
## never has to distinguish "no comparison" from "no state".
const STATE_NONE := "none"
## The slot is free, so the delta is against nothing: every value is a gain and
## `has_counterpart` is false. The half that only works once something is worn.
const STATE_EMPTY_SLOT := "empty_slot"
## A real occupant of the candidate's own subtype. The only state with a
## counterpart, and the only one that answers "should I swap".
const STATE_COMPARABLE := "comparable"
## The slot holds an item whose subtype is not the candidate's, so the numbers
## are published but answer no question the player asked: it is not the same kind
## of thing to compare against.
const STATE_DIFFERENT_SUBTYPE := "different_subtype"
## The subtype's authored rule refuses the very slot the candidate maps to.
const STATE_WRONG_SLOT := "wrong_slot"
## A stack, or a definition that is not equipment. It cannot be worn at all, so
## there is no equip and no delta.
const STATE_NOT_EQUIPPABLE := "not_equippable"
## The subtype is authored as wearing nowhere — socket material, not apparel.
const STATE_UNWEARABLE := "unwearable"
## The actor's realm tier is below the definition's required tier. The swap is
## refused by gameplay, so a delta would be a promise the facade will not keep.
const STATE_GRADE_GATED := "grade_gated"
## Bound to an actor who is not this one.
const STATE_BOUND_TO_OTHER := "bound_to_other"
## The subtype expresses no slot opinion and the player has chosen none.
const STATE_NO_SLOT := "no_slot"

const DIRECTION_UP := "up"
const DIRECTION_DOWN := "down"
const DIRECTION_FLAT := "flat"

## Wording for each state. This panel owns every `%s` and every `%d` in it — the
## screen hands raw values and never formats one.
const COMPARE_TEXT := {
	STATE_NONE: "LOC_UI_PANELS_74539C002D",
	STATE_EMPTY_SLOT: "LOC_UI_PANELS_A7FA79BE54",
	STATE_COMPARABLE: "LOC_UI_PANELS_120FD3E3C5",
	STATE_DIFFERENT_SUBTYPE: "LOC_UI_PANELS_35789B325D",
	STATE_WRONG_SLOT: "LOC_UI_PANELS_543932CBC8",
	STATE_NOT_EQUIPPABLE: "LOC_UI_PANELS_13586D6A52",
	STATE_UNWEARABLE: "LOC_UI_PANELS_0DDBB1292B",
	STATE_GRADE_GATED: "LOC_UI_PANELS_73319D3B51",
	STATE_BOUND_TO_OTHER: "LOC_UI_PANELS_D60E22AF2A",
	STATE_NO_SLOT: "LOC_UI_PANELS_594E691ACD",
}

## Why the lock control is dark. `lock_unsupported` is the honest one today: the
## module verb the lock needs is not published yet, and a lit button that cannot
## write would be the exact defect this lane exists to fix.
const LOCK_NO_SELECTION := "no_selection"
const LOCK_STACK := "stack_not_lockable"
const LOCK_UNSUPPORTED := "lock_unsupported"
const LOCK_WORN := "already_equipped"

var _actor: Actor
var _rows: Array[Dictionary] = []
var _suppress: bool = false
var _focus_target: String = ""
var _inventory_source: RefCounted = null
var _equipment_source: RefCounted = null
var _header: Label = null
var _list: ItemList = null
## The slot the player will equip into, handed down by the screen so the
## comparison targets the slot an equip would actually use.
var _target_slot: StringName = &""
var _compare: Dictionary = {}
var _lock: Dictionary = {}
var _lock_read: Callable = Callable()
var _lock_write: Callable = Callable()
var _compare_title: Label = null
var _compare_head: Label = null
var _compare_rows: VBoxContainer = null
var _lock_button: Button = null


func _init() -> void:
	_compare = _empty_comparison()
	_lock = _empty_lock()


## Empty contracts for the comparison/lock reads (boot repair, owner: lane-compare lane).
## `_init` calls both but their definitions have not landed yet, which fails this
## file's parse and everything that loads it (`screens/item_workbench.gd` up to the
## boot scene). `STATE_NONE` is the lane's own documented empty contract ("`none` is
## the empty contract"), so these return its shape until the lane fills them in.
func _empty_comparison() -> Dictionary:
	return {"state": STATE_NONE}


func _empty_lock() -> Dictionary:
	return {"state": STATE_NONE}


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
		_header.text = L.t(_header_text())


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
	L.localize_tree(self)
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
	return L.t("LOC_UI_PANELS_646340D28C") % [row["display_name"], int(row["quantity"]), rarity]


func _header_text() -> String:
	return L.t("LOC_UI_PANELS_54885601F8") % [_used_slots(), _capacity()]


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
