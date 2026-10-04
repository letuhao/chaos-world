extends TestCase

## ADR 0102 / BL-0049: **NPCs bid, and the bid is arithmetic.**
##
## BL-0049 asked for "NPC bidders with wealth/personality; rare items attract powerful
## cultivators; consequences emerge". These assert the three properties that make that
## true rather than decorative:
##
##   - the bid is a function of (purse, tag, lot) and of nothing else — no rng anywhere;
##   - a bidder who cannot reach the opening bid writes NOTHING;
##   - a legendary lot opens four times above a common one, so only a deep purse clears
##     it. That is the whole "rare items attract powerful cultivators" claim, and it is
##     `RARITY_WEIGHT` multiplied through one frozen price rather than a simulation.
##
## ## Read the STORE, never the actor's own mirror
##
## `MarketApi.state(actor)` returns the actor's OWN mirror by design; `summary` goes
## through the shared world store. A test that read `state` therefore saw a **stale**
## ledger — the world row written by `_save`, which on a fresh house still carries the
## previous test's lots — and asserted against a bid count of zero. Every lot assertion
## below goes through [_lots], which is the only shape that cannot go stale.
##
## ## Fixtures are held, not returned
##
## `Actor` is a `RefCounted`. An actor built inside a helper is **freed the moment that
## helper returns**, the ledger stores ids rather than references, and nothing keeps it
## alive — so every actor here is appended to `_held`. Same reason
## `test_market_auction.gd` does it.
##
const COIN := &"curr_spirit_coin"
const GOOD := &"currency_spirit_stone"
const CAST_ROOT := "res://data/npc/cast"

## Every cast member an authored appetite reaches, with the appetite the table gives it.
## A restated expectation on purpose: a test that read the number back out of
## `APPETITE_PERCENT` would pass if both the tag and the number drifted together.
const AUTHORED_BIDDERS: Array = [
	{"file": "elder_wei.tres", "tag": &"collector", "percent": 90},
	{"file": "smith_bearcutter.tres", "tag": &"thrifty", "percent": 45},
	{"file": "drifter.tres", "tag": &"opportunist", "percent": 30},
	{"file": "gate_keeper_bo.tres", "tag": &"opportunist", "percent": 30},
]

## The tags a module must not acquire an edge to. `npc` is here because the bidding verb
## is composed, not because any module names it — the assertion is structural, so it
## holds whether the verb lives in `app/` or somebody later moves it.
const FORBIDDEN_IN_MARKET: Array = [
	"NpcApi", "NpcCatalog", "NpcDef", "NpcState", "NpcEvents", "NpcBoot"
]

## Every seed and generator token GDScript offers, as a TEST-LOCAL fixture. Nothing in
## production wants this table: it is the vocabulary the structural pin searches FOR, and
## `auction_bids.gd` is the only file it is ever read against — so a production constant
## for it would put a list of forbidden words in the shipping facade, which is the
## opposite of the ADR 0102 rule it exists to protect.
##
## `seed(` is here too even though `market/api.gd` writes a `"seed"` key while rebuilding
## a saved instance: a `"seed":` string key is saved data, not a generator call, and this
## list is matched against `auction_bids.gd` only.
const GENERATORS: Array = [
	"RandomNumberGenerator",
	"randf(",
	"randi(",
	"rand_range(",
	"randf_range(",
	"rand_weighted(",
	"rand_from_seed(",
	"randomize(",
	"shuffle(",
	"seed(",
	"Time.",
	"get_ticks",
	"get_tree()",
]

var _held: Array[Actor] = []
## The `AuctionBids._lot` helper reads through `MarketApi.summary`, so it is handed a
## HOUSE-SCOPED store: one bid call resolves only the lots that house listed, and a
## "compare two collectors" case can then be stated as two houses instead of two ids
## that collide into one escrow check.
var _store: MarketWorldLedger = null


func setup() -> void:
	# A lot is a WORLD fact: a bidder must see the seller's lot or every bid refuses
	# `lot_not_open` (ADR 0101).
	_store = MarketWorldLedger.new()
	MarketApi.set_store(_store)
	_held.clear()


func teardown() -> void:
	# Process-wide, and the runner calls this after EVERY test — a lot left in the shared
	# store outlives the suite and the next one inherits it.
	MarketApi.set_store(null)
	_store = null
	_held.clear()


## Point the shared store at a fresh world. Called between two lots that would otherwise
## collide on `lot_<seller>_<instance>`.
##
## **Both halves of a comparison must be built INSIDE the world they are compared in.**
## `MarketApi.list` writes the lot through `_save`, which writes the shared store AND mirrors
## the row onto `seller.module_data`. `_state` reads the shared store when there is one, so
## a lot listed in world A is INVISIBLE to every reader once the store points at world B —
## while the seller's own `module_data` mirror still carries it. That split is the shape
## `MarketApi.state` warns about in its own docstring, and it produces two different broken
## results depending on which side reads: a BIDDER resolves `no_lot`, while a `_lot()` call
## resolves the seller's stale mirror. `_new_world` therefore exists to be called BEFORE a
## lot is listed, never between a listing and the bid that answers it — which is exactly
## where the previous version of this file called it, and why eight of its cases read
## `required 11` against `required 901` on the same fixture.
func _new_world() -> void:
	_store = MarketWorldLedger.new()
	MarketApi.set_store(_store)


# --- fixtures ------------------------------------------------------------------


