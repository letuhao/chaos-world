extends "res://tests/modules/combat_engine/qi_damage_fixture.gd"

## The BOUNDS and DEGRADATION cases for QiDamage: penetration's bounded reciprocal, the
## elementless and untrained channels, the tuning-default refusal, every null / NaN /
## divide-by-zero degradation, a ceiling above one that must not heal, an out-of-range
## share, the structural census that the mechanism names no `elements` class, the two
## injection routes, and the round trip through the resource and the read model.
##
## Split out of `test_qi_damage.gd` when that file passed gdlint's `max-file-lines`
## ceiling. Both suites extend the same fixture, so the hero, the defender, the tuning and
## the rules arrive exactly as they did; `test_qi_damage.gd` keeps the numeric table, the
## spine proposal and the mastery terms.


## The bound ADR 0200's reciprocal buys, which the subtraction never had.
##
## `D_eff = D / (1 + max(0, pen) / pierce_scale)` lies in `(0, 1]`, so penetration can push
## an ENORMOUS defense arbitrarily close to zero and can never drive it NEGATIVE. The old
## `maxf(resistance - pen, 0)` subtracted straight past a defended point into a free one —
## so a defender's armour could be removed outright by a large enough penetration, which is
## a strike with NO penetration limit at all.
##
## Every loop here is a measurement of the ratio's shape, and each half states its own claim
## because they are different claims: non-increasing in penetration (the ordering), and
## strictly positive however deep the defense started (the bound).
##
## ## ADR 0200 + the element-defense ladder: the defense under test was RAISED, and the
## ceiling assertion has to follow the curve rather than assume a distance from it
##
## `10000.0` defense points against a `K = 4.5` left `D_eff >= 0.0918` even at a
## penetration of `1e9`, and `0.095 * 0.0918 / (4.5 + 0.0918) = 0.0019` was comfortably
## below the ceiling. That headroom was an accident of the figure chosen, not a property:
## `mitigation_rate` is a pure ratio of the two terms, so once `D_eff` dominates `K` it
## exceeds `mitigation_ceiling * K/D` for ANY ceiling, and the "strictly below" claim stops
## holding at some defense however small the ceiling is.
##
## Doubling the defense to `20000.0` crosses it: at `pen == 0` the ratio is
## `0.95 * 20000 / (4.5 + 20000) = 0.94979`, which rounds past `0.95` in float64. That is
## not a clamp leaking back in — `_mitigation_of` returns `ceiling * share` with no
## comparison against `ceiling` at all, and the value is provably still `ceiling * share`
## (asserted below against the ratio itself). It is the ceiling being a number no curve
## approaches forever in a finite float.
##
## So the invariant that actually holds, and that replaces the removed comparison, is
## THREE-PARTED and stated in the order the mechanism guarantees it: the rate is exactly
## `ceiling * D_eff / (K + D_eff)` at every penetration; it is strictly inside `(0, 1]`
## whenever `D_eff > 0`, which is what makes the defender non-immune; and it is strictly
## below the ceiling for every defense where `D_eff` is not already dominant over `K` —
## which is asserted against a figure the fixture derives rather than one pasted beside it.
func test_penetration_is_a_bounded_reciprocal_on_the_defense_and_never_goes_negative() -> void:
	# (a) Against a defender far past anything the ladder builds, penetration can only move
	# the effective defense DOWN and never to or below zero -- which is the whole claim.
	# `10000.0` defense points is a figure where `D_eff / K` stays well under one at every
	# penetration in the loop, which is the regime the ceiling comparison below is about.
	var last := INF
	for value in [0.0, 0.6, 1.0, 10.0, 1000.0, 1.0e9]:
		var attacker := _attacker()
		attacker.stats.add_modifier(
			StatModifier.new(CombatStats.PENETRATION, Stat.Op.FLAT, value, &"test_mastery")
		)
		var parts := QiDamage.new().breakdown(
			_context(attacker, _defender(ElementStats.FIRE, 10000.0), ElementStats.FIRE, 0.8)
		)
		var pierced := float(parts["defense_effective"])
		assert_eq(pierced > 0.0, true, "%s never reaches zero defense" % str(value))
		assert_eq(pierced <= float(parts["defense"]), true, "%s never exceeds D" % str(value))
		assert_eq(pierced <= last, true, "%s is non-increasing in penetration" % str(value))
		# The mitigation is an OUTPUT of the ratio, so it is bounded by `[0, 1]` rather
		# than clamped at the ceiling, and the rate is the unbounded-on-`(0, 1]` figure the
		# elemental term is multiplied by. Positivity is the non-immunity guarantee: it
		# holds for every finite `D_eff`, because `D_eff` never reaches zero.
		assert_eq(float(parts["mitigation"]) <= 1.0, true, "and mitigation never exceeds 1.0")
		assert_eq(
			float(parts["mitigation"]) > 0.0,
			true,
			"nor reaches full mitigation at any penetration -- the defender is never immune"
		)
		# And the ceiling comparison, stated where it is a property: `D_eff` still below `K`,
		# so the ratio is not yet dominant and the curve has not arrived. Both sides are
		# read off the row rather than one of them pasted.
		if float(parts["defense_effective"]) < float(parts["divisor_k"]):
			assert_eq(
				float(parts["mitigation_rate"]) < _tuning.mitigation_ceiling,
				true,
				"nor reaches the ceiling while D_eff is below K"
			)
		last = pierced
	# (b) The measured curve, not just its ordering: the reciprocal is exactly
	# `D / (1 + pen/pierce_scale)` at each penetration, which is what distinguishes it from
	# the deletion and from any other monotone shape with the same endpoint.
	for value in [0.0, 0.6, 1.0, 10.0, 1000.0, 1.0e9]:
		var attacker := _attacker()
		attacker.stats.add_modifier(
			StatModifier.new(CombatStats.PENETRATION, Stat.Op.FLAT, value, &"test_mastery")
		)
		var parts := QiDamage.new().breakdown(
			_context(attacker, _defender(ElementStats.FIRE, 50.0), ElementStats.FIRE, 0.8)
		)
		assert_almost_eq(
			float(parts["defense_effective"]),
			float(parts["defense"]) / (1.0 + value / _tuning.pierce_scale),
			"penetration %s is exactly D / (1 + pen/pierce_scale)" % str(value)
		)
	# (c) The bound, at its sharpest: a defense a hundred times the pierce scale is still
	# strictly defended, because the reciprocal is in `(0, 1]` rather than a subtraction.
	var deep := _defender(ElementStats.FIRE, _tuning.pierce_scale * 100.0 * _tuning.resist_divisor)
	var piercing := _attacker()
	piercing.stats.add_modifier(
		StatModifier.new(
			CombatStats.PENETRATION, Stat.Op.FLAT, _tuning.pierce_scale, &"test_mastery"
		)
	)
	var parts := QiDamage.new().breakdown(_context(piercing, deep, ElementStats.FIRE, 0.8))
	assert_almost_eq(
		float(parts["defense_effective"]), float(parts["defense"]) * 0.5, "pierce_scale halves D"
	)
	assert_eq(
		float(parts["defense_effective"]) > 0.0,
		true,
		"so a hundred-times-deeper defense is halved, never deleted"
	)


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
		float(a["defense"]), 50.0 / _tuning.resist_divisor, "the stat channel still answers"
	)
	assert_eq(float(a["raw_term"]) > 0.0, true, "raw term intact")
	assert_eq(is_finite(float(a["total"])), true, "and it is a finite number")

	# (b) an element the rule table does not know.
	var unknown := _context(attacker, target, &"shadow", 0.8)
	var b := QiDamage.new().breakdown(unknown)
	assert_eq(b["element"], "", "an unknown element is no element")
	assert_eq(float(b["share"]), 0.0, "so no elemental share")
	assert_almost_eq(
		float(b["elemental_power"]), 0.0, "and no channel resolves for an id nobody published"
	)
	assert_eq(float(b["raw_term"]) > 0.0, true, "raw term intact")
	assert_eq(is_finite(float(b["total"])), true, "finite")

	# (c) a defender nobody attached the element provider to: defense reads 0.0 and
	# therefore mitigation 1.0 -- the only way `mitigation` is ever exactly `1.0`, because
	# the curve is asymptotic and never reaches it for a positive `D`.
	var bare := Actor.new(&"bare", {Stat.WILL: 10.0})
	bare.add_resource(ResourcePool.new(&"health", 1000.0))
	var c := QiDamage.new().breakdown(_context(attacker, bare, ElementStats.FIRE, 0.8))
	assert_almost_eq(float(c["defense"]), 0.0, "an unattached defender resists nothing")
	assert_almost_eq(float(c["mitigation"]), 1.0, "so mitigation is exactly 1.0")
	assert_eq(is_finite(float(c["total"])), true, "finite")

	# (d) an unelemental technique with NO authored share: physical, whole magnitude raw.
	# The tuning default does not reach it -- it prices an elemental technique that
	# forgot its share (BL-0348's physical-by-default ruling), and the pure-qi channel
	# is opt-in by authoring one (see the omni-channel case below).
	var d := QiDamage.new().breakdown(_context(attacker, target, &"", 0.0))
	assert_eq(d["element"], "", "no element authored")
	assert_eq(float(d["share"]), 0.0, "and no authored share")
	assert_eq(float(d["raw"]), float(d["magnitude"]), "the whole magnitude is raw")
	assert_almost_eq(
		float(d["total"]),
		float(d["magnitude"]) * float(d["raw_attack"]),
		"so the hit is a pure spiritual hit"
	)


