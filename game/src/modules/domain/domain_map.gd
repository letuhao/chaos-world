class_name DomainMap
extends RefCounted

## The single description of a domain's SHAPE (ADR 0072).
##
## Engine-agnostic on purpose: no `Node`, no `TileMap`, no `Vector2`. A `DomainScene`
## realizes this for play, but no gameplay rule reads a node, so the map is testable
## without a scene tree — which is what makes the acceptance criteria unit tests.
##
## **There is deliberately no `producer` / `template_id` / `layout` field.** ADR 0072
## says nothing downstream can tell whether a map was handcrafted or generated, and a
## provenance field would make that literally false. Provenance lives in the test, not
## in the data.
##
## Ordering is canonical everywhere: rooms by `room_id`, exits sorted, spawn refs by
## their ref id. GDScript dictionaries are insertion-ordered, so sorting on output is
## what makes "the same seed produces a byte-identical map" an actual claim.

const SCHEMA_VERSION := 1

## ## The weather catalogue, and why weather is a real bias
##
## ADR 0075 says weather "biases which zones are active". That promise is only kept
## by a bias that MOVES A NUMBER, and a bias that moved a number nobody reads would be
## the same inert field wearing a hat. So weather is resolved HERE, into a zone's
## EFFECTIVE intensity, by [method effective_intensity] — the one read every consumer
## goes through — and the resolved value is published in [method zones].
##
## The rules that make it honest rather than arbitrary:
##
## 1. **CLOSED.** [constant WEATHERS] is the whole vocabulary. An id outside it is
##    REFUSED BY NAME by [method accepts_weather] and never quietly treated as calm
##    weather, because a typo that defaulted to "no bias" is a typo that deletes a
##    mechanic while looking like it worked.
## 2. **WITHIN AUTHORED BOUNDS.** The bias moves a zone by AT MOST one authored band
##    and never below band 1, so a domain's authored ceiling is a floor the weather
##    cannot undercut and an authored scorch can never be talked up to annihilating.
##    Weather re-weights authored content; it never invents intensity.
## 3. **ELEMENT-KEYED, NOT ZONE-KEYED.** Each weather declares the ELEMENT it carries,
##    and it moves a zone only when the zone authors that same element in its own
##    `tags` (`EnvironmentZoneDef.tags` is already the "elements this zone is hostile
##    to" list — `environment_field.gd` reads the same set as `HOSTILE_ELEMENTS`). A
##    `verdant` domain does not get hotter because the weather is dry; a zone that
##    never names the element the weather carries is untouched.
## 4. **NO WEATHER, NO BIAS.** `&""` means the run has no weather and every effective
##    intensity equals its authored band. That is the state a caller with nothing
##    authored is in, and it must be a no-op rather than a default bias.
##
## Deliberately NOT done here: weather does not create a zone, does not apply a
## status of its own, and does not touch mitigation. It re-weights a magnitude
## through the band ladder and nothing else.
const WEATHERS: Dictionary = {
	&"ashfall": &"fire",
	&"ember_heat": &"fire",
	&"rime_mist": &"ice",
	&"storm_gale": &"lightning",
	&"spore_drift": &"wood",
	&"void_tide": &"dark",
}

## The id used when a run has no weather at all. Absent from [constant WEATHERS] on
## purpose — it is the absence of a bias, not a bias that happens to be zero.
const WEATHER_NONE := &""

## The grid a generated map occupies, in TILES.
var extent: Vector2i = Vector2i.ZERO

## Realized rooms, keyed by their map-unique `room_id`.
var rooms: Dictionary = {}

## The room a run begins in. A map with no entry is not enterable.
var entry_room: StringName = &""

## The seed this map was generated from, or 0 for a handcrafted map that is read
## rather than rolled.
var seed: int = 0

## Domain-level weather bias (ADR 0075), one of [constant WEATHERS] or [constant
## WEATHER_NONE].
##
## It re-weights which authored zones are active — see [method effective_intensity],
## which is where that promise is kept. It never applies a status of its own and never
## invents a zone. Assigning an id that is not in [constant WEATHERS] would make every
## [method effective_intensity] silently answer "no bias", so [method accepts_weather]
## is the question to ask before assigning and the tests assert the refusal.
var weather: StringName = WEATHER_NONE


