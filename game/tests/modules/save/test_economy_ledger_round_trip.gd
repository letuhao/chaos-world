extends TestCase

## ADR 0165: the three economy ledgers survive a save/load (DEF-0223).
##
## ## Why this suite exists
##
## `holdings`, `market` and `custody` were the last three world facts on bare in-memory
## dictionaries, so a claimed vein, a listed lot and an open custody claim died at quit — and
## every suite passed, because a single-actor in-memory test passes. That is ADR 0101's exact
## finding applied a third time: the failure is silent until a second session exists.
##
## The four properties proved here are the ones the audit named as the criterion that was `no`:
## the round trip, a future `SCHEMA_VERSION` refused BY NAME, a corrupt file refused BY NAME
## rather than read as an empty world, and the three ledgers staying SEPARATE.
##
## ## These tests touch the real filesystem
##
## They write to `user://save`, which is per-run scratch. Every case clears it first, so a
## previous run's generation cannot make an assertion pass or fail for the wrong reason — the
## `test_save_envelope.gd` precedent verbatim.

const COIN := &"curr_spirit_coin"
const GOOD := &"currency_spirit_stone"
const SUBJECT := &"smith_bearcutter"
const NODE := &"vein_ledger"

## `Actor` is a `RefCounted`, so an actor minted inside a helper is freed the moment that helper
## returns — the ledgers store ids and never references. Every actor is held here for that
## reason, which is the same fix `test_market_auction.gd` documents.
var _held: Array[Actor] = []


func setup() -> void:
	_clear_disk()
	_held.clear()
	ResourceNodeCatalog.instance().reset()
	SaveApi.reset_clock()


## Every process-wide seam this suite installs outlives it, and a suite that leaves them wired
## hands the NEXT suite the previous one's world — `SaveApi._stores` is a static dictionary.
## Idempotent and safe after an early return, which is why it is teardown and not a tail.
func teardown() -> void:
	for actor in _held:
		if actor != null:
			actor = null
	_held.clear()
	for key in ["holdings", "market", "custody"]:
		SaveApi.install_store(key, null)
		HoldingsApi.set_store(null)
		MarketApi.set_store(null)
		CustodyApi.set_store(null)
	HoldingsApi.set_resolver(Callable())
	CustodyApi.set_resolver(Callable())
	ResourceNodeCatalog.instance().reset()
	_clear_disk()


## The three files removed individually. `DirAccess.remove_absolute` on the directory itself
## fails silently on some platforms and leaves a previous run's generation behind — which is
## exactly how a "nothing saved yet" assertion reads wrong.
func _clear_disk() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)


## Install the durable stores for all three keys and hand each module the SAME instance, which
## is precisely what `item_workbench_app._ready` does through `EconomyBoot._store_for`. Built
## per key rather than shared, so the three can never address one another's container.
func _install_durable() -> Dictionary:
	var stores := {
		"holdings": WorldLedgerStore.new("holdings", HoldingsState.SCHEMA_VERSION),
		"market": WorldLedgerStore.new("market", MarketState.SCHEMA_VERSION),
		"custody": WorldLedgerStore.new("custody", CustodyState.SCHEMA_VERSION),
	}
	for key in stores.keys():
		SaveApi.install_store(String(key), stores[key])
	HoldingsApi.set_store(stores["holdings"])
	MarketApi.set_store(stores["market"])
	CustodyApi.set_store(stores["custody"])
	HoldingsApi.set_resolver(func(_kind: String, _id: String) -> Dictionary: return {"ok": true})
	CustodyApi.set_resolver(func(_kind: String, _id: String) -> Dictionary: return {"ok": true})
	return stores


func _actor(id: StringName) -> Actor:
	var actor := Actor.new(id, {})
	ItemsApi.attach(actor)
	EconomyApi.attach(actor)
	HoldingsApi.attach(actor)
	MarketApi.attach(actor)
	CustodyApi.attach(actor)
	_held.append(actor)
	return actor


func _owner(id: StringName, kind: StringName = &"actor") -> Dictionary:
	return {"kind": String(kind), "id": String(id)}


func _install_node() -> void:
	ResourceNodeCatalog.instance().reset()
	var node := ResourceNodeDef.new()
	node.node_id = NODE
	node.display_name = String(NODE)
	node.kind = &"ore"
	node.yield_per_period = 4
	node.claim_floor = 0
	ResourceNodeCatalog.instance().install([node])


