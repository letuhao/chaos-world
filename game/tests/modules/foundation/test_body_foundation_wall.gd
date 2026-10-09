extends TestCase

## BL-0951 / ADR 0939: the foundation wall on the body path.
##
## ## What this test proves, and the finding it records
##
## The WALL'S MECHANISM is proven synthetically: an actor that arrived at a realm without
## the history a real climb snapshots (a state only a fixture can hold) is REFUSED by name
## and the refusal costs nothing.
##
## The body's authored floors cannot bite a real run on the shipped content, and that is
## measured rather than assumed: `BodyTraining.strengthen` trains the acupoint toward the
## realm's `quality_target` unconditionally, so the quality axis saturates under MINIMAL
## legal play — a walk that stops every channel at the gate still departs at perfection
## 1.000 on every realm (the diagnostic that established this lived in this file's
## history; BL-0951's tracker records the finding). Making the body's floors bite needs a
## content/rules ruling (the verb's point ceiling, or an authored breadth dial), and until
## that ruling the floors stay authored and INERT rather than fake.

const Play := preload("res://tests/modules/body_cultivation/body_play_fixture.gd")


## An actor at `at_realm` with NO foundation history — the state a fixture can hold and a
## player cannot, which is exactly what a synthetic wall test needs.
func _unhistorical(at_realm: StringName) -> Actor:
	var actor := Actor.new(&"wall_hero", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, at_realm))
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor, 128)
	BodyTraining.synchronize(actor)
	return actor


func _wall_reported(actor: Actor) -> bool:
	var condition := BodyBreakthroughCondition.new()
	return condition.describe_unmet(actor, actor.path(BodyPath.PATH_ID)).has(
		"foundation_insufficient"
	)


func test_an_actor_without_history_is_refused_by_name_and_the_refusal_costs_nothing() -> void:
	var actor := _unhistorical(&"spirit_transformation")
	var target := RealmDefaults.ladder().next(actor.path(BodyPath.PATH_ID).rank_id)
	assert_ne(target, null, "there is a realm above the standing one")
	var seed := BodyRealmSeed.for_realm(target.id)
	assert_eq(seed.min_foundation > 0.0, true, "the target authors a floor")
	assert_eq(_wall_reported(actor), true, "the wall is reported by name")
	var play := Play.new()
	play.stock(actor, seed.breakthrough_item)
	var pills_before := ItemsApi.inventory(actor).count(seed.breakthrough_item)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20_260_301
	assert_eq(BodyAdvancement.try_breakthrough(actor, rng), false, "the transaction refuses")
	assert_eq(
		actor.path(BodyPath.PATH_ID).rank_id,
		&"spirit_transformation",
		"and the realm does not move"
	)
	assert_eq(
		ItemsApi.inventory(actor).count(seed.breakthrough_item),
		pills_before,
		"and no pill is spent"
	)


## The counterpart: the history a real climb writes clears the same wall — the fixture's
## backfill is the state a played actor holds, and the floor reads it as earned.
func test_the_implied_history_clears_the_wall() -> void:
	var play := Play.new()
	var actor: Actor = play.actor(&"spirit_transformation")
	assert_eq(_wall_reported(actor), false, "a climbed body clears the authored floor")
