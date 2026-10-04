extends TestCase

## Why a completed quest DELIVERS its item grant instead of recording it.
##
## `QuestGrants.pay` used to record an `item` grant as `unspent` with reason
## `no_inventory_dependency`, on the grounds that `items` was not a declared quest
## dependency. It is declared now, and a granted id that only gets written down is
## the ADR 0065 failure this repository keeps naming: it reads as a working reference
## and hands the player nothing.
##
## ## Every test here drives the SHIPPED path, not a shortcut
##
## `BeatDirector.offer` -> `WorldFact.record` -> `QuestBeatHandler` ->
## `QuestApi.advance` -> `QuestGrants.pay` -> `ItemsApi.generate`. That is the whole
## chain the running game has (`app/world_pulse.gd` registers the sink), so a test
## calling `QuestApi.complete` directly would prove less than it appears to: it would
## skip the director that records the fact and dispatches the sink.
##
## **No test in this file writes an inventory or a ledger row by hand.** The beat is
## offered to the director, which is the production writer of both, and the only verb
## that acquires an item is `ItemsApi.generate`. So an item in the bag at the end of a
## test can only have arrived because a beat completed a quest that owed it.

## The one quest the shipped catalog grants an item to, read from content rather than
## duplicated here: `the_returned_instrument` pays `quest_sealed_letter` once the
## player holds `the_one_who_returned` and once `oaths_discharged` is in the ledger.
const SHIPPED_QUEST := &"the_returned_instrument"
const SHIPPED_ITEM := &"quest_sealed_letter"
const SHIPPED_FACT := &"oaths_discharged"
const SHIPPED_GATE_DESTINY := &"the_one_who_returned"

## A REAL authored item: `craft:` and `domain:` routes, `stackable = false`,
## subcategory `armor`, so it is also the one a test can FILL a bag with or EQUIP.
const REAL_ITEM := &"armor_iron_helm"

## The fixture quest's own id and step fact, named once so the catalog a test installs
## and the ids that test then drives cannot drift apart — which is exactly what made
## an earlier draft of this file report an unclaimed beat instead of its own mistake.
const FIXTURE_QUEST := &"t_owes_a_thing"
const FIXTURE_FACT := &"t_the_thing_is_owed"

const SOURCE := "combat"

## A unique-per-call occurrence id, as `beat_director.gd`'s docstring requires: the
## director deliberately owns no "did this already fire" registry, so the caller names
## WHICH occurrence it is handing over.
var _occurrence := 0


func setup() -> void:
	# No fixture catalog, so `QuestCatalog.instance()` loads the SHIPPED tree. A suite
	# that installed one and returned early would otherwise hand the next test a
	# catalog of its own making, and every content claim here would be about a fixture.
	QuestFixtureCatalog.teardown()
	DestinyFixtureCatalog.teardown()


func teardown() -> void:
	QuestFixtureCatalog.teardown()
	DestinyFixtureCatalog.teardown()


# --- The pipeline, end to end, on shipped content ----------------------------


## **The load-bearing test.** A beat crosses the shipped chain and the quest's item
## grant lands in the bag. Everything else in this suite narrows one branch of it.
##
## Mutation target: break `QuestGrants._deliver` — return the `unknown_item` refusal
## unconditionally, or route `GRANT_ITEM` back to `unspent` — and this goes red on
## `has_item`.
func test_a_beat_that_completes_the_shipped_quest_puts_its_item_in_the_bag() -> void:
	var actor := _shipped_hero()
	# Asserted BEFORE anything is driven, so this test cannot pass on an item that was
	# already in the bag and would therefore prove nothing about delivery.
	assert_eq(ItemsApi.has_item(actor, SHIPPED_ITEM), false, "the bag starts without it")

	var report := _drive(SHIPPED_QUEST, SHIPPED_FACT, actor)

	assert_eq(bool(report["ok"]), true, "the director recorded the beat")
	assert_eq(bool(report["claimed"]), true, "the quest sink claimed it")
	assert_eq(String(report["claimed_by"]), "QuestBeatHandler", "and it names the handler")
	var detail := report["detail"] as Dictionary
	assert_eq(
		(detail["completed"] as Array).has(String(SHIPPED_QUEST)),
		true,
		"the quest completed through the beat, not through a direct call"
	)
	assert_eq(ItemsApi.has_item(actor, SHIPPED_ITEM), true, "and its item grant is in the bag")
	assert_eq((detail["unspent"] as Array).size(), 0, "nothing was left owed")
	assert_eq(
		_ids_of_kind(detail["paid"] as Array, QuestDef.GRANT_ITEM),
		[String(SHIPPED_ITEM)],
		"and the report names the item as paid"
	)


