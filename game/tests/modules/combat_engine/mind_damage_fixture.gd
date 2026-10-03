extends TestCase

## Shared fixture for the mind-damage suites. Not a suite itself: the runner
## discovers `test_*.gd` only, so this file is never executed on its own.
##
## It exists so `test_mind_damage.gd` (the mechanism's own properties) and
## `test_mind_damage_collapse.gd` (ADR 0071's rupture and collapse ticks) share ONE
## copy of the pinned actor arithmetic. A second copy would drift, and a drift here is
## invisible: both suites would still be green against their own copy.
##
## ## The one architectural rule this file keeps honest
##
## `combat_engine` declares `["contracts", "core"]` and `mind_damage.gd` names NO class
## of `mind_cultivation` -- not `SeaOfConsciousness`, not `MindStats`, not
## `MindCultivationApi`. The sea arrives as INJECTED state and every field is reached
## through `get()`. **A TEST is not the implementation**, so this fixture is the one
## place in `tests/modules/combat_engine/` that legitimately holds that edge: it uses it
## to build a REAL `SeaOfConsciousness` through the module's own `attach_sea`, so the
## mechanism is measured against the real component rather than a duck-typed stand-in
## that could drift from it.
##
## ## The pinned actor arithmetic
##
## `MindProvider` contributes (ADR 0071 / BRIEF 4b):
## - `mental_attack = (perception * 2.0 + mental_clarity * 1.5) * technique_factor`
## - `mental_defense  = (mental_clarity * 2.0 + will * 0.5) * technique_factor * (1 + power)`
## - `illusion_resistance = minf(0.8, mental_clarity * 0.004 + will * 0.002)`
##
## where `power` is the meridian network's bonus, `0.0` for a fresh actor.
##
## An actor with NO started mind path has `technique_factor == RealmRate.NEUTRAL == 1.0`
## and `meridian_power == 0.0`, so every derived stat above is a plain linear read of the
## base attributes and each expected number below is exact rather than approximate.
## Nothing here sets a realm, so nothing here pins a ladder factor.

## `perception` 20.0 with no `mental_clarity` gives `mental_attack == 40.0` exactly, at
## the neutral realm rate. `physique` is the one base stat the spine's S1/S7/S8 own derived
## stats need to be non-degenerate. `comprehension` is NOT authored: BL-0163 deleted
## `comprehension_bonus` and its formula was `1.0 + comprehension * 0.01 +
## technique_factor * 0.02`, so an author who thought it "fed nothing" put the stat back on
## the fixture and `MindCultivationApi.attach` -- which resolves every provider including
## `MindProvider.contribute` -- raised a PARSE ERROR reading the deleted
## `comprehension` local. Every erosion row in both mind suites then read `mental_attack ==
## 0.0` and a FAILURE had no cause anywhere near its own assertion.
const ATTACKER_BASE := {
	MindStats.PERCEPTION: 20.0,
	Stat.PHYSIQUE: 10.0,
}
## The attacker's pinned `mental_attack`, restated for the assertions that quote it.
const ATTACKER_MENTAL_ATTACK := 40.0
## The FULL pool every fixture actor carries, so `rupture_bleed`'s `max_health` term is
## legible and a mind strike's untouched health pool is a byte-identical number.
##
## ## Why the pool is 150.0 and not 1000.0
##
## `MindCultivationApi.attach` resolves every provider the actor declares, and one of them
## derives `max_health` — so a pool authored at `1000.0` is REPLACED by that derived ceiling
## (perception 0.0, physique 10.0, no realm) the moment attachment runs. Every row read
## `150.0` after the fixture believed it had written `1000.0`, and `test_mind_damage`'s
## `assert_eq(before_health, HEALTH, "the pool was full before the hit, as pinned")` reported
## `expected 1000.0, got 150.0` — a failure naming a number the fixture no longer controlled.
##
## So the pool is authored at its own derived ceiling. The value stops being arbitrary: it is
## what a fresh actor's health actually is, and `HEALTH` is re-asserted against that live read
## rather than against a constant the provider can overwrite.
const HEALTH := 150.0
## The sea's structural capacity for the default fixture row: R1's authored 100.0, the
## one number ADR 0071 puts in the denominator.
const SEA_CAPACITY := 100.0
## The tier ladder's steps, shallowest first. A sea nobody promoted is `shallow`, and a
## collapse from `shallow` lands on `deep` -- the only demotion the shipped floors author.
const TIER_SHALLOW := &"shallow"
const TIER_DEEP := &"deep"
const TIER_VAST := &"vast"
## The `MENTAL_ATTACK` share the shipped tuning defaults to. ADR 0071's `share` term.
const SHARE := 1.0
## The `_defender` defense pin's modifier SOURCE. It names the pin to the one stat it
## belongs to, so a later `remove_modifiers_from` can lift it again -- needed because
## `ACTOR_SCRATCH` copies base stats and pools but NOT the modifier stack.
const DEFENSE_SOURCE := &"mind_test_defense"
## The value that pin ZEROES a defender's defense to, whatever `MindProvider` derives.
## NOT the `_defender` argument: `_recompute` has already settled that argument's own
## contribution against a HALVED baseline, so subtracting it would land on `2 * b - d`.
const ZEROED_DEFENSE := -1.0

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTuning.shipped()


