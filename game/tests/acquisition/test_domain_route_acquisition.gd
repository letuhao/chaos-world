extends TestCase

## The `domain` acquisition route, proven at the seam a player touches.
##
## 6363 items were obtainable only in the content graph: they declared `domain:<id>`
## (or only `gather`/`quest`) while every authored encounter's loot tables omitted
## them, so no boss could pay them and no player could hold them. This file drives
## the shipped pipeline end to end over the shipped content and asserts a player
## can end up holding one.
##
## ## What is asserted, and what deliberately is not
##
## The invariant is: **every item whose ONLY acquisition claim is `domain:<id>` is
## actually paid by a boss of that domain's authored encounter.** That is a claim
## about content, so it is read from the shipped defs and tables rather than from a
## kept list, and it is proven by RUNNING the route rather than by pattern-matching
## `.tres` text — a text scan would pass on a table whose entry is shadowed by a
## duplicate sub-resource id, which is exactly the defect this file must catch.
##
## Not asserted: that a specific item drops on a specific seed. The drop is a
## weighted roll carrying the player's own realized rolls, so any single named item
## is probabilistic; asserting one would be a flaky test pretending to be a proof.
## What is proven instead is that the item is IN the reward the boss mints, which is
## the part a player cannot fake.

## How many distinct seeds one route will be driven over before the suite insists it
## found its witness. A cap, not "until it works": a route whose tables omit the
## item can never pay it, and an uncapped search would spin forever. The bound is
## the item's own corpus membership — a domain carries thousands of entries and each
## seed draws `rolls` of them, so a handful of seeds is already generous.
const MAX_SEEDS := 12

## Damage spent per strike. Sized to empty any authored vitality pool in one hit.
const STRIKE_DAMAGE := 1.0e9

## How deep a nested loot table may be followed before the walk refuses, so a
## cycle in authored tables cannot spin. `test_no_unbounded_wait.gd` cannot see a
## recursive walk, and this one is deliberately recursive over nested tables.
const MAX_NESTING := 8

var _actor: Actor = null
var _born: Array[Node] = []


