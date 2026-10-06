class_name CombatSpine
extends RefCounted

## The one damage pipeline every hit passes through (ADR 0067). Eleven stages, in
## order, unchangeable without an ADR. Nine are SHARED; S4 and S5 are the seam. ADR
## 0067's `effects[]` step follows them, in `CombatEffectApply`, and is not a numbered
## stage: it is the path's own state writes, applied after health.
##
## ## The four load-bearing orderings
##
## - **S1 before S2.** The realm ladder scales MAGNITUDE only. Were it to move
##   `p_hit`, it would be an invisible second dial on `Stat.EVASION` — a stat nobody
##   can see, audit or build against.
## - **S2 before S4.** A miss never invokes a mechanism. Assertable for all three, and
##   the reason a cheap AI can decline to compute a hit it will not take.
## - **S4 before S6.** Crit multiplies what the mechanism produced; it is never an
##   INPUT to it. That is what stops the three mechanisms from disagreeing about a
##   shared stat — they never see one.
## - **S7 before S8, and S8 before S9.** Reduction runs, THEN the floor restores the
##   chip. Reverse these and enough flat `DAMAGE_REDUCTION` (ADR 0022) returns zero
##   from a landed crit. This pair IS the immunity invariant.
##
## ## There is no `if/else on path_id` here, and that is the point
##
## Nothing in this file knows what a qi, a body or a mind hit is. The seam is
## `mechanism.resolve(ctx)` then `mechanism.mitigate(ctx, proposal)`; swapping the
## stub for qi is one `app/` line and zero combat edits. That is a property of THIS
## file, so it is a test: `tests/modules/combat_engine/test_combat_mechanism_seam.gd`
## drives
## three stub mechanisms with three distinct returns through the identical code.
##
## ## Numerics
##
## Float end to end, NEVER rounded: rounding is the one operation whose result depends
## on how stages are grouped, and one `roundf()` would destroy every "order doesn't
## matter except where I say" test. No division except by an authored positive
## constant. The result is non-negative, and the sign is flipped in EXACTLY one place —
## S9's `change_resource(&"health", -overflow)`. One `is_finite` guard, at S6's
## entrance, because `maxf(NaN, chip) == NaN` and `ResourcePool.change` has no guard
## of its own.
##
## ## `ctx` is read by field name, and that is deliberate
##
## `AttackContext` is built by [method _context], here. Its declared fields are
## `attacker`, `target`, `technique` and `tuning`; the spine then sets `base`,
## `magnitude`, `rolled` and `crit` on it, because those four are the spine's to
## publish and a mechanism must be able to read S1's OUTPUT rather than the technique's
## raw magnitude. That is what makes "S1 before S2" and "S4 before S6" testable: a
## mechanism reading `ctx.base` cannot see a pre-gate value, and reading `ctx.crit`
## rather than rolling its own means three mechanisms cannot disagree about when crit
## counts.
##
## `ctx_builder` is the extension point that carries anything else — an element rule
## table, a location resolver — through the seam without a sixth stage. It receives the
## built context and returns it; returning the argument unchanged is the default.

## What a parry refunds at NEUTRAL investment: the share of the landed amount that
## reaches the defender's health before [method _refusal] moves it by the response's own
## `strength`/`shred` pair (ADR 0878). A parry is a DEFENSIVE RESPONSE to a blow, not an
## exemption from it — and because S8's chip floor runs before S9, a refusal can never
## refuse every hit. This is the only vocabulary combat needs to express a parry, and it
## needs no extra stage and no second `mitigate` call.
const PARRY_COST := 0.5
## Block's twin of `PARRY_COST`: a block is the cheaper, weaker response.
const BLOCK_COST := 0.75

## The component key S9 reads a shield through. Duck-typed on purpose: `shield.gd` was
## deleted by ADR 0076 and is wave E's to write, so naming `Shield` here would make the
## spine uncompilable until a later wave lands — and the spine is testable NOW, which is
## the point of building it first. The contract is stated rather than typed: a component
## under this key whose `absorb(amount: float) -> float` returns the overflow it did NOT
## take. A real `Shield` binds with no edit here, and anything else in that slot absorbs
## nothing rather than crashing the hit.
const SHIELD_COMPONENT := &"Shield"


