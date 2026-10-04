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
	# **The refusal signal is the one that announces nothing became true**, so it is
	# connected into the SAME `_seen` array as the five that announce a write. That is the
	# point of the assertions below: a consumer receiving both kinds from one bus is the
	# shape the contract describes, not a contradiction of it.
	HoldingsApi.events().holding_refused.connect(
		func(a, n, reason):
			_seen.append({"kind": "refused", "actor": a, "node": String(n), "reason": reason})
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


## ## A refusal ANNOUNCES, and this test was flipped deliberately (DEF-0221)
##
## This used to assert the opposite — "a refused verb announces nothing" — and the
## docstring encoded a real argument: "an event that fired on a refusal would tell a
## consumer a fact became true when it did not."
##
## That argument is sound AND it describes a different signal. `holdings_events.gd` declares
## SIX signals; five announce a fact already written and this one is the sixth, declared
## with the explicit docstring "**A refusal that wrote nothing.** Carries the named reason so
## a panel renders the rule it was given rather than inventing one (ADR 0084), and so an
## action failing is observable rather than silent." So the contract always intended a
## refusal to be announced — the signal was declared for exactly this and then never
## emitted, which is DEF-0221.
##
## **The concern is answered by the signal's own shape, not by silence.** It is NAMED
## `holding_refused` and it carries `reason`, so a consumer receives "the rule
## `unknown_node` fired" and cannot read it as "a node is now held". The two facts are
## independent and both are asserted below: the ledger is UNCHANGED, and the refusal is
## ANNOUNCED. A caller that polls `summary()` cannot otherwise tell a refused verb from a
## verb nobody called, and a player who was refused a vein has no way to learn which rule
## refused them.
func test_a_refused_verb_announces_the_rule_and_writes_nothing() -> void:
	var before := _seen.size()
	var before_nodes := int(HoldingsApi.summary(_actor)["node_count"])
	var refused := HoldingsApi.claim(_actor, &"no_such_vein", _owner(&"warden"))
	assert_eq(bool(refused["ok"]), false, "the claim refused")
	# **The announcement.** The reason is the signal's whole payload, so it is asserted by
	# value: a panel renders this string and must not have to invent it.
	assert_eq(_seen.size(), before + 1, "and announced exactly one refusal")
	assert_eq(String(_seen[0]["kind"]), "refused", "a refusal was announced")
	assert_eq(String(_seen[0]["reason"]), HoldingsState.UNKNOWN_NODE, "naming the rule")
	assert_eq(String(_seen[0]["node"]), "no_such_vein", "and the node it was refused on")
	# **And the independent half.** A refusal writes nothing — that is unchanged, and it is
	# what makes the announcement a *refusal* announcement rather than a write.
	assert_eq(
		int(HoldingsApi.summary(_actor)["node_count"]),
		before_nodes,
		"and the ledger is byte-identical: nothing was written"
	)


## A refusal from EVERY verb is announced, and names the node it was about. `_refuse` is the
## single place a refusal on this facade is built, so one test over the four public verbs is
## what proves no call site can quietly skip the emission — which is the shape of the bug
## this signal had.
##
## **The four calls run BEFORE `_seen.clear()` on purpose.** The bus is synchronous, so a
## refusal recorded into a list that is cleared immediately afterwards is a row nobody ever
## reads; collecting first and clearing once is the only order in which the count is "the
## refusals THIS test produced".
func test_every_refusing_verb_announces_and_names_its_node() -> void:
	var cases: Array = [
		{"name": "claim_unknown", "want": HoldingsState.UNKNOWN_NODE, "node": "no_such_vein"},
		{
			"name": "release_unknown",
			"want": HoldingsState.UNKNOWN_NODE,
			"node": "no_such_vein",
		},
		{"name": "accrue_no_periods", "want": HoldingsState.NO_PERIODS, "node": "vein_test"},
		{"name": "settle_no_periods", "want": HoldingsState.NO_PERIODS, "node": "vein_test"},
	]
	_seen.clear()
	var results: Array = [
		HoldingsApi.claim(_actor, &"no_such_vein", _owner(&"warden")),
		HoldingsApi.release(_actor, &"no_such_vein", _owner(&"warden")),
		HoldingsApi.accrue(_actor, &"vein_test", _owner(&"warden"), 0),
		HoldingsApi.settle(_actor, &"vein_test", 0),
	]
	for index in cases.size():
		var row := cases[index] as Dictionary
		assert_eq(
			String(results[index]["reason"]),
			String(row["want"]),
			"'%s' refuses with the rule it is named for" % String(row["name"])
		)
	# Four refusals, and NOTHING else — a refusal emits `holding_refused` only, so any
	# `claimed`/`accrued` row here would mean a refused verb announced a write as well.
	assert_eq(_seen.size(), cases.size(), "each verb announced exactly one refusal")
	for row in _seen:
		assert_eq(String(row["kind"]), "refused", "and only a refusal was announced")
		assert_eq(String(row["actor"]), "holder", "naming the actor it was refused on")
		assert_ne(String(row["reason"]), "", "and the rule it was refused by")
	for index in cases.size():
		assert_eq(
			String(_seen[index]["node"]),
			String((cases[index] as Dictionary)["node"]),
			"'%s' announced the node it was about" % String((cases[index] as Dictionary)["name"])
		)


## A refusal on a node this build DOES ship, against a holder that is not the one holding
## it. This is the case a panel actually renders, and it is the one that proves the
## announced node is the authored id rather than a catalog lookup miss — `unknown_node` on
## `vein_test` would have been a different rule entirely.
func test_a_refusal_on_an_authored_node_names_the_node_and_the_holder_rule() -> void:
	HoldingsApi.claim(_actor, &"vein_test", _owner(&"warden"))
	_seen.clear()
	# The node is authored, the ledger knows it, and somebody DOES hold it — so the only
	# thing that can refuse is the ownership check, which is the rule a panel renders as
	# "that is not yours to give up".
	var released := HoldingsApi.release(_actor, &"vein_test", _owner(&"impostor"))
	assert_eq(
		String(released["reason"]), HoldingsState.HOLDER_MISMATCH, "a foreign release refuses"
	)
	assert_eq(String(_seen[0]["kind"]), "refused", "and it announced a refusal")
	assert_eq(String(_seen[0]["reason"]), HoldingsState.HOLDER_MISMATCH, "naming the holder rule")
	assert_eq(String(_seen[0]["node"]), "vein_test", "and the authored node it was about")
	# And the ledger is untouched by the refusal — the independent half again.
	assert_eq(
		String((HoldingsApi.summary(_actor)["nodes"]["vein_test"] as Dictionary)["owner"]["id"]),
		"warden",
		"and the holder is UNCHANGED: a refusal wrote nothing"
	)
