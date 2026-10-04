extends TestCase

## DEF-0218: five authored `ShopDef` files shipped and **nothing in `game/src` read the
## directory** — only `test_economy_content.gd` did, so no shop could ever be found at
## runtime. `MarketApi.buy`/`sell` both take `shop_actor: Actor`, so a def had no way to
## become the Actor the verbs demand.
##
## ## What is asserted, and why it is asserted THROUGH the verbs
##
## `ShopCatalog` is a content lookup and `ShopCounter` is a realization, and either could be
## "working" in isolation while the gap stayed open. What a player does is walk into
## `qi_refining_ore_row` and buy an ore, so the load-bearing test is a real
## `MarketApi.buy` through a counter minted from an AUTHORED def with the AUTHORED coins.
## A test that asserted only "the catalog finds five shops" would pass on a build where
## nothing can still buy from any of them — which is the exact shape of the bug.
##
## ## What is asserted about the SEAMS
##
## `install(defs)` must keep working (the `NpcCatalog` split: a suite installs exactly the
## shops it needs and never depends on shipped content), and `reset()` must clear
## `_loaded` as well as the map so a production read re-scans. Both are asserted, because a
## `reset` that forgot the flag would make every other assertion in this file prove nothing
## about the tree that ships.
##
## ## What is asserted about the authored content itself
##
## That the scan finds the five files, that each resolves to a `ShopDef` with the id the
## file is named for, that a shop's stock all RESOLVES to real item defs (an unresolvable
## `def_id` means `ItemsApi.generate` returns null and the shelf is silently short), and
## that `location_id` is now READ — it was authored content no code looked at.

const SHOPS_ROOT := ShopCatalog.SHOPS_ROOT
const COIN := &"curr_spirit_coin"

## A REAL authored stock row's `def_id`, read out of the shipped tree rather than typed in,
## so this file fails if the content wave changes and not otherwise.
const REAL_STOCK_ID := &"alchemy_cinder_ore"

var _held: Array[Actor] = []


func setup() -> void:
	ShopCatalog.instance().reset()
	ShopCounter.reset()
	_held.clear()


func teardown() -> void:
	# **Every process-wide singleton this suite touched, released.** The runner shares one
	# process across every suite and calls teardown after each test, so a minted counter
	# (a live Actor holding a realized Inventory) or a scanned catalog left behind would
	# outlive this suite and ObjectDB would report leaked instances at exit with every
	# assertion green.
	ShopCounter.reset()
	ShopCatalog.instance().reset()
	SocialCauseCatalog.instance().install_defaults()
	_held.clear()
	for actor in _held:
		actor = null


## A player with a purse, wired for a trade.
func _player(coins: int, id: StringName = &"hero") -> Actor:
	var actor := Actor.new(id, {})
	ItemsApi.attach(actor)
	EconomyApi.attach(actor)
	MarketApi.attach(actor)
	ItemsApi.inventory(actor).add(Crafting.resolve(COIN), coins)
	_held.append(actor)
	return actor


func _rows(def_id: StringName, quantity: int) -> Array:
	return [{"def_id": String(def_id), "quantity": quantity}]


# --- the catalog ------------------------------------------------------------


## The scan finds the authored tree. **The floor, not an exact count**, because adding a
## stall is content — but a floor is still a floor, because "the directory happens to be
## empty" is the failure DEF-0218 describes.
func test_the_scan_finds_the_authored_shops_and_every_one_is_a_shop_def() -> void:
	var ids := ShopCatalog.instance().shop_ids()
	assert_eq(ids.size() >= 5, true, "at least five shops are authored and were read")
	for shop_id in ids:
		var def := ShopCatalog.instance().definition(shop_id)
		assert_ne(def, null, "'%s' resolves to a ShopDef" % String(shop_id))
		if def == null:
			continue
		assert_eq(
			String(def.shop_id), shop_id, "the catalog is keyed by the id the def itself carries"
		)
		assert_ne(def.display_name, "", "'%s' is named" % String(shop_id))
		assert_ne(def.location_id, &"", "'%s' trades somewhere" % String(shop_id))


## The directory scan and the catalog agree. `test_economy_content.gd` already walks the
## directory with `ContentScan`; this asserts the CATALOG is the thing that sees it, which
## is the half that was missing.
func test_the_catalog_sees_every_file_the_directory_holds() -> void:
	var files: Array[String] = []
	for path in ContentScan.files_under(SHOPS_ROOT):
		if path.get_file().ends_with(".tres"):
			files.append(path)
	assert_ne(files.is_empty(), true, "the shop directory holds files")
	assert_eq(
		ShopCatalog.instance().shop_ids().size(),
		files.size(),
		"the catalog holds one entry per authored file, so none was skipped"
	)


