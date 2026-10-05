extends TestCase

## The Mind path's recovery content is authored, wired, and — until this file
## existed — never measured.
##
## Every realm seed names a `recovery_item` and `MindCultivationApi.recover_next`
## spends it (ADR 0031), but the two neighbouring ladders each carry an acquisition
## suite that walks the authored graph end to end and `mind` carried none. A finding
## recorded against the mind chain therefore decayed silently: it claimed the thirty
## elixirs rested only on `gather:`/`quest:`, which `ItemSources.KINDS` marks
## `shipped: false`. Measured against the corpus that is false — all thirty declare a
## `craft:` route, which is shipped — so the finding had gone stale before anyone
## acted on it. The gap this file closes is the measurement, and the pin below is
## what stops the next finding decaying the same way.
##
## Nothing here hands an actor an `ItemDef`. Every assertion walks the authored graph
## — `ItemDef.sources` -> reagent -> boss/domain -> `LootApi` -> `ItemsApi.craft` ->
## `MindCultivationApi` — because a declared source no shipping code can deliver is
## exactly the defect this suite exists to catch (ADR 0007).
##
## ## The one place this suite differs from the body's
##
## `_paying_domains` reads BOTH `boss:` and `domain:` refs. A boss-only walk reports
## thirteen mind reagents as naming no boss at all, which is the false negative that
## made the stale finding plausible in the first place: those reagents declare a
## `domain:` route instead, and a domain route is delivered by whichever table that
## domain's encounter binds.
##
## Every loop is bounded and names the condition that failed to converge.

const REALM_DIR := "res://data/mind_cultivation/realms/"
const RECIPE_DIR := "res://data/recipes/"
const REALM_COUNT := 30
## One strike spends this much vitality, as the composition root's strike damage.
const STRIKE_DAMAGE := 25.0
## Stops when a boss's authored vitality stops falling. Names the condition: a table
## that never resolves a defeat would otherwise strike forever.
const MAX_STRIKES := 64
## Stops claiming payloads when nothing is pending. Names the condition: a drop that
## never leaves the pending state would otherwise be re-claimed forever.
const MAX_CLAIMS := 16
## Enough slots for both reagents, the elixir, and every filler drop a hunt pays.
const INVENTORY_SLOTS := 128

## `Crafting.resolve` walks the whole item tree on a miss, and a `mind_*` id misses
## its category guess, so the resolver is the one thing memoized here. Everything else
## is derived fresh, so no case's answer depends on which case ran first.
var _defs: Dictionary = {}

# --- The authored chain -----------------------------------------------------


## An `ItemDef` by id, through the items module's own single resolver.
func _def(item_id: String) -> ItemDef:
	if not _defs.has(item_id):
		_defs[item_id] = Crafting.resolve(StringName(item_id))
	return _defs[item_id] as ItemDef


## Every mind realm id, from the authored seeds, sorted.
func _realms() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(REALM_DIR)
	assert_ne(dir, null, "the mind realm seed directory opens")
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


## The refs of one kind on an item, as `[kind, ref]` pairs the reader accepts.
func _refs_of(item_id: String, kind: String) -> Array[String]:
	var out: Array[String] = []
	var def := _def(item_id)
	if def == null:
		return out
	for source in def.sources:
		if source.begins_with(kind + ":"):
			out.append(String(source).trim_prefix(kind + ":"))
	return out


## `{elixir, recipe, reagents}`, resolved purely from authored data.
##
## The recipe is read off the elixir's own `craft:` route rather than rebuilt from a
## naming convention, so a realm that renames its recipe fails here as an unresolved
## route instead of silently loading a file that happens to match.
func _chain(realm_id: String) -> Dictionary:
	var seed := load(REALM_DIR + realm_id + ".tres") as MindRealmSeed
	var elixir := "" if seed == null else String(seed.recovery_item)
	var craft := _refs_of(elixir, "craft")
	var recipe_id := "" if craft.is_empty() else craft[0]
	var recipe := load(RECIPE_DIR + recipe_id + ".tres") as RecipeDef
	var reagents: Array = []
	for input_id in recipe.inputs if recipe != null else [] as Array[StringName]:
		reagents.append(String(input_id))
	return {"seed": seed, "elixir": elixir, "recipe": recipe_id, "reagents": reagents}


