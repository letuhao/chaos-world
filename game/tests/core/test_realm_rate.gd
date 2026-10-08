extends TestCase

## ADR 0066: the realm RATE is one shared curve in `core`, not three copies.
##
## `RealmRate.factor(realm_id)` answers "how much is one unit of this realm's
## training worth". It is not a magnitude and must never become one — the removed
## shared ladder reached 1e46, so a single training tick at R30 was worth more
## than every other investment in the game put together (ADR 0050).
##
## The three `*RealmProfile` classes that used to be three private curves are
## GONE (ADR 0116 retired them): `core/realm_rate.gd` is the one implementation
## and every path that reads a realm calls it directly. This file exists to make
## that state impossible to undo quietly:
##
##   - no module may AUTHOR a rate. `const RATE_STEP` and `const NEUTRAL` may not
##     appear anywhere in a path module, and `pow(` is banned in the same pass,
##     because a path that re-derived the curve would be numerically identical
##     today and free to drift tomorrow.
##   - no `*RealmProfile` class may be reintroduced by copying an old file back.
##   - the three paths must be seen multiplying their gain through the ONE shared factor
##     (`CultivationGain.scale_gain`, ADR 0926), and that helper must read the ladder's
##     SPAN rather than the ladder itself — a per-realm read there would make the factor
##     compound with the ladder, which is the thing the factor is bounded to prevent.
##   - every path must be seen READING the shared curve, so a path cannot quietly
##     go back to a local implementation under another name.
##
## A value comparison cannot do any of that. The guard that shipped before this
## one read `RealmRate.factor` three times and compared the results — `x == x` —
## so it passed unchanged with all three paths back on private curves. That is
## why these checks read SOURCE rather than numbers: a numerically-identical
## fourth copy stays green under every value assertion ever written here.
##
## The fourth copy was then found anyway, in `dual_cultivation`, written as an
## inline `1.0 + ordinal * 0.05` rather than a `const` or a `pow` — so it slipped
## past all three pins above as well, and the call-site table is the check that
## finally saw it. A new shape needs a new pin; that is the standing cost of a
## numeric copy surviving as an idiom rather than as a copy.
##
## The rest is carried coverage: the rate rises strictly at every realm; the span is
## the AUTHORED NUMBER and is INVARIANT to ladder length rather than a consequence of
## it; an unknown or empty realm id degrades to `NEUTRAL`; the step fits inside the
## AUTHORED work budget, computed from the seeds rather than typed in; and the
## rate/magnitude split is MACHINE-CHECKED — `RealmScaling` reads the authored
## `RealmDef.power`, `RealmRate` must not, or the two would count the same realm
## twice.
##
## Nothing here asserts a ladder LENGTH. This file used to say `30` in two places, and
## the first realm anyone added would have turned them into no-ops — the guard would
## have kept passing while checking less and less of the thing it names. The rate is
## a curve over a ladder whose length content is allowed to change (ADR 0268), so the
## assertions are derived from `RealmDefaults.ladder()` and the rate's own span.

const FIRST := &"qi_refining"
const LAST := &"primordial_origin"
const UNKNOWN := &"not_a_realm"

## Every module that reads a realm off the shared ladder, by the directory that
## holds it. Enumerated so a FOURTH path cannot join without a decision.
##
## `dual_cultivation` is here for a found reason, not for symmetry: its provider
## held a private `1.0 + ladder_ordinal * 0.05` and published the ordinal as
## `SUCCUBUS_DOMINION`. It was invisible to every pin below — no `const RATE_STEP`,
## no `pow(`, no `*RealmProfile`, so all of them shipped green over a fourth curve
## whose span (2.45x at R30) was past the under-2x ceiling a rate is held to. It
## now reads `RealmRate.factor` like the other three.
const PATH_DIRS := ["body_cultivation", "qi_cultivation", "mind_cultivation", "dual_cultivation"]

## The subset that also AUTHOR a per-realm work budget under
## `res://data/<dir>/realms/`. Not every reader is an author: `dual_cultivation`
## advances on the shared ladder and owns no seeds of its own, so the budget bound
## below has nothing to read for it and would fail on a null `load` rather than on
## a wrong number.
const SEED_PATH_DIRS := ["body_cultivation", "qi_cultivation", "mind_cultivation"]

## The authored per-realm training budget, read from the realm seeds. `work_required` on
## the body seed is DERIVED from this field (DEF-0130) and pinned equal to it by
## `test_seed_balance_invariants.gd`, so `progress_required` is the authored name on all
## three paths and the bound is checked against one uniform field.
const BUDGET_FIELD := "progress_required"

