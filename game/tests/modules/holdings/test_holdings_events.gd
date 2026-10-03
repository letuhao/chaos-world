extends TestCase

## ADR 0093 / ADR 0097: holdings publishes an event contract. The load-bearing assertion is
## that a CONTEST announces the UNCHANGED holder — a consumer that reads a challenge as a
## conquest is the exact failure ADR 0085 exists to prevent, and a signal that reported the
## challenger as the new holder would cause it.

var _actor: Actor
var _seen: Array[Dictionary] = []


func setup() -> void:
	ResourceNodeCatalog.instance().reset()
	ResourceNodeCatalog.instance().install([_node(&"vein_test", 4, 0, 0)])
	HoldingsApi.set_store(WorldLedger.new())
	HoldingsApi.set_resolver(func(_kind: String, _id: String) -> Dictionary: return {"ok": true})
	_actor = Actor.new()
	_actor.id = &"holder"
	HoldingsApi.attach(_actor)
	# `events()` is a SINGLETON (ADR 0093's shape), so a connection made by an earlier test is
	# still live and would add its own rows to `_seen`. Disconnecting first is what makes each
	# test's count mean "events from THIS test" — without it the count climbs monotonically and
	# the assertion stops testing anything.
	_seen.clear()
	_disconnect_all()
	HoldingsApi.events().node_claimed.connect(
		func(_a, _n, h): _seen.append({"kind": "claimed", "holder": h})
	)
	HoldingsApi.events().node_contested.connect(
		func(_a, _n, holder, challenger):
			_seen.append({"kind": "contested", "holder": holder, "challenger": challenger})
	)
	HoldingsApi.events().node_released.connect(
		func(_a, _n, h): _seen.append({"kind": "released", "holder": h})
	)
	HoldingsApi.events().node_accrued.connect(
		func(_a, _n, _h, p, y): _seen.append({"kind": "accrued", "periods": p, "yielded": y})
	)
	HoldingsApi.events().prize_applied.connect(
		func(_a, _n, prize, holder, winner):
			_seen.append({"kind": "prize", "prize": prize, "holder": holder, "winner": winner})
	)


## Release everything this suite installed on a process-wide singleton.
##
## `HoldingsApi.events()`, `HoldingsApi._store`/`_resolver` and
## `ResourceCatalog.instance()` are all statics that outlive the suite, so a suite that
## leaves them populated keeps its own connections — and the actors those lambdas
## captured — alive until the engine shuts down. ObjectDB then reports leaked instances
## at exit and the process leaves non-zero **with every assertion green**, which is the
## worst possible reading: a suite that passes and still fails the run.
func teardown() -> void:
	_disconnect_all()
	_seen.clear()
	_actor = null
	HoldingsApi.set_resolver(Callable())
	HoldingsApi.set_store(null)
	ResourceNodeCatalog.instance().reset()


## Drop every connection this suite made. A test framework that leaves signal connections on
## a shared singleton is how a green suite becomes order-dependent.
func _disconnect_all() -> void:
	var bus := HoldingsApi.events()
	for connection in bus.node_claimed.get_connections():
		bus.node_claimed.disconnect(connection["callable"])
	for connection in bus.node_contested.get_connections():
		bus.node_contested.disconnect(connection["callable"])
	for connection in bus.node_released.get_connections():
		bus.node_released.disconnect(connection["callable"])
	for connection in bus.node_accrued.get_connections():
		bus.node_accrued.disconnect(connection["callable"])
	for connection in bus.prize_applied.get_connections():
		bus.prize_applied.disconnect(connection["callable"])
	for connection in bus.holding_refused.get_connections():
		bus.holding_refused.disconnect(connection["callable"])


func _node(node_id: StringName, yield_units: int, depletion: int, upkeep: int) -> ResourceNodeDef:
	var node := ResourceNodeDef.new()
	node.node_id = node_id
	node.kind = &"ore"
	node.yield_per_period = yield_units
	node.depletion = depletion
	node.upkeep_per_period = upkeep
	return node


func _owner(id: StringName) -> Dictionary:
	return {"kind": "actor", "id": String(id)}


func test_events_are_a_singleton_reachable_from_the_facade() -> void:
	var events := HoldingsApi.events()
	assert_eq(events != null, true, "the contract is reachable")
	assert_eq(events == HoldingsApi.events(), true, "and it is one instance")


