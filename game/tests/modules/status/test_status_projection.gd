extends TestCase

## ADR 0902 (P8, BL-0924): the projection host. The load-bearing counterexamples:
## an unchanged stage produces NO second apply (the pre-read, not the stacking mode), a
## stage change withdraws the previous pair before writing the next, `-1` withdraws, and
## the track's grant scopes the withdraw so one track cannot reach another's instance.

var _watcher: Callable = Callable()


func setup() -> void:
	StatusEvents.shared().clear_log()


func teardown() -> void:
	if _watcher.is_valid() and StatusEvents.shared().status_applied.is_connected(_watcher):
		StatusEvents.shared().status_applied.disconnect(_watcher)
	_watcher = Callable()
	StatusEvents.shared().clear_log()


func _actor() -> Actor:
	return ActorFactory.build(&"projection_probe", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})


func _watch_applied(hits: Array) -> void:
	_watcher = (func(
		host_id: StringName, status_id: StringName, instance_id: int, grant_id: StringName
	) -> void:
		hits.append({"host": host_id, "id": status_id, "grant": grant_id}))
	StatusEvents.shared().status_applied.connect(_watcher)


func test_a_stage_change_applies_once_and_an_unchanged_sync_writes_nothing() -> void:
	var actor := _actor()
	var rungs := AgeBands.rungs()
	var hits: Array = []
	_watch_applied(hits)
	var first := StatusApi.sync_projection(actor, AgeBands.TRACK, 1, rungs)
	assert_eq(String(first.get("change", "")), "applied", "the first sync applies")
	assert_eq((first.get("ids") as Array).size(), 2, "the whole pair, not one half")
	assert_eq(hits.size(), 2, "two applied facts for the pair")
	assert_eq(
		actor.has_status(AgeBands.wear_id(&"greenwood")),
		true,
		"the stage's own ids are on the actor"
	)
	# THE row: the idempotence is the PRE-READ, so N syncs at an unchanged stage are ONE
	# apply — not a fresh instance wearing the same id.
	var again := StatusApi.sync_projection(actor, AgeBands.TRACK, 1, rungs)
	assert_eq(String(again.get("change", "")), "no_change", "an unchanged stage writes nothing")
	assert_eq(hits.size(), 2, "and announces nothing")
	var moved := StatusApi.sync_projection(actor, AgeBands.TRACK, 2, rungs)
	assert_eq(String(moved.get("change", "")), "applied", "the next stage applies")
	assert_eq(actor.has_status(AgeBands.wear_id(&"greenwood")), false, "withdrawing the old pair")
	assert_eq(actor.has_status(AgeBands.wear_id(&"gilded")), true, "before writing the new one")
	assert_eq(hits.size(), 4, "two more facts")
	var withdrawn := StatusApi.sync_projection(actor, AgeBands.TRACK, -1, rungs)
	assert_eq(String(withdrawn.get("change", "")), "withdrew", "stage -1 withdraws")
	assert_eq(actor.has_status(AgeBands.wear_id(&"gilded")), false, "the pair is gone")
	var nothing := StatusApi.sync_projection(actor, AgeBands.TRACK, -1, rungs)
	assert_eq(
		String(nothing.get("change", "")),
		"no_change",
		"nothing live and nothing wanted is a no-op, not a churn"
	)


func test_the_track_grant_scopes_the_withdraw() -> void:
	var actor := _actor()
	assert_eq(
		String(
			StatusApi.sync_projection(actor, AgeBands.TRACK, 0, AgeBands.rungs()).get("change", "")
		),
		"applied",
		"the age track projects"
	)
	# A second track's boolean stage, found by its exact id and scoped by its own grant.
	var boolean := StatusApi.sync_projection(
		actor, &"probe", 0, [[&"metal_sever"]], StatusProjection.MATCH_EXACT
	)
	assert_eq(String(boolean.get("change", "")), "applied", "a second track applies")
	var dropped := StatusApi.sync_projection(
		actor, &"probe", -1, [[&"metal_sever"]], StatusProjection.MATCH_EXACT
	)
	assert_eq(String(dropped.get("change", "")), "withdrew", "and withdraws")
	assert_eq(
		actor.has_status(AgeBands.wear_id(&"first_ash")),
		true,
		"the age track's instance is untouched by the other track's withdraw"
	)
	assert_eq(actor.has_status(&"metal_sever"), false, "while the boolean track's is gone")


func test_rung_validation_refuses_a_repeated_id() -> void:
	var problems := StatusProjection.rung_problems([[&"a", &"b"], [&"a"]])
	assert_ne(problems.is_empty(), true, "a repeated id is refused")
	var actor := _actor()
	var refused := StatusApi.sync_projection(actor, &"probe", 1, [[&"a", &"b"], [&"a"]])
	assert_eq(
		String(refused.get("change", "")), "no_change", "and a sync carrying it writes nothing"
	)
	assert_eq(String(refused.get("reason", "")).contains("two rungs"), true, "naming the rule")
	assert_eq(actor.statuses.size(), 0, "nothing was applied")


func test_a_stage_out_of_range_is_refused() -> void:
	var actor := _actor()
	var refused := StatusApi.sync_projection(actor, &"probe", 99, [[&"metal_sever"]])
	assert_eq(String(refused.get("reason", "")), "stage_out_of_range", "the range is named")
	assert_eq(actor.statuses.size(), 0, "and nothing was written")


func test_the_summary_publishes_the_age_track_read_model() -> void:
	var actor := _actor()
	var report := StatusApi.summary(actor)
	assert_eq(report.has("age"), true, "the age read model rides the summary")
	var age := report["age"] as Dictionary
	assert_eq(age.has("band"), true, "with the band")
	assert_eq(age.has("ids"), true, "and the pair as one list")
