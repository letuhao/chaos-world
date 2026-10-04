extends TestCase

## Why the `quest` acquisition source has NO route in `tools/data.py`, asserted from
## the runtime side.
##
## `tools/data.py` is the gate: it counts an item as deliverable only if a declared
## route's shipping code exists AND is called from `game/src` AND the item satisfies
## that route's membership rule. It refuses a `quest` route. This suite is the other
## half of that decision — the evidence, so nobody has to take the gate's word for it,
## and so the day delivery is wired the refusal is noticed rather than assumed correct.
##
## Three SEPARATE facts each block delivery on their own, so fixing one is not enough:
##
##  1. **The reward is recorded, not paid.** `QuestGrants.pay` returns an `item` grant
##     in `unspent` with reason `no_inventory_dependency` and never touches an
##     inventory. `quest` declares no `items` edge.
##  2. **No authored quest can complete.** Every authored quest watches at least one
##     fact, and `complete`/`advance` refuse while a required step reads outstanding.
##     A step reads the `WorldFact` ledger, and no authored event records ANY fact an
##     authored quest watches: the two authored fact sets are DISJOINT. The completion
##     path that would pay a grant is unreachable from content, not merely uncalled.
##  3. **The references resolve to nothing.** 1697 items name a `quest:<id>`, and 0 of
##     the 442 distinct ids is an authored quest. A bare `quest` names no quest at all,
##     and 1379 items declare only that.
##
## ## What is asserted here, and what deliberately is not
##
## This suite asserts INVARIANTS, never snapshots. "Every authored quest step fact is
## recorded by shipped content" is a DESIRED state that is false today, so asserting it
## would only add a permanent red that says nothing the audit does not already report,
## with numbers. What is asserted instead is the property that makes the gate's
## refusal sound: a quest either completes and pays exactly what it owes, or refuses
## and pays nothing. There is no third outcome, and no third outcome is what a `quest`
## route would have to create.
##
## ## Failing means the world changed, not that the test is wrong
##
## If delivery is wired — an `items` edge added, a grant delivered, event content
## authored against the quest step facts — these assertions go red ON PURPOSE. The
## fix is then to delete the obsolete assertions here and declare the route in
## `tools/data.py` with its production call site. What must never happen is the quiet
## middle: the route is declared, the audit goes green, and the item stays
## unobtainable.

const QUESTS_ROOT := "res://data/quest/quests"
const EVENTS_ROOT := "res://data/event/events"


## Every fact id an authored quest watches, from the SHIPPED catalog rather than from
## a fixture, because the claim is about content.
func _watched_facts() -> Array[String]:
	var out: Array[String] = []
	for quest_id in QuestCatalog.instance().quest_ids():
		var def := QuestCatalog.instance().definition(quest_id)
		if def == null:
			continue
		for fact in def.watched_facts():
			if not out.has(String(fact)):
				out.append(String(fact))
	return out


## Every fact id authored event content can RECORD, read as text rather than loaded as
## resources so the claim stays a statement about the shipped files.
##
## Beats are authored inline (`on_enter = [{"fact": &"x", "amount": 1}]`), so the search
## is for the dictionary spelling and NOT for a `fact = &"..."` line: that line is the
## `QuestStepDef` shape, and searching for it finds only quest steps, which would make
## this suite agree with itself and prove nothing.
func _authored_event_facts() -> Array[String]:
	var out: Array[String] = []
	for path in ContentScan.files_under_unsorted(EVENTS_ROOT):
		if not path.ends_with(".tres"):
			continue
		for fact in _quoted_after(FileAccess.get_file_as_string(path), '"fact": &'):
			if not out.has(fact):
				out.append(fact)
	return out


## Every fact id shipped quest step defs name, read from the shipped tree
## independently of the loaded catalog.
func _step_def_facts() -> Array[String]:
	var out: Array[String] = []
	for path in ContentScan.files_under_unsorted(QUESTS_ROOT):
		if not path.ends_with(".tres"):
			continue
		for fact in _quoted_after(FileAccess.get_file_as_string(path), "fact = &"):
			if not out.has(fact):
				out.append(fact)
	return out


