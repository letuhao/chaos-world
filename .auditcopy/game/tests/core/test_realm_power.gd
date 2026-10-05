extends TestCase

## ADR 0050: the authored per-realm power table. What replaced the one power ladder is
## DATA, so these tests assert the properties the runtime depends on - one entry per
## realm, R1 at exactly 1.0, every realm strictly above the one below it, all finite,
## and the top of the ladder readable - and never a pasted number.
##
## That is deliberate. A pasted value is a balance decision frozen into a test, so a
## legitimate retune of the table would arrive as a red suite instead of as a reviewable
## one-line data edit. Read the table instead.


## The table is keyed by realm id, so it must name every realm on the ladder and nothing
## else. A realm added without an entry would silently scale as a mortal; a realm removed
## without dropping its entry would leave a number nothing reads.
func test_one_multiplier_per_realm_and_no_others() -> void:
	var realms := RealmDefaults.ladder().realms()
	for realm in realms:
		assert_eq(
			RealmDefaults.POWER.multipliers.has(realm.id), true, "realm %s has an entry" % realm.id
		)
	assert_eq(
		RealmDefaults.POWER.multipliers.size(), realms.size(), "no entry for a realm off the ladder"
	)


## A mortal is the unscaled baseline. If R1 is not 1.0 then every other number in the
## table is relative to a fiction, and `RealmScaling` would quietly nerf a starting actor.
func test_the_first_realm_is_unscaled() -> void:
	assert_eq(
		RealmDefaults.POWER.power_for(RealmDefaults.ladder().realms()[0].id),
		1.0,
		"R1 is exactly 1.0x"
	)


## The one property the table exists to hold: a breakthrough is never a power loss.
## A dip shipped silently once under ADR 0042, which is why this asserts every step and
## not just the endpoints.
func test_every_realm_outranks_the_one_below_it() -> void:
	var realms := RealmDefaults.ladder().realms()
	for index in range(1, realms.size()):
		assert_eq(
			realms[index].power > realms[index - 1].power,
			true,
			"realm %d (%s) outranks realm %d" % [index + 1, realms[index].id, index]
		)


## Non-finite or negative multipliers are the failure modes a hand edit can introduce
## and a machine edit cannot: NaN propagates into every stat silently, and a negative
## flips a stat's sign.
func test_every_multiplier_is_finite_and_positive() -> void:
	for realm in RealmDefaults.ladder().realms():
		var power := RealmDefaults.POWER.power_for(realm.id)
		assert_eq(is_finite(power), true, "realm %s is finite" % realm.id)
		assert_eq(power > 0.0, true, "realm %s is positive" % realm.id)


## The removed ladder reached 1.13e46 at R30. A bound is what stops an authored retune
## from producing a number no stat, save payload or UI row can carry.
func test_the_top_of_the_ladder_stays_readable() -> void:
	var realms := RealmDefaults.ladder().realms()
	assert_eq(
		realms[realms.size() - 1].power <= 1.0e6, true, "top of the ladder is at or below 1e6x"
	)


## Off the table means unscaled, never zero. A stat multiplier of 0 would delete the
## stat rather than leave it alone, and a missing entry must fail safe.
func test_an_unknown_realm_is_unscaled() -> void:
	assert_eq(RealmDefaults.POWER.power_for(&""), 1.0, "no realm at all")
	assert_eq(RealmDefaults.POWER.power_for(&"not_a_realm"), 1.0, "an id off the ladder")


## The field, not a second lookup. `RealmScaling` reads `RealmDef.power`; a consumer
## that reads the table itself would hold a private copy of the ladder's contract and
## the two would drift the first time a realm is added.
func test_realm_def_carries_the_table_value() -> void:
	for realm in RealmDefaults.ladder().realms():
		assert_eq(
			realm.power, RealmDefaults.POWER.power_for(realm.id), "%s reads the table" % realm.id
		)


## The property ADR 0042 bought with a curve and this table keeps as data: a higher realm
## is a BIGGER jump, not just a bigger number. The step escalates at every tier
## boundary, so a Transcendent arrival costs more than an Immortal one.
func test_the_step_escalates_at_every_tier_boundary() -> void:
	var realms := RealmDefaults.ladder().realms()
	for index in range(2, realms.size()):
		if realms[index].tier == realms[index - 1].tier:
			continue
		var crossing := realms[index].power / realms[index - 1].power
		var before := realms[index - 1].power / realms[index - 2].power
		assert_eq(
			crossing > before,
			true,
			"the step into %s is bigger than the step below it" % realms[index].id
		)


## Authored data has to be deterministic across a reload, or a save/reload could shift
## an actor's stats. The table is read from one file with no computation, and this is
## the assertion that would catch anything reintroducing one.
func test_the_table_is_the_same_after_a_ladder_round_trip() -> void:
	var before := RealmDefaults.ladder()
	var snapshot: Array[float] = []
	for realm in before.realms():
		snapshot.append(realm.power)
	var after := RealmDefaults.ladder()
	for index in after.realms().size():
		assert_eq(after.realms()[index].power, snapshot[index], "realm %d is stable" % index)
