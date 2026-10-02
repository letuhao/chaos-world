class_name ItemStack
extends RefCounted

## A batch of stackable items sharing one definition and one realization
## (ADR 0025). Merging requires an identical stacking signature, so a rolled
## consumable never absorbs a different roll. Non-stackable items are
## ItemInstances instead, each singly owned.

var def_id: StringName
var quantity: int
## Realized rolled options shared by every unit in this batch. Empty for plain
## content; set for anything whose definition declares a roll specification.
var rolled: Array[Dictionary] = []
var rarity: StringName = &"common"
var realm: StringName = &""
## Live reference to the authored definition (never serialized).
var def_ref: ItemDef = null


func _init(p_def_id: StringName = &"", p_quantity: int = 0) -> void:
	def_id = p_def_id
	quantity = maxi(0, p_quantity)


## Definition, rarity, realm and every realized option/value. Two batches may
## merge only when this matches exactly.
func signature() -> String:
	return ItemStack.signature_of(def_id, rarity, realm, rolled)


## One implementation shared by batches and instances so both agree on what
## "equivalent" means for stacking (ADR 0025).
static func signature_of(
	def_id: StringName, rarity: StringName, realm: StringName, rolled: Array[Dictionary]
) -> String:
	var parts: Array[String] = [String(def_id), String(rarity), String(realm)]
	for effect in rolled:
		(
			parts
			. append(
				(
					"%s:%s:%s:%.4f"
					% [
						effect.get("option_id", ""),
						effect.get("op", ""),
						effect.get("scope", ""),
						float(effect.get("value", 0.0)),
					]
				)
			)
		)
	return "|".join(parts)


## A batch carrying one unit of `instance`'s realization.
static func from_instance(instance: ItemInstance, quantity: int = 1) -> ItemStack:
	var batch := ItemStack.new(instance.def_id, quantity)
	batch.rolled = instance.rolled.duplicate(true)
	batch.rarity = instance.rarity
	batch.realm = instance.realm
	batch.def_ref = instance.def_ref
	return batch


func to_dict() -> Dictionary:
	var rolled_out: Array = []
	for effect in rolled:
		rolled_out.append(effect.duplicate())
	return {
		"def_id": String(def_id),
		"quantity": quantity,
		"rolled": rolled_out,
		"rarity": String(rarity),
		"realm": String(realm),
	}


static func from_dict(data: Dictionary) -> ItemStack:
	var batch := ItemStack.new(StringName(data.get("def_id", "")), int(data.get("quantity", 0)))
	batch.rarity = StringName(data.get("rarity", "common"))
	batch.realm = StringName(data.get("realm", ""))
	for effect in data.get("rolled", []):
		if effect is Dictionary:
			batch.rolled.append(effect)
	return batch
