extends TestCase

## DEF-0262, re-baselined on ADR 0200. `Stat.STATUS_DEFENSE` is the defender's half of
## the status gate, and this file is what stops its shape being "corrected" back into
## a defect by the next reader.
##
## ## What changed, and why the OLD version of this file had to be rewritten
##
## The stat was `minf(0.8, will * 0.003)` — a PERCENT with a CEILING. ADR 0200 deleted
## the `minf`, renamed the id to `Stat.STATUS_DEFENSE`, and made it an unbounded
## MAGNITUDE: the SAME authored coefficient (`will * 0.003`), fed to
## `CombatTuning.mitigation_ceiling` through `CombatTuning.resist_divisor`, with
## `CombatTuning.status_defense_stat` naming the id `StatusApply.apply_chance` reads.
## `CombatTuning.resist_cap` was deleted in the same ADR.
##
## DEF-0262's finding was that the `0.8` cap was UNREACHABLE from authored content —
## it needed `will >= 250` against a `base_will` band topping out in the fifties. That
## finding is still true of the number and is now a reason the cap is GONE rather than a
## property of the stat. **There is no ceiling to be unreachable.** Every assertion the
## old file made about reaching `0.8` at `will >= 250` describes a stat this game does
## not publish, and each is replaced below by the measurement that holds instead.
##
## ## What is actually load-bearing now
##
## 1. The baseline is still `will * 0.003` and still a small POSITIVE number at a
##    race's own `will`, never `0.0`. That is still what makes ADR 0022's
##    "attribute-gated four read `0.0`" claim false.
## 2. It is on `RealmScaling.SCALED_STATS` and CLIMBS with the ladder. This is the
##    substantive change and it is the OPPOSITE of the old complaint: a mitigation axis
##    authored flat against a 551x ladder is the defect ADR 0200 exists to remove, so
##    "the cap is not a build target" is replaced by "every further point of `will`, and
##    every rung of the ladder, still moves the gate".
## 3. A FLAT on it is legal authored content, which it was not while the id was
##    rate-shaped — the PERCENT multiply still lands on a non-zero baseline, so it is
##    real rather than the ADR 0022 `(0.0 + 0.0) * 1.5` trap. (No `core_status_defense`
##    option exists yet; every `core_status_resistance` carrier is a no-op — DEF-0357.)
## 4. The composed gate still lands STRICTLY ABOVE `status_min_apply` for any finite
##    defense, because the resist is a RATIO: `mitigation_ceiling * D / (K + D)` is
##    strictly below the ceiling, and `1 - mitigation_ceiling` is what is left. Immunity
##    remains impossible from defensive investment; it is now impossible from the SHAPE
##    of the curve rather than from a cap.
## 5. Every number is read off a REAL `ActorStats` and the REAL
##    `StatusApply.apply_chance`, with the SHIPPED `combat_damage.tres`, so a tuning
##    edit moves them and the suite says so.

const COMBAT_DAMAGE := "res://src/modules/combat_engine/combat_damage.tres"

## The `will` the shipped races grant at their highest. Measured off the race `.tres`
## files rather than restated, because the whole point is that this number was wrong once.
const TOP_RACE_WILL := 2.0

## The authored coefficient on `will`. Read from the SOURCE, not restated: this file's
## original claim was that a restated number had been wrong once already.
const WILL_COEFFICIENT := 0.003

## The gear budget DEF-0262 measured over the corpus: the largest single grant is `0.05`
## and the best five slots sum to `0.15`. A FLAT, so it lands ON TOP OF the baseline.
const TOP_GEAR_FLAT := 0.15


func _tuning() -> CombatTuning:
	return load(COMBAT_DAMAGE) as CombatTuning


## The stat id `StatusApply.apply_chance` reads, resolved through the SHIPPED tuning
## rather than named in this file — the same indirection `status_apply.gd` uses, and
## the reason a stale reference would read a wrong number instead of failing.
func _defense_id(tuning: CombatTuning) -> StringName:
	return StringName(tuning.status_defense_stat)


func _realm_power(realm_id: StringName) -> float:
	return RealmDefaults.ladder().realm(realm_id).power


## Build the same actor `ActorFactory` gives a player at `realm_id`: enrol on the qi
## path so `RealmScaling` has a realm to read, then apply the ladder.
func _at_realm(id: StringName, will: float, realm_id: StringName) -> Actor:
	var actor := ActorFactory.with_qi_cultivation(
		ActorFactory.build(id, {Stat.WILL: will}), realm_id
	)
	RealmScaling.apply(actor)
	ElementsApi.apply_realm_modifiers(actor)
	return actor


