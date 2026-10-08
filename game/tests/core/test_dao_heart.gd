extends TestCase

## BL-0932's ruling, pinned: the dao heart is a LIVE stat with TWO axes and a CRACK.
##
## - `TribulationEndurance` reads comprehension AND the dao heart as separate terms;
## - the deepest trials gate on the dao heart (`Breakthrough.dao_heart_ok`);
## - a failed breakthrough or a heart-demon wave CRACKS it, and the crack persists.
##
## Before this, `Stat.DAO_HEART` was derived and granted by gear, sets, bloodlines and
## fates and read by NO mechanic, and the endurance's `_dao_heart` helper returned
## comprehension under that name.


func _hero(will: float = 10.0, comprehension: float = 50.0) -> Actor:
	return Actor.new(&"dao_heart_probe", {Stat.WILL: will, Stat.COMPREHENSION: comprehension})


# --- the stat itself ----------------------------------------------------------


func test_the_derived_heart_is_will_until_it_is_cracked() -> void:
	var actor := _hero(10.0)
	assert_almost_eq(actor.stats.derived(Stat.DAO_HEART), 10.0, "whole: will", 0.0001)
	assert_almost_eq(DaoHeart.crack_of(actor), 0.0, "and no scar")
	DaoHeart.crack(actor, 4.0)
	assert_almost_eq(
		actor.stats.derived(Stat.DAO_HEART), 6.0, "cracked: will minus the scar", 0.0001
	)
	assert_almost_eq(DaoHeart.crack_of(actor), -4.0, "the scar is negative", 0.0001)


func test_a_crack_cannot_take_the_heart_below_zero() -> void:
	var actor := _hero(3.0)
	DaoHeart.crack(actor, 100.0)
	assert_almost_eq(DaoHeart.crack_of(actor), -3.0, "the scar stops at will", 0.0001)
	assert_almost_eq(
		actor.stats.derived(Stat.DAO_HEART), 0.0, "and the heart is empty, never negative", 0.0001
	)


func test_rebuilding_restores_a_whole_heart_and_never_grants_one() -> void:
	var actor := _hero(10.0)
	DaoHeart.crack(actor, 6.0)
	assert_almost_eq(DaoHeart.rebuild(actor, 2.0), -4.0, "mended two points")
	assert_almost_eq(DaoHeart.rebuild(actor, 100.0), 0.0, "and never past whole")
	assert_almost_eq(actor.stats.derived(Stat.DAO_HEART), 10.0, "back to will", 0.0001)


## The scar rides `base`, which IS serialized (`ActorStats.to_dict` carries only the
## aptitude cache, and `Actor.to_dict` carries `base`), so a crack cannot heal itself
## on the next load the way a `StatModifier` would.
func test_a_crack_survives_a_save_round_trip() -> void:
	var actor := _hero(10.0)
	DaoHeart.crack(actor, 4.0)
	var restored := Actor.from_dict(actor.to_dict())
	assert_ne(restored, null, "the payload restored")
	if restored == null:
		return
	assert_almost_eq(DaoHeart.crack_of(restored), -4.0, "the scar came back", 0.0001)
	assert_almost_eq(
		restored.stats.derived(Stat.DAO_HEART), 6.0, "and the heart reads cracked", 0.0001
	)


## Grants still add on top of a crack: the derivation is `(will + scar + flat) * ...`,
## so a cracked heart is mendable by content as well as by the recovery elixir.
func test_an_authored_grant_still_composes_with_a_crack() -> void:
	var actor := _hero(10.0)
	DaoHeart.crack(actor, 4.0)
	actor.stats.add_modifier(StatModifier.new(Stat.DAO_HEART, Stat.Op.FLAT, 6.0, &"gear"))
	assert_almost_eq(actor.stats.derived(Stat.DAO_HEART), 12.0, "cracked will + the grant", 0.0001)


# --- the two endurance terms --------------------------------------------------


func test_endurance_reads_comprehension_and_the_heart_separately() -> void:
	var only_comprehension := _hero(0.0, 50.0)
	var record := Tribulation.new(Tribulation.LIGHTNING)
	record.start(only_comprehension, &"earth_immortal")
	var base := TribulationEndurance.endurance(only_comprehension, record)
	assert_eq(base > TribulationEndurance.MIN_ENDURANCE, true, "the fixture sits above the floor")
	only_comprehension.stats.set_base(Stat.COMPREHENSION, 80.0)
	assert_almost_eq(
		TribulationEndurance.endurance(only_comprehension, record) - base,
		30.0 * TribulationEndurance.COMPREHENSION_TO_ENDURANCE,
		"30 more comprehension is 30 points of the comprehension term",
		0.0001
	)
	# ...and the heart is the OTHER term, on its own slope: 30 points of heart move it
	# exactly as far, and neither term is the other under a new name.
	var only_heart := _hero(0.0, 50.0)
	var heart_record := Tribulation.new(Tribulation.LIGHTNING)
	heart_record.start(only_heart, &"earth_immortal")
	var heart_base := TribulationEndurance.endurance(only_heart, heart_record)
	only_heart.stats.set_base(Stat.WILL, 30.0)
	assert_almost_eq(
		TribulationEndurance.endurance(only_heart, heart_record) - heart_base,
		30.0 * TribulationEndurance.DAO_HEART_TO_ENDURANCE,
		"30 more heart is 30 points of the heart term",
		0.0001
	)


