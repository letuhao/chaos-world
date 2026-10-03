extends TestCase

## Entering a realm COMMITS that realm's milestone, on every path (ADR 0018-0021).
##
## The defect this file exists for: the commit was two hand-written calls, one in the
## body resolve path and one in qi's, and the mind resolve path had none. `actor.
## ascension` is created by exactly one place — `WorldAnchor._begin_ascent`, reached
## only from `_commit_micro_world`, reached only from `commit` — so on the path that
## never remembered, `ascension_ok` was false forever. R28 -> R29 was unreachable
## there and NO player action could change it: `ascend()` correctly refuses an ascent
## that has not begun.
##
## The traversal suites passed anyway, because their helpers call `WorldAnchor.commit`
## by hand. That is the shape this file breaks: a gate the product cannot satisfy and
## a test can is not a traversable gate.
##
## `Breakthrough.try_advance` is the assertion point, not any path's resolve, because
## it is the one call all three paths already make on success.

# --- Fixtures ------------------------------------------------------------------


func _realm_id(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


func _hero(path_id: StringName, index: int) -> Actor:
	var actor := Actor.new(&"commit_hero", {Stat.COMPREHENSION: 60.0})
	actor.set_path(PathState.new(path_id, _realm_id(index)))
	return actor


## Every path the ladder has, so a fourth path cannot be added and silently miss the
## commit the way mind did.
func _paths() -> Array[StringName]:
	return PathState.ALL


# --- The commit is the breakthrough's, not a path's ----------------------------


## THE BUG. Advancing any path into the Transcendent tier through the shared
## entry point BEGINS the ascent. Before the fix this failed for
## `mind_cultivation` and passed for the other two, which is exactly why it survived:
## two of three paths were right.
func test_advancing_into_the_transcendent_tier_begins_the_ascent_on_every_path() -> void:
	for path_id in _paths():
		var hero := _hero(path_id, WorldAnchor.COMMIT_MICRO - 1)
		assert_eq(hero.ascension, null, "%s has no ascent before the tier" % path_id)
		assert_eq(
			Breakthrough.try_advance(hero, path_id),
			true,
			"%s advanced into the Transcendent tier" % path_id
		)
		assert_ne(
			hero.ascension,
			null,
			"%s BEGAN the ascent by advancing, with no hand-written commit" % path_id
		)


## The ascent that advancing began is WALKABLE, and walking it is what opens the
## gate. Without this the commit would begin an ascent nothing can advance.
func test_the_ascent_the_advance_began_can_be_walked_to_completion() -> void:
	for path_id in _paths():
		var hero := _hero(path_id, WorldAnchor.COMMIT_MICRO - 1)
		Breakthrough.try_advance(hero, path_id)
		var target: int = WorldAnchor.COMMIT_MICRO + 1
		assert_eq(
			Breakthrough.ascension_ok(hero, target),
			false,
			"%s starts refused, with every step still to walk" % path_id
		)
		var walked := 0
		# Bounded: `WorldAnchor.ascend` refuses on the step past the caps, so its own
		# `false` is the real exit. The bound only names an ascent that will not finish.
		var guard := 0
		while guard < 8 and not Breakthrough.ascension_ok(hero, target):
			guard += 1
			if not WorldAnchor.ascend(hero):
				break
			walked += 1
		assert_ne(walked, 0, "%s walked a step" % path_id)
		assert_eq(
			Breakthrough.ascension_ok(hero, target),
			true,
			"%s opened the gate the ascent was refusing" % path_id
		)


## The high-tier milestone schedule is committed on every path too, not only the
## ascent. `inside_world_ok` reads `WorldAnchor.stage_met`, so a path that never
## committed would read a shut gate for a reason no action could fix.
func test_advancing_commits_the_shared_milestone_schedule_on_every_path() -> void:
	for path_id in _paths():
		var hero := _hero(path_id, WorldAnchor.COMMIT_SEED - 1)
		Breakthrough.try_advance(hero, path_id)
		assert_eq(
			Breakthrough.inside_world_ok(hero, WorldAnchor.COMMIT_SEED + 1),
			true,
			"%s committed the Seed inside world, so the next tier's gate is open" % path_id
		)


# --- The commit is not free ---------------------------------------------------


## Nothing is granted for standing still. A hero who has not advanced has no ascent,
## no inside world and no created world, so the commit cannot be reached by waiting
## or by reloading a save.
func test_nothing_is_committed_without_an_advance() -> void:
	for path_id in _paths():
		var hero := _hero(path_id, WorldAnchor.COMMIT_SEED - 1)
		assert_eq(hero.ascension, null, "%s holds no ascent" % path_id)
		assert_eq(hero.inside_world, null, "%s holds no inside world" % path_id)
		assert_eq(hero.world, null, "%s holds no created world" % path_id)


## The commit costs a breakthrough. A refused advance commits nothing, so the gate it
## was refusing stays shut — the milestone is the price of entering, not a side effect
## of trying.
func test_a_refused_advance_commits_nothing() -> void:
	var hero := _hero(PathState.MIND, WorldAnchor.COMMIT_MICRO - 1)
	var target: int = WorldAnchor.COMMIT_MICRO + 1
	assert_eq(
		Breakthrough.try_advance_gated(hero, PathState.MIND),
		false,
		"an ungated R29 entry is refused, the tribulation having never been fought"
	)
	assert_eq(hero.ascension, null, "and nothing was begun")
	assert_eq(
		String(hero.path(PathState.MIND).rank_id),
		String(_realm_id(WorldAnchor.COMMIT_MICRO - 1)),
		"the realm did not move"
	)


## Committing twice is one milestone. `commit` is documented idempotent, and a caller
## that still commits after `try_advance` must not grow a second artifact.
func test_committing_twice_is_one_milestone() -> void:
	var hero := _hero(PathState.MIND, WorldAnchor.COMMIT_MICRO - 1)
	Breakthrough.try_advance(hero, path_of(hero, WorldAnchor.COMMIT_MICRO))
	var begun := hero.ascension
	WorldAnchor.commit(hero, WorldAnchor.COMMIT_MICRO)
	assert_eq(hero.ascension, begun, "the same ascent, not a second one")
	assert_eq(
		hero.ascension.steps_remaining(),
		AscensionState.ASCENT_STEPS,
		"and its whole climb is still ahead"
	)


func path_of(hero: Actor, index: int) -> StringName:
	for path_id in _paths():
		if hero.path(path_id) != null and hero.path(path_id).rank_id == _realm_id(index):
			return path_id
	return PathState.MIND


# --- The refusal still holds ---------------------------------------------------


## `ascend()` must keep refusing an ascent that has not begun. Making it begin one on
## demand would be a gate that opens itself, and the docstring already says so; this
## is the guard that says it.
func test_ascend_refuses_an_ascent_that_has_not_begun() -> void:
	for path_id in _paths():
		var hero := _hero(path_id, WorldAnchor.COMMIT_MICRO)
		assert_eq(hero.ascension, null, "%s teleported past the tier and holds nothing" % path_id)
		assert_eq(
			WorldAnchor.ascend(hero),
			false,
			(
				"%s: ascend refuses, so a save loaded at R28 cannot walk a gate it never began"
				% path_id
			)
		)


## And the refusal is not a dead end created by this change: the one action that
## begins an ascent is advancing into the tier, and it is reachable.
func test_the_advance_is_the_way_in_and_it_is_reachable() -> void:
	var hero := _hero(PathState.MIND, WorldAnchor.COMMIT_MICRO - 1)
	assert_eq(WorldAnchor.ascend(hero), false, "nothing to walk yet")
	assert_eq(Breakthrough.try_advance(hero, PathState.MIND), true, "advance into the tier")
	assert_eq(WorldAnchor.ascend(hero), true, "and now there is a step to walk")


# --- The terminal realm is a wall ----------------------------------------------


## R30 is the end. There is no realm past it, so no advance, no milestone and no gate.
func test_the_terminal_realm_is_a_wall() -> void:
	for path_id in _paths():
		var top := RealmDefaults.ladder().size() - 1
		var hero := _hero(path_id, top - 1)
		assert_eq(Breakthrough.try_advance(hero, path_id), true, "%s reaches R30" % path_id)
		assert_eq(
			String(hero.path(path_id).rank_id),
			String(_realm_id(top)),
			"and stands at the terminal realm"
		)
		assert_eq(RealmDefaults.ladder().next(_realm_id(top)), null, "which has no realm after it")
		assert_eq(
			Breakthrough.try_advance(hero, path_id), false, "%s cannot advance past it" % path_id
		)
		assert_eq(
			String(hero.path(path_id).rank_id),
			String(_realm_id(top)),
			"and is still where it stood"
		)


## R30 grants its own milestone and asks for nothing after it. Entering the terminal
## realm commits the Great world; and because `ascension_ok` answers true for every
## target at or below `COMMIT_MICRO`, and no realm follows R30 at all, the terminal
## realm owes no further gate — even though the commit leaves an ascent record on the
## actor that nothing will ever ask it to walk.
func test_entering_the_terminal_realm_commits_and_owes_nothing_further() -> void:
	var hero := _hero(PathState.MIND, RealmDefaults.ladder().size() - 2)
	assert_eq(Breakthrough.try_advance(hero, PathState.MIND), true, "entered R30")
	assert_ne(hero.world, null, "the created world was promoted")
	assert_eq(
		Breakthrough.can_advance(hero, PathState.MIND),
		false,
		"and nothing is owed, because there is no realm after R30 to advance into"
	)
