extends TestCase

## The properties BL-0053 and ADR 0113 claim, asserted rather than described.
##
## The through-line of every test here: **a quest READS the world's memory and
## never counts its own progress.** Progress in this suite is only ever produced by
## `QuestFixtureCatalog.record()`, which writes the ADR 0113 ledger the way core
## does. `QuestApi` exposes no write verb at all, so a step can only ever be
## satisfied from outside this module.

const TRACK := &"t_tracked_road"
const GATED := &"t_gated_road"
const UNGATED := &"t_open_road"
const OPTIONAL := &"t_optional_road"
const PAYING := &"t_paying_road"
const UNKNOWN := &"t_never_authored"

const FACT_A := &"t_fact_a"
const FACT_B := &"t_fact_b"
const FACT_GATED := &"t_fact_gated"
const FACT_OPTIONAL := &"t_fact_optional"

const DESTINY := &"t_returned"
const FATE := &"t_witnessed"
const PAY_FATE := &"t_paid_fate"
const PAY_DESTINY := &"t_paid_destiny"

## A REAL authored `ItemDef` (`res://data/items/equipment/armor_iron_helm.tres`,
## `stackable = false`), so an `item` grant naming it has something real to
## deliver. A made-up id would make the delivered case indistinguishable from the
## refused one.
const REAL_ITEM := &"armor_iron_helm"


func setup() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[
				DestinyFixtureCatalog.story_fate(FATE),
				DestinyFixtureCatalog.story_fate(PAY_FATE),
				DestinyFixtureCatalog.story_fate(&"t_blocker"),
			],
			[
				DestinyFixtureCatalog.plain_destiny(DESTINY),
				DestinyFixtureCatalog.plain_destiny(PAY_DESTINY)
			]
		)
	)
	(
		QuestFixtureCatalog
		. install(
			[
				QuestFixtureCatalog.quest(
					TRACK,
					QuestDef.KIND_SYSTEMIC,
					{},
					[{"step_id": &"a", "fact": FACT_A, "need": 2}]
				),
				QuestFixtureCatalog.quest(
					GATED,
					QuestDef.KIND_AUTHORED,
					{"verb": &"has_destiny", "id": DESTINY},
					[{"step_id": &"g", "fact": FACT_GATED, "need": 1}]
				),
				QuestFixtureCatalog.quest(
					UNGATED,
					QuestDef.KIND_EMERGENT,
					{},
					[{"step_id": &"u", "fact": FACT_B, "need": 1}]
				),
				QuestFixtureCatalog.quest(
					OPTIONAL,
					QuestDef.KIND_AUTHORED,
					{},
					[
						{"step_id": &"req", "fact": FACT_A, "need": 1},
						{"step_id": &"opt", "fact": FACT_OPTIONAL, "need": 5, "optional": true}
					]
				),
				(
					QuestFixtureCatalog
					. quest(
						PAYING,
						QuestDef.KIND_AUTHORED,
						{},
						[{"step_id": &"p", "fact": FACT_A, "need": 1}],
						[
							QuestFixtureCatalog.grant(QuestDef.GRANT_FATE, PAY_FATE),
							QuestFixtureCatalog.grant(QuestDef.GRANT_DESTINY, PAY_DESTINY),
						]
					)
				),
			]
		)
	)


func teardown() -> void:
	QuestFixtureCatalog.teardown()
	DestinyFixtureCatalog.teardown()


# --- The gate is data, and it holds content shut ----------------------------


## A gated quest is not offered until the destiny is earned, and it is not
## ACCEPTABLE until then either. Both halves matter: offering it and then
## refusing the accept would put a quest on screen the player can never take.
func test_a_gated_quest_is_not_offered_until_the_destiny_is_earned() -> void:
	var actor := QuestFixtureCatalog.hero()
	assert_eq(_offered_ids(actor).has(String(GATED)), false, "a gated quest is not offered first")

	var refused := QuestApi.accept(actor, GATED)
	assert_eq(bool(refused["ok"]), false, "accepting a gate-unmet quest refuses")
	assert_eq(String(refused["reason"]), "gate_unmet", "the refusal names the gate")
	assert_ne(
		(refused["unmet"] as Array).size(), 0, "the refusal carries the gate's own unmet list"
	)

	DestinyApi.earn_destiny(actor, DESTINY, "quest:test")
	assert_eq(
		_offered_ids(actor).has(String(GATED)), true, "the quest opens once the destiny is held"
	)
	assert_eq(bool(QuestApi.accept(actor, GATED)["ok"]), true, "and is now acceptable")


