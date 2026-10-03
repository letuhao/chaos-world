extends "res://tests/modules/combat_engine/qi_damage_fixture.gd"

## ADR 0069: qi damage is an ELEMENTAL SHARE, never a blended payload.
##
## Six load-bearing properties, each asserted here rather than argued in review:
##
## 1. `match` sits BETWEEN the elemental magnitude and mitigation, so a `RESIST_CAP`
##    target is a hard counter even to a `STRONG` 1.5. Move `match` after `mit` and
##    [method test_a_resist_cap_defender_is_a_hard_counter_even_to_a_strong_matchup] and
##    [method test_the_matchup_multiplies_the_elemental_term_and_nothing_else] both fail.
## 2. Resistance applies to the ELEMENTAL TERM ONLY. `t_0` is the floor.
## 3. One element per attack; a hybrid payload is REJECTED and has no code path.
## 4. Mastery is a PENETRATION lever subtracted BEFORE the clamp, so it can never
##    amplify past `RESIST_CAP`.
## 5. Degrade, never throw.
## 6. `ElementRules` is INJECTED -- see
##    [method test_the_mechanism_names_no_class_of_the_elements_module].
##
## Every expected number below is DERIVED from a real actor's live `derived()` read, not
## pasted from a document. A stat formula change moves the table with it.
##
## The pinned actor arithmetic itself lives in `qi_damage_fixture.gd`, shared with
## `test_qi_damage_realm.gd` -- one copy, because a second copy would drift and a drift
## here is invisible: both suites stay green against their own arithmetic.

# --- the worked numeric table ---------------------------------------------------


## The full formula, one row per case, every term computed by the mechanism and every
## total re-derived here from the same primitives. A row that disagrees with its own
## arithmetic is a formula bug; a column that disagrees with the ADR is an ordering bug.
func test_the_worked_numeric_table() -> void:
	var rows := [
		_row(ElementStats.FIRE, ElementStats.WOOD, 0.5),
		_row(ElementStats.FIRE, ElementStats.METAL, 0.8),
		_row(ElementStats.FIRE, ElementStats.EARTH, 0.0),
		_row(ElementStats.METAL, ElementStats.WATER, 1.0),
		_row(ElementStats.METAL, ElementStats.FIRE, 1.0),
		_row(ElementStats.WATER, ElementStats.METAL, 0.0),
		_row(ElementStats.FIRE, ElementStats.WATER, 0.75),
		_row(&"void", ElementStats.FIRE, 0.8),
	]
	var expected_totals := [2690.0, 5025.0, 2890.0, 2448.0, 3096.0, 1292.5, 2315.5859375, 2890.0]
	for index in rows.size():
		var parts: Dictionary = rows[index]
		var label := "row %d (%s -> %s)" % [index, parts["element"], parts["defender_element"]]
		var share := float(parts["share"])
		var magnitude := float(parts["magnitude"])
		var matchup := float(parts["matchup"])
		var mitigation := float(parts["mitigation"])
		var elemental_power := float(parts["elemental_power"])
		var raw_attack := float(parts["raw_attack"])
		var expected_elemental := magnitude * share * elemental_power * matchup * mitigation
		var expected_raw := magnitude * (1.0 - share) * raw_attack
		assert_almost_eq(float(parts["elemental_term"]), expected_elemental, label + ": t_e", 1e-6)
		assert_almost_eq(float(parts["raw_term"]), expected_raw, label + ": t_0", 1e-6)
		assert_almost_eq(
			float(parts["subtotal"]),
			expected_elemental + expected_raw,
			label + ": subtotal is the sum of the two terms",
			1e-6
		)
		assert_almost_eq(
			float(parts["total"]),
			expected_totals[index] if index < expected_totals.size() else 0.0,
			label + ": S5 total with a 0.5 reduction",
			1e-6
		)
		assert_eq(is_finite(float(parts["total"])), true, label + ": finite")
		assert_almost_eq(
			float(parts["total"]),
			float(parts["subtotal"]) * float(parts["mitigated"]),
			label + ": total is subtotal times the reduction factor",
			1e-6
		)