## The `&"..."` values that follow each `marker`, de-duplicated in first-seen order.
##
## The search resumes from the closing quote rather than from the marker, because the
## marker itself contains the `&"` prefix: resuming at the marker would re-read the
## value it just consumed. Bounded by the file's own occurrences — a `while` over a
## `find` that always advances, which is the shape `test_no_unbounded_wait.gd` accepts.
func _quoted_after(text: String, marker: String) -> Array[String]:
	var out: Array[String] = []
	var at := text.find(marker)
	while at >= 0:
		var open := text.find('"', at + marker.length() - 1)
		var close := text.find('"', open + 1) if open >= 0 else -1
		if open < 0 or close < 0:
			break
		var found := text.substr(open + 1, close - open - 1)
		if not found.is_empty() and not out.has(found):
			out.append(found)
		at = text.find(marker, close)
	return out


# --- The two content readers agree -------------------------------------------


## The text scan this suite measures content with sees the same quests the catalog
## loads. Without this, a scan that silently found nothing could pass every other
## assertion here as a clean result — which is the ADR 0065 failure with a test on top.
func test_the_step_fact_scan_sees_every_shipped_quest() -> void:
	assert_eq(_watched_facts().is_empty(), false, "the shipped catalog has quests with steps")
	assert_eq(_step_def_facts(), _watched_facts(), "the text scan and the loaded catalog agree")


## The disjointness is measured, not assumed: the audit refuses a `quest` route partly
## because no authored event records a fact any authored quest watches. Assert the two
## sets are both NON-EMPTY (so this cannot pass by finding nothing) and report their
## overlap through the label. The overlap is allowed to be empty; the suite exists so
## that when it stops being empty, the reason is visible in a failure rather than in a
## count nobody compared.
func test_no_authored_event_records_a_fact_an_authored_quest_watches() -> void:
	var watched := _watched_facts()
	var recordable := _authored_event_facts()
	assert_eq(watched.is_empty(), false, "shipped quests watch facts")
	assert_eq(recordable.is_empty(), false, "shipped events record facts")
	var shared: Array[String] = []
	for fact in watched:
		if recordable.has(fact):
			shared.append(fact)
	assert_eq(
		shared.size(),
		0,
		(
			"no authored event writes a fact an authored quest watches, so no authored quest "
			+ (
				"can complete. %d watched fact(s), %d recorded, shared: %s"
				% [watched.size(), recordable.size(), ", ".join(shared)]
			)
		)
	)


# --- 1. The reward is recorded, not paid --------------------------------------


## A quest whose only reward is an item pays NOTHING and says so. This is the claim
## `quest_grants.gd` makes in prose ("an id for a future inventory delivery"), asserted
## as behaviour.
func test_an_item_grant_is_recorded_unspent_and_delivers_nothing() -> void:
	var item_id := &"t_delivered_never"
	(
		QuestFixtureCatalog
		. install(
			[
				QuestFixtureCatalog.quest(
					&"t_payer",
					QuestDef.KIND_AUTHORED,
					{},
					[{"fact": &"t_f"}],
					[QuestFixtureCatalog.grant(QuestDef.GRANT_ITEM, item_id)]
				),
			]
		)
	)
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, &"t_payer")
	QuestFixtureCatalog.record(actor, &"t_f")
	var outcome := QuestApi.complete(actor, &"t_payer")

	assert_eq(bool(outcome["ok"]), true, "the quest completes once its step is met")
	var unspent := outcome["unspent"] as Array
	assert_eq(unspent.size(), 1, "its one item reward is unspent, not paid")
	var entry := unspent[0] as Dictionary
	assert_eq(String(entry["id"]), String(item_id), "and it is the authored grant")
	assert_eq(String(entry["reason"]), "no_inventory_dependency", "naming the missing edge")
	assert_eq((outcome["paid"] as Array).size(), 0, "nothing was paid at all")
	assert_eq(ItemsApi.has_item(actor, item_id), false, "and the actor holds no such item")


