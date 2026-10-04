class_name PortraitPanel
extends PanelContainer

## The face the resolver gives this actor, and what it was resolved from.
##
## ## Why the picture is a `TextureRect` and the words are a row of labels
##
## ADR 0131 hands `ui/` a primitives-only dictionary of layer paths and a palette
## KEY, never a `PortraitDef` and never an asset index row. So this panel applies
## the first layer path it can load, sizes itself inside its container, and prints
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
		"drawn": _texture != null and _texture.texture != null,
		"missing_layers": _missing(),
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


## Load the FIRST layer path that resolves and leave the box empty otherwise. First
## rather than last: a composable portrait is authored back to front, so the first
## layer is the one that identifies the face and the others are the finish.
##
## Two loaders, because a layer path is a plain authored string and the repo has no
## import guarantee over it: an IMPORTED resource resolves through `ResourceLoader`,
## and a raw file the generator wrote resolves through `Image.load_from_file`. The
## typed `Variant` is deliberate — a `:=` on an untyped load is a warning-as-error in
## this project, and an image that fails to load must read as "no texture" rather
## than abort the repaint.
func _paint() -> void:
	if _texture == null:
		return
	_texture.texture = null
	for path in _paths():
		var image = _load_texture(String(path))
		if image != null:
			_texture.texture = image as Texture2D
			return


## A layer path as a texture, or null. Never throws: a path that cannot be loaded is
## a content gap, and [method _missing_text] is what reports it.
func _load_texture(path: String) -> Variant:
	if ResourceLoader.exists(path):
		var resource = ResourceLoader.load(path)
		if resource is Texture2D:
			return resource
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


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
	if missing.is_empty():
		return ""
	return "Not on disk: %s" % ", ".join(missing)


func _paths() -> Array:
	var out: Array = []
	for path in _view.get("layer_paths", []) as Array:
		var name := String(path)
		if not name.is_empty():
			out.append(name)
	return out


## Every authored layer path that will not load. A `for` over a data array, never a
## `while` whose bound the body could grow.
func _missing() -> Array:
	var out: Array = []
	for path in _paths():
		if not ResourceLoader.exists(path):
			out.append(String(path))
	return out
