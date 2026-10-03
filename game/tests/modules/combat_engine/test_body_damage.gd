extends "res://tests/modules/combat_engine/body_damage_fixture.gd"

## ADR 0070: body damage is FLAT SUBTRACTION AT A MERIDIAN.
##
## ## The formula, asserted rather than argued
##
## ```
## gross        = attacker ATTACK_PHYSICAL
## meridian     = resolve_location(...)              # 20 meridians, not 60 huyệt
## point        = the huyệt within it
## channel      = target.meridians.get_meridian(meridian_id)
## resistance   = DEFENSE_PHYSICAL * MERIDIAN_ARMOUR_STEP * channel.state_rank()
##              + tissue_defence(meridian_id, target)
## penetration  = maxf(gross - resistance, gross * MIN_PENETRATION_RATIO)   # 0.10
## mitigated    = penetration * point_multiplier(point) * channel_multiplier(channel)
## damage       = mitigated * (1 - DAMAGE_REDUCTION)
## ```
##
## This file carries the FORMULA itself — the flat subtraction, the tissue weighting, the
## reduction channel and the channel ladder that prices the armour.
## `MIN_PENETRATION_RATIO` and the saturation claim moved to `test_body_damage_floor.gd`:
## they are one subject (a subtraction that can be floored) and together they took this
## file past the 400-line cap. The one-flag-opposite-signs properties (`blocked`,
## `injured`) are in `test_body_damage_flags.gd`; aim, wounds, necrosis and degradation
## are in `test_body_damage_aim.gd` and `test_body_damage_wounds.gd`. The actor
## arithmetic lives in `body_damage_fixture.gd`, shared, so no two files can drift while
## both stay green against their own copies.
##
## Every number here is DERIVED from a real actor's live derived read or from the shipped
## `CombatTuning`, never pasted out of ADR 0070. A stat rebalance moves the assertions
## with it, which is the only way they stay honest.

# --- the formula, row by row --------------------------------------------------


## One fully re-derived case. Every primitive is computed here from the pinned actor's own
## stats and the shipped tuning, then compared with what `breakdown` reported — so a
## column that disagrees with ADR 0070 is an ordering bug, and a row that disagrees with
## its own arithmetic is a formula bug, and the two are told apart by WHICH of the
## assertions below fails.
##
## `lung` is opened (`state_rank() == 1`), so it carries exactly one step of armour and
## one step of channel multiplier: the smallest non-zero case, where a sign or an
## off-by-one-step shows up undivided by twenty.
func test_the_formula_is_re_derived_from_the_actors_own_reads() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var parts := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")

	var gross := attacker.stats.derived(Stat.ATTACK_PHYSICAL)
	var defense := target.stats.derived(Stat.DEFENSE_PHYSICAL)
	var channel := target.meridians.get_meridian(&"lung")
	var expected_armour := defense * _tuning.meridian_armour_step * float(channel.state_rank())
	var expected_floor := gross * _tuning.min_penetration_ratio
	var expected_penetration := maxf(gross - expected_armour, expected_floor)
	var site := _site_of(parts, &"lung")
	var expected_site := expected_penetration * float(site["multiplier"])

	# Pin the fixture's own assumptions, so a stat rebalance fails HERE and visibly
	# instead of quietly making every later number wrong for the same reason.
	assert_almost_eq(gross, PHYSIQUE * 2.0, "ATTACK_PHYSICAL is physique x 2")
	assert_almost_eq(defense, DEFENDER_PHYSIQUE * 1.5, "DEFENSE_PHYSICAL is physique x 1.5")

	assert_almost_eq(float(parts["gross"]), gross, "S4 gross is the attacker's own number")
	assert_almost_eq(
		float(parts["resistance"]),
		expected_armour + float(parts["tissue"]),
		"resistance is armour x rank, plus the tissue weighting"
	)
	assert_almost_eq(
		float(parts["tissue"]),
		_tissue_expectation(target),
		"tissue is the archetype weighting of the defender's own three body stats"
	)
	assert_almost_eq(float(parts["floor"]), expected_floor, "the floor is a share of the GROSS")
	assert_almost_eq(float(parts["penetration"]), expected_penetration, "penetration, both ways")
	assert_almost_eq(
		float(site["damage"]), expected_site, "one site is penetration x its multiplier"
	)
	assert_almost_eq(float(parts["subtotal"]), expected_site, "and S4 is the one site's worth")
	assert_almost_eq(float(parts["total"]), float(parts["subtotal"]), "S5 with no reduction")
	assert_eq(float(parts["refused"]), false, "and nothing was refused")


