extends TestCase

## ADR 0097: claiming a resource node. The invariant that matters most is that a CLAIM on
## held ground never moves the holder — that is what separates a claim from a conquest.

var _actor: Actor


func setup() -> void:
	ResourceNodeCatalog.instance().reset()
	ResourceNodeCatalog.instance().install(
		[_node(&"vein_test", 4, 0, 0), _node(&"vein_deep", 8, 2, 0)]
	)
	HoldingsApi.set_resolver(func(_kind: String, _id: String) -> Dictionary: return {"ok": true})
	# The shared world store, not a per-actor ledger: a holder must be visible to a rival or
	# a second claim silently reads the node as vacant (ADR 0085).
	HoldingsApi.set_store(WorldLedger.new())
	_actor = Actor.new()
	_actor.id = &"holder"
	HoldingsApi.attach(_actor)


## Release the process-wide singletons this suite installed. `HoldingsApi._store`,
## `HoldingsApi._resolver` and the `ResourceNodeCatalog` singleton all outlive the suite, so
## a suite that leaves them populated holds authored `ResourceNodeDef` resources alive until
## the engine shuts down. ObjectDB then reports leaked instances at exit and the process
## leaves non-zero **with every assertion green** — a suite that passes and still fails the
## run. Idempotent, and safe after an early return.
func teardown() -> void:
	_actor = null
	HoldingsApi.set_resolver(Callable())
	HoldingsApi.set_store(null)
	ResourceNodeCatalog.instance().reset()


func _node(
	node_id: StringName, yield_units: int, depletion: int, upkeep: int, floor_value: int = 0
) -> ResourceNodeDef:
	var node := ResourceNodeDef.new()
	node.node_id = node_id
	node.display_name = String(node_id)
	node.kind = &"ore"
	node.realm = &""
	node.yield_per_period = yield_units
	node.upkeep_per_period = upkeep
	node.depletion = depletion
	node.claim_floor = floor_value
	return node


## ## The PRODUCTION owner ref, verbatim (ADR 0248)
##
## `{kind, id}` and nothing else — exactly what `ForageScreen._owner()` and
## `ForageAction.owner_ref()` build. This helper used to accept a `standing` argument and
## put it in the ref, and every node it claimed was floor-0, so a suite could carry a ref
## shape no player path supplies and still be green. That is how a floor gate nobody could
## satisfy survived four audits. The parameter is gone so it cannot come back, and
## `test_holdings_claim_floor.gd` exercises the gate over the real authored corpus.
func _owner(id: StringName = &"player", kind: StringName = &"actor") -> Dictionary:
	return {"kind": String(kind), "id": String(id)}


func test_an_unheld_node_is_vacant_not_absent() -> void:
	# ADR 0083's three states. `{}` means there is no node; `vacant` means a node with no
	# holder. Collapsing them is what makes a screen render a vacancy as a zero.
	var summary := HoldingsApi.summary(_actor)
	assert_eq(summary.has("nodes"), true, "summary carries nodes")
	var result := HoldingsApi.claim(_actor, &"vein_test", _owner())
	assert_eq(
		bool(result["ok"]), true, "an unheld node can be claimed: %s" % result.get("reason", "")
	)
	assert_eq(bool(result["contested"]), false, "an unheld claim is not a contest")


func test_a_claim_on_held_ground_opens_a_standoff_and_moves_nothing() -> void:
	HoldingsApi.claim(_actor, &"vein_test", _owner(&"first"))
	var before := HoldingsApi.summary(_actor)
	var holder_before: Dictionary = (before["nodes"] as Dictionary)["vein_test"]["owner"]

	var rival := Actor.new()
	rival.id = &"rival"
	HoldingsApi.attach(rival)
	var result := HoldingsApi.claim(rival, &"vein_test", _owner(&"second"))

	assert_eq(bool(result["ok"]), true, "a challenge is accepted")
	assert_eq(bool(result["contested"]), true, "and it is named as a contest")
	var after := HoldingsApi.summary(rival)
	var holder_after: Dictionary = (after["nodes"] as Dictionary)["vein_test"]["owner"]
	# THE INVARIANT: ADR 0085's "a claim on held ground never moves ground".
	assert_eq(holder_after.get("id"), holder_before.get("id"), "the holder is byte-identical")


func test_a_second_challenge_is_refused() -> void:
	HoldingsApi.claim(_actor, &"vein_test", _owner(&"first"))
	var rival := Actor.new()
	HoldingsApi.attach(rival)
	HoldingsApi.claim(rival, &"vein_test", _owner(&"second"))
	var rival2 := Actor.new()
	HoldingsApi.attach(rival2)
	var result := HoldingsApi.claim(rival2, &"vein_test", _owner(&"third"))
	assert_eq(bool(result["ok"]), false, "two open standoffs on one node are refused")
	assert_eq(String(result["reason"]), HoldingsState.ALREADY_CONTESTED, "and it names the rule")


