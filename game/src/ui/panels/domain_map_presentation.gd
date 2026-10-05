class_name DomainMapPresentation
extends RefCounted

## The fog partition and the marker vocabulary for [DomainMapView], as pure data (ADR
## 0207, ADR 0208). A separate class because both are PRESENTATION over a payload the
## module already published, and neither belongs to the drawing: keeping them here is
## what lets the view be a canvas and this be arithmetic.
##
## ## The remembered band is the MODULE's, and this never re-derives it
##
## It is exactly the rooms the payload's `rooms[]` carries, which `DomainMinimap._rooms`
## already filtered to the discovered set. The frontier is computed here rather than in
## the module, because ADR 0207 forbids widening `DomainMinimap` to emit one — a frontier
## is about rooms the player has NOT stood in, and making that a module fact would put a
## presentation choice into the read model. A frontier room's `rect` is READ from the
## payload's `layout`, never invented, so ADR 0206's "no geometry of its own" holds.
##
## ## The partition is TOTAL, and the hidden band is counted, not walked
##
## `hidden_rooms` is `authored − remembered − frontier` by arithmetic, so a test can
## assert nothing was silently dropped without trusting the order of a filter.
##
## Every loop is bounded by the size of an array the module published, snapshotted
## BEFORE the loop that appends to a list of its own (INC-0002).

## How many frontier outlines are drawn before the cap bites (ADR 0207). A wide room
## graph would otherwise draw a wall of outlines hiding the remembered rooms behind it,
## and a bounded number is a summary field, not a loop.
const MAX_FRONTIER_ROOMS := 8

## `DomainMinimap.POI_BY_TAG`'s own keys, restated verbatim as strings. A UI file may not
## name a domain type, so the "one source" check is written against this table — and a
## test asserts the two agree rather than either being believed.
const POI_BY_TAG := {
	"boss_worthy": "boss",
	"elite_guard": "elite_guard",
	"puzzle_formation": "puzzle",
	"refuge": "refuge",
	"treasure_keyed": "treasure",
}

## The CLOSED glyph vocabulary, keyed by the authored tag. One tag, one shape. There is
## deliberately NO fallback glyph and NO entry keyed by tier or rank: a marker whose
## strength the UI can compute is the ADR 0073 post-hoc heuristic wearing a different
## hat, and a fallback would make the module's skip of an unknown tag invisible.
const MARKER_GLYPHS := {
	"refuge": "open_circle",
	"treasure": "diamond",
	"puzzle": "nested",
	"elite_guard": "chevron",
	"boss": "boss_ring",
}

## One legend row per glyph, keyed by the same tag. A shape a player cannot decode is a
## lie about discoverability, so the legend is part of the promise, not an optional extra.
const LEGEND_ROWS := [
	{"tag": "refuge", "glyph": "open_circle", "promise": "somewhere safe to stand"},
	{"tag": "treasure", "glyph": "diamond", "promise": "something is here to open"},
	{"tag": "puzzle", "glyph": "nested", "promise": "something must be solved"},
	{"tag": "elite_guard", "glyph": "chevron", "promise": "something is guarded"},
	{"tag": "boss", "glyph": "boss_ring", "promise": "the run's climax"},
]

## The tier a room carries when it promises nothing, so a tier test is a comparison
## rather than a substring match on a name that could change.
const TIER_PLAIN := "room"


## Partition a payload into the three bands.
##
## `rooms` is the payload's DISCOVERED `rooms[]`, `authored` is the run's full room list
## (the payload's is a fogged SUBSET, so a seam asked of it would be permanently empty),
## and `layout` is the payload's own rects — the single layout rule in the repo, read and
## never re-laid-out.
func partition(rooms: Array, authored: Array, routes: Array, layout: Array) -> Dictionary:
	var remembered: Array = []
	var remembered_ids := {}
	for entry in rooms:
		var room := entry as Dictionary
		var room_id := String(room.get("room_id", ""))
		if room_id.is_empty():
			continue
		remembered.append(room)
		remembered_ids[room_id] = true
	var candidates: Array = []
	for entry in authored:
		var room := entry as Dictionary
		var room_id := String(room.get("room_id", ""))
		if room_id.is_empty() or remembered_ids.has(room_id):
			continue
		if not is_one_corridor_from(room_id, remembered_ids, routes):
			continue
		# A frontier room needs a rect to be an outline, and a room the layout does not
		# hold has none. Inventing one would be the second map ADR 0206 rules out.
		if not _layout_rect(room_id, layout).is_empty():
			candidates.append(room)
	candidates.sort_custom(_by_room_id)
	var frontier: Array = []
	var index := 0
	# SNAPSHOT the cap before the loop: the body appends to `frontier`, so a bound read
	# off `frontier` would rise in lockstep and never terminate.
	var budget := mini(candidates.size(), MAX_FRONTIER_ROOMS)
	while index < budget:
		frontier.append(candidates[index])
		index += 1
	var authored_count := authored.size() if not authored.is_empty() else rooms.size()
	return {
		"remembered": remembered,
		"frontier": frontier,
		"hidden": maxi(0, authored_count - remembered.size() - frontier.size()),
		"truncated": candidates.size() > MAX_FRONTIER_ROOMS,
	}