## A composite gate fails on ONE unmet child and reports it, so an `all_of`
## requirement cannot open on a partial match.
func test_a_composite_gate_refuses_until_every_child_holds() -> void:
	var both := QuestFixtureCatalog.quest(
		&"t_two_gates",
		QuestDef.KIND_AUTHORED,
		{
			"verb": &"all_of",
			"of": [{"verb": &"has_destiny", "id": DESTINY}, {"verb": &"has_fate", "id": FATE}]
		},
		[{"step_id": &"x", "fact": FACT_B, "need": 1}]
	)
	QuestFixtureCatalog.install([both])
	var actor := QuestFixtureCatalog.hero()
	DestinyApi.earn_destiny(actor, DESTINY, "quest:test")
	assert_eq(_offered_ids(actor).is_empty(), true, "one of two children is not enough")
	DestinyApi.earn_fate(actor, FATE, "quest:test")
	assert_eq(_offered_ids(actor), [String(&"t_two_gates")], "both children open the quest")


# --- Steps read the shared ledger, and never count themselves --------------


## The ADR 0113 property in one test: progress recorded by SOMEONE ELSE in the
## shared ledger satisfies a step, and the quest module contributed nothing to
## that ledger.
func test_steps_read_the_shared_ledger_and_are_not_counted_by_the_quest() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, TRACK)

	var before := _steps_of(actor, TRACK)
	assert_eq(int(before[0]["have"]), 0, "a step starts at the ledger's count")
	assert_eq(bool(before[0]["done"]), false, "and is not done")

	QuestFixtureCatalog.record(actor, FACT_A, 2)
	var after := _steps_of(actor, TRACK)
	assert_eq(int(after[0]["have"]), 2, "the step reads the ledger's count, not a private one")
	assert_eq(bool(after[0]["done"]), true, "the ledger's count satisfies it")

	# And the quest module wrote NOTHING to the ledger. The only rows present are
	# the one the test wrote. A quest that kept its own counter would show a row
	# this module created.
	var ledger: Dictionary = actor.get_module_data(&"world_facts")
	assert_eq((ledger["facts"] as Dictionary).size(), 1, "the quest added no fact of its own")


## A quest must not be able to complete itself. Accepting a quest, reading its
## steps and calling advance() with no world activity completes nothing.
func test_a_quest_completes_only_when_the_world_records_something() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, TRACK)
	for _call in range(3):
		var outcome := QuestApi.advance(actor, "test")
		assert_eq((outcome["completed"] as Array).is_empty(), true, "no progress, no completion")
	assert_eq(DestinyApi.has_fate(actor, PAY_FATE), false, "and nothing was paid")


# --- Completion is decided once, and pays once -----------------------------


## The strongest claim in the module. Three advances pay exactly one fate: the
## ledger's completion row is the once-guard and it is checked before any grant
## moves, so a repeat call cannot pay even a grant with no guard of its own.
func test_completing_pays_its_fate_grant_exactly_once_across_three_advances() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, PAYING)
	QuestFixtureCatalog.record(actor, FACT_A, 1)

	var first := QuestApi.advance(actor, "combat")
	assert_eq(first["completed"], [String(PAYING)], "the first advance completes the quest")
	assert_eq((first["paid"] as Array).size(), 2, "and pays both authored grants")

	for _call in range(3):
		var repeat := QuestApi.advance(actor, "combat")
		assert_eq(
			(repeat["completed"] as Array).is_empty(), true, "a repeat advance completes nothing"
		)

	assert_eq(_fate_source_actor_count(actor, PAY_FATE), 1, "one fate, one earning")


## The explicit path is guarded by the same once-guard, so a caller that drives
## completion from a dialogue cannot double-pay after an `advance()` already did.
func test_an_explicit_complete_after_an_advance_pays_nothing_twice() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, PAYING)
	QuestFixtureCatalog.record(actor, FACT_A, 1)
	QuestApi.advance(actor, "combat")

	var repeat := QuestApi.complete(actor, PAYING)
	assert_eq(bool(repeat["ok"]), false, "an explicit complete after an advance refuses")
	assert_eq(String(repeat["reason"]), "already_completed", "and names the once-guard")
	assert_eq(_fate_source_actor_count(actor, PAY_FATE), 1, "still one fate")


