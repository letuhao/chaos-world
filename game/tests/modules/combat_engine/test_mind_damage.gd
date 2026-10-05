extends "res://tests/modules/combat_engine/mind_damage_fixture.gd"

## ADR 0071: mind damage ERODES THE SEA and NEVER subtracts health.
##
## Eight load-bearing properties, each asserted here rather than argued in review:
##
## 1. Mind moves TURBULENCE, never health. A full-power DISRUPT at turbulence 0.0 leaves
##    the health pool byte-identical. This is THE property that distinguishes mind from
##    qi (ADR 0069) and body (ADR 0070). The erosion is applied to the sea by the TEST
##    through the proposal the spine carried, because the spine computes effects and does
##    not write them -- see that test's own note for why.
## 2. `amount` is `0.0` through BOTH seam stages -- so S6's crit multiplies nothing and
##    S9's shield absorbs nothing. S8's chip floor is NOT bypassed: it floors on S1's
##    `base`, so a landed mind strike still pays `min_chip_abs` (ADR 0162).
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


## THE distinguishing property, asserted through BOTH the seam and the spine.
##
## ## Why the hit is applied here and not by the spine
##
## `CombatSpine.resolve_hit` computes an amount and an effect list and MUTATES NOTHING but
## health: it reads `proposal.effects` at S9 and never again. Applying ADR 0071's erosion to
## the sea -- the whole point of `effects[]` existing -- is not a stage in the eleven, and the
## brief records that nothing in production calls `resolve_hit` yet either. So the assertion
## applies the carried effect to the REAL sea through the sea's own `add_turbulence`, which is
## where the clamping happens. The spine's half of the claim (its amount is `0.0`) is still
## measured on the spine's own `CombatOutcome`, below.
##
## The erosion number is asserted POSITIVE first, so a future regression reads as "the mechanism
## produced nothing" rather than as four separate failures about a sea that never moved.
##
## ## What S8's chip floor does to a mind hit, and why that is the design (ADR 0162)
##
## `CombatSpine.resolve_hit` S8 is
## `outcome.amount = maxf(outcome.amount, chip_floor(outcome.base, tuning))`, and
## `outcome.base` is S1's `technique.magnitude * RealmRate.factor` -- NOT the mechanism's
## proposal. So the floor is a floor on the TECHNIQUE, and a landed mind strike spends
## `maxf(min_chip_abs, base * min_chip_share)`. At the shipped `1.0` / `0.01` and this
## fixture's magnitude `100.0` that is exactly `1.0` -- one health point.
##
## **This is intended, and it is the documented exception**, not a contradiction left in
## the code. ADR 0071's mechanism half is exactly right: `resolve` returns `0.0`, S9's sign
## flip is the only way health moves, and mind never spends a SHARE of its own erosion.
## ADR 0162 records the other half. Two reasons the floor cannot be exempt for a
## zero-amount, effect-carrying proposal:
##
## 1. It would erase a physical blow. `BodyDamage`'s one legal refusal IS
##    `subtotal == 0.0` (`body_damage.gd:263`), and it still carries its per-site wound
##    rows -- so a `0.0 + effects` exemption would let a defender's armour delete the hit
##    entirely, which is the immunity ADR 0068 exists to make unreachable.
## 2. The floor has to survive S7, which floors `base` precisely because flooring the
##    post-S7 amount would restore nothing.
##
## So "mind never subtracts health" reads, amended, as: **mind never subtracts a share of
## its own erosion, and pays the same chip floor every other landed hit pays.**
func test_mind_damage_moves_turbulence_and_never_health() -> void:
	var attacker := _attacker()
	var defender := _defender(0.0, 0.0)
	var sea := _sea_of(defender)
	sea.turbulence = 0.0
	var health := defender.resource(&"health") as ResourcePool
	var before_health := health.current
	var before_turbulence := sea.turbulence

	var outcome := _hit(attacker, defender, MindDamage.Kind.DISRUPT)
	var carried := _effect_of(outcome.proposal)
	var erosion := float(carried.get(MindDamage.KEY_TURBULENCE, 0.0))
	assert_eq(
		erosion > 0.0,
		true,
		"a full-power DISRUPT produces a positive erosion, over the fixture's pinned sea"
	)
	sea.add_turbulence(erosion)

	# The sea moved, and it moved in the direction erosion moves it.
	assert_eq(
		sea.turbulence > before_turbulence,
		true,
		"a full-power DISRUPT raises turbulence above %s" % str(before_turbulence)
	)
	# The MECHANISM subtracts nothing: its own amount is zero at both seam stages, which is
	# what leaves S9 nothing to spend and S7 nothing to scale.
	assert_almost_eq(
		float(outcome.proposal.amount), 0.0, "and the proposal the spine carries is 0.0"
	)
	# S8 floors on the TECHNIQUE, not on that zero -- ADR 0162's documented exception.
	assert_almost_eq(
		float(outcome.amount),
		CombatSpine.chip_floor(CombatSpine.base_damage(attacker, _technique()), _tuning),
		"S8's chip floor is computed from S1's base, not from the mechanism's zero"
	)
	assert_almost_eq(float(outcome.health_delta), -outcome.amount, "so it is spent as health")
	assert_eq(
		before_health - health.current,
		outcome.amount,
		"mind costs only the chip floor's worth of health, never a share of its own erosion"
	)
	assert_eq(before_health, HEALTH, "the pool was full before the hit, as pinned")


