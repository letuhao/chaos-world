class_name PregnancyStatus
extends StatusEffect

## Pregnancy as an actor status. `id` is assigned by FertilityApi so this class does
## not override StatusEffect._init. Stages advance via FertilityApi.advance().

enum Stage { CONCEIVED, GESTATING, LABOR, POSTPARTUM }

var stage: Stage = Stage.CONCEIVED
var progress: float = 0.0
var partner_id: StringName = &""
var partner_base: Dictionary = {}
var species_id: StringName = &""
var offspring: Array[Actor] = []
var recovery_remaining: float = 0.0


func is_gestating() -> bool:
	return stage == Stage.GESTATING


func is_recovering() -> bool:
	return stage == Stage.POSTPARTUM and recovery_remaining > 0.0