## Resolve one hit and apply it. The only mutating function in the spine: S9 spends
## health, S10 spends it again on the other side, S11 heals.
##
## `rng` may be null, in which case nothing random happens and every attack lands —
## the shape the rest of the repo already uses (`CombatDamage.resolve_hit`,
## `LootState`). A caller that wants reproducibility injects one (ADR 0067).
##
## `tuning` and `ctx_builder` are INJECTED rather than defaulted to a loaded constant:
## the spine is static so it can be called with no scene tree, and a `load()` inside a
## stage would make the stages depend on the resource filesystem instead of on their own
## arguments. `CombatApi.resolve_hit` supplies both from `combat_damage.tres`.
##
## ## S12 is HERE again, and the only thing that changed is the PRODUCER
##
## ADR 0087 made status application a twelfth stage of this spine. ADR 0105 superseded
## that PLACEMENT — "S12 is retired as the application site, not re-routed; the spine is
## not built to reach it" — and its DEF-0145 amendment therefore deleted the call, on a
## measured ground rather than a taste one: `StatusApply.apply` reads its authored request
## off `ctx.data` under `StatusApply.REQUEST_KEY`, no shipped `ctx_builder` wrote that key,
## and every landed blow through this spine answered `REFUSE_NO_REQUEST`. ADR 0105 called
## that stage DEAD rather than merely idle.
##
## **Both halves of that argument have moved, and the stage comes back with them.** The
## spine DID ship and the player-facing blow DID start resolving through it —
## [method CombatBoot.duel_blow] installs this spine as the attack resolver — so the
## premise "the spine is not built to reach it" is no longer true of the shipped game.
## And the producer the measurement complained about now exists in production:
## `CombatBoot.ctx_builder_for` composes ADR 0105's element→status request over whichever
## mechanism builder won (`combat_boot.gd:_with_status_request`), reading the SAME
## authored catalogue the status module itself reads through
## `StatusApi.status_for_element` / `StatusDef.on_landed_blow`. ADR 0105's SHAPE is
## followed exactly — the carrier is the ELEMENT, `TechniqueDef` gains no status field, and
## there is one gate rather than two.
##
## A producer that did not exist would make this stage dead again, and dead is what it was:
## it costs a refused dictionary on every landed blow to say "no". That is why the producer
## has its own test asserting the key is written by a SHIPPED `ctx_builder`
## (`tests/modules/combat_engine/test_status_producer.gd`) rather than by a test that writes
## the request itself and therefore proves nothing.
##
## ADR 0105's second half stands unchanged: it retired the BOSS exchange as an application
## site, and `CombatExchange.exchange` keeps its own single call. Nothing below touches
## that path, and the arithmetic S12 needs (`elemental_resist`, `apply_chance`, `potency_of`,
## `status_seed`) is still `StatusApply`'s alone — ADR 0105 said "superseded, not its
## arithmetic", and this is the spine reading that arithmetic rather than restating it.
static func resolve_hit(
	attacker: Actor,
	target: Actor,
	technique: TechniqueDef,
	tuning: CombatTuning,
	rng: Variant = null,
	ctx_builder: Callable = Callable(),
	chain_depth: int = 0,
	hit_index: int = 0
) -> CombatOutcome:
	var outcome := CombatOutcome.new()
	outcome.base = base_damage(attacker, technique)
	outcome.missed = true
	if attacker == null or target == null or technique == null:
		return outcome
	# Read AFTER S1 and BEFORE the roll, so an unbound actor fails loudly HERE rather
	# than silently producing a zero three stages downstream — and so `outcome.base`
	# is still observable for an unbound attacker.
	var mechanism := MechanismSlot.of(attacker)
	# --- S2: one draw, three bands. Nothing below this line runs for a miss. ---
	var band := CombatBand.roll(
		tuning,
		landed_chance(attacker, target, tuning),
		_parry(attacker, target, tuning),
		_block(attacker, target, tuning),
		rng
	)
	outcome.missed = band.missed
	outcome.parried = band.parried
	outcome.blocked = band.blocked
	if band.missed:
		return outcome
	# --- S3: a SECOND draw, clean hits only. A parried or blocked hit never crits. ---
	var crit := band.is_clean() and _crit(attacker, target, tuning, rng)
	outcome.crit = crit
	# --- S4 / S5: the seam. Two virtuals, one shape, three implementations. ---
	var ctx := _context(ctx_builder, attacker, target, technique, tuning, outcome.base, true, crit)
	var proposal := mechanism.resolve(ctx)
	if proposal == null:
		proposal = mechanism.mitigate(ctx, DamageProposal.shared)
	else:
		proposal = mechanism.mitigate(ctx, proposal)
	outcome.proposal = proposal
	# --- S6: crit multiplies the mechanism's output, once. The ONE non-finite guard. ---
	var amount := CombatProposalReader.amount_of(proposal)
	if not is_finite(amount):
		amount = 0.0
	if crit:
		amount *= _crit_damage(attacker, target, tuning)
	outcome.amount = maxf(0.0, amount)
	# --- S7: one mitigation shape for all three paths, linear and floored at zero. ---
	outcome.amount = maxf(
		0.0, outcome.amount * amp_factor(_delta(attacker, target, tuning), tuning)
	)
	# --- S8: the immunity invariant. AFTER S7, or enough reduction erases a crit. ---
	outcome.amount = maxf(outcome.amount, chip_floor(outcome.base, tuning))
	_spend(attacker, target, tuning, outcome, chain_depth)
	# --- ADR 0067's `effects[]` step, LAST of all: after health (S9), after reflect
	# (S10) and after leech (S11). Every mechanism computes its own state writes and
	# NOTHING applied them, so a body hit left no wound and a mind erosion was discarded
	# -- see `effect_apply.gd`. Kept here rather than inside `_spend` so the "effects land
	# after the HP write" ordering is asserted at the ONE call site that decides it.
	CombatEffectApply.apply(target, CombatProposalReader.effects_of(proposal), tuning)
	# --- S12: status application, LAST (ADR 0087). After health (S9), after reflect
	# (S10), after leech (S11) and after the paths' own `effects[]`, so a defender who
	# died of the blow is not burned by it and a leeched hit still applies its status.
	# `StatusApply.apply` gates on `is_clean()` first, so a MISSED / PARRIED / BLOCKED
	# blow spends nothing here and never reads `ctx.data` at all.
	#
	# `ctx` is the context S4 already built — the SAME object the mechanism resolved
	# against — so the producer's request is read for free. ADR 0087's original cost was
	# a second context rebuild per hit, and that rebuild was the reason DEF-0145 could
	# call the stage dead without anyone noticing what else it was paying.
	StatusApply.record(
		outcome,
		StatusApply.apply(attacker, target, tuning, ctx, outcome, rng, technique, hit_index)
	)
	return outcome


