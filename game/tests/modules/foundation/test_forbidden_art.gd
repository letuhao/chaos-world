extends TestCase

## BL-0951 / ADR 0939, S11: the forbidden lifespan art — burn one year of the actor's own
## life to mend a scarred past realm.
##
## This is the avenue whose price is the one thing that does not come back, so the two
## halves are asserted, not described: the mend lands through the capped `mend`, and the
## actor really ages a year. The band is read FIRST, so a body in the final band is refused
## by name rather than burning the last of an already-spent life — and a refusal costs
## nothing (ADR 0044).
##
## The lifespan is authored flat by the test so the band crossings are deterministic, the
## same shape `test_time_currency.gd` builds its heroes with.

const LIFESPAN_DAYS := 36500.0


func _hero() -> Actor:
	var actor := Actor.new(&"art_hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	actor.stats.add_modifier(
		StatModifier.new(&"race_lifespan", Stat.Op.FLAT, LIFESPAN_DAYS, &"test")
	)
	return actor


func _at_lifespan_share(actor: Actor, share: float) -> void:
	actor.age_years = share * LIFESPAN_DAYS / 365.0


func _seed(actor: Actor, realm_id: StringName, perfection: float) -> void:
	assert_eq(
		bool(FoundationApi.snapshot(actor, realm_id, perfection).get("ok", false)),
		true,
		"seed snapshot %s at %f" % [String(realm_id), perfection]
	)


func test_the_art_burns_a_year_and_mends() -> void:
	var actor := _hero()
	_seed(actor, &"qi_refining", 0.1)
	var before: float = actor.age_years
	var result := FoundationApi.forbidden_art(actor, &"qi_refining")
	assert_eq(bool(result.get("ok", false)), true, "the art resolves: %s" % str(result))
	var mended: Dictionary = result.get("mended", {})
	assert_eq(bool(mended.get("ok", false)), true, "the mend lands")
	assert_almost_eq(
		float(mended.get("after", -1.0)),
		0.1 + FoundationApi.FORBIDDEN_ART_MEND,
		"by exactly the authored step"
	)
	assert_almost_eq(actor.age_years - before, 1.0, "and it burns one year of the actor's life")


## The mend is still bounded by the module's ceiling, not by the avenue.
func test_the_art_stops_at_the_mended_ceiling() -> void:
	var actor := _hero()
	_seed(actor, &"qi_refining", 0.4)
	var result := FoundationApi.forbidden_art(actor, &"qi_refining")
	var mended: Dictionary = result.get("mended", {})
	assert_almost_eq(
		float(mended.get("after", -1.0)), FoundationApi.MEND_CAP, "capped, never past it"
	)


func test_the_art_defaults_to_the_weakest_scar() -> void:
	var actor := _hero()
	_seed(actor, &"qi_refining", 0.4)
	_seed(actor, &"spirit_condensation", 0.2)
	var result := FoundationApi.forbidden_art(actor)
	assert_eq(bool(result.get("ok", false)), true, "the art resolves")
	assert_eq(String(result.get("realm", "")), "spirit_condensation", "on the weakest scar")
	assert_almost_eq(
		FoundationApi.snapshot_for(actor, &"spirit_condensation"),
		0.2 + FoundationApi.FORBIDDEN_ART_MEND,
		"the weakest is lifted"
	)
	assert_almost_eq(
		FoundationApi.snapshot_for(actor, &"qi_refining"), 0.4, "the untouched realm stays put"
	)


## Every refusal is named, and a refusal costs nothing (ADR 0044).
func test_refusals_are_named_and_cost_nothing() -> void:
	var actor := _hero()
	var before: float = actor.age_years
	assert_eq(
		String(FoundationApi.forbidden_art(null, &"qi_refining").get("reason", "")),
		FoundationApi.R_NO_ACTOR,
		"a null actor is named"
	)
	assert_eq(
		String(FoundationApi.forbidden_art(actor, &"qi_refining").get("reason", "")),
		FoundationApi.R_NO_SNAPSHOT,
		"a realm never left has nothing to mend"
	)
	assert_almost_eq(actor.age_years, before, "and a refusal costs no life")


func test_a_realm_at_the_ceiling_is_refused() -> void:
	var actor := _hero()
	_seed(actor, &"qi_refining", 0.6)
	var result := FoundationApi.forbidden_art(actor, &"qi_refining")
	assert_eq(bool(result.get("ok", true)), false, "a realm at the ceiling has nothing to win")
	assert_eq(String(result.get("reason", "")), FoundationApi.R_MEND_CAPPED, "refused by name")


## The band is read FIRST: an actor in the final band has no years to spare, and the art
## refuses by name rather than burning the last of an already-spent life.
func test_the_art_refuses_in_the_final_band() -> void:
	var actor := _hero()
	_seed(actor, &"qi_refining", 0.1)
	_at_lifespan_share(actor, 0.9)
	assert_eq(
		AgeBandTable.band_for_actor(actor),
		AgeBandTable.LASTLIGHT,
		"the fixture is in the last band"
	)
	var before: float = actor.age_years
	var result := FoundationApi.forbidden_art(actor, &"qi_refining")
	assert_eq(bool(result.get("ok", true)), false, "the art refuses in the final band")
	assert_eq(
		String(result.get("reason", "")), FoundationApi.R_FORBIDDEN_NO_YEARS, "refused by name"
	)
	assert_almost_eq(actor.age_years, before, "and it burns nothing")
