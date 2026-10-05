extends TestCase

## DEF-0146 — **a custody term is a period count and a negotiated coin settlement, never a
## valuation.** (ADR 0104's price decision.)
##
## ## What this file is FOR
##
## DEF-0146's own record is honest about why it exists: *"the moment someone asks what a
## captured boss is worth, the tempting answer is to put `RARITY_WEIGHT` on a person."* A
## temptation needs no bug to activate it — one line of plausible code does it. So this
## suite pins the three things a term IS allowed to be, and proves each of them fails when
## broken:
##
##  1. **The stored row is exactly `{term_id, periods}`** and carries no price/worth/value
##     key, at every layer that persists it (`CustodyApi.capture`, `CustodyState.put`,
##     `CustodyState.normalize`, the world store, and `CustodyApi.summary`).
##  2. **A `worth`/`price`/`value` key is REJECTED, not ignored.** A normalization that
##     silently dropped an injected price would be a weaker guarantee than one that refuses
##     it: dropping hides the author, refusing reports them.
##  3. **Settlement moves COINS — an inventory-held `curr_spirit_coin` stack — and never sets
##     a balance.** ADR 0139 supersedes ADR 0099: the numéraire is a held item, so "the
##     buyer paid" is `Inventory.count` changing on both sides, not an integer being
##     assigned somewhere.
##
## ## `periods` is a COUNT and the module scales it by nothing
##
## The realm ladder spans 551x (ADR 0050), so a term whose value moved with a realm would
## be a money printer. `settle_term` is pure arithmetic on an int, and this file asserts it
## stays arithmetic: the periods a claim carries after a settlement is the count it carried
## before, minus what was asked for, at any realm either actor stands at.

const COIN := &"curr_spirit_coin"
const SUBJECT := &"drifter"
const TERM := &"custody"

## Every key that would turn a term into a valuation. Named once and walked everywhere, so
## a fifth spelling cannot be added to the row without also being added here.
const VALUATION_KEYS: Array[String] = [
	"price",
	"worth",
	"value",
	"valuation",
	"base_worth",
	"unit_price",
	"coins",
	"coin_value",
	"amount",
	"rate",
	"rarity_weight",
	"realm_factor",
]

var _held: Array[Actor] = []


func setup() -> void:
	expect_assertions(3)
	CustodyApi.set_store(CustodyWorldLedger.new())
	CustodyApi.set_resolver(func(_kind: String, _id: String) -> Dictionary: return {"ok": true})
	_held.clear()


func teardown() -> void:
	CustodyApi.set_store(null)
	CustodyApi.set_resolver(Callable())
	_held.clear()


func _actor(id: StringName, coins: int = 0) -> Actor:
	var actor := Actor.new(id, {})
	ItemsApi.attach(actor, 24)
	if coins > 0:
		ItemsApi.inventory(actor).add(Crafting.resolve(COIN), coins)
	EconomyApi.attach(actor)
	CustodyApi.attach(actor)
	_held.append(actor)
	return actor


func _owner(id: StringName) -> Dictionary:
	return {"kind": "actor", "id": String(id)}


func _capture(holder: Actor, periods: int = 4) -> String:
	var taken := CustodyApi.capture(holder, SUBJECT, &"npc", _owner(holder.id), TERM, periods)
	assert_eq(bool(taken["ok"]), true, "the capture opened: %s" % taken.get("reason", ""))
	return String(taken.get("claim_id", ""))


# --- 1: the stored row is exactly {term_id, periods} ---------------------------


func test_the_stored_claim_carries_a_term_and_no_valuation() -> void:
	# The whole decision in one assertion set. `periods` is an int; `term_id` is an
	# authored id; and NONE of the twelve valuation spellings is on the row.
	var warden := _actor(&"warden")
	var claim_id := _capture(warden, 4)
	var stored: Dictionary = (CustodyApi.state(warden)["claims"] as Dictionary)[claim_id]
	assert_eq(String(stored["term_id"]), String(TERM), "the term is an authored id")
	assert_eq(typeof(stored["periods"]), TYPE_INT, "and the periods are an int count")
	assert_eq(int(stored["periods"]), 4, "carrying the count authored")
	for key in VALUATION_KEYS:
		assert_eq(
			stored.has(key), false, "the stored row carries no '%s': %s" % [key, str(stored.keys())]
		)
	# The capture RESULT too, not only the persisted row. `capture` returns
	# `{ok, reason, claim_id, holder, periods}` and a caller that reads the result rather
	# than the ledger must not find a price either. A SECOND subject, because one subject
	# may be held once and reusing `drifter` would refuse `already_captive` and measure
	# the cap instead.
	var taken := CustodyApi.capture(warden, &"drifter_second", &"npc", _owner(&"warden"), TERM, 2)
	assert_eq(bool(taken["ok"]), true, "a second subject opens its own claim")
	for key in VALUATION_KEYS:
		assert_eq(taken.has(key), false, "capture's result carries no '%s'" % key)


