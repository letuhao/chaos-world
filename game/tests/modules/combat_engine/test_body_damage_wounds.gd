extends "res://tests/modules/combat_engine/body_damage_fixture.gd"

## ADR 0070: the WOUND LEDGER — severity in integrity units, two thresholds, and a
## NECROSIS that never clears.
##
## ## Why severity is measured in integrity
##
## `severity += damage / body_integrity.maximum`, the identical shape
## `BodyAdvancement._deviate` already writes at `advancement.gd:345`
## (`-integrity_maximum * 0.25`). That is what makes the two the SAME wound expressed
## twice: one costs a cultivator a realm through a failed breakthrough, the other costs
## one through a good fighter, with no third number to keep in step. The divisor is the
## pool's `maximum` and NEVER its `current`, and the first test asserts that rather than
## arguing it.
##
## The aim modes and the degradation cases are in `test_body_damage_aim.gd`.

# --- severity, and the wound threshold ------------------------------------------


## Severity accumulates in INTEGRITY units, and a wound below `WOUND_THRESHOLD` writes a
## severity and nothing else: the channel is NOT injured, so a ledger that wounded on
## every hit would have no threshold at all.
func test_severity_is_measured_in_integrity_and_a_small_gash_writes_no_flag() -> void:
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var channel := target.meridians.get_meridian(&"lung")
	var wounds := BodyWounds.new()
	var maximum := _integrity_maximum(target)
	assert_almost_eq(maximum, INTEGRITY_MAXIMUM, "the shipped integrity pool, off the actor")
	assert_eq(
		_tuning.integrity_pool_id,
		BodyStats.BODY_INTEGRITY,
		"and the pool is named in DATA (BRIEF 1.7), so the two cannot drift"
	)

	var result := wounds.add(
		target, &"lung", _severity_for(target, _tuning.wound_threshold * 0.5), _tuning
	)
	assert_eq(bool(result[BodyWounds.KEY_WOUNDED]), false, "below WOUND_THRESHOLD: not wounded")
	assert_eq(channel.injured, false, "and the channel is untouched")
	assert_almost_eq(
		wounds.severity_of(&"lung"), _tuning.wound_threshold * 0.5, "but the severity IS written"
	)

	# The divisor is `maximum`, not `current`: spending half the pool must NOT halve the
	# severity the next gash costs.
	target.change_resource(BodyStats.BODY_INTEGRITY, -maximum * 0.5)
	var after := wounds.add(target, &"lung", _severity_for(target, 0.1), _tuning)
	assert_almost_eq(
		float(after[BodyWounds.KEY_TOTAL]),
		_tuning.wound_threshold * 0.5 + 0.1,
		"the divisor is the pool's MAXIMUM, so a hurt body does not get cheap wounds"
	)
	assert_eq(bool(after[BodyWounds.KEY_WOUNDED]), true, "and this one crossed the threshold")
	assert_eq(channel.injured, true, "so the EXISTING damage_meridian ran")
	assert_eq(channel.get_bonus(), 0.5, "halving the aggregate bonus for EVERY path")


## The two thresholds, in order, on one channel, each asserted at its own crossing.
## `NECROSIS_THRESHOLD` is deliberately ONE failed breakthrough's worth, so a good fighter
## costs a cultivator a realm through the wound the existing failure path already writes.
##
## The quality floor is a FLOOR — a gash must never be a promotion — and exactly ONE point
## is jammed, the highest-quality survivor, because a second jam on the same channel would
## spend the necrosis on nothing.
func test_severity_crosses_the_wound_threshold_and_then_the_necrosis_threshold() -> void:
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var points_on_target: AcupointSet = target.component(&"acupoints")
	var points := _points_on(target, &"lung")
	var channel := target.meridians.get_meridian(&"lung")
	var wounds := BodyWounds.new()
	assert_eq(points.size() > 1, true, "the lung carries several huyệt to choose between")

	wounds.add(target, &"lung", _severity_for(target, _tuning.wound_threshold), _tuning)
	assert_eq(channel.injured, true, "crossing WOUND_THRESHOLD calls damage_meridian")
	assert_eq(wounds.is_wounded(&"lung"), true, "and the ledger reports wounded")
	assert_eq(wounds.is_necrotic(&"lung"), false, "which is NOT necrosis")
	assert_almost_eq(_tuning.necrosis_threshold, 0.25, "NECROSIS_THRESHOLD is one deviation's cost")

	var result := wounds.add(
		target, &"lung", _severity_for(target, _tuning.necrosis_threshold), _tuning
	)
	assert_eq(bool(result[BodyWounds.KEY_NECROSED]), true, "crossing NECROSIS necroses")
	assert_eq(wounds.is_necrotic(&"lung"), true, "and the ledger records it")
	assert_ne(String(result[BodyWounds.KEY_JAMMED]), "", "exactly one point is named")
	assert_eq(
		StringName(result[BodyWounds.KEY_JAMMED]),
		points[0].id,
		"the HIGHEST-quality survivor is the one spent"
	)
	assert_eq(points[0].blocked, true, "and it is blocked")
	assert_eq(
		points_on_target.open_count(),
		points_on_target.points.size() - 1,
		"so open_count dropped by one"
	)
	for point in points:
		assert_eq(
			point.quality <= _tuning.necrosis_quality + 0.0001,
			true,
			"%s was floored to NECROSIS_QUALITY -- a gash is never a promotion" % String(point.id)
		)
	# A second hit does NOT necrosis twice and never jams a second point: the jam is spent
	# once, and necrosis is a `bool` rather than a number to re-cross.
	var second := wounds.add(target, &"lung", _severity_for(target, 1.0), _tuning)
	assert_eq(bool(second[BodyWounds.KEY_NECROSED]), false, "necrosis does not re-fire")
	assert_eq(points_on_target.blocked_count(), 1, "and no second point was spent")