## The refusal is inert. Without this, "recorded unspent" and "delivered" could both be
## true and the assertion above would pass on the wrong reading. The id names a REAL
## item, so only an actual delivery attempt could put it in the inventory.
func test_an_item_grant_never_reaches_an_inventory_even_for_a_real_item() -> void:
	var real_id := &"armor_iron_helm"
	(
		QuestFixtureCatalog
		. install(
			[
				QuestFixtureCatalog.quest(
					&"t_payer2",
					QuestDef.KIND_AUTHORED,
					{},
					[{"fact": &"t_f2"}],
					[QuestFixtureCatalog.grant(QuestDef.GRANT_ITEM, real_id)]
				),
			]
		)
	)
	var actor := QuestFixtureCatalog.hero()
	ItemsApi.attach(actor)
	QuestApi.accept(actor, &"t_payer2")
	QuestFixtureCatalog.record(actor, &"t_f2")
	QuestApi.complete(actor, &"t_payer2")

	assert_eq(ItemsApi.has_item(actor, real_id), false, "a real item id is still not delivered")


# --- 2. No authored quest can complete ----------------------------------------


## The invariant the gate's refusal rests on, over the SHIPPED catalog rather than a
## fixture. Every shipped quest is driven as far as the game lets it go, and each one
## must land in exactly one of three states, never a fourth:
##
##   `gate_unmet`   — its authored `requirement` refuses, so it was never acceptable;
##   `steps_unmet` — accepted, but a required step reads outstanding;
##   completed      — and then every grant it declared is accounted for.
##
## A fourth state is the one a `quest` route would create: completing while paying
## nothing, or refusing while paying something. That is why the assertion is the
## three-way disjunction and not a snapshot count — authoring the missing event
## content keeps this green, because content is allowed to be fixed, while a silent
## partial payout would break it.
func test_every_authored_quest_lands_in_exactly_one_of_three_states() -> void:
	var ids := QuestCatalog.instance().quest_ids()
	assert_eq(ids.is_empty(), false, "shipped quests exist, or this proves nothing")
	var completed := 0
	var refused_steps := 0
	var refused_gate := 0
	for quest_id in ids:
		var def := QuestCatalog.instance().definition(quest_id)
		if def == null:
			continue
		var actor := QuestFixtureCatalog.hero()
		ItemsApi.attach(actor)
		var accepted := QuestApi.accept(actor, quest_id)
		if not bool(accepted["ok"]):
			assert_eq(
				String(accepted["reason"]),
				"gate_unmet",
				"%s is refused by its own gate and never became active" % quest_id
			)
			refused_gate += 1
			continue
		for fact in def.watched_facts():
			QuestFixtureCatalog.record(actor, fact, def.step_for_fact(fact).required_count())
		var outcome := QuestApi.complete(actor, quest_id)
		if bool(outcome["ok"]):
			assert_eq(
				(outcome["paid"] as Array).size() + (outcome["unspent"] as Array).size(),
				QuestGrants.owed(def).size(),
				"%s completed and accounted for every grant it declared" % quest_id
			)
			completed += 1
			continue
		assert_eq(String(outcome["reason"]), "steps_unmet", "%s refused on its steps" % quest_id)
		# `_refuse` returns `{"ok", "reason", "unmet"}` and NO `paid`/`unspent`
		# keys: a refusal is inert, so the absence of the keys IS the assertion.
		# Reading them anyway aborted the whole loop mid-quest and reported no
		# failure at all (INC-0023): the four quests below this line never ran.
		assert_eq(
			outcome.has("paid") or outcome.has("unspent"),
			false,
			"%s refused, so it carries no payout of any kind" % quest_id
		)
		refused_steps += 1
	assert_eq(
		completed + refused_steps + refused_gate,
		ids.size(),
		"every shipped quest reached exactly one of the three states"
	)