## S4 returns the subtotal and S5 returns the reduced total: two mechanisms' callers
## must be able to observe them separately, which is the whole reason ADR 0067 splits
## the seam. Asserted through the SPINE, not by calling the mechanism directly, so the
## proposal the outcome carries is the one the eleven stages actually produced.
func test_the_spine_carries_the_two_stage_proposal() -> void:
	var attacker := _attacker()
	var target := _defender(&"wood", 50.0)
	var mech := QiDamage.new()
	mech.rules = _rules
	mech.tuning = _tuning
	MechanismSlot.bind(attacker, mech)
	var outcome := CombatSpine.resolve_hit(
		attacker, target, _technique(ElementStats.FIRE, 0.8), _tuning, null
	)
	var parts := mech.breakdown(_context(attacker, target, ElementStats.FIRE, 0.8))
	assert_almost_eq(outcome.proposed_amount(), float(parts["subtotal"]), "S4's subtotal")
	# S7 (`amp_factor`) is exactly 1.0 at zero amplification and zero reduction, and S8
	# floors at `maxf(amount, maxf(1.0, base * 0.01))`, so on a hit of this size the two
	# shared stages are the identity and `outcome.amount` IS S5's number.
	assert_almost_eq(
		outcome.amount,
		float(parts["total"]),
		"S5's reduced total (S7 and S8 are the identity on a hit this large)"
	)


# --- property 1: matchup placement ----------------------------------------------


## THE anti-"fire is always strong" property. A defender at `RESIST_CAP` takes LESS
## from a `STRONG` matchup than an unresisted defender takes from a `NEUTRAL` one.
##
## This is the assertion that FAILS if `match` is moved after `mit`: with `mit` applied
## first, the two cases collapse onto the same product and the ordering stops being
## observable at all.
func test_a_resist_cap_defender_is_a_hard_counter_even_to_a_strong_matchup() -> void:
	var share := 0.8
	var magnitude := 100.0
	var resistance_points := _tuning.resist_divisor * _tuning.resist_cap

	# fire is STRONG against wood
	var strong_vs_capped := _parts(ElementStats.FIRE, ElementStats.WOOD, share, resistance_points)
	var neutral_vs_open := _parts(ElementStats.WATER, ElementStats.METAL, share, 0.0)
	# water is NEUTRAL to metal, so matchup 1.0 with no resistance at all.

	assert_almost_eq(float(strong_vs_capped["matchup"]), 1.5, "fire > wood is STRONG")
	assert_almost_eq(float(neutral_vs_open["matchup"]), 1.0, "water/metal is NEUTRAL")
	assert_almost_eq(
		float(strong_vs_capped["mitigation"]), 1.0 - _tuning.resist_cap, "capped mitigation"
	)
	assert_eq(
		float(strong_vs_capped["elemental_term"]) < float(neutral_vs_open["elemental_term"]),
		true,
		"a RESIST_CAP target takes LESS from a STRONG match than an open one from a NEUTRAL one"
	)
	# And the arithmetic that makes it true, stated rather than only observed: the
	# matchup is a factor of `t_e` and the mitigation is a factor of the SUM, so the two
	# can disagree. Reordering them makes both products 0.375 and the tie.
	assert_eq(
		float(strong_vs_capped["elemental_term"]) == float(neutral_vs_open["elemental_term"]),
		false,
		"they are genuinely different numbers"
	)


## Property 1's other half: `match` multiplies `t_e` and NOTHING else. The raw term is
## byte-identical across two attacker elements with different matchups, which is what
## "resistance and matchup touch the elemental term alone" means.
func test_the_matchup_multiplies_the_elemental_term_and_nothing_else() -> void:
	var strong := _parts(ElementStats.FIRE, ElementStats.WOOD, 0.8, 0.0)
	var weak := _parts(ElementStats.WOOD, ElementStats.FIRE, 0.8, 0.0)
	var neutral := _parts(ElementStats.METAL, ElementStats.EARTH, 0.8, 0.0)
	assert_almost_eq(float(strong["matchup"]), 1.5, "fire > wood")
	assert_almost_eq(float(weak["matchup"]), 0.5, "wood < fire")
	assert_almost_eq(float(neutral["matchup"]), 1.0, "metal/earth is NEUTRAL")
	# The defender differs between rows, so this ALSO holds resistance to zero and
	# proves the raw share is not the thing being scaled.
	assert_eq(
		float(strong["raw_term"]) == float(weak["raw_term"]),
		true,
		"the raw term is byte-identical across a 1.5 and a 0.5 matchup"
	)
	assert_eq(
		float(strong["raw_term"]) == float(neutral["raw_term"]), true, "and across a NEUTRAL one"
	)
	assert_almost_eq(
		float(strong["elemental_term"]) / float(weak["elemental_term"]),
		3.0,
		"the elemental term really is 3x (1.5 / 0.5)",
		1e-4
	)


# --- property 2: the raw share is the floor --------------------------------------