## The shipped tuning these rows are measured against, so a suite quotes the balance
## number rather than restating it.
func tuning() -> CombatTuning:
	return _tuning


## An attacker whose `mental_attack` is pinned BY CONSTRUCTION at
## [constant ATTACKER_MENTAL_ATTACK]: `perception 20.0`, no `mental_clarity`, and no
## started mind path so `technique_factor` is the neutral `1.0`.
##
## `MindCultivationApi.attach` is REQUIRED, not decoration: `mental_attack` is
## contributed by `MindProvider` and reads `0.0` on an actor nobody attached one to.
## Without it every erosion assertion in these suites would be measuring "no contest"
## instead of erosion -- the same defect `qi_damage_fixture.gd` documents for
## `ElementsApi.attach`.
func _attacker() -> Actor:
	var actor := Actor.new(&"mind_attacker", ATTACKER_BASE)
	actor.add_resource(ResourcePool.new(&"health", HEALTH))
	MindCultivationApi.attach(actor)
	return actor


## A defender carrying a REAL attached sea, its AWARENESS reserve at
## `awareness_fraction`, and its `mental_defense` pinned at `defense` -- which is a
## DERIVED stat, so it is pinned through a `StatModifier` rather than a base attribute.
##
## The modifier is `FLAT` because `mental_defense` is a derived RATE that is not one of
## core's `Stat` ids (BRIEF 1.8: a `PERCENT` modifier would evaluate against its own
## baseline). `add_modifier` marks the actor's stats dirty, so the next `derived()` read
## recomputes through `MindProvider` with the modifier applied.
##
## `MindCultivationApi.attach` must run BEFORE `attach_sea`: it creates the `awareness`
## pool the coherence term reads and `attach_sea` reads a base stat the provider supplies.
func _defender(
	awareness_fraction: float = 0.0, defense: float = 0.0, clarity: float = 0.5
) -> Actor:
	var actor := Actor.new(
		&"mind_defender", {Stat.PHYSIQUE: 10.0, MindStats.MENTAL_CLARITY: clarity}
	)
	actor.add_resource(ResourcePool.new(&"health", HEALTH))
	MindCultivationApi.attach(actor)
	_pin_defense(actor, defense)
	var sea := MindCultivationApi.attach_sea(actor)
	# Assigned AFTER attachment: `attach_sea` seeds `structural_capacity` from a base
	# stat an actor with no realm does not carry, which is `0.0` -- and a `0.0` capacity
	# makes the mechanism visibly inert (hole 2) rather than wrong.
	sea.set_structural_capacity(SEA_CAPACITY)
	sea.set_clarity(clarity)
	_set_awareness(actor, awareness_fraction)
	return actor


