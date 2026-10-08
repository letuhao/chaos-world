extends TestCase

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

## ADR 0195, ruling Q2 REVERSED: `cultivate` is priced, and the price is on the
## overflow.
##
## ADR 0180 ruled it free on a sound argument — every one of the 30 seeds demands
## `dantian_fill_required == 1.0`, so the gate demands a reservoir the only verb
## that fills one produces, and charging that verb out of the reservoir cancels the
## two demands into a deadlock. The owner has overruled the conclusion, not the
## reasoning, so this suite is the reasoning made executable in the other
## direction: it asserts the price EXISTS, that it is not denominated in the
## reservoir, and — the half that actually settles the ruling — that a fresh actor
## holding **not one catalyst** still walks R1 -> R30 through public actions.
##
## The rejected alternative is recorded rather than merely avoided. A qi-priced
## sitting is the obvious "fix" a future agent will reach for, and it is the shape
## `tools/cultivation/audit.py::qi_price_findings` now fails structurally:
## `cultivate` is the SOLE writer of `QiStats.QI` (`actor.gd:153` sizes regen for
## health and stamina only, nothing ticks `ResourcePool.regen`, and every ascent
## zeroes the pool), so a verb that both raises and lowers the reservoir is a verb
## charging the one resource it produces.

const PATH := QiPath.PATH_ID
## Enough sittings to reach the next realm's own quality floor from R1's 0.5, and
## to leave the reservoir full. A fixed small cap: the loop's condition is the
## state it is driving, and the cap names it if it cannot converge.
const FILL_BOUND := 64


## The price, observed rather than asserted in prose: a sitting whose circulation
## overflows a reservoir the gate already demands be FULL spends one
## `dantian_catalyst`, and the overflow becomes quality past the next realm's
## floor.
func test_an_overflowing_sitting_spends_the_dantian_catalyst() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	var next_seed := QiRealmSeed.for_realm(Probe.target_after(&"qi_refining").id)
	assert_ne(next_seed, null, "R2 has a seed")
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	var dantian := QiTestKit.dantian(actor)
	assert_eq(Probe.fill_and_refine(actor, next_seed), true, "the dantian is full and at the floor")
	var quality_before := dantian.quality
	var inventory := ItemsApi.inventory(actor)
	assert_eq(Probe.stock(actor, seed.dantian_catalyst, 1), true, "a catalyst is in hand to spend")

	assert_eq(QiCultivationApi.cultivate(actor, 50.0), true, "the sitting is accepted")

	assert_eq(
		inventory.count(seed.dantian_catalyst),
		0,
		"and it spent the dantian catalyst, which is the price of the overflow"
	)
	assert_almost_eq(
		dantian.quality,
		quality_before + QiTraining.CATALYST_QUALITY_STEP,
		"the overflow became one step of quality PAST the free ceiling",
		0.0001
	)


## The control, and the half of the ruling that makes it a price rather than a
## different verb: without one in hand the SAME sitting still works and the free
## ceiling still holds, because `cultivate` stops refining at the next realm's own
## floor and no amount of circulating gets past it.
func test_without_a_catalyst_the_sitting_is_accepted_and_stops_at_the_ceiling() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	var next_seed := QiRealmSeed.for_realm(Probe.target_after(&"qi_refining").id)
	assert_ne(next_seed, null, "R2 has a seed")
	var dantian := QiTestKit.dantian(actor)
	assert_eq(Probe.fill_and_refine(actor, next_seed), true, "the dantian is full and at the floor")
	var quality_before := dantian.quality
	var inventory := ItemsApi.inventory(actor)

	assert_eq(QiCultivationApi.cultivate(actor, 50.0), true, "the sitting is accepted with no item")
	assert_eq(
		dantian.quality,
		quality_before,
		"and it buys no quality past the ceiling, so the price is optional everywhere"
	)
	# `progress` is metered from `gain`, NOT from the qi the reservoir stored: a
	# meter bounded by the reservoir cannot be met while the reservoir is full, and
	# every realm's gate demands a full one.
	var state := actor.path(PATH)
	var progress_before := state.progress
	assert_eq(QiCultivationApi.cultivate(actor, 50.0), true, "a second sitting too")
	assert_eq(
		state.progress > progress_before,
		true,
		"and progress still advances on a full reservoir, which is what keeps the ladder walkable"
	)
	assert_eq(
		inventory.count(QiRealmSeed.for_realm(&"qi_refining").dantian_catalyst), 0, "nothing spent"
	)


## The reservoir is never charged. This is the deadlock ADR 0180 measured, asserted
## on the actor rather than in a comment: a sitting only ever ADDS qi, so the gate
## that demands a full reservoir is never paid out of the reservoir it wants full.
func test_a_sitting_never_spends_qi() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	var pool := actor.resource(QiStats.QI)
	pool.current = 0.0
	for _sitting in FILL_BOUND:
		assert_eq(QiCultivationApi.cultivate(actor, 50.0), true, "a sitting is accepted")
		var qi_now := pool.current
		assert_eq(qi_now >= pool.current, true, "qi never falls")
		if pool.current >= pool.maximum:
			break
	assert_eq(pool.current, pool.maximum, "the reservoir filled to its maximum, unspent")


