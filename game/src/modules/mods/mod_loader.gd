class_name ModLoader
extends RefCounted

## Discover `mod.json` files, validate every manifest, and compute the load
## order (ADR 0184). Pure function of the roots it is handed: same roots, same
## order, no clocks, no caches hidden between calls.

## The manifest contract version this loader implements. A mod asking for a
## newer one aborts the boot with a NAMED cause rather than half-loading.
const API_VERSION := 1


## Find every `mod.json` under `roots` and parse each. First failure wins:
## `{ok:false, reason:"bad_manifest", detail:"<path>: <reason>"}` or
## `{ok:false, reason:"duplicate_mod_id", ...}`. Later passes trust every
## manifest that survived this one.
static func discover(roots: Array) -> Dictionary:
	var paths: Array[String] = []
	for root in roots:
		for path in ContentScan.files_under(String(root), "mod.json"):
			paths.append(path)
	paths.sort()
	var mods: Array[Dictionary] = []
	var seen := {}
	for path in paths:
		var text := FileAccess.get_file_as_string(path)
		var parsed := ModManifest.parse(text, path)
		if not bool(parsed.get("ok", false)):
			return {
				"ok": false,
				"reason": "bad_manifest",
				"detail": "%s: %s" % [path, String(parsed.get("reason", ""))],
				"mods": [],
			}
		var manifest: Dictionary = parsed["manifest"]
		if seen.has(manifest["id"]):
			return {
				"ok": false,
				"reason": "duplicate_mod_id",
				"detail":
				"'%s' is declared by both %s and %s" % [manifest["id"], seen[manifest["id"]], path],
				"mods": [],
			}
		seen[manifest["id"]] = path
		mods.append(manifest)
	return {"ok": true, "reason": "", "detail": "", "mods": mods}


## The full pass: discover, validate the dependency graph, sort, and stamp one
## RegistrationContext per mod, filled through the five seams. On success:
## `{ok:true, order:[ids], mods:[manifests], contexts:[RegistrationContext]}`.
## On failure: `{ok:false, reason, detail}` with a named cause — cycle,
## missing dep, version mismatch, api mismatch — and NO silent skips.
static func load_order(roots: Array) -> Dictionary:
	var found := discover(roots)
	if not bool(found.get("ok", false)):
		return found
	var mods: Array[Dictionary] = []
	for row in found["mods"]:
		mods.append(row)
	for mod in mods:
		if int(mod["requires_api"]) > API_VERSION:
			return {
				"ok": false,
				"reason": "api_version_mismatch",
				"detail":
				(
					"'%s' requires api %d, this loader provides %d"
					% [mod["id"], mod["requires_api"], API_VERSION]
				),
				"mods": [],
			}
	var graph := _validate_and_depth(mods)
	if not bool(graph.get("ok", false)):
		graph["mods"] = []
		return graph
	var depths: Dictionary = graph["depths"]
	var ordered: Array[Dictionary] = []
	for mod in mods:
		ordered.append(mod)
	ordered.sort_custom(
		func(a, b):
			var da := int(depths[a["id"]])
			var db := int(depths[b["id"]])
			if da != db:
				return da < db
			# Same dependency depth: a HIGHER priority loads LATER, so a mod that
			# explicitly asks for it wins the overlay (ADR 0184 §5, "later wins").
			if int(a["priority"]) != int(b["priority"]):
				return int(a["priority"]) < int(b["priority"])
			return String(a["id"]) < String(b["id"])
	)
	var order: Array[String] = []
	for mod in ordered:
		order.append(String(mod["id"]))
	# One shared registry per boot: every mod's `register_module` forwards into
	# it, so `ModRuntime.finalize` can order the whole pass from a single graph.
	var registry := ModuleRegistry.new()
	var contexts: Array = []
	for mod in ordered:
		contexts.append(_stamp_context(mod, registry))
	return {
		"ok": true,
		"reason": "",
		"detail": "",
		"order": order,
		"mods": ordered,
		"contexts": contexts,
		"registry": registry
	}


