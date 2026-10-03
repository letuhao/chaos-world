extends TestCase

## ADR 0062's content rules, asserted against the SHIPPED tree rather than a fixture:
## race × path must be a **partition, not a tier list**. Every authored race is genuinely
## refused somewhere — a path it cannot cultivate, a realm it cannot reach, or a life too
## short to get there; no race is strictly best; and the baseline fallback is an authored
## tag rather than a hardcoded id.
##
## These are deliberately NOT isolated with a fixture catalog: the point is to hold the
## `.tres` files, so the real catalog is what they read.

const QI := &"qi_cultivation"
const BODY := &"body_cultivation"
const MIND := &"mind_cultivation"
const AXES: Array[StringName] = [QI, BODY, MIND]

## The bound the ladder imposes on any authored ceiling, and why the partition assertion
## below never compares a ceiling against it.
##
## `HARD_CEILING_ORDINAL` is 30 — the length of the shared ladder. `RaceGate` compares a
## body's `realm_ceiling` against a ladder ORDINAL, so a ceiling at or past the top refuses
## nothing: "has a ceiling at all" is already the whole condition, and no value inside the
## ladder is what makes it true. A threshold *inside* the ladder, by contrast, is a number a
## balance pass can drift across without meaning to, and then a test fails for a reason
## nobody chose.
const HARD_CEILING_ORDINAL := 30
## `RaceDef`'s own default lifespan — the frame a body is born into when nothing shortens
## it, and therefore the rung below which a body is outlived by the ladder.
const DEFAULT_LIFESPAN_DAYS := 36500.0


## These are deliberately NOT isolated with a fixture catalog: the point is to hold the
## `.tres` files, so the real catalog is what they read. The runner calls `teardown` after
## every test now, so a sibling suite's fixture catalog is released before this one starts
## — but a suite that installs one and never tears it down would still leak in. Null the
## singleton here rather than trusting the load order, then force the shipped tree to be
## rescanned.
func setup() -> void:
	RaceFixtureCatalog.teardown()


func _catalog() -> RaceCatalog:
	return RaceCatalog.instance()


# --- The tree loads at all ----------------------------------------------------


func test_the_authored_tree_loads_and_holds_several_races() -> void:
	var ids := _catalog().race_ids()
	assert_eq(ids.size() >= 4, true, "at least four authored races, found %d" % ids.size())
	for race_id in ids:
		var def := _catalog().race_definition(race_id)
		assert_ne(def, null, "'%s' resolves" % [race_id])
		assert_ne(String(def.display_name), "", "'%s' is named" % [race_id])
		assert_ne(String(def.description), "", "'%s' is described" % [race_id])
		assert_eq(
			String(def.source_id()), "race:%s" % [race_id], "'%s' namespaces its source" % [race_id]
		)


func test_an_unknown_race_resolves_to_null_rather_than_a_guess() -> void:
	assert_eq(_catalog().race_definition(&"no_such_race"), null, "null, never a fallback")
	assert_eq(_catalog().race_ids().has(&"no_such_race"), false, "and it is not listed either")


func test_exactly_one_authored_race_is_the_baseline() -> void:
	var tagged: Array[StringName] = []
	for race_id in _catalog().race_ids():
		var def := _catalog().race_definition(race_id)
		if def.tags.has(RaceDef.BASELINE_TAG):
			tagged.append(race_id)
	assert_eq(tagged.size(), 1, "one baseline, found %s" % [tagged])
	assert_eq(_catalog().baseline_race(), tagged[0], "and the catalog names it")


func test_every_authored_race_inherits_the_reproduction_fields_race_def_replaced() -> void:
	for race_id in _catalog().race_ids():
		var def := _catalog().race_definition(race_id)
		assert_eq(def.gestation_days > 0.0, true, "'%s' has a gestation" % [race_id])
		assert_eq(
			def.base_fertility > 0.0 and def.base_fertility <= 1.0,
			true,
			"'%s' has a fertility fraction" % [race_id]
		)
		assert_eq(
			def.base_potency > 0.0 and def.base_potency <= 1.0,
			true,
			"'%s' has a potency fraction" % [race_id]
		)
		assert_eq(def.offspring_variance >= 0.0, true, "'%s' has a variance" % [race_id])


# --- Race x path is a partition ----------------------------------------------