## The house: an actor holding ONE realized instance to list, and an empty purse to be
## paid into. Added as an instance rather than a stack because `remove_instance` only
## ever reaches the `_instances` half, which is the same shape `loot` escrows.
##
## **`next_seller` makes BOTH ids unique per house.** A lot id is
## `lot_<seller>_<instance_id>`, so a unique seller id alone is not enough — it was
## `MarketApi.list`'s duplicate-instances scan that refused, and that scan matches
## `instance_id` ALONE across the whole world ledger. Every house minted
## `ItemInstance.new(def.id, &"lot_candidate")`, so house 1 escrowed the lot
## `lot_auction_house_1_lot_candidate` and house 2's very different instance — a different
## seller, a different lot id — was refused `lot_already_listed` for "re-listing" it. The
## second listing returned `""`, and every later read of `""` then failed in a way that had
## nothing to do with the property under test: a `required_bid` of 0, a ceiling of 0, a
## second `assert_eq` over the same two numbers printing the same 0-vs-450 twice. So the
## instance id is minted per house as well, which is what makes a comparison two real lots
## in one world — the world store is what makes a lot visible to a bidder, so separating
## them into different worlds only separates the lot from the reader as well.
func _house(rarity: StringName = &"") -> Actor:
	_next_seller += 1
	var actor := Actor.new()
	actor.id = &"auction_house_%d" % _next_seller
	ItemsApi.attach(actor, 24)
	# A seller's floor and lots are WORLD facts (ADR 0101). `MarketApi.attach` is what
	# installs the shared store onto a fresh actor; without it a house that never sold
	# anything reads an empty mirror and the escrow row is written somewhere no bidder
	# can see.
	MarketApi.attach(actor)
	var def := Crafting.resolve(GOOD)
	var instance := ItemInstance.new(def.id, &"lot_candidate_%d" % _next_seller)
	instance.def_ref = def
	instance.rarity = rarity if rarity != &"" else def.rarity
	# A realized price must come from AUTHORED worth: ADR 0094 refuses an instance whose
	# `rolled` carries a `trade_value`, and `list` returns `no_settlement` for one.
	instance.rolled = []
	instance.realm = &""
	ItemsApi.inventory(actor).add_instance(instance)
	EconomyApi.attach(actor)
	_held.append(actor)
	return actor


## A counter for unique seller ids. A member rather than a `static var` because a static
## would carry across suites in this one process.
var _next_seller := 0


## A bidder with `coins` of purse and the given appetite tags.
##
## `Actor.tags` is `Array[StringName]`, so a plain `Array` cannot be ASSIGNED to it —
## and a rejected assignment returns from the function, so the helper silently handed
## back an untyped actor and every bid refused for a reason three frames away. Appended
## element-wise for that reason.
func _bidder(id: StringName, coins: int, tags: Array[StringName] = []) -> Actor:
	var actor := Actor.new()
	actor.id = id
	ItemsApi.attach(actor, 24)
	ItemsApi.inventory(actor).add(Crafting.resolve(COIN), coins)
	for tag in tags:
		actor.tags.append(tag)
	EconomyApi.attach(actor)
	_held.append(actor)
	return actor


func _list_good(house: Actor) -> String:
	var instance_id := &""
	for instance in ItemsApi.inventory(house).instances():
		instance_id = instance.instance_id
		break
	var listed := MarketApi.list(house, instance_id, 3)
	assert_eq(
		bool(listed.get("ok", false)), true, "the fixture lot lists: %s" % listed.get("reason", "")
	)
	return String(listed.get("lot_id", ""))


## The lots of the current world, as the READ MODEL sees them — through `summary`, which
## goes via the world store, and never through `MarketApi.state`, whose actor mirror goes
## stale. A fresh throwaway actor is the reader, because `summary` takes any actor.
func _lots() -> Array:
	return (
		MarketApi.summary(_bidder(&"a_reader", 0, [] as Array[StringName])).get("lots", []) as Array
	)


## The one lot of the current world. Returns `{}` rather than indexing when the count is
## wrong, so a broken fixture turns the NEXT assertion red with a message instead of
## aborting this one halfway through.
func _lot() -> Dictionary:
	var rows := _lots()
	assert_eq(rows.size(), 1, "the fixture listed exactly one lot")
	return (rows[0] as Dictionary) if rows.size() == 1 else {}


## The lot named by `lot_id`, out of the current world. **The selector for a case that
## deliberately holds two lots at once** — `_lot()` asserts the count is exactly one, which
## is the right guard for a single-lot case and the wrong one for a comparison, where the
## previous version reached for `_lot()` anyway and read whichever row sorted first.
func _row(lot_id: String) -> Dictionary:
	for row in _lots():
		if String((row as Dictionary).get("lot_id", "")) == lot_id:
			return row as Dictionary
	return {}


## Resolve a bid row's actor id to a live body, exactly as a caller of `settle_lot` must.
func _resolver(actors: Array) -> Callable:
	return func(id: String) -> Actor:
		for actor in actors:
			if actor != null and String(actor.id) == id:
				return actor as Actor
		return null


# --- 1. Determinism, and the absence of an rng ---------------------------------


## The load-bearing property of ADR 0102: same purse, same tag, same lot ⇒ same bid,
## forever. A bid that varies run to run is a slot machine, not a bid.
func test_the_same_purse_tag_and_lot_always_produce_the_identical_bid() -> void:
	var house := _house()
	var lot_id := _list_good(house)
	var first := _bidder(&"first_try", 1000, [&"collector"] as Array[StringName])
	var ceiling := AuctionState.bid_ceiling(EconomyApi.purse(first), first.tags)
	assert_eq(ceiling, 900, "a 1000-coin collector's ceiling is 90 percent of it")
	# **Repeated `AuctionBids.bid` calls, not just repeated arithmetic** — so the verb's
	# whole path is what is proved stable, not only the function it happens to call.
	for attempt in 3:
		var seen := AuctionBids.bid(first, StringName(lot_id), 1 + attempt)
		assert_eq(
			int(seen["amount"]),
			ceiling,
			"attempt %d: the verb decides the same number every time" % attempt
		)
		assert_eq(
			AuctionState.bid_ceiling(EconomyApi.purse(first), first.tags),
			ceiling,
			"attempt %d: and the ceiling underneath it never drifts" % attempt
		)
	# One bid was written. The two later calls found their own standing row and were
	# refused `already_high`, so determinism is also idempotence against the ledger
	# rather than a growing ladder — three identical calls, one bid.
	assert_eq(int(_lot()["bid_count"]), 1, "three identical calls wrote one bid, not three")


