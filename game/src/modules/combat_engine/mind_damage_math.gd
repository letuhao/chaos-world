class_name MindDamageMath
extends RefCounted

## The values [MindDamage] reads and writes through: ADR 0200's mitigation ratio and the
## penetration that feeds it, the capacity ladder a collapse walks, the tuning resolver,
## the pool reader, and the total coercions every reader on this path uses (`finite`,
## `number`, `share`, `read`, `text`).
##
## Extracted from `mind_damage.gd` when that file passed gdlint's `max-file-lines`
## ceiling. Every member is const-free and calls no verb of the mechanism — the set was
## verified closed before the move — so this file names no `MindDamage` symbol and the
## pair loads one-way.
##
## Every verb is a TOTAL function of its arguments: a null tuning, an absent pool, a
## malformed `Variant` and a non-finite float each read a defined value rather than
## raising, because these run on hits that have already spent damage.


## ADR 0200's mitigation curve, the same shape `QiDamage` and `BodyDamage` use:
##
## ```
## m = mitigation_ceiling * D / (K + D)                 for D >= 0
## m = mitigation_ceiling * (2 - K / (K + |D|))        for D <  0
## ```
##
## `K = defense_divisor_k * base` is MIND'S OWN offense, per the owner's ruling that `K` is
## per-mechanism: the three stay independent and a qi rebalance cannot move a mind answer.
##
## `m` APPROACHES `mitigation_ceiling` and never reaches it, so a defender's
## `mental_defense` never stops paying -- the property `MENTAL_DEFENSE_CAP` destroyed, and
## the reason the published floor fell from `0.4` to `1 - 0.95 = 0.05`.
##
## The mirror branch is what makes a composure-sundered sea a real glass cannon: `m` goes
## ABOVE the ceiling and `1 - m` goes negative, so the erosion GROWS. Both branches give
## exactly `mitigation_ceiling` at `D == 0`, so the function is CONTINUOUS there, and that
## agreement is the assertion that catches a missing or mis-signed branch.
##
## Hole 1 is here: `0.0 / 0.0` is `NaN` and a `NaN` survives every `clampf`, so a
## non-positive denominator is caught rather than passed on.
static func mitigation_of(defense: float, divisor_k: float, tuning: CombatTuning) -> float:
	var ceiling := clampf(finite(tuning.mitigation_ceiling), 0.0, 1.0)
	if ceiling <= 0.0:
		return 0.0
	var k := maxf(0.0, finite(divisor_k))
	var magnitude := absf(finite(defense))
	var denominator := k + magnitude
	if denominator <= 0.0:
		return 0.0
	var share := magnitude / denominator if defense >= 0.0 else 2.0 - k / denominator
	return finite(ceiling * share)


## The attacker's penetration against this sea's defense, ANSWERED by the
## defender's `ABSORPTION`, as a magnitude on `CombatTuning.pierce_scale`'s
## scale. Zero when nothing was authored and never negative: a negative
## penetration would be a defence BONUS wearing an attacker's name, and the
## answered form keeps that property through `CombatStats.pierce`.
static func penetration_of(ctx: AttackContext) -> float:
	var id := CombatStats.PENETRATION
	return CombatStats.pierce(
		maxf(0.0, CombatStats.default_of(id) + finite(ctx.attacker_value(id))),
		maxf(
			0.0,
			(
				CombatStats.default_of(CombatStats.ABSORPTION)
				+ finite(ctx.target_value(CombatStats.ABSORPTION))
			)
		)
	)


## `structural_capacity`, through `get()`. `0.0` is a real answer for a sea nobody trained,
## and the caller then refuses to divide by it rather than producing an infinity.
static func capacity_of(state: Variant) -> float:
	if state == null:
		return 0.0
	return maxf(0.0, finite(number(read(state, &"structural_capacity", 0.0))))


