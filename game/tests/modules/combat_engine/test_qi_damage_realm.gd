extends "res://tests/modules/combat_engine/qi_damage_fixture.gd"

## ADR 0069's realm-invariance half of the qi-damage contract.
##
## Split out of `test_qi_damage.gd` (which holds the mechanism's own arithmetic)
## only because the combined file exceeded the 1000-line lint cap. The pinned actor
## helpers live in `qi_damage_fixture.gd` so both suites share one copy.


## The element fraction of a qi hit is realm-INVARIANT, because
## `ElementsApi.attach` writes a source-tagged `MULT` on `element_power_<e>` and
## `RealmScaling.apply` writes the same-shaped `MULT` on `ATTACK_SPIRITUAL`.
##
## Powers are read off the ladder rather than pasted, so a retune of
## `realm_power_table.tres` moves the test with the code instead of breaking it.
func test_the_element_fraction_is_realm_invariant() -> void:
	var share := 0.8
	var fractions := []
	var observed := []
	for realm_id in [&"qi_refining", &"spirit_sea"]:
		var power := _power_of(realm_id)
		var attacker := _attacker()
		attacker.set_path(PathState.new(PathState.QI, realm_id))
		RealmScaling.apply(attacker)
		# Re-apply the element half: `RealmScaling.apply` clears the shared source tag
		# wholesale (core has no prefix matching), so the element modifiers have to be
		# rewritten -- which is exactly what `ElementsApi.apply_realm_modifiers` is for.
		ElementsApi.apply_realm_modifiers(attacker, _rules)
		var target := _defender(ElementStats.FIRE, 0.0)
		target.set_path(PathState.new(PathState.QI, realm_id))
		RealmScaling.apply(target)
		ElementsApi.apply_realm_modifiers(target, _rules)
		var parts := QiDamage.new().breakdown(
			_context(attacker, target, ElementStats.FIRE, share, 100.0, ElementStats.WOOD)
		)
		var subtotal := float(parts["subtotal"])
		fractions.append(float(parts["elemental_term"]) / subtotal)
		observed.append(
			{
				"realm": String(realm_id),
				"power": power,
				"attack_spiritual": float(parts["raw_attack"])
			}
		)
		assert_almost_eq(
			float(parts["elemental_power"]),
			float(_fire_affinity()) * power,
			"element_power_fire took the authored realm power at %s" % String(realm_id),
			1e-3
		)
		assert_almost_eq(
			float(parts["raw_attack"]) / float(_raw_attack_of(&"qi_refining")),
			power,
			"ATTACK_SPIRITUAL took the same authored power",
			1e-3
		)
	# Without the fix the R11 fraction collapses to ~0.43 (measured 0.3678 in the ADR's
	# own build). Stated as the arithmetic rather than asserted, because the whole point
	# is that it CANNOT be observed any more.
	var collapse := (10.0 * 0.8 * 1.0) / (10.0 * 0.8 * 1.0 + 0.2 * 25.0 * _power_of(&"spirit_sea"))
	assert_eq(collapse < fractions[1], true, "the unfixed R11 fraction is far lower")
	assert_almost_eq(
		fractions[0],
		fractions[1],
		(
			"the element fraction is identical at R1 and R11 (measured %s / %s)"
			% [str(fractions[0]), str(fractions[1])]
		),
		1e-6
	)
	assert_eq(fractions.size(), 2, "two realms measured")


