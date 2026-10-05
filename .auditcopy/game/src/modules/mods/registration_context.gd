class_name RegistrationContext
extends RefCounted

## The locked registration surface a mod's entry point calls (ADR 0184 §6).
## `ModLoader` hands one context per discovered mod to that mod, and the five
## seams are the ONLY way a mod can touch the game: a mod cannot grow this
## interface and cannot reach a boot phase outside of it.
##
## W3 wiring: each seam now calls the real engine. `add_content_root` stores a
## CatalogOverlay-shaped row per family; `register_module` forwards to the
## shared ModuleRegistry the loader injects; `register_screen` forwards to the
## static ScreenRegistry route table; `add_attach_hook` and `subscribe` store
## for the app to fold into the AttachPipeline and the events bus after
## `ModRuntime.finalize`. The ctx never names the pipeline or the bus — those
## are app-owned, and the layer rules keep `modules/mods` off both.

## Which mod this context belongs to. Set by the loader, read by the record.
var mod_id: String = ""

## Per-family content roots: {family: Array[{dir, owner, declared_overrides}]}.
## The row shape is CatalogOverlay's stack row, so `ModRuntime.finalize` merges
## ctxs in load order without re-shaping.
var content_roots: Dictionary = {}

## Module declarations recorded through `register_module`, with the registry's
## verdict appended so a caller can see what the runtime accepted.
var modules: Array[Dictionary] = []

## Attach hooks staked by phase name; the app folds them into the AttachPipeline
## after finalize (the pipeline is app-owned, so the ctx never names it).
var attach_hooks: Array[Dictionary] = []

## Screen rows recorded through `register_screen` (also forwarded to the static
## ScreenRegistry, which is the route table the ScreenStack mounts by).
var screens: Array[Dictionary] = []

## Event subscriptions declared by the mod; the app folds them onto the bus.
var subscriptions: Array = []

## The manifest this context was stamped from, so a seam can read the mod's
## declared overrides without the loader re-passing them per call.
var _manifest: Dictionary = {}

## The runtime module registry every mod in one boot shares. Injected by the
## loader; a context made outside a loader pass (tests) builds its own.
var _registry: ModuleRegistry = null


func _init(id: String = "", manifest: Dictionary = {}, registry: ModuleRegistry = null) -> void:
	mod_id = id
	_manifest = manifest
	_registry = registry if registry != null else ModuleRegistry.new()


## Declare one content family rooted at `dir` (e.g. items, recipes). The row
## is stored per family in CatalogOverlay's stack shape so finalize merges ctxs
## in load order without re-shaping. A mod may not register content outside its
## declared roots — enforced when the seams are wired.
##
## `id_field` names the def property holding this family's id when it is not
## "id" (e.g. WorldLocationDef's "location_id", NpcDef's "npc_id"). The value
## is carried on the stack row so CatalogOverlay.merge and the catalog's own
## scan read the correct property per root.
func add_content_root(family: String, dir: String, id_field: String = "id") -> Array[Dictionary]:
	var row := {
		"dir": dir,
		"owner": mod_id,
		"declared_overrides": _manifest.get("overrides", []),
		"id_field": id_field,
	}
	if not content_roots.has(family):
		content_roots[family] = []
	var list: Array = content_roots[family]
	list.append(row)
	# A Dictionary value reads back as an untyped Array, so the typed return is
	# built as a copy — the seam's contract is Array[Dictionary], not Variant.
	var out: Array[Dictionary] = []
	for entry in list:
		out.append(entry)
	return out


## Register one module facade: the `api.gd` a sibling module may reference,
## with the module ids it depends on. `provides` declares what the module
## offers (e.g. ["cultivation_path"]); `seed_dir` overrides the default seed
## directory for a cultivation path. Forwards to the shared ModuleRegistry and
## records the declaration with the registry's verdict.
func register_module(
	name: String,
	api_gd_path: String,
	deps: Array,
	provides: Array[String] = [],
	seed_dir: String = ""
) -> Array[Dictionary]:
	var verdict := _registry.register(name, api_gd_path, deps, provides, seed_dir)
	(
		modules
		. append(
			{
				"name": name,
				"api_gd": api_gd_path,
				"deps": deps,
				"provides": provides,
				"seed_dir": seed_dir,
				"ok": verdict.get("ok", false),
				"reason": verdict.get("reason", ""),
			}
		)
	)
	return modules


## Hook a boot phase. The ctx stores the phase name and Callable; the app
## registers them into the AttachPipeline after finalize (the pipeline is
## app-owned, so the ctx never names it).
func add_attach_hook(phase: String, hook: Callable) -> Array[Dictionary]:
	attach_hooks.append({"phase": phase, "hook": hook})
	return attach_hooks


## Register one screen route. Forwards to the static ScreenRegistry (the route
## table the ScreenStack mounts by) and records the row.
func register_screen(id: String, scene: String, label: String) -> Array[Dictionary]:
	ScreenRegistry.register(id, scene, label)
	screens.append({"id": id, "scene": scene, "label": label})
	return screens


## Subscribe to an events bus. The subscription shape is
## `{event_bus: String, event_name: String, callable: Callable}` where
## `event_bus` names the bus class (e.g. "NpcEvents"), `event_name` is the
## signal to connect, and `callable` is the handler. The app folds the
## declaration onto the bus after finalize; the ctx never names the bus.
func subscribe(subscription: Dictionary) -> Array:
	subscriptions.append(subscription)
	return subscriptions


## The whole record as primitives-friendly rows, keyed by seam family. Tests
## and `ModRuntime.finalize` read THROUGH this, never around the seams.
func registrations() -> Dictionary:
	return {
		"mod_id": mod_id,
		"content_roots": content_roots,
		"modules": modules,
		"attach_hooks": attach_hooks,
		"screens": screens,
		"subscriptions": subscriptions,
	}
