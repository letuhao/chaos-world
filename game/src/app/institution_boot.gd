class_name InstitutionBoot
extends RefCounted

## The composition root's institution wiring (ADR 0271): it discovers every authored
## organization under one flat content directory and registers each KIND it finds
## with `InstitutionRegistry`.
##
## ## This file is the CALLER that resolves a def script in its own scope
##
## `core/institution_registry.gd` may not name `modules/`, and the resolver in
## `tools/arch/enforce.py` reads a path literal as a real edge — including one in a
## docstring. So the registry row holds a String label plus an already-loaded
## `Script` the REGISTERING UNIT resolved, and that unit is this file: `app/` is the
## composition root and may depend on anything. **Both are read off the loaded
## resource** ([method _def_script_of], [method _def_type_of]) rather than written
## down here, so a modder's own def class registers under its own name with no edit
## to this file.
##
## ## DISCOVERY IS AUTOMATIC, and that is the whole point of this slice
##
## `install()` reads `InstitutionDefCatalog` and registers whatever the family holds.
## **This file names no kind, no organization id, no def path and no content root.** A
## modder adding a new kind of organization drops a `.tres` into the family directory
## and touches nothing else; a test asserts this structurally by scanning this file for
## the shipped kind names and for the directory literal.
##
## The alternative — the boot enumerating its rows — is exactly the wiring ADR 0271
## calls the reason a kind could not be added without editing a module, and the
## silent skip ADR 0184's acceptance criterion forbids.
##
## ## ONE LOADER, and this file used to be the second one
##
## `install()` walked `ContentScan` itself while `InstitutionDefCatalog` merged the same
## directory through `CatalogOverlay` — two scans, two verdicts, and a mod's overlay
## roots visible to one of them and not the other. **Both halves now read the catalog**,
## and this file's own `CONTENT_ROOT` is deleted: the family has exactly one loader, and
## the catalog's refused-merge rule (register nothing rather than half of it) is the rule
## both halves now obey. Two constants naming one directory from two layers in two
## directions — which `tests/core/test_institution_def_catalog.gd` had to assert in step
## so the duplication could not rot — is gone with the second loader.
##
## ## A REFUSED FAMILY IS REPORTED, NEVER SKIPPED SILENTLY
##
## `install()` returns `{ok, registered, refused, organizations, root}`, and every
## refusal names the family and the authored reason. The announcement is a
## `push_warning` rather than a `push_error` on purpose: `_wire_content_roots` in this
## same layer uses that split (a family with no overlay catalog is recorded and
## announced, never a boot failure), and a `.tres` an author broke is a content fault
## the author must see, not a crash that takes the game down at boot.
##
## ## A SECOND `.tres` OF ONE KIND IS ANOTHER REGULATION OF IT
##
## Capabilities belong to a KIND, and there is one registry row per kind, so the
## first def of a kind registers it and every later def of that kind must declare the
## SAME set. An identical repeat is folded — a list naming the same flag twice states
## the same thing twice — and a **disagreement** is refused as
## `capability_disagreement`. That is what keeps "the capabilities of this kind" from
## having a second source of truth in the directory.
##
## ## NOTHING HERE IS STATE AND NOTHING HERE TICKS
##
## No `_process`, no `Time.get_ticks*`, no `get_tree()` (DEF-0111). The only process
## value is [member last_report], the pass's own read model, exactly as `ModBoot`
## keeps `active_registrations`.
##
## ## WIRED, and what the wiring is
##
## `install()` runs from the composition root's attach pipeline beside
## `EconomyBoot.install(actor)`, and the root's route binder hands the institution screen
## its three actor-scoped Callables — the reader, the joiner and the leaver. Those three
## are `InstitutionMembership`'s public verbs, so a hero can found a trading guild, join a
## hunting guild and LEAVE both houses from the screen, and the recognition those verbs
## project is the same bounded percent every other institution kind projects.

