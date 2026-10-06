extends TestCase

## The ADR 0022 shape test (ADR 0068: "Every new rate channel ships a SHAPE TEST
## asserting a FLAT modifier at a `0.0` baseline is non-zero").
##
## The defect class: `Stat.DAMAGE_REDUCTION` is FLAT with a `0.0` baseline and is
## deliberately ABSENT from `Stat.RATE_STATS`, because a `PERCENT` modifier on a
## `0.0`-baseline stat evaluates to `(0.0 + 0.0) * (1 + p) = 0.0` — a silent no-op that
## shipped on 44 items and was validated clean by a contract that was itself wrong.
##
## Every combat-owned rate id has the same baseline, and `Stat.RATE_STATS` cannot see any
## of them: it is hand-written over STATIC core ids. ADR 0022's cheaper guard is to
## derive membership from the baselines — `CombatStats.RATE_IDS` is combat's derivation,
## and this file is the test that keeps it honest.

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


# --- the shape itself -----------------------------------------------------------


func test_every_rate_id_has_a_zero_baseline() -> void:
	# The precondition for the whole defect class: without it there is nothing to
	# no-op. Asserted for every id, so a rate id added with a non-zero default is
	# refused here rather than reasoned about later.
	for id in CombatStats.RATE_IDS:
		assert_almost_eq(CombatStats.default_of(id), 0.0, "%s is a 0.0-baseline rate" % String(id))


func test_rate_ids_and_rate_defaults_are_the_same_set() -> void:
	# ADR 0022: "The cheap guard is to derive `RATE_STATS` membership from the
	# baselines." So the two tables must not be able to drift — a rate id with no default
	# reads 0.0 by accident rather than by decision, which is how the original bug hides.
	assert_eq(
		CombatStats.RATE_DEFAULTS.size(), CombatStats.RATE_IDS.size(), "one default per rate id"
	)
	for id in CombatStats.RATE_IDS:
		assert_eq(CombatStats.is_rate(id), true, "%s is rate-shaped" % String(id))
	for id in CombatStats.RATE_DEFAULTS.keys():
		assert_eq(CombatStats.RATE_IDS.has(id), true, "%s is in RATE_IDS" % String(id))


func test_every_rate_id_has_an_authored_flat_rate_modifier() -> void:
	# The one legal shape, per ADR 0068: "author `op: FLAT`, `unit: "rate"`, and add a
	# SHAPE TEST." `CombatStats.rate_modifier` is the single constructor, so this asserts
	# the factory cannot produce a shape that would no-op.
	for id in CombatStats.RATE_IDS:
		var modifier := CombatStats.rate_modifier(id, 0.25, &"test")
		assert_eq(modifier.op, Stat.Op.FLAT, "%s is authored FLAT" % String(id))
		assert_almost_eq(modifier.value, 0.25, "%s carries its value" % String(id))
		assert_eq(modifier.stat, id, "%s carries its own id" % String(id))


func test_a_flat_modifier_on_a_zero_baseline_rate_is_not_a_no_op() -> void:
	# The property the whole exercise is about, asserted END TO END on the real actor:
	# a FLAT rate modifier moves the derived value, where the same value authored as
	# PERCENT would move nothing at all.
	for id in CombatStats.RATE_IDS:
		var actor := CombatTestKit.actor(&"subject")
		actor.stats.add_modifier(CombatStats.rate_modifier(id, 0.25, &"test"))
		assert_almost_eq(
			actor.stats.derived(id), 0.25, "%s moves under a FLAT modifier" % String(id)
		)


func test_the_percent_no_op_is_real_and_is_why_the_shape_test_exists() -> void:
	# The negative control. If this ever stopped being true the defect class would be
	# gone and the shape test would be cargo cult — so it is asserted rather than
	# assumed, and the two together make the guard falsifiable.
	var id := CombatStats.PARRY_RATE
	var actor := CombatTestKit.actor(&"subject")
	actor.stats.add_modifier(StatModifier.new(id, Stat.Op.PERCENT, 5.0, &"test"))
	assert_almost_eq(
		actor.stats.derived(id), 0.0, "a PERCENT on a 0.0 baseline is the silent no-op"
	)
	var flat := CombatTestKit.actor(&"subject")
	flat.stats.add_modifier(CombatStats.rate_modifier(id, 5.0, &"test"))
	assert_almost_eq(flat.stats.derived(id), 5.0, "and a FLAT is not")


