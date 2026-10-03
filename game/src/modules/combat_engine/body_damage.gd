class_name BodyDamage
extends DamageMechanism

## Body damage is FLAT SUBTRACTION AT A MERIDIAN, and it can REFUSE a strike (ADR 0070).
##
## ## The formula, verbatim
##
## ```
## gross        = attacker ATTACK_PHYSICAL
## meridian     = resolve_location(...)           # 20 meridians, not 60 acupoints
## point        = the acupoint within it
## channel      = target.meridians.get_meridian(meridian_id)
## resistance   = DEFENSE_PHYSICAL * MERIDIAN_ARMOUR_STEP * channel.state_rank()
##              + tissue_defence(meridian_id, target)
## penetration  = maxf(gross - resistance, gross * MIN_PENETRATION_RATIO)     # 0.10
## mitigated    = penetration * point_multiplier(point) * channel_multiplier(channel)
## damage       = mitigated * (1 - DAMAGE_REDUCTION)
## ```
##
## and for `broad`, once per unlocked meridian, summed at `BROAD_MULT` — ADR 0070's "hits
## every unlocked meridian at `BROAD_MULT`", implemented as one sum rather than twenty
## proposals so a single strike is still one packet and one effect.
##
## ## Flat subtraction, NOT Keepverse's ratio, and the four reasons that decide it
##
## (1) A ratio never reaches zero, so it has no vocabulary for "this point is not
## defended" — and refusing a strike outright is this path's whole premise. (2) Body's
## premise is the INVERSE of qi's: `ElementRules.NOURISH = 0.75` means qi always lands
## something, and only this mechanism is allowed a `0.0`. (3) Dimensional: under a ratio
## `defense` is un-authorable — doubling it moves the result by less than doubling, so no
## designer can read it off the data. (4) A flat number IS a hit-point value, which is the
## only form a balance table can be reviewed in.
##
## ## `MIN_PENETRATION_RATIO` is load-bearing, and this is where it is proved
##
## Without the floor, enough `DEFENSE_PHYSICAL` and tissue drive `penetration` to `0.0`,
## the location multiplier multiplies nothing, and a stat the defender already had deletes
## the entire mechanic. The suite asserts the floor twice: against armour that REFUSES,
## and against armour that would otherwise floor to zero.
##
## ## The one refusal, and it is bounded below by the spine
##
## A `closed` channel has `state_rank() == 0`, so it contributes no channel armour; a
## `broad` strike has no single channel at all, so its `BROAD_MULT` average is below one.
## Both can drive the mechanism's `subtotal` to `0.0` when the armour or the floor
## conspires. That is a legitimate answer (ADR 0070), and it is not immunity: S8's chip
## floor restores a LANDED hit to at least `min_chip_abs`, so `subtotal == 0.0` means "this
## mechanism refuses this point", never "this attack is unhittable".
##
## ## `DAMAGE_REDUCTION` at S5, shared with qi on purpose
##
## Both are landed physical hits and the spine's S7 runs after `resolve`, so sharing it is
## not sharing the element table, the multiplicative shape or the location vocabulary. It
## is clamped to `damage_reduction_cap` for the same sign reason qi's is: above `1.0` the
## mitigation goes negative and S9's one sign flip would spend the amount as a HEAL.
##
## ## Wound severity is measured off the S4 SUBTOTAL, not the post-reduction amount
##
## A defender at full `DAMAGE_REDUCTION` has been hit just as hard, and basing severity on
## the post-S8 number would let the chip floor mint a wound out of a strike the flat
## subtraction had already refused. `DamageProposal.effects` are applied AFTER health by
## the spine (ADR 0067), so the wound cannot land before the blow it was earned by.
##
## ## The holes ADR 0070's own arithmetic leaves, each closed without a new constant
##
## 1. **`MIN_PENETRATION_RATIO` outside `[0, 1]`** would make armour a liability: above
##    1.0 the floor exceeds the gross and a well-defended point takes MORE. Clamped.
## 2. **`DAMAGE_REDUCTION_CAP > 1`** would make the total negative — a heal. Clamped, and
##    the proposal's own `maxf(0.0, ...)` is never the thing protecting the sign.
## 3. **A `BROAD_MULT` above 1.0** would make one area technique the strongest single hit
##    in the game, per channel, twenty times over. Clamped to `[0, 1]`: a sweep is coverage.
## 4. **`tissue_stat_divisor == 0`** would be a division by zero producing `NaN` on every
##    body with a non-positive pool. A non-positive or non-finite divisor reads as "no
##    tissue", the same degradation `QiDamage._resistance_of` gives a 0.0 divisor.
## 5. **A `NaN` gross** would survive every clamp — `maxf(NaN, floor) == NaN` — so every
##    term passes through `_finite` and no non-finite number can leave this file, which is
##    what the spine's single S6 guard is allowed to assume.

