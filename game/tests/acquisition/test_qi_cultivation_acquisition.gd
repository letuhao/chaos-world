extends TestCase

## Qi cultivation is playable only when every realm's three consumables can be
## acquired through the shipping program: hunt a trial, take what its bosses drop,
## craft the pill.
##
## Nothing here hands an actor an `ItemDef`. Every assertion walks the authored
## acquisition graph — `ItemDef.sources` -> a recipe or a boss -> the domain that
## hosts that boss -> `LootApi` — because a source no shipping code can deliver is
## exactly the defect this suite exists to catch (ADR 0007, ADR 0033). The qi gate
## audits cannot: `tests/modules/qi_cultivation/qi_gate_probe.gd:83` obtains its
## items from `Probe.stock`, so they were never acquired at all.
##
## ## The two things this suite cannot prove, and does not pretend to
##
## The body twin (`test_body_cultivation_acquisition.gd`) walks all thirty realms
## end to end, because every one of its reagents names a `boss:` source. The qi
## path has two gaps the catalog tooling is structurally blind to, and both are
## pinned here rather than asserted away:
##
## 1. **41 of the qi path's 120 distinct reagents declare no shipped route at
##    all** — only `gather` and `quest:<route>`, and `ItemSources.KINDS` marks both
##    `shipped: false`. There is no forager for `gather` (it is `REF_FORBIDDEN`, so
##    it cannot even name one) and `QuestGrants.pay` records a `quest:` grant
##    unspent. **All 30 realms' recovery elixir is unacquirable**, plus 6
##    breakthrough pills and 5 channel elixirs (DEF-0022, DEF-0023).
## 2. **15 qi consumables carry a direct `boss:` source, and every one of them is
##    ROLLED, not `guaranteed`.** A cleared band grants no second run (loot rule
##    E2), so for the 11 of them that are the ONLY route to their consumable, a
##    miss is permanent. `tools acquisition validate` cannot see this: `Trial
##    .catalysts` is built from a recipe REAGENT's `boss:` sources, so a
##    consumable's own `boss:` source is never judged for guaranteed-ness — and
##    `tools data audit` only asks whether the boss is hosted, not whether it
##    pays out.
##
## So every assertion below is one of two things: a real invariant that holds and
## would fail loudly if it broke, or an exact pin on a known gap so the gap cannot
## widen silently and this suite cannot go quietly green on a real break.
##
## Every loop is bounded and names the condition that failed to converge.

