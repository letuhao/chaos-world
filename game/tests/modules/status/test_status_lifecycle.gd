extends TestCase

## ADR 0902 (P5/P13): the lifecycle verbs and the readback on the `status` facade.
## `grant_id` rides the effect; [method StatusApi.clear_grant] removes every instance
## ONE grant wrote and leaves a coexist sibling under ANOTHER grant alone;
## [method StatusApi.withdraw] removes the host's whole table; [method StatusApi.summary]
## publishes the new fields as primitives, including the bus's refused log.
##
## The pilot shape is Keepverse's: two coexisting stacks of one status withdraw
## independently (`StatusDerivedModReader`), a grant is cleared before a replacement is
## written so a stage change never stacks (`StatusProjectionHost`), and a host that
## leaves takes its instances with it (`WithdrawEntity`).

const PROBE := &"probe_lifecycle"
const PROBE_FAMILY := &"probe_family"

var _watcher: Callable = Callable()


func setup() -> void:
	_forget(PROBE)
	StatusEvents.shared().clear_log()
	StatusApi.set_icd_default(0.0)


func teardown() -> void:
	if _watcher.is_valid() and StatusEvents.shared().status_applied.is_connected(_watcher):
		StatusEvents.shared().status_applied.disconnect(_watcher)
	_watcher = Callable()
	_forget(PROBE)
	StatusEvents.shared().clear_log()
	StatusApi.set_icd_default(0.0)


## Both halves of a registration undone — the pattern `test_status_refusals.gd` uses,
## because `StatusCatalog` is a process-wide singleton.
func _forget(probe_id: StringName) -> void:
	StatusCatalog.instance()._rejected.erase(String(probe_id))
	StatusCatalog.instance()._definitions.erase(String(probe_id))
	var ids: Array[StringName] = StatusCatalog.instance()._ids.filter(
		func(candidate: StringName) -> bool: return candidate != probe_id
	)
	StatusCatalog.instance()._ids = ids


## A COEXIST probe so one id can hold two instances under two grants — the exact shape
## `clear_grant` must not collapse. Its family, one category and the CC flag are
## authored too, because `summary` publishes all three.
func _def(icd: float = 0.0) -> StatusDef:
	var def := StatusDef.new()
	def.id = PROBE
	def.element = &"metal"
	def.kind = &"dot"
	def.scope = &"combat"
	def.stacking = &"coexist"
	def.duration = 10.0
	def.magnitude_unit = &"element_power"
	def.magnitude_cap = 5.0
	def.tick_interval = 1.0
	def.icd = icd
	def.family = PROBE_FAMILY
	def.categories = [&"probe_category"]
	def.crowd_control = true
	def.mitigation_tags = [&"affinity", &"technique", &"pill"]
	def.payload = {
		"mechanic": &"bleed",
		"text": "test lifecycle",
		"pool": &"health",
		"share_per_pulse": 0.05,
		"modifiers": [{"stat": &"damage_reduction", "op": &"flat", "value": -0.1}],
	}
	return def


func _register(icd: float = 0.0) -> void:
	assert_eq(StatusCatalog.instance().register(_def(icd)), true, "the probe def is admitted")


