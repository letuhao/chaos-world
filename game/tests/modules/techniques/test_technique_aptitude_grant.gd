extends TestCase

## ADR 0883's technique-learn stage, module side: learning re-resolves the actor's
## aptitudes (the majors via core, then `technique_points` across the DOMINANT posture),
## and a breakthrough cannot wipe the technique half because `path_advanced` re-resolves
## the whole build.


func _actor() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(PathState.BODY, RealmDefaults.ladder().realms()[4].id))
	TechniquesApi.attach(actor)
	return actor


func _per_technique(grant: AptitudeGrant) -> float:
	return float(grant.technique_points) / float(Aptitude.PER_POSTURE)


func _per_realm_for(grant: AptitudeGrant, path_id: StringName) -> float:
	for row in grant.rows:
		if StringName(row.get("path", &"")) == path_id:
			return float(row.get("per_realm", 0.0))
	return 0.0


func test_attach_resolves_the_majors_even_before_any_technique() -> void:
	var actor := _actor()
	assert_eq(actor.stats.aptitude(&"might") > 0.0, true, "the body build resolved force")


func test_a_learned_technique_adds_its_share_into_the_dominant_posture() -> void:
	var actor := _actor()
	var before := actor.stats.aptitude(&"might")
	TechniquesApi.codex(actor).learn(&"some_technique")
	TechniquesApi.resolve_aptitudes(actor)
	assert_almost_eq(
		actor.stats.aptitude(&"might"),
		before + _per_technique(AptitudeGrant.shipped()),
		"force took the technique's quarter"
	)


func test_a_breakthrough_cannot_wipe_the_technique_half() -> void:
	var grant := AptitudeGrant.shipped()
	var actor := _actor()
	TechniquesApi.codex(actor).learn(&"some_technique")
	TechniquesApi.codex(actor).learn(&"another_technique")
	TechniquesApi.resolve_aptitudes(actor)
	var before := actor.stats.aptitude(&"might")
	assert_eq(Breakthrough.try_advance(actor, PathState.BODY), true, "the advance succeeds")
	assert_almost_eq(
		actor.stats.aptitude(&"might"),
		before + _per_realm_for(grant, PathState.BODY) / float(Aptitude.PER_POSTURE),
		"the major's next-realm quarter arrived and the technique half survived"
	)
