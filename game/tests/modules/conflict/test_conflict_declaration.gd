extends TestCase

## ADR 0085 / ADR 0245: a standoff over a contested resource node is a DECLARATION plus a
## RESOLUTION, and the resolution pays the DECLARED prize.
##
## The load-bearing assertions here are the four the gap named:
##   - declaring writes a standoff;
##   - **a claim on held ground still does not move the holder** (byte-identical, ADR 0085);
##   - a resolution pays the declared prize EXACTLY ONCE and a second one refuses;
##   - the whole module is JSON-safe (String keys, no StringName/Actor/Resource inside).
##
## and two more that keep the design honest:
##   - an undeclared prize shape refuses BY NAME;
##   - a verdict naming an unknown side refuses BY NAME.
##
## `expect_assertions` is NOT declared per-test here: the runner charges a failure to any body
## that asserted nothing at all, which already covers a body that returned early, and `tools
## test`'s `SCRIPT ERROR` scan is what catches a body that died mid-way (DEF-0269).

## Every statics this suite installs on a process-wide singleton are released in `teardown`,
## which the runner calls after EVERY test. A suite that leaves them populated holds its own
## connections and `ResourceNodeDef` resources alive until the engine shuts down, and the
## process then leaves non-zero with every assertion green.
var _holder: Actor
var _rival: Actor
var _seen: Array[Dictionary] = []


func setup() -> void:
	ResourceNodeCatalog.instance().reset()
	ResourceNodeCatalog.instance().install([_node(&"vein_test", 4, 0, 2)])
	HoldingsApi.set_resolver(func(_kind: String, _id: String) -> Dictionary: return {"ok": true})
	# TWO shared stores, one per module: a standoff and the holdings ledger are separate world
	# facts (ADR 0101), and neither may fall back to an actor mirror or the two actors below
	# would each hold their own copy.
	HoldingsApi.set_store(WorldLedger.new())
	ConflictApi.set_store(ConflictWorldLedger.new())
	_holder = Actor.new()
	_holder.id = &"warden"
	HoldingsApi.attach(_holder)
	ConflictApi.attach(_holder)
	_rival = Actor.new()
	_rival.id = &"rival"
	HoldingsApi.attach(_rival)
	ConflictApi.attach(_rival)
	_seen.clear()
	_disconnect_all()
	var bus := ConflictApi.events()
	bus.standoff_declared.connect(
		func(_a, _n, conflict_id, prize, quota):
			_seen.append(
				{"kind": "declared", "conflict_id": conflict_id, "prize": prize, "quota": quota}
			)
	)
	bus.standoff_resolved.connect(
		func(_a, _n, conflict_id, prize, winner):
			(
				_seen
				. append(
					{
						"kind": "resolved",
						"conflict_id": conflict_id,
						"prize": prize,
						"winner": winner,
					}
				)
			)
	)
	bus.conflict_refused.connect(
		func(_a, n, reason): _seen.append({"kind": "refused", "node": String(n), "reason": reason})
	)


func teardown() -> void:
	_disconnect_all()
	_seen.clear()
	_holder = null
	_rival = null
	ConflictApi.set_store(null)
	HoldingsApi.set_resolver(Callable())
	HoldingsApi.set_store(null)
	ResourceNodeCatalog.instance().reset()


## Drop every connection this suite made. A test framework that leaves signal connections on a
## shared singleton is how a green suite becomes order-dependent.
func _disconnect_all() -> void:
	var bus := ConflictApi.events()
	for connection in bus.standoff_declared.get_connections():
		bus.standoff_declared.disconnect(connection["callable"])
	for connection in bus.standoff_resolved.get_connections():
		bus.standoff_resolved.disconnect(connection["callable"])
	for connection in bus.conflict_refused.get_connections():
		bus.conflict_refused.disconnect(connection["callable"])