## S1 alone: the authored magnitude through the technique ladder gate.
## `TechniqueMagnitudeTable` is the technique's OWNING per-realm table, keyed by realm id
## (ADR 0055, ADR 0182), and it is read here rather than computed from a realm ordinal.
##
## ## Why the rate that used to stand here is gone
##
## This read `RealmRate.factor(attacker.realm())` -- the TRAINING rate, `1.02^ordinal`,
## a bounded rate of a different quantity. A rate may gate a magnitude but is never one
## (ADR 0182), so the technique ladder ADR 0055 approved was priced at nothing: a deep
## technique reached 1.7758x at R30 instead of 2.7667x. It is replaced, not multiplied in,
## because `RealmRate` was standing in for the ladder rather than adding to it, and the two
## together would count one realm's progress twice.
##
## `TechniqueReadModel` prices `magnitude_now` from the SAME call, so what a panel shows and
## what this builds from cannot be two different ladders. Exposed on its own so S1 is a
## two-line test rather than a debate, and so a caller quoting a number quotes the
## ladder-gated one.
static func base_damage(attacker: Actor, technique: TechniqueDef) -> float:
	if technique == null:
		return 0.0
	var base := technique.magnitude
	if attacker != null:
		base *= TechniqueMagnitudeTable.factor(attacker.realm())
	return maxf(0.0, base)


## S8 alone: the chip floor, `maxf(amount, maxf(min_chip_abs, base * min_chip_share))`.
## Reads its bound from `CombatTuning` so a rebalance is a `.tres` edit and a test
## reads the shipped number instead of restating it.
static func chip_floor(base: float, tuning: CombatTuning) -> float:
	return maxf(tuning.min_chip_abs, base * tuning.min_chip_share)


