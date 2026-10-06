class_name CombatTestKit
extends RefCounted

## Shared builders for the ADR 0067 spine suites. One place to make an actor, a
## technique, a tuning and a stub mechanism, so a test that changes a builder changes
## every suite that uses it — which is the only way "the stub is the same stub" stays
## true across `tests/modules/combat_engine/`.
##
## NOT production code. It lives in `tests/` because a test double is test evidence: the
## moment a fixture is promoted into `src/` it can start being depended on by gameplay
## code, and a double that gameplay depends on is a mechanism that never got replaced by
## qi, body or mind.


## The shipped tuning, loaded the same way `CombatEngineApi.tuning` loads it. A suite
## that pinned its own copy would be pinning a rebalance.
static func shipped() -> CombatTuning:
	return CombatTuning.shipped()


## Tuning with the spine's own defaults — every constant `0.0`. Deliberately degenerate,
## and a suite that wants it says so: with `min_chip_abs = 0.0` every landed hit is
## zeroed and with `rate_scale = 0.0` every trigger reads `0.0` (ADR 0877), so a number
## that comes back non-zero under this tuning is the arithmetic, not the data.
static func bare() -> CombatTuning:
	return CombatTuning.new()


## An actor with a health pool and nothing else — no path, so `realm()` is empty and S1's
## rate gate is `RealmRate.NEUTRAL`. The baseline for "what does the spine do with an
## actor nobody has built up".
static func actor(id: StringName = &"hero", health: float = 1000.0) -> Actor:
	var subject := Actor.new(id, {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 10.0})
	subject.add_resource(ResourcePool.new(&"health", health))
	return subject


## A technique of a chosen authored magnitude. `TechniqueDef` is a `Resource`, so this is
## a plain in-memory def and needs no `.tres` on disk.
static func technique(magnitude: float = 100.0) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.magnitude = magnitude
	return def


## An actor whose author guarantees no crit, so a suite that is not about S3 cannot be
## surprised by one. `Stat.CRIT_CHANCE` is `fortune * 0.002 + agility * 0.0005`, so an
## actor with no fortune and no agility reads `0.0` already; the FLAT below pins that
## zero for any actor that does carry the attributes.
static func quiet_actor(id: StringName = &"hero", health: float = 1000.0) -> Actor:
	var subject := Actor.new(id, {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 10.0})
	subject.add_resource(ResourcePool.new(&"health", health))
	# A FLAT modifier at a `0.0`-baseline rate is the only form that can move it
	# (ADR 0022), which is the same rule `CombatStats.RATE_IDS` guards for combat's own
	# ids. `crit_chance` has a constant 0.05 term, so -1.0 lands it on 0.0.
	subject.stats.add_modifier(
		StatModifier.new(Stat.CRIT_CHANCE, Stat.Op.FLAT, -1.0, &"combat_test_kit")
	)
	return subject


## A seeded stream, for a suite that needs the roll's effect and never its number.
static func rng(seed_value: int = 4242) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = seed_value
	return generator


## A generator that returns a fixed sequence and counts how many draws it served. This
## is how "ONE draw" becomes an assertion rather than a claim: `CombatBand.draw` takes a
## `RandomNumberGenerator` and calls `randf()` on it, so an object that answers `randf()`
## counts exactly the draws the band consumed.
##
## Deliberately NOT a `RandomNumberGenerator` subclass. Godot forbids overriding a native
## method — `randf()` on a subclass is refused with "This won't be called by the engine",
## and this project treats warnings as errors, so the whole file fails to compile and
## every `CombatBand` reference cascades into "Could not resolve class". A `RefCounted`
## that answers `randf()` satisfies the same duck-typed call with no engine rule broken.
class CountingGenerator:
	extends RefCounted

	var draws: int = 0
	var values: Array[float] = []

	func _init(p_values: Array[float] = []) -> void:
		values.assign(p_values)

	func randf() -> float:
		draws += 1
		if values.is_empty():
			return 0.5
		var index := (draws - 1) % values.size()
		return values[index]


## A mechanism that returns a fixed amount and records what it was asked. The seam
## proof: three instances of this class with three amounts are three mechanisms, and the
## spine between them is the identical eleven stages.
class FixedMechanism:
	extends DamageMechanism

	## What `resolve` returns. `mitigate` returns it unchanged.
	var amount: float = 0.0
	## `effects[]` handed back with the proposal, so a suite can assert they survive.
	var effects: Array[Dictionary] = []
	var resolve_calls: int = 0
	var mitigate_calls: int = 0
	## The `base` the spine published on the context it handed over. This is the S1
	## ordering assertion: a mechanism sees the rate-gated value, never `magnitude`.
	var seen_base: float = -1.0
	## Whether the context the spine handed over said the hit had critted.
	var seen_crit: bool = false

	func resolve(ctx: AttackContext) -> DamageProposal:
		resolve_calls += 1
		seen_base = float(ctx.get(&"base"))
		seen_crit = bool(ctx.get(&"crit"))
		# The REAL `contracts/DamageProposal`, not the duck-typed
		# `CombatProposalReader.Proposal` this fixture used before the contracts wave
		# landed. Returning the old shape tripped the declared return type and made
		# every mechanism amount read as the chip floor, which is why one fixture line
		# turned ~80 assertions red across the whole combat_engine suite.
		return DamageProposal.new(amount, effects)

	func mitigate(_ctx: AttackContext, proposal: DamageProposal) -> DamageProposal:
		mitigate_calls += 1
		return proposal
