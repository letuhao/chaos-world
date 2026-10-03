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
## (BL-0204's rule applied to holdings). Nothing here computes a yield or a realm.

static var _shared: ResourceNodeCatalog = null

var _defs: Dictionary = {}


static func instance() -> ResourceNodeCatalog:
	if _shared == null:
		_shared = ResourceNodeCatalog.new()
	return _shared


## Install a set of authored defs. Idempotent per id: installing the same id twice is a
## content bug worth shouting about, because the second would silently win.
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
	return _defs.get(String(node_id))


func node_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in _defs.keys():
		out.append(StringName(key))
	out.sort()
	return out


func has_definition(node_id: StringName) -> bool:
	return _defs.has(String(node_id))


## Every node as a primitive view, for a reader that wants the whole catalog in one call.
func views() -> Array:
	var out: Array = []
	for node_id in node_ids():
		var def := definition(node_id)
		if def != null:
			out.append(def.to_dict())
	return out


## Test seam: drop every authored node.
func reset() -> void:
	_defs.clear()


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