## NECROSIS IS PERMANENT and the permanence is ARITHMETIC, not an `if`. Decay bleeds
## severity — so the number visibly improves, which is what makes the claim readable — and
## floors a necrotic channel at `necrosis_threshold` exactly. `is_necrotic` never clears
## and decay never repairs, so waiting is not a second recovery route and the ADR 0031 item
## stays the only clearable one ADR 0070 names.
func test_decay_improves_the_number_and_never_clears_the_necrotic_state() -> void:
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var points := _points_on(target, &"lung")
	var wounds := BodyWounds.new()
	wounds.add(target, &"lung", _severity_for(target, _tuning.necrosis_threshold * 4.0), _tuning)
	assert_eq(wounds.is_necrotic(&"lung"), true, "necrotic")
	assert_eq(points[0].blocked, true, "and one point is jammed")
	var before := wounds.severity_of(&"lung")
	assert_eq(before > _tuning.necrosis_threshold, true, "well past the threshold")

	var report := wounds.decay(1.0, _tuning)
	assert_eq(int(report["decayed"]), 1, "the number did decay")
	var after := wounds.severity_of(&"lung")
	assert_eq(after < before, true, "and it VISIBLY improved: %f -> %f" % [before, after])
	assert_almost_eq(after, before - _tuning.wound_decay, "by exactly wound_decay per second")
	assert_eq(wounds.is_necrotic(&"lung"), true, "but the necrotic state never cleared")
	assert_eq(points[0].blocked, true, "and the jam is untouched by decay")

	# Long enough that decay alone would take it BELOW the threshold many times over. The
	# floor is what holds, and the channel rests at exactly it.
	wounds.decay(1.0e6, _tuning)
	assert_almost_eq(
		wounds.severity_of(&"lung"),
		_tuning.necrosis_threshold,
		"a million seconds of decay floors at necrosis_threshold exactly"
	)
	assert_eq(wounds.is_necrotic(&"lung"), true, "still necrotic")
	assert_eq(points[0].blocked, true, "and still jammed")

	# Decay never REPAIRS the channel either: injury is the recovery item's business.
	assert_eq(
		target.meridians.get_meridian(&"lung").injured, true, "an injured channel stays injured"
	)
	target.meridians.repair_meridian(&"lung")
	assert_eq(
		target.meridians.get_meridian(&"lung").injured, false, "only repair_meridian clears it"
	)
	# And the floor is SPECIFIC rather than "severity never falls": an ordinary wound does
	# decay all the way to zero.
	var shallow := BodyWounds.new()
	shallow.add(target, &"spleen", _severity_for(target, 0.02), _tuning)
	shallow.decay(1.0e6, _tuning)
	assert_eq(shallow.severity_of(&"spleen"), 0.0, "an ordinary wound decays away entirely")
	assert_eq(shallow.is_necrotic(&"spleen"), false, "and was never necrotic to begin with")
	# A negative delta is a no-op rather than a wound being HEALED backwards.
	var frozen := wounds.severity_of(&"lung")
	wounds.decay(-100.0, _tuning)
	assert_almost_eq(wounds.severity_of(&"lung"), frozen, "a negative tick changes nothing")


