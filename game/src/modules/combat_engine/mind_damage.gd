class_name MindDamage
extends DamageMechanism

## Mind damage ERODES THE SEA and never subtracts health (ADR 0071).
##
## ## The formula, verbatim
##
## ```
## base = attacker MENTAL_ATTACK * share
## d    = defender MENTAL_DEFENSE
## mit  = clampf(d/(d+base), 0, MENTAL_DEFENSE_CAP)          # 0 at d=0, ->0.6 asymptotic
## if OBSCURE: mit = maxf(mit, defender ILLUSION_RESISTANCE)  # illusions read THEIR stat
## mit  = clampf(mit, 0, ILLUSION_RESISTANCE_CAP)
## coh  = 1 - COHERENCE_DAMP * awareness_ratio(defender)     # 1.0 -> 0.5 at full awareness
## g    = base * (1-mit) * coh * (FOCUS_MULT if focused else 1.0)
## g   /= defender_sea.structural_capacity                   # a SHARE of THAT sea
## clarity_delta = -TURBULENCE_TO_CLARITY * g                # every kind, floored at 0
## ```
##
## ## `amount` is ALWAYS `0.0`, and that is the design, not a limitation
##
## `DamageProposal.amount` is what the spine spends through S6-S9 on health, and mind
## spends none of it. The hit is carried by `effects[]`, which ADR 0067 applies AFTER
## health. ADR 0071 is the reason `effects[]` exists at all: qi and body both return an
## `amount` and neither effect would have been needed for them.
##
## ## S4 is the UNMITIGATED erosion and S5 is the defence, exactly as the ADR asks
##
## `resolve` returns `base * coherence * focus`, normalised by `structural_capacity`.
## `mitigate` multiplies those effects by `1 - mit`. That is why the two stages are split at
## all (ADR 0067), and it is what lets a test observe "the mechanism produced X" and "the
## defence of X is Y" independently rather than only one fused number.
##
## ## `structural_capacity` is the denominator, and why
##
## `MENTAL_ATTACK` is a bounded RATE (`MindProvider`: `(perception*2 + clarity*1.5) *
## RealmRate.factor`, so 62.5 -> 110.9903 at R30, `1.02^29 = 1.775845`). `sea_capacity` is
## the AUTHORED magnitude, 100.0 -> 825.0 across the 30 `MindRealmSeed` `.tres`. Those two
## do not share a scale, and dividing one by the other without normalising makes the deep
## realms a one-hit kill. Dividing by `structural_capacity` makes "one full strike" the same
## SHARE of that sea at every realm — which is the property the suite asserts.
##
## ## The 40% floor is STRUCTURAL
##
## `mental_defense` enters only through the saturating `d/(d+base)`, hard-capped at
## `MENTAL_DEFENSE_CAP`, so **40% of every mind strike always lands at any
## `mental_clarity` and at any realm**. This is the mind analogue of the spine's chip-floor
## immunity invariant and it obeys ADR 0051's rule that the breakthrough roll must not read
## a quantity the entry gate already pins. See [method defense_floor].
##
## ## `Stat.DAMAGE_REDUCTION` is NEVER read here
##
## A qi/body tank does nothing at all to erosion. Not by omission: the seam splits S4 from S5
## precisely so mind's `mitigate` applies the MIND defence and nothing else, and
## `CombatTuning`'s mind block deliberately carries no reduction field, so there is no knob
## to turn. A qi/body hit and a mind hit also share no authored stat prefix at all.
##
## ## The sea is INJECTED, and this module has NO `mind_cultivation` edge
##
## The sea arrives on `ctx.data` or on the `sea` field and every field is reached through
## `get()`. This file names no class of that module — not `SeaOfConsciousness`, not
## `MindStats`, not `MindCultivationApi` — so `tools/arch/registry.json` keeps
## `combat_engine` at `["contracts", "core"]` and the registry does not lie about an edge
## that exists only in prose. The ids it DOES read are authored on `CombatTuning`
## (BRIEF 1.7: tuning in DATA), the one honest way to name another module's ids without
## naming its types.
##
## ## Health moves ONLY through rupture bleed, per combat tick
##
## See [method tick_rupture]. Below `RUPTURE_THRESHOLD` health is FLAT — the floor of safety
## qi (ADR 0069) and body (ADR 0070) do not have. A mind duel is won by eroding the sea
## until the loser's breakthrough roll is unaffordable, not by out-damaging them.
##
## ## The holes ADR 0071's own arithmetic leaves, each closed without a new constant
##
## 1. **`d == 0` and `base == 0` together divide by zero.** `mit = d/(d+base)` is
##    `0.0 / 0.0 == NaN` for an unattacked unstatted target and a `NaN` survives every
##    `clampf`. A non-positive denominator reads `0.0` — no contest, never a division, the
##    same degradation `QiDamage._resistance_of` gives a 0.0 divisor.
## 2. **`structural_capacity <= 0.0`** divides by zero. A sea nobody trained has no scale, so
##    the erosion reads `0.0` — visibly inert rather than `INF`.
## 3. **`MENTAL_DEFENSE_CAP > 1`** would make `(1 - mit)` negative and the mechanism would
##    SHARPEN the sea it exists to erode. Clamped to `[0, 1]` on read.
## 4. **`coherence_damp > 1.0`** makes `coh` negative at a full reserve and a negative
##    multiplier hands the defender a share of the attacker's erosion as a heal. Clamped.
## 5. **`focus_mult < 1.0`** would make a crit a WEAKER strike, which no chance stat should
##    ever do. Read as `maxf(focus_mult, 1.0)` rather than clamped, so the neutral stays 1.0.
## 6. **`rupture_threshold >= 1.0`** is unreachable by construction, silently disables bleed,
##    and divides by zero in the `(turbulence - threshold) / (1 - threshold)` headroom. One
##    clamp into `[0, 1)` closes both, because the divisor is read only after it.
## 7. **`collapse_deviation_duration == 0.0`** would build a status already expired on the
##    frame it was applied: `StatusEffect`'s own `-1.0` sentinel means PERMANENT, so a
##    non-positive duration is floored to that sentinel rather than authored as a no-op.
## 8. **A demotion past `vast`** has no meaning and inventing a fourth tier would be a
##    cultivation decision this module may not make, so it is refused and reported.