func _actor() -> Actor:
	var actor := Actor.new(&"lifecycle_probe", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
	actor.attach_core_resources()
	return actor


## Count the applied facts this test's own applications produce. A local array is
## captured BY REFERENCE, so the lambda appends into the caller's list.
func _watch_applied(hits: Array) -> void:
	_watcher = (func(
		host_id: StringName, status_id: StringName, instance_id: int, grant_id: StringName
	) -> void:
		(
			hits
			. append(
				{
					"host": host_id,
					"id": status_id,
					"instance": instance_id,
					"grant": grant_id,
				}
			)
		))
	StatusEvents.shared().status_applied.connect(_watcher)


func test_apply_carries_the_grant_and_the_result_reports_the_handle() -> void:
	_register()
	var actor := _actor()
	var applied := StatusApi.apply(actor, PROBE, 1.0, -1.0, &"g1")
	assert_eq(bool(applied.get("ok", false)), true, "the application lands")
	assert_eq(String(applied.get("grant", "")), "g1", "the result names its grant")
	var held: StatusEffect = actor.statuses[0]
	assert_eq(held.grant_id, &"g1", "and the effect carries it")
	assert_eq(int(applied.get("instance_id", 0)), held.instance_id, "with the live handle")


func test_apply_fires_the_applied_signal_with_the_same_facts() -> void:
	_register()
	var actor := _actor()
	var hits: Array = []
	_watch_applied(hits)
	var applied := StatusApi.apply(actor, PROBE, 1.0, -1.0, &"g1")
	assert_eq(hits.size(), 1, "the completed fact is announced once")
	var hit: Dictionary = hits[0]
	assert_eq(String(hit["host"]), String(actor.id), "naming the host that carries it")
	assert_eq(String(hit["id"]), "probe_lifecycle", "the status")
	assert_eq(int(hit["instance"]), int(applied.get("instance_id", 0)), "the handle")
	assert_eq(String(hit["grant"]), "g1", "and the application's grant")


func test_clear_grant_clears_one_grant_and_leaves_the_sibling() -> void:
	_register()
	var actor := _actor()
	assert_eq(
		bool(StatusApi.apply(actor, PROBE, 1.0, -1.0, &"g1").get("ok", false)),
		true,
		"the first grant lands"
	)
	assert_eq(
		bool(StatusApi.apply(actor, PROBE, 1.0, -1.0, &"g2").get("ok", false)),
		true,
		"and the sibling under the second grant"
	)
	assert_eq(actor.statuses.size(), 2, "two coexisting instances")
	var cleared := StatusApi.clear_grant(actor, &"g1")
	assert_eq(bool(cleared.get("ok", false)), true, "the grant is cleared")
	assert_eq(int(cleared.get("count", 0)), 1, "one instance answered g1")
	assert_eq(actor.statuses.size(), 1, "and the sibling under g2 lives")
	assert_eq(actor.statuses[0].grant_id, &"g2", "which is the g2 one")


func test_clear_grant_refuses_an_empty_grant() -> void:
	var actor := _actor()
	var answer := StatusApi.clear_grant(actor, &"")
	assert_eq(bool(answer.get("ok", true)), false, "an empty grant names nothing")
	assert_eq(String(answer.get("reason", "")), "empty_grant", "and says so")


func test_withdraw_clears_every_tracked_instance_and_leaves_foreign_state() -> void:
	_register()
	var actor := _actor()
	StatusApi.apply(actor, PROBE, 1.0, -1.0, &"g1")
	StatusApi.apply(actor, PROBE, 1.0, -1.0, &"g2")
	var foreign := StatusEffect.new(&"foreign_blessing", 10.0)
	actor.add_status(foreign)
	assert_eq(actor.statuses.size(), 3, "two tracked instances and one foreign")
	var answer := StatusApi.withdraw(actor)
	assert_eq(bool(answer.get("ok", false)), true, "the host left")
	assert_eq(int(answer.get("count", 0)), 2, "both tracked instances went")
	assert_eq(actor.statuses.size(), 1, "the foreign status is not ours to purge")
	assert_eq(actor.statuses[0].id, &"foreign_blessing", "and it is the one left")


func test_summary_reports_the_lifecycle_keys_as_primitives() -> void:
	_register()
	var actor := _actor()
	StatusApi.apply(actor, PROBE, 1.0, -1.0, &"g1")
	var report := StatusApi.summary(actor)
	assert_eq(report.has("resisted"), true, "the refused log rides the report")
	assert_eq(report["resisted"] is Array, true, "as an array")
	var rows: Array = report["active"]
	assert_eq(rows.size(), 1, "one live row")
	var row: Dictionary = rows[0]
	assert_eq(int(row["instance_id"]) > 0, true, "the handle is published")
	assert_eq(String(row["grant"]), "g1", "and the grant")
	assert_eq(String(row["family"]), "probe_family", "the family is published")
	assert_eq(row["categories"], ["probe_category"], "the categories are plain strings")
	assert_eq(bool(row["crowd_control"]), true, "and the CC flag")


func test_the_refused_log_carries_the_module_doors_reason() -> void:
	_register(3.0)
	var actor := _actor()
	assert_eq(
		bool(StatusApi.apply(actor, PROBE, 1.0, -1.0, &"g1").get("ok", false)),
		true,
		"the first lands"
	)
	var refused := StatusApi.apply(actor, PROBE, 1.0, -1.0, &"g2")
	assert_eq(String(refused.get("reason", "")), "status_icd", "the window refuses the second")
	var log := StatusEvents.shared().resisted_log()
	assert_eq(log.size(), 1, "the refusal is the one entry")
	assert_eq(String(log[0]["id"]), "probe_lifecycle", "naming the status")
	assert_eq(String(log[0]["reason"]), "status_icd", "with its reason")
	assert_eq(String(log[0]["host"]), String(actor.id), "and its host")
