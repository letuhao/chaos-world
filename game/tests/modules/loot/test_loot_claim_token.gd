extends TestCase

## The headline invariant: one boss defeat yields exactly one reward payload.
##
## Rule E1 makes the encounter id the claim token, and it is derived only from
## `(domain, boss, tier, run)` — never from a clock, a call count or a reload. So a
## repeated defeat, a re-entry and a save/load all resolve the same token and none of
## them can mint a second payload. Each case below is proved *through the screen*,
## because a player reaching the same state twice must not be able to farm the boss.

var _rig: LootScreenRig = null


func setup() -> void:
	_rig = LootScreenRig.new()


## The baseline every other case compares against: one defeat, one payload.
func test_one_defeat_mints_exactly_one_payload() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	var dead := _rig.defeat_boss(view)
	assert_ne(dead, "", "the boss was defeated")
	var state := view.summary()
	assert_eq(int(state["reward_count"]), 1, "exactly one payload exists")
	assert_eq(int(state["claimed_encounters"]), 0, "and no claim has been spent yet")
	assert_eq(String(state["reward_encounter_id"]), dead, "the payload is claimable")


## A strike with nothing to strike is refused, so the screen can never hand the same
## boss a second death event. This is the UI half of rule E1: the control exists, the
## actor says no, and no payload appears.
func test_a_strike_with_no_live_boss_is_refused_and_mints_nothing() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	var dead := _rig.defeat_boss(view)
	var before := _payloads(actor)
	assert_eq(before.size(), 1, "one payload after the first defeat")

	_rig.press(view, "%LeaveButton")
	assert_eq(bool(view.summary()["in_domain"]), false, "no boss is live any more")
	for _again in 3:
		_rig.press(view, "%StrikeButton")
	var refused := view.summary()
	assert_eq(
		String(refused["message"]),
		"Rejected: not_in_domain",
		"every strike with no boss is refused and says why"
	)
	assert_eq(_payloads(actor), before, "and no payload was minted or changed")
	assert_eq(int(refused["reward_count"]), 1, "the one payload is still the only one")


## Leaving and coming back resolves the same token: rule E4 resumes the run at the
## first boss with no reward, so a boss that already paid is never fought twice.
func test_a_re_entry_does_not_re_mint_the_dead_bosss_payload() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	var dead := _rig.defeat_boss(view)
	var before := _payloads(actor)
	assert_eq(before.size(), 1, "one payload before leaving")

	assert_eq(_rig.press(view, "%LeaveButton"), true, "the Leave control runs")
	var outside := view.summary()
	assert_eq(bool(outside["in_domain"]), false, "the domain is left")
	assert_eq(int(outside["reward_count"]), 1, "and the unclaimed reward is kept")

	_rig.press(view, "%EnterButton")
	var resumed := view.summary()
	assert_eq(bool(resumed["in_domain"]), true, "the run is resumed")
	# The point is not that the id differs — a fresh run number would differ too — it
	# is that the boss which already paid is not put back on screen.
	assert_ne(
		_boss_of(resumed["encounter_id"]),
		_boss_of(dead),
		"the boss that already paid is not the one put back in front of the player"
	)
	assert_ne(String(resumed["encounter_id"]), dead, "and the encounter is a new one")
	assert_eq(_payloads(actor), before, "the original payload is unchanged")
	assert_eq(int(resumed["reward_count"]), 1, "and no second payload was minted")

	# Fighting on from here pays the new boss once, and still leaves the first payload
	# exactly as it was.
	var resumed_dead := _rig.defeat_boss(view)
	assert_ne(resumed_dead, "", "the resumed run fights its first undefeated boss")
	assert_ne(
		_boss_of(resumed_dead),
		_boss_of(dead),
		"which is a different boss from the one that already paid"
	)
	assert_eq(int(view.summary()["reward_count"]), 2, "one payload per boss, still")
	assert_eq(_payload_for(actor, dead), before[0], "and the first payload is untouched")