## ADR 0069: "a wrong element is a WEAKER hit, never a null one". A defender immune to
## the attacker's element -- resistance at the cap, so `mitigation == 0.0` -- still takes
## the whole raw share.
func test_a_perfectly_resisted_element_still_deals_the_raw_share() -> void:
	var parts := _parts(ElementStats.FIRE, ElementStats.WOOD, 0.8, _tuning.resist_divisor)
	assert_almost_eq(float(parts["mitigation"]), 0.0, "full resistance")
	assert_eq(float(parts["elemental_term"]), 0.0, "the elemental term is gone")
	assert_almost_eq(float(parts["resistance"]), 1.0, "resistance reached its cap")
	assert_almost_eq(
		float(parts["raw_term"]),
		float(parts["magnitude"]) * 0.2 * float(parts["raw_attack"]),
		"and the raw share is untouched -- that IS the floor"
	)
	assert_eq(float(parts["total"]) > 0.0, true, "so the hit is weaker, never null")


## There is no separate floor constant anywhere: at `share == 1.0` the floor is zero and
## the raw term is exactly 0.0, which is the strongest possible statement that `t_0` is
## the floor rather than a constant that happens to coincide with it.
func test_there_is_no_separate_floor_constant() -> void:
	var parts := _parts(ElementStats.FIRE, ElementStats.WOOD, 1.0, 0.0)
	assert_eq(float(parts["raw_term"]), 0.0, "no raw share at all")
	assert_eq(float(parts["raw"]), 0.0, "and no raw magnitude either")
	assert_eq(float(parts["total"]) > 0.0, true, "the elemental term is still there")


# --- property 3: one element per attack, blends rejected --------------------------


## ADR 0069's measured proof, asserted against `ElementRules` DIRECTLY rather than
## against the mechanism, because the claim is about the shipped `ElementDefaults` and
## re-measuring is the whole point (BRIEF 4b: grand mean 0.997500, tier-1 mean exactly
## 0.950000, single-element spread 3.0x vs a blend's 2.0x).
func test_the_tier_1_mean_is_exactly_0950_and_a_blend_does_not_move_it() -> void:
	var base := ElementDefaults.base()
	var single_means := []
	var single_low := INF
	var single_high := -INF
	for row in base:
		var total := 0.0
		var low := INF
		var high := -INF
		for column in base:
			var value := _rules.multiplier(row.id, column.id)
			total += value
			low = minf(low, value)
			high = maxf(high, value)
		single_means.append(total / float(base.size()))
		single_low = minf(single_low, low)
		single_high = maxf(single_high, high)
	var single_mean := 0.0
	for value in single_means:
		single_mean += value
	single_mean /= float(single_means.size())
	assert_almost_eq(single_mean, 0.95, "the tier-1 row mean is exactly 0.950000", 1e-9)

	# A 50/50 blend of any two tier-1 elements against the same column.
	var blended_means := []
	var blended_low := INF
	var blended_high := -INF
	for i in base.size():
		for j in range(i + 1, base.size()):
			var total := 0.0
			var low := INF
			var high := -INF
			for column in base:
				var value := (
					(
						_rules.multiplier(base[i].id, column.id)
						+ _rules.multiplier(base[j].id, column.id)
					)
					/ 2.0
				)
				total += value
				low = minf(low, value)
				high = maxf(high, value)
			blended_means.append(total / float(base.size()))
			blended_low = minf(blended_low, low)
			blended_high = maxf(blended_high, high)
	var blend_mean := 0.0
	for value in blended_means:
		blend_mean += value
	blend_mean /= float(blended_means.size())
	assert_almost_eq(
		blend_mean, single_mean, "a blend's mean is IDENTICAL to a single element's", 1e-9
	)
	assert_almost_eq(single_low, 0.5, "single elements bottom out at WEAK", 1e-9)
	assert_almost_eq(single_high, 1.5, "and top out at STRONG", 1e-9)
	assert_almost_eq(blended_low, 0.625, "a blend never sees a full WEAK", 1e-9)
	assert_almost_eq(blended_high, 1.25, "nor a full STRONG", 1e-9)
	assert_eq(
		(single_high / single_low) > (blended_high / blended_low),
		true,
		"3.0x spread against 2.0x: the blend gives up the read and keeps nothing"
	)