func test_no_combat_rate_id_is_in_core_rate_stats() -> void:
	# ADR 0068: "Do not try to add dynamic ids to `RATE_STATS`." Membership is derived
	# from the baselines here, so a combat id appearing in core's hand-written list would
	# be a second, disagreeing definition of the same property.
	for id in CombatStats.RATE_IDS:
		assert_eq(Stat.RATE_STATS.has(id), false, "%s is not in core's RATE_STATS" % String(id))


func test_no_combat_id_is_a_core_stat_id() -> void:
	# The ids are MINE, not core's. A collision would mean two owners of one string.
	#
	# Checked twice, because the two halves catch different things. The list comparison is
	# the cheap one; the PROBE is the one that matters, and it exists because core's derived
	# ids live in no list at all -- `Stat` declares `BASE_ATTRIBUTES` and `RATE_STATS` and
	# nothing else, so `Stat.PENETRATION` (derived as `spirit * 0.5`) was in neither.
	# `CombatStats.PENETRATION` was therefore declared as `&"penetration"` -- the same
	# string, a different quantity (a `[0, 1]` rate subtracted from an elemental
	# resistance) -- and every elemental resistance in the game silently read `0.0`.
	#
	# The probe is what a constant list can never be: a bare actor carries no provider and
	# no modifier, so a core-derived id reads non-zero and a combat-owned one reads exactly
	# 0.0. If core ever starts deriving one of these strings, this fails here.
	#
	# EVERY base attribute is set, and generously. `CombatTestKit.actor` gives an actor
	# PHYSIQUE and COMPREHENSION only, and core derives `Stat.PENETRATION` from `spirit` --
	# so probing that builder read `0.0` for the very id this check exists to catch and the
	# collision went GREEN. The base dict is walked from `Stat.BASE_ATTRIBUTES` so it cannot
	# fall behind core adding an attribute.
	var core_ids := Stat.BASE_ATTRIBUTES + Stat.RATE_STATS
	for id in CombatStats.ALL_IDS:
		assert_eq(core_ids.has(id), false, "%s does not collide with core" % String(id))
	# `ACCURACY` is the ONE deliberate exception to the probe below, and the exception IS
	# the point: ADR 0215 declared the id in BOTH layers so the hit pair has two reachable
	# spellings, and ADR 0877 made CORE derive it (`agility * 0.0015 + 0.005`). The probe
	# asserts "no other owner reaches a combat id"; a shared id cannot satisfy it and must
	# not, so the exception is named rather than the probe weakened.
	var generous := {}
	for id in Stat.BASE_ATTRIBUTES:
		generous[id] = 100.0
	var probe := Actor.new(&"probe", generous)
	probe.add_resource(ResourcePool.new(&"health", 100.0))
	for id in CombatStats.ALL_IDS:
		if id == CombatStats.ACCURACY:
			continue
		assert_almost_eq(
			probe.stats.derived(id),
			0.0,
			(
				(
					"%s is derived by nothing, so no other owner can reach it -- a non-zero here "
					% String(id)
				)
				+ "means core or a provider already owns this string"
			)
		)
	# The exception is LIVE, not inert, and the shared id is one string in both layers.
	assert_ne(
		probe.stats.derived(CombatStats.ACCURACY),
		0.0,
		"core derives the shared accuracy id (ADR 0877)"
	)
	assert_eq(CombatStats.ACCURACY, Stat.ACCURACY, "accuracy is one id in both layers")
	# And the negative control, so the probe is falsifiable rather than vacuous: the same
	# actor DOES derive a non-zero for core's own PENETRATION, which is precisely what the
	# loop above is comparing against. A probe that read 0.0 for everything would otherwise
	# look like a pass.
	assert_ne(probe.stats.derived(Stat.PENETRATION), 0.0, "core's own PENETRATION is non-zero here")


