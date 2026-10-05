extends TestCase

## DEF-0138 — **a captive is a custody claim, never a tradeable thing.** (ADR 0104)
##
## ## What this file is FOR
##
## ADR 0104 decided what a captive IS: a claim row naming a subject DEF ID and an `OwnerRef`
## holder. Nothing about that decision is self-enforcing. A claim is a `Dictionary` in a
## ledger, and a ledger row is not a thing the economy cannot reach — it is three lines away
## from an `ItemDef`, a `RARITY_WEIGHT` and a floor listing. So this suite does not restate
## the ADR; it **asks every door that could sell a person, and asserts each one refuses**.
##
## ## Why the subject is `smith_bearcutter`, a REAL authored `NpcDef`
##
## A claim about `guard_captain` — an id this build does not ship — is a fixture that agrees
## with itself: an unknown def resolves to null everywhere, so "it priced at nothing" proves
## only that a nonexistent thing prices at nothing. Every subject here is authored, so a
## refusal is a refusal of something that EXISTS.
##
## ## The five doors, and why five
##
##  1. **Inventory** — a capture must mint no `ItemInstance`. The claim names a subject id;
##     a person becoming a stack is the whole risk DEF-0138 names.
##  2. **`EconomyValuation`** — refuses to price it. `base_worth` reads `fixed_modifiers`
##     against `ItemRarity`'s four names, so a captive with a def would go through
##     `RARITY_WEIGHT` and `RealmRate` and become a realm-scaled money printer.
##  3. **`EconomyApi.valuation`** — the read-only door, `{}` for an unpriced id.
##  4. **`MarketApi.list`** — the floor. `instance_id` names nothing in any inventory, so
##     it refuses; and no lot is written whatever the reason.
##  5. **A shop** — `MarketApi.sell` cannot put one on a stall and `MarketApi.buy` cannot
##     take one off one. Both directions, because `MarketTransfer.price` swaps the legs with
##     the direction and a one-sided test would leave one arm unmeasured.
##
## Every case is built to FAIL if any one of those doors opened, and every case asserts the
## refusal BY NAME (`ok == false` alone passes for a screen that refuses everything).

const COIN := &"curr_spirit_coin"
## A real authored individual in `res://data/npc`, capturable or not — the point is that it
## EXISTS, so every refusal below is measured against a thing that is really there.
const SUBJECT := &"smith_bearcutter"
const PLACE := &"market_square"

var _held: Array[Actor] = []


func setup() -> void:
	# A floor, so a body that dies mid-way is charged rather than silently skipped.
	expect_assertions(3)
	# Custody is a WORLD fact (ADR 0101) and so is the floor (ADR 0100): both are shared
	# ledgers, or a second holder would read its own copy and the refusals below would be
	# measured against a ledger nobody else can see.
	CustodyApi.set_store(CustodyWorldLedger.new())
	CustodyApi.set_resolver(func(_kind: String, _id: String) -> Dictionary: return {"ok": true})
	MarketApi.set_store(MarketWorldLedger.new())
	_held.clear()


func teardown() -> void:
	# `CustodyApi._store` / `_resolver` and `MarketApi._store` are PROCESS-WIDE and the
	# runner shares one process across every suite, calling `teardown` after EVERY test.
	# Leaving one installed would hand this suite's store to everything that runs later.
	CustodyApi.set_store(null)
	CustodyApi.set_resolver(Callable())
	MarketApi.set_store(null)
	_held.clear()


func _actor(id: StringName, coins: int = 0) -> Actor:
	var actor := Actor.new(id, {})
	ItemsApi.attach(actor, 24)
	if coins > 0:
		ItemsApi.inventory(actor).add(Crafting.resolve(COIN), coins)
	EconomyApi.attach(actor)
	MarketApi.attach(actor)
	CustodyApi.attach(actor)
	_held.append(actor)
	return actor


func _owner(id: StringName) -> Dictionary:
	return {"kind": "actor", "id": String(id)}