func _init(p_extent: Vector2i = Vector2i.ZERO, p_seed: int = 0) -> void:
	extent = p_extent
	seed = p_seed


func room_count() -> int:
	return rooms.size()


func has_room(room_id: StringName) -> bool:
	return rooms.has(room_id)


## The room, or null. Null rather than a guess: a caller that silently fell through to
## the first room would place a spawn somewhere arbitrary.
func room(room_id: StringName) -> RoomDef:
	return rooms.get(room_id, null)


func entry() -> RoomDef:
	return room(entry_room)


func add_room(room_def: RoomDef) -> void:
	rooms[room_def.room_id] = room_def


## Room ids in canonical order. Every traversal, every validator walk and every
## serialized payload goes through here, so ordering is one rule in one place.
func room_ids_sorted() -> Array[StringName]:
	var ids: Array[StringName] = []
	for room_id in rooms.keys():
		ids.append(room_id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids


## Room ids reachable from the entry under the exit graph. Breadth-first over a
## canonically ordered frontier, so the result is a pure function of the map.
func reachable_room_ids() -> Array[StringName]:
	var seen: Dictionary = {}
	if entry_room == &"" or not rooms.has(entry_room):
		return []
	var frontier: Array[StringName] = [entry_room]
	seen[entry_room] = true
	while not frontier.is_empty():
		var current: StringName = frontier.pop_front()
		var room_def := room(current)
		if room_def == null:
			continue
		for exit_id in room_def.exits:
			if seen.has(exit_id) or not rooms.has(exit_id):
				continue
			seen[exit_id] = true
			frontier.append(exit_id)
	var ids: Array[StringName] = []
	for room_id in seen.keys():
		ids.append(room_id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids


## Every room kind present, canonical order. A map reads as a mix of shapes, and this
## is how a caller asks "does this domain have an arena?" without walking it.
func kinds_present() -> Array[StringName]:
	var found: Dictionary = {}
	for room_id in rooms.keys():
		found[rooms[room_id].kind] = true
	var kinds: Array[StringName] = []
	for kind in found.keys():
		kinds.append(kind)
	kinds.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return kinds


## Every actor spawn ref in the map, as `{room_id, ref_id, inhabitant_id, role}`, in
## canonical order. `role` is a TAG on the spawned Actor, never a class (ADR 0074).
func spawn_refs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room_id in room_ids_sorted():
		var room_def: RoomDef = rooms[room_id]
		var refs: Array = room_def.actor_spawn_refs.duplicate()
		refs.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return String(a.get("ref_id", "")) < String(b.get("ref_id", ""))
		)
		for ref in refs:
			(
				out
				. append(
					{
						"room_id": String(room_id),
						"ref_id": String(ref.get("ref_id", "")),
						"inhabitant_id": String(ref.get("inhabitant_id", "")),
						"role": String(ref.get("role", "")),
						"count": int(ref.get("count", 1)),
					}
				)
			)
	return out


## Whether `id` is a weather this build knows. `WEATHER_NONE` is accepted because a
## run with no weather is a real state, not an error; every OTHER unknown id is refused,
## which is what stops a typo from reading as "the weather happens to be calm".
##
## The refusal is a boolean rather than a clamp: a caller that gets `false` can name the
## id it passed, and this map's `weather` field is deliberately left untouched by an
## unknown value so the map cannot end up in a half-authored state.
func accepts_weather(id: StringName) -> bool:
	return id == WEATHER_NONE or WEATHERS.has(id)


## The band shift this map's weather applies to a zone, as `-1`, `0` or `+1`.
##
## `+1` when the weather carries an element the zone authors in its own `tags`, and
## `0` in every other case. The shift is one-directional on purpose: only an authored
## elemental zone moves, and it moves UP, so a run's weather can intensify the hazards
## the content actually declared and can never soften one a player may have routed
## around on the promise that it was authored at band 2.
##
## Never more than one band, so [method effective_intensity] stays inside the authored
## ladder. `WEATHER_NONE` is `0` by definition.
func weather_shift_for(zone: EnvironmentZoneDef) -> int:
	if zone == null or weather == WEATHER_NONE or not WEATHERS.has(weather):
		return 0
	# Bounded `for` over the zone's own authored element tags, which are small authored
	# content. A zone authoring no element is biased by no weather.
	for tag in zone.tags:
		if tag == StringName(WEATHERS[weather]):
			return 1
	return 0


## The band `zone` actually runs at under this map's weather.
##
## THE ONE READ EVERY CONSUMER GOES THROUGH. `zone.intensity` is the AUTHORED band and
## stays exactly as authored; this is the effective value, and it is what `zones()`
## publishes and what a caller must use to answer "how bad is this zone, right now".
## Anything less would leave weather a field nobody acts on — the exact failure ADR
## 0075's promise was written to prevent.
##
## Clamped to the authored ladder on BOTH sides: never below [constant
## EnvironmentZoneDef.BAND_SCORCH], never above [constant
## EnvironmentZoneDef.BAND_ANNIHILATING], and never above the band a shift of `+1`
## could reach. A zone authored at band 3 is already at the ceiling, so weather cannot
## make it worse than the author allowed; a zone authored at band 1 cannot be talked
## below the floor into a band the ladder has no name for.
func effective_intensity(zone: EnvironmentZoneDef) -> int:
	if zone == null:
		return 0
	var authored := zone.resolved_intensity()
	var shifted := authored + weather_shift_for(zone)
	return clampi(shifted, EnvironmentZoneDef.BAND_SCORCH, EnvironmentZoneDef.BAND_ANNIHILATING)


## Every severe environment in the map, flattened, canonical order. Weather is NOT
## included as a zone: it biases these, it is not itself a zone.
##
## `intensity` here is the EFFECTIVE band ([method effective_intensity]) and
## `authored_intensity` is what the `.tres` says, so a consumer can show both and can
## tell a weathered domain from an authored one without re-deriving anything.
func zones() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room_id in room_ids_sorted():
		var room_def: RoomDef = rooms[room_id]
		for zone in room_def.environment_zones:
			var entry: Dictionary = zone.to_dict()
			entry["room_id"] = String(room_id)
			entry["authored_intensity"] = zone.resolved_intensity()
			entry["intensity"] = effective_intensity(zone)
			out.append(entry)
	return out


func to_dict() -> Dictionary:
	var rooms_out: Array = []
	for room_id in room_ids_sorted():
		rooms_out.append(rooms[room_id].to_dict())
	return {
		"schema_version": SCHEMA_VERSION,
		"extent": [extent.x, extent.y],
		"seed": seed,
		"entry_room": String(entry_room),
		"weather": String(weather),
		"rooms": rooms_out,
	}


static func from_dict(data: Dictionary) -> DomainMap:
	var box: Array = data.get("extent", [0, 0])
	var map := DomainMap.new(
		Vector2i(int(box[0]), int(box[1])) if box.size() == 2 else Vector2i.ZERO,
		int(data.get("seed", 0))
	)
	map.entry_room = StringName(data.get("entry_room", ""))
	# A weather id this build does not know is DROPPED, and reported, rather than
	# stored: storing it would make every `effective_intensity` answer "no bias" while
	# the read model still printed the unknown name, so the map would claim a weather it
	# is not applying. Dropping is the honest degradation and the message names the id
	# and the ids that exist, so the author can fix it rather than guess.
	var authored_weather := StringName(data.get("weather", ""))
	if map.accepts_weather(authored_weather):
		map.weather = authored_weather
	elif authored_weather != WEATHER_NONE:
		push_error(
			(
				"DomainMap: unknown weather '%s' dropped; this build knows: %s"
				% [String(authored_weather), ", ".join(_weather_names())]
			)
		)
	for room_data in data.get("rooms", []):
		var room_def := RoomDef.from_dict(room_data)
		map.add_room(room_def)
	return map


## Every id in [constant WEATHERS], sorted, for a refusal that names what does exist
## rather than only what does not. Bounded `for` over a closed constant.
static func _weather_names() -> Array[String]:
	var out: Array[String] = []
	for key in WEATHERS:
		out.append(String(key))
	out.sort()
	return out