## Pin a DEFENDER's `mental_defense` to an absolute `defense`, whatever `MindProvider`
## derives for it.
##
## ## Why the argument is NOT the modifier's value
##
## `mental_defense` is a PROVIDER-CONTRIBUTED stat, not a base attribute, so a modifier is
## the only way to reach it -- but `ActorStats` applies that modifier to the provider's own
## output as an OFFSET: `_ensure_providers` reads
## `(contributed + flat) * (1 + percent) * mult` (`actor_stats.gd:122-127`). So
## `StatModifier.new(MENTAL_DEFENSE, FLAT, defense, ...)` adds `defense` to a baseline the
## fixture never measured, and the pin read `clarity * 2 + d` instead of `d`.
##
## At the fixture's own `mental_clarity 0.5` that is `1.0 + d`: the two assertions that
## stated the defender's defense out loud reported `expected 0.0, got 1.0` and
## `expected 0.0, got 400.0`, and the sweep's `defense 10.0` row measured `11 / (11 + 40)`
## -- the missing `1.0` proving the offset, since a floor would not have moved it. The
## objection to the pin was never `FLAT` vs `PERCENT` (BRIEF 1.8's trap is real, and `FLAT`
## is still the correct op here); it was ADDITIVE where an ABSOLUTE value was needed.
##
## ## Why the offset is measured rather than restated
##
## `derived()` is read BEFORE the pin lands and again after, so the offset IS whatever the
## provider derives -- the argument never restates a formula it cannot see, and a change to
## `MindProvider.contribute` moves the pin with it instead of silently re-breaking it.
func _pin_defense(actor: Actor, defense: float) -> void:
	var derived_before := actor.stats.derived(MindStats.MENTAL_DEFENSE)
	actor.stats.add_modifier(
		StatModifier.new(
			MindStats.MENTAL_DEFENSE, Stat.Op.FLAT, defense - derived_before, DEFENSE_SOURCE
		)
	)
	actor.mark_stats_dirty()
	assert_almost_eq(
		actor.stats.derived(MindStats.MENTAL_DEFENSE),
		defense,
		"the fixture pins mental_defense at the value the caller asked for"
	)


## ## Why there is no "copy a defender with one stat changed" helper here
##
## `Actor` has no copy constructor: [method Actor.new] rebuilds an actor from BASE stats,
## pools and providers and cannot carry a modifier. So a rebuilt copy of a defender arrives
## carrying the provider's own baseline -- `clamped_mental_clarity * 2` on this actor --
## with nothing cancelling it, and the rows that wanted "this defender but with high
## `illusion_resistance`" read `expected 0.0, got 400.0` when they were handed one.
##
## A caller that needs a defender differing on one derived stat asks `_defender` for a
## defender whose BASE attributes produce the difference instead, which is what the
## illusion-resistance rows do: the pin and the build then come from ONE actor, and
## `_pin_defense` zeroes its defense the same way it zeroes every other defender's.


## The sea on an actor this fixture built. `MindCultivationApi.sea` is the module's own
## read, so the key `combat_engine` looks up (`CombatTuning.sea_component`) is asserted
## rather than assumed.
func _sea_of(actor: Actor) -> SeaOfConsciousness:
	return MindCultivationApi.sea(actor)


## The defender's AWARENESS reserve as a `0..1` fraction, read BACK off the pool so an
## assertion states the ratio it measured rather than the one it intended. ADR 0071's
## `coherence` is computed from exactly this.
func _awareness_of(actor: Actor) -> float:
	var pool := actor.resource(MindStats.AWARENESS) as ResourcePool
	if pool == null or pool.maximum <= 0.0:
		return 0.0
	return clampf(pool.current / pool.maximum, 0.0, 1.0)


## The `[method breakdown]` row for one hit. The sea is injected through `ctx.data`
## (`MindDamage.SEA_KEY`), which is the route `MindDamage.builder` uses.
func _parts(
	kind_value: MindDamage.Kind, attacker: Actor, defender: Actor, share: float = SHARE
) -> Dictionary:
	return MindDamage.new().breakdown(_context(kind_value, attacker, defender, share))


## A context shaped exactly as `CombatSpine._context` shapes one, carrying this hit's
## kind, its sea and its share through the ONE extension point.
##
## `with_sea = false` is the only way to reach the "nothing injected anywhere" case: this
## helper injects the sea unconditionally, so a case asserting `sea_bound == false` would
## otherwise be asserting against a context that had one.
func _context(
	kind_value: MindDamage.Kind,
	attacker: Actor,
	defender: Actor,
	share: float = SHARE,
	with_sea: bool = true
) -> AttackContext:
	var ctx := AttackContext.new(attacker, defender, null, _tuning, 100.0)
	ctx.set_data(MindDamage.KIND_KEY, kind_value)
	if with_sea:
		ctx.set_data(MindDamage.SEA_KEY, _sea_of(defender))
	ctx.set_data(MindDamage.SHARE_KEY, share)
	return ctx