## `RealmScaling.SCALED_STATS` cannot hold a dynamic id, which is why the fix is a
## modifier and not a list entry -- and why the resistance channel must stay OUT of it.
func test_the_realm_modifier_covers_power_and_never_resistance() -> void:
	var actor := Actor.new(&"mage", {Stat.SPIRIT: 5.0})
	actor.set_path(PathState.new(PathState.QI, &"spirit_sea"))
	RealmScaling.apply(actor)
	var power_before := actor.stats.derived(ElementStats.power_id(ElementStats.FIRE))
	assert_almost_eq(power_before, 0.0, "no affinity, no power to scale")
	actor.set_affinity(ElementStats.FIRE, 10.0)
	actor.set_affinity(ElementStats.WATER, 10.0)
	# `attach` is REQUIRED, not decoration: `element_power_<e>` is contributed by
	# `ElementProvider` and reads `0.0` on an actor nobody attached one to, so the realm
	# MULT was being written onto a base of nothing. A realm modifier cannot make a stat
	# exist. `attach` writes the provider AND the realm half, so the resistance baseline is
	# read AFTER it -- otherwise the "unchanged" comparison below would be measuring the
	# provider appearing rather than the realm multiplier being withheld.
	ElementsApi.attach(actor, _rules)
	var power_with_modifier := actor.stats.derived(ElementStats.power_id(ElementStats.FIRE))
	var resist_after := actor.stats.derived(ElementStats.resistance_id(ElementStats.FIRE))
	assert_almost_eq(
		power_with_modifier,
		10.0 * _power_of(&"spirit_sea"),
		"element_power_fire took R11's authored power"
	)
	assert_almost_eq(resist_after, 5.0, "element_resistance_fire is the affinity's own half")
	# Re-applying replaces rather than stacks, which is what keeps a second breakthrough
	# from compounding the multiplier -- and it touches the resistance channel not at all,
	# which is the property this suite exists for.
	ElementsApi.apply_realm_modifiers(actor, _rules)
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)),
		power_with_modifier,
		"re-applying is idempotent"
	)
	assert_almost_eq(
		actor.stats.derived(ElementStats.resistance_id(ElementStats.FIRE)),
		resist_after,
		"element_resistance_fire is a RATE and did NOT take the realm power"
	)


## `RealmScaling.apply` clearing the shared source tag wholesale takes the element
## modifiers with it, so the half has to be re-applied. Measured rather than asserted
## from the docstring, because it is the one thing in this fix a caller must know.
func test_realm_scaling_alone_wipes_the_element_half_of_the_modifier() -> void:
	var actor := Actor.new(&"mage", {Stat.SPIRIT: 5.0})
	actor.set_path(PathState.new(PathState.QI, &"spirit_sea"))
	actor.set_affinity(ElementStats.FIRE, 10.0)
	ElementsApi.attach(actor, _rules)
	var scaled := actor.stats.derived(ElementStats.power_id(ElementStats.FIRE))
	assert_almost_eq(scaled, 10.0 * _power_of(&"spirit_sea"), "attach wrote the realm MULT")
	RealmScaling.apply(actor)
	var wiped := actor.stats.derived(ElementStats.power_id(ElementStats.FIRE))
	assert_almost_eq(
		wiped, 10.0, "RealmScaling.apply cleared the shared source tag, so the half is gone"
	)
	ElementsApi.apply_realm_modifiers(actor, _rules)
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)),
		scaled,
		"and one call puts it back"
	)


## The NEGATIVE case for the realm fix, which is what makes the invariance above mean
## something. Without the `ElementsApi.attach` realm modifier an off-ladder-attached
## actor's power is FLAT while its `ATTACK_SPIRITUAL` grows by 3.70x at R11 -- the
## element's share of the hit collapses, and that is the defect the fix removes.
func test_the_element_fraction_would_collapse_without_the_realm_modifier() -> void:
	var flat := Actor.new(&"attacker", ATTACKER_BASE)
	flat.add_resource(ResourcePool.new(&"health", 1000.0))
	flat.set_affinity(ElementStats.FIRE, _fire_affinity())
	# `attach` BEFORE the path, deliberately. `ElementsApi.attach` writes the provider AND
	# calls `apply_realm_modifiers`, and `apply_realm_modifiers` returns early on an actor
	# with no realm on the ladder -- so attaching first installs the provider and writes no
	# MULT, which is exactly the "no realm modifier" state this negative case needs. The
	# old order (path first, then no `attach` at all) left the actor with NO provider, so
	# `element_power_fire` read `0.0` and the "flat" case was not flat -- it was absent,
	# which is why it asserted 10.0 and measured 0.0.
	ElementsApi.attach(flat)
	flat.set_path(PathState.new(PathState.QI, &"spirit_sea"))
	RealmScaling.apply(flat)
	var fixed_actor := _attacker()
	fixed_actor.set_path(PathState.new(PathState.QI, &"spirit_sea"))
	RealmScaling.apply(fixed_actor)
	ElementsApi.apply_realm_modifiers(fixed_actor, _rules)
	var flat_parts := QiDamage.new().breakdown(
		_context(
			flat,
			_defender(ElementStats.FIRE, 0.0),
			ElementStats.FIRE,
			0.8,
			100.0,
			ElementStats.WOOD
		)
	)
	var fixed_parts := QiDamage.new().breakdown(
		_context(
			fixed_actor,
			_defender(ElementStats.FIRE, 0.0),
			ElementStats.FIRE,
			0.8,
			100.0,
			ElementStats.WOOD
		)
	)
	assert_almost_eq(
		float(flat_parts["elemental_power"]), _fire_affinity(), "power stayed realm-FLAT"
	)
	assert_almost_eq(
		float(fixed_parts["elemental_power"]),
		_fire_affinity() * _power_of(&"spirit_sea"),
		"while the fixed actor's power took the authored power"
	)
	var flat_fraction := float(flat_parts["elemental_term"]) / float(flat_parts["subtotal"])
	var fixed_fraction := float(fixed_parts["elemental_term"]) / float(fixed_parts["subtotal"])
	assert_eq(
		flat_fraction < fixed_fraction,
		true,
		"so the element's share of the hit COLLAPSES without the modifier"
	)
	assert_almost_eq(
		flat_fraction,
		8.0 / (8.0 + 0.2 * 25.0 * _power_of(&"spirit_sea")),
		"and it lands on exactly the fraction the unfixed arithmetic predicts",
		1e-6
	)


