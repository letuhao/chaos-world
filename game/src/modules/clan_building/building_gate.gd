class_name BuildingGate
extends RefCounted

## Evaluates building construction and upgrade requirements against an actor's
## clan state, materials, and contribution.
##
## A requirement is **data, never code**. Verbs:
##   `{verb: &"can_construct", building_id: &"hall_of_ancestors"}`
##   `{verb: &"can_upgrade", building_id: &"hall_of_ancestors"}`
##   `{verb: &"can_research", tech_id: &"tech_01"}`
##   `{verb: &"clan_level_at_least", at: 3}`
##   `{verb: &"has_materials", amount: 100}`
##   `{verb: &"has_contribution", amount: 50}`
##   `{verb: &"all_of", of: [...]}`
##   `{verb: &"any_of", of: [...]}`
##   `{verb: &"none_of", of: [...]}`

const KIND_BUILDING := &"building"
const KIND_CLAN_LEVEL := &"clan_level"
const KIND_MATERIALS := &"materials"
const KIND_CONTRIBUTION := &"contribution"
const KIND_TECH := &"tech"
const KIND_GATE := &"gate"


static func evaluate(actor: Actor, requirement: Dictionary) -> Dictionary:
	if requirement.is_empty():
		return _pass()
	var verb := StringName(requirement.get("verb", ""))
	if verb == &"":
		return _refuse("malformed", "A gate names no verb.")
	match verb:
		&"can_construct":
			return _can_construct(actor, requirement)
		&"can_upgrade":
			return _can_upgrade(actor, requirement)
		&"can_research":
			return _can_research(actor, requirement)
		&"clan_level_at_least":
			return _clan_level_at_least(actor, requirement)
		&"has_materials":
			return _has_materials(actor, requirement)
		&"has_contribution":
			return _has_contribution(actor, requirement)
		&"all_of":
			return _composite(actor, requirement, true, false)
		&"any_of":
			return _composite(actor, requirement, false, false)
		&"none_of":
			return _composite(actor, requirement, false, true)
		_:
			return _refuse("unknown_verb", "Gate verb '%s' is not one this module reads." % verb)


static func _can_construct(actor: Actor, requirement: Dictionary) -> Dictionary:
	var building_id := StringName(requirement.get("building_id", ""))
	if building_id == &"":
		return _refuse("malformed", "A can_construct gate names no building id.")
	var def := BuildingCatalog.instance().building_definition(building_id)
	if def == null:
		return _refuse(
			"unknown_building", "Building '%s' is not one this build ships." % building_id
		)
	var ledger := _ledger(actor)
	var clan_lvl := BuildingProjection.clan_level(ledger)
	if clan_lvl < def.unlock_clan_level:
		return _fail(
			KIND_CLAN_LEVEL,
			building_id,
			def.unlock_clan_level,
			clan_lvl,
			"Requires clan level %d" % def.unlock_clan_level
		)
	if BuildingState.building_level(ledger, building_id) > 0:
		return _fail(
			KIND_BUILDING, building_id, 0, 1, "Building '%s' is already constructed" % building_id
		)
	return _pass()


static func _can_upgrade(actor: Actor, requirement: Dictionary) -> Dictionary:
	var building_id := StringName(requirement.get("building_id", ""))
	if building_id == &"":
		return _refuse("malformed", "A can_upgrade gate names no building id.")
	var def := BuildingCatalog.instance().building_definition(building_id)
	if def == null:
		return _refuse(
			"unknown_building", "Building '%s' is not one this build ships." % building_id
		)
	var ledger := _ledger(actor)
	var current_level := BuildingState.building_level(ledger, building_id)
	if current_level <= 0:
		return _fail(
			KIND_BUILDING, building_id, 1, 0, "Building '%s' is not yet constructed" % building_id
		)
	if current_level >= def.max_level:
		return _fail(
			KIND_BUILDING,
			building_id,
			def.max_level,
			current_level,
			"Building '%s' is at max level" % building_id
		)
	return _pass()


static func _can_research(actor: Actor, requirement: Dictionary) -> Dictionary:
	var tech_id := StringName(requirement.get("tech_id", ""))
	if tech_id == &"":
		return _refuse("malformed", "A can_research gate names no tech id.")
	var ledger := _ledger(actor)
	if BuildingState.has_tech(ledger, tech_id):
		return _fail(KIND_TECH, tech_id, 0, 1, "Tech '%s' is already researched" % tech_id)
	return _pass()


static func _clan_level_at_least(actor: Actor, requirement: Dictionary) -> Dictionary:
	var at = requirement.get("at", null)
	if not (at is float or at is int):
		return _refuse("malformed", "A clan_level_at_least gate needs a numeric `at`.")
	var required := maxi(0, int(at))
	var clan_lvl := BuildingProjection.clan_level(_ledger(actor))
	if clan_lvl >= required:
		return _pass()
	return _fail(
		KIND_CLAN_LEVEL,
		&"",
		required,
		clan_lvl,
		"Requires clan level %d (you are at %d)" % [required, clan_lvl]
	)


static func _has_materials(actor: Actor, requirement: Dictionary) -> Dictionary:
	var amount = requirement.get("amount", null)
	if not (amount is float or amount is int):
		return _refuse("malformed", "A has_materials gate needs a numeric `amount`.")
	var required := maxi(0, int(amount))
	# Materials are tracked externally; this gate is a placeholder for
	# integration with the hunting/combat economy. Returns pass for now.
	return _pass()


static func _has_contribution(actor: Actor, requirement: Dictionary) -> Dictionary:
	var amount = requirement.get("amount", null)
	if not (amount is float or amount is int):
		return _refuse("malformed", "A has_contribution gate needs a numeric `amount`.")
	var required := maxi(0, int(amount))
	# Contribution is tracked externally; this gate is a placeholder for
	# integration with the standing economy. Returns pass for now.
	return _pass()


static func _composite(
	actor: Actor, requirement: Dictionary, require_all: bool, refuse_when_any: bool
) -> Dictionary:
	var children = requirement.get("of", [])
	if not (children is Array) or (children as Array).is_empty():
		return _refuse("malformed", "A composite gate names no children.")
	var unmet: Array[Dictionary] = []
	var passed := 0
	for child in children as Array:
		var verdict := evaluate(actor, child as Dictionary)
		if bool(verdict.get("ok", false)):
			passed += 1
			continue
		var nested_reason := String(verdict.get("reason", ""))
		if nested_reason == "malformed" or nested_reason == "unknown_verb":
			return verdict
		for entry in verdict.get("unmet", []) as Array:
			unmet.append(entry)
	var total := (children as Array).size()
	var ok := passed >= total if require_all else passed > 0
	if refuse_when_any:
		ok = passed == 0
	if ok:
		return _pass()
	return {"ok": false, "reason": "unmet", "unmet": unmet}


static func _ledger(actor: Actor) -> Dictionary:
	if actor == null:
		return BuildingState.empty()
	return BuildingState.normalize(actor.get_module_data(BuildingState.MODULE_KEY))


static func _pass() -> Dictionary:
	return {"ok": true, "reason": "", "unmet": []}


static func _fail(kind: StringName, id: StringName, required, actual, label: String) -> Dictionary:
	return {"ok": false, "reason": "unmet", "unmet": [_entry(kind, id, required, actual, label)]}


static func _entry(kind: StringName, id: StringName, required, actual, label: String) -> Dictionary:
	return {
		"kind": String(kind),
		"id": String(id),
		"required": required,
		"actual": actual,
		"label": label,
	}


static func _refuse(reason: String, label: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"unmet": [_entry(KIND_GATE, &"", true, false, label)],
	}
