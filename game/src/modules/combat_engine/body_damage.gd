class_name BodyDamage
extends DamageMechanism

## Body damage is FLAT SUBTRACTION AT A MERIDIAN, and it can REFUSE a strike (ADR 0070).
##
## The formula, verbatim
##
## ```
## gross        = ctx.magnitude * attacker ATTACK_PHYSICAL
## meridian     = resolve_location(...)          # 20 meridians, not 60 acupoints
## point        = the acupoint within it
## channel      = target.meridians.get_meridian(meridian_id)
## D            = DEFENSE_PHYSICAL * MERIDIAN_ARMOUR_STEP * channel.state_rank()
##              + tissue_defence(meridian_id, target)          (a MAGNITUDE, ADR 0200)
## D_eff        = D * 1 / (1 + max(0, mastery_pen) / pierce_scale)
## K            = defense_divisor_k * gross      (scales with the ATTACKER)
## m            = mitigation_ceiling * D_eff / (K + D_eff)    for D_eff >= 0
## m            = mitigation_ceiling * (2 - K / (K + |D_eff|))   for D_eff < 0
## penetration  = maxf(gross * (1 - m), gross * MIN_PENETRATION_RATIO)   # 0.10
## mitigated    = penetration * point_multiplier(point) * channel_multiplier(channel)
## damage       = mitigated * (1 - DAMAGE_REDUCTION)
## ```
##
## ## ADR 0200 moved body onto the same curve, and the FLOOR is what it preserved
##
## Body was the LAST mechanism still on a flat subtraction, and ADR 0200 retires that:
## a flat subtraction against a flat defense is a constant contest, and the offense side
## rides the ladder while the defense side does not. Body now reads the same
## `mitigation_ceiling` / `defense_divisor_k` / `pierce_scale` every other mechanism does.
##
## **What changed:** `gross - defence` became `gross * (1 - m)`. The armour magnitude `D`
## is unchanged — `DEFENSE_PHYSICAL * meridian_armour_step * state_rank + tissue` is still
## read exactly once per site and is still ADR 0070's formula — but it is now the `D` of a
## ratio rather than hit points subtracted from a blow, so it SCALES WITH THE LADDER
## through the same mechanism qi and mind use.
##
## **What did NOT change, and why that is not a contradiction:** `MIN_PENETRATION_RATIO`
## stays, at `0.10`, and it is the only mechanism in the game allowed a `0.0`. The four
## reasons body refused a *pure* ratio are all still true and none of them argues against
## a floor — see the section below. ADR 0070's refusal was of a ratio with NO vocabulary
## for "this point is not defended"; ADR 0200 supplies the vocabulary as a FLOOR, which is
## a distributional claim rather than a truncation.
##
## **Penetration stopped being subtracted from the gross.** It used to read
## `maxf(gross - resistance - pen, gross * ratio)`, and ADR 0200 names that as
## dimensionally wrong: penetration is a share of a defender's ARMOUR, so taking hit
## points off a blow made a deep defender's penetration scale with how hard they were hit
## rather than with how well they were guarded. It is now a bounded reciprocal on `D`:
## `D * 1/(1 + pen/pierce_scale)`, which lies in `(0, 1]` and so can push defense
## arbitrarily close to zero and NEVER negative.
##
## ## `ctx.magnitude` is IN the gross, and it was missing
##
## ADR 0070's prose writes `gross = attacker ATTACK_PHYSICAL`, which was what shipped, and
## that line was WRONG — not in taste, in arithmetic. `AttackContext.magnitude` is S1's
## OUTPUT (ADR 0067): the technique's authored magnitude through the realm rate gate. It is
## the one term `QiDamage` multiplies EVERY one of its shares by, and it is the only thing
## that connects a technique's authored numbers to the damage the player sees; body read
## none of it. Two consequences, both measured:
##
## - The unit of damage is `technique magnitude x attack stat` for every mechanism that
##   touches health, and body alone priced a hit in bare attack-stat points. A body
##   technique at `magnitude 100` was worth the same as one authored at `1`.
## - `QiDamage` takes the realm power TWICE — once through `RealmScaling`'s MULT on
##   `ATTACK_SPIRITUAL`, once through `ElementsApi`'s MULT on `element_power_<e>` — while
##   body took it once, on a fixture build of `20.0` that a real actor's authored physique
##   would put an order of magnitude above. `test_cross_mechanism_balance.gd` measured that
##   asymmetry at 363x at R1 widening to 590x at R30: a gap that GROWS WITH THE LADDER,
##   which is the signature of two mechanisms scaling against different powers rather than
##   a tuning difference.
##
## Restored here rather than by dividing qi down, for the reason the shape of the fix is a
## product and not a correction factor: the missing TERM is the defect. No constant was
## invented and `combat_damage.tres` is untouched.
##
## and for `broad`, once per unlocked meridian, summed at `BROAD_MULT` — ADR 0070's "hits
## every unlocked meridian at `BROAD_MULT`", implemented as one sum rather than twenty
## proposals so a single strike is still one packet and one effect.
##
## ## A ratio WITH a floor, and the four reasons ADR 0070 gave for refusing one WITHOUT
##
## (1) A ratio never reaches zero, so it has no vocabulary for "this point is not
## defended" — and refusing a strike outright is this path's whole premise. (2) Body's
## premise is the INVERSE of qi's: `ElementRules.NOURISH = 0.75` means qi always lands
## something, and only this mechanism is allowed a `0.0`. (3) Dimensional: under a ratio
## `defense` is un-authorable — doubling it moves the result by less than doubling, so no
## designer can read it off the data. (4) A flat number IS a hit-point value, which is the
## only form a balance table can be reviewed in.
##
## ### What ADR 0200 did to these four, stated rather than quietly overwritten
##
## **All four still hold, and three of them now argue for a different thing.** ADR 0200
## landed a ratio here, so the honest reading is that reasons (1) and (2) were refusals of
## a ratio WITHOUT A FLOOR rather than of ratios as such: a ratio with
## `MIN_PENETRATION_RATIO` under it has exactly the vocabulary reason (1) asks for, and it
## still leaves body the one mechanism permitted a `0.0`, which is reason (2). Reason (3)
## is the one ADR 0200 CONTRADICTS on its own terms, and this file says so plainly: under
## `m = mitigation_ceiling * D/(K+D)` doubling `DEFENSE_PHYSICAL` does move the result by
## LESS than doubling. The mitigation is now a share rather than a hit-point value, so a
## balance table reviews `D` and `K` rather than a subtraction. That is a real cost and
## reason (4) is genuinely weaker here than it was — it is the price ADR 0200 pays for
## mitigation growing WITH the ladder instead of being authored flat against it. Reason (3)
## is also why [method breakdown] now publishes `defense`, `defense_effective`,
## `divisor_k` and `mitigation_rate` as four separate terms: an unauthorable SUM is not a
## reason to publish no TERMS.
##
## ## `MIN_PENETRATION_RATIO` is load-bearing, and this is where it is proved
##
## Without the floor, a defender with enough `DEFENSE_PHYSICAL` and tissue drives `m`
## toward `mitigation_ceiling`, drives `gross * (1 - m)` toward zero, has the location
## multiplier multiply nearly nothing, and deletes the entire mechanic with a stat they
## already had. It is the one piece of ADR 0070 that survives the ratio intact, and the
## suite asserts it twice: against armour that REFUSES, and against armour that saturates
## the mitigation without ever reaching it.
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
	# `ctx.magnitude` is S1's OUTPUT (ADR 0067): the technique's authored magnitude through
	# the realm RATE gate, and the ONE term `QiDamage` multiplies every one of its shares
	# by. Dropping it is what left body paying the realm's `RealmDef.power` in full on a
	# FIXTURE build of `20.0` while qi's real actor paid it twice — on its attack stat
	# AND on a magnitude that never went through the realm MULT at all — which measured
	# as a 363x -> 590x gap that widened with the ladder instead of the flat 100x two
	# mechanisms reading two different stat magnitudes would show. The unit of damage is
	# `technique magnitude x attack stat`, not "the attack stat on its own"; see the
	# module docblock.
	var magnitude := maxf(0.0, _finite(ctx.magnitude))
	var gross := magnitude * maxf(0.0, _finite(ctx.attacker_value(Stat.ATTACK_PHYSICAL)))
	var tissue := _tissue_of(ctx, tuning)
	var sites := _sites_of(ctx, tuning)
	# ONE defense figure for the whole hit: `D` is a single sum, and a `broad` sweep
	# whose twenty sites each computed their own mitigation would be a different formula
	# from the ADR's rather than the ADR's formula applied twenty times.
	# `tissue` is READ for the readout row below and is ALREADY inside `_resistance_of`'s
	# per-site sum (`base * step * rank + tissue`), which is ADR 0070's formula with each
	# term counted once. Adding it to that result as well — as this line used to — priced
	# every defender's tissue defence twice, silently inflating every body's armour and
	# making body the strongest of the three mechanisms to defend against for no design
	# reason. The README of this lane is the formula at the top of this file, not this line.
	var armour := _finite(_resistance_of(ctx, tuning, sites))
	# ADR 0200: `K = defense_divisor_k * gross`, which scales with the ATTACKER, and
	# penetration is a bounded reciprocal ON THE ARMOUR rather than hit points off the
	# blow. Both are read before the floor, because the floor is applied to the RESULT and
	# a floor taken against an intermediate would be a second, different constant.
	var penetration_of_attacker := _penetration_of(ctx)
	var defense_effective := _pierced_defense(armour, penetration_of_attacker, tuning)
	var divisor_k := maxf(0.0, _finite(tuning.defense_divisor_k) * gross)
	var mitigation_rate := _mitigation_of(defense_effective, divisor_k, tuning)
	var floor := maxf(0.0, gross * _share(tuning.min_penetration_ratio))
	var penetration := _finite(maxf(gross * (1.0 - mitigation_rate), floor))
	# `MIN_PENETRATION_RATIO` applied ONCE, so the floor is a share of the GROSS and never
	# grows with the strike. Applying it per site — as a `broad` sum of twenty floors —
	# would make an area technique's floor twenty times a single hit's at no extra price,
	# which is the opposite of what "a sweep is coverage" means.
	#
	# `struck` IS `penetration` and is kept as a separate name because three suites read
	# `parts["penetration"]` as the figure the location multipliers act on, and a rename
	# would have them asserting against a key that no longer means "what the armour left".
	# The second `maxf` this used to carry was the floor applied TWICE — the floor is
	# already taken on the line above, so the outer one could never bind and only hid
	# which of the two terms was actually deciding the answer.
	var struck := penetration
	# A body with no location axis has no SITE to carry a multiplier, and the location
	# multiplier is where ADR 0070's entire location axis lives — a subtraction that
	# produced nothing at all because the target has no meridians would delete the hit
	# against every NPC and training dummy in the game, and the module docblock states
	# the opposite: such a body is UNGATED, which is the flat subtraction "with no armour
	# at all", not "with no damage". An empty site list therefore pays out the STRUCK
	# figure once, at the neutral `1.0` — the same number a strike at a meridian with no
	# huyệt on the actor already pays (`BodyLocation._site_in` falls back to `1.0` and
	# reports `locked`), so "no location axis" and "no weak point" price identically.
	# One packet, one effect list: the loop below contributes no row for a body that has
	# no meridian to name.
	var untargeted := sites.is_empty()
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
	if untargeted:
		subtotal = struck
	subtotal = maxf(0.0, _finite(subtotal))
	var reduction := clampf(_finite(ctx.target_value(Stat.DAMAGE_REDUCTION)), 0.0, 1.0)
	var cap := clampf(_finite(tuning.damage_reduction_cap), 0.0, 1.0)
	var mitigated := clampf(1.0 - minf(reduction, cap), 0.0, 1.0)
	return {
		"mode": BodyLocation.mode_name(_mode_of(ctx)),
		"gated": not sites.is_empty(),
		"magnitude": magnitude,
		"gross": gross,
		"defense_physical": maxf(0.0, _finite(ctx.target_value(Stat.DEFENSE_PHYSICAL))),
		"armour_step": maxf(0.0, _finite(tuning.meridian_armour_step)),
		"channel_rank": float(_rank_of(sites)),
		"tissue": tissue,
		# `resistance` is KEPT as a key name because three suites and the cross-mechanism
		# readout assert on it, but it is no longer a subtracted quantity: it is `D`, the
		# armour MAGNITUDE ADR 0200's ratio is built from. The three new keys beside it are
		# what the ratio added, and publishing them is what keeps ADR 0070's reason (3)
		# — "defense is un-authorable under a ratio" — honest rather than merely ignored.
		"resistance": armour,
		"defense_effective": defense_effective,
		"divisor_k": divisor_k,
		"mitigation_rate": mitigation_rate,
		"floor": floor,
		"penetration": struck,
		# Whether the STRIKE was refused, not whether the penetration figure is positive.
		# A penetration the floor keeps above zero produces no damage at all when every
		# site's multiplier is `0.0` — a `BROAD_MULT` of `0.0`, or a body whose channels
		# all answer a neutral `0.0` — and the one refusal ADR 0070 allows body is the
		# mechanism accepting that, not the mechanism minting a `1.0` penetration and
		# calling the strike survived. `subtotal` is the figure that decides it, and it is
		# the figure S4 hands the spine.
		"refused": subtotal <= 0.0,
		"sites": rows,
		"subtotal": subtotal,
		"damage_reduction": minf(reduction, cap),
		"mitigated": mitigated,
		"total": maxf(0.0, subtotal * mitigated),
	}


