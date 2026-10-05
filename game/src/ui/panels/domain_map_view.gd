class_name DomainMapView
extends Control

## The domain floor plan, DRAWN. `DomainMinimap.render` publishes a primitives payload of
## one domain's interior and nothing in `ui/` painted it; `DomainMapView` is the picture
## (ADR 0206). A widget, not a screen: `ui/panels/`, one `show_map(payload)` door, never
## built in `_ready()`, and `.tscn`-instanced like any other panel.
##
## ## What it holds: no geometry of its own
##
## Every room rect, every corridor point and every marker anchor is READ from the
## payload, which is `DomainMinimap`'s own read of `DomainPaths.layout` — the one layout
## rule in the repo. This node never lays rooms out, never derives a tier, never measures
## distance from the entry. Two layouts is one too many (ADR 0072), and a second one
## would be wrong silently. `layout_digest()` publishes the layout it drew so a test can
## compare it against the module's own rather than trust it.
##
## ## How fog is partitioned here (ADR 0207)
##
## Three bands, computed in this file from what the payload already publishes:
##
##  - **Remembered** — the module's `discovered` set, which is the module's to decide.
##    Fill, outline, markers, tier chip.
##  - **Frontier** — every room one corridor away from a remembered room: a bare outline.
##    No fill, no marker, no name, no tier. Capped at [constant MAX_FRONTIER_ROOMS];
##    `frontier_truncated` says when the cap bit, because a wall of outlines would hide
##    the remembered rooms behind it.
##  - **Hidden** — everything else: not drawn. Never a lie, and never a filled block.
##
## `zones`, the room count and `bounds` stay unfogged, because the module already
## publishes them unfogged (ADR 0170: a hazard must be visible before you stand in it).
##
## ## How the canvas draw call reconciles with "anchors + containers, no absolute
## positions"
##
## The UI standard forbids a widget sitting at a hard-coded spot. It does not forbid a
## widget CONVERTING ITS OWN COORDINATE SPACE INTO PIXELS, and that is all `_draw`
## does: `origin + (tile - bounds.origin) * scale` with `scale` derived from this node's
## own `size` and recomputed on `resized`. There is no literal position anywhere in this
## file — every coordinate comes from the payload's `bounds` and this node's measured
## size. The node's own position remains a container result: it is an
## `AspectRatioContainer`'s child, and the aspect fit is what makes the inner rect the
## shape the payload asked for. `MapGraph` is the existing precedent (ADR 0048).
##
## Colours are named constants in art-direction's ink `#263A35` / ivory `#F2E8D2` /
## gold `#C49A53` family, deferred to the one theme by name. No style override anywhere.
##
## Contract: `summary()` is the testable surface, primitives only.

## ── Palette. Ink, ivory and gold, from docs/art-direction.md ────────────────

## The ink contour every painterly surface in this repo draws with.
const INK := Color(0.149, 0.227, 0.208)
## Warm ivory: reserved for readable focal detail, so it names the player.
const IVORY := Color(0.949, 0.910, 0.824)
## Antique gold: a remembered room's body, quiet enough to carry a marker.
const GOLD := Color(0.769, 0.604, 0.325)
## A corridor between rooms. Quiet — terrain is quieter than props (art direction).
const CORRIDOR_INK := Color(0.149, 0.227, 0.208, 0.55)
## The remembered band's fill, gold held well back so a marker still reads on it.
const ROOM_FILL := Color(0.769, 0.604, 0.325, 0.22)
## A remembered room's contour, at full ink.
const ROOM_EDGE := Color(0.149, 0.227, 0.208, 0.95)
## The frontier outline. Dim by design: a shape with no label and no contents.
const FRONTIER_EDGE := Color(0.949, 0.910, 0.824, 0.45)
## The player's room. Ivory, because "you are here" is never qualified.
const PLAYER_INK := Color(0.949, 0.910, 0.824, 1.0)
## The entry room's marker. Named apart from the player's so the two never read as one.
const ENTRY_INK := Color(0.769, 0.604, 0.325, 1.0)
## Hostile rooms carry a hazard wash; the zone layer owns severity, not this.
const HOSTILE_INK := Color(0.718, 0.373, 0.290, 0.30)

## Severity hatch colours, keyed by the payload's own `severity` word. The hatch is
## LINES: a number on the map is unreadable at minimap scale and duplicates a fact the
## zone readout already owns.
const SEVERITY_INK := {
	"low": Color(0.949, 0.910, 0.824, 0.22),
	"med": Color(0.769, 0.604, 0.325, 0.28),
	"high": Color(0.718, 0.373, 0.290, 0.34),
}

## ── Glyph vocabulary (ADR 0208) ──────────────────────────────────────────────

