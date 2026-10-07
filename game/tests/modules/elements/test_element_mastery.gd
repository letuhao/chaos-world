extends TestCase

## ADR 0004/0005/0006: elemental mastery advances on the shared ladder, gates tiers,
## and carries its own 30-stage display vocabulary.


func test_path_def() -> void:
	var def := ElementMastery.path_def()
	assert_eq(def.id, ElementMastery.PATH_ID, "path id")
	assert_eq(def.has_rank(&"qi_refining"), true, "uses shared ladder")


func test_tier_gating_from_realm_tier() -> void:
	assert_eq(ElementMastery.max_tier(&"qi_refining"), 1, "mortal gates tier 1")
	assert_eq(ElementMastery.max_tier(&"spirit_sea"), 2, "spirit gates tier 2")
	assert_eq(ElementMastery.max_tier(&"earth_immortal"), 3, "immortal gates tier 3")
	assert_eq(ElementMastery.max_tier(&"dao_ancestor"), 3, "transcendent capped at tier 3")
	assert_eq(ElementMastery.max_tier(&"unknown"), 1, "unknown defaults to tier 1")


func test_stage_vocabulary_aligns_to_ladder() -> void:
	var def := ElementMastery.path_def()
	assert_eq(def.stage_names.size(), 30, "30 stage names")
	assert_eq(def.stage_name(&"qi_refining"), "Spark", "first stage")
	assert_eq(def.stage_name(&"tribulation"), "Convergence", "last mortal stage")
	assert_eq(def.stage_name(&"spirit_sea"), "Rising Tide", "spirit stage")
	assert_eq(def.stage_name(&"dao_ancestor"), "Elemental Dao Ancestor", "transcendent stage")


func test_element_tier_gating() -> void:
	var rules := ElementsApi.default_rules()
	assert_eq(
		ElementMastery.can_use(rules, &"qi_refining", ElementStats.FIRE), true, "tier 1 at mortal"
	)
	assert_eq(
		ElementMastery.can_use(rules, &"qi_refining", ElementStats.LIGHTNING),
		false,
		"tier 2 blocked"
	)
	assert_eq(
		ElementMastery.can_use(rules, &"spirit_sea", ElementStats.LIGHTNING),
		true,
		"tier 2 at spirit"
	)
	# Tier 3 (ADR 0921) opens at the IMMORTAL tier of the realm ladder and nowhere below.
	assert_eq(
		ElementMastery.can_use(rules, &"spirit_sea", ElementStats.VOID),
		false,
		"tier 3 blocked at spirit"
	)
	assert_eq(
		ElementMastery.can_use(rules, &"earth_immortal", ElementStats.VOID),
		true,
		"tier 3 at immortal"
	)
	assert_eq(
		ElementMastery.can_use(rules, &"dao_ancestor", ElementStats.TIME),
		true,
		"and the cap holds at transcendent"
	)
	assert_eq(
		ElementMastery.can_use(rules, &"spirit_sea", &"no_such_element"), false, "unknown element"
	)


# --- the path's doors (S2) ------------------------------------------------------


func _actor(id: StringName) -> Actor:
	return ActorFactory.build(id, {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})


func _qi_threshold(realm_id: StringName) -> float:
	return QiRealmSeed.for_realm(realm_id).progress_required


func test_awaken_enrolls_the_path_explicitly_and_only_once() -> void:
	var actor := _actor(&"element_path")
	assert_eq(ElementMastery.enrolled(actor), false, "nothing enrolls implicitly")
	var begun := ElementsApi.begin(actor)
	assert_eq(bool(begun.get("ok", false)), true, "the Awaken action enrolls")
	assert_eq(String(begun.get("rank", "")), "qi_refining", "at the first rung")
	assert_eq(ElementMastery.enrolled(actor), true, "and the path is open")
	assert_eq(
		String(ElementsApi.begin(actor).get("reason", "")), "already_enrolled", "and only once"
	)


func test_advance_is_paid_in_mastery_against_the_injected_curve() -> void:
	var actor := _actor(&"element_advance")
	assert_eq(bool(ElementsApi.begin(actor).get("ok", false)), true, "enrolled")
	var target := RealmDefaults.ladder().next(&"qi_refining")
	assert_almost_eq(
		ElementMastery.threshold_for(target.id),
		_qi_threshold(target.id),
		"the injected curve is the qi ladder's own authored labour",
		1e-6
	)
	var preview := ElementsApi.preview(actor)
	assert_almost_eq(
		float(preview.get("threshold", -1.0)), _qi_threshold(target.id), "the read carries it", 1e-6
	)
	assert_eq(
		String(ElementsApi.advance(actor).get("reason", "")),
		"insufficient_mastery",
		"no mastery, no rung"
	)
	actor.set_affinity(ElementStats.FIRE, 5.0)
	var guard := 0
	while ElementMastery.total_mastery(actor) < _qi_threshold(target.id) and guard < 400:
		guard += 1
		assert_eq(ElementsApi.practise(actor, ElementStats.FIRE), true, "a sitting")
	var advanced := ElementsApi.advance(actor)
	assert_eq(bool(advanced.get("ok", false)), true, "the rung is paid")
	assert_eq(String(advanced.get("rank", "")), String(target.id), "and the rank moved")
	assert_eq(
		float(ElementsApi.preview(actor).get("mastery", 0.0)) >= _qi_threshold(target.id),
		true,
		"with the mastery that paid it still on the books"
	)


func test_can_use_needs_both_the_elemental_rank_and_the_qi_realm() -> void:
	var actor := _actor(&"element_use")
	assert_eq(ElementsApi.can_use(actor, ElementStats.FIRE), true, "tier 1 is the base spark")
	assert_eq(ElementsApi.can_use(actor, ElementStats.LIGHTNING), false, "tier 2 needs awakening")
	assert_eq(bool(ElementsApi.begin(actor).get("ok", false)), true, "awakened")
	# The RANK half: an elemental rank at R1 gates tier 2 even with the qi realm high.
	actor.set_path(PathState.new(PathState.QI, &"spirit_sea"))
	assert_eq(ElementsApi.can_use(actor, ElementStats.LIGHTNING), false, "the rank still gates")
	# The REALM half: an elemental rank at spirit is not enough while qi sits at R1.
	actor.set_path(PathState.new(ElementMastery.PATH_ID, &"spirit_sea"))
	actor.set_path(PathState.new(PathState.QI, &"qi_refining"))
	assert_eq(ElementsApi.can_use(actor, ElementStats.LIGHTNING), false, "the qi realm still gates")
	actor.set_path(PathState.new(PathState.QI, &"spirit_sea"))
	assert_eq(
		ElementsApi.can_use(actor, ElementStats.LIGHTNING), true, "both halves met, tier 2 opens"
	)


func test_locked_names_the_refusal_for_an_unreachable_element() -> void:
	var actor := _actor(&"element_locked")
	assert_eq(ElementsApi.locked(actor, ElementStats.FIRE), &"", "tier 1 is usable")
	assert_eq(
		ElementsApi.locked(actor, ElementStats.LIGHTNING),
		&"element_locked",
		"tier 2 names the refusal"
	)
	assert_eq(ElementsApi.locked(actor, &""), &"", "unelemental needs no gate")
	assert_eq(bool(ElementsApi.begin(actor).get("ok", false)), true, "awakened")
	actor.set_path(PathState.new(ElementMastery.PATH_ID, &"spirit_sea"))
	actor.set_path(PathState.new(PathState.QI, &"spirit_sea"))
	assert_eq(ElementsApi.locked(actor, ElementStats.LIGHTNING), &"", "both halves met")