const REALM_DIR := "res://data/qi_cultivation/realms/"
const RECIPE_DIR := "res://data/recipes/"
const REALM_COUNT := 30
## One strike spends this much vitality (the composition root's strike damage).
const STRIKE_DAMAGE := 25.0
## Stops when a boss's authored vitality stops falling. Names the condition: a
## table that never resolves a defeat would otherwise strike forever. The deepest
## authored qi band costs 435.2, so 64 x 25.0 clears every one of them.
const MAX_STRIKES := 64
## Stops claiming payloads when nothing is pending. Names the condition: a drop
## that never leaves the pending state would otherwise be re-claimed forever.
const MAX_CLAIMS := 16
## One actor walks 41 hunt domains and holds every reagent it needs, so the bag is
## sized for that walk rather than for one realm.
const INVENTORY_SLOTS := 512
## Fixed seed so a hunt resolves the same way on every run.
const HUNT_SEED := 20260903
const CONSUMABLE_ROLES := ["breakthrough_item", "training_item", "recovery_item"]
## `LootContent.MAX_NESTING_DEPTH`, mirrored so the walks over nested tables below
## stop where the resolver stops.
const MAX_TABLE_DEPTH := 4
## Stops the backward walk when a recipe chain nests deeper than any authored one.
## Names the condition: a recipe naming its own ancestor never bottoms out.
const MAX_CRAFT_DEPTH := 4
## Every distinct domain the qi chain's boss sources resolve to. Widening the walk
## to the consumables' own `boss:` sources added none, which is worth asserting:
## the whole qi ladder is reachable from its 30 trials plus 10 side domains.
const HUNT_DOMAIN_COUNT := 41
## The one refusal GAP 1 is allowed to produce, in two pieces: a caller tests the
## marker alone, so a genuine break cannot be mistaken for the known gap by
## matching the whole sentence.
const UNSHIPPED_PREFIX := "%s: every route is unshipped [%s]"
const UNSHIPPED_MARKER := "every route is unshipped"
## GAP 1. The number of distinct qi reagents whose every declared route is one no
## shipping code implements. Pinned, not asserted away: growth is a regression,
## shrinkage means a herb was given a boss and this pin must be re-declared.
const PINNED_UNSHIPPED_REAGENTS := 41
## GAP 1. How many of the 90 consumables that leaves unacquirable, by role. Keyed
## by the seed's own role names so a failure reads as which role lost its route.
const PINNED_BLOCKED_BY_ROLE := {"breakthrough_item": 6, "recovery_item": 30, "training_item": 5}
## GAP 2. Every qi consumable a boss drops directly, and every one of them is
## rolled rather than guaranteed. Pinned by exact id so the list is the finding:
## any addition or removal trips here and forces this pin to be re-declared.
const PINNED_ROLLED_CONSUMABLES := [
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

## `Crafting.resolve` walks the whole item tree on a miss, so the resolver is the
## one thing memoized here. Everything else is cheap to derive and is derived
## fresh, so no case's answer depends on which case happened to run first.
var _defs: Dictionary = {}

# --- The authored chain -----------------------------------------------------


## An `ItemDef` by id, through the items module's own single resolver.
func _def(item_id: String) -> ItemDef:
	if not _defs.has(item_id):
		_defs[item_id] = Crafting.resolve(StringName(item_id))
	return _defs[item_id] as ItemDef


## Every qi realm id, from the authored seeds, sorted.
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


## One realm's authored seed, or null.
func _seed(realm_id: String) -> QiRealmSeed:
	return load(REALM_DIR + realm_id + ".tres") as QiRealmSeed


## A `RecipeDef` by id, loaded from the one directory that holds them.
func _recipe(recipe_id: String) -> RecipeDef:
	if recipe_id.is_empty():
		return null
	return load(RECIPE_DIR + recipe_id + ".tres") as RecipeDef


## The `craft:` recipe `item_id` declares, or "". An item with no `craft:` source
## has no recipe, which is a finding rather than an empty list to walk past.
func _craft_recipe(item_id: String) -> String:
	var def := _def(item_id)
	if def == null:
		return ""
	for route in ItemSources.routes(def):
		if StringName(route["kind"]) == ItemSources.KIND_CRAFT:
			return String(route["ref"])
	return ""


## Every distinct route kind `item_id` declares, sorted.
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


## Every `boss:` id `item_id` names as a drop, sorted. An item can name several:
## the qi consumables that carry a direct drop name one on top of their recipe.
func _bosses_of(item_id: String) -> Array[String]:
	var out: Array[String] = []
	var def := _def(item_id)
	if def == null:
		return out
	for route in ItemSources.routes(def):
		if StringName(route["kind"]) != ItemSources.KIND_BOSS:
			continue
		var boss_id := String(route["ref"])
		if not out.has(boss_id):
			out.append(boss_id)
	out.sort()
	return out


## Whether `item_id` has at least one route shipping code can deliver.
func _has_shipped_route(item_id: String) -> bool:
	var def := _def(item_id)
	if def == null:
		return false
	for route in ItemSources.routes(def):
		if bool(route["ok"]) and ItemSources.is_shipped(StringName(route["kind"])):
			return true
	return false


## Every qi consumable, as `{realm, role, item, recipe, inputs}`, resolved purely
## from authored data and in a stable order so a failure is reproducible.
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


## Every distinct reagent the qi recipes need, sorted, so a reagent shared by
## three recipes is one hop rather than three.
func _reagents() -> Array[String]:
	var out: Array[String] = []
	for consumable in _consumables():
		for item_id in consumable["inputs"] as Array[String]:
			if not out.has(item_id):
				out.append(item_id)
	out.sort()
	return out


## Every item whose own sources the chain depends on: the consumables AND their
## reagents. A consumable can be reachable by a drop its recipe never mentions,
## which is exactly how 11 unacquirable-looking pills turn out to be acquirable.
func _chain_items() -> Array[String]:
	var out: Array[String] = []
	for consumable in _consumables():
		for item_id in [String(consumable["item"])] + (consumable["inputs"] as Array[String]):
			if not out.has(item_id):
				out.append(item_id)
	out.sort()
	return out


## The domain that hosts `boss_id`, as its own boss record declares it.
func _domain_of(boss_id: String) -> String:
	return String(LootContent.instance().boss_record(StringName(boss_id))["domain_id"])


## Every boss the qi chain names as a drop, sorted.
func _catalyst_bosses() -> Array[String]:
	var out: Array[String] = []
	for item_id in _chain_items():
		for boss_id in _bosses_of(item_id):
			if not out.has(boss_id):
				out.append(boss_id)
	out.sort()
	return out


## Every domain a qi hunt happens in: the domain of every boss the chain names.
## The domain, not the boss, is the unit a hunt clears, so this is also what stops
## the walk from re-entering a domain one run already finished (loot rule E2).
func _hunt_domains() -> Array[String]:
	var out: Array[String] = []
	for boss_id in _catalyst_bosses():
		var domain_id := _domain_of(boss_id)
		if not domain_id.is_empty() and not out.has(domain_id):
			out.append(domain_id)
	out.sort()
	return out


## Whether `recipe_id`'s every input is reachable, i.e. this consumable can be
## CRAFTED. Distinct from `_blocker` on the item: a consumable with an unshipped
## recipe input can still arrive as a direct boss drop.
func _craftable(recipe_id: String) -> bool:
	var recipe := _recipe(recipe_id)
	if recipe == null:
		return false
	for input_id in recipe.inputs:
		if not _blocker(String(input_id), 0, []).is_empty():
			return false
	return true


# --- The backward walk -----------------------------------------------------


## Whether `table_id` can yield `item_id`, nested tables included. Bounded twice
## over: by the resolver's own nesting limit, and by the ids already walked, so a
## table that references itself terminates instead of recursing on the depth guard
## alone. A `for` over a fixed array of entries cannot fail to converge; `chain`
## is the only re-entry guard this walk needs.
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
## A guaranteed entry inside a pool counts: the pool resolves it once it is
## reached, which is as unconditional as a direct entry. Bounded as `_reaches` is.
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


## "" when shipping code can deliver `item_id`, otherwise the one hop that stops.
## Depth-bounded and cycle-guarded by `chain`, which carries both item ids and
## recipe ids so a recipe that names its own ancestor terminates.
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


## Whether one shipped route can close. Mirrors what `tools/data.py` calls each
## route's membership rule, so the runtime and the catalog cannot disagree about
## what a satisfied route means.
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
			# `starter` is granted by the composition root's own list rather than by
			# a content probe, and no qi item declares it. The kinds the chain
			# actually exercises are asserted, so this stays an unreachable branch
			# rather than a silent "yes" for anything a future author adds.
			return "UNPROBED_ROUTE:%s" % String(route["kind"])


## A `boss:` route closes only once `LootApi.enter_domain` can spawn the boss,
## which needs an authored encounter in the boss's OWN domain that lists it and
## binds a table that resolves on every band.
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
			var table_id := tier.table_for(StringName(boss_id))
			if String(table_id).is_empty():
				reason = "%s: %s binds no table at band %d" % [item_id, domain_id, tier.tier]
			elif content.table(table_id) == null:
				reason = "%s: table %s does not resolve" % [item_id, table_id]
	return reason


## A `domain:` route closes only when an authored encounter spawns a boss whose
## own table can actually yield the item. No qi item declares one; the route is
## walked because a material that grows one must be judged by the same rule.
func _domain_blocker(item_id: String, domain_id: String) -> String:
	var content := LootContent.instance()
	var encounter := content.encounter_for_domain(StringName(domain_id))
	if encounter == null:
		return "%s: domain %s has no authored encounter" % [item_id, domain_id]
	for tier in encounter.tiers:
		if tier == null:
			continue
		for boss_id in encounter.boss_ids:
			var table_id := tier.table_for(boss_id)
			if not String(table_id).is_empty() and _reaches(content, String(table_id), item_id):
				return ""
	return "%s: no boss on %s can drop it" % [item_id, domain_id]


# --- The shipping program ---------------------------------------------------


## The lowest band a domain's own encounter declares, as `enter_domain` spells
## it. Read from the content rather than assumed to be 1: a tier index nothing
## authored is a refusal that reads as a wiring failure.
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
## the composition root uses. `Actor` and `Inventory` are `RefCounted`, so nothing
## here needs freeing and `queue_free` is banned in `res://src` besides.
func _hero() -> Actor:
	var actor := Actor.new(&"qi_delver", {Stat.COMPREHENSION: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor, INVENTORY_SLOTS)
	LootApi.attach(actor)
	return actor


## Clear one authored band of `domain_id` and take everything it owed, the way the
## Hunt screen does: enter, strike until the boss is defeated, claim. Returns the
## reason the run stopped so a caller can name it.
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
		if not bool(active.get("in_domain", false)):
			return _claim_all(actor)
		if bool(active.get("defeated", false)):
			return _claim_all(actor)
		var result := LootApi.strike(actor, STRIKE_DAMAGE, HUNT_SEED)
		if not bool(result.get("ok", false)):
			return "strike:" + String(result.get("reason", "?"))
		if bool(result.get("duplicate", false)):
			return _claim_all(actor)
		strikes += 1
	return "strikes_exhausted:%d" % MAX_STRIKES


## Claim every outstanding payload, so one unclaimed drop cannot look like a
## failed hunt. Claimed after each domain rather than once at the end, so the bag
## never has to hold 41 domains of unclaimed loot at once.
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


## The recipe inputs the bag is short of, so a craft failure names the drop that
## never arrived instead of only reporting that the craft failed.
func _short(recipe: RecipeDef, actor: Actor) -> String:
	var missing: Array[String] = []
	for input_id in recipe.inputs:
		if not ItemsApi.has_item(actor, input_id):
			missing.append(String(input_id))
	return "the bag is short of " + (", ".join(missing) if not missing.is_empty() else "nothing")


# --- The contract -----------------------------------------------------------


## Every realm on the ladder authors a seed, and every seed's three consumables
## resolve to a real item, a real recipe that outputs it, and real items for every
## input. Without this the rest of the suite would walk an empty graph and pass.
##
## One report, naming the first realm that does not resolve: a precondition check
## that asserts every hop of every realm reports the same defect ninety times and
## hides which one it was.
func test_every_qi_realm_authors_three_resolvable_craft_chains() -> void:
	var realms := _realms()
	assert_eq(realms.size(), REALM_COUNT, "30 qi realms are authored")
	var ladder := RealmDefaults.ladder()
	var first_broken := ""
	var checked := 0
	for realm_id in realms:
		var seed := _seed(realm_id)
		if seed == null:
			first_broken = "%s has no realm seed" % realm_id
			break
		if not ladder.has(StringName(realm_id)):
			first_broken = "%s is not on the canonical ladder" % realm_id
			break
		for role in CONSUMABLE_ROLES:
			var item_id := String(seed.get(role))
			if _def(item_id) == null:
				first_broken = "%s: %s resolves to no ItemDef" % [realm_id, item_id]
				break
			var recipe_id := _craft_recipe(item_id)
			if recipe_id.is_empty():
				first_broken = (
					"%s: %s declares no craft: route (sources %s)"
					% [
						realm_id,
						item_id,
						_kinds(item_id),
					]
				)
				break
			var recipe := _recipe(recipe_id)
			if recipe == null:
				first_broken = "%s: recipe %s does not load" % [realm_id, recipe_id]
				break
			if not (recipe.outputs as Array).has(StringName(item_id)):
				first_broken = (
					"%s: %s does not list %s as an output" % [realm_id, recipe_id, item_id]
				)
				break
			if recipe.inputs.is_empty():
				first_broken = (
					"%s: %s consumes nothing, so the pill is free" % [realm_id, recipe_id]
				)
				break
			for input_id in recipe.inputs:
				if _def(String(input_id)) == null:
					first_broken = (
						"%s: %s needs %s, which resolves to no ItemDef"
						% [
							realm_id,
							recipe_id,
							input_id,
						]
					)
					break
			if not first_broken.is_empty():
				break
			checked += 1
		if not first_broken.is_empty():
			break
	assert_eq(first_broken, "", "every qi realm's craft chain resolves")
	assert_eq(checked, REALM_COUNT * CONSUMABLE_ROLES.size(), "all 90 consumables walked")


## The whole point, part one: every boss the qi chain names must be a real boss,
## hosted by an authored encounter, in the domain its own record declares. A
## `boss:` source is only delivered once `LootApi.enter_domain` can spawn it, so
## an authoring claim a player can never cash is a content defect. This covers the
## consumables' own drops as well as the reagents', which is where 15 of them hide.
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


## One authority per domain: a domain the qi chain hunts carries exactly one
## encounter, that encounter spawns every boss the domain declares, and every band
## binds a table that resolves. `encounter_for_domain` answers with the first
## match, so a second encounter for a domain is invisible to every other check —
## the loser sits on disk holding a boss nothing can spawn (rule E10's shape).
func test_every_qi_hunt_domain_carries_one_encounter_that_spawns_what_it_declares() -> void:
	var content := LootContent.instance()
	var claims: Dictionary = {}
	for encounter_id in content.encounter_ids():
		var encounter := content.encounter_by_id(StringName(encounter_id))
		if encounter == null:
			continue
		var ids: Array = claims.get(String(encounter.domain_id), [])
		ids.append(String(encounter.id))
		claims[String(encounter.domain_id)] = ids
	var hunted := 0
	var bands := 0
	for domain_id in _hunt_domains():
		var ids: Array = claims.get(domain_id, [])
		assert_eq(ids.size(), 1, "%s carries exactly one encounter" % domain_id)
		if ids.size() != 1:
			continue
		var encounter := content.encounter_by_id(StringName(ids[0]))
		hunted += 1
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
	assert_eq(hunted, HUNT_DOMAIN_COUNT, "the qi chain hunts exactly 41 domains")
	assert_eq(bands > hunted, true, "every hunted domain has more than one band")


## GAP 2, pinned. A cleared band grants no second run (loot rule E2), so a
## catalyst that is only *rolled* can leave a player permanently unable to reach
## the next realm. Every boss-sourced item in the qi chain must therefore be a
## guaranteed entry of the LOWEST band of the encounter hosting it — the band a
## walk clears, and the cheapest to clear.
##
## Every REAGENT already is. Every CONSUMABLE that a boss drops is not: all 15 are
## rolled, and for 11 of them that drop is the only route to the consumable, so a
## miss is permanent. `tools acquisition validate` reports clean because
## `Trial.catalysts` is built from a reagent's `boss:` sources only.
func test_every_boss_sourced_qi_reagent_is_guaranteed_and_the_rolled_consumables_pinned() -> void:
	var content := LootContent.instance()
	var guaranteed := 0
	var rolled: Array[String] = []
	for item_id in _chain_items():
		for boss_id in _bosses_of(item_id):
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
				reaches = _reaches(content, table_id, item_id)
				unconditional = _guarantees(content, table_id, item_id)
			assert_eq(
				reaches, true, "%s is droppable by %s at band %d" % [item_id, boss_id, lowest]
			)
			if reaches and not unconditional:
				rolled.append(item_id)
			elif unconditional:
				guaranteed += 1
	rolled.sort()
	assert_eq(guaranteed > 0, true, "at least one qi catalyst is guaranteed")
	assert_eq(
		rolled,
		PINNED_ROLLED_CONSUMABLES as Array[String],
		(
			"the qi consumables left to a roll — a cleared band grants no second run, so each"
			+ " of these is a permanent soft-lock unless it also arrives another way"
		)
	)


## GAP 1, pinned. The ONLY reason any qi consumable is unreachable is that some
## reagent rests on a route kind no shipping code implements. Everything else —
## resolution, recipe, host, domain, binding — is proven reachable here, so a new
## break names itself instead of hiding inside the known gap.
func test_the_only_unreachable_hop_in_the_qi_chain_is_the_unshipped_route_gap() -> void:
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
			# A reagent with no shipped route must be ENTIRELY unshipped. One that
			# declared a shipped kind alongside these would be a real break wearing
			# the gap's name, so the kinds are re-checked rather than trusted above.
			if ItemSources.is_shipped(StringName(kind)):
				other.append("%s declares shipped kind %s but resolves no route" % [item_id, kind])
	unshipped.sort()
	exercised.sort()
	var blocked_by_role: Dictionary = {}
	for role in CONSUMABLE_ROLES:
		blocked_by_role[role] = 0
	for consumable in _consumables():
		var entry := consumable as Dictionary
		var reason := _blocker(String(entry["item"]), 0, [])
		if reason.is_empty():
			continue
		if reason.contains(UNSHIPPED_MARKER):
			blocked_by_role[entry["role"]] = int(blocked_by_role[entry["role"]]) + 1
		else:
			other.append("%s %s: %s" % [entry["realm"], entry["role"], reason])
	assert_eq(other, [] as Array[String], "no qi hop is unreachable for any other reason")
	assert_eq(
		unshipped.size(),
		PINNED_UNSHIPPED_REAGENTS,
		"the pinned unshipped-route qi reagent count has not moved"
	)
	assert_eq(
		blocked_by_role,
		PINNED_BLOCKED_BY_ROLE,
		"the pinned per-role count of qi consumables the gap leaves unacquirable"
	)
	assert_eq(
		int(blocked_by_role["recovery_item"]),
		REALM_COUNT,
		"no qi realm has a shipping route to its recovery elixir"
	)
	assert_eq(
		exercised,
		["boss", "craft", "gather", "quest"] as Array[String],
		"the qi chain declares only kinds the backward walk and the catalog both know"
	)


## The end-to-end proof for everything the gap leaves craftable: hunt every domain
## the qi chain names, take what its bosses drop, and craft every consumable whose
## recipe inputs are all reachable. This is the chain a player walks, and it is
## what the qi gate audits never exercise because `Probe.stock` grants items
## outright.
##
## The 11 consumables that are reachable ONLY as a rolled boss drop are not
## attempted: they are the soft-lock GAP 2 names, so requiring them here would be
## asserting the defect away. The 41 the gap leaves unacquirable are named by the
## test above. Neither is hidden — both are counted, and the three counts must sum
## to the whole ladder.
func test_every_craftable_qi_consumable_is_crafted_end_to_end_from_its_trial() -> void:
	var domains := _hunt_domains()
	assert_eq(domains.is_empty(), false, "the qi chain names at least one hunt domain")
	var actor := _hero()
	var first_failure := ""
	for domain_id in domains:
		var reason := _hunt(actor, domain_id, _first_tier(domain_id))
		if reason != "claimed":
			first_failure = "hunting %s stopped: %s" % [domain_id, reason]
			break
	var crafted := 0
	var drop_only := 0
	var unacquirable := 0
	if first_failure.is_empty():
		for consumable in _consumables():
			var entry := consumable as Dictionary
			# Three outcomes, and the difference matters: an item with a blocker has
			# NO shipping route at all, while an unblocked item whose recipe is
			# blocked still arrives as a direct boss drop. Collapsing the second into
			# the first is what would let a rolled drop pass for a craftable pill.
			if not _blocker(String(entry["item"]), 0, []).is_empty():
				unacquirable += 1
				continue
			if not _craftable(String(entry["recipe"])):
				drop_only += 1
				continue
			var recipe := _recipe(String(entry["recipe"]))
			if recipe == null:
				first_failure = "%s: recipe %s does not load" % [entry["realm"], entry["recipe"]]
				break
			if not ItemsApi.craft(recipe, ItemsApi.inventory(actor)):
				first_failure = (
					"%s: crafting %s failed, %s"
					% [
						entry["realm"],
						entry["item"],
						_short(recipe, actor),
					]
				)
				break
			if not ItemsApi.has_item(actor, StringName(entry["item"])):
				first_failure = (
					"%s: crafted %s but the bag does not hold it"
					% [
						entry["realm"],
						entry["item"],
					]
				)
				break
			crafted += 1
	assert_eq(
		first_failure, "", "every craftable qi consumable is crafted from what its own trials drop"
	)
	assert_eq(
		crafted + drop_only + unacquirable,
		REALM_COUNT * CONSUMABLE_ROLES.size(),
		"every qi consumable was crafted, dropped, or named as gap-blocked"
	)
	assert_eq(crafted, 38, "38 qi consumables are craftable through the shipping program")
	assert_eq(drop_only, 11, "11 qi consumables are reachable only as a rolled boss drop")
	assert_eq(unacquirable, 41, "41 qi consumables have no shipping route at all")
