extends "res://tests/acquisition/qi_cultivation_acquisition_fixture.gd"


func test_no_qi_chain_item_rests_only_on_a_route_kind_nothing_ships() -> void:
	var chain := _chain_items()
	# "Every chain item" is unfalsifiable without a size: a recipe that quietly loses an
	# input shrinks the graph this file audits, and every walk below would still pass over
	# the smaller one. Pinned like CHAIN_DOMAIN_COUNT, so the audit's own width is asserted.
	assert_eq(
		chain.size(), CHAIN_ITEM_COUNT, "the qi chain is CHAIN_ITEM_COUNT items wide, as pinned"
	)
	var unshipped: Array[String] = []
	var other: Array[String] = []
	var exercised: Array[String] = []
	for item_id in chain:
		for kind in _kinds(item_id):
			if not exercised.has(kind):
				exercised.append(kind)
			assert_eq(
				ItemSources.knows(StringName(kind)),
				true,
				"%s declares %s, which is outside the ItemSources vocabulary" % [item_id, kind]
			)
		if _has_shipped_route(item_id):
			continue
		unshipped.append(item_id)
		for kind in _kinds(item_id):
			# An item with no shipped route must be ENTIRELY unshipped. One declaring a
			# shipped kind alongside these would be a real break wearing the gap's name.
			if ItemSources.is_shipped(StringName(kind)):
				other.append("%s declares shipped kind %s but resolves no route" % [item_id, kind])
	for consumable in _consumables():
		var entry := consumable as Dictionary
		var reason := _blocker(String(entry["item"]), 0, [])
		if not reason.is_empty() and not reason.contains(UNSHIPPED_MARKER):
			other.append("%s %s: %s" % [entry["realm"], entry["role"], reason])
	unshipped.sort()
	exercised.sort()
	assert_eq(other, [] as Array[String], "no qi hop is unreachable for any reason")
	assert_eq(
		unshipped.size(),
		PINNED_UNSHIPPED_REAGENTS,
		"no qi chain item rests only on gather/quest — the DEF-0188 gap stays closed"
	)
	assert_eq(
		exercised,
		PINNED_CHAIN_KINDS,
		(
			"the exact route kinds the qi chain exercises, as a SET: a kind that stops being"
			+ " declared and one that starts both name themselves in this diff. No item has ever"
			+ " declared `quest`, so pinning it asserted the impossible and looked like coverage"
		)
	)


func _has_shipped_route(item_id: String) -> bool:
	var def := _def(item_id)
	if def == null:
		return false
	for route in ItemSources.routes(def):
		if bool(route["ok"]) and ItemSources.is_shipped(StringName(route["kind"])):
			return true
	return false


## DEF-0199, asserted in its STRONG direction. Every hop closes, so the only thing
## left between a player and a consumable is whether ONE clear delivers it — and rule
## E2 grants no retry. It was 41; it is 0.
##
## The roll-only set is asserted as a SET against `[]`, never as a count, because the
## failure message is the evidence: one regressed consumable prints its own id, so the
## message names the offender instead of saying "41 != 0". The per-role dictionary is
## kept for a different reason — an aggregate total would let one realm regress while
## another improved. The realm-coverage assertion is replaced rather than inverted:
## "every realm has a gap" was true only while the gap existed, so its negation now
## carries the claim — every realm's three consumables are certain.


func test_every_qi_consumable_is_obtainable_on_every_single_clear() -> void:
	var rolled: Array[String] = []
	var by_role: Dictionary = {}
	for role in CONSUMABLE_ROLES:
		by_role[role] = 0
	var realms_with_a_gap: Array[String] = []
	for realm_id in _realms():
		var plan := _realm_plan(realm_id)
		var gapped := plan["rolled"] as Array[String]
		if not gapped.is_empty():
			realms_with_a_gap.append(realm_id)
	for consumable in _consumables():
		var entry := consumable as Dictionary
		var item_id := String(entry["item"])
		if _certain(item_id, 0, []):
			continue
		rolled.append(item_id)
		by_role[entry["role"]] = int(by_role[entry["role"]]) + 1
	rolled.sort()
	assert_eq(
		by_role, PINNED_ROLLED_BY_ROLE, "the per-role count of qi consumables one clear can miss"
	)
	assert_eq(
		rolled,
		[] as Array[String],
		(
			"exactly which qi consumables are obtainable only on a roll — a cleared band"
			+ " grants no second run, so every id named here is a permanent soft-lock"
		)
	)
	assert_eq(
		realms_with_a_gap,
		[] as Array[String],
		(
			"every qi realm's three consumables are acquirable on every clear; these realms"
			+ " still name at least one a single clear can miss"
		)
	)