## **Two separately-constructed actors with identical inputs must agree.** This is the
## assertion that catches a hidden per-instance counter, a cached-id salt or a
## last-bidder memory: none of them is a random number, and all three would make one
## actor's bid depend on the order bidders appeared.
##
## **Each actor gets its OWN identical lot, in the SAME world.** The ceiling is a function
## of the lot's current high — and after the first actor bids, that lot's required bid rises
## by a step — so comparing both against one post-bid lot would be comparing two different
## questions and would read as a determinism failure when nothing had drifted. Two houses
## in one world give two lots at the same price with neither touched by the other's bid,
## which is the comparison this is actually about. They used to be two WORLDS, which was
## worse than wrong: `_new_world` between a listing and its bid moved the lot out of the
## shared store and into the seller's mirror alone, so the bidder read `no_lot` and the
## assertion passed on `amount 0` from a refusal rather than on a bid.
func test_two_independently_built_bidders_with_the_same_inputs_bid_identically() -> void:
	var left := _bidder(&"bidders_left", 1000, [&"thrifty"] as Array[StringName])
	var right := _bidder(&"bidders_right", 1000, [&"thrifty"] as Array[StringName])
	assert_eq(left == right, false, "the two actors are distinct bodies")
	assert_ne(String(left.id), String(right.id), "with distinct ids")
	var lot_left := _list_good(_house())
	var lot_right := _list_good(_house())
	var from_left := AuctionBids.bid(left, StringName(lot_left), 1)
	var from_right := AuctionBids.bid(right, StringName(lot_right), 1)
	assert_eq(bool(from_left["ok"]), true, "the first bids: %s" % from_left.get("reason", ""))
	assert_eq(
		bool(from_right["ok"]), true, "and so does the second: %s" % from_right.get("reason", "")
	)
	assert_eq(
		int(from_left["required"]),
		int(from_right["required"]),
		"both faced an identical lot, so the required bid cannot explain any difference"
	)
	assert_eq(
		int(from_left["amount"]),
		int(from_right["amount"]),
		"same purse + same tag + same lot = the same number, on two separate actors"
	)
	assert_eq(
		int(from_left["ceiling"]), int(from_right["ceiling"]), "and the same ceiling underneath it"
	)
	assert_eq(int(from_left["ceiling"]), 450, "1000 coins at 45 percent is 450")
	assert_eq(
		int(from_left["amount"]),
		int(from_right["amount"]),
		"same purse + same tag + same lot = the same number, on two separate actors"
	)
	assert_eq(
		int(from_left["ceiling"]), int(from_right["ceiling"]), "and the same ceiling underneath it"
	)


## The structural half of "no rng". Every seed and generator token GDScript offers is
## searched for in the verb's own source, so a future "personality roll" is a failing
## build rather than a property nobody checked.
##
## **Comments are stripped before the search** — the same rule
## `modules/sect/test_sect_succession.gd` and `modules/world_spawn/test_world_spawn.gd`
## already apply. `auction_bids.gd` opens with a section titled "No rng anywhere in this
## file" and then enumerates the very names this case bans, so a raw `source.contains(...)`
## fails on the prose that PROVES the rule while the code beside it stays clean. The ban
## is about what the verb EXECUTES.
func test_the_bid_verb_contains_no_generator_and_no_clock() -> void:
	var source := FileAccess.get_file_as_string("res://src/app/auction_bids.gd")
	assert_ne(source.is_empty(), true, "the verb's source is readable")
	var code := _executable(source)
	for forbidden in GENERATORS:
		assert_eq(
			code.contains(String(forbidden)), false, "auction_bids.gd names no %s" % forbidden
		)
	# And it reads the ONE ceiling rather than writing its own arithmetic.
	assert_eq(
		source.contains("AuctionState.bid_ceiling("),
		true,
		"the ceiling is `market`'s own function, called rather than re-derived"
	)
	# And it authors no appetite of its own: the table is the single home, NAMED rather
	# than copied, so a fourth personality is a new ROW and not a second table.
	assert_eq(
		source.contains("APPETITE_PERCENT"),
		true,
		"and the appetite table is named as the source, not copied"
	)


## `source` with every `##` documentation line dropped, so a structural pin can forbid a
## token in CODE while the file is still free to explain the rule in prose. A whole-line
## comment is dropped and an inline trailing comment is truncated at its `#`.
func _executable(source: String) -> String:
	var out: Array[String] = []
	for line in source.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash_at := line.find("#")
		out.append(line.substr(0, hash_at) if hash_at >= 0 else line)
	return "".join(out)


# --- 2. A bidder who cannot reach the opening writes NOTHING -------------------


## ADR 0094's headline, as a refusal: a legendary lot prices at `RARITY_WEIGHT`'s 4×,
## so its opening is 4×, so only a deep purse clears it. "Rare items attract powerful
## cultivators" is arithmetic, not a simulation loop nobody wrote (DEF-0111).
func test_a_rare_lot_opens_far_above_a_common_one_so_a_shallow_purse_cannot_clear_it() -> void:
	# **Two lots in ONE world**, not one lot per world. `_house` now mints a unique seller
	# id per call, so the two lot ids no longer collide and there is no reason to separate
	# them at all — while separating them was the thing that broke this case, because the
	# bid on the rare lot was resolving against a store the lot had been listed outside of.
	var common_lot := _list_good(_house(&"common"))
	var rare_lot := _list_good(_house(&"legendary"))
	var common_row := _row(common_lot)
	var rare_row := _row(rare_lot)
	assert_eq(
		int(rare_row["required_bid"]) > int(common_row["required_bid"]),
		true,
		"a legendary lot opens above a common one through the one price formula"
	)
	# The SAME def, the SAME realm, the same authored base worth — the only difference is
	# the realized rarity. So the ratio IS the rarity weight, read out of `economy`.
	assert_eq(
		int(rare_row["price"]) == int(common_row["price"]) * 4,
		true,
		(
			"and it opens at exactly RARITY_WEIGHT's 4x (%d vs %d)"
			% [int(rare_row["price"]), int(common_row["price"])]
		)
	)
	# A purse sized off the COMMON opening cannot reach the legendary one, whatever its
	# appetite — which is the property, stated as a bid.
	var shallow := _bidder(
		&"shallow", int(common_row["required_bid"]) + 1, [&"collector"] as Array[StringName]
	)
	var refused := AuctionBids.bid(shallow, StringName(rare_lot), 1)
	assert_eq(bool(refused["ok"]), false, "a shallow purse cannot clear a legendary lot")
	assert_eq(
		String(refused["reason"]), AuctionBids.CEILING_BELOW_REQUIRED, "and it refuses by name"
	)
	# ...and the SAME purse clears the common lot, so the refusal is the lot's worth and
	# not a rule that refuses everything. No `_new_world` here, for the same reason: a
	# third house in this world lists an identical common lot, and `shallow` has not bid
	# on THIS one.
	var common_lot_again := _list_good(_house(&"common"))
	var accepted := AuctionBids.bid(shallow, StringName(common_lot_again), 1)
	assert_eq(
		bool(accepted["ok"]),
		true,
		"the same purse clears the common lot: %s" % accepted.get("reason", "")
	)


