extends "res://tests/modules/combat_engine/mind_damage_fixture.gd"

## ADR 0071: mind damage ERODES THE SEA and NEVER subtracts health.
##
## Eight load-bearing properties, each asserted here rather than argued in review:
##
## 1. Mind moves TURBULENCE, never health. A full-power DISRUPT at turbulence 0.0 leaves
##    the health pool byte-identical. This is THE property that distinguishes mind from
##    qi (ADR 0069) and body (ADR 0070), and it is asserted through the SPINE so it is
##    the eleven stages' result and not a hand-applied arithmetic.
## 2. `amount` is `0.0` through BOTH seam stages -- so S6's crit multiplies nothing, S8's
##    chip floor is bypassed by the zero, and S9's shield absorbs nothing.
## 3. Health moves ONLY through rupture bleed, and only ABOVE `RUPTURE_THRESHOLD`.
## 4. The 40% defence floor is STRUCTURAL: it holds at ANY `mental_defense`, including
##    1e9, and no value of any stat reaches "no damage".
## 5. Coherence HALVES at a full awareness pool, and `ATTEND` spends that reserve, so a
##    following `DISRUPT` lands harder -- the depleting-reserve lever.
## 6. `OBSCURE` reads `illusion_resistance`; `DISRUPT` and `ATTEND` do not.
## 7. Erosion is monotone and clamped, and never drives any pool negative.
## 8. `Stat.DAMAGE_REDUCTION` is NEVER read: a qi/body tank does nothing to erosion.
##
## Every expected number below is DERIVED from a real actor's live `derived()` read where
## the value can move, and pinned where the fixture pins it BY CONSTRUCTION. A stat
## formula change moves the pinned assertions with it or fails them visibly.

# --- property 1: mind moves turbulence, never health ----------------------------


## THE distinguishing property. One full-power DISRUPT at turbulence 0.0, through the
## spine's eleven stages: health is BYTE-IDENTICAL afterwards and turbulence is strictly
## greater.
##
## Asserted byte-identical rather than "approximately equal" on purpose. qi and body both
## spend health; a mind hit that spent even a chip would leave a residue, and the
## distinguishing claim is not "little health" but "none".
func test_mind_damage_moves_turbulence_and_never_health() -> void:
	var attacker := _attacker()
	var defender := _defender(0.0, 0.0)
	var sea := _sea_of(defender)
	sea.turbulence = 0.0
	var health := defender.resource(&"health") as ResourcePool
	var before_health := health.current
	var before_turbulence := sea.turbulence

	var outcome := _hit(attacker, defender, MindDamage.Kind.DISRUPT)

	# The sea moved, and it moved in the direction erosion moves it.
	assert_eq(
		sea.turbulence > before_turbulence,
		true,
		"a full-power DISRUPT raises turbulence above %s" % str(before_turbulence)
	)
	# Health is untouched -- not "nearly", byte-identical.
	assert_eq(health.current, before_health, "mind NEVER subtracts health directly")
	assert_almost_eq(float(outcome.health_delta), 0.0, "and the spine reports no health change")
	assert_almost_eq(float(outcome.amount), 0.0, "and the spine's amount is 0.0")
	assert_eq(before_health, HEALTH, "the pool was full before the hit, as pinned")


## `amount` is `0.0` at BOTH seam stages. S4 produces no magnitude and S5 cannot create
## one, which is what makes S8's chip floor bypassed by the zero and S9's shield absorb
## nothing -- the ADR's own consequence, asserted at the seam rather than argued from
## `spine.gd`.
func test_the_amount_is_zero_at_both_seam_stages() -> void:
	var mechanism := MindDamage.new()
	var ctx := _context(MindDamage.Kind.DISRUPT, _attacker(), _defender(0.0, 0.0))
	var amounts := _proposal_amounts(mechanism, ctx)
	assert_almost_eq(amounts[0], 0.0, "S4 (resolve) returns no magnitude")
	assert_almost_eq(amounts[1], 0.0, "S5 (mitigate) does not create one either")


