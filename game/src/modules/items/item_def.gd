class_name ItemDef
extends Resource

## Data-driven item definition (ADR 0007). Author as a `.tres`; no code needed to
## add an item.

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: StringName = ItemCategory.MISC
@export var subcategory: StringName = &""
@export var grade: StringName = ItemGrade.MORTAL
@export var stackable: bool = true
@export var max_stack: int = 99
@export var value: int = 0
@export var tags: Array[StringName] = []
@export var sources: Array[StringName] = []
@export var description: String = ""
@export var flat_modifiers: Dictionary = {}
@export var percent_modifiers: Dictionary = {}
# Rarity controls option counts, affix structure, magnitude budgets, and socket
# limits (ADR 0025). Separate from grade and realm.
@export var rarity: StringName = &"common"
# The canonical 30-realm id this item belongs to; drives eligibility and roll
# magnitude. Saved as a stable id, not a display name.
@export var realm: StringName = &""
# Fixed modifiers reference master option ids with item-authored fixed values
# (ADR 0025): [{option_id: &"...", value: float}, ...].
@export var fixed_modifiers: Array[Dictionary] = []
# Roll specification references a derived pool with count/budget and eligible
# affix positions (ADR 0025): {pool_id, count, contexts}.
@export var roll_spec: Dictionary = {}


func is_equipment() -> bool:
	return category == ItemCategory.EQUIPMENT


func required_tier() -> int:
	return ItemGrade.required_tier(grade)


func rarity_tier() -> int:
	return OptionCatalog.rarity_tier(rarity)


## Build fixed modifiers from master option references (ADR 0025). Each entry
## is {option_id, value}; the option's target stat and op come from the catalog.
func build_fixed_modifiers(source: StringName) -> Array[StatModifier]:
	var modifiers: Array[StatModifier] = []
	for entry in fixed_modifiers:
		var option_id := StringName(entry.get("option_id", ""))
		if option_id == &"":
			continue
		var record: Dictionary = OptionCatalog.instance().option_record(option_id)
		if record.is_empty():
			continue
		var value := float(entry.get("value", 0.0))
		var op: Stat.Op
		match String(record.get("op", "FLAT")):
			"FLAT":
				op = Stat.Op.FLAT
			"PERCENT":
				op = Stat.Op.PERCENT
			_:
				op = Stat.Op.MULT
		var target: Dictionary = record.get("target", {})
		modifiers.append(
			StatModifier.new(StringName(target.get("id", option_id)), op, value, source)
		)
	return modifiers


func build_modifiers(source: StringName) -> Array[StatModifier]:
	var modifiers: Array[StatModifier] = []
	for key in flat_modifiers.keys():
		modifiers.append(
			StatModifier.new(StringName(key), Stat.Op.FLAT, float(flat_modifiers[key]), source)
		)
	for key in percent_modifiers.keys():
		modifiers.append(
			StatModifier.new(
				StringName(key), Stat.Op.PERCENT, float(percent_modifiers[key]), source
			)
		)
	return modifiers