## The sea tier ladder, shallowest first.
##
## ## Why it is NOT sorted
##
## This once read the `collapse_capacity_floors` keys back in SORTED order so that a tie could
## not be broken by whatever order a `Dictionary` happens to enumerate. That is determinism,
## and it is the wrong determinism: sorting only stands in for an ORDER, and the shipped tier
## names defeat it outright -- `"deep" < "shallow" < "vast"` alphabetically, so a sea pinned at
## `shallow`, the FIRST rung a real actor has and the one every collapse starts from, sorted to
## the LAST index and had no successor. Every collapse was then refused by hole 8 as "no
## successor", which is a correct guard firing on a ladder that was in the wrong order beneath it.
##
## The order now comes from the TABLE'S OWN INSERTION ORDER, which is authored, stable and the
## one place the ladder is declared, and it is VERIFIED rather than assumed: the authored
## capacities must be non-decreasing down the ladder, and a table that is not gets reversed
## rather than demoted towards the floor. No second copy of the capacities is kept here — this
## reads the same `collapse_capacity_floors` [method _capacity_floor_of] already reads.
static func ladder_of(tuning: CombatTuning) -> Array[StringName]:
	var keys: Array[StringName] = []
	if tuning.collapse_capacity_floors is Dictionary:
		for key in (tuning.collapse_capacity_floors as Dictionary).keys():
			keys.append(StringName(key))
	if keys.is_empty():
		return [&"shallow", &"deep", &"vast"]
	var previous: float = -1.0
	for tier in keys:
		var capacity := capacity_floor_of(tuning, tier)
		if capacity < previous:
			# Authored deepest-first: demote towards the floor rather than towards the top.
			keys.reverse()
			break
		previous = capacity
	return keys


## The `structural_capacity` a demoted sea is reset to, or `0.0` for "leave it alone". A tier
## missing from the authored table is never demoted further.
static func capacity_floor_of(tuning: CombatTuning, tier: StringName) -> float:
	if not (tuning.collapse_capacity_floors is Dictionary):
		return 0.0
	var value: Variant = (tuning.collapse_capacity_floors as Dictionary).get(String(tier), 0.0)
	return maxf(0.0, finite(number(value)))


# --- internals -----------------------------------------------------------------


## The tuning for a static entry point, which has no context to read a per-attack override
## off. Same three-step order, without the memoisation a per-hit read justifies.
static func tuning_or(source: CombatTuning) -> CombatTuning:
	if source != null:
		return source
	var shipped := CombatTuning.shipped()
	return shipped if shipped != null else CombatTuning.new()


## One `mind_cultivation` stat id, built from the prefix authored on `CombatTuning`. DATA
## rather than a named constant: `combat_engine` may not depend on `mind_cultivation`, and a
## `StringName` naming `MindStats` would be exactly the compile-time edge the registry would
## then have to declare. A prefix the tuning does not carry makes the id the bare name, which
## no provider contributes, so the term reads `0.0` — visibly broken rather than a null
## dereference, and the same shape `QiDamage._suffixed` has.
static func mind_stat(tuning: CombatTuning, suffix: String) -> StringName:
	return StringName(text(tuning.mind_stat_prefix) + suffix)


## A `ResourcePool` off an `Actor`, by an id read out of DATA. `call()` rather than a typed
## `resource()` so a `Variant` actor of another shape degrades to `null` instead of crashing
## a combat tick.
static func pool_of(actor: Variant, pool_id: StringName) -> Variant:
	if actor == null or pool_id == &"" or not (actor is Object):
		return null
	if not (actor as Object).has_method(&"resource"):
		return null
	return (actor as Object).call(&"resource", pool_id)


## Write a field on an injected sea through its setter when it HAS one, else through the
## field itself. The setter is preferred because a real sea clamps (`set_clarity` clamps to
## `[0, 1]`, `set_structural_capacity` floors at 0) and this module may not depend on that
## knowledge being true. A foreign object with neither answers without touching anything,
## which is a collapse that reported itself rather than one that corrupted a field.
static func settle(state: Variant, field: StringName, setter: StringName, amount: Variant) -> void:
	if state == null or not (state is Object):
		return
	var holder := state as Object
	if holder.has_method(setter):
		holder.call(setter, amount)
		return
	assign(holder, field, amount)


## Write a property only when the object already exposes it. A `set()` on an absent property
## pushes an engine warning and this project treats warnings as errors, so the whole file
## would fail to compile. This is what lets a caller hand over any object carrying the four
## fields the sea is read through and get a graceful degradation instead of a warning storm.
static func assign(object: Object, key: StringName, amount: Variant) -> void:
	for entry in object.get_property_list():
		if StringName(entry.get("name", &"")) == key:
			object.set(key, amount)
			return


## `Object.get` with a fallback, never `Object._get` — the latter is an engine hook and a
## same-arity declaration collides with it, which fails the whole file to compile and cascades
## into "Could not resolve class" for everything that depends on it.
static func read(value: Variant, key: StringName, fallback: Variant) -> Variant:
	if value == null or not (value is Object):
		return fallback
	var result: Variant = (value as Object).get(key)
	return result if result != null else fallback


