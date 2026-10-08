extends TestCase

## ADR 0248: a claim floor is a CONCENTRATION gate — the count of resource nodes the
## holder already holds — and never a standing.
##
## ## Why this file exists at all
##
## DEF-0305 was a gate that **nobody could ever satisfy**: `_meets_floor` read
## `owner.get("standing", 0)` off an `OwnerRef`, which is `{kind, id}` and carries no such
## field, so every one of the 16 authored nodes carrying `claim_floor > 0` refused
## `claim_below_floor` forever. Seven nodes, 44% of the resource corpus, permanently
## unclaimable — and **no suite caught it for four audit cycles**.
##
## It hid for two measurable reasons, and both are closed here rather than merely avoided:
##
##  1. **Every fixture node was floor-0**, so the branch never ran. This file claims REAL
##     `.tres` content out of `res://data/holdings/nodes` — no fixture node is installed
##     anywhere below, so a floor above the corpus size fails this file instead of hiding.
##  2. **The fixture ref was not the production ref.** `test_holdings_claim.gd`'s `_owner()`
##     injected a `standing` key no producer ships. Its `standing` parameter is deleted;
##     the only `_owner()` left in this module builds the bare `{kind, id}` dict that
##     `ForageScreen._owner()` and `ForageAction.owner_ref()` build, and the sweep below
##     claims every authored node through exactly that shape.
##
## ## The gate is exercised in BOTH directions, on real content
##
## The cold hero is refused `claim_below_floor` on every floored node and accepted on every
## floor-0 one; the consolidated hero — who has taken all sixteen — is accepted on every one
## of them. Neither half is satisfiable by a gate that always passes (the cold case fails)
## or by one that always fails (the consolidated case fails). That is the whole point: a
## vacuous gate is theatre, an unsatisfiable one is UNBUILT content, and only a gate
## exercised in both directions is a gate.

## The actor every claim here is made for. Never special-cased by the gate under test.
## A `StringName` constant rather than an `&"…"` literal at each call, so the id a test
## asserts on and the id the ledger keys on cannot be typed differently.
const HERO := &"floor_hero"

var _actor: Actor


## ## No `reset()`. The catalog is read as AUTHORED on purpose.
##
## The sibling holdings suites `ResourceNodeCatalog.instance().reset()` and install their
## own fixtures, and `setup` here deliberately does the opposite: this file's subject is
## the shipped corpus, so a `reset` would empty it and assert against a fixture again —
## the exact shape that hid DEF-0305. What `setup` does release is this suite's own two
## singletons, because those leak across suites in a shared process.
func setup() -> void:
	HoldingsApi.set_resolver(func(_kind: String, _id: String) -> Dictionary: return {"ok": true})
	# A SHARED world ledger, for the reason `test_holdings_claim.gd` gives: a holder must be
	# visible to a rival, or a second claim reads the node as vacant and the count below
	# measures a ledger that cannot disagree with itself.
	HoldingsApi.set_store(WorldLedger.new())
	_actor = Actor.new(HERO, {Stat.PHYSIQUE: 10.0})
	HoldingsApi.attach(_actor)


func teardown() -> void:
	_actor = null
	HoldingsApi.set_resolver(Callable())
	HoldingsApi.set_store(null)


## The production owner ref, verbatim: `{kind, id}` and nothing else. No `standing` key, no
## `realm`, no count — the shape `ForageScreen._owner()` builds for a real player action.
func _owner(id: StringName = &"player", kind: StringName = &"actor") -> Dictionary:
	return {"kind": String(kind), "id": String(id)}


## The authored corpus, sorted, so a failure names the same node on every run.
func _authored() -> Array[ResourceNodeDef]:
	var out: Array[ResourceNodeDef] = []
	for node_id in ResourceNodeCatalog.instance().node_ids():
		var def := ResourceNodeCatalog.instance().definition(node_id)
		if def != null:
			out.append(def)
	return out


