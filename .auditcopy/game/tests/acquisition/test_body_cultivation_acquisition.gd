extends TestCase

## Body cultivation is playable only when every realm's three consumables can be
## acquired through the shipping program: hunt the realm's trial, take what its
## bosses drop, craft the pill.
##
## Nothing here hands an actor an `ItemDef`. Every assertion walks the authored
## acquisition graph — `ItemDef.sources` -> a recipe or a boss -> the domain that
## hosts that boss -> `LootApi` — because a source no shipping code can deliver is
## exactly the defect this suite exists to catch (ADR 0007, ADR 0033).
##
## Each hop is asserted separately, because they fail for different reasons:
##
##   sources        an authoring claim; on its own it proves nothing
##   enter_domain   an authored encounter must exist for the boss's domain
##   strike         the boss's authored table must actually yield the catalyst
##   pickup         the drop must reach the inventory, not a refused stash
##   craft          the recipe must turn the two reagents into the consumable
##
## Every loop is bounded and names the condition that failed to converge.

const REALM_DIR := "res://data/body_cultivation/realms/"
const DOMAIN_DIR := "res://data/domains/"
const REALM_COUNT := 30
## One strike spends this much vitality (the composition root's strike damage).
const STRIKE_DAMAGE := 25.0
## Stops when a boss's authored vitality stops falling. Names the condition: a
## table that never resolves a defeat would otherwise strike forever.
const MAX_STRIKES := 64
## Stops claiming payloads when nothing is pending. Names the condition: a drop
## that never leaves the pending state would otherwise be re-claimed forever.
const MAX_CLAIMS := 16
## Enough slots for every reagent and consumable a realm's three recipes need.
const INVENTORY_SLOTS := 64
const CONSUMABLE_ROLES := ["breakthrough_item", "strengthening_item", "recovery_item"]
## Id prefix of an encounter built to carry an authored boss's route table rather
## than to guarantee a realm's catalysts. One on a body trial domain means two
## agents claimed the same domain and the collision is unresolved.
const ROUTE_PREFIX := "loot_route_"
## `LootContent.MAX_NESTING_DEPTH`, mirrored so the walks over nested tables below
## stop where the resolver stops.
const MAX_TABLE_DEPTH := 4

## `Crafting.resolve` walks the whole item tree on a miss, and a `body_*` id
## misses its category guess, so the resolver is the one thing memoized here.
## Without it this suite re-walks 8,000 files per reagent and times the run out.
## Everything else is cheap to derive and is derived fresh, so no case's answer
## depends on which case happened to run first.
var _defs: Dictionary = {}

# --- The authored chain -----------------------------------------------------


## An `ItemDef` by id, through the items module's own single resolver.
func _def(item_id: String) -> ItemDef:
	if not _defs.has(item_id):
		_defs[item_id] = Crafting.resolve(StringName(item_id))
	return _defs[item_id] as ItemDef


## Every body realm id, from the authored seeds, sorted.
func _realms() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(REALM_DIR)
	assert_ne(dir, null, "the body realm seed directory opens")
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(".tres"):
			out.append(entry.trim_suffix(".tres"))
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## `{seed, consumables: [{role, item, recipe, reagents: [{item, bosses}]}]}`,
## resolved purely from authored data. A reagent with no `boss:` source is a
## finding in itself, not an empty list to walk past.
func _chain(realm_id: String) -> Dictionary:
	var seed := load(REALM_DIR + realm_id + ".tres") as BodyRealmSeed
	var consumables: Array = []
	for role in CONSUMABLE_ROLES:
		var item_id := "" if seed == null else String(seed.get(role))
		var recipe_id := ""
		if _def(item_id) != null:
			for source in _def(item_id).sources:
				if source.begins_with("craft:"):
					recipe_id = String(source).trim_prefix("craft:")
					break
		var recipe := load("res://data/recipes/%s.tres" % recipe_id) as RecipeDef
		var reagents: Array = []
		for input_id in recipe.inputs if recipe != null else [] as Array[StringName]:
			var bosses: Array[String] = []
			for source in _def(String(input_id)).sources:
				if source.begins_with("boss:"):
					bosses.append(String(source).trim_prefix("boss:"))
			reagents.append({"item": String(input_id), "bosses": bosses})
		consumables.append(
			{"role": role, "item": item_id, "recipe": recipe_id, "reagents": reagents}
		)
	return {"seed": seed, "consumables": consumables}


