class_name QiDamage
extends DamageMechanism

## Qi damage is an ELEMENTAL SHARE, never a blended payload (ADR 0069).
##
## ## The formula, verbatim
##
## ```
## share    = technique.element_share, or the tuning default, if the element is valid; else 0
## m_e      = magnitude * share              (elemental share)
## m_0      = magnitude * (1 - share)        (raw share -- THIS IS THE FLOOR)
## a_0      = attacker ATTACK_SPIRITUAL
## a_e      = attacker element_power_<e>
## D        = defender element_defense_<e> / resist_divisor      (a MAGNITUDE, not a percent)
## D_eff    = D * 1 / (1 + max(0, mastery_pen) / pierce_scale)   (bounded in (0, 1])
## K        = defense_divisor_k * a_e        (scales with the ATTACKER)
## m_rate   = mitigation_ceiling * D_eff / (K + D_eff)   for D_eff >= 0   -- NEVER a clamp
## m_rate   = mitigation_ceiling * (2 - K / (K + |D_eff|))   for D_eff < 0  (the mirror)
## mit      = 1 - m_rate
## match    = rules.multiplier(attacker_element, defender_element)
## t_e      = m_e * a_e * match * mit
## t_0      = m_0 * a_0
## total    = (t_0 + t_e) * (1 - clampf(defender DAMAGE_REDUCTION, 0, CAP))
## ```
##
## ## `mitigation_ceiling` is a MULTIPLIER, and that is the load-bearing word
##
## `mitigation_ceiling * D/(K+D)` approaches `0.95` and NEVER reaches it, so every further
## point of `element_defense_<e>` still raises the mitigation. The shape this replaced --
## `clampf(D/divisor - pen, 0, RESIST_CAP)` -- is the same dead stat one number higher: at
## the cap the defender is finished, and the cap was `RESIST_CAP = 0.75` at every realm
## while the attacker's power rode a 551x ladder. So `RESIST_CAP` is deleted rather than
## re-tuned, and `minf(0.95, D/(K+D))` must never be reintroduced here.
##
## ## NEGATIVE defense MIRRORS rather than clamping
##
## `mitigation_ceiling * (2 - K/(K + |D|))` for `D < 0`. Both branches give exactly
## `mitigation_ceiling` at `D == 0`, so the function is CONTINUOUS there, and `m` rises
## above the ceiling as `D` goes negative: a body cultivator under a defence debuff is a
## genuine GLASS CANNON and deals MORE than an undefended one. Omitting this branch is how
## a glass cannon silently exceeds its own ceiling while every test still passes.
##
## ## PENETRATION is a bounded reciprocal ON `D`, never a subtraction from the damage
##
## `D * 1/(1 + pen/pierce_scale)` is in `(0, 1]`, so penetration can push defense
## arbitrarily close to zero and can never grant NEGATIVE defense -- which would be a
## second damage source wearing a defender's name. The old form subtracted penetration
## from the RESISTANCE, and `body_damage.gd` subtracted it from the GROSS; the ADR says
## the second is dimensionally wrong, because penetration is a share of a defender's armor
## and not hit points off a blow.
##
## ## `match` sits BETWEEN the elemental magnitude and mitigation
##
## Mitigation is applied to the elemental term AFTER the matchup has been read, so
## a defender with deep `element_defense_<e>` is a hard counter even to a `STRONG` 1.5.
## That is the anti-"fire is always strong" property: the rule scales the ATTACKER's
## element, and the defender's build answers it. Two rejections, from the ADR:
##
## - Applying the matchup to the WHOLE sum guts `m_0` and punishes a realm-scaled
##   magnitude with a vocabulary rule. `tests/modules/combat_engine/test_qi_damage.gd`
##   asserts the raw term is byte-identical across two different attacker elements,
##   which fails the moment anything but `t_e` is multiplied by the matchup.
## - Applying a matchup AFTER mitigation as a factor on the total re-flattens
##   per-target variance: `0.5 * 0.25 = 1.5 * 0.75 = 0.375`, so a `WEAK` against a
##   shielded target would tie a `STRONG` against an open one. Here the matchup is a
##   factor of `t_e` alone and the mitigation is the factor of the SUM, which is the
##   only arrangement in which those two answers can differ.
##
## ## Resistance applies to the ELEMENTAL TERM ONLY
##
## `t_0` IS the floor. There is no separate floor constant, and a wrong element is a
## WEAKER hit, never a null one — the inverse of body's premise (ADR 0070), and the
## reason `ElementRules.NOURISH = 0.75` "qi always does something" survives being a
## rule the defender can also be on the losing end of.
##
## ## One element per attack, machine-checkable
##
## There is no list anywhere in this file. `ctx.data` carries ONE `element` id and
## ONE `element_share`; a payload carrying an `Array` under the element key is not
## read as a blend at all, it degrades to the raw-only hit. A blend has no code path,
## which is the cheapest possible form of "rejected".
##
## ## `ElementRules` is INJECTED, and this module has NO `elements` edge
##
## The rules arrive on `ctx.data` (see [method builder]) or through the `rules` field
## set at bind time, and are used through their OWN methods: this file names no class
## of the `elements` module at all -- not `ElementRules`, not `ElementStats` -- so
## `tools/arch/registry.json` keeps `combat_engine` at `["contracts", "core"]` and the
## registry does not have to lie about an edge that exists only in prose. The
## `element_power_` / `element_defense_` id PREFIXES are authored on `CombatTuning`
## (BRIEF 1.7: tuning in DATA), which is the one honest way to name another module's
## stat ids without naming its types.
##
## ## Degrade, never throw
##
## A null `rules`, an unknown element, a defender nobody attached the element provider
## to, an unattached attacker, a null context and a NaN magnitude all return a number.
## The spine's ONE non-finite guard is at S6's entrance and `maxf(NaN, chip) == NaN`,
## so this file refuses to produce a non-finite number in the first place: every
## arithmetic result passes through [method _finite] and every factor is clamped into
## `[0, 1]`.
##
## ## The holes the ADR's own arithmetic leaves, and what is done about them
##
## Five, all in [method breakdown] / [method _defense_of] / [method _mitigation_of],
## each closed without inventing a new constant and each asserted in this module's suite.
## ADR 0200 REPLACED hole 2 outright, and the replacement introduces one of its own:
##
## 1. **`resist_divisor == 0` divides by zero.** A bare `CombatTuning.new()` (or an
##    author who forgot the `.tres`) would read `0.0 / 0.0 == NaN` and NaN survives
##    every clamp. A non-positive or non-finite divisor means the contest has no
##    scale, so the defense MAGNITUDE reads 0.0 — the same shape `CombatBand.rate` gives
##    a null tuning.
## 2. **(RETIRED) `RESIST_CAP > 1` made the amount NEGATIVE.** ADR 0200 deletes
##    `RESIST_CAP`; there is no cap on an input to be greedy about. What replaces it is
##    `mitigation_ceiling` above `1.0`, which is read clamped to `[0, 1]` — a mitigation
##    above 100% has no meaning and `mit = 1 - m` would go negative, the elemental term
##    with it, and S9's single sign flip would spend it as a HEAL.
## 3. **`DAMAGE_REDUCTION_CAP > 1` does the same to the total.** Clamped the same way.
## 4. **`element_share` out of `[0, 1]`** makes `m_0` negative. Clamped. `NaN` in the
##    authored share fails the `<= 0.0` test an ordinary comparison would reject, so it
##    is caught by [method _finite] first and falls back to the tuning default.
## 5. **`K + D == 0` divides by zero** — the new denominator. `K` is non-negative and
##    `|D|` is taken on the mirror branch, so the only way to reach it is a `0.0`
##    offense against a `0.0` defense, i.e. no contest at all. It reads `0.0`
##    mitigation, which is "nothing is mitigated", rather than dividing.
##
## One thing this file does NOT fix, because fixing it would need a decision the ADR
## has not made: at `element_share == 1.0` there is no raw share left, so an attacker
## with zero affinity for the one element they authored deals a hit the S8 chip floor
## alone rescues. `t_0` is the floor, and at share 1.0 the floor is zero -- inventing a
## second floor constant is exactly what ADR 0069 forbids.