## S7's mitigation shape: `maxf(0.0, 1 + delta / amp_scale)` -- ONE LINEAR FACTOR, floored
## at zero (ADR 0067).
##
## ```
## delta >= 0 -> 1 + delta / amp_scale      (attacker amplification: linear, unbounded)
## delta <  0 -> maxf(0.0, 1 + delta / amp_scale)
## ```
##
## ## Why LINEAR and not a reciprocal, which is the correction
##
## ADR 0067 requires two things of this stage and only one shape satisfies both:
##
## 1. "S7 can drive `amount` to `0.0`, S8 restores it" -- the stated REASON S8 exists.
##    A reciprocal `1 / (1 - delta / amp_scale)` puts its asymptote at POSITIVE
##    `delta`, so on the negative branch it cannot reach zero at any reachable `delta`:
##    at `delta == -amp_scale` it still reads `0.5`, and it only approaches zero as
##    `delta` goes to `-infinity`. With `_scaled_core_reduction` clamping core's flat
##    `DAMAGE_REDUCTION` to `amp_scale`, "S7 can drive the amount to 0.0" was
##    UNREACHABLE, S8's floor was decorative, and the immunity invariant only held
##    because of that clamp -- a workaround for the shape, standing in for the property.
## 2. "Deliberately NOT ported: `AmpFactor` / `AmpFactorReciprocal`. None is re-added
##    without an ADR." The reciprocal this file shipped WAS the refused Keepverse one.
##
## A linear factor floored at zero reaches zero exactly at `delta == -amp_scale`, is
## monotone (more reduction always hurts the attacker, never helps), and never divides
## by anything computed -- `amp_scale` is an authored positive constant. It is also the
## shape four separate suites already described in prose: `9.0` on `amp_scale = 10.0`
## "takes the factor to 0.1, which turns 40.0 into 4.0".
##
## The positive branch is deliberately unbounded. That is the authored price of stacking
## amplification, and a ceiling on it would be ADR 0050's ban on progression ceilings.
##
## No rounding, no permille, no integer narrowing, and no per-mille cap constant -- ADR
## 0067 refuses all three for the same reason it refuses the reciprocal.
static func amp_factor(delta: float, tuning: CombatTuning) -> float:
	var scale := tuning.amp_scale
	if not (scale > 0.0):
		# No scale means no contest, so the factor is the identity -- the same total
		# reading `CombatBand.rate` gives a null tuning, and the same reason: a caller
		# that supplied no `amp_scale` has not chosen a number and must not get a NaN
		# out of `0.0 / 0.0`, which `maxf` would pass straight through to S8.
		return 1.0
	return maxf(0.0, 1.0 + delta / scale)


# --- S9 / S10 / S11, in order -------------------------------------------------


## S9 -> S10 -> S11. Split out only because it is the tail: the three stages that
## MUTATE, as opposed to the eight that compute. The ORDER of the three is asserted
## here at the one place it is decided — reflect is called before leech, both after the
## single health write.
static func _spend(
	attacker: Actor, target: Actor, tuning: CombatTuning, outcome: CombatOutcome, chain_depth: int
) -> CombatOutcome:
	var spendable := outcome.amount * _refusal(attacker, target, tuning, outcome)
	outcome.absorbed = _absorb(target, spendable)
	outcome.overflow = maxf(0.0, spendable - outcome.absorbed)
	var health := target.resource(&"health") as ResourcePool
	if health != null and outcome.overflow > 0.0:
		# THE ONE SIGN FLIP IN THE SPINE. Everything above is non-negative and
		# everything below reads `health_delta`, so a caller cannot find a second
		# negation that disagrees with this one.
		var before := health.current
		health.change(-outcome.overflow)
		outcome.health_delta = health.current - before
	# --- S10, post-shield and never folded into the amount above. ---
	CombatRecoil.reflect(attacker, target, tuning, outcome, chain_depth)
	# --- S11, a separate packet after the HP write, never folded into it either. ---
	CombatRecoil.leech(attacker, tuning, outcome)
	return outcome


