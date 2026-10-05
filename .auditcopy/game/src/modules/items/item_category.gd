class_name ItemCategory
extends RefCounted

## Top-level item categories (ADR 0007). Modules may add subtypes via ItemDef.

const MATERIAL := &"material"
const CONSUMABLE := &"consumable"
const EQUIPMENT := &"equipment"
const TECHNIQUE := &"technique"
const QUEST := &"quest"
const KEY := &"key"
const CURRENCY := &"currency"
const MISC := &"misc"

const ALL := [MATERIAL, CONSUMABLE, EQUIPMENT, TECHNIQUE, QUEST, KEY, CURRENCY, MISC]
