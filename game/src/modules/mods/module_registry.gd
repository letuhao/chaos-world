class_name ModuleRegistry
extends RefCounted

## Runtime module registry: the real behavior behind
## `ctx.register_module` (ADR 0184). The base modules are pre-registered from
## the seed list, then each mod's `api.gd` path and deps arrive through the
## registration seam. `order()` answers "what attaches when?" as a
## deterministic topological order over the REGISTERED modules — base modules
## are already attached by the composition root, so they are never emitted —
## and every failure aborts with a named cause, never a silent skip
## (ADR 0184 §8).

## Layer deps every module implies in tools/arch/registry.json. They are
## satisfied implicitly: no row, no attach slot, never unknown.
const LAYER_DEPS := ["contracts", "core"]

## Base module seed = tools/arch/registry.json module names with their
## declared deps (2026-10-04), layer deps stripped (they are implicit).
## Mirrored statically so the registry is usable before tools/ exists;
## test_module_registry asserts the seam against registry.json.
const BASE_DEPS := {
	"anchor": ["items", "soul"],
	"bloodline": ["race"],
	"body_cultivation": ["destiny", "items", "race"],
	"clan": ["bloodline", "race", "social"],
	"combat": ["destiny", "loot", "status"],
	"combat_engine": [],
	"custody": ["economy"],
	"destiny": [],
	"difficulty": [],
	"domain": [],
	"dual_cultivation": [],
	"economy": ["items"],
	"elements": [],
	"event": ["destiny", "nation", "npc", "world"],
	"fertility": ["bloodline", "dual_cultivation", "race", "social"],
	"forage": ["holdings"],
	"heavenly_tribulation": ["status"],
	"holdings": [],
	"items": [],
	"loot": ["items", "status"],
	"market": ["economy", "items"],
	"mind_cultivation": ["destiny", "items", "race"],
	"mods": [],
	"nation": ["sect", "social"],
	"npc": ["social"],
	"qi_cultivation": ["destiny", "items", "race"],
	"quest": ["destiny", "items"],
	"quick_use": [],
	"race": [],
	"relations": ["nation", "sect", "world"],
	"save": [],
	"sect": ["clan", "social"],
	"set_bonus": ["items"],
	"social": [],
	"socket": ["items"],
	"soul": ["items"],
	"status": [],
	"techniques": ["items"],
	"world": [],
	"world_spawn": ["world"],
}

## name -> {"api": String, "deps": Array}; base modules first, then registered.
var _rows := {}
## Non-base names in first-registered order; ties in order() resolve by it.
var _registered: Array[String] = []


func _init() -> void:
	for name in BASE_DEPS:
		_rows[name] = {"api": "res://src/modules/%s/api.gd" % name, "deps": BASE_DEPS[name]}


## Record one module facade. Only shape-local faults are eager:
## duplicate_module, bad_api_path, and a self-dependency. Unknown deps
## and multi-member cycles are graph faults and surface in order(),
## because a forward reference is the first half of a legal chain.
func register(name: String, api_gd_path: String, deps: PackedStringArray) -> Dictionary:
	if _rows.has(name):
		return _error("duplicate_module", "'%s' is already registered" % name)
	if not FileAccess.file_exists(api_gd_path):
		return _error("bad_api_path", "'%s' api_gd does not exist: %s" % [name, api_gd_path])
	var clean: Array = []
	for dep in deps:
		clean.append(String(dep))
	for dep in clean:
		if dep == name:
			return _error("dependency_cycle", "dependency_cycle: %s" % name)
	_rows[name] = {"api": api_gd_path, "deps": clean}
	_registered.append(name)
	return {"ok": true, "reason": "", "detail": ""}


## The api_gd path a caller should load for `name`, "" when unknown.
func api_path_of(name: String) -> String:
	if not _rows.has(name):
		return ""
	return String((_rows[name] as Dictionary)["api"])


## Deterministic attach order over the REGISTERED modules: topological over
## deps, ties broken by first-registered order. {ok:true, order:[names]} or
## a named cause: unknown_dependency (first offender) or dependency_cycle
## (every leftover member named).
func order() -> Dictionary:
	for name in _registered:
		for dep in (_rows[name] as Dictionary)["deps"]:
			if not _resolvable(String(dep)):
				return _error(
					"unknown_dependency",
					(
						"'%s' depends on '%s', which no base module and no registered module provides"
						% [name, dep]
					)
				)
	var emitted: Array[String] = []
	var done := {}
	# One row per pass or a no-progress pass breaks; the range is a hard bound
	# (never a container-under-test while), so a cycle cannot spin here.
	for _pass in range(_registered.size() + 1):
		if emitted.size() >= _registered.size():
			break
		var pick := ""
		# _registered is first-registered order, so the FIRST ready row is the
		# lowest-index ready row — the tiebreak, with no second index.
		for name in _registered:
			if done.has(name):
				continue
			var ready := true
			for dep in (_rows[name] as Dictionary)["deps"]:
				if _is_satisfied(String(dep)):
					continue
				if not done.has(String(dep)):
					ready = false
					break
			if ready:
				pick = name
				break
		if pick == "":
			break
		emitted.append(pick)
		done[pick] = true
	if emitted.size() < _registered.size():
		var stuck: Array[String] = []
		for name in _registered:
			if not done.has(name):
				stuck.append(name)
		stuck.sort()
		return _error("dependency_cycle", "dependency_cycle: %s" % ", ".join(stuck))
	return {"ok": true, "reason": "", "detail": "", "order": emitted}


func _resolvable(dep: String) -> bool:
	return _is_satisfied(dep) or _rows.has(dep)


## Base and layer deps are attached outside this registry, so they are
## always satisfied as far as the registered graph is concerned.
func _is_satisfied(dep: String) -> bool:
	return BASE_DEPS.has(dep) or LAYER_DEPS.has(dep)


func _error(reason: String, detail: String) -> Dictionary:
	return {"ok": false, "reason": reason, "detail": detail}
