class_name CombatSpine
extends RefCounted

## The one damage pipeline every hit passes through (ADR 0067). Eleven stages, in
## order, unchangeable without an ADR. Nine are SHARED; S4 and S5 are the seam.
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
## file, so it is a test: `tests/modules/combat/test_combat_mechanism_seam.gd` drives
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

## What a parry refunds: the share of the landed amount that reaches the defender's
## health. A parry is a DEFENSIVE RESPONSE to a blow, not an exemption from it — and
## because S8's chip floor runs before S9, a refusal can never refuse every hit. This
## is the only vocabulary combat needs to express a parry, and it needs no extra stage
## and no second `mitigate` call.
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
## health, S10 spends it again on the other side, S11 heals, S12 applies a status.
##
## `rng` may be null, in which case nothing random happens and every attack lands —
## the shape the rest of the repo already uses (`CombatDamage.resolve_hit`,
## `LootState`). A caller that wants reproducibility injects one (ADR 0067). A null
## `rng` also means NO status is applied, never a `randf()` fallback (ADR 0087).
##
## `tuning` and `ctx_builder` are INJECTED rather than defaulted to a loaded constant:
## the spine is static so it can be called with no scene tree, and a `load()` inside a
## stage would make the stages depend on the resource filesystem instead of on their own
## arguments. `CombatApi.resolve_hit` supplies both from `combat_damage.tres`.
##
## `hit_index` is the number of this hit in the exchange, used ONLY to salt S12's
## substream. It is a parameter and not a field some actor carries between fights,
## exactly as `chain_depth` is: two identical attacks in one fight must not roll the
## same status, and the index is the only thing that tells them apart. Defaults to `0`,
## so every existing caller is unaffected.
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
	var crit := band.is_clean() and _crit(attacker, rng)
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
		amount *= _crit_damage(attacker)
	outcome.amount = maxf(0.0, amount)
	# --- S7: one mitigation shape for all three paths, linear and floored at zero. ---
	outcome.amount = maxf(
		0.0, outcome.amount * amp_factor(_delta(attacker, target, tuning), tuning)
	)
	# --- S8: the immunity invariant. AFTER S7, or enough reduction erases a crit. ---
	outcome.amount = maxf(outcome.amount, chip_floor(outcome.base, tuning))
	_spend(attacker, target, tuning, outcome, chain_depth)
	# --- S12: LAST, after S11. Two NEW orderings ride on that placement (ADR 0087):
	# S9 before S12, so a defender that died of the blow is not burned by it, and
	# S11 before S12, so a status cannot change `health_regen` mid-leech-packet. All
	# four of ADR 0067's own orderings are untouched: S12 sits downstream of all of
	# them, and inherits S2's because `is_clean()` is false for anything a miss, a
	# parry or a block produced. The stage writes NO health and negates nothing, so
	# the spine's single sign flip at S9 stays the only one in the engine.
	#
	# The context is REBUILT rather than carried: `_spend` returns the outcome and not
	# the context, and rebuilding is the cheaper of the two by an order of magnitude
	# against a `ctx_builder` that may do real work. It also keeps `ctx_builder` in
	# exactly one call site, which is the property that made the extension point
	# reviewable in the first place.
	StatusApply.record(
		outcome,
		StatusApply.apply(
			attacker,
			target,
			tuning,
			_context(
				ctx_builder, attacker, target, technique, tuning, outcome.base, true, outcome.crit
			),
			outcome,
			rng,
			technique,
			hit_index
		)
	)
	return outcome


## S1 alone: the authored magnitude through the realm rate gate. `RealmRate` is a
## RATE, not a magnitude (ADR 0050) — it returns `1.02^ordinal < 2.0` over the whole
## ladder and never reads the realm power table. Exposed on its own so S1 is a
## two-line test rather than a debate, and so a caller quoting a number quotes the
## rate-gated one.
static func base_damage(attacker: Actor, technique: TechniqueDef) -> float:
	if technique == null:
		return 0.0
	var base := technique.magnitude
	if attacker != null:
		base *= RealmRate.factor(attacker.realm())
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
	var spendable := outcome.amount * _refusal(outcome)
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


## S2's aftermath on the amount: a parry refunds `PARRY_COST`, a block refunds
## `BLOCK_COST`, a clean hit refunds all of it. A miss never reaches this.
static func _refusal(outcome: CombatOutcome) -> float:
	if outcome.parried:
		return PARRY_COST
	if outcome.blocked:
		return BLOCK_COST
	return 1.0


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


## S3's draw. `Stat.CRIT_CHANCE` already caps itself at 0.75 in
## `core/actor_stats.gd`, so a non-negative roll cannot crit.
static func _crit(attacker: Actor, rng: Variant) -> bool:
	if rng == null:
		return false
	return rng.randf() < maxf(0.0, _stat(attacker, Stat.CRIT_CHANCE))


## S2's `p_hit`: the landed chance, from the DEFENDER's `Stat.EVASION` less the
## attacker's `CombatStats.ACCURACY`. That subtraction is the only thing `accuracy`
## does, and it is why `Stat.EVASION`'s 0.6 cap is a real bound: even at zero accuracy
## the landed chance is at least 0.4, so there is no second miss channel.
## The landed probability for one attack, `p_hit` for the band roll. Public because a
## preview must quote the exact chance a screen shows, and a caller reaching into the
## spine's internals to get it would be a second, divergent copy of this line.
static func landed_chance(attacker: Actor, target: Actor, tuning: CombatTuning) -> float:
	var evasion := maxf(0.0, _stat(target, Stat.EVASION) - _stat(attacker, CombatStats.ACCURACY))
	return clampf(1.0 - evasion / tuning.rate_scale, 0.0, 1.0)


## S2's `p_parry`. Linear-from-zero, so an unstatted defender parries 0% and never a
## sigmoid's unchosen 50% (ADR 0068). `PARRY_BREAK` and `PARRY_SHRED` are NOT read
## here: breaking the parry costs the defender poise and re-reads, and shredding it
## costs their ability to parry at all — both are a defensive RESPONSE to a landed
## parry, which wave E owns and which has no business inside a band roll that must
## stay one comparison.
static func _parry(attacker: Actor, target: Actor, tuning: CombatTuning) -> float:
	return CombatBand.rate(
		_stat(target, CombatStats.PARRY_RATE), _stat(attacker, CombatStats.PARRY_RATE), tuning
	)


## S2's `p_block`. Block's twin of [method _parry]: same contest, same scale, one
## vocabulary. `PARRY_STRENGTH` / `BLOCK_STRENGTH` are the defender's amplifiers and are
## NOT read by the spine — they scale the break and shred a response costs, not the
## band itself, so no two of the four parry ids and the four block ids can disagree
## about what parrying means.
static func _block(attacker: Actor, target: Actor, tuning: CombatTuning) -> float:
	return CombatBand.rate(
		_stat(target, CombatStats.BLOCK_RATE), _stat(attacker, CombatStats.BLOCK_RATE), tuning
	)


## S6's multiplier. `Stat.CRIT_DAMAGE` is a MULTIPLIER with a 1.5 baseline, not a
## bonus, and it is read here exactly once: the CHANCE was resolved at S3, so a second
## `Stat.CRIT_CHANCE` read here would make the ladder a second crit dial.
static func _crit_damage(attacker: Actor) -> float:
	return maxf(0.0, _stat(attacker, Stat.CRIT_DAMAGE))


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
