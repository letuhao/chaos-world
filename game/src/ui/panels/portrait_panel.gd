class_name PortraitPanel
extends PanelContainer

## The face the resolver gives this actor, and what it was resolved from.
##
## ## Why the picture is a `TextureRect` and the words are a row of labels
##
## ADR 0131 hands `ui/` a primitives-only dictionary of layer paths and a palette
## KEY, never a `PortraitDef` and never an asset index row. So this panel composes
## those layer paths back to front, sizes itself inside its container, and prints
## the resolution `source` — `chosen` / `race` / `generated` / `placeholder` —
## beside the id. **The source is the load-bearing part**: a fallback that looked
## deliberate is how a content gap hides, and ADR 0131 names exactly that as the
## thing the resolver's `source` exists to prevent.
##
## ## A missing file is stated, never swallowed
##
## Resolution is total (ADR 0131), so this panel always has an id and always has a
## `source`. A layer path the engine cannot load is therefore a CONTENT gap and the
## panel says which path, rather than painting an empty box that reads as "no face
## authored" — which is a different defect and one the placeholder exists to prevent.
##
## Contract: `summary()` is the testable surface, primitives only.

const NO_ACTOR := "No face is resolved, because no hero is bound."
const PLACEHOLDER_MARK := "This is the placeholder every actor resolves to."
## The header prefix per `source`. Named here because the vocabulary is the
## resolver's, and the panel must not invent a fourth word for it.
const SOURCE_LABEL := {
	"chosen": "Chosen at creation",
	"race": "The face of this body plan",
	"generated": "The generated face for this body plan",
	"placeholder": "The fallback face",
	"none": "Nothing",
	"": "Unresolved",
}

var _view: Dictionary = {}
var _id_line: String = ""
var _source_line: String = ""
var _layer_line: String = ""
var _missing_line: String = ""
var _name_label: Label = null
var _id_label: Label = null
var _source_label: Label = null
var _layer_label: Label = null
var _missing_label: Label = null
var _texture: TextureRect = null
var _bound: bool = false
## Layers that load but do not match the base canvas, recorded DURING the paint rather
## than recomputed: `summary()` asks on every read, and reloading every layer to answer
## a question the paint already knew the answer to is a second decode per frame.
var _mismatched: Array = []


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one resolved portrait, exactly as `PortraitResolver.resolve` publishes it.
## An empty dictionary clears the panel, which is what an unbound screen shows.
func show_portrait(view: Dictionary) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_id_line = _id_text()
	_source_line = _source_text()
	_layer_line = _layer_text()
	_missing_line = _missing_text()
	_render()


## Everything this panel shows, primitives only.
func summary() -> Dictionary:
	_bind_nodes()
	return {
		"resolved": not _view.is_empty(),
		"portrait_id": String(_view.get("portrait_id", "")),
		"race_id": String(_view.get("race_id", "")),
		"palette_key": String(_view.get("palette_key", "")),
		"form": String(_view.get("form", "")),
		"source": String(_view.get("source", "")),
		"is_placeholder": bool(_view.get("is_placeholder", false)),
		"layer_paths": _paths(),
		"layer_count": _paths().size(),
		"composited": _paths().size() - _missing().size() - _mismatched.size(),
		"drawn": _texture != null and _texture.texture != null,
		"missing_layers": _missing(),
		"mismatched_layers": _mismatched.duplicate(),
		"id_line": _id_line,
		"source_line": _source_line,
		"layer_line": _layer_line,
		"missing_line": _missing_line,
	}


## The portrait id on show, or `""`. A report, never a selection: ADR 0131 says
## appearance grants no stat and this panel publishes no verb that could change a
## face, so there is nothing here a caller could pick.
func portrait_id() -> String:
	return String(_view.get("portrait_id", ""))


## Whether the panel resolved to the mandatory placeholder. Reported rather than
## rendered alone, because a run where every actor is a placeholder is a CONTENT
## failure and the only place it is visible is here.
func is_placeholder() -> bool:
	return bool(_view.get("is_placeholder", false))


# --- Plumbing ---------------------------------------------------------------


## Resolved lazily, never in `@onready`: the headless runner drives this panel
## before a scene tree exists. Idempotent by construction — nothing is cached
## across calls.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _bound:
		return
	_name_label = get_node_or_null("%PortraitNameLabel") as Label
	_id_label = get_node_or_null("%PortraitIdLabel") as Label
	_source_label = get_node_or_null("%PortraitSourceLabel") as Label
	_layer_label = get_node_or_null("%LayerLabel") as Label
	_missing_label = get_node_or_null("%MissingLabel") as Label
	_texture = get_node_or_null("%PortraitTexture") as TextureRect
	_bound = _id_label != null and _texture != null


func _render() -> void:
	if _id_label == null:
		return
	_name_label.text = _display_name()
	_id_label.text = _id_line
	_source_label.text = _source_line
	_source_label.theme_type_variation = &"WarnLabel" if is_placeholder() else &"MetaLabel"
	_layer_label.text = _layer_line
	_missing_label.text = _missing_line
	_missing_label.visible = not _missing_line.is_empty()
	_paint()


