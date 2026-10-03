extends TestCase

## ADR 0066: the realm RATE is one shared curve in `core`, not three copies.
##
## `RealmRate.factor(realm_id)` answers "how much is one unit of this realm's
## training worth". It is not a magnitude and must never become one — the removed
## shared ladder reached 1e46, so a single training tick at R30 was worth more
## than every other investment in the game put together (ADR 0050).
##
## The three `*RealmProfile` classes are RENAME SEAMS: they alias the constants here and
## delegate `factor`, because six production call sites are mid-flight in other agents'
## changes and may not be edited underneath them. They used to be three private curves.
## That is the state this file exists to make impossible:
##
##   - `BodyRealmProfile` / `QiRealmProfile` / `MindRealmProfile` must return the SAME
##     rate as `RealmRate` at every one of the 30 realms. This is the assertion the
##     deleted `test_realm_rate_parity.gd` made and the replacement did not: the
##     replacement read `RealmRate` three times and compared it with itself.
##   - no module may AUTHOR a `const RATE_STEP`. The only legal line anywhere in the
##     three cultivation modules is the alias `const RATE_STEP := RealmRate.RATE_STEP`,
##     so a fourth copy cannot be added quietly, and cannot be added at all by copying.
##
## The rest is carried coverage: the rate rises strictly at every realm; the span is a
## consequence of the authored step rather than a pasted number and stays a gain; an
## unknown or empty realm id degrades to `NEUTRAL`; and the rate/magnitude split is
## MACHINE-CHECKED — `RealmScaling` reads the authored `RealmDef.power`, `RealmRate` must
## not, or the two would count the same realm twice.

const FIRST := &"qi_refining"
const LAST := &"primordial_origin"
const UNKNOWN := &"not_a_realm"

## The three cultivation modules, by the directory that holds their seed ladder and the
## `realm_profile.gd` seam. Enumerated so a FOURTH path cannot join without a decision.
const PATH_DIRS := ["body_cultivation", "qi_cultivation", "mind_cultivation"]

## The authored per-realm training budget, read from the realm seeds. `work_required` on
## the body seed is DERIVED from this field (DEF-0130) and pinned equal to it by
## `test_seed_balance_invariants.gd`, so `progress_required` is the authored name on all
## three paths and the bound is checked against one uniform field.
const BUDGET_FIELD := "progress_required"


## The rate is a gain at every one of the 30 realms. A flat or falling rate would
## make a breakthrough worth less the deeper you were, which is how the deep
## realms used to become free.
func test_the_rate_rises_at_every_one_of_the_30_realms() -> void:
	var previous := 0.0
	var counted := 0
	for realm in RealmDefaults.ladder().realms():
		var rate := RealmRate.factor(realm.id)
		assert_eq(rate > previous, true, "rate rises at %s" % realm.id)
		previous = rate
		counted += 1
	assert_eq(counted, 30, "the whole ladder was walked")


## R1 is the neutral rate: it is ordinal 0, so `RATE_STEP^0` is exactly 1.0. If it
## were not, every other number in the curve would be relative to a fiction and
## an unstarted path would silently contribute a fraction of a unit.
func test_the_first_realm_is_the_neutral_rate() -> void:
	assert_almost_eq(RealmRate.factor(FIRST), 1.0, "R1 is neutral", 0.0001)
	assert_almost_eq(RealmRate.factor(FIRST), RealmRate.NEUTRAL, "R1 equals NEUTRAL", 0.0001)


## A rate must stay a rate. The span is a CONSEQUENCE of the authored step
## compounded over the ladder, not a pasted number, so retuning `RATE_STEP` is a
## one-line data change and never requires editing this suite.
func test_the_span_is_the_authored_step_and_stays_a_gain() -> void:
	var realms := RealmDefaults.ladder().realms()
	var span := RealmRate.factor(realms[realms.size() - 1].id) / RealmRate.factor(realms[0].id)
	assert_almost_eq(
		span,
		pow(RealmRate.RATE_STEP, float(realms.size() - 1)),
		"the span is the authored step compounded over the ladder",
		0.0001
	)
	assert_eq(span < 2.0, true, "the whole ladder is under 2x, not a magnitude (%s)" % span)
	assert_eq(span > 1.0, true, "and it still rises, or cultivation stops paying")


## Off the ladder means neutral, never zero. A rate of 0 would delete the stat it
## scales instead of leaving it alone, and a missing entry must fail safe. All three
## paths reach this one function through their seam, so this also pins the behaviour
## every `*Provider._realm_factor` relies on for a stale rank.
func test_an_unknown_or_empty_realm_is_neutral() -> void:
	for realm_id in [&"", UNKNOWN]:
		assert_eq(RealmRate.factor(realm_id), RealmRate.NEUTRAL, "rate for '%s'" % realm_id)


