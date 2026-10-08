extends TestCase

## The composition root's starter-kit grant (BL-0904 / BL-0909).
##
## The defect this closes is a boot that opens on an EMPTY bag: nothing granted a
## starter kit, so a real boot's workbench listed no row to select, every action in
## the bar published disabled, and the whole acquire -> roll -> equip loop had no
## starting point. `destiny` already owns the authored pack and its registration
## seam; what did not exist was the call that turns rows into real items, which is
## the composition root's job.
##
## ## What is asserted here that the module's own suite cannot
##
## `test_destiny_starter_pack.gd` proves the pack is real, wearable and grade-legal,
## and that a registration DISPLACES the default inside the registry. What it cannot
## prove is the half that was missing: that the resolved rows reach an actual
## `Inventory` as the right REPRESENTATION. A wearable that landed as a stack would
## be listed by the bag's row builder and refused by `equip_shape_reason` at the same
## time — the exact grey-Equip shape BL-0725 spent ten attempts on — so the instance
## and stack halves are asserted separately, on real defs, through the real grant.

const PACKED := &"t_kit_destiny"

## The default's four authored ids, named so the replacement assertions can ask
## whether a specific row survived rather than comparing two opaque blobs.
const DEFAULT_WEAPON := &"weapon_iron_sword"
const DEFAULT_ARMOR := &"armor_iron_helm"
const DEFAULT_CONSUMABLE := &"alchemy_clarity_pill"
const DEFAULT_TOKEN := &"curr_spirit_coin"

## A second kit, disjoint from the default in every id, so "the default is gone" is
## a statement an appending implementation cannot satisfy.
const OTHER_WEAPON := &"blade_copper"
const OTHER_ARMOR := &"belt_iron_buckle"
const OTHER_CONSUMABLE := &"ash_camp_pilgrims_ration"
const OTHER_TOKEN := &"armor_iron_ore"


func setup() -> void:
	# The pack registry is process-wide, so it is rebuilt per test: a registration
	# left behind would answer a sibling suite's `starter_pack`.
	DestinyStarterPacks.shared = null


func teardown() -> void:
	DestinyStarterPacks.shared = null
	DestinyFixtureCatalog.teardown()


func _hero(actor_id: StringName = &"t_starter") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	ItemsApi.attach(actor)
	DestinyApi.attach(actor)
	return actor


func _rows(
	weapon: StringName, armor: StringName, consumable: StringName, token: StringName
) -> Array:
	return [
		{"role": DestinyStarterPack.ROLE_WEAPON, "item_id": weapon, "count": 1},
		{"role": DestinyStarterPack.ROLE_ARMOR, "item_id": armor, "count": 1},
		{"role": DestinyStarterPack.ROLE_CONSUMABLE, "item_id": consumable, "count": 2},
		{"role": DestinyStarterPack.ROLE_TOKEN, "item_id": token, "count": 7},
	]


# --- The default kit reaches the bag -----------------------------------------


## THE assertion the boot gate was waiting on: a body that has earned nothing opens
## holding all four rows.
func test_a_newborn_body_draws_the_authored_default_kit() -> void:
	var actor := _hero()
	var report := StarterKit.grant(actor)
	assert_eq(bool(report["ok"]), true, "the kit is granted: %s" % str(report))
	assert_eq(
		(report["granted"] as Array).size(),
		4,
		"all four authored rows land rather than being silently skipped"
	)
	var inv := ItemsApi.inventory(actor)
	assert_eq(
		inv.has_instance(DEFAULT_WEAPON),
		true,
		"the sword is minted as an INSTANCE — what the bag row builder lists and equip_shape_reason matches"
	)
	assert_eq(inv.has_instance(DEFAULT_ARMOR), true, "and so is the helm")
	assert_eq(inv.count(DEFAULT_CONSUMABLE), 3, "the consumable lands as a stack of three")
	assert_eq(inv.count(DEFAULT_TOKEN), 25, "and the token as a stack of twenty-five")


## The workbench's first press selects a row, so a kit that landed somewhere the bag
## does not read would leave the gate exactly where it was.
func test_the_drawn_kit_is_visible_to_the_bag_the_workbench_reads() -> void:
	var actor := _hero()
	StarterKit.grant(actor)
	var inv := ItemsApi.inventory(actor)
	assert_eq(inv.used_slots() > 0, true, "the bag the workbench reads is not empty")
	for item_id in [DEFAULT_WEAPON, DEFAULT_ARMOR, DEFAULT_CONSUMABLE, DEFAULT_TOKEN]:
		assert_eq(
			inv.has(item_id as StringName, 1), true, "'%s' is listed in the bag" % String(item_id)
		)


# --- Once, and only once ------------------------------------------------------


