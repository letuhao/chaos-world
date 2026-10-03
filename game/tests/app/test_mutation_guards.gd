extends TestCase

## Guards whose only job is to make one specific, deliberate mutation go red.
##
## A test that cannot fail proves nothing, so each of these was verified by breaking
## the implementation and watching this file fail. The mutation log — including the
## mutations that **survived**, which are the findings — lives in the change
## description of the change that introduced this file; nothing in the repo records
## it, per AGENTS.md.
##
## Everything runs against the mounted app's own actor through `SeamHarness`, so a
## passing guard means the seam holds, not that a module can do it in isolation.

const HELM := "armor_iron_helm"
const BANGLE := "accessory_iron_bangle"
const SCALE_PATH := "res://data/item_options/item_magnitude_scale.json"
const FORGE_SCENE := "res://src/ui/screens/socket_forge.tscn"
## The three things a socket transaction costs, and the item it seats.
const SOCKET_CONTENT: Array[StringName] = [
	&"socket_rune_mortal_offense",
	&"socket_reagent_mortal_slot_offense",
	&"socket_reagent_mortal_imputation",
]


func setup() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


func _boot() -> SeamHarness:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	return harness


# --- MUTATION 1: a rolled value that ignores the seed -----------------------


func test_a_roll_is_reproducible_from_its_seed_and_varies_without_one() -> void:
	# Kills: `ItemsApi.generate` seeding the rng with a constant, or
	# `OptionCatalog.roll_value` ignoring `rng.randf()`. A roll that is the same
	# whatever the seed is not a roll, and a player who rerolls would get the same
	# item forever.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := harness.actor
	var def := Crafting.resolve(StringName(HELM))
	assert_ne(def, null, "the helm definition resolves")

	var first := ItemsApi.generate(actor, def, 4242)
	var again := ItemsApi.generate(actor, def, 4242)
	assert_ne(first, null, "a seeded realization is acquired")
	assert_ne(again, null, "and so is a second one at the same seed")
	assert_eq(
		first.stacking_signature(),
		again.stacking_signature(),
		"the same seed reproduces the same realization exactly"
	)
	assert_eq(int(first.seed), 4242, "and the instance records the seed it came from")

	var different := 0
	for seed in [7, 999, 31337, 5, 618033]:
		var other := ItemsApi.generate(actor, def, seed)
		assert_ne(other, null, "a realization at seed %d is acquired" % seed)
		if other != null and other.stacking_signature() != first.stacking_signature():
			different += 1
	assert_eq(
		different,
		5,
		"every other seed produced a different realization, so the seed is really read"
	)


func test_pressing_generate_repeatedly_never_returns_the_same_roll_twice() -> void:
	# The same claim one level up, through the control a player presses.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var workbench := harness.workbench
	var helm_row := harness.row_of_def(workbench, HELM)
	assert_ne(helm_row, -1, "the iron helm is a selectable row")
	assert_eq(harness.pick_row(workbench, helm_row), true, "the helm row is picked")
	var seen: Dictionary = {}
	for key in _row_keys(workbench):
		seen[String(key)] = true
	var rows_at_start := seen.size()
	for press in 4:
		assert_eq(
			harness.press(workbench, "%GenerateButton"),
			true,
			"Generate is live on press %d" % press
		)
		for key in _row_keys(workbench):
			seen[String(key)] = true
	# A DELTA, measured here rather than asserted as a total: pinning the total
	# re-declares how many rows the shell ships, which every other grant path can
	# change. What this test actually claims is that four presses add four NEW
	# rolls, and only the before/after difference says that (INC-0002's shape:
	# snapshot the bound before the loop, or the body grows what the loop tests).
	assert_eq(
		seen.size() - rows_at_start, 4, "four presses added four distinct realizations, one each"
	)


# --- MUTATION 2: deserialize that appends instead of replacing --------------