func test_a_claim_announces_the_new_holder() -> void:
	HoldingsApi.claim(_actor, &"vein_test", _owner(&"warden"))
	assert_eq(_seen.size(), 1, "one event was announced")
	assert_eq(String(_seen[0]["kind"]), "claimed", "a claim was announced")
	assert_eq(String(_seen[0]["holder"]), "warden", "naming the holder it wrote")


## A challenge must announce the UNCHANGED holder. The name is snake_case because
## `gdlint` rejects a capital in it; the emphasis lives here instead, and the
## assertions below are untouched.
func test_a_challenge_announces_the_unchanged_holder() -> void:
	# The whole point. The holder before and after a challenge is byte-identical (ADR 0085),
	# so the signal must report the holder — never the challenger.
	HoldingsApi.claim(_actor, &"vein_test", _owner(&"warden"))
	_seen.clear()
	var rival := Actor.new()
	rival.id = &"rival"
	HoldingsApi.attach(rival)
	HoldingsApi.claim(rival, &"vein_test", _owner(&"second"))
	assert_eq(_seen.size(), 1, "one event was announced")
	assert_eq(String(_seen[0]["kind"]), "contested", "a contest was announced")
	assert_eq(String(_seen[0]["holder"]), "warden", "reporting the UNCHANGED holder")
	assert_eq(String(_seen[0]["challenger"]), "second", "and naming the challenger separately")


func test_release_and_accrue_each_announce_themselves() -> void:
	HoldingsApi.claim(_actor, &"vein_test", _owner(&"warden"))
	_seen.clear()
	HoldingsApi.accrue(_actor, &"vein_test", _owner(&"warden"), 2)
	HoldingsApi.release(_actor, &"vein_test", _owner(&"warden"))
	assert_eq(_seen.size(), 2, "two events were announced")
	assert_eq(String(_seen[0]["kind"]), "accrued", "the accrual came first")
	assert_eq(int(_seen[0]["periods"]), 2, "carrying the caller's periods")
	assert_eq(int(_seen[0]["yielded"]), 8, "and what actually landed")
	assert_eq(String(_seen[1]["kind"]), "released", "then the release")


func test_a_paid_prize_announces_the_conflict_outcome() -> void:
	# The conflict-to-story seam: a decided standoff publishes what it paid, and the consumer
	# decides whether that is a chronicle line, a quest step or a screen.
	HoldingsApi.claim(_actor, &"vein_test", _owner(&"warden"))
	var rival := Actor.new()
	rival.id = &"rival"
	HoldingsApi.attach(rival)
	HoldingsApi.claim(rival, &"vein_test", _owner(&"second"))
	_seen.clear()
	var paid := HoldingsApi.apply_prize(
		_actor, &"vein_test", {"prize": &"ownership", "winner": _owner(&"second")}
	)
	assert_eq(bool(paid["ok"]), true, "the prize paid")
	assert_eq(_seen.size(), 1, "one event was announced")
	assert_eq(String(_seen[0]["kind"]), "prize", "a prize was announced")
	assert_eq(String(_seen[0]["prize"]), "ownership", "naming the declared prize shape")
	assert_eq(String(_seen[0]["winner"]), "second", "and the winner it paid")


func test_a_recognition_prize_announces_an_empty_holder_not_an_abandoned_node() -> void:
	# `recognition` moves no holder. Reporting an empty holder is correct here, and the signal
	# contract says so, so a consumer cannot read it as "the node was abandoned".
	HoldingsApi.claim(_actor, &"vein_test", _owner(&"warden"))
	var rival := Actor.new()
	rival.id = &"rival"
	HoldingsApi.attach(rival)
	HoldingsApi.claim(rival, &"vein_test", _owner(&"second"))
	_seen.clear()
	HoldingsApi.apply_prize(
		_actor, &"vein_test", {"prize": &"recognition", "winner": _owner(&"second")}
	)
	assert_eq(String(_seen[0]["prize"]), "recognition", "the recognition prize was announced")
	assert_eq(String(_seen[0]["holder"]), "warden", "and the holder is UNCHANGED, not empty")


func test_a_refused_verb_announces_nothing() -> void:
	# A refusal writes nothing and announces nothing: an event that fired on a refusal would
	# tell a consumer a fact became true when it did not.
	var before := _seen.size()
	var refused := HoldingsApi.claim(_actor, &"no_such_vein", _owner(&"warden"))
	assert_eq(bool(refused["ok"]), false, "the claim refused")
	assert_eq(_seen.size(), before, "and announced nothing")
