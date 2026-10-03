extends TestCase

## A band's authored vitality also prices the boss's own combat numbers (ADR 0076), and
## that profile is frozen into the spawned boss rather than re-derived per exchange.

const EMBER_DOMAIN := &"loot_ember_vault_domain"
const EMBER_TIER := 1
const DEEP_DOMAIN := &"elemental_transcendent_domain"
const DEEP_TIER := 1
const SEED := 606


func _delver() -> Actor:
	var actor := Actor.new(&"delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor)
	LootApi.attach(actor)
	return actor


func _tier(encounter_id: StringName, tier_index: int) -> LootTier:
	return LootContent.instance().encounter_by_id(encounter_id).tier_at(tier_index)


func _active(actor: Actor) -> Dictionary:
	return LootApi.summary(actor).get("active", {}) as Dictionary


func test_a_bosss_numbers_are_a_multiple_of_the_vitality_its_band_already_authors() -> void:
	var tier := _tier(&"loot_route_elemental_transcendent_domain", DEEP_TIER)
	assert_ne(tier, null, "the authored band loads")
	var boss_id := tier.boss_ids()[0]
	assert_almost_eq(
		tier.attack_for(boss_id),
		tier.vitality_for(boss_id) * LootTier.ATTACK_PER_VITALITY,
		"its attack is priced off its own authored vitality"
	)
	assert_almost_eq(
		tier.defense_for(boss_id),
		tier.vitality_for(boss_id) * LootTier.DEFENSE_PER_VITALITY,
		"as is its defense"
	)


func test_a_weaker_binding_is_weaker_in_both_directions() -> void:
	# The authored ember vault binds a trash mob at 45 vitality beside a warden at 100.
	# One authored number has to price both halves of an encounter, so the relationship
	# has to hold per binding and not only per band.
	var tier := _tier(&"loot_ember_vault", EMBER_TIER)
	var weak := 0.0
	var strong := 0.0
	for boss_id in tier.boss_ids():
		if tier.vitality_for(boss_id) < tier.vitality:
			weak = tier.attack_for(boss_id)
		else:
			strong = tier.attack_for(boss_id)
	assert_eq(weak > 0.0, true, "the band binds a weaker boss")
	assert_eq(weak < strong, true, "and the weaker boss hits back less hard")


func test_the_spawned_boss_carries_the_profile_it_was_priced_with() -> void:
	var actor := _delver()
	LootApi.enter_domain(actor, DEEP_DOMAIN, DEEP_TIER, SEED)
	var active := _active(actor)
	var tier := _tier(&"loot_route_elemental_transcendent_domain", DEEP_TIER)
	var boss_id := StringName(active["boss_id"])
	assert_almost_eq(float(active["attack"]), tier.attack_for(boss_id), "the frozen attack matches")
	assert_almost_eq(float(active["defense"]), tier.defense_for(boss_id), "and so does the defense")


func test_no_boss_is_live_with_no_numbers() -> void:
	# `LootRewards.active_view` is what `CombatApi` reads; an absent live boss must carry
	# zeros, not stale keys, so a caller can read one bundle shape unconditionally.
	var view := LootRewards.active_view({})
	assert_eq(bool(view["in_domain"]), false, "nobody is in a domain")
	assert_eq(float(view["attack"]), 0.0, "so there is no attack to meet")
	assert_eq(float(view["defense"]), 0.0, "and no defense either")


func test_a_run_in_flight_keeps_the_profile_it_was_priced_with() -> void:
	# The profile is frozen into the spawned boss rather than re-derived per exchange, so a
	# retuned content file cannot change the terms of a fight already under way. Proved by
	# moving the authored number underneath a live run.
	var actor := _delver()
	LootApi.enter_domain(actor, DEEP_DOMAIN, DEEP_TIER, SEED)
	var priced := float(_active(actor)["attack"])
	assert_eq(priced > 0.0, true, "the boss was priced when it spawned")
	var tier := _tier(&"loot_route_elemental_transcendent_domain", DEEP_TIER)
	var authored := tier.vitality
	tier.vitality = authored * 4.0
	assert_eq(
		float(_active(actor)["attack"]),
		priced,
		"and the live boss still fights on the price it was spawned at"
	)
	tier.vitality = authored
	assert_eq(float(_active(actor)["attack"]), priced, "and restoring the content restores it")


func test_every_authored_band_prices_its_bosses_a_fight_it_can_lose() -> void:
	# The floor that keeps an encounter winnable has to hold across the *shipped* content,
	# not just one hand-picked band: an authored vitality small enough to be spent in one
	# exchange is fine, and one so large that `MIN_SHARE` never closes it is not.
	var content := LootContent.instance()
	var bands := 0
	for encounter_id in content.encounter_ids():
		var encounter := content.encounter_by_id(StringName(encounter_id))
		for tier in encounter.tiers:
			if tier == null:
				continue
			bands += 1
			for boss_id in tier.boss_ids():
				var vitality := tier.vitality_for(boss_id)
				assert_eq(vitality > 0.0, true, "%s/%s has vitality" % [encounter_id, boss_id])
				var presses := ceilf(vitality / (vitality * CombatDamage.MIN_SHARE))
				assert_eq(
					presses <= 400.0,
					true,
					"%s/%s closes within a bounded number of exchanges" % [encounter_id, boss_id]
				)
	assert_eq(bands > 0, true, "the shipped content actually has bands to check")


func test_the_profile_adds_no_rule_the_authored_content_can_fail() -> void:
	# Deliberately NOT "the content is valid": a test that reported another owner's content
	# drift as this suite's failure would be reporting the wrong thing. What is asserted is
	# narrower and is this change's own claim: pricing a boss from its band's vitality, and
	# giving it an authored profile, introduced no validation rule of its own, so no reported
	# problem is about either.
	#
	# Counted rather than asserted per problem, because a per-problem loop over an EMPTY
	# array asserts nothing at all — and a test that passes by having nothing to say is not a
	# test. This ran exactly that way while the corpus was briefly clean, and the runner named
	# it (`asserted nothing`); the count is unconditional so it cannot.
	var problems := LootApi.validate(LootValidator.SCOPE_ENCOUNTERS)
	var about_the_boss := 0
	for problem in problems:
		if problem.contains("attack") or problem.contains("defense"):
			about_the_boss += 1
	assert_eq(
		about_the_boss, 0, "no validator problem is about a boss's own numbers: %s" % str(problems)
	)
