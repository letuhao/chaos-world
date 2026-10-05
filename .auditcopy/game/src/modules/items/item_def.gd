class_name ItemDef
extends Resource

## Data-driven item definition (ADR 0007/0025). Author as a `.tres`; no code is
## needed to add an item. Every definition carries item-authored fixed modifiers
## referencing master option ids plus a roll specification; the legacy raw
## stat→value maps are gone, replaced by the master catalog (ADR 0025).

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: StringName = ItemCategory.MISC
@export var subcategory: StringName = &""
@export var grade: StringName = ItemGrade.MORTAL
@export var stackable: bool = true
@export var max_stack: int = 99
@export var tags: Array[StringName] = []
@export var sources: Array[StringName] = []
@export var description: String = ""
# Rarity controls option counts, affix structure, magnitude budgets and socket
# limits (ADR 0025). Separate from grade and realm.
@export var rarity: StringName = &"common"
# The canonical 30-realm id this item belongs to; drives eligibility and roll
# magnitude. Saved as a stable id, not a display name.
@export var realm: StringName = &""
# Fixed modifiers reference master option ids with item-authored fixed values
# (ADR 0025): [{option_id: &"...", value: float}, ...].
@export var fixed_modifiers: Array[Dictionary] = []
# Roll specification references a derived pool with count/budget and eligible
# affix positions (ADR 0025): {count: int, contexts: [...]}.
@export var roll_spec: Dictionary = {}

## Optional requirement profile (ADR 0052). Null or empty means no restriction:
## requirements are opt-in, and rarity never implies demand.
@export var requirement: ItemRequirement = null
## The ONE mitigation lever this consumable answers, or `&""` when it answers none.
## Empty on every one of the 3000-odd authored items; `cleanse` is the verb that spends
## it. See `ItemUse.CLEANSE_LEVER_FIELD` for why it is a named field rather than a key
## dug out of `fixed_modifiers`, and ADR 0107 for the deferral it discharged.
@export var cleanse_lever: StringName = &""


func is_equipment() -> bool:
	return category == ItemCategory.EQUIPMENT


## The wearable slots this definition's subtype may occupy, or `[]` when the
## authored rule has no opinion (or rules the subtype to wear nowhere).
##
## Read through the definition rather than through `Equipment` so any module
## holding content can ask where a subtype goes without reaching into another
## module's internals. `Equipment.slots_for` is the same answer for the same
## definition; this is the value-object spelling of it.
func wearable_slots() -> Array[StringName]:
	return ItemSlots.for_subtype(subcategory)


## Whether a body may wear this definition at all. False only for a subtype the
## authored rule places in no wearable slot — socket material, chiefly.
func is_wearable() -> bool:
	return ItemSlots.is_wearable(subcategory)


func required_tier() -> int:
	return ItemGrade.required_tier(grade)


## Activation channel for this definition's fixed and rolled options (ADR 0028).
## Derived from category so no item applies effects merely by being held.
func activation() -> StringName:
	return ItemActivation.for_category(category)


## Whether this definition can carry rolled modifiers at all.
func is_rollable() -> bool:
	return not roll_spec.is_empty() and ItemRarity.affix_count(rarity) > 0


## Normalized effects for this definition plus an optional realized instance.
## One aggregation path: fixed, rolled and later socket/set/enchantment channels
## all funnel here so each effect is applied exactly once (ADR 0026/0028). Every
## returned effect carries the value window it could legally have taken under
## this item's realm and rarity, so readers never restate the magnitude policy.
func effects(instance: ItemInstance = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var catalog := OptionCatalog.instance()
	for entry in fixed_modifiers:
		var option_id := StringName(entry.get("option_id", ""))
		if option_id == &"":
			continue
		if not catalog.allows_activation(option_id, activation()):
			continue
		var effect := catalog.fixed_effect(option_id, float(entry.get("value", 0.0)))
		if not effect.is_empty():
			out.append(effect)
	if instance != null:
		out.append_array(instance.rolled)
	var rarity := instance.rarity if instance != null else rarity
	var realm := instance.realm if instance != null and instance.realm != &"" else realm
	return catalog.with_bounds(out, realm, rarity)


## Total value of a numeric item property (crafting potency/yield) across this
## definition and its instance. Read by Crafting (ADR 0028).
func property_total(instance: ItemInstance, property_id: StringName) -> float:
	return ItemEffects.property_value(effects(instance), property_id)
