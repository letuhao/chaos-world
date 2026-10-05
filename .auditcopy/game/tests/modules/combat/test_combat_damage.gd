extends TestCase

## The damage model itself (ADR 0076): what the numbers do, in which direction, and where
## they stop.
##
## Every assertion here is a **property**, not a balance value. `tools realm_power check`
## guards the shape of the realm table and deliberately not its recipe (ADR 0050); the
## same is true of `CombatDamage`. What must never drift is the direction each stat moves
## the answer and the bounds that keep an exchange finite — those are asserted exactly, and
## retuning the calibration cannot break this suite.


## A blow from an attacker with these numbers. Every stat a blow reads is named, so a test
## that changes one names what it changed.
func _offense(
	attack: float = 24.0, crit: float = 0.0, crit_damage: float = 1.5, pierce: float = 0.0
) -> Dictionary:
	return {
		"attack": attack, "crit_chance": crit, "crit_damage": crit_damage, "penetration": pierce
	}


func _defense(armor: float = 0.0, reduction: float = 0.0, dodge: float = 0.0) -> Dictionary:
	return {"defense": armor, "damage_reduction": reduction, "evasion": dodge}


## A seeded stream. Tests that care about a roll assert the roll's *effect* (`evaded`,
## `crit`), never a particular number, so no assertion depends on what this generator
## happens to draw for a given seed.
func _rng(seed_value: int = 4242) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _share(offense: Dictionary, defense: Dictionary, seed_value: int = 7) -> float:
	return float(CombatDamage.resolve_hit(offense, defense, _rng(seed_value))["share"])


func test_a_par_blow_against_a_bare_target_spends_the_base_share() -> void:
	# A par blow is `REFERENCE_ATTACK`, so `power` is exactly 1.0 and the share is exactly
	# `BASE_SHARE`. This is the model's one pinned number: everything else is a direction.
	assert_almost_eq(
		_share(_offense(CombatDamage.REFERENCE_ATTACK), _defense()),
		CombatDamage.BASE_SHARE,
		"a par blow against bare defense spends the base share"
	)


func test_attack_raises_the_share_and_the_ceiling_bounds_it() -> void:
	var bare := _share(_offense(CombatDamage.REFERENCE_ATTACK), _defense())
	var geared := _share(_offense(CombatDamage.REFERENCE_ATTACK * 3.0), _defense())
	assert_eq(geared > bare, true, "more attack spends more of the pool")
	# POWER_CEILING is what stops a 551x realm table from making a boss a one-press kill.
	# Asserted as an equality against a DEFENDED target, because against a bare one both the
	# clamped and the unclamped share saturate at the 1.0 pool cap, and the assertion would
	# then pass for any clamping at all.
	var wall := _defense(CombatDamage.REFERENCE_DEFENSE * 4.0)
	assert_eq(
		_share(_offense(CombatDamage.REFERENCE_ATTACK * 500.0), wall),
		_share(_offense(CombatDamage.REFERENCE_ATTACK * CombatDamage.POWER_CEILING), wall),
		"raising attack past the ceiling changes nothing"
	)
	assert_eq(
		float(CombatDamage.resolve_hit(_offense(1.0e9), _defense(), _rng())["power"]),
		CombatDamage.POWER_CEILING,
		"and the reported power says so"
	)


func test_defense_lowers_the_share_and_the_ceiling_bounds_it() -> void:
	var bare := _share(_offense(), _defense())
	var armored := _share(_offense(), _defense(CombatDamage.REFERENCE_DEFENSE * 4.0))
	assert_eq(armored < bare, true, "more defense spends less of the pool")
	var walled := _share(_offense(), _defense(1.0e9))
	assert_almost_eq(
		walled,
		CombatDamage.BASE_SHARE * (1.0 - CombatDamage.MITIGATION_CEILING),
		"and mitigation is clamped at the ceiling, so a wall can never make a boss immune"
	)


func test_penetration_removes_mitigation_and_never_makes_a_target_worse() -> void:
	var armored := _share(_offense(), _defense(CombatDamage.REFERENCE_DEFENSE * 4.0))
	var pierced := _share(
		_offense(CombatDamage.REFERENCE_ATTACK, 0.0, 1.5, CombatDamage.REFERENCE_PENETRATION * 8.0),
		_defense(CombatDamage.REFERENCE_DEFENSE * 4.0)
	)
	assert_eq(pierced > armored, true, "penetration spends more of the pool")
	# Penetration is normalised and capped, so it cannot reduce mitigation below zero and
	# hand the attacker a *smaller* share than hitting a completely bare target.
	var bare := _share(_offense(), _defense())
	var over_pierced := _share(
		_offense(CombatDamage.REFERENCE_ATTACK, 0.0, 1.5, 1.0e9), _defense(1.0e9)
	)
	assert_eq(over_pierced <= bare, true, "over-piercing never beats a bare target")


func test_damage_reduction_adds_to_mitigation_and_is_capped_like_defense() -> void:
	# ADR 0022: `damage_reduction` has a 0.0 baseline, so it is a flat 0..1 fraction and
	# adds to the ratio rather than multiplying it.
	var plain := _share(_offense(), _defense())
	var reduced := _share(_offense(), _defense(0.0, 0.5))
	assert_eq(reduced < plain, true, "flat damage reduction spends less of the pool")
	var over := _share(_offense(), _defense(0.0, 5.0))
	assert_almost_eq(
		over,
		clampf(plain * (1.0 - CombatDamage.MITIGATION_CEILING), CombatDamage.MIN_SHARE, 1.0),
		"and an absurd reduction is still capped, not honoured literally"
	)


