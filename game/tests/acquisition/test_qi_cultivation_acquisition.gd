extends TestCase

## Qi cultivation is playable only when every realm's three consumables can be
## acquired through the shipping program: hunt a trial, take what its bosses drop,
## craft the pill. Nothing hands an actor an `ItemDef`: every assertion walks the
## authored graph — `sources` -> a recipe or a boss or a domain -> the table bound
## to that boss -> `LootApi` — because a source no shipping code delivers is the
## defect this suite exists to catch (ADR 0007, ADR 0033). The qi gate audits
## cannot: `qi_gate_probe.gd:83` uses `Probe.stock`, so nothing was acquired.
##
## ## The ladder is obtainable. It is not yet obtainable EVERY time.
##
## 1. **Obtainable — 210 of 210 chain items.** All 90 consumables resolve to an
##    `ItemDef`, a recipe that outputs it and inputs that resolve, and every hop
##    CLOSES. Nothing rests only on `gather`/`quest`, both `shipped: false`. That
##    was DEF-0188's finding and it no longer holds: `6f141711` gave those 41
##    materials a real `domain:` route with a bound table, so the pin is 0.
## 2. **Obtainable on EVERY clear — 49 of 90.** A cleared band grants no second run
##    (loot rule E2), so "a table can yield this" is not enough: the item must
##    arrive where every hop is `guaranteed`. 41 are left to a roll — 30 recovery
##    elixirs, 6 breakthrough pills, 5 channel elixirs, all 30 realms (DEF-0199).
##
## That is why `_reaches` takes an `unconditional` flag, and why every loop below is
## bounded and names the condition that failed to converge.

const REALM_DIR := "res://data/qi_cultivation/realms/"
const RECIPE_DIR := "res://data/recipes/"
const REALM_COUNT := 30
const STRIKE_DAMAGE := 25.0
## Stops when a boss's authored vitality stops falling: the deepest lowest band any
## domain here hunts costs 272.0, so 64 x 25.0 clears every one of them.

const MAX_STRIKES := 64
const MAX_CLAIMS := 16
const INVENTORY_SLOTS := 256
const HUNT_SEED := 20260903
const CONSUMABLE_ROLES := ["breakthrough_item", "training_item", "recovery_item"]
const MAX_TABLE_DEPTH := 4
const MAX_CRAFT_DEPTH := 4

const CHAIN_DOMAIN_COUNT := 77
const UNSHIPPED_PREFIX := "%s: every route is unshipped [%s]"
const UNSHIPPED_MARKER := "every route is unshipped"

const PINNED_UNSHIPPED_REAGENTS := 0
## Pinned: how many of the 90 consumables rule E2 leaves to a roll, keyed by the seed's
## own role names. Growth regresses; shrinkage is progress and trips this pin.