func test_every_authored_race_closes_at_least_one_of_the_three_paths() -> void:
	var catalog := _catalog()
	var ids := catalog.race_ids()
	for race_id in ids:
		var def := catalog.race_definition(race_id)
		# `is_empty()` is true when the race closes nothing, so the partition
		# rule is "not empty" — which is `assert_eq(..., false)`, NOT `assert_ne`.
		# Written as assert_ne it asserts "is empty", which is the opposite rule
		# and fails on correct content.
		assert_eq(def.closed_paths.is_empty(), false, "'%s' closes something" % [race_id])
		for path_id in def.closed_paths:
			assert_eq(AXES.has(path_id), true, "'%s' closes a real path (%s)" % [race_id, path_id])


func test_every_authored_race_carries_a_structural_liability_not_only_a_penalty() -> void:
	for race_id in _catalog().race_ids():
		var def := _catalog().race_definition(race_id)
		assert_eq(
			def.has_liability(),
			true,
			"'%s' closes a path, caps a realm or shortens life" % [race_id]
		)
		assert_ne(
			(
				def.closed_paths.is_empty()
				and def.realm_ceiling > 0
				and def.lifespan >= DEFAULT_LIFESPAN_DAYS
			),
			true,
			"'%s' has at least one structural one" % [race_id]
		)


func test_some_authored_race_carries_a_hard_realm_ceiling_the_ladder_can_measure() -> void:
	var capped: Array[StringName] = []
	for race_id in _catalog().race_ids():
		var def := _catalog().race_definition(race_id)
		if def.realm_ceiling > 0 and def.realm_ceiling < HARD_CEILING_ORDINAL:
			capped.append(race_id)
	assert_eq(capped.is_empty(), false, "at least one race cannot pass the ladder")


## ## Why this replaced a strength score
##
## ADR 0062's load-bearing claim is that race × path is a **partition, not a tier list**:
## every authored race is genuinely refused somewhere. ADR 0109 already implements that
## refusal — `RaceGate.path_unmet` and `RaceGate.realm_ceiling_unmet` are what the three
## cultivation facades consult at the breakthrough seam — so the assertion reads the real
## refusals instead of re-deriving them from a hand-rolled score.
##
## The score it replaced ("lead attribute, less half of every loss on that axis, a closed
## path worth `-1000.0`", capped at `MAX_TOP_AXES := 2`) could not express that claim. It
## scored leading an axis you are *forbidden to enter* as an artefact of the arithmetic,
## so a race could lead all three axes and pass, and the cap it failed was a constant
## invented in the test file that no ADR states. Two rules cannot both be invented; one of
## them was always going to be wrong, and nothing said which.
##
## What makes this harder to game rather than easier: there is no strength to rank and no
## cap to tune. Every branch is a refusal the shipped `.tres` authors — a path the body may
## never cultivate, a ceiling that stops it inside the ladder, or a life too short to climb
## it — and two of the three are read back out of ADR 0109's gate rather than recomputed
## here. A new race that leads every axis still PASSES, because leading is not the claim;
## being refused somewhere is. The only way to turn this red is to author a body with
## nothing closed, capped or shortened: exactly the content bug ADR 0062 calls a bug and
## ADR 0078 recorded against `commonborn` by name.
func test_every_authored_race_is_genuinely_refused_somewhere() -> void:
	var catalog := _catalog()
	for race_id in catalog.race_ids():
		var def := catalog.race_definition(race_id)
		# (a) a closed path, asked through the gate rather than off `def.closed_paths`, so
		# the assertion holds the refusal the breakthrough seam really hands a player.
		var refused_a_path := false
		for path_id in AXES:
			if not _path_refusal_for(def, path_id).is_empty():
				refused_a_path = true
		assert_eq(refused_a_path, true, "'%s' is refused a cultivation path" % [race_id])
		# (b) a ceiling that stops the body inside the ladder, and (c) a life too short to
		# climb it. `lifespan` is data nothing enforces yet — ADR 0109 records that gap as
		# owned — so (c) is the one branch read straight off the definition, and (b) is
		# asked of the gate so the ceiling the author wrote and the ceiling the game
		# enforces cannot drift apart.
		#
		# This is the rule `commonborn` broke for so long: it leads all three axes and was
		# refused only where no real actor stands — a `race_allows_path` gate at a realm its
		# own ceiling already forbids, and a closed path it is not allowed to attempt in
		# the first place. So branch (a) is narrowed to the paths its OWN closed list names,
		# where a refusal is one a player could actually have met, and branch (b) is left to
		# the ladder: the probe stands on the last realm, which no ceiling is above, so
		# every authored ceiling refuses and a body with no ceiling does not.
		assert_eq(
			(
				_refuses_the_path_of(def)
				or _capped_a_realm(def)
				or def.lifespan < DEFAULT_LIFESPAN_DAYS
			),
			true,
			"'%s' is refused nowhere: no path, no ceiling, a full life" % [race_id]
		)