func _node(node_id: StringName, yield_units: int, depletion: int, upkeep: int) -> ResourceNodeDef:
	var node := ResourceNodeDef.new()
	node.node_id = node_id
	node.kind = &"ore"
	node.display_name = String(node_id)
	node.yield_per_period = yield_units
	node.depletion = depletion
	node.upkeep_per_period = upkeep
	return node


func _owner(id: StringName) -> Dictionary:
	return {"kind": "actor", "id": String(id)}


## Claim the node for the holder, then challenge it as the rival. This is the state a standoff
## is declared over: an OPEN contest row `holdings` wrote and a holder it did not move.
func _contested() -> Dictionary:
	HoldingsApi.claim(_holder, &"vein_test", _owner(&"warden"))
	return HoldingsApi.claim(_rival, &"vein_test", _owner(&"rival"))


# --- the declaration ----------------------------------------------------------


func test_declaring_writes_a_standoff_with_its_declared_prize_and_quota() -> void:
	var contest := _contested()
	assert_eq(
		bool(contest["ok"]), true, "the challenge opened a contest: %s" % contest.get("reason", "")
	)
	var declared := ConflictApi.declare(
		_rival, &"vein_test", {"prize": &"ownership", "tribute_periods": 3}, 2
	)
	assert_eq(
		bool(declared["ok"]), true, "the declaration is accepted: %s" % declared.get("reason", "")
	)
	assert_eq(String(declared["prize"]), "ownership", "and it carries the declared prize shape")
	assert_eq(int(declared["quota"]), 2, "and the declared quota")
	# The LEDGER has it, not just the return value: a declaration that was built but never
	# saved is a standoff that silently did not happen (ADR 0101).
	var ledger := ConflictApi.state(_rival)
	var row := (ledger["standoffs"] as Dictionary)["vein_test"] as Dictionary
	assert_ne(row.is_empty(), true, "the standoff is written to the world ledger")
	assert_eq(String(row["holder"]["id"]), "warden", "naming the unchanged holder as one side")
	assert_eq(String(row["challenger"]["id"]), "rival", "and the challenger as the other")
	assert_eq(int(row["verdicts"]), 0, "with no verdict counted yet")
	assert_eq(_seen.size(), 1, "and the declaration was announced once")
	assert_eq(String(_seen[0]["kind"]), "declared", "as a declaration")


## ADR 0085's invariant, at full strength: **byte-identical**, not merely "unchanged" in
## intent. The holder before and after a claim AND after a declaration is the same dictionary,
## so a consumer that read a challenge as a conquest could not tell from the data.
func test_a_claim_on_held_ground_does_not_move_the_holder_byte_for_byte() -> void:
	HoldingsApi.claim(_holder, &"vein_test", _owner(&"warden"))
	var before := (
		(HoldingsApi.summary(_holder)["nodes"] as Dictionary)["vein_test"]["owner"] as Dictionary
	)
	_contested()
	ConflictApi.declare(_rival, &"vein_test", {"prize": &"ownership"}, 1)
	var after := (
		(HoldingsApi.summary(_holder)["nodes"] as Dictionary)["vein_test"]["owner"] as Dictionary
	)
	assert_eq(
		after.get("id"),
		before.get("id"),
		"the holder is byte-identical across a challenge and a declaration"
	)
	assert_eq(after.get("kind"), before.get("kind"), "and so is its kind")
	assert_eq(after.size(), before.size(), "and so is its shape: nothing was merged in")


# --- the payout ---------------------------------------------------------------