## A sellable realized instance, because `MarketApi.list` escrows an INSTANCE and
## `find_by_instance_id` only ever finds the `_instances` half of an inventory.
func _seller_with_lot(def_id: StringName) -> Actor:
	var actor := _actor(&"auction_house")
	var def := Crafting.resolve(def_id)
	var instance := ItemInstance.new(def.id, &"lot_candidate")
	instance.def_ref = def
	instance.rarity = def.rarity
	instance.realm = def.realm
	ItemsApi.inventory(actor).add_instance(instance)
	return actor


func _first_instance_id(actor: Actor) -> StringName:
	for instance in ItemsApi.inventory(actor).instances():
		return instance.instance_id
	return &""


func _claim_node(actor: Actor) -> Dictionary:
	return HoldingsApi.claim(actor, NODE, _owner(&"warden"))


func _open_claim(actor: Actor) -> Dictionary:
	return CustodyApi.capture(actor, SUBJECT, &"npc", _owner(&"warden"), &"custody", 4)


# --- The round trip: the criterion the audit found `no` ---------------------------


func test_a_claimed_node_a_listed_lot_and_a_held_claim_all_survive_a_save_and_reload() -> void:
	# THE feature. Before this, each of these lived in a bare `var _ledger: Dictionary` and
	# was gone the moment the process ended, with `SaveApi` faithfully writing
	# `world["holdings"] = {}` for a key nothing ever read back.
	_install_node()
	_install_durable()
	var actor := _actor(&"hero")
	ItemsApi.inventory(actor).add(Crafting.resolve(COIN), 5)

	var claimed := _claim_node(actor)
	assert_eq(bool(claimed["ok"]), true, "a vein is claimed: %s" % claimed.get("reason", ""))
	var seller := _seller_with_lot(GOOD)
	var listed := MarketApi.list(seller, _first_instance_id(seller), 3)
	assert_eq(bool(listed["ok"]), true, "a lot is listed: %s" % listed.get("reason", ""))
	var lot_id := StringName(String(listed["lot_id"]))
	var taken := _open_claim(actor)
	assert_eq(bool(taken["ok"]), true, "a captive is taken: %s" % taken.get("reason", ""))
	var claim_id := StringName(String(taken["claim_id"]))

	var written := SaveApi.persist(actor, "standard")
	assert_eq(bool(written["ok"]), true, "the save lands: %s" % written.get("reason", ""))

	# A COLD world: the same save is republished into the same stores from disk, which is the
	# next session rather than a shared in-memory dictionary that still holds the answer.
	var reopened := _install_durable()
	assert_eq(bool(SaveApi.publish_world()["ok"]), true, "the save is published back")
	HoldingsApi.attach(actor)
	MarketApi.attach(actor)
	CustodyApi.attach(actor)

	var nodes := HoldingsApi.summary(actor)["nodes"] as Dictionary
	assert_eq(String((nodes[NODE] as Dictionary)["owner"]["id"]), "warden", "the HOLDER survived")
	var lot: Dictionary = (MarketApi.summary(actor)["lots"] as Dictionary)[String(lot_id)]
	assert_ne(lot.is_empty(), true, "the LOT survived")
	assert_eq(String(lot["seller_id"]), "auction_house", "and it is still the seller's lot")
	var claims := CustodyApi.summary(actor)["claims"] as Dictionary
	var claim: Dictionary = claims[claim_id]
	assert_ne(claim.is_empty(), true, "the CLAIM survived")
	assert_eq(String(claim["holder"]["id"]), "warden", "and the holder is still the holder")
	# The reopened stores are the ones installed, not the pre-save ones, so a stale handle
	# cannot be what made this pass.
	assert_eq(
		(reopened["custody"] as WorldLedgerStore).key, "custody", "the reopened store is live"
	)


func test_a_ledger_written_through_the_api_is_read_back_by_a_fresh_process_view() -> void:
	# The store re-reads the FILE on every call rather than caching, so a store installed at
	# boot and read a minute later sees what was written since. That is what makes the round
	# trip true without a reload dance, and a caching store would fail here while passing the
	# test above on the same instance.
	_install_durable()
	var actor := _actor(&"hero")
	var ledger := HoldingsState.empty()
	ledger["nodes"][NODE] = {
		"owner": OwnerRef.from_dict(_owner(&"warden")).to_dict(),
		"condition": 9,
		"resting": 0,
	}
	var store := WorldLedgerStore.new("holdings", HoldingsState.SCHEMA_VERSION)
	store.write_ledger(HoldingsState.normalize(ledger))
	var reread := WorldLedgerStore.new("holdings", HoldingsState.SCHEMA_VERSION)
	assert_eq(
		int((reread.read_ledger()["nodes"] as Dictionary)[NODE]["condition"]), 9, "it is on disk"
	)


