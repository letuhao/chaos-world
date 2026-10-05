extends TestCase

## The starter kit, and the seam that lets a destiny path REPLACE it.
##
## The defect this closes is a boot that opens on an EMPTY bag: every item surface
## in the game is routable and implemented, and a new player had no row to select,
## nothing to Generate and nothing to Equip. The grant itself belongs to the
## composition root, so what is proven HERE is the part this module owns — the
## authored default kit is real, wearable and grade-legal, and a registered pack
## DISPLACES it rather than joining it.
##
## ## Why replacement is asserted and not merely assumed
##
## The obvious alternative implementation appends, and an appending registry is
## green on every test that only checks "registration did not crash". So the
## assertions below are all of the form "the default's ids are ABSENT", which is
## the only statement an append cannot satisfy. `test_a_registered_pack_replaces_
## the_default_entirely` is the one to mutate.

const PACKED := &"t_pack_bearer"
const OTHER := &"t_packless"

## The default's four ids, named here so the replacement assertions can ask
## whether a specific row survived rather than comparing two opaque blobs.
const DEFAULT_WEAPON := "weapon_iron_sword"
const DEFAULT_ARMOR := "armor_iron_helm"
const DEFAULT_CONSUMABLE := "alchemy_clarity_pill"
const DEFAULT_TOKEN := "curr_spirit_coin"

## A second kit, disjoint from the default in every id. Disjointness is what makes
## "the default is gone" checkable: if the two kits shared an item, an appending
## implementation and a replacing one would hand back the same ids.
const OTHER_WEAPON := "blade_copper"
const OTHER_ARMOR := "belt_iron_buckle"
const OTHER_CONSUMABLE := "ash_camp_pilgrims_ration"
const OTHER_TOKEN := "armor_iron_ore"


func setup() -> void:
	# Both registries are process-wide, so both are rebuilt per test: the catalog
	# because these tests earn fixture destinies, and the pack registry because a
	# registration left behind would answer a sibling suite's `starter_pack`.
	DestinyStarterPacks.shared = null
	DestinyFixtureCatalog.install(
		[],
		[DestinyFixtureCatalog.plain_destiny(PACKED), DestinyFixtureCatalog.plain_destiny(OTHER)]
	)


func teardown() -> void:
	DestinyStarterPacks.shared = null
	DestinyFixtureCatalog.teardown()


func _hero(actor_id: StringName = &"newborn") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	DestinyApi.attach(actor)
	return actor


## A well-formed kit row set naming four OTHER authored defs.
func _rows(weapon: String, armor: String, consumable: String, token: String) -> Array:
	return [
		{"role": DestinyStarterPack.ROLE_WEAPON, "item_id": weapon, "count": 1},
		{"role": DestinyStarterPack.ROLE_ARMOR, "item_id": armor, "count": 1},
		{"role": DestinyStarterPack.ROLE_CONSUMABLE, "item_id": consumable, "count": 2},
		{"role": DestinyStarterPack.ROLE_TOKEN, "item_id": token, "count": 7},
	]


func _other_rows() -> Array:
	return _rows(OTHER_WEAPON, OTHER_ARMOR, OTHER_CONSUMABLE, OTHER_TOKEN)