func test_no_authored_race_is_strictly_best_at_everything() -> void:
	var ids := _catalog().race_ids()
	for race_id in ids:
		var def := _catalog().race_definition(race_id)
		# An affinity set narrower than the tree's widest is the cheapest honest proof a
		# race cannot do everything: something outside its affinities is out of reach.
		var widest := 0
		for other_id in ids:
			widest = maxi(widest, (_catalog().race_definition(other_id)).affinities.size())
		assert_eq(
			def.affinities.size() < widest or def.realm_ceiling > 0 or def.lifespan < 58400.0,
			true,
			"'%s' is missing something" % [race_id]
		)


func test_dominance_and_threshold_stay_inside_the_unit_interval() -> void:
	for race_id in _catalog().race_ids():
		var def := _catalog().race_definition(race_id)
		assert_eq(def.dominance > 0.0 and def.dominance <= 1.0, true, "'%s' dominance" % [race_id])
		assert_eq(
			def.manifestation_threshold >= 0.0 and def.manifestation_threshold < 1.0,
			true,
			"'%s' threshold" % [race_id]
		)


func test_the_shipped_baseline_can_actually_manifest_and_the_shipped_tree_resolves() -> void:
	var baseline := _catalog().baseline_race()
	var a := Actor.new(&"a")
	RaceApi.attach(a)
	assert_eq(RaceApi.set_race(a, baseline), true, "the baseline is authorable onto an actor")
	assert_eq(RaceApi.resolve_race(a, a, 0.5), baseline, "and a like pairing is itself")
	assert_ne(RaceApi.race_definition(a), null, "with a definition behind it")


## An actor born into `def`, standing on `rank_id` on EVERY path — the ceiling question is
## asked of the actor's best ordinal, not of whichever path was written first, so all three
## are enrolled at the same rank.
##
## The rank is named by id and resolved through `RealmDefaults.ladder()` rather than being
## read as a number here, so a realm inserted into the middle of the ladder moves the probe
## with it. Deliberately read-only: a balance inspection, not a new ranking the game ships.
func _body_at(def: RaceDef, rank_id: StringName) -> Actor:
	var actor := Actor.new(&"probe")
	RaceApi.attach(actor)
	RaceApi.set_race(actor, def.id)
	for path_id in AXES:
		actor.set_path(PathState.new(path_id, rank_id))
	return actor


## Whether `RaceGate.path_unmet` (ADR 0109) refuses this body for `path_id`, asked of the
## gate the three cultivation facades consult at the breakthrough seam — so the assertion
## holds the shipped refusal rather than a second opinion about what closing a path means.
func _path_refusal_for(def: RaceDef, path_id: StringName) -> Array[Dictionary]:
	return RaceGate.path_unmet(_body_at(def, _first_rank_id()), path_id)


## Whether the body is refused the cultivation path that its OWN `closed_paths` names —
## the one author a player is actually told about. Narrowing to that list is deliberate:
## probing all three axes would count a refusal authored for a path nobody takes, and a
## `none_of`/`any_of` gate could satisfy the partition by accident. A body whose closed
## list names a path is refused that path, whatever the gate says about the other two.
func _refuses_the_path_of(def: RaceDef) -> bool:
	for path_id in def.closed_paths:
		if not _path_refusal_for(def, path_id).is_empty():
			return true
	return false


## Whether `RaceGate.realm_ceiling_unmet` refuses this body standing on the ladder's LAST
## realm — the top of the 30 rungs, a rank that exists. A ceiling at or under the top is a
## wall this body hits; no ceiling, or one past the top, is not, and both answer "no".
func _capped_a_realm(def: RaceDef) -> bool:
	var ladder := RealmDefaults.ladder()
	var top := ladder.realms()[ladder.size() - 1]
	return not RaceGate.realm_ceiling_unmet(_body_at(def, top.id)).is_empty()


## The ladder's own first realm, so the path probe stands on a rank that exists.
func _first_rank_id() -> StringName:
	return RealmDefaults.ladder().realms()[0].id
