extends TestCase

## ADR 0104: a captive is a custody CLAIM. The load-bearing assertions are:
##  - a refused verb writes nothing, INCLUDING no coin movement (the coin leg runs first);
##  - `holder == subject` cannot be written at all;
##  - a record carries NO prose field, ever.

const COIN := &"curr_spirit_coin"
const SUBJECT := &"guard_captain"

var _held: Array[Actor] = []


func setup() -> void:
	# Custody is a WORLD fact (ADR 0101): the new holder must see the claim the old holder
	# opened, or every transfer refuses `no_such_claim`.
	CustodyApi.set_store(CustodyWorldLedger.new())
	CustodyApi.set_resolver(func(_kind: String, _id: String) -> Dictionary: return {"ok": true})
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


func _owner(id: StringName, kind: StringName = &"actor") -> Dictionary:
	return {"kind": String(kind), "id": String(id)}


func _capture(holder_id: StringName, periods: int = 4) -> String:
	var holder := _actor(holder_id)
	var taken := CustodyApi.capture(holder, SUBJECT, &"npc", _owner(holder_id), &"custody", periods)
	return String(taken.get("claim_id", ""))


func test_capture_opens_a_claim_named_for_the_subject() -> void:
	var claim_id := _capture(&"warden")
	assert_ne(claim_id, "", "the claim is opened")
	var summary := CustodyApi.summary(_held[0])
	assert_eq(int(summary["claim_count"]), 1, "the ledger holds one claim")
	var claim: Dictionary = (summary["claims"] as Dictionary)[claim_id]
	assert_eq(String(claim["subject_id"]), String(SUBJECT), "naming the subject def id")
	assert_eq(int(claim["periods"]), 4, "carrying the term as a period count")


func test_a_claim_carries_no_prose_and_no_actor() -> void:
	# The whole reason the record is clinical: no description, no name copied from the def,
	# and never the live subject. Prose in a save schema is how prose becomes what gets read.
	var claim_id := _capture(&"warden")
	var payload := CustodyApi.state(_held[0])
	var claim: Dictionary = (payload["claims"] as Dictionary)[claim_id]
	for forbidden in ["description", "flavor", "note", "display_name", "actor", "payload", "price"]:
		assert_eq(claim.has(forbidden), false, "the claim carries no '%s'" % forbidden)
	assert_eq(typeof(claim["subject_id"]), TYPE_STRING, "the subject id is a String")
	assert_eq(typeof(claim["holder"]["kind"]), TYPE_STRING, "the holder kind is a String")


func test_a_holder_cannot_hold_themselves() -> void:
	# A record with no exit: transfer refuses self-transfer, release refuses a non-holder,
	# so the claim would be permanent. Refused at capture so it is never written.
	var actor := _actor(&"prisoner")
	var taken := CustodyApi.capture(actor, &"prisoner", &"npc", _owner(&"prisoner"), &"custody", 4)
	assert_eq(bool(taken["ok"]), false, "self-hold refuses")
	assert_eq(String(taken["reason"]), CustodyApi.SELF_HOLD, "and names the rule")


func test_a_capture_with_no_term_refuses() -> void:
	var actor := _actor(&"warden")
	var taken := CustodyApi.capture(actor, SUBJECT, &"npc", _owner(&"warden"), &"custody", 0)
	assert_eq(bool(taken["ok"]), false, "a capture with no term refuses")
	assert_eq(String(taken["reason"]), CustodyApi.NO_TERMS, "a capture with no term is a free grab")
	assert_eq(int(CustodyApi.summary(actor)["claim_count"]), 0, "and writes nothing")


func test_one_subject_may_be_held_once() -> void:
	_capture(&"warden")
	var other := _actor(&"rival")
	var taken := CustodyApi.capture(other, SUBJECT, &"npc", _owner(&"rival"), &"custody", 4)
	assert_eq(bool(taken["ok"]), false, "a second claim on one subject refuses")
	assert_eq(String(taken["reason"]), CustodyApi.ALREADY_CAPTIVE, "two holders is unresolvable")


func test_transfer_moves_the_holder_and_the_coins() -> void:
	var claim_id := _capture(&"warden")
	var payer := _actor(&"buyer", 100)
	var result := CustodyApi.transfer(
		_held[0], StringName(claim_id), _owner(&"warden"), _owner(&"buyer"), 20, payer, _held[0]
	)
	assert_eq(bool(result["ok"]), true, "the transfer settles: %s" % result.get("reason", ""))
	assert_eq(int(result["coins"]), 20, "the agreed coins moved")
	assert_eq(EconomyApi.purse(payer), 80, "the payer lost them")
	var summary := CustodyApi.summary(_held[0])
	var claim: Dictionary = (summary["claims"] as Dictionary)[claim_id]
	assert_eq(String(claim["holder"]["id"]), "buyer", "and the claim changed hands")