## The draw is a monotone world fact, not a field: a restored body funnels through
## the same call and must not be handed a second kit.
func test_a_second_draw_grants_nothing_and_says_so() -> void:
	var actor := _hero()
	StarterKit.grant(actor)
	var slots := ItemsApi.inventory(actor).used_slots()
	var again := StarterKit.grant(actor)
	assert_eq(bool(again["already"]), true, "the second draw reports the kit was already drawn")
	assert_eq((again["granted"] as Array).size(), 0, "and grants nothing")
	assert_eq(ItemsApi.inventory(actor).used_slots(), slots, "the bag did not grow")


## Two bodies draw independently: the fact is per-actor, so a second hero is not
## starved by the first one's draw.
func test_a_second_body_draws_its_own_kit() -> void:
	StarterKit.grant(_hero(&"t_starter_first"))
	var second := _hero(&"t_starter_second")
	var report := StarterKit.grant(second)
	assert_eq(bool(report["already"]), false, "the second body had not drawn yet")
	assert_eq(
		ItemsApi.inventory(second).has_instance(DEFAULT_WEAPON), true, "and it holds its own sword"
	)


# --- A registered pack REPLACES the default, in the bag ----------------------


## THE replacement assertion, carried through to the inventory. Both halves are
## needed: "the registered ids are present" is satisfied by an appending grant, and
## only "every default id is ABSENT" is not.
func test_a_registered_pack_replaces_the_default_in_the_bag() -> void:
	DestinyFixtureCatalog.install([], [DestinyFixtureCatalog.plain_destiny(PACKED)])
	var actor := _hero()
	DestinyApi.earn_destiny(actor, PACKED)
	assert_eq(
		DestinyApi.has_destiny(actor, PACKED),
		true,
		"the fixture destiny is earned, so the body can hold a pack"
	)
	var registered := DestinyApi.register_starter_pack(
		PACKED, _rows(OTHER_WEAPON, OTHER_ARMOR, OTHER_CONSUMABLE, OTHER_TOKEN)
	)
	assert_eq(bool(registered["ok"]), true, "the pack registers: %s" % str(registered))
	var report := StarterKit.grant(actor)
	assert_eq(bool(report["replaced"]), true, "a registered pack answered the draw")
	assert_eq(String(report["destiny_id"]), String(PACKED), "and it names the destiny it came from")
	var inv := ItemsApi.inventory(actor)
	assert_eq(
		inv.has(DEFAULT_WEAPON),
		false,
		"the default's sword is ABSENT — a merged kit would still carry it"
	)
	assert_eq(inv.has(DEFAULT_TOKEN), false, "and so is the default's token, which was 25 coins")
	assert_eq(
		inv.has_instance(OTHER_WEAPON), true, "the registered kit's weapon is what the bag holds"
	)
	assert_eq(inv.count(OTHER_TOKEN), 7, "and its token lands at the authored count")


# --- Refusals are named -------------------------------------------------------


## A pack names ids as strings, and `DestinyStarterPack.make` cannot resolve them —
## it declares no `items` dependency. So a typo survives registration and can only be
## caught here; it is REPORTED rather than skipped, because a player promised a row
## that does not exist would otherwise open on a bag quietly missing it.
func test_a_row_naming_an_item_the_tree_cannot_resolve_is_refused_by_name() -> void:
	DestinyFixtureCatalog.install([], [DestinyFixtureCatalog.plain_destiny(PACKED)])
	var actor := _hero()
	DestinyApi.earn_destiny(actor, PACKED)
	DestinyApi.register_starter_pack(
		PACKED, _rows(&"t_no_such_item_exists", OTHER_ARMOR, OTHER_CONSUMABLE, OTHER_TOKEN)
	)
	var report := StarterKit.grant(actor)
	var refused := report["refused"] as Array
	assert_eq(refused.size(), 1, "exactly the one unresolvable row is refused: %s" % str(report))
	assert_eq(
		String((refused[0] as Dictionary)["reason"]),
		"unknown_item",
		"refused by name, not silently skipped"
	)
	assert_eq(
		ItemsApi.inventory(actor).has_instance(OTHER_ARMOR),
		true,
		"and the rows behind it still land"
	)


## ADR 0083: a body that does not exist is refused by NAME, and nothing is written.
func test_a_null_actor_is_refused_by_name() -> void:
	var report := StarterKit.grant(null)
	assert_eq(bool(report["ok"]), false, "there is no body to grant to")
	assert_eq(String(report["reason"]), "no_actor", "and the refusal says which rule it broke")
	assert_eq((report["granted"] as Array).size(), 0, "with nothing granted")


## The read model a boot probe or a panel tests instead of pixels. `drawn` is the
## once-guard made readable, so "the bag is empty" and "the kit was never drawn" can
## be told apart without opening the bag.
func test_the_summary_reports_whether_the_kit_was_drawn() -> void:
	var actor := _hero()
	assert_eq(bool(StarterKit.summary(actor)["drawn"]), false, "before the draw the read says so")
	StarterKit.grant(actor)
	assert_eq(bool(StarterKit.summary(actor)["drawn"]), true, "and after it, so")
	assert_eq(StarterKit.summary(null), {}, "a null actor answers the empty dictionary")
