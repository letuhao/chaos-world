class_name CultivationAssetDef
extends Resource

## Data-driven resource representing an individual asset specification
## from the Ancient Chinese Low Cultivation Pack (ancient_china_low_cultivation).

@export var id: StringName = &""
@export var display_name: String = ""
@export var pinyin: String = ""
@export var hanzi: String = ""
@export var domain_id: StringName = &""
@export var category_id: StringName = &""
@export var asset_class: StringName = &""
@export var archetype_name: String = ""
@export var texture_path: String = ""
@export var footprint_cells: Vector2i = Vector2i.ONE
@export var canvas_px: Vector2i = Vector2i(128, 128)
@export var collision_type: StringName = &"solid"
@export var primary_material: StringName = &""
@export var secondary_material: StringName = &""
@export var cultivation_element: StringName = &"earth"
@export var elevation_tier: int = 1
@export var mortal_realm_tier: String = ""
@export var interactive_verb: StringName = &"examine"
@export var variants: Array[Dictionary] = []
@export var collision_data: Dictionary = {}
@export var matrix_data: Dictionary = {}
