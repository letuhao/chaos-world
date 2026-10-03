extends TestCase

## **`gather` is not an acquisition route, and no subsystem in the tree can make it one
## today.** 2428 items declare `gather` and `tools/data.py` declares no route for the
## kind.
##
## The standing note calls this a missing subsystem, and unlike `quest` that note is
## right — but it is right for a reason worth pinning, because the nearest-looking
## module is the wrong one. `holdings` has `resource_node_catalog.gd` and
## `resource_node_def.gd`, so "gather" reads as "holdings". It is not, and this suite
## drives the whole node lifecycle to show why:
##
##   claim   `HoldingsApi.claim` writes a holder — the node becomes owned.
##   accrue  `HoldingsApi.accrue` adds `yield_per_period * periods` UNITS to an
##           obligation line keyed by node id. Integers. `ResourceNodeDef` has no
##           exported field of any kind that could name an item.
##   settle  `HoldingsApi.settle` moves units out of the line "into the caller's own
##           accounting", and its own docstring says why: "turning a line into items is
##           the economy's call". The module disclaims items on purpose.
##
## So the shape a `gather` route would need — a world object that yields an ITEM to a
## PLAYER — has no implementation anywhere: no forager, no yield-to-inventory verb, and
## `holdings` declares no `items` dependency in `tools/arch/registry.json`. Building one
## is a new subsystem, not a wiring fix, which is why the answer here is "leave the
## audit reporting 2428 items" rather than "declare the route".
##
## The structural assertion at the end is the one that matters long term: if someone
## adds an item id to `ResourceNodeDef`, the `gather` question becomes a real one and
## this file goes red rather than letting a stale verdict survive.

const NODE := &"vein_acquisition_probe"
const ITEM_KIND_HINTS := ["item", "item_id", "yield_item", "drop", "drops", "loot", "goods"]

var _actor: Actor


func setup() -> void:
	ResourceNodeCatalog.instance().reset()
	ResourceNodeCatalog.instance().install([_node()])
	HoldingsApi.set_store(WorldLedger.new())
	HoldingsApi.set_resolver(func(_kind: String, _id: String) -> Dictionary: return {"ok": true})
	_actor = Actor.new()
	_actor.id = &"gatherer"
	HoldingsApi.attach(_actor)
	ItemsApi.attach(_actor)


## Release the process-wide singletons. Same reason as the other holdings suites: a
## catalog and a store that outlive the suite keep authored resources alive to engine
## shutdown, and ObjectDB then fails a run whose every assertion passed.
func teardown() -> void:
	_actor = null
	HoldingsApi.set_resolver(Callable())
	HoldingsApi.set_store(null)
	ResourceNodeCatalog.instance().reset()


func _node() -> ResourceNodeDef:
	var node := ResourceNodeDef.new()
	node.node_id = NODE
	node.display_name = "Acquisition Probe Vein"
	node.kind = &"ore"
	node.realm = &""
	node.yield_per_period = 5
	node.upkeep_per_period = 1
	node.depletion = 0
	node.claim_floor = 0
	return node


func _owner() -> Dictionary:
	return {"kind": "actor", "id": "gatherer"}


# --- The whole lifecycle, observed --------------------------------------------


## A node that is claimed, worked and settled produces UNITS and nothing else. Read
## through the module's own read model and through the actor's inventory, so the claim
## is not resting on the module's account of itself.
func test_a_fully_worked_node_yields_units_and_no_item_reaches_the_inventory() -> void:
	var inventory := ItemsApi.inventory(_actor)
	assert_eq(inventory.used_slots(), 0, "the bag starts empty")

	var claimed := HoldingsApi.claim(_actor, NODE, _owner())
	assert_eq(
		bool(claimed["ok"]), true, "the node can be claimed: %s" % [claimed.get("reason", "")]
	)

	var worked := HoldingsApi.accrue(_actor, NODE, _owner(), 3)
	assert_eq(bool(worked["ok"]), true, "and worked: %s" % [worked.get("reason", "")])
	assert_eq(int(worked["yielded"]), 15, "yielding units, not items")

	# The line is an obligation ledger keyed by node id — ids and counts, ADR 0083's
	# `InstitutionClaim.obligation` shape. Every row is an integer. That is the durable
	# claim: a pile of goods would be a row holding a dictionary or an array, so the type
	# assertion below is what "never items" means here, and it survives re-authoring.
	var line: Dictionary = HoldingsApi.state(_actor)["line"]
	assert_ne(line.size(), 0, "the yield was written to a line")
	var goods: Array[String] = []
	for key in line.keys():
		if typeof(line[key]) != TYPE_INT:
			goods.append("%s=%s" % [key, typeof(line[key])])
	assert_eq(goods.is_empty(), true, "every row is a count, never a pile of goods: %s" % [goods])
	assert_eq(int(line.get(String(NODE), -1)), 15, "the node's own line carries the whole yield")

	var settled := HoldingsApi.settle(_actor, NODE, 15)
	assert_eq(bool(settled["ok"]), true, "and settles out of it")
	assert_eq(int(settled["settled"]), 15, "as units, into the caller's own accounting")

	assert_eq(
		inventory.used_slots(),
		0,
		"the inventory is untouched: `settle` hands units back and never an item"
	)


