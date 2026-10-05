extends TestCase

## The UI-facing read. `summary` is the one call a lineage screen makes, so what
## matters is that it is primitive-only, survives a null actor, and never leaks a
## `StringName`, `Resource` or `Actor` into a payload a panel has to render.

const COMMON := &"t_common"
const RARE := &"t_rare"

var _actor: Actor


func setup() -> void:
	BloodlineFixtureCatalog.install(
		[BloodlineFixtureCatalog.common(COMMON), BloodlineFixtureCatalog.rare(RARE)]
	)
	_actor = Actor.new(&"screen", {Stat.PHYSIQUE: 10.0})
	BloodlineApi.attach(_actor)


func teardown() -> void:
	BloodlineFixtureCatalog.teardown()


func test_a_null_actor_yields_a_complete_empty_screen_rather_than_a_crash() -> void:
	var view := BloodlineApi.summary(null)
	assert_eq(bool(view["has_actor"]), false, "and it says so")
	assert_eq(String(view["actor_id"]), "", "with no actor id")
	assert_eq(view["lineages"] as Dictionary, {}, "no carried lineage")
	assert_eq(view["awakened"] as Array, [], "none awake")
	assert_almost_eq(float(view["peak_purity"]), 0.0, "and no concentration")
	# The authored block is author-facing rather than actor-facing, so it is populated
	# even with no actor: an empty screen should still show what there is to inherit.
	assert_eq(
		(view["bloodlines"] as Dictionary).keys().size(), 2, "and the content is still offered"
	)
	assert_eq(
		bool((view["bloodlines"][COMMON] as Dictionary)["held"]),
		false,
		"with nothing held, because there is no actor to hold it"
	)


func test_the_carried_block_reports_each_lineage_concentration_tier_and_awake_state() -> void:
	BloodlineApi.set_purity(_actor, COMMON, 0.9)
	BloodlineApi.set_purity(_actor, RARE, 0.2)
	var view := BloodlineApi.summary(_actor)
	assert_eq(bool(view["has_actor"]), true, "there is an actor")
	assert_eq(String(view["actor_id"]), "screen", "named")
	assert_eq(int(view["lineage_count"]), 2, "two carried")
	assert_eq(int(view["awakened_count"]), 1, "one awake")
	assert_eq(view["awakened"] as Array, [String(COMMON)], "listed canonically")
	assert_almost_eq(float(view["peak_purity"]), 0.9, "the strongest")
	assert_almost_eq(float(view["mean_purity"]), 0.55, "the mean")
	# The headline tier is the PEAK's, and 0.9 is above the founding bar whatever the
	# lineage it was earned on. A screen that showed "common" here would under-read the
	# ancestry it is displaying.
	assert_eq(String(view["tier"]), "founding", "and the peak's tier")
	var carried := view["lineages"] as Dictionary
	assert_eq(
		String((carried[COMMON] as Dictionary)["tier"]),
		"founding",
		"the carried entry agrees with the headline"
	)
	assert_eq(String((carried[RARE] as Dictionary)["tier"]), "dormant", "and a dormant one")
	assert_eq(bool((carried[COMMON] as Dictionary)["awake"]), true, "the awake flag")
	assert_eq(bool((carried[RARE] as Dictionary)["known"]), true, "and the content flag")


func test_every_authored_lineage_is_listed_whatever_the_actor_carries() -> void:
	# One call answers the whole screen, so a panel never needs a second catalog read
	# and the `ui/` edge has nothing left to want.
	var before := BloodlineApi.summary(_actor)["bloodlines"] as Dictionary
	assert_eq(before.keys().size(), 2, "both authored lineages are offered")
	assert_eq(bool((before[RARE] as Dictionary)["held"]), false, "and `held` says what is carried")
	assert_ne(String((before[RARE] as Dictionary)["description"]), "", "with a description")
	BloodlineApi.set_purity(_actor, RARE, 0.6)
	var after := BloodlineApi.summary(_actor)["bloodlines"] as Dictionary
	assert_eq(bool((after[RARE] as Dictionary)["held"]), true, "and it flips once carried")
	assert_eq(bool((after[COMMON] as Dictionary)["held"]), false, "while the other stays put")


func test_the_power_aggregate_is_bounded_and_weighted_by_tier() -> void:
	BloodlineApi.set_purity(_actor, COMMON, 0.9)
	BloodlineApi.set_purity(_actor, RARE, 0.9)
	var view := BloodlineApi.summary(_actor)
	# The fixture grants 0.1 (common) and 0.05 (rare), tier-weighted 0.3 and 0.6, so
	# the aggregate is 0.06 — bounded, legible, and nowhere near the backstop.
	assert_almost_eq(float(view["bloodline_power"]), 0.06, "the weighted aggregate")
	assert_eq(
		float(view["bloodline_power"]) <= BloodlineProvider.MAX_BLOODLINE_POWER,
		true,
		"and it never exceeds the provider's backstop"
	)


func test_every_value_in_the_view_is_a_primitive() -> void:
	# A panel binds to this dictionary. A `StringName`, a `Resource` or an `Array` entry
	# holding one would be a rendering bug the type system would not catch.
	BloodlineApi.set_purity(_actor, COMMON, 0.9)
	assert_eq(_primitives_only(BloodlineApi.summary(_actor)), true, "the whole payload")
	assert_eq(_primitives_only(BloodlineApi.summary(null)), true, "and the empty one")


func _primitives_only(value) -> bool:
	if value is String or value is StringName or value is float or value is int or value is bool:
		return true
	if value is Array:
		for entry in value as Array:
			if not _primitives_only(entry):
				return false
		return true
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			if not (key is String) or not _primitives_only((value as Dictionary)[key]):
				return false
		return true
	return false


func test_the_tier_reader_agrees_with_the_gate_everywhere_along_the_ladder() -> void:
	assert_eq(BloodlineApi.rank_tier(0.0), &"dormant", "nothing at all is dormant")
	assert_eq(BloodlineApi.rank_tier(0.41), &"dormant", "just under common")
	assert_eq(BloodlineApi.rank_tier(BloodlineApi.TIER_COMMON), &"common", "exactly common")
	assert_eq(BloodlineApi.rank_tier(BloodlineApi.TIER_RARE), &"rare", "exactly rare")
	assert_eq(BloodlineApi.rank_tier(BloodlineApi.TIER_FOUNDING), &"founding", "exactly founding")
	assert_eq(BloodlineApi.rank_tier(1.0), &"founding", "and pure")
	# The ladder the screen reads and the gate that gates must never disagree about a
	# boundary, or a player is shown "dormant" while the gate says awake. The tiers are
	# a READ of the concentration; only the lowest bar decides the gate, so the test is
	# that the lowest bar is exactly where `rank_tier` stops saying "dormant".
	for value in [0.0, 0.41, 0.42, 0.55, 0.72, 1.0]:
		BloodlineApi.set_purity(_actor, COMMON, value)
		assert_eq(
			BloodlineApi.rank_tier(value) != &"dormant",
			BloodlineApi.is_awake(_actor, COMMON),
			"the common bar and the awake gate agree at %.2f" % value
		)