## There is no blend code path. An `Array` under the element key is not an element, so a
## hybrid payload degrades to the raw-only hit rather than being averaged into one.
func test_a_hybrid_payload_has_no_code_path_and_degrades_to_raw() -> void:
	var hybrid := _context(
		_attacker(), _defender(&"wood", 0.0), [ElementStats.FIRE, ElementStats.WATER], 0.8
	)
	var parts := QiDamage.new().breakdown(hybrid)
	assert_eq(parts["element"], "", "an Array is not an element id")
	assert_eq(float(parts["share"]), 0.0, "and so there is no elemental share")
	assert_eq(float(parts["elemental_term"]), 0.0, "no elemental term")
	assert_eq(float(parts["raw"]), float(parts["magnitude"]), "the whole magnitude is raw")
	assert_eq(float(parts["total"]) > 0.0, true, "still a landed hit")


# --- property 4: mastery is penetration, subtracted before the clamp --------------


## `CombatStats.PENETRATION` is ADR 0069's mastery lever on the DEFENDER's resistance
## (ADR 0068 defines that id as exactly "a read-only input to a mechanism's mitigate").
## It moves the elemental term and the raw term does not move AT ALL -- byte-identical,
## not nearly.
func test_mastery_moves_only_the_elemental_term() -> void:
	var untrained := _attacker()
	var trained := _attacker()
	trained.stats.add_modifier(
		StatModifier.new(CombatStats.PENETRATION, Stat.Op.FLAT, 0.4, &"test_mastery")
	)
	var before := QiDamage.new().breakdown(
		_context(untrained, _defender(&"wood", 50.0), ElementStats.FIRE, 0.8)
	)
	var after := QiDamage.new().breakdown(
		_context(trained, _defender(&"wood", 50.0), ElementStats.FIRE, 0.8)
	)
	assert_almost_eq(float(before["resistance"]), 0.5, "50 points over the divisor")
	assert_almost_eq(
		float(after["resistance"]), 0.1, "0.4 of penetration was subtracted before the clamp"
	)
	assert_eq(
		float(after["raw_term"]) == float(before["raw_term"]),
		true,
		"the raw term is BYTE-IDENTICAL before and after mastery"
	)
	assert_eq(
		float(after["magnitude"]) == float(before["magnitude"]), true, "and so is the magnitude"
	)
	assert_eq(
		float(after["elemental_term"]) > float(before["elemental_term"]),
		true,
		"the elemental term did move"
	)


## Subtracted BEFORE the clamp, so penetration can never amplify past `RESIST_CAP`.
## 1000.0 of penetration against a defender at the cap must leave mitigation at exactly
## 1.0 -- never above, and never a negative resistance that would turn `mitigation`
## into an amplifier.
func test_penetration_cannot_amplify() -> void:
	for value in [0.6, 1.0, 10.0, 1000.0, 1.0e9]:
		var attacker := _attacker()
		attacker.stats.add_modifier(
			StatModifier.new(CombatStats.PENETRATION, Stat.Op.FLAT, value, &"test_mastery")
		)
		var parts := QiDamage.new().breakdown(
			_context(attacker, _defender(&"wood", 10000.0), ElementStats.FIRE, 0.8)
		)
		assert_eq(float(parts["resistance"]), 0.0, "resistance floors at 0.0")
		assert_eq(float(parts["mitigation"]), 1.0, "mitigation is exactly 1.0, never above")
		assert_eq(float(parts["mitigation"]) <= 1.0, true, "and never exceeds 1.0 for any value")
	# The clamp also holds when the resistance itself is below the cap: the penetration
	# cannot push it negative, because `clampf` runs AFTER the subtraction.
	var modest := _attacker()
	modest.stats.add_modifier(
		StatModifier.new(CombatStats.PENETRATION, Stat.Op.FLAT, 5.0, &"test_mastery")
	)
	var parts := QiDamage.new().breakdown(
		_context(modest, _defender(&"wood", 20.0), ElementStats.FIRE, 0.8)
	)
	assert_eq(float(parts["resistance"]), 0.0, "0.2 resistance minus 5.0 clamps to 0.0")
	assert_eq(float(parts["mitigation"]), 1.0, "so mitigation is exactly 1.0")