## ADR 0004's "pure qi is a real omni channel": an elementless technique that AUTHORS a
## share reads the omni pair -- the summed affinity / summed mastery channel
## `ElementProvider` publishes -- and never the matchup table, so its elemental term
## exists with no STRONG/WEAK swing. This is the door a pure-qi blow walks through.
func test_an_elementless_technique_with_a_share_reads_the_omni_channel() -> void:
	var attacker := _attacker(ElementStats.FIRE)
	var target := _defender(ElementStats.WOOD, 0.0)
	var parts := QiDamage.new().breakdown(_context(attacker, target, &"", 0.8))
	assert_almost_eq(
		float(parts["elemental_power"]), _fire_affinity(), "the omni power is the summed affinity"
	)
	assert_almost_eq(float(parts["share"]), 0.8, "the authored share is read, not zeroed")
	assert_almost_eq(float(parts["matchup"]), 1.0, "and the pure channel is always NEUTRAL")
	assert_eq(float(parts["elemental_term"]) > 0.0, true, "so the elemental term exists")
	assert_almost_eq(
		float(parts["total"]),
		float(parts["raw_term"]) + float(parts["elemental_term"]),
		"and the total is the two terms, as for any element"
	)


## The other half of the door: an elementless technique that authors NO share stays
## PHYSICAL — and the SHIPPED default is now `0.0` (BL-0348's ruling: an un-authored
## attack is physical by default). The non-zero case is proven against a LOCAL tuning,
## because the rule is about elementless attacks rather than about this one number.
func test_the_tuning_default_never_reaches_an_elementless_attack() -> void:
	var attacker := _attacker(ElementStats.FIRE)
	var target := _defender(ElementStats.WOOD, 0.0)
	assert_almost_eq(_tuning.default_element_share, 0.0, "the shipped default is physical")
	# A tuning that ships a NON-ZERO default still does not reach an elementless attack:
	# the default prices a technique that NAMED an element and forgot its share.
	var loud := CombatTuning.new()
	loud.default_element_share = 0.5
	var mechanism := QiDamage.new()
	mechanism.tuning = loud
	var parts: Dictionary = mechanism.breakdown(_context(attacker, target, &"", 0.0))
	assert_almost_eq(float(parts["share"]), 0.0, "a non-zero default does not reach it")
	assert_almost_eq(
		float(parts["total"]),
		float(parts["magnitude"]) * float(parts["raw_attack"]),
		"so the hit is entirely raw"
	)
	# The positive control: the same default DOES price an ELEMENTAL technique that
	# authored none, so the refusal above is about elementless attacks and not about a
	# mechanism that ignores its tuning.
	var priced: Dictionary = mechanism.breakdown(_context(attacker, target, ElementStats.FIRE, 0.0))
	assert_almost_eq(float(priced["share"]), 0.5, "a named element reads the default")


