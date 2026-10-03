extends TestCase

## The boss/domain reward lifecycle, proved end to end against the shipped
## content: enter, spawn, defeat, reward, pickup, clear, re-enter — plus the
## headline invariant, that one defeat yields exactly one reward payload no
## matter how many times the death event is observed.

const EMBER_DOMAIN := &"loot_ember_vault_domain"
const EMBER_TIER := 1
const EMBER_BOSS_COUNT := 3
const STORM_DOMAIN := &"loot_storm_crypt_domain"
const STORM_TIER := 3
## The item the acquisition test inspects: a real, non-stackable drop, so a
## delivered instance can be compared field by field.
const MARK := &"amulet_iron_sage_eye"


func _hero(fortune: float = 0.0, capacity: int = 24) -> Actor:
	var actor := Actor.new(&"delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.stats.set_base(Stat.FORTUNE, fortune)
	actor.attach_core_resources()
	ItemsApi.attach(actor, capacity)
	LootApi.attach(actor)
	return actor


func _first_pending(actor: Actor) -> Dictionary:
	for reward in LootApi.summary(actor)["rewards"]:
		if int((reward as Dictionary)["pending_count"]) > 0:
			return reward as Dictionary
	return {}


func _defeat_boss(actor: Actor, damage: float = 10000.0, seed_value: int = 4242) -> Dictionary:
	return LootApi.strike(actor, damage, seed_value)


func _raw_reward(actor: Actor, encounter_id: String) -> Dictionary:
	var state := LootState.normalize(actor.get_module_data(LootState.MODULE_KEY))
	return (state["rewards"] as Dictionary).get(encounter_id, {}) as Dictionary


func _raw_drop(actor: Actor, encounter_id: String, drop_id: String) -> Dictionary:
	for drop in _raw_reward(actor, encounter_id).get("drops", []):
		if String((drop as Dictionary).get("drop_id", "")) == drop_id:
			return drop as Dictionary
	return {}


func _carried_ids(actor: Actor) -> Array:
	var out: Array = []
	var inventory := ItemsApi.inventory(actor)
	for batch in inventory.stacks():
		out.append(String(batch.def_id))
	for instance in inventory.instances():
		out.append(String(instance.def_id))
	return out


## Take everything that is still owed, making room between rounds. Returns the
## number of rounds it needed, so a test can assert the drain terminates.
func _drain(actor: Actor) -> int:
	var rounds := 0
	while rounds < 40:
		var summary := LootApi.summary(actor)
		if int(summary["reward_count"]) == 0 and int(summary["world_drop_count"]) == 0:
			return rounds
		rounds += 1
		ItemsApi.inventory(actor).clear()
		for stash in summary["world_drops"]:
			LootApi.reclaim(actor, String((stash as Dictionary)["stash_id"]))
		for reward in LootApi.summary(actor)["rewards"]:
			LootApi.pickup_all(actor, String((reward as Dictionary)["encounter_id"]))
	return rounds


# --- The headline invariant -------------------------------------------------


## One defeat, one payload. Killing a boss mints exactly one reward keyed by that
## encounter's deterministic id, and the run moves on — so hammering the fight can
## never mint a second payload for a boss that is already dead, and every token in
## a run is distinct.
func test_one_boss_defeat_yields_exactly_one_reward_payload() -> void:
	var actor := _hero()
	assert_eq(
		bool(LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 99)["ok"]), true, "entered"
	)
	var first := _defeat_boss(actor)
	assert_eq(String(first["reason"]), LootState.OK_DEFEATED, "the boss died")
	var reward: Dictionary = first["reward"]
	var token := String(reward["claim_token"])
	assert_eq(token.is_empty(), false, "the payload carries a claim token")
	assert_eq(int(reward["drop_count"]) > 0, true, "the payload holds drops")
	assert_eq(token, String(first["encounter_id"]), "the token is the encounter id")

	# The dead boss is gone from the fight: the next strike lands on the next boss
	# of the run, never on the corpse.
	var second := _defeat_boss(actor)
	assert_eq(String(second["encounter_id"]) == token, false, "a second defeat is a new encounter")
	assert_eq(String(second["reason"]), LootState.OK_DEFEATED, "and it defeats that one")
	assert_eq(
		String(second["reward"]["claim_token"]) == token, false, "with its own distinct token"
	)

	var summary := LootApi.summary(actor)
	var seen: Dictionary = {}
	for entry in summary["rewards"]:
		seen[String((entry as Dictionary)["claim_token"])] = true
	assert_eq(seen.size(), int(summary["reward_count"]), "no two payloads share a token")
	assert_eq(int(summary["reward_count"]), 2, "one payload per defeated boss, no more")