## The delivered instance is a real one, not a bare id: its definition resolves out of
## the bag and a live instance is present to spend, equip or craft with. That is what
## makes the grant an item rather than a line of bookkeeping.
func test_the_delivered_item_resolves_its_own_definition_out_of_the_bag() -> void:
	var actor := _shipped_hero()
	_drive(SHIPPED_QUEST, SHIPPED_FACT, actor)

	var def := ItemsApi.inventory(actor).definition_of(SHIPPED_ITEM)
	assert_ne(def, null, "the bag knows the def the grant named")
	assert_eq(String(def.id), String(SHIPPED_ITEM), "and it is that def")
	assert_ne(
		ItemsApi.inventory(actor).sample(SHIPPED_ITEM),
		null,
		"a live instance is present to spend, equip or craft with"
	)


## **Usable.** The grant is not inert bookkeeping: an item the game delivers can be
## equipped through the facade, which is the strongest use the module offers and the
## only one that proves the realization is functional rather than merely present.
func test_a_delivered_item_can_be_equipped_through_the_facade() -> void:
	QuestFixtureCatalog.install([_fixture(REAL_ITEM)])
	var actor := _hero()
	_drive(FIXTURE_QUEST, FIXTURE_FACT, actor)

	var def := ItemsApi.inventory(actor).definition_of(REAL_ITEM)
	assert_ne(def, null, "the granted item arrived")
	assert_eq(
		ItemsApi.equip_item(actor, &"armor", def),
		true,
		"and the facade equips it, so the delivery is usable rather than inert"
	)
	assert_eq(
		String(ItemsApi.equipment(actor).definition(&"armor").id),
		String(REAL_ITEM),
		"wearing the granted item is what changed"
	)


## ## It persists, and it is not rerolled on the way back
##
## Two claims, because they fail differently: the item can be MISSING after a load
## (the save dropped it) while still being WRONG after a load (the load rerolled it).
## A test that only counted entries would pass on the second, so both halves compare
## the realized payload rather than a presence flag.
##
## `REAL_ITEM` is `stackable = false`, so it is saved as an INSTANCE — the shape that
## carries rolled effects, and the one a reroll would silently change.
func test_a_delivered_instance_survives_a_save_and_load_with_its_realization_intact() -> void:
	QuestFixtureCatalog.install([_fixture(REAL_ITEM)])
	var actor := _hero()
	_drive(FIXTURE_QUEST, FIXTURE_FACT, actor)
	var before := ItemsApi.serialize(actor)["inventory"]["instances"] as Array
	assert_eq(before.size(), 1, "the bag holds the one delivered instance")

	var loaded := Actor.from_dict(actor.to_dict())
	ItemsApi.attach(loaded)

	assert_eq(ItemsApi.has_item(loaded, REAL_ITEM), true, "it is still in the bag")
	var after := ItemsApi.serialize(loaded)["inventory"]["instances"] as Array
	assert_eq(after.size(), 1, "and exactly once: a load must not duplicate it")
	assert_eq(
		String(after[0].get("instance_id", "")),
		String(before[0].get("instance_id", "")),
		"under the same instance id"
	)
	assert_eq(
		after[0].get("effects", before[0].get("effects")),
		before[0].get("effects"),
		"with its realized effects unchanged: a load restores, it never rerolls"
	)


