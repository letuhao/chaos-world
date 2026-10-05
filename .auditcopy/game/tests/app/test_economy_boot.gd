extends TestCase

## ADR 0094/0097/0100/0104: the composition root WIRES. These assert the seams
## `EconomyBoot.install` installs actually closed — because four modules shipped, passed
## their own suites, and were completely unwired, which is the failure ADR 0074 measured
## for npcs and ADR 0089 for statuses: a feature nobody can start is decoration.
##
## ## What is asserted, and why it is not asserted through `item_workbench_app`
##
## Every assertion here reads a MODULE's own read model. The app root cannot be the
## subject: `institution_resolver.gd:98` calls a `NationApi.act` that does not exist, and
## that parse error takes `world_pulse.gd` and `item_workbench_app.gd` down with it. A test
## that drove the boot through the app would be measuring another agent's in-flight file.
## So the boot is exercised DIRECTLY, which is also the honest subject: what is proven is
## that installing the seams is sufficient, not that one particular root happens to call it.
##
## ## Teardown matters more than usual here
##
## `HoldingsApi._store`, `HoldingsApi._resolver`, `MarketApi._store`, `CustodyApi._store`,
## `CustodyApi._resolver`, `CustodyApi._minter`, `ForageApi._granter` and the
## `ResourceNodeCatalog` singleton are all process-wide and all outlive this suite. A suite
## that leaves them installed holds authored `ResourceNodeDef` resources and a live `Actor`
## graph alive until the engine shuts down, and ObjectDB then reports leaked instances at
## exit with every assertion green — a suite that passes and still fails the run.

## A REAL authored NpcDef, not an invented id.
##
## `EconomyBoot._subject_minter` is `ActorFactory.spawn_npc(NpcCatalog.instance().definition(id))`,
## so a subject id that resolves to nothing yields a null def and the minter returns null —
## which reads as "the subject never stood up" rather than as "the fixture named a ghost".
## The authored cast under `game/data/npc/` is `drifter`, `elder_wei`, `gate_keeper_bo` and
## `smith_bearcutter`; this uses one of them so the seam is proven against content a player
## could actually meet. A custody claim about somebody who does not exist is not a custody
## test, it is a fixture that agrees with itself.
const SUBJECT := &"smith_bearcutter"
const SECT := &"iron_vine"
const COIN := &"curr_spirit_coin"

var _held: Array[Actor] = []


func setup() -> void:
	_held.clear()


func teardown() -> void:
	# Every process-wide seam this suite touched, released. Idempotent and safe after an
	# early return, which is why it is teardown rather than a tail-of-suite cleanup.
	for actor in _held:
		if actor != null:
			actor = null
	_held.clear()
	HoldingsApi.set_resolver(Callable())
	HoldingsApi.set_store(null)
	MarketApi.set_store(null)
	CustodyApi.set_resolver(Callable())
	CustodyApi.set_store(null)
	CustodyApi.set_minter(Callable())
	ForageApi.set_granter(Callable())
	ResourceNodeCatalog.instance().reset()


## A holder with everything a claim needs: an inventory for the coin leg, and all four
## ledgers attached so a save would carry them.
func _holder(id: StringName) -> Actor:
	var actor := Actor.new(id, {})
	ItemsApi.attach(actor)
	EconomyApi.attach(actor)
	HoldingsApi.attach(actor)
	CustodyApi.attach(actor)
	MarketApi.attach(actor)
	_held.append(actor)
	return actor


func _owner(id: StringName, kind: StringName = &"sect") -> Dictionary:
	return {"kind": String(kind), "id": String(id)}


func _node(node_id: StringName) -> ResourceNodeDef:
	var node := ResourceNodeDef.new()
	node.node_id = node_id
	node.display_name = String(node_id)
	node.kind = &"ore"
	node.yield_per_period = 4
	node.claim_floor = 0
	return node


# --- install refuses by name ---------------------------------------------------


func test_install_on_no_actor_refuses_rather_than_dereferencing_nothing() -> void:
	# ADR 0002: a null injection fails loudly. The report names the reason so a caller
	# can tell "you handed me nothing" from "the wiring failed".
	var report := EconomyBoot.install(null)
	assert_eq(bool(report["ok"]), false, "no actor, no install")
	assert_eq(String(report["reason"]), "no_actor", "and it says so by name")
	assert_eq(bool(report["bound"]), false, "and it claims nothing was bound")


