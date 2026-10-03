class_name NpcCatalog
extends RefCounted

## The authored individual catalog (ADR 0077). Mirrors `RaceCatalog`: a singleton of
## `NpcDef` resources, with a test seam so a suite can install exactly the cast it needs.

static var _shared: NpcCatalog = null

var _defs: Dictionary = {}


static func instance() -> NpcCatalog:
	if _shared == null:
		_shared = NpcCatalog.new()
	return _shared


func install(defs: Array[NpcDef]) -> void:
	for def in defs:
		if def == null or def.npc_id == &"":
			continue
		_defs[String(def.npc_id)] = def


func definition(npc_id: StringName) -> NpcDef:
	return _defs.get(String(npc_id))


func npc_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in _defs.keys():
		out.append(StringName(key))
	out.sort()
	return out


func has_definition(npc_id: StringName) -> bool:
	return _defs.has(String(npc_id))


## Test seam: drop every authored individual.
func reset() -> void:
	_defs.clear()