func _capture(holder: Actor, periods: int = 4) -> String:
	var taken := CustodyApi.capture(holder, SUBJECT, &"npc", _owner(holder.id), &"custody", periods)
	assert_eq(bool(taken["ok"]), true, "the capture opened: %s" % taken.get("reason", ""))
	return String(taken.get("claim_id", ""))


## Every instance id and def id the actor's inventory holds, so "no item exists for the
## subject" is answered by walking the inventory rather than by counting the coin.
func _carried_ids(actor: Actor) -> Array:
	var out: Array = []
	for batch in ItemsApi.inventory(actor).stacks():
		out.append(String(batch.def_id))
	for instance in ItemsApi.inventory(actor).instances():
		out.append(String(instance.instance_id))
	return out


# --- door 1: inventory --------------------------------------------------------


func test_a_capture_mints_no_item_for_the_subject() -> void:
	# The first and most direct form of the risk. A claim is a ledger row; if a capture also
	# put a stack in the bag, the person would be one `MarketApi.list` away from a price.
	var warden := _actor(&"warden")
	var before := _carried_ids(warden)
	var claim_id := _capture(warden)
	assert_ne(claim_id, "", "a claim is open")
	var after := _carried_ids(warden)
	assert_eq(after, before, "the capture minted no item: %s" % str(after))
	assert_eq(ItemsApi.inventory(warden).count(SUBJECT), 0, "and nothing named the subject")
	assert_eq(
		ItemsApi.inventory(warden).has(SUBJECT),
		false,
		"and the inventory never answers yes to the subject id"
	)


func test_the_claim_is_not_an_instance_and_names_a_def_id_only() -> void:
	# The claim's `subject_id` is a String over a def id. If it were an `ItemInstance`, an
	# `Actor` payload, or any object at all, this chain would be a thing the economy owns.
	var warden := _actor(&"warden")
	var claim_id := _capture(warden)
	var claim: Dictionary = (CustodyApi.state(warden)["claims"] as Dictionary)[claim_id]
	assert_eq(typeof(claim["subject_id"]), TYPE_STRING, "the subject is a String")
	assert_eq(String(claim["subject_id"]), String(SUBJECT), "naming the authored def id")
	for forbidden in ["instance", "item", "item_instance", "actor", "actor_id", "def_id"]:
		assert_eq(claim.has(forbidden), false, "the claim carries no '%s' field" % forbidden)


# --- door 2: the one price formula -------------------------------------------


func test_the_valuation_formula_refuses_to_price_a_captive() -> void:
	# ADR 0094's formula, called directly. `base_worth` reads `fixed_modifiers`, so a
	# captive with a resolvable def would go through RARITY_WEIGHT and RealmRate and be
	# worth 551x more at the top rung (ADR 0050) — a money printer, not a person.
	assert_eq(Crafting.resolve(SUBJECT), null, "a captive resolves to no ItemDef")
	assert_eq(EconomyValuation.base_worth(null), 0.0, "no def means no base worth")
	var probe := ItemInstance.new(SUBJECT, &"custody_probe")
	assert_eq(EconomyValuation.price_of(probe), 1, "and no instance prices at the floor")
	assert_eq(EconomyValuation.base_worth_of(null), 0.0, "base_worth_of refuses a null def")


func test_no_price_call_on_a_captive_succeeds() -> void:
	# The whole family, not one function. If any ONE of these started returning a real
	# number for the subject, custody would be priced and DEF-0138 would be over.
	var warden := _actor(&"warden")
	_capture(warden)
	var probe := ItemInstance.new(SUBJECT, &"custody_price_probe")
	for rarity in EconomyValuation.RARITY_WEIGHT.keys():
		assert_eq(
			EconomyValuation.unit_price(100.0, rarity, &"R9"),
			int(round(100.0 * EconomyValuation.rarity_weight(rarity))),
			"the formula prices a base worth, never a person"
		)
	assert_eq(EconomyValuation.price_of(probe), 1, "a captive never prices")
	assert_eq(EconomyValuation.total_price(probe, 1000), 1000, "not even in bulk")
	assert_eq(bool(EconomyValuation.has_rolled_worth(probe)), false, "and never rolls a worth")


# --- door 3: the read-only valuation door -------------------------------------