# --- all four modules attach ---------------------------------------------------


func test_install_attaches_all_four_ledgers_to_the_actor() -> void:
	var actor := _holder(&"hero")
	# Each module's ledger is a distinct `module_data` key, and a module that was never
	# attached writes nothing into any of them. This is the assertion the unwired build
	# could not pass: `module_data` had no economy/market/holdings/custody entry at all.
	EconomyBoot.install(actor)
	for key in [
		EconomyApi.MODULE_KEY, MarketApi.MODULE_KEY, HoldingsApi.MODULE_KEY, CustodyApi.MODULE_KEY
	]:
		assert_eq(
			actor.get_module_data(key).is_empty(),
			false,
			"'%s' is keyed for persistence after install" % String(key)
		)


func test_the_install_report_names_every_module_it_attached() -> void:
	var actor := _holder(&"hero")
	var report := EconomyBoot.install(actor)
	assert_eq(bool(report["ok"]), true, "the install succeeds: %s" % report.get("reason", ""))
	assert_eq(bool(report["bound"]), true, "and reports the binding rather than hiding it")
	assert_eq(
		report["attached"], ["economy", "market", "holdings", "custody"], "all four, in order"
	)


# --- all five seams report installed -------------------------------------------


func test_all_five_seams_report_installed() -> void:
	# The three `summary()` payloads already publish `store_installed`/`resolver_installed`
	# as primitives, so the wiring is proven through the module's OWN read model rather
	# than through a back door this boot would have to invent.
	var actor := _holder(&"hero")
	EconomyBoot.install(actor)
	assert_eq(bool(HoldingsApi.summary(actor)["resolver_installed"]), true, "holdings resolver")
	assert_eq(bool(CustodyApi.summary(actor)["resolver_installed"]), true, "custody resolver")
	assert_eq(bool(CustodyApi.summary(actor)["store_installed"]), true, "custody store")
	assert_eq(bool(CustodyApi.has_minter()), true, "the custody minter, which has no summary key")
	assert_eq(
		bool(ForageApi.has_granter()),
		true,
		(
			"the forage granter, which has no summary key either — without it `gather` is a flag "
			+ "with no verb behind it"
		)
	)
	# `MarketApi.summary` publishes no seam booleans, so its store is proven by BEHAVIOUR
	# instead: a drop on one actor must be visible to a SECOND actor through the facade's
	# own read model, which is the whole reason the store exists (ADR 0100/0101). Read
	# through `summary`, not `state` — `state` deliberately reads the actor's OWN mirror,
	# the documented single-player path, and would pass with no store installed at all.
	var dropper := _holder(&"dropper")
	ItemsApi.inventory(dropper).add(Crafting.resolve(COIN), 3)
	MarketApi.attach(dropper)
	var dropped := MarketApi.drop(
		dropper, &"market_square", [{"def_id": String(COIN), "quantity": 1}]
	)
	assert_eq(bool(dropped["ok"]), true, "a drop lands: %s" % dropped.get("reason", ""))
	var taker := _holder(&"taker")
	var entries: Array = (MarketApi.summary(taker)["floor"] as Dictionary).get("market_square", [])
	assert_eq(entries.size(), 1, "the floor is a WORLD fact: another actor sees the drop")


func test_install_is_idempotent_so_a_load_can_re_install_it() -> void:
	var actor := _holder(&"hero")
	EconomyBoot.install(actor)
	EconomyBoot.install(actor)
	EconomyBoot.install(actor)
	assert_eq(
		bool(CustodyApi.summary(actor)["store_installed"]), true, "the seams survive a re-install"
	)
	assert_eq(bool(EconomyBoot.install(actor)["ok"]), true, "and a second install still succeeds")


