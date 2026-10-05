class_name WorldEvents
extends RefCounted

## Signal contract for world creation events (ADR 0019).
## Emitted by the world module; consumed by any observer.

signal world_created(actor_id: String, tier: StringName)
signal world_stability_changed(actor_id: String, old_value: float, new_value: float)
signal world_law_added(actor_id: String, law_id: StringName, value: float)
signal world_inhabitant_added(actor_id: String, inhabitant_id: StringName, count: int)
signal world_upkeep_paid(actor_id: String, amount: float, upkeep_rate: float)
signal world_conflict_triggered(actor_id: String, conflict_id: StringName, severity: float)
signal world_evolved(actor_id: String, old_tier: StringName, new_tier: StringName)
signal world_merged(actor_id: String, target_actor_id: String, result_tier: StringName)
signal world_conflict_resolved(actor_id: String, conflict_id: StringName, outcome: StringName)