## The family's merge refused: two roots declaring one id with no override on the later
## one. The catalog leaves itself EMPTY in that state on purpose, so this boot registers
## NOTHING rather than half the family — a registry half-populated is a world that
## disagrees with the refusal, which is the shape `InstitutionDefCatalog._ensure_loaded`
## exists to prevent.
const R_MERGE_REFUSED := "merge_refused"
## Two `.tres` of ONE kind declaring different capability sets. Authored here because
## the registry has no opinion about it: it refuses a duplicate kind and knows nothing
## about two organizations agreeing or not.
const R_CAPABILITY_DISAGREEMENT := "capability_disagreement"
## Two `.tres` of ONE kind authored on DIFFERENT def classes. Authored here for the
## same reason as the reason above: the registry holds one row per kind, so it cannot
## see that a second `.tres` claimed an id whose row is already bound to another
## script — and folding it would be the silent id collision ADR 0184 §5 forbids.
const R_DEF_TYPE_DISAGREEMENT := "def_type_disagreement"

## The last pass, so a caller reads the SAME report the boot stored rather than
## re-walking the directory. Static because a registry row is process state and the
## composition root owns the one instance.
static var last_report: Dictionary = {}


## Register every kind the content directory declares, into `registry` (the shared
## one when none is handed in), and report the pass as primitives.
##
## Idempotent per registry, NOT per process: a second call on a registry that already
## holds the kinds reports them again without a duplicate refusal, because
## [method register_def] folds an identical repeat. `InstitutionRegistry.clear()` is
## what returns a registry to nothing.
static func install(registry: InstitutionRegistry = null) -> Dictionary:
	var target := registry if registry != null else InstitutionRegistry.instance()
	var catalog := InstitutionDefCatalog.instance()
	var report := {
		"ok": true,
		"root": InstitutionDefCatalog.INSTITUTIONS_ROOT,
		"registered": [],
		"refused": [],
		"organizations": [],
	}
	# ## The catalog's verdict comes FIRST, and a refused merge registers NOTHING
	#
	# `is_loaded()` is false for a family that has never loaded as well as for one whose
	# merge refused, so the merge reason is read too: a catalog that has not been read yet
	# has no reason, and a refused one names its own. Loading half the family would leave a
	# registry disagreeing with the refusal, which is the exact state the catalog refuses
	# to serve.
	if not catalog.is_loaded():
		report["ok"] = false
		(
			report["refused"]
			. append(
				{
					"path": String(InstitutionDefCatalog.INSTITUTIONS_ROOT),
					"reason": String(catalog.summary()["merge_reason"]),
				}
			)
		)
		return _published(report, target)
	# A `for` over the catalog's OWN sorted id snapshot, writing into two fresh arrays: the
	# body never grows the array being walked, so the bound is the family's merged file
	# count and there is no shape here for a loop to grow in lockstep with its own bound
	# (`tests/arch_rules/test_no_unbounded_wait.gd`).
	for institution_id in catalog.ids():
		var def := catalog.definition(institution_id)
		if def == null:
			continue
		var accepted := _accept(target, catalog, def)
		if bool(accepted["ok"]):
			report["organizations"].append(accepted["organization"])
			continue
		(
			report["refused"]
			. append(
				{
					"path": catalog.path_of(institution_id),
					"reason": String(accepted["reason"]),
				}
			)
		)
	report["ok"] = (report["refused"] as Array).is_empty()
	return _published(report, target)


## ## Stamp the pass and announce every refusal, then hand the report back
##
## Split out of [method install] because the merge-refusal branch has to return the same
## stamped report as the walked one: a report that skipped the announcement on one branch
## would print nothing about a family that loaded nothing.
static func _published(report: Dictionary, target: InstitutionRegistry) -> Dictionary:
	# The registered kinds are read back off the REGISTRY rather than tallied here, so
	# the report is the resulting STATE and cannot disagree with what a caller then
	# asks the registry.
	var kinds: Array = []
	for kind in target.kinds():
		kinds.append(String(kind))
	report["registered"] = kinds
	last_report = report.duplicate(true)
	if not bool(report["ok"]):
		for row in report["refused"]:
			push_warning(
				(
					"InstitutionBoot: refused '%s' -- %s"
					% [String((row as Dictionary)["path"]), String((row as Dictionary)["reason"])]
				)
			)
	return report