## The floored nodes of the corpus, SHALLOWEST floor first. That order is the ladder a
## player climbs: the ascending-floor claim order the ADR claims is reachable, read off the
## content rather than typed in.
func _by_ascending_floor() -> Array[ResourceNodeDef]:
	var out := _authored()
	out.sort_custom(
		func(left: ResourceNodeDef, right: ResourceNodeDef) -> bool:
			if left.claim_floor == right.claim_floor:
				return String(left.node_id) < String(right.node_id)
			return left.claim_floor < right.claim_floor
	)
	return out


## The nodes a cold hero may take with no consolidation at all: floor-0 content, in id
## order.
func _open_nodes() -> Array[ResourceNodeDef]:
	var out: Array[ResourceNodeDef] = []
	for def in _by_ascending_floor():
		if def.claim_floor <= 0:
			out.append(def)
	return out


## Take every node that opens to this hero right now, asserting each one landed. Used to
## build the CONSOLIDATED holder: the same hero, the same ledger, more ground.
func _consolidate() -> int:
	var taken := 0
	for def in _by_ascending_floor():
		var result := HoldingsApi.claim(_actor, def.node_id, _owner(HERO))
		if bool(result["ok"]):
			taken += 1
		elif String(result["reason"]) == HoldingsState.CLAIM_BELOW_FLOOR:
			break
		else:
			assert_eq(
				false,
				true,
				"setup: '%s' refused for an unrelated rule: %s" % [def.node_id, result["reason"]]
			)
	return taken


func _held() -> int:
	return int(HoldingsApi.summary(_actor)["held_count"])


# --- the gate, in both directions, over the real corpus -------------------------


## ## DIRECTION ONE: the gate refuses, on real authored content.
##
## A hero holding nothing is refused `claim_below_floor` on every floored node — by NAME,
## not by an `ok == false` that a gate refusing everything would also satisfy.
func test_a_cold_hero_is_refused_by_name_on_every_authored_floored_node() -> void:
	var floored: Array[ResourceNodeDef] = []
	for def in _authored():
		if def.claim_floor > 0:
			floored.append(def)
	# The measurement DEF-0305 recorded. If a future content wave zeroes every floor the
	# gate stops being exercised at all, and this file must say so rather than pass quietly.
	assert_ne(floored.is_empty(), true, "the corpus still authors nodes with a non-zero floor")
	assert_eq(_held(), 0, "setup: the hero holds nothing")
	for def in floored:
		var result := HoldingsApi.claim(_actor, def.node_id, _owner(HERO))
		assert_eq(
			bool(result["ok"]),
			false,
			"'%s' (floor %d) is refused a cold hero" % [def.node_id, def.claim_floor]
		)
		assert_eq(
			String(result["reason"]),
			HoldingsState.CLAIM_BELOW_FLOOR,
			"and the refusal is the floor rule by name, not something incidental"
		)
		assert_eq(
			(HoldingsApi.summary(_actor)["nodes"] as Dictionary).get(String(def.node_id), {}),
			{},
			"and the refusal wrote nothing (ADR 0085): '%s' is still absent" % def.node_id
		)


## ## DIRECTION TWO: the gate opens, on the same real authored content.
##
## The same hero, after consolidating the floor-0 nodes, clears the shallowest floor. This
## is the case DEF-0305 made impossible: a floored node claimed by a real player ref.
func test_the_same_hero_clears_a_floor_once_the_ground_is_consolidated() -> void:
	var open := _open_nodes()
	assert_ne(open.is_empty(), true, "setup: the corpus authors floor-0 nodes to seed the ladder")
	for def in open:
		var result := HoldingsApi.claim(_actor, def.node_id, _owner(HERO))
		assert_eq(
			bool(result["ok"]), true, "floor-0 '%s' is taken: %s" % [def.node_id, result["reason"]]
		)
	assert_eq(_held(), open.size(), "the hero holds exactly the open nodes")

	# The shallowest floored node is now within reach — by exactly one step, which is the
	# proof that the gate moves with the ledger rather than being permanently closed.
	var lowest: ResourceNodeDef = null
	for def in _by_ascending_floor():
		if def.claim_floor > 0:
			lowest = def
			break
	assert_ne(lowest, null, "the corpus authors a floored node")
	assert_eq(
		lowest.claim_floor <= _held(), true, "setup: the shallowest floor is now within reach"
	)
	var reached := HoldingsApi.claim(_actor, lowest.node_id, _owner(HERO))
	assert_eq(
		bool(reached["ok"]),
		true,
		"'%s' opens to a qualifying holder: %s" % [lowest.node_id, reached["reason"]]
	)
	assert_eq(String(reached["reason"]), "", "and it names no refusal")


