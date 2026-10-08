class_name ClanCatalog
extends RefCounted

## The authored clan content tree, loaded once and cached.
##
## Clan definitions live in `res://data/packs/clan/organizations/` and are ordinary
## `.tres` resources carrying a `script_class`, loaded the same way `RaceCatalog` loads its tree: a text
## scan for `script_class=` so a `.tres` belonging to some other resource type in the
## same directory is skipped rather than mis-cast.

const CLANS_ROOT := "res://data/packs/clan/organizations"
const CLAN_SCRIPT_CLASS := "ClanDef"
const BASE_OWNER := "base"

static var shared: ClanCatalog = null

## Overlay stack for the clans family (ADR 0184 §5). Empty means "not wired
## yet": `_ensure_loaded` merges only the authored CLANS_ROOT. When set, the
## overlay roots merge AFTER the base root so mod content is visible, with the
## declared-override collision policy CatalogOverlay enforces.
static var _overlay_stack: Array = []

var _clans: Dictionary = {}
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
			"dir": CLANS_ROOT,
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
	return CatalogOverlay.merge(_merge_stack(), CLAN_SCRIPT_CLASS, "id")


static func instance() -> ClanCatalog:
	if shared == null:
		shared = ClanCatalog.new()
	return shared


## Every authored clan id, canonically ordered.
func clan_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _clans.keys():
		out.append(StringName(key))
	out.sort()
	return out


## One clan definition, or null when the id is unknown. Null rather than a guess: an
## unknown clan is a content bug, and inventing a definition would hide it.
func clan_definition(clan_id: StringName) -> ClanDef:
	_ensure_loaded()
	return _clans.get(String(clan_id))


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("ClanCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		var def := load(String(entry["path"])) as ClanDef
		if def != null and def.id != &"":
			_clans[String(def.id)] = def
