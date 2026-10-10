class_name MindDamage
extends DamageMechanism

## Mind damage ERODES THE SEA and never subtracts health (ADR 0071).
##
## ## The formula, verbatim
##
## ```
## base = attacker MENTAL_ATTACK * share
## d    = defender MENTAL_DEFENSE                                  (a MAGNITUDE)
## D    = d / resist_divisor
## D_eff= D * 1 / (1 + max(0, mastery_pen) / pierce_scale)         (bounded in (0, 1])
## K    = defense_divisor_k * base                                 (rides the ATTACKER)
## m    = mitigation_ceiling * D_eff / (K + D_eff)                  for D_eff >= 0
## m    = mitigation_ceiling * (2 - K / (K + |D_eff|))             for D_eff <  0
## if OBSCURE: D_eff = maxf(D_eff, defender ILLUSION_RESISTANCE * ILLUSION_MAGNITUDE_SCALE)
## coh  = 1 - COHERENCE_DAMP * awareness_ratio(defender)     # 1.0 -> 0.5 at full awareness
## g    = base * (1-m) * coh * (FOCUS_MULT if focused else 1.0)
## g   /= defender_sea.structural_capacity                   # a SHARE of THAT sea
## clarity_delta = -TURBULENCE_TO_CLARITY * g                # every kind, floored at 0
## ```
##
## ## ADR 0200: `MENTAL_DEFENSE_CAP` and `ILLUSION_RESISTANCE_CAP` are GONE
##
## Mind was the worst of the three: `clampf(d/(d+base), 0, 0.6)` meant 40% of every mind
## strike landed at ANY `perception` and at ANY realm, forever. The denominator was
## already a ratio — the defect was the CLAMP on it and the `d` that never grew with the
## ladder. Both caps are deleted rather than re-tuned, and mind now reads the same
## `mitigation_ceiling` / `defense_divisor_k` / `pierce_scale` every other mechanism does.
## See the "the floor is now the ASYMPTOTE" section below for what replaced the 40%.
##
## ## `K` is MIND'S OWN, by the owner's ruling
##
## `K = defense_divisor_k * base` where `base` is mind's own offense (`MENTAL_ATTACK *
## share`). `CombatTuning` carries ONE `defense_divisor_k`, and each mechanism multiplies
## it by ITS OWN offense, which is what "per-mechanism" means here: the three mechanisms
## stay independent of one another's balance and a qi rebalance cannot move a mind answer.
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
## ## `structural_capacity` is the denominator, and what it does NOT buy
##
## `MENTAL_ATTACK` is a bounded RATE (`MindProvider`: `(perception*2 + clarity*1.5) *
## RealmRate.factor`). On a stock actor ADR 0183's `_or_core_fall` resolves both base
## attributes to `Stat.WILL`, so production reads `3.5 * will * rate` — the `62.5 ->
## 110.9903` pair this docblock used to quote was a TEST FIXTURE's authored
## `perception 20 / clarity 15`, a value no actor the game builds carries. `sea_capacity`
## is the AUTHORED magnitude: 100.0 -> 825.0 across the 30 `MindRealmSeed` `.tres`, a
## linear ladder of step 25. The rate spans `1.02^29 = 1.775845`.
##
## Dividing by `structural_capacity` makes the erosion a SHARE of that sea and stops the
## DEFENDER's realm leaking into the arithmetic. It does NOT make "one full strike" the
## same share at every realm, because the ATTACKER's own rate is still in the numerator
## against an 8.25x denominator. Over the 30 shipped seeds the share falls strictly at
## every realm, and the DECAY is build-independent: exactly `cap_span / rate_span`
## (`8.25 / 1.775845`) = `4.6457x`. A deep sea therefore takes ~4.6x more strikes to reach
## the same turbulence, so the raw numerator at R30 is the SMALLER share, not a one-hit
## kill.
##
## The share's ABSOLUTE level is a function of the attacker's build, not of the realm: on
## the `test_mind_power_curve` fixture's authored base of `62.5` it reads `0.625` at R1 and
## `0.1345` at R30, and on a stock body `0.35` and `0.0753`. Only the RATIO is a property
## of the ladder, which is why that is the half this docblock claims.
##
## That gradient is UNRULED. ADR 0071 justified this denominator by claiming the share was
## realm-invariant — the claim these numbers refute — so no ADR and no test ever asked for
## the decay. Closing it is a `sea_capacity` re-author, not a rate edit, and it is not this
## file's to make. `test_mind_damage_share_gradient.gd` pins the decay's DIRECTION and its
## rate/magnitude derivation so neither can move without someone ruling on it.
##
## ## The floor is now the ASYMPTOTE, and that is the whole change
##
## This section used to read: "`mental_defense` enters only through the saturating
## `d/(d+base)`, hard-capped at `MENTAL_DEFENSE_CAP`, so **40% of every mind strike always
## lands at any `perception` and at any realm**." Every word of that is still true
## EXCEPT the reason, and the reason was the defect.
##
## The old floor was `1 - MENTAL_DEFENSE_CAP` because the mitigation was CLAMPED at the
## cap: past `d/(d+base) == 0.6` more `mental_defense` bought exactly nothing, so `0.4`
## was a wall rather than a bound. ADR 0200 deletes the clamp, and with it the wall.
## `m = mitigation_ceiling * D/(K + D)` is strictly BELOW `mitigation_ceiling` for every
## finite `D` and strictly RISING in `D`, so:
##
## - **no amount of `mental_defense` reaches immunity** -- `m < mitigation_ceiling` always,
##   so a strike always lands at least `1 - mitigation_ceiling` of itself; and
## - **no amount of `mental_defense` stops paying** -- there is no longer a number past
##   which the stat is dead, which is the half of the old floor that was never a property.
##
## The immunity invariant SURVIVES as a property of the CURVE rather than of an authored
## number, which is a stronger claim than the one it replaces: the old `0.4` was true by
## construction of a constant, and `1 - mitigation_ceiling` is true for every finite pair
## of magnitudes at every realm forever. See [method defense_floor].
##
## This is also the mind analogue of the spine's chip-floor invariant, and it obeys ADR
## 0051's rule that the breakthrough roll must not read a quantity the entry gate already
## pins: clarity can be eroded to zero by a fight, but it can never be protected to zero
## damage by a defence stat.
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
## 1. **`K + |D| == 0` divides by zero.** `m = mitigation_ceiling * D/(K+D)` is
##    `0.0 / 0.0 == NaN` for an unattacked unstatted target and a `NaN` survives every
##    `clampf`. A non-positive denominator reads `0.0` — no contest, never a division, the
##    same degradation `QiDamage._defense_of` gives a `0.0` divisor. (ADR 0200 REPLACED
##    the old `d/(d+base)` hole with this one; the guard is the same and the reason is the
##    same.)
## 2. **`structural_capacity <= 0.0`** divides by zero. A sea nobody trained has no scale, so
##    the erosion reads `0.0` — visibly inert rather than `INF`.
## 3. **(RETIRED) `MENTAL_DEFENSE_CAP > 1`** would have made `(1 - mit)` negative and the
##    mechanism would have SHARPENED the sea it exists to erode. There is no cap on an
##    input any more; what replaced it is `mitigation_ceiling`, which is read clamped to
##    `[0, 1]` for the same sign reason.
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