## The other saved shape. `quest_sealed_letter` declares no `stackable`, so it defaults
## to true and is delivered as a STACK — a different row in the payload with its own
## reload path, so asserting only the instance shape above would leave half the
## delivery untested against a save.
func test_a_delivered_stack_survives_a_save_and_load_unchanged() -> void:
	var actor := _shipped_hero()
	_drive(SHIPPED_QUEST, SHIPPED_FACT, actor)
	var before: Dictionary = ItemsApi.serialize(actor)["inventory"]
	assert_eq((before["stacks"] as Array).size(), 1, "delivered as a stack, as authored")

	var loaded := Actor.from_dict(actor.to_dict())
	ItemsApi.attach(loaded)

	assert_eq(ItemsApi.has_item(loaded, SHIPPED_ITEM), true, "it is still in the bag")
	assert_eq(
		ItemsApi.serialize(loaded)["inventory"]["stacks"],
		before["stacks"],
		"byte-for-byte: the quantity and the realized rolls both came back as saved"
	)


# --- Gates, both halves ------------------------------------------------------


## **Half one: a bare actor does not already pass the gate.** The shipped quest is
## `has_destiny: the_one_who_returned`, and a fresh hero holds nothing, so the offer is
## refused. A beat cannot reach it either: the sink only claims beats an ACTIVE quest
## watches, and nothing was ever accepted.
func test_a_bare_actor_is_refused_the_shipped_quest_and_never_receives_its_item() -> void:
	var actor := _hero()
	var refused := QuestApi.accept(actor, SHIPPED_QUEST)

	assert_eq(bool(refused["ok"]), false, "an ungated hero cannot take a gated quest")
	assert_eq(String(refused["reason"]), "gate_unmet", "naming the gate, not the reward")
	var report := _drive(SHIPPED_QUEST, SHIPPED_FACT, actor, false)
	assert_eq(bool(report["claimed"]), false, "so the beat goes unclaimed")
	assert_eq(ItemsApi.has_item(actor, SHIPPED_ITEM), false, "and the item stays out")


## **Half two: the precondition IS satisfiable from a legal prior state.** The gate is
## passed by `DestinyApi.earn_destiny`, which is the facade verb `CharacterCreationFlow`
## and `EventPrize` both call — so a hero holding the authored destiny is a state the
## game can produce, not one only a test can arrange.
func test_earning_the_authored_destiny_is_what_unlocks_the_quest_and_the_item() -> void:
	var actor := _hero()
	assert_eq(
		DestinyApi.has_destiny(actor, SHIPPED_GATE_DESTINY),
		false,
		"the gate names a destiny the hero does not hold yet"
	)
	DestinyApi.earn_destiny(actor, SHIPPED_GATE_DESTINY, "origin")

	assert_eq(DestinyApi.has_destiny(actor, SHIPPED_GATE_DESTINY), true, "now it does")
	assert_eq(bool(QuestApi.accept(actor, SHIPPED_QUEST)["ok"]), true, "so the quest opens")
	# Already accepted on purpose — the accept IS what this test is about — so the
	# drive is told not to repeat it. A second `accept` on the same actor is refused
	# `already_active`, which is the once-guard working correctly; asking `_drive` to
	# accept again would make this suite assert against the module it is testing.
	_drive(SHIPPED_QUEST, SHIPPED_FACT, actor, false)
	assert_eq(ItemsApi.has_item(actor, SHIPPED_ITEM), true, "and the item lands")


## **The delivery precondition is a gate too, and a bare actor must not pass it.** A
## hero with no `items` module has no bag to put anything in, so the grant is refused
## and named — rather than being reported as paid, which is the lie a silent skip
## would tell.
func test_a_hero_with_no_inventory_is_told_the_item_could_not_be_delivered() -> void:
	QuestFixtureCatalog.install([_fixture(REAL_ITEM)])
	var actor := QuestFixtureCatalog.hero()
	var detail := _payout(_drive(FIXTURE_QUEST, FIXTURE_FACT, actor))

	assert_eq(_ids_of_kind(detail["paid"] as Array, QuestDef.GRANT_ITEM), [], "nothing paid")
	assert_eq(
		String((detail["unspent"] as Array)[0]["reason"]),
		QuestGrants.ITEM_NO_INVENTORY,
		"named as a missing bag, which is not the same claim as a full one"
	)
	assert_eq(ItemsApi.inventory(actor), null, "and there is genuinely no bag")


