class_name SectCatalog
extends RefCounted

## The authored sect content tree, loaded once and cached.
##
## Sect definitions live in `res://data/packs/sect/organizations/` and are ordinary
## `.tres` resources carrying a `script_class`, loaded the same way `FateCatalog` loads its tree: a
## text scan for `script_class=` so a `.tres` belonging to some other resource type
## in the same directory is skipped rather than mis-cast.
##
## **An absent directory is empty, not a crash.** `tools test` may run before a
## single `.tres` is authored, and a catalog that raises on a missing tree makes
## the whole suite unrunnable at exactly the moment someone is building the first
## one. An unanswered question is an empty catalog, and `SectState.normalize`
## treats an empty known-content filter as "accept what you were handed" rather
## than "deny everything" — which is the same rule `destiny` and `race` follow.

## `res://data/packs/sect/organizations` — the authored sect definitions.
const SECTS_ROOT := "res://data/packs/sect/organizations"
## The `script_class` a `.tres` must declare to be read as a sect.
const SECT_SCRIPT_CLASS := "SectDef"
## The def property holding this family's id.
const SECT_ID_FIELD := "id"
## The owner tag for the base content root.
const BASE_OWNER := "base"
## Where the shipped balance lives, so a political cost is a `.tres` edit rather
## than a literal in a `.gd` (ADR 0067's `CombatTuning` shape).
const TUNING_PATH := "res://src/modules/sect/sect_tuning.tres"

static var shared: SectCatalog = null

## Overlay stack for the sect family (ADR 0184 §5). Empty means "not wired
## yet": `_ensure_loaded` merges only the authored SECTS_ROOT. When set, the
## overlay roots merge AFTER the base root so mod content is visible, with the
## declared-override collision policy CatalogOverlay enforces.
static var _overlay_stack: Array = []

var _sects: Dictionary = {}
var _positions: Dictionary = {}
var _tuning: SectTuning = null
var _loaded: bool = false


static func instance() -> SectCatalog:
	if shared == null:
		shared = SectCatalog.new()
	return shared


## Set the family's overlay stack: ordered rows of `{dir, owner,
## declared_overrides, id_field}`. Later rows overlay earlier ones; an id
## collision needs a declared override on the LATER root or the merge fails
## loudly (ADR 0240).
##
## The cached tree is DROPPED here, because a changed stack invalidates it: a
## catalog that kept serving the tree merged from the PREVIOUS stack would report
## content the new stack does not contain — a stale read that looks like a working
## one. The same invalidation `InstitutionDefCatalog` performs on the same seam.
static func set_overlay_roots(stack: Array) -> void:
	_overlay_stack = stack
	shared = null


## Forget every loaded def AND every overlay root. Static, because both are process
## state: the stack is a static and the tree hangs off the shared instance, so a
## non-static `clear` could reach one and not the other — which is how a leaked fixture
## root becomes the next suite's content in the one shared runner process.
static func clear() -> void:
	_overlay_stack = []
	shared = null


## The merge stack: the base root as a base-owned row, then the overlay rows
## in order. The base row carries the family's default id_field so the merge
## reads the correct property even when an overlay row omits it.
func _merge_stack() -> Array:
	var stack: Array = [
		{
			"dir": SECTS_ROOT,
			"owner": BASE_OWNER,
			"declared_overrides": [],
			"id_field": SECT_ID_FIELD,
		}
	]
	for row in _overlay_stack:
		stack.append(row)
	return stack


## Merge the family's overlay stack through CatalogOverlay (ADR 0184 §5).
## Returns CatalogOverlay.merge's dictionary unchanged: `{ok, reason, detail,
## merged, paths, owners}`.
func _overlay_merge() -> Dictionary:
	return CatalogOverlay.merge(_merge_stack(), SECT_SCRIPT_CLASS, SECT_ID_FIELD)


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
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("SectCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		var def := load(String(entry["path"])) as SectDef
		if def != null and def.id != &"":
			_sects[String(def.id)] = def
			for position_id in def.position_ids():
				_positions[String(position_id)] = StringName(def.id)