## DEF-0199's second half, and the assertion that keeps the first honest. "No reagent
## is left to a roll" is also what a boss that stopped dropping one entirely looks
## like, so this walks every `(reagent, boss, lowest-band table)` triple the chain
## names and requires each one to be REACHED UNCONDITIONALLY — every hop `guaranteed`,
## the hop into a nested pool included. A pool is one weighted candidate among many on
## its parent's table, so a `guaranteed = true` entry under a rolled pool is still
## rolled; 26 `qi_<realm>_guardian_core` reagents read as safe for exactly that reason
## until the parent entries were fixed.
##
## The pinned COUNT is what separates "delivered" from "not delivered": the set pin
## elsewhere catches a table that stops naming a reagent, this catches nothing at all
## being delivered, and neither alone can tell those apart from a working route.
func test_every_boss_dropped_qi_reagent_is_paid_unconditionally_on_every_clear() -> void:
	var content := LootContent.instance()
	var triples := 0
	for item_id in _chain_items():
		if _is_consumable(item_id):
			continue
		for boss_id in _refs_of(item_id, ItemSources.KIND_BOSS):
			var domain_id := _domain_of(boss_id)
			if domain_id.is_empty():
				continue
			var encounter := content.encounter_for_domain(StringName(domain_id))
			if encounter == null or not (encounter.boss_ids as Array).has(StringName(boss_id)):
				continue
			var lowest := _first_tier(domain_id)
			for tier in encounter.tiers:
				if tier == null or tier.tier != lowest:
					continue
				var table_id := String(tier.table_for(StringName(boss_id)))
				if table_id.is_empty():
					continue
				triples += 1
				assert_eq(
					_reaches(content, table_id, item_id, true),
					true,
					(
						(
							"%s must be a guaranteed entry of %s at band %d — every hop included,"
							% [item_id, table_id, lowest]
						)
						+ " a cleared band grants no second run"
					)
				)
	assert_eq(
		triples,
		PINNED_REAGENT_DELIVERIES,
		"the number of (qi reagent, boss, lowest-band table) deliveries the chain names"
	)


## The end-to-end proof, per realm, exactly as the body twin does it: a fresh delver
## hunts the domains that realm's certain chain names and ends up holding every
## consumable rule E2 guarantees. Each realm is walked alone because a hunt is per
## actor and one clear is the only one a player gets. This is the chain a player
## walks, and the qi gate audits never exercise it because `Probe.stock` grants items
## outright.
##
## Two ways to hold a certain consumable, both counted: the 15 pinned direct drops
## arrive in the bag from their own domains' hunts, and the rest are crafted. A
## guaranteed drop is never
## re-crafted, because its recipe can name a rolled reagent, so insisting on the craft
## would assert something no player needs to do. Nothing is left to the roll any more,
## so there is no longer a class of consumable that is merely counted rather than
## acquired — which is why this no longer depends on the hunt seed for its total.


func test_every_certain_qi_consumable_is_held_end_to_end_from_its_own_domains() -> void:
	var realms := _realms()
	assert_eq(realms.size(), REALM_COUNT, "30 realms are walked")
	var crafted := 0
	var dropped := 0
	var dropped_ids: Array[String] = []
	var rolled := 0
	var first_failure := ""
	for realm_id in realms:
		var plan := _realm_plan(realm_id)
		var certain := plan["certain"] as Array[String]
		rolled += (plan["rolled"] as Array[String]).size()
		if certain.is_empty():
			continue
		var actor := _hero()
		for domain_id in plan["domains"] as Array[String]:
			var reason := _hunt(actor, domain_id, _first_tier(domain_id))
			if reason != "claimed":
				first_failure = "%s: hunting %s stopped: %s" % [realm_id, domain_id, reason]
				break
		if not first_failure.is_empty():
			break
		for item_id in certain:
			if ItemsApi.has_item(actor, StringName(item_id)):
				dropped += 1
				dropped_ids.append(item_id)
				continue
			var recipe := _recipe(_craft_recipe(item_id))
			if recipe == null:
				first_failure = "%s: %s has no loadable recipe" % [realm_id, item_id]
				break
			if not ItemsApi.craft(recipe, ItemsApi.inventory(actor)):
				first_failure = (
					"%s: crafting %s failed, %s" % [realm_id, item_id, _short(recipe, actor)]
				)
				break
			if not ItemsApi.has_item(actor, StringName(item_id)):
				first_failure = "%s: crafted %s but the bag does not hold it" % [realm_id, item_id]
				break
			crafted += 1
		if not first_failure.is_empty():
			break
	assert_eq(
		first_failure, "", "every certain qi consumable is held after hunting its own domains"
	)
	assert_eq(
		crafted + dropped + rolled,
		REALM_COUNT * CONSUMABLE_ROLES.size(),
		"every qi consumable was crafted, dropped, or is named as the roll gap"
	)
	# Derived, not typed: 30 realms x 3 roles is the whole ladder, so a typo in this
	# number cannot be what keeps the assertion honest — the three below cannot all hold
	# unless every one of the 90 arrived.
	assert_eq(
		crafted + dropped,
		REALM_COUNT * CONSUMABLE_ROLES.size(),
		"all 90 qi consumables are acquirable on every single clear"
	)
	# The GUARANTEE is the route this asserts, not the exact split. Every pinned direct
	# drop must be in the bag straight after its own domains' hunts — that is the claim
	# the 15 exist to make. The COUNT is deliberately not pinned: a rolled pool can hand
	# a craft-certain consumable over as a side drop too, and "the player got an extra
	# elixir" is not a defect. Pinning the count made this suite read the hunt seed's
	# roll stream instead of the acquisition program.
	var missing: Array[String] = []
	for item_id in BOSS_DROPPED_CONSUMABLES:
		if not dropped_ids.has(item_id):
			missing.append(item_id)
	missing.sort()
	assert_eq(
		missing,
		[] as Array[String],
		"every pinned boss-dropped consumable arrives as a guaranteed drop, not as a craft"
	)
	assert_eq(rolled, 0, "no qi consumable arrives only when the roll favours the player")