## Register ONE def's kind. Public so a test and a mod hook can register a def that did
## not come off disk, and so the agreement rule below has a name of its own.
##
## `{ok: true, reason: "", kind, institution, new}` or
## `{ok: false, "reason": <authored constant>}` — ADR 0083's third state, never a
## silent skip and never a default row.
static func register_def(registry: InstitutionRegistry, def: InstitutionDef) -> Dictionary:
	if registry == null or def == null:
		return InstitutionLedger.refuse(InstitutionRegistry.R_UNKNOWN_KIND)
	# ## The CONTENT faults run BEFORE the row exists, and they are ONE authority
	#
	# `def.check(registry)` cannot gate a first `.tres`: its registry half asks whether
	# the kind is registered, and a brand-new kind is not. So the registry-free half
	# runs here instead, and a `.tres` whose offices contradict its own declared
	# capabilities never becomes a live row — a row is not a warning, because other
	# systems consult it. It also owns `no_kind`, `no_id` and `unknown_capability`: an
	# earlier version re-checked all three here, which is two authorities for one
	# refusal (ADR 0066's shape inside the file that exists to remove it).
	var content := def.check_content()
	if not bool(content["ok"]):
		return content
	if registry.knows(def.kind):
		# Already registered. An IDENTICAL repeat is another regulation of a known
		# kind and is folded; a DISAGREEMENT is the content bug, named here because
		# this is the only place that can see both sets.
		if not _same_capabilities(registry.capabilities_of(def.kind), def.authored_capabilities()):
			return InstitutionLedger.refuse(R_CAPABILITY_DISAGREEMENT)
		# A repeat on a DIFFERENT def class is a COLLISION, never a fold. Folding it is
		# the silent overwrite ADR 0184 §5 forbids ("an id collision requires an
		# explicit declaration or it is a loud load error, never silent"): a modder
		# reusing a shipped kind id on their own subclass would watch it be ignored with
		# nothing said, and the row would keep instantiating the first class.
		if registry.def_type_of(def.kind) != _def_type_of(def):
			return InstitutionLedger.refuse(R_DEF_TYPE_DISAGREEMENT)
		return InstitutionLedger.ok(
			{"kind": String(def.kind), "institution": String(def.id), "new": false}
		)
	var script := _def_script_of(def)
	if script == null:
		return InstitutionLedger.refuse(InstitutionRegistry.R_EMPTY_DEF_TYPE)
	var registered := registry.register(
		def.kind, _def_type_of(def), def.authored_capabilities(), script
	)
	return (
		InstitutionLedger.ok({"kind": String(def.kind), "institution": String(def.id), "new": true})
		if bool(registered["ok"])
		else registered
	)


## Everything this pass knows about one organization's content, as primitives. The
## read model a panel, a headless driver and a mod-authoring test all answer from, so
## none of them has to walk the directory itself and none of them can drift from what
## the boot accepted. **Read off the catalog, not off the filesystem**, so this answer
## and [method install]'s cannot describe two different families.
static func summary(registry: InstitutionRegistry = null) -> Dictionary:
	var target := registry if registry != null else InstitutionRegistry.instance()
	var catalog := InstitutionDefCatalog.instance()
	var rows: Array = []
	for institution_id in catalog.ids():
		var def := catalog.definition(institution_id)
		if def == null:
			continue
		rows.append(_organization_row(catalog, def, target))
	return {
		"ok": catalog.is_loaded(),
		"root": String(InstitutionDefCatalog.INSTITUTIONS_ROOT),
		"kinds": _names(target.kinds()),
		"refused": last_report.get("refused", []),
		"organizations": rows,
	}


