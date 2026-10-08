extends TestCase

## Chest reward bundles (BL-0053 / DEF-0023): an authored `ChestDef` opened into the bag
## by `ItemsApi.open_chest`, deterministically from one seed.
##
## The claim under test: a chest pays its guarantees and its weighted draws, the same seed
## always yields the same bundle, and every refusal is NAMED and writes nothing.

const CHEST := &"field_camp_supplies"
const GUARANTEED := &"domain_survival_kit"


func _hero(capacity: int = 24) -> Actor:
	var actor := Actor.new(&"t_chest_hero", {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor, capacity)
	return actor


# --- the authored catalog ---------------------------------------------------


## The shipped chest loads and reports no authoring complaint.
func test_the_authored_chest_loads_with_no_problems() -> void:
	var catalog := ChestCatalog.instance()
	assert_eq(catalog.problems().is_empty(), true, "no problems: %s" % str(catalog.problems()))
	var def := catalog.definition(CHEST)
	assert_ne(def, null, "the chest is defined")
	assert_eq(def.rolls, 2, "it draws two rolls")
	assert_eq(def.guaranteed.size(), 1, "and guarantees one item")


# --- opening ----------------------------------------------------------------


## Opening delivers the guarantee and exactly `rolls` drawn items into the bag.
func test_open_delivers_the_bundle() -> void:
	var actor := _hero()
	var opened := ItemsApi.open_chest(actor, CHEST, 1234)
	assert_eq(bool(opened["ok"]), true, "it opens: %s" % str(opened))
	assert_eq((opened["granted"] as Array).size(), 3, "one guarantee plus two rolls")
	assert_eq((opened["refused"] as Array).is_empty(), true, "nothing refused")
	# The guarantee is always present, and the bag holds everything granted.
	assert_eq((opened["granted"] as Array).has(String(GUARANTEED)), true, "the guarantee landed")
	var inv := ItemsApi.inventory(actor)
	assert_eq(inv.has(GUARANTEED), true, "and it is really in the bag")


## The same chest opened with the same seed yields the same bundle — no reroll.
func test_the_bundle_is_deterministic_in_the_seed() -> void:
	var first := ItemsApi.open_chest(_hero(), CHEST, 99)
	var second := ItemsApi.open_chest(_hero(), CHEST, 99)
	assert_eq(first["granted"], second["granted"], "same seed, same bundle")


## Two different seeds are allowed to differ, and the guarantee is present either way.
func test_a_different_seed_can_draw_differently() -> void:
	var actor := _hero()
	var opened := ItemsApi.open_chest(actor, CHEST, 7)
	assert_eq(
		(opened["granted"] as Array).has(String(GUARANTEED)),
		true,
		"the guarantee is seed-independent"
	)


# --- refusals ---------------------------------------------------------------


## An unknown chest refuses by name and delivers nothing.
func test_an_unknown_chest_refuses() -> void:
	var actor := _hero()
	var opened := ItemsApi.open_chest(actor, &"no_such_chest", 1)
	assert_eq(bool(opened["ok"]), false, "no chest, no open")
	assert_eq(String(opened["reason"]), "unknown_chest", "named refusal")
	assert_eq(ItemsApi.inventory(actor).stacks().is_empty(), true, "and nothing was delivered")


## An actor with no inventory refuses `no_inventory` rather than crashing.
func test_an_actor_with_no_bag_refuses() -> void:
	var bare := Actor.new(&"t_bare", {Stat.PHYSIQUE: 10.0})
	var opened := ItemsApi.open_chest(bare, CHEST, 1)
	assert_eq(bool(opened["ok"]), false, "no bag, no open")
	assert_eq(String(opened["reason"]), "no_inventory", "named refusal")


## A bag too small for the whole bundle refuses the overflow by name and keeps what fit —
## a full bag never aborts the guarantees behind it.
func test_a_full_bag_refuses_the_overflow_by_name() -> void:
	var actor := _hero(1)
	var opened := ItemsApi.open_chest(actor, CHEST, 5)
	assert_eq(bool(opened["ok"]), true, "the open still succeeds")
	assert_eq((opened["refused"] as Array).is_empty(), false, "some rows were refused")
	assert_eq(
		String((opened["refused"] as Array)[0]["reason"]), "inventory_full", "refused by name"
	)
	assert_eq((opened["granted"] as Array).size(), 1, "the guarantee still landed")