## The illusion-resistance conversion, as a DOCUMENTED constant rather than a re-tuned cap.
## The full derivation — the unit error this fixes, the measured `4.2e-4`, and why a floor
## would have papered over it — stays beside [method _illusion_resistance_of], which is the
## math that reads this.
const ILLUSION_MAGNITUDE_SCALE := 100.0

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
## so the shared crit channel is simply inert here. Mind crit is `MIND_CLARITY`, and
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
					scaled[key] = MindDamageMath.finite(
						MindDamageMath.number(scaled.get(key, 0.0)) * defence
					)
				carried.append(scaled)
	if carried.is_empty():
		carried = _effects(parts)
	return DamageProposal.new(0.0, carried)


## Every primitive this mechanism computed, for a UI readout (ADR 0038: primitives in a
## `summary()` payload, never an engine object or a module type).
##
## `{kind, share, mental_attack, base, mental_defense, defense, divisor_k, mitigation,
## illusion_resistance, awareness_ratio, coherence, focused, erosion, defence,
## turbulence, clarity_delta, awareness_delta, structural_capacity, subtotal, total,
## sea_bound, rng_bound}`.
##
## `erosion` is what S4 produced and `turbulence` / `clarity_delta` / `awareness_delta` are
## what it costs; `subtotal` and `total` are the erosion after and before the defence, so a
## panel can show the defence line as the difference between two rows rather than recomputing
## it. All of it is pure and side-effect free: both seam stages read this one function, so
## they cannot disagree.
func breakdown(ctx: AttackContext) -> Dictionary:
	if ctx == null:
		return MindDamageMath.empty_parts()
	var tuning := _tuning_of(ctx)
	var resolved := _kind_of(ctx)
	var share := _share_of(ctx, tuning)
	var mental_attack := maxf(
		0.0,
		MindDamageMath.finite(ctx.attacker_value(MindDamageMath.mind_stat(tuning, "mental_attack")))
	)
	var base := MindDamageMath.finite(mental_attack * share)
	var mental_defense := MindDamageMath.finite(
		ctx.target_value(MindDamageMath.mind_stat(tuning, "mental_defense"))
	)
	var defense := _defense_of(ctx, tuning, mental_defense, resolved)
	var divisor_k := maxf(0.0, MindDamageMath.finite(tuning.defense_divisor_k) * base)
	var mitigation := MindDamageMath.mitigation_of(defense, divisor_k, tuning)
	var awareness := _awareness_ratio_of(ctx, tuning)
	var coherence := _coherence_of(ctx, tuning, resolved, awareness)
	var focused := _focus_of(ctx, tuning)
	var capacity := _structural_capacity_of(ctx, tuning)
	# Hole 2: a sea with no scale is NOT an infinite erosion. `0.0` is visibly inert, which
	# is the whole point of `CombatTuning`'s degenerate defaults.
	var erosion := (
		0.0 if capacity <= 0.0 else MindDamageMath.finite(base * coherence * focused / capacity)
	)
	return {
		"kind": kind_name(resolved),
		"share": share,
		"mental_attack": mental_attack,
		"base": base,
		"mental_defense": mental_defense,
		"defense": defense,
		"divisor_k": divisor_k,
		"mitigation": mitigation,
		"illusion_resistance": _illusion_resistance_of(ctx, tuning, resolved),
		"awareness_ratio": awareness,
		"coherence": coherence,
		"focused": focused > 1.0,
		"erosion": erosion,
		"structural_capacity": capacity,
		"subtotal": erosion,
		"total": erosion * clampf(1.0 - mitigation, 0.0, 1.0),
		"turbulence": MindDamageMath.finite(erosion),
		"clarity_delta":
		MindDamageMath.finite(-MindDamageMath.share(tuning.turbulence_to_clarity) * erosion),
		"awareness_delta": _awareness_delta_of(resolved, awareness, erosion),
		"sea_bound": _sea_of(ctx, tuning) != null,
		"rng_bound": ctx.rng != null,
	}


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
	var bound := MindDamageMath.tuning_or(tuning)
	var result := {KEY_HP_LOSS: 0.0, KEY_BLEEDING: false, KEY_STATE_TURBULENCE: 0.0}
	if sea_component == null or actor == null or not (delta > 0.0):
		return result
	# Hole 6. The clamp is `[0, 1)` and not `[0, 1]` for BOTH reasons at once: a threshold
	# at 1.0 is unreachable by construction, and `1.0 - threshold` is this function's only
	# divisor, so an authored `1.0` would be `0.0 / 0.0` on the one tick it must not be.
	var threshold := clampf(MindDamageMath.finite(bound.rupture_threshold), 0.0, 0.999999)
	result[KEY_THRESHOLD] = threshold
	var turbulence: float = clampf(
		MindDamageMath.finite(
			MindDamageMath.number(MindDamageMath.read(sea_component, &"turbulence", 0.0))
		),
		0.0,
		1.0
	)
	result[KEY_STATE_TURBULENCE] = turbulence
	if turbulence <= threshold:
		return result
	var bleed := MindDamageMath.share(bound.rupture_bleed)
	var pool: Variant = MindDamageMath.pool_of(actor, bound.health_pool_id)
	if bleed <= 0.0 or pool == null:
		return result
	var maximum := maxf(
		0.0,
		MindDamageMath.finite(MindDamageMath.number(MindDamageMath.read(pool, &"maximum", 0.0)))
	)
	if maximum <= 0.0:
		return result
	var over := clampf((turbulence - threshold) / (1.0 - threshold), 0.0, 1.0)
	var loss := MindDamageMath.finite(
		maximum * bleed * over * maxf(0.0, MindDamageMath.finite(delta))
	)
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
	var bound := MindDamageMath.tuning_or(tuning)
	var result := {
		KEY_COLLAPSED: false,
		KEY_HELD: maxf(0.0, MindDamageMath.finite(held)),
		KEY_FROM_TIER: "",
		KEY_TO_TIER: "",
		KEY_CAPACITY: 0.0,
		KEY_CLARITY_NOW: 0.0,
		&"deviation": "",
	}
	if sea_component == null or delta <= 0.0:
		return result
	var tier := StringName(MindDamageMath.text(MindDamageMath.read(sea_component, &"tier", &"")))
	result[KEY_FROM_TIER] = String(tier)
	var window := maxf(0.0, MindDamageMath.finite(bound.rupture_collapse_time))
	var turbulence := clampf(
		MindDamageMath.finite(
			MindDamageMath.number(MindDamageMath.read(sea_component, &"turbulence", 0.0))
		),
		0.0,
		1.0
	)
	if window <= 0.0 or turbulence < 1.0:
		result[KEY_HELD] = 0.0
		return result
	var held_now: float = float(result[KEY_HELD]) + maxf(0.0, MindDamageMath.finite(delta))
	result[KEY_HELD] = held_now
	if held_now < window:
		return result
	var ladder := MindDamageMath.ladder_of(bound)
	var index := ladder.find(tier)
	# Hole 8: `vast` is the floor of the ladder and a tier this tuning never heard of has no
	# successor. Neither is demoted, and the timer resets rather than accumulating into a
	# collapse that can never fire.
	if index < 0 or index >= ladder.size() - 1:
		result[KEY_HELD] = 0.0
		return result
	var demoted := ladder[index + 1]
	var capacity := MindDamageMath.capacity_floor_of(bound, demoted)
	MindDamageMath.settle(sea_component, &"tier", &"set_tier", demoted)
	if capacity > 0.0:
		MindDamageMath.settle(
			sea_component, &"structural_capacity", &"set_structural_capacity", capacity
		)
	var clarity := clampf(MindDamageMath.finite(bound.collapse_clarity_floor), 0.0, 1.0)
	MindDamageMath.settle(sea_component, &"clarity", &"set_clarity", clarity)
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
	var bound := MindDamageMath.tuning_or(tuning)
	var zeroed := StringName(MindDamageMath.text(bound.mind_deviation_stat))
	var stats: Variant = MindDamageMath.read(holder, &"stats", null)
	if stats is Object and (stats as Object).has_method(&"derived"):
		var current := MindDamageMath.finite(
			MindDamageMath.number((stats as Object).call(&"derived", zeroed))
		)
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
	var duration := MindDamageMath.finite(bound.collapse_deviation_duration)
	var effect := StatusEffect.new(DEVIATION_STATUS, duration if duration > 0.0 else -1.0)
	if effect == null:
		return &""
	MindDamageMath.assign(effect, &"magnitude", 0.0)
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
##
## ## Why `p_technique` is a THIRD parameter, and why it is the authored share
##
## The authored field on `TechniqueDef` is spelled `element_share` — ONE field on ONE
## content type, set by every authored `.tres` on all three paths (`qi_gale_step.tres`
## `0.5`, `body_crane_dance.tres` `0.35`, `mind_still_water.tres` `0.1`). This file's
## [constant SHARE_KEY] is `&"mind_share"`, and `builder` never wrote it, so every mind
## strike in the game resolved at `CombatTuning.default_mind_share` (`1.0`) and all seven
## authored mind shares were INERT: `mind_still_water.tres` (`0.1`) and
## `mind_prime_autopsy.tres` (`1.0`) were the same blow. That is the key mismatch, and the
## read below is the whole of the fix.
##
## It mirrors `QiDamage.builder` (`qi_damage.gd:236`) exactly, including the `is Object`
## guard and the `get()` spelling, so the two mechanisms read the SAME authored field by
## the SAME shape and cannot drift apart on a technique authored before one of them moved.
## An unauthored share still answers `0.0`, and `_share_of`'s `<= 0.0` rule sends it to the
## tuning default — unchanged, which is why the non-positive `.tres` entries stay legal.
static func builder(
	p_kind: Variant = Kind.DISRUPT, p_sea: Variant = null, p_technique: Variant = null
) -> Callable:
	return func(ctx: AttackContext) -> AttackContext:
		if ctx == null:
			return ctx
		ctx.set_data(KIND_KEY, p_kind)
		if p_sea != null:
			ctx.set_data(SEA_KEY, p_sea)
		if p_technique is Object:
			ctx.set_data(SHARE_KEY, (p_technique as Object).get(&"element_share"))
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