## The erosion kind, which decides what the hit does BEYOND turbulence. Authored per
## technique, carried on `ctx.data`, never read off a shared enum elsewhere.
enum Kind {
	DISRUPT,  ## turbulence only -- the plain strike.
	OBSCURE,  ## turbulence + confusion; the ONLY kind that reads `ILLUSION_RESISTANCE`.
	ATTEND,  ## drains the AWARENESS reserve `coherence` is computed from.
}

## `ctx.data` key carrying this attack's kind, as a [enum Kind] ordinal or its name.
## Unrecognised values read `DISRUPT`, never a fourth kind nobody wrote a branch for.
const KIND_KEY := &"mind_kind"
## `ctx.data` key carrying the authored share of `MENTAL_ATTACK` this strike carries.
## Non-positive means "use the tuning's default", the same rule `QiDamage._share_of`
## applies to `element_share`, so the two paths cannot disagree about an unauthored share.
const SHARE_KEY := &"mind_share"
## `ctx.data` key carrying the defender's sea. A `Variant` reached only through `get()`.
const SEA_KEY := &"sea"
## `ctx.data` key overriding the tuning for one hit. `CombatTuning` is this module's own
## type, so it is named here and nowhere else on the mind path.
const TUNING_KEY := &"tuning"

## The effect kind every erosion writes. ONE entry per hit carrying every write, because
## turbulence and the clarity it costs are the same event: a panel that read them as two
## effects could show a sea that went turbulent without paying for it.
const EFFECT_KIND := &"mind.erosion"
## The strike kind (`disrupt` / `obscure` / `attend`) as a PAYLOAD field of the erosion
## effect. A name rather than the enum ordinal: an ordinal in a save payload is a renumbering
## hazard and a name is not.
##
## NOT `DamageProposal.KIND`, which is `"kind"` too and means the effect's OWN vocabulary --
## see [_effects].
const KEY_STRIKE_KIND := &"strike_kind"
## The turbulence ADDED by this hit, before the sea clamps it into `[0, 1]`.
const KEY_TURBULENCE := &"turbulence"
## The clarity LOST. Negative, because it is a delta.
const KEY_CLARITY := &"clarity"
## The AWARENESS drained by an `ATTEND` strike. `0.0` for the kinds that do not touch the
## reserve, so the effect shape never changes with the kind.
const KEY_AWARENESS := &"awareness"
## The share of the sea the unmitigated erosion represents, before S5's defence.
const KEY_EROSION := &"erosion"

## The id of the status a COLLAPSE applies. A real `StatusEffect` with a duration, not a
## bespoke mind flag: "the loser is disarmed for a minute" is only true if the disarm is
## something the engine ticks.
const DEVIATION_STATUS := &"mind_deviation"
## The sea field this module parks the collapse timer on, rather than on a
## `mind_cultivation` field it may not add. Written only when the sea exposes it, so a
## foreign object simply cannot collapse and the caller keeps the timer itself.
const HELD_FIELD := &"mind_collapse_held"

## The rupture tick's result keys, so a readout and a test read the same names.
const KEY_HP_LOSS := &"hp_loss"
const KEY_BLEEDING := &"bleeding"
const KEY_STATE_TURBULENCE := &"sea_turbulence"
const KEY_THRESHOLD := &"threshold"
## The collapse tick's result keys.
const KEY_COLLAPSED := &"collapsed"
const KEY_HELD := &"held"
const KEY_FROM_TIER := &"from_tier"
const KEY_TO_TIER := &"to_tier"
const KEY_CAPACITY := &"capacity"
const KEY_CLARITY_NOW := &"clarity"

static var _shipped: CombatTuning = null

## The tuning this mechanism reads, when a caller binds one. Null means "the per-attack
## override, then [method CombatTuning.shipped]".
var tuning: CombatTuning = null
## The injected sea, when a caller binds one. A `Variant` reached only through `get()`.
var sea: Variant = null
## The kind this mechanism produces when the hit authored none.
var kind: Kind = Kind.DISRUPT


## S4. The UNMITIGATED erosion: `base * coherence * focus`, over `structural_capacity`, with
## `amount == 0.0` always. The defence is S5's, not this stage's, which is the whole point
## of ADR 0067 splitting them.
##
## `ctx.crit` is deliberately NOT read: S6 multiplies the AMOUNT and a mind amount is zero,
## so the shared crit channel is simply inert here. Mind crit is `MIND_FOCUS_CHANCE`, and
## [method _focus_of] is its only implementation in the engine — one draw on `ctx.rng`, and
## NO draw at all when `rng` is null, because a deterministic caller is asking for the one
## answer that consults no randomness.
func resolve(ctx: AttackContext) -> DamageProposal:
	var parts := breakdown(ctx)
	return DamageProposal.new(0.0, _effects(parts))


