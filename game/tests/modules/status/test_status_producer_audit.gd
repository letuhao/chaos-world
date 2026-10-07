extends TestCase

## ADR 0902 (T9): the producer audit. Every door that mints a status is exercised
## against the CHANGED semantics — the bus event, the readback — because the new
## surfaces were built and tested from the combat doors first:
##
##   element-riding catalogue -> combat_boot_status_producer / combat_exchange_status
##   mind statuses            -> the mind suites + the T7 guard (decision 7: not gated)
##   tribulation blessings    -> this file (`apply_cultivation`) + status_blessing
##   environment hazards      -> this file (`resolve`, the zone's door) + environment_field
##   domain fields            -> test_domain_fixtures / test_domain_fixture_reads
##   loot afflictions         -> this file (`apply`, the affliction's door) + loot boss suite
##   consumable-applied       -> test_status_cleanse (the pill's lever door)

const BLESSING := &"wood_bloom"

var _watcher: Callable = Callable()


func setup() -> void:
	StatusEvents.shared().clear_log()


func teardown() -> void:
	if _watcher.is_valid() and StatusEvents.shared().status_applied.is_connected(_watcher):
		StatusEvents.shared().status_applied.disconnect(_watcher)
	_watcher = Callable()
	StatusEvents.shared().clear_log()


func _actor() -> Actor:
	return ActorFactory.build(&"producer_audit", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})


func _watch_applied(hits: Array) -> void:
	_watcher = (func(
		host_id: StringName, status_id: StringName, instance_id: int, grant_id: StringName
	) -> void:
		hits.append({"host": host_id, "id": status_id, "instance": instance_id, "grant": grant_id}))
	StatusEvents.shared().status_applied.connect(_watcher)


func test_the_blessing_door_announces_the_applied_fact() -> void:
	var actor := _actor()
	var hits: Array = []
	_watch_applied(hits)
	var applied := StatusApi.apply_cultivation(actor, BLESSING, 1.0)
	assert_eq(bool(applied.get("ok", false)), true, "the blessing lands through its own door")
	assert_eq(hits.size(), 1, "and announces the completed fact")
	assert_eq(String(hits[0]["id"]), "wood_bloom", "naming the blessing")
	assert_eq(int(hits[0]["instance"]) > 0, true, "with its minted handle")


func test_the_zone_door_resolves_and_the_readback_sees_it() -> void:
	var actor := _actor()
	# The zone's door is TWO calls, exactly as `EnvironmentField` performs them: the
	# caller adds the effect it built, then `resolve` binds the module's runtime record.
	var effect := StatusEffect.new(&"metal_sever", 10.0)
	effect.kind = StatusEffect.Kind.DOT
	effect.tick_interval = 1.0
	effect.mitigation_tags = [&"gear"]
	actor.add_status(effect)
	var answer := StatusApi.resolve(actor, effect)
	assert_eq(bool(answer.get("ok", false)), true, "the zone's built effect resolves")
	var rows := StatusApi.summary(actor)["active"] as Array
	assert_eq(rows.size(), 1, "and the readback sees one live row")
	assert_eq(bool((rows[0] as Dictionary)["known"]), true, "known: the module bound its record")


func test_the_affliction_door_lands_through_the_facade_and_reads_back() -> void:
	var actor := _actor()
	var applied := StatusApi.apply(actor, &"fire_immolation", 1.0)
	assert_eq(bool(applied.get("ok", false)), true, "the affliction's door is the facade apply")
	var rows := StatusApi.summary(actor)["active"] as Array
	assert_eq(rows.size(), 1, "the readback carries the row")
	assert_eq(
		int((rows[0] as Dictionary)["instance_id"]),
		int(applied.get("instance_id", 0)),
		"naming the same handle the apply answered with"
	)


## The boundary the audit exists to pin: counters fill from landed blows and authored
## meters (T4/T5), never from the blessing or zone doors.
func test_the_non_combat_doors_leave_the_counter_store_empty() -> void:
	var actor := _actor()
	assert_eq(
		bool(StatusApi.apply_cultivation(actor, BLESSING, 1.0).get("ok", false)),
		true,
		"a blessing lands"
	)
	var effect := StatusEffect.new(&"metal_sunder", 10.0)
	effect.kind = StatusEffect.Kind.DOT
	effect.tick_interval = 1.0
	effect.mitigation_tags = [&"gear"]
	actor.add_status(effect)
	assert_eq(
		bool(StatusApi.resolve(actor, effect).get("ok", false)), true, "a zone effect resolves"
	)
	var counters := StatusApi.counter_snapshot(actor)
	assert_eq((counters["grant"] as Dictionary).is_empty(), true, "no grant counter was written")
	assert_eq(
		(counters["instance"] as Dictionary).is_empty(), true, "and no instance counter either"
	)