## ADR 0200's `D`: the defender's mind-defense MAGNITUDE, in the same space `K` lives in.
##
## `mental_defense` is put on `resist_divisor`'s scale so `D` and `K` are the same kind of
## number -- the divisor is NOT making `D` a percent, which is the whole difference between
## the two regimes. A non-positive or non-finite divisor reads as `0.0` rather than dividing.
##
## ## The SIGN is preserved, for the glass cannon
##
## `maxf(0.0, ...)` is NOT applied to `mental_defense` here. ADR 0200's mirror branch is
## `m = mitigation_ceiling * (2 - K/(K + |D|))` for `D < 0`, and a defender under a
## composure-sunder debuff must be able to REACH it: a mind strike against one takes
## strictly more than it would against an undefended sea. Clamping at zero here is how a
## glass cannon silently exceeds its own ceiling while every test still passes.
##
## ## `OBSCURE` still reads its OWN stat, and it reads it as a MAGNITUDE
##
## ADR 0071's `maxf` against `ILLUSION_RESISTANCE` is preserved — it is what makes an
## illusion-resistance build and a clarity build DIFFERENT defenders of the same skill, and
## it is the one asymmetry `test_mind_damage.gd` pins most sharply. Both halves of the
## `maxf` are MAGNITUDES on `K`'s scale. `ILLUSION_RESISTANCE_CAP` is gone; nothing is
## re-clamped afterwards, so a deep illusion-resistance build now keeps buying mitigation
## past the point where it used to stop dead.
##
## The conversion that makes the two halves comparable is [constant
## ILLUSION_MAGNITUDE_SCALE], read through [method _illusion_defense_of]. Without it the
## `maxf` compares a `0..0.8` band against a magnitude four orders of magnitude larger and
## simply never selects the illusion half — which is what the measured `0.00042203465127`
## was.
func _defense_of(
	ctx: AttackContext, tuning: CombatTuning, defense: float, kind_value: Kind
) -> float:
	var divisor := MindDamageMath.finite(tuning.resist_divisor)
	var scale := divisor if divisor > 0.0 else 1.0
	var out := MindDamageMath.finite(defense) / scale
	if kind_value == Kind.OBSCURE:
		out = maxf(out, _illusion_defense_of(ctx, tuning, kind_value))
	var pen := maxf(0.0, MindDamageMath.finite(MindDamageMath.penetration_of(ctx)))
	var pierce := MindDamageMath.finite(tuning.pierce_scale)
	if pierce > 0.0:
		out = out / (1.0 + pen / pierce)
	return MindDamageMath.finite(out)