## A `ctx_builder` for `CombatSpine.resolve_hit`: carries this mechanism's inputs through
## the ONE context, so the spine needs no sixth stage and no knowledge of what a body hit
## is (ADR 0067).
##
## ```
## CombatSpine.resolve_hit(attacker, target, technique, tuning, rng,
##     BodyDamage.builder(technique, BodyLocation.MODE_NAMED))
## ```
##
## ## There is deliberately NO ledger parameter, and it was DELETED (ADR 0195)
##
## This used to take a `p_wounds` and write it to `ctx.data[WOUNDS_KEY]`, on the stated
## reason that "the wound layer rides `ctx.data`". **Nothing ever read that key.**
## `breakdown` reads `AIM_MERIDIAN_KEY` / `AIM_MODE_KEY` / `TUNING_KEY` and never it,
## production passed `null` (`combat_boot.gd` has always called this with `null`), and
## wounds settle by a different and correct route: `CombatEffectApply._wound` reads
## `CombatEngineApi.wounds_of(target)` off the `body_wounds` COMPONENT. So the channel
## was a second, unwritten, unread path to state that is already bound on the actor —
## a live trap rather than a dormant one, because a caller who passed a ledger would see
## it silently ignored and could conclude the applier had a bug.
##
## Deletion over wiring, deliberately: there is nothing to wire TO. Wounds are component
## state (ADR 0140) and `Actor._wounds_dict` serialises them, so a context channel could
## only ever disagree with the thing a save carries. A caller that wants to settle a
## proposal uses [method apply_wounds], which reads the bound ledger by construction.
static func builder(
	p_technique: Variant = null, p_mode: StringName = &"", p_tuning: Variant = null
) -> Callable:
	return func(ctx: AttackContext) -> AttackContext:
		if ctx == null:
			return ctx
		if p_technique is Object:
			ctx.set_data(AIM_MERIDIAN_KEY, (p_technique as Object).get(&"aim_meridian"))
		if p_mode != &"":
			ctx.set_data(AIM_MODE_KEY, p_mode)
		if p_tuning is CombatTuning:
			ctx.set_data(TUNING_KEY, p_tuning)
		return ctx