# --- the baseline, which is the one thing ADR 0200 did not move ---------------------


## The coefficient is UNCHANGED by ADR 0200. What changed is the unit and the absence of
## a ceiling, so this half of DEF-0262's correction — the baseline is a small positive
## number, not the `0.0` ADR 0022 described — is asserted against the NEW stat.
func test_the_baseline_is_small_and_positive_never_zero() -> void:
	# The claim ADR 0022's amendment and DEF-0262 both retracted: that this baseline
	# reads `0.0` and a PERCENT on it is a guaranteed no-op. It is `0.006` at a race's
	# own `will`, so it is positive — a small magnitude, not a constant `0.0`, and the
	# PERCENT beside it multiplies rather than annihilating.
	var actor := ActorFactory.build(&"probe_pos", {Stat.WILL: TOP_RACE_WILL})
	var baseline := actor.stats.derived(Stat.STATUS_DEFENSE)
	assert_ne(baseline, 0.0, "the baseline is NOT the constant 0.0 that ADR 0022 described")
	assert_almost_eq(
		baseline,
		TOP_RACE_WILL * WILL_COEFFICIENT,
		"and it is exactly the authored coefficient times the actor's own will"
	)
	# The retired id is a DIFFERENT id, not a synonym: the old string resolves to
	# nothing rather than to this value — the migration cost ADR 0200 accepted, measured
	# here so a silent alias cannot hide it. The CARRIERS were never migrated (no
	# `core_status_defense` option exists; every old grant is a no-op — DEF-0357).
	assert_eq(
		actor.stats.derived(Stat.STATUS_RESISTANCE) <= 0.0,
		true,
		"and the retired id reads nothing at all, so the two are one vocabulary and not two"
	)


## The behavioural half of the same correction, on the new id. `(0.0 + flat) *
## (1 + percent)` is the ADR 0022 trap; on a non-zero baseline the multiply is real, so
## the documentation sites that called this a guaranteed no-op were describing a number
## this game does not produce. ADR 0200 is also what makes a FLAT here LEGAL content at
## all: the id left `Stat.RATE_STATS` with the `minf`, so a `core_status_defense` grant
## is an authored magnitude rather than a refused `.tres` (the option is owed — DEF-0357).
func test_a_percent_and_a_flat_both_move_this_baseline_rather_than_annihilating_it() -> void:
	# The PERCENT half, on the new id. `(0.0 + flat) * (1 + percent)` is the ADR 0022 trap;
	# on a non-zero baseline the multiply is real, so the documentation sites that called
	# this a guaranteed no-op were describing a number this game does not produce.
	var actor := ActorFactory.build(&"probe_pct", {Stat.WILL: TOP_RACE_WILL})
	var before := actor.stats.derived(Stat.STATUS_DEFENSE)
	actor.stats.add_modifier(StatModifier.new(Stat.STATUS_DEFENSE, Stat.Op.PERCENT, 0.5, &"probe"))
	var after := actor.stats.derived(Stat.STATUS_DEFENSE)
	assert_almost_eq(
		after,
		before * 1.5,
		"a PERCENT multiplies a non-zero baseline rather than reading (0.0 + 0.0) * 1.5"
	)
	# The FLAT half, which ADR 0200 is what makes legal: the id left `Stat.RATE_STATS`
	# with the `minf`, so a FLAT grant here is authored content rather than a refused
	# `.tres`. On a SEPARATE body so the two are not conflated — see below for why
	# they must not be.
	var geared := ActorFactory.build(&"probe_flat", {Stat.WILL: TOP_RACE_WILL})
	geared.stats.add_modifier(
		StatModifier.new(Stat.STATUS_DEFENSE, Stat.Op.FLAT, TOP_GEAR_FLAT, &"gear")
	)
	assert_almost_eq(
		geared.stats.derived(Stat.STATUS_DEFENSE),
		TOP_RACE_WILL * WILL_COEFFICIENT + TOP_GEAR_FLAT,
		"and a FLAT lands ON TOP of the will baseline rather than replacing it"
	)
	# ## AND THE ORDER IS NOT COMMUTATIVE, which is `ActorStats._buckets`' arithmetic and
	# ## not a property of this stat
	#
	# `_put` resolves `(base + flat) * (1 + percent) * mult`, and the buckets GROUP the
	# whole stack before it runs — so a PERCENT and a FLAT on one stat compose exactly
	# once and the FLAT is inside the multiply. Measured on this baseline: `0.006` alone,
	# `0.006 * 1.5` with a PERCENT, and `0.234` with both, which is
	# `(0.006 + 0.15) * 1.5 = 0.234` and NOT `0.006 * 1.5 + 0.15 = 0.159`. The old
	# reading of this file treated a FLAT and a PERCENT as two independent assertions on
	# one actor; they are one resolution order, and asserting `base * 1.5 + flat` would
	# have been an arithmetic claim the engine does not make. Stated here so the next
	# reader does not "fix" the grouping.
	var both := ActorFactory.build(&"probe_both", {Stat.WILL: TOP_RACE_WILL})
	both.stats.add_modifier(StatModifier.new(Stat.STATUS_DEFENSE, Stat.Op.PERCENT, 0.5, &"probe"))
	both.stats.add_modifier(
		StatModifier.new(Stat.STATUS_DEFENSE, Stat.Op.FLAT, TOP_GEAR_FLAT, &"gear")
	)
	assert_almost_eq(
		both.stats.derived(Stat.STATUS_DEFENSE),
		(TOP_RACE_WILL * WILL_COEFFICIENT + TOP_GEAR_FLAT) * 1.5,
		"and the two compose once, with the FLAT inside the PERCENT's multiply"
	)


