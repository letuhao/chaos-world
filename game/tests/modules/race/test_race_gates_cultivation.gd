extends TestCase

## ADR 0109: a body plan gates the breakthrough it forbids.
##
## ADR 0078 recorded that race gated nothing. These prove it now does, from the consumer side —
## through the real cultivation facades, not by calling `RaceGate` directly, because a gate that
## only its own module calls is theatre.

const STONE := &"stoneborn"  # closes mind_cultivation, realm_ceiling 17
const TIDE := &"tidecaller"  # closes body_cultivation


## These assertions are about the SHIPPED content tree, so the catalog singleton has to be
## the shipped one. Sibling suites install a fixture catalog with `t_`-prefixed ids that does
## not contain `stoneborn`, and the runner calls `teardown` after each test but a suite that
## installs without undoing it would leave that fixture live for this one.
func teardown() -> void:
	RaceFixtureCatalog.teardown()


func _actor(race_id: StringName, rank_id: StringName = &"qi_refining") -> Actor:
	var actor := Actor.new(&"body", {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 50.0})
	actor.set_path(PathState.new(PathState.QI, rank_id))
	actor.set_path(PathState.new(PathState.BODY, rank_id))
	actor.set_path(PathState.new(PathState.MIND, rank_id))
	RaceApi.attach(actor)
	RaceApi.set_race(actor, race_id)
	QiCultivationApi.attach(actor)
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	# Re-assert the race LAST. A body plan is a projected ledger, and anything that re-attaches
	# afterwards can reset it — so the actor's body is settled last, then the gate is read.
	RaceApi.set_race(actor, race_id)
	return actor


## The gate the refusal is built from: the path the body closes.
func _path_unmet(actor: Actor, path_id: StringName) -> Array[Dictionary]:
	return RaceGate.path_unmet(actor, path_id)


# --- The gate refuses, and says why -------------------------------------------


func test_a_race_closing_the_path_is_refused_at_the_seam() -> void:
	var stone := _actor(STONE)
	assert_eq(_path_unmet(stone, PathState.MIND).is_empty(), false, "stoneborn closes mind")
	assert_eq(MindCultivationApi.try_breakthrough(stone), false, "the mind breakthrough is refused")


func test_a_race_that_closes_no_path_is_not_gated() -> void:
	var tide := _actor(TIDE)
	assert_eq(_path_unmet(tide, PathState.MIND).is_empty(), true, "tidecaller leaves mind open")


func test_the_refusal_carries_the_five_key_entry_a_screen_renders() -> void:
	var stone := _actor(STONE)
	var entries := _path_unmet(stone, PathState.MIND)
	assert_eq(entries.is_empty(), false, "there is a complaint to render")
	for key in ["kind", "id", "required", "actual", "label"]:
		assert_eq(entries[0].has(key), true, "the entry names '%s'" % key)
	# `str()` rather than `String()`: this Godot build has no callable `String`
	# constructor for a Variant, and using one throws instead of formatting.
	assert_ne(str(entries[0]["label"]), "", "and says something a player can read")


# --- The ceiling is the second half of the rule -------------------------------


func test_a_realm_above_the_authored_ceiling_is_refused() -> void:
	# stoneborn authors `realm_ceiling = 17`, so `realm_ceiling_unmet` reports a body that has
	# reached ordinal 17 — the ceiling is the realm it may hold, not the one above it.
	var stone := _actor(STONE, &"spirit_sea")
	assert_eq(RaceApi.race_definition(stone).realm_ceiling, 17, "the authored ceiling")
	assert_ne(
		RaceGate.realm_ceiling_unmet(stone).is_empty(), false, "a stoneborn past 17 is refused"
	)


func test_a_race_with_no_ceiling_is_never_refused_by_one() -> void:
	var tide := _actor(TIDE, &"spirit_sea")
	assert_eq(RaceApi.race_definition(tide).realm_ceiling, 0, "no ceiling authored")
	assert_eq(RaceGate.realm_ceiling_unmet(tide).is_empty(), true, "so the ceiling never refuses")


# --- An unauthored body must not lock anyone out ------------------------------


func test_an_actor_with_no_race_takes_no_restriction() -> void:
	# A content gap is not a reason to gate content: an unauthored body would otherwise lock a
	# player out of a path nobody ever denied them. `set_race` refuses an empty id and leaves
	# the previous race in place, so a raceless actor is built without ever setting one.
	var bare := _actor(&"")
	assert_eq(RaceApi.race_of(bare), &"", "no race was ever assigned")
	assert_eq(_path_unmet(bare, PathState.MIND).is_empty(), true, "so no path is closed")
	assert_eq(RaceGate.realm_ceiling_unmet(bare).is_empty(), true, "and no ceiling refusal")
	# And the same for an actor that was never given a race at all.
	var untouched := Actor.new(&"plain", {Stat.PHYSIQUE: 10.0})
	RaceApi.attach(untouched)
	assert_eq(
		RaceGate.path_unmet(untouched, PathState.MIND).is_empty(), true, "nor for a fresh actor"
	)


# --- The three facades all consult the same gate -------------------------------


func test_every_cultivation_path_consults_the_body() -> void:
	var stone := _actor(STONE)
	# STONE closes mind and opens body and qi, so of the three seams exactly one refuses.
	assert_eq(_path_unmet(stone, PathState.QI).is_empty(), true, "qi stays open to stoneborn")
	assert_eq(_path_unmet(stone, PathState.BODY).is_empty(), true, "body stays open too")
	assert_eq(_path_unmet(stone, PathState.MIND).is_empty(), false, "and mind does not")
