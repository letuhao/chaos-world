extends "res://tests/acquisition/qi_cultivation_acquisition_fixture.gd"


func test_every_qi_realm_authors_three_resolvable_craft_chains() -> void:
	var realms := _realms()
	assert_eq(realms.size(), REALM_COUNT, "30 qi realms are authored")
	var first_broken := ""
	for realm_id in realms:
		first_broken = _chain_broken(realm_id)
		if not first_broken.is_empty():
			break
	assert_eq(first_broken, "", "every qi realm's craft chain resolves")


## The ladder is OBTAINABLE, part one: every boss the chain names is a real boss,
## hosted by an authored encounter, in the domain its own record declares.


func test_every_qi_boss_source_is_a_real_boss_hosted_in_its_own_domain() -> void:
	var bosses := _catalyst_bosses()
	assert_eq(bosses.is_empty(), false, "the qi chain names at least one boss")
	var hosts := 0
	for boss_id in bosses:
		var domain_id := _domain_of(boss_id)
		assert_eq(domain_id.is_empty(), false, "%s declares a domain" % boss_id)
		if domain_id.is_empty():
			continue
		var encounter := LootContent.instance().encounter_for_domain(StringName(domain_id))
		if encounter == null:
			assert_eq(
				String(domain_id).is_empty(),
				false,
				"%s is hosted (no encounter for %s)" % [boss_id, domain_id]
			)
			continue
		hosts += 1
		assert_eq(
			(encounter.boss_ids as Array).has(StringName(boss_id)),
			true,
			"the %s encounter spawns %s" % [domain_id, boss_id]
		)
	assert_eq(hosts, bosses.size(), "every boss the qi chain names is enterable")


## One authority per domain: a reached domain carries exactly one encounter, which
## spawns every boss the domain declares, with every band binding a table that
## resolves. `encounter_for_domain` answers with the first match, so a second
## encounter is invisible elsewhere: the loser sits on disk holding a spawnable boss.
##
## Judged over every domain the chain names by ANY route, because a `domain:` ref
## points at a trial the qi path does not own: `boss:` refs alone left 36 unjudged.


func test_every_qi_chain_domain_carries_one_encounter_that_spawns_what_it_declares() -> void:
	var content := LootContent.instance()
	var claims: Dictionary = {}
	for encounter_id in content.encounter_ids():
		var encounter := content.encounter_by_id(StringName(encounter_id))
		if encounter == null:
			continue
		var ids: Array = claims.get(String(encounter.domain_id), [])
		ids.append(String(encounter.id))
		claims[String(encounter.domain_id)] = ids
	var reached := 0
	var bands := 0
	for domain_id in _chain_domains():
		var ids: Array = claims.get(domain_id, [])
		assert_eq(ids.size(), 1, "%s carries exactly one encounter" % domain_id)
		if ids.size() != 1:
			continue
		var encounter := content.encounter_by_id(StringName(ids[0]))
		reached += 1
		for boss_id in content.domain_record(StringName(domain_id))["boss_ids"] as Array:
			assert_eq(
				(encounter.boss_ids as Array).has(String(boss_id)),
				true,
				"%s hosts the %s the domain lists" % [domain_id, boss_id]
			)
		for tier in encounter.tiers:
			assert_ne(tier, null, "%s has a resolvable band" % domain_id)
			if tier == null:
				continue
			bands += 1
			for listed in encounter.boss_ids:
				var table_id := String(tier.table_for(listed))
				assert_ne(table_id, "", "%s binds %s at band %d" % [domain_id, listed, tier.tier])
				assert_ne(
					content.table(table_id), null, "%s resolves table %s" % [domain_id, table_id]
				)
	assert_eq(reached, CHAIN_DOMAIN_COUNT, "the qi chain reaches exactly 77 domains")
	assert_eq(bands > reached, true, "every reached domain has more than one band")


## DEF-0187, asserted rather than pinned. A cleared band grants no second run (loot
## rule E2), so a consumable a boss drops DIRECTLY must be a guaranteed entry of that
## boss's own lowest-band table. All 15 are now, which is what `ddc9229d` did, so the
## CONSUMABLE rolled set is asserted EMPTY. A REAGENT is judged separately, and by the
## stronger route below: a recipe consumes it however the boss hands it over, so this
## test only reports which boss-dropped reagents exist, and
## `test_every_boss_dropped_qi_reagent_is_paid_unconditionally_on_every_clear` proves
## every one of them arrives. Asserting an empty set here would still be true if a
## boss stopped dropping the reagent at all, which is why this file pins the SET and
## that test pins the deliveries.


func test_every_boss_dropped_qi_consumable_is_guaranteed_at_the_lowest_band() -> void:
	var content := LootContent.instance()
	var guaranteed := 0
	var rolled: Array[String] = []
	var dropped_reagents: Array[String] = []
	var direct: Array[String] = []
	for item_id in _chain_items():
		var is_pill := _is_consumable(item_id)
		var boss_ids := _refs_of(item_id, ItemSources.KIND_BOSS)
		for boss_id in boss_ids:
			var domain_id := _domain_of(boss_id)
			if domain_id.is_empty():
				continue
			var encounter := content.encounter_for_domain(StringName(domain_id))
			# A boss this domain's encounter does not host is tested by the test
			# above; judging its table here would report another domain's content.
			if encounter == null or not (encounter.boss_ids as Array).has(StringName(boss_id)):
				continue
			var lowest := _first_tier(domain_id)
			var reaches := false
			var unconditional := false
			for tier in encounter.tiers:
				if tier == null or tier.tier != lowest:
					continue
				var table_id := String(tier.table_for(StringName(boss_id)))
				if table_id.is_empty():
					continue
				reaches = _reaches(content, table_id, item_id, false)
				unconditional = _reaches(content, table_id, item_id, true)
			assert_eq(
				reaches, true, "%s is droppable by %s at band %d" % [item_id, boss_id, lowest]
			)
			if unconditional:
				guaranteed += 1
			if not is_pill and not dropped_reagents.has(item_id):
				dropped_reagents.append(item_id)
			if reaches and not unconditional and is_pill:
				rolled.append(item_id)
		if is_pill and not boss_ids.is_empty():
			direct.append(item_id)
	rolled.sort()
	dropped_reagents.sort()
	direct.sort()
	assert_eq(guaranteed > 0, true, "at least one qi catalyst is guaranteed")
	assert_eq(
		direct,
		BOSS_DROPPED_CONSUMABLES as Array[String],
		"the qi consumables a boss drops directly; every one must be a guaranteed entry"
	)
	assert_eq(
		rolled,
		[] as Array[String],
		(
			"no boss-dropped qi consumable is left to a roll — a cleared band grants no"
			+ " second run, so each of these is a permanent soft-lock"
		)
	)
	assert_eq(
		dropped_reagents,
		PINNED_BOSS_DROPPED_REAGENTS,
		(
			"exactly these qi reagents are handed over by a boss; a set pin, so a table that"
			+ " stops naming one and a table that starts naming one both go red"
		)
	)

## The ladder is OBTAINABLE, part two: nothing rests on a route kind no shipping
## code implements, judged by the same membership rules `tools/data.py` uses, so
## `gather`/`quest`-only material is caught rather than assumed acquirable. This
## is DEF-0188's pin, re-declared at 0.