const PINNED_ROLLED_BY_ROLE := {"breakthrough_item": 6, "training_item": 5, "recovery_item": 30}
## DEF-0199, pinned by exact id: the consumables a single clear can miss, sorted.
const PINNED_ROLLED_CONSUMABLES := [
	"qi_body_integration_recovery_elixir",
	"qi_core_formation_breakthrough_pill",
	"qi_core_formation_recovery_elixir",
	"qi_dao_ancestor_recovery_elixir",
	"qi_dao_fruit_recovery_elixir",
	"qi_earth_immortal_channel_elixir",
	"qi_earth_immortal_recovery_elixir",
	"qi_foundation_recovery_elixir",
	"qi_golden_immortal_breakthrough_pill",
	"qi_golden_immortal_recovery_elixir",
	"qi_great_ascension_channel_elixir",
	"qi_great_ascension_recovery_elixir",
	"qi_great_luo_recovery_elixir",
	"qi_heaven_immortal_recovery_elixir",
	"qi_immortal_sovereign_recovery_elixir",
	"qi_mystic_immortal_recovery_elixir",
	"qi_nascent_soul_channel_elixir",
	"qi_nascent_soul_recovery_elixir",
	"qi_primordial_immortal_recovery_elixir",
	"qi_primordial_origin_recovery_elixir",
	"qi_qi_refining_recovery_elixir",
	"qi_spirit_ascension_breakthrough_pill",
	"qi_spirit_ascension_recovery_elixir",
	"qi_spirit_condensation_breakthrough_pill",
	"qi_spirit_condensation_recovery_elixir",
	"qi_spirit_domain_recovery_elixir",
	"qi_spirit_manifestation_recovery_elixir",
	"qi_spirit_palace_channel_elixir",
	"qi_spirit_palace_recovery_elixir",
	"qi_spirit_sea_recovery_elixir",
	"qi_spirit_severing_recovery_elixir",
	"qi_spirit_sovereign_channel_elixir",
	"qi_spirit_sovereign_recovery_elixir",
	"qi_spirit_transformation_breakthrough_pill",
	"qi_spirit_transformation_recovery_elixir",
	"qi_spirit_unity_recovery_elixir",
	"qi_transcendent_recovery_elixir",
	"qi_tribulation_recovery_elixir",
	"qi_true_immortal_recovery_elixir",
	"qi_void_refinement_breakthrough_pill",
	"qi_void_refinement_recovery_elixir",
]
## DEF-0199, pinned by exact id: the boss-dropped qi REAGENTS guaranteed only inside a
## ROLLED pool, the `qi_<realm>_guardian_core` family, asserted so a fix trips the pin.

const PINNED_ROLLED_REAGENTS := [
	"qi_body_integration_guardian_core",
	"qi_core_formation_guardian_core",
	"qi_dao_ancestor_guardian_core",
	"qi_dao_fruit_guardian_core",
	"qi_foundation_guardian_core",
	"qi_golden_immortal_guardian_core",
	"qi_great_ascension_guardian_core",
	"qi_great_luo_guardian_core",
	"qi_heaven_immortal_guardian_core",
	"qi_immortal_sovereign_guardian_core",
	"qi_mystic_immortal_guardian_core",
	"qi_primordial_immortal_guardian_core",
	"qi_primordial_origin_guardian_core",
	"qi_spirit_ascension_guardian_core",
	"qi_spirit_domain_guardian_core",
	"qi_spirit_manifestation_guardian_core",
	"qi_spirit_palace_guardian_core",
	"qi_spirit_sea_guardian_core",
	"qi_spirit_severing_guardian_core",
	"qi_spirit_sovereign_guardian_core",
	"qi_spirit_transformation_guardian_core",
	"qi_spirit_unity_guardian_core",
	"qi_transcendent_guardian_core",
	"qi_tribulation_guardian_core",
	"qi_true_immortal_guardian_core",
	"qi_void_refinement_guardian_core",
]

const BOSS_DROPPED_CONSUMABLES := [
	"qi_body_integration_breakthrough_pill",
	"qi_core_formation_channel_elixir",
	"qi_dao_ancestor_breakthrough_pill",
	"qi_earth_immortal_breakthrough_pill",
	"qi_golden_immortal_channel_elixir",
	"qi_great_ascension_breakthrough_pill",
	"qi_nascent_soul_breakthrough_pill",
	"qi_primordial_origin_channel_elixir",
	"qi_spirit_ascension_channel_elixir",
	"qi_spirit_condensation_channel_elixir",
	"qi_spirit_palace_breakthrough_pill",
	"qi_spirit_sovereign_breakthrough_pill",
	"qi_spirit_transformation_channel_elixir",
	"qi_transcendent_breakthrough_pill",
	"qi_void_refinement_channel_elixir",
]

var _defs: Dictionary = {}

# --- The authored chain -----------------------------------------------------


func _def(item_id: String) -> ItemDef:
	if not _defs.has(item_id):
		_defs[item_id] = Crafting.resolve(StringName(item_id))
	return _defs[item_id] as ItemDef


func _realms() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(REALM_DIR)
	assert_ne(dir, null, "the qi realm seed directory opens")
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