## A save/load between defeat and pickup is the case that would quietly re-roll: the
## rolls are realized at defeat time and must come back identical, still under one
## token, still worth exactly one payload.
func test_a_save_load_between_defeat_and_pickup_keeps_one_payload_and_its_rolls() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	var dead := _rig.defeat_boss(view)
	var before := _payloads(actor)
	var before_rows := _row_identities(_rig.listed_reward(view)["rows"] as Array)

	# Round-trip through JSON, the way a file save does: this is where a nested
	# StringName key would quietly become a String and change an id.
	var restored = JSON.parse_string(JSON.stringify(actor.to_dict()))
	assert_eq(restored is Dictionary, true, "the actor payload survives a JSON round trip")
	var loaded := Actor.from_dict(restored as Dictionary)
	ItemsApi.attach(loaded, 24)
	LootApi.attach(loaded)

	# A fresh screen over the loaded actor: the player's reload is the pipeline.
	var reloaded := _rig.screen(loaded)
	var state := reloaded.summary()
	assert_eq(int(state["reward_count"]), 1, "the unclaimed reward came back exactly once")
	assert_eq(int(state["claimed_encounters"]), 0, "and no claim was spent by saving")
	assert_eq(String(state["reward_encounter_id"]), dead, "under the same claim token")
	assert_eq(_payloads(loaded), before, "with the same realization: drops, rolls and affixes")
	assert_eq(
		_row_identities((state["reward"] as Dictionary)["rows"] as Array),
		before_rows,
		"and the screen shows the very same rows it did before the reload"
	)

	# The loaded run plays on without re-minting what it already owes.
	assert_ne(_rig.defeat_boss(reloaded), dead, "the next boss of the run is fought")
	assert_eq(int(reloaded.summary()["reward_count"]), 2, "still one payload per boss")
	assert_eq(_payload_for(loaded, dead), before[0], "the first payload is byte for byte intact")


## Once the claim is spent the payload moves to the ledger and nothing can address it
## again: taking it a second time is refused, not served from a second payload.
func test_a_spent_claim_cannot_be_served_twice() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	var dead := _rig.defeat_boss(view)
	_rig.take_all(view)
	var spent := view.summary()
	assert_eq(int(spent["reward_count"]), 0, "the payload left the outstanding list")
	assert_eq(int(spent["claimed_encounters"]), 1, "the ledger records exactly one spend")

	_rig.take_all(view)
	var again := view.summary()
	assert_eq(
		_rig.take_all_offered(view),
		false,
		"with no payload on screen the action is not even offered"
	)
	assert_eq(
		String(again["message"]),
		"Rejected: no_reward_selected",
		"and invoked anyway it is refused and says why"
	)
	assert_eq(int(again["reward_count"]), 0, "nothing came back")
	assert_eq(int(again["claimed_encounters"]), 1, "and the ledger did not grow")
	assert_eq(String(again["reward_encounter_id"]), "", "no payload is listed")
	assert_eq(
		bool(LootApi.reward(actor, dead)["ok"]),
		false,
		"the facade reports the claim as spent rather than as unknown"
	)
	assert_eq(
		String(LootApi.reward(actor, dead)["reason"]),
		LootState.ERR_CLAIM_SPENT,
		"and names the reason"
	)


## Every boss of a run pays exactly once, and a cleared run can never pay again.
func test_every_boss_of_a_run_pays_exactly_once() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	var tokens: Array = []
	for _boss in LootScreenRig.EMBER_BOSS_COUNT:
		var dead := _rig.defeat_boss(view)
		if dead.is_empty():
			break
		tokens.append(dead)
	assert_eq(tokens.size(), LootScreenRig.EMBER_BOSS_COUNT, "every boss of the run was fought")
	assert_eq(
		_payloads(actor).size(), LootScreenRig.EMBER_BOSS_COUNT, "one payload per boss, no more"
	)
	assert_eq(_distinct(tokens).size(), tokens.size(), "and every one is a distinct encounter")

	assert_eq(bool(view.summary()["in_domain"]), false, "the run cleared")
	for _again in 3:
		_rig.press(view, "%StrikeButton")
	assert_eq(
		_payloads(actor).size(),
		LootScreenRig.EMBER_BOSS_COUNT,
		"striking a cleared run mints nothing at all"
	)