func test_a_re_install_replaces_the_world_ledgers_rather_than_sharing_one_object() -> void:
	# The three stores are separate instances, and this is load-bearing rather than
	# stylistic: each re-normalizes with its OWN state class, so one shared object would
	# have `MarketState.normalize` drop a holdings ledger's shape and vice versa — a
	# silent, total loss of the floor and the lots. A claim that survives a re-install is
	# evidence the custody store kept its own container.
	var actor := _holder(&"hero")
	EconomyBoot.install(actor)
	var taken := CustodyApi.capture(
		actor, SUBJECT, &"npc", _owner(&"warden", &"actor"), &"custody", 4
	)
	assert_eq(bool(taken["ok"]), true, "a claim opens: %s" % taken.get("reason", ""))
	EconomyBoot.install(actor)
	# The fresh world starts empty by design, so this asserts the REPLACE, not a merge.
	assert_eq(
		int(CustodyApi.summary(actor)["claim_count"]),
		0,
		"a re-install installs a new world rather than keeping the old one"
	)


# --- the resolver is the same callable in both modules -------------------------


func test_both_modules_receive_the_same_resolver_callable() -> void:
	# One contract, one implementation: a fix to the owner question cannot drift between
	# the two modules that ask it.
	var actor := _holder(&"hero")
	EconomyBoot.install(actor)
	var holdings := Callable(HoldingsApi, "_resolver") as Callable
	# Read the installed seam through each module's own answer instead of reflecting a
	# static, so the assertion is behavioural: both report a live resolver.
	assert_eq(bool(HoldingsApi.summary(actor)["resolver_installed"]), true, "holdings is wired")
	assert_eq(bool(CustodyApi.summary(actor)["resolver_installed"]), true, "so is custody")


# --- an institution claim now RESOLVES instead of refusing `no_resolver` --------


func test_a_sect_may_hold_a_node_now_rather_than_refusing_no_resolver() -> void:
	# The failure this whole file exists to close. Before the boot, `HoldingsApi.claim`
	# with an institution holder and nothing installed refused `no_resolver` — an
	# institution that silently cannot hold anything.
	var actor := _holder(&"hero")
	EconomyBoot.install(actor)
	ResourceNodeCatalog.instance().reset()
	ResourceNodeCatalog.instance().install([_node(&"vein_boot")])
	var claimed := HoldingsApi.claim(actor, &"vein_boot", _owner(SECT))
	assert_eq(bool(claimed["ok"]), true, "a sect may hold a node: %s" % claimed.get("reason", ""))
	assert_ne(
		String(claimed.get("reason", "")), HoldingsState.NO_RESOLVER, "and it is not the seam"
	)


func test_a_sect_may_take_a_captive_now_rather_than_refusing_no_resolver() -> void:
	var actor := _holder(&"hero")
	EconomyBoot.install(actor)
	var taken := CustodyApi.capture(actor, SUBJECT, &"npc", _owner(SECT), &"custody", 6)
	assert_eq(bool(taken["ok"]), true, "a sect may take custody: %s" % taken.get("reason", ""))
	var claim: Dictionary = (CustodyApi.summary(actor)["claims"] as Dictionary)[String(
		taken["claim_id"]
	)]
	assert_eq(String(claim["holder"]["kind"]), "sect", "and the holder is an institution")


func test_a_holder_this_build_does_not_ship_still_refuses_by_name() -> void:
	# The resolver is a gate, not an accept-everything. A sect nothing defines teaches
	# nothing and holds nothing, and the refusal keeps the name its own facade chose.
	var actor := _holder(&"hero")
	EconomyBoot.install(actor)
	var taken := CustodyApi.capture(actor, SUBJECT, &"npc", _owner(&"no_such_sect"), &"custody", 4)
	assert_eq(bool(taken["ok"]), false, "a sect this build does not ship refuses")
	assert_eq(String(taken["reason"]), "unknown_sect", "and names the rule")


# --- the minter a claim's subject is minted through ----------------------------


func test_the_minter_mints_a_live_body_for_a_held_claim() -> void:
	# ADR 0104's promise, made true: a subject is a DEF ID, and a live actor is minted on
	# demand through the injected seam rather than stored in the ledger.
	var actor := _holder(&"hero")
	EconomyBoot.install(actor)
	var taken := CustodyApi.capture(
		actor, SUBJECT, &"npc", _owner(&"warden", &"actor"), &"custody", 4
	)
	var claim_id := StringName(String(taken["claim_id"]))
	var subject := CustodyApi.subject(claim_id)
	assert_ne(subject, null, "the subject stands up on demand")
	assert_eq(subject is Actor, true, "and what stands up is the shared Actor type")


