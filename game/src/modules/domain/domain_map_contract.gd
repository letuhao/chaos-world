class_name DomainMapContract
extends RefCounted

## The ONE contract every domain map must satisfy (ADR 0072/0073), whether it was
## handcrafted or generated.
##
## `assert_valid` RETURNS its failures rather than throwing, so a handcrafted map and a
## seeded generated map produce the identical message set and a parity test can compare
## them. A contract that only one producer is checked against proves nothing.
##
## Every failure here is a loud one: the repo rule is that a feature which cannot work
## must fail out loud rather than substitute a default and carry on.

## A map with fewer rooms than this cannot be traversed and is not a map.
const MIN_ROOMS := 1


## Failures for `map`, empty when it satisfies the contract. Names the condition and
## the numbers, because a message that cannot be acted on is noise, not a failure.
static func assert_valid(map: DomainMap) -> PackedStringArray:
	var problems := PackedStringArray()
	if map == null:
		problems.append("map is null")
		return problems

	if map.room_count() < MIN_ROOMS:
		problems.append("has %d room(s), needs at least %d" % [map.room_count(), MIN_ROOMS])

	if map.entry_room == &"":
		problems.append("has no entry_room, so a run cannot begin")
	elif not map.has_room(map.entry_room):
		problems.append("entry_room '%s' does not resolve to a room" % String(map.entry_room))

	_problems_for_exits(map, problems)
	_problems_for_connectivity(map, problems)
	_problems_for_rooms(map, problems)

	return problems


static func _problems_for_exits(map: DomainMap, problems: PackedStringArray) -> void:
	var exit_count := 0
	for room_id in map.room_ids_sorted():
		var room_def: RoomDef = map.room(room_id)
		for exit_id in room_def.exits:
			exit_count += 1
			if not map.has_room(exit_id):
				problems.append(
					(
						"room '%s' exits to '%s', which does not resolve"
						% [String(room_id), String(exit_id)]
					)
				)
	if map.room_count() >= MIN_ROOMS and exit_count == 0:
		problems.append("has no exit at all, so a run could never be left")


## Every room must be reachable from the entry. A generator that emits a disconnected
## graph fails HERE rather than shipping a map the player cannot finish.
static func _problems_for_connectivity(map: DomainMap, problems: PackedStringArray) -> void:
	if map.entry_room == &"" or not map.has_room(map.entry_room):
		return
	var reachable := map.reachable_room_ids()
	if reachable.size() != map.room_count():
		var orphans: Array[String] = []
		for room_id in map.room_ids_sorted():
			if not reachable.has(room_id):
				orphans.append(String(room_id))
		(
			problems
			. append(
				(
					"%d of %d room(s) unreachable from entry '%s': %s"
					% [
						map.room_count() - reachable.size(),
						map.room_count(),
						String(map.entry_room),
						", ".join(orphans),
					]
				)
			)
		)


static func _problems_for_rooms(map: DomainMap, problems: PackedStringArray) -> void:
	for room_id in map.room_ids_sorted():
		var room_def: RoomDef = map.room(room_id)
		if not RoomDef.KINDS.has(room_def.kind):
			problems.append(
				(
					"room '%s' has unknown kind '%s'; allowed: %s"
					% [String(room_id), String(room_def.kind), _names(RoomDef.KINDS)]
				)
			)
		if room_def.band() == &"":
			problems.append("room '%s' resolves to no roster band" % String(room_id))
		if not _roster_fits_band(room_def):
			problems.append(
				(
					"room '%s' is band '%s' but authors a spawn ref that band does not permit"
					% [String(room_id), String(room_def.band())]
				)
			)
		for ref in room_def.actor_spawn_refs:
			var role := StringName(ref.get("role", ""))
			if role == &"":
				problems.append(
					(
						"room '%s' has a spawn ref with no role; a role is a tag, not a class"
						% String(room_id)
					)
				)
			elif not DomainRoles.ROLES.has(role):
				problems.append(
					(
						"room '%s' spawn ref has unknown role '%s'; allowed: %s"
						% [String(room_id), String(role), _names(DomainRoles.ROLES)]
					)
				)
		for zone in room_def.environment_zones:
			for problem in _problems_for_zone(room_id, zone):
				problems.append(problem)


## Whether a room's authored roster matches its band.
##
## A `social` band exists PRECISELY to hold inhabitants — an npc elder or a rival
## cultivator is what a settlement is for — so it permits those two roles and forbids
## the hostile ones. Only `empty` is genuinely empty: it is a breather, and a spawn ref
## there means the author wrote a fight into their own rest stop.
static func _roster_fits_band(room_def: RoomDef) -> bool:
	if room_def.actor_spawn_refs.is_empty():
		return true
	var band := room_def.band()
	if band == &"empty":
		return false
	for ref in room_def.actor_spawn_refs:
		var role := StringName(ref.get("role", ""))
		if band == &"social":
			if role != DomainRoles.NPC and role != DomainRoles.RIVAL_CULTIVATOR:
				return false
		elif not DomainRoles.is_hostile(role):
			return false
	return true


## ADR 0075's audit rule, asserted here so a bad zone cannot reach play: the catalogue
## is closed, a zone must publish a mitigation lever, and it must not be affinity-only
## (which would deny a player with the wrong spirit root any counterplay).
static func _problems_for_zone(room_id: StringName, zone: EnvironmentZoneDef) -> PackedStringArray:
	var problems := PackedStringArray()
	if not EnvironmentZoneDef.KINDS.has(zone.kind):
		(
			problems
			. append(
				(
					"room '%s' zone '%s' has unknown kind '%s'; allowed: %s"
					% [
						String(room_id),
						String(zone.zone_id),
						String(zone.kind),
						_names(EnvironmentZoneDef.KINDS),
					]
				)
			)
		)
	if zone.mitigation_tags.is_empty():
		problems.append(
			(
				"room '%s' zone '%s' publishes no mitigation_tags; it is a flat damage tax"
				% [String(room_id), String(zone.zone_id)]
			)
		)
	for lever in zone.mitigation_tags:
		if not EnvironmentZoneDef.LEVERS.has(lever):
			(
				problems
				. append(
					(
						"room '%s' zone '%s' mitigation_tag '%s' names no lever; allowed: %s"
						% [
							String(room_id),
							String(zone.zone_id),
							String(lever),
							_names(EnvironmentZoneDef.LEVERS),
						]
					)
				)
			)
	if not zone.mitigation_tags.is_empty() and not zone.has_non_affinity_mitigation():
		problems.append(
			(
				(
					"room '%s' zone '%s' is mitigated only by affinity; a player with the wrong "
					% [String(room_id), String(zone.zone_id)]
				)
				+ "spirit root has no authored counterplay"
			)
		)
	return problems


static func _names(values: Array) -> String:
	var out: Array[String] = []
	for value in values:
		out.append(String(value))
	return ", ".join(out)