## Where `_smallest_work_step()` found its tightest step, as a failure message. A bare
## number sends the next agent hunting for the smallest ratio in three authored ladders;
## this names the path and the transition. Written by the helper, read by the bound test.
var _tightest_at := ""


## The rate is a gain at every realm on the ladder. A flat or falling rate would
## make a breakthrough worth less the deeper you were, which is how the deep
## realms used to become free. The count is the LADDER's, not a literal: this suite
## used to assert `30` here and in the work-budget walk below, so the first realm
## anyone added turned two honest guards into no-ops at once.
func test_the_rate_rises_at_every_realm_on_the_ladder() -> void:
	var previous := 0.0
	var counted := 0
	for realm in RealmDefaults.ladder().realms():
		var rate := RealmRate.factor(realm.id)
		assert_eq(rate > previous, true, "rate rises at %s" % realm.id)
		previous = rate
		counted += 1
	assert_eq(counted, RealmDefaults.ladder().size(), "the whole ladder was walked")


## R1 is the neutral rate: it is ordinal 0, so `rate_step()^0` is exactly 1.0. If it
## were not, every other number in the curve would be relative to a fiction and
## an unstarted path would silently contribute a fraction of a unit.
func test_the_first_realm_is_the_neutral_rate() -> void:
	assert_almost_eq(RealmRate.factor(FIRST), 1.0, "R1 is neutral", 0.0001)
	assert_almost_eq(RealmRate.factor(FIRST), RealmRate.NEUTRAL, "R1 equals NEUTRAL", 0.0001)


## A rate must stay a rate, and the span must be the AUTHORED NUMBER rather than a
## consequence of how many realms the ladder happens to have.
##
## The span used to be `pow(RATE_STEP, size - 1)`, so the total was a function of ladder
## LENGTH: 1.776 at 30 realms, 1.99988 at 36, and 2.040 at 37 - which is to say adding
## seven realms took a gain past the ceiling a gain is held to, by arithmetic rather than
## by decision. `rate_step()` normalises the step over the transitions there are, so the
## span is `rate_span()` at every length and extending the ladder is not a balance edit
## (ADR 0268).
func test_the_span_is_the_authored_step_and_stays_a_gain() -> void:
	var realms := RealmDefaults.ladder().realms()
	var span := RealmRate.factor(realms[realms.size() - 1].id) / RealmRate.factor(realms[0].id)
	assert_almost_eq(
		span,
		pow(RealmRate.rate_step(), float(realms.size() - 1)),
		"the span is the step compounded over the ladder",
		0.0001
	)
	assert_almost_eq(
		span,
		RealmRate.rate_span(),
		"and the span is the authored number, whatever the ladder's length",
		0.0001
	)
	assert_eq(span < 2.0, true, "the whole ladder is under 2x, not a magnitude (%s)" % span)
	assert_eq(span > 1.0, true, "and it still rises, or cultivation stops paying")


## The INVARIANCE itself, at ladder lengths that are not the shipped one.
##
## `RealmDefaults.register_realms` really can lengthen the ladder, and doing that here
## would leave a mutated global behind for every suite that shares the process. So this
## proves the identity arithmetically instead - `rate_span()^(1/(n-1))` compounded back
## over `n-1` transitions - at the four lengths that matter: the shipped one, the two
## that used to breach the ceiling, and a hundred realms.
func test_the_span_is_the_authored_number_at_every_ladder_length() -> void:
	var authored := RealmRate.rate_span()
	assert_eq(authored < 2.0, true, "the authored span is a gain, not a magnitude (%s)" % authored)
	# Every probed step must stay inside the AUTHORED work-budget ceiling. That is the
	# claim the design rests on, so it is asserted rather than left to the derivation:
	# `ln(step) = ln(span)/(n-1)` has a positive numerator, so a LONGER ladder always
	# moves the step AWAY from the ceiling and only a shorter one can walk up onto it.
	var ceiling := _smallest_work_step()
	var previous := INF
	# 0 extra realms (the shipped ladder), then the two lengths at which the old bare
	# step breached 2x, then a hundred-realm ladder. Typed so `size` infers as int.
	var extra_realms: Array[int] = [0, 6, 7, 70]
	for extra in extra_realms:
		var size := RealmRate.AUTHORED_LADDER_SIZE + extra
		var step := pow(authored, 1.0 / float(size - 1))
		assert_almost_eq(
			pow(step, float(size - 1)),
			authored,
			"%d realms span the authored number" % size,
			0.0001
		)
		assert_eq(step > 1.0, true, "%d realms is still a gain (%s)" % [size, step])
		assert_eq(step < previous, true, "%d realms takes a smaller step than a shorter one" % size)
		previous = step
		assert_eq(
			step <= ceiling + 0.000001,
			true,
			"%d realms stays inside the authored work step (%s vs %s)" % [size, step, ceiling]
		)