func test_the_three_ledgers_are_installed_under_their_own_envelope_keys() -> void:
	# A key is a CONSTRUCTOR argument, so a store can only ever address the slot it was made
	# for. Read back off the objects themselves rather than off the facade, because the facade
	# hides which key its store happens to carry.
	var stores := _install_durable()
	assert_eq(String((stores["holdings"] as WorldLedgerStore).key), "holdings", "holdings")
	assert_eq(String((stores["market"] as WorldLedgerStore).key), "market", "market")
	assert_eq(String((stores["custody"] as WorldLedgerStore).key), "custody", "custody")


# --- A version from the future is REFUSED BY NAME ---------------------------------


func test_a_schema_version_from_the_future_is_refused_by_name() -> void:
	# A ledger written by a build whose SCHEMA_VERSION is higher. Accepting it would be
	# DESTRUCTIVE: the newer build may have moved a field this one drops, so reading it and
	# writing it back on the next autosave erases the newer run's world. Refused, and named.
	var ahead := WorldLedgerStore.new("holdings", HoldingsState.SCHEMA_VERSION + 1)
	var stamped := (
		HoldingsState
		. normalize(
			{
				"version": HoldingsState.SCHEMA_VERSION + 1,
				"nodes": {},
			}
		)
	)
	var written := ahead.write_ledger(stamped)
	assert_eq(bool(written["ok"]), true, "a build at its own version writes fine")

	var store := WorldLedgerStore.new("holdings", HoldingsState.SCHEMA_VERSION)
	store.write_ledger(stamped)
	assert_eq(store.read_ledger(), {}, "an older build reads nothing rather than guessing")
	assert_eq(store.last_reason(), WorldLedgerStore.REASON_FUTURE_SCHEMA, "and says why BY NAME")
	# And the refusal is NOT the same answer as "nothing saved", which is the whole point:
	# a store that read a newer world as an empty one is how every claim is silently lost.
	assert_ne(store.last_reason(), WorldLedgerStore.REASON_NO_SAVE, "distinct from a new game")
	assert_eq(store.is_empty(), false, "a REFUSED ledger is not reported as empty")


func test_a_write_over_a_newer_ledger_is_refused_rather_than_overwriting_it() -> void:
	# The same rule on the write side, and it is the more expensive of the two errors: an older
	# build saving over a newer one destroys the newer world's fields with no trace.
	var ahead := WorldLedgerStore.new("market", MarketState.SCHEMA_VERSION + 1)
	var stamped := MarketState.normalize({"version": MarketState.SCHEMA_VERSION + 1})
	var floor_rows := MarketState.empty()
	floor_rows["floor"]["square"] = [{"drop_id": "drop_0", "def_id": "kept", "quantity": 1}]
	ahead.write_ledger(stamped)

	var behind := WorldLedgerStore.new("market", MarketState.SCHEMA_VERSION)
	var refusal := behind.write_ledger(MarketState.empty())
	assert_eq(bool(refusal["ok"]), false, "the older build refuses to write")
	assert_eq(
		String(refusal["reason"]), WorldLedgerStore.REASON_FUTURE_SCHEMA, "and names the rule"
	)
	assert_eq(ahead.last_reason(), "", "the newer build still reads its own world")


func test_an_older_schema_version_is_accepted_and_migrated_by_normalize() -> void:
	# The migration story, and the reason a refusal is reserved for the FUTURE half: an old
	# ledger is re-normalized onto the current shape rather than refused, so a save written by
	# an earlier build keeps loading. Nothing is rewritten in place — the module's own
	# `normalize` supplies the skeleton in exactly one place.
	var store := WorldLedgerStore.new("custody", CustodyState.SCHEMA_VERSION)
	store.write_ledger({"version": 1, "claims": {}})
	var ledger := store.read_ledger()
	assert_eq(int(ledger.get("version", 0)), CustodyState.SCHEMA_VERSION, "still versioned")
	assert_eq(store.last_reason(), "", "and an old version is not a refusal")


# --- A corrupt or truncated file is REFUSED BY NAME ------------------------------


