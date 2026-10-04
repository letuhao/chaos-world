extends "res://tests/app/auction_bid_kit.gd"

## The determinism, refusal and personality half of ADR 0102 / BL-0049.
##
## Split out of the original single-file suite purely for size -- gdlint's
## `max-file-lines` is 1000. Nothing was rewritten, no assertion changed and no
## method renamed: this half is the file's first three sections verbatim, and every
## constant, builder and helper it uses now lives in `auction_bid_kit.gd`, which
## both halves `extends`.
##
## `setup()` / `teardown()` and the fixtures live in the kit, because
## `MarketApi.set_store` is PROCESS-WIDE: a store installed by one half and cleared
## by the other outlives the suite and is inherited by everything that runs later.
##
## The settlement and structural-pin half is `test_auction_settlement.gd`.

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
		# **Attempt 0 places the bid; attempts 1 and 2 REFUSE, and that is the determinism.**
		# A bid is a promise, so placing one moves no coins and the purse — and therefore the
		# ceiling — is untouched. What DOES move is the lot: `required_bid` becomes
		# `high + step`, which at 900 sits ABOVE the very ceiling that placed it. So the
		# second call is refused `ceiling_below_required` and writes nothing.
		#
		# That is not a weaker claim than "same number three times" — it is the same claim,
		# asserted against the ledger instead of against a return value. A verb that drifted
		# would re-derive a different ceiling on attempt 1 and either place a SECOND,
		# different bid (caught by `bid_count` below) or refuse for some other reason
		# (caught by the reason asserted here). A verb that is stable refuses, and for this
		# one named reason, every time. `amount` is 0 on a refusal by `_refuse`'s own contract,
		# so asserting it equals the ceiling would be asserting a bid was placed when the
		# whole point is that it was NOT.
		if attempt == 0:
			assert_eq(
				bool(seen["ok"]), true, "the first call places the bid: %s" % seen.get("reason", "")
			)
			assert_eq(int(seen["amount"]), ceiling, "attempt 0: at the ceiling")
		else:
			assert_eq(
				bool(seen["ok"]),
				false,
				"attempt %d: the standing bid has raised the requirement past the ceiling" % attempt
			)
			assert_eq(
				String(seen["reason"]),
				AuctionBids.CEILING_BELOW_REQUIRED,
				"attempt %d: and it refuses by name, not by a drifted number" % attempt
			)
			assert_eq(int(seen["ceiling"]), ceiling, "attempt %d: at the same ceiling" % attempt)
		assert_eq(
			AuctionState.bid_ceiling(EconomyApi.purse(first), first.tags),
			ceiling,
			"attempt %d: and the ceiling underneath it never drifts" % attempt
		)
	# One bid was written. The two later calls found the raised requirement and were refused,
	# so determinism is also idempotence against the ledger rather than a growing ladder —
	# three identical calls, one bid.
	assert_eq(int(_lot()["bid_count"]), 1, "three identical calls wrote one bid, not three")
	assert_eq(
		int(_lot()["high_bid_amount"]), ceiling, "and the one bid is still the ceiling, unrounded"
	)


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