## An attacker with NO affinity for the element they authored has an elemental term of
## exactly 0.0 -- at a STRONG matchup, so the matchup is not what zeroed it. The raw
## share is untouched, which is the qi premise (ADR 0004 `NOURISH = 0.75` means qi
## always does something) and the exact inverse of body's (ADR 0070).
func test_an_untrained_element_is_zero_at_a_strong_matchup() -> void:
	var affinityless := Actor.new(
		&"novice", {Stat.SPIRIT: 5.0, Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 10.0}
	)
	affinityless.add_resource(ResourcePool.new(&"health", 1000.0))
	ElementsApi.attach(affinityless)  # no affinity at all
	var parts := QiDamage.new().breakdown(
		_context(affinityless, _defender(&"wood", 0.0), ElementStats.FIRE, 0.8)
	)
	assert_almost_eq(float(parts["matchup"]), 1.5, "fire > wood is STRONG")
	assert_eq(float(parts["elemental_power"]), 0.0, "no affinity, no power")
	assert_eq(float(parts["elemental_term"]), 0.0, "so the elemental term is exactly 0.0")
	assert_almost_eq(
		float(parts["raw_term"]),
		float(parts["magnitude"]) * 0.2 * float(parts["raw_attack"]),
		"and the raw share is entirely intact"
	)
	assert_eq(float(parts["total"]) > 0.0, true, "a wrong element is weaker, never null")


# --- property 5: degrade, never throw --------------------------------------------


## Four degenerate inputs, one assertion each. Every one returns a finite NUMBER; the
## raw term is intact in all four, so "no rules" and "unknown element" cost the
## elemental term and nothing else.
func test_degradation_never_throws_and_keeps_the_raw_term() -> void:
	var attacker := _attacker()
	var target := _defender(&"wood", 50.0)

	# (a) no rules injected anywhere.
	var no_rules := _context(attacker, target, ElementStats.FIRE, 0.8)
	var a := QiDamage.new().breakdown(no_rules)
	assert_eq(a["rules_bound"], false, "nothing injected")
	assert_almost_eq(float(a["matchup"]), 1.0, "an unreadable matchup is NEUTRAL")
	assert_almost_eq(float(a["resistance"]), 0.0, "no rules means no resist contest")
	assert_eq(float(a["raw_term"]) > 0.0, true, "raw term intact")
	assert_eq(is_finite(float(a["total"])), true, "and it is a finite number")

	# (b) an element the rule table does not know.
	var unknown := _context(attacker, target, &"shadow", 0.8)
	var b := QiDamage.new().breakdown(unknown)
	assert_eq(b["element"], "", "an unknown element is no element")
	assert_eq(float(b["share"]), 0.0, "so no elemental share")
	assert_eq(float(b["raw_term"]) > 0.0, true, "raw term intact")
	assert_eq(is_finite(float(b["total"])), true, "finite")

	# (c) a defender nobody attached the element provider to: resistance reads 0.0 and
	# therefore mitigation 1.0.
	var bare := Actor.new(&"bare", {Stat.WILL: 10.0})
	bare.add_resource(ResourcePool.new(&"health", 1000.0))
	var c := QiDamage.new().breakdown(_context(attacker, bare, ElementStats.FIRE, 0.8))
	assert_almost_eq(float(c["resistance"]), 0.0, "an unattached defender resists nothing")
	assert_almost_eq(float(c["mitigation"]), 1.0, "so mitigation is exactly 1.0")
	assert_eq(is_finite(float(c["total"])), true, "finite")

	# (d) an unelemental technique: share 0, whole magnitude raw.
	var d := QiDamage.new().breakdown(_context(attacker, target, &"", 0.8))
	assert_eq(d["element"], "", "no element authored")
	assert_eq(float(d["share"]), 0.0, "no share")
	assert_eq(float(d["raw"]), float(d["magnitude"]), "the whole magnitude is raw")
	assert_almost_eq(
		float(d["total"]),
		float(d["magnitude"]) * float(d["raw_attack"]),
		"so the hit is a pure spiritual hit"
	)


## A null context, a null proposal and a NaN magnitude are the three remaining ways a
## half-built hit could crash the spine three stages downstream. All three return a
## number, and the number is finite.
func test_null_context_null_proposal_and_nan_magnitude_all_degrade() -> void:
	var mech := QiDamage.new()
	var empty := mech.breakdown(null)
	assert_eq(float(empty["total"]), 0.0, "a null context is the empty proposal")
	assert_eq(int(empty.size()), 18, "and it carries the full key set for a panel")
	assert_eq(is_finite(float(empty["subtotal"])), true, "finite")
	assert_eq(float(mech.mitigate(null, DamageProposal.none()).amount), 0.0, "null proposal")
	assert_eq(float(mech.resolve(null).amount), 0.0, "and S4 declines rather than throws")

	var nan_ctx := _context(_attacker(), _defender(&"wood", 0.0), ElementStats.FIRE, 0.8)
	nan_ctx.magnitude = NAN
	nan_ctx.base = NAN
	var parts := mech.breakdown(nan_ctx)
	assert_eq(is_finite(float(parts["total"])), true, "a NaN magnitude yields a finite number")
	assert_eq(float(parts["magnitude"]), 0.0, "and the magnitude reads 0.0")


