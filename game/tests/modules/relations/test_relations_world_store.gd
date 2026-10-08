extends TestCase

## **A declared stance reaches the graph through the world store** (DEF-0179).
##
## `RelationGraph` reads the authored catalog from every owner's `summary(null)`,
## so before this seam a player-declared schism or war was invisible to `graph()`,
## `stance()` and `hostile_to()`. The graph now reads the world polity ledger
## through an injected store, and an explicitly handed ledger still wins.
##
## ## What this suite pins
##
##   - no store: the bare call is authored-only and the memo still covers it;
##   - store: the bare call sees the declared pair with `polity` provenance;
##   - an explicit argument beats the store;
##   - a store-backed answer survives a cache wipe identically;
##   - a store-backed build is never memoized, and uninstalling restores the memo.
##
## Every loop here is a `for` over a dictionary's own keys or a fixed array; none
## appends to the container it walks, so each bound is fixed before the first pass.


## A tiny in-memory world polity store: the seam is duck-typed, so this is the
## right double — no disk, no `SaveApi`, and `read_ledger`/`write_ledger` exactly
## as `WorldLedgerStore` spells them.
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


const HALF := "t_half"
const PARENT := "t_parent"
const WAR_A := "n_a"
const WAR_B := "n_b"


func setup() -> void:
	_clear()


func teardown() -> void:
	_clear()


func _clear() -> void:
	RelationsApi.set_store(null)
	RelationsApi.shared = null
	RelationsApi._memo = {}


## A store whose ledger already carries one schism and one war, written through
## the REAL writers so the reader is tested against the shape the writers produce.
func _store() -> FakeStore:
	var world := WorldPolityLedger.empty()
	var schism := InstitutionRelation.declare_schism(world, PARENT, HALF)
	world = schism["ledger"]
	var war := InstitutionRelation.declare_war(world, WAR_A, WAR_B)
	world = war["ledger"]
	return FakeStore.new(world)


func _pair(kind_a: String, id_a: String, kind_b: String, id_b: String) -> String:
	return RelationKey.pair_key(
		RelationKey.node_key(kind_a, id_a), RelationKey.node_key(kind_b, id_b)
	)


func test_without_a_store_the_bare_call_is_authored_only_and_the_memo_covers_it() -> void:
	RelationsApi.set_store(null)
	var bare := RelationsApi.graph()
	assert_eq(bare.has(_pair("sect", HALF, "sect", PARENT)), false, "no declared schism is visible")
	assert_eq(
		bare.has(_pair("nation", WAR_A, "nation", WAR_B)), false, "no declared war is visible"
	)
	# The memo still covers the bare call: fill it and read through it.
	RelationsApi.shared = RelationsApi.new()
	RelationsApi._memo = {}
	var warm := RelationsApi.graph()
	assert_eq(RelationsApi._memo.size(), warm.size(), "the authored-only build was memoized")
	assert_ne(RelationsApi._memo.size(), 0, "and the memo is not empty, so this is a real read")


func test_a_store_backed_bare_call_sees_the_declared_pair_with_polity_provenance() -> void:
	RelationsApi.set_store(_store())
	var edges := RelationsApi.graph()
	var schism_key := _pair("sect", HALF, "sect", PARENT)
	var war_key := _pair("nation", WAR_A, "nation", WAR_B)
	assert_eq(edges.has(schism_key), true, "the declared schism reached the bare graph")
	assert_eq(edges.has(war_key), true, "and so did the war")
	var schism_edge: Dictionary = edges[schism_key]
	assert_eq(String(schism_edge["source"]), "polity", "with provenance 'polity', not an owner")
	assert_eq(String(schism_edge["stance"]), RelationKey.HOSTILE, "a schism reads hostile")
	assert_eq(String((edges[war_key] as Dictionary)["stance"]), RelationKey.HOSTILE, "a war too")
	# `stance` and `hostile_to` read the same graph, so both see it with no argument.
	var stance := RelationsApi.stance(
		RelationKey.node_key("sect", HALF), RelationKey.node_key("sect", PARENT)
	)
	assert_eq(String(stance["source"]), "polity", "stance() sees it too")
	var enemies := RelationsApi.hostile_to(RelationKey.node_key("nation", WAR_A))
	assert_eq(enemies.has(RelationKey.node_key("nation", WAR_B)), true, "hostile_to() sees it too")
	# `summary()` folds the same graph, so a screen reads the pair with no argument.
	var read := RelationsApi.summary()
	assert_eq(int(read["edge_count"]), edges.size(), "summary() publishes the same graph")
	assert_eq((read["edges"] as Dictionary).has(war_key), true, "including the declared war")


func test_an_explicit_ledger_always_wins_over_the_store() -> void:
	RelationsApi.set_store(_store())
	var handed := WorldPolityLedger.empty()
	var war := InstitutionRelation.declare_war(handed, "n_c", "n_d")
	handed = war["ledger"]
	var edges := RelationsApi.graph(handed)
	assert_eq(edges.has(_pair("nation", "n_c", "nation", "n_d")), true, "the handed ledger is read")
	assert_eq(edges.has(_pair("nation", WAR_A, "nation", WAR_B)), false, "and the store is not")


func test_wiping_the_memo_cannot_change_a_store_backed_answer() -> void:
	RelationsApi.set_store(_store())
	RelationsApi.shared = RelationsApi.new()
	var before := RelationsApi.graph()
	RelationsApi.shared = null
	RelationsApi._memo = {}
	var after := RelationsApi.graph()
	assert_eq(after, before, "a wiped cache is indistinguishable from a warm one")


func test_a_store_backed_build_is_never_memoized() -> void:
	RelationsApi.set_store(_store())
	RelationsApi.shared = RelationsApi.new()
	RelationsApi._memo = {}
	RelationsApi.graph()
	assert_eq(RelationsApi._memo.is_empty(), true, "the ledger is the thing that moves, so no memo")
	# Uninstall the store and the pure authored call memoizes again.
	RelationsApi.set_store(null)
	RelationsApi._memo = {}
	RelationsApi.graph()
	assert_eq(RelationsApi._memo.is_empty(), false, "with no store, the bare call is memoized")