## boss id -> the reagent ids of `realm_id` that boss must drop.
func _catalysts_of(realm_id: String) -> Dictionary:
	var out: Dictionary = {}
	for consumable in _chain(realm_id)["consumables"] as Array:
		for reagent in consumable["reagents"] as Array:
			for boss_id in reagent["bosses"] as Array:
				var ids: Array = out.get(boss_id, [])
				ids.append(String(reagent["item"]))
				out[boss_id] = ids
	return out


## The domain that hosts `boss_id`, as its own boss record declares it.
func _domain_of(boss_id: String) -> String:
	return String(LootContent.instance().boss_record(StringName(boss_id))["domain_id"])


## Every catalyst boss the body path needs, from every realm's authored chain.
func _every_catalyst_boss() -> Array[String]:
	var out: Array[String] = []
	for realm_id in _realms():
		for boss_id in (_catalysts_of(realm_id) as Dictionary).keys():
			if not out.has(String(boss_id)):
				out.append(String(boss_id))
	out.sort()
	return out


## Every boss the body domains list, which is the set a body encounter hosts.
func _every_body_boss() -> Array[String]:
	var out: Array[String] = []
	for file_name in DirAccess.get_files_at(DOMAIN_DIR):
		if not file_name.begins_with("body_") or not file_name.ends_with(".tres"):
			continue
		var domain := load(DOMAIN_DIR + file_name) as DomainDef
		if domain == null:
			continue
		for boss_id in domain.boss_ids:
			if not out.has(String(boss_id)):
				out.append(String(boss_id))
	out.sort()
	return out


## Every body trial domain id, from the authored domains, sorted. The domain is the
## unit a hunt happens in, so it — not the boss — is what one encounter per means.
func _every_body_domain() -> Array[String]:
	var out: Array[String] = []
	for file_name in DirAccess.get_files_at(DOMAIN_DIR):
		if not file_name.begins_with("body_") or not file_name.ends_with(".tres"):
			continue
		out.append(file_name.trim_suffix(".tres"))
	out.sort()
	return out


# --- The shipping program ---------------------------------------------------


## The lowest band a domain's own encounter declares, as `enter_domain` spells
## it. Read from the content rather than assumed to be 0: a tier index nothing
## authored is an `unknown_tier` refusal that reads as a wiring failure.
func _first_tier(domain_id: String) -> int:
	var encounter := LootContent.instance().encounter_for_domain(StringName(domain_id))
	if encounter == null or encounter.tiers.is_empty():
		return -1
	var lowest := encounter.tiers[0].tier
	for tier in encounter.tiers:
		if tier != null:
			lowest = mini(lowest, tier.tier)
	return lowest


