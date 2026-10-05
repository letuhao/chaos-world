class_name RoomDef
extends Resource

## One authored room (ADR 0073). `RoomDef` is the SHARED currency of a domain: a
## handcrafted room and a generated room are the same def, so a template assembles
## authored rooms rather than inventing a parallel cheap kit.
##
## `kind` decides the SHAPE of what a room permits (its encounter band); `tags` decide
## its CONTENT. `kind` never names an actor and no rule branches on a room's size or
## its distance from the core — those are post-hoc heuristics ADR 0073 forbids.
##
## Every field is optional: a def that omits them is still a valid room.

## Room shape. The set is CLOSED so `tools data audit` can hard-fail an unknown kind
## rather than accepting a typo that silently rooms nothing.
const KINDS: Array[StringName] = [
	&"floor",
	&"corridor",
	&"chamber",
	&"settlement",
	&"arena",
	&"gate",
	&"core",
]

## How much hostility this room's SHAPE permits. A room's `kind` supplies the default
## and an author may override it; the audit fails a roster inconsistent with the band.
const BANDS: Array[StringName] = [
	&"empty",
	&"traffic",
	&"skirmish",
	&"contact",
	&"trial",
	&"boss",
	&"social",
]

const DEFAULT_BAND: StringName = &"skirmish"

## The one band that means "there is an antagonist here", named so the vocabulary has ONE
## spelling. `BANDS` above holds it inline because it is a list of every legal value, and
## a reader that needed "is this room a boss room" had no named answer to ask for — so
## `DomainApi._open_band` was about to spell `&"boss"` a second time and `DomainMinimap`
## a third. The constant is the answer; the array is unchanged.
const BOSS_BAND: StringName = &"boss"

## The id this room is known by inside a map. Unique per `DomainMap`, not per def: a
## template may place the same def twice, so the map namespaces it as `<room_id>#<n>`.
@export var room_id: StringName = &""

@export var display_name: String = ""

## One of `KINDS`. An empty value is authored as `floor`, never guessed per map.
@export var kind: StringName = &"floor"

## One of `BANDS`. Empty resolves to the default band for `kind`.
@export var roster_band: StringName = &""

## Authored tags. They drive the encounter roster, hazard placement, treasure
## weighting and the minimap POI layer FROM ONE SOURCE — never a post-hoc heuristic.
@export var tags: Array[StringName] = []

## Size in TILES. The map's realized rect; the scene asserts it rather than inventing
## geometry. A zero size resolves to the template's authored band, never a default.
@export var size: Vector2i = Vector2i.ZERO

## Who stands here, named by id. A role is a tag on the spawned `Actor`, never a class
## (ADR 0074), so this list names `InhabitantDef`s and the role separately.
@export var actor_spawn_refs: Array[Dictionary] = []

## Traps, puzzles and treasure. Same placement mechanism as actors, different payload.
@export var fixtures: Array[Dictionary] = []

## Severe environments as local volumes (ADR 0075). A room with none has none; the
## generator never invents a hazard.
@export var environment_zones: Array[EnvironmentZoneDef] = []

## Room ids this room connects to. The generator derives these from the corridor
## graph; a handcrafted room authors them. Every target must resolve or the map fails.
@export var exits: Array[StringName] = []


func band() -> StringName:
	if roster_band != &"" and BANDS.has(roster_band):
		return roster_band
	return default_band_for(kind)


## The shape band a `kind` permits. `settlement` is social by definition, `core` is a
## boss by definition, and everything else scales by how much room it is.
static func default_band_for(room_kind: StringName) -> StringName:
	match room_kind:
		&"settlement":
			return &"social"
		&"core":
			return &"boss"
		&"corridor":
			return &"traffic"
		&"gate":
			return &"contact"
		&"arena":
			return &"trial"
		&"chamber":
			return &"contact"
		_:
			return DEFAULT_BAND


## The band permits no hostile spawn at all. `social` rooms hold npc and rival
## cultivators; `empty` rooms hold a breather.
func is_hostile() -> bool:
	return band() not in [&"empty", &"social"]


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func to_dict() -> Dictionary:
	var spawns: Array = []
	for ref in actor_spawn_refs:
		spawns.append(ref.duplicate())
	var fixture_out: Array = []
	for fixture in fixtures:
		fixture_out.append(fixture.duplicate())
	var zones: Array = []
	for zone in environment_zones:
		zones.append(zone.to_dict())
	var exits_out: Array = []
	for exit_id in exits:
		exits_out.append(String(exit_id))
	return {
		"room_id": String(room_id),
		"display_name": display_name,
		"kind": String(kind),
		"band": String(band()),
		"tags": _tags_to_strings(tags),
		"size": [size.x, size.y],
		"actor_spawn_refs": spawns,
		"fixtures": fixture_out,
		"environment_zones": zones,
		"exits": exits_out,
	}


static func from_dict(data: Dictionary) -> RoomDef:
	var room := RoomDef.new()
	room.room_id = StringName(data.get("room_id", ""))
	room.display_name = String(data.get("display_name", ""))
	room.kind = StringName(data.get("kind", "floor"))
	room.roster_band = StringName(data.get("band", ""))
	room.tags = _strings_to_names(data.get("tags", []))
	room.size = Vector2i(
		int((data.get("size", [0, 0]) as Array)[0]), int((data.get("size", [0, 0]) as Array)[1])
	)
	room.actor_spawn_refs.assign(data.get("actor_spawn_refs", []))
	room.fixtures.assign(data.get("fixtures", []))
	room.exits.assign(_strings_to_names(data.get("exits", [])))
	for zone_data in data.get("environment_zones", []):
		room.environment_zones.append(EnvironmentZoneDef.from_dict(zone_data))
	return room


func _tags_to_strings(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out


static func _strings_to_names(values: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for value in values:
		out.append(StringName(value))
	return out