## A null context, a null proposal and a NaN magnitude are the three remaining ways a
## half-built hit could crash the spine three stages downstream. All three return a
## number, and the number is finite.
func test_null_context_null_proposal_and_nan_magnitude_all_degrade() -> void:
	var mech := QiDamage.new()
	var empty := mech.breakdown(null)
	assert_eq(float(empty["total"]), 0.0, "a null context is the empty proposal")
	# ADR 0200 REPLACED the read model's key set rather than extending it: `resistance` is
	# gone (it named a PERCENT, and the percent is now an OUTPUT of the ratio) and four keys
	# took its place -- `defense`, `defense_effective`, `divisor_k` and `mitigation_rate`.
	# The count is stated, not derived from the mechanism, so a future author who adds or
	# drops a key has to come here and say why.
	assert_eq(int(empty.size()), 21, "and it carries the full key set for a panel")
	for key in [
		"defense",
		"defense_effective",
		"divisor_k",
		"mitigation_rate",
		"mitigation",
		"penetration",
		"resistance"
	]:
		if key == "resistance":
			# Deliberately asserted as GONE rather than skipped: ADR 0200's docblock on
			# `QiDamage.breakdown` says `resistance` "is not spelled by a second key", so a
			# spelling that answers to the old name would defeat the point of the rename.
			assert_eq(empty.has("resistance"), false, "`resistance` is gone from the read model")
			continue
		assert_eq(empty.has(key), true, "the read model publishes %s" % key)
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
## `resist_divisor == 0.0` and `mitigation_ceiling == 0.0` are the two guards ADR 0200's
## ratio adds, and a bare tuning is exactly the state a caller reaches by forgetting the
## `.tres`.
func test_a_degenerate_tuning_never_divides_by_zero() -> void:
	var bare := CombatTuning.new()
	var mech := QiDamage.new()
	mech.rules = _rules
	mech.tuning = bare
	var parts := mech.breakdown(
		_context(_attacker(), _defender(ElementStats.FIRE, 50.0), ElementStats.FIRE, 0.0)
	)
	assert_eq(float(parts["defense"]), 0.0, "a 0.0 divisor is no contest, not a division")
	assert_eq(float(parts["defense_effective"]), 0.0, "and a 0.0 pierce scale does nothing")
	assert_almost_eq(float(parts["mitigation"]), 1.0, "so mitigation is 1.0")
	assert_eq(float(parts["share"]), 0.0, "and the default share is 0.0 too")
	assert_eq(is_finite(float(parts["total"])), true, "the number is finite")