## Kahn's pass over the depends_on graph. Validates missing deps and version
## floors (loud, named), then emits one node per pass; a node whose deps are
## all known gets its depth — 0, else 1 + the deepest dep — so a dependent
## always sorts strictly after its dependency. Anything never emitted sits in
## a cycle and is named.
static func _validate_and_depth(mods: Array[Dictionary]) -> Dictionary:
	var by_id := {}
	for mod in mods:
		by_id[mod["id"]] = mod
	var unmet := {}
	for mod in mods:
		unmet[mod["id"]] = {}
		for dep in mod["depends_on"]:
			if not by_id.has(dep["id"]):
				return {
					"ok": false,
					"reason": "missing_dependency",
					"detail":
					(
						"'%s' depends on '%s', which no discovered mod provides"
						% [mod["id"], dep["id"]]
					),
				}
			if (
				dep.has("min_version")
				and ModManifest.version_lt(by_id[dep["id"]]["version"], dep["min_version"])
			):
				return {
					"ok": false,
					"reason": "version_mismatch",
					"detail":
					(
						"'%s' requires '%s' >= %s, found %s"
						% [mod["id"], dep["id"], dep["min_version"], by_id[dep["id"]]["version"]]
					),
				}
			unmet[mod["id"]][dep["id"]] = true
	var remaining: Array[String] = []
	for mod in mods:
		remaining.append(mod["id"])
	var depths := {}
	var ready: Array[String] = []
	for mod in mods:
		if (unmet[mod["id"]] as Dictionary).is_empty():
			ready.append(mod["id"])
	var emitted := 0
	## The body pops the tested container and each id is queued at most once, so
	## every pass shrinks `ready` by definition — the drain the no-unbounded
	## wait gate reads. A cycle leaves `emitted < mods.size()`.
	while not ready.is_empty():
		var mod_id: String = ready.pop_front()
		var mod: Dictionary = by_id[mod_id]
		var depth := 0
		for dep in mod["depends_on"]:
			depth = maxi(depth, int(depths[dep["id"]]) + 1)
		depths[mod_id] = depth
		emitted += 1
		remaining.erase(mod_id)
		for other in mods:
			if (unmet[other["id"]] as Dictionary).has(mod_id):
				unmet[other["id"]].erase(mod_id)
				if (unmet[other["id"]] as Dictionary).is_empty():
					ready.append(other["id"])
	if emitted < mods.size():
		remaining.sort()
		return {
			"ok": false,
			"reason": "dependency_cycle",
			"detail": "dependency_cycle: %s" % ", ".join(remaining),
		}
	return {"ok": true, "depths": depths}


## One mod's declarations, played through the five seams into a fresh
## context. The ctx is stamped with its mod_id, its manifest (so the seams can
## read the declared overrides) and the shared registry (so `register_module`
## forwards into the one graph the boot orders from). Attach hooks carry an
## EMPTY Callable here: the manifest declares the phase, the mod's own entry
## point binds the real function in W3+.
static func _stamp_context(mod: Dictionary, registry: ModuleRegistry) -> RegistrationContext:
	var ctx := RegistrationContext.new(mod["id"], mod, registry)
	for row in mod["content_roots"]:
		ctx.add_content_root(row["family"], row["dir"])
	for module in mod["modules"]:
		ctx.register_module(
			module["name"],
			module["api_gd"],
			module["deps"],
			module.get("provides", []),
			module.get("seed_dir", "")
		)
	for hook in mod["attach_hooks"]:
		ctx.add_attach_hook(hook["phase"], Callable())
	for screen in mod["screens"]:
		ctx.register_screen(screen["id"], screen["scene"], screen["label"])
	if not (mod["events"] as Array).is_empty():
		ctx.subscribe(mod["events"])
	return ctx
