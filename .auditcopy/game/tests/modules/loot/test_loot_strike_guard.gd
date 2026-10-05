extends TestCase

## `LootApi.strike`'s `ERR_NO_DAMAGE` guard, restored with the state that triggers it
## named (BL-0325).
##
## The guard's whole purpose is to refuse a free win: a strike that spends nothing must
## not advance a boss, must not spend the run, and must not mint the once-only reward a
## defeat would. A screen-level test for it was deleted during a correct refactor (the
## flat-damage slot left `LootBridge`), which left a live production guard with zero
## assertions — nothing would have caught its removal.
##
## So it is asserted here, at the module level where the verb actually lives, and in
## **both** directions, because they fail independently:
##
##   refuses  — a live boss plus damage that spends nothing is `no_damage`, and the
##              whole world is byte-for-byte what it was.
##   permits  — the very same boss spends a legal strike, and the guard is what makes
##              the two different rather than the guard blocking everything.
##
## Every refusal branch is named with the concrete input that reaches it: zero, a
## negative amount, and a non-finite amount all satisfy `damage <= 0.0`, and all three
## are asserted. The ordering matters too — with no boss live the reason is
## `not_in_domain`, so this suite proves the guard is reached only in the state it
## claims to guard.

const EMBER_DOMAIN := &"loot_ember_vault_domain"
const EMBER_TIER := 1
## A legal strike well inside the ember warden's authored pool, so the positive
## direction leaves the boss alive rather than killing it on the first press.
const LEGAL_DAMAGE := 25.0
## The seed every strike here carries. Fixed, so the run is reproducible: the assertion
## about *which* boss is live must not depend on a draw.
const SEED := 20260902


func _hero() -> Actor:
	var actor := Actor.new(&"delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor, 24)
	LootApi.attach(actor)
	return actor


## A delver already standing in the ember vault with a boss live, reached through the
## facade's own entry path — not by hand-writing `active` into `module_data`, because a
## state the game cannot produce would not be the state a player can be in.
func _in_domain() -> Actor:
	var actor := _hero()
	var entered := LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, SEED)
	assert_eq(bool(entered.get("ok", false)), true, "the ember vault opens for a bare delver")
	assert_eq(
		bool((LootApi.summary(actor).get("active", {}) as Dictionary).get("in_domain", false)),
		true,
		"with a boss live"
	)
	return actor


func _active(actor: Actor) -> Dictionary:
	return LootApi.summary(actor).get("active", {}) as Dictionary


## The whole loot world as a comparable value: what a refused strike must leave alone.
func _world(actor: Actor) -> Dictionary:
	var state := LootApi.summary(actor)
	return {
		"active": _active(actor),
		"rewards": state.get("rewards", []),
		"reward_count": int(state.get("reward_count", 0)),
		"claimed": int(state.get("claimed_encounters", 0)),
		"runs": state.get("runs", {}),
		"world_drops": int(state.get("world_drop_count", 0)),
	}


## Direction one, refusal: the concrete input state is **a live boss at full vitality
## plus an amount that spends nothing**. Every one of those is asserted, because a guard
## that only checked `== 0.0` would still let a negative amount through, and a negative
## amount is exactly as free.
func test_a_strike_that_spends_nothing_is_refused_and_changes_nothing() -> void:
	var actor := _in_domain()
	var before := _world(actor)
	var vitality := float(before["active"].get("vitality", 0.0))
	assert_eq(vitality > 0.0, true, "the guard is proved against a live boss, not an empty run")

	# Each amount below satisfies `damage <= 0.0` or is not finite, and each names the
	# branch it reaches. NEGATIVE_INFINITY is the one that is both.
	for case in [
		["zero", 0.0],
		["negative", -1.0],
		["nan", NAN],
		["positive infinity", INF],
		["negative infinity", -INF],
	]:
		var label := String((case as Array)[0])
		var damage := float((case as Array)[1])
		var result := LootApi.strike(actor, damage, SEED)
		assert_eq(bool(result.get("ok", true)), false, "%s damage is refused" % label)
		assert_eq(
			String(result.get("reason", "")), LootState.ERR_NO_DAMAGE, "%s names the guard" % label
		)
		assert_eq(
			String(result.get("encounter_id", "")),
			String(before["active"].get("encounter_id", "")),
			"%s reports the boss it would have hit" % label
		)
		assert_eq(_world(actor), before, "%s damage leaves the entire loot world untouched" % label)

	# Spelled out once more, because "the world is untouched" is only meaningful if the
	# pool really was full and really is still full.
	assert_eq(float(_active(actor).get("vitality", 0.0)), vitality, "no vitality was spent")
	assert_eq(
		float(_active(actor).get("vitality_max", 0.0)),
		float(before["active"].get("vitality_max", 0.0)),
		"and the pool it would have been spent from is unchanged"
	)
	assert_eq(int(_world(actor)["reward_count"]), 0, "no reward was minted")
	assert_eq(int(_world(actor)["claimed"]), 0, "and no claim was spent")


## The reason a free win is impossible is that the guard runs BEFORE the pool is spent,
## not after: the reported pool is the one the caller was about to hit, and a guard that
## ran afterwards would already have moved it. Pinned by reading the refusal's own
## reported figures, which is the only place the ordering is observable.
func test_the_refusal_reports_the_pool_it_refused_to_spend() -> void:
	var actor := _in_domain()
	var live := _active(actor)
	var result := LootApi.strike(actor, 0.0, SEED)
	assert_eq(
		float(result.get("vitality", -1.0)),
		float(live.get("vitality", 0.0)),
		"the refusal reports the boss's vitality untouched"
	)
	assert_eq(
		float(result.get("vitality_max", -1.0)),
		float(live.get("vitality_max", 0.0)),
		"and its ceiling, so a reader can show what was not spent"
	)
	assert_eq(result.has("reward"), false, "a refused strike mints nothing to report")