func test_a_corrupt_ledger_file_is_refused_by_name_and_not_read_as_an_empty_world() -> void:
	# THE failure this whole suite exists to prevent: an empty world silently losing every
	# claim. So the store must NOT answer "empty, carry on" — it must answer nothing and NAME
	# the condition, and `is_empty()` must refuse to call a refusal empty.
	DirAccess.make_dir_recursive_absolute(SavePaths.DIR)
	var broken := FileAccess.open(SavePaths.PRIMARY, FileAccess.WRITE)
	broken.store_string('{"format": "chaos-world.save", "envelope_version": 1, "wor')  # truncated
	broken.close()

	var store := WorldLedgerStore.new("custody", CustodyState.SCHEMA_VERSION)
	assert_eq(store.read_ledger(), {}, "nothing is invented from a truncated file")
	assert_eq(
		store.last_reason(), WorldLedgerStore.REASON_LEDGER_UNREADABLE, "and it is named BY NAME"
	)
	assert_eq(store.is_empty(), false, "a refused ledger is NOT reported as an empty world")


func test_a_truncated_primary_recovers_the_whole_previous_generation_rather_than_a_refusal(
) -> void:
	# `SaveStore.restore` routes an unreadable primary to the backup, so the common case is a
	# RECOVERY rather than a refusal — and the recovery is a complete generation, never a
	# salvage of the broken file. The refusal above is what remains when neither slot reads.
	var actor := _actor(&"hero")
	var store := WorldLedgerStore.new("holdings", HoldingsState.SCHEMA_VERSION)
	SaveApi.install_store("holdings", store)
	HoldingsApi.set_store(store)
	var ledger := HoldingsState.empty()
	ledger["nodes"][NODE] = {"owner": OwnerRef.from_dict(_owner(&"warden")).to_dict()}
	store.write_ledger(HoldingsState.normalize(ledger))
	# A second write makes the first generation the BACKUP.
	store.write_ledger(HoldingsState.normalize(ledger))
	var recovered := WorldLedgerStore.new("holdings", HoldingsState.SCHEMA_VERSION)
	assert_ne(recovered.read_ledger().get("nodes"), null, "a readable generation is found")

	var good := FileAccess.get_file_as_string(SavePaths.PRIMARY)
	DirAccess.rename_absolute(SavePaths.PRIMARY, SavePaths.BACKUP)
	var truncated := FileAccess.open(SavePaths.PRIMARY, FileAccess.WRITE)
	truncated.store_string(good.substr(0, 40))
	truncated.close()
	var after := WorldLedgerStore.new("holdings", HoldingsState.SCHEMA_VERSION)
	assert_ne(after.read_ledger().get("nodes"), null, "the backup answered instead of the wreck")
	assert_eq(after.last_reason(), "", "and a recovery is not a refusal")


func test_no_save_at_all_is_a_new_game_and_not_a_refusal() -> void:
	# The three answers must stay three answers. Collapsing "nothing saved" into "refused" is
	# how a first boot would be reported as a corrupt save.
	var store := WorldLedgerStore.new("holdings", HoldingsState.SCHEMA_VERSION)
	assert_eq(store.read_ledger(), {}, "nothing to read")
	assert_eq(store.last_reason(), WorldLedgerStore.REASON_NO_SAVE, "named as a new game")
	assert_eq(store.is_empty(), true, "and a genuinely empty world IS empty")


func test_the_module_reports_a_refused_ledger_rather_than_an_empty_one() -> void:
	# "the module reports it rather than starting empty" — proved through the module's OWN
	# read model, not through the store, because a store that reports it is only half of it.
	DirAccess.make_dir_recursive_absolute(SavePaths.DIR)
	var broken := FileAccess.open(SavePaths.PRIMARY, FileAccess.WRITE)
	broken.store_string("not json at all")
	broken.close()
	var stores := _install_durable()
	var actor := _actor(&"hero")
	assert_eq(int(CustodyApi.summary(actor)["claim_count"]), 0, "no claim is invented")
	assert_eq(
		String((stores["custody"] as WorldLedgerStore).last_reason()),
		WorldLedgerStore.REASON_LEDGER_UNREADABLE,
		"and the store the module reads through says so by name"
	)
	# The store IS wired — which is the distinction the audit found impossible to make before.
	assert_eq(bool(HoldingsApi.summary(actor)["store_installed"]), true, "a store is installed")