func test_loading_replaces_item_state_and_never_duplicates_it() -> void:
	# Kills: dropping the `inv.clear()` / unequip-everything preamble in
	# `ItemsApi.deserialize`, so a load appends the saved items to the ones already
	# carried. This was a real bug; the guard is here so it cannot come back.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var workbench := harness.workbench
	var actor := harness.actor
	var def := Crafting.resolve(StringName(HELM))
	assert_ne(def, null, "the helm definition resolves")
	assert_ne(ItemsApi.generate(actor, def, 777), null, "an extra helm is acquired")

	var rows_before := int((workbench.summary() as Dictionary)["row_count"])
	assert_eq(
		rows_before > 0,
		true,
		"the app carries the starter kit, and acquiring the helm added a row to it"
	)

	# Round-trip the payload three times in memory, exactly as the workbench's Load
	# control does.
	#
	# Only the *instance* rows are asserted to survive verbatim. `ItemsApi.deserialize`
	# restores a stack through `Inventory.add()`, which mints a fresh realization
	# rather than replaying the saved one, so a stack's row key legitimately differs
	# after a load. That is a real fidelity gap in stack persistence — reported
	# separately — and asserting it here would mean asserting the bug.
	var payload := ItemsApi.serialize(actor)
	assert_eq(
		int(payload["version"]),
		ItemsApi.SCHEMA_VERSION,
		"the payload is versioned by the items module's own schema"
	)
	var instances_before := _instance_keys(workbench)
	for round in 3:
		ItemsApi.deserialize(actor, payload)
		assert_eq(
			int((workbench.summary() as Dictionary)["row_count"]),
			rows_before,
			"deserialize round %d replaced the item state instead of appending" % round
		)
		assert_eq(
			_instance_keys(workbench),
			instances_before,
			"and every instance is still the same realization, not a second copy"
		)
	assert_eq(
		ItemsApi.equipment(actor).equipped(&"armor"), null, "an empty slot is not filled by a load"
	)


func test_loading_a_save_that_equips_an_item_applies_its_stats_once() -> void:
	# The append mutation's other half: an item restored twice applies its modifiers
	# twice. The effective stat is the observable, not the row count.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := harness.actor
	var def := Crafting.resolve(StringName(HELM))
	assert_ne(def, null, "the helm definition resolves")
	assert_eq(ItemsApi.equip_item(actor, &"armor", def), true, "the helm is equipped")
	var equipped_once := actor.stats.derived(Stat.DEFENSE_PHYSICAL)
	var payload := ItemsApi.serialize(actor)
	for round in 3:
		ItemsApi.deserialize(actor, payload)
		assert_almost_eq(
			actor.stats.derived(Stat.DEFENSE_PHYSICAL),
			equipped_once,
			"load round %d applied the equipped item's defense exactly once" % round
		)


# --- MUTATION 3: a socket contribution that applies twice -------------------


func test_a_socket_contribution_reaches_a_worn_host_exactly_once() -> void:
	# Kills: removing the `remove_modifiers_from(source)` preamble in
	# `SocketEffects.apply`, so re-applying a host's contribution accumulates instead
	# of replacing it. `add_modifier` appends, so a second apply is a second entry
	# with the same source and `modifier_count()` is the cheapest witness.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := harness.actor
	# The forge's own default host is `accessory_iron_bangle`, grade `earth`, which
	# needs realm tier 2. The starter hero is tier 1, so it can never be worn and a
	# socket contribution would never reach the actor at all. The body path is raised
	# to the ladder's second realm here so the host can be worn at all; that the
	# starter save cannot wear its own forge host is a finding, not a test artefact.
	_raise_realm_tier(actor)
	var forge := _socket_up(harness)
	assert_ne(forge, null, "the mounted forge accepted every socket transaction")
	if forge == null:
		return

	var unworn := actor.stats.modifier_count()
	var worn_result := _wear_the_shown_host(actor, forge)
	assert_eq(worn_result["ok"], true, "the socket host is worn (%s)" % worn_result["reason"])
	harness.app.call("refresh_socket_screen")
	var worn := actor.stats.modifier_count()
	assert_eq(
		worn > unworn,
		true,
		"wearing the socket host adds its contribution, so the contribution is real"
	)
	var baseline := actor.stats.derived_all()

	# Extract and re-seat the socket item. Each transaction re-syncs every worn host,
	# which is exactly the path a doubled apply would compound along.
	for cycle in 4:
		assert_eq(
			harness.action(forge, &"extract_socket"), true, "extract is live, cycle %d" % cycle
		)
		harness.app.call("refresh_socket_screen")
		assert_eq(harness.action(forge, &"insert_socket"), true, "insert is live, cycle %d" % cycle)
		harness.app.call("refresh_socket_screen")
		assert_eq(
			actor.stats.modifier_count(),
			worn,
			"extract/insert cycle %d left the modifier count exactly where it was" % cycle
		)
		assert_eq(
			actor.stats.derived_all(),
			baseline,
			"and moved no derived stat, so the contribution applied once, not twice"
		)