## A body with no integrity pool writes NO wound and says so — the honest degradation, and
## the same shape `QiDamage._resistance_of` gives a `0.0` divisor. `body_integrity` stays
## the body's SINGLE reservoir (ADR 0028), so a missing one is a body with no wound
## vocabulary rather than a division by zero.
func test_a_body_with_no_integrity_pool_writes_no_wound_and_does_not_divide() -> void:
	var wounds := BodyWounds.new()
	var result := wounds.add(CombatTestKit.actor(&"dummy"), &"lung", 500.0, _tuning)
	assert_eq(float(result[BodyWounds.KEY_TOTAL]), 0.0, "nothing was written")
	assert_eq(bool(result[BodyWounds.KEY_WOUNDED]), false, "and nothing was wounded")
	assert_eq(is_finite(float(result[BodyWounds.KEY_TOTAL])), true, "and the number is finite")

	assert_eq(
		float(wounds.add(_defender(["lung"]), &"", 10.0, _tuning)[BodyWounds.KEY_TOTAL]),
		0.0,
		"an empty meridian id writes nothing"
	)
	assert_eq(
		float(wounds.add(_defender(["lung"]), &"lung", 10.0, null)[BodyWounds.KEY_TOTAL]),
		0.0,
		"a null tuning has no thresholds and no pool id, so it writes nothing"
	)
	for damage in [0.0, -1.0, -1.0e9, NAN, INF]:
		var ledger := BodyWounds.new()
		assert_eq(
			float(ledger.add(_defender(["lung"]), &"lung", damage, _tuning)[BodyWounds.KEY_TOTAL]),
			0.0,
			"damage %s writes nothing" % str(damage)
		)
	assert_eq(int(wounds.apply_all(null, [], _tuning).size()), 0, "a null target applies none")
	assert_eq(BodyDamage.decay(null, 1.0, _tuning).is_empty(), true, "a null ledger decays to {}")
	assert_eq(
		int(BodyDamage.new().apply_wounds(null, DamageProposal.new(10.0), _tuning).size()),
		0,
		"and a null proposal applies nothing"
	)
	# A body whose meridian is not in the ledger at all still writes, so a wound is never
	# silently dropped for want of a prior entry.
	var fresh := BodyWounds.new()
	assert_eq(
		float(fresh.add(_defender(["lung"]), &"lung", 1.0, _tuning)[BodyWounds.KEY_TOTAL]) > 0.0,
		true,
		"an untracked meridian still accrues"
	)


## The ledger ROUND-TRIPS as raw data, because `Actor.to_dict` carries module state as data
## and never as a typed object — and a save that could not restore a necrotic channel would
## quietly un-necrose it, which is the one thing ADR 0070 forbids.
func test_the_ledger_round_trips_through_its_raw_dict() -> void:
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var wounds := BodyWounds.new()
	wounds.add(target, &"lung", _severity_for(target, _tuning.necrosis_threshold * 2.0), _tuning)
	var restored := BodyWounds.new()
	restored.load_from(wounds.to_dict())
	assert_eq(restored.is_necrotic(&"lung"), true, "necrosis survived the round trip")
	assert_almost_eq(
		restored.severity_of(&"lung"), wounds.severity_of(&"lung"), "and so did the severity"
	)
	restored.decay(1.0e6, _tuning)
	assert_almost_eq(
		restored.severity_of(&"lung"), _tuning.necrosis_threshold, "and the floor still holds"
	)
	assert_eq(restored.is_necrotic(&"lung"), true, "so a restored save cannot un-necrose")
	# A zero severity is dropped rather than restored as a wound that decayed to nothing:
	# `to_dict` says those are different facts.
	var blank := BodyWounds.new()
	var zeroed := BodyWounds.new()
	zeroed.severity["lung"] = 0.0
	blank.load_from(zeroed.to_dict())
	assert_eq(blank.severity.has("lung"), false, "a zero severity is not a wound")


