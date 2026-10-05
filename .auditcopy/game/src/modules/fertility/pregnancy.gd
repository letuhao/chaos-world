class_name PregnancyStatus
extends StatusEffect

## Pregnancy as an actor status. `id` is assigned by FertilityApi so this class does
## not override StatusEffect._init. Stages advance via FertilityApi.advance().
##
## The lineage snapshot is what makes a child a function of WHO conceived it rather than of who
## happens to be present at labor (ADR 0108). `partner_base` already existed for exactly that
## reason; `partner_race` and `partner_purity` extend the same idea to the two systems that
## inherited the previous ADR left with nothing to inherit.

enum Stage { CONCEIVED, GESTATING, LABOR, POSTPARTUM }

var stage: Stage = Stage.CONCEIVED
var progress: float = 0.0
var partner_id: StringName = &""
var partner_base: Dictionary = {}
var species_id: StringName = &""
## The partner's race at conception, or `&""` when the partner had none. A child is born ONE
## race, so this is a single id rather than a set.
var partner_race: StringName = &""
## `{lineage_id: purity}` the partner carried at conception.
var partner_purity: Dictionary = {}
## The conception roll that decided this pregnancy, stored so birth is reproducible.
var conception_roll: float = 0.5
## The race roll captured at conception and spent at birth. Stored rather than drawn at labor:
## the same pregnancy resolved twice must produce the same child (ADR 0108).
var race_roll: float = 0.5
var offspring: Array[Actor] = []
var recovery_remaining: float = 0.0


func is_gestating() -> bool:
	return stage == Stage.GESTATING


func is_recovering() -> bool:
	return stage == Stage.POSTPARTUM and recovery_remaining > 0.0
