class_name ModRuntime
extends RefCounted

## Fold every mod's RegistrationContext into the boot's runtime registrations
## (ADR 0184). One call, in load order, produces the collections the composition
## root consumes: per-family content roots for the catalog overlay stack, the
## module attach order, the screen routes, the attach hooks, and the sixth seam's
## stat/resource declarations (ADR 0275).
##
## Pure aggregation: no clocks, no caches. Same contexts in the same order, same
## result — with ONE documented exception below, which is file reading.
##
## ## Three more collections come out, and one of them can be a FAILURE
##
## `stat_declarations`, `declared_resources` and `declaration_refusals` are the
## sixth seam's answer (ADR 0275), folded here beside the five so the composition
## root has ONE place to read a mod's whole registration. `declaration_refusals`
## is a refusal CHANNEL, not a collection of rows: an unknown stat id or an
## undeclared resource id arrives there naming its mod, and the caller decides
## whether that aborts the boot — which is the app's call, not this module's,
## because ADR 0184 §6 makes the loader locked but says nothing about what an
## app does with a refused declaration.
##
## ## The ONE departure from pure aggregation, and why it cannot live elsewhere
##
## It reads each mod's `stats.json` (see `_read_declaration_block`). The alternative is
## a separate public read step the composition root would have to call — and the
## composition root is not this module's to edit, so such a step would have no caller: a
## validated list nothing consults on the boot path, which is exactly the "narrowed, not
## closed" outcome this ADR refuses. `finalize` is the last thing every boot passes
## through on the mods path, so that is where the read has to be.


## Aggregate `contexts` (in load order) into the runtime registrations.
## `registry` is the shared ModuleRegistry the contexts registered through.
## Returns `{content_roots, modules, screens, attach_hooks, subscriptions,
## stat_declarations, declared_resources, declaration_refusals}`:
##   content_roots: {family: Array[{dir, owner, declared_overrides}]}
##   modules: ModuleRegistry.order() — {ok, order, reason, detail}
##   screens: Array[{id, scene_path, label}]
##   attach_hooks: Array[{phase, callable}]
##   subscriptions: Array[{event_bus, event_name, callable, mod_id}] — `mod_id` is
##     STAMPED from the context, not declared by the mod (ADR 0269): the composition
##     root reports an unresolvable bus by naming the mod that asked for it.
##   stat_declarations: Array[{mod_id, id, op, resource, zero_baseline}] (ADR 0275)
##   declared_resources: {pool_id: mod_id} — who owns each pool across the boot
##   declaration_refusals: Array[{mod_id, reason, detail}] — every REFUSED row
static func finalize(contexts: Array, registry: ModuleRegistry) -> Dictionary:
	var content_roots := {}
	var screens: Array[Dictionary] = []
	var attach_hooks: Array[Dictionary] = []
	var subscriptions: Array[Dictionary] = []
	var stat_declarations: Array[Dictionary] = []
	var declared_resources: Dictionary = {}
	var declaration_refusals: Array[Dictionary] = []
	for ctx in contexts:
		if ctx == null:
			continue
		for family in ctx.content_roots:
			if not content_roots.has(family):
				content_roots[family] = []
			for row in ctx.content_roots[family]:
				(content_roots[family] as Array).append(row)
		for row in ctx.screens:
			(
				screens
				. append(
					{
						"id": String(row.get("id", "")),
						"scene_path": String(row.get("scene", "")),
						"label": String(row.get("label", "")),
					}
				)
			)
		for row in ctx.attach_hooks:
			(
				attach_hooks
				. append(
					{
						"phase": String(row.get("phase", "")),
						"callable": row.get("hook", Callable()),
					}
				)
			)
		for row in ctx.subscriptions:
			(
				subscriptions
				. append(
					{
						"event_bus": String(row.get("event_bus", "")),
						"event_name": String(row.get("event_name", "")),
						"callable": row.get("callable", Callable()),
						# Stamped here, not declared by the mod (ADR 0269): a subscription the
						# composition root cannot resolve has to name the mod that asked for
						# it, and `ctx` is the only place that knows which mod a row came from.
						# Without it an unknown bus is skipped with no owner to report.
						"mod_id": ctx.mod_id,
					}
				)
			)
	_collect_stat_declarations(
		contexts, stat_declarations, declared_resources, declaration_refusals
	)
	return {
		"content_roots": content_roots,
		"modules": registry.order(),
		"screens": screens,
		"attach_hooks": attach_hooks,
		"subscriptions": subscriptions,
		"stat_declarations": stat_declarations,
		"declared_resources": declared_resources,
		"declaration_refusals": declaration_refusals,
		"registry": registry,
	}