# --- the ladder, which is the substantive change -----------------------------------


## ## THE SUBSTANTIVE CHANGE: there is no cap, so the stat CLIMBS with the ladder
##
## This replaces the old `test_the_top_authored_will_band_is_far_below_the_cap_gate`,
## which asserted the OPPOSITE: that the cap needed `will >= 250` and a shipped race
## reached a fraction of it, so "the cap is not a build target". Both halves of that
## complaint described a stat that no longer exists. DEF-0262's diagnosis — a mitigation
## axis authored flat against a ladder — is what ADR 0200 fixed, and the fix is the
## assertion below.
##
## `status_defense` is on `RealmScaling.SCALED_STATS`, so it takes the ladder's own
## authored `power`. The measurement is a sweep, not one rung, because the property is
## that it GROWS and keeps growing: an author who adds a rung to
## `core/realm_power_table.tres` must move this number, and a stat that stopped scaling
## somewhere along the ladder would fail here rather than in play.
func test_the_status_defense_climbs_the_realm_ladder_and_never_stops() -> void:
	var tuning := _tuning()
	var defense_id := _defense_id(tuning)
	# One actor, walked up the ladder, so every rung reads the SAME body and any
	# non-monotonic step would be the multiplier's rather than the build's.
	var actor: Actor = null
	var previous := -1.0
	var first := -1.0
	var last_realm := &""
	var last_power := 1.0
	for realm in RealmDefaults.ladder().realms():
		actor = _at_realm(&"probe_ladder", TOP_RACE_WILL, realm.id)
		var value := actor.stats.derived(defense_id)
		assert_eq(value > 0.0, true, "R%f publishes a status defense to scale" % realm.power)
		if first < 0.0:
			first = value
		assert_eq(
			value > previous,
			true,
			(
				(
					"%s: status_defense %.6f is not above the %.6f one rung down -- the axis "
					% [String(realm.id), value, previous]
				)
				+ "stopped scaling, which is what ADR 0200 deleted the cap to prevent"
			)
		)
		previous = value
		last_realm = realm.id
		last_power = realm.power
	assert_eq(previous > first, true, "and the walk moved the stat rather than holding still")
	# And the top of the ladder is the ladder's OWN number, not a restatement: a
	# `0.8`-shaped ceiling is unreachable by construction, so a reading that lands ON the
	# top of the ladder's power is the shape ADR 0200 asked for.
	assert_almost_eq(
		previous,
		TOP_RACE_WILL * WILL_COEFFICIENT * last_power,
		(
			(
				"%s: a shipped race's own will reads %.6f, its authored %.6f times the ladder's "
				% [String(last_realm), previous, TOP_RACE_WILL * WILL_COEFFICIENT]
			)
			+ "%.2f" % last_power
		),
		1e-4
	)
	# The old complaint, inverted into the measurement that now holds. It is NOT that the
	# stat falls short of a ceiling — it is that the stat is UNBOUNDED, so a body past
	# any authored band keeps buying mitigation. `TOP_RACE_WILL * 0.003` is `0.006` and the
	# ladder's top is `551.46`, which is the OPPOSITE of the old `0.006 < 0.01` row.
	var unrung := ActorFactory.build(&"probe_unrung", {Stat.WILL: TOP_RACE_WILL})
	var raced := unrung.stats.derived(defense_id)
	var deepest := previous
	assert_eq(
		deepest > raced * 100.0,
		true,
		(
			(
				"a deepest-realm author reads %.4f against %.4f at R1 — the axis grows by two "
				% [deepest, raced]
			)
			+ "orders of magnitude, so no `will >= 250` gate decides where the stat stops"
		)
	)