func test_unequipping_a_socket_host_takes_its_contribution_with_it() -> void:
	# The other direction: a contribution that is never removed is the same bug seen
	# from the other side, and a stat that merely looks plausible hides it.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := harness.actor
	_raise_realm_tier(actor)
	var forge := _socket_up(harness)
	if forge == null:
		return
	var worn := actor.stats.modifier_count()
	var worn_result := _wear_the_shown_host(actor, forge)
	assert_eq(worn_result["ok"], true, "the socket host is worn (%s)" % worn_result["reason"])
	var host_id := String((forge.summary() as Dictionary)["host_instance_id"])
	assert_ne(host_id, "", "the forge names its host")
	assert_eq(_socket_modifier_count(actor, host_id) > 0, true, "the host owns a socket source")
	assert_eq(
		ItemsApi.equipment(actor).equipped(&"accessory_a") != null, true, "the slot is filled"
	)

	assert_eq(ItemsApi.unequip_to_inventory(actor, &"accessory_a"), true, "the host is removed")
	assert_eq(
		_socket_modifier_count(actor, host_id),
		0,
		"unwearing the host removed its socket source entirely"
	)
	# A socket contribution that survives the item it rides on is the same bug seen
	# from the other side, so the whole stack must not have grown either.
	assert_eq(
		actor.stats.modifier_count() <= worn,
		true,
		"and the actor's modifier stack did not grow, so nothing was left behind"
	)


## Seat a socket on whatever host the mounted forge is already showing, by pressing
## its own action buttons. Returns the forge, or null when a transaction was refused.
func _socket_up(harness: SeamHarness) -> Control:
	var actor := harness.actor
	# Reach the forge the way a player does, so every assertion below is about the
	# screen the app bound and the stack is showing.
	var moved := harness.navigate(SeamHarness.route_for_scene(FORGE_SCENE))
	assert_eq(moved["ok"], true, "the forge route opens: %s" % moved["note"])
	if not bool(moved["ok"]):
		return null
	var forge := harness.live_screen()
	for item_id in SOCKET_CONTENT:
		var def := SocketApi.resolve_content(item_id)
		assert_ne(def, null, "%s resolves through the socket facade" % item_id)
		if def == null:
			return null
		assert_ne(
			ItemsApi.generate(actor, def, 3300 + absi(int(item_id.hash())) % 71),
			null,
			"%s was acquired through ItemsApi.generate" % item_id
		)
	harness.app.call("refresh_socket_screen")
	for action_id in [&"create_slot", &"impute_slot", &"insert_socket"]:
		if not harness.action(forge, action_id):
			return null
		harness.app.call("refresh_socket_screen")
	return forge


## Wear the host the forge is actually showing, and say why when it cannot be worn.
## The forge picks its host from what the actor owns, so equipping a hard-coded
## starter item would leave the counted source on something the player never put on
## and the count would be zero for a reason unrelated to the claim under test.
func _wear_the_shown_host(actor: Actor, forge: Node) -> Dictionary:
	var view := forge.call(&"summary") as Dictionary
	var host_def_id := StringName(String(view.get("host_def_id", "")))
	if host_def_id.is_empty():
		return {"ok": false, "reason": "the forge names no host"}
	var def := SocketApi.resolve_content(host_def_id)
	if def == null:
		def = Crafting.resolve(host_def_id)
	if def == null:
		return {"ok": false, "reason": "'%s' resolves through no facade" % host_def_id}
	for slot in [&"accessory_a", &"weapon", &"armor", &"accessory_b", &"artifact"]:
		if ItemsApi.equipment(actor).definition(slot) != null:
			continue
		if ItemsApi.equip_item(actor, slot, def):
			return {"ok": true, "reason": ""}
		return {
			"ok": false,
			"reason":
			(
				"grade '%s' needs realm tier %d and the hero is '%s' at tier %d"
				% [
					def.grade,
					def.required_tier(),
					actor.realm(),
					RealmDefaults.ladder().tier_of(actor.realm())
				]
			),
		}
	return {"ok": false, "reason": "every equipment slot is already filled"}


