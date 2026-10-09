extends TestCase

## BL-0951 / ADR 0939, S16: the sloppy/perfect traversal matrix, all three paths in ONE
## place.
##
## Each path's own suite proves its wall in depth (`test_qi_foundation_wall.gd`,
## `test_body_foundation_wall.gd`, `test_mind_foundation_wall.gd`). This asserts the
## CROSS-PATH claim they share: the SAME rule over the SAME shared record — an actor
## standing at a realm WITHOUT the history a real climb writes (a state only a fixture can
## hold) is REFUSED by name at the wall, and the history a climb writes CLEARS it. Three
## paths, two directions, one record.
##
## The realm is `core_formation`, whose next realm authors a floor on all three paths; the
## floor's presence is asserted rather than assumed, so a retune that zeroes it fails this
## test by name instead of passing it vacuously.
##
## Every loop is a bounded `for`; there is no `while`.

const STANDING := &"core_formation"


## Snapshot every realm BELOW `standing` at perfection 1.0 — the history a flawless climb
## writes, which is what each path's own backfill produces.
func _backfill(actor: Actor, standing: StringName) -> void:
	var ladder := RealmDefaults.ladder()
	var index := maxi(0, ladder.index_of(standing))
	for i in index:
		assert_eq(
			bool(FoundationApi.snapshot(actor, ladder.realms()[i].id, 1.0).get("ok", false)),
			true,
			"backfill %s" % ladder.realms()[i].id
		)


func _qi_wall(actor: Actor) -> bool:
	var preview := QiBreakthroughTransaction.preview(actor)
	return (preview.get("unmet_conditions", []) as Array).has("foundation_insufficient")


func _body_wall(actor: Actor) -> bool:
	var condition := BodyBreakthroughCondition.new()
	return condition.describe_unmet(actor, actor.path(BodyPath.PATH_ID)).has(
		"foundation_insufficient"
	)


func _mind_wall(actor: Actor) -> bool:
	var preview := MindAdvancement.preview(actor)
	return (preview.get("conditions", []) as Array).has("foundation_insufficient")


## The floor the standing realm's next realm authors, asserted to EXIST so the matrix cannot
## pass on a realm nobody gates.
func _assert_floor(target_realm: StringName) -> void:
	var seed := QiRealmSeed.for_realm(target_realm)
	assert_ne(seed, null, "the target realm authors a qi seed")
	if seed != null:
		assert_eq(seed.min_foundation > 0.0, true, "the target authors a floor")


## A qi body at `rank_id` with NO foundation history. `QiProbe.fresh_actor` BACKFILLS (it is
## the climbed fixture the enterability suites use), so the sloppy half is built here.
func _qi_unhistorical(rank_id: StringName) -> Actor:
	var actor := Actor.new(&"wall_hero", {Stat.COMPREHENSION: 0.0, QiStats.DANTIAN_CAPACITY: 100.0})
	actor.set_path(PathState.new(QiPath.PATH_ID, rank_id))
	actor.meridians.unlock_for_realm(rank_id)
	QiCultivationApi.attach(actor)
	ItemsApi.attach(actor, 512)
	QiTraining.synchronize(actor)
	return actor


func test_qi_sloppy_is_refused_and_the_climb_clears_it() -> void:
	var sloppy := _qi_unhistorical(STANDING)
	_assert_floor(RealmDefaults.ladder().next(STANDING).id)
	assert_eq(_qi_wall(sloppy), true, "a qi body with no history is refused at the wall")
	_backfill(sloppy, STANDING)
	assert_eq(_qi_wall(sloppy), false, "and the climb's history clears it")


func test_body_sloppy_is_refused_and_the_climb_clears_it() -> void:
	var sloppy := Actor.new(&"wall_hero", {Stat.PHYSIQUE: 20.0})
	sloppy.set_path(PathState.new(BodyPath.PATH_ID, STANDING))
	BodyCultivationApi.attach(sloppy)
	BodyCultivationApi.attach_acupoints(sloppy)
	ItemsApi.attach(sloppy, 128)
	BodyTraining.synchronize(sloppy)
	assert_eq(_body_wall(sloppy), true, "a body with no history is refused at the wall")
	_backfill(sloppy, STANDING)
	assert_eq(_body_wall(sloppy), false, "and the climb's history clears it")


func test_mind_sloppy_is_refused_and_the_climb_clears_it() -> void:
	var sloppy := Actor.new(
		&"wall_hero", {Stat.COMPREHENSION: 0.0, Stat.WILL: 0.0, MindStats.SEA_CAPACITY: 100.0}
	)
	sloppy.set_path(PathState.new(MindPath.PATH_ID, STANDING))
	sloppy.meridians.unlock_for_realm(STANDING)
	MindCultivationApi.attach(sloppy)
	MindCultivationApi.attach_sea(sloppy)
	ItemsApi.attach(sloppy, 500)
	MindTraining.synchronize(sloppy)
	assert_eq(_mind_wall(sloppy), true, "a mind with no history is refused at the wall")
	_backfill(sloppy, STANDING)
	assert_eq(_mind_wall(sloppy), false, "and the climb's history clears it")
