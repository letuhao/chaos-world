extends TestCase

## BL-0951 / ADR 0939, S7: the mending contract and its reference avenue.
##
## `FoundationApi.mend` lifts one realm's snapshot toward — never past — `MEND_CAP, and
## the miracle elixir spends through it: the item names the amount, the module owns the
## ceiling. The shipped elixir is the trigger predicate in the cleanse pill's shape: an
## authored consumable carrying the field, so the verb keeps a production caller.

const ELIXIR_PATH := "res://data/items/consumable/miracle_foundation_elixir.tres"


func _hero() -> Actor:
	var actor := Actor.new(&"mend_hero", {})
	ItemsApi.attach(actor)
	return actor


## An in-memory consumable carrying a mend amount, so the mechanism is proven without
## depending on content — the shipped def gets its own trigger test below.
func _def(mend: float) -> ItemDef:
	var def := ItemDef.new()
	def.id = &"probe_mend_elixir"
	def.category = ItemCategory.CONSUMABLE
	def.subcategory = &"pill"
	def.rarity = ItemRarity.COMMON
	def.foundation_mend = mend
	return def


func _stock(actor: Actor, def: ItemDef, count: int = 1) -> void:
	ItemsApi.inventory(actor).add(def, count)


func _snapshotted(actor: Actor, realm_id: StringName, perfection: float) -> void:
	assert_eq(
		bool(FoundationApi.snapshot(actor, realm_id, perfection).get("ok", false)),
		true,
		"snapshot %s at %f" % [String(realm_id), perfection]
	)


# --- the trigger: the shipped elixir carries the field ------------------------


func test_the_shipped_elixir_names_a_mend_amount() -> void:
	var def := load(ELIXIR_PATH) as ItemDef
	assert_ne(def, null, "the miracle elixir exists")
	assert_eq(String(def.subcategory), "pill", "and it is a pill")
	assert_eq(def.foundation_mend > 0.0, true, "and it names a mend amount")
	assert_eq(
		def.sources.has(&"craft:miracle_foundation_elixir_recipe"),
		true,
		"paid for by its authored recipe, the hardest earn in the game"
	)


# --- the contract: bounded lifts, a ceiling, named refusals --------------------


func test_a_mend_lifts_toward_the_cap_and_never_past_it() -> void:
	var actor := _hero()
	_snapshotted(actor, &"qi_refining", 0.0)
	var first := FoundationApi.mend(actor, &"qi_refining", 0.1, "probe")
	assert_eq(bool(first.get("ok", false)), true, "the mend lands")
	assert_almost_eq(float(first.get("after", -1.0)), 0.1, "by the authored step")
	assert_almost_eq(float(first.get("mended", -1.0)), 0.1, "and names what moved")
	var capped := FoundationApi.mend(actor, &"qi_refining", 0.9, "probe")
	assert_eq(bool(capped.get("ok", false)), true, "an overlarge mend still lands")
	assert_almost_eq(
		float(capped.get("after", -1.0)),
		FoundationApi.MEND_CAP,
		"but stops at the cap, never at the amount"
	)


func test_mending_is_capped_below_full() -> void:
	var actor := _hero()
	_snapshotted(actor, &"qi_refining", 0.0)
	var guard := 0
	while guard < 10:
		guard += 1
		FoundationApi.mend(actor, &"qi_refining", 0.1, "probe")
	var record := FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
	assert_almost_eq(
		FoundationRecord.snapshot_for(record, &"qi_refining"),
		FoundationApi.MEND_CAP,
		"six mends still stop at the cap"
	)
	assert_eq(
		FoundationRecord.snapshot_for(record, &"qi_refining") < 1.0, true, "a scar, never erased"
	)