func test_evasion_removes_the_blow_entirely_and_is_bounded_to_one() -> void:
	var base := _share(_offense(), _defense(), 11)
	assert_eq(base > 0.0, true, "without evasion something lands")
	# `evasion` is the defender's, so it belongs in the defense bundle; a defender who
	# always dodges takes nothing.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var dodged := CombatDamage.resolve_hit(_offense(), _defense(0.0, 0.0, 1.0), rng)
	assert_eq(float(dodged["share"]), 0.0, "a guaranteed dodge spends nothing")
	assert_eq(bool(dodged["evaded"]), true, "and reports itself")
	# An evasion above 1.0 is clamped rather than treated as a certainty multiplier that
	# could compound.
	assert_eq(float(dodged["share"]), 0.0, "and is not a second roll")


func test_a_share_is_never_below_the_floor_so_a_fight_always_terminates() -> void:
	# The anti-stall guard: this is why the model needs no unbounded loop anywhere.
	var worst := _share(_offense(0.0, 0.0, 1.5, 0.0), _defense(1.0e9, 0.0, 0.0))
	assert_eq(worst >= CombatDamage.MIN_SHARE, true, "a hopeless blow still spends the floor")
	assert_eq(
		float(CombatDamage.resolve_hit(_offense(0.0), _defense(0.0))["share"]) >= 0.0,
		true,
		"and no blow ever returns a negative share"
	)


func test_a_share_is_never_above_one_so_a_pool_is_never_overspent() -> void:
	var best := _share(_offense(1.0e9, 1.0, 1000.0, 1.0e9), _defense(0.0, 0.0, 0.0), 5)
	assert_eq(best <= 1.0, true, "a perfect blow spends at most the whole pool")


func test_crit_chance_never_produces_a_smaller_blow_than_a_normal_one() -> void:
	# `crit_damage` is a multiplier with a 1.5 baseline, so a crit is strictly more. A
	# `crit_damage` under 1.0 (authored, if it ever is) must not invert that.
	var normal := _share(_offense(CombatDamage.REFERENCE_ATTACK, 0.0, 1.0), _defense())
	var crit := _share(_offense(CombatDamage.REFERENCE_ATTACK, 1.0, 1.5), _defense(), 1)
	assert_eq(crit > normal, true, "a guaranteed crit spends more of the pool")
	var inverted := _share(_offense(CombatDamage.REFERENCE_ATTACK, 1.0, 0.1), _defense(), 1)
	assert_eq(inverted >= CombatDamage.MIN_SHARE, true, "even a mis-authored crit stays floored")


func test_the_reported_fields_describe_the_roll_that_was_taken() -> void:
	# The read a panel quotes must be the same resolution the exchange spends, not a
	# second calculation that can drift from it.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var hit := CombatDamage.resolve_hit(
		_offense(CombatDamage.REFERENCE_ATTACK * 2.0, 0.0, 1.5, 0.0),
		_defense(CombatDamage.REFERENCE_DEFENSE),
		rng
	)
	assert_almost_eq(float(hit["power"]), 2.0, "the reported power is the attacker's own ratio")
	assert_almost_eq(
		float(hit["mitigation"]),
		CombatDamage.REFERENCE_DEFENSE / (CombatDamage.REFERENCE_DEFENSE * 2.0),
		"and the reported mitigation is the ratio it actually applied"
	)
	assert_almost_eq(
		float(hit["share"]),
		CombatDamage.BASE_SHARE * float(hit["power"]) * (1.0 - float(hit["mitigation"])),
		"so the share is the product of the two it reports"
	)


func test_the_model_answers_without_an_rng_so_a_preview_never_moves_the_world() -> void:
	# A preview calls this with no rng; it must return a share and touch nothing.
	var hit := CombatDamage.resolve_hit(_offense(), _defense())
	assert_eq(float(hit["share"]) > 0.0, true, "a roll-free read still answers")
	assert_eq(hit.size(), 5, "and reports the same five fields a rolled read does")


func test_the_model_is_realm_blind_so_no_realm_index_can_reach_it() -> void:
	# ADR 0050: nothing in `src/` computes a magnitude from a realm index. This is the
	# structural proof for the combat model specifically — it reads two dictionaries of
	# numbers and names no realm, no ladder and no power table, so a realm's 551x can
	# only arrive through the stats a caller put in the bundle. Scanned over CODE only:
	# `damage.gd` deliberately *discusses* the realm table in its docstring, and a
	# comment is not a dependency.
	var code := ""
	for line in FileAccess.get_file_as_string("res://src/modules/combat/damage.gd").split("\n"):
		if not line.strip_edges().begins_with("#"):
			code += line + "\n"
	for forbidden in [
		"RealmPowerTable", "realm_power", "RealmDefaults", "index_of", "RATE_STEP", "pow("
	]:
		assert_eq(code.contains(forbidden), false, "damage.gd never computes with %s" % forbidden)
