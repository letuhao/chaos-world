class_name ElementCatalog
extends RefCounted

## The authored element catalog (ADR 0184 §5). Reads `res://data/elements`
## the way every peer catalog reads its own tree — `ContentScan.files_under`, a
## `script_class="ElementDef"` text test so a `.tres` of another resource type
## in the same folder is skipped rather than mis-cast, and `load()` per file —
## so the elements a player encounters are content, never a literal.
##
## ## Overlay support (ADR 0184 §5)
##
## `set_overlay_roots` accepts an ordered stack of `{dir, owner,
## declared_overrides, id_field}` rows. The overlay roots are scanned AFTER the
## base root so mod content is visible; later roots overlay earlier ones.
##
## ## Code-defined defaults are separate
##
## `ElementDefaults.all()` returns the code-defined default element set (ADR
## 0004). This catalog scans authored `.tres` files. The two paths are separate:
## defaults are always present, authored files are content a mod may add.

const ELEMENTS_ROOT := "res://data/elements"
const ELEMENT_SCRIPT_CLASS := "ElementDef"

static var shared: ElementCatalog = null

## Overlay stack for the element family (ADR 0184 §5). Empty means "not wired
## yet": `_ensure_loaded` scans only the authored ELEMENTS_ROOT. When set, the
## overlay roots are scanned AFTER the base root so mod content is visible.
static var _overlay_stack: Array = []

var _defs: Dictionary = {}
var _loaded: bool = false


## Set the family's overlay stack: ordered rows of `{dir, owner,
## declared_overrides, id_field}`. Later rows overlay earlier ones.
static func set_overlay_roots(stack: Array) -> void:
	_overlay_stack = stack


## The directories to scan: base root first, then overlay roots in order.
func _scan_roots() -> Array[String]:
	var out: Array[String] = [ELEMENTS_ROOT]
	for row in _overlay_stack:
		var dir := String(row.get("dir", ""))
		if dir != "":
			out.append(dir)
	return out


static func instance() -> ElementCatalog:
	if shared == null:
		shared = ElementCatalog.new()
	return shared


## Every authored element id, canonically ordered.
func element_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _defs.keys():
		out.append(StringName(key))
	out.sort()
	return out


## One element definition, or null when the id is unknown. Null rather than a
## guess: an unknown element is a content bug, and inventing a definition
## would hide it.
func definition(element_id: StringName) -> ElementDef:
	_ensure_loaded()
	return _defs.get(String(element_id))


func has_definition(element_id: StringName) -> bool:
	_ensure_loaded()
	return _defs.has(String(element_id))


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for root in _scan_roots():
		for path in _scan(root):
			if not path.get_file().ends_with(".tres"):
				continue
			if not FileAccess.get_file_as_string(path).contains(
				'script_class="%s"' % ELEMENT_SCRIPT_CLASS
			):
				continue
			var def := load(path) as ElementDef
			if def != null and def.id != &"":
				_defs[String(def.id)] = def


## `ContentScan` is the ONE walker every catalog uses. A local `_scan` here
## would be a second implementation with its own depth rule, which is exactly
## what `tests/arch_rules/test_no_unbounded_wait.gd` cannot see through.
func _scan(root: String) -> Array[String]:
	return ContentScan.files_under(root)