## S5. The mind defence, applied to the effects rather than to an amount, and applied ONCE.
## The erosion already carries `(1 - mit)` nowhere else, so this is the only place the
## defence is applied and multiplying it here is not a second application.
##
## The amount stays `0.0` through here and `Stat.DAMAGE_REDUCTION` is never read. The
## proposal handed in is never edited in place, and `DamageProposal.shared` — which the spine
## passes when S4 declined — is answered by rebuilding the effects rather than by crashing
## on a proposal with none.
func mitigate(ctx: AttackContext, proposal: DamageProposal) -> DamageProposal:
	var parts := breakdown(ctx)
	var defence := clampf(1.0 - float(parts["mitigation"]), 0.0, 1.0)
	var carried: Array[Dictionary] = []
	if proposal != null:
		for entry in proposal.effects:
			if entry.get(DamageProposal.KIND, &"") == EFFECT_KIND:
				var scaled := entry.duplicate(true)
				for key in [KEY_TURBULENCE, KEY_CLARITY, KEY_AWARENESS]:
					scaled[key] = _finite(_number(scaled.get(key, 0.0)) * defence)
				carried.append(scaled)
	if carried.is_empty():
		carried = _effects(parts)
	return DamageProposal.new(0.0, carried)


## Every primitive this mechanism computed, for a UI readout (ADR 0038: primitives in a
## `summary()` payload, never an engine object or a module type).
##
## `{kind, share, mental_attack, base, mental_defense, mitigation, illusion_resistance,
## awareness_ratio, coherence, focused, erosion, defence, turbulence, clarity_delta,
## awareness_delta, structural_capacity, subtotal, total, sea_bound, rng_bound}`.
##
## `erosion` is what S4 produced and `turbulence` / `clarity_delta` / `awareness_delta` are
## what it costs; `subtotal` and `total` are the erosion after and before the defence, so a
## panel can show the defence line as the difference between two rows rather than recomputing
## it. All of it is pure and side-effect free: both seam stages read this one function, so
## they cannot disagree.
func breakdown(ctx: AttackContext) -> Dictionary:
	if ctx == null:
		return _empty_parts()
	var tuning := _tuning_of(ctx)
	var resolved := _kind_of(ctx)
	var share := _share_of(ctx, tuning)
	var mental_attack := maxf(0.0, _finite(ctx.attacker_value(_mind_stat(tuning, "mental_attack"))))
	var base := _finite(mental_attack * share)
	var mental_defense := maxf(0.0, _finite(ctx.target_value(_mind_stat(tuning, "mental_defense"))))
	var mitigation := _mitigation_of(ctx, tuning, base, mental_defense, resolved)
	var awareness := _awareness_ratio_of(ctx, tuning)
	var coherence := _coherence_of(ctx, tuning, resolved, awareness)
	var focused := _focus_of(ctx, tuning)
	var capacity := _structural_capacity_of(ctx, tuning)
	# Hole 2: a sea with no scale is NOT an infinite erosion. `0.0` is visibly inert, which
	# is the whole point of `CombatTuning`'s degenerate defaults.
	var erosion := 0.0 if capacity <= 0.0 else _finite(base * coherence * focused / capacity)
	return {
		"kind": kind_name(resolved),
		"share": share,
		"mental_attack": mental_attack,
		"base": base,
		"mental_defense": mental_defense,
		"mitigation": mitigation,
		"illusion_resistance": _illusion_resistance_of(ctx, tuning, resolved),
		"awareness_ratio": awareness,
		"coherence": coherence,
		"focused": focused > 1.0,
		"erosion": erosion,
		"structural_capacity": capacity,
		"subtotal": erosion,
		"total": erosion * clampf(1.0 - mitigation, 0.0, 1.0),
		"turbulence": _finite(erosion),
		"clarity_delta": _finite(-_share(tuning.turbulence_to_clarity) * erosion),
		"awareness_delta": _awareness_delta_of(resolved, awareness, erosion),
		"sea_bound": _sea_of(ctx, tuning) != null,
		"rng_bound": ctx.rng != null,
	}


## The share of a mind strike that lands at ANY `mental_clarity` and at ANY realm:
## `1 - MENTAL_DEFENSE_CAP`. `0.4` at the shipped value.
##
## Published rather than left to every caller to re-derive, because this number IS the mind
## analogue of the spine's `min_chip_abs` and a second copy of the arithmetic is a second
## place for a rebalance to miss. It is what makes a mind fight's difficulty come from
## coherence, awareness and the matchup of intent rather than from stacking `mental_clarity`.
static func defense_floor(tuning: CombatTuning = null) -> float:
	var source := tuning
	if source == null:
		source = CombatTuning.shipped()
	if source == null:
		return 0.0
	return clampf(1.0 - _share(source.mental_defense_cap), 0.0, 1.0)