func test_mend_refusals_are_named() -> void:
	var actor := _hero()
	assert_eq(
		String(FoundationApi.mend(null, &"qi_refining", 0.1).get("reason", "")),
		FoundationApi.R_NO_ACTOR,
		"no actor"
	)
	assert_eq(
		String(FoundationApi.mend(actor, &"", 0.1).get("reason", "")),
		FoundationApi.R_EMPTY_REALM,
		"empty realm"
	)
	assert_eq(
		String(FoundationApi.mend(actor, &"qi_refining", 0.0).get("reason", "")),
		FoundationApi.R_BAD_AMOUNT,
		"zero amount"
	)
	assert_eq(
		String(FoundationApi.mend(actor, &"qi_refining", -0.5).get("reason", "")),
		FoundationApi.R_BAD_AMOUNT,
		"negative amount"
	)
	assert_eq(
		String(FoundationApi.mend(actor, &"qi_refining", 0.1).get("reason", "")),
		FoundationApi.R_NO_SNAPSHOT,
		"a realm never left has nothing to mend"
	)
	_snapshotted(actor, &"qi_refining", 0.9)
	assert_eq(
		String(FoundationApi.mend(actor, &"qi_refining", 0.1).get("reason", "")),
		FoundationApi.R_MEND_CAPPED,
		"a snapshot above the cap is already whole"
	)


func test_mend_target_is_the_weakest_scar() -> void:
	var actor := _hero()
	assert_eq(FoundationApi.mend_target(actor), &"", "an empty record names nothing")
	assert_eq(FoundationApi.mend_target(null), &"", "no actor names nothing")
	_snapshotted(actor, &"qi_refining", 0.8)
	_snapshotted(actor, &"foundation", 0.1)
	_snapshotted(actor, &"core_formation", 0.4)
	assert_eq(FoundationApi.mend_target(actor), &"foundation", "the weakest scar first")
	_snapshotted(actor, &"nascent_soul", 0.05)
	assert_eq(FoundationApi.mend_target(actor), &"nascent_soul", "and it tracks the new weakest")


# --- the avenue: the elixir spends through the contract -------------------------


func test_using_the_elixir_mends_through_the_contract() -> void:
	var actor := _hero()
	_snapshotted(actor, &"qi_refining", 0.2)
	_snapshotted(actor, &"foundation", 0.0)
	var def := _def(0.1)
	_stock(actor, def)
	var result := ItemsApi.use_item(actor, def.id)
	assert_eq(bool(result.get("ok", false)), true, "the use lands")
	var mended: Dictionary = result.get("mended", {})
	assert_eq(bool(mended.get("ok", false)), true, "and it names the mend")
	assert_eq(String(mended.get("realm", "")), "foundation", "on the weakest scar")
	assert_almost_eq(float(mended.get("after", -1.0)), 0.1, "lifted by the step")
	assert_eq(ItemsApi.inventory(actor).count(def.id), 0, "and the elixir is spent")


func test_using_the_elixir_with_no_scar_below_the_cap_refuses_and_spends_nothing() -> void:
	var actor := _hero()
	_snapshotted(actor, &"qi_refining", 0.9)
	var def := _def(0.1)
	_stock(actor, def)
	var result := ItemsApi.use_item(actor, def.id)
	assert_eq(bool(result.get("ok", true)), false, "the use refuses")
	assert_eq(String(result.get("reason", "")), ItemUse.REASON_NO_EFFECT, "as having no effect")
	assert_eq(ItemsApi.inventory(actor).count(def.id), 1, "and the elixir is unspent")


func test_the_shipped_elixir_mends_end_to_end() -> void:
	var actor := _hero()
	_snapshotted(actor, &"qi_refining", 0.0)
	var def := load(ELIXIR_PATH) as ItemDef
	assert_ne(def, null, "the shipped def loads")
	_stock(actor, def)
	var result := ItemsApi.use_item(actor, def.id)
	assert_eq(bool(result.get("ok", false)), true, "the shipped elixir spends")
	var record := FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
	assert_almost_eq(
		FoundationRecord.snapshot_for(record, &"qi_refining"),
		0.1,
		"lifting the scar by its authored step"
	)