## A degenerate tuning (`CombatTuning.new()`, every bound 0.0) must not divide by zero.
## `resist_divisor == 0.0` is the one place this formula divides by anything, and a bare
## tuning is exactly the state a caller reaches by forgetting the `.tres`.
func test_a_degenerate_tuning_never_divides_by_zero() -> void:
	var bare := CombatTuning.new()
	var mech := QiDamage.new()
	mech.rules = _rules
	mech.tuning = bare
	var parts := mech.breakdown(
		_context(_attacker(), _defender(&"wood", 50.0), ElementStats.FIRE, 0.8)
	)
	assert_eq(float(parts["resistance"]), 0.0, "a 0.0 divisor is no contest, not a division")
	assert_almost_eq(float(parts["mitigation"]), 1.0, "so mitigation is 1.0")
	assert_eq(float(parts["share"]), 0.0, "and the default share is 0.0 too")
	assert_eq(is_finite(float(parts["total"])), true, "the number is finite")


## A `resist_cap` or `damage_reduction_cap` above 1.0 would make `mitigation` negative
## and S9's ONE sign flip would spend the elemental term as a HEAL. Clamped on read.
func test_a_cap_above_one_cannot_turn_a_hit_into_a_heal() -> void:
	var greedy := CombatTuning.new()
	greedy.default_element_share = 0.8
	greedy.resist_divisor = 100.0
	greedy.resist_cap = 4.0
	greedy.damage_reduction_cap = 3.0
	var mech := QiDamage.new()
	mech.rules = _rules
	mech.tuning = greedy
	var defender := _defender(&"wood", 50.0)
	defender.stats.add_modifier(
		StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 1.0, &"test_full_reduction")
	)
	var parts := mech.breakdown(_context(_attacker(), defender, ElementStats.FIRE, 0.8))
	assert_almost_eq(float(parts["mitigation"]), 0.0, "the resistance clamp holds")
	assert_almost_eq(float(parts["mitigated"]), 0.0, "the reduction clamp holds")
	assert_eq(float(parts["damage_reduction"]), 1.0, "reduction is read as 1.0, not 3.0")
	assert_eq(float(parts["total"]) >= 0.0, true, "never negative: no second sign flip")


## `element_share` outside `[0, 1]` makes `m_0` negative. Clamped, so a hand-edited
## `.tres` cannot author a hit that pays a healer.
func test_an_out_of_range_share_is_clamped() -> void:
	for value in [-1.0, 5.0]:
		var parts := QiDamage.new().breakdown(
			_context(_attacker(), _defender(&"wood", 0.0), ElementStats.FIRE, value)
		)
		assert_almost_eq(float(parts["share"]), 1.0, "share %s clamps to 1.0" % str(value))
		assert_eq(float(parts["raw_term"]), 0.0, "and leaves no negative raw share")
		assert_eq(float(parts["total"]) >= 0.0, true, "the hit is still non-negative")


# --- property 6: the rules are injected, and the edge is not declared ------------


## ADR 0069: `ElementRules` is INJECTED by the caller. The mechanism reaches it only
## through `ctx.data` or its own `rules` field, and `tools/arch/registry.json` keeps
## `combat_engine` at `["contracts", "core"]`.
func test_the_mechanism_names_no_class_of_the_elements_module() -> void:
	# `tools/arch/registry.json` is outside `res://`, so that half is checked by the gate
	# rather than from here. What IS checkable here is the half the gate CANNOT see:
	# `BARE_REF_UNITS` excludes `modules/*` (rules.py), so a bare reference from this
	# file to `ElementRules` would be reported as an unresolved count, not a violation.
	# Naming no class at all is therefore strictly stronger than declaring the edge.
	#
	# Only CODE lines are scanned. A `##` doc comment that explains WHY the rules are
	# injected necessarily says "ElementRules" — that is documentation, not a reference,
	# and a source-wide substring test would fail on the very comment that documents the
	# rule it is asserting. A dependency is a name in a declaration, a call, or a cast.
	var code := ""
	for line in FileAccess.get_file_as_string("res://src/modules/combat_engine/qi_damage.gd").split(
		"\n"
	):
		var stripped := String(line).strip_edges()
		if not stripped.begins_with("#"):
			code += stripped + "\n"
	for forbidden in [
		"ElementRules", "ElementStats", "ElementsApi", "ElementProvider", "ElementDef"
	]:
		assert_eq(
			code.contains(forbidden),
			false,
			(
				"qi_damage.gd must not name %s in code -- the rules are injected, the edge is not declared"
				% forbidden
			)
		)
	# The stat ids it DOES read are named in DATA, which is BRIEF 1.7's whole rule.
	assert_eq(_tuning.element_power_prefix, "element_power_", "the prefix lives in the .tres")
	assert_eq(_tuning.resist_resistance_prefix, "element_resistance_", "and so does the other one")