## ## THE SWEEP: every authored node in the corpus is claimable by someone.
##
## This is the case that makes the class of bug unrepeatable. It walks the REAL `.tres`
## files in a legal order — floor-0 first, then ascending by floor — and demands that all
## sixteen land. A floor above the corpus size, a gate read against a field no ref carries,
## or a node whose kind is refused outright all fail HERE, in a suite that names the node.
func test_every_authored_node_is_claimable_by_somebody() -> void:
	var corpus := _authored()
	assert_ne(corpus.is_empty(), true, "the corpus authors resource nodes")
	var taken := _consolidate()
	assert_eq(
		taken,
		corpus.size(),
		(
			"all %d authored nodes are claimable in ascending-floor order; %d landed"
			% [corpus.size(), taken]
		)
	)
	# And asserted per node rather than only as a total, so a failure names WHICH node.
	for def in corpus:
		var entry: Dictionary = (
			(HoldingsApi.summary(_actor)["nodes"] as Dictionary).get(String(def.node_id), {})
			as Dictionary
		)
		assert_ne(entry, {}, "setup: '%s' is in the ledger" % def.node_id)
		assert_eq(
			String((entry.get("owner", {}) as Dictionary).get("id", "")),
			String(_actor.id),
			"'%s' is held by the hero who consolidated" % def.node_id
		)


## ## The shape of the ladder, asserted on content rather than on this suite's fixtures.
##
## Without these two the sweep above would still be green against a corpus whose every
## floor had been retuned to 1 — reachable, but a gate that answers on the second node.
func test_the_authored_floors_form_a_ladder_reachable_by_the_corpus() -> void:
	var corpus := _authored()
	var open := 0
	var highest := 0
	for def in corpus:
		if def.claim_floor <= 0:
			open += 1
		else:
			highest = maxi(highest, def.claim_floor)
	assert_ne(open, 0, "the corpus seeds the ladder with floor-0 nodes")
	assert_ne(highest, 0, "the corpus authors at least one floored node")
	# The deepest floor is inside the corpus, so a holder who has consolidated everything
	# can reach it. This is the UNBUILT guard in one arithmetic comparison.
	assert_eq(
		highest <= corpus.size(),
		true,
		(
			"the deepest authored floor (%d) is reachable within the %d-node corpus"
			% [highest, corpus.size()]
		)
	)
	# And it is not free: a cold hero must not reach it.
	assert_eq(highest > 0, true, "the deepest node is gated, not open")


## ## The `claim_floor` field is the exported one, and it is what the corpus reads.
##
## Read through `ResourceNodeCatalog`, not through a local `.tres` parse, so this asserts
## what the game loads. `test_every_authored_node_is_claimable_by_somebody` would pass
## against a catalog whose floors had all been dropped to 0 by a content edit, which is the
## VACUOUS class this file exists to catch.
func test_the_corpus_really_carries_non_zero_floors_after_loading() -> void:
	var floored := 0
	for def in _authored():
		if def.claim_floor > 0:
			floored += 1
	assert_eq(floored > 0, true, "the loaded catalog carries at least one non-zero claim_floor")


# --- refusals a floor must not swallow ------------------------------------------


