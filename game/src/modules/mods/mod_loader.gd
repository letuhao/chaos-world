class_name ModLoader
extends RefCounted

## Discover `mod.json` files, validate every manifest, and compute the load
## order (ADR 0184). Pure function of the roots it is handed: same roots, same
## order, no clocks, no caches hidden between calls.

## The manifest contract version this loader implements. A mod asking for a
## newer one aborts the boot with a NAMED cause rather than half-loading.
const API_VERSION := 1


## Mount .pck files found in roots and return the extended roots list.
## After mounting, the .pck contents are available at res://, so res:// is
## added to the roots. If a .pck fails to mount, returns a named error.
static func mount_pcks(roots: Array) -> Dictionary:
	var pck_paths: Array[String] = []
	for root in roots:
		for path in ContentScan.files_under(String(root), ".pck"):
			pck_paths.append(path)
	if pck_paths.is_empty():
		return {"ok": true, "roots": roots}
	var out_roots: Array = roots.duplicate()
	if not out_roots.has("res://"):
		out_roots.append("res://")
	for path in pck_paths:
		var mounted := ProjectSettings.load_resource_pack(path, true)
		if not mounted:
			return {
				"ok": false,
				"reason": "pck_mount_failed",
				"detail": "%s: failed to mount" % path,
			}
	return {"ok": true, "roots": out_roots}


## Resolve a "path/to/script.gd:method_name" string into a Callable.
## Returns an empty Callable if the format is invalid or the script fails to load.
##
## Split at the LAST colon, never `split(":")`: every spec here is a `res://` or
## `user://` path and both schemes carry their own colon, so a first-colon split
## yields three parts and this resolver answered an EMPTY Callable for every
## manifest callable — attach and lifecycle hooks alike.
##
## The returned Callable OWNS its target. A plain `Callable(obj, method)` does
## NOT keep a RefCounted target alive, so the hook was invalid the moment this
## function returned — measured: `is_valid()` answered false for every spec even
## with the split fixed. The lambda captures `obj` in a Variant, which refcounts
## it, and its defaulted parameter forwards both call shapes the seams use — no
## argument, and the one-argument actor/context.
static func _resolve_callable(spec: String) -> Callable:
	var split_at := spec.rfind(":")
	if split_at <= 0 or split_at >= spec.length() - 1:
		return Callable()
	var script_path := spec.substr(0, split_at)
	var method_name := spec.substr(split_at + 1)
	var script: Resource = load(script_path)
	if script == null:
		return Callable()
	var obj: Object = script.new()
	if not obj.has_method(method_name):
		# Only a Node needs the explicit free; a RefCounted target is released by
		# the local reference going out of scope.
		if obj is Node:
			obj.free()
		return Callable()
	return func(argument = null):
		if argument == null:
			return obj.call(method_name)
		return obj.call(method_name, argument)


## Find every `mod.json` under `roots` and parse each. First failure wins:
## `{ok:false, reason:"bad_manifest", detail:"<path>: <reason>"}` or
## `{ok:false, reason:"duplicate_mod_id", ...}`. Later passes trust every
## manifest that survived this one.
static func discover(roots: Array) -> Dictionary:
	var mounted := mount_pcks(roots)
	if not bool(mounted.get("ok", false)):
		return {
			"ok": false,
			"reason": String(mounted.get("reason", "")),
			"detail": String(mounted.get("detail", "")),
			"mods": [],
		}
	var effective_roots: Array = mounted["roots"]
	var paths: Array[String] = []
	for root in effective_roots:
		for path in ContentScan.files_under(String(root), "mod.json"):
			paths.append(path)
	paths.sort()
	# Deduplicate paths (same file found via multiple roots)
	var seen_paths := {}
	var unique_paths: Array[String] = []
	for path in paths:
		if not seen_paths.has(path):
			seen_paths[path] = true
			unique_paths.append(path)
	var mods: Array[Dictionary] = []
	var seen := {}
	for path in unique_paths:
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
		if not String(manifest["engine_version"]).is_empty():
			var running := Engine.get_version_info()
			var running_version := (
				"%d.%d.%d" % [int(running["major"]), int(running["minor"]), int(running["patch"])]
			)
			if ModManifest.version_lt(running_version, String(manifest["engine_version"])):
				return {
					"ok": false,
					"reason": "engine_version_mismatch",
					"detail":
					(
						"'%s' requires engine >= %s, this engine is %s"
						% [manifest["id"], manifest["engine_version"], running_version]
					),
					"mods": [],
				}
		mods.append(manifest)
	return {"ok": true, "reason": "", "detail": "", "mods": mods}