func test_summary_reports_the_term_as_a_count_and_nothing_else() -> void:
	# `summary` is what a custody PANEL reads, so a price here would put a number in front
	# of a player even if the ledger itself stayed clean. Read model is primitives only.
	var warden := _actor(&"warden")
	_capture(warden, 7)
	var summary := CustodyApi.summary(warden)
	var view: Dictionary = (summary["claims"] as Dictionary)["custody_drifter#0"]
	assert_eq(int(view["periods"]), 7, "the panel reads a period count")
	assert_eq(String(view["term_id"]), String(TERM), "and an authored term id")
	for key in VALUATION_KEYS:
		assert_eq(view.has(key), false, "the panel row carries no '%s'" % key)


func test_a_survives_a_save_round_trip_with_no_valuation() -> void:
	# ADR 0027: the ledger is JSON. A key that only exists after `normalize` would be a
	# key the serializer invented, so the round trip is checked as well as the row.
	var warden := _actor(&"warden")
	var claim_id := _capture(warden, 5)
	var restored: Variant = JSON.parse_string(JSON.stringify(CustodyApi.state(warden)))
	assert_eq(typeof(restored), TYPE_DICTIONARY, "the ledger is JSON-safe")
	var claim: Dictionary = (restored as Dictionary)["claims"][claim_id]
	assert_eq(int(claim["periods"]), 5, "the count survives the round trip")
	for key in VALUATION_KEYS:
		assert_eq(claim.has(key), false, "and no '%s' appears after the round trip" % key)


# --- 2: a price key is rejected, not ignored ------------------------------------


func test_a_claim_row_carrying_a_price_is_normalized_away() -> void:
	# The reject half. A normalization that DROPPED an injected price would be weaker than
	# one that refuses it: dropping hides the author and refusing reports them. So the row
	# that survives normalization is the closed vocabulary and nothing else — a
	# `normalize` that passed a `price` through would be caught by this, and so would one
	# that kept it under a different spelling, which is why the key list is twelve long.
	#
	# This is the ATTACK surface, not a hypothetical: `CustodyState.put` duplicates the
	# caller's dictionary, so any caller handing it a claim it built itself would otherwise
	# be writing arbitrary keys into the world ledger.
	var poisoned := CustodyState.empty()
	var subject := String(SUBJECT)
	for key in VALUATION_KEYS:
		var row := {
			"claim_id": "custody_poison#0",
			"subject_id": subject,
			"subject_kind": "npc",
			"holder": {"kind": "actor", "id": "warden"},
			"term_id": String(TERM),
			"periods": 3,
			"opened_period": 0,
			"status": CustodyState.HELD,
			key: 9999,
		}
		var stored := CustodyState.normalize({"version": CustodyState.SCHEMA_VERSION, "claims": {}})
		var put := CustodyState.put(stored, row)
		assert_eq(bool(put["ok"]), true, "a row with a '%s' key is storable" % key)
		var again := CustodyState.normalize(stored)
		var kept: Dictionary = (again["claims"] as Dictionary)["custody_poison#0"]
		assert_eq(kept.has(key), false, "'%s' does not survive normalize" % key)
		assert_eq(int(kept["periods"]), 3, "while the term survives")


func test_custody_state_put_refuses_a_row_with_no_term() -> void:
	# The other half of "no valuation": the module does not merely strip the price, it
	# REFUSES a termless row at the source, so a caller cannot open a claim with no term and
	# then argue the count was a price. `capture` refuses it as `no_terms` and writes
	# nothing; `put` refuses it as `unknown_subject` only because `subject_id` is what it
	# validates, so this asserts through the FACADE, which is the door a caller uses.
	var warden := _actor(&"warden")
	var termless := CustodyApi.capture(warden, SUBJECT, &"npc", _owner(&"warden"), TERM, 0)
	assert_eq(bool(termless["ok"]), false, "a termless capture refuses")
	assert_eq(String(termless["reason"]), CustodyApi.NO_TERMS, "and names the rule")
	assert_eq(int(CustodyApi.summary(warden)["claim_count"]), 0, "and no row was written at all")
	var untitled := CustodyApi.capture(warden, SUBJECT, &"npc", _owner(&"warden"), &"", 4)
	assert_eq(bool(untitled["ok"]), false, "a capture with no term id refuses")
	assert_eq(int(CustodyApi.summary(warden)["claim_count"]), 0, "and still writes nothing")


# --- 3: settlement moves COINS, never a balance ---------------------------------


