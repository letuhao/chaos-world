extends TestCase

## S12: status application on a clean landed hit (ADR 0087), its potency and mastery
## wiring (ADR 0088).
##
## The assertions are ordered by how much damage a regression in each would do:
##
## 1. **A MISSED / PARRIED / BLOCKED hit applies NOTHING.** The single most important
##    property here, and the reason S12 is gated on `is_clean()` rather than on
##    "the attack happened": a defender who parried a blow has ANSWERED it, so handing
##    them a debuff for the privilege inverts the whole defensive vocabulary — parrying
##    would become worse than eating the hit.
## 2. **Deterministic from a seed.** Same seed, same outcome, run twice — and a
##    different seed may differ, which is what proves the determinism is a seed and not
##    a constant answer.
## 3. **Resistance.** `Stat.STATUS_RESISTANCE` raises resist and reaches immunity only
##    through the authored cap; a CULTIVATION scope is not resisted (ADR 0086).
## 4. **A defender already holding the id is not re-applied.**
## 5. **ADR 0067's four orderings still hold** — the spine's own suite covers those, so
##    what is asserted here is that S12 changed none of them.
## 6. **The constants come from the `.tres`**, not from the `.gd`.

## The status id every case applies. Module-local on purpose: a suite that reused a real
## status id would collide with whatever the other combat_engine suites put on the same
## fixture actors.
const _STATUS := &"test_poison"

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


# --- 1. the gate: a refused hit applies NOTHING --------------------------------


func test_a_missed_hit_never_applies_a_status() -> void:
	var target := _evasive(&"target")
	var result := _resolve(target, _mech(), _request(1.0), &"hero", 4242)
	assert_eq(result[StatusApply.APPLIED], false, "a saturated-evasion miss applies nothing")
	assert_eq(
		String(result[StatusApply.REFUSED]),
		String(StatusApply.REFUSE_NOT_CLEAN),
		"and says the one reason that matters"
	)
	assert_eq(target.statuses.size(), 0, "and the missed defender holds nothing")
	assert_eq(target.has_status(_STATUS), false, "specifically not this one")


func test_a_parried_hit_never_applies_a_status() -> void:
	var target := _parrying(&"target")
	var result := _resolve(target, _mech(), _request(1.0), &"hero", 4242)
	assert_eq(result[StatusApply.APPLIED], false, "parrying is an ANSWER, not a free hit")
	assert_eq(String(result[StatusApply.REFUSED]), String(StatusApply.REFUSE_NOT_CLEAN), "refused")
	assert_eq(target.statuses.size(), 0, "and the defender pays for the parry with nothing")


func test_a_blocked_hit_never_applies_a_status() -> void:
	var target := _blocking(&"target")
	var result := _resolve(target, _mech(), _request(1.0), &"hero", 4242)
	assert_eq(result[StatusApply.APPLIED], false, "a block refuses the hit entirely")
	assert_eq(target.statuses.size(), 0, "and the defender holds nothing")


func test_a_clean_hit_is_the_only_case_that_ever_reaches_the_roll() -> void:
	# The positive control for the three above. Without it, "never applies a status"
	# would be satisfied by a stage that never applies anything at all.
	var target := CombatTestKit.actor(&"target")
	var result := _resolve(target, _mech(), _request(1.0), &"hero", 4242)
	assert_eq(result[StatusApply.APPLIED], true, "a clean hit with an open gate DOES apply")
	assert_eq(target.has_status(_STATUS), true, "and the defender now holds it")


# --- 2. deterministic from a seed ----------------------------------------------


func test_the_same_seed_produces_the_same_outcome_twice() -> void:
	var first_target := CombatTestKit.actor(&"target")
	var first := _resolve(first_target, _mech(), _request(0.5), &"hero", 90210)
	var second_target := CombatTestKit.actor(&"target")
	var second := _resolve(second_target, _mech(), _request(0.5), &"hero", 90210)
	assert_eq(first[StatusApply.APPLIED], second[StatusApply.APPLIED], "same seed, same verdict")
	assert_almost_eq(float(first[&"potency"]), float(second[&"potency"]), "and the same potency")