## The CLOSED shape vocabulary, keyed by the payload's authored `tag`. One tag, one
## shape. There is deliberately NO fallback glyph and NO entry keyed by tier or rank: a
## marker whose strength the UI can compute is the ADR 0073 post-hoc heuristic wearing a
## different hat, and a fallback would make the module's skip of an unknown tag
## invisible. A tag absent here draws nothing, which is the honest reading.
##
## The shapes, and the promise each one makes:
##   open_circle — refuge: somewhere safe to stand (not: that it is open).
##   diamond     — treasure: something is here to open (not: what it is worth).
##   nested      — puzzle: something must be solved (not: how hard).
##   chevron     — elite_guard: something is guarded (not: by how much).
##   boss_ring   — boss: the run's climax (not: that it can be beaten now).
##
## Aliased to [DomainMapPresentation]'s tables rather than restated: two copies of a closed
## vocabulary is two vocabularies, and this file's draw calls and its `summary()` publish
## must read the same one the partition reads.
const MARKER_GLYPHS := DomainMapPresentation.MARKER_GLYPHS
const POI_BY_TAG := DomainMapPresentation.POI_BY_TAG
const LEGEND_ROWS := DomainMapPresentation.LEGEND_ROWS
const TIER_PLAIN := DomainMapPresentation.TIER_PLAIN
## How many frontier outlines are drawn before the cap bites (ADR 0207).
const MAX_FRONTIER_ROOMS := DomainMapPresentation.MAX_FRONTIER_ROOMS

## ── Geometry metrics, named so art can retune them without reading the drawing ──

## The smallest a tile may be drawn at, so a large map zooms out to a legible blob
## rather than to sub-pixel hairlines. Floored here, never silently.
const MIN_TILE_PX := 2.0
## Room fills are inset by this many tiles so corridors read as corridors between them
## rather than as seams inside one mass.
const ROOM_INSET_TILES := 1.0
## Corridor stroke width, in tiles, when the route publishes no width of its own.
const DEFAULT_CORRIDOR_TILES := 1.0
## Marker radius, in tiles. One tile, so a marker reads at a glance beside a room.
const MARKER_RADIUS_TILES := 1.5

## The layer order, back to front. Declared so `summary()` and a reader can see which
## layer reads which payload key: each layer is one key and nothing else.
const LAYERS := ["corridors", "room_fills", "room_outlines", "zones", "markers", "player"]

## What the legend says when no map has been handed over. Named rather than blank,
## because an empty legend reads as "this map has no markers" and the truth is that
## this panel is not connected to anything.
const LEGEND_UNWIRED_TEXT := "The floor plan is not wired to a domain."

## Outline width, in pixels. Named because art owns it, and a number in a draw call is
## a number a reader cannot retune.
const OUTLINE_PX := 1.5

## Marker ink: ivory, because a marker is a readable focal detail and ivory is what
## art-direction reserves for those.
const MARKER_INK := Color(0.949, 0.910, 0.824, 1.0)

## Zone hatch spacing, in pixels. A drawing metric rather than a payload value: the
## payload publishes a severity WORD and this decides how loud that word looks.
const HATCH_STEP_PX := 6.0

## The room chip: font size, inset from the room's corner, baseline from it, and ink.
## All named, all art's to retune, none of them a style override.
const CHIP_FONT_PX := 11
const CHIP_INSET_PX := 3.0
const CHIP_BASELINE_PX := 12.0
const CHIP_INK := Color(0.949, 0.910, 0.824, 0.85)

## The room the actor is standing in, or `""`. Named the `from` argument because ADR
## 0209's settlement panel reads it with the same name, and one word for one thing.
var _player_room: String = ""
## The legend rows actually painted this frame: the five vocabulary entries, minus the
## ones this payload carries no tag for.
var _legend: Array[Dictionary] = []
## One `{room_id, rect: [x,y,w,h]}` per room, VERBATIM from the payload's `layout` and
## never re-laid-out. Empty whenever the payload carried no layout, which is what makes
## `layout_digest()` an honest answer to "is this the module's own layout?".
var _layout: Array[Dictionary] = []
## What the last draw painted, counted. Every number here is a count of primitives this
## node read, so `summary()` is answerable with no scene tree and no frame.
var _drawn: Dictionary = {}
## The scale the last draw used, and whether the fitted rect ran out of room.
var _scale: float = 0.0
var _tile_px: float = 0.0
var _clipped: bool = false
## Where the fitted inner rect sits inside this node, and the size it was given.
var _inner: Rect2 = Rect2()
var _bounds: Array = []
var _bound: bool = false
var _rooms: Array = []
var _pois: Array = []
var _routes: Array = []
var _zones: Array = []
## The payload WHOLE, held so a later `set_authored_rooms` can re-partition the fog
## without a caller re-handing the same dictionary. Never mutated.
var _payload: Dictionary = {}
## Every room the RUN authored, fog notwithstanding — `DomainApi.rooms` through the
## bridge, which is the one list the payload's `rooms[]` is a fogged SUBSET of.
var _authored: Array = []
## The remembered band, the capped frontier, and the three counts `summary()` publishes.
var _remembered: Array = []
var _frontier: Array = []
var _hidden_rooms: int = 0
var _frontier_truncated: bool = false
var _legend_label: Label = null
var _bound_nodes: bool = false
var _chip_font_cache: Font = null
## The fog partition and the marker vocabulary as pure data (ADR 0206's split), so this
## node stays the CANVAS and the arithmetic over a published payload lives beside it.
## Stateless, so one shared instance answers every partition.
var _presentation: DomainMapPresentation = DomainMapPresentation.new()