## Every mod's declaration block, folded in load order alongside the other
## collections. A ctx's rows come off its OWN recorded list, and
## [method RegistrationContext.declare_stats] REPLACES rather than appends, so a
## second finalize over the same contexts re-reads the same rows instead of
## doubling them — which would read as a DUPLICATE_RESOURCE collision between a mod
## and itself.
##
## ## The FIRST mod to DECLARE a pool owns it, and the second is REFUSED
##
## A pool id is a content id, so ADR 0184 §5's collision rule applies: two mods
## declaring `rage` is two declarations of one fact with nothing keeping them in
## agreement, which is ADR 0066. Load order decides — the earlier ctx owns the pool
## and the later one's declaration is refused NAMING BOTH, so the author learns which
## mod to talk to. Not silently dropped, and not silently winning because it sorted
## later.
##
## Ownership is read off the mod's `resources[]` DECLARATIONS, not off the stat rows
## that happen to reference them. Those are different lists, and conflating them means
## a pool no stat row reads is owned by nobody — so a second mod could take it
## silently, and the collision this whole pass exists to catch would be the one case
## it misses. `declared_resource_ids` is also per-mod, which is what makes "the same
## pool read by two of this mod's rows" legal while "declared by two mods" is not.
##
## Reached over `registrations()`, the ctx's own record, rather than by reading its
## fields: the record is the shape `ModBoot.active_registrations` publishes, so
## aggregating what the record says is what keeps this answer and the app's agree.
## `.get` with a default keeps a mod that declared nothing a no-op.
static func _collect_stat_declarations(
	contexts: Array, stat_declarations: Array, declared_resources: Dictionary, refusals: Array
) -> void:
	for ctx in contexts:
		if ctx == null:
			continue
		var read := _read_declaration_block(ctx)
		for refusal in read["refusals"] as Array:
			refusals.append(refusal)
		var record: Dictionary = ctx.registrations()
		_claim_pools(record, String(record.get("mod_id", "")), declared_resources, refusals)
		for row in record.get("stat_declarations", []) as Array:
			stat_declarations.append(row)
		# The parser's refusals ride out VERBATIM, not through a second shaping step.
		# A caller that has to map them through again is a caller that can re-derive
		# them wrongly, and a refusal must look the same coming out of either gate.
		for refusal in record.get("declaration_refusals", []) as Array:
			refusals.append(refusal)


## Record who owns each pool this mod declared, and refuse one another mod already
## owns. `declared_resources` maps `pool_id -> mod_id`: the OWNER, not a boolean,
## because the whole answer is "who declared this" and a boolean could not name the
## mod a colliding author has to talk to.
static func _claim_pools(
	record: Dictionary, owner: String, declared_resources: Dictionary, refusals: Array
) -> void:
	for entry in record.get("declared_resource_ids", []) as Array:
		var pool_id := String(entry)
		var held_by := String(declared_resources.get(pool_id, ""))
		if not held_by.is_empty() and held_by != owner:
			(
				refusals
				. append(
					{
						"mod_id": owner,
						"reason": RegistrationContext.DUPLICATE_RESOURCE,
						"detail":
						(
							"%s: declares resource '%s', which '%s' already owns"
							% [owner, pool_id, held_by]
						),
					}
				)
			)
			continue
		declared_resources[pool_id] = owner


## Read one mod's `stats.json` and play it through the sixth seam. Returns
## `{path, present, refusals}` — `refusals` carries only what happened BEFORE the
## seam ran (an unreadable file, a block that is not an object), because once the
## seam has run the ctx's own record holds its verdicts and re-appending them here
## would report one refusal twice.
##
## ## Why the READ lives here and not in ModLoader
##
## ADR 0184 decision 7 locks the loader, and decision 8 makes a bad MANIFEST abort
## the boot. A bad declaration is a different failure: the mod's identity, version and
## dependency graph are all sound and its other content still loads. So discovery must
## not fail on it — the mod loads, its rows are refused, and the composition root
## decides what a refusal is worth. Reading the block in `discover` would make every
## mod with one typo invisible, which is the defect this seam exists to remove.
##
## ## An ABSENT block is not a refusal
##
## Most mods declare no stats at all, and `""` — no file, or a context built outside a
## loader pass — contributes nothing rather than an error. An absent declaration is not
## a malformed one (ADR 0083's three-state vocabulary).
static func _read_declaration_block(ctx: RegistrationContext) -> Dictionary:
	var path := ctx.declaration_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"path": path, "present": false, "refusals": []}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {
			"path": path,
			"present": true,
			"refusals":
			[
				_read_refusal(
					ctx.mod_id,
					DeclarationBlock.BAD_BLOCK,
					"is not valid JSON: %s" % json.get_error_message()
				)
			],
		}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {
			"path": path,
			"present": true,
			"refusals":
			[
				_read_refusal(
					ctx.mod_id,
					DeclarationBlock.BAD_BLOCK,
					"must be an object carrying 'stats' and/or 'resources'"
				)
			],
		}
	ctx.declare_stats(json.data)
	return {"path": path, "present": true, "refusals": []}


## One refusal row in the parser's own shape, stamped with the mod, so a file this
## seam could not read is indistinguishable in the output from a row the parser
## refused — a caller must not need to know which half of the pipeline objected.
static func _read_refusal(mod_id: String, reason: String, detail: String) -> Dictionary:
	return {"mod_id": mod_id, "reason": reason, "detail": "%s: %s" % [mod_id, detail]}