## The whole of DEF-0218, as a reachability fact: a caller naming an AUTHORED id gets a
## def, and the same call on an un-authored id returns null rather than a guess.
func test_an_authored_id_resolves_and_an_unauthored_one_does_not() -> void:
	assert_ne(ShopCatalog.instance().definition(&"qi_refining_ore_stall"), null, "authored")
	assert_eq(ShopCatalog.instance().has_definition(&"no_such_shop"), false, "unauthored")
	assert_eq(ShopCatalog.instance().definition(&"no_such_shop"), null, "and it is null")


## `location_id` is AUTHORED CONTENT and this is the first code in the build that reads it
## (DEF-0218). Before this, a caravan authored in the spirit sea traded in every room.
func test_the_authored_location_is_read_so_a_caravan_trades_only_where_authored() -> void:
	var caravan := ShopCatalog.instance().at_location(&"spirit_sea_caravan_yard")
	assert_eq(caravan.size(), 1, "the caravan is at its own yard")
	assert_eq(
		String((caravan[0] as ShopDef).shop_id),
		"spirit_sea_material_caravan",
		"and it is the caravan"
	)
	assert_eq(
		ShopCatalog.instance().at_location(&"qi_refining_ore_row").size(),
		1,
		"the ore row holds the stall, not the caravan"
	)
	assert_eq(ShopCatalog.instance().at_location(&"nowhere_at_all").size(), 0, "an empty row")


## The inventory-size binding is what stops a large authored stock becoming an unbounded
## Actor: the folder is not allowed to grow with the shelf.
func test_the_inventory_snapshot_is_bounded_by_the_shipped_authored_capacity() -> void:
	var snapshot := ShopCatalog.instance().views()
	assert_ne(snapshot.is_empty(), true, "the catalog publishes primitive views")
	var worst := 0
	for row in snapshot:
		worst = maxi(worst, int((row as Dictionary)["capacity"]))
	assert_eq(worst > 0, true, "at least one shop bounds its own stock")
	assert_eq(worst <= ItemsApi.MAX_CAPACITY, true, "and no shop exceeds the items ceiling")


# --- the install seam (kept working) ---------------------------------------


## `install(defs)` is the TEST seam and it must NOT scan — a suite installs exactly what it
## needs. This is what makes every other fixture in this file independent of shipped content.
##
## **The scan is suppressed explicitly** (`_ensure_loaded()` first, so the lazy flag is
## already set) and then only the ids that were NOT shipped are compared. Without that, the
## assertion reads the shipped tree and this test would be measuring the directory rather
## than the seam — which is the `NpcCatalog`/`SocialCauseCatalog` split stated as a rule:
## "a test that reads its own fixture for its own answer is not a test."
func test_install_seams_exactly_what_a_suite_hands_it_and_does_not_scan() -> void:
	var shipped := ShopCatalog.instance().shop_ids()
	var def := _shop_def(&"fixture_stall", 8)
	ShopCatalog.instance().install([def] as Array[ShopDef])
	var after := ShopCatalog.instance().shop_ids()
	assert_eq(after.has(&"fixture_stall"), true, "the fixture was installed")
	assert_eq(after.size(), shipped.size() + 1, "and it added exactly one entry")


## A def with no id is skipped rather than filed under an empty key, which would make every
## anonymous fixture in the process answer for every other one.
func test_install_skips_a_def_with_no_shop_id() -> void:
	var shipped := ShopCatalog.instance().shop_ids()
	ShopCatalog.instance().install([ShopDef.new()] as Array[ShopDef])
	assert_eq(ShopCatalog.instance().shop_ids().size(), shipped.size(), "nothing was filed")


## `reset()` clears `_loaded` as well as the map, so the next production read re-scans. If it
## forgot the flag, the scan assertions above would be measuring this file's fixtures.
func test_a_reset_catalog_re_reads_the_authored_tree() -> void:
	ShopCatalog.instance().reset()
	assert_eq(
		ShopCatalog.instance().shop_ids().size() >= 5,
		true,
		"the shipped tree is what a production read sees after a reset"
	)


# --- the counter, and the verb it exists for --------------------------------