## THE ONLY thing on the mind path that moves health (ADR 0071). A COMBAT TICK, not a hit:
## `CombatSpine` has no stage for it and ADR 0071 adds none, exactly as ADR 0070's
## `BodyDamage.decay` is separate for the same reason.
##
## ```
## hp_loss = max_health * RUPTURE_BLEED * (turbulence - RUPTURE_THRESHOLD)
##                                    / (1 - RUPTURE_THRESHOLD) * delta
## ```
##
## `delta` is ALWAYS a parameter and never a wall-clock read, so a replay bleeds exactly as it
## was driven. Zero at or below the threshold — a mind duel's floor of safety — and linear
## from there to `RUPTURE_BLEED` of the whole pool at `turbulence == 1.0`.
##
## Returns `{hp_loss, bleeding, sea_turbulence, threshold}`. Zero below the threshold, never
## negative, and clamped to the pool's own `maximum` so a pathological `delta` cannot spend
## more health than the actor holds.
func tick_rupture(
	sea_component: Variant, actor: Variant, delta: float, tuning: CombatTuning = null
) -> Dictionary:
	var bound := _tuning_or(tuning)
	var result := {KEY_HP_LOSS: 0.0, KEY_BLEEDING: false, KEY_STATE_TURBULENCE: 0.0}
	if sea_component == null or actor == null or not (delta > 0.0):
		return result
	# Hole 6. The clamp is `[0, 1)` and not `[0, 1]` for BOTH reasons at once: a threshold
	# at 1.0 is unreachable by construction, and `1.0 - threshold` is this function's only
	# divisor, so an authored `1.0` would be `0.0 / 0.0` on the one tick it must not be.
	var threshold := clampf(_finite(bound.rupture_threshold), 0.0, 0.999999)
	result[KEY_THRESHOLD] = threshold
	var turbulence: float = clampf(
		_finite(_number(_read(sea_component, &"turbulence", 0.0))), 0.0, 1.0
	)
	result[KEY_STATE_TURBULENCE] = turbulence
	if turbulence <= threshold:
		return result
	var bleed := _share(bound.rupture_bleed)
	var pool: Variant = _pool_of(actor, bound.health_pool_id)
	if bleed <= 0.0 or pool == null:
		return result
	var maximum := maxf(0.0, _finite(_number(_read(pool, &"maximum", 0.0))))
	if maximum <= 0.0:
		return result
	var over := clampf((turbulence - threshold) / (1.0 - threshold), 0.0, 1.0)
	var loss := _finite(maximum * bleed * over * maxf(0.0, _finite(delta)))
	if loss <= 0.0:
		return result
	loss = minf(loss, maximum)
	pool.call(&"change", -loss)
	result[KEY_HP_LOSS] = loss
	result[KEY_BLEEDING] = true
	return result


## The collapse check, and the only place a mind fight costs anything beyond turbulence. A
## separate COMBAT TICK from [method tick_rupture] because it reads different state — how
## LONG the sea has been at full turbulence — and because it is the only place this module
## mutates a sea's STRUCTURE rather than its turbulence.
##
## `turbulence == 1.0` held for `RUPTURE_COLLAPSE_TIME` CONTINUOUS seconds demotes the sea
## one tier, resets `structural_capacity` to that tier's authored floor, floors `clarity` at
## `COLLAPSE_CLARITY_FLOOR`, and applies `mind_deviation`. **The loser is disarmed for a
## minute, not killed.** Continuity is why `meditate` matters: any calming RESETS the clock,
## so defending by meditating is a real answer rather than a second resource to manage.
##
## `held` is the caller's accumulator and is returned rather than stored on the sea: this
## module may not add a field to a component it does not own, and a `mind_collapse_held`
## field the sea happens to expose is honoured on read but never required. That keeps the
## timer in the caller, which is also the only place a combat tick's own clock belongs.
##
## Returns `{collapsed, held, from_tier, to_tier, capacity, clarity, deviation}`.
static func tick_collapse(
	sea_component: Variant, actor: Variant, delta: float, held: float, tuning: CombatTuning = null
) -> Dictionary:
	var bound := _tuning_or(tuning)
	var result := {
		KEY_COLLAPSED: false,
		KEY_HELD: maxf(0.0, _finite(held)),
		KEY_FROM_TIER: "",
		KEY_TO_TIER: "",
		KEY_CAPACITY: 0.0,
		KEY_CLARITY_NOW: 0.0,
		&"deviation": "",
	}
	if sea_component == null or delta <= 0.0:
		return result
	var tier := StringName(_text(_read(sea_component, &"tier", &"")))
	result[KEY_FROM_TIER] = String(tier)
	var window := maxf(0.0, _finite(bound.rupture_collapse_time))
	var turbulence := clampf(_finite(_number(_read(sea_component, &"turbulence", 0.0))), 0.0, 1.0)
	if window <= 0.0 or turbulence < 1.0:
		result[KEY_HELD] = 0.0
		return result
	var held_now: float = float(result[KEY_HELD]) + maxf(0.0, _finite(delta))
	result[KEY_HELD] = held_now
	if held_now < window:
		return result
	var ladder := _ladder_of(bound)
	var index := ladder.find(tier)
	# Hole 8: `vast` is the floor of the ladder and a tier this tuning never heard of has no
	# successor. Neither is demoted, and the timer resets rather than accumulating into a
	# collapse that can never fire.
	if index < 0 or index >= ladder.size() - 1:
		result[KEY_HELD] = 0.0
		return result
	var demoted := ladder[index + 1]
	var capacity := _capacity_floor_of(bound, demoted)
	_settle(sea_component, &"tier", &"set_tier", demoted)
	if capacity > 0.0:
		_settle(sea_component, &"structural_capacity", &"set_structural_capacity", capacity)
	var clarity := clampf(_finite(bound.collapse_clarity_floor), 0.0, 1.0)
	_settle(sea_component, &"clarity", &"set_clarity", clarity)
	result[KEY_COLLAPSED] = true
	result[KEY_HELD] = 0.0
	result[KEY_TO_TIER] = String(demoted)
	result[KEY_CAPACITY] = capacity
	result[KEY_CLARITY_NOW] = clarity
	result[&"deviation"] = String(apply_deviation(actor, bound))
	return result


