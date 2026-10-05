extends TestCase

## ADR 0051's rule, applied to qi, which that ADR named as unfixed: the
## breakthrough roll must not read a quantity the entry gate already pins.
##
## `Stat.BREAKTHROUGH_CHANCE` is derived in core as
## `0.1 + comprehension * 0.01 + will * 0.005`, and comprehension IS this path's
## gate (`comprehension_required`, authored to 66). Reading it meant the gate's own
## floor plus dantian quality pushed the sum through the 0.95 clamp from the
## Immortal tier on: every deep attempt was certain, `_deviate` stopped firing, and
## all thirty authored `recovery_item`s became unspendable content.
##
## Every assertion below reads the constants from `QiChance` rather than restating
## 0.05 / 0.95 / 0.5, so retuning the roll does not turn this file into a lie.

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

const PATH := QiPath.PATH_ID


func _dantian_at(quality: float) -> Dantian:
	var dantian := Dantian.new()
	dantian.quality = quality
	return dantian


## The ceiling is unreachable by any dantian quality a legal actor can hold, so no
## boundary on the ladder is a certain success.
func test_the_chance_never_reaches_the_ceiling() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	for quality in [0.0, 0.25, 0.5, 0.75, 1.0]:
		QiAccess.dantian(actor).set_quality(quality)
		var chance := QiChance.of(QiAccess.dantian(actor))
		assert_eq(chance < QiChance.MAX_CHANCE, true, "chance %f at quality %f" % [chance, quality])
		assert_eq(chance >= QiChance.MIN_CHANCE, true, "chance %f is above the floor" % chance)


## The floor is what makes a deviation always possible, so nothing can fall below
## it — including a dantian that has been halved to nothing by one.
func test_the_chance_never_falls_below_the_floor() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	QiAccess.dantian(actor).set_quality(0.0)
	assert_eq(
		QiChance.of(QiAccess.dantian(actor)), QiChance.MIN_CHANCE, "the floor at zero quality"
	)


## The invariant at all 29 boundaries, on a pre-state earned through public actions:
## a cultivator standing ready to attempt a breakthrough can still fail it. This is
## the assertion the old formula fails from the Immortal tier up, where the sum sat
## pinned on the clamp.
func test_no_boundary_on_the_ladder_is_a_guaranteed_success() -> void:
	var checked := 0
	for realm in RealmDefaults.ladder().realms():
		var target := Probe.target_seed_after(realm.id)
		if target == null:
			continue
		var actor := Probe.prepared(realm.id, target)
		var dantian := QiAccess.dantian(actor)
		assert_ne(dantian, null, "dantian at %s" % realm.id)
		if dantian == null:
			continue
		var chance := float(Probe.preview(actor)["chance"])
		assert_eq(
			chance < QiChance.MAX_CHANCE,
			true,
			(
				"attempting %s is rollable (chance %f at quality %f)"
				% [realm.id, chance, dantian.quality]
			)
		)
		assert_eq(chance > 0.0, true, "and not impossible at %s" % realm.id)
		checked += 1
	assert_eq(checked, Probe.BOUNDARY_COUNT, "every boundary on the ladder was checked")


## The rule stated as a test: comprehension is a gate input, not a difficulty dial.
## Raising it far past the floor must not move the roll at all.
func test_the_chance_does_not_move_with_comprehension_past_the_gate() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	var seed := Probe.target_seed_after(&"qi_refining")
	assert_ne(seed, null, "target seed")
	QiAccess.dantian(actor).set_quality(seed.dantian_quality_required)
	var before := QiChance.of(QiAccess.dantian(actor))
	for _step in 200:
		assert_eq(
			QiCultivationApi.meditate(actor, QiCultivationApi.MEDITATE_STEP), true, "meditated"
		)
	assert_eq(
		actor.stats.derived(Stat.COMPREHENSION) > seed.comprehension_required * 4.0,
		true,
		"comprehension is far past the floor"
	)
	assert_eq(QiChance.of(QiAccess.dantian(actor)), before, "and the roll did not move with it")
	assert_eq(
		QiChance.of(QiAccess.dantian(actor)),
		clampf(
			QiChance.MIN_CHANCE + seed.dantian_quality_required * QiChance.QUALITY_TO_CHANCE,
			QiChance.MIN_CHANCE,
			QiChance.MAX_CHANCE
		),
		"the roll is the dantian and nothing else"
	)