## One wound's result, applied to `target`. The route a caller uses to settle a
## `DamageProposal`'s `effects[]` AFTER health (ADR 0067), which is the only ordering under
## which a wound may land: `contracts/location_resolver.gd`'s own `apply_wound` writes
## nothing on purpose, for exactly this reason.
##
## It settles onto the ledger BOUND on `target`, and that is the whole fix. This function
## built a `BodyWounds.new()` per call, so every wound it wrote landed on a fresh ledger
## that was then dropped: the accumulating ledger ADR 0070 is named for could never
## accumulate at all, and two calls could not disagree about what the target carried because
## neither could see the other. Wounds now live where `CombatEngineApi.wounds_of` says they
## live, which is the same component key `Actor._wounds_dict` serialises.
##
## A target with NO ledger bound is a supported state, not a failure, and it writes nothing
## rather than quietly growing one nobody can save: `CombatBoot.bind_mechanisms` binds the
## ledger, and a save that deliberately carries no wounds slot restores none.
func apply_wounds(
	target: Variant, proposal: DamageProposal, tuning: CombatTuning
) -> Array[Dictionary]:
	if target == null or proposal == null:
		return []
	var ledger := CombatEngineApi.wounds_of(target as Actor)
	if ledger == null:
		return []
	return ledger.apply_all(target, proposal.effects, tuning)


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