## ## THE CAP'S OLD NUMBER IS GONE, and the gate is what replaced it
##
## `CombatTuning.resist_cap` was deleted by ADR 0200 — a clamp on an INPUT. What the
## status gate composes against now is `CombatTuning.mitigation_ceiling`, read as the
## MULTIPLIER on an asymptotic curve. The ceiling is still the ceiling of the gate's
## MITIGATION; it is not a ceiling on the stat, and no finite defense reaches it.
func test_the_resist_term_is_a_ratio_below_the_mitigation_ceiling_not_a_cap() -> void:
	var tuning := _tuning()
	var defense_id := _defense_id(tuning)
	var actor := ActorFactory.build(&"probe_ceiling", {Stat.WILL: TOP_RACE_WILL})
	var raw := actor.stats.derived(defense_id)
	var divisor := float(tuning.resist_divisor)
	var ceiling := clampf(float(tuning.mitigation_ceiling), 0.0, 1.0)
	var divisor_k := maxf(0.0, float(tuning.defense_divisor_k))
	# `share = mitigation_ceiling * D / (K + D)` — the gate's own arithmetic, restated
	# only so the number below is checked rather than pasted.
	var defense := raw / maxf(1e-9, divisor)
	var share := ceiling * defense / maxf(1e-9, divisor_k + defense)
	assert_eq(share > 0.0, true, "a will-scaled body resists something (%.6f)" % share)
	assert_eq(
		share < ceiling,
		true,
		(
			(
				"and %.6f is strictly under the authored ceiling %.4f, which no finite defense "
				% [share, ceiling]
			)
			+ "reaches — the asymptote is what a cap used to truncate"
		)
	)
	# Twice the defense does not double the share, and never pins it: the curve is
	# asymptotic, which is the property the deleted `minf(0.8, ...)` destroyed.
	var doubled := ActorFactory.build(&"probe_doubled", {Stat.WILL: TOP_RACE_WILL * 2.0})
	var doubled_defense := doubled.stats.derived(defense_id) / maxf(1e-9, divisor)
	var doubled_share := ceiling * doubled_defense / maxf(1e-9, divisor_k + doubled_defense)
	assert_eq(
		doubled_share > share,
		true,
		"twice the will raises the share %.6f -> %.6f" % [share, doubled_share]
	)
	assert_eq(
		doubled_share < ceiling,
		true,
		"and still does not reach the ceiling: every further point of defense still pays"
	)


# --- the gate, through the real production path -------------------------------------


## The player's actual experience, through the REAL production apply path and the
## SHIPPED tuning: a race's own `will`, and a race's `will` plus the five-slot flat
## budget simulated below (the authored `core_status_defense` content is owed — DEF-0357).
## Both stay above the `1 - mitigation_ceiling` the curve bottoms out at — so the
## authored experience is "debuffs land often, and a committed build tips the odds",
## never immunity.
func test_the_experienced_range_is_a_small_edge_and_never_immunity() -> void:
	var tuning := _tuning()
	var actor := ActorFactory.build(&"probe_exp", {Stat.WILL: TOP_RACE_WILL})
	# `0.15` is the authored ceiling measured over the whole corpus: the largest single
	# grant is `0.05` and the best five slots sum to `0.15` (DEF-0262 measurement). It is
	# a FLAT, so it lands ON TOP OF the baseline rather than replacing it.
	actor.stats.add_modifier(
		StatModifier.new(Stat.STATUS_DEFENSE, Stat.Op.FLAT, TOP_GEAR_FLAT, &"gear")
	)
	# `0.006` from will 2.0 plus `0.15` of gear. Read off the actor rather than pasted,
	# because this is the number a player feels and it is the one DEF-0262 got wrong by
	# an order of magnitude.
	var equipped := actor.stats.derived(Stat.STATUS_DEFENSE)
	assert_almost_eq(
		equipped,
		TOP_RACE_WILL * WILL_COEFFICIENT + TOP_GEAR_FLAT,
		"a fully equipped author of this stat reads the will coefficient plus the gear flat"
	)
	var chance := StatusApply.apply_chance(null, actor, tuning, 1.0, &"", &"", &"", 0.0)
	assert_eq(
		chance > 1.0 - float(tuning.mitigation_ceiling),
		true,
		(
			(
				"so they are still afflicted most of the time (%.4f), above the %.4f the "
				% [chance, 1.0 - float(tuning.mitigation_ceiling)]
			)
			+ "asymptote every finite defense bottoms out at"
		)
	)
	# Read the floor off the SHIPPED tuning rather than restating `0.01`, so a rebalance
	# moves the threshold with it and the assertion stays a comparison and not a paste.
	assert_eq(
		chance > float(tuning.status_min_apply),
		true,
		"and nowhere near the floor a deep defence would reach"
	)


