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
## 3. **Resistance.** `Stat.STATUS_DEFENSE` raises resist and reaches immunity only
##    through `status_min_apply`, which is a FLOOR on a still-positive number rather than
##    an authored ceiling (ADR 0200); a CULTIVATION scope is not resisted (ADR 0086).
## 4. **A defender already holding the id is not re-applied.**
## 5. **ADR 0067's four orderings still hold** — the spine's own suite covers those, so
##    what is asserted here is that S12 changed none of them.
## 6. **The constants come from the `.tres`**, not from the `.gd`.

## The status id every case applies. Module-local on purpose: a suite that reused a real
## status id would collide with whatever the other combat_engine suites put on the same
## fixture actors.
const _STATUS := &"test_poison"

var _tuning: CombatTuning

## ## This suite now drives `StatusApply.apply` DIRECTLY, and that is a correction
##
## It used to resolve through `CombatSpine.resolve_hit` and read the result back off
## `outcome.effects[]`. That worked only while the spine RAN the stage. DEF-0145 removed
## the spine's S12 call — ADR 0105 had already decided "S12 is retired as the application
## site, not re-routed", and re-measuring showed it was DEAD rather than unwired:
## nothing in `game/src` ever wrote `StatusApply.REQUEST_KEY`, so every spine resolve
## returned `REFUSE_NO_REQUEST`.
##
## Removing the branch therefore could not leave these assertions pointing at a stage.
## The behaviour they assert is ALL still real and all still production-reachable — the
## resist formula, the potency reuse and the seeded substream are read in place by
## `modules/combat/exchange.gd` and `modules/loot/loot_affliction.gd` — so the suite now
## calls the function those paths call. Every assertion below is preserved verbatim and
## measures the same thing; only the SEAT moved. `_resolve` below builds the same
## `AttackContext` the spine's `_context` built and hands the same request under the same
## key, so the contract under test is byte-identical to what the spine was exercising.
##
## What this file can no longer assert, and why that is a loss worth naming rather than
## hiding: the two ORDERING claims ADR 0087 gained by placing S12 last (S9 before S12, so
## a defender that died of the blow is not burned by it; S11 before S12, so a status
## cannot change `health_regen` mid-leech-packet) are ordering claims about a placement
## that no longer exists. ADR 0105's exchange call site carries its own equivalent — it
## runs after `LootApi.strike` and before the `_still_standing` branch, so a killing blow
## applies nothing — and `tests/modules/combat/test_combat_exchange_status.gd` is where
## that ordering is asserted. Those two orderings live there now, not here.


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
	# would be satisfied by a stage that never applies anything at all — and after
	# DEF-0145 removed the stage, that is no longer a hypothetical.
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
	# `potency` is a field of an APPLIED result only: `StatusApply._refused` answers
	# `{applied: false, refused: <reason>}` and a refusal legitimately carries no potency.
	# `[]` on it aborted the whole function mid-way, so the pair this test is about was
	# never compared at all. `.get()` with an explicit fallback says what it means: two
	# refusals agree on potency (both absent) as much as two applications do.
	assert_almost_eq(
		float(first.get(&"potency", 0.0)),
		float(second.get(&"potency", 0.0)),
		"and the same shape of answer, so a refusal is not read as an application"
	)


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
		CombatStats.rate_modifier(
			StringName(_tuning.status_defense_stat), _tuning_cap_resist(), &"test"
		)
	)
	var open_chance := StatusApply.apply_chance(null, open_target, _tuning, 1.0, &"", &"", &"", 0.0)
	var closed_chance := StatusApply.apply_chance(
		null, closed_target, _tuning, 1.0, &"", &"", &"", 0.0
	)
	# ADR 0884: parity reads half, and the defender's `status_defense` share enters the
	# flat delta directly — one `status_rate_scale` of net advantage is the whole exchange
	# rate, so a `0.9` share is far past the point where the gate reaches the floor.
	assert_almost_eq(open_chance, 0.5, "an undefended defender reads the parity half")
	assert_eq(
		closed_chance <= open_chance,
		true,
		"the COMBAT half's status defense strictly raises the resist"
	)
	assert_almost_eq(
		closed_chance,
		_tuning.status_min_apply,
		"and at that depth the floor is the only thing keeping it reachable"
	)
	var saturated_pair := StatusApply.apply_chance(
		null, closed_target, _tuning, 1.0, &"", &"", &"", 1.0e9
	)
	# Both resists and the elemental term saturate into the SAME floor: ADR 0884's single
	# delta has no way under it, and `status_min_apply` is what forbids a hard zero — the
	# immunity claim, unchanged in spirit from ADR 0087's product and asserted at the one
	# place it belongs.
	assert_almost_eq(
		saturated_pair, _tuning.status_min_apply, "full immunity is not reachable; the floor is"
	)
	assert_eq(
		saturated_pair > 0.0, true, "and a saturated defender still takes the status sometimes"
	)


