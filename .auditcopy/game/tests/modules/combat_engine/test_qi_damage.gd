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
##
## The matchup column is the SHIPPED wuxing-克 cycle, and reading it correctly is what this
## table exists to catch: fire > metal, metal > wood, wood > earth, earth > water,
## water > fire. So `fire > metal` is the STRONG pair and `fire > wood` is NEUTRAL. This
## file used to assert `fire > wood == 1.5` and carried an `expected_totals` array derived
## from it; that is the bulk of what a status-program audit counted as "31 test_qi_damage
## failures" (DEF-0140, whose resolution is that the shipped table was right and this test
## was the defect).
func test_the_worked_numeric_table() -> void:
	var rows := [
		_row(ElementStats.FIRE, ElementStats.WOOD, 0.8),
		_row(ElementStats.FIRE, ElementStats.METAL, 0.8),
		_row(ElementStats.FIRE, ElementStats.EARTH, 0.0),
		_row(ElementStats.FIRE, ElementStats.WATER, 1.0),
		_row(ElementStats.FIRE, ElementStats.FIRE, 1.0),
		_row(ElementStats.WATER, ElementStats.METAL, 0.0),
		_row(ElementStats.FIRE, ElementStats.WATER, 0.75),
		_row(&"void", ElementStats.FIRE, 0.8),
	]
	# Every row: magnitude 100.0, elemental power 10.0, raw attack 25.0, resistance 50
	# points in the ATTACKER's element (so `mit == 0.5`), and a 0.5 flat reduction.
	# So `t_e = 500 * share * matchup`, `t_0 = 2500 * (1 - share)`, `total = sum * 0.5`.
	# Row 2's authored share is 0.0, which means "use the tuning default" (0.8), and row 7's
	# element is unknown to the rules, so it degrades to the raw-only hit.
	var expected_totals := [450.0, 550.0, 400.0, 125.0, 250.0, 450.0, 406.25, 1250.0]
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
## `QiDamage.builder` is PASSED to the spine. Without it the spine's own context carries no
## `element` and no `element_share` at all — `CombatSpine._context` writes only the four
## shared fields and knows nothing about qi — so the spine produced the raw-only 2500.0
## while the reference `breakdown` read 1300.0 from a context that HAD been given them. The
## two numbers were never comparable, and the pair of assertions could only ever have passed
## on a spine that guessed the element out of the technique.
func test_the_spine_carries_the_two_stage_proposal() -> void:
	var attacker := _attacker()
	var target := _defender(ElementStats.FIRE, 0.0)
	var mech := QiDamage.new()
	mech.rules = _rules
	mech.tuning = _tuning
	MechanismSlot.bind(attacker, mech)
	var technique := _technique(ElementStats.FIRE, 0.8)
	var outcome := CombatSpine.resolve_hit(
		attacker,
		target,
		technique,
		_tuning,
		null,
		QiDamage.builder(_rules, technique, ElementStats.WOOD)
	)
	var parts := mech.breakdown(
		_context(attacker, target, ElementStats.FIRE, 0.8, 100.0, ElementStats.WOOD)
	)
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

	# fire > metal is the STRONG pair in the shipped cycle
	var strong_vs_capped := _parts(ElementStats.FIRE, ElementStats.METAL, share, resistance_points)
	var neutral_vs_open := _parts(ElementStats.WATER, ElementStats.METAL, share, 0.0)
	# water > metal is NEUTRAL — water overcomes FIRE, not metal — so matchup 1.0 with no
	# resistance at all.

	assert_almost_eq(float(strong_vs_capped["matchup"]), 1.5, "fire > metal is STRONG")
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
	assert_almost_eq(magnitude, 100.0, "the magnitude both rows share")


## Property 1's other half: `match` multiplies `t_e` and NOTHING else. The raw term is
## byte-identical across two attacker elements with different matchups, which is what
## "resistance and matchup touch the elemental term alone" means.
##
## The pairs are read off the shipped cycle, not asserted into it: `fire > metal` is
## STRONG and `metal > wood` is the WEAK that answers it, so wood-as-attacker against a
## metal defender is the mirror image.
func test_the_matchup_multiplies_the_elemental_term_and_nothing_else() -> void:
	var strong := _parts(ElementStats.FIRE, ElementStats.METAL, 0.8, 0.0)
	var weak := _parts(ElementStats.WOOD, ElementStats.METAL, 0.8, 0.0)
	var neutral := _parts(ElementStats.METAL, ElementStats.EARTH, 0.8, 0.0)
	assert_almost_eq(float(strong["matchup"]), 1.5, "fire > metal")
	assert_almost_eq(float(weak["matchup"]), 0.5, "wood < metal")
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


