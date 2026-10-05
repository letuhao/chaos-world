extends TestCase

## ADR 0100: the floor. A dropped item is NOT a loot overflow — `LootState.world_drops` is a
## list of indices into a reward payload, not holdings. The assertions are about ownership of
## the item and about decay without a clock (DEF-0111).

const GOOD := &"currency_spirit_stone"
const PLACE := &"market_square"


func setup() -> void:
	# The floor is a world fact (ADR 0101): a shared store, or a taker would only ever see
	# what they dropped themselves.
	MarketApi.set_store(MarketWorldLedger.new())


func _actor_with(def_id: StringName, quantity: int) -> Actor:
	var actor := Actor.new()
	actor.id = &"dropper"
	ItemsApi.attach(actor)
	ItemsApi.inventory(actor).add(Crafting.resolve(def_id), quantity)
	MarketApi.attach(actor)
	return actor


func _rows(def_id: StringName, quantity: int) -> Array:
	return [{"def_id": String(def_id), "quantity": quantity}]


func test_drop_moves_a_good_off_the_inventory_onto_the_floor() -> void:
	var actor := _actor_with(GOOD, 3)
	var dropped := MarketApi.drop(actor, PLACE, _rows(GOOD, 2))
	assert_eq(bool(dropped["ok"]), true, "the drop succeeds: %s" % dropped.get("reason", ""))
	assert_eq(ItemsApi.inventory(actor).count(GOOD), 1, "the inventory gave up the goods")
	var entries: Array = (MarketApi.state(actor)["floor"] as Dictionary)[String(PLACE)]
	assert_eq(entries.size(), 1, "and the floor holds one entry")
	assert_eq(int(entries[0]["quantity"]), 2, "with the right quantity")


func test_a_refused_drop_writes_nothing() -> void:
	# ADR 0044. The player does not hold four, so nothing leaves the inventory and nothing
	# lands on the floor.
	var actor := _actor_with(GOOD, 1)
	var dropped := MarketApi.drop(actor, PLACE, _rows(GOOD, 4))
	assert_eq(bool(dropped["ok"]), false, "dropping more than is carried refuses")
	assert_eq(String(dropped["reason"]), EconomyExchange.NOT_CARRIED, "and names the rule")
	assert_eq(ItemsApi.inventory(actor).count(GOOD), 1, "and the inventory is untouched")
	var entries: Array = (MarketApi.state(actor)["floor"] as Dictionary).get(String(PLACE), [])
	assert_eq(entries.size(), 0, "and the floor is untouched")


func test_take_moves_a_good_back_off_the_floor() -> void:
	var dropper := _actor_with(GOOD, 3)
	MarketApi.drop(dropper, PLACE, _rows(GOOD, 1))
	var drop_id := _drop_id(dropper)

	var taker := Actor.new()
	taker.id = &"taker"
	ItemsApi.attach(taker)
	MarketApi.attach(taker)
	var taken := MarketApi.take(taker, PLACE, drop_id)
	assert_eq(bool(taken["ok"]), true, "the take succeeds: %s" % taken.get("reason", ""))
	assert_eq(ItemsApi.inventory(taker).count(GOOD), 1, "and the taker holds the good")
	var entries: Array = (MarketApi.state(taker)["floor"] as Dictionary).get(String(PLACE), [])
	assert_eq(entries.size(), 0, "and the floor is empty again")


func test_the_floor_is_bounded_per_location() -> void:
	var actor := _actor_with(GOOD, 40)
	for _i in MarketApi.MAX_FLOOR_PER_LOCATION:
		MarketApi.drop(actor, PLACE, _rows(GOOD, 1))
	var entries: Array = (MarketApi.state(actor)["floor"] as Dictionary)[String(PLACE)]
	assert_eq(entries.size(), MarketApi.MAX_FLOOR_PER_LOCATION, "the floor holds exactly its cap")
	var overflow := MarketApi.drop(actor, PLACE, _rows(GOOD, 1))
	assert_eq(bool(overflow["ok"]), false, "one more refuses")
	assert_eq(String(overflow["reason"]), MarketApi.FLOOR_FULL, "and names the cap")