## Set the defender's AWARENESS reserve to `fraction` of its pool, through the POOL
## rather than by authoring a stat: `coherence` reads `current / maximum`, so the pool is
## the state the mechanic actually consumes.
func _set_awareness(actor: Actor, fraction: float) -> void:
	var pool := actor.resource(MindStats.AWARENESS) as ResourcePool
	if pool == null:
		return
	pool.current = pool.maximum * clampf(fraction, 0.0, 1.0)


## A technique of a chosen magnitude. `MindDamage` reads no field off it -- ADR 0071's
## `share` travels on `ctx.data` -- but the spine's S1 does, so a suite that goes through
## the spine needs one.
func _technique(magnitude: float = 100.0) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = &"mind_test"
	def.magnitude = magnitude
	return def


## Drive one full landed hit through the SPINE with [method MindDamage.builder] as the
## `ctx_builder`, so a suite that asserts "mind never touches health" is measuring the
## eleven stages' actual result and not a hand-applied arithmetic.
##
## The `ctx_builder` is COMPOSED rather than handed over bare: [method MindDamage.builder]
## carries the kind and the sea, but ADR 0071's `share` travels on its own `SHARE_KEY` and
## nothing but this fixture sets it, so a spine-driven hit at a non-default share would
## otherwise silently fall back to `CombatTuning.default_mind_share` -- and a test that
## thought it was measuring share `0.4` would be measuring `1.0`.
##
## `rng` is null by default: a null generator spends no draw, so `_focus_of` and
## `_avoidance_of` both answer `1.0` and `0.0` respectively (ADR 0067's determinism
## rule). Every erosion number in these suites is therefore the UNFOCUSED one.
func _hit(
	attacker: Actor,
	defender: Actor,
	kind_value: MindDamage.Kind,
	share: float = SHARE,
	magnitude: float = 100.0,
	rng: Variant = null
) -> CombatOutcome:
	MechanismSlot.bind(attacker, MindDamage.new())
	var carry := MindDamage.builder(kind_value, _sea_of(defender))
	return CombatSpine.resolve_hit(
		attacker,
		defender,
		_technique(magnitude),
		_tuning,
		rng,
		func(ctx: AttackContext) -> AttackContext:
			var staged: AttackContext = carry.call(ctx) as AttackContext
			staged.set_data(MindDamage.SHARE_KEY, share)
			return staged
	)


## The `amount` a mechanism's proposal carries for one hit. S4 alone, then S5 applied --
## the split ADR 0067 exists for, and the order the spine runs them in.
func _proposal_amounts(mechanism: DamageMechanism, ctx: AttackContext) -> Array[float]:
	var resolved: DamageProposal = mechanism.resolve(ctx)
	var mitigated: DamageProposal = mechanism.mitigate(ctx, resolved)
	return [resolved.amount, mitigated.amount]


## The single erosion effect a proposal carries, or an empty dictionary when it carries
## none. One helper because every mind assertion reads the SAME one entry: ADR 0071's
## `effects[]` is deliberately ONE entry per hit carrying every write, so a panel can
## never show a sea that went turbulent without the clarity it cost.
func _effect_of(proposal: DamageProposal) -> Dictionary:
	return proposal.effect_of(MindDamage.EFFECT_KIND)


## `MindDamage.tick_rupture` through a bound instance.
##
## It is declared WITHOUT `static` on the implementation while its twin
## [method MindDamage.tick_collapse] and [method MindDamage.apply_deviation] both ARE
## static, so a caller cannot write `MindDamage.tick_rupture(...)`. Neither needs any
## instance state -- the method only reads its four parameters and a shipped tuning --
## which is exactly why the asymmetry is worth this helper's comment rather than a
## silent workaround: it is the one mind entry point whose call shape disagrees with its
## siblings.
func _rupture(sea: Variant, actor: Actor, delta: float) -> Dictionary:
	return MindDamage.new().tick_rupture(sea, actor, delta, _tuning)