func _ids(pack: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for row in pack["entries"] as Array:
		out.append(String((row as Dictionary)["item_id"]))
	return out


func _roles(pack: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for row in pack["entries"] as Array:
		out.append(String((row as Dictionary)["role"]))
	return out


# --- The default kit is real content -----------------------------------------


## Every id in the default resolves to an authored `ItemDef`. The ids are spelled
## as string literals in a module constant, so nothing but a test can catch a
## typo — and a typo here is a boot that hands a player an item id no definition
## answers for, which silently grants nothing.
func test_every_default_item_id_resolves_to_an_authored_definition() -> void:
	var defaults := DestinyStarterPacks.instance().default_pack()
	assert_eq(defaults.item_ids().size(), 4, "the default kit carries one row per authored role")
	for item_id in defaults.item_ids():
		var def := Crafting.resolve(StringName(item_id))
		assert_ne(def, null, "'%s' resolves to a real ItemDef" % item_id)
		assert_eq(String(def.id), item_id, "and it is the def that id names, not a fallback")


## Grade `mortal` on all four, because it is the only grade a starting hero can
## wear. `ItemGrade.TIER_BY_GRADE` puts mortal at tier 1 and every other grade at
## 2 or higher, a starting hero's ladder tier is 1, and
## `Equipment._meets_requirements` refuses anything above it — so a starter item
## one grade up is an item the player is handed and can never equip.
func test_every_default_item_is_grade_mortal_and_therefore_wearable_at_tier_one() -> void:
	for item_id in DestinyStarterPacks.instance().default_pack().item_ids():
		var def := Crafting.resolve(StringName(item_id))
		assert_eq(
			def.grade,
			ItemGrade.MORTAL,
			"'%s' is grade mortal, the only grade a tier-1 hero satisfies" % item_id
		)
		assert_eq(
			ItemGrade.required_tier(def.grade),
			1,
			"and that grade's required tier is the one a starting hero is on"
		)


## The two wearable rows are non-stackable defs in a subtype `ItemSlots` rules
## wearable. Two separate requirements, and both are load-bearing: a stackable
## armor lands as an `ItemStack` the workbench's row builder lists but
## `ItemActionRules.equip_shape_reason` cannot match, because that rule resolves
## through `Inventory.find_instance` and an instance lookup cannot see a stack.
func test_the_wearable_rows_are_wearable_instances_and_not_stacks() -> void:
	var defaults := DestinyStarterPacks.instance().default_pack()
	for role in [DestinyStarterPack.ROLE_WEAPON, DestinyStarterPack.ROLE_ARMOR]:
		var item_id := defaults.item_for_role(role)
		assert_ne(item_id, "", "the default carries a '%s' row" % role)
		var def := Crafting.resolve(StringName(item_id))
		assert_eq(
			def.stackable,
			false,
			"'%s' is non-stackable, so generate() mints an instance a row can equip" % item_id
		)
		assert_eq(
			ItemSlots.is_wearable(def.subcategory),
			true,
			"and its subtype '%s' is wearable, not socket material" % def.subcategory
		)
		assert_ne(
			ItemSlots.for_subtype(def.subcategory),
			[],
			"and the authored slot table names a slot for '%s'" % def.subcategory
		)


## The four roles are the ones a kit is read by, and the default fills all four:
## a weapon, armor, a consumable and a token. Asserted on the published view, so a
## pack that silently lost a row cannot pass by returning a shorter id list.
func test_the_default_kit_is_a_weapon_armor_a_consumable_and_a_token() -> void:
	var view := DestinyApi.starter_pack(_hero())
	assert_eq(
		_roles(view),
		[
			String(DestinyStarterPack.ROLE_WEAPON),
			String(DestinyStarterPack.ROLE_ARMOR),
			String(DestinyStarterPack.ROLE_CONSUMABLE),
			String(DestinyStarterPack.ROLE_TOKEN),
		],
		"the default kit is one of each authored role, in canonical order"
	)
	assert_eq(
		_ids(view),
		[DEFAULT_WEAPON, DEFAULT_ARMOR, DEFAULT_CONSUMABLE, DEFAULT_TOKEN],
		"naming the authored ids a starting hero is handed"
	)


## A body that has earned nothing holds the default, and the read says so rather
## than leaving a consumer to infer it from a matching pack id.
func test_a_hero_who_has_earned_nothing_holds_the_default_pack() -> void:
	var view := DestinyApi.starter_pack(_hero())
	assert_eq(view["replaced"], false, "nothing replaced the default")
	assert_eq(String(view["destiny_id"]), "", "and no destiny is named as the source")
	assert_eq(
		String(view["pack_id"]), String(DestinyStarterPacks.DEFAULT_PACK_ID), "the default answered"
	)


## A null actor is answered, not refused: the composition root builds the hero and
## asks in one breath, and a body that does not exist yet has earned nothing, so
## the default is the honest answer rather than an error.
func test_a_null_actor_is_answered_with_the_default_rather_than_refused() -> void:
	var view := DestinyApi.starter_pack(null)
	assert_eq(view["has_actor"], false, "the read says it had no actor to read a ledger from")
	assert_eq(view["replaced"], false, "so nothing replaced the default")
	assert_eq(_ids(view).size(), 4, "and the default is still described in full")


# --- The replacement seam ----------------------------------------------------


## THE assertion. A registered pack DISPLACES the default: the registered ids are
## present and every default id is GONE.
##
## Both halves are needed. Asserting only that the registered ids are present is
## satisfied by an appending registry — the append adds the new rows and leaves
## the old ones, so the id list grows and every "registration worked" check still
## passes. Asserting only that the default is gone would be satisfied by a
## registry that simply dropped it. The pair is what an append cannot satisfy.
func test_a_registered_pack_replaces_the_default_entirely() -> void:
	var actor := _hero()
	assert_eq(
		DestinyApi.register_starter_pack(PACKED, _other_rows()),
		{"ok": true, "pack_id": String(PACKED)},
		"a destiny path registers its own pack"
	)
	DestinyApi.earn_destiny(actor, PACKED, "story")
	var view := DestinyApi.starter_pack(actor)
	assert_eq(view["replaced"], true, "the registered pack answered")
	assert_eq(String(view["destiny_id"]), String(PACKED), "and it names the destiny that owns it")
	assert_eq(
		_ids(view),
		[OTHER_WEAPON, OTHER_ARMOR, OTHER_CONSUMABLE, OTHER_TOKEN],
		"the registered kit is what the actor begins holding"
	)
	# The replacement claim, stated per row rather than as a length. A length check
	# would pass on an append of four rows to four that removed four, so each
	# default id is asked about by name.
	for gone in [DEFAULT_WEAPON, DEFAULT_ARMOR, DEFAULT_CONSUMABLE, DEFAULT_TOKEN]:
		assert_eq(
			_ids(view).has(gone),
			false,
			"the default's '%s' did not survive alongside the registered pack" % gone
		)
	assert_eq(int(view["entry_count"]), 4, "four rows, not eight: the default was not appended")


## Re-registering the same destiny overwrites. That is what makes the verb safe to
## run on every boot: a pack authored twice is a CORRECTION, not a doubled kit,
## and a merge would turn a fix into a balance change nobody wrote.
func test_registering_the_same_destiny_twice_replaces_rather_than_doubles() -> void:
	var actor := _hero()
	DestinyApi.register_starter_pack(PACKED, _other_rows())
	DestinyApi.earn_destiny(actor, PACKED, "story")
	# A second kit, again disjoint from the first, so "replaced" and "appended"
	# cannot produce the same ids.
	var third := _rows(DEFAULT_WEAPON, DEFAULT_ARMOR, OTHER_CONSUMABLE, OTHER_TOKEN)
	assert_eq(
		DestinyApi.register_starter_pack(PACKED, third)["ok"], true, "the pack is re-registered"
	)
	var view := DestinyApi.starter_pack(actor)
	assert_eq(int(view["entry_count"]), 4, "still four rows after a second registration")
	assert_eq(
		_ids(view),
		[DEFAULT_WEAPON, DEFAULT_ARMOR, OTHER_CONSUMABLE, OTHER_TOKEN],
		"the SECOND registration is what the actor holds"
	)
	for gone in [OTHER_WEAPON, OTHER_ARMOR]:
		assert_eq(_ids(view).has(gone), false, "the superseded '%s' is gone" % gone)


## The replacement is scoped to the destiny that registered it. A sibling destiny
## earns nothing extra, and an actor who never earned either still holds the
## default — otherwise one registration would silently restock every body.
func test_a_registration_reaches_only_the_destiny_that_made_it() -> void:
	var bearer := _hero("bearer")
	var bystander := _hero("bystander")
	DestinyApi.register_starter_pack(PACKED, _other_rows())
	DestinyApi.earn_destiny(bearer, PACKED, "story")
	assert_eq(
		DestinyApi.starter_pack(bearer)["replaced"], true, "the bearer holds the registered pack"
	)
	assert_eq(
		DestinyApi.starter_pack(bystander)["replaced"],
		false,
		"an actor who earned nothing is untouched by the registration"
	)
	assert_eq(
		_ids(DestinyApi.starter_pack(bystander)).has(OTHER_WEAPON), false, "and gets the default"
	)


## Two registered destinies on one body: the winner is decided by the ledger's
## canonical id order, not by the order they were earned in. Two reads of the
## same ledger must not be able to disagree, or a save could change which kit a
## player gets by replaying their history differently.
func test_when_two_destinies_have_packs_the_canonical_order_decides_not_the_earn_order() -> void:
	var actor := _hero()
	DestinyApi.register_starter_pack(PACKED, _other_rows())
	DestinyApi.register_starter_pack(
		OTHER, _rows("blade_iron", "boots_leather", OTHER_CONSUMABLE, OTHER_TOKEN)
	)
	# Earned in the order that puts the canonically-LATER id first.
	DestinyApi.earn_destiny(actor, OTHER, "story")
	DestinyApi.earn_destiny(actor, PACKED, "story")
	assert_eq(
		String(DestinyApi.starter_pack(actor)["destiny_id"]),
		String(PACKED),
		"'%s' sorts before '%s' and wins regardless of earn order" % [PACKED, OTHER]
	)


# --- Refusals ----------------------------------------------------------------


## An unknown destiny id is refused and stored nowhere. A pack filed under a
## destiny the catalog does not ship can never be resolved by any body, because no
## body can ever hold that destiny — so storing it would leave a dead registration
## that reads on the surface exactly like a working one.
func test_a_pack_for_an_unknown_destiny_is_refused_and_stores_nothing() -> void:
	var answer := DestinyApi.register_starter_pack(&"t_no_such_destiny", _other_rows())
	assert_eq(answer["ok"], false, "an id the catalog does not ship is refused")
	assert_eq(
		String(answer["reason"]),
		DestinyStarterPacks.REASON_UNKNOWN_DESTINY,
		"and it says which rule refused it"
	)
	assert_eq(
		DestinyStarterPacks.instance().registered_ids(),
		[],
		"nothing was stored, so the registry is empty"
	)
	assert_eq(
		DestinyApi.starter_pack(_hero())["replaced"],
		false,
		"and a body still holds the default rather than a phantom kit"
	)


## An empty id is refused by its own reason rather than filed under `""`, which
## would collide with every other malformed registration.
func test_an_empty_destiny_id_is_refused() -> void:
	var answer := DestinyApi.register_starter_pack(&"", _other_rows())
	assert_eq(answer["ok"], false, "an empty destiny id is refused")
	assert_eq(String(answer["reason"]), DestinyStarterPacks.REASON_NO_DESTINY, "by name")


## A malformed kit is refused by name rather than stored with a hole in it. A pack
## is boot content, so a row that silently vanished at boot is a player opening an
## empty bag with nothing to select — the exact failure this seam closes.
func test_a_malformed_row_set_is_refused_by_name_and_stores_nothing() -> void:
	var cases := {
		DestinyStarterPack.REASON_BAD_ITEM:
		[{"role": DestinyStarterPack.ROLE_WEAPON, "item_id": "", "count": 1}],
		DestinyStarterPack.REASON_BAD_COUNT:
		[{"role": DestinyStarterPack.ROLE_WEAPON, "item_id": DEFAULT_WEAPON, "count": 0}],
		DestinyStarterPack.REASON_NO_ROWS: [],
	}
	for reason in cases.keys():
		var answer := DestinyApi.register_starter_pack(PACKED, cases[reason] as Array)
		assert_eq(answer["ok"], false, "a kit with '%s' is refused" % reason)
		# `register` reports the pack-level refusal and carries the pack's own
		# reason in `detail`, so the content bug is named rather than collapsed
		# into one opaque "bad pack".
		assert_eq(
			String(answer.get("detail", answer["reason"])),
			String(reason),
			"and the refusal names '%s'" % reason
		)
	assert_eq(
		DestinyStarterPacks.instance().registered_ids(), [], "no malformed registration was stored"
	)


## A role may appear once. Two rows claiming the weapon slot is a kit whose
## identity is already ambiguous, so it is refused instead of resolved by an
## arbitrary pick — which would make the published view depend on row order.
func test_two_rows_claiming_one_role_are_refused() -> void:
	var rows := _other_rows()
	rows.append({"role": DestinyStarterPack.ROLE_WEAPON, "item_id": "blade_iron", "count": 1})
	var answer := DestinyApi.register_starter_pack(PACKED, rows)
	assert_eq(answer["ok"], false, "a duplicated role is refused")
	assert_eq(String(answer.get("detail", "")), DestinyStarterPack.REASON_DUPLICATE_ROLE, "by name")


## A refused registration leaves the PREVIOUS pack in place rather than clearing
## the slot. Overwrite-on-success is what makes re-registration safe to run every
## boot; overwrite-on-attempt would turn one bad row into a player with no kit.
func test_a_refused_re_registration_leaves_the_standing_pack_intact() -> void:
	var actor := _hero()
	DestinyApi.register_starter_pack(PACKED, _other_rows())
	DestinyApi.earn_destiny(actor, PACKED, "story")
	DestinyApi.register_starter_pack(PACKED, [])
	assert_eq(
		_ids(DestinyApi.starter_pack(actor)),
		[OTHER_WEAPON, OTHER_ARMOR, OTHER_CONSUMABLE, OTHER_TOKEN],
		"a malformed second registration did not empty the kit"
	)


# --- The published shape -----------------------------------------------------


## `starter_pack` is a primitives-only read, because it is what a `summary()`-shaped
## caller publishes without re-deriving anything. A `DestinyStarterPack` or an
## `ItemDef` in the payload would make the view unusable to a panel and would drag
## this module's types across a boundary that only speaks primitives.
func test_the_pack_view_is_primitives_only() -> void:
	var actor := _hero()
	DestinyApi.register_starter_pack(PACKED, _other_rows())
	DestinyApi.earn_destiny(actor, PACKED, "story")
	var view := DestinyApi.starter_pack(actor)
	assert_eq(
		_is_primitive_tree(view),
		true,
		"every value in the pack view is a primitive or an Array/Dictionary of them"
	)


func _is_primitive_tree(value) -> bool:
	if value is Array:
		for entry in value as Array:
			if not _is_primitive_tree(entry):
				return false
		return true
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			if not _is_primitive_tree((value as Dictionary)[key]):
				return false
		return true
	return value is bool or value is int or value is float or value is String or value is StringName