## ## `ILLUSION_RESISTANCE` is NOT a `[0, 1]` percent, and treating it as one is the
## defect ADR 0200's rename left behind
##
## ADR 0200 replaced `ILLUSION_RESISTANCE_CAP` with an unbounded MAGNITUDE, and this file
## divides the stat by `resist_divisor` before the `maxf` so `D` and `K` meet as like
## quantities. It also clamps the read to `[0, 1]`, because the stat's own authored formula
## is `will * 0.006` (ADR 0900) and every value the engine can
## produce is in that band.
##
## Those two facts are inconsistent, and the result is not a rounding drift — it is the
## stat doing nothing. `resist_divisor` is a SINGLE `CombatTuning` field shared by all three
## mechanisms, and qi sizes its `element_defense_<e>` contribution against it at
## `affinity * 0.5 + will * 0.2`, which is `0` at an untrained element and lands near
## `2.5..5.0` on a shipped body. Mind's `ILLUSION_RESISTANCE` at the same stat values lands
## between `0.0` and `0.8`. It is the SAME `100.0` meeting magnitudes that are 4.7x apart in
## their natural ranges.
##
## Measured at the time of that defect on the suite's own fixtures (`mind_damage_fixture.gd`,
## the then-`mental_clarity 200.0` illusion build, `ILLUSION_RESISTANCE == 0.8`):
##
## ```
## base = mental_attack * share = 40.0
## K    = defense_divisor_k * base = 0.45 * 40.0 = 18.0
## D    = illusion_resistance / resist_divisor = 0.8 / 100.0 = 0.008
## m    = 0.95 * 0.008 / (18.0 + 0.008) = 0.0004220346512...
## ```
##
## That is `4.2e-4` of mitigation from the stat that exists for exactly one purpose: to make
## an illusion-resistance build a DIFFERENT defender of `OBSCURE` from a clarity build.
## `ILLUSION_RESISTANCE_CAP` deleted at ADR 0200 had been holding this up by accident — it
## put a flat `0.8` on the mitigation, and 0.8 on the OTHER side of this ratio is
## `0.95 * 0.8/18.8 = 0.0404`, which is also small, but it was a constant rather than a
## near-zero. Restoring a floor instead would have papered over the unit error.
##
## [constant ILLUSION_MAGNITUDE_SCALE] is the fix: a DOCUMENTED CONVERSION constant, not
## a re-tuned cap. It says "one point of `ILLUSION_RESISTANCE` is worth what 100 points of
## authored `element_defense_<e>` are worth on qi" — the same `100.0` the shared
## `resist_divisor` already divides by, so the stat is read in the units its own formula's
## `0.004`-and-`0.002` coefficients imply instead of being divided into irrelevance.
##
## That puts the illusion build's `D` at `100.0` against the same `K = 18.0` the clarity
## half meets, for `m = 0.95 * 100/118 = 0.8042` — a REAL contest, and deliberately a
## strong one. Measured against the suite's own `mental_defense` rows, a `1.0` defense
## reads `0.0431`, `10.0` reads `0.2931` and `1000.0` reads `0.9523`, so a saturated
## illusion-resistance build sits at the strong end of exactly the range a deep
## `mental_defense` build reaches. A weaker conversion would leave `OBSCURE` the worst-
## defended kind in the game against the one defender the game explicitly offers for it,
## which is what `0.00042203465127` was.
##
## The constant is declared with the ids above, where gdlint's definition order puts it.
## It is a named constant rather than an inline literal because a second copy of this
## number is how the unit error would come back, and because it is the ONE thing a balance
## pass would legitimately want to turn: the question "is an illusion build worth as much
## against `OBSCURE` as a clarity build's `mental_defense`" has to have an answer in one
## place ([constant ILLUSION_MAGNITUDE_SCALE]).