## `advance()` is idempotent: five calls with no new facts change nothing at all.
func test_advance_is_idempotent() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, PAYING)
	QuestFixtureCatalog.record(actor, FACT_A, 1)

	var first := QuestApi.advance(actor, "combat")
	var shape := _ledger_shape(actor)
	for _call in range(5):
		var repeat := QuestApi.advance(actor, "combat")
		assert_eq((repeat["completed"] as Array).is_empty(), true, "a repeat advance is a no-op")
	assert_eq(_ledger_shape(actor), shape, "the ledger is byte-identical after five extra advances")
	assert_eq((first["completed"] as Array).size(), 1, "the first advance was the only completion")


## The explicit path refuses when a REQUIRED step is unmet, and says which.
func test_a_completion_with_unmet_required_steps_refuses() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, TRACK)

	var refused := QuestApi.complete(actor, TRACK)
	assert_eq(bool(refused["ok"]), false, "completing an unmet quest refuses")
	assert_eq(String(refused["reason"]), "steps_unmet", "the refusal names the step gate")
	assert_eq((refused["unmet"] as Array).size(), 1, "and carries the outstanding step")

	# One short of the need is still unmet; `need` is a count, not a flag.
	QuestFixtureCatalog.record(actor, FACT_A, 1)
	assert_eq(bool(QuestApi.complete(actor, TRACK)["ok"]), false, "one of two is still unmet")
	QuestFixtureCatalog.record(actor, FACT_A, 1)
	assert_eq(bool(QuestApi.complete(actor, TRACK)["ok"]), true, "two of two completes it")


## An OPTIONAL step is flavour, never a blocker. If it could block, the flag would
## be a lie and a player could be hard-stuck on a quest they were always allowed
## to finish without it.
func test_an_optional_step_never_blocks_completion() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, OPTIONAL)
	QuestFixtureCatalog.record(actor, FACT_A, 1)

	var outcome := QuestApi.advance(actor, "combat")
	assert_eq(
		outcome["completed"], [String(OPTIONAL)], "the quest completes on its required step alone"
	)
	var steps := _steps_of(actor, OPTIONAL)
	assert_eq(bool(steps[1]["done"]), false, "the optional step is still outstanding")
	assert_eq(bool(steps[1]["optional"]), true, "and reports itself optional")


# --- Refusals name themselves ----------------------------------------------


## Every refusal carries a machine-readable reason, because "no" is not an API.
func test_every_refusal_names_a_reason() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, UNGATED)

	assert_eq(
		String(QuestApi.accept(actor, UNKNOWN)["reason"]), "unknown_quest", "an unauthored id"
	)
	assert_eq(
		String(QuestApi.accept(actor, UNGATED)["reason"]), "already_active", "a second accept"
	)
	assert_eq(
		String(QuestApi.complete(actor, UNKNOWN)["reason"]), "unknown_quest", "completing nothing"
	)
	# `OPTIONAL`, not a made-up id: the catalog has to DEFINE a quest for the
	# refusal to be about the quest never being accepted. An id the catalog does
	# not ship is correctly `unknown_quest`, so the original spelling here was
	# asserting the wrong refusal and passing only because both were wrong.
	assert_eq(
		String(QuestApi.complete(actor, OPTIONAL)["reason"]),
		"not_active",
		"completing a quest never accepted"
	)


# --- DEF-0107, closed -------------------------------------------------------


## The fate source string is exactly what DEF-0107 prescribed, read off the
## destiny ledger's own entry. A quest that paid under some other string would
## leave a history a player cannot read.
func test_a_fate_grant_is_earned_with_the_prescribed_source_string() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, PAYING)
	QuestFixtureCatalog.record(actor, FACT_A, 1)
	QuestApi.advance(actor, "combat")

	var entry: Dictionary = (DestinyApi.state(actor)["fates"] as Dictionary)[String(PAY_FATE)]
	assert_eq(String(entry["source"]), "quest:%s" % PAYING, "DEF-0107's source string, verbatim")