## The duplicate guard itself: a defeat reported for an encounter that already owns
## a payload returns that same payload and mints nothing. This is the path a combat
## system's second `boss_died` event takes.
func test_a_repeated_death_event_returns_the_same_payload() -> void:
	var actor := _hero()
	LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 99)
	var defeated := _defeat_boss(actor)
	var token := String(defeated["encounter_id"])
	var drop_count := int(defeated["drop_count"])
	var before: int = (
		(LootState.normalize(actor.get_module_data(LootState.MODULE_KEY))["rewards"]).size()
	)
	# Put the corpse back in the active slot, exactly as a stale death event for
	# the previous encounter would arrive.
	var state := LootState.normalize(actor.get_module_data(LootState.MODULE_KEY))
	state["active"]["encounter_id"] = token
	state["active"]["boss_id"] = String(defeated["reward"]["boss_id"])
	state["active"]["defeated"] = false
	var repeat := LootState.strike(state, actor, 10000.0, 99)
	assert_eq(String(repeat["reason"]), LootState.OK_DUPLICATE, "the repeat is diagnosed")
	assert_eq(bool(repeat["duplicate"]), true, "flagged as a duplicate")
	assert_eq(String(repeat["encounter_id"]), token, "for the same encounter")
	assert_eq(int(repeat["drop_count"]), drop_count, "and the same drops")
	assert_eq((state["rewards"] as Dictionary).size(), before, "no third payload was minted")


## Re-entering after abandoning, and abandoning after a defeat, both resolve the
## same encounter ids, so neither can mint a second payload for a dead boss.
func test_re_entry_and_abandon_never_duplicate_the_reward() -> void:
	var actor := _hero()
	LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 5)
	var defeated := _defeat_boss(actor)
	var token := String(defeated["encounter_id"])
	assert_eq(bool(LootApi.abandon(actor)["ok"]), true, "left the domain")
	var re_entered := LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 5)
	assert_eq(bool(re_entered["ok"]), true, "re-entered the same tier")
	assert_eq(int(re_entered["active"]["run"]), 1, "the same run is resumed")
	assert_eq(String(re_entered["active"]["encounter_id"]) == token, false, "past the dead boss")
	assert_eq(int(re_entered["active"]["boss_index"]), 1, "at the next undefeated boss")
	assert_eq(int(LootApi.summary(actor)["reward_count"]), 1, "no second payload for the dead boss")
	assert_eq(
		String(LootApi.reward(actor, token)["reason"]) == LootState.ERR_CLAIM_SPENT,
		false,
		"the original payload is still claimable"
	)


## Save/load between defeat and pickup restores the unclaimed reward with its full
## instance state, and the restored run continues without re-minting.
func test_save_load_between_defeat_and_pickup_preserves_the_unclaimed_reward() -> void:
	var actor := _hero()
	LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 21)
	var defeated := _defeat_boss(actor)
	var token := String(defeated["encounter_id"])
	var before := _first_pending(actor)
	var before_drops: Array = before["drops"]
	var before_claimed := int(LootApi.summary(actor)["claimed_encounters"])

	# Round-trip through JSON, the way a file save does: this is where a nested
	# StringName key would quietly become a String.
	var restored = JSON.parse_string(JSON.stringify(actor.to_dict()))
	assert_eq(restored is Dictionary, true, "the actor payload survives a JSON round trip")
	var loaded := Actor.from_dict(restored as Dictionary)
	ItemsApi.attach(loaded, 24)
	LootApi.attach(loaded)
	var after_summary := LootApi.summary(loaded)
	assert_eq(int(after_summary["reward_count"]), 1, "the unclaimed reward survived")
	assert_eq(
		int(after_summary["claimed_encounters"]), before_claimed, "and so did the claim ledger"
	)
	var after := _first_pending(loaded)
	assert_eq(String(after["claim_token"]), token, "the same claim token")
	assert_eq(int(after["drop_count"]), (before_drops as Array).size(), "the same drop count")
	for index in (before_drops as Array).size():
		var was: Dictionary = before_drops[index]
		var now: Dictionary = (after["drops"] as Array)[index]
		assert_eq(String(now["drop_id"]), String(was["drop_id"]), "drop id preserved")
		assert_eq(String(now["rarity"]), String(was["rarity"]), "rarity preserved")
		assert_eq(String(now["realm"]), String(was["realm"]), "realm preserved")
		assert_eq(int(now["rolled_count"]), int(was["rolled_count"]), "realized rolls preserved")
		assert_eq(int(now["effect_count"]), int(was["effect_count"]), "resolved effects preserved")
	# The loaded run carries on: the next boss is a new encounter, never a re-mint.
	var again := _defeat_boss(loaded)
	assert_eq(String(again["reason"]), LootState.OK_DEFEATED, "the next boss of the run is fought")
	assert_eq(String(again["encounter_id"]) == token, false, "and it is a new encounter")
	assert_eq(int(LootApi.summary(loaded)["reward_count"]), 2, "still one payload per boss")