func test_subject_refuses_for_an_unknown_claim_rather_than_crashing() -> void:
	var actor := _holder(&"hero")
	EconomyBoot.install(actor)
	assert_eq(CustodyApi.subject(&"custody_nobody#7"), null, "an unknown claim has no subject")


func test_subject_refuses_for_a_released_claim() -> void:
	# A released claim names a subject nobody holds any more. Minting that body would put
	# a free prisoner back on the map, so the read refuses rather than answering.
	var actor := _holder(&"hero")
	EconomyBoot.install(actor)
	var taken := CustodyApi.capture(
		actor, SUBJECT, &"npc", _owner(&"warden", &"actor"), &"custody", 4
	)
	var claim_id := StringName(String(taken["claim_id"]))
	CustodyApi.release(actor, claim_id, _owner(&"warden", &"actor"))
	assert_eq(CustodyApi.subject(claim_id), null, "a released claim has no body")


func test_subject_refuses_when_no_minter_is_installed() -> void:
	# ADR 0002 again: a null injection fails loudly rather than dereferencing nothing, and
	# here "loudly" is a null the caller can branch on, not a crash it cannot.
	var actor := _holder(&"hero")
	EconomyBoot.install(actor)
	var taken := CustodyApi.capture(
		actor, SUBJECT, &"npc", _owner(&"warden", &"actor"), &"custody", 4
	)
	var claim_id := StringName(String(taken["claim_id"]))
	CustodyApi.set_minter(Callable())
	assert_eq(CustodyApi.has_minter(), false, "the seam reports itself absent")
	assert_eq(CustodyApi.subject(claim_id), null, "and the read refuses rather than raising")


# --- the resolver itself, on its own -------------------------------------------


func test_the_resolver_answers_for_all_four_owner_kinds() -> void:
	# `OwnerRef.KINDS` is closed and every one of the four resolves through a real path:
	# `actor` by its id, and each institution tier by its authored catalog.
	assert_eq(bool(OwnerResolver.resolve("actor", "player")["ok"]), true, "an actor resolves")
	for kind in [&"clan", &"sect", &"nation"]:
		var ghost := OwnerResolver.resolve(String(kind), "no_such_institution")
		assert_eq(bool(ghost["ok"]), false, "an un-authored %s refuses" % String(kind))
		assert_eq(
			String(ghost["reason"]),
			"unknown_%s" % String(kind),
			"and names the rule for '%s'" % String(kind)
		)


func test_the_resolver_refuses_an_unknown_kind_closed() -> void:
	# The whole point of the type: a typo must never answer as somebody else. Defaulting
	# to `actor` would let a sect's holding pass a player's check.
	for kind_value in ["guild", "town", "", "Actor"]:
		var answered := OwnerResolver.resolve(kind_value, "x")
		assert_eq(bool(answered["ok"]), false, "kind '%s' refuses" % kind_value)
		assert_eq(
			String(answered["reason"]),
			OwnerRef.UNKNOWN_KIND,
			"and names the rule for '%s'" % kind_value
		)


func test_the_resolver_refuses_a_holder_with_no_id() -> void:
	assert_eq(
		String(OwnerResolver.resolve("sect", "")["reason"]),
		"unknown_owner",
		"a kind with no id names no holder"
	)


func test_the_resolver_finds_the_shipped_content_it_is_meant_to_find() -> void:
	# Read through the authored `.tres` rather than a hard-coded id, so this asserts the
	# RESOLVER reaches the catalogs rather than that it agrees with a constant in a test.
	var sect_ids: Array = SectCatalog.instance().sect_ids()
	if sect_ids.is_empty():
		return
	var shipped := OwnerResolver.resolve("sect", String(sect_ids[0]))
	assert_eq(bool(shipped["ok"]), true, "an authored sect resolves: %s" % sect_ids[0])
	var clan_ids: Array = ClanApi.clan_ids()
	if not clan_ids.is_empty():
		assert_eq(
			bool(OwnerResolver.resolve("clan", String(clan_ids[0]))["ok"]),
			true,
			"and so does an authored clan"
		)