func test_a_write_over_an_unreadable_save_is_refused_rather_than_replacing_it() -> void:
	# Losing a whole world to preserve nothing is not a recovery, so a ledger write against an
	# unreadable envelope refuses by name instead of overwriting the only evidence.
	DirAccess.make_dir_recursive_absolute(SavePaths.DIR)
	var broken := FileAccess.open(SavePaths.PRIMARY, FileAccess.WRITE)
	broken.store_string("{ truncated")
	broken.close()
	var store := WorldLedgerStore.new("holdings", HoldingsState.SCHEMA_VERSION)
	var refusal := store.write_ledger(HoldingsState.empty())
	assert_eq(bool(refusal["ok"]), false, "the write refuses")
	assert_eq(String(refusal["reason"]), WorldLedgerStore.REASON_LEDGER_UNREADABLE, "by name")
	assert_eq(
		FileAccess.get_file_as_string(SavePaths.PRIMARY), "{ truncated", "and the wreck is intact"
	)


# --- The three ledgers stay SEPARATE ---------------------------------------------


func test_a_holdings_ledger_written_through_the_market_store_does_not_corrupt_the_floor() -> void:
	# The conflation the audit found the three ledgers once at risk of: one object, and
	# `MarketState.normalize` drops every holdings field (no `floor`, no `lots`, no `claims`).
	# A per-key store makes the write a no-op on the wrong container instead.
	_install_durable()
	var actor := _actor(&"hero")
	var market_store := WorldLedgerStore.new("market", MarketState.SCHEMA_VERSION)
	var floor := MarketState.empty()
	floor["floor"]["square"] = [{"drop_id": "drop_0", "def_id": "spare", "quantity": 2}]
	floor["lots"]["lot_1"] = {"lot_id": "lot_1", "status": "open"}
	market_store.write_ledger(MarketState.normalize(floor))

	var holdings_ledger := (
		HoldingsState
		. normalize(
			{
				"nodes": {NODE: {"owner": OwnerRef.from_dict(_owner(&"warden")).to_dict()}},
			}
		)
	)
	# Written through the MARKET store on purpose: the mistake this guards.
	market_store.write_ledger(holdings_ledger)

	var reread := WorldLedgerStore.new("market", MarketState.SCHEMA_VERSION).read_ledger()
	var rows: Array = (reread["floor"] as Dictionary).get("square", [])
	assert_eq(rows.size(), 1, "the FLOOR is intact")
	assert_eq(String((rows[0] as Dictionary)["def_id"]), "spare", "and still holds the drop")
	assert_ne((reread["lots"] as Dictionary).get("lot_1"), null, "and the open lot survives")
	assert_eq((reread.get("nodes") as Dictionary).get(NODE), null, "no holdings key was written")
	# The other two read nothing from it, and hold nothing.
	assert_eq(
		(
			(
				WorldLedgerStore.new("holdings", HoldingsState.SCHEMA_VERSION).read_ledger().get(
					"nodes"
				)
				as Dictionary
			)
			. size()
		),
		0,
		"holdings is untouched by a market-key write"
	)


func test_a_market_ledger_written_through_the_custody_store_cannot_invent_a_claim() -> void:
	# The same rule from the other side and the other pair, because one direction is not
	# evidence for the other: custody's ledger has a `claims` container and nothing else, so a
	# floor dropped into it is a drop nobody can ever see.
	var custody_store := WorldLedgerStore.new("custody", CustodyState.SCHEMA_VERSION)
	var claim := CustodyState.empty()
	claim["claims"]["custody_a#0"] = {
		"claim_id": "custody_a#0",
		"subject_id": "held_one",
		"subject_kind": "npc",
		"holder": OwnerRef.from_dict(_owner(&"warden")).to_dict(),
		"term_id": "custody",
		"periods": 4,
		"opened_period": 0,
		"status": CustodyState.HELD,
	}
	custody_store.write_ledger(CustodyState.normalize(claim))

	var floor := MarketState.empty()
	floor["floor"]["square"] = [{"drop_id": "drop_0", "def_id": "stowaway", "quantity": 1}]
	custody_store.write_ledger(MarketState.normalize(floor))

	var reread := WorldLedgerStore.new("custody", CustodyState.SCHEMA_VERSION).read_ledger()
	assert_eq((reread["claims"] as Dictionary).size(), 1, "the claim is intact")
	assert_eq(
		String(((reread["claims"] as Dictionary)["custody_a#0"] as Dictionary)["subject_id"]),
		"held_one",
		"and still names the captive it always named"
	)
	assert_eq(reread.get("floor"), null, "no market container was written into custody")
	assert_eq(
		(
			(
				WorldLedgerStore.new("market", MarketState.SCHEMA_VERSION).read_ledger().get(
					"floor"
				)
				as Dictionary
			)
			. size()
		),
		0,
		"and the market floor is untouched by a custody-key write"
	)


