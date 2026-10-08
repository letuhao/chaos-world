class_name InstitutionDefCatalog
extends RefCounted

## Every authored organization of ANY kind, base game and mod overlays together
## (ADR 0184 §5, ADR 0271 §5, ADR 0278).
##
## ## WHAT THIS ANSWERS, and what it deliberately does not
##
## One question: **which defs does the `institutions` family have, where did each one
## come from, and in what order.** `set_overlay_roots` is the seam that answers it.
##
## It does **NOT** register a kind and it does **NOT** own a refusal. Those live in
## `InstitutionBoot` in the composition root, and the reason is a layering fact rather
## than a preference: the boot's four named causes — a capability disagreement, a def
## type disagreement, an unreadable file, a `.tres` that is not an institution — are
## declared in `app/`, and `core/` may not reference `app/`. Restating them here would
## be a second copy of one refusal vocabulary, which is the ADR 0066 failure mode
## inside the file that exists to prevent it. So this catalog LOADS and REPORTS, and
## the boot REGISTERS.
##
## ## Why `core/`, and the precedents that already say so
##
## `core/catalog_overlay.gd` — the merger this routes through — is in `core/`, and
## `core/portrait_catalog.gd` is a content catalog in `core/` that loads a `.tres` tree
## through `ContentScan` on exactly this shape. `core` is a LAYER rather than a module,
## so the cross-module facade rule never applied to it and this file adds **zero new
## edges**: it references only `core`. An `institutions` MODULE would be the worse
## shape, because the generic def is `core`-owned and a module facade for it would be
## an indirection with no second owner.
##
## ## AN INSTANCE, because a content tree is state within one boot
##
## `RaceCatalog` and `PortraitCatalog` are both singletons with an explicit `shared`
## accessor, and the reason is the one `InstitutionRegistry` states for itself: the
## headless runner drives every suite in ONE process, so a cached tree that a suite
## forgets to clear is handed to every suite after it. `clear()` is therefore part of
## the surface rather than a test convenience.
##
## ## The DOCUMENTED limit of the merge: `InstitutionDef` only
##
## `CatalogOverlay.merge` selects a `.tres` with a TEXT scan for
## `script_class="InstitutionDef"`, which is the right rule (loading every `.tres` and
## casting it would mis-read a foreign resource) and has one consequence worth stating
## rather than discovering: **a `.tres` authored on a SUBCLASS of `InstitutionDef` is
## not merged.** A subclass def still registers correctly when handed straight to
## `InstitutionBoot.register_def` — which is how the registry suite exercises one — but
## it is invisible to the directory scan. That is acceptable because ADR 0278's whole
## decision is that `core` ships ONE authored type for every kind; a mod authors a
## KIND (a `kind` string plus capabilities), not a new def class. Pinned as a case in
## `test_institution_def_catalog.gd` so the boundary stays visible instead of becoming
## a silent skip.
##
## ## A PACK is a mod whose organizations ship together (D6)
##
## Layout: `game/data/packs/<pack_id>/organizations/*.tres` plus a `mod.json`
## the existing loader already reads — `provides: ["organization_pack"]`, one
## `modules[]` entry with `provides: ["organization_pack"]` and `seed_dir`
## naming the pack's `organizations/` dir, and `content_roots:
## [{family: "institutions", dir: "./organizations"}]` so the mod seam layers
## the same tree this catalog merges. No second loader: the manifest shape is
## exactly what `ModManifest.parse` and `ModLoader._stamp_context` already
## play through untouched, and a new org kind is a pack with `.tres` files
## plus optional capability scripts and zero base-game edits.
##
## ## The pack's cost, counter and scarcity (D8)
##
## A pack that fails its contract costs its load: `ModuleRegistry` refuses the
## whole pack at registration (`invalid_organization_pack`), and a refused
## merge registers nothing here either. Capabilities are the counter — every
## claimed implementation must pass its own suite at registration or the kind
## is refused by name. Content roots are scarce: an id collision needs a
## declared override on the later root or the merge refuses by name.
##
## ## NOTHING HERE TICKS
##
## No `_process`, no `Time.get_ticks*`, no `get_tree()` (DEF-0111).

## The one directory the base game scans for its own organizations: the guilds
## pack's `organizations/` dir. A pack dir like any other, so `_merge_stack`
## skips the pack row that would merge it twice — a same-id collision with no
## declared override refuses the whole family, even against itself. Def ids are
## unchanged by the pack move, so saves survive it.
const INSTITUTIONS_ROOT := "res://data/packs/guilds/organizations"
## The directory shipped organization packs live under. One pack per
## subdirectory; a pack's organizations live in its `organizations/` child, so
## the family row for a pack is `<PACKS_ROOT>/<pack_id>/organizations`.
## Scanned as BASE rows (owner `base`), in sorted pack order, between the base
## root and the mod overlays: a pack is shipped content, so it layers exactly
## where shipped content layers, and a pack id colliding with no declared
## override refuses the whole family — content roots are scarce, and the
## declared-override collision policy is the scarcity (D8). An absent
## directory is empty, never a crash: until the tier moves land there are no
## shipped packs, so zero pack rows is the honest answer, not a missing dir.
const PACKS_ROOT := "res://data/packs"
## The child directory inside a pack that carries its organizations. Fixed, so
## a pack manifest's `content_roots` dir and this scan cannot disagree about
## where a pack's content lives: `game/data/packs/<pack_id>/organizations/`.
const PACK_ORGANIZATIONS_SUBDIR := "organizations"
## The one def class this family merges. Also the `def_class` the family row declares,
## so the Python gate and this scan are graded against the same name.
const DEF_SCRIPT_CLASS := "InstitutionDef"
## `InstitutionDef` keys its organization by `id`, so no row overrides this.
const ID_FIELD := "id"
## The owner name the base root carries. Every other catalog uses the same spelling, so
## a panel reading `owners` does not branch on which catalog answered.
const BASE_OWNER := "base"

