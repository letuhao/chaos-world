extends TestCase

## ADR 0899: the soul block's three stats — a ceiling, a recovery rate, an anchor factor.
##
## Every baseline is the value the shipped code already used (`integrity` 100, no passive
## recovery, repair factor 1.0), so an actor with no contributions reads byte-for-byte the
## soul it read before the stats existed. These tests pin that neutrality AND the writes
## that make the sockets real.

var _actor: Actor
var _store: SoulWorldLedger


func setup() -> void:
	_store = SoulWorldLedger.new()
	SoulApi.set_store(_store)
	_actor = Actor.new()
	_actor.id = &"soul_stats_bearer"
	SoulApi.attach(_actor)


## The store is a process-wide static on the facade; a suite that leaves it installed lets the
## next suite read THIS suite's soul. Idempotent, and safe after an early return.
func teardown() -> void:
	_actor = null
	_store = null
	SoulApi.set_store(null)


# --- the neutral sockets ----------------------------------------------------------


func test_the_three_channels_publish_their_neutral_baselines() -> void:
	assert_almost_eq(_actor.stats.derived(SoulStats.SOUL_INTEGRITY), 100.0, "the shipped ceiling")
	assert_almost_eq(
		_actor.stats.derived(SoulStats.SOUL_RECOVERY), 0.0, "no passive recovery ships"
	)
	assert_almost_eq(_actor.stats.derived(SoulStats.SOUL_ANCHOR), 1.0, "the shipped repair factor")


func test_attach_is_idempotent_about_the_provider_too() -> void:
	# A second attach must not stack a second provider: `add_provider` appends unguarded, and
	# two providers would read 200 wherever one reads 100.
	SoulApi.attach(_actor)
	SoulApi.attach(_actor)
	assert_almost_eq(
		_actor.stats.derived(SoulStats.SOUL_INTEGRITY), 100.0, "one provider, one baseline"
	)


# --- the ceiling raises one way -----------------------------------------------------


func test_a_raised_ceiling_lets_repair_fill_past_the_authored_max() -> void:
	_actor.stats.add_modifier(
		StatModifier.new(SoulStats.SOUL_INTEGRITY, Stat.Op.FLAT, 50.0, &"test")
	)
	SoulApi.damage(_actor, 40, "test")
	var healed := SoulApi.repair(_actor, 1000, "test")
	assert_eq(
		int(healed.get("applied", 0)),
		90,
		"damage 40 of a 150 ceiling: one call fills to the RAISED ceiling, not the old 100"
	)
	assert_eq(int(SoulApi.soul(_actor).get("integrity", 0)), 150, "and the soul reads whole")
	assert_eq(
		int(SoulApi.soul(_actor).get("integrity_max", 0)), 150, "the ceiling was raised, once"
	)


func test_a_falling_ceiling_never_shrinks_a_soul() -> void:
	_actor.stats.add_modifier(
		StatModifier.new(SoulStats.SOUL_INTEGRITY, Stat.Op.FLAT, 50.0, &"test")
	)
	SoulApi.repair(_actor, 1000, "test")
	_actor.stats.add_modifier(
		StatModifier.new(SoulStats.SOUL_INTEGRITY, Stat.Op.FLAT, -100.0, &"test")
	)
	# ONE WAY: the ceiling the soul already reached stays reached. Falling below a life it
	# survived would be a second death the rules did not ask for.
	assert_eq(int(SoulApi.soul(_actor).get("integrity_max", 0)), 150, "the ceiling does not shrink")
	assert_eq(int(SoulApi.soul(_actor).get("integrity", 0)), 150, "and neither does the soul")


# --- recovery is explicit periods ---------------------------------------------------


func test_recovery_refuses_without_a_rate_and_reads_periods_when_one_exists() -> void:
	var refused := SoulApi.recover(_actor, 5)
	assert_eq(String(refused.get("reason", "")), "no_recovery", "no rate, no passive repair")
	SoulApi.damage(_actor, 30, "test")
	_actor.stats.add_modifier(StatModifier.new(SoulStats.SOUL_RECOVERY, Stat.Op.FLAT, 2.0, &"test"))
	var healed := SoulApi.recover(_actor, 5)
	assert_eq(int(healed.get("restored", 0)), 10, "two per period over five periods")
	assert_eq(
		int(SoulApi.soul(_actor).get("integrity", 0)), 80, "and the soul moved by exactly that"
	)


func test_recovery_refuses_a_non_positive_period_count() -> void:
	assert_eq(
		String(SoulApi.recover(_actor, 0).get("reason", "")), "no_periods", "a zero ask is refused"
	)


# --- the anchor factor ---------------------------------------------------------------


func test_the_anchor_factor_is_neutral_without_the_stat_and_reads_it_with_one() -> void:
	var bare := Actor.new()
	assert_almost_eq(SoulApi.anchor_factor(bare), 1.0, "no provider: the shipped factor")
	_actor.stats.add_modifier(StatModifier.new(SoulStats.SOUL_ANCHOR, Stat.Op.FLAT, 0.5, &"test"))
	assert_almost_eq(SoulApi.anchor_factor(_actor), 1.5, "the stat IS the multiplier")