## `1 - COHERENCE_DAMP * awareness_ratio`, less whatever a `mind_veil` spend removes.
##
## The DEPLETING reserve is the mind path's first defensive lever and the only term that
## moves with it: a defender who spends awareness to take a mind strike takes the next one
## at nearly double the erosion, so the reserve is a resource to hold rather than a stat to
## stack. At the shipped `0.5` a full reserve halves the incoming coherence and an empty one
## does not.
##
## `mind_veil`'s spend removes exactly `COHERENCE_DAMP` of the coherence, which at the
## shipped `0.5` is half of it — deliberately different from a crit, which SPENDS
## `FOCUS_MULT`. Avoidance is a STEADIER, not a refusal, so it can be as cheap as a half and
## can never become a second miss channel the way an `EVASION` stat could. `ATTEND` is
## excluded: it spends the reserve the coherence is computed FROM, and refunding one for the
## other would double-dip the same stat.
func _coherence_of(
	ctx: AttackContext, tuning: CombatTuning, kind_value: Kind, awareness: float
) -> float:
	var damp := MindDamageMath.share(tuning.coherence_damp)
	var coherence := clampf(1.0 - damp * clampf(awareness, 0.0, 1.0), 0.0, 1.0)
	var refund := _avoidance_of(ctx, tuning, kind_value)
	return clampf(maxf(coherence, refund), 0.0, 1.0)