# --- the crack's triggers -----------------------------------------------------


func test_a_common_wave_strains_comprehension_and_a_heart_demon_cracks_the_heart() -> void:
	var common := _hero(10.0)
	var common_record := Tribulation.new(Tribulation.LIGHTNING)
	common_record.start(common, &"earth_immortal")
	common_record._charge_toll(common)
	assert_almost_eq(DaoHeart.crack_of(common), 0.0, "a common trial does not touch the heart")
	assert_almost_eq(
		common.stats.get_base(Stat.COMPREHENSION),
		50.0 - Tribulation.WAVE_TOLL,
		"a common wave strains comprehension instead",
		0.0001
	)

	var demon := _hero(10.0)
	var demon_record := Tribulation.new(Tribulation.HEART_DEMON)
	demon_record.start(demon, &"earth_immortal")
	demon_record._charge_toll(demon)
	assert_almost_eq(
		DaoHeart.crack_of(demon), -Tribulation.WAVE_TOLL, "a heart demon spends the heart"
	)
	assert_almost_eq(demon.stats.derived(Stat.DAO_HEART), 9.0, "and the heart reads it", 0.0001)
	assert_almost_eq(
		demon.stats.get_base(Stat.COMPREHENSION), 50.0, "with comprehension untouched", 0.0001
	)


# --- the gate -----------------------------------------------------------------


func test_the_deepest_trials_gate_on_the_dao_heart() -> void:
	var actor := _hero(0.0)
	assert_eq(Breakthrough.dao_heart_ok(actor, 18), true, "the immortal tier asks nothing")
	assert_eq(Breakthrough.dao_heart_ok(actor, 26), true, "not even at its peak")
	assert_eq(Breakthrough.dao_heart_ok(actor, 27), false, "the DEEPEST trial asks for a heart")
	actor.stats.set_base(
		Stat.WILL, float(Breakthrough.DAO_HEART_BY_TIER[RealmDefaults.TRANSCENDENT])
	)
	assert_eq(Breakthrough.dao_heart_ok(actor, 27), true, "and a heart that meets it passes")
	assert_eq(Breakthrough.dao_heart_ok(actor, 29), true, "through the last realm on the ladder")


## The gate is REACHABLE through authored content, at the boundary where the ask
## actually fires: a body standing at R26 (entering the Transcendent tier) wears the two
## uniques the realm-tier guard admits — +20 and +6 against the ask of 24 — while the
## lantern's +40 is refused until the tier it belongs to is reached. Equipment is the
## one path that APPLIES a grant (a consumable's stat targets are reported, never
## applied — `ItemUse`, ADR 0001).
func test_authored_gear_opens_the_deepest_gate_at_its_own_boundary() -> void:
	var actor := ActorFactory.build(&"dao_heart_probe", {Stat.WILL: 0.0})
	actor.attach_core_resources()
	ActorFactory.with_qi_cultivation(actor, &"immortal_sovereign")
	ItemsApi.attach(actor, 8)
	assert_eq(Breakthrough.dao_heart_ok(actor, 27), false, "a will-only body is stopped")
	for def_id in [&"unique_void_coil_coiled_heart", &"unique_ironhide_hearthguard"]:
		var def := Crafting.resolve(def_id)
		assert_ne(def, null, "the authored %s resolves" % def_id)
		if def == null:
			return
		ItemsApi.inventory(actor).add(def, 1)
		assert_eq(
			ItemsApi.equip_item(actor, def.subcategory, def), true, "%s equips at R26" % def_id
		)
	assert_eq(Breakthrough.dao_heart_ok(actor, 27), true, "and the gear opens the deepest gate")


## The player-visible half: the qi preview NAMES the gate, so a refusal is observable
## rather than a silent no (the criterion every gate owes).
func test_the_qi_preview_names_the_heart_when_it_is_short() -> void:
	# Through the factory, not a bare `Actor.new`: a preview needs the dantian the qi
	# enrolment attaches, and a body without one returns before the tier clauses.
	var actor := ActorFactory.build(&"dao_heart_probe", {Stat.WILL: 0.0})
	actor.attach_core_resources()
	ActorFactory.with_qi_cultivation(actor, &"immortal_sovereign")
	var short := QiBreakthroughTransaction.preview(actor)
	assert_eq(
		String(short.get("target_realm", "")),
		"transcendent",
		"the fixture stands one realm below the deepest tier"
	)
	assert_eq(
		(short["unmet_conditions"] as Array).has("dao_heart_too_low"),
		true,
		"the preview names the short heart"
	)
	actor.stats.set_base(
		Stat.WILL, float(Breakthrough.DAO_HEART_BY_TIER[RealmDefaults.TRANSCENDENT])
	)
	var met := QiBreakthroughTransaction.preview(actor)
	assert_eq(
		(met["unmet_conditions"] as Array).has("dao_heart_too_low"),
		false,
		"and stops naming it once the heart meets the tier"
	)
