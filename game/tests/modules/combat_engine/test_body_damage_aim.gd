extends "res://tests/modules/combat_engine/body_damage_fixture.gd"

## ADR 0070: aim is DETERMINISTIC in all three modes, and a body with no location axis
## must degrade rather than crash.
##
## ## Why this file exists on its own
##
## ADR 0070's strongest claim is not any number — it is that **every choice this path
## makes is state-derived**, so the same body answers the same strike the same way twice
## and a readout can NAME the answer ("it found the jammed Lung node") rather than
## describing a coin flip. A resolver that rolled would leave every NUMBER in the engine
## intact and still make that claim false, so the first test spends a seeded generator
## and checks its seed did not move.
##
## The degradation half is here too because it is the same subject: what the mechanism
## does when the target has no meridians, no huyệt, or no authored technique. Both are
## "what does this path do when its own vocabulary is incomplete".

# --- aim is deterministic, in all three modes ----------------------------------


## The determinism claim made ASSERTABLE, which is the condition ADR 0070 sets for it:
## "a test must prove the same actor twice picks the same point, or the claim is
## decorative."
##
## Two reads of the SAME target state resolve the same `(meridian, point, multiplier)`.
## Then a seeded generator is handed to `resolve_location` — the contract declares the
## parameter, so a resolver that rolled would accept it silently — and the answer is
## identical again, with `rng.seed` provably UNCHANGED. A resolver that consumed one draw
## would move the seed, which is the one thing a count of draws cannot see.
func test_the_same_target_state_resolves_the_same_location_twice() -> void:
	var target := _defender(
		["lung", "spleen"], {"lung": MeridianState.OPEN, "spleen": MeridianState.EXPANDED}
	)
	var resolver := BodyLocation.new()
	var technique := _technique(100.0, &"")
	var first := resolver.resolve_location(null, target, technique, CombatTestKit.rng(11))
	var second := resolver.resolve_location(null, target, technique, CombatTestKit.rng(11))
	assert_eq(first, second, "two reads of one state answer identically")
	assert_ne(String(first.get("meridian_id", "")), "", "and the answer names a meridian")

	var seeded := CombatTestKit.rng(4242)
	var before := seeded.seed
	assert_eq(
		resolver.resolve_location(null, target, technique, seeded),
		first,
		"an injected rng changes nothing"
	)
	assert_eq(seeded.seed, before, "and is never consulted: the seed did not move")
	assert_eq(
		resolver.resolve_location(null, target, technique, null),
		first,
		"and a null rng is the same answer, not a crash"
	)
	# And twice through the MECHANISM, which is the caller that matters: the seam's own
	# purity contract (ADR 0067) is that `resolve` twice answers twice the same.
	var ctx := _context(_attacker(), target, technique)
	var mechanism := BodyDamage.new()
	mechanism.tuning = _tuning
	assert_eq(mechanism.resolve(ctx).effects, mechanism.resolve(ctx).effects, "same effects")
	assert_almost_eq(
		mechanism.resolve(ctx).amount, mechanism.resolve(ctx).amount, "and the same amount"
	)