## The roll must read `Stat.BREAKTHROUGH_CHANCE` nowhere. It is a core stat every
## other path may read, so this is asserted structurally: give the actor a huge
## comprehension and a huge will, and the chance must not budge.
func test_a_pinned_core_stat_cannot_decide_the_qi_roll() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	QiAccess.dantian(actor).set_quality(0.6)
	var quiet := QiChance.of(QiAccess.dantian(actor))
	actor.stats.set_base(Stat.COMPREHENSION, 400.0)
	actor.stats.set_base(Stat.WILL, 400.0)
	actor.mark_stats_dirty()
	assert_eq(
		actor.stats.derived(Stat.BREAKTHROUGH_CHANCE) >= QiChance.MAX_CHANCE,
		true,
		"the core stat really is saturated here, so this test would catch a read"
	)
	assert_eq(QiChance.of(QiAccess.dantian(actor)), quiet, "the qi roll ignored it")
	assert_eq(QiAdvancement.chance(actor), quiet, "and so did the facade's view of it")


## Cultivating harder buys a sharper dantian rather than a certain breakthrough:
## the roll rises with quality and stops at the next realm's floor, which is where
## circulation stops refining.
func test_circulating_raises_the_chance_and_stops_at_the_next_floors_floor() -> void:
	var realm_id := &"qi_refining"
	var target := Probe.target_seed_after(realm_id)
	assert_ne(target, null, "target seed")
	var actor := Probe.fresh_actor(realm_id)
	var dantian := QiAccess.dantian(actor)
	QiAccess.dantian(actor).set_quality(0.0)
	var low := QiChance.of(dantian)
	var waited := 0
	while waited < Probe.FILL_BOUND and dantian.quality < target.dantian_quality_required:
		waited += 1
		assert_eq(QiCultivationApi.cultivate(actor, 400.0), true, "circulated")
	var high := QiChance.of(dantian)
	assert_eq(high > low, true, "circulating raised the roll (%f -> %f)" % [low, high])
	var guard := 0
	while guard < 64:
		guard += 1
		if not QiCultivationApi.cultivate(actor, 400.0):
			break
	assert_eq(
		dantian.quality <= target.dantian_quality_required + 0.0001,
		true,
		"quality stops at the next realm's floor (%f)" % dantian.quality
	)
	assert_eq(
		QiChance.of(dantian) < QiChance.MAX_CHANCE,
		true,
		"so the roll never becomes certain, however long the player circulates"
	)


## The formula itself, so a future edit to `QiChance` cannot quietly widen it.
func test_the_roll_is_the_named_formula() -> void:
	assert_eq(QiChance.of(null), QiChance.MIN_CHANCE, "no dantian is the floor, never a crash")
	assert_eq(QiChance.of(_dantian_at(0.0)), QiChance.MIN_CHANCE, "zero quality")
	assert_almost_eq(
		QiChance.of(_dantian_at(0.5)),
		QiChance.MIN_CHANCE + 0.5 * QiChance.QUALITY_TO_CHANCE,
		"half quality",
		0.0001
	)
	assert_almost_eq(
		QiChance.of(_dantian_at(1.0)),
		QiChance.MIN_CHANCE + 1.0 * QiChance.QUALITY_TO_CHANCE,
		"full quality is the sum, and the clamp never binds",
		0.0001
	)
	assert_eq(
		QiChance.MIN_CHANCE + QiChance.QUALITY_TO_CHANCE < QiChance.MAX_CHANCE,
		true,
		"which is why no dantian quality can reach the ceiling"
	)
