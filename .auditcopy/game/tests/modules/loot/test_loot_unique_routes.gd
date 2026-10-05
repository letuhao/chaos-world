extends TestCase

## Every authored unique item is route-locked to a named boss, so a unique that
## no authored encounter carries is *unobtainable*: it exists, it resolves, and
## no player can ever win it. That is the failure this file exists to catch.
##
## The route tables are hand-authored, so the invariant cannot be checked by
## looking at the tables alone — the claim has to be proven at runtime. Each test
## below drives the shipped pipeline through the facade: enter the domain, strike
## the authored vitality pool until it dies, read the minted reward, and look at
## what actually dropped.

var _actor: Actor = null


func setup() -> void:
	_actor = Actor.new(&"unique_route", {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(_actor)
	_actor.attach_core_resources()
	LootApi.attach(_actor)


## Every route-locked unique is paid by at least one authored route. Read from
## the shipped defs and tables rather than a kept list, so authoring a new
## unique without a route fails here instead of failing quietly in play.
func test_every_route_locked_unique_is_paid_by_some_authored_route() -> void:
	var locked := _locked_uniques()
	assert_eq(locked.is_empty(), false, "the content set has route-locked uniques to check")
	for def_id in locked:
		var routes := _routes_carrying(def_id)
		assert_eq(
			routes.is_empty(),
			false,
			"unique '%s' is route-locked but no authored encounter pays it" % def_id
		)


## The pipeline for one route, end to end: the unique only appears after the
## boss dies, and it arrives with its realized rolls rather than as a bare id.
func test_a_route_pays_its_unique_and_the_unique_carries_realized_effects() -> void:
	var def_id: String = _locked_uniques()[0]
	var route: Dictionary = _routes_carrying(def_id)[0]

	var entered := LootApi.enter_domain(_actor, StringName(route["domain_id"]), 1, 7)
	assert_eq(bool(entered.get("ok")), true, "the route is enterable: %s" % entered)
	var active = entered.get("active", {})
	assert_ne(String(active.get("boss_id", "")), "", "a boss is on the other side")

	var drops := _drops_of(_defeat(active))
	var ids := _def_ids(drops)
	assert_eq(ids.has(def_id), true, "route '%s' pays '%s'" % [route["label"], def_id])

	var unique := _drop_of(drops, def_id)
	assert_eq(
		int(unique.get("effect_count", 0)) > 0,
		true,
		"the unique arrives with rolled effects, not a bare def id"
	)
	for effect in unique.get("effects", []):
		assert_ne(
			float((effect as Dictionary).get("value", 0.0)),
			0.0,
			"every effect on the unique has a realized value"
		)


## No authored table may list a unique the table's own boss is not routed for.
##
## This is the invariant that makes the lock mean anything. `LootRoutes.permits`
## is consulted per entry while resolving, so a table listing someone else's
## unique would otherwise be one content edit away from paying it. Asserted over
## every binding in the shipped set rather than kept by hand.
func test_no_authored_table_lists_a_unique_its_boss_is_not_routed_for() -> void:
	var bindings := _all_bindings()
	assert_eq(bindings.is_empty(), false, "the content set has bindings to check")
	for binding in bindings:
		var boss_id := StringName(binding["boss_id"])
		for entry in (binding["table"] as LootTableDef).entries:
			var def_id := String(entry.item_id)
			if not _is_unique(def_id):
				continue
			var def = LootContent.instance().definition(StringName(def_id))
			if def == null:
				continue
			assert_eq(
				bool(LootRoutes.permits(def, boss_id)),
				true,
				(
					"table '%s' lists '%s' but boss '%s' is not routed for it"
					% [binding["table"].id, def_id, boss_id]
				)
			)


## The lock is load-bearing at the seam, not merely declared: the resolver drops
## a unique a table lists when the context's boss is not routed for it.
##
## Drives `LootResolver.resolve` on a real shipped table twice, naming two
## different bosses. If `permits` were removed the second resolve would pay it.
func test_the_resolver_drops_a_unique_the_context_boss_is_not_routed_for() -> void:
	var binding := _first_binding_carrying_a_unique()
	assert_eq(binding.is_empty(), false, "some authored binding carries a unique")
	var table := binding["table"] as LootTableDef
	var def_id := String(_first_unique_entry(table).item_id)
	var routed := LootRoutes.routes(LootContent.instance().definition(StringName(def_id)))
	assert_eq(routed.is_empty(), false, "the unique is route-locked")

	var stranger := _a_boss_outside(def_id, StringName(binding["boss_id"]))
	var matched := _resolve_paid(table, StringName(binding["boss_id"]))
	assert_eq(matched.has(def_id), true, "the routed boss pays the unique its own table lists")

	var refused := _resolve_paid(table, stranger)
	assert_eq(
		refused.has(def_id),
		false,
		"a boss the unique is not routed to pays nothing, even though the table lists it"
	)


## The reward is minted once per kill. Re-reading the same claim token must not
## hand out a second copy, or a route pays its unique twice for one victory.
func test_re_reading_a_settled_claim_token_does_not_mint_a_second_reward() -> void:
	var route: Dictionary = _routes_carrying(_locked_uniques()[0])[0]
	var entered := LootApi.enter_domain(_actor, StringName(route["domain_id"]), 1, 7)
	var active = entered.get("active", {})
	_defeat(active)

	var token := String(active.get("encounter_id", ""))
	var first := _payload(LootApi.reward(_actor, token))
	var second := _payload(LootApi.reward(_actor, token))
	assert_eq(
		_drops_of(second).size(),
		_drops_of(first).size(),
		"re-reading a settled claim token yields the same drops, not a second mint"
	)
	assert_eq(
		int(first.get("drop_count", 0)),
		int(first.get("pending_count", 0)) + int(first.get("claimed_count", 0)),
		"every minted drop is accounted for exactly once"
	)


# --- helpers -------------------------------------------------------------


## Kill the active boss and return the reward payload for the run.
##
## Damage is deliberately oversized. The claim under test is *what a kill pays*,
## not how many swings it took; a hand-rolled damage loop here would only add a
## second thing to be wrong.
func _defeat(active: Dictionary) -> Dictionary:
	var hit := LootApi.strike(_actor, 1.0e9, 100)
	assert_eq(
		String(hit.get("reason", "")),
		"defeated",
		"the authored vitality pool can be emptied by shipping damage"
	)
	return _payload(LootApi.reward(_actor, String(active.get("encounter_id", ""))))


func _payload(reward: Dictionary) -> Dictionary:
	var inner = reward.get("reward", null)
	if inner is Dictionary:
		return inner
	return reward


func _drops_of(payload: Dictionary) -> Array:
	var drops: Array = payload.get("drops", [])
	return drops


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


## Route-locked unique def ids, sorted so failures read in a stable order.
##
## Enumerated from `Crafting.ITEM_ROOTS` — the one list every item resolver reads
## — rather than a kept list, so a unique authored into a new root is still
## checked. The facade has no catalog accessor by design, so the scan is here.
func _locked_uniques() -> Array[String]:
	var out: Array[String] = []
	for def_id in _unique_def_ids():
		var def := LootContent.instance().definition(def_id)
		if def == null:
			continue
		if not LootRoutes.routes(def).is_empty():
			out.append(String(def_id))
	out.sort()
	return out


## Every authored item def id whose file declares a unique. `unique_` is the
## authored naming convention for a unique artifact.
func _unique_def_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for root in Crafting.ITEM_ROOTS:
		_scan_unique_defs(root, out)
	return out


func _scan_unique_defs(root: String, out: Array[StringName]) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				_scan_unique_defs(path, out)
			elif entry.begins_with("unique_") and entry.ends_with(".tres"):
				out.append(StringName(entry.get_basename()))
		entry = dir.get_next()
	dir.list_dir_end()


## Every (encounter, tier, boss, table) binding in the shipped content, as plain
## dictionaries. Read through the same accessors the runtime resolves with, so
## this cannot disagree with the game about what a domain pays.
func _all_bindings() -> Array:
	var content := LootContent.instance()
	var out: Array = []
	for encounter_id in content.encounter_ids():
		var encounter := content.encounter_by_id(StringName(encounter_id))
		if encounter == null:
			continue
		for tier_index in range(1, encounter.tier_count() + 1):
			var tier = encounter.tier_at(tier_index)
			if tier == null:
				continue
			for boss_id in tier.boss_ids():
				var table = content.table(tier.table_for(boss_id))
				if table == null:
					continue
				(
					out
					. append(
						{
							"label": "%s/%s" % [encounter_id, boss_id],
							"domain_id": String(encounter.domain_id),
							"tier": tier_index,
							"boss_id": String(boss_id),
							"table": table,
						}
					)
				)
	return out


func _routes_carrying(def_id: String) -> Array:
	var out: Array = []
	for binding in _all_bindings():
		for entry in (binding["table"] as LootTableDef).entries:
			if String(entry.item_id) == def_id:
				out.append(binding)
				break
	return out


func _routes_without_uniques() -> Array:
	var out: Array = []
	for binding in _all_bindings():
		var carries := false
		for entry in (binding["table"] as LootTableDef).entries:
			if _is_unique(String(entry.item_id)):
				carries = true
				break
		if not carries:
			out.append(binding)
	return out


## Routes carrying at least one unique that is not `def_id`.
func _routes_carrying_a_different_unique(def_id: String) -> Array:
	var out: Array = []
	for binding in _all_bindings():
		for entry in (binding["table"] as LootTableDef).entries:
			var other := String(entry.item_id)
			if _is_unique(other) and other != def_id:
				out.append(binding)
				break
	return out


func _first_binding_carrying_a_unique() -> Dictionary:
	for binding in _all_bindings():
		if _first_unique_entry(binding["table"] as LootTableDef) != null:
			return binding
	return {}


func _first_unique_entry(table: LootTableDef) -> LootEntry:
	for entry in table.entries:
		if _is_unique(String(entry.item_id)):
			return entry
	return null


## A boss id the unique is definitely *not* routed to, so the refusal assertion
## cannot accidentally pass because the stranger happens to be the owner.
func _a_boss_outside(def_id: String, own_boss: StringName) -> StringName:
	var def = LootContent.instance().definition(StringName(def_id))
	for candidate in LootRoutes.routes(def):
		if StringName(candidate) != own_boss:
			return StringName(candidate)
	return &"__no_rival_boss__"


## Resolve `table` naming `boss_id` and return the def ids it plans to pay.
## The seed is fixed so the two resolves differ only by the boss.
func _resolve_paid(table: LootTableDef, boss_id: StringName) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var out := LootResolver.resolve(
		table, LootResolver.make_context(&"nascent_soul", &"legendary", boss_id, {}), rng
	)
	var ids: Array[String] = []
	for plan in out.get("plans", []):
		ids.append(String((plan as Dictionary).get("def_id", "")))
	return ids


func _is_unique(def_id: String) -> bool:
	return def_id.begins_with("unique_")
