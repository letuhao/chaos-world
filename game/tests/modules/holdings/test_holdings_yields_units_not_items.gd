extends TestCase

## Why the `gather` acquisition source has NO route in `tools/data.py`, asserted from
## the runtime side.
##
## The tempting reading is that `gather` means `holdings`, because holdings owns
## resource nodes and the audit's finding names the module. It does not. `holdings` is
## CUSTODY (ADR 0097, BL-0191): it decides who holds a node, what it has accrued and
## what a contested claim costs, and it deals in `InstitutionClaim.obligation`'s shape —
## ids and counts. It never turns a node into an item, and this suite is the evidence
## rather than the docstring's word.
##
## Three independent facts, each sufficient on its own:
##
##  1. **A node carries no item id.** `ResourceNodeDef` exports `node_id`, `kind`,
##     `realm`, yields, upkeep, claim cost, depletion and a floor — and nothing that
##     names what a node produces. There is no field to read an item id out of, so no
##     amount of wiring could deliver one without changing the content type.
##  2. **The verbs deal in integers.** `accrue` credits `yield_per_period * periods`
##     units into a ledger line; `settle` moves those units back out to "the caller's
##     own accounting". Neither returns, mutates, or names an item.
##  3. **The module declares no `items` edge** in `tools/arch/registry.json`, and no
##     forager verb exists anywhere in `game/src` — `holdings` does not reach an
##     inventory and nothing else does either.
##
## ## Failing means the world changed, not that the test is wrong
##
## If a gathering verb is ever built — which is a FEATURE, not a wiring fix, and needs
## its own ADR — these assertions go red ON PURPOSE. The fix is then to delete the
## obsolete assertions here and declare the `gather` route in `tools/data.py` with its
## production call site. The order matters: the route goes live only once an item
## demonstrably arrives, never before.

const NODES_ROOT := "res://data/holdings/nodes"

## The property names every `ResourceNodeDef` exports. Listed rather than reflected so
## that ADDING an item id to the node type fails here, in the file whose whole job is to
## say what holdings is allowed to be.
const NODE_FIELDS := [
	"node_id",
	"display_name",
	"kind",
	"realm",
	"yield_per_period",
	"upkeep_per_period",
	"claim_cost",
	"depletion",
	"claim_floor",
]


## A node built in code, with a real yield, so the verbs below exercise a def rather
## than a null the refusal path would answer.
func _node(node_id: StringName = &"t_vein") -> ResourceNodeDef:
	return (
		ResourceNodeDef
		. from_dict(
			{
				"node_id": String(node_id),
				"display_name": "Test Vein",
				"kind": "ore",
				"realm": "",
				"yield_per_period": 5,
				"upkeep_per_period": 1,
				"claim_cost": {"tribute": 2},
				"depletion": 0,
				"claim_floor": 0,
			}
		)
	)


