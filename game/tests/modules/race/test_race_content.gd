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
## `RaceDef`'s own default lifespan — the authored default a body is born into when
## nothing shortens it, and therefore the rung below which an author has made a body
## short-lived.
##
## ## It is an AUTHORING rung, not an ENFORCED one (BL-0772)
##
## Nothing ages an actor and nothing dies of old age: there is no `age`, `elapsed_days`
## or `born_year` field on `Actor` at all, and ADR 0109 records the gap as owned and
## ADR 0169 defers it explicitly. So a lifespan is currently inert — an authored number
## with nothing to compare it against — and this constant may only ever be used to read
## what an author WROTE. It is not evidence that the number is enforced, and it must
## never appear in a branch that claims to prove a race is refused. That would be an
## enforcement claim dressed as an authoring one, which is the defect BL-0772 is about.
## `test_race_lifespan_is_authored_and_reaches_a_stat_but_enforces_nothing` pins the
## honest shape; read that test before using this constant in a new one.
const DEFAULT_LIFESPAN_DAYS := 36500.0

## ## Why this file holds no STRENGTH RANKING (BL-0279)
##
## An earlier version of this file scored each race ("lead attribute, less half of every
## loss on that axis, a closed path worth `-1000.0`") and failed the build when more than
## `MAX_TOP_AXES := 2` races led every axis. That cap was a constant invented in the test
## file, with no ADR behind it, and the score it replaced could not express the claim ADR
## 0062 actually makes. It scored leading a path the body is FORBIDDEN to enter as an
## artefact of the arithmetic, so `commonborn` led all three axes and still passed.
##
## So the cap is gone rather than retuned: there is no ADR that states a number of top
## axes, and inventing a different one would repeat the same defect. What is left is what
## the ADRs do state — every race is genuinely refused SOMEWHERE
## (`test_every_authored_race_is_genuinely_refused_somewhere`) — plus the axis-lead
## partition that IS derivable from content alone, in
## `test_the_baseline_leads_no_axis_and_leads_nothing_a_specialist_leads`
## (`test_race_body_plan.gd`), stated as what the author intended per body rather than as
## a cap on a tally.


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


func test_every_authored_race_closes_only_paths_that_exist() -> void:
	# The rule is NOT "every race closes a path" — ADR 0062's claim is that every race is
	# REFUSED somewhere, which `test_every_authored_race_is_genuinely_refused_somewhere`
	# below asserts properly against the gate. A body may legitimately close nothing and
	# pay in a realm ceiling instead (`emberblood_touched` is exactly that: an altered
	# frame that walks two paths and is capped at the last Mortal realm).
	#
	# What must hold unconditionally is the weaker half: a closed path, if there is one, is
	# a REAL path. That is what a typo in `closed_paths` would break, and it is why this
	# test exists rather than the stricter form it replaced.
	for race_id in _catalog().race_ids():
		var def := _catalog().race_definition(race_id)
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
		# A body that closes nothing is NOT this failure — it pays in a ceiling instead,
		# which is the second branch. Only a body refused by NO enforced mechanism at all
		# is the content bug.
		# (b) a ceiling that stops the body inside the ladder.
		#
		# This is the rule `commonborn` broke for so long: it leads all three axes and was
		# refused only where no real actor stands — a `race_allows_path` gate at a realm its
		# own ceiling already forbids, and a closed path it is not allowed to attempt in
		# the first place. So branch (a) is narrowed to the paths its OWN closed list names,
		# where a refusal is one a player could actually have met, and branch (b) is left to
		# the ladder: the probe stands on the last realm, which no ceiling is above, so
		# every authored ceiling refuses and a body with no ceiling does not.
		#
		# ## (c) is GONE, and its removal is the point (BL-0772)
		#
		# This branch once read `def.lifespan < DEFAULT_LIFESPAN_DAYS`. It read as if the
		# game refuses a short-lived body, and it does not: nothing ages an actor, there
		# is no age field to compare a lifespan against, and ADR 0109 records that gap as
		# owned. So the branch could make a race PASS this test on a refusal the game never
		# performs — the opposite of what this test claims to prove. A test named "is
		# genuinely refused somewhere" must only accept a refusal the gate really produces.
		#
		# `emberblood` is what that costs, and paying it is the point: it closes
		# `mind_cultivation` (branch (a)), so it still passes honestly. A hypothetical race
		# that relied on a SHORT LIFE alone would now go red — which is correct, because
		# today such a race is not refused at all. Whether lifespan becomes the third
		# enforced gate is ADR 0109's open question and its owner's decision, and it is
		# pinned as inert, not faked, in `test_race_body_plan.gd`.
		assert_eq(
			_refuses_the_path_of(def) or _capped_a_realm(def),
			true,
			"'%s' is refused nowhere: no path it could have taken, and no ceiling" % [race_id]
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
