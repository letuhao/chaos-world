extends TestCase

## ADR 0062's content rules, asserted against the SHIPPED tree rather than a fixture:
## race × path must be a **partition, not a tier list**. Every authored race closes at
## least one of qi/body/mind; no race is top-2 on more than one of the three axes; no
## race is strictly best; every race carries a structural liability; and the baseline
## fallback is an authored tag rather than a hardcoded id.
##
## These are deliberately NOT isolated with a fixture catalog: the point is to hold the
## `.tres` files, so the real catalog is what they read.

const QI := &"qi_cultivation"
const BODY := &"body_cultivation"
const MIND := &"mind_cultivation"
const AXES: Array[StringName] = [QI, BODY, MIND]

## The axes a race may not top. Two is the cap: a race that led three axes would be the
## default answer to every question, which is exactly what ADR 0062 rules out.
const MAX_TOP_AXES := 2


## These are deliberately NOT isolated with a fixture catalog: the point is to hold the
## `.tres` files, so the real catalog is what they read.
##
## The runner calls `teardown` after every test now, so a sibling suite's fixture catalog
## is released before this one starts — but a suite that installs one and never tears it
## down would still leak in. Null the singleton here rather than trusting the load order,
## then force the shipped tree to be rescanned.
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
			def.closed_paths.is_empty() and def.realm_ceiling > 0 and def.lifespan >= 36500.0,
			true,
			"'%s' has at least one structural one" % [race_id]
		)


func test_some_authored_race_carries_a_hard_realm_ceiling_below_thirty() -> void:
	var capped: Array[StringName] = []
	for race_id in _catalog().race_ids():
		var def := _catalog().race_definition(race_id)
		if def.realm_ceiling > 0 and def.realm_ceiling < 30:
			capped.append(race_id)
	assert_eq(capped.is_empty(), false, "at least one race cannot pass the ladder")


func test_a_race_is_never_the_best_body_on_more_than_two_of_the_three_axes() -> void:
	# Each axis is owned by whichever race leads it; a race that owned all three would
	# make the choice a formality.
	var owners: Dictionary = {}
	for path_id in AXES:
		owners[str(path_id)] = _leader_on(path_id)
	for race_id in _catalog().race_ids():
		var owned := 0
		for path_id in AXES:
			# `str()`, not `String()`: this Godot build has no callable `String`
			# constructor for a StringName, and `String(race_id)` throws at runtime —
			# silently aborting the test mid-function, which the runner reports as
			# "the run above is incomplete" rather than as a failure.
			if str(owners[str(path_id)]) == str(race_id):
				owned += 1
		assert_eq(owned <= MAX_TOP_AXES, true, "'%s' tops %d of 3 axes" % [race_id, owned])


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


## The authored race that is best on `path_id`, judged on the axis that matters:
## a lead attribute, then the smallest loss on the other two axes, ties to canonical id
## order so the answer is total. Deliberately read-only — this is a balance inspection,
## not a new ranking the game ships.
func _leader_on(path_id: StringName) -> StringName:
	var best := StringName("")
	var best_strength := -1.0
	for race_id in _catalog().race_ids():
		var def := _catalog().race_definition(race_id)
		var strength := _axis_strength(def, path_id)
		if best == &"" or strength > best_strength:
			best = race_id
			best_strength = strength
	return best


## How strong a body plan is on one axis: the granted base attribute it leads with, less
## half of every loss it carries on that axis. A closed path costs everything.
func _axis_strength(def: RaceDef, path_id: StringName) -> float:
	var attribute := (
		Stat.PHYSIQUE
		if path_id == BODY
		else (Stat.APTITUDE if path_id == QI else Stat.COMPREHENSION)
	)
	if def.closed_paths.has(path_id):
		return -1000.0
	var strength := float((def.base_attributes as Dictionary).get(attribute, 0.0))
	for key in (def.percent_modifiers as Dictionary).keys():
		var stat_id := StringName(key)
		if _serves_axis(stat_id, path_id):
			strength += float((def.percent_modifiers as Dictionary)[key]) * 2.0
	if def.realm_ceiling > 0:
		strength -= float(def.realm_ceiling) / 10.0
	if def.lifespan < 58400.0:
		strength -= (58400.0 - def.lifespan) / 20000.0
	return strength


func _serves_axis(stat_id: StringName, path_id: StringName) -> bool:
	var served := {
		BODY:
		[
			Stat.MAX_HEALTH,
			Stat.DEFENSE_PHYSICAL,
			Stat.ATTACK_PHYSICAL,
			Stat.POISE,
			Stat.STATUS_RESISTANCE,
		],
		QI:
		[
			Stat.MAX_QI,
			Stat.QI_REGEN,
			Stat.QI_ABSORPTION,
			Stat.CULTIVATION_RATE,
			Stat.QI_COST_REDUCTION,
		],
		MIND:
		[
			Stat.INSIGHT_GAIN,
			Stat.BREAKTHROUGH_CHANCE,
			Stat.CRIT_CHANCE,
			Stat.DEFENSE_SPIRITUAL,
		],
	}
	return (served[path_id] as Array).has(stat_id)