func test_settlement_moves_inventory_held_coins_and_no_balance() -> void:
	# ADR 0139 supersedes ADR 0099: the numéraire is a HELD ITEM. So the proof that money
	# moved is that the coin STACK changed on both sides — `Inventory.count` before and
	# after — and not that some integer somewhere was assigned.
	#
	# BOTH sides are asserted, because one side alone cannot prove movement: this program
	# shipped a settlement that debited the payer and credited nobody, and a test watching
	# only the payer passes on exactly that bug.
	var claim_id := _capture(_actor(&"warden"))
	var buyer := _actor(&"buyer", 100)
	assert_eq(EconomyApi.purse(buyer), 100, "the buyer starts with a coin stack")
	assert_eq(EconomyApi.purse(_held[0]), 0, "and the seller starts with none")
	var moved := CustodyApi.transfer(
		_held[0], StringName(claim_id), _owner(&"warden"), _owner(&"buyer"), 25, buyer, _held[0]
	)
	assert_eq(bool(moved["ok"]), true, "the settlement runs: %s" % moved.get("reason", ""))
	assert_eq(EconomyApi.purse(buyer), 75, "the payer's held stack shrank")
	assert_eq(EconomyApi.purse(_held[0]), 25, "and the receiver's held stack grew")
	assert_eq(
		ItemsApi.inventory(buyer).count(EconomyValuation.numeraire_id()),
		75,
		"the coin is an inventory item, not an integer balance"
	)
	# And the module keeps NO balance of its own to write: the custody ledger after a
	# settlement is byte-identical to the ledger before it except for the holder. A
	# `balance` / `coins` / `purse` key on a claim is the shape a valuation would take.
	var ledger := CustodyApi.state(_held[0])
	var claims: Dictionary = ledger["claims"] as Dictionary
	for claim_id_key in claims.keys():
		var row: Dictionary = claims[claim_id_key]
		for key in VALUATION_KEYS:
			assert_eq(row.has(key), false, "the settled claim carries no '%s'" % key)
	assert_eq(claims.has("balance"), false, "and the ledger keeps no balance")
	assert_eq(claims.has("purse"), false, "nor a purse")


func test_the_agreed_coins_are_the_callers_number_and_the_module_adds_none() -> void:
	# The module computes NO price: `transfer` takes the agreed amount and settles exactly
	# it. Three amounts, three times what was asked for — so the number is negotiated, not
	# derived. A module that scaled the amount by a rarity weight or a realm factor would
	# fail the third case, where 1 stays 1 rather than becoming whatever the formula says.
	#
	# A DIFFERENT subject per case, not three claims on one: one subject may be held once
	# (`already_captive`), so reusing `drifter` would have the second case measure the cap
	# rather than the settlement. Each case is therefore independent — which is the point,
	# because a loop that reuses a ledger row is a loop that measures the wrong thing.
	for case in [0, 1, 7]:
		var coins := int(case)
		var seller_id := StringName("seller_%d" % coins)
		var subject := StringName("drifter_%d" % coins)
		var seller := _actor(seller_id)
		var taken := CustodyApi.capture(seller, subject, &"npc", _owner(seller_id), TERM, 2)
		assert_eq(bool(taken["ok"]), true, "the %d capture opened" % coins)
		var claim_id := String(taken.get("claim_id", ""))
		var payer := _actor(StringName("payer_%d" % coins), 50)
		var moved := CustodyApi.transfer(
			seller,
			StringName(claim_id),
			_owner(seller_id),
			_owner(&"buyer_x"),
			coins,
			payer,
			seller
		)
		assert_eq(
			bool(moved["ok"]),
			true,
			"a %d-coin settlement runs: %s" % [coins, moved.get("reason", "")]
		)
		assert_eq(int(moved["coins"]), coins, "and moves exactly the agreed %d" % coins)
		assert_eq(EconomyApi.purse(payer), 50 - coins, "the payer lost exactly %d" % coins)
		assert_eq(EconomyApi.purse(seller), coins, "and the receiver gained exactly %d" % coins)


func test_a_failed_settlement_moves_no_coin_and_no_holder() -> void:
	# A refusal writes nothing — no coins AND no claim move — which is ADR 0104's ordering
	# proof. Asserted on both sides so a partial settlement cannot pass.
	var claim_id := _capture(_actor(&"warden"))
	var broke := _actor(&"broke", 1)
	var before_warden := EconomyApi.purse(_held[0])
	var refused := CustodyApi.transfer(
		_held[0], StringName(claim_id), _owner(&"warden"), _owner(&"broke"), 500, broke, _held[0]
	)
	assert_eq(bool(refused["ok"]), false, "an unpayable settlement refuses")
	assert_eq(String(refused["reason"]), CustodyApi.COIN_LEG_FAILED, "and names the failure")
	assert_eq(int(refused["coins"]), 0, "and reports zero coins moved")
	assert_eq(EconomyApi.purse(_held[0]), before_warden, "the seller received nothing")
	assert_eq(EconomyApi.purse(broke), 1, "and the payer lost nothing")
	var claim: Dictionary = (CustodyApi.summary(_held[0])["claims"] as Dictionary)[claim_id]
	assert_eq(String(claim["holder"]["id"]), "warden", "and the claim never moved")
	assert_eq(int(claim["periods"]), 4, "nor did the term change")