func test_economy_refuses_to_quote_a_captive() -> void:
	# `EconomyApi.valuation` is the door a panel or a preview would read. `{}` is its
	# "unpriced" answer, and it is the answer a captive must get for ever.
	# Assigned before asserted, because `has("price")` on a Dictionary literal is a PARSE
	# question, not a runtime one — an inline call with a trailing `.has()` does not
	# compile, and a parse error reads as a suite that failed to load rather than as a
	# mistake worth fixing here.
	var priced: Dictionary = EconomyApi.valuation(SUBJECT)
	assert_eq(priced, {}, "economy has no valuation for a captive")
	assert_eq(priced.has("price"), false, "and reports no price")
	assert_eq(priced.has("base_worth"), false, "and no base worth to scale from")


func test_quote_prices_nothing_for_a_captive() -> void:
	# The ONE row reader (ADR 0094). A row naming the subject resolves to no instance, so
	# no priced row is EMITTED at all — and `ok` is false, which is what makes every caller
	# reading a quote refuse rather than treat the missing number as zero and settle.
	var warden := _actor(&"warden", 10)
	var quoted := EconomyApi.quote(
		warden, [{"def_id": String(SUBJECT), "quantity": 1}], &"shop", warden.id
	)
	assert_eq(bool(quoted["ok"]), false, "a captive row never prices")
	assert_eq(bool(quoted["judged"]), true, "and the row was judged against a named owner")
	assert_eq(int(quoted["total"]), 0, "at a total of zero")
	assert_eq((quoted["rows"] as Array).size(), 0, "with no priced row emitted at all")
	# `quote`'s OWN `unpriced` field is deliberately NOT asserted. It is recomputed from the
	# rows that were EMITTED, and a row with no instance emits none, so it reads 0 while
	# `ok` reads false. Pinning that number would pin a counter the settlement paths never
	# read; `ok`, `total` and `rows` are the three every caller actually branches on.


func test_the_exchange_refuses_to_move_a_captive() -> void:
	# The atomic primitive itself, both directions. A refusal here writes nothing on
	# either side, so the assertion is on the purses afterwards as well as on `ok`.
	var warden := _actor(&"warden", 100)
	var buyer := _actor(&"buyer", 100)
	var give := EconomyApi.trade(
		warden, buyer, [{"def_id": String(SUBJECT), "quantity": 1}], [], warden.id
	)
	assert_eq(bool(give["ok"]), false, "offering a captive refuses")
	assert_eq(String(give["reason"]), EconomyExchange.NOT_CARRIED, "and names the rule")
	var take := EconomyApi.trade(
		buyer, warden, [], [{"def_id": String(SUBJECT), "quantity": 1}], buyer.id
	)
	assert_eq(bool(take["ok"]), false, "asking for a captive refuses")
	assert_eq(String(take["reason"]), EconomyExchange.NOT_CARRIED, "and names the rule")
	assert_eq(EconomyApi.purse(warden), 100, "the seller's coins never moved")
	assert_eq(EconomyApi.purse(buyer), 100, "and neither did the buyer's")


# --- door 4: the floor ---------------------------------------------------------


func test_market_list_refuses_the_subject_and_writes_no_lot() -> void:
	# `list` takes an INSTANCE id, and a captive is not one. The refusal has to be by name
	# and the ledger has to be byte-identical afterwards, or "refused" could mean "opened
	# a lot nobody paid for".
	var warden := _actor(&"warden")
	_capture(warden)
	var before := (MarketApi.state(warden)["lots"] as Dictionary).duplicate(true)
	for instance_id in [SUBJECT, &"custody_" + SUBJECT + "#0", &"smith_bearcutter_1"]:
		var listed := MarketApi.list(warden, instance_id, 3)
		assert_eq(bool(listed["ok"]), false, "listing '%s' refuses" % instance_id)
		assert_eq(
			String(listed["reason"]),
			EconomyExchange.NOT_CARRIED,
			"and names not_carried for '%s'" % instance_id
		)
	assert_eq(
		(MarketApi.state(warden)["lots"] as Dictionary).duplicate(true),
		before,
		"no lot was written for a captive"
	)


