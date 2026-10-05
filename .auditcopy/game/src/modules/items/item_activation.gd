class_name ItemActivation
extends RefCounted

## Category -> activation channel (ADR 0028). Every item category resolves to
## exactly one channel so a definition's fixed and rolled options always have a
## real consumer. Nothing applies merely because an item is held.

const EQUIPPED := &"equipped"
const CONSUMED := &"consumed"
const LEARNED := &"learned"
const CRAFTED := &"crafted"
const PROPERTY := &"property"

const BY_CATEGORY := {
	ItemCategory.EQUIPMENT: EQUIPPED,
	ItemCategory.CONSUMABLE: CONSUMED,
	ItemCategory.TECHNIQUE: LEARNED,
	ItemCategory.MATERIAL: CRAFTED,
	ItemCategory.KEY: PROPERTY,
	ItemCategory.CURRENCY: PROPERTY,
	ItemCategory.QUEST: PROPERTY,
	ItemCategory.MISC: PROPERTY,
}


static func for_category(category: StringName) -> StringName:
	return BY_CATEGORY.get(category, PROPERTY)