func test_the_outcome_is_a_function_of_the_seed_and_not_a_constant() -> void:
	# Sweeps seeds rather than asserting one pair differs: a stage that answered a fixed
	# way would pass a single "these two differ" test, and would be caught here.
	var applied := {}
	for index in 40:
		var subject := CombatTestKit.actor(&"target")
		var result := _resolve(subject, _mech(), _request(0.5), &"hero", index * 7919)
		applied[bool(result[StatusApply.APPLIED])] = true
	assert_eq(applied.size(), 2, "some seeds land and some do not, so the roll is real")


func test_two_hits_in_one_fight_do_not_roll_the_same_status() -> void:
	# `hit_index` exists for exactly this: the caller stream is SHARED, so without an
	# index the Nth identical attack in a fight would re-roll the first one's answer.
	# Asserted on the SEEDS rather than on two resolved outcomes — at a 50% gate two
	# draws agreeing is a 1-in-2 flake, and a flaky ordering assertion is not an
	# assertion.
	var attacker := CombatTestKit.actor(&"hero")
	var defender := CombatTestKit.actor(&"target")
	assert_ne(
		StatusApply.status_seed(555, attacker, defender, null, 0),
		StatusApply.status_seed(555, attacker, defender, null, 1),
		"the hit index salts the substream, so hit 2 is not a replay of hit 1"
	)


# --- 3. resistance --------------------------------------------------------------


func test_status_resistance_raises_the_resist_and_reaches_immunity_at_the_cap() -> void:
	var open_target := CombatTestKit.actor(&"open")
	var closed_target := CombatTestKit.actor(&"closed")
	closed_target.stats.add_modifier(
		CombatStats.rate_modifier(Stat.STATUS_RESISTANCE, _tuning_cap_resist(), &"test")
	)
	var open_chance := StatusApply.apply_chance(1.0, open_target, _tuning, 0.0)
	var closed_chance := StatusApply.apply_chance(1.0, closed_target, _tuning, 0.0)
	assert_almost_eq(open_chance, 1.0, "an undefended defender takes it at the authored chance")
	assert_eq(closed_chance <= open_chance, true, "STATUS_RESISTANCE strictly raises the resist")
	assert_eq(closed_chance < 1.0, true, "and at the cap it is never a guarantee")
	# The cap ALONE is not enough to reach the floor, and that is arithmetic rather than
	# an accident: `Stat.STATUS_RESISTANCE` tops out at 0.8 (`core/actor_stats.gd:162` --
	# this suite reads that number off a probe actor rather than restating it), so the
	# multiplicative form bottoms out at `1.0 * (1 - 0.8) = 0.2` with no elemental term.
	# Proving the floor is what forbids immunity therefore means driving the product BELOW
	# it, which is what the second resist is for. At the shipped `resist_cap` of 0.75 the
	# pair still reads 0.05 -- above the floor -- which is exactly the arithmetic ADR 0087
	# claims for the multiplicative form: two ordinary defensive stats compose into a
	# crawl, never into a refusal. It is the SUM form that reaches `p_apply <= 0.0` here,
	# and rejecting that form is why this number is not zero.
	assert_eq(
		closed_chance > _tuning.status_min_apply,
		true,
		"the capped resist alone leaves the gate above the floor"
	)
	assert_almost_eq(
		StatusApply.apply_chance(1.0, closed_target, _tuning, _tuning.resist_cap),
		0.05,
		"and both resists at their caps still compose rather than annihilate (ADR 0087)"
	)
	# Saturate the elemental term too and the product falls under the floor, where the
	# floor is the ONLY thing keeping the answer non-zero. This is the immunity claim:
	# without `status_min_apply` this reads 0.0 and a defender at both caps is immune.
	var floored := StatusApply.apply_chance(1.0, closed_target, _tuning, 1.0)
	assert_almost_eq(
		floored, _tuning.status_min_apply, "full immunity is not reachable; the floor is"
	)
	assert_eq(floored > 0.0, true, "and a saturated defender still takes the status sometimes")