# --- Failure is reachable, and named ----------------------------------------


## The concrete input state is a quest authored with
## `grant(kind=item, id=<an id no content file declares>)`. It is a REFUSAL, not a
## silent skip: the quest completed and owed something that does not exist, and the
## report says so instead of losing the reward quietly.
func test_a_grant_naming_no_real_item_is_refused_with_its_reason() -> void:
	var missing := &"t_no_such_item_def"
	QuestFixtureCatalog.install([_fixture(missing)])
	var actor := _hero()
	var detail := _payout(_drive(FIXTURE_QUEST, FIXTURE_FACT, actor))

	assert_eq(_ids_of_kind(detail["paid"] as Array, QuestDef.GRANT_ITEM), [], "nothing paid")
	assert_eq(
		String((detail["unspent"] as Array)[0]["reason"]),
		QuestGrants.ITEM_UNKNOWN,
		"the refusal names an id the content tree does not have"
	)
	assert_eq(ItemsApi.inventory(actor).used_slots(), 0, "and the bag is untouched")


## The concrete input state is a hero whose bag is at capacity when the quest pays, and
## the bag is holding something ELSE — otherwise "the granted item did not land" would
## be answered by the filler and the refusal would prove nothing. `ItemsApi.generate`
## returns null rather than overflow, so the refusal is total: a delivery that could
## not happen leaves no half-delivered entry behind.
func test_a_full_bag_refuses_the_grant_rather_than_overflowing() -> void:
	QuestFixtureCatalog.install([_fixture(SHIPPED_ITEM)])
	var actor := QuestFixtureCatalog.hero()
	ItemsApi.attach(actor, 1)
	var filler := ItemsApi.generate(actor, Crafting.resolve(REAL_ITEM), 1)
	assert_ne(filler, null, "the one slot is taken by a real item")
	assert_eq(ItemsApi.has_item(actor, SHIPPED_ITEM), false, "not by the item that is owed")
	assert_eq(ItemsApi.inventory(actor).is_full(), true, "so the bag is full")

	var detail := _payout(_drive(FIXTURE_QUEST, FIXTURE_FACT, actor))

	assert_eq(_ids_of_kind(detail["paid"] as Array, QuestDef.GRANT_ITEM), [], "nothing paid")
	assert_eq(
		String((detail["unspent"] as Array)[0]["reason"]),
		QuestGrants.ITEM_INVENTORY_FULL,
		"named as a full bag"
	)
	assert_eq(ItemsApi.has_item(actor, SHIPPED_ITEM), false, "the granted item did not land")
	assert_eq(ItemsApi.inventory(actor).used_slots(), 1, "and the bag is exactly as it was")


## `ItemsApi.generate` realizes ONE unit, and no authored def is `stackable`, so a grant
## of two has no delivery at all. It is refused by name rather than looped over a
## request that cannot be honoured.
func test_a_grant_of_more_than_one_unit_is_refused_rather_than_half_delivered() -> void:
	QuestFixtureCatalog.install([_fixture(REAL_ITEM, 2)])
	var actor := _hero()
	var detail := _payout(_drive(FIXTURE_QUEST, FIXTURE_FACT, actor))

	assert_eq(_ids_of_kind(detail["paid"] as Array, QuestDef.GRANT_ITEM), [], "nothing paid")
	assert_eq(
		String((detail["unspent"] as Array)[0]["reason"]),
		QuestGrants.ITEM_AMOUNT_UNSUPPORTED,
		"the unsupported amount is named rather than quietly delivered as one"
	)
	assert_eq(ItemsApi.has_item(actor, REAL_ITEM), false, "and no single unit sneaked in")