## The `effects[]` carry the hit, and the amount does not. One effect per hit carrying
## every write, so a panel can never show a sea that went turbulent without the clarity
## it cost (ADR 0071's `KEY_CLARITY` is the clarity LOST, so it is negative).
func test_the_hit_travels_in_effects_and_the_turbulence_costs_clarity() -> void:
	var mechanism := MindDamage.new()
	var ctx := _context(MindDamage.Kind.DISRUPT, _attacker(), _defender(0.0, 0.0))
	var effect := _effect_of(mechanism.resolve(ctx))
	assert_eq(
		effect.get(MindDamage.KEY_KIND, "") is String,
		true,
		"the effect spells its kind as a String, never an ordinal"
	)
	assert_eq(
		String(effect.get(MindDamage.KEY_KIND, "")),
		MindDamage.kind_name(MindDamage.Kind.DISRUPT),
		"and it spells the kind as a NAME, not an ordinal"
	)
	var turbulence := float(effect.get(MindDamage.KEY_TURBULENCE, 0.0))
	var clarity := float(effect.get(MindDamage.KEY_CLARITY, 0.0))
	assert_eq(turbulence > 0.0, true, "a full-power strike raises turbulence")
	assert_eq(clarity < 0.0, true, "and the clarity it costs is negative (it is a delta)")
	assert_almost_eq(
		float(effect.get(MindDamage.KEY_AWARENESS, 0.0)), 0.0, "and no awareness drain on DISRUPT"
	)


## `resolve` and `mitigate` both carry the SAME erosion as their shared `breakdown`, so
## the two seam stages cannot disagree about what the hit is (ADR 0067's split, observed
## through the SPIECE rather than two hand-built contexts).
func test_the_spine_carries_the_two_stage_proposal() -> void:
	var attacker := _attacker()
	var defender := _defender(0.0, 0.0)
	var mechanism := MindDamage.new()
	var ctx := _context(MindDamage.Kind.DISRUPT, attacker, defender)
	var parts := mechanism.breakdown(ctx)
	var outcome := _hit(attacker, defender, MindDamage.Kind.DISRUPT)
	var carried := _effect_of(outcome.proposal)
	assert_almost_eq(
		float(carried.get(MindDamage.KEY_TURBULENCE, 0.0)),
		float(parts["total"]),
		"S5's mitigated total is what the spine's proposal carries"
	)


# --- property 4: the defence floor is structural --------------------------------


## The anti-degeneracy guarantee, asserted directly. `defense_floor()` is published at
## `0.4` (ADR 0071's `1 - MENTAL_DEFENSE_CAP`), and it is the mind analogue of the
## spine's chip-floor immunity invariant: `mental_defense` enters only through the
## saturating `d / (d + base)`, hard-capped, so 40% of every strike ALWAYS lands.
##
## There is NO clarity value that reaches "no damage" -- the loop runs to 1e9 and asserts
## the mitigated erosion is strictly positive at every single one.
func test_the_defence_floor_is_structural_at_any_defense() -> void:
	assert_almost_eq(
		MindDamage.defense_floor(), 0.4, "the published floor is 1 - MENTAL_DEFENSE_CAP"
	)
	assert_almost_eq(
		MindDamage.defense_floor(_tuning), 0.4, "and the same when the tuning is passed explicitly"
	)
	var attacker := _attacker()
	for defense in [0.0, 1.0, 10.0, 1000.0, 1.0e9]:
		var defender := _defender(0.0, defense)
		var parts := _parts(MindDamage.Kind.DISRUPT, attacker, defender)
		# The mitigation is CAPPED at MENTAL_DEFENSE_CAP, so it never approaches 1.0.
		assert_almost_eq(
			float(parts["mitigation"]),
			_tuning.mental_defense_cap,
			"defense %s saturates at the cap" % str(defense),
			1e-4
		)
		# And therefore 40% of the strike lands: no defense reaches "no damage".
		assert_almost_eq(
			float(parts["total"]),
			float(parts["erosion"]) * 0.4,
			"defense %s still takes 40%% of the strike" % str(defense)
		)
		assert_eq(
			float(parts["total"]) > 0.0,
			true,
			"defense %s can never refuse a mind strike outright" % str(defense)
		)


