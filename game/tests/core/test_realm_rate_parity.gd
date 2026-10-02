extends TestCase

## The three cultivation paths each carry a verbatim copy of `RATE_STEP` and the
## `factor(realm_id) = RATE_STEP^ordinal` formula. The copies are deliberate: a module may
## only reach another module through its `api.gd` facade, and the alternative — one
## shared curve — is the magnitude ladder this replaced.
##
## The cost of deliberate duplication is that nothing stops one path being retuned and
## the other two left behind. That drift is invisible: each path's own suite computes its
## expectation from its OWN constant (`pow(BodyRealmProfile.RATE_STEP, n)`), so a body
## retune breaks nothing in qi or mind, and mind had no profile suite at all. Three paths
## would then disagree about what a realm's training is worth, and the only symptom would
## be that the same realm is priced differently depending on which path you cultivate.
##
## So this test compares the three copies against EACH OTHER. It pins no literal: the
## number is free to move, but it must move in all three at once.

const FIRST := &"qi_refining"
const LAST := &"primordial_origin"


## Every path must price the same realm identically, at both ends of the ladder.
func test_the_three_paths_agree_on_the_rate() -> void:
	for realm_id in [FIRST, LAST]:
		var body := BodyRealmProfile.factor(realm_id)
		var qi := QiRealmProfile.factor(realm_id)
		var mind := MindRealmProfile.factor(realm_id)
		assert_almost_eq(body, qi, "body and qi agree on %s" % realm_id, 1e-9)
		assert_almost_eq(body, mind, "body and mind agree on %s" % realm_id, 1e-9)


## The constant itself is duplicated text in three files, so compare them directly too.
## A copy that is edited without being exercised — say a suite that stops calling it —
## would otherwise drift while every behavioural test still agreed with itself.
func test_the_rate_step_constant_is_identical_in_all_three() -> void:
	var steps := [
		BodyRealmProfile.RATE_STEP,
		QiRealmProfile.RATE_STEP,
		MindRealmProfile.RATE_STEP,
	]
	for step in steps:
		assert_eq(step, steps[0], "every path uses the same RATE_STEP")


## A rate must stay a rate. If this ever fails, a path has started tracking a magnitude
## again — which is what once made a single breakthrough worth more than everything else
## combined, no matter how deep you were.
func test_the_rate_stays_a_gain_across_the_whole_ladder() -> void:
	var span := BodyRealmProfile.factor(LAST) / BodyRealmProfile.factor(FIRST)
	assert_eq(span < 2.0, true, "the whole ladder is under 2x, not a magnitude")
	assert_eq(span > 1.0, true, "and it still rises, or cultivation stops paying")


## An unknown realm is neutral on every path. A path that disagreed here would let an
## off-ladder realm id change a rate on one path only.
func test_an_unknown_realm_is_neutral_on_every_path() -> void:
	for realm_id in [&"", &"not_a_realm"]:
		assert_eq(BodyRealmProfile.factor(realm_id), 1.0, "body is neutral for '%s'" % realm_id)
		assert_eq(QiRealmProfile.factor(realm_id), 1.0, "qi is neutral for '%s'" % realm_id)
		assert_eq(MindRealmProfile.factor(realm_id), 1.0, "mind is neutral for '%s'" % realm_id)