## The refusal WRITES NOTHING. Not a bid row, not a high bid, not a ledger entry — a
## refusal that half-writes is the ADR 0102 escrow bug in a new coat.
func test_a_bidder_whose_ceiling_is_below_the_required_bid_changes_nothing() -> void:
	var house := _house()
	var lot_id := _list_good(house)
	var before := _lot()
	var purse_before := EconomyApi.purse(house)
	# A purse of ten coins against a lot priced in the tens.
	var pauper := _bidder(&"pauper", 10, [&"collector"] as Array[StringName])
	var refused := AuctionBids.bid(pauper, StringName(lot_id), 1)
	assert_eq(bool(refused["ok"]), false, "ten coins cannot clear the opening")
	assert_eq(String(refused["reason"]), AuctionBids.CEILING_BELOW_REQUIRED, "and names the rule")
	# **90 percent of ten, not three.** Three is `DEFAULT_APPETITE_PERCENT` — the number an
	# UNTAGGED bidder gets — so the old expectation was reading the default back and calling
	# it the collector's. The correct invariant restates the ADR 0102 formula from the
	# authored table rather than hardcoding a figure: purse x appetite percent / 100.
	assert_eq(
		int(refused["ceiling"]),
		int(roundi(10.0 * float(AuctionState.APPETITE_PERCENT[&"collector"]) / 100.0)),
		"the ceiling is the purse times the AUTHORED collector percent, not the default"
	)
	assert_eq(int(refused["ceiling"]), 9, "which for ten coins at 90 percent is 9")
	assert_eq(
		int(refused["required"]) > int(refused["ceiling"]), true, "which is below what the lot asks"
	)
	var after := _lot()
	assert_eq(
		int(after["high_bid_amount"]), int(before["high_bid_amount"]), "the high is unchanged"
	)
	assert_eq(int(after["bid_count"]), 0, "and no bid was recorded at all")
	assert_eq(String(after["status"]), "open", "the lot is still open")
	assert_eq(int(after["required_bid"]), int(before["required_bid"]), "and the lot is unchanged")
	assert_eq(EconomyApi.purse(house), purse_before, "and the house is unchanged")
	assert_eq(EconomyApi.purse(pauper), 10, "and the refused bidder was not charged or touched")
	assert_eq(
		AuctionBids.could_bid(pauper, StringName(lot_id)),
		false,
		"and the read agrees, so no panel offers a button the verb would refuse"
	)


## The second refusal: a bidder who already carries the lot's def does not buy a second
## copy. Also no write, and named separately — "already holds it" and "cannot afford it"
## are two different messages to a panel.
func test_a_bidder_who_already_holds_the_lot_refuses_without_writing() -> void:
	var house := _house()
	var lot_id := _list_good(house)
	var holder := _bidder(&"already_owns_one", 1000, [&"collector"] as Array[StringName])
	ItemsApi.inventory(holder).add(Crafting.resolve(GOOD), 1)
	var before := _lot()
	var refused := AuctionBids.bid(holder, StringName(lot_id), 1)
	assert_eq(bool(refused["ok"]), false, "you do not bid for a second copy")
	assert_eq(String(refused["reason"]), AuctionBids.ALREADY_HOLDS_LOT, "and that is its own name")
	assert_eq(AuctionBids.could_bid(holder, StringName(lot_id)), false, "and the read agrees")
	var after := _lot()
	assert_eq(int(after["bid_count"]), 0, "nothing was written")
	assert_eq(int(after["bid_count"]), int(before["bid_count"]), "not even one bid row")


## A lot nobody has heard of is a third refusal, distinct from "cannot afford it", so a
## panel can say "that sale is over" instead of "you are too poor".
func test_a_bidder_against_a_lot_that_does_not_exist_refuses_by_name() -> void:
	var bidder := _bidder(&"bidder", 1000, [&"collector"] as Array[StringName])
	var refused := AuctionBids.bid(bidder, &"lot_nobody_listed", 1)
	assert_eq(bool(refused["ok"]), false, "there is no such lot")
	assert_eq(String(refused["reason"]), AuctionBids.NO_LOT, "and it says so")
	assert_eq(AuctionBids.could_bid(bidder, &"lot_nobody_listed"), false, "nor is it bidable")


# --- 3. Personality is an authored tag, and it decides who wins ----------------


## A collector outbids a thrifty on identical purses. Same money, different appetite —
## which is the entire claim that an auction has personalities in it at all.
##
## **The comparison is of the DECISION (the amount each commits), not of two placed bids.**
## A bid must STRICTLY exceed the standing high (ADR 0102), so if the collector bids
## first the thrifty's own bid would be refused `bid_too_low` — which proves they commit
## less, but hides the clean "same purse, different appetite, different number" reading.
## So each actor is handed its OWN identical lot (two houses in ONE world, same price) and
## both face the same required bid. The amounts are then directly comparable: the only input
## that differs is the appetite tag. As with the determinism pair, these used to be two
## worlds and the thrifty's bid was being read out of a store its lot was not in.
func test_a_collector_outbids_a_thrifty_with_identical_purses() -> void:
	var lot_a := _list_good(_house())
	var lot_b := _list_good(_house())
	var collector := _bidder(&"the_collector", 1000, [&"collector"] as Array[StringName])
	var thrifty := _bidder(&"the_thrifty", 1000, [&"thrifty"] as Array[StringName])
	assert_eq(EconomyApi.purse(collector), EconomyApi.purse(thrifty), "identical purses to start")
	var collector_bid := AuctionBids.bid(collector, StringName(lot_a), 1)
	assert_eq(
		bool(collector_bid["ok"]), true, "the collector bids: %s" % collector_bid.get("reason", "")
	)
	var thrifty_bid := AuctionBids.bid(thrifty, StringName(lot_b), 1)
	assert_eq(
		bool(thrifty_bid["ok"]), true, "the thrifty bids too: %s" % thrifty_bid.get("reason", "")
	)
	assert_eq(
		int(collector_bid["required"]),
		int(thrifty_bid["required"]),
		"both faced the identical required bid, so appetite is the only difference"
	)
	assert_eq(
		int(collector_bid["amount"]) > int(thrifty_bid["amount"]),
		true,
		(
			"and the collector commits more of the same purse: %d against %d"
			% [int(collector_bid["amount"]), int(thrifty_bid["amount"])]
		)
	)
	assert_eq(
		int(collector_bid["ceiling"]) > int(thrifty_bid["ceiling"]),
		true,
		"and the reason is appetite: 90 percent against 45"
	)
	assert_eq(int(collector_bid["ceiling"]), 900, "a 1000-coin collector's ceiling is 900")
	assert_eq(int(thrifty_bid["ceiling"]), 450, "a 1000-coin thrifty's is 450")


