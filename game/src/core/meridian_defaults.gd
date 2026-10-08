class_name MeridianDefaults
extends RefCounted

## The 20 meridians: 12 primary + 8 extraordinary (ADR 0017). The authored `.tres`
## under `res://data/meridians/` are the single source (BL-0272): `all()` LOADS them
## through [ContentScan] instead of hardcoding a list, so adding a meridian is a file
## and retiring one is deleting a file — the claim [MeridianDef]'s docblock has always
## made and this file did not keep.
##
## ## Order is ID-KEYED
##
## `ContentScan.files_under` sorts by path and every filename IS its id, so `all()` is
## deterministic across platforms — never `DirAccess` iteration order, which is not
## stable and decides which of two wounded channels a recovery repairs first. Unlock
## ladders key by id (`MeridianNetwork.unlock_for_realm` reads `def.tier`), so this
## order is presentation and repair-selection only.
##
## ## A file that will not load is a loud skip, not a silent 19
##
## `load()` answering something that is not a [MeridianDef] is a content bug that
## would otherwise drop a channel from every actor without a word, so it pushes an
## error naming the path and moves on: the rest of the corpus still plays and the
## error is the finding. `tests/core/test_meridian_def.gd` asserts the loaded set
## equals the authored files, which is what turns the skip into a red.

const PRIMARY := &"primary"
const EXTRAORDINARY := &"extraordinary"

## Where the authored defs live. `game/data/meridians`, the directory
## `tools cultivation audit` reads (`MERIDIAN_DIR`), so the runtime and the audit
## grade the same corpus.
const DIR := "res://data/meridians"

static var _defs: Array[MeridianDef] = []


static func all() -> Array[MeridianDef]:
	if _defs.is_empty():
		_defs = _build()
	return _defs


static func _build() -> Array[MeridianDef]:
	var defs: Array[MeridianDef] = []
	for path in ContentScan.files_under(DIR):
		var def := load(path) as MeridianDef
		if def == null:
			push_error("MeridianDefaults: %s is not a MeridianDef" % path)
			continue
		defs.append(def)
	return defs