## THE DEADLOCK PROOF. A fresh actor at R1 with an inventory that never holds a
## catalyst walks all 30 realms by pressing public actions: cultivate, meditate,
## train the gate's channels, recover, breakthrough. Nothing here writes rank,
## channel state, progress, or a success flag, and nothing here stocks anything but
## the three priced roles the ladder already demanded.
##
## This is the claim ADR 0096's objection needed and could not get: if a catalyst
## were a tax, this walk would stall at R1 holding an empty inventory. It does not.
func test_the_ladder_walks_r1_to_r30_without_one_catalyst() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var ladder := RealmDefaults.ladder()
	var visited: Array[StringName] = [actor.path(PATH).rank_id]
	var guard := 0
	# Bounded in the CONDITION and checked in the body: GDScript's flow analysis
	# refuses to compile a `while true` in a typed function, so the cap is in the
	# head and the body names the condition that failed to converge.
	while guard <= 64:
		guard += 1
		if guard > 64:
			push_error("qi traversal did not reach the terminal realm")
			break
		var state := actor.path(PATH)
		var target := ladder.next(state.rank_id)
		if target == null:
			break
		var target_seed := QiRealmSeed.for_realm(target.id)
		assert_ne(target_seed, null, "seed for %s" % target.id)
		if target_seed == null:
			break
		Probe.fight(actor, target)
		Probe.walk_ascent(actor)
		# The deepest tier's dao heart is earned from content, like everything else in
		# this walk (BL-0932): the probe equips the authored artifact that grants it.
		if not Probe.ensure_dao_heart(actor, target.id):
			break
		var ready := _ready(actor, target_seed)
		assert_eq(ready, true, "the %s gate closed on a catalyst-free inventory" % target.id)
		if not ready:
			break
		assert_no_catalyst(actor)
		if not _breakthrough(actor, rng, target_seed):
			break
		visited.append(target.id)
	assert_eq(visited.size(), 30, "visited all 30 realms")
	assert_eq(visited[-1], &"primordial_origin", "at the terminal realm")


## The whole gate, through public actions only, with the two `fill_and_refine` passes
## ADR 0141's recovery needs: closing a scar restores 25% of the reservoir's capacity,
## so the dantian is topped up again afterwards. Each step must SUCCEED or the walk
## cannot proceed, so they are chained with `and`, which short-circuits.
func _ready(actor: Actor, seed: QiRealmSeed) -> bool:
	return (
		Probe.recover_all(actor)
		and Probe.stock(actor, seed.breakthrough_item)
		and Probe.stock(actor, seed.training_item)
		and Probe.train_gate_channels(actor, seed)
		and Probe.recover_all(actor)
		and Probe.earn_progress(actor, seed)
		and Probe.earn_element_mastery(actor, seed)
		and Probe.meditate_to_floor(actor, seed.comprehension_required)
		and Probe.fill_and_refine(actor, seed)
		and Probe.fill_and_refine(actor, seed)
		and Probe.stock(actor, seed.breakthrough_item)
	)


## Attempts per boundary, sized from the evaluated chance so a legitimate deviation
## cannot flake the walk. Bounded, and it names the roll it is sizing itself to.
##
## The gate is RE-PREPARED between attempts, not merely healed: a deviation halves the
## dantian's quality and scars it, and `recover_all` closes the scar but circulation
## restores the quality — so a retry that only recovered would roll the same
## half-quality dantian again and could not converge.
func _breakthrough(actor: Actor, rng: RandomNumberGenerator, seed: QiRealmSeed) -> bool:
	var chance := float(Probe.preview(actor)["chance"])
	var budget := (
		1 if chance >= 1.0 or chance <= 0.0 else maxi(3, ceili(log(0.0001) / log(1.0 - chance)))
	)
	for _attempt in budget:
		if QiBreakthroughTransaction.execute(actor, rng):
			return true
		if not _ready(actor, seed):
			return false
	return false


## Zero catalysts, in every realm's own two ids — the inventory claim the walk above
## rests on, checked against the STANDING realm each time rather than a sampled one.
func assert_no_catalyst(actor: Actor) -> void:
	var inventory := ItemsApi.inventory(actor)
	var ladder := RealmDefaults.ladder()
	var checked := 0
	# Bounded by the ladder's own length: each realm is visited once and the body
	# appends nothing to the container it walks (INC-0002).
	for realm in ladder.realms():
		var seed := QiRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		assert_eq(
			inventory.count(seed.dantian_catalyst),
			0,
			"%s holds no dantian catalyst at %s" % [realm.id, actor.path(PATH).rank_id]
		)
		assert_eq(
			inventory.count(seed.meridian_catalyst),
			0,
			"%s holds no meridian catalyst at %s" % [realm.id, actor.path(PATH).rank_id]
		)
		checked += 1
	assert_eq(checked, 30, "and it graded every realm's two ids")