func _ready() -> void:
	_bind_nodes()
	_connect_resized()
	_refit()
	queue_redraw()


## Connect this node's own `resized` to [method _on_resized], ONCE.
##
## Guarded like every other connect in this program (AGENTS.md): an unguarded connect
## is one handler per call, and a reused panel would then recompute its fit N times per
## frame. `_bind_nodes` already has the same guard, and this returns early when the
## signal is connected so a re-`_ready` cannot stack a second handler.
func _connect_resized() -> void:
	if resized.is_connected(_on_resized):
		return
	resized.connect(_on_resized)


## The one door. `payload` is `DomainMinimap.render`'s dictionary WHOLE, or `{}` outside
## a run. Nothing is interpreted beyond the fog partition and the geometry read: a
## payload the module did not publish has nothing this node will invent to replace it.
##
## `player_room` is the room the actor is in — not a tracked transform, because the
## module publishes no intra-room position (ADR 0206).
##
## The fog partition happens HERE, once, so `_draw` walks two snapshots rather than
## re-deriving a set per pixel — and so `summary()` is answerable before any frame runs.
func show_map(payload: Dictionary, player_room: String = "") -> void:
	_bind_nodes()
	_player_room = player_room
	_payload = payload.duplicate(true)
	_bound = not payload.is_empty()
	_rooms = _array_of(payload.get("rooms", []))
	_pois = _array_of(payload.get("pois", []))
	_routes = _array_of(payload.get("routes", []))
	_zones = _array_of(payload.get("zones", []))
	_bounds = _box_of(payload.get("bounds", []))
	_layout = _layout_rows(payload.get("layout", {}))
	var bands := _fog_bands()
	_remembered = bands["remembered"] as Array
	_frontier = bands["frontier"] as Array
	_hidden_rooms = int(bands["hidden"])
	_frontier_truncated = bool(bands["truncated"])
	_legend = _legend_rows()
	# Counts of WHAT THE DRAWING READS, published without a frame: the payload a draw
	# consults is the only thing that has to be present for these to be honest.
	_drawn = {
		"corridors": _count_drawable_routes(),
		"rooms": _count_filled_rooms(),
		"room_outlines": _count_filled_rooms(),
		"zones": _count_drawable_zones(),
		"markers": _count_drawable_markers(),
		"frontier_rooms": _count_drawable_frontier(),
		"frontier_doors": _count_frontier_doors(),
		"zone_lines": 0,
		"player": 1 if not _room_by_id(_player_room).is_empty() else 0,
	}
	_refit()
	_render()
	queue_redraw()


## Everything this node shows, primitives only, with a child's summary nested under the
## child's own key. Every count is a count of what the node PAINTED, or 0 — `bound:false`
## is the empty vocabulary, so an unwired panel reads as the honest nothing rather than
## as a blank map.
func summary() -> Dictionary:
	_bind_nodes()
	return {
		"bound": _bound,
		"layers": LAYERS.duplicate(),
		"wires": _drawn.get("corridors", 0),
		"rooms": _drawn.get("rooms", 0),
		"corridors": _drawn.get("corridors", 0),
		"zones": _drawn.get("zones", 0),
		"markers": _drawn.get("markers", 0),
		"frontier_rooms": _drawn.get("frontier_rooms", 0),
		"zone_lines": _drawn.get("zone_lines", 0),
		"player_room": _player_room,
		"player_drawn": _drawn.get("player", 0),
		"scale": _scale,
		"tile_px": _tile_px,
		"bounds": _bounds.duplicate(),
		"clipped": _clipped,
		"frontier": _frontier.size(),
		"frontier_truncated": _frontier_truncated,
		"hidden_rooms": _hidden_rooms,
		"authored_rooms": _rooms.size(),
		"remembered_rooms": _remembered.size(),
		"markers_drawn": _drawn.get("markers", 0),
		"marker_kinds": _marker_kinds(),
		"tier_chips": _tier_chips(),
		"legend_rows": _legend.size(),
		"legend": _legend.duplicate(true),
		"legend_text": _text_of(_legend_label),
		"layout_rooms": _layout.size(),
		"layout_digest": _digest(),
		"glyphs": MARKER_GLYPHS.duplicate(),
		"tags": _known_tags(),
	}