## `ctx.data` key carrying the aim mode: `named`, `random` or `broad`. A per-HIT choice,
## unlike `TechniqueDef.aim_meridian`, which is authored on the `.tres`.
const AIM_MODE_KEY := &"aim_mode"
## `ctx.data` key carrying the authored aim id.
const AIM_MERIDIAN_KEY := &"aim_meridian"
## `ctx.data` key carrying the defender's `BodyWounds` ledger.
const WOUNDS_KEY := &"body_wounds"
## `ctx.data` key overriding the tuning for one hit. `CombatTuning` is this module's own
## type, so it is named here and nowhere else on the body path.
const TUNING_KEY := &"tuning"

static var _shipped: CombatTuning = null

## The tuning this mechanism reads, when a caller binds one. Null means "the per-attack
## override, then [method CombatTuning.shipped]".
var tuning: CombatTuning = null


## S4. The flat-subtraction result for one landed hit, before any reduction. For a `broad`
## aim this is the sum over every unlocked meridian at `BROAD_MULT`; for `named` and
## `random` it is the one resolved location's worth.
func resolve(ctx: AttackContext) -> DamageProposal:
	var parts := breakdown(ctx)
	var proposal := DamageProposal.new(float(parts["subtotal"]))
	for site in parts["sites"]:
		(
			proposal
			. add_effect(
				BodyWounds.EFFECT_KIND,
				{
					BodyWounds.KEY_MERIDIAN: String(site.get("meridian_id", "")),
					BodyWounds.KEY_SEVERITY: _finite(float(site.get("damage", 0.0))),
				}
			)
		)
	return proposal


## S5. The defender's flat `Stat.DAMAGE_REDUCTION`, applied to the whole amount. Split
## from `resolve` because ADR 0067 splits S4 and S5 so a test can observe "the mechanism
## produced X" and "the reduction of X is Y" independently.
##
## A `null` proposal declines rather than crashes: the spine hands `DamageProposal.shared`
## when S4 returned one, and a hit whose mechanism declined must still answer a number here.
## A `broad` proposal's effects are CARRIED rather than rebuilt — S4 wrote one per struck
## meridian and rebuilding them here would risk the two stages disagreeing about how many
## meridians were hit.
func mitigate(ctx: AttackContext, proposal: DamageProposal) -> DamageProposal:
	var amount := _finite(_amount_of(proposal) * float(breakdown(ctx)["mitigated"]))
	var carried: Array[Dictionary] = proposal.effects.duplicate(true) if proposal != null else []
	return DamageProposal.new(amount, carried)