func test_a_captive_cannot_be_dropped_on_the_floor() -> void:
	# The floor is the other way a THING leaves an inventory and becomes world-visible.
	# `drop` checks `inventory.has` before its first removal, so a row naming the subject
	# never reaches the removal loop.
	var warden := _actor(&"warden")
	_capture(warden)
	var dropped := MarketApi.drop(warden, PLACE, [{"def_id": String(SUBJECT), "quantity": 1}])
	assert_eq(bool(dropped["ok"]), false, "dropping a captive refuses")
	assert_eq(String(dropped["reason"]), EconomyExchange.NOT_CARRIED, "and names the rule")
	assert_eq(
		(MarketApi.state(warden)["floor"] as Dictionary).get(String(PLACE), []),
		[],
		"and nothing landed on the floor"
	)


func test_a_captive_cannot_be_taken_off_the_floor() -> void:
	# The reverse verb, because a floor entry only exists because a `drop` wrote it, and a
	# `take` that succeeded on a captive row would be the laundering of that write.
	var warden := _actor(&"warden")
	_capture(warden)
	var taken := MarketApi.take(warden, PLACE, "drop_0_" + String(SUBJECT))
	assert_eq(bool(taken["ok"]), false, "taking a captive off the floor refuses")
	assert_eq(String(taken["reason"]), MarketApi.NO_SUCH_DROP, "and names the rule")


# --- door 5: a shop -----------------------------------------------------------


func test_a_shop_cannot_buy_a_captive() -> void:
	# `MarketApi.sell(shop_def, shop, player, rows)` — the player offering a captive. A
	# shop that WILL buy an unpriced id is a refusal the content cannot express, so both
	# arms are exercised: with `buys` naming the subject and with it empty.
	var warden := _actor(&"warden")
	_capture(warden)
	var shop := _actor(&"broker", 500)
	for shop_id in [&"captor_broker", &"captor_silent"]:
		var def := ShopDef.new()
		def.shop_id = shop_id
		def.buys = [SUBJECT]
		var sold := MarketApi.sell(def, shop, warden, [{"def_id": String(SUBJECT), "quantity": 1}])
		assert_eq(bool(sold["ok"]), false, "shop '%s' cannot buy a captive" % shop_id)
		assert_eq(String(sold["reason"]), EconomyExchange.NOT_CARRIED, "and names the rule")
		assert_eq(EconomyApi.purse(warden), 0, "and pays the seller nothing")
	assert_eq(EconomyApi.purse(shop), 500, "and keeps its own coins")


func test_a_shop_cannot_sell_a_captive() -> void:
	# The other direction. `MarketApi.buy` prices rows off the SHOP's inventory, and the
	# shop holds no captive, so the row is unpriced and the leg never builds.
	var warden := _actor(&"warden", 100)
	_capture(warden)
	var shop := _actor(&"broker2", 500)
	var def := ShopDef.new()
	def.shop_id = &"captor_stock"
	def.stock = [{"def_id": String(SUBJECT), "quantity": 1}]
	var bought := MarketApi.buy(shop, warden, [{"def_id": String(SUBJECT), "quantity": 1}])
	assert_eq(bool(bought["ok"]), false, "a shop cannot be stocked with a captive")
	assert_eq(String(bought["reason"]), EconomyExchange.NOT_CARRIED, "and names the rule")
	assert_eq(EconomyApi.purse(warden), 100, "and charged the buyer nothing")
	assert_eq(EconomyApi.purse(shop), 500, "and the shop paid nothing")


