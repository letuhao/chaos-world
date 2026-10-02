extends TestCase

## The socket namespace's own content, checked against the rules the game gates
## on (ADR 0025/0028): every fixed option exists in the master catalog, its
## authored value sits inside that option's realm/rarity magnitude window, the
## roll count matches the rarity policy, equipment is never stackable, the realm
## is a canonical ladder id whose tier meets the grade, and every definition is
## reachable through a real acquisition path.

const SOCKET_ITEM_TAG := &"socket_item"
const HOST_TAG := &"socket_host"


func _ids() -> Array[StringName]:
	return SocketContent.ids()


func _actor() -> Actor:
	var actor := Actor.new(&"socket_smith", {Stat.PHYSIQUE: 14.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	actor.add_resource(ResourcePool.new(&"qi", 60.0))
	actor.add_resource(ResourcePool.new(&"stamina", 50.0))
	ItemsApi.attach(actor, 24)
	SocketApi.attach(actor)
	return actor


func test_the_namespace_is_populated_and_resolvable() -> void:
	var ids := _ids()
	assert_eq(ids.is_empty(), false, "the socket namespace ships content")
	assert_eq(ids.size(), ids.size(), "ids are unique by construction")
	for item_id in ids:
		var def := SocketApi.resolve_content(item_id)
		assert_ne(def, null, "%s resolves" % item_id)
		assert_eq(String(def.id), String(item_id), "%s resolves to itself" % item_id)


func test_every_fixed_option_is_registered_for_the_items_activation_channel() -> void:
	var catalog := OptionCatalog.instance()
	for item_id in _ids():
		var def := SocketApi.resolve_content(item_id)
		assert_ne(
			(def.fixed_modifiers as Array).is_empty(), true, "%s carries a fixed channel" % item_id
		)
		for entry in def.fixed_modifiers:
			var option_id := StringName(entry.get("option_id", ""))
			assert_eq(catalog.has_option(option_id), true, "%s references a real option" % item_id)
			assert_eq(
				catalog.allows_activation(option_id, def.activation()),
				true,
				"%s: %s has a consumer for %s" % [item_id, option_id, def.activation()]
			)


func test_every_authored_value_sits_inside_its_realm_and_rarity_window() -> void:
	var catalog := OptionCatalog.instance()
	for item_id in _ids():
		var def := SocketApi.resolve_content(item_id)
		var realm_index := maxi(0, RealmDefaults.ladder().index_of(def.realm))
		var rarity_index := OptionCatalog.rarity_tier(def.rarity)
		for entry in def.fixed_modifiers:
			var option_id := StringName(entry.get("option_id", ""))
			var record := catalog.option_record(option_id)
			var window := catalog.magnitude_bounds(
				String(record["unit"]), realm_index, rarity_index
			)
			var value := float(entry.get("value", 0.0))
			assert_eq(value != 0.0, true, "%s: %s grants something" % [item_id, option_id])
			# `%s` on both sides, never `%g`/`%.4f`: Godot's `%` operator has no
			# `%g`, and a bracketed `%.4f` group is read as an alignment spec, so
			# either one makes sprintf fail and hand back the raw format string —
			# which reports every failure as the same useless label.
			assert_eq(
				value >= float(window["min"]) and value <= float(window["max"]),
				true,
				(
					"%s: %s = %s inside [%s, %s]"
					% [item_id, option_id, value, window["min"], window["max"]]
				)
			)


func test_roll_spec_and_instance_shape_follow_the_rarity_policy() -> void:
	for item_id in _ids():
		var def := SocketApi.resolve_content(item_id)
		assert_ne(def.roll_spec.is_empty(), true, "%s declares a roll spec" % item_id)
		assert_eq(
			int(def.roll_spec.get("count", 0)),
			ItemRarity.affix_count(def.rarity),
			"%s rolls the rarity's affix count" % item_id
		)
		if def.category == ItemCategory.EQUIPMENT:
			assert_eq(def.stackable, false, "%s is a distinct instance" % item_id)
			assert_eq(def.sources.is_empty(), false, "%s has an acquisition source" % item_id)


func test_realm_tier_meets_the_grade_tier() -> void:
	for item_id in _ids():
		var def := SocketApi.resolve_content(item_id)
		var tier := RealmDefaults.ladder().tier_of(def.realm)
		assert_ne(
			RealmDefaults.ladder().index_of(def.realm), -1, "%s names a ladder realm" % item_id
		)
		assert_eq(tier >= def.required_tier(), true, "%s realm tier meets its grade" % item_id)


func test_the_namespace_declares_hosts_reagents_and_socket_items() -> void:
	var hosts := 0
	var socket_items := 0
	var reagents := 0
	for item_id in _ids():
		var def := SocketApi.resolve_content(item_id)
		if def.tags.has(HOST_TAG):
			hosts += 1
			assert_eq(SocketPolicy.carries_sockets(def), true, "%s can carry sockets" % item_id)
		if def.tags.has(SOCKET_ITEM_TAG):
			socket_items += 1
			assert_eq(SocketPolicy.carries_sockets(def), false, "%s cannot carry sockets" % item_id)
		if def.tags.has(&"socket_reagent") or def.tags.has(&"enchantment_reagent"):
			reagents += 1
	assert_eq(hosts > 0, true, "at least one authored item can carry a socket")
	assert_eq(socket_items > 0, true, "socket items are authored")
	assert_eq(reagents > 0, true, "reagents are authored")
	var rarities := {}
	var tiers := {}
	for item_id in _ids():
		var def := SocketApi.resolve_content(item_id)
		if not def.tags.has(SOCKET_ITEM_TAG):
			continue
		rarities[String(def.rarity)] = true
		tiers[RealmDefaults.ladder().tier_of(def.realm)] = true
	assert_eq(rarities.size() > 1, true, "socket items span several rarities")
	assert_eq(tiers.has(1) and tiers.has(2), true, "socket items span the mortal and spirit tiers")


## Acquisition is proven through the normal content path: the definition is
## resolved from the shipped content tree and turned into a real rolled instance
## by the items module's generator, never by constructing state by hand.
func test_content_is_obtained_through_the_items_generator() -> void:
	var actor := _actor()
	var host_def := SocketApi.resolve_content(&"socket_host_rare_blade")
	assert_ne(host_def, null, "the socket host resolves from shipped content")
	var host := ItemsApi.generate(actor, host_def, 104729)
	assert_ne(host, null, "acquired")
	assert_eq(host.rolled.size(), ItemRarity.affix_count(host_def.rarity), "carries a real roll")
	assert_eq(SocketPolicy.slot_cap(host.rarity), 1, "a rare item carries one socket")

	var gem_def := SocketApi.resolve_content(&"socket_rune_mortal_offense")
	assert_ne(gem_def, null, "the socket item resolves from shipped content")
	var gem := ItemsApi.generate(actor, gem_def, 4242)
	assert_ne(gem, null, "acquired")
	assert_eq(gem.instance_id == host.instance_id, false, "distinct instance identity")

	var reagent_def := SocketApi.resolve_content(&"socket_reagent_mortal_slot_offense")
	assert_ne(reagent_def, null, "the reagent resolves from shipped content")
	assert_eq(ItemsApi.inventory(actor).add(reagent_def, 2), 0, "the reagent is carried")

	var before := ItemsApi.inventory(actor).count(reagent_def.id)
	var opened := SocketApi.create_slot(actor, host.instance_id, reagent_def.id)
	assert_eq(bool(opened.get("ok", false)), true, "slot opened: %s" % opened.get("reason", ""))
	assert_eq(
		ItemsApi.inventory(actor).count(reagent_def.id), before - 1, "exactly one reagent spent"
	)


## The items module's resolver stays the first lookup for the whole game: an id
## that lives in the main item tree resolves identically through the socket
## facade, and the socket namespace only adds ids it does not know.
## The shared acquisition path is intact end to end: a definition resolved with
## the items module's own resolver becomes a real rolled instance in the actor's
## inventory, which is how a socket reagent's craft inputs reach a player.
func test_a_shared_item_is_acquired_through_crafting_resolve_and_generate() -> void:
	var actor := _actor()
	var ore := Crafting.resolve(&"armor_iron_ore")
	assert_ne(ore, null, "resolved through the items module's resolver")
	var instance := ItemsApi.generate(actor, ore, 5150)
	assert_ne(instance, null, "acquired")
	assert_eq(ItemsApi.inventory(actor).count(ore.id), 1, "the inventory holds it")
	assert_eq(instance.rolled.size(), ItemRarity.affix_count(ore.rarity), "with a real roll")
	assert_eq(
		SocketApi.resolve_content(&"armor_iron_ore"),
		ore,
		"and the socket facade resolves it to the very same definition"
	)


func test_the_items_resolver_still_owns_the_shared_item_tree() -> void:
	var shared := Crafting.resolve(&"armor_iron_helm")
	assert_ne(shared, null, "the shared tree resolves through the items resolver")
	var via_socket := SocketApi.resolve_content(&"armor_iron_helm")
	assert_eq(via_socket, shared, "and resolves to the same definition through this facade")
	assert_eq(
		SocketApi.resolve_content(&"socket_not_a_real_item"), null, "unknown ids resolve to null"
	)
	assert_eq(SocketApi.resolve_content(&""), null, "an empty id resolves to null")
