class_name DomainRoomCopy
extends RefCounted

## The deep copy of an authored `RoomDef` a realization places, split out of
## `domain_generator.gd` for its thousand-line ceiling and kept beside it because the
## reason it exists is the generator's own: the generator NEVER mutates an authored
## resource. The same def is placed again in the next map a seed builds, and a shared
## write would change both.
##
## Every surface an authored def carries is copied here, so adding one to `RoomDef` and
## forgetting this file is the next way a realized map can lose authored content — the
## failure `test_domain_content.gd:760` records happening for `fixtures` already.


## A deep copy of `def`, carrying every authored surface.
static func room(def: RoomDef) -> RoomDef:
	var out := RoomDef.new()
	out.room_id = def.room_id
	out.display_name = def.display_name
	out.kind = def.kind
	out.roster_band = def.roster_band
	out.tags = def.tags.duplicate()
	out.size = def.size
	for ref in def.actor_spawn_refs:
		out.actor_spawn_refs.append((ref as Dictionary).duplicate(true))
	for fixture in def.fixtures:
		out.fixtures.append((fixture as Dictionary).duplicate(true))
	for zone in def.environment_zones:
		out.environment_zones.append(zone_def(zone))
	return out


## A deep copy of one authored environment zone.
static func zone_def(zone: EnvironmentZoneDef) -> EnvironmentZoneDef:
	var out := EnvironmentZoneDef.new()
	out.zone_id = zone.zone_id
	out.kind = zone.kind
	out.intensity = zone.intensity
	out.status_id = zone.status_id
	out.stay_budget = zone.stay_budget
	out.tags = zone.tags.duplicate()
	out.mitigation_tags = zone.mitigation_tags.duplicate()
	out.bounds = zone.bounds
	return out