## `accrue` is the only verb in the module that produces anything, and its entire
## output is an integer. Pinning the return shape keeps a future "well, it could also
## carry an item id" from arriving without this suite noticing.
func test_the_only_yield_verb_returns_counts_and_carries_no_item() -> void:
	HoldingsApi.claim(_actor, NODE, _owner())
	var worked := HoldingsApi.accrue(_actor, NODE, _owner(), 1)
	var item_shaped: Array[String] = []
	for key in worked.keys():
		var name := String(key)
		for hint in ITEM_KIND_HINTS:
			if name.find(hint) >= 0:
				item_shaped.append(name)
	assert_eq(item_shaped.is_empty(), true, "accrue returns no item-shaped key: %s" % [item_shaped])
	assert_eq(typeof(worked["yielded"]), TYPE_INT, "the yield is a plain count")


# --- The structural reason, which is the durable part -------------------------


## **`ResourceNodeDef` has no field that could name an item.** This is the reason a
## `gather` route cannot be declared, stated as a property of the content type rather
## than as a fact about today's content, so it holds however the catalog is authored.
##
## If this goes red, someone has added an item id to a resource node: the `gather`
## question is now real, and the route decision in `tools/data.py` must be revisited in
## the same change.
func test_a_resource_node_def_carries_no_field_that_could_name_an_item() -> void:
	var item_shaped: Array[String] = []
	for property in _node().get_property_list():
		var name := String(property.get("name", ""))
		if name.begins_with("Resource/"):
			continue
		for hint in ITEM_KIND_HINTS:
			if name.find(hint) >= 0:
				item_shaped.append(name)
	assert_eq(
		item_shaped.is_empty(),
		true,
		(
			"ResourceNodeDef grew an item-shaped field %s; gather is no longer a missing subsystem"
			% [item_shaped]
		)
	)


## The same claim over the def's own read model, which is what a caller or a panel would
## serialize. `to_dict` is the whole surface, so this covers what anything can see.
func test_a_node_read_model_exposes_no_item_id() -> void:
	var view := _node().to_dict()
	var item_shaped: Array[String] = []
	for key in view.keys():
		var name := String(key)
		for hint in ITEM_KIND_HINTS:
			if name.find(hint) >= 0:
				item_shaped.append(name)
	assert_eq(item_shaped.is_empty(), true, "to_dict exposes no item field: %s" % [item_shaped])
	assert_eq(
		typeof(view["yield_per_period"]),
		TYPE_INT,
		"and the yield is a count, which is the whole of what a node produces"
	)


## The runtime's own answer, which `tools/data.py::_route_agreement_problems` cross-checks
## against the gate's routes. Same two-sided pin as the quest suite: a route declared for
## a kind the engine calls unshipped fails the audit, and this is the assertion that says
## the engine's answer is `false`.
func test_the_runtime_itself_reports_the_gather_source_kind_as_unshipped() -> void:
	assert_eq(
		ItemSources.is_shipped(ItemSources.KIND_GATHER),
		false,
		"the engine says no route delivers a gather source, because there is no forager"
	)
	var sources: Array[StringName] = [ItemSources.KIND_GATHER]
	var def := ItemDef.new()
	def.id = &"t_gather_only_ore"
	def.sources = sources
	assert_eq(
		bool(ItemSources.resolve(def)["obtainable"]),
		false,
		"an item on a gather source alone is not obtainable"
	)