## The glyph `tag` earns, or `""` when the tag is not in `POI_BY_TAG`. Chosen by the
## AUTHORED TAG ALONE: no rank, no distance, no room size, and nothing the UI computed.
func glyph_of(tag: String) -> String:
	return String(MARKER_GLYPHS.get(String(POI_BY_TAG.get(tag, "")), ""))


## The tags a marker list actually names, sorted and deduplicated. Read off the payload's
## own `pois[].tag`, never off a room's tier list.
func tags_in(pois: Array) -> Array[String]:
	var out: Array[String] = []
	for entry in pois:
		var tag := String((entry as Dictionary).get("tag", ""))
		if not tag.is_empty() and not out.has(tag):
			out.append(tag)
	out.sort()
	return out


## The glyphs a marker list earns, sorted. Published so a test asserts the glyph table and
## the payload agree — a test never counts pixels.
func glyphs_in(pois: Array) -> Array[String]:
	var out: Array[String] = []
	for tag in tags_in(pois):
		var shape := glyph_of(tag)
		if not shape.is_empty() and not out.has(shape):
			out.append(shape)
	out.sort()
	return out


## The legend rows for the tags a payload carries: the five vocabulary entries, minus
## the ones it has none of. A legend with no rows is an honest "this map has no marker
## vocabulary yet", not a blank the player reads as "nothing to see".
func legend_for(pois: Array) -> Array[Dictionary]:
	var tags := tags_in(pois)
	var out: Array[Dictionary] = []
	for row in LEGEND_ROWS:
		if tags.has(String(row["tag"])):
			out.append((row as Dictionary).duplicate(true))
	return out


## The tiers drawn as chips, sorted, and only the ones that promise something. Separate
## from [method glyphs_in] for exactly the reason ADR 0208 gives: a tier is a text chip
## and must never become a glyph upgrade.
func tier_chips_in(rooms: Array) -> Array[String]:
	var out: Array[String] = []
	for entry in rooms:
		var tier := String((entry as Dictionary).get("tier", ""))
		if tier.is_empty() or tier == TIER_PLAIN:
			continue
		if not out.has(tier):
			out.append(tier)
	out.sort()
	return out


## Every tag `POI_BY_TAG` names, sorted — the closed vocabulary, published so a test can
## check the table against the module's without either naming a module type.
func known_tags() -> Array[String]:
	var out: Array[String] = []
	for tag in POI_BY_TAG.keys():
		out.append(String(tag))
	out.sort()
	return out


## The rooms `rooms` carries with a four-number rect: exactly what a room layer draws.
func count_with_rect(rooms: Array) -> int:
	var count := 0
	for entry in rooms:
		if ((entry as Dictionary).get("rect", []) as Array).size() == 4:
			count += 1
	return count


## Corridors a route list will stroke: a route with a polyline of at least two points.
func count_routes(routes: Array) -> int:
	var count := 0
	for entry in routes:
		if ((entry as Dictionary).get("points", []) as Array).size() >= 2:
			count += 1
	return count


## Zones with a four-number bounds box: the hatch layer's own test.
func count_zones(zones: Array) -> int:
	var count := 0
	for entry in zones:
		if ((entry as Dictionary).get("bounds", []) as Array).size() == 4:
			count += 1
	return count


## Markers that will be drawn: a tag `POI_BY_TAG` names, a two-number anchor, and a
## REMEMBERED room. The remembered test is what makes "never on a frontier room" (ADR
## 0208) a property of the drawing rather than a promise in a comment.
func count_markers(pois: Array, remembered_ids: Dictionary) -> int:
	var count := 0
	for entry in pois:
		var poi := entry as Dictionary
		if glyph_of(String(poi.get("tag", ""))).is_empty():
			continue
		if not remembered_ids.has(String(poi.get("room_id", ""))):
			continue
		if (poi.get("anchor", []) as Array).size() == 2:
			count += 1
	return count


## Corridor mouths on the seam: the cost of a frontier room, and the one affordance fog
## never withholds (ADR 0207).
func count_frontier_doors(frontier: Array, routes: Array) -> int:
	var count := 0
	for entry in frontier:
		var room_id := String((entry as Dictionary).get("room_id", ""))
		for route in routes:
			var edge := route as Dictionary
			if String(edge.get("from", "")) == room_id or String(edge.get("to", "")) == room_id:
				count += 1
	return count


## Whether `room_id` is joined to a remembered room by a route. `routes[].from` /
## `routes[].to` are the module's own mutual-confirmed pairs, so the seam is made of the
## payload's own corridors and no graph is built here.
##
## Public because [DomainMapView] asked the same question of its own routes before this
## split existed, and `partition` is the one place that asks it now.
static func is_one_corridor_from(
	room_id: String, remembered_ids: Dictionary, routes: Array
) -> bool:
	for entry in routes:
		var route := entry as Dictionary
		var from_id := String(route.get("from", ""))
		var to_id := String(route.get("to", ""))
		if from_id == room_id and remembered_ids.has(to_id):
			return true
		if to_id == room_id and remembered_ids.has(from_id):
			return true
	return false


## The payload's own rect for a room, or `[]` when the layout does not hold it.
static func _layout_rect(room_id: String, layout: Array) -> Array:
	for entry in layout:
		if String((entry as Dictionary).get("room_id", "")) == room_id:
			return (entry as Dictionary).get("rect", []) as Array
	return []


static func _by_room_id(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("room_id", "")) < String(b.get("room_id", ""))
