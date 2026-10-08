extends TestCase

## **A declared war writes the WORLD half of the fact** (DEF-0179).
##
## Mirrors the sect suite: the actor's ledger records the standoff, the prize and
## the cost; the pair's hostility is true of the two INSTITUTIONS and is written to
## the world polity ledger through an injected store, then read back through
## `RelationsApi` when the same store is installed there.
##
## ## What this suite pins
##
##   - with a store: the world row carries `war` with debtor = the declarer and
##     creditor = the other polity, and the graph sees the pair;
##   - without one: the verb's payload and the actor ledger are unchanged;
##   - a cross-actor repeat whose world flag is already open is a NO-OP at the world
##     level and still succeeds;
##   - a refusal leaves BOTH ledgers byte-identical.
##
## Every loop here is a `for` over a fixed array or a dictionary's own keys; none
## appends to the container it walks, so each bound is fixed before the first pass.

const MARCH := &"march_of_the_nine_provinces"
const RIVAL := &"court_of_the_star"
const CLAIM := &"river_march"


## A tiny in-memory world polity store: the seam is duck-typed, so this is the
## right double — no disk, no `SaveApi`.
class FakeStore:
	extends RefCounted
	var ledger: Dictionary = {}

	func _init(initial: Dictionary = {}) -> void:
		ledger = initial

	func read_ledger() -> Dictionary:
		return ledger

	func write_ledger(next: Dictionary) -> Dictionary:
		ledger = next
		return {"ok": true}


func setup() -> void:
	NationApi.set_world_store(null)
	RelationsApi.set_store(null)
	RelationsApi.shared = null
	RelationsApi._memo = {}


func teardown() -> void:
	NationApi.set_world_store(null)
	RelationsApi.set_store(null)
	RelationsApi.shared = null
	RelationsApi._memo = {}


func _actor(actor_id: StringName = &"polity_a") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0})
	NationApi.attach(actor)
	NationApi.found(actor, MARCH, String(actor_id))
	return actor


func _prize() -> Dictionary:
	return {
		"mode": "contest",
		"transfer": "ownership",
		"standing": {"polity_a": 10, "court_of_the_star": -8},
	}


## The world ledger's row for the pair, whatever direction it was declared in.
func _world_row(ledger: Dictionary, a_id: String, b_id: String) -> Dictionary:
	var live := WorldPolityLedger.normalize_payload(ledger)
	for key in (live["debts"] as Dictionary).keys():
		var row = (live["debts"] as Dictionary)[key]
		if not (row is Dictionary):
			continue
		var debtor := String((row as Dictionary).get("debtor_id", ""))
		var creditor := String((row as Dictionary).get("creditor_id", ""))
		if WorldPolityLedger.pair_key(debtor, creditor) == WorldPolityLedger.pair_key(a_id, b_id):
			return row as Dictionary
	return {}


func test_a_declaration_writes_the_world_row_and_the_graph_reads_it() -> void:
	var store := FakeStore.new(WorldPolityLedger.empty())
	NationApi.set_world_store(store)
	var actor := _actor()
	var declared := NationApi.declare_war(actor, RIVAL, CLAIM, _prize())
	assert_eq(bool(declared["ok"]), true, "the war landed: %s" % declared)
	var row := _world_row(store.ledger, "polity_a", String(RIVAL))
	assert_eq(row.is_empty(), false, "the world ledger carries the pair")
	assert_eq(int((row["lines"] as Dictionary).get("war", 0)), 1, "with the war flag open")
	assert_eq(String(row["debtor_id"]), "polity_a", "the declarer is the debtor")
	assert_eq(String(row["creditor_id"]), String(RIVAL), "and the other polity is the creditor")
	# The same store installed into the graph makes the pair visible, which is the
	# production chain: one instance, written by the verb and read by the graph.
	RelationsApi.set_store(store)
	var key := RelationKey.pair_key(
		RelationKey.node_key("nation", "polity_a"), RelationKey.node_key("nation", String(RIVAL))
	)
	var edges := RelationsApi.graph()
	assert_eq(edges.has(key), true, "the graph sees the declared war")
	assert_eq(String((edges[key] as Dictionary)["source"]), "polity", "with polity provenance")


func test_without_a_store_the_verb_and_the_actor_ledger_are_unchanged() -> void:
	var bare := _actor()
	var bare_declared := NationApi.declare_war(bare, RIVAL, CLAIM, _prize())
	assert_eq(bool(bare_declared["ok"]), true, "the war still lands with no store")
	var store := FakeStore.new(WorldPolityLedger.empty())
	NationApi.set_world_store(store)
	var wired := _actor()
	var wired_declared := NationApi.declare_war(wired, RIVAL, CLAIM, _prize())
	# The actor-facing payload is the SAME with and without the world leg: the store
	# records the pair, it does not alter the standoff.
	for field in ["standoff_id", "mode", "quota"]:
		assert_eq(wired_declared[field], bare_declared[field], "'%s' is unchanged" % field)
	assert_eq(NationApi.state(wired), NationApi.state(bare), "and the actor ledgers are identical")
	assert_eq(store.ledger.is_empty(), false, "the wired run did write the world")


func test_a_cross_actor_repeat_is_a_world_no_op_and_still_succeeds() -> void:
	var store := FakeStore.new(WorldPolityLedger.empty())
	NationApi.set_world_store(store)
	var first := _actor()
	assert_eq(bool(NationApi.declare_war(first, RIVAL, CLAIM, _prize())["ok"]), true, "first war")
	var world_after_first := store.ledger.duplicate(true)
	var second := _actor()
	var declared := NationApi.declare_war(second, RIVAL, CLAIM, _prize())
	# The actor side permits it: the second member's own ledger never declared this
	# standoff, so their own standoff and prize are written.
	assert_eq(bool(declared["ok"]), true, "a second member may open their own standoff")
	assert_eq(
		(NationApi.state(second)["standoffs"] as Dictionary).is_empty(),
		false,
		"and their own ledger records their own war"
	)
	# The world side is idempotent: a declaration is a fact, not a counter, so the
	# repeat neither adds a second row nor moves a sequence.
	assert_eq(
		store.ledger, world_after_first, "the world ledger is byte-identical after the repeat"
	)


func test_a_refusal_leaves_both_ledgers_byte_identical() -> void:
	var store := FakeStore.new(WorldPolityLedger.empty())
	NationApi.set_world_store(store)
	var actor := _actor()
	var actor_before := NationApi.state(actor)
	var world_before := store.ledger.duplicate(true)
	# `unknown_mode` is refused BEFORE the world leg, so the world cannot have been
	# touched — and neither can the actor's ledger.
	var refused := NationApi.declare_war(actor, RIVAL, CLAIM, {"mode": "armageddon"})
	assert_eq(String(refused["reason"]), "unknown_mode", "refused by name")
	assert_eq(store.ledger, world_before, "the world ledger is untouched")
	assert_eq(NationApi.state(actor), actor_before, "and so is the actor's")