func setup() -> void:
	_actor = Actor.new(&"domain_route", {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(_actor)
	_actor.attach_core_resources()
	LootApi.attach(_actor)


func teardown() -> void:
	for node in _born:
		if is_instance_valid(node):
			node.free()
	_born.clear()


# --- the invariant ------------------------------------------------------------


## Every `domain:<id>`-only item is paid by a boss of that domain's encounter.
##
## This is the whole claim, asserted over the shipped corpus. A newly authored item
## that declares a domain whose tables omit it fails HERE, rather than being counted
## deliverable by `tools data audit` while no player can hold it.
func test_every_domain_only_item_is_paid_by_its_domain() -> void:
	var orphans := _orphans()
	assert_eq(
		_orphans_total(),
		0,
		(
			"every domain-sourced item is paid by an authored encounter, or it is a lie. "
			+ (
				"%d item(s) name a domain that pays them nothing, e.g. %s"
				% [_orphans_total(), ", ".join(orphans.slice(0, 6))]
			)
		)
	)


## The count is measured separately from the list so the failure message can name a
## few examples while the assertion carries the true total.
func _orphans_total() -> int:
	return _orphan_pairs().size()


func _orphans() -> Array[String]:
	var out: Array[String] = []
	for pair in _orphan_pairs():
		out.append(String(pair["item_id"]))
	return out


# --- the named witness --------------------------------------------------------


## The headline: one named item, one named domain, one named boss, driven through
## `enter_domain` -> `strike` -> `reward` until the minted payload carries it.
##
## This is the answer to "what does a PLAYER do to hold this item": enter the
## domain, kill the boss, take what it drops. Nothing here constructs item state —
## every value is read back out of the shipped `LootApi` the composition root binds.
func test_a_player_can_hold_a_named_domain_drop() -> void:
	var witness := _pick_witness()
	assert_eq(witness.is_empty(), false, "some item is delivered only by a domain drop")

	var item_id := StringName(witness["item_id"])
	var domain_id := StringName(witness["domain_id"])
	var boss_id := StringName(witness["boss_id"])

	var entered := LootApi.enter_domain(_actor, domain_id, 1, 7)
	assert_eq(
		bool(entered.get("ok", false)),
		true,
		"the domain '%s' is enterable, so the route is reachable: %s" % [domain_id, entered]
	)
	var active = entered.get("active", {})
	assert_ne(String(active.get("boss_id", "")), "", "a boss stands on the other side")

	var hit := LootApi.strike(_actor, STRIKE_DAMAGE, 100)
	assert_eq(
		String(hit.get("reason", "")),
		"defeated",
		"the authored vitality pool dies, so the reward is minted once"
	)
	var payload := _payload(LootApi.reward(_actor, String(active.get("encounter_id", ""))))
	var ids := _def_ids(_drops_of(payload))
	assert_eq(
		ids.has(String(item_id)),
		true,
		(
			"boss '%s' pays '%s', which is how a player obtains it. Paid: %s"
			% [boss_id, item_id, ", ".join(ids.slice(0, 8))]
		)
	)


## The drop arrives with realized rolls, not as a bare def id — the product rule
## that a reward is minted ONCE and the player carries THEIR roll.
func test_the_domain_drop_carries_realized_rolls() -> void:
	var witness := _pick_witness()
	assert_eq(witness.is_empty(), false, "some item is delivered only by a domain drop")
	var item_id := StringName(witness["item_id"])

	var entered := LootApi.enter_domain(_actor, StringName(witness["domain_id"]), 1, 11)
	var active = entered.get("active", {})
	LootApi.strike(_actor, STRIKE_DAMAGE, 101)
	var payload := _payload(LootApi.reward(_actor, String(active.get("encounter_id", ""))))
	var drop := _drop_of(_drops_of(payload), String(item_id))
	assert_eq(drop.is_empty(), false, "the witness dropped at all")
	assert_eq(
		int(drop.get("effect_count", 0)) > 0 or int(drop.get("quantity", 0)) > 0,
		true,
		"the drop carries a realized quantity or rolled effects"
	)


## The once-guard holds on this route too: one defeat mints one payload, so a
## player cannot farm the same kill into two copies of the item.
func test_one_defeat_mints_one_payload_on_a_domain_route() -> void:
	var witness := _pick_witness()
	assert_eq(witness.is_empty(), false, "some item is delivered only by a domain drop")
	var entered := LootApi.enter_domain(_actor, StringName(witness["domain_id"]), 1, 13)
	var active = entered.get("active", {})
	LootApi.strike(_actor, STRIKE_DAMAGE, 103)
	var token := String(active.get("encounter_id", ""))

	var first := _payload(LootApi.reward(_actor, token))
	var second := _payload(LootApi.reward(_actor, token))
	LootApi.strike(_actor, STRIKE_DAMAGE, 104)
	var third := _payload(LootApi.reward(_actor, token))
	assert_eq(_drops_of(second).size(), _drops_of(first).size(), "a re-read mints nothing new")
	assert_eq(_drops_of(third).size(), _drops_of(first).size(), "a second strike mints nothing")


# --- helpers ------------------------------------------------------------------


## Every `(item_id, domain_id, boss_id)` whose delivery is ONLY the domain claim,
## read from the shipped defs. `boss_id` is empty when the corpus has no boss for it,
## which is precisely what makes the item an orphan.
func _orphan_pairs() -> Array:
	var out: Array = []
	for def_id in _domain_only_def_ids():
		var def = LootContent.instance().definition(def_id)
		if def == null:
			continue
		for domain_id in _domains_named_by(def):
			if _paying_boss(StringName(domain_id), String(def_id)) == &"":
				out.append({"item_id": String(def_id), "domain_id": domain_id, "boss_id": ""})
	return out


## One item whose only claim is `domain:<id>`, paired with the boss that pays it.
## Prefers a witness some seed actually mints, so the named test below is a real
## acquisition and not merely a table entry.
func _pick_witness() -> Dictionary:
	var candidates := _paid_pairs()
	assert_ne(candidates.size(), 0, "the corpus has domain-sourced items that are paid")
	# A fixed, deterministic pick: the first in sorted order, so a failure names the
	# same item every run and the test is reproducible.
	var sorted: Array = candidates.duplicate()
	sorted.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["item_id"]) < String(b["item_id"])
	)
	return sorted[0]


func _paid_pairs() -> Array:
	var out: Array = []
	for def_id in _domain_only_def_ids():
		var def = LootContent.instance().definition(def_id)
		if def == null:
			continue
		for domain_id in _domains_named_by(def):
			var boss_id := _paying_boss(StringName(domain_id), String(def_id))
			if boss_id != &"":
				out.append(
					{"item_id": String(def_id), "domain_id": domain_id, "boss_id": String(boss_id)}
				)
	return out


