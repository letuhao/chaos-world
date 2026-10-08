extends TestCase

## ADR 0214 + ADR 0926: the gain-side multiplier is TWO bounded factors — the place's
## density and the actor's own rate stat — and neither compounds with the realm rate.
##
## ADR 0214 shipped the place half (`CultivationGain`'s density reads and the zone's
## `qi_density` field) but the wiring was never landed: `scale_gain` had zero callers and
## no zone authored a density (DEF-0117). ADR 0926 landed the actor half: `Stat.
## CULTIVATION_RATE` was derived and granted by dozens of authored options and read by NO
## cultivation gain (BL-0931). The three paths now call `scale_gain` once, and this suite
## pins the mechanism they call.

const RATE := Stat.CULTIVATION_RATE


## A hero on the qi path with a known aptitude, so the derived rate is exact:
## `1.0 + aptitude * 0.02` (`actor_stats.gd`).
func _hero(aptitude: float = 10.0, rank_id: StringName = &"qi_refining") -> Actor:
	var actor := ActorFactory.build(&"rate_probe", {Stat.APTITUDE: aptitude})
	actor.attach_core_resources()
	ActorFactory.with_qi_cultivation(actor, rank_id)
	return actor


## The place band is closed and CLAMPED on the way in: a `.tres` authoring `3.0` gets the
## ceiling rather than deleting a reward, and a junk value gets the neutral.
func test_the_density_band_is_closed_and_clamps() -> void:
	assert_almost_eq(CultivationGain.clamp_density(1.1), 1.1, "in band passes")
	assert_almost_eq(
		CultivationGain.clamp_density(3.0), CultivationGain.QI_DENSITY_MAX, "3.0 -> ceiling"
	)
	assert_almost_eq(
		CultivationGain.clamp_density(0.1), CultivationGain.QI_DENSITY_MIN, "0.1 -> floor"
	)
	assert_almost_eq(CultivationGain.clamp_density(NAN), CultivationGain.NEUTRAL, "NaN -> neutral")
	assert_almost_eq(CultivationGain.clamp_density(INF), CultivationGain.NEUTRAL, "INF -> neutral")


func test_publishing_round_trips_and_clears() -> void:
	var actor := _hero()
	assert_almost_eq(
		CultivationGain.density_of(actor), CultivationGain.NEUTRAL, "unpublished reads neutral"
	)
	assert_almost_eq(
		CultivationGain.publish_density(actor, 1.2), 1.2, "publish answers what it applied"
	)
	assert_almost_eq(CultivationGain.density_of(actor), 1.2, "and reads back")
	CultivationGain.publish_density(actor, CultivationGain.NEUTRAL)
	assert_almost_eq(CultivationGain.density_of(actor), CultivationGain.NEUTRAL, "cleared")


## A body carrying the OLD bare-float shape answers NEUTRAL rather than raising: a carry
## that trips over one stale key must not cost a player their run. Written directly
## because `set_module_data` is typed `(id, data: Dictionary)` and cannot re-create it.
func test_a_stale_slot_shape_reads_neutral_rather_than_raising() -> void:
	var actor := _hero()
	actor.module_data[CultivationGain.DENSITY_KEY] = 1.2
	assert_almost_eq(
		CultivationGain.density_of(actor), CultivationGain.NEUTRAL, "a bare float is the old shape"
	)
	actor.set_module_data(CultivationGain.DENSITY_KEY, {"density": "rich"})
	assert_almost_eq(CultivationGain.density_of(actor), CultivationGain.NEUTRAL, "and a junk value")


func test_the_rate_reads_the_derived_stat() -> void:
	assert_almost_eq(CultivationGain.rate_of(_hero(10.0)), 1.2, "1.0 + 10 * 0.02", 0.0001)


## The mechanism every authored `core_cultivation_rate` grant uses — item options,
## bloodlines, sets, fates, consumables all land as PERCENT modifiers on the stat.
func test_item_style_percent_grants_move_the_rate() -> void:
	var actor := _hero(10.0)
	actor.stats.add_modifier(StatModifier.new(RATE, Stat.Op.PERCENT, 0.04, &"gear"))
	assert_almost_eq(CultivationGain.rate_of(actor), 1.2 * 1.04, "a 4% grant is live", 0.0001)


func test_a_huge_grant_clamps_at_the_ladder_span() -> void:
	var actor := _hero(10.0)
	actor.stats.add_modifier(StatModifier.new(RATE, Stat.Op.PERCENT, 999.0, &"test"))
	assert_almost_eq(
		CultivationGain.rate_of(actor), CultivationGain.rate_ceiling(), "clamped at the span"
	)