func test_settle_ages_the_floor_without_a_clock() -> void:
	# DEF-0111: the caller owns time. `settle` takes an explicit period count and nothing
	# reads a wall clock, so a test needs no generator and no waiting. The decay is AUTHORED
	# at drop time rather than patched afterwards, because `normalize` hands back a copy and
	# a patch through it silently does nothing.
	var actor := _actor_with(GOOD, 2)
	MarketApi.drop(actor, PLACE, _rows(GOOD, 1), 3)
	var first := MarketApi.settle(actor, PLACE, 1)
	assert_eq(bool(first["ok"]), true, "settling a period succeeds")
	assert_eq(int(first["expired"]), 0, "and nothing expired yet")
	var second := MarketApi.settle(actor, PLACE, 2)
	assert_eq(int(second["expired"]), 1, "the entry expires once its periods elapse")
	assert_eq(int(second["remaining"]), 0, "and is gone from the floor")


func test_an_entry_with_no_decay_never_expires() -> void:
	var actor := _actor_with(GOOD, 2)
	MarketApi.drop(actor, PLACE, _rows(GOOD, 1))
	var result := MarketApi.settle(actor, PLACE, 999)
	assert_eq(bool(result["ok"]), true, "settling many periods succeeds")
	assert_eq(int(result["expired"]), 0, "an entry that never decays survives")
	assert_eq(int(result["remaining"]), 1, "and is still on the floor")


func test_settle_refuses_zero_periods() -> void:
	var actor := _actor_with(GOOD, 1)
	var result := MarketApi.settle(actor, PLACE, 0)
	assert_eq(bool(result["ok"]), false, "zero periods refuses")
	assert_eq(String(result["reason"]), MarketApi.NO_PERIODS, "and names the rule")


func test_taking_an_unknown_drop_refuses() -> void:
	var actor := _actor_with(GOOD, 1)
	var result := MarketApi.take(actor, PLACE, "drop_nope")
	assert_eq(bool(result["ok"]), false, "an unknown drop refuses")
	assert_eq(String(result["reason"]), MarketApi.NO_SUCH_DROP, "and names the rule")


func test_the_floor_ledger_is_json_safe() -> void:
	# ADR 0027: the realized instance payload must survive a save, or a dropped roll is lost.
	var actor := _actor_with(GOOD, 1)
	MarketApi.drop(actor, PLACE, _rows(GOOD, 1))
	var payload := MarketApi.state(actor)
	var restored: Variant = JSON.parse_string(JSON.stringify(payload))
	assert_eq(typeof(restored), TYPE_DICTIONARY, "the ledger is JSON-safe")
	var entries: Array = (restored as Dictionary)["floor"][String(PLACE)]
	assert_eq(entries.size(), 1, "and the entry survives")
	assert_eq(
		typeof((entries[0] as Dictionary)["dropped_by"]),
		TYPE_STRING,
		"the dropper id is a String, not a StringName"
	)


func test_summary_is_empty_without_an_actor() -> void:
	assert_eq(MarketApi.summary(null), {}, "summary is {} with no actor")


func test_summary_reports_the_spread() -> void:
	var actor := _actor_with(GOOD, 1)
	var summary := MarketApi.summary(actor)
	assert_eq(bool(summary["spread"]["arbitrage_possible"]), false, "no arbitrage is possible")
	assert_eq(bool(summary["spread"].has("buy_rate")), true, "and the panel can read the buy rate")


func _drop_id(actor: Actor) -> String:
	var entries: Array = (MarketApi.state(actor)["floor"] as Dictionary)[String(PLACE)]
	return String(entries[0]["drop_id"])