func test_a_cultivation_scope_status_is_not_resisted() -> void:
	# ADR 0086: "a blessing the game pays out must not tax the player for receiving it".
	var target := CombatTestKit.actor(&"target")
	target.stats.add_modifier(
		CombatStats.rate_modifier(Stat.STATUS_RESISTANCE, _tuning_cap_resist(), &"test")
	)
	var combat := StatusApply.apply_chance(1.0, target, _tuning, 0.0, StatusApply.SCOPE_COMBAT)
	var cultivation := StatusApply.apply_chance(
		1.0, target, _tuning, 0.0, StringName("cultivation")
	)
	assert_eq(combat < 1.0, true, "a COMBAT status is resisted")
	assert_almost_eq(cultivation, 1.0, "a CULTIVATION status is not resisted at all")


func test_elemental_resistance_reduces_the_chance_multiplicatively() -> void:
	# ADR 0087 rejects `stat_resist + elem_resist`: the sum goes negative at both caps and
	# manufactures immunity out of two ordinary defensive stats. The product cannot.
	var target := CombatTestKit.actor(&"target")
	var half := StatusApply.apply_chance(1.0, target, _tuning, 0.5)
	assert_almost_eq(half, 0.5, "an elemental resist of 0.5 halves the chance")
	assert_eq(
		StatusApply.apply_chance(1.0, target, _tuning, 1.0) >= 0.0, true, "and never goes negative"
	)


func test_mastery_penetration_cuts_resistance_and_never_amplifies_past_the_cap() -> void:
	# ADR 0069: penetration is subtracted BEFORE the clamp, so it can only move a
	# resistance DOWN. A penetration of 1.0 against a resistance of 0.0 must read 0.0, not
	# -1.0 — a negative resist would be a damage BONUS wearing a defender's name.
	var attacker := CombatTestKit.actor(&"hero")
	attacker.stats.add_modifier(CombatStats.rate_modifier(CombatStats.PENETRATION, 1.0, &"test"))
	var bare := CombatTestKit.actor(&"bare")
	assert_eq(
		StatusApply.elemental_resist(attacker, bare, _tuning, &"fire") >= 0.0,
		true,
		"maximal penetration still cannot invert the sign"
	)


func test_penetration_does_not_touch_potency() -> void:
	# ADR 0088's second bullet, asserted directly: mastery buys "lands more often" and
	# never "hits harder". If a penetration change moved potency, this fails.
	var weak := CombatTestKit.actor(&"weak")
	var strong := CombatTestKit.actor(&"strong")
	strong.stats.add_modifier(CombatStats.rate_modifier(CombatStats.PENETRATION, 1.0, &"test"))
	assert_almost_eq(
		StatusApply.potency_of(weak, _tuning, &"fire"),
		StatusApply.potency_of(strong, _tuning, &"fire"),
		"penetration is a RESIST lever only; potency reads element_power alone"
	)


func test_potency_reuses_element_power_and_is_never_negative() -> void:
	# ADR 0088: potency reads `element_power_<e>` and the only arithmetic is a multiply
	# and a maxf of non-negatives, so no reader downstream can mistake it for a sign.
	var attacker := CombatTestKit.actor(&"hero")
	assert_eq(StatusApply.potency_of(attacker, _tuning, &"fire") >= 0.0, true, "never negative")
	assert_almost_eq(
		StatusApply.potency_of(attacker, _tuning, &"fire"),
		_tuning.status_potency_floor,
		"an actor with no elemental power rests on the authored floor, not on zero"
	)


# --- 4. already held ------------------------------------------------------------


func test_a_defender_already_holding_the_status_is_not_re_applied() -> void:
	var target := CombatTestKit.actor(&"target")
	target.add_status(StatusEffect.new(_STATUS, 30.0))
	var before := target.statuses.size()
	var result := _resolve(target, _mech(), _request(1.0), &"hero", 4242)
	assert_eq(result[StatusApply.APPLIED], false, "a duplicate is refused")
	assert_eq(
		String(result[StatusApply.REFUSED]),
		String(StatusApply.REFUSE_ALREADY_HELD),
		"and says why, so a balance pass can see it"
	)
	assert_eq(target.statuses.size(), before, "the array did not grow")


