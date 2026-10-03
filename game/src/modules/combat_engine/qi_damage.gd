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
## resist   = clampf(defender element_resistance_<e>/RESIST_DIVISOR - mastery_pen, 0, RESIST_CAP)
## mit      = 1 - resist
## match    = rules.multiplier(attacker_element, defender_element)
## t_e      = m_e * a_e * match * mit
## t_0      = m_0 * a_0
## total    = (t_0 + t_e) * (1 - clampf(defender DAMAGE_REDUCTION, 0, CAP))
## ```
##
## ## `match` sits BETWEEN the elemental magnitude and mitigation
##
## Resistance is applied to the elemental term AFTER the matchup has been read, so
## a defender at `RESIST_CAP` is a hard counter even to a `STRONG` 1.5. That is the
## anti-"fire is always strong" property: the rule scales the ATTACKER's element, and
## the defender's build answers it. Two rejections, from the ADR:
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
## `element_power_` / `element_resistance_` id PREFIXES are authored on `CombatTuning`
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
## Four, all in [method breakdown] / [method _resistance_of], each closed without
## inventing a new constant and each asserted in this module's suite:
##
## 1. **`RESIST_DIVISOR = 0` divides by zero.** A bare `CombatTuning.new()` (or an
##    author who forgot the `.tres`) would read `0.0 / 0.0 == NaN` and NaN survives
##    every clamp. A non-positive or non-finite divisor means the contest has no
##    scale, so resistance reads 0.0 — the same shape `CombatBand.rate` gives a null
##    tuning.
## 2. **`RESIST_CAP > 1` makes the amount NEGATIVE.** `mit = 1 - resist` goes below
##    zero, the elemental term goes negative, and S9's single sign flip spends it as a
##    HEAL. `mitigation` is clamped to `[0, 1]`, and `resist_cap` is read clamped to
##    `[0, 1]`, because a mitigation above 100% has no meaning.
## 3. **`DAMAGE_REDUCTION_CAP > 1` does the same to the total.** Clamped the same way.
## 4. **`element_share` out of `[0, 1]`** makes `m_0` negative. Clamped. `NaN` in the
##    authored share fails the `<= 0.0` test an ordinary comparison would reject, so it
##    is caught by [method _finite] first and falls back to the tuning default.
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
## resistance, penetration, mitigation, raw_term, elemental_term, subtotal,
## damage_reduction, mitigated, total, rules_bound}`.
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
	var resistance := _resistance_of(ctx, tuning, element)
	# Clamped to [0, 1]: a `RESIST_CAP` above 1.0 would make `mitigation` negative and
	# the elemental term with it, and S9's one sign flip would spend that as a heal.
	var mitigation := clampf(1.0 - resistance, 0.0, 1.0)
	var penetration := _penetration_of(ctx)
	var raw_attack := _finite(ctx.attacker_value(Stat.ATTACK_SPIRITUAL))
	var elemental_power := _element_power_of(ctx, tuning, element)
	var reduction := clampf(_finite(ctx.target_value(Stat.DAMAGE_REDUCTION)), 0.0, 1.0)
	var cap := clampf(_finite(tuning.damage_reduction_cap), 0.0, 1.0)
	var mitigated := clampf(1.0 - minf(reduction, cap), 0.0, 1.0)
	# `t_0` takes NEITHER the matchup NOR the resistance NOR the reduction's own
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
		"resistance": resistance,
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


## `clampf(defender element_resistance_<e> / RESIST_DIVISOR - mastery_pen, 0, RESIST_CAP)`.
##
## The penetration is subtracted BEFORE the clamp, so mastery can only ever move
## resistance DOWN and can never amplify a hit past `RESIST_CAP` (ADR 0069). It is read
## from `CombatStats.PENETRATION`, the combat-owned channel ADR 0068 defines as exactly
## this lever ("how hard the attacker cuts the defender's guard, a read-only input to a
## mechanism's mitigate"), in the same `[0, 1]` space as `resist`. `element_mastery_<e>`
## itself is an input to the attacker's `element_power_<e>` inside `ElementProvider`, so
## mastery moves the elemental term from both ends and this term from neither.
##
## A non-positive or non-finite divisor reads as 0.0 rather than dividing: see the
## first hole in the module docblock.
func _resistance_of(ctx: AttackContext, tuning: CombatTuning, element: StringName) -> float:
	if element == &"":
		return 0.0
	var divisor := _finite(tuning.resist_divisor)
	var raw := 0.0
	if divisor > 0.0:
		raw = _finite(ctx.target_value(_suffixed(tuning.resist_resistance_prefix, element)))
		var penalty := _penetration_of(ctx)
		raw = clampf(raw / divisor - penalty, 0.0, clampf(_finite(tuning.resist_cap), 0.0, 1.0))
	return raw


## The attacker's penetration against this element's resistance, in resist's own
## `[0, 1]` space. Zero when nothing was authored, and never negative: a negative
## penetration would be a resistance BONUS wearing an attacker's name.
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
		"resistance": 0.0,
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
