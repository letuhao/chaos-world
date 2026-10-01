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

# technique
const MANUAL := &"manual"
const SCROLL := &"scroll"
const JADE_SLIP := &"jade_slip"