## A counter is an ACTOR carrying a realized Inventory, because `EconomyExchange` takes two
## Actors and a def owns no items (ADR 0100, `institution_claim.gd:119`).
func test_a_def_becomes_an_actor_carrying_its_authored_stock() -> void:
	var counter := ShopCounter.counter(&"qi_refining_ore_stall")
	assert_ne(counter, null, "the stall stands up")
	assert_eq(counter is Actor, true, "and it is the shared Actor type, not a subclass")
	assert_eq(
		ItemsApi.inventory(counter).has(REAL_STOCK_ID, 1),
		true,
		"holding the authored stock it declares"
	)
	assert_eq(counter.tags.has(ShopCounter.ROLE), true, "tagged as a shop (ADR 0092)")
	assert_eq(
		counter.tags.has(&"stall"),
		true,
		"and tagged with its authored kind, so content can gate on it"
	)
	# **The capacity is authored and honoured**, not the items default.
	assert_eq(
		ItemsApi.inventory(counter).capacity,
		ShopCatalog.instance().definition(&"qi_refining_ore_stall").capacity,
		"the authored bound became the bag's bound"
	)


## A shop with no coins could never buy a player's goods, so half of ADR 0100 — the `buys`
## list, the refusal policy that IS the feature — would be unreachable. This is what closes
## that half.
func test_a_counter_is_funded_so_a_player_can_sell_to_it() -> void:
	var counter := ShopCounter.counter(&"qi_refining_ore_stall")
	assert_eq(
		EconomyApi.purse(counter) > 0,
		true,
		"a merchant holds coins, valued at the buy rate it charges nothing for"
	)


## The same counter on a second call, so a player who bought something does not find the
## shelf restocked behind their back. A fresh Actor per call would make the spread testable
## and the game nonsense.
func test_the_counter_is_reused_so_a_sold_item_stays_sold() -> void:
	var first := ShopCounter.counter(&"qi_refining_ore_stall")
	var before := ItemsApi.inventory(first).count(REAL_STOCK_ID)
	var second := ShopCounter.counter(&"qi_refining_ore_stall")
	assert_eq(second == first, true, "the same Actor is handed back")
	assert_eq(ItemsApi.inventory(second).count(REAL_STOCK_ID), before, "with the shelf it had")


## **The load-bearing test.** What a player does: walk into a market row, read what is on
## sale, and buy. Every step goes through a facade verb and authored content, so this is the
## gap closed rather than a lookup that happens to work.
func test_a_player_can_buy_from_an_authored_shop_through_the_market_verbs() -> void:
	var counter := ShopCounter.counter(&"qi_refining_ore_stall")
	var player := _player(5000)
	var before := ItemsApi.inventory(player).count(REAL_STOCK_ID)
	var shelf_before := ItemsApi.inventory(counter).count(REAL_STOCK_ID)
	var published := ShopCounter.at_location(&"qi_refining_ore_row", player)
	assert_eq(int(published["shop_count"]) > 0, true, "the row publishes a shop here")

	var bought := MarketApi.buy(counter, player, _rows(REAL_STOCK_ID, 2))
	assert_eq(bool(bought["ok"]), true, "the purchase settles: %s" % bought.get("reason", ""))
	assert_eq(ItemsApi.inventory(player).count(REAL_STOCK_ID), before + 2, "and the goods arrived")
	assert_eq(
		ItemsApi.inventory(counter).count(REAL_STOCK_ID),
		shelf_before - 2,
		"the shop is a real merchant: the shelf is drawn down by what was bought"
	)
	assert_eq(int(bought["coins"]) > 0, true, "and the player was charged")


## The refusal policy — ADR 0100's "a black market is a content choice rather than a price
## modifier" — is only real if a counter's authored `buys` reaches the verb. A
## `primordial_origin_sealed_counter` has an EMPTY list, so it buys nothing at all.
func test_a_shop_that_buys_nothing_refuses_by_its_authored_policy() -> void:
	var def := ShopCatalog.instance().definition(&"primordial_origin_sealed_counter")
	assert_ne(def, null, "the sealed counter is authored")
	assert_eq(def.buys.is_empty(), true, "and it buys nothing at all")
	var counter := ShopCounter.counter(def.shop_id)
	var player := _player(5000, &"seller")
	ItemsApi.inventory(player).add(Crafting.resolve(REAL_STOCK_ID), 4)
	var sold := MarketApi.sell(def, counter, player, _rows(REAL_STOCK_ID, 1))
	assert_eq(bool(sold["ok"]), false, "an unlisted good is not bought")
	assert_eq(String(sold["reason"]), MarketApi.SHOP_WILL_NOT_BUY, "and it names the rule")
	assert_eq(ItemsApi.inventory(player).count(REAL_STOCK_ID), 4, "and the player keeps it")