func _seed(realm_id: String) -> QiRealmSeed:
	return load(REALM_DIR + realm_id + ".tres") as QiRealmSeed


func _recipe(recipe_id: String) -> RecipeDef:
	if recipe_id.is_empty():
		return null
	return load(RECIPE_DIR + recipe_id + ".tres") as RecipeDef


func _craft_recipe(item_id: String) -> String:
	var def := _def(item_id)
	if def == null:
		return ""
	for route in ItemSources.routes(def):
		if StringName(route["kind"]) == ItemSources.KIND_CRAFT:
			return String(route["ref"])
	return ""


func _kinds(item_id: String) -> Array[String]:
	var out: Array[String] = []
	var def := _def(item_id)
	if def == null:
		return out
	for route in ItemSources.routes(def):
		var kind := String(route["kind"])
		if not out.has(kind):
			out.append(kind)
	out.sort()
	return out


func _refs_of(item_id: String, kind: StringName) -> Array[String]:
	var out: Array[String] = []
	var def := _def(item_id)
	if def == null:
		return out
	for route in ItemSources.routes(def):
		if StringName(route["kind"]) != kind:
			continue
		var ref := String(route["ref"])
		if not out.has(ref):
			out.append(ref)
	out.sort()
	return out


func _consumables() -> Array:
	var out: Array = []
	for realm_id in _realms():
		var seed := _seed(realm_id)
		for role in CONSUMABLE_ROLES:
			var item_id := "" if seed == null else String(seed.get(role))
			var recipe_id := _craft_recipe(item_id)
			var inputs: Array[String] = []
			var recipe := _recipe(recipe_id)
			if recipe != null:
				for input_id in recipe.inputs:
					inputs.append(String(input_id))
			(
				out
				. append(
					{
						"realm": realm_id,
						"role": role,
						"item": item_id,
						"recipe": recipe_id,
						"inputs": inputs,
					}
				)
			)
	return out


func _chain_items() -> Array[String]:
	var out: Array[String] = []
	for consumable in _consumables():
		for item_id in [String(consumable["item"])] + (consumable["inputs"] as Array[String]):
			if not out.has(item_id):
				out.append(item_id)
	out.sort()
	return out


func _domain_of(boss_id: String) -> String:
	return String(LootContent.instance().boss_record(StringName(boss_id))["domain_id"])


func _hunt_domains_of(item_id: String) -> Array[String]:
	var out: Array[String] = []
	for domain_id in _refs_of(item_id, ItemSources.KIND_DOMAIN):
		if not out.has(domain_id):
			out.append(domain_id)
	for boss_id in _refs_of(item_id, ItemSources.KIND_BOSS):
		var domain_id := _domain_of(boss_id)
		if not domain_id.is_empty() and not out.has(domain_id):
			out.append(domain_id)
	out.sort()
	return out


func _chain_domains() -> Array[String]:
	var out: Array[String] = []
	for item_id in _chain_items():
		for domain_id in _hunt_domains_of(item_id):
			if not out.has(domain_id):
				out.append(domain_id)
	out.sort()
	return out


func _catalyst_bosses() -> Array[String]:
	var out: Array[String] = []
	for item_id in _chain_items():
		for boss_id in _refs_of(item_id, ItemSources.KIND_BOSS):
			if not out.has(boss_id):
				out.append(boss_id)
	out.sort()
	return out


func _is_consumable(item_id: String) -> bool:
	for consumable in _consumables():
		if String((consumable as Dictionary)["item"]) == item_id:
			return true
	return false


func _lowest_band_tables(domain_id: String) -> Array[String]:
	var out: Array[String] = []
	var encounter := LootContent.instance().encounter_for_domain(StringName(domain_id))
	if encounter == null:
		return out
	var lowest := _first_tier(domain_id)
	for tier in encounter.tiers:
		if tier == null or tier.tier != lowest:
			continue
		for boss_id in encounter.boss_ids:
			var table_id := String(tier.table_for(boss_id))
			if not table_id.is_empty() and not out.has(table_id):
				out.append(table_id)
	out.sort()
	return out