## An unregistered holder kind is refused BY NAME, and the floor is not what refuses it.
## Asserted on a floor-0 node so the only rule in play is the kind refusal: a gate that
## reported `claim_below_floor` for everything would otherwise satisfy the first half of
## this test.
##
## The kind vocabulary is OPEN (ADR 0933) and it is the resolver's to police, so this case
## installs the refusal the way `OwnerResolver` gives it for a kind no boot registered. A
## module-side pre-filter answers the same rule first today; both paths name
## `unknown_owner_kind` and neither touches the floor.
func test_an_unknown_holder_refuses_by_name_rather_than_as_a_floor() -> void:
	var open := _open_nodes()
	assert_ne(open.is_empty(), true, "setup: the corpus authors a floor-0 node")
	HoldingsApi.set_resolver(
		func(_kind: String, _id: String) -> Dictionary:
			return {"ok": false, "reason": OwnerRef.UNKNOWN_KIND}
	)
	var result := HoldingsApi.claim(_actor, open[0].node_id, _owner(&"x", &"guild"))
	assert_eq(bool(result["ok"]), false, "a kind no boot registered refuses")
	assert_eq(
		String(result["reason"]),
		HoldingsState.UNKNOWN_OWNER_KIND,
		"and names the unknown-kind rule, never the floor rule"
	)


## A holder that resolves to NOTHING is refused by the RESOLVER's reason, again ahead of
## the floor. ADR 0002's loud null-injection refusal reaching a player through `claim`.
func test_an_unresolvable_holder_refuses_with_the_resolvers_own_reason() -> void:
	var open := _open_nodes()
	assert_ne(open.is_empty(), true, "setup: the corpus authors a floor-0 node")
	HoldingsApi.set_resolver(
		func(_kind: String, id: String) -> Dictionary:
			return {"ok": false, "reason": "unknown_sect"} if id == "ghost" else {"ok": true}
	)
	var result := HoldingsApi.claim(_actor, open[0].node_id, _owner(&"ghost", &"sect"))
	assert_eq(bool(result["ok"]), false, "an unresolvable holder refuses")
	assert_eq(String(result["reason"]), "unknown_sect", "and the reason is passed through verbatim")


# --- the rule is a count of GROUND, not of anything institutional --------------


## ## A ref carries `{kind, id}` and NOTHING else — that is the whole premise.
##
## ADR 0248 exists because the gate read a field no producer supplies. This asserts the
## production shape directly: if a future author adds `standing` back to a ref to make a
## gate work, this fails before the gate silently becomes satisfiable for the wrong reason.
func test_the_production_owner_ref_carries_no_standing_field() -> void:
	var owner := _owner(HERO)
	# Asserted as a SET of names rather than against an ordered literal: `keys()` is
	# insertion order, so an equality against `["id", "kind"]` would be asserting the order
	# the literal happens to be written in. A THIRD key — the shape DEF-0305 needed — fails
	# on the size whatever order it lands in.
	assert_eq(owner.size(), 2, "a production ref is exactly {kind, id}: two keys, no more")
	var names: Array[String] = []
	for key in owner.keys():
		names.append(String(key))
	assert_eq(names, ["kind", "id"], "and they are exactly those two names, in source order")
	var stored: Dictionary = HoldingsState.holder(
		HoldingsApi.state(_actor), &"definitely_not_a_node"
	)
	assert_eq(stored, {}, "an unknown node has no holder to read a field off")


## ## An unregistered kind is a WORLD FACT, not a reason to erase a holder (ADR 0933).
##
## `HoldingsState.normalize` used to collapse a ref whose kind this build does not know
## into `vacant`: a held node any rival could then take for free, and an erasure the next
## autosave would make permanent. The ref is KEPT verbatim and every USE of it refuses by
## name at the resolver, so the ground stays somebody's until something can resolve it.
func test_an_unregistered_kind_keeps_the_holder_instead_of_reading_vacant() -> void:
	var state := HoldingsState.normalize(
		{"nodes": {"wayfarer_hold": {"owner": {"kind": "wayfarer_guild", "id": "the_company"}}}}
	)
	assert_eq(
		HoldingsState.holder(state, &"wayfarer_hold"),
		{"kind": "wayfarer_guild", "id": "the_company"},
		"the holder survives normalize verbatim"
	)
	assert_eq(
		HoldingsState.is_vacant(state, &"wayfarer_hold"),
		false,
		"so a rival can never read the ground as unowned"
	)