## Apply the `mind_deviation` disarm: a real `StatusEffect` with a duration, plus the
## `MIND_TECHNIQUE_POWER` zero it exists to apply. Returns the status id, or `&""` when
## nothing could be applied — a declined status is REPORTED rather than swallowed, because
## "the loser is disarmed for a minute" silently not happening is the one failure ADR 0071's
## consequence exists to prevent.
##
## The zero is a real `StatModifier` at apply time, not a flag somebody has to remember to
## honour: `FLAT` because `mind_technique_power` is a PERCENT-UNSAFE derived rate (BRIEF
## 1.8) and `PERCENT` on it would evaluate against its own baseline. Its LIMITATION is
## stated rather than hidden: the zero is a snapshot of the value at the moment of collapse,
## so a later raw-stat gain is not re-zeroed for the rest of the minute. That is the honest
## shape of a one-line modifier on a derived stat, and inventing a resolver for it would be
## a `mind_cultivation` change this module may not make.
static func apply_deviation(actor: Variant, tuning: CombatTuning = null) -> StringName:
	if actor == null or not (actor is Object):
		return &""
	var holder := actor as Object
	var bound := _tuning_or(tuning)
	var zeroed := StringName(_text(bound.mind_deviation_stat))
	var stats: Variant = _read(holder, &"stats", null)
	if stats is Object and (stats as Object).has_method(&"derived"):
		var current := _finite(_number((stats as Object).call(&"derived", zeroed)))
		if (stats as Object).has_method(&"add_modifier"):
			# `stats.as.Object` is not a CAST -- GDScript has no `.as` property, so this read
			# a property on the object rather than narrowing the Variant and raised
			# `Invalid access to property or key 'as'` against EVERY actor with an
			# `ActorStats`. The `add_modifier` guard above is the real check that the method
			# exists, and `call` needs the receiver only.
			stats.call(
				&"add_modifier", StatModifier.new(zeroed, Stat.Op.FLAT, -current, DEVIATION_STATUS)
			)
	# Hole 7: `StatusEffect`'s own `-1.0` sentinel means PERMANENT, so a non-positive
	# authored duration is floored to it. A `0.0` would build a status already expired on
	# the frame it was applied, which is the silent-failure shape a default exists to catch.
	var duration := _finite(bound.collapse_deviation_duration)
	var effect := StatusEffect.new(DEVIATION_STATUS, duration if duration > 0.0 else -1.0)
	if effect == null:
		return &""
	_assign(effect, &"magnitude", 0.0)
	if not holder.has_method(&"add_status"):
		return DEVIATION_STATUS
	# The registry's ANSWER is read, not discarded. `Actor.add_status` refuses an empty id or
	# a null status and reports it as `{ok, status_id, outcome, ...}`, so a status that was
	# never registered left the actor holding nothing while this function went on to answer
	# `DEVIATION_STATUS` — "the loser is disarmed for a minute" silently not happening, which
	# is the exact failure this docblock exists to prevent. A refusal is now REPORTED as `""`.
	var answer: Variant = holder.call(&"add_status", effect)
	if answer is Dictionary:
		var outcome := StringName((answer as Dictionary).get(&"outcome", &""))
		if not (answer as Dictionary).get(&"ok", false) and outcome != StatusRegistry.APPLIED:
			return &""
	var held := (
		true
		if not holder.has_method(&"has_status")
		else bool(holder.call(&"has_status", DEVIATION_STATUS))
	)
	return DEVIATION_STATUS if held else &""


## A `ctx_builder` for `CombatSpine.resolve_hit`: carries this mechanism's inputs through the
## ONE context, so the spine needs no sixth stage and no knowledge of what a mind hit is
## (ADR 0067).
##
## ```
## CombatSpine.resolve_hit(attacker, target, technique, tuning, rng,
##     MindDamage.builder(MindDamage.Kind.OBSCURE, defender_sea))
## ```
##
## Both are `Variant` and read through `get()`, because a caller in another module hands over
## its own authored content type and this file must not acquire a compile-time edge to it.
static func builder(p_kind: Variant = Kind.DISRUPT, p_sea: Variant = null) -> Callable:
	return func(ctx: AttackContext) -> AttackContext:
		if ctx == null:
			return ctx
		ctx.set_data(KIND_KEY, p_kind)
		if p_sea != null:
			ctx.set_data(SEA_KEY, p_sea)
		return ctx


## The kind's lowercase name, as the effect payload spells it.
static func kind_name(value: Kind) -> String:
	match value:
		Kind.OBSCURE:
			return "obscure"
		Kind.ATTEND:
			return "attend"
		_:
			return "disrupt"


# --- the formula's terms --------------------------------------------------------