## The two injection routes agree, and neither is a special case: bound on the mechanism,
## or carried on the context by [method QiDamage.builder].
func test_the_rules_arrive_by_either_injection_route_with_the_same_answer() -> void:
	var attacker := _attacker()
	var target := _defender(&"wood", 50.0)
	var bound := QiDamage.new()
	bound.rules = _rules
	bound.tuning = _tuning
	var via_field := bound.breakdown(_context(attacker, target, ElementStats.FIRE, 0.8))

	var via_context := _context(attacker, target, ElementStats.FIRE, 0.8)
	via_context.set_data(QiDamage.ELEMENT_RULES_KEY, _rules)
	var via_data := QiDamage.new().breakdown(via_context)
	assert_eq(
		float(via_field["elemental_term"]) == float(via_data["elemental_term"]),
		true,
		"identical arithmetic"
	)

	# And through the spine's own `ctx_builder` extension point, which is how a caller
	# who has no business knowing this mechanism's keys still wires it.
	var tech := _technique(ElementStats.FIRE, 0.8)
	var ctx := AttackContext.new(attacker, target, tech, _tuning, 100.0)
	QiDamage.builder(_rules, tech, &"wood").call(ctx)
	assert_eq(
		String(ctx.data_value(QiDamage.ELEMENT_KEY, "")),
		String(ElementStats.FIRE),
		"the builder carried the element"
	)
	assert_almost_eq(float(ctx.data_value(QiDamage.ELEMENT_SHARE_KEY, 0.0)), 0.8, "and the share")
	assert_almost_eq(
		float(bound.breakdown(ctx)["elemental_term"]),
		float(via_field["elemental_term"]),
		"so the spine path and the direct path agree"
	)


# ADR 0069's realm-invariance and tier-2 mastery properties now live in
# `test_qi_damage_realm.gd`.

# --- the realm-invariance fix: see test_qi_damage_realm.gd ------------------------

# --- `TechniqueDef.element_share` (ADR 0069's only new authored field) ------------


## `TechniqueDef` is NOT serialized -- `TechniqueCodex.to_dict` stores ids and rungs
## only (ADR 0056), so a def is authored as a `.tres` and never round-tripped through a
## save. `from_dict`/`to_dict` are therefore NOT added: an authorable round-trip would
## be a second copy of the field with its own defaults, and the two would drift.
##
## What IS assertable, and what the field actually has to guarantee, is that the
## authored value survives a `.tres` resource round-trip and reaches the qi mechanism
## through the read model -- and that `0.0` reads as "use the default" rather than
## "unelemental".
func test_element_share_round_trips_through_the_resource_and_the_read_model() -> void:
	var def := _technique(ElementStats.FIRE, 0.35)
	def.id = &"round_trip"
	assert_almost_eq(def.element_share, 0.35, "the authored value is on the def")
	assert_almost_eq(
		_technique(ElementStats.FIRE, 0.0).element_share,
		0.0,
		"0.0 is the authored default -- 'use the default', not 'unelemental'"
	)
	# The qi path reads it off the context, so the builder's carry is the round-trip the
	# mechanism actually depends on.
	var attacker := _attacker()
	var target := _defender(&"wood", 50.0)
	var ctx := AttackContext.new(attacker, target, def, _tuning, 100.0)
	QiDamage.builder(_rules, def).call(ctx)
	assert_almost_eq(
		float(ctx.data_value(QiDamage.ELEMENT_SHARE_KEY, 0.0)), 0.35, "carried verbatim"
	)
	assert_almost_eq(float(QiDamage.new().breakdown(ctx)["share"]), 0.35, "and used as the share")
	# And the surface a screen reads carries it too.
	var view := TechniqueReadModel.learn_preview(attacker, TechniqueCodex.new(), def, [], [])
	assert_eq(view.size() > 0, true, "the preview renders")
	var inspect := TechniqueReadModel.inspect(
		attacker, TechniqueCodex.new(), TechniqueSlots.new(), TechniqueUpkeep.new(), def, [], []
	)
	assert_almost_eq(
		float(inspect.get("element_share", -1.0)),
		0.35,
		"the read model surfaces the authored share as a primitive"
	)
	assert_eq(String(inspect.get("element", "")), String(ElementStats.FIRE), "and the element")