## S5 reads `Stat.DAMAGE_REDUCTION`, the ONE channel body shares with qi, and applies it
## to the whole amount — clamped to `damage_reduction_cap` on read, because above 1.0 the
## mitigation goes negative and S9's single sign flip would spend the amount as a HEAL.
## Both halves asserted: the linear factor in the normal range, and the clamp past it.
func test_damage_reduction_is_the_one_channel_body_shares_and_never_heals() -> void:
	var attacker := _attacker()
	var plain := _parts(attacker, _defender(["lung"]), BodyLocation.MODE_NAMED, &"lung")
	assert_almost_eq(float(plain["damage_reduction"]), 0.0, "no modifier, no reduction")
	assert_almost_eq(float(plain["mitigated"]), 1.0, "so the factor is the identity")

	for value in [0.25, 0.5, _tuning.damage_reduction_cap]:
		var target := _defender(["lung"])
		_reduction(target, value)
		var reduced := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
		assert_almost_eq(
			float(reduced["damage_reduction"]), value, "a %s reduction reads" % str(value)
		)
		assert_almost_eq(float(reduced["mitigated"]), 1.0 - value, "so the factor is 1 - value")
		assert_almost_eq(
			float(reduced["total"]),
			float(reduced["subtotal"]) * (1.0 - value),
			"and S5 reduces the WHOLE amount, not one site"
		)
	var greedy := _defender(["lung"])
	_reduction(greedy, _tuning.damage_reduction_cap + 5.0)
	var capped := _parts(attacker, greedy, BodyLocation.MODE_NAMED, &"lung")
	assert_almost_eq(
		float(capped["damage_reduction"]),
		_tuning.damage_reduction_cap,
		"past the cap it reads the cap, not the authored value"
	)
	assert_eq(float(capped["total"]) >= 0.0, true, "never negative: S9 has one sign flip")


## Tissue is a SEASONING on the armour term, not a second armour: ADR 0070 is explicit
## that it is "a per-meridian WEIGHTING of the defender's existing stats", not a third
## location axis. So it is a fraction of one armour step, and a body with none of the
## three stats reads no tissue at all rather than a NaN.
func test_tissue_is_a_seasoning_on_the_armour_term_and_never_a_second_armour() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.STRENGTHENED})
	var tissue := float(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")["tissue"])
	assert_almost_eq(tissue, _tissue_expectation(target), "the weighting, exactly")
	assert_eq(tissue > 0.0, true, "a body with the three stats really has tissue")
	var armour_step := target.stats.derived(Stat.DEFENSE_PHYSICAL) * _tuning.meridian_armour_step
	assert_eq(
		tissue < armour_step,
		true,
		"tissue is well under one armour step: %f vs %f" % [tissue, armour_step]
	)
	var lean := _parts(attacker, CombatTestKit.actor(&"lean"), BodyLocation.MODE_NAMED, &"lung")
	assert_eq(float(lean["tissue"]), 0.0, "a body with no body stats has no tissue")
	assert_eq(is_finite(float(lean["total"])), true, "and the hit is still a number")


## `tissue = tissue_scale * (sum of stat x archetype weight) / divisor`, for the heaviest
## archetype weight in `CombatTuning.tissue_weights` — found the same way
## `BodyDamage._weights_of` ranks, so the two cannot disagree about which archetype a
## body is described by, and a balance pass that re-weights the archetypes moves this
## assertion with it.
func _tissue_expectation(target: Actor) -> float:
	var heaviest := 0.0
	var heaviest_total := 0.0
	for key in _tuning.tissue_weights.keys():
		var row: Array = _tuning.tissue_weights[key]
		var sum := 0.0
		for value in row:
			sum += absf(float(value))
		if sum > heaviest_total:
			heaviest_total = sum
			heaviest = sum / maxf(1.0, float(row.size()))
	var total := 0.0
	for index in _tuning.tissue_stat_ids.size():
		total += target.stats.derived(StringName(_tuning.tissue_stat_ids[index])) * heaviest
	return _tuning.tissue_scale * total / _tuning.tissue_stat_divisor


# --- the channel ladder prices the armour ---------------------------------------


## `channel.state_rank()` is the armour multiplier, read through
## `MeridianState.STATE_ORDER` and never restated: closed 0, open 1, expanded 2,
## strengthened 3. A `closed` channel contributes no armour AT ALL — which is the refusal
## ADR 0070's flat subtraction exists to make expressible and a ratio has no vocabulary
## for.
func test_channel_rank_prices_the_armour_and_a_closed_channel_prices_none() -> void:
	var attacker := _attacker()
	var previous := -1.0
	for state in [
		MeridianState.CLOSED, MeridianState.OPEN, MeridianState.EXPANDED, MeridianState.STRENGTHENED
	]:
		var target := _defender(["lung"], {"lung": state})
		var parts := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
		var channel := target.meridians.get_meridian(&"lung")
		var label := String(state)
		assert_almost_eq(
			float(parts["channel_rank"]),
			float(channel.state_rank()),
			"%s: the reported rank IS core's own" % label
		)
		assert_almost_eq(
			float(parts["penetration"]),
			maxf(float(parts["gross"]) - float(parts["resistance"]), float(parts["floor"])),
			"%s: penetration is gross less resistance, floored" % label
		)
		if channel.state_rank() == 0:
			assert_almost_eq(
				float(parts["resistance"]),
				float(parts["tissue"]),
				"a CLOSED channel contributes NO armour -- only tissue"
			)
		assert_eq(float(parts["total"]) > 0.0, true, "%s: still a landed hit" % label)
		if previous >= 0.0:
			assert_eq(
				float(parts["penetration"]) <= previous,
				true,
				"%s: training a channel makes it a harder place" % label
			)
		previous = float(parts["penetration"])