func test_a_resolution_pays_the_declared_prize_exactly_once() -> void:
	_contested()
	ConflictApi.declare(_rival, &"vein_test", {"prize": &"ownership"}, 1)
	_seen.clear()
	var paid := ConflictApi.resolve(_rival, &"vein_test", "rival")
	assert_eq(bool(paid["ok"]), true, "the resolution is accepted: %s" % paid.get("reason", ""))
	assert_eq(bool(paid["paid"]), true, "and it PAID rather than merely counting")
	assert_eq(String(paid["prize"]), "ownership", "the DECLARED prize, not a computed one")
	# The holder swapped, and only because `holdings` was told to do it.
	assert_eq(_holder_id(), "rival", "holdings paid the ownership swap")
	# And the contest row is cleared, so the node is no longer contested.
	var node := (HoldingsApi.summary(_holder)["nodes"] as Dictionary)["vein_test"] as Dictionary
	assert_eq(bool(node["contested"]), false, "and the standoff row holdings owned is cleared")
	# The announcement names the prize that was declared, once.
	var resolved := _filter("resolved")
	assert_eq(resolved.size(), 1, "exactly one resolution was announced")
	assert_eq(String(resolved[0]["prize"]), "ownership", "naming the declared prize shape")
	assert_eq(String(resolved[0]["winner"]), "rival", "and the winner the verdict named")


## The prize is paid ONCE. A second resolution refuses BY NAME and moves nothing — the
## double-payout is the failure a paid war nobody can re-answer exists to prevent.
func test_a_second_resolution_refuses_and_pays_nothing() -> void:
	_contested()
	ConflictApi.declare(_rival, &"vein_test", {"prize": &"ownership"}, 1)
	assert_eq(
		bool(ConflictApi.resolve(_rival, &"vein_test", "rival")["paid"]), true, "the first resolved"
	)
	var owner_after := _holder_id()
	_seen.clear()
	var again := ConflictApi.resolve(_rival, &"vein_test", "warden")
	assert_eq(bool(again["ok"]), false, "a second resolution refuses")
	assert_eq(
		String(again["reason"]),
		ConflictState.ALREADY_RESOLVED,
		"and names the rule rather than inventing a reason"
	)
	assert_eq(_holder_id(), owner_after, "and the holder is untouched by the refusal")
	assert_eq(_filter("resolved").size(), 0, "no second payout was announced")
	assert_eq(_filter("refused").size(), 1, "and the refusal was announced, carrying its rule")


## A quota is a quota: a verdict below it is counted and pays nothing, and the standoff stays
## open. This is why `resolve` is safe to call from the place a fight decides — one call is one
## exchange, and the quota decides whether that exchange ended anything.
func test_a_verdict_below_the_quota_counts_and_pays_nothing() -> void:
	_contested()
	ConflictApi.declare(_rival, &"vein_test", {"prize": &"ownership"}, 3)
	_seen.clear()
	var first := ConflictApi.resolve(_rival, &"vein_test", "rival")
	assert_eq(bool(first["ok"]), true, "the verdict is accepted")
	assert_eq(bool(first["paid"]), false, "but the quota of three is not met")
	assert_eq(int(first["verdicts"]), 1, "so it is COUNTED")
	assert_eq(_holder_id(), "warden", "and the holder has not moved")
	var row := (ConflictApi.state(_rival)["standoffs"] as Dictionary)["vein_test"] as Dictionary
	assert_eq(bool(row["resolved"].is_empty()), true, "the standoff is still OPEN")


# --- the refusals -------------------------------------------------------------


## ADR 0085's one prohibition is a resolution that quietly invents what was at stake, so a
## prize outside the closed vocabulary refuses **by name** and writes NOTHING.
func test_an_undeclared_prize_shape_refuses_by_name_and_writes_nothing() -> void:
	_contested()
	var before := ConflictApi.state(_rival)
	for prize in [&"conquest", "", &"victory_points", &"damage"]:
		var refused := ConflictApi.declare(_rival, &"vein_test", {"prize": prize}, 1)
		assert_eq(bool(refused["ok"]), false, "a prize of '%s' refuses" % String(prize))
		assert_eq(
			String(refused["reason"]),
			ConflictState.UNDECLARED_PRIZE,
			"and names `undeclared_prize` rather than defaulting to ownership"
		)
	assert_eq(
		ConflictApi.state(_rival),
		before,
		"and the world ledger is byte-identical: four refusals wrote nothing"
	)