## One organization's whole content read model, as primitives. `owner` and `path` come
## from the MERGE rather than from this file, so a base def and a mod's are told apart by
## the decision that accepted them instead of by a second walk of the same tree.
static func _organization_row(
	catalog: InstitutionDefCatalog, def: InstitutionDef, target: InstitutionRegistry
) -> Dictionary:
	var capabilities: Array = []
	for capability in def.authored_capabilities():
		capabilities.append(String(capability))
	return {
		"id": String(def.id),
		"kind": String(def.kind),
		"def_type": _def_type_of(def),
		"capabilities": capabilities,
		"positions": _names(def.position_ids()),
		"territories": _names(def.claimed_territories()),
		"founding_cost": int(def.founding_cost),
		"registered": target.knows(def.kind),
		"owner": catalog.owner_of(def.id),
		"path": catalog.path_of(def.id),
	}


## The def script this def was authored on, or null. **Read off the loaded resource**
## rather than preloaded here: a def whose script is a mod's own subclass registers
## that subclass, and this file needs no knowledge of any def class at all.
static func _def_script_of(def: InstitutionDef) -> Script:
	if def == null:
		return null
	return def.get_script() as Script


## The `class_name` the def's own script declares, or `""` for a script with none.
## A def type nothing can name is a kind nothing can author, so the empty string is
## refused by name rather than registered as an unprintable row.
static func _def_type_of(def: InstitutionDef) -> String:
	var script := _def_script_of(def)
	if script == null:
		return ""
	return String(script.get_global_name())


## ## Register one MERGED def and publish the row it reached the registry on
##
## `{ok: true, organization}` or `{ok: false, reason}`. The def comes from the catalog,
## so `path` is the winning path the MERGE chose and a mod's organization reports the
## mod's file rather than the base directory's.
static func _accept(
	target: InstitutionRegistry, catalog: InstitutionDefCatalog, def: InstitutionDef
) -> Dictionary:
	var answer := register_def(target, def)
	if not bool(answer["ok"]):
		return answer
	# The def's OWN check runs here too, now that the kind IS registered, and its
	# verdict is published rather than swallowed. `register_def` already ran the
	# registry-free half, so this can only fail on the registry half — and a caller
	# reading the report can see which `.tres` reached a live row on which terms.
	var verdict := def.check(target)
	var flags: Array = []
	for capability in def.authored_capabilities():
		flags.append(String(capability))
	return (
		InstitutionLedger
		. ok(
			{
				"organization":
				{
					"path": catalog.path_of(def.id),
					"owner": catalog.owner_of(def.id),
					"id": String(def.id),
					"kind": String(def.kind),
					"capabilities": flags,
					"positions": _names(def.position_ids()),
					"founding_cost": int(def.founding_cost),
					"verdict": String(verdict["reason"]),
				}
			}
		)
	)


static func _names(ids: Array[StringName]) -> Array:
	var out: Array = []
	for id in ids:
		out.append(String(id))
	return out


## ## Whether two capability lists state the SAME SET. Order-independent, and that is
## a measurement rather than a style choice.
##
## `InstitutionRegistry.capabilities_of` sorts an `Array[StringName]`, and this engine
## does not order interned ids by their string value — measured here: a def declaring
## `[has_offices, has_territory]` reads back from the registry as
## `[has_territory, has_offices]`. So a positional comparison refuses a regulation
## that declared **exactly** the same capabilities, and the refusal fires on the very
## second `.tres` a modder drops into the directory. The set is what both sides mean,
## and the size plus a membership walk says so.
static func _same_capabilities(left: Array[StringName], right: Array[StringName]) -> bool:
	if left.size() != right.size():
		return false
	for capability in left:
		if not right.has(capability):
			return false
	return true