## `clampf(d/(d+base), 0, MENTAL_DEFENSE_CAP)` — saturating, so enormous `mental_defense` is
## refused only up to the cap and `1 - cap` of the strike always lands.
##
## `OBSCURE` takes a `maxf` against `ILLUSION_RESISTANCE`, which is what makes an
## illusion-resistance build and a clarity build DIFFERENT defenders of the same skill: an
## `ILLUSION_RESISTANCE` build is flat `0.0` against `DISRUPT` and `ATTEND`, while a high
## `mental_clarity` build answers every kind. The `maxf` is taken BEFORE the
## `ILLUSION_RESISTANCE_CAP` re-clamp so a hand-edited `.tres` cannot author a cap of `4.0`
## and have the mitigation go negative.
##
## Hole 1 is here: `0.0 / 0.0` is `NaN` and a `NaN` survives every `clampf`, so a
## non-positive denominator is caught rather than passed on.
func _mitigation_of(
	ctx: AttackContext, tuning: CombatTuning, base: float, defense: float, kind_value: Kind
) -> float:
	var denominator := defense + base
	var saturated := 0.0 if denominator <= 0.0 else defense / denominator
	var rate := clampf(saturated, 0.0, _share(tuning.mental_defense_cap))
	if kind_value == Kind.OBSCURE:
		rate = maxf(rate, _illusion_resistance_of(ctx, tuning, kind_value))
	return clampf(rate, 0.0, _share(tuning.illusion_resistance_cap))


## `1 - COHERENCE_DAMP * awareness_ratio`, less whatever a `mind_avoidance` spend removes.
##
## The DEPLETING reserve is the mind path's first defensive lever and the only term that
## moves with it: a defender who spends awareness to take a mind strike takes the next one
## at nearly double the erosion, so the reserve is a resource to hold rather than a stat to
## stack. At the shipped `0.5` a full reserve halves the incoming coherence and an empty one
## does not.
##
## `mind_avoidance`'s spend removes exactly `COHERENCE_DAMP` of the coherence, which at the
## shipped `0.5` is half of it — deliberately different from a crit, which SPENDS
## `FOCUS_MULT`. Avoidance is a STEADIER, not a refusal, so it can be as cheap as a half and
## can never become a second miss channel the way an `EVASION` stat could. `ATTEND` is
## excluded: it spends the reserve the coherence is computed FROM, and refunding one for the
## other would double-dip the same stat.
func _coherence_of(
	ctx: AttackContext, tuning: CombatTuning, kind_value: Kind, awareness: float
) -> float:
	var damp := _share(tuning.coherence_damp)
	var coherence := clampf(1.0 - damp * clampf(awareness, 0.0, 1.0), 0.0, 1.0)
	var refund := _avoidance_of(ctx, tuning, kind_value)
	return clampf(maxf(coherence, refund), 0.0, 1.0)


## `FOCUS_MULT` when the `mind_focus_chance` roll came up, `1.0` otherwise.
##
## The ONLY consumer of `MIND_FOCUS_CHANCE` in the engine. One draw on `ctx.rng`, the ADR
## 0067 determinism rule: a null `rng` spends NO draw and answers `1.0`, because a
## deterministic caller is asking for the one answer that consults no randomness and a
## silent `randf()` fallback would make the same hit replay differently.
func _focus_of(ctx: AttackContext, tuning: CombatTuning) -> float:
	# Hole 5: a multiplier below 1.0 would make a crit a WEAKER strike, so the read floor is
	# 1.0 rather than a clamp at 0.0 -- the neutral is 1.0 and the dial only ever adds.
	var mult := maxf(1.0, _finite(tuning.focus_mult))
	if ctx.rng == null:
		return 1.0
	var chance := clampf(
		_finite(ctx.attacker_value(_mind_stat(tuning, "mind_focus_chance"))), 0.0, 1.0
	)
	if chance <= 0.0:
		return 1.0
	return mult if ctx.rng.randf() < chance else 1.0


## Whether the defender's `mind_avoidance` roll came up, as the coherence share it is worth.
## The twin of [method _focus_of] on the other side of the exchange, and it shares that
## function's null-`rng` rule: no generator, no draw, no answer.
func _avoidance_of(ctx: AttackContext, tuning: CombatTuning, kind_value: Kind) -> float:
	if kind_value == Kind.ATTEND or ctx.rng == null:
		return 0.0
	var chance := clampf(_finite(ctx.target_value(_mind_stat(tuning, "mind_avoidance"))), 0.0, 1.0)
	if chance <= 0.0 or ctx.rng.randf() >= chance:
		return 0.0
	return _share(tuning.coherence_damp)


## The defender's `ILLUSION_RESISTANCE`, read ONLY for `OBSCURE` — every other kind answers
## `0.0`, which is what makes "a clarity build and an illusion-resistance build are different
## defenders of the same skill" machine-checkable rather than asserted.
func _illusion_resistance_of(ctx: AttackContext, tuning: CombatTuning, kind_value: Kind) -> float:
	if kind_value != Kind.OBSCURE:
		return 0.0
	var id := _mind_stat(tuning, "illusion_resistance")
	return clampf(_finite(ctx.target_value(id)), 0.0, 1.0)