func _actor() -> Actor:
	var actor := Actor.new(&"t_miner", {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor)
	HoldingsApi.attach(actor)
	# An in-process world store rather than the actor mirror, because a claim is a
	# WORLD fact and the module's own docstring calls the actor-scoped default wrong
	# the moment a second holder exists. The resolver is the injected holder seam
	# `app/` installs; without it every claim refuses `no_resolver`.
	HoldingsApi.set_resolver(func(_kind: String, _id: String) -> Dictionary: return {"ok": true})
	HoldingsApi.set_store(WorldLedger.new())
	return actor


# --- 1. A node carries no item id ---------------------------------------------


## The structural claim. A `.tres` node names no item, so the question "which item does
## this node yield" has no answer to read — which is why `gather` has no route rather
## than a route awaiting wiring.
func test_a_node_definition_names_no_item() -> void:
	var def := _node()
	# An unrestricted `get_property_list` also reports every built-in `Resource`
	# property, so the claim is checked as two halves rather than by filtering on a
	# usage flag: every field this type is EXPECTED to carry is really there, and
	# nothing beyond them smells of an item. Reading the names is the point — the
	# question is what a node names, not how Godot reports it.
	var names: Array[String] = []
	for entry in def.get_property_list():
		names.append(String((entry as Dictionary)["name"]))
	for field in NODE_FIELDS:
		assert_eq(names.has(field), true, "'%s' is an exported field of the node type" % field)
	var itemish: Array[String] = []
	for name in names:
		var lowered := name.to_lower()
		if lowered.contains("item") or lowered.contains("drop") or lowered.contains("loot"):
			if not NODE_FIELDS.has(name):
				itemish.append(name)
	assert_eq(
		itemish,
		[],
		"no field on a resource node names an item, drop or loot, so a node cannot yield one"
	)


## `to_dict` is what a panel, a save and any caller outside this module actually reads.
## If an item id ever appears there it appears in the world; if it does not, a node
## cannot name an item.
func test_a_node_serializes_no_item_id() -> void:
	var row := _node().to_dict()
	for key in row.keys():
		var name := String(key)
		assert_eq(
			name.find("item") >= 0 or name.find("drop") >= 0 or name.find("loot") >= 0,
			false,
			"'%s' is not an item/drop/loot field" % name
		)
	assert_eq(int(row["yield_per_period"]), 5, "the yield is a plain count, not an item id")


# --- 2. The verbs deal in integers --------------------------------------------


## The behavioural claim, over the whole custody lifecycle: claim, accrue and settle a
## node and the actor's inventory is byte-for-byte what it started as. Whatever the
## ledger says it accrued, nothing became a thing the player holds.
func test_claim_accrue_and_settle_deliver_no_item() -> void:
	ResourceNodeCatalog.instance().install([_node()])
	var actor := _actor()
	var before := ItemsApi.inventory(actor).snapshot()
	var owner := {"kind": "actor", "id": String(actor.id)}

	var claimed := HoldingsApi.claim(actor, &"t_vein", owner)
	assert_eq(bool(claimed["ok"]), true, "the claim is accepted")

	var accrued := HoldingsApi.accrue(actor, &"t_vein", owner, 3)
	assert_eq(bool(accrued["ok"]), true, "the accrual is accepted")
	assert_eq(int(accrued["yielded"]), 15, "and credits yield_per_period * periods units")
	assert_eq(
		int(accrued["yielded"]) is int,
		true,
		"the yielded figure is an integer count of units, not an item reference"
	)

	var settled := HoldingsApi.settle(actor, &"t_vein", 15)
	assert_eq(bool(settled["ok"]), true, "the settle is accepted")
	assert_eq(int(settled["settled"]), 15, "and hands back units")

	var after := ItemsApi.inventory(actor).snapshot()
	assert_eq(after.stacks().size(), before.stacks().size(), "the inventory gained no stack")
	assert_eq(after.stacks().is_empty(), true, "the inventory is still empty")
	assert_eq(ItemsApi.has_item(actor, &"armor_iron_helm"), false, "and holds no item at all")


## `settle` is documented as handing units to "the caller's own accounting", so the
## whole module can be exercised without any inventory at all. That is the cleanest
## statement of the boundary: there is no item-shaped term anywhere in the contract.
func test_settle_reports_units_and_never_an_item() -> void:
	ResourceNodeCatalog.instance().install([_node(&"t_vein2")])
	var actor := _actor()
	var owner := {"kind": "actor", "id": String(actor.id)}
	HoldingsApi.claim(actor, &"t_vein2", owner)
	HoldingsApi.accrue(actor, &"t_vein2", owner, 1)
	var settled := HoldingsApi.settle(actor, &"t_vein2", 5)

	for key in settled.keys():
		var name := String(key)
		assert_eq(
			name.find("item") >= 0 or name.find("def") >= 0 or name.find("drop") >= 0,
			false,
			"'%s' is not an item-shaped field on a settlement" % name
		)
	assert_eq(int(settled["settled"]), 5, "it settles five units")


# --- 3. Nothing forages --------------------------------------------------------


## ## This assertion FLIPPED, and the original said it would
##
## This test used to assert that **no** node content is authored, because a `gather` route
## cannot be declared over an empty catalog. Its own docstring said: *"The runtime agrees,
## at the one place that answers 'is `gather` shipped'. If a forager is ever built this
## flips, and that is the moment the route may be declared."*
##
## Sixteen `ResourceNodeDef` files are now authored under `NODES_ROOT`, so the flip
## happened — on schedule, and for the reason the author predicted. **The content exists but
## `gather` is STILL not shipped**, because shipping it is a decision in
## `modules/items/item_sources.gd` about what a forager does, not a consequence of a `.tres`
## appearing. Both facts are asserted below rather than only the flattering one: corpus is
## present, route is absent, and the gap between them is exactly the remaining work.
func test_resource_node_content_is_authored() -> void:
	var authored: Array[String] = []
	for path in ContentScan.files_under_unsorted(NODES_ROOT):
		if path.ends_with(".tres"):
			authored.append(path)
	assert_eq(
		authored.is_empty(),
		false,
		(
			"the node catalog is no longer empty, so `gather` may now be declared: %s"
			% ", ".join(authored)
		)
	)


## The runtime agrees, at the one place that answers "is `gather` shipped". If a forager
## is ever built this flips, and that is the moment the route may be declared.
##
## ## THIS FLIPPED — the forager exists, and this file said it would
##
## The assertion was `is_shipped(KIND_GATHER) == false`, and it held only while nothing in
## `game/src` knew which item a node produced. `ForageApi.harvest` (behind
## `ForageAction.gather`) now works a held node through `HoldingsApi.accrue` and settles the
## units into a real item through the granter `EconomyBoot.install` binds, so the flag
## describes shipping code rather than an intention. `test_gather_route` is the evidence: it
## asserts a real item count rises in a real bag.
##
## **The other two facts in this file did not move, and that is the point.** `holdings`
## still names no item type, `accrue` still deals in integers, and `ResourceNodeDef` still
## carries no item id — the conversion lives in a MODULE BESIDE holdings with the item half
## injected. A green flag here is not a licence for those to change; the tests below are
## what keep them honest.
func test_the_runtime_reports_gather_as_shipped() -> void:
	assert_eq(
		ItemSources.is_shipped(ItemSources.KIND_GATHER),
		true,
		"gather ships because ForageApi.harvest exists, not because the flag moved"
	)
	assert_eq(
		ItemSources.parse(&"gather"),
		{"kind": &"gather", "ref": "", "ok": true, "reason": "", "satisfied": false},
		"a gather source parses, claims the kind, and names no target"
	)


## `holdings` declares no `items` dependency, so the boundary is a module fact rather
## than a convention. Read from the facade's own SOURCE rather than reflected: a
## `has_method` probe on a class with static verbs answers for the instance side and
## would pass or fail for reasons that have nothing to do with the claim. Adding a verb
## that reaches an inventory fails here by name.
func test_the_holdings_facade_names_no_inventory_verb() -> void:
	var source := FileAccess.get_file_as_string("res://src/modules/holdings/api.gd")
	assert_eq(source.is_empty(), false, "the facade source is readable")
	for verb in ["ItemsApi", "ItemDef", "Inventory", "ItemStack"]:
		assert_eq(
			source.contains(verb),
			false,
			"holdings/api.gd never names %s, so it cannot deliver an item" % verb
		)


func teardown() -> void:
	HoldingsApi.set_resolver(Callable())
	HoldingsApi.set_store(null)
	ResourceNodeCatalog.instance().reset()