## A full inventory leaves the drop retrievable and spends no claim: it overflows
## into the bounded world drop container, and reclaiming it after making room
## delivers the exact instance, rolls intact.
func test_a_full_inventory_never_loses_or_spends_a_drop() -> void:
	var actor := _hero(0.0, 24)
	var filler := Crafting.resolve(&"amulet_storm_phoenix_feather")
	for slot in 24:
		ItemsApi.inventory(actor).add_instance(
			ItemInstance.new(filler.id, StringName("filler_%d" % slot))
		)
	assert_eq(ItemsApi.inventory(actor).is_full(), true, "the inventory is full")

	LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 7)
	var reward: Dictionary = _defeat_boss(actor)["reward"]
	var token := String(reward["claim_token"])
	var drop: Dictionary = (reward["drops"] as Array)[0]
	var drop_id := String(drop["drop_id"])
	var expected := LootRewards.instance_from(_raw_drop(actor, token, drop_id), "")

	var overflow := LootApi.pickup(actor, token, drop_id)
	assert_eq(
		String(overflow["status"]), LootState.OK_OVERFLOW, "it overflows rather than vanishing"
	)
	assert_eq(String(overflow["reason"]), LootState.ERR_INVENTORY_FULL, "naming the cause")
	assert_eq(
		ItemsApi.inventory(actor).count(StringName(drop["def_id"])) > 0,
		false,
		"nothing was pushed into a full inventory"
	)
	var summary := LootApi.summary(actor)
	assert_eq(int(summary["world_drop_count"]), 1, "the drop is stashed in the world, retrievable")
	var still := LootApi.reward(actor, token)
	assert_eq(bool(still["ok"]), true, "the reward is still there")
	var recoverable := 0
	for entry in (still["reward"] as Dictionary)["drops"]:
		if bool((entry as Dictionary)["claimable"]) or bool((entry as Dictionary)["stashed"]):
			recoverable += 1
	assert_eq(
		recoverable,
		int((still["reward"] as Dictionary)["drop_count"]),
		"no drop was claimed by the refused pickup"
	)
	# Picking the stashed drop up again is refused, so it cannot be double-taken.
	var again := LootApi.pickup(actor, token, drop_id)
	assert_eq(
		String(again["reason"]), LootState.ERR_DROP_STASHED, "a stashed drop is not re-pickable"
	)

	# Make room and reclaim it: the exact instance arrives with its rolls.
	ItemsApi.inventory(actor).remove_instance(&"filler_0")
	var reclaimed := LootApi.reclaim(actor, drop_id)
	assert_eq(bool(reclaimed["ok"]), true, "the stashed drop is reclaimed")
	assert_eq(String(reclaimed["status"]), LootState.OK_CLAIMED, "claimed")
	var carried := ItemsApi.inventory(actor).find_instance(StringName(drop["def_id"]))
	assert_ne(carried, null, "the instance is in the inventory")
	assert_eq(
		carried.stacking_signature(),
		expected.stacking_signature(),
		"the realized roll is identical to the one minted at defeat"
	)
	assert_eq(carried.rolled.size() > 0, true, "the delivered instance carries its roll")
	assert_eq(int(LootApi.summary(actor)["world_drop_count"]), 0, "the container is empty again")