## An `item` grant naming an id no content file declares is RECORDED as unspent,
## never delivered, and it names the cause. **This is the refusal half, and it is
## what the delivered case is measured against:** `paid` means "in the bag", so a
## grant that resolves is paid (below) and one that does not is `unknown_item`
## rather than a grant quietly written down.
##
## The id is deliberately one nothing authors: the point is that an unresolvable
## reference is refused by name instead of becoming the ADR 0065 lie.
func test_an_item_grant_naming_no_real_definition_is_recorded_as_unspent_with_its_reason() -> void:
	var paying := QuestFixtureCatalog.quest(
		&"t_item_paying",
		QuestDef.KIND_AUTHORED,
		{},
		[{"step_id": &"i", "fact": FACT_A, "need": 1}],
		[QuestFixtureCatalog.grant(QuestDef.GRANT_ITEM, &"t_a_sealed_letter")]
	)
	QuestFixtureCatalog.install([paying])
	var actor := QuestFixtureCatalog.hero()
	ItemsApi.attach(actor)
	QuestApi.accept(actor, &"t_item_paying")
	QuestFixtureCatalog.record(actor, FACT_A, 1)

	var outcome := QuestApi.advance(actor, "combat")
	assert_eq((outcome["paid"] as Array).is_empty(), true, "an unresolvable grant id pays nothing")
	assert_eq((outcome["unspent"] as Array).size(), 1, "but it is recorded as owed")
	assert_eq(
		String((outcome["unspent"] as Array)[0]["reason"]),
		QuestGrants.ITEM_UNKNOWN,
		"and names the missing definition rather than a dependency the module does have"
	)
	assert_eq(ItemsApi.inventory(actor).used_slots(), 0, "so the bag is untouched")


## The delivered half, through the same facade verb. `items` IS a declared quest
## dependency (`tools/arch/registry.json`), so a grant naming a real authored
## `ItemDef` is realized into the actor's bag and reported as PAID. This used to
## be the opposite assertion — an `item` grant paid nothing this module could do
## — which was true only while the edge was undeclared.
##
## `REAL_ITEM` is read from content, not invented here, and it is a
## `stackable = false` armor, so a resolution that silently returned null would
## fail on the bag as well as on `paid`.
func test_an_item_grant_naming_a_real_definition_is_delivered_into_the_bag() -> void:
	var paying := QuestFixtureCatalog.quest(
		&"t_item_delivering",
		QuestDef.KIND_AUTHORED,
		{},
		[{"step_id": &"d", "fact": FACT_A, "need": 1}],
		[QuestFixtureCatalog.grant(QuestDef.GRANT_ITEM, REAL_ITEM)]
	)
	QuestFixtureCatalog.install([paying])
	var actor := QuestFixtureCatalog.hero()
	ItemsApi.attach(actor)
	assert_eq(ItemsApi.has_item(actor, REAL_ITEM), false, "the bag starts without it")

	QuestApi.accept(actor, &"t_item_delivering")
	QuestFixtureCatalog.record(actor, FACT_A, 1)
	var outcome := QuestApi.advance(actor, "combat")

	assert_eq((outcome["unspent"] as Array).size(), 0, "nothing was left owed")
	assert_eq(
		String((outcome["paid"] as Array)[0]["kind"]),
		String(QuestDef.GRANT_ITEM),
		"and the item grant is the one reported as paid"
	)
	assert_eq(ItemsApi.has_item(actor, REAL_ITEM), true, "so the grant is in the bag")


## A grant id carrying a reserved namespace is REFUSED. `quest:*` is the exact
## failure ADR 0065 names: an id that "reads as a working reference and silently
## grants nothing". Refusing loudly is the whole point.
func test_a_namespaced_grant_id_is_refused_rather_than_silently_losing() -> void:
	var broken := QuestFixtureCatalog.quest(
		&"t_namespaced",
		QuestDef.KIND_AUTHORED,
		{},
		[{"step_id": &"n", "fact": FACT_A, "need": 1}],
		[QuestFixtureCatalog.grant(QuestDef.GRANT_FATE, &"quest:not_a_fate_id")]
	)
	QuestFixtureCatalog.install([broken])
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, &"t_namespaced")
	QuestFixtureCatalog.record(actor, FACT_A, 1)

	var outcome := QuestApi.advance(actor, "combat")
	assert_eq((outcome["completed"] as Array).size(), 1, "the quest still completes")
	assert_eq((outcome["paid"] as Array).is_empty(), true, "but the bad grant pays nothing")
	assert_eq(
		String((outcome["unspent"] as Array)[0]["reason"]),
		"reserved_namespace",
		"and names the reserved namespace as the reason"
	)