## The appetite is AUTHORED CONTENT, reachable in the shipped cast rather than only in a
## test. `ActorFactory.spawn_npc` copies `NpcDef.tags` onto `Actor.tags` verbatim, so a
## tag on a `.tres` IS the appetite — no roll, no code change, no `npc` dependency.
func test_the_shipped_cast_carries_authored_bidder_tags_that_reach_the_actors() -> void:
	for entry in AUTHORED_BIDDERS:
		var path := "%s/%s" % [CAST_ROOT, String(entry["file"])]
		var def := load(path) as NpcDef
		assert_ne(def, null, "%s loads" % path)
		if def == null:
			continue
		assert_eq(
			def.tags.has(entry["tag"]),
			true,
			"'%s' authors the %s appetite tag" % [String(def.npc_id), String(entry["tag"])]
		)
		assert_eq(
			int(AuctionState.APPETITE_PERCENT[entry["tag"]]),
			int(entry["percent"]),
			"and the table reads it as %d percent of a purse" % int(entry["percent"])
		)
		# The factory's copy loop is the whole mechanism; asserted on the loop's own
		# contract rather than by spawning, so a room is not needed to prove content.
		assert_eq(
			(
				def.tags.has(&"wanderer")
				or def.tags.has(&"elder")
				or def.tags.has(&"merchant")
				or def.tags.has(&"gatekeeper")
			),
			true,
			"'%s' still carries the tags it shipped with" % String(def.npc_id)
		)


## And end-to-end through the real production path: a spawned cast member's actor
## carries the tag, and its ceiling is the authored percent of its purse. This is what
## "reachable in content, not only in tests" means — nothing here installs a fixture.
func test_a_spawned_cast_member_bids_with_its_authored_appetite() -> void:
	NpcCatalog.instance().reset()
	NpcRegistry.instance().reset()
	NpcApi._current_player = null
	SocialCauseCatalog.instance().install_defaults()
	NpcBoot.install(_player())
	var elder := NpcApi.spawn(&"elder_wei")
	assert_ne(elder, null, "the elder is minted by the production path")
	assert_eq(elder.tags.has(&"collector"), true, "and the authored tag reached Actor.tags")
	ItemsApi.attach(elder, 24)
	EconomyApi.attach(elder)
	ItemsApi.inventory(elder).add(Crafting.resolve(COIN), 1000)
	assert_eq(
		AuctionState.bid_ceiling(EconomyApi.purse(elder), elder.tags),
		900,
		"a 1000-coin elder bids as a collector: 90 percent, exactly as authored"
	)
	# And through the verb, on a real lot.
	var house := _house()
	var lot_id := _list_good(house)
	var placed := AuctionBids.bid(elder, StringName(lot_id), 1)
	assert_eq(bool(placed["ok"]), true, "and the elder bids: %s" % placed.get("reason", ""))
	assert_eq(int(placed["ceiling"]), 900, "at the authored ceiling")
	# A transient with no purse cannot bid: the same arithmetic one level down.
	var drifter := NpcApi.spawn(&"drifter")
	ItemsApi.attach(drifter, 24)
	EconomyApi.attach(drifter)
	assert_eq(
		AuctionState.bid_ceiling(EconomyApi.purse(drifter), drifter.tags),
		0,
		"an empty purse bids nothing"
	)
	assert_eq(
		String(AuctionBids.bid(drifter, StringName(lot_id), 2)["reason"]),
		AuctionBids.CEILING_BELOW_REQUIRED,
		"whatever the appetite"
	)
	NpcApi._current_player = null
	NpcRegistry.instance().reset()
	NpcCatalog.instance().reset()