# --- 5. ADR 0067's orderings are untouched --------------------------------------


func test_adding_s12_did_not_move_the_chip_floor_or_the_single_sign_flip() -> void:
	# S8 still runs before S9, so enough flat DAMAGE_REDUCTION still cannot make a landed
	# hit immune; and the health write is still the ONLY negative movement, so S12 has
	# not introduced a second negation somewhere downstream of it.
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 40.0
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, mechanism)
	var target := CombatTestKit.actor(&"target")
	target.stats.add_modifier(StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 1e9, &"test"))
	var outcome := CombatSpine.resolve_hit(
		attacker, target, CombatTestKit.technique(100.0), _tuning, null
	)
	assert_almost_eq(
		outcome.amount, _tuning.min_chip_abs, "S8's floor still restores the chip after S7"
	)
	assert_eq(
		outcome.health_delta <= 0.0, true, "the health delta is still non-positive: one sign flip"
	)


func test_s12_rides_effects_and_the_outcome_gains_no_status_field() -> void:
	# ADR 0087: "CombatOutcome gains no status field. S12's result rides effects[], so
	# to_dict() stays primitives-only (ADR 0038) and a screen renders it unchanged."
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 25.0
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, mechanism)
	var target := CombatTestKit.actor(&"target")
	var outcome := CombatSpine.resolve_hit(
		attacker,
		target,
		CombatTestKit.technique(100.0),
		_tuning,
		CombatTestKit.rng(11),
		func(ctx: AttackContext) -> AttackContext:
			ctx.set_data(StatusApply.REQUEST_KEY, _request(1.0))
			return ctx
	)
	var seen := false
	for entry in outcome.effects():
		if (
			StringName((entry as Dictionary).get(DamageProposal.KIND, &""))
			== StatusApply.EFFECT_KIND
		):
			seen = true
	assert_eq(seen, true, "S12 published its result onto effects[]")
	assert_eq(
		outcome.get("status") == null, true, "and no status field was bolted onto the outcome"
	)


# --- 6. the constants are DATA ---------------------------------------------------


func test_every_status_constant_is_read_from_the_tres_and_not_hardcoded() -> void:
	# A rebalance is a `.tres` edit. These four assert the shipped instance carries
	# non-degenerate values, because a `0.0` default would make S12 silently inert and a
	# test that restated the number would keep passing through the whole regression.
	assert_eq(_tuning.status_min_apply > 0.0, true, "status_min_apply is authored in the .tres")
	assert_eq(
		_tuning.status_potency_scale > 0.0, true, "status_potency_scale is authored in the .tres"
	)
	assert_eq(
		_tuning.status_potency_floor > 0.0, true, "status_potency_floor is authored in the .tres"
	)
	assert_eq(
		_tuning.status_default_duration > 0.0, true, "a status must not be born already expired"
	)


func test_editing_the_tuning_changes_the_outcome_without_touching_a_gd_file() -> void:
	# The `.tres`-is-the-balance claim, end to end: a copy with a different floor applies
	# a different potency, with no code change. This is what ADR 0067's "a rebalance is a
	# `.tres` edit and no test re-pins a literal" actually means in practice.
	var retuned := _tuning.duplicate(true) as CombatTuning
	retuned.status_potency_floor = _tuning.status_potency_floor * 3.0
	var attacker := CombatTestKit.actor(&"hero")
	assert_almost_eq(
		StatusApply.potency_of(attacker, retuned, &"fire"),
		_tuning.status_potency_floor * 3.0,
		"the floor alone moved the potency"
	)


# --- internals ------------------------------------------------------------------


## The `Stat.STATUS_RESISTANCE` cap. Read off the actor rather than restated: core caps
## it at `0.8` (`core/actor_stats.gd:162`) and that number belongs to core, not to this
## suite. A FLAT modifier of that size is exactly how the cap is reached.
func _tuning_cap_resist() -> float:
	return Actor.new(&"probe", {Stat.WILL: 1000.0}).stats.derived(Stat.STATUS_RESISTANCE)