## A rate read out of DATA and clamped into `[0, 1]`. Above `1.0` a "cap" exceeds the thing
## it caps and a defence becomes a liability — holes 3 and 4 in the module docblock.
static func share(value: Variant) -> float:
	return clampf(finite(float(value)), 0.0, 1.0) if (value is float or value is int) else 0.0


## Every arithmetic result in this file passes through here. The spine's ONE non-finite guard
## sits at S6's entrance and `maxf(NaN, chip) == NaN`, so a `NaN` produced here would reach
## `ResourcePool.change`, which has no guard of its own.
static func finite(value: float) -> float:
	return value if is_finite(value) else 0.0


## A `Variant` as a finite float, or `0.0`. A `bool` is deliberately not a number here:
## `true` as a share would silently read `1.0`.
static func number(value: Variant) -> float:
	if value is float or value is int:
		return finite(float(value))
	return 0.0


## A `Variant` as text, or `""` when it is not text at all.
##
## `StringName` is NOT a `String` — `x is String` is FALSE for one, because a `StringName` is
## its own interned type — so this accepted only literal `String` and silently discarded
## EVERY `StringName` it was handed. That is invisible in prose and catastrophic in effect:
## every `StringName`-typed field this module reads arrives empty, so
## - `tick_collapse` read a sea's `tier` as `""`, found no successor in the ladder and
##   REFUSED every collapse (hole 8, wrongly — the sea was demotable the whole time);
## - `_mind_stat` built the bare name `"mental_attack"` instead of `&"mental_attack"`, which
##   no provider contributes, so `mental_attack`, `mental_defense`, `mind_clarity`
##   (ADR 0215's rename of `mind_focus_chance`), `mind_veil` (of `mind_avoidance`) and
##   `illusion_resistance` ALL read `0.0` — which is why
##   "defense 0.0 saturates at the cap" could pass with a `0.0` on BOTH sides of the
##   assertion and the `40%` floor check beside it, and the fixture's sea silently stopped
##   being read at all;
## - `apply_deviation` zeroed the bare name `"mind_technique_power"` rather than the id.
##
## The fix is to accept both text types rather than to restate the value at each call site:
## `String()` on either is lossless. `_number` above stays strict on purpose, because a
## `StringName` used as a NUMBER is a genuine defect and not a spelling to paper over.
static func text(value: Variant) -> String:
	if value is String or value is StringName:
		return String(value)
	return ""


## What a null context answers. Every key present, so a panel rendering [method breakdown]'s
## shape never has to ask whether a key exists.
static func empty_parts() -> Dictionary:
	return {
		"kind": "disrupt",
		"share": 0.0,
		"mental_attack": 0.0,
		"base": 0.0,
		"mental_defense": 0.0,
		"defense": 0.0,
		"divisor_k": 0.0,
		"mitigation": 0.0,
		"illusion_resistance": 0.0,
		"awareness_ratio": 0.0,
		"coherence": 1.0,
		"focused": false,
		"erosion": 0.0,
		"structural_capacity": 0.0,
		"subtotal": 0.0,
		"total": 0.0,
		"turbulence": 0.0,
		"clarity_delta": 0.0,
		"awareness_delta": 0.0,
		"sea_bound": false,
		"rng_bound": false,
	}


## The share of a mind strike that lands at ANY `perception` and at ANY realm:
## `1 - mitigation_ceiling`. `0.05` at the shipped value.
##
## Published rather than left to every caller to re-derive, because this number IS the mind
## analogue of the spine's `min_chip_abs` and a second copy of the arithmetic is a second
## place for a rebalance to miss. It is what makes a mind fight's difficulty come from
## coherence, awareness and the matchup of intent rather than from stacking `perception`.
##
## ## It used to be `1 - MENTAL_DEFENSE_CAP`, and the difference is the ADR
##
## The OLD floor was `1 - 0.6 = 0.4`, true because the mitigation was CLAMPED at `0.6`:
## it was a WALL, and past it more `mental_defense` bought literally nothing. The new floor
## is `1 - mitigation_ceiling = 0.05`, true because the curve is ASYMPTOTIC: `m` is
## bounded strictly below the ceiling for every finite defense, so the floor is a much
## smaller bound, and what it bounds is much harder to reach -- which is the point. Both
## halves of the immunity invariant survive; the dead-stat half does not.
static func defense_floor(tuning: CombatTuning = null) -> float:
	var source := tuning
	if source == null:
		source = CombatTuning.shipped()
	if source == null:
		return 0.0
	return clampf(1.0 - share(source.mitigation_ceiling), 0.0, 1.0)