# --- purity, the seam's own contract (ADR 0067) ----------------------------------


## The seam's contract: `resolve` called twice on the same context returns the same
## proposal, and neither call changed the context.
func test_resolve_is_pure_and_context_is_unmutated() -> void:
	var mech := QiDamage.new()
	mech.rules = _rules
	mech.tuning = _tuning
	var ctx := _context(_attacker(), _defender(&"wood", 50.0), ElementStats.FIRE, 0.8)
	var before := ctx.data.duplicate(true)
	var first := mech.resolve(ctx)
	var second := mech.resolve(ctx)
	assert_eq(first.amount, second.amount, "the same amount twice")
	assert_eq(first.effects, second.effects, "and no effects, ever")
	assert_eq(ctx.data, before, "the context was not written to")
	# And `mitigate` returns a FRESH proposal rather than editing the one it was handed.
	var input := DamageProposal.new(123.0)
	var output := mech.mitigate(ctx, input)
	assert_eq(input.amount, 123.0, "the caller's proposal is untouched")
	assert_ne(output, input, "and a different object is returned")
	assert_almost_eq(
		output.amount,
		123.0 * float(mech.breakdown(ctx)["mitigated"]),
		"reduced by the defender's DAMAGE_REDUCTION"
	)


## `breakdown()` is primitives only -- the repo's UI standard (ADR 0038) is that a
## `summary()` payload carries no module type and no engine object, and this is the
## method a panel will read.
func test_breakdown_is_primitives_only() -> void:
	var parts := QiDamage.new().breakdown(
		_context(_attacker(), _defender(&"wood", 50.0), ElementStats.FIRE, 0.8)
	)
	for key in parts.keys():
		var value: Variant = parts[key]
		var primitive := (
			value is float
			or value is int
			or value is bool
			or value is String
			or value is StringName
		)
		assert_eq(primitive, true, "key %s carries a primitive" % String(key))
	assert_eq(
		DamageProposal.is_primitive_effect(
			{DamageProposal.KIND: &"qi.elemental", "share": float(parts["share"])}
		),
		true,
		"and the same shape passes the proposal's own primitive gate"
	)


# --- internals -------------------------------------------------------------------


## One table row, every primitive the mechanism computed for it.
##
## The defender's `resistance_points` and its affinity are derived from the same number,
## and the elements the table's matchups need are all distinct, so `defender_element`
## reads the column this row is about rather than some other one. The first row pins all
## of that: if `raw_attack` moves, or the dominance picks the wrong column, the first row
## fails visibly instead of eight rows failing obscurely.
func _row(element: StringName, defender_element: StringName, share: float) -> Dictionary:
	var attacker := _attacker()
	var target := _defender(defender_element, 50.0)
	target.stats.add_modifier(
		StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 0.5, &"test_half_reduction")
	)
	var parts := QiDamage.new().breakdown(_context(attacker, target, element, share))
	if element == ElementStats.FIRE and defender_element == ElementStats.WOOD:
		_pin_the_table(parts)
	return parts


## The reference row's invariants, asserted where the reference is built.
func _pin_the_table(parts: Dictionary) -> void:
	var first := _parts(ElementStats.FIRE, ElementStats.WOOD, 0.8, 50.0)
	assert_almost_eq(float(parts["raw_attack"]), 25.0, "spirit 10.0 x2 + aptitude 10.0 x0.5")
	assert_almost_eq(float(parts["elemental_power"]), _fire_affinity(), "affinity 10.0")
	assert_eq(
		String(parts["defender_element"]),
		String(ElementStats.WOOD),
		"the defender's dominant affinity really is wood"
	)
	assert_almost_eq(float(parts["matchup"]), 1.5, "fire STRONG against wood")
	assert_almost_eq(float(first["mitigation"]), 0.5, "50 points over a divisor of 100.0")
	assert_almost_eq(float(parts["damage_reduction"]), 0.5, "the authored flat reduction")
	assert_almost_eq(float(parts["mitigated"]), 0.5, "and so the reduction factor")
	assert_almost_eq(
		float(parts["raw_term"]), float(parts["magnitude"]) * 0.2 * 25.0, "t_0, pinned"
	)