static var shared: InstitutionDefCatalog = null

## Overlay stack for this family (ADR 0184 §5). Empty means "not wired yet": the merge
## then reads the base root alone. When set, the overlay roots merge AFTER the base root
## so mod content is visible, under the declared-override collision policy
## `CatalogOverlay` enforces.
static var _overlay_stack: Array = []

## Loaded defs by organization id, and the order the merge produced them in.
var _defs: Dictionary = {}
var _paths: Dictionary = {}
var _owners: Dictionary = {}
var _loaded: bool = false
## Whether the last merge succeeded, and why it did not when it did not. Recorded rather
## than only pushed: a refusal a caller cannot read back is a refusal nobody can test.
var _merge_ok: bool = true
var _merge_reason: String = ""


static func instance() -> InstitutionDefCatalog:
	if shared == null:
		shared = InstitutionDefCatalog.new()
	return shared


## Set the family's overlay stack: ordered rows of `{dir, owner,
## declared_overrides, id_field}`. Later rows overlay earlier ones; an id collision
## needs a declared override on the LATER root or the merge refuses by name.
##
## ## This is the seam a mod reaches, and it is the whole of the mod contract
##
## A mod declares `content_roots: [{family: "institutions", dir: ...}]` in its
## manifest; `ModRuntime` hands the composition root one stack per family; the root
## calls this once. Nothing else about the mod's content is reachable, which is why
## adding a kind needs no base-game edit.
##
## ## The cached tree is DROPPED here, because a changed stack invalidates it
##
## A catalog that kept serving a tree merged from the PREVIOUS stack would report
## content the new stack does not contain — a stale read that looks like a working one,
## which is the worst shape a catalog failure takes. So the seam invalidates rather than
## leaving every caller to remember to.
static func set_overlay_roots(stack: Array) -> void:
	_overlay_stack = stack
	shared = null


## ## Forget every loaded def AND every overlay root. STATIC, because both are process
## state: the stack is a static and the tree hangs off the shared instance, so a
## non-static `clear` could reach one and not the other — which is how a leaked fixture
## root becomes the next suite's content in the one shared runner process.
##
## Dropping the instance rather than emptying it means a caller still holding a reference
## sees a STALE catalog rather than a half-emptied one, and `instance()` hands out a
## fresh one.
static func clear() -> void:
	_overlay_stack = []
	shared = null


## The merge stack: the base root as a base-owned row, then the shipped pack
## rows in sorted pack order, then the overlay rows in load order. The base row
## carries the family's id_field so the merge reads the correct property
## even when an overlay row omits it. A pack row naming the base root's own
## dir is SKIPPED: the guilds pack's `organizations/` dir IS the base root, and
## merging one dir twice is an undeclared collision of every id with itself.
## A `for` over `_pack_rows()`' own snapshot, appending only to the stack it
## builds — the body never grows the array being walked, so the bound is the
## shipped pack count (`test_no_unbounded_wait.gd`).
func _merge_stack() -> Array:
	var stack: Array = [
		{
			"dir": INSTITUTIONS_ROOT,
			"owner": BASE_OWNER,
			"declared_overrides": [],
			"id_field": ID_FIELD,
		}
	]
	for row in _pack_rows():
		if String((row as Dictionary).get("dir", "")) == INSTITUTIONS_ROOT:
			continue
		stack.append(row)
	for row in _overlay_stack:
		stack.append(row)
	return stack


## One base-owned merge row per shipped pack, in sorted pack-id order. Sorted
## because `DirAccess` iteration order is not stable across platforms, and an
## unstable base order is a content authority that changes between runs.
## `_merge_stack` drops the row whose dir is the base root's own (the guilds
## pack): pack rows are unique among themselves, so that is the only duplicate.
## A `for` over a materialised, sorted id list: the body appends to a NEW row
## array, never to the list being walked, so no bound grows in lockstep with
## its own body (`test_no_unbounded_wait.gd`).
func _pack_rows() -> Array:
	var ids: Array[String] = []
	var dir := DirAccess.open(PACKS_ROOT)
	if dir == null:
		return []
	# The `DirAccess` terminator (`entry != ""`): the loop drains the listing and
	# cannot spin on anything it is itself growing.
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and dir.current_is_dir():
			ids.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	ids.sort()
	var rows: Array = []
	for pack_id in ids:
		(
			rows
			. append(
				{
					"dir": PACKS_ROOT.path_join(pack_id).path_join(PACK_ORGANIZATIONS_SUBDIR),
					"owner": BASE_OWNER,
					"declared_overrides": [],
					"id_field": ID_FIELD,
				}
			)
		)
	return rows


