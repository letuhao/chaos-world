extends TestCase

## BL-0951 / ADR 0939, S15: the foundation read model a readout renders.
##
## Every loop is a bounded `for`; there is no `while`.


func _hero() -> Actor:
	return Actor.new(&"readout_hero", {Stat.PHYSIQUE: 10.0})


func test_the_summary_is_empty_for_a_null_actor() -> void:
	assert_eq(FoundationApi.summary(null), {}, "no actor, no readout")


func test_the_summary_reports_the_carried_foundation_and_the_floor() -> void:
	var actor := _hero()
	FoundationApi.snapshot(actor, &"qi_refining", 0.3)
	FoundationApi.seed_karmic(actor, 0.05)
	var read := FoundationApi.summary(actor)
	assert_almost_eq(float(read.get("foundation", -1.0)), 0.3, "the carried foundation")
	assert_almost_eq(float(read.get("karmic", -1.0)), 0.05, "the karmic floor")
	assert_almost_eq(
		float(read.get("mend_cap", -1.0)), FoundationApi.MEND_CAP, "the mended ceiling"
	)
	assert_eq(int(read.get("count", -1)), 1, "one realm left")
	assert_eq(String(read.get("weakest", "")), "qi_refining", "and the weakest scar is named")
	assert_eq(bool(read.get("lastlight", true)), false, "and the final-band flag reads")


func test_the_rows_render_in_ladder_order() -> void:
	var actor := _hero()
	# Seed OUT of ladder order; the readout must still render in ladder order, so two runs
	# of the same record render identically and a player can compare them.
	FoundationApi.snapshot(actor, &"spirit_condensation", 0.2)
	FoundationApi.snapshot(actor, &"qi_refining", 0.4)
	var rows: Array = FoundationApi.summary(actor).get("snapshots", [])
	assert_eq(rows.size(), 2, "one row per realm left")
	assert_eq(String((rows[0] as Dictionary).get("realm_id", "")), "qi_refining", "lowest first")
	assert_eq(
		String((rows[1] as Dictionary).get("realm_id", "")), "spirit_condensation", "then the next"
	)
	assert_almost_eq(float((rows[0] as Dictionary).get("perfection", -1.0)), 0.4, "with its value")


func test_the_summary_is_json_clean() -> void:
	var actor := _hero()
	FoundationApi.snapshot(actor, &"qi_refining", 0.4)
	var parsed: Variant = JSON.parse_string(JSON.stringify(FoundationApi.summary(actor)))
	assert_eq(parsed is Dictionary, true, "the readout is primitives only")
