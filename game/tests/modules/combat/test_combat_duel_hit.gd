extends TestCase

## One blow, actor to actor, over the existing share model (ADR 0126).
##
## ## What this suite is evidence for
##
## Before ADR 0126 the only combat resolution reachable was `CombatExchange.exchange`,
## which answers for a player and a boss `loot` had already spawned. These assertions cover
## the second party: two `Actor`s, one blow, the defender's own pool spent by a SHARE.
##
## ## No scene tree, no frame, no node
##
## `run_tests.gd` quits before the first frame, so nothing here may need one. Every
## assertion is on `RefCounted` state — an `Actor`, a `ResourcePool`, a returned
## `Dictionary` — and the `PlayerAdapter` case is driven through `attack()` on a DETACHED
## `CharacterBody2D`, which needs no `SceneTree` because it never calls `move_and_slide`.

const SEED := 20_260_903

## Blows one duel may take before the test calls it a stall. A share is floored at
## `CombatDamage.MIN_SHARE` and `ResourcePool.change` clamps at zero, so a working model
## cannot reach this: it names the condition that failed to terminate.
const BLOW_CAP := 200


## A bare actor: no gear, no cultivation, a health pool sized from its own derived
## `MAX_HEALTH`. `CombatExchange`'s `_health` attaches one lazily; this does it up front so
## a suite assertion on the pool is about the blow and not about whether an attach ran.
func _fighter(id: StringName, physique: float = 10.0) -> Actor:
	var actor := Actor.new(id, {Stat.PHYSIQUE: physique, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	return actor


## The same actor after one realm step. `RealmScaling` multiplies `ATTACK_PHYSICAL` by the
## realm's authored `power`, so a higher-realm actor genuinely attacks harder — which is
## the whole point of test (9), and is why the realm is set through `set_path` and applied
## through `RealmScaling` rather than by writing a stat.
func _realm_fighter(id: StringName, realm_id: StringName) -> Actor:
	var actor := _fighter(id)
	actor.set_path(PathState.new(&"qi", realm_id))
	RealmScaling.apply(actor)
	actor.attach_core_resources()
	return actor


func _rng(seed_value: int = SEED) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = seed_value
	return generator


func _health(actor: Actor) -> float:
	var pool := actor.resource(&"health") as ResourcePool
	return 0.0 if pool == null else pool.current


func test_a_blow_spends_share_times_the_defenders_own_maximum() -> void:
	var attacker := _fighter(&"striker")
	var defender := _fighter(&"ward")
	var maximum := _health(defender)
	var result := CombatApi.hit(attacker, defender, SEED)
	assert_eq(bool(result["ok"]), true, "a blow between two living actors lands")
	assert_eq(bool(result["defender_slain"]), false, "and nobody died to one blow")
	# The model is a SHARE, never a magnitude: the arithmetic only has meaning relative to
	# the pool it is spent from, so this asserts the multiplication itself rather than any
	# balance value — `CombatDamage`'s own suite owns those.
	assert_almost_eq(
		float(result["taken"]),
		float(result["share"]) * maximum,
		"taken is the share of the defender's own maximum, not an authored number"
	)
	assert_almost_eq(
		maximum - _health(defender), float(result["taken"]), "and the pool moved by exactly that"
	)


func test_health_reaching_zero_reports_defender_slain_and_the_read_refuses() -> void:
	var attacker := _fighter(&"striker")
	var defender := _fighter(&"ward")
	var blow := 0
	# Bounded by BLOW_CAP, which a share floored at `MIN_SHARE` cannot reach: this loop
	# terminates or the model stopped terminating fights.
	while blow < BLOW_CAP:
		blow += 1
		var last := CombatApi.hit(attacker, defender, SEED + blow)
		if bool(last["defender_slain"]):
			break
	assert_almost_eq(_health(defender), 0.0, "the fight ran the defender's pool to zero")
	var alive := CombatDuelHit.alive(defender)
	assert_eq(bool(alive["ok"]), false, "and alive() refuses a body at zero health")
	assert_eq(String(alive["reason"]), "defender_slain", "by name, not by an exception")
	assert_almost_eq(float(alive["health_ratio"]), 0.0, "and the ratio reads zero")


func test_a_slain_actor_cannot_be_hit_again() -> void:
	var attacker := _fighter(&"striker")
	var slain := _fighter(&"ward")
	slain.resource(&"health").change(-slain.resource(&"health").maximum)
	var before := _health(slain)
	var result := CombatApi.hit(attacker, slain, SEED)
	assert_eq(bool(result["ok"]), false, "a corpse refuses the blow")
	assert_eq(String(result["reason"]), "defender_slain", "with the named reason")
	assert_almost_eq(float(result["taken"]), 0.0, "and spends nothing")
	assert_almost_eq(_health(slain), before, "on a pool that is already empty")


func test_the_same_seed_produces_a_bit_identical_outcome_twice() -> void:
	# Two identically built pairs, two identically seeded blows. Every reported key must
	# match, which is a stronger claim than "the share matched": it is that the whole
	# answer — the crit verdict and the evasion verdict included — is a function of the
	# seed rather than of the call order.
	var first_attacker := _fighter(&"striker")
	var first_defender := _fighter(&"ward")
	var second_attacker := _fighter(&"striker")
	var second_defender := _fighter(&"ward")
	var first := CombatApi.hit(first_attacker, first_defender, SEED)
	var second := CombatApi.hit(second_attacker, second_defender, SEED)
	for key in ["share", "taken", "crit", "evaded", "power", "mitigation", "defender_slain"]:
		assert_eq(second[key], first[key], "seed %d reproduces '%s' exactly" % [SEED, key])
	assert_almost_eq(
		_pool_delta(first_defender, second_defender), 0.0, "and moves both pools identically"
	)
	# A different seed is a different stream, so the answer is not guaranteed to move —
	# only that nothing here hard-codes it. Asserting a difference would make this suite
	# read "green" for a constant, which test (4) above already rules out.
	assert_eq(
		CombatApi.hit(_fighter(&"striker"), _fighter(&"ward"), SEED + 1).has("share"),
		true,
		"and a different seed answers in the same shape"
	)


func test_an_actor_cannot_attack_itself() -> void:
	var actor := _fighter(&"loner")
	var before := _health(actor)
	var result := CombatApi.hit(actor, actor, SEED)
	assert_eq(bool(result["ok"]), false, "a self-directed blow is refused")
	assert_eq(String(result["reason"]), "same_actor", "by name")
	assert_almost_eq(_health(actor), before, "and spends nothing off the attacker's own pool")


func test_every_refusal_is_named_and_none_of_them_spends() -> void:
	var actor := _fighter(&"ward")
	var poolless := Actor.new(&"poolless", {Stat.PHYSIQUE: 10.0})
	var before := _health(actor)
	assert_eq(String(CombatApi.hit(null, actor, SEED)["reason"]), "no_attacker", "no attacker")
	assert_eq(String(CombatApi.hit(actor, null, SEED)["reason"]), "no_defender", "no defender")
	assert_eq(
		String(CombatApi.hit(actor, poolless, SEED)["reason"]),
		"no_health_pool",
		"an actor nobody attached resources to"
	)
	assert_almost_eq(_health(actor), before, "and not one refusal touched a pool")


func test_binding_a_mechanism_is_what_retires_the_loud_lookup() -> void:
	# `CombatSpine.resolve_hit` calls `MechanismSlot.of(attacker)`, which ASSERTS when
	# nothing is bound. `CombatEngineApi.bind_mechanism` had zero production callers, so
	# the technique-casting seam asserted for any real actor. This is that gap, asserted.
	var attacker := _fighter(&"striker")
	assert_eq(CombatEngineApi.has_mechanism(attacker), false, "a bare actor has no mechanism")
	var bound: Dictionary = CombatBoot.bind_mechanisms(attacker)
	assert_eq(bool(bound["ok"]), true, "the root binds one")
	assert_eq(String(bound["mechanism"]), "QiDamage", "and names the concrete mechanism it bound")
	assert_eq(CombatEngineApi.has_mechanism(attacker), true, "so the actor now carries one")
	assert_eq(
		String(CombatBoot.bind_mechanisms(attacker)["mechanism"]),
		String(bound["mechanism"]),
		"and re-binding is idempotent rather than a second mechanism"
	)


func test_the_spine_decomposes_a_bound_actor_instead_of_asserting() -> void:
	# Reaching `MechanismSlot.of` at all is the assertion: an assert failure kills the
	# process, so a green suite here IS the evidence that the latent assert is retired.
	var attacker := _fighter(&"striker")
	var defender := _fighter(&"ward")
	CombatBoot.bind_mechanisms(attacker)
	var parts := CombatEngineApi.breakdown(
		attacker, defender, CombatTestKit.technique(100.0), CombatEngineApi.tuning(), null
	)
	# `CombatOutcome.to_dict` is `{}` for a MISS, so the shape rather than any one key is
	# what this asserts: a non-empty decomposition is the evidence the mechanism ran.
	assert_eq(parts.is_empty(), false, "the spine decomposed the hit through a bound mechanism")
	assert_eq(float(parts.get("amount", 0.0)) > 0.0, true, "and the qi mechanism produced damage")
	assert_eq(bool(parts["crit"]), false, "with a null rng every attack lands and none crits")


func test_player_adapter_attack_reaches_the_injected_resolver() -> void:
	var attacker := _fighter(&"hero")
	var defender := _fighter(&"ward")
	var calls: Array[Dictionary] = []
	var seen := func(who: Actor, whom: Actor, seed_value: int) -> Dictionary:
		calls.append({"attacker": String(who.id), "defender": String(whom.id), "seed": seed_value})
		return {"ok": true, "reason": "", "share": 0.0, "taken": 0.0}
	CombatBoot.set_attack_resolver(seen)
	var adapter := PlayerAdapter.new(attacker)
	adapter.set_state(PlayerAdapter.State.COMBAT)
	var target := PlayerAdapter.new(defender)
	adapter.add_interactable(target)
	adapter.attack(target)
	assert_eq(calls.size(), 1, "attack reached the resolver exactly once")
	assert_eq(String(calls[0]["attacker"]), "hero", "with the adapter's own actor as attacker")
	assert_eq(String(calls[0]["defender"]), "ward", "and the target's wrapped actor as defender")
	# The stub's guards are still the stub's guards: an unbound-state adapter and a
	# target that is not a combatant both return without calling anything.
	adapter.set_state(PlayerAdapter.State.EXPLORATION)
	adapter.attack(target)
	assert_eq(calls.size(), 1, "and exploration never swings")
	adapter.set_state(PlayerAdapter.State.COMBAT)
	adapter.attack(Node2D.new())
	assert_eq(calls.size(), 1, "nor does a prop with no actor behind it")


func test_a_higher_realm_attacker_spends_a_larger_share() -> void:
	var realm := RealmDefaults.ladder().realms()
	assert_eq(realm.size() > 1, true, "the ladder has a step above its first rung")
	var shallow := _realm_fighter(&"shallow", realm[0].id)
	var deep := _realm_fighter(&"deep", realm[realm.size() - 1].id)
	var defender := _fighter(&"ward")
	var weak := CombatApi.hit(shallow, defender, SEED)
	var strong := CombatApi.hit(deep, defender, SEED)
	# `CombatDamage` is deliberately realm-blind (ADR 0076): the realm reaches the share
	# only because `RealmScaling` multiplies ATTACK_PHYSICAL by the authored realm power
	# on the way in. A suite that raised the share by reading the realm index instead
	# would fail here, which is the point.
	assert_eq(
		float(strong["share"]) > float(weak["share"]),
		true,
		"the deepest realm attacks hardest, so it spends more of the same authored pool"
	)
	assert_almost_eq(
		float(strong["power"]),
		clampf(
			(
				float(
					(
						deep.stats.derived(Stat.ATTACK_PHYSICAL)
						+ deep.stats.derived(Stat.ATTACK_SPIRITUAL)
					)
				)
				/ CombatDamage.REFERENCE_ATTACK
			),
			CombatDamage.MIN_SHARE / CombatDamage.BASE_SHARE,
			CombatDamage.POWER_CEILING
		),
		"and the power it reaches is that attack read straight off the scaled stat"
	)


func test_the_report_quotes_the_blow_without_spending_it() -> void:
	var attacker := _fighter(&"striker")
	var defender := _fighter(&"ward")
	var before := _health(defender)
	var quoted := CombatDuelHit.report(attacker, defender, _rng(SEED))
	assert_eq(bool(quoted["ok"]), true, "a living pair reports")
	assert_almost_eq(_health(defender), before, "and a report spends nothing")
	# The same seed, spent for real: the quote must be the number the swing produces.
	var spent := CombatApi.hit(attacker, defender, SEED)
	assert_almost_eq(
		float(quoted["taken"]),
		float(spent["taken"]),
		"so the quote is exactly what the blow spends"
	)
	assert_almost_eq(
		before - _health(defender), float(spent["taken"]), "and the swing moved the pool by it"
	)


## The distance between two identically built defenders' pools. `CombatApi.hit` salts the
## stream with BOTH actor ids, so a pair of same-id actors still land the same roll —
## which is what makes the reproducibility assertion meaningful.
func _pool_delta(left: Actor, right: Actor) -> float:
	return absf(_health(left) - _health(right))