## `ctx.data` key carrying the injected `ElementRules`. Read through the rules' own
## `multiplier` / `ids` / `has` methods, never through a typed reference.
const ELEMENT_RULES_KEY := &"element_rules"
## `ctx.data` key carrying the attacking technique's ONE element id.
const ELEMENT_KEY := &"element"
## `ctx.data` key carrying `TechniqueDef.element_share`; `0` means "use the tuning's
## default", so a technique that never authored one is not pinned to a hard-coded
## share here.
const ELEMENT_SHARE_KEY := &"element_share"
## `ctx.data` key naming the DEFENDER's element. Optional: without it the defender's
## dominant affinity among the injected rules' elements is used, and an actor with no
## affinity at all is `NEUTRAL` to everything rather than undefined.
const DEFENDER_ELEMENT_KEY := &"defender_element"
## `ctx.data` key overriding the tuning for one attack. `CombatTuning` is this
## module's own type, so it is named here and nowhere else in the mechanism.
const TUNING_KEY := &"tuning"
## The matchup of an attack whose element or defender's element is unknown. Read
## straight out of `ElementRules.multiplier`'s own vocabulary -- `NEUTRAL` is 1.0 there
## too -- so an unreadable matchup is the same number as a real neutral one rather
## than a second invented constant.
const NEUTRAL := 1.0