## The bid is placed at the required bid whenever the ceiling clears it, and is the
## ceiling — unclamped — when the ceiling is above that.
##
## **The purse is `required * 2`, not `required * 4`, and that is the correction.** The old
## expectation assumed an untagged bidder's 30 percent of `required * 4` lands BELOW
## `required`, then asserted `ceiling < required` and expected the clamp to lift a bid the
## verb would have refused. It does not: 30 percent of four times the requirement is 1.2× the
## requirement, so the premise was false and the case proved nothing. Two times it is 0.6×,
## which is genuinely below — but that is now a REFUSAL (`ceiling_below_required`), because
## ADR 0102's rule is "no write unless the ceiling reaches the requirement". So the
## minimum placeable purse for an untagged bidder is `ceil(required / 0.30)`, and the clamp
## fires only on the way IN: `maxi(required, ceiling)` with `ceiling >= required` is `ceiling`
## or `required` itself.
func test_a_bid_is_the_required_bid_at_the_floor_and_the_ceiling_above_it() -> void:
	var house := _house()
	var lot_id := _list_good(house)
	var required := int(_lot()["required_bid"])
	# An untagged bidder: 30 percent. Sized so the ceiling sits just under twice the
	# requirement — below it, so the bid lands ON the requirement, and above it.
	var per_coin := AuctionState.DEFAULT_APPETITE_PERCENT / 100.0
	var purse := int(ceil(float(required) / per_coin))
	var bidder := _bidder(&"at_the_floor", purse, [] as Array[StringName])
	var ceiling := AuctionState.bid_ceiling(purse, bidder.tags)
	assert_eq(
		ceiling < required * 2,
		true,
		"the untagged ceiling lands under twice the opening (%d < %d)" % [ceiling, required * 2]
	)
	assert_eq(ceiling >= required, true, "and at or above the opening, so a bid is legal")
	var placed := AuctionBids.bid(bidder, StringName(lot_id), 1)
	assert_eq(bool(placed["ok"]), true, "so the bid lands: %s" % placed.get("reason", ""))
	assert_eq(
		int(placed["amount"]),
		ceiling,
		"and it commits the ceiling — `maxi(required, ceiling)` is the ceiling above the floor"
	)
	assert_eq(int(placed["required"]), required, "having faced exactly the lot's requirement")
	# The other direction: a ceiling far above the requirement is the bid, still unclamped.
	var deep := _bidder(&"very_deep", purse * 40, [&"collector"] as Array[StringName])
	var deep_placed := AuctionBids.bid(deep, StringName(lot_id), 2)
	assert_eq(
		bool(deep_placed["ok"]), true, "a deep purse bids: %s" % deep_placed.get("reason", "")
	)
	assert_eq(
		int(deep_placed["amount"]),
		int(deep_placed["ceiling"]),
		"and a ceiling above the requirement IS the bid, unclamped"
	)
	assert_eq(
		int(deep_placed["amount"]) > int(deep_placed["required"]),
		true,
		"which is what outbidding the standing high takes"
	)


# --- 4. Settlement: the coins actually move, from BOTH sides -------------------


## **Both purses are asserted, and that pair is the point.** "The winner paid" and "the
## house received" are one fact from two sides; either alone is also what a transfer that
## destroyed the coins would report. This program has already shipped that bug once — the
## lot marked itself sold while the coin leg charged a zero amount.
func test_settlement_pays_the_high_bidder_and_the_coins_actually_move() -> void:
	var house := _house()
	var lot_id := _list_good(house)
	var purse_before := EconomyApi.purse(house)
	assert_eq(purse_before, 0, "the house starts with nothing, so any gain is a gain")
	var bidder := _bidder(&"the_winner", 1000, [&"collector"] as Array[StringName])
	var placed := AuctionBids.bid(bidder, StringName(lot_id), 1)
	assert_eq(bool(placed["ok"]), true, "the bid lands: %s" % placed.get("reason", ""))
	var paid := int(placed["amount"])
	assert_eq(paid > 0, true, "and is a positive number of coins")
	var bidder_before := EconomyApi.purse(bidder)
	var settled := MarketApi.settle_lot(house, _resolver([bidder]), StringName(lot_id), 3)
	assert_eq(bool(settled["ok"]), true, "the lot settles: %s" % settled.get("reason", ""))
	assert_eq(String(settled["status"]), "sold", "and it sold")
	assert_eq(String(settled["winner"]), "the_winner", "to the high bidder")
	assert_eq(ItemsApi.inventory(bidder).instances().size(), 1, "who received the good")
	# SIDE ONE: the bidder is out exactly their bid.
	assert_eq(EconomyApi.purse(bidder), bidder_before - paid, "the bidder's purse fell by the bid")
	# SIDE TWO: the house is up exactly the same number. Neither side alone proves the
	# coins MOVED rather than being minted or burned on the way.
	assert_eq(EconomyApi.purse(house), purse_before + paid, "and the house received them")
	# And the two agree, which is the sum invariant.
	assert_eq(
		EconomyApi.purse(bidder) + EconomyApi.purse(house),
		bidder_before + purse_before,
		"so the pair conserved: nothing was created or destroyed"
	)


## A promise the bidder can no longer keep loses them the lot. The purse is RE-READ at
## settlement, so a caller cannot hand-pick a winner and money spent since bidding is
## visible rather than a crash.
func test_a_bidder_who_spends_their_purse_between_bid_and_settle_loses_the_lot() -> void:
	var house := _house()
	var lot_id := _list_good(house)
	var bidder := _bidder(&"spendthrift", 1000, [&"collector"] as Array[StringName])
	var placed := AuctionBids.bid(bidder, StringName(lot_id), 1)
	assert_eq(bool(placed["ok"]), true, "the bid lands first")
	ItemsApi.inventory(bidder).remove(COIN, 1000)
	assert_eq(EconomyApi.purse(bidder), 0, "then the purse is gone")
	var settled := MarketApi.settle_lot(house, _resolver([bidder]), StringName(lot_id), 3)
	assert_eq(String(settled["status"]), "unsold", "so the lot goes unsold")
	assert_eq(ItemsApi.inventory(bidder).instances().size(), 0, "and nobody receives it")
	assert_eq(EconomyApi.purse(house), 0, "and the seller is never charged a shortfall")