## A verdict naming somebody the declaration did not name refuses `unknown_side`. The
## alternative — resolving a standoff between two parties the caller did not pick between — is
## a verdict this module has no authority to reach.
func test_a_verdict_naming_an_unknown_side_refuses_by_name() -> void:
	_contested()
	ConflictApi.declare(_rival, &"vein_test", {"prize": &"ownership"}, 1)
	_seen.clear()
	var refused := ConflictApi.resolve(_rival, &"vein_test", "somebody_else")
	assert_eq(bool(refused["ok"]), false, "a verdict naming a stranger refuses")
	assert_eq(String(refused["reason"]), ConflictState.UNKNOWN_SIDE, "and names `unknown_side`")
	assert_eq(_holder_id(), "warden", "and the holder did not move")
	assert_eq(_filter("resolved").size(), 0, "nothing was announced as resolved")


## No claimant, no standoff. A node nobody contests has no prize to pay, and the refusal is
## the rule rather than a default winner.
func test_declaring_over_an_uncontested_node_refuses_by_name() -> void:
	HoldingsApi.claim(_holder, &"vein_test", _owner(&"warden"))
	_seen.clear()
	var refused := ConflictApi.declare(_rival, &"vein_test", {"prize": &"ownership"}, 1)
	assert_eq(
		bool(refused["ok"]), false, "a node nobody contested has no standoff to bind a prize to"
	)
	assert_eq(
		String(refused["reason"]),
		ConflictState.NO_CONTEST,
		"and names `no_contest` rather than opening one here"
	)
	assert_eq(_filter("declared").size(), 0, "and no standoff was announced")


func test_a_quota_outside_its_bounds_refuses_by_name() -> void:
	_contested()
	var before := ConflictApi.state(_rival)
	for quota in [0, -3, ConflictState.MAX_QUOTA + 1]:
		var refused := ConflictApi.declare(_rival, &"vein_test", {"prize": &"ownership"}, quota)
		assert_eq(bool(refused["ok"]), false, "a quota of %d refuses" % quota)
		assert_eq(String(refused["reason"]), ConflictState.BAD_QUOTA, "and names `bad_quota`")
	assert_eq(ConflictApi.state(_rival), before, "and wrote nothing")


# --- persistence and shape ---------------------------------------------------


## ADR 0101's whole point: a standoff is a WORLD fact. Two actors, ONE store, and the verdict
## resolves against a row the other side can see — the bug the ADR says was found and fixed
## twice in this program.
func test_a_standoff_is_one_world_fact_shared_by_both_parties() -> void:
	_contested()
	ConflictApi.declare(_rival, &"vein_test", {"prize": &"ownership"}, 1)
	# Read through the HOLDER, who never declared anything.
	var from_holder := ConflictApi.state(_holder)
	var row := (from_holder["standoffs"] as Dictionary).get("vein_test", {}) as Dictionary
	assert_ne(row.is_empty(), true, "the holder can see the standoff the rival declared")
	assert_eq(String(row["challenger"]["id"]), "rival", "naming the rival as the challenger")
	assert_eq(int(HoldingsApi.summary(_holder)["contested_count"]), 1, "and it is a real contest")


