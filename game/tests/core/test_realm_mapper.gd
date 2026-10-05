extends TestCase

## ADR 0268: a cultivation system keeps its OWN progression array and maps onto the
## shared standard ladder BY FORMULA, rather than being forced to share its length.
##
## A partial ladder is already legal — `modules/mods/module_registry.gd` validates the
## seeds it finds and explicitly does not require one per ladder realm — so a mod path
## of 12 steps is a legal thing to register. What was missing is the correspondence, and
## without it every caller guessed it by index and a path whose array was not 30 long
## misaligned silently. `RealmMapper` is that correspondence, and it lives in `core/`
## because `CultivationPathContract.validate_provider_source` and
## `test_realm_rate.gd::test_no_path_provider_computes_a_rate_from_the_ladder_itself`
## both refuse a provider that reads `RealmDefaults.ladder()` for itself.


## Equal lengths are the IDENTITY, which is the whole safety property: all five shipped
## paths author a 30-stage vocabulary against a 30-realm ladder, so nothing they do
## changes. If this ever fails, a shipped path is being re-indexed by the map.
func test_equal_lengths_are_the_identity() -> void:
	var realms := RealmDefaults.ladder().realms()
	for index in realms.size():
		assert_eq(
			RealmMapper.standard_ordinal(index, realms.size()),
			index,
			"%s keeps its own ordinal" % realms[index].id
		)
		assert_eq(
			RealmMapper.standard_realm_id(index, realms.size()),
			realms[index].id,
			"%s maps onto itself" % realms[index].id
		)


## A SHORTER path still reaches the top realm, and every one of its steps lands on a
## realm that exists. Anchoring both ends is what makes a 12-step ladder legal: it skips
## standard realms rather than stopping short of the top and leaving the deep content
## unreachable.
func test_a_shorter_path_anchors_both_ends_and_lands_on_the_ladder() -> void:
	var realms := RealmDefaults.ladder().realms()
	var short := 7
	assert_eq(RealmMapper.standard_realm_id(0, short), realms[0].id, "the first step is R1")
	assert_eq(
		RealmMapper.standard_realm_id(short - 1, short),
		realms[realms.size() - 1].id,
		"the last step is the top realm"
	)
	for step in short:
		var realm_id := RealmMapper.standard_realm_id(step, short)
		assert_eq(RealmDefaults.ladder().has(realm_id), true, "step %d lands on the ladder" % step)


## A LONGER path holds a realm across several of its steps instead of running off the
## end. This is the case that makes "its own array" safe in the other direction: a
## 90-step path is not asking the ladder for 90 realms.
func test_a_longer_path_reuses_realms_rather_than_running_off_the_end() -> void:
	var realms := RealmDefaults.ladder().realms()
	var long := realms.size() * 3
	var distinct: Dictionary = {}
	for step in long:
		var realm_id := RealmMapper.standard_realm_id(step, long)
		assert_eq(RealmDefaults.ladder().has(realm_id), true, "step %d lands on the ladder" % step)
		distinct[realm_id] = step
	assert_eq(
		distinct.size() < long,
		true,
		"a longer path reuses realms (%d distinct of %d steps)" % [distinct.size(), long]
	)
	assert_eq(RealmMapper.standard_realm_id(long - 1, long), realms[realms.size() - 1].id, "top")


## A step past the path's own top clamps onto the top realm rather than reading off the
## array. An advancement model that over-counts by one is a real bug; the map refuses it
## instead of returning an empty id the caller would price at neutral by accident.
func test_a_step_past_the_top_clamps_rather_than_falling_off() -> void:
	var realms := RealmDefaults.ladder().realms()
	var size := realms.size()
	assert_eq(
		RealmMapper.standard_ordinal(size, size),
		size - 1,
		"one step past the top holds the top realm"
	)
	assert_eq(RealmMapper.standard_ordinal(-1, size), -1, "a negative step maps nowhere")
	assert_eq(String(RealmMapper.standard_realm_id(-1, size)), "", "and yields no realm id")


## The map is a RATE projection, not a second curve: every step's factor IS
## `RealmRate.factor` on the realm it maps onto. A path that holds a copy of this
## arithmetic would be numerically identical today and free to drift, which is exactly
## what ADR 0116 found in `dual_cultivation`.
func test_the_rate_is_the_shared_curve_on_the_realm_the_step_maps_onto() -> void:
	var size := RealmDefaults.ladder().size()
	var probed: Array[int] = [0, 1, 10, size - 1]
	for step in probed:
		var realm_id := RealmMapper.standard_realm_id(step, size)
		assert_almost_eq(
			RealmMapper.factor_for_ordinal(step, size),
			RealmRate.factor(realm_id),
			"step %d is priced off the shared curve" % step,
			0.0001
		)
	assert_eq(
		RealmMapper.factor_for_ordinal(-1, size),
		RealmRate.NEUTRAL,
		"a step that maps nowhere is neutral, never zero"
	)


## A mapped realm INHERITS the standard realm's authored MAGNITUDE, so extending a path
## adds no fourth magnitude table (`RealmScaling` reads the `RealmDef.power` of the realm
## the actor's rank names). Asserted so a future "and let a path scale its own realms"
## cannot land without this suite saying the magnitude count went up.
func test_a_mapped_realm_carries_the_authored_magnitude_of_the_realm_it_maps_onto() -> void:
	var realms := RealmDefaults.ladder().realms()
	var top := realms[realms.size() - 1]
	assert_ne(top.power, 0.0, "the probe realm is powered, or the test proves nothing")
	assert_almost_eq(
		RealmRate.factor(top.id) / RealmRate.factor(realms[0].id),
		RealmRate.rate_span(),
		"and the rate across it is the shared span, not a per-path one",
		0.0001
	)
	assert_eq(top.power > realms[0].power, true, "magnitudes still rise with the ladder")