## An unknown or empty realm id degrades to neutral, never zero. A rate of 0 would
## delete the stat it scales instead of leaving it alone, and a missing entry must fail
## safe. All three paths reach this one function through their seam, so this also pins
## the behaviour every `*Provider._realm_factor` relies on for a stale rank.
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
			pow(RealmRate.rate_step(), float(ordinal)),
			"rate for %s is the step at its ordinal" % realm.id,
			0.0001
		)


## Every cultivation module READS the shared curve. This is the assertion that
## survives the collapse: parity of a number can only be checked between surfaces
## that still exist, and there is one surface left. What is still checkable — and
## what a re-private-isation would break — is that each path reaches for it.
##
## A path that grew its own rate under some other name would still produce the
## right answers today, so the value assertions above cannot see it. Reading the
## source can: `RealmRate.factor` must appear in each path, and the call sites
## named here are the ones that produce training gain and the provider
## contributions.
func test_every_path_reads_the_shared_curve() -> void:
	for path_dir in PATH_DIRS:
		var source := _module_source(path_dir)
		assert_ne(source, "", "%s is readable" % path_dir)
		assert_eq(
			source.contains("RealmRate.factor"),
			true,
			"%s reads the shared rate rather than a local one" % path_dir
		)


## The one place each path prices a unit of training, and the one place each
## provider resolves a realm's factor. Both are named exactly so a future edit
## cannot quietly route around the shared curve — a path whose `cultivate` stops
## reading it, or whose `_realm_factor` does, is a path that has stopped being
## priced in realm rate at all.
##
## `dual_cultivation/provider.gd` is the fourth row and it is the one this file
## exists for. It shipped a private `1.0 + ladder_ordinal * 0.05` in place of this
## call: no `RATE_STEP`, no `pow(`, no `*RealmProfile`, so the three structural pins
## above all read green over it. The pinned call site is the assertion that sees
## that shape — it is the only check here that fails when a provider computes its
## own per-realm multiplier instead of reading the shared one.
func test_the_training_and_provider_call_sites_read_the_shared_curve() -> void:
	var expected := {
		"qi_cultivation/training.gd": "RealmRate.factor(state.rank_id)",
		"qi_cultivation/provider.gd": "RealmRate.factor(state.rank_id)",
		"body_cultivation/training.gd": "RealmRate.factor(state.rank_id)",
		"body_cultivation/provider.gd": "RealmRate.factor(state.rank_id)",
		"mind_cultivation/training.gd": "RealmRate.factor(state.rank_id)",
		"mind_cultivation/provider.gd": "RealmRate.factor(state.rank_id)",
		"dual_cultivation/provider.gd": "RealmRate.factor(state.rank_id)",
	}
	for relative in expected:
		var source := FileAccess.get_file_as_string("res://src/modules/%s" % relative)
		assert_ne(source, "", "%s is readable" % relative)
		assert_eq(
			source.contains(String(expected[relative])),
			true,
			"%s prices through the shared rate" % relative
		)
	assert_eq(expected.size(), 7, "and all seven call sites are covered")


## The gain-side multiplier is read through ONE shared helper, and the pin is a source
## scan for the reason the fourth copy taught: a value assertion cannot see a path that
## multiplies its gain by a local number — `amount * factor * flow * 1.1` is numerically
## identical to the shared call today and free to drift tomorrow.
##
## The three paths are the ones `CultivationGain.scale_gain` documents. `dual_cultivation`
## is deliberately NOT on this list: it advances on its own rate stat
## (`DUAL_CULTIVATION_RATE`), and wiring that id is its own decision (DEF-0356 tracks it).
func test_the_three_paths_multiply_through_the_shared_gain_factor() -> void:
	var paths := [
		"qi_cultivation/training.gd",
		"body_cultivation/training.gd",
		"mind_cultivation/training.gd",
	]
	for relative in paths:
		var source := FileAccess.get_file_as_string("res://src/modules/%s" % relative)
		assert_ne(source, "", "%s is readable" % relative)
		assert_eq(
			source.contains("CultivationGain.scale_gain("),
			true,
			"%s multiplies its gain through the shared factor" % relative
		)
	assert_eq(paths.size(), 3, "and all three paths are covered")


