class_name NationCatalog
extends RefCounted

## The authored nation content tree, loaded once and cached.
##
## Definitions live in `res://data/packs/nation/organizations/` and are ordinary `.tres` resources
## carrying a `script_class`, loaded the way `RaceCatalog` loads its tree: a text
## scan for `script_class=` so a `.tres` of some other resource type sitting in the
## same directory is skipped rather than mis-cast.
##
## Nothing here is a `WorldLocationDef` and nothing here is a sect type. A
## `NationTerritoryDef` names its places as plain ids, because the nation module
## declares no `world` and no `clan` dependency and a `.tres` reference would be a
## `res://` edge the boundary checker reads as a real one.

const NATIONS_ROOT := "res://data/packs/nation/organizations"
const NATION_SCRIPT_CLASS := "NationDef"
const TERRITORY_SCRIPT_CLASS := "NationTerritoryDef"
const TUNING_PATH := "res://src/modules/nation/nation_tuning.tres"
const BASE_OWNER := "base"

static var shared: NationCatalog = null

## Overlay stack for the nations and nation_territories families (ADR 0184 §5).
## Empty means "not wired yet": `_ensure_loaded` merges only the authored
## NATIONS_ROOT. When set, the overlay roots merge AFTER the base root so mod
## content is visible, with the declared-override collision policy CatalogOverlay
## enforces.
static var _overlay_stack: Array = []

var _nations: Dictionary = {}
var _territories: Dictionary = {}
var _tuning: NationTuning = null
var _loaded: bool = false


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
			"dir": NATIONS_ROOT,
			"owner": BASE_OWNER,
			"declared_overrides": [],
			"id_field": "id",
		}
	]
	for row in _overlay_stack:
		stack.append(row)
	return stack


## Merge the family's overlay stack through CatalogOverlay (ADR 0184 §5).
## Returns CatalogOverlay.merge's dictionary unchanged: `{ok, reason, detail,
## merged, paths, owners}`.
func _overlay_merge() -> Dictionary:
	return CatalogOverlay.merge(_merge_stack(), NATION_SCRIPT_CLASS, "id")


## Merge the territory half of the family's overlay stack. Territories share
## the same root directory but a different script_class, so they need their own
## merge pass.
func _overlay_merge_territories() -> Dictionary:
	return CatalogOverlay.merge(_merge_stack(), TERRITORY_SCRIPT_CLASS, "id")


static func instance() -> NationCatalog:
	if shared == null:
		shared = NationCatalog.new()
	return shared


## Every authored nation id, canonically ordered.
func nation_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _nations.keys():
		out.append(StringName(key))
	out.sort()
	return out


## One nation definition, or null when the id is unknown. Null rather than a guess:
## an unknown nation is a content bug, and inventing a definition would hide it.
func nation_definition(nation_id: StringName) -> NationDef:
	_ensure_loaded()
	return _nations.get(String(nation_id))


## Every authored territory id, canonically ordered.
func territory_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _territories.keys():
		out.append(StringName(key))
	out.sort()
	return out


## One territory definition, or null when the id is unknown.
func territory_definition(territory_id: StringName) -> NationTerritoryDef:
	_ensure_loaded()
	return _territories.get(String(territory_id))


## The office definitions one nation authors, keyed by office id. **Every seat is
## present, including one with a `""` holder**: a vacancy is a row whose value is
## absent (ADR 0083), so a caller must be handed the seat to discover that nobody
## fills it, rather than discovering its absence by lookup failure.
func office_definitions(nation_id: StringName) -> Dictionary:
	var def := nation_definition(nation_id)
	var out := {}
	if def == null:
		return out
	for office_id in def.office_ids():
		var office := def.office_definition(office_id)
		if office != null:
			out[String(office_id)] = office
	return out


## The content ids the build ships, as a filter `NationState.normalize` reads.
## Claims and seats naming anything else are dropped rather than persisted.
func known_ids() -> Dictionary:
	_ensure_loaded()
	var out := {}
	for territory_id in _territories.keys():
		out[String(territory_id)] = true
	for nation_id in _nations.keys():
		var def: NationDef = _nations[nation_id]
		for office_id in def.office_ids():
			out[String(office_id)] = true
		for territory_id in def.territory_ids:
			out[String(territory_id)] = true
	return out


## The shipped tuning. Loaded from the `.tres`, never built in code, so a rebalance
## is a data edit (ADR 0067). **Never `null`**: a `.tres` that cannot be read
## resolves to a zeroed tuning rather than to `null`, so that no caller has to
## handle the absence and every one of them pays the same thing it would have paid
## with no tuning at all.
func tuning() -> NationTuning:
	_ensure_loaded()
	if _tuning == null:
		_tuning = NationTuning.shipped_or_zero()
	return _tuning


## The exhaustion at which a side may fight no more, as `NationState` compares it.
##
## `war_break` is read here rather than at each call site because of the direction a
## missing value fails in: exhaustion is compared with `>=`, so a break of `0`
## declares every side exhausted the moment it loses one verdict, and a break that
## is itself `null` is a runtime error in the middle of a war. A break of `0` is
## also the default of an authored field, and "nobody ever breaks" is a legitimate
## thing to author — so it is kept, as the unreachable value it is, by resolving a
## non-positive break to a step below the step exhaustion actually arrives in. The
## result is the one reading that is safe to act on: **no side breaks unless the
## build says one may.**
func war_break() -> float:
	var authored := tuning().war_break
	return authored if authored > 0.0 else -1.0


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("NationCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		var def := load(String(entry["path"])) as NationDef
		if def != null and def.id != &"":
			_nations[String(def.id)] = def
	var merged_territories := _overlay_merge_territories()
	if not bool(merged_territories.get("ok", false)):
		push_error("NationCatalog: %s" % String(merged_territories.get("detail", "")))
		return
	for entry in merged_territories["merged"]:
		var territory := load(String(entry["path"])) as NationTerritoryDef
		if territory != null and territory.id != &"":
			_territories[String(territory.id)] = territory
