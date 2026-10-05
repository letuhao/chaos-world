class_name InstitutionRegistryFixtureDef
extends Resource

## A stand-in authored def, registered by `test_institution_registry.gd` as the def
## SCRIPT for a kind.
##
## It exists because `core/` may not name `modules/`, so a registration cannot reach
## for `SectDef` — the shape being tested is that the registry takes an opaque `Script`
## the caller resolved in its own scope. A fixture under `res://tests/` is the honest
## way to have one: it is not a module, so no boundary edge exists in either direction.
##
## Deliberately minimal. What the registry needs from a def is its TYPE, and a row's
## properties are the tier's business.

@export var id: StringName = &""
@export var standing_cap: int = 100