## With more drops than free slots the surplus overflows, and the world drop
## container is the only thing standing between a full inventory and a refusal.
func test_overflow_goes_to_the_world_drop_container_and_is_reclaimable() -> void:
	var actor := _hero(0.0, 1)
	LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 31)
	var reward: Dictionary = _defeat_boss(actor)["reward"]
	var token := String(reward["encounter_id"])
	var drops: Array = reward["drops"]
	assert_eq(drops.size() >= 2, true, "the table produced several drops to overflow with")

	var delivered := 0
	var overflowed := 0
	for drop in drops:
		var result := LootApi.pickup(actor, token, String((drop as Dictionary)["drop_id"]))
		match String(result.get("status", "")):
			LootState.OK_CLAIMED:
				delivered += 1
			LootState.OK_OVERFLOW:
				overflowed += 1
				assert_eq(
					String(result["reason"]),
					LootState.ERR_INVENTORY_FULL,
					"overflow names the cause"
				)
			_:
				assert_eq(true, false, "nothing is refused while the container has room")
	assert_eq(delivered, 1, "the first drop fits the single free slot")
	assert_eq(overflowed, drops.size() - 1, "the rest overflow while the container has room")

	var summary := LootApi.summary(actor)
	assert_eq(int(summary["world_drop_count"]), drops.size() - 1, "each surplus drop is stashed")
	assert_eq(bool(summary["world_drops_full"]), false, "the container is not full")
	var stash_id := String((summary["world_drops"] as Array)[0]["stash_id"])
	assert_eq(stash_id.is_empty(), false, "the stash is addressable")

	var rounds := _drain(actor)
	assert_eq(rounds < 40, true, "the drain terminates")
	var final := LootApi.summary(actor)
	assert_eq(int(final["reward_count"]), 0, "the encounter's claim is spent")
	assert_eq(int(final["world_drop_count"]), 0, "and the container is empty")
	assert_eq(int(final["claimed_encounters"]) > 0, true, "the claim ledger keeps the trace")


## The world drop container is bounded: past its capacity a pickup is refused and
## the drop is still retrievable in the reward.
func test_the_world_drop_container_is_bounded() -> void:
	var actor := _hero(0.0, 1)
	assert_eq(LootState.WORLD_DROP_CAPACITY, 6, "the container is small and declared")
	var stashes: Array = []
	var state := LootState.normalize(actor.get_module_data(LootState.MODULE_KEY))
	for index in LootState.WORLD_DROP_CAPACITY + 2:
		stashes.append({"stash_id": "s%d" % index, "encounter_id": "e", "drop_id": "d%d" % index})
	state["world_drops"] = stashes
	actor.set_module_data(LootState.MODULE_KEY, state)
	# Fill the single inventory slot too, so the drop genuinely cannot be held.
	var filler := Crafting.resolve(&"amulet_storm_phoenix_feather")
	ItemsApi.inventory(actor).add_instance(ItemInstance.new(filler.id, &"occupied"))
	assert_eq(bool(LootApi.summary(actor)["world_drops_full"]), true, "the container reports full")

	LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 3)
	var reward: Dictionary = _defeat_boss(actor)["reward"]
	var token := String(reward["encounter_id"])
	var drop: Dictionary = (reward["drops"] as Array)[0]
	var result := LootApi.pickup(actor, token, String(drop["drop_id"]))
	assert_eq(String(result["status"]), "refused", "a full container refuses the overflow")
	assert_eq(String(result["reason"]), LootState.ERR_INVENTORY_FULL, "with the cause")
	assert_eq(bool(result["world_drops_full"]), true, "and says why")
	assert_eq(
		int(LootApi.reward(actor, token)["reward"]["drop_count"]),
		(reward["drops"] as Array).size(),
		"the reward still holds every drop"
	)
	assert_eq(
		int(LootApi.summary(actor)["world_drop_count"]),
		LootState.WORLD_DROP_CAPACITY + 2,
		"and the container did not grow"
	)


