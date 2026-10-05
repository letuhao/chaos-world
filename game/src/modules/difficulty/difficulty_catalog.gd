class_name DifficultyCatalog
extends RefCounted

## The authored difficulty table, loaded once and cached (ADR 0129).
##
## One `.tres` carrying every preset, loaded the way `FateCatalog` loads its own tree: a text
## scan for `script_class=` so a `.tres` of another resource type in the same directory is
## skipped rather than mis-cast. `ContentScan` caps the walk depth, so a junction pointing back
## at an ancestor cannot return nothing.

const TABLE_ROOT := "res://data/difficulty"
const SCRIPT_CLASS := "DifficultyTable"
const BASE_OWNER := "base"

## The shipped baseline. A table that failed to load still resolves every preset to the
## neutral row, so a missing content tree is inert rather than destructive — the
## `DestinyApi._catalog_loaded` rule, applied to numbers rather than to a ledger.
const NEUTRAL_SCALARS := {
	"soul_damage_share": 1.0,
	"guardian_effectiveness": 1.0,
	"tribulation_preparation_credit": 1.0,
}

static var shared: DifficultyCatalog = null

## Overlay stack for the difficulty family (ADR 0184 §5). Empty means "not
## wired yet": `_ensure_loaded` merges only the authored TABLE_ROOT. When set,
## the overlay roots merge AFTER the base root so mod content is visible, with
## the declared-override collision policy CatalogOverlay enforces.
static var _overlay_stack: Array = []

var _table: DifficultyTable = null
var _loaded: bool = false


## Set the family's overlay stack: ordered rows of `{dir, owner,
## declared_overrides, id_field}`. Later rows overlay earlier ones; an id
## collision needs a declared override on the LATER root or the merge fails
## loudly (ADR 0240).
static func set_overlay_roots(stack: Array) -> void:
	_overlay_stack = stack


## The merge stack: the base root as a base-owned row, then the overlay rows
## in order. The base row carries the family's default id_field so the merge
## reads the correct property even when an overlay row omits it.
func _merge_stack() -> Array:
	var stack: Array = [
		{
			"dir": TABLE_ROOT,
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
	return CatalogOverlay.merge(_merge_stack(), SCRIPT_CLASS, "id")


static func instance() -> DifficultyCatalog:
	if shared == null:
		shared = DifficultyCatalog.new()
	return shared


## The scalar row for `difficulty_id`. The neutral row when the id is unknown and the neutral
## row when the tree failed to load — never a zero and never an empty dictionary, so a consumer
## cannot read an absent preset as a deletion.
func scalars_for(difficulty_id: StringName) -> Dictionary:
	if not is_loaded():
		return NEUTRAL_SCALARS.duplicate()
	return _table.scalars_for(difficulty_id)


## Every authored preset id, sorted.
func ids() -> Array[StringName]:
	if not is_loaded():
		return [DifficultyTable.NEUTRAL]
	return _table.ids()


## The table itself, for a settings screen listing what a player may choose. `{}` when the tree
## failed to load, which is the honest answer rather than a synthesised list.
func rows() -> Dictionary:
	if not is_loaded():
		return {}
	return _table.presets


## Whether the content tree loaded. The distinction matters: an empty tree is not a build that
## ships no difficulties, it is a build whose content is missing, and the two must not read the
## same way.
func is_loaded() -> bool:
	_ensure_loaded()
	return _table != null


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("DifficultyCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		_table = load(String(entry["path"])) as DifficultyTable
		return