## The AWARENESS an `ATTEND` strike drains: the erosion itself, spent out of the reserve.
##
## Dimensional by construction — `erosion` is a `0..1`-ish SHARE of the sea and awareness is
## read as a `0..1` fraction — and clamped to what is actually held, so a strike can empty the
## reserve and can never invent a negative one. A target with no reserve at all answers `0.0`,
## which is the same degradation every other absent read on this file gives.
func _awareness_delta_of(kind_value: Kind, awareness: float, erosion: float) -> float:
	if kind_value != Kind.ATTEND or erosion <= 0.0:
		return 0.0
	return -clampf(awareness * clampf(erosion, 0.0, 1.0), 0.0, 1.0)


## The defender's AWARENESS as a `0..1` fraction, through `Actor.resource`'s own table and
## the `awareness_pool_id` authored on `CombatTuning`. An empty reserve reads `0.0` — the
## WORST coherence — which is the honest answer for a target with no awareness at all rather
## than a fabricated full one.
func _awareness_ratio_of(ctx: AttackContext, tuning: CombatTuning) -> float:
	var pool: Variant = _pool_of(ctx.target, tuning.awareness_pool_id)
	if pool == null:
		return 0.0
	var maximum := _finite(_number(_read(pool, &"maximum", 0.0)))
	if maximum <= 0.0:
		return 0.0
	return clampf(_finite(_number(_read(pool, &"current", 0.0))) / maximum, 0.0, 1.0)


## The sea's `structural_capacity` — ADR 0071's denominator and the reason the mechanism is
## realm-invariant. Read through `get()` off the injected sea, never off a named type.
func _structural_capacity_of(ctx: AttackContext, tuning: CombatTuning) -> float:
	var state: Variant = _sea_of(ctx, tuning)
	return 0.0 if state == null else _capacity_of(state)


## The sea: the per-hit injection, then this mechanism's bound one, then the target's own
## component bag under the tuning's authored key. Three routes, one answer, and the last is
## the only one that costs nothing from a caller who already built the actor.
func _sea_of(ctx: AttackContext, tuning: CombatTuning) -> Variant:
	var injected: Variant = ctx.data_value(SEA_KEY, null)
	if injected != null:
		return injected
	if sea != null:
		return sea
	var bag: Variant = _read(ctx.target, &"components", null)
	var key := StringName(_text(tuning.sea_component))
	if bag is Dictionary and key != &"":
		var found: Variant = (bag as Dictionary).get(key, null)
		if found != null:
			return found
	return null


## `structural_capacity`, through `get()`. `0.0` is a real answer for a sea nobody trained,
## and the caller then refuses to divide by it rather than producing an infinity.
static func _capacity_of(state: Variant) -> float:
	if state == null:
		return 0.0
	return maxf(0.0, _finite(_number(_read(state, &"structural_capacity", 0.0))))


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
static func _ladder_of(tuning: CombatTuning) -> Array[StringName]:
	var keys: Array[StringName] = []
	if tuning.collapse_capacity_floors is Dictionary:
		for key in (tuning.collapse_capacity_floors as Dictionary).keys():
			keys.append(StringName(key))
	if keys.is_empty():
		return [&"shallow", &"deep", &"vast"]
	var previous: float = -1.0
	for tier in keys:
		var capacity := _capacity_floor_of(tuning, tier)
		if capacity < previous:
			# Authored deepest-first: demote towards the floor rather than towards the top.
			keys.reverse()
			break
		previous = capacity
	return keys


## The `structural_capacity` a demoted sea is reset to, or `0.0` for "leave it alone". A tier
## missing from the authored table is never demoted further.
static func _capacity_floor_of(tuning: CombatTuning, tier: StringName) -> float:
	if not (tuning.collapse_capacity_floors is Dictionary):
		return 0.0
	var value: Variant = (tuning.collapse_capacity_floors as Dictionary).get(String(tier), 0.0)
	return maxf(0.0, _finite(_number(value)))


# --- internals -----------------------------------------------------------------


## The kind for this hit: the per-hit key, then this mechanism's bound field. An ordinal
## outside the enum and an unknown NAME both read `DISRUPT`, never a fourth kind nobody wrote
## a branch for.
func _kind_of(ctx: AttackContext) -> Kind:
	var raw: Variant = ctx.data_value(KIND_KEY, null)
	if raw == null:
		return kind
	if raw is int or raw is float:
		var index := int(raw)
		return (index if index >= 0 and index < Kind.size() else 0) as Kind
	var spelled := _text(raw)
	if spelled == "obscure":
		return Kind.OBSCURE
	if spelled == "attend":
		return Kind.ATTEND
	return Kind.DISRUPT


## The erosion effects for one hit: ONE entry carrying every write, so a panel can never show
## a sea that went turbulent without the clarity it cost.
##
## ## The one `kind` key, and why the strike's kind is NOT it
##
## `DamageProposal.KIND` is `"kind"` and it is the effect's OWN vocabulary -- what the write
## IS. `BodyWounds` and `StatusApply` both put their `EFFECT_KIND` there and put their payload
## under their own keys, and that is the shape this file now follows: `effect_of(EFFECT_KIND)`
## matches, `mitigate` matches, and a reader asks the entry for its turbulence.
##
## This literal originally spelled BOTH `DamageProposal.KIND: EFFECT_KIND` and
## `KEY_KIND: <the strike kind>` -- two constants with the same value in one dictionary, which
## is a duplicate key the parser rejects outright, and semantically two different meanings
## fighting over one field. `KEY_KIND` is therefore the STRIKE kind under its own name,
## `KEY_STRIKE_KIND`, and the id of the write stays under `DamageProposal.KIND`.
func _effects(parts: Dictionary) -> Array[Dictionary]:
	return [
		{
			DamageProposal.KIND: EFFECT_KIND,
			KEY_STRIKE_KIND: String(parts["kind"]),
			KEY_TURBULENCE: _finite(float(parts["turbulence"])),
			KEY_CLARITY: _finite(float(parts["clarity_delta"])),
			KEY_AWARENESS: _finite(float(parts["awareness_delta"])),
		}
	]