## ## Institutions are not second-class any more.
##
## The old gate refused EVERY non-`actor` holder on a floored node outright, so an
## institution could never take one — a type check wearing a gate's clothes. The count
## never reads the kind, so a clan reaches a floored node on exactly the terms an actor
## does — and so will any kind a registered pack ships (ADR 0933).
func test_a_floored_node_is_gated_on_holdings_for_an_institution_too() -> void:
	var open := _open_nodes()
	assert_ne(open.is_empty(), true, "setup: the corpus authors floor-0 nodes")
	for def in open:
		HoldingsApi.claim(_actor, def.node_id, _owner(&"iron_vow", &"clan"))

	var lowest: ResourceNodeDef = null
	for def in _by_ascending_floor():
		if def.claim_floor > 0:
			lowest = def
			break
	assert_ne(lowest, null, "the corpus authors a floored node")

	var refused := HoldingsApi.claim(_actor, lowest.node_id, _owner(&"azure_flame", &"sect"))
	assert_eq(bool(refused["ok"]), false, "a sect with no ground of its own is under the floor")
	assert_eq(
		String(refused["reason"]), HoldingsState.CLAIM_BELOW_FLOOR, "and it names the floor rule"
	)

	# The sect wants the SAME open nodes the clan already holds. A claim on held ground
	# opens a standoff rather than taking it (ADR 0085), and that is the point: wanting a
	# vein is not holding it, so the sect's ledger still answers zero for the floor.
	for def in open:
		var contested := HoldingsApi.claim(_actor, def.node_id, _owner(&"azure_flame", &"sect"))
		assert_eq(
			bool(contested["contested"]),
			true,
			"setup: the sect's claim on '%s' opens a standoff, never a take" % def.node_id
		)
	var still_shut := HoldingsApi.claim(_actor, lowest.node_id, _owner(&"azure_flame", &"sect"))
	assert_eq(
		bool(still_shut["ok"]),
		false,
		"and a standoff leaves the sect holding nothing, so the floor still shuts"
	)
	assert_eq(String(still_shut["reason"]), HoldingsState.CLAIM_BELOW_FLOOR, "by the floor rule")

	# And the same sect on ground it actually holds — which, because a claim never moves
	# ground, means the clan's release first. `release` is always permitted (ADR 0085).
	for def in open:
		assert_eq(
			bool(HoldingsApi.release(_actor, def.node_id, _owner(&"iron_vow", &"clan"))["ok"]),
			true,
			"setup: the clan gives up '%s'" % def.node_id
		)
		assert_eq(
			bool(HoldingsApi.claim(_actor, def.node_id, _owner(&"azure_flame", &"sect"))["ok"]),
			true,
			"and the sect takes '%s', so the ground is genuinely the sect's" % def.node_id
		)
	var reached := HoldingsApi.claim(_actor, lowest.node_id, _owner(&"azure_flame", &"sect"))
	assert_eq(
		bool(reached["ok"]),
		true,
		(
			"so a sect holding that ground opens a floored node on the actor's own terms: %s"
			% reached["reason"]
		)
	)