## Claiming a drop twice is refused, and a spent encounter reports itself as such
## instead of handing out a second copy.
func test_a_spent_claim_reports_itself_and_hands_out_nothing() -> void:
	var actor := _hero()
	LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 13)
	var reward: Dictionary = _defeat_boss(actor)["reward"]
	var token := String(reward["encounter_id"])
	var first: Dictionary = (reward["drops"] as Array)[0]
	var first_id := String(first["drop_id"])
	var carried_before := ItemsApi.inventory(actor).count(StringName(first["def_id"]))
	assert_eq(bool(LootApi.pickup(actor, token, first_id)["ok"]), true, "the first pickup works")
	assert_eq(
		ItemsApi.inventory(actor).count(StringName(first["def_id"])) > carried_before,
		true,
		"a copy did arrive"
	)
	var again := LootApi.pickup(actor, token, first_id)
	assert_eq(bool(again["ok"]), false, "the same drop cannot be taken twice")
	assert_eq(String(again["reason"]), LootState.ERR_DROP_CLAIMED, "and says so")
	LootApi.pickup_all(actor, token)
	var spent := LootApi.reward(actor, token)
	assert_eq(bool(spent["ok"]), false, "a settled encounter is spent")
	assert_eq(String(spent["reason"]), LootState.ERR_CLAIM_SPENT, "reported as spent")
	assert_eq(
		String(LootApi.pickup(actor, token, first_id)["reason"]),
		LootState.ERR_CLAIM_SPENT,
		"a spent encounter hands out nothing"
	)


# --- The domain lifecycle ---------------------------------------------------


## A domain can be entered, cleared and re-entered, and the second entry does not
## re-award the first encounter. A higher authored tier is how a new run is
## granted.
func test_a_domain_can_be_cleared_and_re_entered_without_re_awarding() -> void:
	var actor := _hero()
	assert_eq(
		bool(LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 77)["ok"]), true, "entered"
	)
	var tokens: Array = []
	for _boss in EMBER_BOSS_COUNT:
		assert_eq(bool(LootApi.summary(actor)["in_domain"]), true, "a boss is live")
		tokens.append(String(_defeat_boss(actor)["encounter_id"]))
	assert_eq(tokens.size(), EMBER_BOSS_COUNT, "every boss was fought")
	var unique := {}
	for token in tokens:
		unique[String(token)] = true
	assert_eq(unique.size(), EMBER_BOSS_COUNT, "one distinct encounter id per boss")
	assert_eq(bool(LootApi.summary(actor)["in_domain"]), false, "the run cleared")
	assert_eq(
		int(LootApi.summary(actor)["claimed_encounters"]),
		0,
		"unclaimed rewards survive the clear rather than being spent"
	)
	assert_eq(
		int(LootApi.summary(actor)["reward_count"]), EMBER_BOSS_COUNT, "all three are pending"
	)
	assert_eq(
		int(LootApi.summary(actor)["runs"][EMBER_DOMAIN]["cleared_tier"]),
		EMBER_TIER,
		"the clear is recorded"
	)

	# Rule E2: the cleared tier grants no new run.
	var again := LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 77)
	assert_eq(bool(again["ok"]), false, "a cleared tier cannot be re-entered")
	assert_eq(String(again["reason"]), LootState.ERR_DOMAIN_CLEARED, "and says why")
	assert_eq(int(again["cleared_tier"]), EMBER_TIER, "reporting the cleared tier")
	assert_eq(
		int(LootApi.summary(actor)["reward_count"]), EMBER_BOSS_COUNT, "no new payload was minted"
	)
	for token in tokens:
		assert_eq(
			String(LootApi.reward(actor, String(token))["reason"]) == LootState.ERR_UNKNOWN_REWARD,
			false,
			"each payload is still claimable"
		)

	# A higher authored tier is a new run, and the old tier stays closed.
	var higher := LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER + 1, 78)
	assert_eq(bool(higher["ok"]), true, "a higher tier grants the next run")
	assert_eq(int(higher["active"]["run"]), 2, "the run advanced")
	assert_eq(bool(LootApi.abandon(actor)["ok"]), true, "left the higher tier")
	var retread := LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 79)
	assert_eq(String(retread["reason"]), LootState.ERR_DOMAIN_CLEARED, "the old tier stays closed")
	assert_eq(
		int(LootApi.summary(actor)["reward_count"]), EMBER_BOSS_COUNT, "and still mints nothing"
	)