## An unknown grant kind is refused and reported. Treating it as "no reward"
## would lose content without saying so.
func test_an_unknown_grant_kind_is_refused_and_reported() -> void:
	var broken := QuestFixtureCatalog.quest(
		&"t_unknown_kind",
		QuestDef.KIND_AUTHORED,
		{},
		[{"step_id": &"k", "fact": FACT_A, "need": 1}],
		[QuestFixtureCatalog.grant(&"nothing", &"t_thing")]
	)
	QuestFixtureCatalog.install([broken])
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, &"t_unknown_kind")
	QuestFixtureCatalog.record(actor, FACT_A, 1)

	var outcome := QuestApi.advance(actor, "combat")
	assert_eq(
		String((outcome["unspent"] as Array)[0]["reason"]),
		"unknown_grant_kind",
		"'nothing' is not a grant kind, and an unreadable grant is refused"
	)


# --- The facade's own surface ----------------------------------------------


## Other modules may reference ONLY `api.gd`, so the facade is the whole
## reachable surface — and the cap is a hard arch failure above twelve. Naming
## every verb means an unlisted method added later fails here rather than
## silently shipping.
func test_the_facade_is_the_documented_surface_and_nothing_more() -> void:
	var public := _public_methods()
	assert_eq(
		public,
		[
			"accept",
			"active",
			"advance",
			"attach",
			"catalog",
			"complete",
			"gates_for",
			"offered",
			"steps",
			"summary"
		],
		"the facade is the documented quest surface, and nothing else"
	)
	assert_eq(public.size() <= 12, true, "and it is under the twelve-method cap")


## A quest module that could take a fact back could un-take a completion, which
## is the ADR 0065 failure applied to progress. No public name may carry a
## removal verb.
func test_the_facade_exposes_no_write_verb_against_the_fact_ledger() -> void:
	for name in _public_methods():
		for forbidden in ["record", "write", "add_fact", "set_fact", "reset"]:
			assert_eq(
				name.contains(forbidden),
				false,
				"'%s' must not expose a ledger write verb ('%s')" % [name, forbidden]
			)


# --- Helpers ----------------------------------------------------------------


func _offered_ids(actor: Actor) -> Array[String]:
	var out: Array[String] = []
	for view in QuestApi.offered(actor):
		out.append(String(view["id"]))
	return out


func _steps_of(actor: Actor, quest_id: StringName) -> Array[Dictionary]:
	return QuestApi.steps(actor, quest_id)


## How many earning records name `fate_id` in the destiny ledger's history. The
## ledger's own history is the audit trail, so counting it measures the number of
## times the earn RAN, which is what "paid exactly once" means.
func _fate_source_actor_count(actor: Actor, fate_id: StringName) -> int:
	var found := 0
	for record in DestinyApi.state(actor)["history"] as Array:
		var entry := record as Dictionary
		if (
			String(entry.get("kind", "")) == "fate"
			and String(entry.get("id", "")) == String(fate_id)
		):
			found += 1
	return found


func _ledger_shape(actor: Actor) -> String:
	return JSON.stringify(QuestApi.summary(actor))


## The verbs `QuestApi` publishes to other modules — every function the facade
## SCRIPT declares, minus the `_`-prefixed helpers.
##
## Read off the loaded `GDScript` rather than off `self`: the question is what
## `quest` exposes, not what this suite happens to be named, and a bare
## `get_script_method_list()` here asked the wrong object — it is a method on
## `Script`, not on the `RefCounted` a suite instance is, so this file did not
## even parse. `get_script_method_list()` on the loaded script returns the
## script's OWN declarations and not the inherited `Object` surface, which is why
## the inherited-name whitelist this used to carry is gone. The same call is how
## `tests/modules/sect/test_sect_founding.gd` reads that facade.
##
## `load()` rather than a `class_name` reference because a facade is all static
## functions and GDScript refuses a non-static call on a class reference. An
## unreadable facade hands back an empty list, which the surface test above fails
## on rather than quietly accepts.
func _public_methods() -> Array[String]:
	var out: Array[String] = []
	var script: GDScript = load("res://src/modules/quest/api.gd")
	if script == null:
		return out
	for method in script.get_script_method_list():
		var name := String(method["name"])
		if name.begins_with("_") or out.has(name):
			continue
		out.append(name)
	out.sort()
	return out