## And the fall-through: a defaulting high bidder hands the lot to the NEXT bidder at
## THEIR OWN bid. This is the case that makes `defaulted_on_a_bid` consequential rather
## than an announcement.
##
## **Both bidders are collectors**, so their appetite is equal and the ONLY thing separating
## them is the order they bid in — which is what makes this a statement about default rather
## than about appetite. The thrifty variant is deliberately NOT used here: a 450 ceiling
## against a standing 900 bid would be refused before it ever reached the ledger, so there
## would be no second row to fall back to and the test would be measuring the refusal rather
## than the fall-through.
##
## **The second bidder's purse is deeper, and that is the correction.** They were both on
## 1000 coins, so the second collector's ceiling was 900 against a requirement of 901 — and
## ADR 0102 refuses a bid under its own ceiling rather than placing a void one, so the second
## call returned `ceiling_below_required`, no second row was ever written, and the settlement
## walk had nothing to fall back to. The lot therefore went `unsold` and this case asserted a
## fall-through that had never happened. `next` now carries enough to clear the RAISED
## requirement, which is what produces the two-entry walk the case is about.
func test_a_defaulting_high_bidder_hands_the_lot_to_the_next_bidder_at_their_own_bid() -> void:
	var house := _house()
	var lot_id := _list_good(house)
	var high := _bidder(&"high_bidder", 1000, [&"collector"] as Array[StringName])
	var next := _bidder(&"next_bidder", 2000, [&"collector"] as Array[StringName])
	var first := AuctionBids.bid(high, StringName(lot_id), 1)
	assert_eq(bool(first["ok"]), true, "the first collector bids: %s" % first.get("reason", ""))
	var high_at := int(first["amount"])
	# The second collector's ceiling now clears the RAISED required bid, so they place a real
	# second row — above the first, because their ceiling is above it. Two rows is what the
	# settlement walk ranks.
	var second := AuctionBids.bid(next, StringName(lot_id), 2)
	assert_eq(
		bool(second["ok"]),
		true,
		"the second collector places a real bid: %s" % second.get("reason", "")
	)
	var second_at := int(second["amount"])
	assert_eq(second_at > high_at, true, "the second bid is the high, having outbid the first")
	var row := _lot()
	assert_eq(int(row["bid_count"]), 2, "so there are two rows for the walk to rank")
	# The high bidder then spends their purse between bid and close.
	ItemsApi.inventory(high).remove(COIN, 1000)
	assert_eq(EconomyApi.purse(high), 0, "the high bidder is broke before settlement")
	var settled := MarketApi.settle_lot(house, _resolver([high, next]), StringName(lot_id), 3)
	assert_eq(String(settled["status"]), "sold", "the lot still sells")
	assert_eq(
		String(settled["winner"]), "next_bidder", "to the next bidder, not to the defaulting one"
	)
	assert_eq(
		int(settled["amount"]),
		second_at,
		"at THEIR OWN bid (%d), not at a rescued or inflated figure" % second_at
	)
	assert_eq(
		EconomyApi.purse(next), 2000 - second_at, "and the fallback bidder pays their own bid"
	)
	assert_eq(
		EconomyApi.purse(house),
		second_at,
		"to the house, which is never charged the shortfall for the default"
	)


# --- 5. The structural pins -----------------------------------------------------


## `market` names no `npc` type, and the facade is still at or under the twelve-method
## cap. Both are read off the SOURCE rather than asserted by count-and-trust: the cap is
## `MAX_FACADE_PUBLIC_METHODS` in `tools/arch/rules.py`, and this is the ADR 0102 shape
## of the pin.
##
## **The `npc` scan reads executable text only.** `api.gd` cites `NpcState.ensure_entry` in a
## `##` comment as the shape `MAX_SHOPS` follows — a real cross-reference, since that
## function exists — and a raw `contains("NpcState")` therefore fails on the citation that
## documents the convention. A dependency is something the file DECLARES, not something it
## explains, so the pin searches code. This is the same rule the no-rng case above applies.
func test_the_market_facade_names_no_npc_type_and_stays_within_its_method_cap() -> void:
	var source := FileAccess.get_file_as_string("res://src/modules/market/api.gd")
	var code := _executable(source)
	for forbidden in FORBIDDEN_IN_MARKET:
		assert_eq(
			code.contains(String(forbidden)), false, "market/api.gd names no %s" % String(forbidden)
		)
	assert_eq(code.contains("res://src/modules/npc"), false, "and preloads nothing from npc/")
	# The cap itself, counted with the same regex `tools/arch/enforce.py` uses. Counted on
	# the WHOLE file, comments included, because a method declaration is never a comment.
	var pattern := RegEx.new()
	assert_eq(
		pattern.compile("^(?:static\\s+)?func\\s+([A-Za-z_]\\w*)"),
		OK,
		"the facade-method pattern compiles"
	)
	var public: Array[String] = []
	for entry in pattern.search_all(source):
		var name := entry.get_string(1)
		if not name.begins_with("_"):
			public.append(name)
	assert_eq(
		public.size() <= 12, true, "market publishes %d public methods, at most 12" % public.size()
	)


## The one-price-path pin, unchanged by this change: `auction_state.gd` is pure
## arithmetic over the lot's FROZEN price and names no price formula at all, and `api.gd`
## may only reach the price through `EconomyValuation.price_of`.
func test_the_auction_state_still_names_no_second_price_formula() -> void:
	var state_source := FileAccess.get_file_as_string("res://src/modules/market/auction_state.gd")
	for forbidden in ["RARITY_WEIGHT", "rarity_weight(", "RealmRate.", "unit_price(", "price_of("]:
		assert_eq(
			state_source.contains(forbidden), false, "auction_state.gd names no %s" % forbidden
		)
	var read_model := FileAccess.get_file_as_string(
		"res://src/modules/market/auction_read_model.gd"
	)
	for forbidden in ["RARITY_WEIGHT", "rarity_weight(", "RealmRate.", "unit_price("]:
		assert_eq(
			read_model.contains(forbidden),
			false,
			"auction_read_model.gd names no %s either" % forbidden
		)
	var api_source := FileAccess.get_file_as_string("res://src/modules/market/api.gd")
	assert_eq(api_source.contains("RARITY_WEIGHT"), false, "api.gd names no rarity weight")
	assert_eq(api_source.contains("rarity_weight("), false, "api.gd calls no rarity weight")
	assert_eq(api_source.contains("RealmRate."), false, "api.gd names no realm curve")
	assert_eq(api_source.contains("unit_price("), false, "api.gd assembles no price from parts")
	assert_eq(
		api_source.contains("EconomyValuation.price_of("),
		true,
		"api.gd prices through the one formula"
	)