## The layout this node drew from, as a stable digest of its room ids and rects.
##
## Public because it is the ONLY honest answer to "is this the module's own layout or a
## second one?" — a caller re-reads `DomainMinimap.render` and compares. `""` whenever
## the payload published no layout, so a view that re-laid-out rooms could never report
## the module's digest.
func layout_digest() -> String:
	_bind_nodes()
	return _digest()


## Every tag this payload's markers name, sorted. Published so a caller can check the
## glyph table against what was actually drawn rather than against a claim.
func marker_tags() -> Array[String]:
	_bind_nodes()
	var out: Array[String] = []
	for entry in _pois:
		var tag := String((entry as Dictionary).get("tag", ""))
		if not tag.is_empty() and not out.has(tag):
			out.append(tag)
	out.sort()
	return out


## The rooms the fog put on the seam, in the order they would be drawn.
func frontier_room_ids() -> Array[String]:
	_bind_nodes()
	var out: Array[String] = []
	for entry in _frontier:
		out.append(String((entry as Dictionary).get("room_id", "")))
	return out


## The rooms drawn at full detail, in the order they would be drawn.
func remembered_room_ids() -> Array[String]:
	_bind_nodes()
	var out: Array[String] = []
	for entry in _remembered:
		out.append(String((entry as Dictionary).get("room_id", "")))
	return out


## The room `summary.get("kind", "")` is about, or `""`. The one lookup a panel keyed
## on the SELECTED room needs, kept here so that panel holds no map of its own.
func kind_of(summary: Dictionary) -> String:
	_bind_nodes()
	var room_id := String(summary.get("room_id", ""))
	for entry in _rooms:
		var room := entry as Dictionary
		if String(room.get("room_id", "")) == room_id:
			return String(room.get("kind", ""))
	return ""


# ── the three fog bands (ADR 0207) ───────────────────────────────────────────


func _fog_bands() -> Dictionary:
	return _presentation.partition(_rooms, _authored, _routes, _layout)


## Whether `room_id` is joined to a remembered room by a route. Two bounded walks over
## arrays the module published; no map is built and no edge is written.
func _one_corridor_from(room_id: String, remembered_ids: Dictionary) -> bool:
	return _presentation.is_one_corridor_from(room_id, remembered_ids, _routes)


## Every room the RUN authored, for the frontier and the `hidden_rooms` arithmetic.
## The payload's `rooms[]` is the DISCOVERED subset, so without this list a seam could
## never reach past it and every room beyond would be counted as hidden whether it was
## adjacent or not.
##
## Setting it RE-PARTITIONS rather than merely re-reading: the authored set is what the
## frontier and the hidden count are measured against, so a summary publishing a
## partition from a list it no longer holds is the drift this closes.
func set_authored_rooms(rooms: Array) -> void:
	_bind_nodes()
	_authored = _array_of(rooms)
	var bands := _fog_bands()
	_remembered = bands["remembered"] as Array
	_frontier = bands["frontier"] as Array
	_hidden_rooms = int(bands["hidden"])
	_frontier_truncated = bool(bands["truncated"])
	_drawn["frontier_rooms"] = _count_drawable_frontier()
	_drawn["frontier_doors"] = _count_frontier_doors()
	_render()
	queue_redraw()


func _authored_room_count() -> int:
	return _authored.size() if not _authored.is_empty() else _rooms.size()


# ── what the drawing reads, counted without a frame ──────────────────────────


## Corridors the corridor layer will stroke: a route with a polyline of at least two
## points. The layer and this count read the SAME test, so `wires` cannot disagree with
## the pixels.
func _count_drawable_routes() -> int:
	return _presentation.count_routes(_routes)


## Remembered rooms with a four-number rect: exactly what both room layers draw.
func _count_filled_rooms() -> int:
	return _count_rooms_with_rect(_remembered)


## Frontier rooms with a rect in the payload's own `layout`.
func _count_drawable_frontier() -> int:
	return _count_rooms_with_rect(_frontier)


func _count_rooms_with_rect(rooms: Array) -> int:
	return _presentation.count_with_rect(rooms)


## Zones with a four-number bounds box: the hatch layer's own test.
func _count_drawable_zones() -> int:
	return _presentation.count_zones(_zones)


## Markers the marker layer will draw: a tag `POI_BY_TAG` names, a two-number anchor, and
## a REMEMBERED room. The remembered test is what makes "never on a frontier room"
## (ADR 0208) a property of the drawing rather than a promise in a comment.
func _count_drawable_markers() -> int:
	return _presentation.count_markers(_pois, _remembered_ids())


## Corridor mouths on the seam: the cost of a frontier room, and the one affordance fog
## never withholds (ADR 0207).
func _count_frontier_doors() -> int:
	return _presentation.count_frontier_doors(_frontier, _routes)