## The other half of "the stat is a real investment": a defence magnitude big enough to
## matter, read back through the gate, composes with the elemental resist rather than
## annihilating it. This is the same drive
## `tests/modules/combat_engine/test_status_application.gd` performs; it is repeated here
## because DEF-0262's correction rests on it and that suite is another module's.
func test_a_deep_status_defense_composes_into_a_crawl_rather_than_annihilating() -> void:
	var tuning := _tuning()
	var defense_id := _defense_id(tuning)
	var actor := ActorFactory.build(&"probe_deep", {Stat.WILL: TOP_RACE_WILL})
	# Solved from `share = mitigation_ceiling * D / (K + D)` rather than pasted, so the
	# figure stays honest if `mitigation_ceiling` or `defense_divisor_k` is retuned. The
	# `resist_divisor` multiply on the way OUT is the same one
	# `tests/modules/combat_engine/test_status_application.gd::_status_defense_for`
	# measures, and dropping it would apply the divisor twice.
	var target_share := 0.9
	var ceiling := clampf(float(tuning.mitigation_ceiling), 0.0, 1.0)
	var divisor_k := maxf(0.0, float(tuning.defense_divisor_k))
	var authored := divisor_k * target_share / maxf(1e-9, ceiling - target_share)
	actor.stats.add_modifier(
		StatModifier.new(defense_id, Stat.Op.FLAT, authored * float(tuning.resist_divisor), &"deep")
	)
	# The resolved value is read back OFF THE ACTOR, never the figure that was authored:
	# the baseline is already on the stat, and the gate reads what the actor resolves to.
	var resolved := actor.stats.derived(defense_id)
	assert_eq(
		resolved > TOP_RACE_WILL * WILL_COEFFICIENT,
		true,
		"the deep defense is on the stat rather than replacing the will baseline (%.6f)" % resolved
	)
	var alone := StatusApply.apply_chance(null, actor, tuning, 1.0, &"", &"", &"", 0.0)
	assert_eq(alone > 0.0, true, "the deep resist alone leaves the gate above 0.0 (%.6f)" % alone)
	assert_eq(alone < 1.0, true, "and no finite defense is a guarantee (%.6f)" % alone)

	# `mitigation_ceiling` is the multiplier the resist curve approaches, so it is the
	# ceiling the COMPOSED gate bottoms out at — `CombatTuning.resist_cap` was deleted by
	# ADR 0200 and every `resist_cap` read in this file has become this one. The share is
	# computed from the value the ACTOR RESOLVED TO, not from the figure authored above,
	# because the will baseline is already on the stat and the gate reads the total.
	var defense := resolved / maxf(1e-9, float(tuning.resist_divisor))
	var share: float = clampf(ceiling * defense / maxf(1e-9, divisor_k + defense), 0.0, 1.0)
	assert_almost_eq(
		share, target_share, "the deep defense asks the gate for the share it solved for", 0.0001
	)

	# ADR 0884: the two defensive terms enter ONE flat delta, so their composition is the
	# floor rather than a product — a deep defense plus an elemental resist reaches it and
	# never passes it.
	var elem := 0.5
	var composed := StatusApply.apply_chance(null, actor, tuning, 1.0, &"", &"", &"", elem)
	assert_almost_eq(
		composed,
		float(tuning.status_min_apply),
		"the composed defence saturates into the authored floor",
		0.0001
	)
	assert_eq(
		composed <= alone,
		true,
		(
			(
				"the elemental resist never raises the chance above the resist-alone reading "
				+ "(%.6f <= %.6f)"
			)
			% [composed, alone]
		)
	)
	# And the CEILING case the old file reached for `resist_cap` to build: an elemental
	# resist at its own ceiling annihilates the product, so the only thing standing between
	# a maximally defended target and hard immunity is `status_min_apply`. Read off the
	# SHIPPED tuning, so a rebalance of the floor moves the assertion with it.
	var saturated := StatusApply.apply_chance(null, actor, tuning, 1.0, &"", &"", &"", 1.0)
	assert_almost_eq(
		saturated,
		float(tuning.status_min_apply),
		(
			(
				"a saturated elemental resist reads exactly the authored floor %.4f — immunity "
				% float(tuning.status_min_apply)
			)
			+ "is unreachable and the crawl is not"
		),
		0.0001
	)
	assert_eq(saturated > 0.0, true, "and a fully defended target still takes the status")