## Every primitive this mechanism computed, for a UI readout (ADR 0038: primitives in a
## `summary()` payload, never an engine object or a module type). No effect is primitives-
## only AND a plain-Dictionary gate can check on its own, which is why `sites` is an
## `Array[Dictionary]` of strings and floats rather than the richer site rows
## `BodyLocation` builds: a panel has to be able to assert on what it is handed.
##
## `subtotal` is what S4 returned and `total` is what S5 returned, so a panel can show the
## reduction line as the difference between two rows. Total, cheap, side-effect free: both
## `resolve` and `mitigate` read it and the arithmetic is pure.
func breakdown(ctx: AttackContext) -> Dictionary:
	if ctx == null:
		return _empty_parts()
	var tuning := _tuning_of(ctx)
	var gross := maxf(0.0, _finite(ctx.attacker_value(Stat.ATTACK_PHYSICAL)))
	var tissue := _tissue_of(ctx, tuning)
	var sites := _sites_of(ctx, tuning)
	# ONE penetration figure for the whole hit: `resistance` is a single sum, and a
	# `broad` sweep whose twenty sites each subtracted their own armour would be a
	# different formula from the ADR's rather than the ADR's formula applied twenty times.
	var defence := _finite(_resistance_of(ctx, tuning, sites) + tissue)
	var floor := maxf(0.0, gross * _share(tuning.min_penetration_ratio))
	var penetration := _finite(maxf(0.0, gross - defence))
	# `MIN_PENETRATION_RATIO` applied ONCE, so the floor is a share of the GROSS and never
	# grows with the strike. Applying it per site — as a `broad` sum of twenty floors —
	# would make an area technique's floor twenty times a single hit's at no extra price,
	# which is the opposite of what "a sweep is coverage" means.
	var struck := _finite(maxf(penetration, floor))
	var subtotal := 0.0
	var rows: Array[Dictionary] = []
	for site in sites:
		var point := maxf(0.0, _finite(float(site.get("multiplier", 0.0))))
		var value := _finite(struck * point)
		subtotal += value
		# `BodyLocation` builds a RICHER row than the four keys below: it already
		# separated `point_multiplier`, `channel_multiplier`, `state_rank`, `injured` and
		# `locked`, and a readout cannot do what ADR 0070's second inversion needs with a
		# single product. Rebuilding the row here DROPPED all five, so every panel and every
		# assertion asking "which of the two terms moved?" read a missing key. The four
		# primitives ADR 0038 requires are still primitives — the split is two floats that
		# multiply to the one already published — and the extra keys are copied through
		# rather than recomputed, so a panel can never disagree with the damage about why.
		var row := {
			"meridian_id": String(site.get("meridian_id", "")),
			"point_id": String(site.get("point_id", "")),
			"multiplier": point,
			"damage": value,
			"point_multiplier": _finite(float(site.get("point_multiplier", 0.0))),
			"channel_multiplier": _finite(float(site.get("channel_multiplier", 0.0))),
			"point_score": _finite(float(site.get("point_score", 0.0))),
			"state_rank": int(site.get("state_rank", 0)),
			"injured": bool(site.get("injured", false)),
			"locked": bool(site.get("locked", false)),
		}
		rows.append(row)
	subtotal = maxf(0.0, _finite(subtotal))
	var reduction := clampf(_finite(ctx.target_value(Stat.DAMAGE_REDUCTION)), 0.0, 1.0)
	var cap := clampf(_finite(tuning.damage_reduction_cap), 0.0, 1.0)
	var mitigated := clampf(1.0 - minf(reduction, cap), 0.0, 1.0)
	return {
		"mode": BodyLocation.mode_name(_mode_of(ctx)),
		"gated": not sites.is_empty(),
		"gross": gross,
		"defense_physical": maxf(0.0, _finite(ctx.target_value(Stat.DEFENSE_PHYSICAL))),
		"armour_step": maxf(0.0, _finite(tuning.meridian_armour_step)),
		"channel_rank": float(_rank_of(sites)),
		"tissue": tissue,
		"resistance": defence,
		"floor": floor,
		"penetration": struck,
		"refused": struck <= 0.0,
		"sites": rows,
		"subtotal": subtotal,
		"damage_reduction": minf(reduction, cap),
		"mitigated": mitigated,
		"total": maxf(0.0, subtotal * mitigated),
	}


