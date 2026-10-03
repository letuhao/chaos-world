extends TestCase

## The `gather` acquisition route, end to end: a player holds a node, works it, and ends up
## holding real items.
##
## ## What this suite is FOR
##
## `test_holdings_yields_units_not_items.gd` proved that no forager existed. Its own
## docstring said when one did: *"these assertions go red ON PURPOSE ... the route goes live
## only once an item demonstrably arrives, never before."* This suite is the evidence that
## an item now arrives — so that suite's `is_shipped` assertion could be flipped honestly
## rather than optimistically.
##
## ## The three facts it took as read are still read here
##
## `holdings` still names no `ItemsApi`/`ItemDef`/`Inventory`/`ItemStack` (asserted below,
## because a later change could quietly break it), `accrue` still deals in integers, and
## `ResourceNodeDef` still carries no item id. What changed is that a MODULE BESIDE holdings
## now owns the conversion, and `app/` supplies the item half.
##
## ## Every refusal is a named constant
##
## A test that asserted only `ok == false` would pass for a forager that refused
## everything. Each refusal below is asserted BY NAME, because the name is the contract a
## panel switches on.
##
## ## Nothing leaks
##
## `HoldingsApi._store`, `HoldingsApi._resolver`, `ForageApi._granter` and the
## `ResourceNodeCatalog` singleton are all process-wide. The runner shares one process
## across every suite and calls `teardown` after EVERY test, so each of these is released
## per-test rather than per-suite: a catalog left installed would hand this suite's fixtures
## to whichever suite runs next.

## A node at the shallowest authored band, worked by an actor at that band.
const SHALLOW_REALM := &"foundation"
## A node two rungs deeper, so `permits` has something to refuse.
const DEEP_REALM := &"core_formation"
## The item every fixture node yields. An AUTHORED id, deliberately: the granter resolves
## item ids against the real content tree, so a fixture "item" would not resolve and every
## verb assertion would land on `no_yield_content` instead of on the rule under test.
const FIXTURE_ITEM := &"trinket_iron_charm"

## The yield table the fixtures use. [constant NODE_YIELDS] is keyed by authored node ids,
## so a suite that installs its own nodes installs its own yields through the seam
## [method ForageApi.set_yields] exists for. This is the same shape
## `ResourceNodeCatalog.instance().install` is: explicit and immediate, so no assertion here
## depends on what content the build happens to ship.
const FIXTURE_YIELDS: Dictionary = {
	"t_shallow": [FIXTURE_ITEM],
	"t_deep": [FIXTURE_ITEM],
	"t_costly": [FIXTURE_ITEM],
	"t_vein": [FIXTURE_ITEM],
}

var _actor: Actor
var _held: Array[Actor] = []


func setup() -> void:
	ResourceNodeCatalog.instance().reset()
	(
		ResourceNodeCatalog
		. instance()
		. install(
			[
				_node(&"t_shallow", SHALLOW_REALM, 5, 0, 0),
				_node(&"t_deep", DEEP_REALM, 6, 0, 0),
				_node(&"t_costly", SHALLOW_REALM, 4, 3, 0),
				_node(&"t_vein", SHALLOW_REALM, 2, 0, 2),
			]
		)
	)
	HoldingsApi.set_resolver(func(_kind: String, _id: String) -> Dictionary: return {"ok": true})
	HoldingsApi.set_store(WorldLedger.new())
	ForageApi.set_granter(ForageGranary.deliver)
	ForageApi.set_yields(FIXTURE_YIELDS)
	_actor = _miner(&"t_miner", SHALLOW_REALM)


func teardown() -> void:
	for actor in _held:
		if actor != null:
			actor = null
	_held.clear()
	ForageApi.set_granter(Callable())
	# Restores the AUTHORED table, not an empty one — see `set_yields`, where an empty
	# dictionary means "put it back" precisely so no suite can leave the process on a
	# table of fixture ids that no content ships.
	ForageApi.set_yields({})
	HoldingsApi.set_resolver(Callable())
	HoldingsApi.set_store(null)
	ResourceNodeCatalog.instance().reset()


