class_name WorldDefIndex
extends RefCounted

## One id→def index over the authored world families the runtime NAMES from:
## `faction` and `tier` today, because `WorldApi.locations()` reports a location's
## faction and tier and could only hand back raw ids — the authored
## `WorldFactionDef`/`WorldTierDef` catalogs had no production reader at all
## (BL-0227, re-measured 2026-10-09). A family earns a row here the day a production
## read needs its display name; `law` and `inhabitant` wait for the ADR 0019
## creation ritual, which is the lane that will author them.
##
## Scan discipline is `ContentScan.files_under` plus a `script_class` text test —
## the rule `WorldLocationCatalog` and every peer catalog follow — so a `.tres` of
## another resource type in the folder is skipped rather than mis-cast, and the
## walk is depth-capped. Lazy per family and cached for the process.

const FAMILIES := {
	&"faction":
	{
		"dir": "res://data/world/factions",
		"script_class": "WorldFactionDef",
		"id_field": &"faction_id",
	},
	&"tier":
	{
		"dir": "res://data/world/tiers",
		"script_class": "WorldTierDef",
		"id_field": &"tier_id",
	},
}

static var _defs: Dictionary = {}


## Every authored id of `family`, canonically ordered. `[]` for a family this index
## does not serve, so a typo is an empty answer and never a crash.
static func ids(family: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for key in _definitions(family).keys():
		out.append(StringName(key))
	out.sort()
	return out


## One def, or null when the id is unknown. Null rather than a guess: an unknown id
## is a content bug, and inventing a definition would hide it.
static func definition(family: StringName, def_id: StringName) -> Resource:
	return _definitions(family).get(String(def_id)) as Resource


## The def's authored display name (a LOC key a reader resolves), or "" when the id
## is unknown. The one string `locations()` rows and the map screen both render.
static func display_name(family: StringName, def_id: StringName) -> String:
	var def := definition(family, def_id)
	return String((def as Resource).get("display_name")) if def != null else ""


static func _definitions(family: StringName) -> Dictionary:
	if not FAMILIES.has(family):
		return {}
	if _defs.has(family):
		return _defs[family] as Dictionary
	var row := FAMILIES[family] as Dictionary
	var out := {}
	for path in ContentScan.files_under(String(row["dir"])):
		var text := FileAccess.get_file_as_string(path)
		if not text.contains('script_class="%s"' % String(row["script_class"])):
			continue
		var def := load(path) as Resource
		if def == null:
			continue
		var def_id := String(def.get(row["id_field"]))
		if def_id != "":
			out[def_id] = def
	_defs[family] = out
	return out