## ADR 0069: "a wrong element is a WEAKER hit, never a null one". A defender whose
## resistance is AT THE CAP takes the smallest elemental term the formula allows, and
## still takes the whole raw share.
##
## The cap is `resist_cap = 0.75`, so `mitigation` at the cap is `0.25` and NOT `0.0`.
## This used to ask for `mitigation == 0.0` and `resistance == 1.0`, which no `resist_cap`
## below 1.0 can produce — and `QiDamage` clamps `resist_cap` into `[0, 1]` on read, so a
## literal `1.0` resistance is unreachable by construction.
func test_a_perfectly_resisted_element_still_deals_the_raw_share() -> void:
	var parts := _parts(
		ElementStats.FIRE, ElementStats.WOOD, 0.8, _tuning.resist_divisor * _tuning.resist_cap
	)
	assert_almost_eq(float(parts["mitigation"]), 1.0 - _tuning.resist_cap, "resistance at the cap")
	assert_eq(float(parts["resistance"]), _tuning.resist_cap, "resistance reached its cap")
	assert_almost_eq(
		float(parts["elemental_term"]),
		(
			float(parts["magnitude"])
			* 0.8
			* float(parts["elemental_power"])
			* 1.0
			* (1.0 - _tuning.resist_cap)
		),
		"and the elemental term is scaled by exactly the cap"
	)
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
		_attacker(), _defender(ElementStats.FIRE, 0.0), [ElementStats.FIRE, ElementStats.WATER], 0.8
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
		_context(untrained, _defender(ElementStats.FIRE, 50.0), ElementStats.FIRE, 0.8)
	)
	var after := QiDamage.new().breakdown(
		_context(trained, _defender(ElementStats.FIRE, 50.0), ElementStats.FIRE, 0.8)
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


## Subtracted BEFORE the clamp, so penetration can never amplify past `RESIST_CAP`, and so
## it can never invert the sign.
##
## The two halves are stated separately because they are different claims. Against a
## defender whose pre-clamp rate is ENORMOUS the cap binds and penetration cannot move the
## resistance at all — which is the property, and the old single loop asserted the opposite
## (that any penetration at all floors such a resistance), so it measured the clamp and not
## the subtraction.
func test_penetration_cannot_amplify() -> void:
	# (a) Against a defender far past the cap, penetration can only move the resistance
	# DOWN and never above `RESIST_CAP` -- which is the whole claim. The old single loop
	# asserted `resistance == 0.0` for every value, which is only true for penetrations
	# larger than the defender's pre-clamp rate, so it measured the subtraction rather than
	# the bound.
	var last := INF
	for value in [0.0, 0.6, 1.0, 10.0, 1000.0, 1.0e9]:
		var attacker := _attacker()
		attacker.stats.add_modifier(
			StatModifier.new(CombatStats.PENETRATION, Stat.Op.FLAT, value, &"test_mastery")
		)
		var parts := QiDamage.new().breakdown(
			_context(attacker, _defender(ElementStats.FIRE, 10000.0), ElementStats.FIRE, 0.8)
		)
		var resistance := float(parts["resistance"])
		assert_eq(resistance <= _tuning.resist_cap, true, "%s never exceeds the cap" % str(value))
		assert_eq(resistance >= 0.0, true, "%s never goes negative" % str(value))
		assert_eq(resistance <= last, true, "%s is non-increasing in penetration" % str(value))
		assert_eq(float(parts["mitigation"]) <= 1.0, true, "and mitigation never exceeds 1.0")
		last = resistance
	# (b) A defender whose resistance sits exactly AT the cap: a penetration at or past the
	# cap floors it to 0.0 and the mitigation is exactly 1.0 -- never above, and never a
	# negative resistance that would turn `mitigation` into an amplifier.
	for value in [_tuning.resist_cap, 1.0, 10.0, 1000.0, 1.0e9]:
		var attacker := _attacker()
		attacker.stats.add_modifier(
			StatModifier.new(CombatStats.PENETRATION, Stat.Op.FLAT, value, &"test_mastery")
		)
		var parts := QiDamage.new().breakdown(
			_context(
				attacker,
				_defender(ElementStats.FIRE, _tuning.resist_divisor * _tuning.resist_cap),
				ElementStats.FIRE,
				0.8
			)
		)
		assert_eq(float(parts["resistance"]), 0.0, "resistance floors at 0.0")
		assert_almost_eq(float(parts["mitigation"]), 1.0, "mitigation is exactly 1.0, never above")
	# The clamp also holds when the resistance itself is below the cap: the penetration
	# cannot push it negative, because `clampf` runs AFTER the subtraction.
	var modest := _attacker()
	modest.stats.add_modifier(
		StatModifier.new(CombatStats.PENETRATION, Stat.Op.FLAT, 5.0, &"test_mastery")
	)
	var parts := QiDamage.new().breakdown(
		_context(modest, _defender(ElementStats.FIRE, 20.0), ElementStats.FIRE, 0.8)
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
		_context(
			affinityless,
			_defender(ElementStats.FIRE, 0.0),
			ElementStats.FIRE,
			0.8,
			100.0,
			ElementStats.METAL
		)
	)
	assert_almost_eq(float(parts["matchup"]), 1.5, "fire > metal is STRONG")
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
	var target := _defender(ElementStats.FIRE, 50.0)

	# (a) no rules injected anywhere. `with_rules = false` is load-bearing: the fixture's
	# `_context` injects them unconditionally, so this case used to build a context that
	# HAD them and then assert `rules_bound == false`.
	var no_rules := _context(attacker, target, ElementStats.FIRE, 0.8, 100.0, &"", false)
	var a := QiDamage.new().breakdown(no_rules)
	assert_eq(a["rules_bound"], false, "nothing injected")
	assert_almost_eq(float(a["matchup"]), 1.0, "an unreadable matchup is NEUTRAL")
	# The resist contest SURVIVES the missing rules, because it never consulted them: it
	# reads a stat id and a divisor. What "nothing injected" costs is the matchup only —
	# `_element_of` trusts an authored element as-is when there is no table to validate it
	# against. This used to assert the resistance read 0.0, which was never true and would
	# have been a claim that a `[0,1]`-scaled stat id needs a rule table to be readable.
	assert_almost_eq(
		float(a["resistance"]), 50.0 / _tuning.resist_divisor, "the stat channel still answers"
	)
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

	var nan_ctx := _context(_attacker(), _defender(ElementStats.FIRE, 0.0), ElementStats.FIRE, 0.8)
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
		_context(_attacker(), _defender(ElementStats.FIRE, 50.0), ElementStats.FIRE, 0.0)
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
	# The stat-id PREFIXES too. A bare `CombatTuning.new()` ships them empty, so
	# `_suffixed("", "fire")` names the stat `&"fire"`, which nothing derives — the cap
	# assertions below were reading a resistance of 0.0 and passing for the wrong reason.
	greedy.element_power_prefix = "element_power_"
	greedy.resist_resistance_prefix = "element_defense_"
	var mech := QiDamage.new()
	mech.rules = _rules
	mech.tuning = greedy
	# Resistance points at four times the divisor, so the pre-clamp rate is 4.0 and the
	# CLAMPED cap of 1.0 is what binds: mitigation is exactly 0.0.
	var defender := _defender(ElementStats.FIRE, greedy.resist_divisor * 4.0)
	defender.stats.add_modifier(
		StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 1.0, &"test_full_reduction")
	)
	var parts := mech.breakdown(_context(_attacker(), defender, ElementStats.FIRE, 0.8))
	assert_almost_eq(float(parts["mitigation"]), 0.0, "the resistance clamp holds")
	assert_almost_eq(float(parts["mitigated"]), 0.0, "the reduction clamp holds")
	assert_eq(float(parts["damage_reduction"]), 1.0, "reduction is read as 1.0, not 3.0")
	assert_eq(float(parts["total"]) >= 0.0, true, "never negative: no second sign flip")