## S9's shield gate: what the shield REMOVED from `spendable`, so `overflow` is the
## remainder that reached health.
##
## ## Why this translates, instead of returning the shield's own number
##
## `Shield.absorb(amount) -> overflow` answers what it did NOT take, but this function's
## answer has to mean "the removed share", because `CombatOutcome.absorbed` documents THAT
## and because an absent shield must be the same shape as a shield that took nothing.
## Returning the shield's return value directly made ONE number carry TWO opposite meanings
## depending on whether a component was bound: `0.0` meant "no shield" and "the shield took
## it all" at the same time, so NO arrangement of the two assignments in `_spend` could be
## right for both cases. Swapping them fixed every shielded case and broke every unshielded
## one; subtracting once, HERE, is what makes the absent case read `0.0` for the only reason
## it should. That ambiguity was DEF-0139.
##
## The subtraction is clamped into `[0, spendable]`, so a hostile or buggy `absorb` that
## returns more than it was handed cannot hand S9 an `absorbed` larger than the blow, which
## would drive `overflow` negative and spend the refund as a heal through the one sign flip
## in `_spend`.
##
## The component is duck-typed on purpose. `shield.gd` was deleted by ADR 0076 and is
## wave E's to write, so naming `Shield` here would make the spine uncompilable until a
## later wave lands — and the spine is testable NOW, which is the point of building it
## first. The contract is therefore stated rather than typed: a component under
## `SHIELD_COMPONENT` whose `absorb(amount: float) -> float` returns the overflow it
## did NOT take. A real `Shield` binds to this with no edit here, and anything else in
## that slot absorbs nothing rather than crashing the hit.
static func _absorb(target: Actor, spendable: float) -> float:
	var shield := target.component(SHIELD_COMPONENT)
	if shield == null or spendable <= 0.0:
		return 0.0
	if not shield.has_method(&"absorb"):
		return 0.0
	var overflow: Variant = shield.call(&"absorb", spendable)
	if not (overflow is float or overflow is int):
		return 0.0
	return clampf(spendable - float(overflow), 0.0, spendable)


## S2's aftermath on the amount: a parry keeps `PARRY_COST`, a block keeps `BLOCK_COST`,
## a clean hit keeps all of it. A miss never reaches this.
##
## ## The removal is a PAIR (ADR 0878): the defender's `strength` raises what the
## ## response removes and the attacker's `shred` lowers it, as a flat delta over
## ## `rate_scale` — ADR 0877's shape, read at the one place a landed blow's cost is
## ## decided. Equal halves cancel to the neutral, the floor is zero (a fully shredded
## ## response removes nothing), and the cap is `CombatTuning.refusal_cap`, so no stack
## ## of `strength` ever refuses a landed blow outright.
static func _refusal(
	attacker: Actor, target: Actor, tuning: CombatTuning, outcome: CombatOutcome
) -> float:
	if tuning == null:
		return 1.0
	var neutral := 0.0
	var strength_id := &""
	var shred_id := &""
	if outcome.parried:
		neutral = 1.0 - PARRY_COST
		strength_id = CombatStats.PARRY_STRENGTH
		shred_id = CombatStats.PARRY_SHRED
	elif outcome.blocked:
		neutral = 1.0 - BLOCK_COST
		strength_id = CombatStats.BLOCK_STRENGTH
		shred_id = CombatStats.BLOCK_SHRED
	else:
		return 1.0
	var scale := tuning.rate_scale
	var removal := neutral
	if scale > 0.0:
		removal += (_stat(target, strength_id) - _stat(attacker, shred_id)) / scale
	removal = clampf(removal, 0.0, clampf(tuning.refusal_cap, 0.0, 1.0))
	return 1.0 - removal


## S10's aftermath, S11's aftermath, and the bounce arithmetic all live in
## `CombatRecoil` (`recoil.gd`): the two stages that read the HP write rather than
## compute into it, kept together so "S9 -> S10 -> S11" is asserted at the one call site
## above and implemented in one place.

# --- reads --------------------------------------------------------------------