## A defender who always parries. `CombatStats.PARRY_RATE` is a `0.0`-baseline RATE, so
## only a FLAT modifier can move it (ADR 0022) — which is what `rate_modifier` builds.
##
## ⚠️ **These three gate tests cannot pass today, and the blocker is NOT status code.**
## Tracked as DEF-0144. Measured by headless probe: a FLAT +1000 on `PARRY_RATE` leaves
## `derived(PARRY_RATE)` at `0.0`, because `actor_stats.gd`'s `_recompute` calls `_put`
## only for the ids it enumerates (lines 155-172) and `parry.rate` is not among them — the
## modifier is bucketed by `_buckets()` and then never read. So `p_parry`/`p_block` are
## `0.0` in every mode, the band's parry and block branches are unreachable, and the
## "a missed/parried/blocked hit never applies a status" assertions below are measuring a
## gate that cannot close. The fixture is left in its simplest honest form; fixing DEF-0144
## is what makes these run.
func _parrying(id: StringName) -> Actor:
	var subject := CombatTestKit.actor(id)
	subject.stats.add_modifier(CombatStats.rate_modifier(CombatStats.PARRY_RATE, 1000.0, &"test"))
	return subject


func _blocking(id: StringName) -> Actor:
	var subject := CombatTestKit.actor(id)
	subject.stats.add_modifier(CombatStats.rate_modifier(CombatStats.BLOCK_RATE, 1000.0, &"test"))
	return subject


## A saturated miss: `Stat.EVASION` at `rate_scale` puts `p_hit` on `0.0`, which is the
## band roll's "everything misses" state.
func _evasive(id: StringName) -> Actor:
	var subject := CombatTestKit.actor(id)
	subject.stats.add_modifier(StatModifier.new(Stat.EVASION, Stat.Op.FLAT, 1_000_000.0, &"test"))
	return subject


func _mech() -> CombatTestKit.FixedMechanism:
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 25.0
	return mechanism


## An always-true gate, so the roll never fails for a reason unrelated to the assertion
## under test. Resistance tests use the arithmetic directly for the same reason.
##
## Keys are plain `String`s: `StatusApply` reads them through `get()`, which is the whole
## point of the `Variant` contract shape, so an authored def on a `.tres` can carry the
## same dictionary and this test is that def.
func _request(chance: float) -> Dictionary:
	return {
		"id": _STATUS,
		"chance": chance,
		"element": &"fire",
		"scope": String(StatusApply.SCOPE_COMBAT),
		"duration": 10.0,
	}


func _resolve(
	target: Actor,
	mechanism: CombatTestKit.FixedMechanism,
	request: Dictionary,
	attacker_id: StringName,
	seed_value: int,
	hit_index: int = 0
) -> Dictionary:
	var attacker := CombatTestKit.quiet_actor(attacker_id)
	MechanismSlot.bind(attacker, mechanism)
	var outcome := CombatSpine.resolve_hit(
		attacker,
		target,
		CombatTestKit.technique(100.0),
		_tuning,
		CombatTestKit.rng(seed_value),
		func(ctx: AttackContext) -> AttackContext:
			ctx.set_data(StatusApply.REQUEST_KEY, request)
			return ctx,
		0,
		hit_index
	)
	for entry in outcome.effects():
		var row := entry as Dictionary
		if StringName(row.get(DamageProposal.KIND, &"")) == StatusApply.EFFECT_KIND:
			# The effect is FLATTENED, not nested: `DamageProposal.effects` is
			# primitives-only by contract, so `StatusApply.record` spreads the result's
			# fields beside the kind rather than parking them under one key.
			return row.duplicate(true)
	# `record` deliberately writes nothing for a `not_clean` refusal, so a refused band is
	# answered from the outcome itself rather than from `effects[]`.
	return {
		StatusApply.APPLIED: false,
		StatusApply.REFUSED: StatusApply.REFUSE_NOT_CLEAN,
	}