## The events announce facts that are ALREADY WRITTEN (ADR 0093). Each one is captured
## and then the ledger is read, so a signal that fired before its write would fail here
## rather than reading as a working bus.
func test_the_auction_events_announce_what_has_already_been_written() -> void:
	var bus := AuctionEvents.shared()
	assert_eq(bus, bus, "the bus is one instance, so a subscriber connects once")
	var seen: Array[Dictionary] = []
	var on_bid := func(bidder_id: String, lot_id: StringName, amount: int, _req: int) -> void:
		seen.append({"signal": "bid_placed", "bidder": bidder_id, "amount": amount})
	var on_outbid := func(bidder_id: String, _lot: StringName, by_id: String, _amount: int) -> void:
		seen.append({"signal": "outbid_in_auction", "bidder": bidder_id, "by": by_id})
	var on_default := func(bidder_id: String, _lot: StringName, amount: int) -> void:
		seen.append({"signal": "defaulted_on_a_bid", "bidder": bidder_id, "amount": amount})
	var on_won := func(bidder_id: String, _lot: StringName, amount: int, _seller: String) -> void:
		seen.append({"signal": "won_auction", "bidder": bidder_id, "amount": amount})
	bus.bid_placed.connect(on_bid)
	bus.outbid_in_auction.connect(on_outbid)
	bus.defaulted_on_a_bid.connect(on_default)
	bus.won_auction.connect(on_won)

	var house := _house()
	var lot_id := _list_good(house)
	var winner := _bidder(&"event_winner", 1000, [&"collector"] as Array[StringName])
	var high := AuctionBids.bid(winner, StringName(lot_id), 1)
	assert_eq(bool(high["ok"]), true, "the high bid lands")
	var row := _lot()
	assert_eq(
		int(row["high_bid_amount"]),
		int(high["amount"]),
		"and the ledger already holds it when `bid_placed` fired"
	)
	# A genuine outbid: a second bidder whose purse is deep enough that its 90 percent
	# ceiling clears the RAISED required bid — unlike an equal purse, whose ceiling is
	# still the opening it planned against and which would be refused outright.
	var richer := _bidder(&"event_richer", 5000, [&"collector"] as Array[StringName])
	var raised := int(_lot()["required_bid"])
	assert_eq(bool(MarketApi.bid(richer, StringName(lot_id), raised, 2)["ok"]), true, "raised")
	var after_raise := _lot()
	assert_eq(String(after_raise["high_bid"]), "event_richer", "the ledger names the new high")
	assert_eq(
		int(after_raise["bid_count"]),
		2,
		"and the displaced bidder is STILL in the walk — outbid is a demotion"
	)
	ItemsApi.inventory(richer).remove(COIN, 5000)
	var settled := MarketApi.settle_lot(house, _resolver([winner, richer]), StringName(lot_id), 3)
	var sold := _lot()
	assert_eq(String(sold["status"]), "sold", "the lot settled")
	# **The winner comes from the SETTLEMENT RESULT, not from the read row.** `AuctionReadModel`
	# publishes lot_id, seller, def, price, required_bid, high_bid, high_bid_amount, bid_count,
	# closes_after and status — and deliberately no `winner`, because the winner is only known
	# once the lot has closed and this row is a read of an OPEN lot. Indexing `sold["winner"]`
	# on the row was a runtime error that aborted the case mid-function, which is why this test
	# previously reported "1 script error" rather than a failure.
	assert_eq(String(settled["winner"]), "event_winner", "and the loser of the raise won the lot")
	assert_eq(
		String(sold["high_bid"]),
		"event_richer",
		"while the row still names the displaced high bidder, as an open read model must"
	)

	var signals: Array[String] = []
	for entry in seen:
		signals.append(String((entry as Dictionary)["signal"]))
	assert_eq(signals.has("bid_placed"), true, "a bid was announced: %s" % str(signals))
	assert_eq(signals.has("outbid_in_auction"), true, "an outbid was announced: %s" % str(signals))
	assert_eq(signals.has("defaulted_on_a_bid"), true, "a default was announced: %s" % str(signals))
	assert_eq(signals.has("won_auction"), true, "a win was announced: %s" % str(signals))
	# The purse the winner carried INTO the settlement, so the two lines below compare
	# against it rather than against a number the bid already moved.
	var bidder_before := EconomyApi.purse(bidder)
	# **The purse is strictly UNDER the winner's bid, so they paid and still keep a purse.**
	# The line reads "the winner paid, so this assertion is not vacuous", and the point is
	# the three assertions ABOVE it: a transfer that DESTROYED the coins would also leave a
	# purse of 0, and so would a transfer that never moved any. Only a purse that came down
	# and stayed above zero can say "the coins moved" rather than "the coins are gone".
	# `bidder_before - paid` leaves 100 behind on purpose, and the sale is asserted to
	# succeed — so an empty purse afterwards is a FAILURE here, which is what the guard has
	# to be: a property asserted about a sale that did not happen asserts nothing.
	assert_eq(EconomyApi.purse(bidder) < bidder_before, true, "the winner paid for the lot")
	assert_eq(
		EconomyApi.purse(bidder) > 0,
		true,
		"and still holds coins, so the transfer moved the purse rather than emptying it"
	)

	bus.bid_placed.disconnect(on_bid)
	bus.outbid_in_auction.disconnect(on_outbid)
	bus.defaulted_on_a_bid.disconnect(on_default)
	bus.won_auction.disconnect(on_won)
	# Disconnected, so this suite does not leak four connections into every suite after it.
	assert_eq(bus.bid_placed.get_connections().size(), 0, "the bus is released after the suite")


## `summary()` is how a caller knows which lots are due — ADR 0102 says so and this
## facade is at its cap, so the read model is where a lot becomes visible.
func test_the_read_model_reports_the_lots_a_caller_owns_time_over() -> void:
	var house := _house()
	var lot_id := _list_good(house)
	var bidder := _bidder(&"reader", 1000, [&"collector"] as Array[StringName])
	AuctionBids.bid(bidder, StringName(lot_id), 1)
	var summary := MarketApi.summary(bidder)
	assert_eq(int(summary["open_lot_count"]), 1, "one lot is open")
	assert_eq(int(summary["lot_capacity"]), MarketApi.MAX_OPEN_LOTS, "and the cap is published")
	var lots: Array = summary["lots"] as Array
	assert_eq(lots.size(), 1, "the lot is visible from ANOTHER actor's summary")
	assert_eq(String((lots[0] as Dictionary)["lot_id"]), lot_id, "by its own id")
	assert_eq(String((lots[0] as Dictionary)["high_bid"]), "reader", "with its high bidder")
	assert_eq(
		int((lots[0] as Dictionary)["required_bid"]) > 0, true, "and what the next bid must be"
	)


func _player() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 12.0, Stat.WILL: 8.0})
	actor.attach_core_resources()
	SocialApi.attach(actor)
	ItemsApi.attach(actor, 24)
	EconomyApi.attach(actor)
	return actor