## The domains that can pay `reagent_id`, from its SHIPPED routes only.
##
## `gather` and `quest` are `shipped: false` in `ItemSources.KINDS`, so they are not
## a domain and are not walked: a route the runtime cannot deliver is not a place a
## player goes. `boss:` is resolved through the boss's own record, because that is
## where the domain it lives in is authored.
func _paying_domains(reagent_id: String) -> Array[String]:
	var out: Array[String] = []
	for boss_id in _refs_of(reagent_id, "boss"):
		var domain_id := _domain_of(boss_id)
		if not domain_id.is_empty() and not out.has(domain_id):
			out.append(domain_id)
	for domain_id in _refs_of(reagent_id, "domain"):
		if not out.has(domain_id):
			out.append(domain_id)
	out.sort()
	return out


## The domain that hosts `boss_id`, as its own boss record declares it.
func _domain_of(boss_id: String) -> String:
	return String(LootContent.instance().boss_record(StringName(boss_id))["domain_id"])


## Every domain a realm's recovery reagents live in, sorted. One run through a
## domain defeats every boss it lists (loot rule E3), so the hunt is per domain.
func _reagent_domains(realm_id: String) -> Array[String]:
	var out: Array[String] = []
	for reagent_id in _chain(realm_id)["reagents"] as Array:
		for domain_id in _paying_domains(String(reagent_id)):
			if not out.has(domain_id):
				out.append(domain_id)
	out.sort()
	return out


# --- The shipping program ---------------------------------------------------


## The lowest band a domain's own encounter declares, as `enter_domain` spells it.
## Read from the content rather than assumed to be 0: a tier index nothing authored
## is an `unknown_tier` refusal that reads as a wiring failure.
func _first_tier(domain_id: String) -> int:
	var encounter := LootContent.instance().encounter_for_domain(StringName(domain_id))
	if encounter == null or encounter.tiers.is_empty():
		return -1
	var lowest := encounter.tiers[0].tier
	for tier in encounter.tiers:
		if tier != null:
			lowest = mini(lowest, tier.tier)
	return lowest