## A fingerprint of every outstanding payload: encounter id, claim token, seed and
## each drop's full realization. Two fingerprints being equal means nothing was
## re-rolled and nothing was added.
func _payloads(actor: Actor) -> Array:
	var rewards := (
		LootState.normalize(actor.get_module_data(LootState.MODULE_KEY))["rewards"] as Dictionary
	)
	var out: Array = []
	for token in rewards.keys():
		var payload := rewards[token] as Dictionary
		(
			out
			. append(
				{
					"encounter_id": String(payload.get("encounter_id", "")),
					"claim_token": String(payload.get("claim_token", "")),
					"seed": int(payload.get("seed", 0)),
					"drops": _drop_identities(payload.get("drops", [])),
				}
			)
		)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["encounter_id"] < b["encounter_id"]
	)
	return out


func _payload_for(actor: Actor, encounter_id: String) -> Dictionary:
	for payload in _payloads(actor):
		if String(payload["encounter_id"]) == encounter_id:
			return payload
	return {}


## The realized identity of each drop: id, quantity, rarity, realm and the instance
## it was built with, rolls included.
func _drop_identities(drops: Array) -> Array:
	var out: Array = []
	for drop in drops:
		var entry := drop as Dictionary
		(
			out
			. append(
				{
					"drop_id": String(entry.get("drop_id", "")),
					"quantity": int(entry.get("quantity", 0)),
					"rarity": String(entry.get("rarity", "")),
					"realm": String(entry.get("realm", "")),
					"instance": _instance_fingerprint(entry.get("instance", {})),
				}
			)
		)
	return out


## The same identity read off a rendered row, so the screen and the save file can be
## compared: a row carries the instance id rather than the whole realization.
func _row_identities(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		var entry := row as Dictionary
		(
			out
			. append(
				{
					"drop_id": String(entry.get("drop_id", "")),
					"quantity": int(entry.get("quantity", 0)),
					"rarity": String(entry.get("rarity", "")),
					"realm": String(entry.get("realm", "")),
					"instance_id": String(entry.get("instance_id", "")),
					"effects": entry.get("effects", []),
				}
			)
		)
	return out


## One instance as comparable primitives: what it is, how rolled it is, and every
## affix with the window it was legally rolled from. Normalized rather than raw
## because a JSON round trip widens ints to floats, and `2` becoming `2.0` is not a
## different roll.
func _instance_fingerprint(instance: Dictionary) -> Array:
	var rolled: Array = []
	for effect in instance.get("rolled", []):
		var affix := effect as Dictionary
		(
			rolled
			. append(
				(
					"|"
					. join(
						PackedStringArray(
							[
								String(affix.get("option_id", "")),
								String(affix.get("target_id", "")),
								String(affix.get("op", "")),
								String(affix.get("scope", "")),
								String(affix.get("channel", "")),
								String(affix.get("family", "")),
								"%.4f" % float(affix.get("value", 0.0)),
								"%.4f" % float(affix.get("value_min", 0.0)),
								"%.4f" % float(affix.get("value_max", 0.0)),
							]
						)
					)
				)
			)
		)
	return [
		String(instance.get("def_id", "")),
		String(instance.get("instance_id", "")),
		String(instance.get("rarity", "")),
		String(instance.get("realm", "")),
		"%.4f" % float(instance.get("durability", 1.0)),
		"%.4f" % float(instance.get("refinement", 0.0)),
		rolled,
	]


func _distinct(values: Array) -> Dictionary:
	var out: Dictionary = {}
	for value in values:
		out[String(value)] = true
	return out


## The boss an encounter id names. Ids are `domain/boss@tier#run`, so the boss is the
## middle segment: comparing bosses is what distinguishes "the run resumed past the
## boss that already paid" from "the run restarted and put it back on screen".
func _boss_of(encounter_id: String) -> String:
	var parts := String(encounter_id).split("/")
	if parts.size() < 2:
		return ""
	return parts[1].split("@")[0]