## ADR 0070's armour: the channel's armour PLUS the tissue weighting, now named `D` --
## the MAGNITUDE ADR 0200's ratio is built from.
##
## `DEFENSE_PHYSICAL * MERIDIAN_ARMOUR_STEP * channel.state_rank()` for `named` /
## `random`, and the DEFENDER'S BEST channel for `broad` -- the single figure the average
## over a sweep has to beat. Two properties follow and both are asserted: armour rises
## monotonically with `state_rank`, so training a channel makes it a harder place, and a
## `closed` channel is refused outright, which is the vocabulary the ratio cannot express
## on its own and which [method mitigation_of]'s curve plus `MIN_PENETRATION_RATIO`
## together supply.
##
## ## Why it returns a NEGATIVE-capable figure
##
## The SIGN is preserved rather than clamped at zero, because a defence DEBUFF is the
## case ADR 0200 names: `D < 0` must reach [method mitigation_of]'s mirror branch or the
## glass cannon silently exceeds its own ceiling. `DEFENSE_PHYSICAL` itself is read
## `maxf(0.0, ...)` because core derives it that way, so only a DEBUFF modifier can make
## the sum negative -- which is exactly the intended author.
func _resistance_of(ctx: AttackContext, tuning: CombatTuning, sites: Array) -> float:
	var base := maxf(0.0, _finite(ctx.target_value(Stat.DEFENSE_PHYSICAL)))
	var step := maxf(0.0, _finite(tuning.meridian_armour_step))
	var tissue := _tissue_of(ctx, tuning)
	if sites.is_empty():
		return _finite(tissue)
	var best := -INF
	for site in sites:
		var meridian_id := StringName(site.get("meridian_id", &""))
		var value := _finite(base * step * float(int(site.get("state_rank", 0))) + tissue)
		best = maxf(best, value)
	return _finite(best)