## The shared factor must not grow a second curve of its own. It READS the ladder's span
## (`RealmRate.rate_span()`) and must never read the ladder itself: a per-realm read there
## would make the factor a function of the realm — compounding with `1.02^ordinal` — which
## is exactly what "the multiplier cannot outrun the ladder" forbids.
func test_the_gain_factor_reads_the_span_and_never_the_ladder() -> void:
	var source := FileAccess.get_file_as_string("res://src/core/cultivation_gain.gd")
	assert_ne(source, "", "the gain helper is readable")
	assert_eq(
		source.contains("RealmRate.rate_span()"),
		true,
		"the ceiling is derived from the shared span"
	)
	assert_eq(source.contains("RealmDefaults"), false, "and never reads the ladder itself")
	assert_eq(source.contains("const RATE_STEP"), false, "nor authors a step of its own")


## The three `*RealmProfile` classes are gone and stay gone. Copying an old
## `realm_profile.gd` back is the exact failure this closes: it would reintroduce
## three `class_name` declarations and, with them, a second place to retune. The
## check is for the CLASS NAME rather than the file name, so the copy cannot be
## renamed out of reach of it.
func test_no_cultivation_module_carries_a_realm_profile_class() -> void:
	for path_dir in PATH_DIRS:
		for class_name_found in _class_names(_module_source(path_dir)):
			assert_eq(
				class_name_found.ends_with("RealmProfile"),
				false,
				"%s declares %s, a second realm rate" % [path_dir, class_name_found]
			)


## No module may AUTHOR the curve. `RATE_STEP` and `NEUTRAL` are declared in
## `core/realm_rate.gd` and nowhere else, so the only way to add a second
## definition is to add one of these lines — and the build then goes red naming
## which module and which line.
##
## This is deliberately stricter than the guard that shipped with the seams, which
## allowed exactly one aliased `const RATE_STEP := RealmRate.RATE_STEP` per module
## on the argument that an alias authors nothing. An alias still leaves three more
## names to keep in step, and the whole point of the collapse is that there is one
## place to retune. `core/realm_rate.gd` is where the number lives.
func test_no_cultivation_module_authors_its_own_rate_step() -> void:
	for path_dir in PATH_DIRS:
		for declaration in _const_declarations(_module_source(path_dir)):
			var const_name := String(declaration).split(" ", false)[1]
			assert_eq(
				const_name in ["RATE_STEP", "NEUTRAL"],
				false,
				(
					"%s authors %s — the rate is authored in core/realm_rate.gd only"
					% [path_dir, declaration]
				)
			)


## `pow(` is banned by a different route to the same end: a path that re-derived
## the curve from some other step would be numerically identical today and free to
## drift tomorrow, and searching for the constant alone would not see it. This
## reads the WHOLE module directory rather than one file, so a private step
## authored beside `training.gd` — or in a new `rates.gd` — is caught too.
func test_no_cultivation_module_derives_a_curve_of_its_own() -> void:
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
			assert_eq(
				FileAccess.get_file_as_string(path).contains("pow("),
				false,
				"%s derives no curve of its own" % path
			)


## The pin that finally GENERALISES, and the one to read first.
##
## A provider's only legitimate use of the shared ladder is `RealmRate.factor(rank_id)`.
## Anything else it reaches for is a per-realm number it computed for itself. This is
## the shape `dual_cultivation` had — `1.0 + RealmDefaults.ladder().index_of(rank_id) *
## 0.05` — and every pin above missed it, because the ordinal was an inline literal
## on an inline slope: no `RATE_STEP`, no `pow(`, no `*RealmProfile`, and the module
## carried no other rate to be inconsistent with. So the check that generalises is
## not "is there another copy of this curve" but "does a provider reach past
## `RealmRate` for a realm at all".
##
## Scoped to `provider.gd` on purpose, because the ladder index is a legitimate
## answer to a TRAVERSAL question: `ladder().next(rank_id)`, an acupoint unlock
## index, a breakthrough target. Those live in `advancement.gd`, `refusal.gd`, the
## seed classes and the `api.gd` facades, and this pin must not reach them. Only a
## provider turns a realm into a multiplier, so only a provider is held to this.
##
## Comments are stripped before the read: a docblock is allowed to name
## `RealmRate` and the ladder while explaining why it does not reach for one, and a
## guard that failed on the explanation would teach the next agent to write a worse
## one.
func test_no_path_provider_computes_a_rate_from_the_ladder_itself() -> void:
	for path_dir in PATH_DIRS:
		var path := "res://src/modules/%s/provider.gd" % path_dir
		var source := FileAccess.get_file_as_string(path)
		assert_ne(source, "", "%s is readable" % path)
		assert_eq(
			_code_only(source).contains("RealmDefaults.ladder()"),
			false,
			(
				(
					"%s reads the shared ladder — a provider's only per-realm factor is "
					+ "RealmRate.factor(rank_id), so a ladder read here is a rate of its own"
				)
				% path
			)
		)