## Two DIFFERENT out-of-range answers, because `_share_of` treats them differently on
## purpose: a share ABOVE one is clamped to 1.0, and a share at or BELOW zero means "the
## technique authored none" and reads the tuning's `default_element_share`.
##
## This used to loop `[-1.0, 5.0]` over one expectation -- `clamp(value, 0, 1)` for both --
## which contradicts `TechniqueDef.element_share`'s own "`0.0` is the authored default --
## 'use the default', not 'unelemental'" and `QiDamage._share_of`'s documented rule that
## "anything non-positive" falls back. Both behaviours are now asserted separately, and
## both were already the shipped ones.
func test_an_out_of_range_share_is_clamped_or_defaults_and_never_negatives() -> void:
	var greedy := QiDamage.new().breakdown(
		_context(_attacker(), _defender(ElementStats.FIRE, 0.0), ElementStats.FIRE, 5.0)
	)
	assert_almost_eq(float(greedy["share"]), 1.0, "a share above one clamps to 1.0")
	assert_eq(float(greedy["raw_term"]), 0.0, "and leaves no negative raw share")
	assert_eq(float(greedy["total"]) >= 0.0, true, "the hit is still non-negative")
	for value in [-1.0, 0.0, -0.5]:
		var parts := QiDamage.new().breakdown(
			_context(_attacker(), _defender(ElementStats.FIRE, 0.0), ElementStats.FIRE, value)
		)
		assert_almost_eq(
			float(parts["share"]),
			_tuning.default_element_share,
			"share %s is 'authored none' and reads the tuning default" % str(value)
		)
		assert_eq(float(parts["raw_term"]) >= 0.0, true, "and never authors a negative raw share")


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
	assert_eq(_tuning.resist_resistance_prefix, "element_defense_", "and so does the other one")


