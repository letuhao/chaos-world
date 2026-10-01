class_name SpeciesDef
extends Resource

## Data-driven species: reproduction parameters and offspring rules. Add a species
## by authoring a `.tres`, not code (ADR 0002).

@export var id: StringName = &""
@export var display_name: String = ""
@export var gestation_days: float = 30.0
@export var base_fertility: float = 0.0
@export var base_potency: float = 0.0
@export var offspring_variance: float = 0.1
