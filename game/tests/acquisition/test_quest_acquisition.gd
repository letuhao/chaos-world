extends TestCase

## **`quest` is not an acquisition route, and this suite is the proof rather than the
## claim.**
##
## 3076 items declare a `quest` source and `tools/data.py` declares no route for the
## kind, so `data audit` reports them as graph-obtainable and unreachable. The standing
## reason used to be "the quest system does not exist". **That is wrong, and the wrong
## reason is worse than no reason**, because it invites a content fix for a code gap.
## The quest module ships and works; what it cannot do is hand over an item. Driven
## end to end here, once, so the verdict is reproducible:
##
##   accept     `QuestApi.accept` takes the quest — the catalog and gate both answer.
##   satisfy    `WorldFact.record` puts the fact in the shared ledger and
##              `QuestFactReader` reads it at the right depth, so the step is done.
##              (ADR 0117 fixed a reader that asked `ledger.get(fact_id)` of a payload
##              whose keys are `version` and `facts`; this half is what that fix bought,
##              and it is exercised here rather than assumed.)
##   complete   `QuestApi.advance` completes and pays, once — `QuestState.finish`
##              writes a boolean now, so the once-guard is live. (ADR 0117's second
##              fix: it wrote `completed = 0` into a field read with `> 0`, so quests
##              re-paid on every call.)
##   deliver    **nothing.** `QuestGrants.pay` records the item grant as unspent with
##              `no_inventory_dependency`, because `quest` declares no `items`
##              dependency and the module refuses to take an undeclared edge. The
##              actor's inventory is untouched.
##
## The last step is the one `ItemDef.sources` cannot tell you, which is why
## `tools/data.py` trusts nothing here. If item delivery is ever wired, the fourth
## assertion below goes red and the route decision has to be revisited in the same
## change — that is what keeps this file from becoming a stale alibi.

const FACT := &"t_the_road_walked"
const PAYING := &"t_paying_road"
const SEALED := &"t_a_sealed_letter"


func setup() -> void:
	DestinyFixtureCatalog.install([DestinyFixtureCatalog.story_fate(&"t_witnessed")])
	QuestFixtureCatalog.install([_quest()])


## Release the catalog and the destiny catalog this suite installed.
func teardown() -> void:
	QuestFixtureCatalog.teardown()
	DestinyFixtureCatalog.teardown()


func _quest() -> QuestDef:
	return (
		QuestFixtureCatalog
		. quest(
			PAYING,
			QuestDef.KIND_AUTHORED,
			{},
			[{"step_id": &"walked", "fact": FACT, "need": 1}],
			[
				QuestFixtureCatalog.grant(QuestDef.GRANT_FATE, &"t_witnessed"),
				QuestFixtureCatalog.grant(QuestDef.GRANT_ITEM, SEALED),
			]
		)
	)


## An actor with both the quest module and an inventory attached, so "delivered" and
## "not delivered" are distinguishable by observation rather than by reading a verdict
## dictionary. The inventory is the same thing `LootApi` delivers into, which is what
## makes this a comparison rather than an analogy.
func _hero() -> Actor:
	var actor := QuestFixtureCatalog.hero()
	ItemsApi.attach(actor)
	return actor


# --- The chain works, up to the last step ------------------------------------


## The first three hops DO work. If this goes red the reason is the quest chain, not
## the acquisition claim, and the two must not be conflated again.
func test_a_quest_driven_through_shipping_code_completes_and_pays_its_fate_grant() -> void:
	var actor := _hero()
	assert_eq(bool(QuestApi.accept(actor, PAYING)["ok"]), true, "the quest is acceptable")

	# Nothing in `game/src` writes this ledger in production, so the test writes it the
	# way `WorldFact.record` does. That is the honest shape of the demonstration: every
	# step the chain needs is satisfied, and the chain still delivers no item.
	QuestFixtureCatalog.record(actor, FACT, 1)
	assert_eq(QuestFixtureCatalog.held(actor, FACT), 1, "the ledger holds the fact")

	var outcome := QuestApi.advance(actor, "combat")
	assert_eq((outcome["completed"] as Array).has(String(PAYING)), true, "the quest completed")
	assert_eq((outcome["paid"] as Array).size(), 1, "and paid the one grant it can pay")
	assert_eq(String((outcome["paid"] as Array)[0]["kind"]), String(QuestDef.GRANT_FATE), "a fate")