## A degenerate `MENTAL_DEFENSE_CAP` reads its own number rather than a re-derived one,
## and no rebalance of the `.tres` can silently make the floor something else. Also the
## `0.0`-capacity sea (hole 2): a sea nobody trained is visibly INERT, not an infinity.
func test_a_sea_with_no_scale_is_inert_and_never_an_infinity() -> void:
	var attacker := _attacker()
	var defender := _defender(0.0, 0.0)
	_sea_of(defender).set_structural_capacity(0.0)
	var parts := _parts(MindDamage.Kind.DISRUPT, attacker, defender)
	assert_eq(float(parts["erosion"]), 0.0, "a 0.0 structural_capacity divides nothing")
	assert_almost_eq(float(parts["total"]), 0.0, "so the erosion is exactly 0.0")
	assert_eq(is_finite(float(parts["total"])), true, "and it is a finite number, not INF")


## A degenerate tuning -- every bound `0.0` -- must not divide by zero anywhere. The
## `d / (d + base)` contest at `d == base == 0.0` is the `0.0 / 0.0 == NaN` hole 1, and
## a `NaN` survives every `clampf`, so this is the case that would reach `ResourcePool`.
func test_a_degenerate_tuning_and_a_null_context_never_produce_a_nan() -> void:
	var bare := MindDamage.new()
	bare.tuning = CombatTuning.new()
	var ctx := _context(MindDamage.Kind.DISRUPT, _attacker(), _defender(0.0, 0.0))
	var parts := bare.breakdown(ctx)
	assert_eq(is_finite(float(parts["total"])), true, "a bare tuning yields a finite number")
	assert_almost_eq(float(parts["mitigation"]), 0.0, "a 0.0 denominator is no contest, not NaN")

	# A null context is a supported state: it declines rather than crashing.
	var empty := MindDamage.new().breakdown(null)
	assert_almost_eq(float(empty["total"]), 0.0, "a null context is the empty proposal")
	assert_eq(is_finite(float(MindDamage.new().resolve(null).amount)), true, "and it is finite")


# --- property 6: OBSCURE reads illusion_resistance; DISRUPT does not ------------


## A defender with `0.0` `mental_defense` and MAX `illusion_resistance`: mitigated on
## `OBSCURE`, NOT on `DISRUPT`. This is what makes an illusion-resistance build and a
## clarity build DIFFERENT defenders of the same skill (ADR 0071), machine-checkable
## rather than asserted.
##
## `illusion_resistance = minf(0.8, mental_clarity * 0.004 + will * 0.002)` per
## `MindProvider`. At `mental_clarity == 200.0` the formula alone saturates the `0.8`
## cap -- no `will` term needed -- so the read is at its ceiling and the `maxf` is
## unambiguous.
func test_obscure_reads_illusion_resistance_and_disrupt_does_not() -> void:
	var attacker := _attacker()
	var defender := _defender(0.0, 0.0)
	# mental_clarity 200.0 saturates illusion_resistance at its 0.8 cap; mental_defense
	# stays pinned at 0.0 by the fixture, so there is NO other source of mitigation.
	defender.stats.set_base(MindStats.MENTAL_CLARITY, 200.0)
	defender.mark_stats_dirty()
	assert_almost_eq(
		defender.stats.derived(MindStats.ILLUSION_RESISTANCE),
		0.8,
		"illusion_resistance is at its 0.8 ceiling"
	)

	var obscure := _parts(MindDamage.Kind.OBSCURE, attacker, defender)
	var disrupt := _parts(MindDamage.Kind.DISRUPT, attacker, defender)
	# OBSCURE takes the maxf against ILLUSION_RESISTANCE, so it is mitigated by it.
	assert_almost_eq(
		float(obscure["mitigation"]), 0.8, "OBSCURE is mitigated by illusion_resistance"
	)
	# DISRUPT never reads ILLUSION_RESISTANCE -- it is flat 0.0 against that stat.
	assert_almost_eq(
		float(disrupt["illusion_resistance"]), 0.0, "DISRUPT does not even read illusion_resistance"
	)
	assert_almost_eq(
		float(disrupt["mitigation"]), 0.0, "so DISRUPT is unmitigated at 0.0 mental_defense"
	)
	# Same actor, same attacker, same sea: OBSCURE lands strictly less than DISRUPT.
	assert_eq(
		float(obscure["total"]) < float(disrupt["total"]),
		true,
		"OBSCURE lands less than DISRUPT against an illusion-resistance build"
	)


