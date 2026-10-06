extends TestCase

## ADR 0902 (P5): the SPINE's S12 door. `StatusApply._written` applies through
## `Actor.add_status` without ever naming the `status` module — so its applied and
## refused facts are announced on the contract bus and land in the same log the
## module's own door feeds. Driven through a real resolve (a landed blow) rather than
## by calling the emit helpers, because the claim is that THIS door announces.
##
## The attacker's status power is oversaturated so `p_apply` clamps to 1.0 and the seed
## can never decide which branch a case lands in; the refused case is an immunity tag,
## which refuses before the roll.

const SPINE_STATUS := &"probe_spine_status"

var _tuning: CombatTuning
var _watcher: Callable = Callable()


func setup() -> void:
	_tuning = CombatTestKit.shipped()
	StatusEvents.shared().clear_log()


func teardown() -> void:
	if _watcher.is_valid() and StatusEvents.shared().status_applied.is_connected(_watcher):
		StatusEvents.shared().status_applied.disconnect(_watcher)
	_watcher = Callable()
	StatusEvents.shared().clear_log()


func _attr(actor: Actor, id_prefix: String, suffix: String, value: float) -> void:
	actor.stats.add_modifier(
		CombatStats.rate_modifier(StringName(id_prefix + suffix), value, &"test")
	)


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


func _request(extra: Dictionary = {}) -> Dictionary:
	var request := {
		"id": SPINE_STATUS,
		"chance": 1.0,
		"element": &"fire",
		"kind": &"dot",
		"duration": 10.0,
		"potency": 1.0,
		"scope": String(StatusApply.SCOPE_COMBAT),
		"grant_id": &"g-spine",
	}
	for key in extra.keys():
		request[key] = extra[key]
	return request


## One landed blow: saturated accuracy AND status power, so the band and the apply roll
## are both past their clamps and the request decides the case alone.
func _apply(request: Dictionary, setup_target: Callable = Callable()) -> Dictionary:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	attacker.stats.add_modifier(CombatStats.rate_modifier(CombatStats.ACCURACY, 1.0, &"test"))
	_attr(attacker, _tuning.status_power_prefix, "omni", 1.0)
	var target := CombatTestKit.actor(&"target")
	if setup_target.is_valid():
		setup_target.call(target)
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 25.0
	MechanismSlot.bind(attacker, mechanism)
	var rng := CombatTestKit.rng(11)
	var technique := CombatTestKit.technique(100.0)
	var outcome := CombatSpine.resolve_hit(attacker, target, technique, _tuning, rng)
	var ctx := AttackContext.new(attacker, target, technique, _tuning)
	ctx.set_data(StatusApply.REQUEST_KEY, request)
	return StatusApply.apply(attacker, target, _tuning, ctx, outcome, rng, technique, 0)


func test_a_landed_status_fires_applied_with_the_spine_grant() -> void:
	var hits: Array = []
	_watch_applied(hits)
	var result := _apply(_request())
	assert_eq(bool(result.get(StatusApply.APPLIED, false)), true, "the status landed")
	assert_eq(hits.size(), 1, "the applied fact fired once")
	var hit: Dictionary = hits[0]
	assert_eq(String(hit["id"]), "probe_spine_status", "naming the status")
	assert_eq(String(hit["grant"]), "g-spine", "carrying the request's grant")
	assert_eq(int(hit["instance"]) > 0, true, "with the handle the registry minted")
	assert_eq(String(hit["host"]), "target", "and the host that carries it")


func test_a_refused_status_fires_resisted_with_the_immune_reason() -> void:
	var result := _apply(
		_request({"immunity_tags": [&"probe_tag"]}),
		func(target: Actor) -> void: _attr(target, _tuning.status_immune_prefix, "probe_tag", 1.0)
	)
	assert_eq(bool(result.get(StatusApply.APPLIED, true)), false, "the immunity refused it")
	assert_eq(String(result.get(StatusApply.REFUSED, "")), "immune", "hard, before the roll")
	var log := StatusEvents.shared().resisted_log()
	assert_eq(log.size(), 1, "the refusal is the one entry")
	assert_eq(String(log[0]["id"]), "probe_spine_status", "naming the status")
	assert_eq(String(log[0]["reason"]), "immune", "with the immune reason")
	assert_eq(String(log[0]["detail"]), "probe_tag", "naming the tag that refused")
	assert_eq(String(log[0]["host"]), "target", "and the host")