## A delver with the loot lifecycle and an inventory attached, in the same order
## the composition root uses.
func _hero() -> Actor:
	var actor := Actor.new(&"delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor, INVENTORY_SLOTS)
	LootApi.attach(actor)
	return actor


## Clear one authored band of `domain_id` and take everything it owed, the way the
## Hunt screen does: enter, strike until the boss is defeated, claim. Returns the
## reason the run stopped so a caller can name it.
func _hunt(actor: Actor, domain_id: String, tier: int) -> String:
	var entered := LootApi.enter_domain(actor, StringName(domain_id), tier, 20260902)
	if not bool(entered.get("ok", false)):
		return "enter:" + String(entered.get("reason", "?"))
	var strikes := 0
	while strikes < MAX_STRIKES:
		var active := LootApi.summary(actor)["active"] as Dictionary
		# Defeating the last boss ends the run and clears the live boss (rule E3).
		# That is not a failure: the payload the last boss left is still unclaimed,
		# so the run ends by claiming rather than by reporting an exit.
		if not bool(active.get("in_domain", false)):
			return _claim_all(actor)
		if bool(active.get("defeated", false)):
			return _claim_all(actor)
		var result := LootApi.strike(actor, STRIKE_DAMAGE, 20260902)
		if not bool(result.get("ok", false)):
			return "strike:" + String(result.get("reason", "?"))
		if bool(result.get("duplicate", false)):
			return _claim_all(actor)
		strikes += 1
	return "strikes_exhausted:%d" % MAX_STRIKES


## Claim every outstanding payload, so one unclaimed drop cannot look like a
## failed hunt.
func _claim_all(actor: Actor) -> String:
	var rounds := 0
	while rounds < MAX_CLAIMS:
		rounds += 1
		var summary := LootApi.summary(actor)
		if int(summary["pending_drops"]) == 0:
			return "claimed"
		var rewards: Array = summary["rewards"]
		if rewards.is_empty():
			return "no_reward_left"
		for reward in rewards:
			LootApi.pickup_all(actor, String((reward as Dictionary)["encounter_id"]))
	return "claims_exhausted:%d" % MAX_CLAIMS


# --- The contract -----------------------------------------------------------


## Every realm on the ladder authors a seed and every seed's three consumables
## resolve to a real item and a real recipe. Without this the rest of the suite
## would walk an empty graph and pass.
##
## One report, naming the first realm that does not resolve: a precondition check
## that asserts every hop of every realm reports the same defect two hundred
## times and hides which one it was.
func test_every_body_realm_authors_a_resolvable_craft_chain() -> void:
	var realms := _realms()
	assert_eq(realms.size(), REALM_COUNT, "30 body realms are authored")
	var ladder := RealmDefaults.ladder()
	var first_broken := ""
	for realm_id in realms:
		var chain := _chain(realm_id)
		if chain["seed"] == null:
			first_broken = "%s has no realm seed" % realm_id
			break
		if not ladder.has(StringName(realm_id)):
			first_broken = "%s is not on the canonical ladder" % realm_id
			break
		if (chain["consumables"] as Array).size() != CONSUMABLE_ROLES.size():
			first_broken = (
				"%s names %d consumables" % [realm_id, (chain["consumables"] as Array).size()]
			)
			break
		for consumable in chain["consumables"] as Array:
			var entry := consumable as Dictionary
			if String(entry["recipe"]).is_empty():
				first_broken = (
					"%s: %s resolved to %s with sources %s"
					% [
						realm_id,
						entry["item"],
						_def(String(entry["item"])),
						(
							[]
							if _def(String(entry["item"])) == null
							else _def(String(entry["item"])).sources
						),
					]
				)
				break
			if (entry["reagents"] as Array).is_empty():
				first_broken = "%s: %s has no reagents" % [realm_id, entry["item"]]
				break
		if not first_broken.is_empty():
			break
	assert_eq(first_broken, "", "every realm's craft chain resolves")


## The whole point: every reagent the body path needs must name a boss, and that
## boss's domain must resolve to an authored encounter, because a `boss:` source
## is only delivered once `LootApi.enter_domain` can spawn the boss.
func test_every_body_reagent_resolves_to_an_enterable_domain() -> void:
	var realms := _realms()
	var hosted := 0
	for realm_id in realms:
		var catalysts := _catalysts_of(realm_id)
		assert_eq(catalysts.is_empty(), false, "%s needs at least one boss catalyst" % realm_id)
		for boss_id in catalysts.keys():
			var domain_id := _domain_of(String(boss_id))
			assert_eq(domain_id.is_empty(), false, "%s declares a domain" % boss_id)
			var encounter := LootContent.instance().encounter_for_domain(StringName(domain_id))
			if encounter == null:
				assert_eq(
					String(domain_id).is_empty(),
					false,
					"%s hosts %s (no encounter for %s)" % [realm_id, boss_id, domain_id]
				)
				continue
			hosted += 1
			assert_eq(
				(encounter.boss_ids as Array).has(StringName(boss_id)),
				true,
				"the %s encounter spawns %s" % [domain_id, boss_id]
			)
	assert_eq(hosted > 0, true, "at least one body catalyst is enterable")


## The end-to-end proof, for every realm: hunt the trial, take the reagents, and
## craft the realm's breakthrough pill out of them. This is the chain a player
## walks; handing an actor an item directly would not fail here.
##
## A realm that breaks reports once, naming the hop that stopped, and the walk
## continues. Asserting every hop of every realm would turn one missing encounter
## into two hundred identical lines and bury the cause.
func test_a_body_pill_is_acquirable_for_every_realm_through_the_shipping_program() -> void:
	var realms := _realms()
	assert_eq(realms.size(), REALM_COUNT, "30 realms are walked")
	var acquired := 0
	var first_failure := ""
	for realm_id in realms:
		var broke := _acquire(realm_id)
		if broke.is_empty():
			acquired += 1
		elif first_failure.is_empty():
			first_failure = broke
	assert_eq(
		acquired,
		realms.size(),
		(
			"every realm's pill is craftable from what its own trial drops (first failure: %s)"
			% (first_failure if first_failure.is_empty() else first_failure)
		)
	)


## The distinct domains a realm's reagents live in, sorted.
##
## A realm's guardians and its tier wardens share one domain, and one run clears
## all of them, so the hunt is per domain. De-duplicating here is also what stops
## the walk from re-entering a domain it has already cleared.
func _catalyst_domains(realm_id: String) -> Array[String]:
	var out: Array[String] = []
	for boss_id in (_catalysts_of(realm_id) as Dictionary).keys():
		var domain_id := _domain_of(String(boss_id))
		if not domain_id.is_empty() and not out.has(domain_id):
			out.append(domain_id)
	out.sort()
	return out


## Hunt every catalyst boss of `realm_id`, then craft its three consumables.
## Returns "" when the whole chain worked, and otherwise one sentence naming the
## hop that stopped, because "acquisition is broken" is not a diagnosis.
func _acquire(realm_id: String) -> String:
	var chain := _chain(realm_id)
	var actor := _hero()
	# One run through a domain defeats every boss it lists (loot rule E3), so the
	# walk hunts each DOMAIN once. Hunting per boss would clear the run on the
	# first one and refuse the second with `domain_cleared`, which is correct game
	# behaviour and not a defect.
	for domain_id in _catalyst_domains(realm_id):
		var reason := _hunt(actor, domain_id, _first_tier(domain_id))
		if reason != "claimed":
			return "%s: hunting %s stopped: %s" % [realm_id, domain_id, reason]
	for consumable in chain["consumables"] as Array:
		var entry := consumable as Dictionary
		var recipe := load("res://data/recipes/%s.tres" % entry["recipe"]) as RecipeDef
		if recipe == null:
			return "%s: recipe %s does not load" % [realm_id, entry["recipe"]]
		if not ItemsApi.craft(recipe, ItemsApi.inventory(actor)):
			return (
				"%s: crafting %s failed, %s"
				% [realm_id, entry["item"], _missing_inputs(recipe, actor)]
			)
		if not ItemsApi.has_item(actor, StringName(entry["item"])):
			return "%s: crafted %s but the bag does not hold it" % [realm_id, entry["item"]]
	return ""


## The recipe inputs the bag is short of, so a craft failure names the drop that
## never arrived instead of only reporting that the craft failed.
func _missing_inputs(recipe: RecipeDef, actor: Actor) -> String:
	var short: Array[String] = []
	for input_id in recipe.inputs:
		if not ItemsApi.has_item(actor, input_id):
			short.append(String(input_id))
	return "the bag is short of " + (", ".join(short) if not short.is_empty() else "nothing")


## A cleared band grants no second run (loot rule E2), so a catalyst that is only
## *rolled* can leave a player permanently unable to reach the next realm. Every
## catalyst therefore has to be a guaranteed entry of its boss's own table.
func test_every_body_catalyst_is_guaranteed_not_rolled() -> void:
	var content := LootContent.instance()
	var guaranteed := 0
	var rolled := 0
	for boss_id in _every_catalyst_boss():
		var domain_id := _domain_of(boss_id)
		var encounter := content.encounter_for_domain(StringName(domain_id))
		# A catalyst this encounter's boss does not host is a different boss's
		# problem; judging it here would report another author's content as broken.
		if encounter == null or not (encounter.boss_ids as Array).has(StringName(boss_id)):
			continue
		var wanted: Array[String] = []
		for realm_id in _realms():
			var catalysts := _catalysts_of(realm_id)
			for item_id in catalysts.get(boss_id, []) as Array:
				wanted.append(String(item_id))
		for tier in encounter.tiers:
			if tier == null:
				continue
			var table := content.table(tier.table_for(StringName(boss_id)))
			assert_ne(table, null, "%s tier %d names a table" % [boss_id, tier.tier])
			if table == null:
				continue
			var listed := {}
			for entry in table.entries:
				if entry != null and not entry.is_nested() and entry.item_id != &"":
					listed[String(entry.item_id)] = entry.guaranteed
			for item_id in wanted:
				if not listed.has(item_id):
					continue
				if bool(listed[item_id]):
					guaranteed += 1
				else:
					rolled += 1
					assert_eq(
						bool(listed[item_id]),
						true,
						"%s guarantees %s at tier %d" % [boss_id, item_id, tier.tier]
					)
	assert_eq(rolled, 0, "no body catalyst is left to a roll")
	assert_eq(guaranteed > 0, true, "at least one catalyst is guaranteed")


## One authority per boss: a boss bound to an authored loot table must not also
## carry a legacy `loot` list, because those are two independent answers to
## "what does this boss drop" and the runtime reads only one of them.
func test_a_hosted_body_boss_leaves_its_loot_to_the_loot_module() -> void:
	var content := LootContent.instance()
	var hosted := 0
	for boss_id in _every_body_boss():
		var record := content.boss_record(StringName(boss_id))
		assert_eq(bool(record["found"]), true, "%s has a boss record" % boss_id)
		var encounter := content.encounter_for_domain(StringName(record["domain_id"]))
		# Only a boss the encounter actually lists has moved its drops into a loot
		# table; a sibling that shares the domain keeps its own list.
		if encounter == null or not (encounter.boss_ids as Array).has(StringName(boss_id)):
			continue
		hosted += 1
		assert_eq(
			(record["loot"] as Array).is_empty(),
			true,
			"%s leaves its loot array to the loot module" % boss_id
		)
	assert_eq(hosted > 0, true, "at least one body boss is hosted")


## Every band of a body encounter binds every boss it lists, and the table it
## names resolves. A band that leaves a boss unbound is content that cannot be
## fought, which is the whole reason the encounter exists.
func test_every_body_encounter_binds_each_boss_on_every_band() -> void:
	var content := LootContent.instance()
	var seen: Dictionary = {}
	for boss_id in _every_body_boss():
		var record := content.boss_record(StringName(boss_id))
		var encounter := content.encounter_for_domain(StringName(record["domain_id"]))
		if encounter == null or seen.has(String(encounter.id)):
			continue
		seen[String(encounter.id)] = true
		assert_eq(encounter.tiers.size() >= 2, true, "%s has two bands" % String(encounter.id))
		assert_eq(encounter.boss_ids.is_empty(), false, "%s hosts a boss" % String(encounter.id))
		for tier in encounter.tiers:
			for listed in encounter.boss_ids:
				assert_ne(
					tier.table_for(listed), &"", "%s binds %s" % [String(encounter.id), listed]
				)
				assert_ne(
					content.table(tier.table_for(listed)),
					null,
					"%s resolves the table for %s" % [String(encounter.id), listed]
				)
	assert_eq(seen.size() > 0, true, "at least one body boss is hosted")


# --- One encounter per domain ------------------------------------------------


## A domain carries at most one encounter, and two agents seeding the same body
## trial can each claim it. The loser was a `loot_route_*` encounter with ONE band
## that ROLLED the catalysts; a cleared band grants no second run (rule E2), so a
## rolled catalyst can soft-lock the path for good. That is why the trial's own
## encounter wins, and this asserts the ruling structurally: the domain's encounter
## is the one named for it, so either set coming back is a failure.
func test_one_encounter_per_body_domain_and_no_route_encounter_reclaims_one() -> void:
	var content := LootContent.instance()
	var claims: Dictionary = {}
	for encounter_id in content.encounter_ids():
		var encounter := content.encounter_by_id(StringName(encounter_id))
		if encounter == null:
			continue
		var ids: Array = claims.get(String(encounter.domain_id), [])
		ids.append(String(encounter.id))
		claims[String(encounter.domain_id)] = ids
	var body_domains := 0
	var route_claims: Array[String] = []
	for domain_id in claims.keys():
		var ids: Array = claims[domain_id]
		assert_eq(ids.size(), 1, "%s carries exactly one encounter" % domain_id)
		if not String(domain_id).begins_with("body_"):
			continue
		body_domains += 1
		assert_eq(
			String(ids[0]),
			"loot_%s" % domain_id,
			"%s is hosted by the trial's own encounter" % domain_id
		)
		if String(ids[0]).begins_with(ROUTE_PREFIX):
			route_claims.append(String(ids[0]))
	assert_eq(body_domains, REALM_COUNT, "every body trial domain has an encounter")
	assert_eq(
		route_claims, [] as Array[String], "no loot_route_* encounter claims a body trial domain"
	)


## Every boss a body domain lists is hosted by that domain's encounter, on every
## band. A boss left off is an authored `boss:` source nothing can spawn, which is
## how `E10_dao_warden` sat on the domain with no encounter naming it.
func test_every_body_domain_boss_is_hosted_by_its_own_trial() -> void:
	var content := LootContent.instance()
	var hosted := 0
	for domain_id in _every_body_domain():
		var encounter := content.encounter_for_domain(StringName(domain_id))
		assert_ne(encounter, null, "%s has an encounter" % domain_id)
		if encounter == null:
			continue
		for boss_id in content.domain_record(StringName(domain_id))["boss_ids"] as Array:
			assert_eq(
				(encounter.boss_ids as Array).has(String(boss_id)),
				true,
				"%s hosts the %s the domain lists" % [domain_id, boss_id]
			)
			hosted += 1
	assert_eq(hosted > 0, true, "body domain bosses are checked")


## A folded encounter's table is carried onto the winner, so the E-tier boss keeps
## its non-catalyst drops — the unique artifacts are guaranteed entries there, and
## regenerating the table would demote them to weighted rolls. Asserted as "bound",
## not "named a particular way", so the guarantee survives a future re-fold.
func test_every_route_table_is_bound_by_a_band_of_some_encounter() -> void:
	var content := LootContent.instance()
	var bound: Dictionary = {}
	for encounter_id in content.encounter_ids():
		var encounter := content.encounter_by_id(StringName(encounter_id))
		if encounter == null:
			continue
		for tier in encounter.tiers:
			if tier == null:
				continue
			for listed in encounter.boss_ids:
				var table_id := String(tier.table_for(listed))
				if not table_id.is_empty():
					bound[table_id] = int(bound.get(table_id, 0)) + 1
	var routes := 0
	for table_id in content.table_ids():
		if not table_id.begins_with(ROUTE_PREFIX):
			continue
		routes += 1
		assert_ne(
			int(bound.get(table_id, 0)),
			0,
			"route table %s is bound by a band, so its drops stay reachable" % table_id
		)
	assert_eq(routes > 0, true, "route tables are authored to carry")


# --- Catalysts are guaranteed, whatever table carries them --------------------


## Every reagent a realm's three recipes need, sorted and de-duplicated.
func _catalyst_items(realm_id: String) -> Array[String]:
	var out: Array[String] = []
	for item_ids in (_catalysts_of(realm_id) as Dictionary).values():
		for item_id in item_ids as Array:
			if not out.has(String(item_id)):
				out.append(String(item_id))
	out.sort()
	return out


## Whether `table_id` can yield `item_id`, nested tables included.
##
## Bounded twice over: by the resolver's own nesting limit, and by the ids already
## walked, so a table that references itself terminates instead of recursing until
## the depth guard alone happens to stop it.
func _reaches(
	content: LootContent, table_id: String, item_id: String, depth: int = 0, chain: Array = []
) -> bool:
	if depth > MAX_TABLE_DEPTH or chain.has(table_id):
		return false
	var table := content.table(StringName(table_id))
	if table == null:
		return false
	var next_chain := chain.duplicate()
	next_chain.append(table_id)
	for entry in table.entries:
		if entry == null:
			continue
		if entry.is_nested():
			if _reaches(content, String(entry.table_id), item_id, depth + 1, next_chain):
				return true
		elif String(entry.item_id) == item_id:
			return true
	return false


## Whether `table_id` resolves `item_id` unconditionally, nested tables included.
## A guaranteed entry inside a pool counts: the pool resolves it once it is reached,
## which is as unconditional as a direct entry. Bounded as `_reaches` is.
func _guarantees(
	content: LootContent, table_id: String, item_id: String, depth: int = 0, chain: Array = []
) -> bool:
	if depth > MAX_TABLE_DEPTH or chain.has(table_id):
		return false
	var table := content.table(StringName(table_id))
	if table == null:
		return false
	var next_chain := chain.duplicate()
	next_chain.append(table_id)
	for entry in table.entries:
		if entry == null:
			continue
		if entry.is_nested():
			if _guarantees(content, String(entry.table_id), item_id, depth + 1, next_chain):
				return true
		elif String(entry.item_id) == item_id and entry.guaranteed:
			return true
	return false


## A catalyst its OWN boss rolls is one exposure; a catalyst a SIBLING boss rolls is
## the same soft-lock by another route, and a sibling is exactly what folding a
## second encounter into a trial introduces. So every table the trial binds on every
## band is judged, not only the catalyst's own: a table that cannot yield the
## catalyst at all is another boss's business and is left alone, because not every
## boss in a trial has to carry every reagent.
func test_every_body_catalyst_is_guaranteed_on_every_table_of_its_trial() -> void:
	var content := LootContent.instance()
	var judged := 0
	for realm_id in _realms():
		var wanted := _catalyst_items(realm_id)
		if wanted.is_empty():
			continue
		var domain_id := ""
		for boss_id in (_catalysts_of(realm_id) as Dictionary).keys():
			var found := _domain_of(String(boss_id))
			if not found.is_empty():
				domain_id = found
				break
		var encounter := content.encounter_for_domain(StringName(domain_id))
		if encounter == null:
			continue
		var seen: Dictionary = {}
		for tier in encounter.tiers:
			if tier == null:
				continue
			for listed in encounter.boss_ids:
				var table_id := String(tier.table_for(listed))
				if table_id.is_empty() or seen.has(table_id):
					continue
				seen[table_id] = true
				judged += 1
				var rolled: Array[String] = []
				for item_id in wanted:
					if (
						_reaches(content, table_id, item_id)
						and not _guarantees(content, table_id, item_id)
					):
						rolled.append(item_id)
				assert_eq(
					rolled,
					[] as Array[String],
					(
						"%s: %s guarantees %s at band %d"
						% [realm_id, table_id, ", ".join(rolled), tier.tier]
					)
				)
	assert_eq(judged > 0, true, "body trial tables are judged")