static var _shipped: CombatTuning = null

## The tuning this mechanism reads, when a caller binds one. Null means "resolve the
## per-attack override, then [method CombatTuning.shipped]".
var tuning: CombatTuning = null
## The injected `ElementRules`, when a caller binds one. Held as a `Variant` and used
## only through its own methods: see the module docblock for why this file names no
## class of the `elements` module.
var rules: Variant = null


## S4. The elemental and raw terms, before any reduction.
##
## `ctx.magnitude` is S1's OUTPUT (ADR 0067), so the rate gate has already been
## applied by the time this reads it, and `ctx.crit` is deliberately NOT read: crit
## multiplies what this produced at S6 and is never one of its terms, which is what
## stops three mechanisms disagreeing about a shared stat.
func resolve(ctx: AttackContext) -> DamageProposal:
	return DamageProposal.new(float(breakdown(ctx)["subtotal"]))


## S5. This path's own mitigation: the defender's flat `Stat.DAMAGE_REDUCTION`, applied
## to the whole amount (ADR 0067 splits S4 and S5 for exactly this reason).
##
## The defender's ELEMENTAL resistance is NOT applied here: it is part of the
## mechanism's own `resolve`, because it applies to `t_e` alone and not to `t_0`.
## Reads the amount off the proposal through `get()` and returns a FRESH one, so a
## caller's proposal is never edited in place and a proposal of another shape is
## handled instead of crashed on.
func mitigate(ctx: AttackContext, proposal: DamageProposal) -> DamageProposal:
	var mitigated := _finite(_amount_of(proposal) * float(breakdown(ctx)["mitigated"]))
	return DamageProposal.new(mitigated)