func test_an_unknown_node_refuses() -> void:
	var result := HoldingsApi.claim(_actor, &"no_such_vein", _owner())
	assert_eq(bool(result["ok"]), false, "an unknown node refuses")
	assert_eq(String(result["reason"]), HoldingsState.UNKNOWN_NODE, "and names the rule")


func test_an_institution_claim_without_a_resolver_refuses_loudly() -> void:
	# ADR 0002: a null injection fails loudly rather than dereferencing nothing. An
	# institution that silently cannot hold anything would be worse than an error.
	HoldingsApi.set_resolver(Callable())
	var result := HoldingsApi.claim(_actor, &"vein_test", _owner(&"azure_flame", &"sect"))
	assert_eq(bool(result["ok"]), false, "an institution claim with no resolver refuses")
	assert_eq(
		String(result["reason"]), HoldingsState.NO_RESOLVER, "and says the resolver is missing"
	)


func test_an_unresolvable_holder_refuses_with_the_resolver_s_own_reason() -> void:
	HoldingsApi.set_resolver(
		func(_kind: String, id: String) -> Dictionary:
			return {"ok": false, "reason": "unknown_sect"} if id == "ghost" else {"ok": true}
	)
	var result := HoldingsApi.claim(_actor, &"vein_test", _owner(&"ghost", &"sect"))
	assert_eq(bool(result["ok"]), false, "an unresolvable holder refuses")
	assert_eq(String(result["reason"]), "unknown_sect", "and passes the reason through verbatim")


## The kind vocabulary is OPEN (ADR 0933) and the RESOLVER is the one gate that answers
## "does this name something real". So this case installs a resolver that refuses an
## unregistered kind — the shape `test_holdings_claim_floor.gd` already pins — and asserts
## the refusal reaches the caller BY NAME rather than defaulting to `actor`.
func test_an_unknown_owner_kind_refuses_through_the_resolver() -> void:
	HoldingsApi.set_resolver(
		func(kind: String, _id: String) -> Dictionary:
			return (
				{"ok": true}
				if kind == "actor" or kind == "sect"
				else {"ok": false, "reason": HoldingsState.UNKNOWN_OWNER_KIND}
			)
	)
	var result := HoldingsApi.claim(_actor, &"vein_test", _owner(&"x", &"guild"))
	assert_eq(bool(result["ok"]), false, "an unregistered kind refuses")
	assert_eq(
		String(result["reason"]),
		HoldingsState.UNKNOWN_OWNER_KIND,
		"rather than defaulting to actor"
	)


func test_release_makes_a_node_vacant_again() -> void:
	HoldingsApi.claim(_actor, &"vein_test", _owner())
	var released := HoldingsApi.release(_actor, &"vein_test", _owner())
	assert_eq(bool(released["ok"]), true, "release is always allowed")
	var summary := HoldingsApi.summary(_actor)
	assert_eq(
		bool((summary["nodes"] as Dictionary)["vein_test"]["vacant"]),
		true,
		"and the node is vacant"
	)


func test_a_foreign_holder_cannot_release() -> void:
	HoldingsApi.claim(_actor, &"vein_test", _owner(&"first"))
	var result := HoldingsApi.release(_actor, &"vein_test", _owner(&"someone_else"))
	assert_eq(bool(result["ok"]), false, "a stranger cannot release a holding")
	assert_eq(String(result["reason"]), HoldingsState.HOLDER_MISMATCH, "and names the rule")


func test_summary_is_empty_without_an_actor() -> void:
	assert_eq(HoldingsApi.summary(null), {}, "summary is {} with no actor")


func test_state_round_trips_through_json() -> void:
	# ADR 0027: String keys throughout, no inner StringName.
	HoldingsApi.claim(_actor, &"vein_test", _owner())
	var payload := HoldingsApi.state(_actor)
	var restored: Variant = JSON.parse_string(JSON.stringify(payload))
	assert_eq(typeof(restored), TYPE_DICTIONARY, "the ledger is JSON-safe")
	var node: Dictionary = (restored as Dictionary)["nodes"]["vein_test"]
	assert_eq(typeof(node["owner"]["kind"]), TYPE_STRING, "the owner kind is a String")
	assert_eq(typeof(node["owner"]["id"]), TYPE_STRING, "the owner id is a String")


func test_catalog_rejects_a_node_that_yields_nothing() -> void:
	ResourceNodeCatalog.instance().reset()
	ResourceNodeCatalog.instance().install([_node(&"dead_vein", 0, 0, 0)])
	var problems := ResourceNodeCatalog.validate()
	assert_eq(problems.size() > 0, true, "a node that yields nothing fails the audit")