## The mitigation level this module names is `1 + delta / amp_scale` with `delta` the
## attacker's amplification LESS the defender's reduction, so the level this file reads
## for one reduction channel is `1.0 - reduction / amp_scale`. Read [method amp_factor]
## for the shape and why it is not a reciprocal.
##
## `CombatStats.DAMAGE_REDUCTION` (this module's `REDUCTION`) is a FLAT, UNSCALED
## subtraction. `Stat.DAMAGE_REDUCTION` is core's, also FLAT and also unscaled, but
## ADR 0067's S7 — `ampFactor(amp - reduction)` — measures `d` against `amp_scale`, so
## core's channel is scaled to that scale before being handed over. Without the scaling
## the two would not be the same kind of number: a core `0.05` would be worth five times
## what this module's `0.05` is, and a rebalance of one would silently rebalance the
## other. The scaling happens HERE, once, on the edge — not in the arithmetic — which is
## the whole reason this function exists rather than a subtraction inline in `_delta`.
static func _delta(attacker: Actor, target: Actor, tuning: CombatTuning) -> float:
	return (
		_stat(attacker, CombatStats.AMPLIFICATION)
		- (_stat(target, CombatStats.REDUCTION) + _scaled_core_reduction(target, tuning))
	)


## Core's `Stat.DAMAGE_REDUCTION` expressed on `amp_scale`. The clamp is deliberate and
## is now REDUNDANT with [method amp_factor]'s own floor -- it is kept because it bounds
## `_delta` to `>= -amp_scale` so the number handed to S7 stays readable, and because it
## is the statement that a flat reduction of a million is an authored REFUSAL rather than
## a balance dial. It used to be load-bearing: `amp_factor`'s reciprocal branch could not
## reach zero, so this clamp was the only thing making the immunity invariant reachable.
## Read `amp_factor` for why that shape is gone.
static func _scaled_core_reduction(target: Actor, tuning: CombatTuning) -> float:
	return clampf(_stat(target, Stat.DAMAGE_REDUCTION), 0.0, tuning.amp_scale)


## S3's draw. The crit CHANCE trigger: attacker's `Stat.CRIT_CHANCE` BEATS the
## defender's `Stat.CRIT_RESIST` — `clampf((crit_chance - crit_resist) / rate_scale, 0, 1)`
## through [method CombatStats.contest_of] (ADR 0877). Equal halves read `0.0`, so the
## crit is something the attacker WINS rather than a midpoint nobody chose; the defence
## half has been read since ADR 0215 and is untouched by the shape change.
static func _crit(attacker: Actor, target: Actor, tuning: CombatTuning, rng: Variant) -> bool:
	if rng == null:
		return false
	var p := CombatStats.contest_of(
		Stat.CRIT_CHANCE, attacker, Stat.CRIT_RESIST, target, tuning.rate_scale
	)
	return rng.randf() < p


## S2's `p_hit`: the landed chance, as the flat delta
## `clampf((accuracy - evasion) / rate_scale, 0, 1)` through [method CombatStats.contest_of]
## (ADR 0877). The landed probability for one attack, `p_hit` for the band roll. Public
## because a preview must quote the exact chance a screen shows, and a caller reaching
## into the spine's internals to get it would be a second, divergent copy of this line.
##
## ## Zero at parity is the design, and the base accuracy is what keeps combat playable
##
## The owner's rule: a defender who MATCHES the attack cancels it completely, and one who
## beats it cannot be hit at all. That is deliberately stricter than either earlier shape
## — ADR 0068's subtraction and ADR 0215's ratio both let a matched defender be hit — and
## it is why `Stat.ACCURACY` is DERIVED at last (`0.005 + agility * 0.0015`, ADR 0877):
## every attack carries a base accuracy, so a defender meets it by investing EVASION
## rather than by the accident of both halves reading `0.0`. A dodge build answers by
## out-evading the base; an accuracy build answers the dodge build. Neither half is
## capped, and only the output is a probability.
##
## The complement-reading this function used to carry (`1 - evasion/(evasion + accuracy)`,
## so that two stock actors with no stats landed) is DELETED with the ratio: under the
## flat rule the two spellings differ at parity, and the parity `0.0` is the point
## rather than a discontinuity to paper over.
static func landed_chance(attacker: Actor, target: Actor, tuning: CombatTuning) -> float:
	return CombatStats.contest_of(
		CombatStats.ACCURACY, attacker, Stat.EVASION, target, tuning.rate_scale
	)