## Every primitive this mechanism computed, for a UI readout (ADR 0038: primitives in
## a `summary()` payload, never an engine object or a module type).
##
## `{element, share, magnitude, raw, elemental_power, matchup, defender_element,
## defense, defense_effective, divisor_k, mitigation_rate, penetration, mitigation,
## raw_term, elemental_term, subtotal, damage_reduction, mitigated, total, rules_bound}`.
##
## `resistance` is GONE and is not spelled by a second key: it named a PERCENT, and the
## percent is now an OUTPUT of the ratio. `defense` is `D`, `defense_effective` is `D_eff`
## after penetration, `divisor_k` is `K` and `mitigation_rate` is `m` — so a panel can
## show which of the four moved rather than only the difference between two rows.
##
## `subtotal` is what S4 returned and `total` is what S5 returned, so a panel can show
## the reduction line as the difference between two rows rather than recomputing it.
## Total, cheap, and free of side effects: `resolve` and `mitigate` both call it and
## the arithmetic is pure, so the two calls cannot disagree.
func breakdown(ctx: AttackContext) -> Dictionary:
	if ctx == null:
		return _empty_parts()
	var tuning := _tuning_of(ctx)
	var element := _element_of(ctx)
	var share := 0.0 if element == &"" else _share_of(ctx, tuning)
	var magnitude := maxf(0.0, _finite(ctx.magnitude))
	var matchup := _matchup_of(ctx, element)
	var raw_attack := _finite(ctx.attacker_value(Stat.ATTACK_SPIRITUAL))
	var elemental_power := _element_power_of(ctx, tuning, element)
	var defense := _defense_of(ctx, tuning, element)
	var defense_effective := _pierced_defense(defense, _penetration_of(ctx), tuning)
	var divisor_k := maxf(0.0, _finite(tuning.defense_divisor_k) * elemental_power)
	var mitigation_rate := _mitigation_of(defense_effective, divisor_k, tuning)
	# Clamped to [0, 1]: a `mitigation_ceiling` above 1.0 would make `mitigation` negative
	# and the elemental term with it, and S9's one sign flip would spend that as a heal.
	# The CEILING is clamped; the CURVE is not, and `mitigation_rate` above is the
	# unclamped reading a panel or a test asserts against.
	var mitigation := clampf(1.0 - mitigation_rate, 0.0, 1.0)
	var penetration := _penetration_of(ctx)
	var reduction := clampf(_finite(ctx.target_value(Stat.DAMAGE_REDUCTION)), 0.0, 1.0)
	var cap := clampf(_finite(tuning.damage_reduction_cap), 0.0, 1.0)
	var mitigated := clampf(1.0 - minf(reduction, cap), 0.0, 1.0)
	# `t_0` takes NEITHER the matchup NOR the defense NOR the reduction's own
	# element lever: it is the floor, and ADR 0069's whole rejection of a separate
	# floor constant is that there is nothing below it to be pushed under.
	var raw_term := _finite(magnitude * (1.0 - share) * raw_attack)
	var elemental_term := _finite(magnitude * share * elemental_power * matchup * mitigation)
	var subtotal := maxf(0.0, raw_term + elemental_term)
	return {
		"element": String(element),
		"share": share,
		"magnitude": magnitude,
		"raw": _finite(magnitude * (1.0 - share)),
		"elemental_power": elemental_power,
		"matchup": matchup,
		"defender_element": String(_defender_element_of(ctx)),
		"defense": defense,
		"defense_effective": defense_effective,
		"divisor_k": divisor_k,
		"mitigation_rate": mitigation_rate,
		"penetration": penetration,
		"mitigation": mitigation,
		"raw_attack": raw_attack,
		"raw_term": raw_term,
		"elemental_term": elemental_term,
		"subtotal": subtotal,
		"damage_reduction": minf(reduction, cap),
		"mitigated": mitigated,
		"total": maxf(0.0, subtotal * mitigated),
		"rules_bound": _rules_of(ctx) != null,
	}


## A `ctx_builder` for `CombatSpine.resolve_hit`: carries this mechanism's four inputs
## through the ONE context, so the spine needs no sixth stage and no knowledge of what
## a qi hit is (ADR 0067).
##
## All three objects are `Variant` and are read through `get()`, because a caller in
## another module may hand over its own authored content type and this file must not
## acquire a compile-time edge to it:
##
## ```
## CombatSpine.resolve_hit(attacker, target, technique, tuning, rng,
##     QiDamage.builder(ElementsApi.default_rules(), technique, boss_element))
## ```
##
## `p_defender_element` is optional and is the one input a caller usually cannot know
## before the hit: omit it and the defender's dominant affinity is read instead.
static func builder(
	p_rules: Variant = null, p_technique: Variant = null, p_defender_element: StringName = &""
) -> Callable:
	return func(ctx: AttackContext) -> AttackContext:
		if ctx == null:
			return ctx
		if p_rules != null:
			ctx.set_data(ELEMENT_RULES_KEY, p_rules)
		if p_technique is Object:
			ctx.set_data(ELEMENT_KEY, (p_technique as Object).get(&"element"))
			ctx.set_data(ELEMENT_SHARE_KEY, (p_technique as Object).get(&"element_share"))
		if p_defender_element != &"":
			ctx.set_data(DEFENDER_ELEMENT_KEY, p_defender_element)
		return ctx


# --- internals -----------------------------------------------------------------


## The rules for this hit: the per-attack override, then the bound one. Null is a
## supported state, not a failure -- see [method _matchup_of].
func _rules_of(ctx: AttackContext) -> Variant:
	var injected: Variant = ctx.data_value(ELEMENT_RULES_KEY, null)
	if injected != null:
		return injected
	return rules