## The attacker's penetration against this body's armour, ANSWERED by the
## defender's `ABSORPTION`, as a magnitude on `CombatTuning.pierce_scale`'s
## scale. Zero when nothing was authored and never negative: a negative
## penetration would be a defence BONUS wearing an attacker's name, and the
## answered form keeps that property through `CombatStats.pierce`.
func _penetration_of(ctx: AttackContext) -> float:
	var id := CombatStats.PENETRATION
	return CombatStats.pierce(
		maxf(0.0, CombatStats.default_of(id) + _finite(ctx.attacker_value(id))),
		maxf(
			0.0,
			(
				CombatStats.default_of(CombatStats.ABSORPTION)
				+ _finite(ctx.target_value(CombatStats.ABSORPTION))
			)
		)
	)


## ADR 0200's bounded reciprocal ON THE ARMOUR: `D_eff = D / (1 + max(0, pen) /
## pierce_scale)`.
##
## ## Why the old subtraction off the gross was wrong, and is gone
##
## `body_damage.gd` used to subtract penetration from the GROSS. ADR 0200 names that as
## dimensionally wrong and the arithmetic agrees: penetration is a share of a defender's
## ARMOUR, so taking hit points off a blow made a deep defender's penetration scale with
## how hard they were hit rather than with how well they were guarded -- two defenders
## with identical armour answered a light blow and a heavy one differently. Here it
## scales the ARMOUR, which is the quantity it names.
##
## ## Bounded, which is the property the subtraction never had
##
## The reciprocal lies in `(0, 1]`, so `D_eff` keeps `D`'s sign and shrinks toward zero
## WITHOUT crossing it. The old form could subtract straight past a defended point into a
## free one; this one can push armour arbitrarily close to zero and never negative.
##
## A non-positive or non-finite `pierce_scale` reads as "penetration does nothing", never
## as a division.
static func _pierced_defense(armour: float, penetration: float, tuning: CombatTuning) -> float:
	var scale := _finite(tuning.pierce_scale)
	if scale <= 0.0:
		return armour
	var pen := maxf(0.0, _finite(penetration))
	return _finite(armour / (1.0 + pen / scale))