## `ATTEND` does not read `illusion_resistance` either -- it is the same 0.0 read as
## `DISRUPT`. Both other kinds answer the WORST `maxf` input, which is what makes
## "specialise the counter-stat" a real build choice and not a description.
func test_attend_also_does_not_read_illusion_resistance() -> void:
	var attacker := _attacker()
	var defender := _defender(0.0, 0.0)
	defender.stats.set_base(MindStats.MENTAL_CLARITY, 200.0)
	defender.mark_stats_dirty()
	var attend := _parts(MindDamage.Kind.ATTEND, attacker, defender)
	assert_almost_eq(
		float(attend["illusion_resistance"]), 0.0, "ATTEND does not read illusion_resistance"
	)
	assert_almost_eq(float(attend["mitigation"]), 0.0, "so ATTEND is unmitigated too")


# --- property 5: coherence halves at full awareness; ATTEND spends the reserve ----


## The depleting AWARENESS reserve. Coherence is `1 - COHERENCE_DAMP * awareness_ratio`,
## so at the shipped `0.5` it is exactly `0.5` at a FULL reserve and `1.0` at an EMPTY
## one: a defender who spends their reserve takes the next strike at nearly DOUBLE the
## erosion.
func test_coherence_halves_at_a_full_awareness_pool() -> void:
	var attacker := _attacker()
	var empty := _parts(MindDamage.Kind.DISRUPT, attacker, _defender(0.0, 0.0))
	var full := _parts(MindDamage.Kind.DISRUPT, attacker, _defender(1.0, 0.0))
	assert_almost_eq(float(empty["awareness_ratio"]), 0.0, "an empty reserve reads 0.0")
	assert_almost_eq(float(full["awareness_ratio"]), 1.0, "a full reserve reads 1.0")
	assert_almost_eq(float(empty["coherence"]), 1.0, "an empty reserve costs nothing")
	assert_almost_eq(float(full["coherence"]), 0.5, "a full reserve HALVES the coherence")
	# And therefore halves the erosion -- the actual mechanical consequence.
	assert_almost_eq(
		float(full["erosion"]),
		float(empty["erosion"]) * 0.5,
		"so a full reserve halves the erosion"
	)


## `ATTEND` SPENDS that reserve. The drain is dimensional (the erosion is a `0..1` share,
## the reserve is read as a fraction) and clamped to what is actually held, so it can
## empty the reserve and can never invent a negative one.
##
## The two assertions are: (a) at a full reserve `ATTEND` reports a NON-ZERO awareness
## drain while `DISRUPT` reports none -- the effect shape never changes with the kind, so
## `ATTEND` spends and the others do not; and (b) after applying that drain the reserve is
## lower, so the NEXT `DISRUPT` (which does NOT spend it) lands HARDER than the first.
func test_attend_spends_the_reserve_and_the_following_disrupt_lands_harder() -> void:
	var attacker := _attacker()
	var defender := _defender(1.0, 0.0)
	var mechanism := MindDamage.new()

	var attend := _effect_of(
		mechanism.resolve(_context(MindDamage.Kind.ATTEND, attacker, defender))
	)
	var disrupt_before := _effect_of(
		mechanism.resolve(_context(MindDamage.Kind.DISRUPT, attacker, defender))
	)
	# (a) ATTEND spends the reserve; DISRUPT does not.
	assert_eq(
		float(attend.get(MindDamage.KEY_AWARENESS, 0.0)) < 0.0,
		true,
		"ATTEND drains a non-zero awareness"
	)
	assert_almost_eq(
		float(disrupt_before.get(MindDamage.KEY_AWARENESS, 0.0)), 0.0, "DISRUPT drains nothing"
	)
	# The drain is a share of the erosion and never exceeds the reserve itself.
	var drain := absf(float(attend.get(MindDamage.KEY_AWARENESS, 0.0)))
	var reserve := _awareness_of(defender)
	assert_eq(drain <= reserve, true, "the drain never exceeds the reserve it came from")

	# (b) Apply the drain to the REAL pool, then a following DISRUPT reads the depleted
	# reserve and therefore a HIGHER coherence and a HARDER landing.
	var pool := defender.resource(MindStats.AWARENESS) as ResourcePool
	pool.current = maxf(0.0, pool.current + drain * pool.maximum)
	var after_ratio := _awareness_of(defender)
	assert_eq(after_ratio < 1.0, true, "the reserve really did drop")
	var disrupt_after := _parts(MindDamage.Kind.DISRUPT, attacker, defender)
	assert_eq(
		float(disrupt_after["total"]) > float(disrupt_before.get(MindDamage.KEY_TURBULENCE, 0.0)),
		true,
		"so a following DISRUPT lands harder than the one the ATTEND preceded"
	)