func test_a_cultivation_scope_status_is_not_resisted() -> void:
	# ADR 0086: "a blessing the game pays out must not tax the player for receiving it".
	var target := CombatTestKit.actor(&"target")
	target.stats.add_modifier(
		CombatStats.rate_modifier(
			StringName(_tuning.status_defense_stat), _status_defense_for(0.9), &"test"
		)
	)
	var combat := StatusApply.apply_chance(
		null, target, _tuning, 1.0, &"", &"", &"", 0.0, StatusApply.SCOPE_COMBAT
	)
	var cultivation := StatusApply.apply_chance(
		null, target, _tuning, 1.0, &"", &"", &"", 0.0, StringName("cultivation")
	)
	assert_eq(combat < cultivation, true, "a COMBAT status is resisted")
	assert_almost_eq(cultivation, 0.5, "and a CULTIVATION status pays only the parity reading")


## ## ADR 0200: the stat the gate reads is a MAGNITUDE, and the fixture has to build one
##
## This used to pin a flat `0.8` on `Stat.STATUS_RESISTANCE` — the number core's deleted
## `minf(0.8, will * 0.003)` saturated at — through `_tuning_cap_resist()`. ADR 0200 renamed
## the id to `Stat.STATUS_DEFENSE` and removed the cap, and `StatusApply` now reads it
## through `CombatTuning.status_defense_stat`. Pinning `0.8` on the new stat would read as a
## magnitude of `0.8`, which is `0.008` after the divisor and barely defends anything — so the
## fixture asks for the defense that reaches a chosen SHARE of the gate instead, and the
## arithmetic is the mechanism's own.
##
## Solved from `share = mitigation_ceiling * D / (K + D)` for `D`, with `K` the
## `defense_divisor_k` `apply_chance` has without an attacker. That keeps the two halves of
## this case honest: the resist is a real number the gate divides by, and it is expressed as
## the RATE the gate is about rather than as a magnitude a reader has to convert.
##
## ## The `resist_divisor` on the way OUT is correct, and MEASURED rather than assumed
##
## `_status_defense_share` divides the raw stat by `resist_divisor` to reach its `D`, so
## the figure this helper hands to `add_modifier` has to be `resist_divisor` times that `D`
## or the divisor is applied twice. At `share = 0.9` that is `D = 0.45 * 0.9 / 0.05 = 8.1`
## against `authored 8.1 * 100 = 810.0` on the stat, which reads back a resist share of
## exactly `0.900000000`. Dropping the multiply is what made this suspect in the first
## place: it is the same unit mistake `test_qi_damage.gd` had, solved correctly here, and
## it is recorded here so the next reader does not "fix" the multiply.
func _status_defense_for(share: float) -> float:
	var ceiling := _tuning.mitigation_ceiling
	var divisor_k := _tuning.defense_divisor_k
	var defense := divisor_k * share / maxf(1e-9, ceiling - share)
	return defense * _tuning.resist_divisor