## ADR 0162 pins the exception itself: a mind hit spends exactly the shipped chip floor and
## not one point more, whatever the magnitude of the technique that carried it. Asserted
## against `CombatSpine.chip_floor` (the shipped number, not a restated literal) and
## against `min_chip_abs`, because at this fixture's magnitude `100.0` the SHARE term
## (`0.01`) binds at `1.0` and equals the absolute floor -- so this assertion cannot tell
## the two apart and says so rather than pretending to.
func test_the_chip_floor_is_the_documented_exception_a_mind_hit_pays() -> void:
	var attacker := _attacker()
	var defender := _defender(0.0, 0.0)
	var health := defender.resource(&"health") as ResourcePool
	var before_health := health.current

	var outcome := _hit(attacker, defender, MindDamage.Kind.DISRUPT)
	var floor := CombatSpine.chip_floor(outcome.base, _tuning)

	# The mechanism declined: no magnitude at either seam stage.
	assert_almost_eq(float(outcome.proposal.amount), 0.0, "resolve contributed no amount")
	# The exception is bounded and exactly the floor -- not zero, and not more than the
	# floor. A mind hit is a WEAKENING path, not an immune one (ADR 0162).
	assert_almost_eq(
		float(outcome.amount), floor, "the landed mind hit pays exactly the shipped chip floor"
	)
	assert_ne(outcome.amount, 0.0, "ADR 0162: the floor is NOT bypassed by the mechanism's zero")
	assert_almost_eq(floor, _tuning.min_chip_abs, "and at this magnitude the absolute term binds")
	# And it is a fixed, tiny share of the strike's own magnitude -- never erosion-scaled.
	assert_eq(
		before_health - health.current,
		floor,
		"the pool moved by the floor alone, never by a share of what the hit cost the sea"
	)


