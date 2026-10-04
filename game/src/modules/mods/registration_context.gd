class_name RegistrationContext
extends RefCounted

## The locked registration surface a mod's entry point calls (ADR 0184 §6).
## `ModLoader` hands one context per discovered mod to that mod, and the five
## seams are the ONLY way a mod can touch the game: a mod cannot grow this
## interface and cannot reach a boot phase outside of it.
##
## W2 stub: every seam only RECORDS what it is told (and returns the record
## list, so a caller can answer "what did this mod register?" without touching
## boot internals). W3–W8 wire the recorded rows to real catalogs, hooks,
## screen routes and the events bus — the signatures below are what they get.

## Which mod this context belongs to. Set by the loader, read by the record.
var mod_id: String = ""

## Every recorded row by seam family. Public read-only views; writes go
## through the five seams so a caller cannot smuggle a shape the seam refused.
var content_roots: Array[Dictionary] = []
var modules: Array[Dictionary] = []
var attach_hooks: Array[Dictionary] = []
var screens: Array[Dictionary] = []
var subscriptions: Array = []


func _init(id: String = "") -> void:
	mod_id = id


## Declare one content family rooted at `dir` (e.g. items, recipes). A mod may
## not register content outside its declared roots — enforced when the seams
## are wired (W3+).
func add_content_root(family: String, dir: String) -> Array[Dictionary]:
	content_roots.append({"family": family, "dir": dir})
	return content_roots


## Register one module facade: the `api.gd` a sibling module may reference,
## with the module ids it depends on.
func register_module(name: String, api_gd_path: String, deps: Array) -> Array[Dictionary]:
	modules.append({"name": name, "api_gd": api_gd_path, "deps": deps})
	return modules


## Hook a boot phase. W2 only records the phase name; the mod's entry point is
## expected to pass the real Callable (a manifest declares `{phase}` and the
## loader stakes an empty Callable until the entry point binds it).
func add_attach_hook(phase: String, hook: Callable) -> Array[Dictionary]:
	attach_hooks.append({"phase": phase, "hook": hook})
	return attach_hooks


## Register one screen route.
func register_screen(id: String, scene: String, label: String) -> Array[Dictionary]:
	screens.append({"id": id, "scene": scene, "label": label})
	return screens


## Subscribe an events bus (W2 records the declaration; W8 passes the bus).
func subscribe(events_bus) -> Array:
	subscriptions.append(events_bus)
	return subscriptions


## The whole record as primitives-friendly rows, keyed by seam family. Tests
## and later waves' boot step read THROUGH this, never around the seams.
func registrations() -> Dictionary:
	return {
		"mod_id": mod_id,
		"content_roots": content_roots,
		"modules": modules,
		"attach_hooks": attach_hooks,
		"screens": screens,
		"subscriptions": subscriptions,
	}