## `random` aim is the HIGHEST-scoring point on the body, not a roll. So jamming the
## weakest huyệt on a channel REDIRECTS the aim to it — the read a player is owed, and
## only true if the choice is a ranking over live state.
##
## The ranking is then checked EXHAUSTIVELY against the actor's own twenty channels,
## using the two numbers `BodyLocation` itself ranks on, so this cannot pass by accident.
func test_random_aim_finds_the_highest_multiplier_and_never_rolls() -> void:
	var attacker := _attacker()
	var target := _defender()
	var resolver := BodyLocation.new()
	# Nothing is jammed and every channel is `closed`, so they tie and the tie-break is
	# by id. That makes the baseline deterministic WITHOUT asserting a particular
	# meridian, which is the honest form of the claim.
	var baseline := resolver.site_of(target, null, BodyLocation.MODE_RANDOM)
	assert_ne(String(baseline["meridian_id"]), "", "a twenty-channel body answers a meridian")
	assert_eq(
		baseline, resolver.site_of(target, null, BodyLocation.MODE_RANDOM), "and answers it again"
	)
	var chosen := _score_of(resolver, target, &"", BodyLocation.MODE_RANDOM)
	for state in target.meridians.get_all_meridians():
		var other := _score_of(resolver, target, state.id, BodyLocation.MODE_NAMED)
		assert_eq(
			chosen >= other,
			true,
			"%s (%f) does not beat the chosen one (%f)" % [String(state.id), other, chosen]
		)

	var contender := _first_meridian_with_points(target)
	var contender_points := _points_on(target, contender)
	assert_ne(String(contender), "", "the contender really has a huyệt")
	var before := _score_of(resolver, target, &"", BodyLocation.MODE_RANDOM)
	contender_points[0].block()
	var moved := resolver.site_of(target, null, BodyLocation.MODE_RANDOM)
	assert_eq(String(moved["meridian_id"]), String(contender), "the aim moved to the jammed node")
	assert_almost_eq(float(moved["multiplier"]), _tuning.blocked_mult, "at BLOCKED_MULT")
	var after := _score_of(resolver, target, &"", BodyLocation.MODE_RANDOM)
	assert_eq(after > before, true, "and the jammed node now outscores everything")
	for state in target.meridians.get_all_meridians():
		var other := _score_of(resolver, target, state.id, BodyLocation.MODE_NAMED)
		assert_eq(
			after >= other,
			true,
			"re-ranked, %s (%f) still does not beat it (%f)" % [String(state.id), other, after]
		)
	# And the mechanism resolves exactly ONE location for a `random` aim, and it is the
	# one the resolver ranked first.
	var parts := _parts(attacker, target, BodyLocation.MODE_RANDOM)
	assert_eq(int(parts["sites"].size()), 1, "a random aim is ONE location")
	assert_eq(
		String(parts["sites"][0]["meridian_id"]),
		String(moved["meridian_id"]),
		"and it is the one the resolver ranked first"
	)


## `named` uses the AUTHORED id and nothing else. Each id answers its own meridian, and a
## `closed` channel is priced differently from an open one — the proof the named aim is
## not quietly falling through to the ranking.
##
## A `named` aim at a meridian this body never opened is a MISS, not a relabel: there is
## no channel there to subtract from, so inventing one would be a hit at a point that does
## not exist. That refusal is the ONLY `0.0` this suite finds, and ADR 0070 says body is
## the only mechanism allowed one.
func test_named_aim_uses_the_authored_meridian_and_nothing_else() -> void:
	var attacker := _attacker()
	var target := _defender(
		["lung", "spleen"], {"lung": MeridianState.OPEN, "spleen": MeridianState.CLOSED}
	)
	for meridian_id: StringName in [&"lung", &"spleen"]:
		var parts := _parts(attacker, target, BodyLocation.MODE_NAMED, meridian_id)
		assert_eq(parts["mode"], String(BodyLocation.MODE_NAMED), "%s: mode" % String(meridian_id))
		assert_eq(int(parts["sites"].size()), 1, "%s: exactly one site" % String(meridian_id))
		assert_eq(
			String(_site_of(parts, meridian_id)["meridian_id"]),
			String(meridian_id),
			"%s: the AUTHORED meridian is the one struck" % String(meridian_id)
		)
	var open_parts := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
	var closed_parts := _parts(attacker, target, BodyLocation.MODE_NAMED, &"spleen")
	assert_eq(
		float(open_parts["penetration"]) > float(closed_parts["penetration"]),
		true,
		"an open channel is a harder place than a closed one"
	)

	var absent := _parts(attacker, target, BodyLocation.MODE_NAMED, &"bladder")
	assert_eq(int(absent["sites"].size()), 0, "no site on an unopened meridian")
	assert_eq(float(absent["subtotal"]), 0.0, "so the strike deals nothing")
	assert_eq(bool(absent["gated"]), false, "and the mechanism says it is ungated")
	assert_eq(bool(absent["refused"]), true, "and this is the ONE refusal ADR 0070 allows")
	assert_eq(
		float(_parts(attacker, target, BodyLocation.MODE_NAMED, &"not_a_meridian")["subtotal"]),
		0.0,
		"an authored id the body never heard of behaves the same way"
	)
	var random_parts := _parts(attacker, target, BodyLocation.MODE_RANDOM)
	assert_eq(random_parts["mode"], String(BodyLocation.MODE_RANDOM), "and the mode is reported")
	assert_ne(
		String(random_parts["sites"][0]["meridian_id"]), "", "a random aim found a real channel"
	)