## A landed hit carries its wound as an `effects[]` entry of the body path's OWN kind, and
## it lands AFTER health (ADR 0067) — the only ordering under which a wound may exist, and
## `contracts/location_resolver.gd`'s own `apply_wound` writes nothing for exactly that
## reason. Asserted through the SPINE, so the effects the outcome carries are the ones the
## eleven stages produced rather than ones a direct call manufactured.
##
## Severity is measured off the S4 SUBTOTAL, never the post-S8 amount, so the chip floor can
## never mint a wound out of a strike the flat subtraction already refused.
func test_a_landed_hit_carries_its_wound_as_an_effect_after_health() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var technique := _technique(100.0, &"lung")
	var mechanism := BodyDamage.new()
	mechanism.tuning = _tuning
	MechanismSlot.bind(attacker, mechanism)
	var health_before := target.resource(&"health").current
	var outcome := CombatSpine.resolve_hit(
		attacker,
		target,
		technique,
		_tuning,
		null,
		BodyDamage.builder(technique, null, BodyLocation.MODE_NAMED)
	)
	assert_eq(outcome.missed, false, "a null rng lands every attack")
	assert_eq(outcome.health_delta < 0.0, true, "health was spent")
	assert_almost_eq(
		target.resource(&"health").current, health_before + outcome.health_delta, "exactly"
	)
	var effect: Dictionary = outcome.proposal.effect_of(BodyWounds.EFFECT_KIND)
	assert_ne(effect.is_empty(), true, "the wound travelled as an effect")
	assert_eq(StringName(effect[BodyWounds.KEY_MERIDIAN]), &"lung", "naming the struck meridian")
	assert_eq(float(effect[BodyWounds.KEY_SEVERITY]) > 0.0, true, "carrying a severity")
	assert_eq(
		DamageProposal.is_primitive_effect(effect),
		true,
		"and it is primitives only -- effects[] travel into save and summary payloads"
	)
	assert_almost_eq(
		float(effect[BodyWounds.KEY_SEVERITY]),
		float(
			(
				mechanism
				. breakdown(_context(attacker, target, technique, BodyLocation.MODE_NAMED))["subtotal"]
			)
		),
		"severity is measured off the S4 SUBTOTAL, not the post-reduction amount",
		0.0001
	)
	# Nothing has been settled yet: the wound lands after health, by the caller.
	assert_eq(
		target.meridians.get_meridian(&"lung").injured, false, "the channel is not yet injured"
	)
	var settled := mechanism.apply_wounds(target, outcome.proposal, _tuning)
	assert_eq(int(settled.size()), 1, "one wound settled")
	assert_almost_eq(
		float(settled[0][BodyWounds.KEY_TOTAL]),
		float(effect[BodyWounds.KEY_SEVERITY]) / _integrity_maximum(target),
		"and its severity is the damage over the integrity maximum"
	)
	# A broad hit carries ONE effect per struck channel, all on distinct meridians, and
	# the caller settles all of them — which is the assertion that S4 and S5 cannot
	# disagree about how many meridians were hit.
	var swept := mechanism.resolve(
		_context(attacker, target, _technique(100.0, &""), BodyLocation.MODE_BROAD)
	)
	var seen: Dictionary = {}
	for entry in swept.effects:
		var typed: Dictionary = entry
		seen[StringName(typed[BodyWounds.KEY_MERIDIAN])] = true
	assert_eq(seen.size(), swept.effects.size(), "no meridian carries two wounds from one sweep")
	assert_eq(
		int(mechanism.apply_wounds(target, swept, _tuning).size()),
		swept.effects.size(),
		"and every struck channel's wound is settled by the one call"
	)


## `breakdown()` is primitives only — ADR 0038's UI standard, and the method a panel will
## read. The `sites[]` rows are deliberately `Array[Dictionary]` of strings and floats rather
## than the richer rows `BodyLocation` builds, so an effect a plain dictionary gate can check
## on its own is one that reaches a `summary()` payload.
func test_breakdown_is_primitives_only() -> void:
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var parts := _parts(_attacker(), target, BodyLocation.MODE_NAMED, &"lung")
	for key in parts.keys():
		var value: Variant = parts[key]
		if key == "sites":
			continue
		var primitive := (
			value is float
			or value is int
			or value is bool
			or value is String
			or value is StringName
		)
		assert_eq(primitive, true, "key %s carries a primitive" % String(key))
	for row in parts["sites"]:
		var site: Dictionary = row
		for key in ["meridian_id", "point_id"]:
			assert_eq(site[key] is String, true, "site key %s is a String" % String(key))
		assert_eq(is_finite(float(site["damage"])), true, "site damage is a finite number")
	assert_eq(
		(
			DamageProposal
			. is_primitive_effect(
				{
					DamageProposal.KIND: BodyWounds.EFFECT_KIND,
					BodyWounds.KEY_MERIDIAN: &"lung",
					BodyWounds.KEY_SEVERITY: 0.1,
				}
			)
		),
		true,
		"and the wound effect the mechanism builds passes the contract's own gate"
	)