## The tuning for this hit: the per-attack override, the bound one, then the shipped
## `.tres`. Memoised because it is read on every `resolve` and every `mitigate`; a
## null load falls back to a fresh `CombatTuning.new()`, whose every bound is `0.0` --
## a visibly broken balance rather than a NaN (BRIEF 1.7).
func _tuning_of(ctx: AttackContext) -> CombatTuning:
	var injected: Variant = ctx.data_value(TUNING_KEY, null)
	if injected is CombatTuning:
		return injected as CombatTuning
	if tuning != null:
		return tuning
	if _shipped == null:
		_shipped = CombatTuning.shipped()
	return _shipped if _shipped != null else CombatTuning.new()


## The ONE element this attack carries, or `&""`. A non-id value (an `Array`, which is
## how a hybrid payload would arrive) is not an element, so a blend degrades to the
## raw-only hit instead of being silently averaged into one.
##
## With no rules injected the element is trusted as authored, because there is no table
## to validate it against; with rules, an id the table does not know is not an element.
func _element_of(ctx: AttackContext) -> StringName:
	var raw: Variant = ctx.data_value(ELEMENT_KEY, null)
	var candidate: StringName = raw if raw is StringName or raw is String else &""
	if candidate == &"":
		return &""
	var table: Variant = _rules_of(ctx)
	if table == null:
		return candidate
	return candidate if _has_element(table, candidate) else &""


## `element_share`, or the tuning's default when the technique authored none. `0` means
## "use the default" (ADR 0069), and so does anything non-positive: a share outside
## `[0, 1]` is an authoring error and the raw share's sign is checked here rather than
## left to produce a negative floor.
func _share_of(ctx: AttackContext, tuning: CombatTuning) -> float:
	var authored := _number(ctx.data_value(ELEMENT_SHARE_KEY, 0.0))
	if authored <= 0.0:
		authored = _finite(tuning.default_element_share)
	return clampf(authored, 0.0, 1.0)


## `rules.multiplier(attacker_element, defender_element)`, or `NEUTRAL` when either
## side is unknown or the rules are not injected. Never a second invented table: a
## rules object that does not answer `multiplier` is unreadable, not absent, and the
## unreadable answer is the neutral one.
func _matchup_of(ctx: AttackContext, element: StringName) -> float:
	if element == &"":
		return NEUTRAL
	var table: Variant = _rules_of(ctx)
	if table == null or not (table is Object) or not (table as Object).has_method(&"multiplier"):
		return NEUTRAL
	var defender := _defender_element_of(ctx)
	if defender == &"":
		return NEUTRAL
	var value: Variant = (table as Object).call(&"multiplier", element, defender)
	return maxf(0.0, _number(value)) if value is float or value is int else NEUTRAL


## The defender's element: the authored id when one was handed in, else the element
## their highest affinity is in. Candidates are walked in SORTED order so a tie is
## broken by id rather than by whatever order a `Dictionary` happens to enumerate --
## a matchup that changed between two identical runs would be a defect nobody can
## reproduce. No affinity at all is `&""`, which reads `NEUTRAL`.
func _defender_element_of(ctx: AttackContext) -> StringName:
	var explicit: Variant = ctx.data_value(DEFENDER_ELEMENT_KEY, null)
	var authored: StringName = explicit if explicit is StringName or explicit is String else &""
	if authored != &"":
		var table: Variant = _rules_of(ctx)
		return authored if table == null or _has_element(table, authored) else &""
	var table: Variant = _rules_of(ctx)
	if table == null or not (table is Object) or not (table as Object).has_method(&"ids"):
		return &""
	var listed: Variant = (table as Object).call(&"ids")
	if not (listed is Array):
		return &""
	var ids: Array[StringName] = []
	for entry in listed as Array:
		ids.append(StringName(entry))
	ids.sort()
	var best := &""
	var best_affinity := 0.0
	for candidate in ids:
		var affinity := _finite(ctx.target.affinity(candidate)) if ctx.target != null else 0.0
		if affinity > best_affinity:
			best_affinity = affinity
			best = candidate
	return best


