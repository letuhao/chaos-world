class_name DaoDef
extends Resource

## Dao definition (ADR 0021). Data-driven dao types with conflicts, synergies,
## and effects. Adding a dao is a data change, not a code change.

# Weapon daos
const SWORD := &"sword"
const BLADE := &"blade"
const SPEAR := &"spear"

# Elemental daos
const FIRE := &"fire"
const WATER := &"water"
const WOOD := &"wood"
const METAL := &"metal"
const EARTH := &"earth"
const THUNDER := &"thunder"
const WIND := &"wind"
const ICE := &"ice"

# Conceptual daos
const SPACE := &"space"
const TIME := &"time"
const LIFE := &"life"
const DEATH := &"death"
const SOUL := &"soul"
const FORMATION := &"formation"
const ALCHEMY := &"alchemy"
const BEAST := &"beast"
const KARMA := &"karma"

@export var id: StringName = &""
@export var display_name: String = ""
@export var conflicts: Array[StringName] = []
@export var synergies: Array[StringName] = []
@export var effects: Array[StringName] = []