## A `ctx_builder` for `CombatSpine.resolve_hit`: carries this mechanism's inputs and the
## defender's wound ledger through the ONE context, so the spine needs no sixth stage and
## no knowledge of what a body hit is (ADR 0067).
##
## ```
## CombatSpine.resolve_hit(attacker, target, technique, tuning, rng,
##     BodyDamage.builder(technique, BodyWounds.new()))
## ```
static func builder(
	p_technique: Variant = null,
	p_wounds: Variant = null,
	p_mode: StringName = &"",
	p_tuning: Variant = null
) -> Callable:
	return func(ctx: AttackContext) -> AttackContext:
		if ctx == null:
			return ctx
		if p_technique is Object:
			ctx.set_data(AIM_MERIDIAN_KEY, (p_technique as Object).get(&"aim_meridian"))
		if p_mode != &"":
			ctx.set_data(AIM_MODE_KEY, p_mode)
		if p_wounds != null:
			ctx.set_data(WOUNDS_KEY, p_wounds)
		if p_tuning is CombatTuning:
			ctx.set_data(TUNING_KEY, p_tuning)
		return ctx


## One wound's result, applied to `target`. The route a caller uses to settle a
## `DamageProposal`'s `effects[]` AFTER health (ADR 0067), which is the only ordering under
## which a wound may land: `contracts/location_resolver.gd`'s own `apply_wound` writes
## nothing on purpose, for exactly this reason.
func apply_wounds(
	target: Variant, proposal: DamageProposal, tuning: CombatTuning
) -> Array[Dictionary]:
	if target == null or proposal == null:
		return []
	return BodyWounds.new().apply_all(target, proposal.effects, tuning)


## Decay `wounds` by `delta` seconds. Separate from [method apply_wounds] because it is a
## COMBAT TICK, not a hit: `CombatSpine` has no stage for it and ADR 0070 does not add one.
static func decay(wounds: BodyWounds, delta: float, tuning: CombatTuning) -> Dictionary:
	return {} if wounds == null else wounds.decay(delta, tuning)


# --- internals -----------------------------------------------------------------


## The sites this hit touches: one row for `named` / `random`, one per unlocked meridian
## for `broad`. A body with no location axis — an NPC, a training dummy, a qi-only
## fighter — answers `[]`, and the mechanism then computes its UNGATED form: the flat
## subtraction with no armour at all, which is `LocationResolver.supports()` false
## refusing to invent a meridian that does not exist.
func _sites_of(ctx: AttackContext, tuning: CombatTuning) -> Array:
	# Read through the seam's OWN accessor, which is what `AttackContext._as_context`
	# documents a mechanism is meant to use. `meridian_network()` returns null for a
	# target that carries none, and null is a real answer: an NPC, a training dummy and a
	# qi-only fighter have no location axis, so their strike is UNGATED — the flat
	# subtraction with no armour at all — rather than a hit at a point that does not
	# exist. That is also what `LocationResolver.supports()` answers false for.
	if ctx.target == null or ctx.target.meridian_network() == null:
		return []
	var target: Variant = _target_source_of(ctx)
	var resolver := BodyLocation.new()
	var mode := _mode_of(ctx)
	if mode == BodyLocation.MODE_BROAD:
		return resolver.broad_sites(target, tuning)
	var site := resolver.site_of(target, _aim_of(ctx), mode)
	if String(site.get("meridian_id", "")) == "":
		return []
	return [site]


## The authored aim id as the resolver's `technique` argument.
##
## `BodyLocation.site_of` reads `technique.aim_meridian`, and `AttackContext` does not
## retain the `TechniqueDef` — `contracts/` cannot name one, and it keeps only
## `technique_id`. The authored meridian therefore rides `ctx.data[AIM_MERIDIAN_KEY]`,
## which is exactly what [method builder] writes and what the fixture writes, and this is
## the ONE place that hands it back to the resolver.
##
## Passing `null` here instead is what made every `named` aim miss: `_aim_id(null)` is
## `&""`, `site_of` read that as "a named aim at nothing", and returned the EMPTY_SITE —
## so a strike authored at `lung` landed nowhere, `sites[]` was empty, `channel_rank`
## reported 0, and the armour ladder the whole path is priced on never ran. `random` and
## `broad` were unaffected because neither consults the authored id, which is why the
## symptom looked like a rank bug rather than a lost aim.
func _aim_of(ctx: AttackContext) -> Variant:
	return {"aim_meridian": StringName(ctx.data_value(AIM_MERIDIAN_KEY, &""))}