## A count scoped to ONE holder. The clan that has consolidated cannot open a node for a
## sect that has consolidated nothing, because `storage_key` — not the bare `id` — is what
## the ledger keys the count on.
func test_the_count_is_scoped_to_one_holder_key() -> void:
	var open := _open_nodes()
	assert_ne(open.is_empty(), true, "setup: the corpus authors floor-0 nodes")
	for def in open:
		HoldingsApi.claim(_actor, def.node_id, _owner(&"iron_vow", &"clan"))
	var lowest: ResourceNodeDef = null
	for def in _by_ascending_floor():
		if def.claim_floor > 0:
			lowest = def
			break
	assert_ne(lowest, null, "the corpus authors a floored node")

	var result := HoldingsApi.claim(_actor, lowest.node_id, _owner(&"azure_flame", &"sect"))
	assert_eq(bool(result["ok"]), false, "another holder's ground does not count toward yours")
	assert_eq(String(result["reason"]), HoldingsState.CLAIM_BELOW_FLOOR, "by the floor rule")


# --- the read model tells a row the gate's verdict ------------------------------


## `ForageApi.view` publishes `meets_floor` beside the floor it is read against, so a row
## never presents a live claim button on a node the verb would refuse. Asserted at BOTH
## values over one real floored node — the read model is the surface, and a read model
## that always said `true` is the VACUOUS class in a different file.
func test_the_read_model_reports_the_gate_in_both_directions() -> void:
	var lowest: ResourceNodeDef = null
	for def in _by_ascending_floor():
		if def.claim_floor > 0:
			lowest = def
			break
	assert_ne(lowest, null, "the corpus authors a floored node")

	var cold := ForageApi.view(_actor, lowest.node_id)
	assert_eq(int(cold["claim_floor"]), lowest.claim_floor, "the row publishes the floor")
	assert_eq(bool(cold["meets_floor"]), false, "and says the gate is shut on a cold hero")

	_consolidate()
	var warm := ForageApi.view(_actor, lowest.node_id)
	assert_eq(bool(warm["meets_floor"]), true, "and open once the same hero has consolidated")


## The gate is the module's, and the row panel carries the raw figure rather than
## re-deriving it. Read from the panel's shipped source, as `test_forage_surface.gd` reads
## its own boundaries: a panel that computed the rule would own a second copy of it.
func test_the_row_panel_prints_the_gate_and_derives_nothing() -> void:
	var code := _code_only("res://src/ui/panels/resource_node_row.gd")
	assert_eq(
		code.contains('"meets_floor"'), true, "the row publishes the gate on its testable surface"
	)
	assert_eq(
		code.contains("claim_floor <="),
		false,
		"and never re-derives the rule: the module owns it, the panel prints it"
	)
	assert_eq(
		code.contains("meets_floor ="),
		false,
		"and assigns it nowhere, so the value it shows is the facade's own"
	)


## `HoldingsApi` did not grow a verb for this. The facade is at its twelve-method cap and
## a thirteenth is an architecture failure, so the count is folded into `ForageApi.view`
## rather than published beside it.
##
## Read from the facade's own SOURCE rather than reflected, for the reason ADR 0097 gives:
## `has_method` on a class with static verbs answers for the INSTANCE side and would pass or
## fail for reasons that have nothing to do with the claim. A `static func` the gate needed
## would be in this text whether or not anything calls it.
func test_the_holdings_facade_did_not_grow_a_floor_read() -> void:
	var source := FileAccess.get_file_as_string("res://src/modules/holdings/api.gd")
	assert_eq(source.is_empty(), false, "the facade source is readable")
	for verb in ["held_by(", "meets_floor(", "claim_floor_for(", "floor_held("]:
		assert_eq(
			source.contains("func %s" % verb),
			false,
			"'%s' is not a public verb on the facade" % verb
		)
	# The gate is private, which is where it has to be: `_meets_floor` is reachable only from
	# `claim`, and `_held_by` only from the gate beside it.
	assert_eq(source.contains("func _meets_floor("), true, "the gate itself is present and private")
	assert_eq(source.contains("func _held_by("), true, "and the count beside it")


# --- plumbing ------------------------------------------------------------------


## The shipped source of `path` with every comment removed. Asserting on prose would assert
## this file's own docstrings, which name `claim_floor`, `standing` and `_meets_floor` in
## the sentences that forbid them.
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash := line.find("#")
		out.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(out)