## `FOCUS_MULT` when the `mind_clarity` roll came up, `1.0` otherwise.
##
## The ONLY consumer of `MIND_CLARITY` in the engine. One draw on `ctx.rng`, the ADR
## 0067 determinism rule: a null `rng` spends NO draw and answers `1.0`, because a
## deterministic caller is asking for the one answer that consults no randomness and a
## silent `randf()` fallback would make the same hit replay differently.
##
## ## ADR 0215. The id it reads, and why it is a MAGNITUDE now
## The stat was `mind_focus_chance` and is `mind_clarity`: the contest finally has a
## name for both halves (`mind_clarity` attacks, `mind_veil` hides), which is what ADR
## 0215 renamed it for. The `clampf` below is the SHAPE this read has always had -- a
## `[0, 1]` fraction a roll compares against -- and ADR 0215's `minf(0.75, …)` was
## deleted at the PUBLISH end (`MindProvider`), not here. The clamp is therefore NOT a
## cap on the stat and must not be read as one: an unbounded `mind_clarity` reads `1.0`
## through it, which is a fully invested attacker critting every mind strike it lands.
func _focus_of(ctx: AttackContext, tuning: CombatTuning) -> float:
	# Hole 5: a multiplier below 1.0 would make a crit a WEAKER strike, so the read floor is
	# 1.0 rather than a clamp at 0.0 -- the neutral is 1.0 and the dial only ever adds.
	var mult := maxf(1.0, MindDamageMath.finite(tuning.focus_mult))
	if ctx.rng == null:
		return 1.0
	var chance := clampf(
		MindDamageMath.finite(ctx.attacker_value(MindDamageMath.mind_stat(tuning, "mind_clarity"))),
		0.0,
		1.0
	)
	if chance <= 0.0:
		return 1.0
	return mult if ctx.rng.randf() < chance else 1.0