func test_a_failed_coin_leg_moves_neither_money_nor_the_claim() -> void:
	# The ordering proof (ADR 0104): the coin leg runs FIRST, so a refused settlement has
	# written nothing and the claim has not moved. The reverse order is the "granted but
	# never written" failure ADR 0101 records, unrecoverable without a rollback path.
	var claim_id := _capture(&"warden")
	var broke := _actor(&"broke", 1)
	var before_warden := EconomyApi.purse(_held[0])
	var result := CustodyApi.transfer(
		_held[0], StringName(claim_id), _owner(&"warden"), _owner(&"broke"), 500, broke, _held[0]
	)
	assert_eq(bool(result["ok"]), false, "an unpayable settlement refuses")
	assert_eq(String(result["reason"]), CustodyApi.COIN_LEG_FAILED, "and names the failure")
	assert_eq(EconomyApi.purse(_held[0]), before_warden, "the seller received nothing")
	var summary := CustodyApi.summary(_held[0])
	var claim: Dictionary = (summary["claims"] as Dictionary)[claim_id]
	assert_eq(String(claim["holder"]["id"]), "warden", "and the claim is byte-identical to before")


func test_a_transfer_with_no_coins_is_a_legal_handoff() -> void:
	# A hand-off with no coin leg must not be forced to invent one: zero skips the exchange
	# entirely, so no `no_settlement` refusal is possible.
	var claim_id := _capture(&"warden")
	var result := CustodyApi.transfer(
		_held[0], StringName(claim_id), _owner(&"warden"), _owner(&"buyer"), 0
	)
	assert_eq(bool(result["ok"]), true, "a hand-off settles: %s" % result.get("reason", ""))
	assert_eq(int(result["coins"]), 0, "and moved no coins")


func test_self_transfer_is_refused() -> void:
	# A same-party sale at an agreed price is a money printer — the same reason the exchange
	# refuses `SAME_ACTOR`.
	var claim_id := _capture(&"warden")
	var payer := _actor(&"warden2", 100)
	var result := CustodyApi.transfer(
		_held[0], StringName(claim_id), _owner(&"warden"), _owner(&"warden"), 5, payer, _held[0]
	)
	assert_eq(bool(result["ok"]), false, "a holder cannot buy from themself")
	assert_eq(String(result["reason"]), CustodyApi.SELF_TRANSFER, "and names the rule")


func test_a_stranger_cannot_release_or_transfer() -> void:
	var claim_id := _capture(&"warden")
	var stranger := _actor(&"stranger")
	var released := CustodyApi.release(stranger, StringName(claim_id), _owner(&"stranger"))
	assert_eq(bool(released["ok"]), false, "a stranger cannot release")
	assert_eq(String(released["reason"]), CustodyApi.HOLDER_MISMATCH, "and names the rule")
	var moved := CustodyApi.transfer(
		stranger, StringName(claim_id), _owner(&"stranger"), _owner(&"thief"), 0
	)
	assert_eq(bool(moved["ok"]), false, "nor transfer")


func test_an_institution_may_hold_without_any_module_edge() -> void:
	# The whole boundary claim: a sect holder resolves through the injected Callable, so
	# `custody` names no sect type and holds no edge to the module.
	var holder := _actor(&"clerk")
	var taken := CustodyApi.capture(
		holder, SUBJECT, &"npc", _owner(&"azure_flame", &"sect"), &"custody", 6
	)
	assert_eq(bool(taken["ok"]), true, "a sect may take custody: %s" % taken.get("reason", ""))
	var summary := CustodyApi.summary(holder)
	var claim: Dictionary = (summary["claims"] as Dictionary)[String(taken["claim_id"])]
	assert_eq(String(claim["holder"]["kind"]), "sect", "and the holder is an institution")


func test_an_unresolvable_holder_refuses_with_the_resolvers_reason() -> void:
	CustodyApi.set_resolver(
		func(_kind: String, id: String) -> Dictionary:
			return {"ok": false, "reason": "unknown_sect"} if id == "ghost" else {"ok": true}
	)
	var holder := _actor(&"clerk")
	var taken := CustodyApi.capture(
		holder, SUBJECT, &"npc", _owner(&"ghost", &"sect"), &"custody", 4
	)
	assert_eq(bool(taken["ok"]), false, "an unresolvable holder refuses")
	assert_eq(String(taken["reason"]), "unknown_sect", "and passes the reason through verbatim")