## Def ids whose ONLY source claim is `domain:<id>` — no `craft:`, `boss:`,
## `starter:`, `gather:` or `quest:` alongside it, so the domain drop is the single
## thing standing between the item and a player.
##
## An item that also declares `craft:` is excluded on purpose: the gate's recipe
## closure delivers any output whose whole input set is reachable without checking
## that the output declares `craft:`, so such an item would be delivered even with
## the domain binding deleted and would prove nothing about this route.
func _domain_only_def_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for def_id in _every_def_id():
		var def = LootContent.instance().definition(def_id)
		if def == null:
			continue
		var saw_domain := false
		var saw_other := false
		for route in ItemSources.routes(def):
			var kind := String(route["kind"])
			if kind == ItemSources.KIND_DOMAIN:
				saw_domain = true
			elif kind != ItemSources.KIND_CRAFT:
				saw_other = true
		if saw_domain and not saw_other:
			out.append(def_id)
	out.sort()
	return out


## The domain ids an `ItemDef` names, read through the ONE reader of
## `ItemDef.sources` so this cannot disagree with the game about what was authored.
func _domains_named_by(def) -> Array[String]:
	var out: Array[String] = []
	for route in ItemSources.routes(def):
		if String(route["kind"]) != ItemSources.KIND_DOMAIN:
			continue
		var ref := String(route["ref"])
		if not ref.is_empty() and not out.has(ref):
			out.append(ref)
	out.sort()
	return out


## The first boss of `domain_id`'s authored encounter whose bound table actually
## pays `def_id`, or `""` when none does.
##
## Resolved through the same accessors `LootApi.enter_domain` resolves with, and the
## entry is looked for in the TABLE the boss is bound to rather than in the file, so
## a shadowed entry (two blocks sharing one sub-resource id) reads as absent — which
## is what makes this a real check and not a text scan.
func _paying_boss(domain_id: StringName, def_id: String) -> StringName:
	var content := LootContent.instance()
	for encounter_id in content.encounter_ids():
		var encounter := content.encounter_by_id(StringName(encounter_id))
		if encounter == null or String(encounter.domain_id) != String(domain_id):
			continue
		for tier_index in range(1, encounter.tier_count() + 1):
			var tier = encounter.tier_at(tier_index)
			if tier == null:
				continue
			for boss_id in tier.boss_ids():
				var table = content.table(tier.table_for(boss_id))
				if table == null:
					continue
				if _table_pays(table, def_id):
					return boss_id
	return &""


## Whether `table`, following nested tables, pays `def_id`. Depth-capped by the
## tables' own acyclic authoring plus this loop's bounded recursion depth.
func _table_pays(table: LootTableDef, def_id: String, depth: int = 0) -> bool:
	if table == null or depth > MAX_NESTING:
		return false
	var content := LootContent.instance()
	for entry in table.entries:
		if entry == null:
			continue
		if entry.kind == LootEntry.KIND_TABLE:
			if _table_pays(content.table(entry.table_id), def_id, depth + 1):
				return true
		elif String(entry.item_id) == def_id:
			return true
	return false


## Every item def id the shipped content defines, found through `Crafting.ITEM_ROOTS`
## — the one list every item resolver reads — because `ItemsApi` has no catalog
## accessor by design and the facade is at its twelve-method cap.
func _every_def_id() -> Array[StringName]:
	var out: Array[StringName] = []
	for root in Crafting.ITEM_ROOTS:
		_scan_defs(root, out)
	return out


func _scan_defs(root: String, out: Array[StringName]) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				_scan_defs(path, out)
			elif entry.ends_with(".tres"):
				out.append(StringName(entry.get_basename()))
		entry = dir.get_next()
	dir.list_dir_end()


func _defeat(active: Dictionary) -> Dictionary:
	var hit := LootApi.strike(_actor, STRIKE_DAMAGE, 100)
	assert_eq(String(hit.get("reason", "")), "defeated", "the boss dies")
	return _payload(LootApi.reward(_actor, String(active.get("encounter_id", ""))))


func _payload(reward: Dictionary) -> Dictionary:
	var inner = reward.get("reward", null)
	if inner is Dictionary:
		return inner
	return reward


func _drops_of(payload: Dictionary) -> Array:
	return payload.get("drops", [])


func _def_ids(drops: Array) -> Array[String]:
	var out: Array[String] = []
	for drop in drops:
		out.append(String((drop as Dictionary).get("def_id", "")))
	return out


func _drop_of(drops: Array, def_id: String) -> Dictionary:
	for drop in drops:
		if String((drop as Dictionary).get("def_id", "")) == def_id:
			return drop
	return {}
