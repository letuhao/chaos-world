extends TestCase

## ADR 0902 (P3): `coexist` is the merge mode that never matches — two applications of
## one id leave TWO independent instances, each with its own minted handle. Driven here
## through the FRONT DOOR (`StatusApi.apply` on an authored def), because that is where a
## `stacking` string could silently fall back to refresh: the def-to-effect mapping is
## the mechanism, and the registry's own merge tests cannot see it.

const PROBE := &"probe_coexist_smoke"


func setup() -> void:
	_forget(PROBE)


func teardown() -> void:
	_forget(PROBE)


## Both halves of a registration undone — the pattern `test_status_refusals.gd` uses,
## because `StatusCatalog` is a process-wide singleton.
func _forget(probe_id: StringName) -> void:
	StatusCatalog.instance()._rejected.erase(String(probe_id))
	StatusCatalog.instance()._definitions.erase(String(probe_id))
	var ids: Array[StringName] = StatusCatalog.instance()._ids.filter(
		func(candidate: StringName) -> bool: return candidate != probe_id
	)
	StatusCatalog.instance()._ids = ids


## A well-formed def, mirrored off `test_status_refusals.gd`'s baseline so the probe is
## refused for nothing but its own shape.
func _def(id: StringName, stacking: StringName) -> StatusDef:
	var def := StatusDef.new()
	def.id = id
	def.element = &"metal"
	def.kind = &"dot"
	def.scope = &"combat"
	def.stacking = stacking
	def.duration = 10.0
	def.magnitude_unit = &"element_power"
	def.magnitude_cap = 5.0
	def.tick_interval = 1.0
	def.mitigation_tags = [&"affinity", &"technique", &"pill"]
	def.payload = {
		"mechanic": &"bleed",
		"text": "test coexist",
		"pool": &"health",
		"share_per_pulse": 0.05,
		"modifiers": [{"stat": &"damage_reduction", "op": &"flat", "value": -0.1}],
	}
	return def


func _actor() -> Actor:
	var actor := Actor.new(&"coexist_probe", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
	actor.attach_core_resources()
	return actor


func _two_burning_instances() -> Actor:
	var actor := _actor()
	assert_eq(bool(StatusApi.apply(actor, PROBE, 1.0).get("ok", false)), true, "the first lands")
	assert_eq(
		bool(StatusApi.apply(actor, PROBE, 1.0).get("ok", false)),
		true,
		"and the second lands too — coexist never matches"
	)
	assert_eq(actor.statuses.size(), 2, "two live instances of one id")
	return actor


func test_a_coexist_def_takes_two_instances_with_distinct_handles() -> void:
	var def := _def(PROBE, &"coexist")
	assert_eq(StatusCatalog.instance().register(def), true, "the probe def is admitted")
	var actor := _two_burning_instances()
	var first: StatusEffect = actor.statuses[0]
	var second: StatusEffect = actor.statuses[1]
	assert_ne(first.instance_id, second.instance_id, "two distinct handles")
	assert_eq(first.instance_id > 0 and second.instance_id > 0, true, "both minted")


## The store reconciles per INSTANCE (ADR 0902): a tick must keep the sibling, not
## collapse the pair back into the one-per-id shape the older key space assumed.
func test_a_tick_keeps_both_coexisting_instances() -> void:
	var def := _def(PROBE, &"coexist")
	assert_eq(StatusCatalog.instance().register(def), true, "the probe def is admitted")
	var actor := _two_burning_instances()
	var first: StatusEffect = actor.statuses[0]
	var second: StatusEffect = actor.statuses[1]
	StatusApi.tick_statuses(actor, 0.5)
	assert_eq(actor.statuses.size(), 2, "the reconcile keeps the sibling")
	assert_ne(
		actor.statuses[0].instance_id, actor.statuses[1].instance_id, "and both handles are intact"
	)
	assert_eq(
		(
			actor.statuses[0].instance_id == first.instance_id
			and actor.statuses[1].instance_id == second.instance_id
		),
		true,
		"with the SAME two instances, not two fresh ones"
	)