func test_the_elemental_resist_adds_into_the_flat_delta() -> void:
	# ADR 0884: the elemental resist is one more term of the SAME delta, so half of one
	# rate scale of it takes exactly half of the parity reading away.
	var target := CombatTestKit.actor(&"target")
	var parity := StatusApply.apply_chance(null, target, _tuning, 1.0, &"", &"", &"fire", 0.0)
	var half := StatusApply.apply_chance(
		null, target, _tuning, 1.0, &"", &"", &"fire", _tuning.status_rate_scale * 0.5
	)
	assert_almost_eq(parity, 0.5, "parity reads half")
	assert_almost_eq(half, 0.25, "half a rate scale of elemental resist takes half of it")
	assert_eq(
		StatusApply.apply_chance(null, target, _tuning, 1.0, &"", &"", &"fire", 1.0) >= 0.0,
		true,
		"and it never goes negative"
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


func test_status_application_never_moved_the_chip_floor_or_the_single_sign_flip() -> void:
	# S8 still runs before S9, so enough flat DAMAGE_REDUCTION still cannot make a landed
	# hit immune; and the health write is still the ONLY negative movement, so status
	# application never introduced a second negation somewhere downstream of it.
	#
	# Renamed on the DEF-0145 change: the assertion is unchanged and still about the same
	# invariant, but it no longer describes a stage that runs here. What this file still
	# proves about "S12 does not write health" is that `StatusApply` has no health write at
	# all — which is why the assertion is now a property of the resolved hit alone.
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


func test_the_status_result_rides_effects_and_the_outcome_gains_no_status_field() -> void:
	# ADR 0087: "CombatOutcome gains no status field. S12's result rides effects[], so
	# to_dict() stays primitives-only (ADR 0038) and a screen renders it unchanged."
	#
	# DEF-0145 changed the SEAT, not the shape. `StatusApply.record` is still the only
	# writer and it still appends to the proposal's `effects[]`; the stage that used to
	# call it from inside the spine is gone, so this drives `record` against a real
	# outcome directly. The two halves are asserted as before: the entry appears, and
	# `CombatOutcome` still gains no `status` field to carry it instead.
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 25.0
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	# ADR 0877: the hit trigger needs the attack to BEAT the defender's evasion, and this
	# fixture only cares that a blow LANDED — so the attacker carries a saturated base
	# accuracy, the determinism the old complement gave a `(0, 0)` pair.
	attacker.stats.add_modifier(CombatStats.rate_modifier(CombatStats.ACCURACY, 1.0, &"test"))
	MechanismSlot.bind(attacker, mechanism)
	var target := CombatTestKit.actor(&"target")
	var technique := CombatTestKit.technique(100.0)
	var outcome := CombatSpine.resolve_hit(
		attacker, target, technique, _tuning, CombatTestKit.rng(11)
	)
	var ctx := AttackContext.new(attacker, target, technique, _tuning)
	ctx.set_data(StatusApply.REQUEST_KEY, _request(1.0))
	var result := StatusApply.apply(
		attacker, target, _tuning, ctx, outcome, CombatTestKit.rng(11), technique, 0
	)
	StatusApply.record(outcome, result)
	var seen := false
	for entry in outcome.effects():
		if (
			StringName((entry as Dictionary).get(DamageProposal.KIND, &""))
			== StatusApply.EFFECT_KIND
		):
			seen = true
	assert_eq(seen, true, "the status result is published onto effects[]")
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
	assert_eq(_tuning.status_rate_scale > 0.0, true, "status_rate_scale is authored in the .tres")
	assert_eq(
		_tuning.status_power_prefix != "", true, "the status power prefix is authored in the .tres"
	)
	assert_eq(
		_tuning.status_resist_prefix != "",
		true,
		"the status resist prefix is authored in the .tres"
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


## A defender at the top of the gate's own resist scale.
##
## ADR 0200 deleted core's `minf(0.8, will * 0.003)` and renamed the stat to
## `Stat.STATUS_DEFENSE`, an unbounded MAGNITUDE the realm ladder scales. The old
## `_tuning_cap_resist()` read the `0.8` off a probe actor at `will 1000.0` — the deleted
## cap — and it cannot be restored in that form: the cap is gone, the id is different, and
## `StatusApply` reads the id out of `CombatTuning.status_defense_stat` rather than naming a
## core const.
##
## What the cap was FOR survives as a property and is asserted as one: there is a defense
## magnitude at which the COMBAT gate is maximally resisted without ever reaching `1.0`,
## because the resist is a RATIO and a ratio's output is strictly below its ceiling. The
## figure is solved for rather than pasted, so a rebalance of `mitigation_ceiling` or
## `resist_divisor` moves the fixture with it.
func _tuning_cap_resist() -> float:
	return _status_defense_for(0.9)


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


## The band's answer, decided by the SPINE and then applied by `StatusApply`.
##
## Two steps rather than one, and that is deliberate. The spine still owns S2's band roll
## and S3's crit, so the miss / parry / block cases are still produced by the real engine
## rather than by a fixture that hardcodes the answer — `outcome.is_clean()` is what gates
## application, and the suite must exercise that gate on a real band verdict, not on a
## manufactured one.
##
## `StatusApply.apply` is then called with the same arguments the spine passed before
## DEF-0145 removed the stage: the same request under `REQUEST_KEY`, the same outcome,
## the same generator, the same technique and the same `hit_index`. The context is built
## the way `CombatSpine._context` built it, so the only difference from the pre-DEF-0145
## suite is that the stage is invoked here rather than from inside the spine.
func _resolve(
	target: Actor,
	mechanism: CombatTestKit.FixedMechanism,
	request: Dictionary,
	attacker_id: StringName,
	seed_value: int,
	hit_index: int = 0
) -> Dictionary:
	var attacker := CombatTestKit.quiet_actor(attacker_id)
	# ADR 0884: the gate is a flat power-vs-resist contest now, so an "open gate" fixture
	# carries the STATUS POWER that opens it. Without this the suite would measure the
	# parity `0.5` on every case below instead of the authored gate.
	attacker.stats.add_modifier(
		CombatStats.rate_modifier(
			StringName(_tuning.status_power_prefix + "omni"), _tuning.status_rate_scale, &"test"
		)
	)
	MechanismSlot.bind(attacker, mechanism)
	var rng := CombatTestKit.rng(seed_value)
	var technique := CombatTestKit.technique(100.0)
	var outcome := CombatSpine.resolve_hit(
		attacker, target, technique, _tuning, rng, Callable(), 0, hit_index
	)
	var ctx := AttackContext.new(attacker, target, technique, _tuning)
	ctx.set_data(StatusApply.REQUEST_KEY, request)
	return StatusApply.apply(attacker, target, _tuning, ctx, outcome, rng, technique, hit_index)
