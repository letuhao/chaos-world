extends TestCase

## **A declared schism writes the WORLD half of the fact** (DEF-0179).
##
## The member's own ledger records what the split cost (standing, the bill, the
## actor's `schisms` line). The pair's hostility is true of the two INSTITUTIONS,
## so it is written to the world polity ledger through an injected store — and read
## back through `RelationsApi` when the same store is installed there.
##
## ## What this suite pins
##
##   - with a store: the world row carries `schism` with debtor = the seceding half
##     and creditor = the parent, and the graph sees the pair;
##   - without one: the verb's payload and the actor ledger are unchanged;
##   - a cross-actor repeat whose world flag is already open is a NO-OP at the world
##     level (a declaration is a fact, not a counter) and still succeeds;
##   - a refusal leaves BOTH ledgers byte-identical.
##
## Every loop here is a `for` over a fixed array or a dictionary's own keys; none
## appends to the container it walks, so each bound is fixed before the first pass.

const PARENT := &"t_foundry"
const HALF := &"t_seceded_house"
const DOCTRINE := &"t_foundry_doctrine"
## The places `PARENT` authors a claim over, so a split leaves authored ground.
const PLACES: Array[StringName] = [&"t_yard", &"t_terrace", &"t_orchard"]


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
	SectFixtureCatalog.install([_parent(), _half()])
	SectFixtureCatalog.install_doctrine([SectFixtureCatalog.doctrine(DOCTRINE)])
	SectApi.set_world_store(null)
	RelationsApi.set_store(null)
	RelationsApi.shared = null
	RelationsApi._memo = {}


func teardown() -> void:
	SectFixtureCatalog.teardown()
	SectApi.set_world_store(null)
	RelationsApi.set_store(null)
	RelationsApi.shared = null
	RelationsApi._memo = {}


func _parent() -> SectDef:
	var def := SectFixtureCatalog.foundable_sect(PARENT)
	def.territory_ids = PLACES
	return def


func _half() -> SectDef:
	return SectFixtureCatalog.foundable_sect(HALF)


## A founder of `PARENT`: sworn, seated in the top office, and holding the refund
## standing `SectFounding` grants, so a split can pay its declared price.
func _founder() -> Actor:
	var actor := Actor.new(&"keeper", {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	actor.add_resource(ResourcePool.new(SectFounding.FUNDING_POOL, 1000.0))
	SectApi.attach(actor)
	assert_eq(bool(SectApi.found(actor, PARENT, DOCTRINE, "keeper")["ok"]), true, "founded")
	return actor


## The world ledger's row for the pair, whatever direction it was declared in.
func _world_row(ledger: Dictionary, half: StringName, parent: StringName) -> Dictionary:
	var live := WorldPolityLedger.normalize_payload(ledger)
	for key in (live["debts"] as Dictionary).keys():
		var row = (live["debts"] as Dictionary)[key]
		if not (row is Dictionary):
			continue
		var debtor := String((row as Dictionary).get("debtor_id", ""))
		var creditor := String((row as Dictionary).get("creditor_id", ""))
		if (
			WorldPolityLedger.pair_key(debtor, creditor)
			== WorldPolityLedger.pair_key(String(half), String(parent))
		):
			return row as Dictionary
	return {}


func test_a_declaration_writes_the_world_row_and_the_graph_reads_it() -> void:
	var store := FakeStore.new(WorldPolityLedger.empty())
	SectApi.set_world_store(store)
	var actor := _founder()
	var verdict := SectApi.declare_schism(actor, HALF, PLACES)
	assert_eq(bool(verdict["ok"]), true, "the split landed: %s" % verdict)
	var row := _world_row(store.ledger, HALF, PARENT)
	assert_eq(row.is_empty(), false, "the world ledger carries the pair")
	assert_eq(int((row["lines"] as Dictionary).get("schism", 0)), 1, "with the schism flag open")
	assert_eq(String(row["debtor_id"]), String(HALF), "the seceding half is the debtor")
	assert_eq(String(row["creditor_id"]), String(PARENT), "and the parent is the creditor")
	# The same store installed into the graph makes the pair visible, which is the
	# production chain: one instance, written by the verb and read by the graph.
	RelationsApi.set_store(store)
	var key := RelationKey.pair_key(
		RelationKey.node_key("sect", String(HALF)), RelationKey.node_key("sect", String(PARENT))
	)
	var edges := RelationsApi.graph()
	assert_eq(edges.has(key), true, "the graph sees the declared split")
	assert_eq(String((edges[key] as Dictionary)["source"]), "polity", "with polity provenance")


func test_without_a_store_the_verb_and_the_actor_ledger_are_unchanged() -> void:
	var bare := _founder()
	var bare_verdict := SectApi.declare_schism(bare, HALF, PLACES)
	assert_eq(bool(bare_verdict["ok"]), true, "the split still lands with no store")
	var store := FakeStore.new(WorldPolityLedger.empty())
	SectApi.set_world_store(store)
	var wired := _founder()
	var wired_verdict := SectApi.declare_schism(wired, HALF, PLACES)
	# The actor-facing numbers are the SAME with and without the world leg: the
	# store records the pair, it does not alter the bill.
	for field in ["undivided", "half", "price", "unassigned", "settled", "shortfall", "applied"]:
		assert_eq(wired_verdict[field], bare_verdict[field], "'%s' is unchanged" % field)
	assert_eq(SectApi.state(wired), SectApi.state(bare), "and the actor ledgers are identical")
	assert_eq(store.ledger.is_empty(), false, "the wired run did write the world")


func test_a_cross_actor_repeat_is_a_world_no_op_and_still_succeeds() -> void:
	var store := FakeStore.new(WorldPolityLedger.empty())
	SectApi.set_world_store(store)
	var first := _founder()
	assert_eq(bool(SectApi.declare_schism(first, HALF, PLACES)["ok"]), true, "first declaration")
	var world_after_first := store.ledger.duplicate(true)
	var second := _founder()
	var verdict := SectApi.declare_schism(second, HALF, PLACES)
	# The actor side permits it: the second member's own ledger never declared this
	# split, so their own `schisms` line is written and their own standing is paid.
	assert_eq(bool(verdict["ok"]), true, "a second member may declare the same split")
	assert_eq(
		SectState.schism(SectApi.state(second), HALF).is_empty(),
		false,
		"and their own ledger records their own fact"
	)
	# The world side is idempotent: a declaration is a fact, not a counter, so the
	# repeat neither adds a second row nor moves a sequence.
	assert_eq(
		store.ledger, world_after_first, "the world ledger is byte-identical after the repeat"
	)


func test_a_refusal_leaves_both_ledgers_byte_identical() -> void:
	var store := FakeStore.new(WorldPolityLedger.empty())
	SectApi.set_world_store(store)
	var actor := _founder()
	# `nothing_to_split`: drive standing to one point, where the split is refused
	# BEFORE the world leg — so the world cannot have been touched.
	var cap := int(SectApi.state(actor)["standing_cap"])
	SectApi.move_standing(actor, -(cap - 1))
	var actor_before := SectApi.state(actor)
	var world_before := store.ledger.duplicate(true)
	var refused := SectApi.declare_schism(actor, HALF, PLACES)
	assert_eq(String(refused["reason"]), SectApi.NOTHING_TO_SPLIT, "refused by name")
	assert_eq(store.ledger, world_before, "the world ledger is untouched")
	assert_eq(SectApi.state(actor), actor_before, "and so is the actor's")