func test_each_store_declares_the_schema_version_of_the_module_that_owns_it() -> void:
	# A store bound to the WRONG module's version would refuse that module's own ledger, so the
	# three numbers are asserted against the three state classes rather than against each other.
	assert_eq(HoldingsState.SCHEMA_VERSION, 1, "holdings is at 1")
	assert_eq(MarketState.SCHEMA_VERSION, 1, "market is at 1")
	assert_eq(CustodyState.SCHEMA_VERSION, 1, "custody is at 1")
	assert_eq(
		WorldLedgerStore.new("holdings", HoldingsState.SCHEMA_VERSION).schema_version,
		HoldingsState.SCHEMA_VERSION,
		"and the store carries the module's own"
	)


func test_a_store_for_a_key_the_envelope_does_not_carry_refuses_by_name() -> void:
	# Closed, so a typo in a key is a named refusal rather than a slot that silently accepts
	# every write and is read by nobody.
	var store := WorldLedgerStore.new("hoding", HoldingsState.SCHEMA_VERSION)
	assert_eq(store.read_ledger(), {}, "a key the envelope does not carry reads nothing")
	assert_eq(store.last_reason(), WorldLedgerStore.REASON_UNKNOWN_KEY, "by name")
	assert_eq(bool(store.write_ledger(HoldingsState.empty())["ok"]), false, "and writes nothing")


# --- The shipped wiring ----------------------------------------------------------


func test_the_composition_root_installs_a_save_backed_store_when_the_save_owns_the_key() -> void:
	# `EconomyBoot._install_stores` picks the save's store up through `SaveApi.store_for`, so
	# the shipped path is the durable one. Asserted through the module's own read model: a
	# custody claim made here must still be there after a fresh store reads the file.
	var actor := _actor(&"hero")
	_install_durable()
	EconomyBoot.install(actor)
	var taken := _open_claim(actor)
	assert_eq(bool(taken["ok"]), true, "a claim opens: %s" % taken.get("reason", ""))
	assert_eq(bool(CustodyApi.summary(actor)["store_installed"]), true, "and a store is wired")

	var cold := WorldLedgerStore.new("custody", CustodyState.SCHEMA_VERSION)
	var reread := CustodyState.normalize(cold.read_ledger())
	assert_ne(reread["claims"].get(String(taken["claim_id"])), null, "it is on disk, not in memory")
	assert_eq(
		String((reread["claims"][String(taken["claim_id"])] as Dictionary)["holder"]["id"]),
		"warden",
		"with the holder it was captured under"
	)


func test_the_composition_root_falls_back_to_the_in_memory_seam_when_the_save_owns_nothing(
) -> void:
	# The other half of the rule, and the reason every existing suite is unaffected: no save
	# store installed means the seam is what a module gets, which is the behaviour those suites
	# were written against and must keep.
	var actor := _actor(&"hero")
	var report := EconomyBoot.install(actor)
	assert_eq(bool(report["ok"]), true, "the boot still succeeds: %s" % report.get("reason", ""))
	assert_eq(bool(report["store"]), true, "and still claims the stores are installed")
	assert_eq(bool(HoldingsApi.summary(actor)["store_installed"]), true, "the seam is wired")
	assert_eq(bool(CustodyApi.summary(actor)["store_installed"]), true, "for custody too")


func test_the_economy_boot_still_installs_three_separate_ledgers() -> void:
	# ADR 0101's separation, restated against the shipped path: three modules own three ledgers
	# and `app/` wires them together rather than merging them. Each re-normalizes with its OWN
	# state class, and those normalizers are not interchangeable.
	var actor := _actor(&"hero")
	_install_node()
	EconomyBoot.install(actor)
	assert_eq(bool(HoldingsApi.claim(actor, NODE, _owner(&"warden"))["ok"]), true, "a vein is held")
	# A holdings ledger read as a market ledger loses the `floor` container entirely, and vice
	# versa. Claiming first and then reading the market proves the floor was not merged in.
	var rows: Array = (MarketApi.summary(actor)["floor"] as Dictionary).get("square", [])
	assert_eq(rows.size(), 0, "a holdings claim invents no market drop")
	assert_eq(int(CustodyApi.summary(actor)["claim_count"]), 0, "and no custody claim")