## ADR 0070's `resistance`: the channel's armour PLUS the tissue weighting.
##
## `DEFENSE_PHYSICAL * MERIDIAN_ARMOUR_STEP * channel.state_rank()` for `named` /
## `random`, and the DEFENDER'S BEST channel for `broad` — the single figure the average
## over a sweep has to beat. Two properties follow and both are asserted: armour rises
## monotonically with `state_rank`, so training a channel makes it a harder place, and a
## `closed` channel is refused outright, which is the vocabulary a ratio cannot express.
func _resistance_of(ctx: AttackContext, tuning: CombatTuning, sites: Array) -> float:
	var base := maxf(0.0, _finite(ctx.target_value(Stat.DEFENSE_PHYSICAL)))
	var step := maxf(0.0, _finite(tuning.meridian_armour_step))
	var tissue := _tissue_of(ctx, tuning)
	if sites.is_empty():
		return _finite(tissue)
	var best := 0.0
	for site in sites:
		var meridian_id := StringName(site.get("meridian_id", &""))
		var value := _finite(base * step * float(int(site.get("state_rank", 0))) + tissue)
		best = maxf(best, value)
	return best


## The best `state_rank` among the struck channels, for the readout. The armour term uses
## the SAME number per site; this is the one a panel prints.
func _rank_of(sites: Array) -> int:
	var best := 0
	for site in sites:
		best = maxi(best, int(site.get("state_rank", 0)))
	return best


## `tissue_scale * (sum of each body stat x its archetype weight) / tissue_stat_divisor`.
##
## ADR 0070 is explicit that tissue is "a per-meridian WEIGHTING of the defender's
## existing `bone_density` / `muscle_fiber` / `organ_vitality`" and NOT a third location
## axis: the same three numbers, spent somewhere different. A `broad` sweep reads the
## DEFENDER'S HEAVIEST archetype, which is the single figure its average has to beat.
##
## A non-positive or non-finite divisor reads as 0.0 rather than dividing — hole 4 in the
## module docblock — and a meridian absent from `meridian_archetypes` reads no tissue and
## reports 0.0, so adding a 21st meridian without a weighting is a visible gap.
func _tissue_of(ctx: AttackContext, tuning: CombatTuning) -> float:
	var divisor := _finite(tuning.tissue_stat_divisor)
	if divisor <= 0.0:
		return 0.0
	var ids: PackedStringArray = tuning.tissue_stat_ids
	var weights: Variant = _weights_of(tuning)
	if not (weights is Array):
		return 0.0
	var row: Array = weights as Array
	if row.is_empty() or ids.is_empty():
		return 0.0
	var total := 0.0
	for index in mini(ids.size(), row.size()):
		total += _finite(ctx.target_value(StringName(ids[index]))) * _finite(float(row[index]))
	return _finite(maxf(0.0, _finite(tuning.tissue_scale) * total / divisor))


## The archetype weight row, `[bone, muscle, vitality]`, or null.
##
## The HEAVIEST archetype this defender's body is described by, not the one belonging to
## the meridian the aim happened to pick: a `broad` sweep does not aim, so it cannot know
## which channel it will cross, and pricing it at the best body it can reach is the only
## choice that does not understate a thick-skinned defender's armour. For a `named` or
## `random` strike the extra precision is spent instead where ADR 0070 puts it — the
## channel's own rank — and the tissue reads the same, which is what makes "a sweep is
## covered, not better" true rather than asserted.
func _weights_of(tuning: CombatTuning) -> Variant:
	var table: Variant = tuning.tissue_weights
	if not (table is Dictionary):
		return null
	var archetypes: Variant = tuning.meridian_archetypes
	if not (archetypes is Dictionary):
		return null
	var best_name := ""
	var best_total := -INF
	for meridian_id in (archetypes as Dictionary).keys():
		var name := String((archetypes as Dictionary)[meridian_id])
		if not (table as Dictionary).has(name):
			continue
		var row: Variant = (table as Dictionary)[name]
		var total := 0.0
		if row is Array:
			for value in row as Array:
				total += absf(_finite(float(value)))
		if total > best_total:
			best_total = total
			best_name = name
	if best_name == "":
		return null
	return (table as Dictionary)[best_name]


