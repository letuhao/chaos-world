extends TestCase

## ADR 0883: what an actor has BUILT resolves into aptitude points. The three majors are
## the three postures (body -> force, qi -> finesse, mind -> bastion), a started path's
## points are its ladder index (1-based) times the table's per-realm budget split across
## the posture's four, and a posture is READ (Keepverse's DominantPosture), never stored.


func _grant() -> AptitudeGrant:
	var grant := AptitudeGrant.shipped()
	assert_ne(grant, null, "the shipped grant table loads")
	return grant


func _actor_with(path_id: StringName, realm_id: StringName) -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(path_id, realm_id))
	return actor


func _row_for(grant: AptitudeGrant, path_id: StringName) -> Dictionary:
	for row in grant.rows:
		if StringName(row.get("path", &"")) == path_id:
			return row
	assert_eq(false, true, "the table carries a row for %s" % String(path_id))
	return {}


func test_the_shipped_table_covers_the_three_majors_once_each() -> void:
	var grant := _grant()
	assert_eq(grant.rows.size(), 3, "three rows")
	var postures := {}
	for row in grant.rows:
		var posture := StringName(row.get("posture", &""))
		assert_eq(Aptitude.POSTURES.has(posture), true, "%s is a posture" % String(posture))
		postures[posture] = true
		assert_eq(PathState.ALL.has(StringName(row.get("path", &""))), true, "a real major path")
		assert_eq(float(row.get("per_realm", 0.0)) > 0.0, true, "a positive budget")
	assert_eq(postures.size(), 3, "one row per posture")


func test_a_path_grants_its_ladder_index_times_the_budget_split_four_ways() -> void:
	var grant := _grant()
	var row := _row_for(grant, PathState.BODY)
	var realm := RealmDefaults.ladder().realms()[1].id
	var points := grant.resolve(_actor_with(PathState.BODY, realm))
	for id in Aptitude.in_posture(Aptitude.POSTURE_FORCE):
		assert_almost_eq(
			float(points[id]),
			2.0 * float(row.get("per_realm", 0.0)) / float(Aptitude.PER_POSTURE),
			"%s takes its quarter" % String(id)
		)
	assert_eq(points.has(&"agility"), false, "another posture is untouched")


func test_an_unstarted_or_unknown_path_grants_nothing() -> void:
	var grant := _grant()
	assert_eq(grant.resolve(_actor_with(PathState.BODY, &"")).is_empty(), true, "an unstarted path")
	assert_eq(grant.resolve(Actor.new(&"hero", {})).is_empty(), true, "no paths at all")
	assert_eq(
		grant.resolve(_actor_with(&"no_such_path", &"primordial_origin")).is_empty(),
		true,
		"an unknown path"
	)


func test_the_dominant_posture_is_read_and_a_tie_reads_none() -> void:
	assert_eq(AptitudeGrant.dominant_posture({}), &"", "nothing leads nothing")
	assert_eq(
		AptitudeGrant.dominant_posture({&"might": 1.0, &"agility": 1.0}), &"", "a tie reads none"
	)
	assert_eq(
		AptitudeGrant.dominant_posture({&"might": 2.0, &"agility": 1.0}), &"force", "the lead"
	)
	var grant := _grant()
	var body := grant.resolve(_actor_with(PathState.BODY, RealmDefaults.ladder().realms()[5].id))
	assert_eq(AptitudeGrant.dominant_posture(body), &"force", "a body build reads force")


func test_apply_replaces_the_store_from_the_build() -> void:
	var grant := _grant()
	var actor := _actor_with(PathState.QI, RealmDefaults.ladder().realms()[3].id)
	actor.stats.set_aptitude(&"might", 99.0)
	grant.apply(actor)
	assert_almost_eq(actor.stats.aptitude(&"might"), 0.0, "a stale store is replaced, never merged")
	assert_eq(actor.stats.aptitude(&"focus") > 0.0, true, "and the qi build's posture is there")


func test_breakthrough_is_the_stage_that_resolves_the_build() -> void:
	var actor := _actor_with(PathState.BODY, RealmDefaults.ladder().realms()[0].id)
	assert_almost_eq(actor.stats.aptitude(&"might"), 0.0, "nothing resolved before the advance")
	assert_eq(Breakthrough.try_advance(actor, PathState.BODY), true, "the advance succeeds")
	assert_eq(actor.stats.aptitude(&"might") > 0.0, true, "and the build resolved into aptitudes")