## A boss whose table legitimately drops nothing is a decided outcome: it is
## recorded as spent at once, so a repeated death event cannot re-roll it.
func test_a_no_drop_boss_is_decided_once_and_reported() -> void:
	var actor := _hero()
	assert_eq(
		bool(LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER + 1, 5)["ok"]),
		true,
		"entered the higher band"
	)
	var tokens: Array = []
	var guard := 0
	while bool(LootApi.summary(actor)["in_domain"]) and guard < 8:
		guard += 1
		var defeated := _defeat_boss(actor)
		tokens.append(String(defeated["encounter_id"]))
	assert_eq(tokens.size(), EMBER_BOSS_COUNT, "the whole band was fought")
	assert_eq(
		bool(LootApi.summary(actor)["in_domain"]), false, "and it cleared, no-drop boss and all"
	)
	var nothing := ""
	for token in tokens:
		if String(LootApi.reward(actor, String(token))["reason"]) == LootState.OK_NO_DROP:
			nothing = String(token)
	assert_eq(nothing.is_empty(), false, "the no-drop table really produced nothing")
	var spent := LootApi.reward(actor, nothing)
	assert_eq(bool(spent["ok"]), false, "it is decided, not pending")
	assert_eq(String(spent["reason"]), LootState.OK_NO_DROP, "reported as no drop")
	assert_eq(int(spent["drop_count"]), 0, "with no drops")
	var state := LootState.normalize(actor.get_module_data(LootState.MODULE_KEY))
	var ledger: Dictionary = (state["claimed"] as Dictionary).get(nothing, {})
	assert_eq(String(ledger.get("reason", "")), LootState.OK_NO_DROP, "the ledger records it")
	assert_eq(int(ledger.get("drops", -1)), 0, "with no drops claimed")


## The domain entry gate is a key item's `key_reach` property (ADR 0033).
func test_a_domains_key_reach_gates_entry() -> void:
	var actor := _hero()
	assert_almost_eq(LootApi._key_reach(actor), 0.0, "a bare actor opens nothing")
	var gated := LootApi.enter_domain(actor, STORM_DOMAIN, STORM_TIER, 3)
	assert_eq(bool(gated["ok"]), false, "the gated domain refuses a bare actor")
	assert_eq(String(gated["reason"]), LootState.ERR_KEY_REACH, "with the gate reason")
	assert_eq(int(gated["required"]), 6, "the required reach is reported")
	assert_eq(
		bool(LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 3)["ok"]),
		true,
		"an ungated domain is open"
	)

	# A real, shipped key item opens it.
	var ledger := Crafting.resolve(&"A26_immortal_auditroll_account")
	assert_ne(ledger, null, "the key item resolves through the content tree")
	assert_eq(bool(LootApi.abandon(actor)["ok"]), true, "left the open domain")
	ItemsApi.inventory(actor).add(ledger, 1)
	assert_almost_eq(LootApi._key_reach(actor), 6.0, "the key's own property decides the gate")
	assert_eq(
		bool(LootApi.enter_domain(actor, STORM_DOMAIN, STORM_TIER, 3)["ok"]),
		true,
		"the key opens it"
	)


## Boss difficulty is authored data, never scaled to the player's gear: the same
## band behaves identically for a weak and a strong actor.
func test_boss_difficulty_is_authored_not_scaled_to_the_actor() -> void:
	var weak := _hero(0.0)
	var strong := _hero(400.0)
	for actor in [weak, strong]:
		LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 1)
	var weak_vitality := float(LootApi.summary(weak)["active"]["vitality_max"])
	var strong_vitality := float(LootApi.summary(strong)["active"]["vitality_max"])
	assert_almost_eq(
		strong_vitality, weak_vitality, "the authored vitality does not move with gear"
	)
	var chip := LootApi.strike(weak, 10.0, 1)
	assert_eq(String(chip["reason"]), LootState.OK_ALIVE, "a partial hit leaves the boss alive")
	assert_almost_eq(
		float(chip["vitality"]), weak_vitality - 10.0, "damage accumulates on the authored pool"
	)
	assert_eq(
		String(LootApi.strike(weak, 0.0, 1)["reason"]), LootState.ERR_NO_DAMAGE, "zero damage"
	)
	assert_eq(
		String(LootApi.strike(weak, -5.0, 1)["reason"]), LootState.ERR_NO_DAMAGE, "negative damage"
	)
	assert_eq(
		String(LootApi.strike(weak, NAN, 1)["reason"]), LootState.ERR_NO_DAMAGE, "non-finite damage"
	)


## The same seed and encounter reproduce the same reward, so a defeat is not a
## coin flip the moment it happens.
func test_a_defeat_is_reproducible_from_its_seed() -> void:
	var first := _hero()
	var second := _hero()
	for actor in [first, second]:
		LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 2024)
	var one: Dictionary = _defeat_boss(first)["reward"]
	var two: Dictionary = _defeat_boss(second)["reward"]
	assert_eq(int(one["drop_count"]), int(two["drop_count"]), "the same seed yields the same count")
	var one_ids: Array = []
	for drop in one["drops"]:
		one_ids.append("%s:%d" % [(drop as Dictionary)["def_id"], (drop as Dictionary)["quantity"]])
	var two_ids: Array = []
	for drop in two["drops"]:
		two_ids.append("%s:%d" % [(drop as Dictionary)["def_id"], (drop as Dictionary)["quantity"]])
	assert_eq(str(one_ids), str(two_ids), "the same drops, in the same order")