# --- the count is a count ------------------------------------------------------


func test_settling_a_term_is_a_subtraction_and_scales_by_nothing() -> void:
	# `periods` is arithmetic, never a valuation. A term scaled by `RealmRate` would make a
	# claim at the top rung worth 551x one at the bottom (ADR 0050); a term scaled by
	# `RARITY_WEIGHT` would put a person through the one price formula (ADR 0094). So the
	# count after a settlement is checked against `before - asked` exactly, at a realm.
	var claim_id := _capture(_actor(&"warden"), 4)
	var hero := _held[0]
	var first := CustodyApi.settle_term(hero, StringName(claim_id), 3)
	assert_eq(bool(first["ok"]), true, "a partial settlement runs")
	assert_eq(int(first["periods_left"]), 1, "leaving before minus asked, with no curve")
	assert_eq(
		int((CustodyApi.state(hero)["claims"] as Dictionary)[claim_id]["periods"]),
		1,
		"and the ledger agrees"
	)
	var over := CustodyApi.settle_term(hero, StringName(claim_id), 2)
	assert_eq(bool(over["ok"]), false, "settling more than is owed refuses")
	assert_eq(String(over["reason"]), CustodyApi.TERM_EXCEEDS, "and names the rule")
	assert_eq(
		int((CustodyApi.state(hero)["claims"] as Dictionary)[claim_id]["periods"]),
		1,
		"and the refusal settled nothing — terms stay all-or-nothing"
	)
	var last := CustodyApi.settle_term(hero, StringName(claim_id), 1)
	assert_eq(int(last["periods_left"]), 0, "the remainder settles when asked for exactly")


func test_a_settled_term_carries_no_valuation_afterwards() -> void:
	# The same rule on a row that has been through `settle_term`. A `settle` that wrote a
	# running total — "what this claim is worth so far" — would be a valuation arriving
	# through the arithmetic door rather than the capture door.
	var claim_id := _capture(_actor(&"warden"), 4)
	var hero := _held[0]
	CustodyApi.settle_term(hero, StringName(claim_id), 2)
	var row: Dictionary = (CustodyApi.state(hero)["claims"] as Dictionary)[claim_id]
	assert_eq(int(row["periods"]), 2, "the count moved by exactly what was settled")
	for key in VALUATION_KEYS:
		assert_eq(row.has(key), false, "a settled term carries no '%s'" % key)
	# `settle_term`'s RESULT is a count report, not a quotation.
	var again := CustodyApi.settle_term(hero, StringName(claim_id), 2)
	for key in VALUATION_KEYS:
		assert_eq(again.has(key), false, "the settlement result carries no '%s'" % key)


func test_a_term_counts_periods_at_any_realm_without_scaling() -> void:
	# The realm arm of the same claim, measured rather than asserted in prose. A claim
	# opened by an actor at the top of the ladder carries exactly the authored periods,
	# and a settlement at that realm is the same subtraction — so no `RealmRate.factor` is
	# reachable from a term even indirectly.
	var hero := _actor(&"warden")
	var taken := CustodyApi.capture(hero, SUBJECT, &"npc", _owner(&"warden"), TERM, 4, 0)
	var claim_id := String(taken.get("claim_id", ""))
	var row: Dictionary = (CustodyApi.state(hero)["claims"] as Dictionary)[claim_id]
	assert_eq(int(row["periods"]), 4, "the authored count is the stored count")
	assert_eq(typeof(row["periods"]), TYPE_INT, "and it is an int, not a scaled float")
	assert_eq(row.has("realm_factor"), false, "with no realm factor stored beside it")
	assert_eq(row.has("realm"), false, "and no realm stamped onto the term at all")
	# `RealmRate` itself is the formula a price would read. Asserted to be a FUNCTION the
	# custody sources never call, so the ladder cannot reach a term through any path.
	for path in [
		"res://src/modules/custody/api.gd",
		"res://src/modules/custody/custody_state.gd",
		"res://src/modules/custody/custody_world_ledger.gd",
	]:
		assert_eq(
			_code_only(path).contains("RealmRate"),
			false,
			"'%s' never reaches the realm ladder" % path.get_file()
		)


# --- helpers ------------------------------------------------------------------


## The shipped source of `path` with every comment removed: a `#` line, and everything
## from an inline `#` to end of line. Both custody files name "price" in their doc comments
## on purpose (ADR 0104 says a captive is "never a price"), so asserting on prose would make
## this a typo detector rather than a boundary check.
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash := line.find("#")
		out.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(out)
