class_name ResourceNodeCatalog
extends RefCounted

## The authored resource-node catalog (ADR 0097). Mirrors `NpcCatalog` and `SectCatalog`: a
## singleton of `ResourceNodeDef` resources with a test seam, so a suite installs exactly
## the nodes it needs and `app/` loads the authored `.tres` set.
##
## ## A def that fails to load is dropped, not kept as null
##
## A node that fails to load and a node that was never authored answer "no such node" to a
## caller, so keeping a null would hide a content bug behind a game rule. Both are pushed
## as errors instead.
##
## ## Authored content, never code
##
## Every node is a `.tres` under `res://data/holdings/nodes/`, so adding a mine is content
## (BL-0204's rule applied to holdings). Nothing here computes a yield or a realm. The tree
## is scanned the way `SectCatalog` scans `res://data/sect`: a lazy `_ensure_loaded`, a
## `script_class=` text test so a `.tres` of another resource type in the same folder is
## skipped rather than mis-cast, and `ContentScan.files_under` for the walk itself.

## `res://data/holdings/nodes` — the authored resource-node definitions.
const NODES_ROOT := "res://data/holdings/nodes"
## The `script_class` a `.tres` must declare to be read as a node.
const NODE_SCRIPT_CLASS := "ResourceNodeDef"

static var _shared: ResourceNodeCatalog = null

var _defs: Dictionary = {}
var _loaded: bool = false


static func instance() -> ResourceNodeCatalog:
	if _shared == null:
		_shared = ResourceNodeCatalog.new()
	return _shared


## Install a set of authored defs. Idempotent per id: installing the same id twice is a
## content bug worth shouting about, because the second would silently win.
##
## ## `install` does NOT scan, and it must not
##
## This is the TEST seam, and the two paths are kept apart deliberately:
##
##   - `install` is explicit and immediate, so a suite can install exactly the two nodes it
##     needs and every assertion is independent of what content the build happens to ship;
##   - `node_ids`, `definition`, `views` and `validate` are the PRODUCTION reads, and each
##     calls `_ensure_loaded` first — so a process that never calls `install` still sees
##     every authored `.tres`.
##
## Merging them would make every holdings test depend on authored content, and a test that
## reads a test's fixtures for its own answer is not a test.
func install(defs: Array[ResourceNodeDef]) -> void:
	for def in defs:
		if def == null or def.node_id == &"":
			push_error("Holdings: a node def shipped with no node_id")
			continue
		if _defs.has(String(def.node_id)):
			push_error("Holdings: duplicate node id '%s'" % def.node_id)
			continue
		_defs[String(def.node_id)] = def


func definition(node_id: StringName) -> ResourceNodeDef:
	_ensure_loaded()
	return _defs.get(String(node_id))


func node_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _defs.keys():
		out.append(StringName(key))
	out.sort()
	return out


func has_definition(node_id: StringName) -> bool:
	_ensure_loaded()
	return _defs.has(String(node_id))


## Every node as a primitive view, for a reader that wants the whole catalog in one call.
func views() -> Array:
	_ensure_loaded()
	var out: Array = []
	for node_id in node_ids():
		var def := definition(node_id)
		if def != null:
			out.append(def.to_dict())
	return out


## Test seam: drop every authored node **and** forget that the tree was ever read, so the
## next real read scans it again. Clearing `_loaded` as well as `_defs` is what makes this
## a seam rather than a one-way door: a suite that resets the singleton and then asserts
## against shipped content would otherwise see a permanently empty catalog.
func reset() -> void:
	_defs.clear()
	_loaded = false


## Read the authored tree once. **An absent directory is empty, not a crash** — the same
## rule `SectCatalog` follows, and for the same reason: `tools test` may run before a single
## `.tres` is authored, and a catalog that raised on a missing tree would make the whole
## suite unrunnable at exactly the moment somebody is building the first one.
##
## `ContentScan` is the ONE walker every catalog uses. A local `_scan` here would be a
## second implementation with its own depth rule, which is precisely what
## `tests/arch_rules/test_no_unbounded_wait.gd` cannot see through: a recursive walk is a
## `while` in disguise, so a copy with no `MAX_DEPTH` cap is invisible to the guard that
## exists for it.
func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path in _scan(NODES_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains(
			'script_class="%s"' % NODE_SCRIPT_CLASS
		):
			continue
		var def := load(path) as ResourceNodeDef
		if def == null or def.node_id == &"":
			continue
		_defs[String(def.node_id)] = def


func _scan(root: String) -> Array[String]:
	return ContentScan.files_under(root)


## Content audit. A node with a zero yield is decoration — claimable, holdable, chargeable,
## and producing nothing — so it fails rather than shipping.
static func validate() -> Array[String]:
	var problems: Array[String] = []
	var known := instance()
	if known.node_ids().is_empty():
		problems.append("holdings: no resource nodes are authored")
		return problems
	for node_id in known.node_ids():
		var def := known.definition(node_id)
		if def.yield_per_period <= 0:
			problems.append("node '%s' yields nothing" % node_id)
		if not ResourceNodeDef.KINDS.has(def.normalized_kind()):
			problems.append("node '%s' has kind '%s', outside the closed set" % [node_id, def.kind])
	return problems