## The check that could not exist before the collapse. `RealmRate` must be
## invariant under the authored MAGNITUDE: rewrite a `RealmDef.power` and the rate
## for that realm is unchanged. If this ever fails, the rate has started tracking a
## magnitude again — which is what once made a single breakthrough worth more than
## everything else combined, and which would double-count the realm against
## `RealmScaling` on every stat the three providers emit.
##
## The ordinal is read through `RealmDefaults.ladder().index_of`, so a retuned
## `power` cannot even reach the curve. Asserting it keeps that true if someone
## later "simplifies" the lookup into a table read.
func test_the_rate_is_invariant_under_the_authored_realm_power() -> void:
	var realm := RealmDefaults.ladder().realm(FIRST)
	assert_ne(realm, null, "the first realm is on the ladder")
	if realm == null:
		return
	var rate_before := RealmRate.factor(realm.id)
	var power_before := realm.power
	assert_eq(
		power_before != 0.0, true, "the probe power is non-zero, or the rewrite proves nothing"
	)
	realm.power = power_before * 7.5
	var rate_after := RealmRate.factor(realm.id)
	# Restore before asserting, so a failure here cannot leak a mutated ladder
	# into whichever suite runs next and turn one failure into three.
	realm.power = power_before
	assert_eq(
		rate_after, rate_before, "a retuned RealmDef.power does not move the rate for %s" % realm.id
	)


## The same isolation as above, stated as a property of the lookup itself: the
## curve is a function of the ladder ORDINAL only, and the ordinal is the ladder's,
## not a field on the realm. A realm re-indexed on the ladder moves its rate; a
## realm merely re-powered does not.
func test_the_curve_reads_the_ladder_ordinal_and_nothing_else() -> void:
	var realms := RealmDefaults.ladder().realms()
	for index in realms.size():
		var realm := realms[index]
		var ordinal := RealmDefaults.ladder().index_of(realm.id)
		assert_eq(ordinal, index, "%s is ordinal %d" % [realm.id, index])
		assert_almost_eq(
			RealmRate.factor(realm.id),
			pow(RealmRate.RATE_STEP, float(ordinal)),
			"rate for %s is the step at its ordinal" % realm.id,
			0.0001
		)


## The assertion the deleted `test_realm_rate_parity.gd` made and the version that
## replaced it did not. That version called `RealmRate.factor` three times and compared
## the results with each other — `x == x` — so it would have passed unchanged with all
## three paths back on private curves, which is the state it was written against.
##
## This compares FOUR independent call sites against each other at EVERY realm on the
## ladder, so one path being retuned or re-implemented fails here and names the path. The
## number is free to move, but it must move in all four at once.
func test_every_path_returns_the_same_rate_as_the_shared_curve() -> void:
	var realms := RealmDefaults.ladder().realms()
	for realm in realms:
		var shared := RealmRate.factor(realm.id)
		assert_almost_eq(
			BodyRealmProfile.factor(realm.id), shared, "body rates %s as core does" % realm.id, 1e-9
		)
		assert_almost_eq(
			QiRealmProfile.factor(realm.id), shared, "qi rates %s as core does" % realm.id, 1e-9
		)
		assert_almost_eq(
			MindRealmProfile.factor(realm.id), shared, "mind rates %s as core does" % realm.id, 1e-9
		)
	assert_eq(realms.size(), 30, "and the whole ladder was walked")


## The same four surfaces off the ladder. A path that disagreed here would let a stale
## rank move one path's rate and not another's.
func test_every_path_is_neutral_off_the_ladder() -> void:
	for realm_id in [&"", UNKNOWN]:
		var shared := RealmRate.factor(realm_id)
		assert_almost_eq(
			BodyRealmProfile.factor(realm_id), shared, "body neutral for '%s'" % realm_id
		)
		assert_almost_eq(QiRealmProfile.factor(realm_id), shared, "qi neutral for '%s'" % realm_id)
		assert_almost_eq(
			MindRealmProfile.factor(realm_id), shared, "mind neutral for '%s'" % realm_id
		)


## `RATE_STEP` is duplicated TEXT in four files, so compare the four constants directly.
## A copy edited but no longer exercised — a seam whose `factor` stopped calling it —
## would otherwise drift while every behavioural test still agreed with itself.
func test_every_path_names_the_one_authored_step() -> void:
	var profiles := {"body": BodyRealmProfile, "qi": QiRealmProfile, "mind": MindRealmProfile}
	for label in profiles:
		var profile: Variant = profiles[label]
		assert_eq(profile.RATE_STEP, RealmRate.RATE_STEP, "%s uses the one RATE_STEP" % label)
		assert_eq(profile.NEUTRAL, RealmRate.NEUTRAL, "%s uses the one NEUTRAL" % label)
	assert_eq(profiles.size(), 3, "and there really are three paths")


## The guard against the FOURTH copy. `const RATE_STEP` may appear exactly once in each
## cultivation module, and its right-hand side must be the shared constant, so the only way
## to add a private rate is to delete this line — and the build then goes red naming which
## module and which line.
##
## `pow(` is banned by a different route to the same end: a path that re-derived the curve
## would be numerically identical today and free to drift tomorrow, and searching for the
## constant alone would not see it.
func test_no_cultivation_module_authors_its_own_rate_step() -> void:
	for path_dir in PATH_DIRS:
		var source := FileAccess.get_file_as_string(
			"res://src/modules/%s/realm_profile.gd" % path_dir
		)
		assert_ne(source, "", "%s/realm_profile.gd is readable" % path_dir)
		assert_eq(source.contains("pow("), false, "%s derives no curve of its own" % path_dir)
		var authored := _authored_steps(source)
		assert_eq(
			authored,
			["const RATE_STEP := RealmRate.RATE_STEP"],
			"%s authors one aliased step" % path_dir
		)