# ── the draw ─────────────────────────────────────────────────────────────────


func _draw() -> void:
	if _bounds.size() != 4 or _scale <= 0.0:
		return
	_draw_corridors()
	_draw_room_fills()
	_draw_room_outlines()
	_draw_frontier_outlines()
	_draw_zones()
	_draw_markers()
	_draw_player_room()


## The scale and the fitted rect, recomputed from THIS node's size whenever it changes.
##
## `resized` is the same recompute `world_map_screen.gd` already performs for `MapArea`,
## and it is why the view may live in an `AspectRatioContainer` rather than hard-coding
## any position: the container decides where the node is, and this decides how a tile
## becomes a pixel.
func _on_resized() -> void:
	_refit()
	queue_redraw()


func _refit() -> void:
	var box_w := float(int(_bounds[2]))
	var box_h := float(int(_bounds[3]))
	if box_w <= 0.0 or box_h <= 0.0:
		_scale = 0.0
		_tile_px = 0.0
		_inner = Rect2()
		return
	var area := size
	if area.x < 1.0 or area.y < 1.0:
		# A control the container has not sized yet has no rect to fit into. Answering
		# zero here is honest, and the `resized` that follows recomputes it.
		_scale = 0.0
		_tile_px = 0.0
		_inner = Rect2()
		return
	var scale := minf(area.x / box_w, area.y / box_h)
	# Floor-clamped at MIN_TILE_PX so a large domain zooms out to a legible blob rather
	# than to sub-pixel hairlines, and the factor actually used is published so a reader
	# can tell "as small as it goes" from "as large as it goes".
	if scale * box_w < MIN_TILE_PX * box_w:
		scale = MIN_TILE_PX
	_scale = scale
	_tile_px = scale
	var fitted := Vector2(box_w, box_h) * scale
	# Centred, never anchored to a corner: the origin is arithmetic over the payload's
	# own `bounds`, so a map drawn from a different domain is centred in exactly the same
	# way and the position is never a constant in this file.
	_inner = Rect2(
		Vector2(maxf(0.0, (area.x - fitted.x) * 0.5), maxf(0.0, (area.y - fitted.y) * 0.5)), fitted
	)
	_clipped = fitted.x > area.x + 0.5 or fitted.y > area.y + 0.5
	_sync_aspect(box_w / box_h)


## Keep the container's aspect on the payload's own, so the box the container gives this
## node is the SHAPE of the domain and the letterboxing below is slack rather than
## waste. This is the anchoring half of the reconciliation: the container decides where
## the node is and how big, and only the ratio is handed upward — a property of the map,
## not a position. Guarded because a headless test drives this node with no parent at
## all, and a missing container is not a failure.
func _sync_aspect(ratio: float) -> void:
	var container := get_parent() as AspectRatioContainer
	if container == null:
		return
	# `HEIGHT_CONTROLS_WIDTH`, so the container tracks the payload's own shape rather
	# than this node's box being distorted to fit a square it was never drawn in.
	container.stretch_mode = AspectRatioContainer.STRETCH_HEIGHT_CONTROLS_WIDTH
	if not is_equal_approx(container.ratio, ratio):
		container.ratio = ratio


## Tiles to pixels, through the fitted rect. THE ONLY coordinate conversion in this file.
func _to_pixels(tile: Vector2) -> Vector2:
	return _inner.position + (tile - Vector2(int(_bounds[0]), int(_bounds[1]))) * _scale


func _to_pixels_rect(rect: Array) -> Rect2:
	if rect.size() != 4:
		return Rect2()
	var grown := [
		float(int(rect[0])) + ROOM_INSET_TILES,
		float(int(rect[1])) + ROOM_INSET_TILES,
		maxf(0.0, float(int(rect[2])) - ROOM_INSET_TILES * 2.0),
		maxf(0.0, float(int(rect[3])) - ROOM_INSET_TILES * 2.0),
	]
	var top_left := _to_pixels(Vector2(grown[0], grown[1]))
	return Rect2(top_left, Vector2(grown[2], grown[3]) * _scale)


## Layer 1 — corridors. `routes[].points` stroked at `width` tiles. Read first, so a
## corridor sits UNDER both room layers and the door between two rooms reads as a gap
## between them rather than as a line across them.
func _draw_corridors() -> void:
	var count := 0
	for entry in _routes:
		var route := entry as Dictionary
		var points: Array = route.get("points", []) as Array
		if points.size() < 2:
			continue
		var width := maxf(DEFAULT_CORRIDOR_TILES, float(int(route.get("width", 1))))
		var index := 1
		# Bounded by the polyline's own point count, and the body draws rather than
		# appends: nothing below grows the array it walks.
		while index < points.size():
			var a := _to_pixels(_point_of(points[index - 1]))
			var b := _to_pixels(_point_of(points[index]))
			draw_line(a, b, CORRIDOR_INK, maxf(1.0, width * _scale))
			index += 1
		count += 1
	_drawn["corridors"] = count