## Source with every `#` comment line removed. Only whole-line comments: GDScript's
## `#` inside a string is not a comment, and pretending to parse it would make this
## guard a second parser to keep correct. This is a source-shape guard, and a
## multi-line string that hid a ladder read is a review finding, not a blind spot
## worth a parser here.
func _code_only(source: String) -> String:
	var kept: Array[String] = []
	for line in source.split("\n"):
		var stripped := String(line).strip_edges()
		if not stripped.begins_with("#"):
			kept.append(stripped)
	return "\n".join(kept)


## Every `class_name` a source file declares, as written.
func _class_names(source: String) -> Array[String]:
	return _declarations(source, "class_name")


## Every `const <NAME> ...` a source file declares, as written. Reading the source
## rather than the value is the point: an unexercised copy is invisible to a value
## comparison, and an unexercised copy is what drifts.
func _const_declarations(source: String) -> Array[String]:
	return _declarations(source, "const")


func _declarations(source: String, keyword: String) -> Array[String]:
	var found: Array[String] = []
	for line in source.split("\n"):
		var stripped := String(line).strip_edges()
		if stripped.begins_with("%s " % keyword):
			found.append(stripped)
	return found


## One cultivation module's whole source, every `.gd` file in it concatenated. The
## guards above are per-directory, not per-file: naming one file would let a
## private rate be added beside it.
func _module_source(path_dir: String) -> String:
	var joined := ""
	var dir := DirAccess.open("res://src/modules/%s" % path_dir)
	if dir == null:
		return joined
	for file_name in dir.get_files():
		var file := String(file_name)
		if file.ends_with(".gd"):
			joined += FileAccess.get_file_as_string("res://src/modules/%s/%s" % [path_dir, file])
	return joined


## `rate_step()` is authored, but the bound it must respect is not: it has to stay at or
## below the smallest per-realm step in the AUTHORED work budget, or the rate outruns the
## price of a breakthrough and the deep realms get cheap. The check this replaces compared
## it against a typed-in `1.05`, which is LOOSER than the data - it permitted a retune
## that broke qi's last transition.
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
	var smallest := _smallest_work_step()
	assert_eq(
		smallest < INF, true, "every authored ladder was walked, so the bound is a real number"
	)
	assert_eq(RealmRate.rate_step() > 1.0, true, "the rate is still a gain")
	assert_eq(
		RealmRate.rate_step() <= smallest + 0.000001,
		true,
		(
			"rate_step() %s outruns the authored work step %s at %s — the rate outruns the price"
			% [RealmRate.rate_step(), smallest, _tightest_at]
		)
	)


## Where `_smallest_work_step()` found its tightest step is recorded on `_tightest_at`
## so a failure names the path and transition, not just a ratio.
##
## The tightest per-realm step any of the three authored `progress_required` ladders
## prices a transition at. Factored out because the bound is now needed in two places:
## once against the shipped ladder's step, and once against each hypothetical length in
## `test_the_span_is_the_authored_number_at_every_ladder_length`.
##
## `INF` when nothing was walked, so a caller that forgot to check fails its own
## comparison loudly instead of silently passing against a sentinel.
func _smallest_work_step() -> float:
	var smallest := INF
	_tightest_at = ""
	var ladder := RealmDefaults.ladder().realms()
	for path_dir in SEED_PATH_DIRS:
		var budgets := _authored_budgets(path_dir)
		assert_eq(
			budgets.size(),
			RealmDefaults.ladder().size(),
			"%s authored a budget for every realm on the ladder" % path_dir
		)
		# The bound is over CONSECUTIVE ratios, so it is undefined under three entries;
		# the ladder always has far more.
		if budgets.size() < 3:
			continue
		for index in range(2, budgets.size()):
			var step := budgets[index] / budgets[index - 1]
			if step < smallest:
				smallest = step
				_tightest_at = ("%s %s->%s" % [path_dir, ladder[index - 1].id, ladder[index].id])
	return smallest


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