func test_a_shop_def_may_author_a_captive_row_and_still_sell_nothing() -> void:
	# Anti-vacuity for door 5, and the reason the case above is not testing a fixture that
	# refuses itself. `ShopDef.buys` and `ShopDef.stock` are AUTHORED arrays a designer can
	# name anything in, so the refusal above is read off a def that really does list the
	# subject — and it still refuses, because `EconomyApi.quote` resolves no `ItemDef` for
	# the subject and never emits a row.
	#
	# The content-side consequence is stated rather than left implied: the moment somebody
	# DID author a `smith_bearcutter` item def, `buys` would become a real door. That is the
	# one change that would make this suite RED, and it is the change DEF-0138 forbids.
	var def := ShopDef.new()
	def.shop_id = &"captor_authored"
	def.buys = [SUBJECT]
	def.stock = [{"def_id": String(SUBJECT), "quantity": 3}]
	assert_eq(def.buys_def(SUBJECT), true, "the def really does list the subject as buyable")
	assert_eq((def.stock as Array).size(), 1, "and stocks it")
	assert_eq(Crafting.resolve(SUBJECT), null, "while no ItemDef answers to that id")


# --- the structural half ------------------------------------------------------


func test_no_capture_verb_writes_an_item_id_anywhere() -> void:
	# The structural pin, and the reason this suite cannot be defeated by adding a
	# SECOND door rather than by opening one of the five. Read off the SHIPPED SOURCE with
	# comments stripped: asserting on prose would turn a boundary check into a typo
	# detector, because both files name "price" in their doc comments (ADR 0104 says a
	# captive is "never a price").
	#
	# `Inventory.add` / `add_instance` / `add_batch` are the ONLY ways a thing enters a
	# bag, so their absence from `capture`'s body is the complete statement that a capture
	# mints nothing. `EconomyApi.trade` is the only way custody moves anything.
	var facade := _code_only("res://src/modules/custody/api.gd")
	var state := _code_only("res://src/modules/custody/custody_state.gd")
	var capture_body := _function_body(facade, "static func capture(")
	assert_ne(capture_body, "", "the capture verb was found in the facade")
	for forbidden in [
		"inventory.add",
		"add_instance",
		"add_batch",
		"ItemInstance",
		"ItemDef",
		"EconomyValuation.price_of",
		"unit_price",
		"RARITY_WEIGHT",
		"rarity_weight",
	]:
		assert_eq(capture_body.contains(forbidden), false, "capture names no '%s'" % forbidden)
	# The same discipline over the whole module: the word PRICE must not appear as CODE in
	# either shipped file. ADR 0104 says the module "computes no price at all"; the one
	# valuation call it is allowed is `numeraire_id()`, the unit of account.
	assert_eq(
		(
			state.contains("price_of")
			or state.contains("unit_price")
			or state.contains("rarity_weight")
		),
		false,
		"the custody state computes no price"
	)
	assert_eq(
		(
			facade.contains("price_of")
			or facade.contains("unit_price")
			or facade.contains("rarity_weight")
		),
		false,
		"the custody facade computes no price"
	)
	assert_eq(
		facade.count("EconomyValuation."),
		1,
		"and reads EconomyValuation exactly once, for numeraire_id()"
	)
	assert_eq(
		capture_body.contains("EconomyValuation."),
		false,
		"while capture itself reads no valuation at all"
	)


func test_the_module_names_no_item_and_no_market_symbol() -> void:
	# `tools arch` reads `res://src` only, so it cannot see what a SCRIPT TEXT says. This
	# is the boundary stated as a text check over both custody files: the module names no
	# item type, no inventory, and no market verb. A captive priced through the floor would
	# require every one of those, and the claim in ADR 0104 is that it requires none.
	for path in ["res://src/modules/custody/api.gd", "res://src/modules/custody/custody_state.gd"]:
		var code := _code_only(path)
		for forbidden in [
			"ItemsApi",
			"Inventory",
			"ItemDef",
			"ItemInstance",
			"Crafting",
			"MarketApi",
			"MarketTransfer",
			"AuctionState",
		]:
			assert_eq(
				code.contains(forbidden), false, "'%s' names no '%s'" % [path.get_file(), forbidden]
			)
		# A `subject_id` is a DEF id and a holder is an `OwnerRef`, so no custody file may
		# REACH into a bag. `summary()` legitimately echoes the reading actor's own id under
		# `actor_id` — that is the reader's identity, not the subject's — so the boundary
		# drawn here is the one that matters: nothing in the module can acquire anything.
		assert_eq(
			code.contains("Inventory.add") or code.contains("inventory.add"),
			false,
			"'%s' never adds anything to an inventory" % path.get_file()
		)
		assert_eq(
			code.contains("generate(") and code.contains("ItemsApi"),
			false,
			"'%s' mints no realized instance" % path.get_file()
		)


