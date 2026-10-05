class_name SectCatalog
extends RefCounted

## The authored sect content tree, loaded once and cached.
##
## Sect definitions live in `res://data/sect/` and are ordinary `.tres` resources
## carrying a `script_class`, loaded the same way `FateCatalog` loads its tree: a
## text scan for `script_class=` so a `.tres` belonging to some other resource type
## in the same directory is skipped rather than mis-cast.
##
## **An absent directory is empty, not a crash.** `tools test` may run before a
## single `.tres` is authored, and a catalog that raises on a missing tree makes
## the whole suite unrunnable at exactly the moment someone is building the first
## one. An unanswered question is an empty catalog, and `SectState.normalize`
## treats an empty known-content filter as "accept what you were handed" rather
## than "deny everything" — which is the same rule `destiny` and `race` follow.

## `res://data/sect` — the authored sect definitions.
const SECTS_ROOT := "res://data/sect"
## The `script_class` a `.tres` must declare to be read as a sect.
const SECT_SCRIPT_CLASS := "SectDef"
## Where the shipped balance lives, so a political cost is a `.tres` edit rather
## than a literal in a `.gd` (ADR 0067's `CombatTuning` shape).
const TUNING_PATH := "res://src/modules/sect/sect_tuning.tres"

static var shared: SectCatalog = null

var _sects: Dictionary = {}
var _positions: Dictionary = {}
var _tuning: SectTuning = null
var _loaded: bool = false


static func instance() -> SectCatalog:
	if shared == null:
		shared = SectCatalog.new()
	return shared


## Every authored sect id, canonically ordered.
func sect_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _sects.keys():
		out.append(StringName(key))
	out.sort()
	return out


## One sect definition, or null when the id is unknown. Null rather than a guess:
## a sect nothing defines teaches nothing and grants nothing, and inventing one
## would hide a content bug behind a working-looking join.
func sect_definition(sect_id: StringName) -> SectDef:
	_ensure_loaded()
	return _sects.get(String(sect_id))


## Every office id any authored sect ships, keyed to the sect that authors it.
##
## ## Why the allowlist spans every sect and not one
##
## `SectState.normalize` is handed this as its known-content filter, and it has
## to answer a single question about a single claim: is the position named in
## this save a position this build still ships? A position belongs to a sect, and
## a claim names a sect too, so a stricter filter would be possible — but a
## player who switches sect and then loads a save whose claim predates the switch
## would lose the office they legitimately held. The union is the conservative
## answer, and it is the same one `DestinyState` makes across two unrelated
## fates and destinies.
func known_position_ids() -> Dictionary:
	_ensure_loaded()
	return _positions.duplicate()


## The sect that authors `position_id`, or null. This is what lets a caller that
## was handed a bare office id — a save, a quest, a nation filling its board —
## find out which institution it belongs to without also carrying the sect id.
func sect_of_position(position_id: StringName) -> StringName:
	_ensure_loaded()
	return _positions.get(String(position_id), &"")


## The shipped balance. Loaded from the `.tres`, never built in code, so a
## rebalance is a data edit (ADR 0067). A missing `.tres` yields a degenerate
## instance whose costs are zero — deliberately obviously wrong rather than
## plausibly free.
func tuning() -> SectTuning:
	_ensure_loaded()
	if _tuning == null:
		_tuning = SectTuning.shipped()
	if _tuning == null:
		_tuning = SectTuning.new()
	return _tuning


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path in _scan(SECTS_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains(
			'script_class="%s"' % SECT_SCRIPT_CLASS
		):
			continue
		var def := load(path) as SectDef
		if def == null or def.id == &"":
			continue
		_sects[String(def.id)] = def
		for position_id in def.position_ids():
			_positions[String(position_id)] = StringName(def.id)


func _scan(root: String) -> Array[String]:
	return ContentScan.files_under(root)
