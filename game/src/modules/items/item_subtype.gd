class_name ItemSubtype
extends RefCounted

## Common item subtypes (ADR 0007). Subtypes are open StringNames; these defaults
## give content and code a shared vocabulary.

# material
const HERB := &"herb"
const ORE := &"ore"
const BEAST_CORE := &"beast_core"
const ESSENCE := &"essence"

# consumable
const PILL := &"pill"
const ELIXIR := &"elixir"
const TALISMAN := &"talisman"
const FOOD := &"food"

# equipment
const WEAPON := &"weapon"
const ARMOR := &"armor"
const ACCESSORY := &"accessory"
const ARTIFACT := &"artifact"
# Equipment subtypes the content tree authors beyond the four above. Naming them
# here keeps the vocabulary honest: a subtype nobody declares is a subtype the
# slot rule has no reason to rule on, which is how 488 items ended up fitting any
# slot. Which slots each occupies is authored content ([ItemSlots]), not a guess
# made from the name.
const GREAVES := &"greaves"
const BANDOLIER := &"bandolier"
const LENS := &"lens"
const ORB := &"orb"
## Socket payload: carries a slot's effects but is never worn on its own.
const GEM := &"gem"

## Every equipment subtype this vocabulary declares, in a stable order. The set is
## the vocabulary's claim, not the content's: the content suite asserts the other
## direction too, that nothing shipped uses a subtype missing from here.
const EQUIPMENT_SUBTYPES: Array[StringName] = [
	WEAPON,
	ARMOR,
	ACCESSORY,
	ARTIFACT,
	GREAVES,
	BANDOLIER,
	LENS,
	ORB,
	GEM,
]

# technique
const MANUAL := &"manual"
const SCROLL := &"scroll"
const JADE_SLIP := &"jade_slip"