## Whether the defender's `mind_veil` roll came up, as the coherence share it is worth.
## The twin of [method _focus_of] on the other side of the exchange, and it shares that
## function's null-`rng` rule: no generator, no draw, no answer.
##
## ## ADR 0215. Same rename, same reason the clamp is a shape and not a cap
## `mind_avoidance` is `mind_veil`, and its `minf(0.6, …)` is deleted at the publish end.
## `MindDamageMath.share(tuning.coherence_damp)` — not the stat itself — is what this roll
## is worth, so an unbounded `mind_veil` buys a MORE reliable spend of the reserve rather
## than a bigger one; the ceiling that bounded the RELIABILITY is the thing ADR 0215 removed.
func _avoidance_of(ctx: AttackContext, tuning: CombatTuning, kind_value: Kind) -> float:
	if kind_value == Kind.ATTEND or ctx.rng == null:
		return 0.0
	var chance := clampf(
		MindDamageMath.finite(ctx.target_value(MindDamageMath.mind_stat(tuning, "mind_veil"))),
		0.0,
		1.0
	)
	if chance <= 0.0 or ctx.rng.randf() >= chance:
		return 0.0
	return MindDamageMath.share(tuning.coherence_damp)


## The defender's `ILLUSION_RESISTANCE`, read ONLY for `OBSCURE` -- every other kind
## answers `0.0`, which is what makes "an illusion-resistance build and a
## clarity-resistance build are different defenders of the same skill" machine-checkable
## rather than asserted.
##
## ADR 0071's `minf(0.8, ...)` ceiling is kept on the READ, because that is the stat's own
## authored shape rather than a clamp this module imposes: `ILLUSION_RESISTANCE_CAP` was
## deleted, and it was a ceiling on the MITIGATION, which is a different quantity. The
## ceiling that would have belonged here -- one on the value rather than on what it buys --
## is [constant ILLUSION_MAGNITUDE_SCALE]'s job, and it lives in
## [method _defense_of] where the unit is converted.
func _illusion_resistance_of(ctx: AttackContext, tuning: CombatTuning, kind_value: Kind) -> float:
	if kind_value != Kind.OBSCURE:
		return 0.0
	var id := MindDamageMath.mind_stat(tuning, "illusion_resistance")
	return clampf(MindDamageMath.finite(ctx.target_value(id)), 0.0, 1.0)


## The `ILLUSION_RESISTANCE` term of [method _defense_of]'s `maxf`, already on `D`'s scale.
##
## `D` is in "points of defense" — the space `mental_defense / resist_divisor` lives in — so
## this is the stat multiplied straight into that space and NOT divided again. Dividing it
## by `resist_divisor` a second time is what read `0.00042203465127`: the conversion
## constant already carries the whole factor, and the divisor would have applied it twice.
##
## This is the ONLY place the conversion happens, which is what keeps `_defense_of` readable:
## it takes two `D`-scale numbers and takes their maximum, and the fact that one of them
## arrived from a `[0, 1]` band is a fact about that stat, not about the defence contest.
##
## Deliberately NOT a floor, and deliberately NOT a re-clamp after the conversion: a floor
## would guarantee OBSCURE a mitigation it had not earned from the defence the defender
## actually built, and a re-clamp would reintroduce the dead-stat shape ADR 0200 deletes.
## Unbounded `ILLUSION_RESISTANCE` keeps buying mitigation, which is the property the
## deleted cap destroyed.
func _illusion_defense_of(ctx: AttackContext, tuning: CombatTuning, kind_value: Kind) -> float:
	return ILLUSION_MAGNITUDE_SCALE * _illusion_resistance_of(ctx, tuning, kind_value)


