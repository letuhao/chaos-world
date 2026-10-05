extends TestCase

## The route index is gone, so boss and slot are owned by the item definition and
## nothing else. `test_unique_routes.gd` proves the index no longer restates them;
## this file proves the surviving owner is a real one, which is a different and
## stronger claim: that the runtimes which enforce these facts read the definition.
##
## That is the load-bearing half of deleting the duplicates. If `LootRoutes` stopped
## honouring `unique_route:` or `equip` stopped honouring the subtype rule, the
## definition would still declare both facts correctly, every declaration-shaped
## assert would stay green, and the routes would be dead — unique content nothing
## could drop. So neither half is asserted by comparing a value to itself; each is
## asserted by asking the runtime, positively and negatively, because a tag nobody
## refuses is not a route and a slot nobody refuses is not a ruling.
##
## Both halves fail independently and are named separately: the boss is exclusive
## to one boss, and the slot is exhaustive across every wearable slot.


func _unique_ids() -> Array[StringName]:
	return SetCatalog.instance().unique_ids()


func _definition(item_id: StringName) -> ItemDef:
	var def := SetBonusApi.definition(item_id)
	assert_ne(def, null, "definition %s resolves" % item_id)
	return def


## The definition owns the boss because the loot runtime will pay that boss and
## no other. `LootRoutes.permits` returns true for a definition with NO route at
## all, so the negative row is the one that carries the claim: it can only be
## refused if the definition actually declared an exclusive route.
func test_the_loot_runtime_pays_exactly_the_boss_the_definition_names() -> void:
	var checked := 0
	for unique_id in _unique_ids():
		var def := _definition(unique_id)
		var boss_id := StringName(SetBonusApi.drop_route(unique_id)["boss_id"])
		assert_ne(boss_id, &"", "%s: the definition declares a route" % unique_id)
		assert_eq(
			str(LootRoutes.routes(def)),
			str([String(boss_id)]),
			"%s: the loot runtime reads exactly the boss the definition names" % unique_id
		)
		assert_eq(
			bool(LootRoutes.permits(def, boss_id)), true, "%s: and will pay that boss" % unique_id
		)
		assert_eq(
			bool(LootRoutes.permits(def, &"a_boss_that_drops_no_unique_at_all")),
			false,
			"%s: and refuses every other, so the tag is the route and not decoration" % unique_id
		)
		checked += 1
	assert_ne(checked, 0, "uniques were checked against the runtime that enforces them")


## The definition owns the slot, and the proof is that the equip path agrees with
## the definition's own subtype — asked for EVERY slot, positively and negatively.
##
## The deleted `slot` column is why this cannot be a string comparison. That column
## named a SLOT (`accessory_a`) where `subcategory` names a SUBTYPE (`accessory`),
## and it disagreed with the subtype for three of its five rows, so "the route's
## slot equals the item's subtype" is not even the right claim to check. What is
## checkable, and what the old duplication was really asserting, is that a body
## wearing the item does so exactly where the definition's subtype allows and
## nowhere else.
##
## The route payload's `item_subtype` is resolved the same way rather than
## compared to `def.subcategory`: `drop_route` copies that field verbatim, so
## comparing them is `f(x) == f(x)` and passes just as loudly on a payload naming a
## subtype the definition does not wear. Resolving the payload's subtype through
## the real subtype rule and then handing each slot to `equip` cannot be right on
## both counts at once.
func test_the_equip_path_wears_the_item_exactly_where_its_own_subtype_allows() -> void:
	var checked := 0
	for unique_id in _unique_ids():
		var def := _definition(unique_id)
		_sweep_slots(def, SetBonusApi.drop_route(unique_id))
		checked += 1
	assert_ne(checked, 0, "uniques were checked against the runtime that enforces them")


## One body per slot: an equip that succeeds would otherwise leave that slot
## occupied, so the next row would be a replacement rather than the refusal it
## claims to be.
func _sweep_slots(def: ItemDef, route: Dictionary) -> void:
	var ruled: Array = def.wearable_slots()
	assert_ne(ruled.is_empty(), true, "%s: its subtype names a wearable slot" % def.id)
	var declared := StringName(route.get("item_subtype", ""))
	assert_ne(declared, &"", "%s: the route reports the slot its item occupies" % def.id)
	assert_eq(
		ItemSlots.for_subtype(declared),
		ruled,
		"%s: the route's reported subtype rules exactly the definition's slots" % def.id
	)
	for slot in Equipment.SLOTS:
		var body := Actor.new(&"slot_probe", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
		ItemsApi.attach(body, 16)
		ItemsApi.inventory(body).add(def, 1)
		assert_eq(
			ItemsApi.equip_item(body, slot, def),
			ruled.has(slot),
			(
				"%s: is worn in '%s' exactly when its own subtype '%s' allows it"
				% [def.id, slot, String(def.subcategory)]
			)
		)