## Layer 2 — remembered room fills.
func _draw_room_fills() -> void:
	var count := 0
	for entry in _remembered:
		var room := entry as Dictionary
		var drawn := _to_pixels_rect(room.get("rect", []) as Array)
		if drawn.size.x <= 0.0 or drawn.size.y <= 0.0:
			continue
		draw_rect(drawn, ROOM_FILL, true)
		if bool(room.get("hostile", false)):
			draw_rect(drawn, HOSTILE_INK, true)
		count += 1
	_drawn["rooms"] = count


## Layer 3 — remembered room outlines.
func _draw_room_outlines() -> void:
	var count := 0
	for entry in _remembered:
		var room := entry as Dictionary
		var rect := room.get("rect", []) as Array
		if (rect as Array).size() != 4:
			continue
		var drawn := _to_pixels_rect(rect)
		if drawn.size.x <= 0.0 or drawn.size.y <= 0.0:
			continue
		draw_rect(drawn, ROOM_EDGE, false, maxf(1.0, OUTLINE_PX))
		_draw_room_chip(room, drawn)
		count += 1
	_drawn["room_outlines"] = count


## The tier, as a TEXT CHIP beside the room's label — never a glyph upgrade and never a
## change to a marker's shape (ADR 0208). A room that is `miniboss` because a spawn role
## says so and carries no POI tag must not gain a glyph, or the marker set stops being
## tag-derived. `draw_string` is used rather than a font because the one theme owns
## widgets, not canvases; the chip is a name the payload published.
func _draw_room_chip(room: Dictionary, drawn: Rect2) -> void:
	var tier := String(room.get("tier", ""))
	if tier.is_empty() or tier == TIER_PLAIN:
		return
	var label := "%s %s" % [String(room.get("room_id", "")), tier]
	var font := _chip_font()
	if font == null:
		return
	draw_string(
		font,
		drawn.position + Vector2(CHIP_INSET_PX, CHIP_BASELINE_PX),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		CHIP_FONT_PX,
		CHIP_INK
	)


## Layer 4 — severe zones. UNFOGGED by design, both because `_zones` is unfogged in the
## module and because ADR 0170 depends on it: a hazard must be visible before you stand
## in it. Hatched by severity, because severity is a word a player reads and not a
## number a map can render.
func _draw_zones() -> void:
	var count := 0
	var lines := 0
	for entry in _zones:
		var zone := entry as Dictionary
		var box: Array = zone.get("bounds", []) as Array
		if box.size() != 4:
			continue
		var severity := String(zone.get("severity", "low"))
		var ink: Color = SEVERITY_INK.get(severity, SEVERITY_INK["low"])
		var top_left := _to_pixels(Vector2(float(int(box[0])), float(int(box[1]))))
		var drawn := Rect2(top_left, Vector2(float(int(box[2])), float(int(box[3]))) * _scale)
		if drawn.size.x <= 0.0 or drawn.size.y <= 0.0:
			continue
		draw_rect(drawn, ink, false, maxf(1.0, OUTLINE_PX))
		lines += _hatch(drawn, ink)
		count += 1
	_drawn["zones"] = count
	_drawn["zone_lines"] = lines


## A zone's hatch, at a spacing derived from its own severity: denser where the module
## says the zone is worse. Bounded by the drawn rect's own size, taken before the loop,
## and the body draws rather than appends.
func _hatch(drawn: Rect2, ink: Color) -> int:
	var step := maxf(2.0, HATCH_STEP_PX)
	var lines := 0
	var offset := 0.0
	while offset < drawn.size.x + drawn.size.y:
		var a := drawn.position + Vector2(offset, 0.0)
		var b := drawn.position + Vector2(maxf(0.0, drawn.size.x - offset), drawn.size.y)
		draw_line(a, b, ink, 1.0)
		lines += 1
		offset += step
	return lines


## Layer 5 — POI markers. The glyph is chosen by the payload's AUTHORED TAG alone, and
## the anchor is the payload's verbatim. A frontier room is not in `_pois` (the module
## only emits markers for rooms it drew) and the frontier loop below draws no marker, so
## an unfilled outline carries none.
func _draw_markers() -> void:
	var count := 0
	for entry in _pois:
		var poi := entry as Dictionary
		var tag := String(poi.get("tag", ""))
		var shape := String(MARKER_GLYPHS.get(POI_BY_TAG.get(tag, ""), ""))
		if shape.is_empty():
			# A tag `POI_BY_TAG` does not name marks nothing, and this node has no
			# fallback to hide the module's own skip behind.
			continue
		if not _remembered_ids().has(String(poi.get("room_id", ""))):
			continue
		var anchor: Array = poi.get("anchor", []) as Array
		if anchor.size() != 2:
			continue
		_draw_glyph(
			shape,
			_to_pixels(Vector2(float(int(anchor[0])), float(int(anchor[1])))),
			maxf(2.0, MARKER_RADIUS_TILES * _scale)
		)
		count += 1
	_drawn["markers"] = count


