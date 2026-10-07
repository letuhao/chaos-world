extends TestCase

## ADR 0902 (P6=C): the FIRING. `CombatBoot.resolve_hit` — the app funnel every landed
## blow passes through — offers the S12 `status_application` row to
## `StatusApi.record_landed_blow`, which advances a counter ONLY when the status's def
## authors `payload.counter`.
##
## Driven end to end with nothing stubbed: `ActorFactory` actors, `CombatBoot.install`,
## the shipped tuning, a real seeded blow. A status the game itself does not counter
## (every shipped def) leaves both spaces empty; a probe def that authors a counter
## advances through the SAME funnel. The probe claims `metal`, which is why the shipped
## metal claimant is set aside for the two positive rows and restored afterwards.

const METAL := &"metal"
const PROBE := &"probe_counter_metal"
const SHIPPED_METAL := &"metal_sever"
const EFFECT_KIND := &"status_application"
const HERO_BASE := {Stat.PHYSIQUE: 12.0, Stat.AGILITY: 8.0, Stat.WILL: 8.0}

var _shipped: StatusDef = null
var _shipped_index: int = -1


func setup() -> void:
	_shipped = StatusApi.definition(SHIPPED_METAL)
	_shipped_index = StatusCatalog.instance()._ids.find(StringName(SHIPPED_METAL))
	assert_ne(_shipped, null, "the shipped metal status loads")
	_forget(PROBE)


func teardown() -> void:
	_forget(PROBE)
	if _shipped == null:
		return
	if not StatusCatalog.instance()._definitions.has(String(SHIPPED_METAL)):
		StatusCatalog.instance()._definitions[String(SHIPPED_METAL)] = _shipped
		if _shipped_index >= 0:
			StatusCatalog.instance()._ids.insert(_shipped_index, SHIPPED_METAL)
		else:
			StatusCatalog.instance()._ids.append(SHIPPED_METAL)


func _forget(probe_id: StringName) -> void:
	StatusCatalog.instance()._rejected.erase(String(probe_id))
	StatusCatalog.instance()._definitions.erase(String(probe_id))
	var ids: Array[StringName] = StatusCatalog.instance()._ids.filter(
		func(candidate: StringName) -> bool: return candidate != probe_id
	)
	StatusCatalog.instance()._ids = ids


## Put the shipped claimant aside so the probe is the ONE def a metal blow maps to.
func _hide_shipped() -> void:
	_forget(SHIPPED_METAL)


func _probe(every_hits: int, reset_on_burst: bool) -> StatusDef:
	var def := StatusDef.new()
	def.id = PROBE
	def.element = METAL
	def.on_landed_blow = true
	def.kind = &"dot"
	def.scope = &"combat"
	def.stacking = &"refresh"
	def.duration = 10.0
	def.magnitude_unit = &"element_power"
	def.magnitude_cap = 5.0
	def.tick_interval = 1.0
	def.mitigation_tags = [&"affinity", &"technique", &"pill"]
	def.payload = {
		"mechanic": &"bleed",
		"text": "counter firing probe",
		"pool": &"health",
		"share_per_pulse": 0.05,
		"modifiers": [{"stat": &"damage_reduction", "op": &"flat", "value": -0.1}],
		"counter": {"every_hits": every_hits, "reset_on_burst": reset_on_burst},
	}
	return def


## One attacker who means to land a status (saturated status power, the producer
## suite's own reading of ADR 0884) and a body-cultivated defender to land it on.
func _pair() -> Dictionary:
	var attacker := ActorFactory.with_body_cultivation(
		ActorFactory.build(&"counter_bruiser", HERO_BASE)
	)
	var tuning := CombatEngineApi.tuning()
	attacker.stats.add_modifier(
		CombatStats.rate_modifier(
			StringName(tuning.status_power_prefix + "omni"),
			float(tuning.status_rate_scale) * 4.0,
			&"test"
		)
	)
	CombatBoot.install(attacker)
	var defender := ActorFactory.spawn_inhabitant(&"counter_target")
	ActorFactory.with_body_cultivation(defender)
	defender.meridians.unlock_for_realm(&"qi_refining")
	return {"attacker": attacker, "defender": defender}