## The AWARENESS an `ATTEND` strike drains: the erosion itself, spent out of the reserve.
##
## Dimensional by construction — `erosion` is a `0..1`-ish SHARE of the sea and awareness is
## read as a `0..1` fraction — and clamped to what is actually held, so a strike can empty the
## reserve and can never invent a negative one. A target with no reserve at all answers `0.0`,
## which is the same degradation every other absent read on this file gives.
##
## It stays here rather than in [MindDamageMath] with the other readings: its subject is this
## mechanism's own `Kind` vocabulary, and a helper that names an enum declared in the file it
## left is a class cycle rather than a split.
func _awareness_delta_of(kind_value: Kind, awareness: float, erosion: float) -> float:
	if kind_value != Kind.ATTEND or erosion <= 0.0:
		return 0.0
	return -clampf(awareness * clampf(erosion, 0.0, 1.0), 0.0, 1.0)


## The defender's AWARENESS as a `0..1` fraction, through `Actor.resource`'s own table and
## the `awareness_pool_id` authored on `CombatTuning`. An empty reserve reads `0.0` — the
## WORST coherence — which is the honest answer for a target with no awareness at all rather
## than a fabricated full one.
func _awareness_ratio_of(ctx: AttackContext, tuning: CombatTuning) -> float:
	var pool: Variant = MindDamageMath.pool_of(ctx.target, tuning.awareness_pool_id)
	if pool == null:
		return 0.0
	var maximum := MindDamageMath.finite(
		MindDamageMath.number(MindDamageMath.read(pool, &"maximum", 0.0))
	)
	if maximum <= 0.0:
		return 0.0
	return clampf(
		(
			MindDamageMath.finite(MindDamageMath.number(MindDamageMath.read(pool, &"current", 0.0)))
			/ maximum
		),
		0.0,
		1.0
	)


## The sea's `structural_capacity` — ADR 0071's denominator, and the reason the erosion is
## a share of THAT sea rather than an absolute. Read through `get()` off the injected sea,
## never off a named type.
##
## It removes the DEFENDER's realm from the arithmetic and nothing more; the attacker's own
## realm rate is still in the numerator, so the share is NOT realm-invariant. See the
## module docblock for the measured `4.6457x` decay that follows from the two ladders.
func _structural_capacity_of(ctx: AttackContext, tuning: CombatTuning) -> float:
	var state: Variant = _sea_of(ctx, tuning)
	return 0.0 if state == null else MindDamageMath.capacity_of(state)


## The sea: the per-hit injection, then this mechanism's bound one, then the target's own
## component bag under the tuning's authored key. Three routes, one answer, and the last is
## the only one that costs nothing from a caller who already built the actor.
func _sea_of(ctx: AttackContext, tuning: CombatTuning) -> Variant:
	var injected: Variant = ctx.data_value(SEA_KEY, null)
	if injected != null:
		return injected
	if sea != null:
		return sea
	var bag: Variant = MindDamageMath.read(ctx.target, &"components", null)
	var key := StringName(MindDamageMath.text(tuning.sea_component))
	if bag is Dictionary and key != &"":
		var found: Variant = (bag as Dictionary).get(key, null)
		if found != null:
			return found
	return null


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
	var spelled := MindDamageMath.text(raw)
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
			KEY_TURBULENCE: MindDamageMath.finite(float(parts["turbulence"])),
			KEY_CLARITY: MindDamageMath.finite(float(parts["clarity_delta"])),
			KEY_AWARENESS: MindDamageMath.finite(float(parts["awareness_delta"])),
		}
	]


## The authored share, falling back to the tuning default when the hit authored none.
func _share_of(ctx: AttackContext, tuning: CombatTuning) -> float:
	var authored := MindDamageMath.number(ctx.data_value(SHARE_KEY, 0.0))
	if authored <= 0.0:
		authored = MindDamageMath.finite(tuning.default_mind_share)
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