## ADR 0200's mitigation curve, the same shape `QiDamage` and `MindDamage` use:
##
## ```
## m = mitigation_ceiling * D / (K + D)                 for D >= 0
## m = mitigation_ceiling * (2 - K / (K + |D|))        for D <  0
## ```
##
## Here `K = defense_divisor_k * gross`, and the OWNER'S RULING is that `K` is PER
## MECHANISM: body authors its own so the three mechanisms stay independent and a qi
## rebalance cannot move a body's answer.
##
## `m` APPROACHES `mitigation_ceiling` and never reaches it, so every further point of
## armour still pays -- the property `MIN_PENETRATION_RATIO` then sits UNDER as a floor,
## which is the whole of ADR 0200's answer to ADR 0070's first objection: the ratio has
## no vocabulary for "this point is not defended", and the floor supplies it.
##
## The mirror branch is what makes a glass cannon real: a body under a defence debuff
## takes `gross * (1 - m)` with `m` ABOVE the ceiling, so it deals strictly MORE than an
## undefended body. Both branches give exactly `mitigation_ceiling` at `D == 0`, so the
## function is CONTINUOUS there.
static func _mitigation_of(armour: float, divisor_k: float, tuning: CombatTuning) -> float:
	var ceiling := clampf(_finite(tuning.mitigation_ceiling), 0.0, 1.0)
	if ceiling <= 0.0:
		return 0.0
	var k := maxf(0.0, _finite(divisor_k))
	var magnitude := absf(_finite(armour))
	var denominator := k + magnitude
	if denominator <= 0.0:
		return 0.0
	var share := magnitude / denominator if armour >= 0.0 else 2.0 - k / denominator
	return _finite(ceiling * share)


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
		"magnitude": 0.0,
		"gross": 0.0,
		"defense_physical": 0.0,
		"armour_step": 0.0,
		"channel_rank": 0.0,
		"tissue": 0.0,
		"resistance": 0.0,
		"defense_effective": 0.0,
		"divisor_k": 0.0,
		"mitigation_rate": 0.0,
		"floor": 0.0,
		"penetration": 0.0,
		"refused": true,
		"sites": [],
		"subtotal": 0.0,
		"damage_reduction": 0.0,
		"mitigated": 1.0,
		"total": 0.0,
	}