func test_a_negative_grant_floors_rather_than_stalling() -> void:
	var actor := _hero(10.0)
	actor.stats.add_modifier(StatModifier.new(RATE, Stat.Op.PERCENT, -10.0, &"test"))
	assert_almost_eq(CultivationGain.rate_of(actor), CultivationGain.RATE_FLOOR, "floored")
	assert_eq(
		CultivationGain.scale_gain(actor, 100.0) > 0.0, true, "a sitting is still worth something"
	)


## The ceiling is DERIVED from the shared curve rather than typed: a retune of the ladder
## moves it, and a copy of the number would not (ADR 0268's discipline).
func test_the_ceiling_is_the_ladder_span_derived_not_typed() -> void:
	assert_almost_eq(
		CultivationGain.rate_ceiling(), RealmRate.rate_span(), "the ceiling IS the shared span"
	)
	assert_eq(CultivationGain.rate_ceiling() > 1.0, true, "and it is a gain above neutral")


func test_scale_gain_multiplies_the_factors_and_never_sums_them() -> void:
	var actor := _hero(10.0)
	CultivationGain.publish_density(actor, 1.25)
	var scaled := CultivationGain.scale_gain(actor, 100.0)
	assert_almost_eq(scaled, 100.0 * 1.25 * 1.2, "100 x density x rate", 0.0001)
	assert_ne(scaled, 100.0 * (1.0 + 0.25 + 0.2), "never a sum of the factors")


## The multiplier is realm-INDEPENDENT, which is what "it cannot outrun the ladder"
## means: it adds a constant and never compounds with `1.02^ordinal`. The ratio of a deep
## actor's gain to a shallow one's is therefore exactly the ratio of their realm factors.
func test_the_multiplier_is_realm_independent() -> void:
	var low := _hero(10.0, &"qi_refining")
	var high := _hero(10.0, &"primordial_origin")
	CultivationGain.publish_density(low, 1.25)
	CultivationGain.publish_density(high, 1.25)
	assert_almost_eq(
		CultivationGain.scale_gain(low, 100.0),
		CultivationGain.scale_gain(high, 100.0),
		"the same factor at R1 and at the top realm",
		0.0001
	)
	var shallow_gain := (
		100.0 * RealmRate.factor(&"qi_refining") * CultivationGain.scale_gain(low, 1.0)
	)
	var deep_gain := (
		100.0 * RealmRate.factor(&"primordial_origin") * CultivationGain.scale_gain(high, 1.0)
	)
	assert_almost_eq(
		deep_gain / shallow_gain,
		RealmRate.factor(&"primordial_origin") / RealmRate.factor(&"qi_refining"),
		"the multiplier cancels out of the ratio",
		0.0001
	)


func test_a_null_actor_is_neutral() -> void:
	assert_almost_eq(CultivationGain.rate_of(null), CultivationGain.NEUTRAL, "no actor, no factor")
	assert_almost_eq(CultivationGain.density_of(null), CultivationGain.NEUTRAL, "and no place")
	assert_almost_eq(CultivationGain.scale_gain(null, 50.0), 50.0, "so the gain is untouched")


## The wiring, end to end through the REAL verb: one qi sitting in a rich room meters
## `1.25x` the progress of the same sitting in a plain one. `progress` is read rather than
## the stored qi, because the reservoir CLAMPS at capacity and a full one would hide the
## difference — the qi module's own reason `progress` is metered from `gain`.
func test_a_rich_room_pays_more_through_the_real_cultivate_verb() -> void:
	var plain := _hero(10.0)
	var rich := _hero(10.0)
	CultivationGain.publish_density(rich, 1.25)
	assert_eq(QiTraining.cultivate(plain, 25.0), true, "the plain sitting lands")
	assert_eq(QiTraining.cultivate(rich, 25.0), true, "the rich sitting lands")
	var plain_state := plain.path(QiPath.PATH_ID)
	var rich_state := rich.path(QiPath.PATH_ID)
	assert_ne(plain_state, null, "the plain actor carries the qi path")
	if plain_state == null or rich_state == null:
		return
	assert_eq(plain_state.progress > 0.0, true, "the plain sitting metered progress")
	assert_almost_eq(
		rich_state.progress / plain_state.progress,
		1.25,
		"the rich room paid exactly a quarter more",
		0.0001
	)
