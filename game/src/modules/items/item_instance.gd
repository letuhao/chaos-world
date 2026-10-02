class_name ItemInstance
extends RefCounted

## A realized item instance: definition id plus per-instance state — realized
## rolled options, rarity, realm, durability, refinement and binding (ADR 0025).
## Definitions stay shared immutable content; everything mutable lives here.

const SCHEMA_VERSION := 2

var def_id: StringName
var instance_id: StringName
var durability: float = 1.0
var refinement: int = 0
var bound_to: StringName = &""
## Realized rolled options, in roll order. Each entry is the normalized effect
## shape produced by OptionCatalog: option_id, target_type, target_id, scope,
## op, unit, value, channel, label, family.
var rolled: Array[Dictionary] = []
var rarity: StringName = &"common"
## The canonical 30-realm id this instance was rolled for; stable id, not index.
var realm: StringName = &""
## Generator provenance so a re-load never re-rolls or re-interprets (ADR 0027).
var catalog_version: int = 0
var seed: int = 0
## The authored definition this instance was realized from. Kept as a live
## reference (never serialized) so consumers resolve the real definition
## without a second lookup.
var def_ref: ItemDef = null


func _init(p_def_id: StringName = &"", p_instance_id: StringName = &"") -> void:
	def_id = p_def_id
	instance_id = p_instance_id


## Full stacking signature: two instances merge only when every realized value
## matches, so a rolled consumable never silently absorbs a different roll.
func stacking_signature() -> String:
	return ItemStack.signature_of(def_id, rarity, realm, rolled)


func signature() -> String:
	return stacking_signature()


func signature_matches(other: ItemInstance) -> bool:
	return other != null and stacking_signature() == other.stacking_signature()


func to_dict() -> Dictionary:
	var rolled_out: Array = []
	for effect in rolled:
		rolled_out.append(effect.duplicate())
	return {
		"version": SCHEMA_VERSION,
		"def_id": String(def_id),
		"instance_id": String(instance_id),
		"durability": durability,
		"refinement": refinement,
		"bound_to": String(bound_to),
		"rarity": String(rarity),
		"realm": String(realm),
		"rolled": rolled_out,
		"catalog_version": catalog_version,
		"seed": seed,
	}


static func from_dict(data: Dictionary) -> ItemInstance:
	var instance := ItemInstance.new(
		StringName(data.get("def_id", "")), StringName(data.get("instance_id", ""))
	)
	instance.durability = float(data.get("durability", 1.0))
	instance.refinement = int(data.get("refinement", 0))
	instance.bound_to = StringName(data.get("bound_to", ""))
	instance.rarity = StringName(data.get("rarity", "common"))
	instance.realm = StringName(data.get("realm", ""))
	instance.catalog_version = int(data.get("catalog_version", 0))
	instance.seed = int(data.get("seed", 0))
	for effect in data.get("rolled", []):
		if effect is Dictionary:
			instance.rolled.append(effect)
	return instance


## v1 payloads carried bare affix ids with no realized values. They are kept as
## ids only; a legacy affix is never silently reinterpreted into a new effect.
static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 1))
	if version >= SCHEMA_VERSION:
		return data
	var migrated := data.duplicate(true)
	migrated["version"] = SCHEMA_VERSION
	migrated["rarity"] = String(data.get("rarity", "common"))
	migrated["realm"] = String(data.get("realm", ""))
	migrated["rolled"] = []
	migrated["catalog_version"] = int(data.get("catalog_version", 0))
	migrated["seed"] = 0
	return migrated