## Move the hero's body path to the ladder's second realm, which is the smallest tier
## that clears the `earth` grade gate. Only the tier is asserted, never the id, so
## inserting a realm into the ladder does not silently retune this.
func _raise_realm_tier(actor: Actor) -> void:
	var ladder := RealmDefaults.ladder()
	# Selected by TIER, not by position: the ladder's order is authored data and a
	# retier must not silently turn this into a no-op.
	var target := &""
	for realm in ladder.realms():
		if int((realm as RealmDef).tier) >= 2:
			target = (realm as RealmDef).id
			break
	if target == &"":
		return
	actor.set_path(PathState.new(PathState.BODY, target))
	assert_eq(actor.realm(), target, "the hero's realm is at tier 2")


## Modifiers owned by one host's socket source. Counted through the actor's own
## modifier stack, because a doubled apply is a second entry with the same source.
func _socket_modifier_count(actor: Actor, host_id: String) -> int:
	var source := StringName("socket:%s" % host_id)
	var count := 0
	for property in actor.stats.get_property_list():
		if (int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if String(property.name) != "_modifiers":
			continue
		for entry in actor.stats.get("_modifiers") as Array:
			if entry is StatModifier and (entry as StatModifier).source == source:
				count += 1
	return count


# --- MUTATION 4: an inventory-full pickup that discards the reward ----------


func test_a_pickup_into_a_full_inventory_keeps_the_drop_retrievable() -> void:
	# Kills: `LootState.pickup`/`pickup_all` spending the claim (or dropping the drop)
	# when the inventory is full, instead of overflowing to the world drop container.
	# Driven through the facade the mounted loot screen's bridge is built from, so
	# this is the same program the player reaches through the route.
	var actor := Actor.new(&"stuffed", {Stat.PHYSIQUE: 10.0})
	actor.attach_core_resources()
	# A one-slot inventory, filled with a single stackable that no drop can merge
	# with. Every drop then meets a full inventory, and the assertion does not depend
	# on how many drops a given boss authored. `Inventory` clamps its capacity to 1,
	# so a one-slot bag is the tightest inventory the module allows.
	ItemsApi.attach(actor, 1)
	var filler := Crafting.resolve(&"armor_iron_ore")
	assert_ne(filler, null, "the filler item resolves through the items resolver")
	if filler != null:
		ItemsApi.inventory(actor).add(filler, 1)
	assert_eq(ItemsApi.inventory(actor).is_full(), true, "the bag is full before any pickup")
	LootApi.attach(actor)
	var domain := _open_domain()
	assert_ne(domain, "", "an ungated authored domain exists")
	if domain.is_empty():
		return

	var entered := LootApi.enter_domain(actor, domain, _first_tier(domain), 11)
	assert_eq(
		bool(entered["ok"]),
		true,
		"the domain is entered (refused: %s)" % String(entered.get("reason", "?"))
	)
	if not bool(entered["ok"]):
		return
	var active := LootApi.summary(actor)["active"] as Dictionary
	assert_eq(bool(active["in_domain"]), true, "a boss is live")
	assert_eq(float(active["vitality_max"]) > 0.0, true, "and it has authored vitality")

	# Strike until the boss reports itself defeated. `in_domain` stays true after a
	# defeat — the player has not left the domain yet — so defeat is the flag to read.
	var defeat := LootApi.strike(actor, float(active["vitality_max"]) + 1.0, 12)
	assert_eq(
		String(defeat.get("reason", "")),
		"defeated",
		"one strike past its authored vitality defeats the boss"
	)
	var summary := LootApi.summary(actor)
	assert_eq(int(summary["pending_drops"]) > 0, true, "the defeated boss left drops to claim")
	var rewards: Array = summary["rewards"]
	assert_eq(rewards.is_empty(), false, "a reward is owed")
	if rewards.is_empty():
		return
	var listed := rewards[0] as Dictionary
	var drops: Array = listed["drops"]
	assert_eq(drops.is_empty(), false, "the reward lists at least one drop")
	if drops.is_empty():
		return
	var encounter := String(listed["encounter_id"])

	var owed := int(summary["pending_drops"])
	var taken := LootApi.pickup_all(actor, encounter)
	var claimed := int(taken["claimed"])
	var overflowed := int(taken["overflowed"])
	assert_eq(int(taken["refused"]), 0, "no pickup was refused outright")
	assert_eq(
		claimed + overflowed,
		owed,
		"every drop either fitted or overflowed, and none was thrown away"
	)
	assert_eq(claimed, 0, "a full inventory fitted nothing, so no claim was spent")
	assert_eq(
		overflowed, owed, "every drop overflowed to the world container instead of being discarded"
	)

	var after := LootApi.summary(actor)
	# A pickup that discarded its reward would lose the drop: no claim, nothing stashed.
	# `pending_drops` counts only what is neither claimed nor stashed, so the invariant
	# is that owed is fully accounted for by what is still pending plus what moved into
	# the world container.
	assert_eq(
		int(after["pending_drops"]) + int(after["world_drop_count"]),
		owed,
		"every drop the boss left is either still claimable or stashed for reclaim"
	)
	assert_eq(int(after["claimed_encounters"]), 0, "and no claim was spent")
	var stashed: Array = after["world_drops"]
	assert_eq(stashed.size() >= overflowed, true, "every overflowed drop reached the container")
	assert_eq(
		int(after["world_drop_count"]),
		stashed.size(),
		"and the container is reported so the player can find them"
	)
	# Each stashed drop must still name its reward, or it is unreachable.
	for stash in stashed:
		var entry := stash as Dictionary
		assert_ne(String(entry.get("encounter_id", "")), "", "a stashed drop names its reward")
		assert_ne(String(entry.get("stash_id", "")), "", "a stashed drop names itself")
		assert_eq(
			bool(entry.get("claimable", true)),
			false,
			"a stashed drop is reclaimable, not claimable in place"
		)

	# Reclaim is what makes an overflow recoverable rather than lost.
	ItemsApi.attach(actor, 16)
	var reclaimed := LootApi.reclaim(actor, String((stashed[0] as Dictionary)["stash_id"]))
	assert_eq(
		bool(reclaimed["ok"]),
		true,
		"the drop can be reclaimed (refused: %s)" % String(reclaimed.get("reason", "?"))
	)
	assert_eq(
		int(LootApi.summary(actor)["world_drop_count"]),
		stashed.size() - 1,
		"and it left the container when it did"
	)


# --- MUTATION 5: a corrupted realm entry in the item magnitude scale --------


func test_every_realm_on_the_ladder_has_a_usable_authored_magnitude_scale() -> void:
	# Kills: a deleted, zero, negative, non-finite or unreadable entry in
	# `data/item_options/item_magnitude_scale.json`. `OptionCatalog` answers a missing
	# entry with `push_error` and falls back to 1.0, and `push_error` does not fail
	# this gate — so a corrupted realm would otherwise degrade silently.
	var authored := _authored_scales()
	assert_eq(authored.is_empty(), false, "the scale file declares realms")
	var ladder := RealmDefaults.ladder().realms()
	assert_eq(ladder.size(), 30, "the canonical ladder is thirty realms")
	for realm in ladder:
		var realm_id := String((realm as RealmDef).id)
		assert_eq(
			authored.has(realm_id), true, "realm '%s' has no authored magnitude scale" % realm_id
		)
		if not authored.has(realm_id):
			continue
		var value := float(authored[realm_id])
		assert_eq(is_finite(value), true, "realm '%s' magnitude is finite" % realm_id)
		assert_eq(value > 0.0, true, "realm '%s' magnitude is positive" % realm_id)
		assert_eq(
			value <= 10.0,
			true,
			"realm '%s' magnitude %f is readable, not a typo" % [realm_id, value]
		)


func test_the_runtime_scale_table_is_the_authored_file() -> void:
	# The assertion that turns the silent 1.0 fallback into a failure: what the
	# catalog actually holds must be the file, keyed by realm id, for every realm on
	# the ladder. Deliberately read through the catalog's own cache rather than
	# through `realm_magnitude_scale`/`magnitude_bounds`, whose signatures are
	# mid-refactor - the claim here is about the data, not the accessor.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var authored := _authored_scales()
	var ladder := RealmDefaults.ladder().realms()
	# A facade call is the stable way to make the catalog read the file at all.
	_reset_option_catalog_scales()
	ItemsApi.generate(harness.actor, Crafting.resolve(StringName(HELM)), 1)
	var cached: Dictionary = OptionCatalog._scales
	assert_eq(
		cached.size(), authored.size(), "the runtime scale table holds exactly the authored entries"
	)
	for realm in ladder:
		var realm_id := String((realm as RealmDef).id)
		assert_eq(
			cached.has(realm_id),
			true,
			"the runtime has a scale for realm '%s' rather than falling back to 1.0" % realm_id
		)
		if cached.has(realm_id) and authored.has(realm_id):
			assert_almost_eq(
				float(cached[realm_id]),
				float(authored[realm_id]),
				"the runtime value for realm '%s' is the authored one" % realm_id
			)


func test_a_rolled_value_scales_with_its_realm_factor() -> void:
	# The end of the chain: the authored factor has to reach observable item values,
	# or the table is decoration. The same definition and seed realized at two realms
	# differ only by the authored factor, so the rolled magnitudes must differ too,
	# in the direction the authored factors say.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var authored := _authored_scales()
	var ladder := RealmDefaults.ladder().realms()
	var def := Crafting.resolve(StringName(HELM))
	assert_ne(def, null, "the helm definition resolves")
	var high := String((ladder[ladder.size() - 1] as RealmDef).id)
	var low := String((ladder[0] as RealmDef).id)
	var high_value := _rolled_value(harness.actor, def, high)
	var low_value := _rolled_value(harness.actor, def, low)
	assert_eq(high_value > 0.0, true, "a value rolled at the ladder's top realm")
	assert_eq(low_value > 0.0, true, "and one at its start")
	assert_eq(
		high_value > low_value,
		true,
		(
			"the realm factor is consumed: realm '%s' (%f) rolls above realm '%s' (%f)"
			% [high, float(authored.get(high, 0.0)), low, float(authored.get(low, 0.0))]
		)
	)


## The magnitude of the first rolled option on `def` realized at `realm_id`, through
## the items facade only. Returns 0.0 when the definition could not be rolled there.
func _rolled_value(actor: Actor, def: ItemDef, realm_id: String) -> float:
	var contextual := def.duplicate() as ItemDef
	contextual.realm = StringName(realm_id)
	var instance := ItemsApi.generate(actor, contextual, 20260903)
	if instance == null or instance.rolled.is_empty():
		return 0.0
	return float((instance.rolled[0] as Dictionary).get("value", 0.0))
	OptionCatalog._scales_loaded = false


# --- Plumbing ---------------------------------------------------------------


## The lowest-tier authored domain with no entry gate, so a fresh actor can enter.
func _open_domain() -> String:
	for entry in LootApi.domains():
		var descriptor := entry as Dictionary
		if int(descriptor.get("key_reach", 0)) == 0:
			return String(descriptor["domain_id"])
	return ""


## The tier a domain's own content declares first, as `enter_domain` spells it. Read
## from the domain list rather than guessed, so a retier does not turn this into an
## `unknown_tier` refusal that looks like a wiring failure.
func _first_tier(domain_id: String) -> int:
	for entry in LootApi.domains():
		if String((entry as Dictionary)["domain_id"]) != domain_id:
			continue
		var tiers: Array = (entry as Dictionary).get("tiers", [])
		if tiers.is_empty():
			return 0
		return int((tiers[0] as Dictionary).get("tier", 0))
	return 0


func _row_keys(node: Node) -> Array:
	var panel := node.get_node_or_null("%InventoryPanel") as InventoryPanel
	if panel == null:
		return []
	return (panel.summary() as Dictionary)["row_keys"]


## The row keys of the inventory's *instances* only. An instance's row key is its
## instance id, so it is stable across a save/load; a stack's key is its realization
## signature, which `deserialize` does not replay. Kept separate so an assertion about
## duplication is never quietly weakened into an assertion about stacks.
func _instance_keys(node: Node) -> Array:
	var panel := node.get_node_or_null("%InventoryPanel") as InventoryPanel
	if panel == null:
		return []
	var summary := panel.summary() as Dictionary
	var kinds: Array = summary["row_keys"]
	var out: Array = []
	for index in (summary["row_keys"] as Array).size():
		if String((summary["row_def_ids"] as Array)[index]) == "":
			continue
		var inventory := ItemsApi.inventory(_actor_of(node))
		if inventory != null and inventory.find_instance(StringName(String(kinds[index]))) != null:
			out.append(String(kinds[index]))
	return out


## The actor an inventory panel is bound to, read from the panel itself so this does
## not need the harness.
func _actor_of(node: Node) -> Actor:
	var panel := node.get_node_or_null("%InventoryPanel")
	return null if panel == null else panel.get("_actor") as Actor


func _authored_scales() -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(SCALE_PATH)) != OK:
		return {}
	return (json.data as Dictionary).get("realms", {})


## `OptionCatalog` caches the scale table in a static, so a mutated file would
## otherwise be invisible to every later suite in the same process. Clearing it is
## what makes the assertion about the file rather than about the cache.
func _reset_option_catalog_scales() -> void:
	OptionCatalog._scales = {}
	OptionCatalog._scales_loaded = false