# --- The backward walk -----------------------------------------------------

## Whether `table_id` can yield `item_id`, nested tables included — and, when
## `unconditional` is set, ONLY along a path every hop of which is `guaranteed`. A
## guaranteed item inside a ROLLED pool is still rolled, the pool being one weighted
## candidate among many, so descending into it unconditionally over-claims by one
## draw. That flag is the rule DEF-0187 was written against.
##
## Bounded twice: by the resolver's nesting limit, and by the ids already walked, so a
## self-referencing table terminates instead of recursing on the depth guard alone.


func _reaches(
	content: LootContent,
	table_id: String,
	item_id: String,
	unconditional: bool,
	depth: int = 0,
	chain: Array = []
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
			if unconditional and not entry.guaranteed:
				continue
			var child := String(entry.table_id)
			if _reaches(content, child, item_id, unconditional, depth + 1, next_chain):
				return true
		elif String(entry.item_id) == item_id and (not unconditional or entry.guaranteed):
			return true
	return false


func _blocker(item_id: String, depth: int, chain: Array) -> String:
	if depth > MAX_CRAFT_DEPTH:
		return "%s: craft chain deeper than MAX_CRAFT_DEPTH" % item_id
	if chain.has(item_id):
		return "%s: craft chain names itself" % item_id
	var def := _def(item_id)
	if def == null:
		return "%s: no ItemDef resolves" % item_id
	var shipped: Array = []
	var declared: Array[String] = []
	for route in ItemSources.routes(def):
		var kind := StringName(route["kind"])
		if not declared.has(String(kind)):
			declared.append(String(kind))
		if bool(route["ok"]) and ItemSources.is_shipped(kind):
			shipped.append(route)
	if shipped.is_empty():
		return UNSHIPPED_PREFIX % [item_id, ", ".join(declared)]
	var next_chain := chain.duplicate()
	next_chain.append(item_id)
	var first_refusal := ""
	for route in shipped:
		var reason := _route_blocker(item_id, route, depth, next_chain)
		if reason.is_empty():
			return ""
		if first_refusal.is_empty():
			first_refusal = reason
	return first_refusal


## Whether one shipped route can close, by the membership rule `tools/data.py` uses.


func _route_blocker(item_id: String, route: Dictionary, depth: int, chain: Array) -> String:
	var ref := String(route["ref"])
	match StringName(route["kind"]):
		ItemSources.KIND_BOSS:
			return _boss_blocker(String(item_id), ref)
		ItemSources.KIND_DOMAIN:
			return _domain_blocker(item_id, ref)
		ItemSources.KIND_CRAFT:
			var recipe := _recipe(ref)
			if recipe == null:
				return "%s: recipe %s does not load" % [item_id, ref]
			var inner := chain.duplicate()
			inner.append(ref)
			for input_id in recipe.inputs:
				var reason := _blocker(String(input_id), depth + 1, inner)
				if not reason.is_empty():
					return "%s via craft:%s needs %s" % [item_id, ref, reason]
			return ""
		_:
			# `starter` is granted by the composition root's own list rather than by a
			# content probe, and no qi item declares it. The kinds the chain actually
			# exercises are asserted, so this stays an unreachable branch rather than
			# a silent "yes" for anything a future author adds.
			return "UNPROBED_ROUTE:%s" % String(route["kind"])


func _boss_blocker(item_id: String, boss_id: String) -> String:
	var content := LootContent.instance()
	var record := content.boss_record(StringName(boss_id))
	if not bool(record["found"]):
		return "%s: boss %s has no BossDef" % [item_id, boss_id]
	var domain_id := String(record["domain_id"])
	if domain_id.is_empty():
		return "%s: boss %s declares no domain" % [item_id, boss_id]
	var encounter := content.encounter_for_domain(StringName(domain_id))
	if encounter == null:
		return "%s: domain %s has no authored encounter" % [item_id, domain_id]
	var reason := ""
	if not (encounter.boss_ids as Array).has(StringName(boss_id)):
		reason = "%s: the %s encounter never spawns %s" % [item_id, domain_id, boss_id]
	for tier in encounter.tiers:
		if reason.is_empty() and tier != null:
			var table_id := String(tier.table_for(StringName(boss_id)))
			if String(table_id).is_empty():
				reason = "%s: %s binds no table at band %d" % [item_id, domain_id, tier.tier]
			elif content.table(table_id) == null:
				reason = "%s: table %s does not resolve" % [item_id, table_id]
	return reason


func _domain_blocker(item_id: String, domain_id: String) -> String:
	if LootContent.instance().encounter_for_domain(StringName(domain_id)) == null:
		return "%s: domain %s has no authored encounter" % [item_id, domain_id]
	for table_id in _lowest_band_tables(domain_id):
		if _reaches(LootContent.instance(), table_id, item_id, false):
			return ""
	return "%s: no boss on %s drops it at band %d" % [item_id, domain_id, _first_tier(domain_id)]


# --- Rule E2: obtainable on every clear ------------------------------------

## Whether `item_id` is obtainable on EVERY clear of one of its domains, so one
## unlucky draw cannot lock a player out (loot rule E2). `_blocker`'s shape with a
## stronger rule on the two drop kinds: a table must GUARANTEE the item, not merely
## be able to yield it. `craft:` composes as `_blocker` does, so a pill is certain
## exactly when both its reagents are.


func _certain(item_id: String, depth: int, chain: Array) -> bool:
	if depth > MAX_CRAFT_DEPTH or chain.has(item_id):
		return false
	var def := _def(item_id)
	if def == null:
		return false
	var next_chain := chain.duplicate()
	next_chain.append(item_id)
	for route in ItemSources.routes(def):
		var kind := StringName(route["kind"])
		if not bool(route["ok"]) or not ItemSources.is_shipped(kind):
			continue
		match kind:
			ItemSources.KIND_BOSS:
				if _boss_guarantees(item_id, String(route["ref"])):
					return true
			ItemSources.KIND_DOMAIN:
				if _domain_guarantees(item_id, String(route["ref"])):
					return true
			ItemSources.KIND_CRAFT:
				var recipe := _recipe(String(route["ref"]))
				if recipe == null:
					continue
				var inner := next_chain.duplicate()
				inner.append(String(route["ref"]))
				var short := ""
				for input_id in recipe.inputs:
					if not _certain(String(input_id), depth + 1, inner):
						short = String(input_id)
						break
				if short.is_empty():
					return true
	return false


func _boss_guarantees(item_id: String, boss_id: String) -> bool:
	var record := LootContent.instance().boss_record(StringName(boss_id))
	if not bool(record["found"]):
		return false
	var domain_id := String(record["domain_id"])
	if domain_id.is_empty():
		return false
	var encounter := LootContent.instance().encounter_for_domain(StringName(domain_id))
	if encounter == null or not (encounter.boss_ids as Array).has(StringName(boss_id)):
		return false
	for tier in encounter.tiers:
		if tier == null or tier.tier != _first_tier(domain_id):
			continue
		var table_id := String(tier.table_for(StringName(boss_id)))
		if not table_id.is_empty() and _reaches(LootContent.instance(), table_id, item_id, true):
			return true
	return false


func _domain_guarantees(item_id: String, domain_id: String) -> bool:
	for table_id in _lowest_band_tables(domain_id):
		if _reaches(LootContent.instance(), table_id, item_id, true):
			return true
	return false


func _realm_plan(realm_id: String) -> Dictionary:
	var certain: Array[String] = []
	var rolled: Array[String] = []
	var domains: Array[String] = []
	for consumable in _consumables():
		var entry := consumable as Dictionary
		if String(entry["realm"]) != realm_id:
			continue
		var item_id := String(entry["item"])
		if not _certain(item_id, 0, []):
			rolled.append(item_id)
			continue
		certain.append(item_id)
		for needed in [item_id] + (entry["inputs"] as Array[String]):
			for domain_id in _hunt_domains_of(needed):
				if not domains.has(domain_id):
					domains.append(domain_id)
	certain.sort()
	rolled.sort()
	domains.sort()
	return {"certain": certain, "rolled": rolled, "domains": domains}


# --- The shipping program ---------------------------------------------------


func _first_tier(domain_id: String) -> int:
	var encounter := LootContent.instance().encounter_for_domain(StringName(domain_id))
	if encounter == null or encounter.tiers.is_empty():
		return -1
	var lowest := encounter.tiers[0].tier
	for tier in encounter.tiers:
		if tier != null:
			lowest = mini(lowest, tier.tier)
	return lowest


func _hero() -> Actor:
	var actor := Actor.new(&"qi_delver", {Stat.COMPREHENSION: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor, INVENTORY_SLOTS)
	LootApi.attach(actor)
	return actor


func _hunt(actor: Actor, domain_id: String, tier: int) -> String:
	var entered := LootApi.enter_domain(actor, StringName(domain_id), tier, HUNT_SEED)
	if not bool(entered.get("ok", false)):
		return "enter:" + String(entered.get("reason", "?"))
	var strikes := 0
	while strikes < MAX_STRIKES:
		var active := LootApi.summary(actor)["active"] as Dictionary
		# Defeating the last boss ends the run and clears the live boss (rule E3).
		# That is not a failure: the payload the last boss left is still unclaimed,
		# so the run ends by claiming rather than by reporting an exit.
		if not bool(active.get("in_domain", false)) or bool(active.get("defeated", false)):
			return _claim_all(actor)
		var result := LootApi.strike(actor, STRIKE_DAMAGE, HUNT_SEED)
		if not bool(result.get("ok", false)):
			return "strike:" + String(result.get("reason", "?"))
		if bool(result.get("duplicate", false)):
			return _claim_all(actor)
		strikes += 1
	return "strikes_exhausted:%d" % MAX_STRIKES


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


func _short(recipe: RecipeDef, actor: Actor) -> String:
	var missing: Array[String] = []
	for input_id in recipe.inputs:
		if not ItemsApi.has_item(actor, input_id):
			missing.append(String(input_id))
	return "the bag is short of " + (", ".join(missing) if not missing.is_empty() else "nothing")


func _chain_broken(realm_id: String) -> String:
	var seed := _seed(realm_id)
	if seed == null:
		return "%s has no realm seed" % realm_id
	if not RealmDefaults.ladder().has(StringName(realm_id)):
		return "%s is not on the canonical ladder" % realm_id
	var broken := ""
	for role in CONSUMABLE_ROLES:
		broken = _role_broken(realm_id, seed, role)
		if not broken.is_empty():
			break
	return broken


func _role_broken(realm_id: String, seed: QiRealmSeed, role: String) -> String:
	var item_id := String(seed.get(role))
	if _def(item_id) == null:
		return "%s: %s resolves to no ItemDef" % [realm_id, item_id]
	var recipe_id := _craft_recipe(item_id)
	var recipe := _recipe(recipe_id)
	if recipe == null:
		return (
			"%s: %s declares no usable craft: route (sources %s)"
			% [realm_id, item_id, _kinds(item_id)]
		)
	if not (recipe.outputs as Array).has(StringName(item_id)):
		return "%s: %s does not list %s as an output" % [realm_id, recipe_id, item_id]
	if recipe.inputs.is_empty():
		return "%s: %s consumes nothing, so the pill is free" % [realm_id, recipe_id]
	for input_id in recipe.inputs:
		if _def(String(input_id)) == null:
			return "%s: %s needs %s, which resolves to no ItemDef" % [realm_id, recipe_id, input_id]
	return ""


# --- The contract -----------------------------------------------------------

## Every realm authors a seed, and every seed's three consumables resolve to a real
## item, a recipe that outputs it, and real items for every input.


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
## CONSUMABLE rolled set is asserted EMPTY. A REAGENT is judged separately: a recipe
## consumes it however the boss hands it over, so a rolled reagent is DEF-0199 rather
## than a repeat of DEF-0187, and is pinned by id instead.


func test_every_boss_dropped_qi_consumable_is_guaranteed_at_the_lowest_band() -> void:
	var content := LootContent.instance()
	var guaranteed := 0
	var rolled: Array[String] = []
	var rolled_reagents: Array[String] = []
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
			if reaches and not unconditional:
				if is_pill:
					rolled.append(item_id)
				else:
					rolled_reagents.append(item_id)
			elif unconditional:
				guaranteed += 1
		if is_pill and not boss_ids.is_empty():
			direct.append(item_id)
	rolled.sort()
	rolled_reagents.sort()
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
		rolled_reagents,
		PINNED_ROLLED_REAGENTS as Array[String],
		(
			"the boss-dropped qi reagents still left to a roll — each is guaranteed inside a"
			+ " ROLLED pool, so the draw that reaches the pool decides it, not the entry"
		)
	)


## The ladder is OBTAINABLE, part two: nothing rests on a route kind no shipping
## code implements, judged by the same membership rules `tools/data.py` uses, so
## `gather`/`quest`-only material is caught rather than assumed acquirable. This
## is DEF-0188's pin, re-declared at 0.


func test_no_qi_chain_item_rests_only_on_a_route_kind_nothing_ships() -> void:
	var unshipped: Array[String] = []
	var other: Array[String] = []
	var exercised: Array[String] = []
	for item_id in _chain_items():
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
		["boss", "craft", "domain", "gather", "quest"] as Array[String],
		"the qi chain declares only kinds the backward walk and the catalog both know"
	)