## S2's `p_parry`: the defender's `PARRY_RATE` beats the attacker's `PARRY_BREAK`
## (ADR 0877). `PARRY_STRENGTH` and `PARRY_SHRED` are NOT read here: they move the
## refusal share at the S2 AFTERMATH ([method _refusal], ADR 0878) — what a landed parry
## COSTS — and have no business inside a band roll that must stay one comparison.
##
## The second argument is `PARRY_BREAK` and fixing it here is part of the ADR: it read
## the attacker's own `PARRY_RATE`, so the attacker's suppress half was dead and an
## attacker's parry investment silently weakened the defender's parry.
static func _parry(attacker: Actor, target: Actor, tuning: CombatTuning) -> float:
	return CombatBand.rate(
		_stat(target, CombatStats.PARRY_RATE), _stat(attacker, CombatStats.PARRY_BREAK), tuning
	)


## S2's `p_block`. Block's twin of [method _parry]: same contest, same fixing of the
## suppress argument to `BLOCK_BREAK`, one vocabulary (ADR 0877). `BLOCK_STRENGTH` and
## `BLOCK_SHRED` are read at [method _refusal] rather than here — they scale what a
## block REMOVES, not the band itself, so no two of the four parry ids and the four
## block ids can disagree about what blocking means.
static func _block(attacker: Actor, target: Actor, tuning: CombatTuning) -> float:
	return CombatBand.rate(
		_stat(target, CombatStats.BLOCK_RATE), _stat(attacker, CombatStats.BLOCK_BREAK), tuning
	)


## S6's multiplier: `1.0 + rate_from_zero(crit_damage, crit_resist_damage, rate_scale)`
## (ADR 0877). It is read here exactly once: the CHANCE was resolved at S3, so a second
## `Stat.CRIT_CHANCE` read here would make the ladder a second crit dial.
##
## ## Why the shape is `1 +` and not the delta itself
## A crit that triggered must never be WEAKER than a normal hit, so the multiplier
## FLOORS at `1.0`: equal halves mean the crit is cosmetic rather than a penalty, and
## the attacker's excess buys up to a doubling (`rate_from_zero` saturates at `1.0`).
## `Stat.CRIT_DAMAGE` therefore ships as the bonus MAGNITUDE `comprehension * 0.004`
## and not a `1.5 +` multiplier (ADR 0877): the constant term was a bonus no defender
## could ever contest, and its removal is what makes this pair a real pair.
##
## Both reads are TOTAL through [method _stat], so a half-built actor contests nothing
## rather than crashing a hit that has already committed to mutating both of them.
static func _crit_damage(attacker: Actor, target: Actor, tuning: CombatTuning) -> float:
	return (
		1.0
		+ CombatStats.rate_from_zero(
			_stat(attacker, Stat.CRIT_DAMAGE),
			_stat(target, Stat.CRIT_RESIST_DAMAGE),
			tuning.rate_scale
		)
	)


# --- context ------------------------------------------------------------------


## Build the seam's context. `ctx_builder` is the extension point that lets a later
## wave carry an element rule table or a location resolver through the spine without a
## sixth stage: it receives the built context and returns it.
static func _context(
	ctx_builder: Callable,
	attacker: Actor,
	target: Actor,
	technique: TechniqueDef,
	tuning: CombatTuning,
	base: float,
	rolled: bool,
	crit: bool
) -> AttackContext:
	var ctx := AttackContext.new(attacker, target, technique, tuning)
	ctx.set(&"base", base)
	ctx.set(&"magnitude", base)
	ctx.set(&"rolled", rolled)
	ctx.set(&"crit", crit)
	if ctx_builder.is_valid():
		return ctx_builder.call(ctx) as AttackContext
	return ctx


# --- stat plumbing ------------------------------------------------------------
#
# `_stat` is TOTAL: an actor with no `ActorStats` and an id nobody declares both read
# 0.0. The spine is the one place that must never crash on a half-built actor, because
# every stage past S2 has already committed to mutating two of them.


static func _stat(actor: Actor, id: StringName) -> float:
	if actor == null or actor.stats == null:
		return 0.0
	return actor.stats.derived(id)
