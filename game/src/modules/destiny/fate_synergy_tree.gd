class_name FateSynergyTree
extends RefCounted

## Validates the fate synergy graph (ADR 0383).
##
## A synergy is a prerequisite edge: `A.unlocks` contains `B` means holding A makes B
## earnable. The graph must be acyclic — a cycle means neither fate can ever be
## earned. All references must resolve to authored fates, and the `unlocks` /
## `requires` views must be consistent.
##
## This is a pure validator: it reads the catalog and reports errors. It holds no
## state and mutates nothing.


## Whether the synergy graph is acyclic. Uses DFS with a three-color mark
## (white/gray/black) to detect back edges.
static func is_acyclic() -> bool:
	var catalog := FateCatalog.instance()
	var color := {}  # 0=white, 1=gray, 2=black
	for fate_id in catalog.fate_ids():
		color[String(fate_id)] = 0
	for fate_id in catalog.fate_ids():
		if int(color[String(fate_id)]) == 0:
			if not _dfs_acyclic(catalog, fate_id, color):
				return false
	return true


## Validate the synergy graph. Returns a list of error strings; empty means valid.
## Checks: acyclic, all references resolve, unlocks/requires views consistent.
static func validate() -> Array[String]:
	var errors: Array[String] = []
	var catalog := FateCatalog.instance()
	# Acyclic check.
	if not is_acyclic():
		errors.append("synergy graph has a cycle")
	# Reference resolution and consistency.
	for fate_id in catalog.fate_ids():
		var def := catalog.fate_definition(fate_id)
		if def == null:
			continue
		for unlocked_id in def.unlocks:
			var target := catalog.fate_definition(unlocked_id)
			if target == null:
				errors.append(
					"fate '%s' unlocks '%s' which does not exist" % [fate_id, unlocked_id]
				)
			elif not target.requires.has(fate_id):
				errors.append(
					(
						(
							"fate '%s' unlocks '%s' but '%s.requires"
							% [fate_id, unlocked_id, unlocked_id]
						)
						+ "' does not list '%s'" % fate_id
					)
				)
		for required_id in def.requires:
			var source := catalog.fate_definition(required_id)
			if source == null:
				errors.append(
					"fate '%s' requires '%s' which does not exist" % [fate_id, required_id]
				)
			elif not source.unlocks.has(fate_id):
				errors.append(
					(
						(
							"fate '%s' requires '%s' but '%s.unlocks"
							% [fate_id, required_id, required_id]
						)
						+ "' does not list '%s'" % fate_id
					)
				)
	return errors


## Fates unlocked by holding `fate_id`, canonically ordered.
static func unlocks_for(fate_id: StringName) -> Array[StringName]:
	var catalog := FateCatalog.instance()
	var def := catalog.fate_definition(fate_id)
	if def == null:
		return []
	return _sorted_ids(def.unlocks)


## Fates required before `fate_id` can be earned, canonically ordered.
static func requires_for(fate_id: StringName) -> Array[StringName]:
	var catalog := FateCatalog.instance()
	var def := catalog.fate_definition(fate_id)
	if def == null:
		return []
	return _sorted_ids(def.requires)


## Fates whose synergy requirements are all met by `held`, canonically ordered.
## A fate with no requirements is always available.
static func available_with(held: Array[StringName]) -> Array[StringName]:
	var catalog := FateCatalog.instance()
	var held_set := {}
	for fate_id in held:
		held_set[String(fate_id)] = true
	var out: Array[StringName] = []
	for fate_id in catalog.fate_ids():
		var def := catalog.fate_definition(fate_id)
		if def == null:
			continue
		var all_met := true
		for required_id in def.requires:
			if not held_set.has(String(required_id)):
				all_met = false
				break
		if all_met:
			out.append(fate_id)
	return out


## Fates that are NOT available because their synergy requirements are unmet.
## Returns `{fate_id: [missing_requirement, ...]}` for each blocked fate.
static func blocked_by(held: Array[StringName]) -> Dictionary:
	var catalog := FateCatalog.instance()
	var held_set := {}
	for fate_id in held:
		held_set[String(fate_id)] = true
	var out := {}
	for fate_id in catalog.fate_ids():
		var def := catalog.fate_definition(fate_id)
		if def == null:
			continue
		var missing: Array[StringName] = []
		for required_id in def.requires:
			if not held_set.has(String(required_id)):
				missing.append(required_id)
		if not missing.is_empty():
			out[String(fate_id)] = missing
	return out


## The synergy graph as an adjacency list: `{fate_id: [unlocked_fate_id, ...]}`.
## Used by the UI to render edges.
static func graph() -> Dictionary:
	var catalog := FateCatalog.instance()
	var out := {}
	for fate_id in catalog.fate_ids():
		var def := catalog.fate_definition(fate_id)
		if def == null:
			continue
		out[String(fate_id)] = _string_list(def.unlocks)
	return out


# --- Internals -------------------------------------------------------------


## DFS cycle detection. Returns false if a back edge is found.
static func _dfs_acyclic(catalog: FateCatalog, fate_id: StringName, color: Dictionary) -> bool:
	color[String(fate_id)] = 1  # gray: on the current path
	var def := catalog.fate_definition(fate_id)
	if def != null:
		for unlocked_id in def.unlocks:
			var state := int(color.get(String(unlocked_id), 0))
			if state == 1:
				return false  # back edge: cycle
			if state == 0:
				if not _dfs_acyclic(catalog, unlocked_id, color):
					return false
	color[String(fate_id)] = 2  # black: fully explored
	return true


static func _sorted_ids(ids: Array[StringName]) -> Array[StringName]:
	var strings: Array[String] = []
	for id in ids:
		strings.append(String(id))
	strings.sort()
	var out: Array[StringName] = []
	for s in strings:
		out.append(StringName(s))
	return out


static func _string_list(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