## Direction two, permission: the **same boss, same call shape, one legal amount**. This
## is the half that fails independently — a guard that refuses everything is as broken
## as no guard at all, and nothing above would notice.
func test_a_legal_strike_on_the_same_boss_still_spends_the_pool() -> void:
	var actor := _in_domain()
	var live := _active(actor)
	var vitality := float(live.get("vitality", 0.0))

	var refused := LootApi.strike(actor, 0.0, SEED)
	assert_eq(String(refused.get("reason", "")), LootState.ERR_NO_DAMAGE, "the free strike refused")

	var landed := LootApi.strike(actor, LEGAL_DAMAGE, SEED)
	assert_eq(bool(landed.get("ok", false)), true, "a legal strike on that same boss lands")
	assert_ne(String(landed.get("reason", "")), LootState.ERR_NO_DAMAGE, "and is not the guard")
	assert_eq(
		String(landed.get("reason", "")),
		LootState.OK_ALIVE,
		"the boss is still standing on a partial strike"
	)
	assert_almost_eq(
		float(_active(actor).get("vitality", 0.0)),
		vitality - LEGAL_DAMAGE,
		"exactly the authored amount was spent, and only that much"
	)


## The legal path still reaches its end: a lethal legal strike defeats the boss and mints
## the once-only payload, so the guard cannot have made a defeat unreachable.
func test_a_legal_strike_still_defeats_the_boss_and_mints_the_reward() -> void:
	var actor := _in_domain()
	LootApi.strike(actor, 0.0, SEED)
	var killed := LootApi.strike(actor, float(_active(actor).get("vitality_max", 1.0)) * 10.0, SEED)
	assert_eq(bool(killed.get("ok", false)), true, "the legal strike defeats the boss")
	assert_eq(String(killed.get("reason", "")), LootState.OK_DEFEATED, "and reports the defeat")
	assert_eq(int(killed.get("drop_count", 0)) > 0, true, "the payload carries drops")
	assert_eq(int(LootApi.summary(actor)["reward_count"]), 1, "and exactly one payload was minted")


## Ordering, so this guard cannot be confused with the one before it. With **no boss
## live**, a zero strike is `not_in_domain`: `LootState.strike` refuses the empty run
## before it ever looks at the damage. A guard asserted only here would be asserting the
## wrong rule, and one asserted only above would leave this path untested.
func test_a_zero_strike_with_no_boss_live_reports_the_empty_run_not_the_damage() -> void:
	var actor := _hero()
	assert_eq(bool(_active(actor).get("in_domain", true)), false, "no run is in flight")
	var result := LootApi.strike(actor, 0.0, SEED)
	assert_eq(bool(result.get("ok", true)), false, "the strike is refused")
	assert_eq(
		String(result.get("reason", "")),
		LootState.ERR_NOT_IN_DOMAIN,
		"and the reason is the empty run, not the damage"
	)
	assert_eq(int(LootApi.summary(actor)["reward_count"]), 0, "nothing was minted either way")


## Persistence: a refused strike must not survive a save/load as damage taken. The save
## is the JSON round trip `Actor.to_dict` really performs, so the boss comes back at the
## vitality it had — once, in the one key that carries it.
func test_a_refused_strike_survives_a_save_and_load_unchanged() -> void:
	var actor := _in_domain()
	LootApi.strike(actor, 0.0, SEED)
	var before := _world(actor)

	var restored = JSON.parse_string(JSON.stringify(actor.to_dict()))
	assert_ne(restored, null, "the actor round-trips through a save")
	var saved := restored as Dictionary
	var loaded := Actor.from_dict(saved)
	LootApi.attach(loaded)

	var reloaded := _world(loaded)
	assert_eq(reloaded["active"], before["active"], "the boss comes back at full vitality")
	assert_eq(int(reloaded["reward_count"]), 0, "with nothing owed")

	# Serialized exactly once. The whole lifecycle travels in the one `loot_state` key:
	# `runs` is a field inside it rather than a second top-level key beside it, so a save
	# can never carry two copies of the truth that could disagree.
	var stored := saved.get("module_data", {}) as Dictionary
	assert_eq(stored.has(String(LootState.MODULE_KEY)), true, "the loot state is stored")
	assert_eq(
		(stored[LootState.MODULE_KEY] as Dictionary).has("runs"),
		true,
		"with the run ledger inside that one key"
	)
	assert_eq(
		stored.keys().filter(func(key: Variant) -> bool: return String(key).contains("domain_run")),
		[],
		"and nothing beside it owns a second copy of a run"
	)


## Repeated free strikes must not add up to a kill. `LootState.strike` refuses each one
## on its own, so a loop of them cannot converge on the reward — which is the property
## that makes the guard worth having rather than a formality.
func test_repeated_free_strikes_never_add_up_to_a_defeat() -> void:
	var actor := _in_domain()
	var live := _active(actor)
	var attempts := 0
	var refusals := 0
	while attempts < 25:
		attempts += 1
		var result := LootApi.strike(actor, 0.0, SEED)
		if String(result.get("reason", "")) == LootState.ERR_NO_DAMAGE:
			refusals += 1
	assert_eq(refusals, 25, "every one of the 25 free strikes hit the guard")
	assert_eq(
		float(_active(actor).get("vitality", 0.0)),
		float(live.get("vitality", 0.0)),
		"and none of them moved the pool"
	)
	assert_eq(int(LootApi.summary(actor)["reward_count"]), 0, "so no payload was ever minted")
