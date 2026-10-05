class_name CombatDamage
extends RefCounted

## The damage model (ADR 0076). Pure, stateless, and deliberately blind to realms.
##
## ## A share, never a magnitude
##
## `resolve_hit` returns a **share of the target's own pool**, never an absolute number.
## The caller multiplies it by whatever pool is being spent. That is the whole reason the
## model works at all: `RealmScaling` multiplies `ATTACK_PHYSICAL` and friends by
## `RealmDef.power`, the 1.0-551x authored realm table (ADR 0050), while authored boss
## vitality spans 40-520. A model that treated the actor's attack as an absolute damage
## figure would make every boss a one-press kill at high realm and every deep boss
## unkillable at low realm. Spending a *share* of the defender's pool makes the realm
## table move both sides together, so it cannot desynchronise them.
##
## ## Every number here is a reference or a bound
##
## None of these is a power scale. The `REFERENCE_*` values are the derived numbers of an
## un-equipped actor built from the composition root's base attributes — the
## normalisation point the ratios divide by, not a curve. Nothing derives from a realm
## index, and nothing new is added to the three per-realm scales AGENTS.md names
## (`core/realm_power_table.tres`, `item_magnitude_scale.json`, the ADR 0055 technique
## ladder).

## `ATTACK_PHYSICAL` of an un-equipped actor: the point at which a blow is "par". Derived
## stats are read from the live actor, so gear moves the ratio in both directions.
const REFERENCE_ATTACK := 24.0
## `DEFENSE_PHYSICAL` of that same actor, and the denominator of the mitigation ratio.
const REFERENCE_DEFENSE := 18.0
## `PENETRATION` of that same actor. Penetration is normalised the same way defense is,
## so its baseline buys a partial removal instead of erasing every mitigation outright.
const REFERENCE_PENETRATION := 4.0

## How many times the reference attack a blow is worth, at most. A ceiling and not a
## curve: it bounds what realm strength can do to one exchange so no boss is ever a
## one-press kill and no fight is ever unwinnable.
const POWER_CEILING := 6.0
## The most defense and flat `DAMAGE_REDUCTION` (ADR 0022) can ever remove. An exchange
## always spends at least `1 - MITIGATION_CEILING` of a blow.
const MITIGATION_CEILING := 0.6
## The share of the mitigation ratio penetration can remove, at full penetration.
const PENETRATION_SHARE := 0.5

## What one par blow spends of the target's pool.
const BASE_SHARE := 0.3
## The floor, so a fight always terminates in bounded presses: no exchange can spend so
## little that a boss becomes unkillable. This is the anti-stall guard, and it is why the
## model needs no unbounded loop anywhere.
const MIN_SHARE := 0.05


## Resolve one blow.
##
## `offense` reads `attack`, `crit_chance`, `crit_damage`, `penetration`;
## `defense` reads `defense`, `damage_reduction`, `evasion`. Both are plain dictionaries
## so a boss profile authored on a `LootTier` and a live `Actor` resolve through the same
## function — `CombatApi.offense` / `CombatApi.guard` are the two builders.
##
## `rng` may be null, in which case the roll is `randf()`. Returns primitives only:
## `{share, crit, evaded, power, mitigation}`.
static func resolve_hit(
	offense: Dictionary, defense: Dictionary, rng: RandomNumberGenerator = null
) -> Dictionary:
	var roll := randf() if rng == null else rng.randf()
	var evaded := roll < clampf(float(defense.get("evasion", 0.0)), 0.0, 1.0)
	var power := clampf(
		float(offense.get("attack", 0.0)) / REFERENCE_ATTACK, MIN_SHARE / BASE_SHARE, POWER_CEILING
	)
	var mitigation := clampf(_mitigation(defense, offense), 0.0, MITIGATION_CEILING)
	var share := clampf(BASE_SHARE * power * (1.0 - mitigation), MIN_SHARE, 1.0)
	var crit := false
	if not evaded:
		crit = roll < clampf(float(offense.get("crit_chance", 0.0)), 0.0, 1.0)
		if crit:
			# `crit_damage` is a multiplier with a 1.5 baseline, not a bonus, so it
			# multiplies the share rather than adding to it.
			share = clampf(share * float(offense.get("crit_damage", 1.0)), MIN_SHARE, 1.0)
	if evaded:
		share = 0.0
	return {
		"share": share,
		"crit": crit,
		"evaded": evaded,
		"power": power,
		"mitigation": mitigation,
	}


## Defense as a fraction, less what penetration cuts, capped. Returned uncapped-in-sign:
## penetration can push it negative, and the caller clamps, so a heavily pierced target
## is never worse off than a bare one.
static func _mitigation(defense: Dictionary, offense: Dictionary) -> float:
	var armor := float(defense.get("defense", 0.0))
	# `defense / (defense + REFERENCE_DEFENSE)` is bounded by 1.0 by construction, so it
	# cannot run away as an actor's defense grows with its realm.
	var share := armor / (armor + REFERENCE_DEFENSE) if armor > 0.0 else 0.0
	# ADR 0022: `damage_reduction` has a 0.0 baseline, so it is already a flat 0..1
	# fraction and adds to the ratio rather than multiplying it.
	share += float(defense.get("damage_reduction", 0.0))
	var pierce := float(offense.get("penetration", 0.0))
	var cut := (
		pierce / (pierce + REFERENCE_PENETRATION) * PENETRATION_SHARE if pierce > 0.0 else 0.0
	)
	return share - cut