func test_no_resolver_refuses_loudly_rather_than_silently() -> void:
	CustodyApi.set_resolver(Callable())
	var holder := _actor(&"clerk")
	var taken := CustodyApi.capture(
		holder, SUBJECT, &"npc", _owner(&"azure_flame", &"sect"), &"custody", 4
	)
	assert_eq(bool(taken["ok"]), false, "an institution claim with no resolver refuses")
	assert_eq(String(taken["reason"]), CustodyApi.NO_RESOLVER, "and says the resolver is missing")


func test_release_is_a_holder_verb_and_leaves_the_history() -> void:
	# Release does NOT forgive the term, and the claim stays in the ledger as released, so a
	# subject can be captured again under a NEW claim rather than the old one reopening.
	var claim_id := _capture(&"warden", 7)
	var result := CustodyApi.release(_held[0], StringName(claim_id), _owner(&"warden"))
	assert_eq(bool(result["ok"]), true, "the holder may release")
	assert_eq(int(result["periods_left"]), 7, "and the term is not forgiven")
	var summary := CustodyApi.summary(_held[0])
	var claim: Dictionary = (summary["claims"] as Dictionary)[claim_id]
	assert_eq(String(claim["status"]), "released", "the claim reads as released")
	assert_eq(bool(claim["holder"].get("vacant", false)), true, "and its holder is vacant")


func test_settling_a_term_is_all_or_nothing() -> void:
	# All-or-nothing (ADR 0104): a request larger than the term settles NOTHING, so a holder
	# is never left owing less than it claimed to owe and never silently forgiven.
	var claim_id := _capture(&"warden", 4)
	var partial := CustodyApi.settle_term(_held[0], StringName(claim_id), 2)
	assert_eq(bool(partial["ok"]), true, "a partial settlement succeeds")
	assert_eq(int(partial["periods_left"]), 2, "and leaves the remainder")
	var over := CustodyApi.settle_term(_held[0], StringName(claim_id), 9)
	assert_eq(bool(over["ok"]), false, "settling more than is owed refuses")
	assert_eq(String(over["reason"]), CustodyApi.TERM_EXCEEDS, "and names the rule")
	var unchanged := CustodyApi.settle_term(_held[0], StringName(claim_id), 1)
	assert_eq(int(unchanged["periods_left"]), 1, "and the refusal settled nothing")
	var last := CustodyApi.settle_term(_held[0], StringName(claim_id), 1)
	assert_eq(bool(last["ok"]), true, "the remainder settles when asked for exactly")
	assert_eq(int(last["periods_left"]), 0, "leaving nothing owed")


func test_summary_is_empty_without_an_actor() -> void:
	assert_eq(CustodyApi.summary(null), {}, "summary is {} with no actor")


func test_the_ledger_is_json_safe() -> void:
	var claim_id := _capture(&"warden")
	var payload := CustodyApi.state(_held[0])
	var restored: Variant = JSON.parse_string(JSON.stringify(payload))
	assert_eq(typeof(restored), TYPE_DICTIONARY, "the ledger is JSON-safe")
	var claim: Dictionary = (restored as Dictionary)["claims"][claim_id]
	assert_eq(typeof(claim["holder"]["kind"]), TYPE_STRING, "the holder kind is a String")
	assert_eq(typeof(claim["subject_id"]), TYPE_STRING, "the subject id is a String")


func test_no_escape_verb_exists_on_the_facade() -> void:
	# The structural pin (ADR 0084's shape). An escape resolved here would be a second
	# authority on combat and an rng-shaped outcome; combat decides it and the holder then
	# releases. `tools arch` cannot see a method that does not exist, so a test reads the
	# facade's own source and asserts none is published. Reading the FILE rather than calling
	# `has_method` is what makes it a structural check: a static class exposes no instance to
	# ask, and instantiating one to inspect its methods would be the odd way to test a
	# stateless facade.
	var source := FileAccess.get_file_as_string("res://src/modules/custody/api.gd")
	for verb in ["escape", "free", "liberate", "rescue", "break_free", "flee"]:
		assert_eq(
			source.contains("static func %s(" % verb),
			false,
			"custody publishes no '%s' verb" % verb
		)


func test_the_facade_stays_inside_its_twelve_method_cap() -> void:
	# ISP is enforced by `tools arch` for other modules; asserting it here as well means a
	# verb added past the cap fails in a suite with a readable message rather than only in a
	# gate whose output is a wall of warnings.
	var source := FileAccess.get_file_as_string("res://src/modules/custody/api.gd")
	var count := 0
	for line in source.split("\n"):
		if line.begins_with("static func ") and not line.begins_with("static func _"):
			count += 1
	assert_eq(count <= 12, true, "the custody facade publishes %d public methods" % count)