func _has_shipped_route(item_id: String) -> bool:
	var def := _def(item_id)
	if def == null:
		return false
	for route in ItemSources.routes(def):
		if bool(route["ok"]) and ItemSources.is_shipped(StringName(route["kind"])):
			return true
	return false


## DEF-0199, pinned. Every hop closes, so the only thing left between a player and
## a consumable is whether ONE clear delivers it. 41 do not, and rule E2 grants no retry.


func test_the_qi_consumables_rule_e2_leaves_to_a_roll_are_pinned() -> void:
	var rolled: Array[String] = []
	var by_role: Dictionary = {}
	for role in CONSUMABLE_ROLES:
		by_role[role] = 0
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
		PINNED_ROLLED_CONSUMABLES as Array[String],
		"exactly these qi consumables are obtainable only on a roll"
	)
	assert_eq(
		rolled.size(),
		REALM_COUNT,
		"every qi realm has at least one consumable a single clear can miss"
	)


## The end-to-end proof, per realm, exactly as the body twin does it: a fresh delver
## hunts the domains that realm's certain chain names and ends up holding every
## consumable rule E2 guarantees. Each realm is walked alone because a hunt is per
## actor and one clear is the only one a player gets. This is the chain a player
## walks, and the qi gate audits never exercise it because `Probe.stock` grants items
## outright.
##
## Two ways to hold a certain consumable, both counted: 15 are guaranteed DIRECT
## drops already in the bag, the rest are crafted. A guaranteed drop is never
## re-crafted, because its recipe can name a rolled reagent, so insisting on the craft
## would assert something no player needs to do. The pinned 41 are counted, not
## acquired: they are obtainable, but not on demand, and asserting they arrive would
## make the test depend on the hunt seed.


func test_every_certain_qi_consumable_is_held_end_to_end_from_its_own_domains() -> void:
	var realms := _realms()
	assert_eq(realms.size(), REALM_COUNT, "30 realms are walked")
	var crafted := 0
	var dropped := 0
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
		"every qi consumable was crafted, dropped, or is named as the pinned roll gap"
	)
	assert_eq(crafted + dropped, 49, "49 qi consumables are acquirable on every single clear")
	assert_eq(
		dropped,
		BOSS_DROPPED_CONSUMABLES.size(),
		"the boss-dropped consumables arrive as guaranteed drops, not as crafts"
	)
	assert_eq(rolled, 41, "41 qi consumables arrive only when the roll favours the player")