## The two injection routes agree, and neither is a special case: bound on the mechanism,
## or carried on the context by [method QiDamage.builder].
func test_the_rules_arrive_by_either_injection_route_with_the_same_answer() -> void:
	var attacker := _attacker()
	var target := _defender(ElementStats.FIRE, 50.0)
	var bound := QiDamage.new()
	bound.rules = _rules
	bound.tuning = _tuning
	var via_field := bound.breakdown(
		_context(attacker, target, ElementStats.FIRE, 0.8, 100.0, ElementStats.METAL)
	)

	var via_context := _context(attacker, target, ElementStats.FIRE, 0.8, 100.0, ElementStats.METAL)
	via_context.set_data(QiDamage.ELEMENT_RULES_KEY, _rules)
	var via_data := QiDamage.new().breakdown(via_context)
	assert_eq(
		float(via_field["elemental_term"]) == float(via_data["elemental_term"]),
		true,
		"identical arithmetic"
	)
	# A STRONG pair, so the agreement is not two NEUTRALs coinciding: against METAL the
	# matchup is 1.5 on every route, and the arithmetic below would notice if one of them
	# fell back to the dominance walk and read `&""`.
	assert_almost_eq(float(via_field["matchup"]), 1.5, "fire > metal is STRONG on the field route")
	assert_almost_eq(float(via_data["matchup"]), 1.5, "and on the context route")

	# And through the spine's own `ctx_builder` extension point, which is how a caller
	# who has no business knowing this mechanism's keys still wires it.
	var tech := _technique(ElementStats.FIRE, 0.8)
	var ctx := AttackContext.new(attacker, target, tech, _tuning, 100.0)
	QiDamage.builder(_rules, tech, ElementStats.METAL).call(ctx)
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
	var target := _defender(ElementStats.FIRE, 50.0)
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

# --- internals -------------------------------------------------------------------


## One table row, every primitive the mechanism computed for it.
##
## The attacker is built with its affinity in the row's OWN element and the defender with
## its resistance in that same element, so `elemental_power` and `mitigation` are the same
## on every row and the matchup is the only thing that varies — which is what makes the
## eight totals comparable. `defender_element` is carried on the context explicitly rather
## than left to the dominance walk, so a row whose defender has no affinity in the column
## still reads the column it is about. The first row pins all of that: if `raw_attack`
## moves, or the wrong column is read, the first row fails visibly instead of eight rows
## failing obscurely.
func _row(element: StringName, defender_element: StringName, share: float) -> Dictionary:
	var attacker := _attacker(element)
	var target := _defender(element, 50.0)
	target.stats.add_modifier(
		StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 0.5, &"test_half_reduction")
	)
	var parts := QiDamage.new().breakdown(
		_context(attacker, target, element, share, 100.0, defender_element)
	)
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
		"the carried defender element really is wood"
	)
	# `fire > wood` is NEUTRAL in the shipped cycle: fire overcomes METAL, metal overcomes
	# WOOD, and nothing generates into that pair. DEF-0140 recorded this table as the
	# authority and this assertion as the defect.
	assert_almost_eq(float(parts["matchup"]), 1.0, "fire is NEUTRAL against wood")
	assert_almost_eq(float(first["mitigation"]), 0.5, "50 points over a divisor of 100.0")
	assert_almost_eq(float(parts["damage_reduction"]), 0.5, "the authored flat reduction")
	assert_almost_eq(float(parts["mitigated"]), 0.5, "and so the reduction factor")
	assert_almost_eq(
		float(parts["raw_term"]), float(parts["magnitude"]) * 0.2 * 25.0, "t_0, pinned"
	)