## Merge the family's overlay stack through `CatalogOverlay`. Returns its dictionary
## unchanged: `{ok, reason, detail, merged, paths, owners}`.
##
## Public because the family suites and a mod author both need to see the merge VERDICT
## — an undeclared collision is a refusal, and a caller that cannot read it would have
## to infer it from an empty catalog, which is the same invented default the registry
## refuses by name.
func overlay_merge() -> Dictionary:
	return CatalogOverlay.merge(_merge_stack(), DEF_SCRIPT_CLASS, ID_FIELD)


## Every organization id, canonically ordered by STRING value. Sorted on `Array[String]`
## and converted back for the reason `InstitutionRegistry._canonical` states — the ids
## here are interned, and interned order is not string order.
func ids() -> Array[StringName]:
	_ensure_loaded()
	var text: Array[String] = []
	for id in _defs.keys():
		text.append(String(id))
	text.sort()
	var out: Array[StringName] = []
	for entry in text:
		out.append(StringName(entry))
	return out


## One organization's def, or null when the id is unknown. **Null rather than a
## guess**: an unknown organization is a content bug, and an invented def would hide it.
func definition(institution_id: StringName) -> InstitutionDef:
	_ensure_loaded()
	return _defs.get(String(institution_id))


## Whether this family carries an organization with that id.
func has(institution_id: StringName) -> bool:
	_ensure_loaded()
	return _defs.has(String(institution_id))


## The winning path for `institution_id`, or `""`. The path is what tells a base def
## from a mod's, which is the question the whole overlay seam exists to answer.
func path_of(institution_id: StringName) -> String:
	_ensure_loaded()
	return String(_paths.get(String(institution_id), ""))


## The root owner that supplied `institution_id` — `base` or a mod id.
func owner_of(institution_id: StringName) -> String:
	_ensure_loaded()
	return String(_owners.get(String(institution_id), ""))


## Whether the merge refused. False for a family that never loaded, so a caller cannot
## read an empty tree as a clean one — the `PortraitCatalog.is_loaded` distinction.
func is_loaded() -> bool:
	_ensure_loaded()
	return _loaded and _merge_ok


## ## The whole family as PRIMITIVES, and why a panel never walks the tree itself
##
## `ok`, `root`, `merge_ok`, `merge_reason`, `ids`, and `rows` of
## `{id, kind, owner, path, capabilities}`. Primitives only, so a headless driver, a
## test and a mod author all answer from ONE read model and none of them can drift from
## what the merge actually accepted.
func summary() -> Dictionary:
	_ensure_loaded()
	var rows: Array = []
	for institution_id in ids():
		var def := definition(institution_id)
		if def == null:
			continue
		var flags: Array = []
		for capability in def.authored_capabilities():
			flags.append(String(capability))
		(
			rows
			. append(
				{
					"id": String(def.id),
					"kind": String(def.kind),
					"owner": owner_of(institution_id),
					"path": path_of(institution_id),
					"capabilities": flags,
				}
			)
		)
	return {
		"ok": _merge_ok,
		"root": INSTITUTIONS_ROOT,
		"merge_ok": _merge_ok,
		"merge_reason": _merge_reason,
		"ids": _names(ids()),
		"rows": rows,
	}


# --- Internals ---------------------------------------------------------------


## Load once. `ContentScan` caps the walk depth and sorts its result, so the load order
## never depends on `DirAccess` iteration order.
##
## ## A refused merge leaves the catalog EMPTY, on purpose
##
## `_loaded` is set BEFORE the merge so a second call cannot retry, and a merge that
## refuses registers nothing. An empty catalog plus `is_loaded() == false` is the honest
## shape; loading half the stack would be a catalog that disagrees with the refusal.
func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_merge_ok = true
	_merge_reason = ""
	var merged := overlay_merge()
	if not bool(merged.get("ok", false)):
		_merge_ok = false
		_merge_reason = String(merged.get("reason", ""))
		push_error("InstitutionDefCatalog: %s" % String(merged.get("detail", "")))
		return
	# A `for` over the merge's OWN row array, writing into three fresh dictionaries:
	# the body never grows the container being walked, so the bound is the merged
	# file count and there is no shape here for a loop to grow in lockstep with its
	# own bound (`test_no_unbounded_wait.gd`).
	for entry in merged["merged"]:
		var id := String(entry["id"])
		var loaded := load(String(entry["path"])) as InstitutionDef
		if loaded == null or id == "":
			continue
		_defs[id] = loaded
		_paths[id] = String(entry["path"])
		_owners[id] = String(entry["owner"])


static func _names(ids: Array[StringName]) -> Array:
	var out: Array = []
	for id in ids:
		out.append(String(id))
	return out