# --- the spine reads them -------------------------------------------------------


## ## ADR 0877. The spine reads parry as a FLAT DELTA: the defender's `parry.rate`
## against the ATTACKER's `parry.break`, zero at parity, and the suppress slot is the
## break half — fixing the wiring that read the attacker's own `parry.rate`.
func test_the_spine_reads_parry_as_a_flat_delta_over_the_break_half() -> void:
	var scale := _tuning.rate_scale
	var target := CombatTestKit.actor(&"target")
	target.stats.add_modifier(
		CombatStats.rate_modifier(CombatStats.PARRY_RATE, scale * 0.25, &"test")
	)
	# A quarter of the scale of parry above no break reads a quarter.
	assert_almost_eq(
		CombatStats.contest_of(
			CombatStats.PARRY_RATE, target, CombatStats.PARRY_BREAK, target, scale
		),
		1.0 / 4.0,
		"a quarter of the scale of advantage reads a quarter"
	)
	# The suppress half is `parry.break`: a break at or above the rate cancels the parry
	# outright, which is the yin-yang parity the ADR buys.
	var breaker := CombatTestKit.actor(&"breaker")
	breaker.stats.add_modifier(
		CombatStats.rate_modifier(CombatStats.PARRY_BREAK, scale * 0.75, &"test")
	)
	assert_almost_eq(
		CombatStats.contest_of(
			CombatStats.PARRY_RATE, target, CombatStats.PARRY_BREAK, breaker, scale
		),
		0.0,
		"a break at or above the rate cancels the parry"
	)
	# And the attacker's OWN `parry.rate` is NOT the suppress half: the same investment
	# in `parry.rate` leaves the parry standing, which is the wiring fix.
	var mimic := CombatTestKit.actor(&"mimic")
	mimic.stats.add_modifier(
		CombatStats.rate_modifier(CombatStats.PARRY_RATE, scale * 0.75, &"test")
	)
	assert_almost_eq(
		CombatStats.contest_of(
			CombatStats.PARRY_RATE, target, CombatStats.PARRY_BREAK, mimic, scale
		),
		1.0 / 4.0,
		"the attacker's own parry rate does not suppress -- only the break half does"
	)
	# End to end through the band roll: a quarter rate parries a quarter of the draws,
	# because the band compares one draw against the rate and nothing else scales it.
	var parried := 0
	var index := 0
	while index < 1000:
		var value := float(index) / 1000.0
		if (
			CombatBand
			. roll(_tuning, 1.0, 1.0 / 4.0, 0.0, CombatTestKit.CountingGenerator.new([value]))
			. parried
		):
			parried += 1
		index += 1
	# The count is a COUNT off the sweep, not the rate restated: the roll parries when
	# `r >= 1 - p`, so `p == 0.25` parries the draws from `0.75` up and the assertion
	# follows from the shape.
	assert_eq(parried, 250, "250 of 1000 draws parried, off the quarter rate")


func test_an_unstatted_defender_parries_and_blocks_nothing() -> void:
	# ADR 0068's own promised property: "an unstatted actor has `p_parry == p_block == 0.0`
	# and parries 0% of the time".
	var bare := CombatTestKit.actor(&"target")
	assert_almost_eq(CombatBand.rate_of(CombatStats.PARRY_RATE, bare, _tuning), 0.0, "no parry")
	assert_almost_eq(CombatBand.rate_of(CombatStats.BLOCK_RATE, bare, _tuning), 0.0, "no block")


func test_default_of_reads_neither_table_as_zero() -> void:
	# Total: an id this module has never heard of reads 0.0 rather than crashing a call
	# site that is asking a question about the future.
	assert_almost_eq(
		CombatStats.default_of(&"a_stat_that_does_not_exist"), 0.0, "an unknown id is 0.0"
	)
	assert_almost_eq(CombatStats.default_of(CombatStats.PARRY_RATE), 0.0, "a rate default")
	assert_almost_eq(CombatStats.default_of(CombatStats.REFLECT_DAMAGE), 1.0, "a non-rate default")