## A grant whose KIND is outside the closed set is refused and reported, never guessed
## at — and it is not mistaken for an item grant, because the kind is checked first.
func test_a_grant_of_a_kind_that_is_not_one_of_the_three_is_refused() -> void:
	QuestFixtureCatalog.install(
		[
			QuestFixtureCatalog.quest(
				&"t_odd_grant",
				QuestDef.KIND_AUTHORED,
				{},
				[{"fact": FIXTURE_FACT}],
				[QuestFixtureCatalog.grant(&"t_not_a_grant_kind", REAL_ITEM)]
			)
		]
	)
	var actor := _hero()
	var detail := _payout(_drive(&"t_odd_grant", FIXTURE_FACT, actor))

	assert_eq((detail["paid"] as Array).size(), 0, "nothing was paid at all")
	assert_eq(
		String((detail["unspent"] as Array)[0]["reason"]),
		"unknown_grant_kind",
		"naming the unreadable kind instead of treating it as an item"
	)
	assert_eq(ItemsApi.has_item(actor, REAL_ITEM), false, "and the bag is untouched")


## The completion report still accounts for every grant: delivered and undeliverable
## together equal what the quest owed. This is the invariant that stops a delivery
## change from quietly DROPPING a grant, which is the failure mode a `paid` list alone
## would hide.
func test_every_grant_a_completed_quest_owes_is_accounted_for_either_way() -> void:
	var actor := _shipped_hero()
	var def := QuestCatalog.instance().definition(SHIPPED_QUEST)
	var detail := _payout(_drive(SHIPPED_QUEST, SHIPPED_FACT, actor))

	assert_ne(def, null, "the shipped quest exists")
	assert_eq(
		(detail["paid"] as Array).size() + (detail["unspent"] as Array).size(),
		QuestGrants.owed(def).size(),
		"paid plus unspent is exactly what was owed, so nothing vanished"
	)


## One grant is delivered exactly once, however many times the fact arrives.
##
## **Two guards stand in front of the second payout, and this asks about both,
## because they are different claims.** The sink's `handles` is a predicate over
## ACTIVE quests, so a completed quest is not even CLAIMED by a later beat and the
## director's report carries no `detail` to read a payout out of. That is the
## outer guard. The module's own once-guard is behind it, and it is reachable only
## by asking `advance` directly — which is exactly what an earlier draft of this
## test got wrong: it read `detail["completed"]` off an unclaimed report, which
## aborted the body mid-function.
func test_a_repeated_beat_delivers_the_item_only_once() -> void:
	QuestFixtureCatalog.install([_fixture(REAL_ITEM)])
	var actor := _hero()
	_drive(FIXTURE_QUEST, FIXTURE_FACT, actor)
	assert_eq(ItemsApi.has_item(actor, REAL_ITEM), true, "the first beat delivered it")

	# A SECOND occurrence of the same fact, offered to the same sink: `WorldFact` is
	# monotone over `fact`, so the ledger count rises and the step is still satisfied.
	var again := _drive(FIXTURE_QUEST, FIXTURE_FACT, actor, false)
	assert_eq(bool(again["claimed"]), false, "the sink does not claim a beat for a finished quest")
	assert_eq(
		QuestFixtureCatalog.held(actor, FIXTURE_FACT),
		2,
		"and the fact really did arrive twice, so nothing above was a coincidence"
	)

	var second := QuestApi.advance(actor, "combat")
	assert_eq((second["completed"] as Array).size(), 0, "nothing completed a second time")
	assert_eq((second["paid"] as Array).size(), 0, "and nothing was paid a second time")
	assert_eq(ItemsApi.inventory(actor).used_slots(), 1, "and the item was not delivered twice")


## ## Both completion paths share one decision, and one once-guard
##
## `advance()` and `complete()` both route through `QuestApi._complete`, which is the
## only caller of `QuestGrants.pay`. Asserted through the other verb: after the beat
## already delivered, an explicit `complete` must refuse rather than hand over a second
## copy. A delivery wired into one branch and not the other is a coin flip, and this is
## what says they are the same decision.
func test_the_explicit_completion_path_cannot_deliver_a_second_copy() -> void:
	QuestFixtureCatalog.install([_fixture(REAL_ITEM)])
	var actor := _hero()
	_drive(FIXTURE_QUEST, FIXTURE_FACT, actor)
	assert_eq(ItemsApi.has_item(actor, REAL_ITEM), true, "the beat delivered it")

	var outcome := QuestApi.complete(actor, FIXTURE_QUEST)

	assert_eq(bool(outcome["ok"]), false, "so the explicit path refuses")
	assert_eq(String(outcome["reason"]), "already_completed", "naming the shared once-guard")
	assert_eq(ItemsApi.inventory(actor).used_slots(), 1, "and the bag still holds exactly one")