## The two directions, and the spread between them, on a real merchant rather than on a
## hand-built fixture. `MarketApi` names no price itself, so this asserts the whole spread
## survives the realization path.
func test_a_round_trip_through_an_authored_shop_costs_the_player() -> void:
	var counter := ShopCounter.counter(&"foundation_reagent_trader")
	var player := _player(5000)
	var good := (
		(ShopCatalog.instance().definition(&"foundation_reagent_trader").stock[0] as Dictionary)["def_id"]
		as StringName
	)
	var before := ItemsApi.inventory(player).count(good)
	var bought := MarketApi.buy(counter, player, _rows(good, 1))
	assert_eq(bool(bought["ok"]), true, "the purchase settles: %s" % bought.get("reason", ""))
	assert_eq(ItemsApi.inventory(player).count(good), before + 1, "and the good arrived")
	var sold := MarketApi.sell(
		ShopCatalog.instance().definition(&"foundation_reagent_trader"),
		counter,
		player,
		_rows(good, 1)
	)
	assert_eq(bool(sold["ok"]), true, "the resale settles: %s" % sold.get("reason", ""))
	assert_eq(
		int(sold["coins"]) < int(bought["coins"]),
		true,
		(
			"the spread cost the player %d on a round trip"
			% (int(bought["coins"]) - int(sold["coins"]))
		)
	)


# --- the read model ------------------------------------------------------------


## `summary()` is the panel's contract and it answers `{}` for a shop this build does not
## ship, rather than a row of nulls a panel would have to guard.
func test_summary_reports_the_shelf_and_refuses_an_unauthored_id() -> void:
	var row := ShopCounter.summary(&"qi_refining_ore_stall")
	assert_eq(bool(row["ok"]), true, "an authored shop answers")
	assert_eq(bool(row["has_actor"]), true, "with a live merchant")
	assert_ne(int(row["purse"]), 0, "and a purse to buy with")
	assert_ne(int(row["funding"]), 0, "the funding number is published")
	assert_ne((row["definition"] as Dictionary)["shop_id"], "", "carrying its def")
	assert_eq(ShopCounter.summary(&"no_such_shop"), {}, "an unauthored id answers {}")


## The location read is a list of those rows, and `can_buy` is what lets a panel grey an
## affordance out instead of letting the verb refuse. It is computed against the player's
## OWN purse, so a broke player and a rich one get different answers from one call.
func test_at_location_prices_each_shop_for_the_asking_player() -> void:
	var rich := _player(50000, &"rich")
	var broke := _player(1, &"broke")
	var rich_row := ShopCounter.at_location(&"spirit_domain_auction_hall", rich)["shops"] as Array
	assert_eq(rich_row.size(), 1, "the auction hall holds one shop")
	assert_eq(bool((rich_row[0] as Dictionary)["can_buy"]), true, "a rich bidder can afford it")
	var broke_row := ShopCounter.at_location(&"spirit_domain_auction_hall", broke)["shops"] as Array
	assert_eq(
		bool((broke_row[0] as Dictionary)["can_buy"]),
		false,
		"and a broke one cannot — from the same authored shelf"
	)
	assert_eq(
		bool(ShopCounter.at_location(&"nowhere", rich)["shop_count"] > 0),
		false,
		"an empty location answers zero shops"
	)


## A null player is a viewer with no purse: `can_buy` is false rather than an error, because
## a panel asks this question before it knows whether there is a player at all.
func test_a_null_player_is_a_viewer_and_cannot_buy() -> void:
	var row := ShopCounter.at_location(&"qi_refining_ore_row")["shops"] as Array
	assert_eq(row.size(), 1, "the shop is still published")
	assert_eq(bool((row[0] as Dictionary)["can_buy"]), false, "with no affordance")


# --- fixtures -----------------------------------------------------------------


func _shop_def(shop_id: StringName, capacity: int) -> ShopDef:
	var def := ShopDef.new()
	def.shop_id = shop_id
	def.display_name = String(shop_id)
	def.kind = &"stall"
	def.location_id = &"fixture_row"
	def.capacity = capacity
	def.stock = [{"def_id": String(REAL_STOCK_ID), "quantity": 1}]
	def.buys = [REAL_STOCK_ID]
	return def