## The attacker's strength at this point, and the ONE place a body hit is measured. Never
## `ctx.base`: that is the technique's magnitude through the realm RATE gate (ADR 0067),
## and a body build's power is its body.
func _gross_of(ctx: AttackContext) -> float:
	return maxf(0.0, _finite(ctx.attacker_value(Stat.ATTACK_PHYSICAL)))


## The aim mode for this hit: the per-hit override on `ctx.data`, else what the authored
## id implies. An unrecognised mode reads as `random`, never as an ungated strike.
func _mode_of(ctx: AttackContext) -> StringName:
	var raw: Variant = ctx.data_value(AIM_MODE_KEY, &"")
	var mode := StringName(raw) if raw is StringName or raw is String else &""
	if mode != &"":
		return mode
	var aim: Variant = ctx.data_value(AIM_MERIDIAN_KEY, &"")
	return BodyLocation.MODE_NAMED if StringName(aim) != &"" else BodyLocation.MODE_RANDOM


## The tuning for this hit: the per-attack override, the bound one, then the shipped
## `.tres`. Memoised because it is read on every `resolve` and every `mitigate`; a null
## load falls back to a fresh `CombatTuning.new()` whose every bound is 0.0 — a visibly
## broken balance rather than a NaN (BRIEF 1.7).
func _tuning_of(ctx: AttackContext) -> CombatTuning:
	var injected: Variant = ctx.data_value(TUNING_KEY, null)
	if injected is CombatTuning:
		return injected as CombatTuning
	if tuning != null:
		return tuning
	if _shipped == null:
		_shipped = CombatTuning.shipped()
	return _shipped if _shipped != null else CombatTuning.new()


## The live object the target side was built from, when the caller handed over more than a
## `StatContext` (the spine has an `Actor`). `AttackContext` keeps it untyped precisely so
## a mechanism can read it without `contracts/` naming an `Actor`, and `_read` returns the
## honest absent case rather than a fabricated one.
static func _target_source_of(ctx: AttackContext) -> Variant:
	return _read(ctx, &"_target_source", null)


## The amount on a proposal of any shape. `get()` rather than `.amount`, so a proposal
## written against a shape this file does not have answers `0.0` instead of crashing a hit
## three stages downstream.
static func _amount_of(proposal: RefCounted) -> float:
	if proposal == null:
		return 0.0
	var value: Variant = proposal.get(&"amount")
	return _finite(float(value)) if (value is float or value is int) else 0.0


## `Object.get` with a fallback, never `Object._get` — the latter is an engine hook and a
## same-arity declaration collides with it, which fails the whole file to compile.
static func _read(value: Variant, key: StringName, fallback: Variant) -> Variant:
	if value == null or not (value is Object):
		return fallback
	var result: Variant = (value as Object).get(key)
	return result if result != null else fallback


## A rate read out of DATA and clamped into `[0, 1]`. Above 1.0 a "floor" exceeds the
## gross and a "cap" exceeds the thing it caps, and both make a defence a liability —
## holes 1 and 3 in the module docblock.
static func _share(value: Variant) -> float:
	return clampf(_finite(float(value)), 0.0, 1.0) if (value is float or value is int) else 0.0


static func _finite(value: float) -> float:
	return value if is_finite(value) else 0.0


## What a null context answers. Every key present, so a panel rendering [method
## breakdown]'s shape never has to ask whether a key exists.
static func _empty_parts() -> Dictionary:
	return {
		"mode": String(BodyLocation.MODE_RANDOM),
		"gated": false,
		"gross": 0.0,
		"defense_physical": 0.0,
		"armour_step": 0.0,
		"channel_rank": 0.0,
		"tissue": 0.0,
		"resistance": 0.0,
		"floor": 0.0,
		"penetration": 0.0,
		"refused": true,
		"sites": [],
		"subtotal": 0.0,
		"damage_reduction": 0.0,
		"mitigated": 1.0,
		"total": 0.0,
	}