## The same rule widened to the WHOLE module directory rather than one file. The seam
## happens to be named `realm_profile.gd`, but a private step authored beside
## `training.gd` — or in a new `rates.gd` — would satisfy the file-level pin above while
## still being a second number. `get_files()` returns a finished array, so there is no
## directory walk to bound.
func test_the_rate_step_is_authored_once_across_the_whole_cultivation_layer() -> void:
	for path_dir in PATH_DIRS:
		var dir := DirAccess.open("res://src/modules/%s" % path_dir)
		assert_ne(dir, null, "%s is readable" % path_dir)
		if dir == null:
			continue
		for file_name in dir.get_files():
			var file := String(file_name)
			if not file.ends_with(".gd"):
				continue
			var path := "res://src/modules/%s/%s" % [path_dir, file]
			var source := FileAccess.get_file_as_string(path)
			for step in _authored_steps(source):
				assert_eq(
					step,
					"const RATE_STEP := RealmRate.RATE_STEP",
					"%s is the only place a rate step may be declared" % path
				)


## Every `const RATE_STEP` declaration in a source file, as written. Reading the source
## rather than the value is the point: an unexercised copy is invisible to a value
## comparison, and this is what the deleted parity test's second test was for.
func _authored_steps(source: String) -> Array[String]:
	var authored: Array[String] = []
	for line in source.split("\n"):
		var stripped := String(line).strip_edges()
		if stripped.begins_with("const RATE_STEP"):
			authored.append(stripped)
	return authored


## `RATE_STEP` is authored, but the bound it must respect is not: it has to stay at or
## below the smallest per-realm step in the AUTHORED work budget, or the rate outruns the
## price of a breakthrough and the deep realms get cheap. The check this replaces compared
## it against a typed-in `1.05`, which is LOOSER than the data — it permitted a retune that
## broke qi's last transition.
##
## This reads all three authored ladders from the realm seeds and takes the smallest step
## any of them prices a transition at. It is a cross-path bound, so no single path's suite
## can state it: no single path knows what the other two author. The three per-path suites
## each guard their OWN ladder's PRICE side; this guards the rate against the tightest of
## all three.
##
## The FIRST transition is excluded, and that is a property of the data rather than a
## convenience: qi and mind author R1 and R2 equal (100 and 100), so the entry price has no
## predecessor realm to be cheaper than and a bound taken over it would be vacuously 1.0.
## All three per-path suites skip it for exactly this reason.
func test_the_rate_step_fits_inside_the_smallest_authored_work_step() -> void:
	var smallest := INF
	var tightest := ""
	for path_dir in PATH_DIRS:
		var budgets := _authored_budgets(path_dir)
		assert_eq(budgets.size(), 30, "%s authored a budget for every realm" % path_dir)
		if budgets.size() < 3:
			continue
		for index in range(2, budgets.size()):
			var step := budgets[index] / budgets[index - 1]
			if step < smallest:
				smallest = step
				tightest = (
					"%s %s->%s"
					% [
						path_dir,
						RealmDefaults.ladder().realms()[index - 1].id,
						RealmDefaults.ladder().realms()[index].id,
					]
				)
	assert_eq(
		smallest < INF, true, "every authored ladder was walked, so the bound is a real number"
	)
	assert_eq(RealmRate.RATE_STEP > 1.0, true, "the rate is still a gain")
	assert_eq(
		RealmRate.RATE_STEP <= smallest + 0.000001,
		true,
		(
			"RATE_STEP %s outruns the authored work step %s at %s — the rate would outrun the price"
			% [RealmRate.RATE_STEP, smallest, tightest]
		)
	)


## The per-realm training budget as AUTHORED, in ladder order. Loaded as a resource and
## read generically rather than through the three seed classes: this bound is a property of
## the data under `res://data`, not of three module APIs, and a guard that named the seed
## classes would have to be rewritten whenever a path renamed one. `work_required` on the
## body seed is DERIVED from `progress_required` (DEF-0130) and pinned equal to it, so one
## field name is the authored one on all three paths.
func _authored_budgets(path_dir: String) -> Array[float]:
	var budgets: Array[float] = []
	for realm in RealmDefaults.ladder().realms():
		var seed := load("res://data/%s/realms/%s.tres" % [path_dir, realm.id])
		assert_ne(seed, null, "%s seed for %s loads" % [path_dir, realm.id])
		if seed == null:
			budgets.append(0.0)
			continue
		var authored: Variant = seed.get(BUDGET_FIELD)
		var budget := 0.0 if authored == null else float(authored)
		assert_eq(budget > 0.0, true, "%s/%s authors a %s" % [path_dir, realm.id, BUDGET_FIELD])
		budgets.append(budget)
	return budgets