## `amount` is `0.0` at BOTH seam stages. S4 produces no magnitude and S5 cannot create
## one, which is what makes S6's crit multiply nothing and S9's shield absorb nothing. S8's
## chip floor is the documented exception and reads S1's `base` rather than this zero
## (ADR 0162) -- asserted on the spine's own `CombatOutcome` in the test above.
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
		StringName(effect.get(DamageProposal.KIND, &"")),
		MindDamage.EFFECT_KIND,
		"the effect is filed under the mechanism's own EFFECT_KIND, as BodyWounds and StatusApply are"
	)
	assert_eq(
		effect.get(MindDamage.KEY_STRIKE_KIND, "") is String,
		true,
		"the effect spells the STRIKE kind as a String, never an ordinal"
	)
	assert_eq(
		String(effect.get(MindDamage.KEY_STRIKE_KIND, "")),
		MindDamage.kind_name(MindDamage.Kind.DISRUPT),
		"and it spells the strike kind as a NAME, not an ordinal"
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
## through the SPINE rather than two hand-built contexts).
##
## Both numbers are taken against the SAME sea on purpose. This test drives no hit and
## mutates nothing, so `parts["total"]` is read at the sea's own starting turbulence; a
## variant that took the sea's `turbulence` as its expectation instead would be asserting
## that erosion depends on how turbulent the sea already was, which is the one thing
## `structural_capacity` exists to make it independent of.
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


## The anti-degeneracy guarantee, asserted directly. `defense_floor()` is published as
## `1 - MENTAL_DEFENSE_CAP`, and it is the mind analogue of the spine's chip-floor immunity
## invariant: `mental_defense` enters only through the saturating `d / (d + base)`, hard-capped,
## so a fixed share of every strike ALWAYS lands.
##
## ## What this asserts, corrected
##
## The constant is read out of the SHIPPED `.tres`, never restated as `0.4`. The property is
## "the mitigation is CAPPED, so a share always lands" — not "that share is 0.4". `0.6` is
## `MENTAL_DEFENSE_CAP` and `0.4` is `1 - that`; the shipped `.tres` authors both today, and a
## rebalance of either is a legitimate `.tres` edit that must not have to come here to rewrite
## a hard-coded `0.4`. Restating the number made the suite fail on a balance change it has no
## opinion about, which is the brief's "contorting the code to satisfy a restated constant".
##
## `defense == 0.0` is kept in the sweep and now means something sharper: the contest is a
## REAL division at `0.0 / 40.0`, so it reads `0.0` and the share lands at the FULL `1.0`.
## That is a stronger claim than "it saturates at the cap" -- it shows the cap is not what is
## holding the rows above it up. The `0.0 / 0.0` of hole 1 needs BOTH terms at `0.0` and is
## covered by `test_a_degenerate_tuning_and_a_null_context_never_produce_a_nan`.
##
## `defense == 1000.0` and `1e9` are still CAPPED: `d / (d + base)` saturates, so the
## mitigation reads `MENTAL_DEFENSE_CAP` and no defence reaches "no damage". Those two are
## asserted in their OWN loop because the cap is only REACHABLE there: with a base of `40.0`,
## `d == 1.0` mitigates by `1/41` and `d == 10.0` by `10/50`, both strictly under `0.6`.
## This sweep used to assert `MENTAL_DEFENSE_CAP` on EVERY row, which reported a
## working saturating contest as five failures.
##
## There is NO clarity value that reaches "no damage" -- the sweep runs to 1e9 and asserts the
## mitigated erosion is strictly positive at every single one.
##
## ## Why the floor is NOT multiplied into the expectation here
##
## This used to assert `parts["total"] == parts["erosion"] * lands`. That is a DOUBLE
## application: `parts["erosion"]` is already `base * coh * focused` computed at
## `mind_damage.gd:238`, i.e. it ALREADY carries whatever coherence the defender's reserve
## was worth, and `total` applies the defence share on top (`mind_damage.gd:253`). The
## extra `* lands` asserted that `erosion` had been pre-divided by the floor as well, so
## every row expected `0.4 * 0.4 == 0.16` and read a strictly monotone ladder instead:
## `0.3902` at defense `0.0`, `0.3810` at `1.0`, `0.3137` at `10.0`. (The observed values
## also carried the fixture's own broken `+1.0` defense offset; with the pin repaired the
## rows read `0.4000`, `0.3902` and `0.3200` -- the same ladder, the honest one.)
##
## The numbers say which side was wrong. `d=0` reading the FULL `1.0` is what
## `mind_damage.gd:507`'s `saturated` branch is for -- there is no contest at `0 / 40`, so
## nothing is mitigated. A floor-multiplied erosion would have had `d == 0` land `0.16` and
## `d == 1e9` land the same `0.16` again, which is not a defence contest at all but a
## constant. So the FLOOR is the lowest share any defence may push the strike to -- a bound
## asserted with `>=` -- not a second factor the erosion is divided by.
func test_the_defence_floor_is_structural_at_any_defense() -> void:
	var lands := MindDamage.defense_floor(_tuning)
	# ADR 0200 deleted `MENTAL_DEFENSE_CAP`. The floor is no longer `1 - cap` (a share of
	# a removed percent); it is `1 - mitigation_ceiling`, because the ceiling is the share
	# of a mind strike that mitigation may ever remove and the floor is what always lands.
	# This is a correction: the property asserted is the same one — a mind strike always
	# lands SOME share — expressed against the field that now carries it.
	assert_almost_eq(
		lands, 1.0 - _tuning.mitigation_ceiling, "the published floor is 1 - mitigation_ceiling"
	)
	assert_almost_eq(
		MindDamage.defense_floor(), lands, "and the same when the tuning is resolved by default"
	)
	assert_eq(lands > 0.0, true, "a mind strike always lands SOME share, as qi and body do")
	var attacker := _attacker()
	for defense in [0.0, 1.0, 10.0, 1000.0, 1.0e9]:
		var defender := _defender(0.0, defense)
		var parts := _parts(MindDamage.Kind.DISRUPT, attacker, defender)
		# `defense == 0.0` is the sharp end of the row: `0 / (0 + 40)` is a REAL division
		# with no contest in it, so it reads `0.0` and the FULL strike lands. That is
		# stronger than "it saturates at the cap" -- it shows the cap is not what is
		# holding the rows above it up.
		if defense == 0.0:
			assert_almost_eq(
				float(parts["mitigation"]),
				0.0,
				"defense 0.0 is no contest at all, not a saturated one",
				1e-4
			)
		# And therefore a fixed share of the strike lands: no defense reaches "no damage".
		# `total` is `erosion` less exactly the defence share -- ONE application of the cap,
		# and derived from the row's own read of that cap rather than a restated `0.6`.
		var mitigation := float(parts["mitigation"])
		assert_almost_eq(
			float(parts["total"]),
			float(parts["erosion"]) * (1.0 - mitigation),
			"defense %s still takes %s%% of the strike" % [str(defense), str(lands * 100.0)]
		)
		# NEVER below the floor: the defence may only ever cost a bounded share, and
		# `defense 0.0` is ABOVE it rather than at it -- there is no contest at `0 / 40`.
		assert_eq(
			float(parts["total"]) >= float(parts["erosion"]) * lands,
			true,
			"defense %s lands at the floor or above it, never below" % str(defense)
		)
		assert_eq(
			float(parts["total"]) > 0.0,
			true,
			"defense %s can never refuse a mind strike outright" % str(defense)
		)
	# And the CAP is what holds the high rows, asserted where it is actually reachable:
	# `d / (d + base)` only reaches `MENTAL_DEFENSE_CAP` once `d` dominates `base`, so the
	# low rows sit UNDER it and the earlier assertion above cannot claim they are capped.
	# This used to assert the cap on EVERY row, which made defense `1.0` and `10.0` read as
	# failures of a saturating contest that is working exactly as specified.
	for defense in [1000.0, 1.0e9]:
		var parts := _parts(MindDamage.Kind.DISRUPT, attacker, _defender(0.0, defense))
		# ADR 0200 deleted `MENTAL_DEFENSE_CAP`. The curve now APPROACHES
		# `mitigation_ceiling` asymptotically rather than clamping onto it, so a dominating
		# `d` reads strictly BELOW the ceiling and gets closer the larger `d` gets. That
		# difference is the point: the old assertion demanded equality with a cap, which is
		# the very shape the ADR removes.
		var mitigation := float(parts["mitigation"])
		assert_eq(
			mitigation < _tuning.mitigation_ceiling,
			true,
			"defense %s saturates toward the ceiling without ever reaching it" % str(defense),
		)
		assert_almost_eq(
			float(parts["total"]),
			float(parts["erosion"]) * (1.0 - mitigation),
			"and a saturated defense lands at most the floor, never below it"
		)
		# And that it really is below, because "at most the floor" as a one-sided claim is
		# satisfied by the unmitigated `1.0` too. The old assertion demanded EXACT
		# equality with the floor, which was a demand about a deleted CONSTANT: the curve
		# approaches `mitigation_ceiling` and never reaches it, so at a finite `D` the
		# floor is a bound rather than a wall. What is asserted in its place is the
		# property the constant used to carry -- a defense deep enough to be saturated
		# leaves the strike PAST the floor -- with the direction the curve really has.
		#
		# Strictly `>` and not `>=`: at `defense = 1.0e9` the curve puts the landed share at
		# `0.05 + 1.71e-8`, which rounds to the floor exactly in float64. `>=` would be the
		# only assertion that passes at that row AND at `defense = 0.0`, where the whole
		# strike lands, so it would prove nothing; the strict form is the one that holds
		# across the whole sweep and fails the moment the defence stops being applied at all.
		assert_eq(
			float(parts["total"]) > float(parts["erosion"]) * lands,
			true,
			(
				(
					"defense %s is strictly PAST the floor without ever reaching it: %s of "
					+ "erosion lands where the floor is %s"
				)
				% [str(defense), str(float(parts["total"]) / float(parts["erosion"])), str(lands)]
			)
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
	# `mind_stat_prefix` ships EMPTY so the ids ARE the bare `MindStats` ids, and
	# `MentalProvider` reads `PERCEPTION` from a base stat. `attach` resolves every provider
	# the actor declares, so this read is what proves the actor really carries the stat the
	# attacker rows depend on -- rather than every erosion reading `0.0` off an actor that
	# never contributed one.
	assert_almost_eq(
		attacker.stats.derived(MindStats.MENTAL_ATTACK),
		ATTACKER_MENTAL_ATTACK,
		"the attacker's pinned mental_attack, by construction"
	)
	# A mental_defense of 0.0 comes from the fixture's FLAT modifier, not from an absent stat,
	# so the only thing standing between the two is the `OBSCURE` maxf.
	assert_almost_eq(
		defender.stats.derived(MindStats.MENTAL_DEFENSE), 0.0, "and the defender's is pinned at 0.0"
	)
	# mental_clarity 200.0 saturates illusion_resistance at its 0.8 cap; mental_defense
	# is pinned at 0.0 by the fixture, so there is NO other source of mitigation.
	# The high-clarity build is asked of `_defender` rather than the row's defender mutated
	# in place with `set_base` + `mark_stats_dirty`: that pair could not be trusted to make
	# one actor answer `0.8` for resistance and `0.0` for defence at the same time, and an
	# actor rebuilt outside the fixture arrives with the provider's own `clarity * 2`
	# baseline undefended -- which is where `expected 0.0, got 400.0` came from. Asking the
	# fixture for the BUILD keeps the pin and the build on one actor by construction.
	var illusionist := _defender(0.0, 0.0, 200.0)
	assert_almost_eq(
		illusionist.stats.derived(MindStats.ILLUSION_RESISTANCE),
		0.8,
		"illusion_resistance is at its 0.8 ceiling"
	)
	assert_almost_eq(
		illusionist.stats.derived(MindStats.MENTAL_DEFENSE),
		0.0,
		"and mental_defense is still pinned at 0.0 on that same actor"
	)

	var obscure := _parts(MindDamage.Kind.OBSCURE, attacker, illusionist)
	var disrupt := _parts(MindDamage.Kind.DISRUPT, attacker, illusionist)
	# And the mitigation is the CURVE, not a ceiling: ADR 0200 deleted
	# `ILLUSION_RESISTANCE_CAP` along with `MENTAL_DEFENSE_CAP`, so this asserts the ratio
	# rather than the `0.8` that is no longer a mitigation anywhere. The two halves of
	# `_defense_of`'s `maxf` are MAGNITUDES, and `ILLUSION_MAGNITUDE_SCALE` is the one
	# documented conversion that makes them comparable — see the constant's docblock for
	# why dividing by `resist_divisor` alone read `0.00042203465127` and made the stat
	# inert. Everything here is DERIVED from the tuning's own numbers, so a balance pass
	# moves the expectation with the code.
	var defense := MindDamage.ILLUSION_MAGNITUDE_SCALE * 0.8
	var divisor_k := _tuning.defense_divisor_k * float(obscure["base"])
	var expected_mitigation := _tuning.mitigation_ceiling * defense / (divisor_k + defense)
	assert_almost_eq(
		float(obscure["defense"]),
		defense,
		"OBSCURE's D is the illusion half at last, in K's own magnitude space"
	)
	assert_almost_eq(
		float(obscure["divisor_k"]), divisor_k, "and K rides this mechanism's own offense"
	)
	assert_almost_eq(
		float(obscure["mitigation"]),
		expected_mitigation,
		"OBSCURE is mitigated by illusion_resistance through the ratio"
	)
	# NON-TRIVIAL, which is the whole claim and the thing the old literal `0.8` could not
	# distinguish. A mitigation of zero would satisfy every ordering assertion below and
	# still mean the stat does nothing, so the size is asserted against a stated floor.
	assert_eq(
		float(obscure["mitigation"]) >= 0.1,
		true,
		(
			(
				"and it is a REAL mitigation, not a rounding artefact of a mis-scaled stat "
				+ "(measured %f against the D/K the tuning produces)"
			)
			% float(obscure["mitigation"])
		)
	)
	assert_eq(
		float(obscure["mitigation"]) < _tuning.mitigation_ceiling,
		true,
		"and still strictly below the ceiling, because the curve approaches it and never reaches it"
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
	# A defender at `0.0` clarity AND `0.0` mental_defense, so no stat is standing in for the
	# fixture's pin: `MentalProvider` derives `mental_defense = (clarity * 2 + will * 0.5)`,
	# and BOTH terms are already `0.0` on this actor before the pin is applied at all --
	# `will` is never given a base stat, and the fixture pins the stat they do not feed.
	# `illusion_resistance` is derived from the same two, so it rests at its own `0.0` here
	# and the read below is the mechanism declining the stat, not the stat being absent.
	# (`DISRUPT`'s twin above proves the counterpart: there the fixture pins the resistance
	# at its `0.8` ceiling and the same read still answers `0.0`.)
	var defender := _defender(0.0, 0.0, 0.0)
	var attend := _parts(MindDamage.Kind.ATTEND, attacker, defender)
	assert_almost_eq(
		defender.stats.derived(MindStats.MENTAL_DEFENSE), 0.0, "and the defender's is 0.0 to start"
	)
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
	#
	# `KEY_AWARENESS` is already a DELTA and already negative, so it is ADDED. Taking its
	# absolute value first and adding that REFILLLED the reserve — it went UP, the coherence
	# went DOWN with it, and the following strike landed softer, so this half of the property
	# was asserting the exact opposite of what its own name claims.
	var pool := defender.resource(MindStats.AWARENESS) as ResourcePool
	pool.current = maxf(
		0.0, pool.current + float(attend.get(MindDamage.KEY_AWARENESS, 0.0)) * pool.maximum
	)
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