## The full pass: discover, validate the dependency graph, sort, and stamp one
## RegistrationContext per mod, filled through the registration seams. On success:
## `{ok:true, order:[ids], mods:[manifests], contexts:[RegistrationContext]}`.
## On failure: `{ok:false, reason, detail}` with a named cause — cycle,
## missing dep, version mismatch, api mismatch, engine version mismatch —
## and NO silent skips.
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
	var compat := _check_compatibility(mods)
	if not bool(compat.get("ok", false)):
		compat["mods"] = []
		return compat
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
	# One shared API registry per boot: every mod's `register_mod_api` stores
	# into it, so one mod's context can resolve another mod's registered API.
	var api_registry := {}
	var contexts: Array = []
	for mod in ordered:
		contexts.append(_stamp_context(mod, registry, api_registry))
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


## Check incompatible_with and conflicts_with declarations across all mods.
## Returns `{ok: true}` or `{ok: false, reason, detail}` with a named cause.
static func _check_compatibility(mods: Array[Dictionary]) -> Dictionary:
	var by_id := {}
	for mod in mods:
		by_id[mod["id"]] = mod
	for mod in mods:
		for other_id in mod["incompatible_with"]:
			if by_id.has(other_id):
				return {
					"ok": false,
					"reason": "incompatible_mod",
					"detail":
					"'%s' is incompatible with '%s', which is loaded" % [mod["id"], other_id],
				}
		for other_id in mod["conflicts_with"]:
			if by_id.has(other_id):
				return {
					"ok": false,
					"reason": "conflicting_mod",
					"detail": "'%s' conflicts with '%s', which is loaded" % [mod["id"], other_id],
				}
	return {"ok": true}


## One mod's declarations, played through the registration seams into a fresh
## context. The ctx is stamped with its mod_id, its manifest (so the seams can
## read the declared overrides) and the shared registry (so `register_module`
## forwards into the one graph the boot orders from). A manifest `callable` spec
## on an attach or lifecycle hook is resolved HERE, so the ctx carries the real
## Callable; an event-only hook (no `callable`) stays an empty stub.
##
## Config is loaded from disk BEFORE the mod's `on_load` hook runs, so a mod
## reading its config during registration sees the persisted values.
static func _stamp_context(
	mod: Dictionary, registry: ModuleRegistry, api_registry: Dictionary = {}
) -> RegistrationContext:
	var ctx := RegistrationContext.new(mod["id"], mod, registry, api_registry)
	# Load config from disk before the mod's entry point runs.
	var config_result := ModConfigStore.load(mod["id"], mod.get("config", []))
	if bool(config_result.get("ok", false)):
		ctx._config_values = config_result.get("values", {})
	for row in mod["content_roots"]:
		ctx.add_content_root(row["family"], row["dir"], row.get("id_field", "id"))
	for module in mod["modules"]:
		ctx.register_module(
			module["name"],
			module["api_gd"],
			module["deps"],
			module.get("provides", []),
			module.get("seed_dir", "")
		)
	for hook in mod["attach_hooks"]:
		var callable := Callable()
		if hook.has("callable"):
			callable = _resolve_callable(String(hook["callable"]))
		ctx.add_attach_hook(hook["phase"], callable)
	for screen in mod["screens"]:
		ctx.register_screen(screen["id"], screen["scene"], screen["label"])
	for event in mod["events"]:
		ctx.subscribe(
			{"event_bus": "WorldEvents", "event_name": String(event), "callable": Callable()}
		)
	for hook in mod.get("lifecycle_hooks", []):
		var callable := Callable()
		if hook.has("callable"):
			callable = _resolve_callable(String(hook["callable"]))
		ctx.add_lifecycle_hook(hook["event"], callable)
	return ctx