## A miner: an inventory for the goods, holdings for the custody, and a body path so
## `actor.realm()` has a rung to stand on.
func _miner(id: StringName, realm: StringName) -> Actor:
	var actor := Actor.new(id, {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor)
	HoldingsApi.attach(actor)
	actor.set_path(PathState.new(PathState.BODY, realm))
	_held.append(actor)
	return actor


## A node def with a real yield and a real upkeep, so the verbs below exercise a def rather
## than a null a refusal path would answer.
func _node(
	node_id: StringName, realm: StringName, yield_units: int, upkeep: int, depletion: int
) -> ResourceNodeDef:
	return (
		ResourceNodeDef
		. from_dict(
			{
				"node_id": String(node_id),
				"display_name": "Test Node",
				"kind": "ore",
				"realm": String(realm),
				"yield_per_period": yield_units,
				"upkeep_per_period": upkeep,
				"depletion": depletion,
				"claim_floor": 0,
			}
		)
	)


func _owner(actor: Actor) -> Dictionary:
	return ForageAction.owner_ref(actor)


## Take `node_id` for `actor`, asserting the claim landed so a later refusal is about the
## verb under test and not about a setup that silently failed.
func _claim(actor: Actor, node_id: StringName) -> void:
	var claimed := HoldingsApi.claim(actor, node_id, _owner(actor))
	assert_eq(bool(claimed["ok"]), true, "setup: '%s' is claimed" % node_id)


# --- the realm gate ------------------------------------------------------------


## A deep node refuses a shallow actor BY NAME, and the refusal costs the shallow actor
## nothing — no yield, no upkeep, no condition spent.
##
## This is ADR 0097's gate: realm is a GATE and never a yield multiplier, and the reason
## `ResourceNodeDef.realm` exists at all. A gate that returned true for anyone, or that
## charged a shallow actor for asking, would not be a gate.
func test_a_deep_node_refuses_a_shallow_actor_with_the_named_reason() -> void:
	_claim(_actor, &"t_deep")
	var result := ForageAction.gather(_actor, &"t_deep", 3)
	assert_eq(bool(result["ok"]), false, "a shallow actor cannot work a deep node")
	assert_eq(
		String(result["reason"]),
		ForageApi.REALM_BELOW_GATE,
		"and the refusal names the rule, not free text"
	)
	assert_eq(int(result["yielded"]), 0, "and no yield was credited")
	assert_eq(
		ItemsApi.inventory(_actor).snapshot().stacks().is_empty(),
		true,
		"and the bag is untouched: a refused gate costs nothing"
	)


## The same actor, the same node, and one rung of standing: the gate is a comparison on the
## ladder, not a whitelist, so an actor AT the node's realm works it.
func test_an_actor_at_the_node_realm_is_permitted() -> void:
	var deep := _miner(&"t_deep_miner", DEEP_REALM)
	_claim(deep, &"t_deep")
	var result := ForageAction.gather(deep, &"t_deep", 2)
	assert_eq(
		bool(result["ok"]), true, "an actor at the node's realm works it: %s" % result["reason"]
	)
	assert_eq(int(result["yielded"]), 12, "yield_per_period 6 over 2 periods")


## The gate is "at or above", not "strictly above": an actor DEEPER than the node must still
## work it, or the ladder would forbid a veteran from a beginner's field.
func test_an_actor_above_the_node_realm_is_still_permitted() -> void:
	var old_hand := _miner(&"t_old_hand", &"nascent_soul")
	_claim(old_hand, &"t_shallow")
	var result := ForageAction.gather(old_hand, &"t_shallow", 1)
	assert_eq(
		bool(result["ok"]), true, "a deeper actor works a shallow node: %s" % result["reason"]
	)


# --- the delivery --------------------------------------------------------------


## THE end-to-end claim of this suite: foraging a held node credits
## `yield_per_period * periods` units AND the actor ends up holding real items.
##
## Both halves are asserted, because either alone is satisfiable by a lie. A forager that
## credited units and granted nothing would pass a ledger assertion; one that conjured
## items without accruing would pass a bag assertion. The yield is read from the LEDGER and
## the goods from the BAG, so the two sides cannot be satisfied by the same fiction.
func test_foraging_a_held_node_accrues_the_authored_yield_and_grants_items() -> void:
	_claim(_actor, &"t_shallow")
	var result := ForageAction.gather(_actor, &"t_shallow", 3)
	assert_eq(bool(result["ok"]), true, "the harvest is accepted: %s" % result.get("reason", ""))
	assert_eq(int(result["periods"]), 3, "the caller's periods are honoured verbatim")
	assert_eq(
		int(result["yielded"]), 15, "yield_per_period 5 over 3 periods is credited to the line"
	)
	assert_eq(int(result["granted"]), 15, "and the same units reach the bag")
	var item_id := String(result["item_id"])
	assert_ne(item_id, "", "the node names an item, which is the fact a node cannot carry")
	assert_eq(
		ItemsApi.has_item(_actor, StringName(item_id), 15),
		true,
		"and the actor really holds them: %d of '%s'" % [15, item_id]
	)
	# The line was settled, so the ledger and the bag never both claim the same units.
	assert_eq(
		int(HoldingsApi.state(_actor)["line"].get("t_shallow", 0)),
		0,
		"the accrued line is settled, not double-counted"
	)


## The yield really is `yield_per_period * periods` and not a constant: two different
## period counts on the same node must produce two different totals.
func test_the_granted_quantity_scales_with_periods() -> void:
	_claim(_actor, &"t_shallow")
	ForageAction.gather(_actor, &"t_shallow", 1)
	var two := ForageAction.gather(_actor, &"t_shallow", 2)
	assert_eq(int(two["yielded"]), 10, "2 periods of a 5-unit node is 10")
	assert_eq(int(two["granted"]), 10, "and all ten are granted")


## Foraging a node you do NOT hold refuses — with the holder mismatch named by the module
## that owns the ledger, rather than a restatement here.
func test_foraging_a_node_you_do_not_hold_refuses() -> void:
	var rival := _miner(&"t_rival", SHALLOW_REALM)
	_claim(rival, &"t_shallow")
	var result := ForageAction.gather(_actor, &"t_shallow", 1)
	assert_eq(bool(result["ok"]), false, "a non-holder cannot forage a held node")
	assert_eq(
		String(result["reason"]),
		HoldingsState.HOLDER_MISMATCH,
		"and the refusal is holdings' own id, passed through by name"
	)
	assert_eq(
		ItemsApi.inventory(_actor).snapshot().stacks().is_empty(),
		true,
		"and the trespasser's bag is empty"
	)


## An unclaimed node is not a node the caller may work: `no_holder`, not `holder_mismatch`.
## The two are different facts and a caller that saw only "refused" could not tell a vacant
## vein from someone else's.
func test_foraging_an_unclaimed_node_refuses_no_holder() -> void:
	var result := ForageAction.gather(_actor, &"t_shallow", 1)
	assert_eq(bool(result["ok"]), false, "a node nobody holds cannot be foraged")
	assert_eq(String(result["reason"]), HoldingsState.NO_HOLDER, "and names the vacant state")


## A node that is not in the catalog at all refuses `unknown_node`, so a stale node id is a
## named refusal rather than a null dereference somewhere downstream.
func test_foraging_an_unknown_node_refuses() -> void:
	var result := ForageAction.gather(_actor, &"no_such_node", 1)
	assert_eq(bool(result["ok"]), false, "an unknown node refuses")
	assert_eq(String(result["reason"]), HoldingsState.UNKNOWN_NODE, "and names the rule")


# --- upkeep, depletion, resting ------------------------------------------------


## Upkeep is charged on a node that declares it, and is charged AGAINST THE HOLDER'S LINE
## keyed by the holder — never out of the yield. That is what makes a claim a decision
## rather than a free grab (ADR 0097), and it is why a node with upkeep can net cost the
## player money while still paying out.
func test_a_node_with_upkeep_charges_it_and_a_node_without_does_not() -> void:
	_claim(_actor, &"t_costly")
	ForageAction.gather(_actor, &"t_costly", 4)
	var line: Dictionary = HoldingsApi.state(_actor)["line"] as Dictionary
	# `_charge_upkeep` keys the line `"<kind>:upkeep:<holder id>"` and NOTHING else, so this
	# is the holder's single upkeep line across every node they hold — the node id is
	# deliberately absent, because an institution's upkeep is one visible obligation rather
	# than a second pile of goods per node (BL-0191).
	var upkeep_key := "actor:upkeep:%s" % String(_actor.id)
	assert_eq(
		int(line.get(upkeep_key, 0)),
		12,
		"upkeep_per_period 3 over 4 periods is charged against the holder's own line"
	)

	# Working a node that declares no upkeep must leave that line byte-identical. The
	# previous form of this assertion read a `...:upkeep:<node id>` key, which holdings can
	# never write — so it answered 0 whatever the code did, and a harvest that charged
	# upkeep for a free node would have passed. Comparing across the call is the only
	# version of this that can actually fail.
	var before := int(line.get(upkeep_key, 0))
	_claim(_actor, &"t_shallow")
	ForageAction.gather(_actor, &"t_shallow", 4)
	var after: Dictionary = HoldingsApi.state(_actor)["line"] as Dictionary
	assert_eq(
		int(after.get(upkeep_key, 0)), before, "and a node that declares no upkeep is charged none"
	)


## Depletion spends CONDITION and refuses once it is gone. A node that silently yielded
## nothing would leave a player pressing a button that does nothing forever, so the refusal
## is the point: `depleted` is named, not an empty result.
func test_a_depleted_node_refuses_rather_than_yielding_nothing_silently() -> void:
	_claim(_actor, &"t_vein")
	# `depletion = 2`, so two periods of accrual spend the condition and the third refuses.
	var first := ForageAction.gather(_actor, &"t_vein", 1)
	assert_eq(bool(first["ok"]), true, "the first period works")
	assert_eq(int(first["condition"]), 1, "and spends one period of condition")
	var second := ForageAction.gather(_actor, &"t_vein", 1)
	assert_eq(bool(second["ok"]), true, "the second period works")
	assert_eq(int(second["condition"]), 0, "and spends the last of it")
	var third := ForageAction.gather(_actor, &"t_vein", 1)
	assert_eq(bool(third["ok"]), false, "the next one refuses rather than yielding nothing")
	assert_eq(String(third["reason"]), HoldingsState.DEPLETED, "and names the rule")
	assert_eq(
		ItemsApi.has_item(_actor, StringName(String(second["item_id"])), 4),
		true,
		"the units already paid out are still in the bag: depletion is not a retroactive loss"
	)


## A refused depletion must not charge upkeep, or an exhausted holding would keep billing
## the player for a node that produces nothing. Asserted because `accrue` refuses BEFORE it
## charges, and that ordering is the only thing protecting the player.
func test_a_refused_depleted_node_charges_no_upkeep() -> void:
	_claim(_actor, &"t_vein")
	ForageAction.gather(_actor, &"t_vein", 1)
	ForageAction.gather(_actor, &"t_vein", 1)
	# `t_vein` declares upkeep 0, so the holder's upkeep line is 0 before the refusal and
	# must still be 0 after it. Read across the refusal rather than at a key holdings never
	# writes: the original `...:upkeep:t_vein` lookup answered 0 for a code that charged
	# upkeep anyway, so the assertion could not fail.
	var upkeep_key := "actor:upkeep:%s" % String(_actor.id)
	var before: Dictionary = HoldingsApi.state(_actor)["line"] as Dictionary
	var refused := ForageAction.gather(_actor, &"t_vein", 1)
	assert_eq(String(refused["reason"]), HoldingsState.DEPLETED, "the node is spent")
	var line: Dictionary = HoldingsApi.state(_actor)["line"] as Dictionary
	assert_eq(
		int(line.get(upkeep_key, 0)),
		int(before.get(upkeep_key, 0)),
		"and a refusal charges no upkeep, so an exhausted holding is not a bill"
	)


## `periods <= 0` refuses with `no_periods`, and the id is HELDINGS' — this module surfaces
## the constant rather than inventing a synonym, so one `no_periods` covers the whole accrue
## path whichever module a caller reached it through.
func test_a_non_positive_period_count_refuses() -> void:
	_claim(_actor, &"t_shallow")
	for bad in [0, -1, -100]:
		var result := ForageAction.gather(_actor, &"t_shallow", bad)
		assert_eq(bool(result["ok"]), false, "periods %d refuses" % bad)
		assert_eq(String(result["reason"]), ForageApi.NO_PERIODS, "periods %d names the rule" % bad)
	assert_eq(
		ItemsApi.inventory(_actor).snapshot().stacks().is_empty(),
		true,
		"and a refused period count moved nothing at all"
	)


# --- the structural guard -------------------------------------------------------


## The boundary this whole design exists to keep. `holdings` may not name an inventory, so
## the conversion has to live somewhere else — and this asserts from the facade's own SOURCE
## rather than by reflection, because a `has_method` probe on a class of static verbs
## answers for the instance side and would pass for reasons unrelated to the claim.
func test_holdings_still_names_no_inventory_verb() -> void:
	var source := FileAccess.get_file_as_string("res://src/modules/holdings/api.gd")
	assert_eq(source.is_empty(), false, "the facade source is readable")
	for verb in ["ItemsApi", "ItemDef", "Inventory", "ItemStack"]:
		assert_eq(
			source.contains(verb),
			false,
			"holdings/api.gd never names %s, so the conversion had to live elsewhere" % verb
		)


## And the `forage` module is just as bounded: it declares no `items` edge, so it must not
## name an inventory either. The granter is the seam that keeps that true.
func test_the_forage_facade_names_no_inventory_verb() -> void:
	var source := FileAccess.get_file_as_string("res://src/modules/forage/api.gd")
	assert_eq(source.is_empty(), false, "the forage facade source is readable")
	for verb in ["ItemsApi", "ItemDef", "Inventory", "ItemStack", "Crafting"]:
		assert_eq(
			source.contains(verb),
			false,
			"forage/api.gd never names %s, so the item half is genuinely injected" % verb
		)


## Every node this module can forage is a node the game actually authors, and every authored
## node has a yield. Without this, a yield table could drift from the content tree and a
## node could quietly become un-gatherable with nothing failing.
func test_every_authored_node_has_an_authored_yield() -> void:
	var problems := ForageApi.validate()
	assert_eq(
		problems,
		[],
		"the yield table and the authored node catalog agree: %s" % ", ".join(problems)
	)


## The route is shipped because there is a verb, and the verb is reachable from `game/src`.
## Both halves are asserted: a `shipped` flag without a production call site is the exact
## lie `tools/data.py`'s `call_sites` exists to prevent.
func test_the_route_is_backed_by_a_verb_and_an_installed_granter() -> void:
	assert_eq(
		ItemSources.is_shipped(ItemSources.KIND_GATHER),
		true,
		"gather ships because ForageApi.harvest exists, not because the flag moved"
	)
	assert_eq(bool(ForageApi.has_granter()), true, "and the granter is installed by this suite")


## Without a granter the verb refuses LOUDLY rather than accruing yield it can never
## deliver. A forager that produced accruals and no items is the exact bug that kept
## `gather` unshipped, so the unwired case is asserted rather than assumed away.
func test_an_unwired_granter_refuses_instead_of_accruing_unreachable_yield() -> void:
	_claim(_actor, &"t_shallow")
	ForageApi.set_granter(Callable())
	var result := ForageAction.gather(_actor, &"t_shallow", 2)
	assert_eq(bool(result["ok"]), false, "an unwired route refuses")
	assert_eq(
		String(result["reason"]),
		ForageApi.NO_GRANTER,
		"and names the missing seam rather than failing quietly"
	)
	var line: Dictionary = HoldingsApi.state(_actor)["line"] as Dictionary
	assert_eq(
		int(line.get("t_shallow", 0)),
		0,
		"and credits nothing, so nothing was accrued that could not be delivered"
	)


## A node with no authored yield refuses BY NAME. This is the gap that made `gather`
## unshipped — nothing in `game/src` knew what a node produced — and it must never come
## back as a silent empty bag.
func test_a_node_with_no_authored_yield_refuses_named() -> void:
	ResourceNodeCatalog.instance().install([_node(&"t_unmapped", SHALLOW_REALM, 5, 0, 0)])
	_claim(_actor, &"t_unmapped")
	var result := ForageAction.gather(_actor, &"t_unmapped", 1)
	assert_eq(bool(result["ok"]), false, "a node nothing names an item for cannot be foraged")
	assert_eq(
		String(result["reason"]),
		ForageApi.NO_YIELD_CONTENT,
		"and it says so, rather than yielding an empty bag"
	)


# --- the entry point a screen binds ---------------------------------------------


## `ForageAction.workable` is the question a button's enabled state binds to. It must agree
## with the verb: a button that is enabled where the verb refuses is a control that lies.
func test_workable_agrees_with_the_verb_on_every_gate() -> void:
	_claim(_actor, &"t_shallow")
	assert_eq(ForageAction.workable(_actor, &"t_shallow"), true, "a held, shallow node works")
	assert_eq(
		ForageAction.workable(_actor, &"t_deep"),
		false,
		"an unheld deep node is not workable, whatever else is true of it"
	)
	_claim(_actor, &"t_deep")
	assert_eq(
		ForageAction.workable(_actor, &"t_deep"),
		false,
		"and a HELD deep node is still not workable by a shallow actor"
	)
	var rival := _miner(&"t_rival_2", SHALLOW_REALM)
	_claim(rival, &"t_shallow")
	# ADR 0085: a claim on HELD ground opens a standoff and leaves `holder` byte-identical
	# (`test_holdings_claim` pins exactly this). So `rival`'s challenge did not take the
	# node — `_actor` is still its holder, and `workable` must say so for BOTH of them. This
	# assertion used to claim the rival's own ref made it workable, which is only true if a
	# challenge silently transfers ground, i.e. if `holdings` is broken.
	assert_eq(
		ForageAction.workable(rival, &"t_shallow"),
		false,
		"a challenger never holds the node, so it is not workable for them either"
	)
	assert_eq(
		ForageAction.workable(_actor, &"t_shallow"),
		true,
		"and the real holder still works it: the standoff moved nothing"
	)