## ## The whole module is JSON-safe
##
## `Actor.to_dict` converts only the OUTER `module_data` key (ADR 0027), so an inner
## `StringName`, `Actor` or `Resource` reaches the save untouched and breaks every round trip.
## This walks the ledger recursively rather than asserting one key, because the defect is
## exactly the key nobody looked at.
func test_the_whole_ledger_is_json_safe() -> void:
	_contested()
	ConflictApi.declare(_rival, &"vein_test", {"prize": &"ownership", "tribute_periods": 2}, 2)
	ConflictApi.resolve(_rival, &"vein_test", "rival")
	var payload := ConflictApi.state(_rival)
	var wire := JSON.stringify(payload)
	var restored: Variant = JSON.parse_string(wire)
	assert_eq(typeof(restored), TYPE_DICTIONARY, "the ledger survives a JSON round trip")
	# The round trip must be LOSSLESS, not merely parseable: a StringName key is dropped by
	# the JSON encoder rather than converted, so an unequal pair is the real failure.
	#
	# ## …measured against the WIRE, not against the live ledger
	#
	# This compared `restored` to `payload`, and it failed on `version: 1` versus `1.0` —
	# on a value the module never wrote as a float. `JSON.parse_string` in this engine widens
	# EVERY integral number to a float: `JSON.parse_string('{"v":1}')` answers `{ "v": 1.0 }`.
	# So the round trip is lossy for any payload at all, and comparing it to a ledger that
	# correctly holds ints measures the parser, not the module.
	#
	# `wire` is the right yardstick, because `wire` is what a save actually stores: the bytes
	# on disk are produced by `JSON.stringify` and read back by a parser, and BOTH ends of
	# that have now been observed. Comparing `restored` against a re-parse of `wire` proves
	# the module's values encode to JSON that survives re-decoding unchanged, which is the
	# property ADR 0027 is about — and it still fails if a `StringName` key is dropped,
	# because the encoder writes `&"ownership"` as `"ownership"` while `payload` keeps it a
	# `StringName`, so the loss shows up as an unequal pair either way.
	assert_eq(
		restored,
		JSON.parse_string(wire),
		"and the round trip is lossless: no StringName key anywhere"
	)
	# …and the ledger itself is int-clean going in, which is what makes the wire comparison
	# above a statement about the module rather than a tautology about the parser.
	assert_eq(
		_reasons(payload), 0, "and no StringName, Actor or Resource is hidden anywhere inside it"
	)
	# And no whole number is published as a float where a whole period, a whole quota or a
	# whole count was declared: `2.0` in a save reads back as a fractional tribute.
	for path in ["version"] + _int_paths(payload):
		assert_eq(
			typeof(_at(payload, path)),
			TYPE_INT,
			"and '%s' is published as an int, not a float" % path
		)
	var summary := ConflictApi.summary(_rival)
	assert_eq(_reasons(summary), 0, "and the read model a screen renders is JSON-safe too")


# --- the event contract and the read model -----------------------------------


func test_events_are_a_singleton_reachable_from_the_facade() -> void:
	assert_ne(ConflictApi.events(), null, "the contract is reachable")
	assert_eq(ConflictApi.events() == ConflictApi.events(), true, "and it is one instance")


func test_a_refusal_announces_the_rule_it_names() -> void:
	_seen.clear()
	ConflictApi.declare(_rival, &"vein_test", {"prize": &"conquest"}, 1)
	assert_eq(_seen.size(), 1, "the refusal announced exactly one row")
	assert_eq(String(_seen[0]["kind"]), "refused", "and it is a refusal, not a write")
	assert_eq(String(_seen[0]["reason"]), ConflictState.UNDECLARED_PRIZE, "naming the rule")
	assert_eq(String(_seen[0]["node"]), "vein_test", "and the node it was about")


func test_summary_is_empty_without_an_actor() -> void:
	assert_eq(ConflictApi.summary(null), {}, "summary is {} with no actor (ADR 0083)")
	assert_eq(ConflictApi.state(null), ConflictState.empty(), "and so is state")