## `loot_bonus` reaches the real lifecycle and stays inside its declared caps: over
## many kills a lucky delver is given more loot, never more than the plan cap, and
## the guaranteed entry is still present on every payload.
func test_loot_bonus_reaches_the_defeat_and_stays_bounded() -> void:
	assert_almost_eq(LootBonus.rate_for(_hero(0.0)), 0.0, "no fortune, no bonus")
	assert_almost_eq(LootBonus.rate_for(_hero(400.0)), 4.0, "fortune 400 clamps at the input cap")
	var unlucky_total := 0
	var lucky_total := 0
	var cap := LootResolver.MAX_PLANS_PER_RESOLVE
	for index in 16:
		for pair in [[0.0, "plain"], [400.0, "lucky"]]:
			var actor := _hero(float(pair[0]))
			assert_eq(
				bool(LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 900 + index)["ok"]),
				true,
				"%s entered" % pair[1]
			)
			var defeated := _defeat_boss(actor, 10000.0, 900 + index)
			var count := int(defeated.get("drop_count", 0))
			assert_eq(count <= cap, true, "%s payload %d inside the plan cap" % [pair[1], count])
			var mark := false
			for drop in (defeated.get("reward", {}) as Dictionary).get("drops", []):
				if String((drop as Dictionary)["entry_id"]) == "ew1_sigil":
					mark = true
			assert_eq(mark, true, "%s still gets the guaranteed entry" % pair[1])
			if String(pair[1]) == "lucky":
				lucky_total += count
			else:
				unlucky_total += count
	assert_eq(lucky_total > unlucky_total, true, "the bonus produces more loot over 16 kills")


## Acquisition, end to end through the real lifecycle and the real inventory: a
## boss is genuinely defeated, its drop is genuinely picked up, and the item is
## genuinely carried with its realized rolls.
func test_a_boss_is_defeated_and_its_drop_is_genuinely_acquired() -> void:
	var actor := _hero()
	var carried_before := _carried_ids(actor)
	LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 314)
	var reward: Dictionary = _defeat_boss(actor)["reward"]
	var token := String(reward["encounter_id"])
	var taken: Array = []
	for drop in reward["drops"]:
		if bool(LootApi.pickup(actor, token, String((drop as Dictionary)["drop_id"]))["ok"]):
			taken.append((drop as Dictionary)["def_id"])
	assert_eq(taken.is_empty(), false, "at least one drop was picked up")
	var carried_after := _carried_ids(actor)
	for def_id in taken:
		assert_eq(carried_after.has(def_id), true, "%s is in the inventory" % def_id)
		assert_eq(carried_before.has(def_id), false, "%s was not there before" % def_id)
	# The mark item is a distinct instance, so the roll is inspectable.
	var mark := ItemsApi.inventory(actor).find_instance(MARK)
	assert_ne(mark, null, "the mark instance is carried")
	assert_eq(mark.rolled.size() > 0, true, "it carries a real roll")
	assert_eq(
		mark.def_ref.effects(mark).is_empty(), false, "its effects resolve through the items module"
	)
	assert_eq(String(mark.realm), "spirit_severing", "it rolled for the band it fell in")
	assert_eq(bool(ItemsApi.has_item(actor, MARK)), true, "the items facade sees it too")
	assert_eq(
		bool(ItemsApi.equip_item(actor, Equipment.ACCESSORY_A, mark.def_ref)), true, "it equips"
	)


