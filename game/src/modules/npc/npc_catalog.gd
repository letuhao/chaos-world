class_name NpcCatalog
extends RefCounted

## The authored individual catalog (ADR 0077). Reads `res://data/npc/cast` the way
## every peer catalog reads its own tree — `ContentScan.files_under`, a
## `script_class="NpcDef"` text test so a `.tres` of another resource type in the
## same folder is skipped rather than mis-cast, and `load()` per file — so the cast
## a player meets is content, never a literal (BL-0626).
##
## ## Two paths, kept apart
##
## The catalog is one of the few whose seam is `install` rather than a lazy read,
## and that is deliberate, exactly as `ResourceNodeCatalog` documents:
##
##   - `load_authored` is the PRODUCTION read path. The composition root calls it
##     through `NpcBoot.install`, before anything can spawn. `NpcApi.spawn`
##     resolves through this catalog and refuses an id it does not ship, so a boot
##     that never read the tree leaves a player able to meet nobody;
##   - `install` is the TEST seam, explicit and immediate, so a suite can install
##     exactly the cast its assertions depend on.
##
## The reads themselves stay PURE. `SocialCauseCatalog` is the precedent for that
## split: shipped content arrives once, at the seam, and a read never quietly
## overwrites a fixture the caller installed a line earlier. Merging the two would
## make `install` unsatisfiable — a suite that installed one def would find four
## more behind it — and a test that reads its own fixture for its own answer is not
## a test.
##
## ## An absent tree is empty, not a crash
##
## `ContentScan` returns nothing for a directory it cannot open, so `tools test` is
## runnable before a single `.tres` is authored. An unanswered question is an empty
## catalog.
##
## ## A file that will not load is reported, not absorbed
##
## A `.tres` that is not an `NpcDef`, or that carries no `npc_id`, is skipped with
## a warning naming the file. A silent skip is a content bug nobody finds, and a
## malformed cast file must not take the boot down with it.

## `res://data/npc/cast` — the authored individual definitions.
const CAST_ROOT := "res://data/npc/cast"
## The `script_class` a `.tres` must declare to be read as an individual.
const NPC_SCRIPT_CLASS := "NpcDef"

static var _shared: NpcCatalog = null

var _defs: Dictionary = {}
var _loaded: bool = false


static func instance() -> NpcCatalog:
	if _shared == null:
		_shared = NpcCatalog.new()
	return _shared


## Read the authored cast from disk, once, and report how many individuals the
## build ships. Idempotent: a second call re-reads nothing, so calling it on boot
## and again after a load costs a directory walk's absence rather than a rescan.
##
## The composition root calls this through `NpcBoot.install` rather than a read,
## because `install` is the one place that already runs before anything can spawn.
func load_authored() -> int:
	if _loaded:
		return _defs.size()
	_loaded = true
	for path in _scan(CAST_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains('script_class="%s"' % NPC_SCRIPT_CLASS):
			continue
		var def := load(path) as NpcDef
		if def == null:
			push_warning("NpcCatalog: skipped '%s', which is not an NpcDef" % path)
			continue
		if def.npc_id == &"":
			push_warning("NpcCatalog: skipped '%s', which carries no npc_id" % path)
			continue
		_defs[String(def.npc_id)] = def
	return _defs.size()


## Install a set of authored defs. The TEST seam, and deliberately not a scan: a
## suite installs exactly the cast it needs, and every assertion stays independent
## of what content the build happens to ship.
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


## Test seam: drop every authored individual AND forget that the tree was ever read,
## so the next `load_authored` scans it again. Clearing `_loaded` as well as `_defs`
## is what makes this a seam rather than a one-way door: a suite that resets the
## singleton and then asserts against shipped content would otherwise see a
## permanently empty catalog.
func reset() -> void:
	_defs.clear()
	_loaded = false


## `ContentScan` is the ONE walker every catalog uses. A local `_scan` here would be
## a second implementation with its own depth rule, which is exactly what
## `tests/arch_rules/test_no_unbounded_wait.gd` cannot see through.
func _scan(root: String) -> Array[String]:
	return ContentScan.files_under(root)