func test_the_read_model_publishes_the_declared_prize_verbatim() -> void:
	_contested()
	ConflictApi.declare(_rival, &"vein_test", {"prize": &"tribute", "tribute_periods": 4}, 1)
	var row := (ConflictApi.summary(_rival)["standoffs"] as Dictionary)["vein_test"] as Dictionary
	assert_eq(
		String(row["prize"]["prize"]), "tribute", "the DECLARED prize is published as declared"
	)
	assert_eq(int(row["prize"]["tribute_periods"]), 4, "carrying its declared terms")
	assert_eq(bool(row["open"]), true, "and the standoff reads as open")
	assert_eq(String(row["holder"]["id"]), "warden", "naming the unchanged holder")
	assert_eq(String(row["winner_id"]), "", "and an undecided standoff names no winner")


# --- helpers ------------------------------------------------------------------


func _filter(kind: String) -> Array:
	var out: Array = []
	for row in _seen:
		if String(row["kind"]) == kind:
			out.append(row)
	return out


## The id of whoever currently holds the node, read through `holdings`' own facade. `""` when
## the node has no holder, which is ADR 0083's "not a holder" rather than an error.
##
## Every holder assertion in this suite goes through here, so a change to the read shape is one
## edit rather than the same cast repeated at ten call sites — and so a test that accidentally
## compared two DIFFERENT reads of the holder cannot pass by construction.
func _holder_id() -> String:
	var node := (HoldingsApi.summary(_holder)["nodes"] as Dictionary)["vein_test"] as Dictionary
	var owner := node["owner"] as Dictionary
	return String(owner.get("id", ""))


## Every leaf under `key` in `value`, as a dotted path, that is a whole number — i.e. every
## place the module publishes a count, a quota or a period count. Used to assert each is an
## `int`, because `2.0` in a save reads back as a fractional tribute and the round trip alone
## cannot say so: this engine's parser widens integers to floats on the way in, which would
## hide a float the module had already written.
##
## Recursion with the same depth cap `_reasons` uses, and for the same reason.
func _int_paths(value: Dictionary, prefix: String = "", depth: int = 0) -> Array[String]:
	var out: Array[String] = []
	if depth > 8:
		return out
	for key in value.keys():
		var path := "%s.%s" % [prefix, String(key)] if prefix != "" else String(key)
		var leaf = value[key]
		match typeof(leaf):
			TYPE_DICTIONARY:
				out.append_array(_int_paths(leaf as Dictionary, path, depth + 1))
			TYPE_INT, TYPE_FLOAT:
				# Only WHOLE numbers are at stake. A real float would have been authored as
				# one, and this ledger declares none — but the check must not claim otherwise.
				if float(leaf) == floor(float(leaf)):
					out.append(path)
	return out


## The leaf a dotted `path` from `_int_paths` names. Indexed STEP BY STEP rather than with
## `payload[path]`, because a GDScript dictionary index takes one key: handing it
## `"standoffs.vein_test.prize.tribute_periods"` is a lookup of that literal key, which is
## absent, and an absent key on a typed dictionary is a SCRIPT ERROR rather than a null —
## so the assertion loop would abort mid-function and the runner would score the test as
## neither passed nor failed.
func _at(value: Dictionary, path: String) -> Variant:
	var cursor: Variant = value
	for segment in path.split("."):
		if not cursor is Dictionary:
			return null
		cursor = (cursor as Dictionary).get(segment)
	return cursor


## How many leaves of `value` are a `StringName`, an `Object` (an `Actor` is one) or a
## `Resource`, at any depth. Recursion with an explicit depth cap: a recursive walk needs one,
## and the depth is a constant rather than a bound this walk is itself growing.
func _reasons(value: Variant, depth: int = 0) -> int:
	if depth > 8:
		return 0
	var found := 0
	match typeof(value):
		TYPE_DICTIONARY:
			for key in (value as Dictionary).keys():
				if typeof(key) != TYPE_STRING:
					found += 1
				found += _reasons((value as Dictionary)[key], depth + 1)
		TYPE_ARRAY:
			for item in value as Array:
				found += _reasons(item, depth + 1)
		TYPE_OBJECT, TYPE_STRING_NAME:
			found += 1
	return found
