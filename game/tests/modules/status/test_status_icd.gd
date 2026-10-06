extends TestCase

## ADR 0902 (P4): the per-status re-application lockout. A def that authors `icd` —
## or a def that authors none while the tuning default says otherwise — refuses a
## second application of the same id until the window has elapsed. The clock is REAL
## time advanced by `tick_statuses`, and the application that lands resets it.

const PROBE := &"probe_icd_burn"
const PROBE_DEFAULT := &"probe_icd_default"


func setup() -> void:
	# The default is module state; every test starts and ends outside any window.
	StatusApi.set_icd_default(0.0)
	_forget(PROBE)
	_forget(PROBE_DEFAULT)


func teardown() -> void:
	StatusApi.set_icd_default(0.0)
	_forget(PROBE)
	_forget(PROBE_DEFAULT)


## Both halves of a registration undone — the pattern `test_status_refusals.gd` uses,
## because `StatusCatalog` is a process-wide singleton and a probe left inside would be
## reported as a content change by a suite that never made one.
func _forget(probe_id: StringName) -> void:
	StatusCatalog.instance()._rejected.erase(String(probe_id))
	StatusCatalog.instance()._definitions.erase(String(probe_id))
	var ids: Array[StringName] = StatusCatalog.instance()._ids.filter(
		func(candidate: StringName) -> bool: return candidate != probe_id
	)
	StatusCatalog.instance()._ids = ids


## A well-formed def, mirrored off `test_status_refusals.gd`'s baseline so the probe is
## refused for the ICD and never for a shape problem.
func _def(id: StringName, icd: float) -> StatusDef:
	var def := StatusDef.new()
	def.id = id
	def.element = &"metal"
	def.kind = &"dot"
	def.scope = &"combat"
	def.stacking = &"refresh"
	def.duration = 10.0
	def.magnitude_unit = &"element_power"
	def.magnitude_cap = 5.0
	def.tick_interval = 1.0
	def.icd = icd
	def.mitigation_tags = [&"affinity", &"technique", &"pill"]
	def.payload = {
		"mechanic": &"bleed",
		"text": "test icd",
		"pool": &"health",
		"share_per_pulse": 0.05,
		"modifiers": [{"stat": &"damage_reduction", "op": &"flat", "value": -0.1}],
	}
	return def


func _actor() -> Actor:
	var actor := Actor.new(&"icd_probe", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
	actor.attach_core_resources()
	return actor


## The control: no authored ICD and no default means no window at all — the check is
## additive and cannot lock out statuses that never asked for it.
func test_a_def_without_an_icd_never_locks_out() -> void:
	var def := _def(PROBE_DEFAULT, 0.0)
	assert_eq(StatusCatalog.instance().register(def), true, "the probe def is admitted")
	var actor := _actor()
	assert_eq(bool(StatusApi.apply(actor, PROBE_DEFAULT, 1.0).get("ok", false)), true, "it lands")
	assert_eq(
		bool(StatusApi.apply(actor, PROBE_DEFAULT, 1.0).get("ok", false)),
		true,
		"and a second application is not locked out: no ICD authored, no default"
	)


## The authored window, end to end: refused inside it, accepted past it, and the
## refusal names its own reason (ADR 0902/P14's `status_icd`).
func test_the_icd_refuses_a_re_application_and_releases_after_the_window() -> void:
	var def := _def(PROBE, 2.0)
	assert_eq(StatusCatalog.instance().register(def), true, "the probe def is admitted")
	var actor := _actor()
	assert_eq(bool(StatusApi.apply(actor, PROBE, 1.0).get("ok", false)), true, "the first lands")
	var refused := StatusApi.apply(actor, PROBE, 1.0)
	assert_eq(bool(refused.get("ok", true)), false, "an immediate re-application is refused")
	assert_eq(String(refused.get("reason", "")), "status_icd", "with the ICD reason")
	# The window is REAL time, not the pulse cadence: one tick of `icd` seconds opens it.
	StatusApi.tick_statuses(actor, 2.0)
	assert_eq(
		bool(StatusApi.apply(actor, PROBE, 1.0).get("ok", false)),
		true,
		"past the window the id accepts again"
	)


## The tuning default is the fallback a def without its own `icd` reads — P4's C half.
func test_the_tuning_default_locks_out_a_def_that_authors_none() -> void:
	StatusApi.set_icd_default(3.0)
	var def := _def(PROBE_DEFAULT, 0.0)
	assert_eq(StatusCatalog.instance().register(def), true, "the probe def is admitted")
	var actor := _actor()
	assert_eq(bool(StatusApi.apply(actor, PROBE_DEFAULT, 1.0).get("ok", false)), true, "it lands")
	assert_eq(
		String(StatusApi.apply(actor, PROBE_DEFAULT, 1.0).get("reason", "")),
		"status_icd",
		"the tuning default is the fallback the check reads"
	)
