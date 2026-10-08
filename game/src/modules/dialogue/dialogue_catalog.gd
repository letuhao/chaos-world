class_name DialogueCatalog
extends RefCounted

## The authored conversation index, loaded once and cached (ADR 0862).
##
## ## Mirrors [DialogCatalog]'s load, deliberately
##
## `DialogCatalog` scans `res://data/dialog/dialogues/` for
## `script_class="DialogDef"` before loading, and this class does the same over
## `res://data/dialogue/`. The text pre-scan is not defensive noise: a directory of
## `.tres` files can hold more than one resource type, and `load()`ing all of them
## would put a non-dialogue resource into a dictionary typed as a dialog.
##
## ## A repeated node id keeps the FIRST row and is REPORTED
##
## [method _absorb] is where a second row carrying an id already held is refused by
## name rather than overwriting. A conversation whose branches resolve by a lookup is
## exactly the case where "whichever came last" is indistinguishable from "the author's
## intent", and a player meeting the wrong branch has no way to tell it was a content
## defect.

const DIALOGUE_ROOT := "res://data/dialogue"
## The script class THIS catalog loads. It is `DialogueDef`, NOT `DialogDef`: the two
## resource types are different concerns (an authored branching graph versus a
## fate-modified speech line in `destiny/`), and this constant was copy-pasted from
## `DialogCatalog` and never updated — so the pre-scan skipped every authored
## conversation and the catalog was permanently empty.
const DIALOG_SCRIPT_CLASS := "DialogueDef"

static var shared: DialogueCatalog = null

var _by_id: Dictionary = {}
var _by_npc: Dictionary = {}
var _problems: Array[String] = []
var _loaded: bool = false


static func instance() -> DialogueCatalog:
	if shared == null:
		shared = DialogueCatalog.new()
	return shared


## Every authored conversation id, canonically ordered. Sorted on TEXT for the reason
## `NpcState.npc_ids` records: `StringName` ordering is a property of which ids
## interned first in the process.
func dialog_ids() -> Array[StringName]:
	_ensure_loaded()
	return _sorted_names(_by_id.keys())


## One conversation, or null when the id is unknown.
func definition(dialog_id: StringName) -> DialogueDef:
	_ensure_loaded()
	return _by_id.get(String(dialog_id))


## The conversation this npc can have, or null.
##
## One per npc by construction, and a SECOND def claiming the same npc is refused at
## load: an npc with two entry conversations has no answer to "what do you say", and
## whichever sorted first would be the one they say while the other is unreachable
## content nothing can report.
func for_npc(npc_id: StringName) -> DialogueDef:
	_ensure_loaded()
	return _by_npc.get(String(npc_id))


## Every authoring complaint the load found, as stable strings. A content guard reads
## this and fails on a non-empty list; `summary` publishes it so a screen or the
## headless driver can say a conversation is unreachable rather than discovering it by
## pressing nothing.
func problems() -> Array[String]:
	_ensure_loaded()
	return _problems.duplicate()


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path in ContentScan.files_under(DIALOGUE_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains(
			'script_class="%s"' % DIALOG_SCRIPT_CLASS
		):
			continue
		_absorb(load(path) as DialogueDef, path)


## Take one def, refusing the three ways a conversation can be unplayable: it declares
## no id, its entry names no node it authors, or another conversation already claims its
## npc. Every refusal is a NAMED string rather than a dropped row, because a catalog
## that silently skips an unplayable def answers a content question with a smaller
## catalogue and no explanation.
func _absorb(def: DialogueDef, path: String) -> void:
	if def == null:
		return
	if def.dialog_id == &"" or def.npc_id == &"":
		_problems.append("%s: a conversation with no dialog_id or npc_id" % path)
		return
	var key := String(def.dialog_id)
	if _by_id.has(key):
		_problems.append("%s: duplicate dialog_id '%s'" % [path, key])
		return
	_by_id[key] = def
	if not def.has_node(def.entry_node):
		_problems.append(
			(
				("%s: entry_node '%s' is not one of this conversation's nodes" % [path, key])
				% String(def.entry_node)
			)
		)
	var npc_key := String(def.npc_id)
	if _by_npc.has(npc_key):
		_problems.append(
			(
				"%s: npc '%s' already has a conversation ('%s')"
				% [path, npc_key, _by_npc[npc_key].dialog_id]
			)
		)
		return
	_by_npc[npc_key] = def
	_report_duplicate_nodes(def, path)


## Two rows sharing a node id make a choice's target resolve by arrival order. The FIRST
## row is kept and the repeat is reported — never the second, because overwriting would
## make the conversation change shape depending on file enumeration order.
func _report_duplicate_nodes(def: DialogueDef, path: String) -> void:
	var seen: Dictionary = {}
	for row in def.nodes:
		var key := String(row.node_id)
		if seen.has(key):
			_problems.append("%s: '%s' declares node '%s' twice" % [path, def.dialog_id, key])
			continue
		seen[key] = true


## Keys sorted by TEXT, re-interned as `StringName`.
func _sorted_names(keys: Array) -> Array[StringName]:
	var texts: Array[String] = []
	for key in keys:
		texts.append(String(key))
	texts.sort()
	var out: Array[StringName] = []
	for text in texts:
		out.append(StringName(text))
	return out