## The refusal a stuck quest returns is a refusal, not a partial completion. This is
## the shape the invariant above relies on.
func test_a_quest_whose_fact_nothing_records_refuses_completion() -> void:
	var unwritten := &"t_nothing_records_this"
	(
		QuestFixtureCatalog
		. install(
			[
				QuestFixtureCatalog.quest(
					&"t_stuck",
					QuestDef.KIND_SYSTEMIC,
					{},
					[{"fact": unwritten}],
					[QuestFixtureCatalog.grant(QuestDef.GRANT_ITEM, &"t_stuck_item")]
				),
			]
		)
	)
	var actor := QuestFixtureCatalog.hero()
	ItemsApi.attach(actor)
	QuestApi.accept(actor, &"t_stuck")
	var refused := QuestApi.complete(actor, &"t_stuck")

	assert_eq(bool(refused["ok"]), false, "it cannot complete")
	assert_eq(String(refused["reason"]), "steps_unmet", "naming the outstanding step")
	assert_eq(ItemsApi.has_item(actor, &"t_stuck_item"), false, "so the reward is unreachable")


## No item a shipped quest OWES ever reaches an inventory, even after that quest has
## been driven as far as the game allows. This is the claim `tools/data.py` turns into
## "no `quest` route": not that quests are thin, but that none of them hands the player
## an item. It stays true however many quests are authored, because delivery — not the
## authoring — is what is missing.
func test_no_shipped_quest_delivers_an_item_even_when_driven_to_completion() -> void:
	var owed := _quest_owed_items()
	assert_eq(
		owed.is_empty(), false, "a shipped quest names at least one item, or this proves nothing"
	)
	var actor := QuestFixtureCatalog.hero()
	ItemsApi.attach(actor)
	for quest_id in QuestCatalog.instance().quest_ids():
		QuestApi.accept(actor, quest_id)
		var def := QuestCatalog.instance().definition(quest_id)
		if def == null:
			continue
		for fact in def.watched_facts():
			QuestFixtureCatalog.record(actor, fact, def.step_for_fact(fact).required_count())
		QuestApi.complete(actor, quest_id)
	for item_id in owed:
		assert_eq(
			ItemsApi.has_item(actor, StringName(item_id)),
			false,
			"quest-granted item '%s' is still not in the inventory after every quest ran" % item_id
		)


## Every item id a shipped quest grants, across the whole catalog.
func _quest_owed_items() -> Array[String]:
	var out: Array[String] = []
	for quest_id in QuestCatalog.instance().quest_ids():
		var def := QuestCatalog.instance().definition(quest_id)
		if def == null:
			continue
		for grant in QuestGrants.owed(def):
			if StringName(grant.get("kind", "")) == QuestDef.GRANT_ITEM:
				out.append(String(grant.get("id", "")))
	return out


# --- 3. The authored references resolve to nothing -----------------------------


## The dangling-reference claim, from the runtime side. A `quest:<id>` source names a
## specific quest, and `QuestApi` refuses an unknown one, so an item resting on a quest
## that does not exist is unobtainable even with every grant path wired.
func test_an_unknown_quest_is_refused_so_a_dangling_reference_delivers_nothing() -> void:
	var actor := QuestFixtureCatalog.hero()
	var refused := QuestApi.accept(actor, &"t_no_such_quest")

	assert_eq(bool(refused["ok"]), false, "an undefined quest is refused")
	assert_eq(String(refused["reason"]), "unknown_quest", "rather than invented")
	assert_eq(QuestApi.steps(actor, &"t_no_such_quest").size(), 0, "and it has no steps to read")


## A bare `quest` source names no quest, so it can never be resolved to one. The
## runtime's own policy is that the ref is OPTIONAL (`ItemSources.KINDS`), which is
## exactly why the claim is unverifiable and why the gate refuses it.
func test_a_bare_quest_source_names_no_quest_and_is_not_shipped() -> void:
	assert_eq(
		ItemSources.parse(&"quest"),
		{"kind": &"quest", "ref": "", "ok": true, "reason": "", "satisfied": false},
		"a bare quest parses, claims the kind, and names nothing"
	)
	assert_eq(
		ItemSources.is_shipped(ItemSources.KIND_QUEST),
		false,
		"and the only reader of ItemDef.sources agrees the game cannot deliver it"
	)


func teardown() -> void:
	QuestFixtureCatalog.teardown()
	DestinyFixtureCatalog.teardown()