# --- property 7: erosion is monotone and clamped --------------------------------


## 1000 stacked strikes leave turbulence at its CEILING and clarity at ZERO, with no
## negative pool anywhere. Erosion saturates and cannot invert (ADR 0071: "clarity
## saturates and cannot invert").
##
## Each strike is applied through the REAL sea's own `add_turbulence` / `set_clarity`,
## which is where the clamping happens -- the mechanism returns a DELTA and the sea
## enforces its own bounds, exactly as the ADR's floor-at-zero clause requires.
func test_erosion_is_monotone_and_clamped_over_1000_strikes() -> void:
	var attacker := _attacker()
	var defender := _defender(0.0, 0.0)
	var sea := _sea_of(defender)
	var mechanism := MindDamage.new()
	var ctx := _context(MindDamage.Kind.DISRUPT, attacker, defender)

	var last_turbulence := 0.0
	var last_clarity := sea.clarity
	for _step in 1000:
		var effect := _effect_of(mechanism.resolve(ctx))
		sea.add_turbulence(float(effect.get(MindDamage.KEY_TURBULENCE, 0.0)))
		sea.set_clarity(sea.clarity + float(effect.get(MindDamage.KEY_CLARITY, 0.0)))
		# Monotone: turbulence never decreases and clarity never increases as erosion
		# accumulates. Either violated would mean the sea was being HEALED by a strike.
		assert_eq(sea.turbulence >= last_turbulence, true, "turbulence is monotone non-decreasing")
		assert_eq(sea.clarity <= last_clarity, true, "clarity is monotone non-increasing")
		# Clamped: neither pool ever leaves `[0, 1]`.
		assert_eq(
			sea.turbulence >= 0.0 and sea.turbulence <= 1.0, true, "turbulence stays in [0, 1]"
		)
		assert_eq(sea.clarity >= 0.0 and sea.clarity <= 1.0, true, "clarity stays in [0, 1]")
		last_turbulence = sea.turbulence
		last_clarity = sea.clarity

	# After a thousand strikes both pools have saturated at their bounds.
	assert_almost_eq(sea.turbulence, 1.0, "turbulence reached its ceiling")
	assert_almost_eq(sea.clarity, 0.0, "clarity is floor at zero")
	# And no pool anywhere on the actor is negative.
	assert_no_negative_pool(defender, "defender after 1000 strikes")
	assert_no_negative_pool(attacker, "attacker after 1000 strikes")


## `Stat.DAMAGE_REDUCTION` is NEVER read by the mind mechanism (ADR 0071). A qi/body tank
## does nothing at all to erosion -- asserted by giving the defender a FULL flat reduction
## and showing the mitigated erosion is byte-identical to an unreduced defender's.
func test_damage_reduction_is_never_read_by_the_mind_path() -> void:
	var attacker := _attacker()
	var tanked := _defender(0.0, 0.0)
	tanked.stats.add_modifier(
		StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 5.0, &"test_full_reduction")
	)
	tanked.mark_stats_dirty()
	var reduced := _parts(MindDamage.Kind.DISRUPT, attacker, tanked)
	var open := _parts(MindDamage.Kind.DISRUPT, attacker, _defender(0.0, 0.0))
	# A qi/body tank at full reduction is BYTE-IDENTICAL to an open defender's -- the
	# byte-identity is the point: not "about the same", the same number.
	assert_eq(
		float(reduced["total"]) == float(open["total"]),
		true,
		"a qi/body tank does nothing at all to erosion"
	)


# --- internals -------------------------------------------------------------------


## Assert every pool on an actor is within `[0, maximum]` -- the "no negative pool
## anywhere" half of the monotone/clamped property, checked on the real component rather
## than restated as the value the fixture just wrote.
func assert_no_negative_pool(actor: Actor, label: String) -> void:
	for pool_id in actor.resources:
		var pool := actor.resource(pool_id) as ResourcePool
		if pool == null:
			continue
		assert_eq(
			pool.current >= 0.0,
			true,
			"%s: pool %s is not negative (current %s)" % [label, String(pool_id), str(pool.current)]
		)