## A delver with the loot lifecycle and an inventory attached, in the same order the
## composition root uses.
func _hero() -> Actor:
	var actor := Actor.new(&"mind_delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor, INVENTORY_SLOTS)
	LootApi.attach(actor)
	return actor


## Clear one authored band of `domain_id` and take everything it owed, the way the
## Hunt screen does: enter, strike until the boss is defeated, claim. Returns the
## reason the run stopped so a caller can name it.
func _hunt(actor: Actor, domain_id: String, tier: int) -> String:
	var entered := LootApi.enter_domain(actor, StringName(domain_id), tier, 20261004)
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
		var result := LootApi.strike(actor, STRIKE_DAMAGE, 20261004)
		if not bool(result.get("ok", false)):
			return "strike:" + String(result.get("reason", "?"))
		if bool(result.get("duplicate", false)):
			return _claim_all(actor)
		strikes += 1
	return "strikes_exhausted:%d" % MAX_STRIKES


## Claim every outstanding payload, so one unclaimed drop cannot look like a failed
## hunt.
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


## Without this the rest of the suite would walk an empty graph and pass.
##
## One report, naming the first realm that does not resolve: a precondition check
## that asserts every hop of every realm reports the same defect thirty times and
## hides which one it was.
func test_every_mind_realm_authors_a_resolvable_recovery_chain() -> void:
	var realms := _realms()
	assert_eq(realms.size(), REALM_COUNT, "30 mind realms are authored")
	var ladder := RealmDefaults.ladder()
	var first_broken := ""
	for realm_id in realms:
		var chain := _chain(realm_id)
		if chain["seed"] == null:
			first_broken = "%s has no realm seed" % realm_id
		elif not ladder.has(StringName(realm_id)):
			first_broken = "%s is not on the canonical ladder" % realm_id
		elif _def(String(chain["elixir"])) == null:
			first_broken = "%s: recovery_item %s is not an item" % [realm_id, chain["elixir"]]
		elif String(chain["recipe"]).is_empty():
			first_broken = "%s: %s declares no craft route" % [realm_id, chain["elixir"]]
		elif (chain["reagents"] as Array).is_empty():
			first_broken = "%s: recipe %s has no inputs" % [realm_id, chain["recipe"]]
		if not first_broken.is_empty():
			break
	assert_eq(first_broken, "", "every realm's recovery chain resolves")


## Every reagent must name a domain an authored encounter can spawn, and that
## encounter must actually pay the reagent. A `domain:` route is delivered only by a
## table the encounter binds, so an encounter that exists but pays nothing closes the
## graph on paper and nothing else.
func test_every_mind_recovery_reagent_is_paid_by_a_hosted_encounter() -> void:
	var content := LootContent.instance()
	var first_broken := ""
	var paid := 0
	for realm_id in _realms():
		for reagent_id in _chain(realm_id)["reagents"] as Array:
			var domains := _paying_domains(String(reagent_id))
			if domains.is_empty():
				first_broken = "%s: %s names no shipped route" % [realm_id, reagent_id]
				break
			for domain_id in domains:
				var encounter := content.encounter_for_domain(StringName(domain_id))
				if encounter == null:
					first_broken = (
						"%s: %s names domain %s, which has no encounter"
						% [
							realm_id,
							reagent_id,
							domain_id,
						]
					)
					break
				if _reachable(content, encounter, String(reagent_id)):
					paid += 1
			if not first_broken.is_empty():
				break
		if not first_broken.is_empty():
			break
	assert_eq(first_broken, "", "every reagent is paid by an authored encounter")
	assert_eq(paid > 0, true, "at least one reagent is paid")


## Whether any table this encounter binds can hand out `item_id`, read through the
## runtime's own nesting-aware resolver rather than by scanning `.tres` text.
func _reachable(content: LootContent, encounter: LootEncounterDef, item_id: String) -> bool:
	for tier in encounter.tiers:
		if tier == null:
			continue
		for boss_id in encounter.boss_ids:
			var table := content.table(tier.table_for(boss_id))
			if table == null:
				continue
			if (table.reachable_item_ids() as Array).has(StringName(item_id)):
				return true
	return false


## THE end-to-end proof, for every realm: hunt the domains its recovery reagents
## live in, take what they drop, and craft the realm's recovery elixir out of it.
## This is the chain a player walks; handing an actor an item directly would not
## fail here.
##
## A realm that breaks reports once, naming the hop that stopped, and the walk
## continues — asserting every hop of every realm would turn one rolled reagent into
## thirty identical lines and bury the cause.
func test_every_mind_recovery_elixir_is_acquirable_through_the_shipping_program() -> void:
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
			"every realm's recovery elixir is craftable from what its own drops pay "
			+ (
				"(first failure: %s)"
				% (first_failure if not first_failure.is_empty() else first_failure)
			)
		)
	)


## Hunt every domain a realm's recovery reagents live in, then craft its elixir.
## Returns "" when the whole chain worked, and otherwise one sentence naming the hop
## that stopped, because "acquisition is broken" is not a diagnosis.
func _acquire(realm_id: String) -> String:
	var chain := _chain(realm_id)
	var actor := _hero()
	for domain_id in _reagent_domains(realm_id):
		var reason := _hunt(actor, domain_id, _first_tier(domain_id))
		if reason != "claimed":
			return "%s: hunting %s stopped: %s" % [realm_id, domain_id, reason]
	var recipe := load(RECIPE_DIR + String(chain["recipe"]) + ".tres") as RecipeDef
	if recipe == null:
		return "%s: recipe %s does not load" % [realm_id, chain["recipe"]]
	if not ItemsApi.craft(recipe, ItemsApi.inventory(actor)):
		return (
			"%s: crafting %s failed, %s"
			% [
				realm_id,
				chain["elixir"],
				_missing_inputs(recipe, actor),
			]
		)
	if not ItemsApi.has_item(actor, StringName(chain["elixir"])):
		return "%s: crafted %s but the bag does not hold it" % [realm_id, chain["elixir"]]
	return ""


## The recipe inputs the bag is short of, so a craft failure names the drop that
## never arrived instead of only reporting that the craft failed.
func _missing_inputs(recipe: RecipeDef, actor: Actor) -> String:
	var short: Array[String] = []
	for input_id in recipe.inputs:
		if not ItemsApi.has_item(actor, input_id):
			short.append(String(input_id))
	return "the bag is short of " + (", ".join(short) if not short.is_empty() else "nothing")