## ADR 0200's `D`: the defender's authored `element_defense_<e>`, a MAGNITUDE in points
## rather than the `[0, 1]` PERCENT this used to read.
##
## It is divided by `CombatTuning.resist_divisor` only to share a magnitude space with the
## attacker's `element_power_<e>` — NOT to become a fraction, and that is the whole
## difference between the two regimes. A constant divisor meeting two growing numbers is
## the defect that made mitigation collapse to zero at depth; here `D` only ever meets a
## `K` that rides the attacker's own ladder, so the mitigated FRACTION is scale-invariant.
##
## A non-positive or non-finite divisor reads as `0.0` rather than dividing — hole 1 in
## the module docblock.
##
## The SIGN is preserved deliberately. `ElementProvider` publishes `maxf(0.0, ...)` so no
## shipped actor carries a negative today, but a defence DEBUFF is the case ADR 0200 names
## and a `maxf(0.0, ...)` here would erase it before the mirror branch ever saw it.
func _defense_of(ctx: AttackContext, tuning: CombatTuning, element: StringName) -> float:
	if element == &"":
		return 0.0
	var divisor := _finite(tuning.resist_divisor)
	if divisor <= 0.0:
		return 0.0
	return _finite(ctx.target_value(_suffixed(tuning.resist_resistance_prefix, element))) / divisor


## ADR 0200's penetration, as a bounded reciprocal ON THE DEFENSE VALUE:
## `D_eff = D * 1 / (1 + max(0, pen) / pierce_scale)`.
##
## ## Why this and not a subtraction from the DAMAGE
##
## `body_damage.gd` used to subtract penetration from the gross, which ADR 0200 calls out
## by name as dimensionally wrong: penetration is a share of a defender's ARMOUR, so
## subtracting hit points off a blow made a deep defender's penetration scale with how
## hard they were hit rather than with how well they were guarded. Here it scales the
## DEFENSE, which is the quantity it means.
##
## ## Why it can never go NEGATIVE
##
## The reciprocal is in `(0, 1]` for every finite `pen >= 0`, so `D_eff` keeps `D`'s sign
## and shrinks toward zero WITHOUT crossing it — bounded, as the ADR requires, and never a
## second damage source wearing a defender's name.
##
## It is read from `CombatStats.PENETRATION`, the combat-owned channel ADR 0068 defines as
## exactly this lever ("how hard the attacker cuts the defender's guard, a read-only input
## to a mechanism's mitigate"). A non-positive or non-finite `pierce_scale` reads as
## "penetration does nothing", never as a division.
static func _pierced_defense(defense: float, penetration: float, tuning: CombatTuning) -> float:
	var scale := _finite(tuning.pierce_scale)
	if scale <= 0.0:
		return defense
	var pen := maxf(0.0, _finite(penetration))
	return _finite(defense / (1.0 + pen / scale))


## ADR 0200's mitigation curve:
##
## ```
## m = mitigation_ceiling * D / (K + D)                 for D >= 0
## m = mitigation_ceiling * (2 - K / (K + |D|))        for D <  0
## ```
##
## Three properties, each load-bearing and each asserted BY MEASUREMENT rather than by a
## value check:
##
## 1. **Scale-invariant.** `K = defense_divisor_k * offense` grows with the ATTACKER, so
##    doubling offense and defense together doubles `K` and leaves the mitigated FRACTION
##    unchanged. A constant divisor meeting two growing numbers cannot do this.
## 2. **Asymptotic, and the ceiling is a MULTIPLIER not a clamp.** `m` approaches
##    `mitigation_ceiling` and never reaches it, so every further point of defense still
##    pays. `minf(ceiling, D/(K+D))` would be the same dead stat one number higher, which
##    is the precise failure ADR 0200 exists to remove.
## 3. **The mirror branch is what makes a glass cannon work.** For `D < 0` the curve goes
##    ABOVE the ceiling and `mit = 1 - m` goes negative, so a defender under a defence
##    debuff takes strictly MORE than an undefended one. Both branches give exactly
##    `mitigation_ceiling` at `D == 0`, so the function is CONTINUOUS there — and that
##    agreement is the assertion which catches a missing or mis-signed branch.
##
## `K + |D| == 0` (hole 5) reads `0.0` mitigation: no contest, never a division.
static func _mitigation_of(defense: float, divisor_k: float, tuning: CombatTuning) -> float:
	var ceiling := clampf(_finite(tuning.mitigation_ceiling), 0.0, 1.0)
	if ceiling <= 0.0:
		return 0.0
	var k := maxf(0.0, _finite(divisor_k))
	var magnitude := absf(_finite(defense))
	var denominator := k + magnitude
	if denominator <= 0.0:
		return 0.0
	var share := magnitude / denominator if defense >= 0.0 else 2.0 - k / denominator
	return _finite(ceiling * share)