## ADR 0117's once-guard, asserted through the same drive. `advance` is called three
## times: the second and third must pay nothing at all. It used to pay every time.
func test_the_completion_is_once_guarded_across_repeated_advances() -> void:
	var actor := _hero()
	QuestApi.accept(actor, PAYING)
	QuestFixtureCatalog.record(actor, FACT, 1)
	QuestApi.advance(actor, "combat")
	QuestApi.advance(actor, "combat")
	var third := QuestApi.advance(actor, "combat")
	assert_eq((third["completed"] as Array).is_empty(), true, "nothing completed a second time")
	assert_eq((third["paid"] as Array).is_empty(), true, "and nothing was paid a second time")
	assert_eq(
		bool(QuestApi.complete(actor, PAYING)["ok"]), false, "an explicit re-complete refuses"
	)


# --- The step that does not happen --------------------------------------------


## **The verdict.** A quest that completes owes its item grant and delivers nothing:
## the grant comes back unspent, naming the reason, and the inventory is byte-identical.
func test_a_completed_quest_delivers_no_item_and_names_why() -> void:
	var actor := _hero()
	QuestApi.accept(actor, PAYING)
	QuestFixtureCatalog.record(actor, FACT, 1)
	var outcome := QuestApi.advance(actor, "combat")

	var unspent := outcome["unspent"] as Array
	assert_eq(unspent.size(), 1, "exactly the item grant is unpaid")
	assert_eq(String(unspent[0]["id"]), String(SEALED), "and it names the item it owes")
	assert_eq(
		String(unspent[0]["reason"]),
		"no_inventory_dependency",
		"`QuestGrants.pay` refuses the edge rather than taking an undeclared one"
	)


## The same drive, observed on the inventory instead of on the return value — the two
## halves of the claim, because a verdict dictionary is the module's own account of
## itself and an untouched inventory is what the player would see.
func test_a_completed_quest_leaves_the_actor_inventory_untouched() -> void:
	var actor := _hero()
	var inventory := ItemsApi.inventory(actor)
	assert_eq(inventory.used_slots(), 0, "the bag starts empty")

	QuestApi.accept(actor, PAYING)
	QuestFixtureCatalog.record(actor, FACT, 1)
	QuestApi.advance(actor, "combat")

	assert_eq(inventory.used_slots(), 0, "and is still empty after the quest completed")
	assert_eq(ItemsApi.has_item(actor, SEALED), false, "the owed item never entered the inventory")


## A required step nothing has recorded still blocks completion, so the item grant is
## not merely unpaid on the happy path — it is unreachable on every path. `complete()`
## is the hand-off a scripted moment would use, and it refuses with the outstanding step
## rather than paying anyway.
func test_a_required_step_the_world_never_records_blocks_the_item_grant_too() -> void:
	var actor := _hero()
	QuestApi.accept(actor, PAYING)
	var refused := QuestApi.complete(actor, PAYING)
	assert_eq(bool(refused["ok"]), false, "completion with no recorded fact refuses")
	assert_eq(String(refused["reason"]), "steps_unmet", "naming the step, not the reward")
	assert_eq((refused["unmet"] as Array).size(), 1, "and carrying the outstanding step")


# --- The runtime's own answer, which the gate cross-checks --------------------


## `ItemSources` is the only reader of `ItemDef.sources` in `game/src`, and its
## `shipped` flag is the engine's own answer to "can shipping code deliver this kind".
## `tools/data.py::_route_agreement_problems` reads this same table and fails the audit
## if a route is ever declared for a kind the runtime calls unshipped. Asserted here so
## the two-sided claim is falsifiable from both files.
func test_the_runtime_itself_reports_the_quest_source_kind_as_unshipped() -> void:
	assert_eq(
		ItemSources.is_shipped(ItemSources.KIND_QUEST),
		false,
		"the engine says no route delivers a quest source"
	)
	assert_eq(
		ItemSources.unshipped_kind_ids().has(String(ItemSources.KIND_QUEST)),
		true,
		"and lists it among the kinds it cannot deliver"
	)


## What a player would be told. A def resting only on `quest` resolves to
## `no_shipped_route` — the item is declared-and-unreachable, in the runtime's own
## vocabulary. If this ever answers `obtainable`, item delivery has been wired and the
## route decision in `tools/data.py` is now overdue.
func test_resolving_a_quest_only_source_answers_no_shipped_route() -> void:
	var sources: Array[StringName] = [ItemSources.KIND_QUEST]
	var def := ItemDef.new()
	def.id = &"t_quest_only_relic"
	def.sources = sources
	var verdict := ItemSources.resolve(def)
	assert_eq(
		bool(verdict["obtainable"]), false, "an item on a quest source alone is not obtainable"
	)
	assert_eq(
		String(verdict["reason"]),
		ItemSources.NO_SHIPPED_ROUTE,
		"and the reason is the missing route, not an unprobed one"
	)