## One glyph, by silhouette. Five shapes and no fallbacks: at minimap scale colour alone
## is unreadable and shape is what survives (ADR 0208).
func _draw_glyph(shape: String, at: Vector2, radius: float) -> void:
	match shape:
		"open_circle":
			draw_arc(at, radius, 0.0, TAU, 18, MARKER_INK, maxf(1.0, radius * 0.28), true)
		"diamond":
			_draw_diamond(at, radius)
		"nested":
			_draw_nested(at, radius)
		"chevron":
			draw_polyline(
				PackedVector2Array(
					[
						at + Vector2(0.0, -radius),
						at + Vector2(radius, radius * 0.5),
						at + Vector2(-radius, radius * 0.5),
						at + Vector2(0.0, -radius),
					]
				),
				MARKER_INK,
				maxf(1.0, radius * 0.28),
				true
			)
		"boss_ring":
			draw_circle(at, radius * 0.62, MARKER_INK)
			draw_arc(at, radius, 0.0, TAU, 20, MARKER_INK, maxf(1.0, radius * 0.22), true)


func _draw_diamond(at: Vector2, radius: float) -> void:
	var points := PackedVector2Array(
		[
			at + Vector2(0.0, -radius),
			at + Vector2(radius, 0.0),
			at + Vector2(0.0, radius),
			at + Vector2(-radius, 0.0),
		]
	)
	draw_colored_polygon(points, MARKER_INK)


func _draw_nested(at: Vector2, radius: float) -> void:
	draw_rect(
		Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0),
		MARKER_INK,
		false,
		maxf(1.0, radius * 0.26)
	)
	draw_rect(
		Rect2(at - Vector2(radius * 0.5, radius * 0.5), Vector2(radius, radius)),
		MARKER_INK,
		false,
		maxf(1.0, radius * 0.26)
	)


## Layer 6 — the player's room. Drawn on the REMEMBERED band only: "you are here" is the
## one thing fog must never qualify, and a player who cannot locate themselves has no
## frame for any of the frontier's affordances.
func _draw_player_room() -> void:
	var room := _room_by_id(_player_room)
	if room.is_empty():
		_drawn["player"] = 0
		return
	var rect: Array = room.get("rect", []) as Array
	if rect.size() != 4:
		_drawn["player"] = 0
		return
	var drawn := _to_pixels_rect(rect)
	if drawn.size.x <= 0.0 or drawn.size.y <= 0.0:
		_drawn["player"] = 0
		return
	draw_rect(drawn, PLAYER_INK, false, maxf(2.0, OUTLINE_PX * 2.0))
	_drawn["player"] = 1


## The frontier's own layer, drawn between room outlines and zones so a seam is never
## hidden behind a remembered room's fill. Outline ONLY: no fill, no marker, no name, no
## tier — the seam IS the information (ADR 0207).
func _draw_frontier_outlines() -> void:
	var count := 0
	for entry in _frontier:
		var room := entry as Dictionary
		var room_id := String(room.get("room_id", ""))
		var rect := _layout_rect(room_id)
		if rect.is_empty():
			continue
		var drawn := _to_pixels_rect(rect)
		if drawn.size.x <= 0.0 or drawn.size.y <= 0.0:
			continue
		draw_rect(drawn, FRONTIER_EDGE, false, maxf(1.0, OUTLINE_PX))
		_draw_corridor_mouths(room_id, drawn)
		count += 1
	_drawn["frontier_rooms"] = count


## How many doors a frontier outline has, drawn as short ticks on its edge. The
## corridor COUNT is what fog never withholds, because it is the cost of the room: two
## doors is a detour and one is the shortest way in.
func _draw_corridor_mouths(room_id: String, drawn: Rect2) -> void:
	var mouths := 0
	for entry in _routes:
		var route := entry as Dictionary
		if not _route_touches(route, room_id):
			continue
		draw_arc(
			drawn.get_center(),
			minf(drawn.size.x, drawn.size.y) * 0.5,
			0.0,
			TAU,
			16,
			FRONTIER_EDGE,
			maxf(1.0, OUTLINE_PX)
		)
		mouths += 1
	_drawn["frontier_doors"] = int(_drawn.get("frontier_doors", 0)) + mouths


func _route_touches(route: Dictionary, room_id: String) -> bool:
	return String(route.get("from", "")) == room_id or String(route.get("to", "")) == room_id


# ── plumbing ─────────────────────────────────────────────────────────────────