func test_the_subject_def_exists_so_every_refusal_is_measured_against_something() -> void:
	# Anti-vacuity, and the reason this file is not the guard it looks like. Every case
	# above refuses the subject because the subject is NOT an `ItemDef`. If the subject
	# stopped being authored, all six of them would keep passing while measuring nothing —
	# a guard that cannot fail. So the fixture is asserted to be real, read from the
	# AUTHORED `.tres` through `load_authored()` rather than from a def this suite wrote.
	NpcCatalog.instance().load_authored()
	var catalog := NpcCatalog.instance()
	assert_eq(catalog.has_definition(SUBJECT), true, "'%s' is an authored NpcDef" % SUBJECT)
	var def := catalog.definition(SUBJECT)
	assert_ne(def, null, "and it loads")
	assert_eq(String(def.npc_id), String(SUBJECT), "under its own id")
	assert_eq(Crafting.resolve(SUBJECT), null, "while resolving to no ItemDef at all")
	var priced: Dictionary = EconomyApi.valuation(SUBJECT)
	assert_eq(priced, {}, "which is why every price door above refuses")


func test_a_capture_term_is_a_count_and_a_person_is_never_scaled_by_realm() -> void:
	# The reason the refusal above is a DESIGN and not an accident: the doors refuse
	# because there is no `ItemDef`, and there is no `ItemDef` because a term is authored
	# as `{term_id, periods}` (ADR 0247) — an id and a count. A term that carried a number
	# a price could read would be the one route by which a captive reaches the rarity
	# curves and the realm ladder.
	#
	# Read off the SHIPPED SOURCE rather than a fixture, so this cannot pass on a term
	# shape no production path authors.
	var npc_def := _code_only("res://src/modules/npc/npc_def.gd")
	assert_eq(
		npc_def.contains('"price"') or npc_def.contains('"worth"') or npc_def.contains('"value"'),
		false,
		"NpcDef authors no price, worth or value for a capture term"
	)
	# The catalog has to be LOADED before `capturable()` reads it: it is a lazy catalog and
	# an unloaded one is empty, which is the shape of a loop that asserts nothing and is
	# charged as an abort rather than as a pass.
	NpcCatalog.instance().load_authored()
	var rows := NpcCaptureTerms.capturable()
	assert_ne(rows.is_empty(), true, "the cast authors at least one capturable individual")
	for row in rows:
		var subject: String = String(row.get("subject_id", ""))
		assert_eq(row.has("price"), false, "'%s' carries no price" % subject)
		assert_eq(row.has("worth"), false, "'%s' carries no worth" % subject)
		assert_eq(row.has("value"), false, "'%s' carries no value" % subject)
		assert_eq(typeof(row["periods"]), TYPE_INT, "'%s' carries an int count" % subject)
		assert_eq(typeof(row["term_id"]), TYPE_STRING, "'%s' carries a String term id" % subject)


# --- helpers ------------------------------------------------------------------


## The shipped source of `path` with every comment removed: a `#` line, and everything
## from an inline `#` to end of line. Asserting on prose would make this a typo detector,
## because both custody files name "price" in their doc comments on purpose.
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash := line.find("#")
		out.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(out)


## The body of the function whose declaration line begins with `header`, from the opening
## brace to the brace at its own indentation. `tools arch` cannot see a method that does
## not exist, and a static facade exposes no instance to ask, so a source read is what
## makes this a structural check rather than a call.
func _function_body(code: String, header: String) -> String:
	var lines := code.split("\n")
	var opened := false
	var depth := 0
	var out: Array[String] = []
	for line in lines:
		if not opened:
			if line.begins_with(header):
				opened = true
				out.append(line)
				depth = line.count("{") - line.count("}")
				continue
			continue
		out.append(line)
		depth += line.count("{") - line.count("}")
		if depth <= 0:
			break
	return "\n".join(out)