## Paint the portrait by COMPOSING every layer that loads, back to front.
##
## `PortraitDef.layer_paths` is "the composable layers, back to front... which is
## what lets the same body plan read differently per occasion"
## (`core/portrait_def.gd:37-39`), and this used to load the FIRST loadable layer
## and return — so a regalia overlay, a faction variant or a second expression
## frame was structurally addressable and visually discarded (ADR 0177). One
## layer still composes to exactly itself, so the single-layer case is unchanged.
##
## **The first layer that loads is the base and it defines the canvas.** A later
## layer of a different size is SKIPPED and reported rather than scaled or
## cropped: `tools/unique_characters.py:_validate_image` already refuses an
## installed PNG that does not match its shot's declared canvas exactly, so a
## mismatched layer is a content gap by the same rule, and silently fitting it
## would hide it twice.
##
## Two loaders, because a layer path is a plain authored string and the repo has no
## import guarantee over it: an IMPORTED resource resolves through `ResourceLoader`,
## and a raw file the generator wrote resolves through `Image.load_from_file`.
## Returned as `Image` and NOT as `Variant`, because a Variant return makes the
## caller's `:=` infer Variant — which this project treats as a warning-as-error —
## and makes `get_size()` untyped, which `Rect2i`'s constructor rejects. A path
## that cannot be loaded returns null and must read as "no texture" rather than
## abort the repaint.
func _paint() -> void:
	if _texture == null:
		return
	_texture.texture = null
	_mismatched = []
	# Snapshot of the authored array; the body reads it and never grows it, so the
	# `for` is bounded by data rather than by anything this loop can change.
	var base: Image = null
	for path in _paths():
		var layer: Image = _load_image(String(path))
		if layer == null:
			continue
		if base == null:
			# Duplicated because `blend_rect` mutates its destination, and a layer that
			# came from `ResourceLoader` is shared with the engine's cache.
			base = layer.duplicate()
			continue
		if layer.get_size() != base.get_size():
			_mismatched.append(String(path))
			continue
		base = _over(base, layer)
	if base != null:
		_texture.texture = ImageTexture.create_from_image(base)


## `top` composited over `bottom`, both the same size, returning a NEW image.
##
## Written out longhand rather than via `Image.blend_rect` on purpose. The engine's argument
## order for that call does not match the documented `(src, src_rect, blend)` — it rejects a
## `float` third argument and asks for a `Vector2i` — and guessing at it would put a
## silently-wrong blend in the one place a face is drawn. `Color.blend` is stable, and
## [method test_two_layers_are_both_drawn_not_just_the_first] asserts the resulting PIXEL, so
## this is verified by evidence rather than by an API assumption.
##
## LOOP GUARD: the bounds are read from the two images BEFORE either `for`, and neither loop
## changes a width or a height, so each runs exactly `width * height` times. Nothing here can
## grow the thing being measured — the INC-0002 shape.
func _over(bottom: Image, top: Image) -> Image:
	var width := bottom.get_width()
	var height := bottom.get_height()
	var out := Image.create_empty(width, height, false, bottom.get_format())
	for y in height:
		for x in width:
			out.set_pixel(x, y, top.get_pixel(x, y).blend(bottom.get_pixel(x, y)))
	return out


## A layer path as an `Image`, or null. Never throws: a path that cannot be loaded is
## a content gap, and [method _missing_text] is what reports it.
func _load_image(path: String) -> Image:
	if ResourceLoader.exists(path):
		var resource = ResourceLoader.load(path)
		if resource is Texture2D:
			return (resource as Texture2D).get_image()
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return image


## The authored display name when the resolver published one, else the id. The
## resolver publishes no name — it is a primitives-only view — so this falls back
## to the id rather than inventing one.
func _display_name() -> String:
	var id := portrait_id()
	return id.capitalize() if not id.is_empty() else "No face"


func _id_text() -> String:
	if _view.is_empty():
		return NO_ACTOR
	var id := portrait_id()
	if id.is_empty():
		return NO_ACTOR
	return "Portrait %s" % id


## Which of the resolver's three named steps answered, in the resolver's own words.
## The placeholder says so in a second sentence rather than only in colour.
func _source_text() -> String:
	if _view.is_empty():
		return ""
	var source := String(_view.get("source", ""))
	var line := "%s." % String(SOURCE_LABEL.get(source, "Unresolved"))
	if is_placeholder():
		return "%s %s" % [line, PLACEHOLDER_MARK]
	return line


## The palette KEY, never a colour: styling belongs to the one theme and a literal
## colour in content is a second place to retune it (ADR 0131).
func _layer_text() -> String:
	if _view.is_empty():
		return ""
	var parts: Array[String] = []
	var palette := String(_view.get("palette_key", ""))
	if not palette.is_empty():
		parts.append("palette %s" % palette)
	var form := String(_view.get("form", ""))
	if not form.is_empty():
		parts.append("form %s" % form)
	return "  ".join(parts)


## Any layer path the engine cannot load, named. A content gap stated rather than a
## blank box: resolution is total, so a path that will not load is not "no face".
func _missing_text() -> String:
	var missing := _missing()
	var parts: Array[String] = []
	if not missing.is_empty():
		parts.append("Not on disk: %s" % ", ".join(missing))
	if not _mismatched.is_empty():
		parts.append("Wrong size for this portrait: %s" % ", ".join(_mismatched))
	return "  ".join(parts)


func _paths() -> Array:
	var out: Array = []
	for path in _view.get("layer_paths", []) as Array:
		var name := String(path)
		if not name.is_empty():
			out.append(name)
	return out


## Every authored layer path that will not load. A `for` over a data array, never a
## `while` whose bound the body could grow.
##
## Checks BOTH ways a layer can exist, because [method _load_image] accepts both: an IMPORTED
## resource resolves through `ResourceLoader`, and a raw PNG the generator wrote resolves only as
## a file. This used to test `ResourceLoader.exists` alone, so every raw generator-written
## portrait was drawn correctly and simultaneously reported "Not on disk" — a file that is on
## disk, on screen, and reported missing. Existence is tested rather than a decode, because
## `summary()` asks on every read and decoding a PNG per query is a second decode per frame.
func _missing() -> Array:
	var out: Array = []
	for path in _paths():
		var name := String(path)
		if not ResourceLoader.exists(name) and not FileAccess.file_exists(name):
			out.append(name)
	return out