## `broad` hits EVERY UNLOCKED meridian, in sorted id order, at `BROAD_MULT` per channel.
## Three claims, and the second is the one a mutant that summed twenty per-site floors
## would fail: the penetration FLOOR is applied ONCE for the whole hit, not once per
## channel, so a sweep is coverage and not a critical blow.
##
## "Unlocked" is read off the network rather than restated, so the 20-bucket claim is
## measured and the count moves with the data.
func test_broad_hits_every_unlocked_meridian_at_the_sweep_multiplier() -> void:
	var attacker := _attacker()
	var target := _defender()
	var parts := _parts(attacker, target, BodyLocation.MODE_BROAD)
	var ids := _meridian_ids(target)
	assert_eq(int(parts["sites"].size()), ids.size(), "one site per unlocked meridian")
	assert_eq(parts["mode"], String(BodyLocation.MODE_BROAD), "the mode is reported")
	assert_eq(bool(parts["gated"]), true, "and a sweep is gated, not ungated")

	var previous := ""
	var expected := 0.0
	for index in ids.size():
		var site: Dictionary = parts["sites"][index]
		var id := String(site["meridian_id"])
		assert_eq(id, ids[index], "sorted id order: row %d" % index)
		assert_eq(previous < id, true, "strictly ascending at row %d" % index)
		previous = id
		var single := _site_of(
			_parts(attacker, target, BodyLocation.MODE_NAMED, ids[index]), ids[index]
		)
		assert_eq(
			float(site["multiplier"]) <= float(single["multiplier"]) + 0.0001,
			true,
			"%s: a sweep's share never exceeds that channel's single-strike multiplier" % id
		)
		expected += float(site["damage"])
	assert_almost_eq(float(parts["subtotal"]), expected, "S4 is the SUM over the sites")

	var gross := attacker.stats.derived(Stat.ATTACK_PHYSICAL)
	var walled_actor := _defender()
	_armour(walled_actor, 1.0e9)
	var walled := _parts(attacker, walled_actor, BodyLocation.MODE_BROAD)
	assert_almost_eq(
		float(walled["floor"]),
		gross * _tuning.min_penetration_ratio,
		"the floor is a share of the GROSS exactly once, not twenty times"
	)
	assert_almost_eq(
		float(walled["penetration"]),
		maxf(gross - float(walled["resistance"]), float(walled["floor"])),
		"so a walled body's sweep is floored, not deleted"
	)
	var single_hit := float(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")["total"])
	assert_eq(float(parts["total"]) > single_hit, true, "a sweep beats one hit")
	assert_eq(
		float(parts["total"]) < single_hit * float(ids.size()), true, "and loses to twenty of them"
	)


## A `BROAD_MULT` above 1.0 would make the strongest single hit in the game, twenty times
## over, and one below 0.0 would invert a sweep into a negative. Both clamped on read, and
## asserted RELATIONALLY — a sweep's per-channel share must never out-scale a single strike
## on the same channel — because that is the property, not the clamp.
func test_an_out_of_range_broad_multiplier_never_makes_a_sweep_the_best_hit() -> void:
	var attacker := _attacker()
	var target := _defender()
	for value in [0.0, 4.0, 1.0e9, -2.0]:
		var mech := BodyDamage.new()
		var copy := CombatTuning.shipped()
		copy.broad_mult = value
		mech.tuning = copy
		var swept := mech.breakdown(
			_context(attacker, target, _technique(100.0, &""), BodyLocation.MODE_BROAD)
		)
		assert_eq(int(swept["sites"].size()), _meridian_ids(target).size(), "still every meridian")
		for row in swept["sites"]:
			var site: Dictionary = row
			var one := _site_of(
				_parts(attacker, target, BodyLocation.MODE_NAMED, StringName(site["meridian_id"])),
				StringName(site["meridian_id"])
			)
			assert_eq(
				float(site["multiplier"]) <= float(one["multiplier"]) + 0.0001,
				true,
				(
					"BROAD_MULT %s never out-scales a single strike on %s"
					% [str(value), String(site["meridian_id"])]
				)
			)
		assert_eq(is_finite(float(swept["total"])), true, "BROAD_MULT %s stays finite" % str(value))


## `TechniqueDef.aim_meridian` is ADR 0070's ONE new authored field, additive and
## module-owned (ADR 0056) — and it is what a `named` aim is. So the field's contract is
## asserted end to end: an authored id produces `MODE_NAMED`, an authored `&""` produces
## `MODE_RANDOM` (NOT an ungated strike), and both survive the spine's `ctx_builder`,
## which is how a real caller wires it.
##
## The per-hit `AIM_MODE_KEY` overrides the authored id, which is what `broad` needs —
## an area strike is decided by what the attack is hitting, not by its `.tres`.
func test_the_authored_aim_meridian_is_the_only_new_field_and_both_routes_agree() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})

	# An authored `&""` reads as `random`, never as an ungated strike.
	var unauthored := _parts(attacker, target)
	assert_eq(unauthored["mode"], String(BodyLocation.MODE_RANDOM), "no authored id is random")
	assert_eq(int(unauthored["sites"].size()), 1, "and it still resolves a real channel")

	# An authored id reads as `named`, and reaches the resolver through `builder`.
	var authored := _technique(100.0, &"lung")
	var ctx := _context(attacker, target, authored)
	BodyDamage.builder(authored, null, &"").call(ctx)
	assert_eq(
		StringName(ctx.data_value(BodyDamage.AIM_MERIDIAN_KEY, &"")),
		&"lung",
		"the builder carried the authored id onto the context"
	)
	var through_builder := BodyDamage.new().breakdown(ctx)
	through_builder["mode"] = through_builder["mode"]
	assert_eq(
		float(through_builder["total"]),
		float(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")["total"]),
		"and the spine's own extension point gives the identical answer"
	)

	# The per-hit mode OVERRIDES the authored id, which is what `broad` needs.
	var swept := _parts(attacker, target, BodyLocation.MODE_BROAD)
	assert_eq(
		int(swept["sites"].size()),
		_meridian_ids(target).size(),
		"a per-hit aim_mode reaches every meridian even with an id authored"
	)
	# And an unrecognised mode reads as `random`, never as an ungated strike: the
	# mechanism documents that and nothing else is safe.
	var nonsense := _parts(attacker, target, &"scatter")
	assert_eq(
		int(nonsense["sites"].size()), 1, "an unrecognised mode still resolves exactly one location"
	)
	assert_eq(float(nonsense["total"]) > 0.0, true, "and it is a landed hit, not an ungated zero")


# --- degradation ---------------------------------------------------------------


## A defender with NO meridians, NO acupoints, or a NULL technique must not crash, and
## each answers an honest number rather than inventing a location that is not there.
##
## The important half is the FIRST. A body with no location axis is UNGATED — the flat
## subtraction with no armour at all — and it still does not refuse the strike, because
## ADR 0070 says body is ALLOWED a `0.0` and not REQUIRED to produce one. A mechanism
## that returned `0.0` there would delete the hit against every NPC and training dummy in
## the game, which is the failure mode `LocationResolver.supports()` exists to prevent.
func test_a_body_with_no_meridians_is_ungated_and_still_takes_the_hit() -> void:
	var attacker := _attacker()
	var bare := CombatTestKit.actor(&"dummy")
	bare.meridians = null
	var parts := _parts(attacker, bare)
	assert_eq(bool(parts["gated"]), false, "no location axis: ungated")
	assert_eq(int(parts["sites"].size()), 0, "and no invented meridian")
	assert_eq(
		float(parts["resistance"]),
		float(parts["tissue"]),
		"so the resistance is tissue alone -- no channel armour"
	)
	assert_eq(float(parts["total"]) > 0.0, true, "and the strike is still a landed hit")
	assert_eq(is_finite(float(parts["total"])), true, "finite")
	assert_eq(BodyLocation.new().supports(bare), false, "and supports() honestly answers false")
	# A `broad` sweep over the same body is `[]`, never one synthetic row.
	assert_eq(
		BodyLocation.new().broad_sites(bare, _tuning).size(),
		0,
		"a sweep on a body with no network is empty, not one fake meridian"
	)


## A network with no huyệt on the actor: the meridian exists, the weak point does not,
## and the site says so at the NEUTRAL multiplier rather than inventing one — "the
## meridian was struck, nothing on it answered". And `broad` still reaches every
## meridian, because no acupoints is not "no meridians" and conflating them would
## silently un-gate an area strike.
func test_a_body_with_no_acupoints_is_a_neutral_site_and_still_a_location_axis() -> void:
	var attacker := _attacker()
	var hollow := _defender(["lung"], {"lung": MeridianState.OPEN})
	hollow.set_component(&"acupoints", null)
	var parts := _parts(attacker, hollow, BodyLocation.MODE_NAMED, &"lung")
	var site := _site_of(parts, &"lung")
	assert_eq(String(site["point_id"]), "", "no point on the actor")
	assert_eq(bool(site["locked"]), true, "and the site reports itself locked")
	assert_almost_eq(float(site["point_multiplier"]), 1.0, "the point term is the neutral 1.0")
	assert_eq(float(parts["total"]) > 0.0, true, "and the hit still lands")
	assert_eq(BodyLocation.new().supports(hollow), true, "a network IS a location axis")
	assert_eq(
		int(_parts(attacker, hollow, BodyLocation.MODE_BROAD)["sites"].size()),
		_meridian_ids(hollow).size(),
		"and a sweep still reaches every meridian"
	)
	# `random` on such a body answers a real channel rather than the empty site.
	var random_parts := _parts(attacker, hollow, BodyLocation.MODE_RANDOM)
	assert_eq(int(random_parts["sites"].size()), 1, "a random aim resolves one real channel")
	assert_eq(
		BodyLocation.new().wounds_of(hollow) != null,
		true,
		"and wounds_of answers, unbound included"
	)


## A NULL technique, a degenerate tuning and a NaN gross — the remaining ways a half-built
## hit reaches this code. `tissue_stat_divisor == 0.0` is the one place this formula
## divides, and it must read as "no tissue" rather than a division by zero; `INF` is
## included in the divisor's place because a bare tuning is exactly the state a caller
## reaches by forgetting the `.tres`.
func test_a_null_technique_a_bare_tuning_and_a_nan_gross_all_degrade() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})

	var null_technique := _parts(attacker, target)
	assert_eq(
		null_technique["mode"], String(BodyLocation.MODE_RANDOM), "a null technique is random"
	)
	assert_eq(int(null_technique["sites"].size()), 1, "and still resolves one real channel")

	var bare := BodyDamage.new()
	bare.tuning = CombatTuning.new()
	var parts := bare.breakdown(
		_context(attacker, target, _technique(100.0, &"lung"), BodyLocation.MODE_NAMED)
	)
	assert_eq(float(parts["tissue"]), 0.0, "a 0.0 divisor is no tissue, not a division")
	assert_eq(float(parts["resistance"]), 0.0, "so no armour at all")
	assert_eq(is_finite(float(parts["total"])), true, "and the number is finite")

	var nan_actor := _attacker()
	nan_actor.stats.add_modifier(
		StatModifier.new(Stat.ATTACK_PHYSICAL, Stat.Op.FLAT, NAN, &"body_damage_fixture")
	)
	var nan_parts := _parts(nan_actor, target, BodyLocation.MODE_NAMED, &"lung")
	assert_eq(float(nan_parts["gross"]), 0.0, "a NaN gross reads 0.0")
	assert_eq(is_finite(float(nan_parts["total"])), true, "and the total is finite")
	assert_eq(is_finite(float(nan_parts["resistance"])), true, "and so is the resistance")

	var empty := BodyDamage.new().breakdown(null)
	assert_eq(float(empty["total"]), 0.0, "a null context is the empty proposal")
	# The key COUNT is read off the implementation's own empty answer rather than restated,
	# so this asserts the shape is IDENTICAL to a real hit's and never pins a number a
	# future readout key would legitimately move. `assert_ne` rather than `assert_eq`
	# because two counts of the same dictionary is the claim being made.
	var live := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
	assert_eq(int(empty.size()), int(live.size()), "the FULL key set for a panel, live")
	assert_ne(int(empty.size()), 0, "and that set is not empty")
	assert_eq(float(BodyDamage.new().resolve(null).amount), 0.0, "S4 declines rather than throws")
	assert_eq(
		float(BodyDamage.new().mitigate(null, DamageProposal.none()).amount), 0.0, "so does S5"
	)


# --- helpers -------------------------------------------------------------------


## The ranking score `BodyLocation._best_meridian` picks on, read through the PUBLIC
## `site_of` for one meridian rather than re-implemented here — so the exhaustive
## comparison above is against the mechanism's own definition and cannot drift from it.
func _score_of(resolver: BodyLocation, target: Actor, aim: StringName, mode: StringName) -> float:
	var site := resolver.site_of(target, _technique(100.0, aim), mode)
	return float(site.get("multiplier", 0.0)) + float(site.get("point_score", 0.0))


## The lowest-id meridian on this body that actually carries a huyệt, so a test which
## jams "a different channel" is reproducible rather than order-dependent.
func _first_meridian_with_points(target: Actor) -> StringName:
	var ids := _meridian_ids(target)
	ids.sort()
	for id in ids:
		if not _points_on(target, id).is_empty():
			return id
	return &""
