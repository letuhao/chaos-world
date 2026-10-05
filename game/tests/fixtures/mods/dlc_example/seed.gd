class_name DlcExampleRealmSeed
extends Resource

## Cultivation-path seed for the DLC example mod (ADR 0184).
## Proves the contract: one seed per realm, each carrying the required fields.

@export var id: StringName = &""
@export var breakthrough_item: StringName = &""
@export var recovery_item: StringName = &""
@export var progress_required: float = 100.0
@export var required_meridians: Array[StringName] = []
@export var rewards: Dictionary = {}
