extends TestCase

## Fate-gated quests (ADR 0398): a quest with `fate_gate` only appears when the
## player holds ALL listed fates. These assert:
##   - an ungated quest is offered regardless of fates held;
##   - a fate-gated quest is NOT offered when the gate is unmet;
##   - a fate-gated quest IS offered when the gate is met;
##   - a fate_gate combined with a requirement requires both to pass;
##   - accept() refuses with gate_unmet when the fate_gate is unmet;
##   - accept() succeeds when the fate_gate is met.

const FATE_X := &"t_fate_x"
const FATE_Y := &"t_fate_y"
const FATE_Z := &"t_fate_z"
const QUEST_OPEN := &"t_quest_open"
const QUEST_GATED := &"t_quest_gated"
const QUEST_BOTH := &"t_quest_both"
const QUEST_MULTI := &"t_quest_multi"


func setup() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[
				DestinyFixtureCatalog.story_fate(FATE_X),
				DestinyFixtureCatalog.story_fate(FATE_Y),
				DestinyFixtureCatalog.story_fate(FATE_Z),
			],
			[DestinyFixtureCatalog.plain_destiny(&"t_destiny_q")]
		)
	)
	(
		QuestFixtureCatalog
		. install(
			[
				QuestFixtureCatalog.quest(QUEST_OPEN, QuestDef.KIND_AUTHORED, {}, []),
				QuestFixtureCatalog.with_fate_gate(
					QuestFixtureCatalog.quest(QUEST_GATED, QuestDef.KIND_AUTHORED, {}, []), [FATE_X]
				),
				QuestFixtureCatalog.with_fate_gate(
					QuestFixtureCatalog.quest(
						QUEST_BOTH,
						QuestDef.KIND_AUTHORED,
						{"verb": &"has_destiny", "id": &"t_destiny_q"},
						[]
					),
					[FATE_Y]
				),
				QuestFixtureCatalog.with_fate_gate(
					QuestFixtureCatalog.quest(QUEST_MULTI, QuestDef.KIND_AUTHORED, {}, []),
					[FATE_X, FATE_Y]
				),
			]
		)
	)


func teardown() -> void:
	QuestFixtureCatalog.teardown()
	DestinyFixtureCatalog.teardown()


func _hero(actor_id: StringName = &"q_keeper") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	DestinyApi.attach(actor)
	QuestApi.attach(actor)
	return actor


func _offered_ids(actor: Actor) -> Array[String]:
	var out: Array[String] = []
	for view in QuestApi.offered(actor):
		out.append(String(view["id"]))
	return out


# --- offered -----------------------------------------------------------------


func test_ungated_quest_is_always_offered() -> void:
	var actor := _hero()
	assert_eq(_offered_ids(actor).has(QUEST_OPEN), true, "ungated quest offered with no fates")


func test_fated_gated_quest_not_offered_when_gate_unmet() -> void:
	var actor := _hero()
	assert_eq(_offered_ids(actor).has(QUEST_GATED), false, "gated quest not offered without fate")


func test_fate_gated_quest_offered_when_gate_met() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, FATE_X, "test")
	assert_eq(_offered_ids(actor).has(QUEST_GATED), true, "gated quest offered with fate held")


func test_fate_gate_combined_with_requirement_requires_both() -> void:
	var actor := _hero()
	# Hold the destiny but not the fate: should NOT be offered.
	DestinyApi.earn_destiny(actor, &"t_destiny_q", "test")
	assert_eq(_offered_ids(actor).has(QUEST_BOTH), false, "fate gate blocks even when destiny met")
	# Hold the fate too: should be offered.
	DestinyApi.earn_fate(actor, FATE_Y, "test")
	assert_eq(_offered_ids(actor).has(QUEST_BOTH), true, "both gates met means offered")


func test_multi_fate_gate_requires_all_fates() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, FATE_X, "test")
	assert_eq(_offered_ids(actor).has(QUEST_MULTI), false, "one of two fates is not enough")
	DestinyApi.earn_fate(actor, FATE_Y, "test")
	assert_eq(_offered_ids(actor).has(QUEST_MULTI), true, "both fates held means offered")


# --- accept ------------------------------------------------------------------


func test_accept_refuses_when_fate_gate_unmet() -> void:
	var actor := _hero()
	var verdict := QuestApi.accept(actor, QUEST_GATED)
	assert_eq(bool(verdict["ok"]), false, "accept refused")
	assert_eq(String(verdict["reason"]), "gate_unmet", "reason is gate_unmet")


func test_accept_succeeds_when_fate_gate_met() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, FATE_X, "test")
	var verdict := QuestApi.accept(actor, QUEST_GATED)
	assert_eq(bool(verdict["ok"]), true, "accept succeeds")
	assert_eq(String(verdict["reason"]), "", "no refusal reason")