## A bare swing carrying `metal`, built the way `fight_loop` builds its opponent's
## swing — an in-memory def, because no authored "counter probe swing" exists.
func _swing() -> TechniqueDef:
	var def := TechniqueDef.new()
	def.path = PathState.BODY
	def.magnitude = CombatBoot.BARE_SWING_MAGNITUDE
	def.element_share = CombatBoot.BARE_SWING_SHARE
	def.element = METAL
	return def


func _blow(pair: Dictionary, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return (
		CombatBoot
		. resolve_hit(pair["attacker"], pair["defender"], _swing(), CombatEngineApi.tuning(), rng)
		. to_dict()
	)


## The `status_application` row one outcome carries, or `{}`.
func _status_row(outcome: Dictionary) -> Dictionary:
	for entry in outcome.get("effects", []) as Array:
		if (
			entry is Dictionary
			and StringName((entry as Dictionary).get("kind", &"")) == EFFECT_KIND
		):
			return entry as Dictionary
	return {}


func test_the_funnel_advances_an_authored_counter_and_keeps_the_residual() -> void:
	_hide_shipped()
	assert_eq(StatusCatalog.instance().register(_probe(2, true)), true, "the probe is admitted")
	var pair := _pair()
	var first := _blow(pair, 17)
	var row := _status_row(first)
	assert_eq(bool(row.get("applied", false)), true, "the first blow lands the probe status")
	var defender := pair["defender"] as Actor
	var instance_id := int(row.get("instance_id", 0))
	assert_eq(instance_id > 0, true, "the S12 row carries the minted handle")
	var counters := StatusApi.counter_snapshot(defender)
	assert_eq(int(counters["instance"].get(instance_id, 0)), 1, "the funnel counted one hit")
	var second := _blow(pair, 18)
	var carried := _status_row(second)
	assert_eq(
		String(carried.get("refused", "")),
		"already_held",
		"the second blow is still the merge's to refuse — and still files a row"
	)
	assert_eq(
		String(carried.get("status_id", "")),
		"probe_counter_metal",
		"which NAMES the status it carried, so the count can advance"
	)
	counters = StatusApi.counter_snapshot(defender)
	assert_eq(
		int(counters["instance"].get(instance_id, 0)),
		0,
		"and the crossing kept the residual on the same instance"
	)


func test_the_latch_form_grows_past_its_threshold() -> void:
	_hide_shipped()
	assert_eq(StatusCatalog.instance().register(_probe(2, false)), true, "the probe is admitted")
	var pair := _pair()
	assert_eq(
		bool(_status_row(_blow(pair, 23)).get("applied", false)), true, "the first blow lands"
	)
	assert_eq(
		String(_status_row(_blow(pair, 24)).get("refused", "")),
		"already_held",
		"the second blow is an already-held landing, not a fresh one"
	)
	var defender := pair["defender"] as Actor
	var space := StatusApi.counter_snapshot(defender)["instance"] as Dictionary
	assert_eq(space.size(), 1, "one live instance counted")
	var instance_id := int(space.keys()[0])
	assert_eq(int(space[instance_id]), 2, "the latch kept the total at its crossing")
	_blow(pair, 25)
	space = StatusApi.counter_snapshot(defender)["instance"] as Dictionary
	assert_eq(int(space.get(instance_id, 0)), 3, "and grew on the next landed blow")


func test_a_shipped_status_leaves_both_spaces_empty() -> void:
	var pair := _pair()
	var outcome := _blow(pair, 31)
	assert_eq(
		bool(_status_row(outcome).get("applied", false)),
		true,
		"the shipped claim lands the blow's metal status"
	)
	var defender := pair["defender"] as Actor
	var counters := StatusApi.counter_snapshot(defender)
	assert_eq(
		(counters["instance"] as Dictionary).is_empty(),
		true,
		"a def that authors no counter counts nothing"
	)
	assert_eq((counters["grant"] as Dictionary).is_empty(), true, "in either space")