## The attacker's penetration against this element's DEFENSE, as a magnitude on
## `CombatTuning.pierce_scale`'s own scale rather than in the old resistance's `[0, 1]`
## space. Zero when nothing was authored, and never negative: a negative penetration
## would be a defence BONUS wearing an attacker's name.
func _penetration_of(ctx: AttackContext) -> float:
	var id := CombatStats.PENETRATION
	return maxf(0.0, CombatStats.default_of(id) + _finite(ctx.attacker_value(id)))


## `element_power_<e>`, or 0.0 when there is no element. Zero is a real answer and not
## a failure: an actor with no affinity for an element has an elemental term of zero,
## which is the "untrained element" case and the only way this term is ever 0.0.
func _element_power_of(ctx: AttackContext, tuning: CombatTuning, element: StringName) -> float:
	if element == &"":
		return 0.0
	return maxf(0.0, _finite(ctx.attacker_value(_suffixed(tuning.element_power_prefix, element))))


## Whether `table` knows `element`, through whichever of `has` / `ids` it answers.
## Both exist on `ElementRules` and a caller may hand over a narrower object, so the
## read is by behaviour rather than by type -- which is also what keeps this file from
## naming a class of the module that owns them.
func _has_element(table: Variant, element: StringName) -> bool:
	if not (table is Object):
		return false
	var holder := table as Object
	if holder.has_method(&"has"):
		return bool(holder.call(&"has", element))
	if holder.has_method(&"ids"):
		var listed: Variant = holder.call(&"ids")
		return listed is Array and (listed as Array).has(String(element))
	return false


## One stat id built from an authored prefix. A prefix the tuning does not carry makes
## the id the bare element name, which no provider contributes, so the term reads 0.0:
## a visibly broken balance rather than a null-dereference.
func _suffixed(prefix: String, element: StringName) -> StringName:
	return StringName(_finite_text(prefix) + String(element))


func _finite_text(value: Variant) -> String:
	return String(value) if value is String else ""


## The amount on a proposal of any shape. `get()` rather than `.amount`, so a proposal
## written against a shape this file does not have answers `0.0` instead of crashing a
## hit three stages downstream.
func _amount_of(proposal: RefCounted) -> float:
	if proposal == null:
		return 0.0
	return _number(proposal.get(&"amount"))


## Every arithmetic result in this file passes through here. The spine's ONE non-finite
## guard sits at S6's entrance and `maxf(NaN, chip) == NaN`, so a NaN produced here
## would survive `DamageProposal`'s own `maxf` clamp (which returns `0.0` for NaN, but
## only by accident of how `maxf` is implemented) and reach `ResourcePool.change`,
## which has no guard at all.
static func _finite(value: float) -> float:
	return value if is_finite(value) else 0.0


## A `Variant` from `ctx.data` as a finite float, or 0.0. A `bool` is deliberately not
## a number here: `true` as a share would silently read 1.0.
static func _number(value: Variant) -> float:
	if value is float or value is int:
		return _finite(float(value))
	return 0.0


## What a null context answers. Every key present so a panel rendering [method
## breakdown]'s shape never has to ask whether a key exists.
static func _empty_parts() -> Dictionary:
	return {
		"element": "",
		"share": 0.0,
		"magnitude": 0.0,
		"raw": 0.0,
		"elemental_power": 0.0,
		"matchup": NEUTRAL,
		"defender_element": "",
		"defense": 0.0,
		"defense_effective": 0.0,
		"divisor_k": 0.0,
		"mitigation_rate": 0.0,
		"penetration": 0.0,
		"mitigation": 1.0,
		"raw_attack": 0.0,
		"raw_term": 0.0,
		"elemental_term": 0.0,
		"subtotal": 0.0,
		"damage_reduction": 0.0,
		"mitigated": 1.0,
		"total": 0.0,
		"rules_bound": false,
	}
