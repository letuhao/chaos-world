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

## The shipped baseline. A table that failed to load still resolves every preset to the
## neutral row, so a missing content tree is inert rather than destructive — the
## `DestinyApi._catalog_loaded` rule, applied to numbers rather than to a ledger.
const NEUTRAL_SCALARS := {
	"soul_damage_share": 1.0,
	"death_loss_cap": 1.0,
	"guardian_effectiveness": 1.0,
	"loot_ceiling": 1.0,
	"tribulation_preparation_credit": 1.0,
}

static var shared: DifficultyCatalog = null

var _table: DifficultyTable = null
var _loaded: bool = false


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
	for path in ContentScan.files_under(TABLE_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains('script_class="%s"' % SCRIPT_CLASS):
			continue
		_table = load(path) as DifficultyTable
		return
