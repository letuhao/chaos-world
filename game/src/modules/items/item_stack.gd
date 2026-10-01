class_name ItemStack
extends RefCounted

## A stack of a stackable item: definition id + quantity (ADR 0007).

var def_id: StringName
var quantity: int


func _init(p_def_id: StringName = &"", p_quantity: int = 0) -> void:
	def_id = p_def_id
	quantity = maxi(0, p_quantity)


func to_dict() -> Dictionary:
	return {"def_id": String(def_id), "quantity": quantity}


static func from_dict(data: Dictionary) -> ItemStack:
	return ItemStack.new(StringName(data.get("def_id", "")), int(data.get("quantity", 0)))
