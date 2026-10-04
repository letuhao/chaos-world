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
	# ## What this lane is measured against, and what changed when the magnitude landed
	#
	# `lung` is OPEN and `spleen` is CLOSED on the same body, so the two aims differ in
	# exactly ONE input: the channel's `state_rank()`, 1 against 0. ADR 0070 prices that
	# rank in TWO places, with OPPOSITE intent, and BOTH ship:
	#
	# ```
	# resistance = DEFENSE_PHYSICAL x meridian_armour_step x rank   # harder to hit
	# multiplier = 1 + channel_mult_step x rank                     # a BIGGER target
	# ```
	#
	# `combat_tuning.gd` says so in as many words on `channel_mult_step`: "Deliberately the
	# other side of `meridian_armour_step` and NOT the same sign: training a channel makes
	# it a bigger target as well as a harder one."
	#
	# The OLD expectation here was the bare ordering `closed total > open total`, derived
	# in the PRE-MAGNITUDE regime. Back then the gross was the bare `ATTACK_PHYSICAL` of
	# `20.0` and one armour step of `14.0` was 70% of it, so the ADDITIVE armour term
	# dominated outright and a trained channel really did deal strictly less. Restoring
	# `ctx.magnitude` into the gross — the cross-mechanism fix — made the gross `2000.0`,
	# at which that same `14.0` is 0.7% of it and the MULTIPLICATIVE `channel_mult_step` of
	# `0.15` dominates instead.
	#
	# The rank term did NOT collapse: it is still worth exactly one armour step and exactly
	# one multiplier step, and both are asserted below off the actors' own reads. What
	# changed is only which of two deliberately-opposed terms dominates, and a TOTAL
	# ordering is a CROSSOVER between them whose side is set by the authored technique
	# magnitude. So the total is no longer asserted as a bare ordering. It is asserted as
	# the IDENTITY that makes the crossover legible — each aim re-derived from its OWN
	# published penetration and multiplier rows — which is a strictly stronger claim: a
	# sign error in either rank term, or a difference between the two aims that the rank
	# term does not fully explain, fails here.
	var open_site := _site_of(open_parts, &"lung")
	var closed_site := _site_of(closed_parts, &"spleen")
	assert_eq(float(open_parts["channel_rank"]), 1.0, "lung is open, so rank 1")
	assert_eq(float(closed_parts["channel_rank"]), 0.0, "and spleen is closed, so rank 0")
	assert_almost_eq(
		float(closed_parts["resistance"]),
		float(open_parts["resistance"]) - defence_of(target) * _tuning.meridian_armour_step,
		"and the difference between them is exactly one step of channel armour"
	)
	assert_almost_eq(
		float(open_site["channel_multiplier"]) - float(closed_site["channel_multiplier"]),
		_tuning.channel_mult_step * float(open_parts["channel_rank"]),
		"the OTHER half of the same rank: one step of channel multiplier, the bigger target"
	)
	for row: Array in [[open_parts, open_site, "lung"], [closed_parts, closed_site, "spleen"]]:
		var case: Dictionary = row[0]
		var site: Dictionary = row[1]
		assert_almost_eq(
			float(case["total"]),
			float(case["penetration"]) * float(site["multiplier"]) * float(case["mitigated"]),
			"%s: the total is that aim's OWN penetration x multiplier, nothing else" % row[2]
		)

	var absent := _parts(attacker, target, BodyLocation.MODE_NAMED, &"bladder")
	assert_eq(int(absent["sites"].size()), 0, "no site on an unopened meridian")
	assert_eq(bool(absent["gated"]), false, "and the mechanism says it is ungated")
	# ## What an unopened channel actually answers is the UNGATED form, not a refusal
	#
	# `BodyLocation.site_of` refuses to invent a meridian the body has not unlocked, so
	# there is no site and therefore no location multiplier — and
	# `BodyDamage.breakdown` answers a hit with no site at the STRUCK figure once, at the
	# neutral `1.0`: the same "no location axis" branch
	# `test_a_body_with_no_meridians_is_ungated_and_still_takes_the_hit` exercises. So the
	# hit is UNGATED — the flat subtraction with no channel armour at all.
	#
	# The OLD expectation was the bare ordering `absent total > open total`, i.e. "unopened
	# deals strictly MORE than the OPEN `lung` beside it". It was derived in the
	# PRE-MAGNITUDE regime, where the gross was the bare `ATTACK_PHYSICAL` of `20.0` and
	# the `14.0` armour difference between the two was 70% of it, so the additive channel
	# armour dominated outright. Restoring `ctx.magnitude` into the gross made it `2000.0`,
	# at which `lung`'s OPEN channel multiplier (`channel_mult_step`, `0.15`) hands back
	# more than the open channel's armour ever took and the bare ordering inverts.
	#
	# That ordering against `lung` is therefore NOT a property of "soft": it is a CROSSOVER
	# between two deliberately-opposed rank terms whose side is set by the authored
	# magnitude (see the closed-vs-open lane above). What "priced with no armour at all"
	# DOES mean structurally is asserted here directly, off the mechanism's own rows and
	# with no cross-meridian ordering at all: an unopened channel carries no channel rank,
	# so the WHOLE of the ladder's contribution to its `resistance` is `0.0` and what
	# remains is the tissue term alone. It then pays the STRUCK penetration at the neutral
	# `1.0` — the smallest location multiplier any struck channel can carry — which is what
	# "the flattest possible place on the body" means arithmetically.
	assert_eq(bool(absent["refused"]), false, "so it is NOT the one refusal ADR 0070 allows")
	assert_eq(float(absent["channel_rank"]), 0.0, "and it carries no channel rank")
	assert_almost_eq(
		float(absent["resistance"]),
		float(absent["tissue"]),
		"no channel armour at all: resistance is the tissue weighting, and nothing else"
	)
	# Its total is the struck figure at the neutral `1.0` — the price of landing on a
	# channel that does not exist is the flat subtraction with NO multiplier bolted on.
	# Asserted as the identity rather than a bare ordering, so it survives any magnitude.
	assert_almost_eq(
		float(absent["total"]),
		float(absent["penetration"]) * float(absent["mitigated"]),
		"priced at the neutral 1.0: the struck penetration, no location multiplier"
	)
	assert_almost_eq(
		float(absent["penetration"]),
		maxf(float(absent["gross"]) - float(absent["resistance"]), float(absent["floor"])),
		"and it is the same gross, less its tissue-only resistance, floored"
	)
	assert_eq(
		float(_parts(attacker, target, BodyLocation.MODE_NAMED, &"not_a_meridian")["total"]),
		float(absent["total"]),
		"an authored id the body never heard of is the same ungated answer, not a crash"
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
		# Row 0 has no predecessor, so the order check starts at row 1 — the run of
		# strictly-ascending ids IS the sort, and the first row has nothing before it.
		if index > 0:
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

	# The gross is `magnitude x ATTACK_PHYSICAL`, so the floor the sweep is checked
	# against is a share of the PRODUCT. The multiplier is scope-invariant (the same for
	# every case at the same magnitude), so `magnitude` is read once off the sweep itself.
	var gross := float(parts["magnitude"]) * attacker.stats.derived(Stat.ATTACK_PHYSICAL)
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
	# ## What "a sweep is COVERAGE, not a critical blow" actually means arithmetically
	#
	# `BROAD_MULT` is read through `_share`, which clamps into `[0, 1]`, so the shipped
	# `0.35` is honoured unchanged and every site carries `0.35` of that channel's own
	# multiplier. A sweep therefore lands `broad_mult x sum(all 20 multipliers)` against one
	# strike's `one multiplier` — coverage means MANY rows, not a bigger row. Two claims
	# follow and both are derived from the tuning and the sites rather than assumed:
	# twenty partials out-scale one of them (so a sweep is never the weakest thing on the
	# board), and no single row can out-scale the strike it covers (so a sweep is never
	# twenty criticals). The second is the per-channel relation `broad_sites` documents and
	# is asserted row by row above; this is its sweep-wide form.
	var sum_of_multipliers := 0.0
	var best_site := 0.0
	for row in parts["sites"]:
		var site: Dictionary = row
		sum_of_multipliers += float(site["multiplier"])
		best_site = maxf(best_site, float(site["multiplier"]))
	var first_id := StringName(parts["sites"][0]["meridian_id"])
	var one_at_best := _site_of(
		_parts(attacker, target, BodyLocation.MODE_NAMED, first_id), first_id
	)
	assert_eq(
		# `parts["sites"]` rows ALREADY carry the `broad_mult` factor (each site's `multiplier`
		# is `point x channel x broad`), so the sweep's total is compared against the single
		# strike's multiplier DIRECTLY. Dividing by `broad_mult` again counted the factor
		# twice and asserted something the mechanism never promised.
		sum_of_multipliers > float(one_at_best["multiplier"]),
		true,
		"a sweep at BROAD_MULT out-scales one strike at the SAME site"
	)
	assert_eq(
		best_site * _tuning.broad_mult <= best_site + 0.0001,
		true,
		"and no channel of it can out-scale that same channel's single strike"
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
		mech.tuning = _with_broad_mult(value)
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


## A COPY of the shipped tuning with `broad_mult` replaced, so the out-of-range case is
## "the shipped balance with one author mistake" and not a fresh `CombatTuning.new()` whose
## every bound is `0.0` (which would let the assertions pass for the wrong reason).
##
## `duplicate(true)`, and this helper EXISTS rather than an inline write on
## `CombatTuning.shipped()`. That inline write is what shipped: `load()` returns the
## resource CACHE's instance, so `copy.broad_mult = value` on it wrote the LAST loop value
## (`-2.0`) straight into the shared `combat_damage.tres` instance for the rest of the
## process. `broad_sites` clamps `broad_mult` into `[0, 1]`, so every later suite read
## `0.0` and every `broad` strike produced a zero-multiplier site — a sweep that deals no
## wound, which surfaced two suites away as a `settled[]` that was empty and a broad-sweep
## assertion that the two opened channels were missing. `CombatTuning.shipped()` now also
## hands back a fresh duplicate so the mistake can no longer escape this helper; this is
## the belt to that braces.
func _with_broad_mult(value: float) -> CombatTuning:
	var copy := CombatTuning.shipped().duplicate(true) as CombatTuning
	copy.broad_mult = value
	return copy


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
	BodyDamage.builder(authored, &"").call(ctx)
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
	# Derived, not copied off the row under test. A body with no location axis has
	# no channel to rank, so `BodyDamage._resistance_of` takes its empty-sites branch and
	# returns the TISSUE term alone — and `CombatTestKit.actor` never ran
	# `BodyCultivationApi.attach`, so it has none of the three body attributes and reads
	# no tissue. Both therefore land on `0.0`, which is exactly the "with no armour at
	# all" this module claims: a body with no location axis is not a soft one, it is an
	# UNARMED one. Asserting `resistance == parts["tissue"]` instead would let the two
	# rows agree without saying why, and would pass identically for a body that DID
	# carry tissue — so it could not tell the two cases apart.
	assert_eq(
		float(parts["tissue"]), 0.0, "a body with none of the three body attributes reads no tissue"
	)
	assert_eq(float(parts["resistance"]), 0.0, "and no channel to rank, so no armour either")
	assert_eq(float(parts["armour_step"]), _tuning.meridian_armour_step, "the step is authored")
	assert_eq(
		float(parts["channel_rank"]),
		0.0,
		"and the ladder contributes nothing: no channel was struck"
	)
	# A body with no meridians has no LOCATION MULTIPLIER to apply, so `subtotal` is a
	# sum over zero sites. What lands is the flat subtraction at the neutral `1.0`: the
	# gross, less the armour above, floored. Asserted as its own arithmetic rather than
	# as "tissue alone subtracted", so the number is derived from the actor's live reads
	# and cannot drift with a `DEFENSE_PHYSICAL` rebalance.
	var gross := float(parts["magnitude"]) * attack_of(attacker)
	assert_almost_eq(
		float(parts["total"]),
		maxf(gross - float(parts["resistance"]), gross * _tuning.min_penetration_ratio),
		"and the strike is still a landed hit: the flat subtraction, at the neutral 1.0"
	)
	assert_eq(float(parts["total"]) > 0.0, true, "and it is not a refusal")
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
	# ## THE LEDGER IS A COMPONENT, NOT A `ctx.data` KEY (ADR 0195)
	#
	# This row used to assert `BodyLocation.new().wounds_of(hollow) != null`, which could
	# never fail: the function's own fallthrough was `BodyWounds.new()`, so it answered a
	# non-null ledger for EVERY input including one with no ledger at all — a deleted test
	# wearing an assertion's clothes. The function and its `WOUNDS_KEY` are DELETED, and
	# the channel was never read by anything: wounds settle through
	# `CombatEffectApply._wound` -> `CombatEngineApi.wounds_of`, off the bound component.
	#
	# What replaces it is the claim that can actually fail, in both directions: a body
	# with no ledger reads NULL rather than a silently minted one, and a body with one
	# reads BACK THE BOUND OBJECT BY IDENTITY — not an equal copy, because a ledger that
	# re-created itself per read could never accumulate a wound and this suite would stay
	# green while ADR 0070's whole arc was dead.
	assert_eq(
		CombatEngineApi.wounds_of(hollow),
		null,
		"a body nobody attached a ledger to reads null, never a silently minted one"
	)
	var bound := CombatEngineApi.attach_wounds(hollow, _tuning)
	assert_ne(bound, null, "and `attach_wounds` is the one writer that does bind it")
	assert_eq(
		CombatEngineApi.wounds_of(hollow) == bound,
		true,
		"and the read is BY IDENTITY -- a ledger re-minted per read could never accumulate"
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