## The declared authority for a boss's loot is the authored table; the legacy
## `BossDef.loot` list is only projected when no authored table exists.
##
## The legacy boss is authored here rather than borrowed. No shipped boss carries a
## legacy `loot` array any more, so borrowing one would have pinned this assertion to
## content drift — and the assertion would then be describing a corpus that no longer
## exists instead of a rule that still holds.
func test_the_boss_loot_authority_is_single_and_legacy_is_projected() -> void:
	var content := LootContent.instance()
	var authored := content.table_for_boss(&"loot_ember_vault_warden", EMBER_TIER)
	assert_ne(authored, null, "the authored binding resolves")
	assert_eq(String(authored.id), "loot_ember_warden_t1", "and is the bound table")
	assert_eq(
		bool(authored.allow_empty), false, "the authored table decides whether it may be empty"
	)

	# A boss authored before loot tables carried a flat item list. It is projected
	# deterministically, once, into an implicit table.
	var legacy_boss := &"probe_projected_loot_bear"
	(
		content
		. provide_boss(
			legacy_boss,
			{
				"found": true,
				"id": String(legacy_boss),
				"domain_id": "",
				"boss_ids": [],
				"loot": ["amulet_iron_sage_eye", "amulet_storm_phoenix_feather"],
			}
		)
	)
	var record := content.boss_record(legacy_boss)
	assert_eq(bool(record["found"]), true, "the legacy boss content resolves")
	assert_eq((record["loot"] as Array).is_empty(), false, "and carries a legacy loot list")
	assert_eq(bool(content.has_authored_table(legacy_boss)), false, "no authored table claims it")
	var projected := content.table_for_boss(legacy_boss, 0)
	assert_ne(projected, null, "the legacy list projects into a table")
	assert_eq(
		String(projected.id), "legacy:probe_projected_loot_bear", "under a declared legacy id"
	)
	assert_eq(bool(projected.allow_empty), true, "a projection may legitimately drop nothing")
	assert_eq(projected.entries.size(), (record["loot"] as Array).size(), "one entry per item")
	for entry in projected.entries:
		assert_almost_eq(entry.weight, 1.0, "a projection is uniform")
	assert_eq(
		String(content.table_for_boss(legacy_boss, 0).id),
		String(projected.id),
		"and the projection is stable across calls"
	)
	for item_id in projected.reachable_item_ids():
		assert_ne(content.definition(item_id), null, "%s resolves" % String(item_id))
	# An empty legacy list really produces nothing.
	var empty := content.project_legacy(&"loot_probe_empty_boss", [] as Array[StringName])
	assert_eq(empty.entries.is_empty(), true, "no entries")
	assert_eq(bool(empty.allow_empty), true, "declared as a no-drop table")


## Nothing is silently swallowed: an unknown stash, an unknown reward, an unknown
## domain, an unknown tier and a strike with nothing to hit each report their own
## reason.
func test_every_refusal_is_diagnosed_rather_than_silent() -> void:
	var actor := _hero()
	assert_eq(bool(LootApi.reclaim(actor, "no_such_stash")["ok"]), false, "an unknown stash")
	assert_eq(
		String(LootApi.reclaim(actor, "no_such_stash")["reason"]),
		LootState.ERR_UNKNOWN_STASH,
		"with its own reason"
	)
	assert_eq(
		String(LootApi.reward(actor, "no_such_encounter")["reason"]),
		LootState.ERR_UNKNOWN_REWARD,
		"an unknown reward too"
	)
	assert_eq(
		String(LootApi.pickup(actor, "no_such_encounter", "d")["reason"]),
		LootState.ERR_UNKNOWN_REWARD,
		"and a pickup of one"
	)
	assert_eq(
		String(LootApi.strike(actor, 5.0)["reason"]),
		LootState.ERR_NOT_IN_DOMAIN,
		"striking nothing"
	)
	assert_eq(
		String(LootApi.enter_domain(actor, &"no_such_domain", 0)["reason"]),
		LootState.ERR_UNKNOWN_DOMAIN,
		"entering an un-authored domain"
	)
	assert_eq(
		String(LootApi.enter_domain(actor, EMBER_DOMAIN, 99)["reason"]),
		LootState.ERR_UNKNOWN_TIER,
		"an un-authored tier"
	)


## Entering twice is refused rather than silently restarting the run.
func test_entering_twice_is_refused() -> void:
	var actor := _hero()
	assert_eq(bool(LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 4)["ok"]), true, "entered")
	var second := LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, 4)
	assert_eq(bool(second["ok"]), false, "a second entry is refused")
	assert_eq(String(second["reason"]), LootState.ERR_ALREADY_IN_DOMAIN, "with its reason")
	assert_eq(bool(LootApi.abandon(actor)["ok"]), true, "the first leave works")
	assert_eq(
		String(LootApi.abandon(actor)["reason"]),
		LootState.ERR_NOT_IN_DOMAIN,
		"leaving twice is refused"
	)