## Resolved lazily and idempotently, never in an annotation: the headless runner drives
## this panel before a scene tree exists (AGENTS.md, UI standard). Guarded `_draw` and
## `summary()` both read through here, so a test that never instantiates the scene still
## gets the empty vocabulary rather than a null dereference.
func _bind_nodes() -> void:
	if _bound_nodes:
		return
	_bound_nodes = true
	_legend_label = get_node_or_null("%LegendLabel") as Label
	_render()


## The legend, as one `Label` holding BBCode — five glyph names beside the five tags.
##
## ## Why a Label and not five row widgets
##
## A `VBoxContainer` of `Label`s would be five `Control`s re-parented on every refresh,
## which is the per-refresh churn INC-0002/INC-0041 warn about, for five lines that
## change only when the payload's tags change. One label is one widget.
func _render() -> void:
	if _legend_label == null:
		return
	_legend_label.text = _legend_text()


func _legend_text() -> String:
	if not _bound:
		return LEGEND_UNWIRED_TEXT
	if _legend.is_empty():
		return "No marker vocabulary in this floor plan yet."
	var lines: Array[String] = []
	for row in _legend:
		(
			lines
			. append(
				(
					"%s — %s (%s)"
					% [
						String(row["glyph"]),
						String(row["promise"]),
						String(row["tag"]),
					]
				)
			)
		)
	return "\n".join(lines)


## The font a canvas string needs. `ThemeDB.fallback_font` rather than the one theme,
## because the theme types widgets and a `_draw` call draws pixels: a `Label` child would
## be a second widget per room and a `SystemFont` resource would be style this program
## does not own. Null only when the engine publishes no fallback at all, and the chip
## then simply is not drawn rather than crashing a repaint.
func _chip_font() -> Font:
	if _chip_font_cache == null:
		_chip_font_cache = ThemeDB.fallback_font
	return _chip_font_cache


# ── payload readers. Each takes one key and invents nothing ──────────────────


func _array_of(value: Variant) -> Array:
	return value as Array if value is Array else []


func _box_of(value: Variant) -> Array:
	var box := _array_of(value)
	return box.duplicate() if box.size() == 4 else [0, 0, 0, 0]


func _point_of(value: Variant) -> Vector2:
	var pair := _array_of(value)
	if pair.size() != 2:
		return Vector2.ZERO
	return Vector2(float(int(pair[0])), float(int(pair[1])))


## The payload's `layout`, verbatim: one `{room_id, rect}` per entry, in the payload's
## own key order. A COPY rather than a re-layout, and `layout_digest()` is published so
## a caller can prove it.
func _layout_rows(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not value is Dictionary:
		return out
	var ids: Array = (value as Dictionary).keys()
	ids.sort()
	for room_id in ids:
		var rect := _array_of((value as Dictionary)[room_id])
		if rect.size() != 4:
			continue
		out.append({"room_id": String(room_id), "rect": rect.duplicate()})
	return out


func _layout_rect(room_id: String) -> Array:
	for entry in _layout:
		if String(entry["room_id"]) == room_id:
			return entry["rect"] as Array
	return []


func _room_by_id(room_id: String) -> Dictionary:
	if room_id.is_empty():
		return {}
	for entry in _rooms:
		var room := entry as Dictionary
		if String(room.get("room_id", "")) == room_id:
			return room
	return {}


func _remembered_ids() -> Dictionary:
	var out := {}
	for entry in _remembered:
		out[String((entry as Dictionary).get("room_id", ""))] = true
	return out


func _marker_kinds() -> Array[String]:
	var out: Array[String] = []
	for tag in marker_tags():
		var shape := String(MARKER_GLYPHS.get(POI_BY_TAG.get(tag, ""), ""))
		if not shape.is_empty() and not out.has(shape):
			out.append(shape)
	out.sort()
	return out


## The tiers drawn as chips, sorted, so a caller can assert that a tier never became a
## glyph: this list is text, and `marker_kinds` is shape, and the two are separate keys
## for exactly that reason.
func _tier_chips() -> Array[String]:
	return _presentation.tier_chips_in(_remembered)


func _legend_rows() -> Array[Dictionary]:
	return _presentation.legend_for(_pois)


## Every tag `POI_BY_TAG` names, sorted. Published so a test can assert the closed
## vocabulary against the module's own without naming a module type.
func _known_tags() -> Array[String]:
	return _presentation.known_tags()


## A stable digest of the layout this node drew. `"room@x,y,w,h"` rows joined by `;`,
## so two dicts with different key orders compare equal and two layouts never do.
func _digest() -> String:
	if _layout.is_empty():
		return ""
	var rows: Array[String] = []
	for entry in _layout:
		var rect := entry["rect"] as Array
		rows.append(
			(
				"%s@%d,%d,%d,%d"
				% [String(entry["room_id"]), int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3])]
			)
		)
	return ";".join(rows)


func _by_room_id(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("room_id", "")) < String(b.get("room_id", ""))


func _text_of(label: Label) -> String:
	return "" if label == null else label.text
