class_name ModsApi
extends RefCounted

## Public facade for the `mods` module (ADR 0184).
## Other modules may reference ONLY this file (`api.gd`).
##
## The module is the locked loader: it is policy plus a parsed-manifest plus a
## sorted order, never a plugin host. The facade computes the load order and
## stamps RegistrationContexts, and the composition root publishes the boot
## (`set_active`) and fires the load-time seam (`fire_lifecycle_event`). A mod
## can never replace the loader itself, so boot policy stays uniform no matter
## what content a mod registers.

## The manifest contract version the loader speaks. Surfaced so a mod tooling
## probe can read it without parsing the loader's source.
const LOADER_API_VERSION := ModLoader.API_VERSION

## The lifecycle events THIS build fires. `ModManifest.LIFECYCLE_EVENTS` is the
## declared vocabulary a manifest may use; this is the subset with a production
## firer, and a hook declared for any other event is recorded and NEVER called.
## `on_load` fires from `ModBoot.run` once per successful boot pass, after
## `set_active`, so a hook can already read its config and its own context.
## Adding a firer means adding the event here and to the test that pins the list.
const FIRED_EVENTS := ["on_load"]


## Parse one `mod.json` text into the normalized manifest row or a NAMED
## parse error. `source_path` is only used for error detail.
static func parse_manifest(text: String, source_path: String = "") -> Dictionary:
	return ModManifest.parse(text, source_path)


## Find and parse every `mod.json` under `roots`. First bad manifest or
## duplicate id wins, named.
static func discover_mods(roots: Array) -> Dictionary:
	return ModLoader.discover(roots)


## Discover, validate and sort: the deterministic load order, or a NAMED
## cause (cycle, missing dependency, version mismatch, api mismatch,
## engine version mismatch, duplicate id, bad manifest). On success also
## returns the per-mod RegistrationContext rows recorded through the five seams.
static func load_order(roots: Array) -> Dictionary:
	return ModLoader.load_order(roots)


## A fresh registration context, for a caller that wants the five seams
## without a loader pass (tests, in-repo registrants in a later wave).
static func build_context(mod_id: String = "") -> RegistrationContext:
	return RegistrationContext.new(mod_id)


## Active contexts and registrations, set by the composition root after boot.
## Stored here so the facade can answer queries without referencing app/.
static var _active_contexts: Array = []
static var _active_registrations: Dictionary = {}


## Set the active contexts and registrations after a boot pass.
static func set_active(contexts: Array, registrations: Dictionary) -> void:
	_active_contexts = contexts
	_active_registrations = registrations


## Get a mod's config value by key. Returns the value, or null when the key
## is not in the mod's config schema.
static func get_config(mod_id: String, key: String) -> Variant:
	var ctx := _find_context(mod_id)
	if ctx == null:
		return null
	return ctx.get_config(key)


## Set a mod's config value and persist to disk. Returns `{ok, reason, detail}`.
static func set_config(mod_id: String, key: String, value: Variant) -> Dictionary:
	var ctx := _find_context(mod_id)
	if ctx == null:
		return {"ok": false, "reason": "unknown_mod", "detail": "'%s' is not loaded" % mod_id}
	return ctx.set_config(key, value)


## Fire all lifecycle hooks registered for an event, in registration order. Each
## hook is called with ITS OWN mod's RegistrationContext — the load-time seam: a
## hook declared as `{"event": "on_load", "callable": "<mod>/api.gd:boot"}` is
## handed the same context `ModRuntime.finalize` played the mod's declarations
## through, so its `declared_resource_ids()` are the pools that were accepted.
## A hook with an empty/invalid Callable (an event-only declaration, or a spec
## that failed to resolve) is skipped, never an error. GDScript has no
## exceptions: a hook that errors at runtime aborts only its own call, so later
## hooks still fire.
static func fire_lifecycle_event(event: String) -> void:
	for ctx in _active_contexts:
		if ctx == null:
			continue
		for row in ctx.lifecycle_hooks:
			if String(row.get("event", "")) == event:
				var callable: Callable = row.get("callable", Callable())
				if callable.is_valid():
					callable.call(ctx)


## Apply all def patches for a family to a def. Returns the number of patches
## applied. Patches are applied in load order.
static func apply_def_patches(family: String, def: Resource) -> int:
	var registrations: Dictionary = _active_registrations
	var patches: Array = registrations.get("def_patches", [])
	var applied := 0
	for patch in patches:
		if String(patch.get("family", "")) != family:
			continue
		# `def` is a Resource, so the read is single-arg `Object.get`: the
		# two-arg Dictionary default form does not exist on it and fails the
		# parse, which takes this whole file (and every boot through it) down.
		# Absent reads null and never matches an authored patch id (boot repair).
		var def_id: Variant = def.get("id")
		if def_id == null or String(patch.get("id", "")) != String(def_id):
			continue
		var result := DefPatch.apply(def, patch)
		if bool(result.get("ok", false)):
			applied += 1
	return applied


## Find a loaded context by mod id.
static func _find_context(mod_id: String) -> RegistrationContext:
	for ctx in _active_contexts:
		if ctx != null and ctx.mod_id == mod_id:
			return ctx
	return null