# --- Content exists ----------------------------------------------------------


## Every item id the shipped catalog's quests owe resolves to a real authored
## `ItemDef`. The count is asserted too, so a reader can tell an empty corpus from a
## checked one.
func test_every_item_the_shipped_quests_owe_names_a_real_def() -> void:
	var owed := _shipped_owed_item_ids()
	assert_eq(owed.is_empty(), false, "a shipped quest names at least one item")
	for item_id in owed:
		assert_ne(
			Crafting.resolve(StringName(item_id)),
			null,
			"the granted id '%s' resolves to an authored ItemDef" % item_id
		)


## Every item id any shipped quest owes, de-duplicated.
func _shipped_owed_item_ids() -> Array[String]:
	var out: Array[String] = []
	for quest_id in QuestCatalog.instance().quest_ids():
		var def := QuestCatalog.instance().definition(quest_id)
		if def == null:
			continue
		for grant in QuestGrants.owed(def):
			if StringName(grant.get("kind", "")) != QuestDef.GRANT_ITEM:
				continue
			var item_id := String(grant.get("id", ""))
			if not item_id.is_empty() and not out.has(item_id):
				out.append(item_id)
	return out


# --- Helpers -----------------------------------------------------------------


## A one-step, ungated quest whose only grant is `item_id`. `amount` is the grant's
## authored quantity, so a test that wants an unsupported amount asks for it here
## rather than reaching into the resource afterwards.
func _fixture(item_id: StringName, amount: int = 1) -> QuestDef:
	return QuestFixtureCatalog.quest(
		FIXTURE_QUEST,
		QuestDef.KIND_AUTHORED,
		{},
		[{"fact": FIXTURE_FACT}],
		[QuestFixtureCatalog.grant(QuestDef.GRANT_ITEM, item_id, amount)]
	)


## A hero with a bag, ready to be paid into.
func _hero() -> Actor:
	var actor := QuestFixtureCatalog.hero()
	ItemsApi.attach(actor)
	return actor


## A hero with a bag AND the authored destiny the shipped quest is gated on, so a test
## about the shipped pipeline is not quietly blocked by its gate.
func _shipped_hero() -> Actor:
	var actor := _hero()
	DestinyApi.earn_destiny(actor, SHIPPED_GATE_DESTINY, "origin")
	return actor


## Drive `quest_id` to completion over the shipped path and return the director's
## report. `accept_first = false` skips acceptance, so a test can drive a beat at a
## quest the actor was never allowed to take.
##
## The `accept` assertion is deliberate: without it a test that forgot to install its
## fixture catalog produced an unclaimed beat and read as a delivery bug.
func _drive(
	quest_id: StringName, fact: StringName, actor: Actor, accept_first: bool = true
) -> Dictionary:
	var director := BeatDirector.new()
	director.add_sink(QuestBeatHandler.new())
	if accept_first:
		var accepted := QuestApi.accept(actor, quest_id)
		assert_eq(
			bool(accepted["ok"]), true, "the quest was acceptable: %s" % String(accepted["reason"])
		)
	_occurrence += 1
	return director.offer(actor, WorldBeat.make(&"t_occurrence_%d" % _occurrence, fact, 1, SOURCE))


## The sink's payload inside a director report: which quests completed and what they
## paid. Read through the report rather than through `QuestApi`, so every assertion
## here sees what a caller of the director would see.
func _payout(report: Dictionary) -> Dictionary:
	assert_eq(bool(report["claimed"]), true, "the quest sink claimed the beat")
	return report["detail"] as Dictionary


## The ids of every entry of `kind` in a payout list, so an assertion names WHICH grants
## rather than a count that a different grant could satisfy.
func _ids_of_kind(entries: Array, kind: StringName) -> Array[String]:
	var out: Array[String] = []
	for entry in entries:
		if StringName((entry as Dictionary).get("kind", "")) == kind:
			out.append(String((entry as Dictionary).get("id", "")))
	return out
