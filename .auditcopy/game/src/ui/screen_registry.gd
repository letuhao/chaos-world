class_name ScreenRegistry
extends RefCounted

## Static screen registry: screen id → {scene_path, label} (ADR 0184's
## `register_screen` seam). Mods register through `RegistrationContext`; the
## recorded rows are folded in here by `register_from_contexts`, and the
## `ScreenStack` mounts by id through `push_registered`.
##
## Static because a route table is per-process state, like `ModBoot`'s stored
## order. `clear()` exists so each test starts from an empty table.

static var _screens: Dictionary = {}


## Register one screen. A duplicate id, empty id, or empty scene path is a
## named loud error and the row is refused — never overwritten silently.
## Returns true when the row was accepted.
static func register(id: String, scene_path: String, label: String) -> bool:
	if id.is_empty():
		push_error("ScreenRegistry: a screen id must not be empty")
		return false
	if scene_path.is_empty():
		push_error("ScreenRegistry: screen '%s' needs a scene path" % id)
		return false
	if _screens.has(id):
		push_error("ScreenRegistry: duplicate screen id '%s' refused" % id)
		return false
	_screens[id] = {"scene_path": scene_path, "label": label}
	return true


## The scene path registered under `id`, or "" when none.
static func path_of(id: String) -> String:
	if not _screens.has(id):
		return ""
	return String(_screens[id]["scene_path"])


## The label registered under `id`, or "" when none.
static func label_of(id: String) -> String:
	if not _screens.has(id):
		return ""
	return String(_screens[id]["label"])


## Every registered id, sorted, so callers read a stable order.
static func ids() -> Array:
	var out: Array = []
	for id in _screens.keys():
		out.append(String(id))
	out.sort()
	return out


## Fold the recorded `register_screen` rows of each stored `RegistrationContext`
## (`ModBoot.active_contexts`) into the registry. Returns how many rows were
## accepted. Duck-typed on the `screens` property so `ui/` never names the
## module that owns the context type (the facade-only rule).
static func register_from_contexts(contexts: Array) -> int:
	var accepted := 0
	for ctx in contexts:
		if ctx == null:
			continue
		for row in ctx.screens:
			if row is Dictionary:
				if register(
					String(row.get("id", "")),
					String(row.get("scene", "")),
					String(row.get("label", ""))
				):
					accepted += 1
	return accepted


## Empty the table. Test isolation only; production never clears.
static func clear() -> void:
	_screens.clear()