## A cleared band grants no second run (loot rule E2), so a reagent that is only
## ROLLED can leave a player permanently unable to craft the realm's recovery elixir
## — and, because `recover_next` spends that elixir, permanently unable to close the
## wound a failed breakthrough left. Every reagent therefore has to be a guaranteed
## entry of the table that pays it, not a candidate in a weighted draw.
##
## This is the pin that keeps the finding measurable. It fails the moment one is
## promoted, so the list shrinks one id at a time instead of decaying into a claim
## nobody re-measured.
func test_every_mind_recovery_reagent_is_guaranteed_not_rolled() -> void:
	var content := LootContent.instance()
	var guaranteed := 0
	var first_rolled := ""
	for realm_id in _realms():
		for reagent_id in _chain(realm_id)["reagents"] as Array:
			for domain_id in _paying_domains(String(reagent_id)):
				var encounter := content.encounter_for_domain(StringName(domain_id))
				if encounter == null:
					continue
				for tier in encounter.tiers:
					if tier == null:
						continue
					for boss_id in encounter.boss_ids:
						var table := content.table(tier.table_for(boss_id))
						if table == null:
							continue
						for entry in table.entries:
							if entry == null or entry.is_nested():
								continue
							if entry.item_id != StringName(reagent_id):
								continue
							if entry.guaranteed:
								guaranteed += 1
							elif first_rolled.is_empty():
								first_rolled = (
									"%s is rolled on %s at tier %d"
									% [
										reagent_id,
										String(table.id),
										tier.tier,
									]
								)
	assert_eq(
		first_rolled,
		"",
		"no mind recovery reagent is left to a roll (first offender: %s)" % first_rolled
	)
	assert_eq(guaranteed > 0, true, "at least one reagent is a guaranteed entry")


## The reason the chain above matters: the elixir a player crafts from a drop is the
## same one `recover_next` spends. Acquiring an item nothing consumes would leave the
## content reachable and the mechanic unreachable, which is the same failure one hop
## later.
##
## The wound is set up through `damage_meridian` because that is what a mind
## deviation does; the acquisition under test is the hunt and the craft above, so the
## fixture hands over nothing.
func test_a_crafted_recovery_elixir_is_the_one_recover_next_spends() -> void:
	var realm_id := "core_formation"
	var chain := _chain(realm_id)
	var actor := _hero()
	for domain_id in _reagent_domains(realm_id):
		assert_eq(
			_hunt(actor, domain_id, _first_tier(domain_id)), "claimed", "%s is hunted" % domain_id
		)
	var recipe := load(RECIPE_DIR + String(chain["recipe"]) + ".tres") as RecipeDef
	assert_ne(recipe, null, "the realm's recovery recipe loads")
	assert_eq(
		ItemsApi.craft(recipe, ItemsApi.inventory(actor)), true, "the elixir is crafted from drops"
	)

	# Stand the actor at the realm whose elixir it now holds, and open a wound.
	actor.set_path(PathState.new(MindPath.PATH_ID, StringName(realm_id)))
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	actor.meridians.unlock_for_realm(StringName(realm_id))
	var burned := _injure_first_required(actor, realm_id)
	assert_ne(String(burned), "", "the realm has a channel to burn")
	var held := ItemsApi.has_item(actor, StringName(chain["elixir"]))
	assert_eq(held, true, "the crafted elixir is in the bag before recovery")
	assert_eq(MindCultivationApi.recover_next(actor), true, "recover_next closes the wound")
	assert_eq(
		actor.meridians.get_meridian(StringName(burned)).is_injured(),
		false,
		"the channel is repaired"
	)
	assert_eq(
		ItemsApi.has_item(actor, StringName(chain["elixir"])),
		false,
		"the elixir was spent, so the recovery cost the item the hunt paid for"
	)


## The first channel of `realm_id`'s authored requirement list that exists on the
## actor, injured. Returns "" when the seed names none, which the caller reports.
func _injure_first_required(actor: Actor, realm_id: String) -> String:
	var seed := load(REALM_DIR + realm_id + ".tres") as MindRealmSeed
	if seed == null:
		return ""
	for meridian_id in seed.required_meridians:
		if actor.meridians.get_meridian(meridian_id) == null:
			continue
		actor.meridians.damage_meridian(meridian_id)
		if actor.meridians.get_meridian(meridian_id).is_injured():
			return String(meridian_id)
	return ""