# --- the tier-2 mastery divisor (ADR 0069) --------------------------------------


## The tax falls only on the dominant tier, and tier 1 is BIT-FOR-BIT unchanged. This
## is why `tests/modules/elements/test_element_provider.gd::test_mastery_scales_power`
## passes unmodified; this suite asserts the same number from the other side.
func test_tier_one_mastery_is_bit_for_bit_unchanged() -> void:
	var actor := Actor.new(&"mage", {ElementStats.mastery_id(ElementStats.FIRE): 5.0})
	actor.set_affinity(ElementStats.FIRE, 10.0)
	ElementsApi.attach(actor)
	assert_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)),
		15.0,
		"10.0 affinity x (1 + 5.0 x 0.1 / 1.0) -- the tier-1 divisor is exactly 1.0"
	)
	for element in ElementStats.BASE_ELEMENTS:
		var basic := Actor.new(&"basic", {ElementStats.mastery_id(element): 5.0})
		basic.set_affinity(element, 10.0)
		ElementsApi.attach(basic)
		assert_eq(
			basic.stats.derived(ElementStats.power_id(element)), 15.0, "%s is unchanged" % element
		)


## Tier 2 pays the tax, strictly, and the tax divides the MASTERY TERM only: power
## still rises monotonically with mastery, and affinity is untouched.
func test_tier_two_pays_the_tax_and_mastery_still_pays() -> void:
	var divisor := 1.0 + (2 - 1) * ElementProvider.TIER_MASTERY_STEP
	var mastery_actor := Actor.new(&"mage", {ElementStats.mastery_id(ElementStats.LIGHTNING): 5.0})
	mastery_actor.set_affinity(ElementStats.LIGHTNING, 10.0)
	ElementsApi.attach(mastery_actor)
	assert_almost_eq(
		mastery_actor.stats.derived(ElementStats.power_id(ElementStats.LIGHTNING)),
		10.0 * (1.0 + 0.1 * 5.0 / divisor),
		"tier 2's mastery term is taxed by the tier divisor",
		1e-6
	)
	assert_eq(
		mastery_actor.stats.derived(ElementStats.power_id(ElementStats.LIGHTNING)) < 15.0,
		true,
		"strictly less than the same numbers in tier 1"
	)

	# Zero mastery is the untaxed case for tier 2 too: the divisor rides the mastery
	# coefficient, so a trainer with no mastery pays nothing.
	var novice := Actor.new(&"novice")
	novice.set_affinity(ElementStats.LIGHTNING, 10.0)
	ElementsApi.attach(novice)
	assert_almost_eq(
		novice.stats.derived(ElementStats.power_id(ElementStats.LIGHTNING)),
		10.0,
		"zero mastery in tier 2 is exactly affinity",
		1e-9
	)
	# And monotonic: more mastery is still more power, just less marginal power.
	var higher := Actor.new(&"adept", {ElementStats.mastery_id(ElementStats.LIGHTNING): 9.0})
	higher.set_affinity(ElementStats.LIGHTNING, 10.0)
	ElementsApi.attach(higher)
	assert_eq(
		(
			higher.stats.derived(ElementStats.power_id(ElementStats.LIGHTNING))
			> mastery_actor.stats.derived(ElementStats.power_id(ElementStats.LIGHTNING))
		),
		true,
		"mastery still pays at tier 2 -- the tax changes what it costs, not whether"
	)