## A `mitigation_ceiling` or `damage_reduction_cap` above 1.0 would make `mitigation`
## negative and S9's ONE sign flip would spend the elemental term as a HEAL. Clamped on read.
##
## ## ADR 0200: `resist_cap` is deleted, so the ceiling is the input that must be clamped
##
## This used to write `greedy.resist_cap = 4.0` and assert that the CLAMP bound it. The cap
## is gone, and what replaced it is not a cap on a resistance but a MULTIPLIER on the whole
## curve, so the guard that matters is different: `_mitigation_of` reads
## `clampf(tuning.mitigation_ceiling, 0, 1)`, and a ceiling of `4.0` therefore reads as
## `1.0`. The heal is still impossible, and now for the reason the production docblock gives
## (`combat_tuning.gd:95-98`): the clamp is on the CEILING THE AUTHOR TYPED, and the curve's
## output is never clamped, which is the whole distinction ADR 0200 turns on.
func test_a_ceiling_above_one_cannot_turn_a_hit_into_a_heal() -> void:
	var greedy := CombatTuning.new()
	greedy.default_element_share = 0.8
	greedy.resist_divisor = 100.0
	greedy.mitigation_ceiling = 4.0
	greedy.defense_divisor_k = 0.45
	greedy.pierce_scale = 10.0
	greedy.damage_reduction_cap = 3.0
	# The stat-id PREFIXES too. A bare `CombatTuning.new()` ships them empty, so
	# `_suffixed("", "fire")` names the stat `&"fire"`, which nothing derives -- the cap
	# assertions below were reading a defense of 0.0 and passing for the wrong reason.
	greedy.element_power_prefix = "element_power_"
	greedy.resist_resistance_prefix = "element_defense_"
	var mech := QiDamage.new()
	mech.rules = _rules
	mech.tuning = greedy
	# Defense points at four times the divisor, so `D = 4.0` against a `K` of `4.5`. The
	# ceiling is read clamped to `1.0`, so `m = 1.0 * 4.0 / 8.5 = 0.470588` -- strictly below
	# `1.0` even at a ceiling that was authored at `4.0`, so the mitigation is a real positive
	# number rather than a sign flip.
	var defender := _defender(ElementStats.FIRE, greedy.resist_divisor * 4.0)
	defender.stats.add_modifier(
		StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 1.0, &"test_full_reduction")
	)
	var parts := mech.breakdown(_context(_attacker(), defender, ElementStats.FIRE, 0.8))
	assert_almost_eq(float(parts["defense"]), 4.0, "400 points over the divisor")
	assert_almost_eq(float(parts["mitigation_rate"]), 4.0 / (4.5 + 4.0), "the ratio itself")
	assert_almost_eq(
		float(parts["mitigation"]),
		1.0 - 4.0 / (4.5 + 4.0),
		"the ceiling is read clamped to 1.0, so the mitigation is strictly positive"
	)
	assert_almost_eq(float(parts["mitigated"]), 0.0, "the reduction clamp holds")
	assert_eq(float(parts["damage_reduction"]), 1.0, "reduction is read as 1.0, not 3.0")
	assert_eq(float(parts["total"]) >= 0.0, true, "never negative: no second sign flip")
	# And the clamp is on the CEILING alone: `mitigation_rate` is published unclamped, so a
	# panel can still see the curve's own reading. The healing shape is only reachable if
	# the clamp is removed, and this is the assertion that would notice.
	assert_eq(float(parts["mitigation_rate"]) < greedy.mitigation_ceiling, true, "unclamped curve")


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
	# And the surface a screen reads carries it too. `inspect` is the read model
	# a screen actually reaches; it used to be preceded by a `learn_preview` call,
	# which published the same shape under a second name and was deleted as a second
	# door to a learn (DEF-0300). The assertion below is the one that matters.
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