## The authored share, falling back to the tuning default when the hit authored none.
func _share_of(ctx: AttackContext, tuning: CombatTuning) -> float:
	var authored := _number(ctx.data_value(SHARE_KEY, 0.0))
	if authored <= 0.0:
		authored = _finite(tuning.default_mind_share)
	return clampf(authored, 0.0, 1.0)


## The tuning for this hit: the per-attack override, the bound one, then the shipped `.tres`.
## Memoised because it is read on every `resolve` and every `mitigate`; a null load falls back
## to a fresh `CombatTuning.new()` whose every bound is `0.0` — a visibly broken balance
## rather than a `NaN` (BRIEF 1.7).
func _tuning_of(ctx: AttackContext) -> CombatTuning:
	var injected: Variant = ctx.data_value(TUNING_KEY, null)
	if injected is CombatTuning:
		return injected as CombatTuning
	if tuning != null:
		return tuning
	if _shipped == null:
		_shipped = CombatTuning.shipped()
	return _shipped if _shipped != null else CombatTuning.new()


## The tuning for a static entry point, which has no context to read a per-attack override
## off. Same three-step order, without the memoisation a per-hit read justifies.
static func _tuning_or(source: CombatTuning) -> CombatTuning:
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
static func _mind_stat(tuning: CombatTuning, suffix: String) -> StringName:
	return StringName(_text(tuning.mind_stat_prefix) + suffix)


## A `ResourcePool` off an `Actor`, by an id read out of DATA. `call()` rather than a typed
## `resource()` so a `Variant` actor of another shape degrades to `null` instead of crashing
## a combat tick.
static func _pool_of(actor: Variant, pool_id: StringName) -> Variant:
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
static func _settle(state: Variant, field: StringName, setter: StringName, amount: Variant) -> void:
	if state == null or not (state is Object):
		return
	var holder := state as Object
	if holder.has_method(setter):
		holder.call(setter, amount)
		return
	_assign(holder, field, amount)


## Write a property only when the object already exposes it. A `set()` on an absent property
## pushes an engine warning and this project treats warnings as errors, so the whole file
## would fail to compile. This is what lets a caller hand over any object carrying the four
## fields the sea is read through and get a graceful degradation instead of a warning storm.
static func _assign(object: Object, key: StringName, amount: Variant) -> void:
	for entry in object.get_property_list():
		if StringName(entry.get("name", &"")) == key:
			object.set(key, amount)
			return


## `Object.get` with a fallback, never `Object._get` — the latter is an engine hook and a
## same-arity declaration collides with it, which fails the whole file to compile and cascades
## into "Could not resolve class" for everything that depends on it.
static func _read(value: Variant, key: StringName, fallback: Variant) -> Variant:
	if value == null or not (value is Object):
		return fallback
	var result: Variant = (value as Object).get(key)
	return result if result != null else fallback


## A rate read out of DATA and clamped into `[0, 1]`. Above `1.0` a "cap" exceeds the thing
## it caps and a defence becomes a liability — holes 3 and 4 in the module docblock.
static func _share(value: Variant) -> float:
	return clampf(_finite(float(value)), 0.0, 1.0) if (value is float or value is int) else 0.0


## Every arithmetic result in this file passes through here. The spine's ONE non-finite guard
## sits at S6's entrance and `maxf(NaN, chip) == NaN`, so a `NaN` produced here would reach
## `ResourcePool.change`, which has no guard of its own.
static func _finite(value: float) -> float:
	return value if is_finite(value) else 0.0


## A `Variant` as a finite float, or `0.0`. A `bool` is deliberately not a number here:
## `true` as a share would silently read `1.0`.
static func _number(value: Variant) -> float:
	if value is float or value is int:
		return _finite(float(value))
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
##   no provider contributes, so `mental_attack`, `mental_defense`, `mind_focus_chance`,
##   `mind_avoidance` and `illusion_resistance` ALL read `0.0` — which is why
##   "defense 0.0 saturates at the cap" could pass with a `0.0` on BOTH sides of the
##   assertion and the `40%` floor check beside it, and the fixture's sea silently stopped
##   being read at all;
## - `apply_deviation` zeroed the bare name `"mind_technique_power"` rather than the id.
##
## The fix is to accept both text types rather than to restate the value at each call site:
## `String()` on either is lossless. `_number` above stays strict on purpose, because a
## `StringName` used as a NUMBER is a genuine defect and not a spelling to paper over.
static func _text(value: Variant) -> String:
	if value is String or value is StringName:
		return String(value)
	return ""


## What a null context answers. Every key present, so a panel rendering [method breakdown]'s
## shape never has to ask whether a key exists.
static func _empty_parts() -> Dictionary:
	return {
		"kind": "disrupt",
		"share": 0.0,
		"mental_attack": 0.0,
		"base": 0.0,
		"mental_defense": 0.0,
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
