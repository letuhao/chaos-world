extends TestCase

## The dialogue module's authored conversation, driven end to end from the REAL content
## under `res://data/dialogue/` (ADR 0862).
##
## The claim under test: an authored graph walks, a choice's effect is written BEFORE
## the move so a later node can gate on it, a gated choice is PUBLISHED with its refusal
## rather than dropped, and every refusal names itself and writes nothing.

const NPC := &"elder_wei"
const DIALOG := &"elder_wei_intro"

var _actor: Actor = null


func setup() -> void:
	_actor = _hero()
	DialogueApi.attach(_actor)


func teardown() -> void:
	_actor = null


func _hero() -> Actor:
	var actor := Actor.new(&"t_dialogue_hero", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	return actor


# --- the authored catalog ---------------------------------------------------


## The shipped conversation loads and the catalog reports no authoring complaint.
func test_the_authored_conversation_loads_with_no_problems() -> void:
	var catalog := DialogueCatalog.instance()
	assert_eq(catalog.problems().is_empty(), true, "no problems: %s" % str(catalog.problems()))
	var def := catalog.definition(DIALOG)
	assert_ne(def, null, "the conversation is defined")
	assert_eq(String(def.npc_id), String(NPC), "it belongs to the elder")
	assert_eq(String(def.entry_node), &"intro", "it opens at intro")
	assert_eq(def.node_count(), 3, "three nodes authored")


## `for_npc` answers the conversation an npc owns — the entry the settlement asks for.
func test_the_conversation_resolves_by_npc() -> void:
	var def := DialogueCatalog.instance().for_npc(NPC)
	assert_ne(def, null, "the elder has a conversation")
	assert_eq(String(def.dialog_id), String(DIALOG), "and it is the authored one")


# --- the state machine ------------------------------------------------------


## Starting opens at the entry node and publishes its lines and choices.
func test_start_opens_at_the_entry_node() -> void:
	var opened := DialogueApi.start(_actor, NPC)
	assert_eq(bool(opened["ok"]), true, "start opens: %s" % str(opened))
	assert_eq(String(opened["node_id"]), &"intro", "at the entry node")

	var view := DialogueApi.current(_actor)
	assert_eq(bool(view["ok"]), true, "current renders: %s" % str(view))
	assert_eq(String(view["speaker"]), String(NPC), "the elder speaks")
	assert_eq((view["lines"] as Array).size(), 2, "two lines")
	assert_eq((view["choices"] as Array).size(), 1, "one choice offered")


## A choice carries its effect into the move: the target node can gate on what the
## choice wrote, which is what makes a conversation remember anything across nodes.
func test_a_choice_writes_before_it_moves() -> void:
	DialogueApi.start(_actor, NPC)
	var taken := DialogueApi.choose(_actor, &"ask_oath")
	assert_eq(bool(taken["ok"]), true, "the choice is taken: %s" % str(taken))
	assert_eq(String(taken["node_id"]), &"oath", "it moved to the oath node")

	# The effect landed in the store the node now reads.
	var store := DialogueApi.variables(_actor)
	assert_eq(store.has(&"asked_about_the_oath"), true, "the effect variable was written")

	var view := DialogueApi.current(_actor)
	var choices := view["choices"] as Array
	assert_eq(choices.size(), 2, "the oath node offers two choices")


## The cross-node gate is PUBLISHED locked with a refusal — a locked door is not a
## missing door.
func test_a_gated_choice_is_published_locked() -> void:
	DialogueApi.start(_actor, NPC)
	DialogueApi.choose(_actor, &"ask_oath")

	var gated := _choice(DialogueApi.current(_actor), &"ask_debt")
	assert_ne(gated, null, "the gated choice is published, not dropped")
	assert_eq(bool(gated["locked"]), true, "and it is locked before the fact exists")
	assert_eq(String(gated["refusal"]), "not_yet_set", "with a named refusal")

	# Choosing a locked door refuses BY NAME and writes nothing.
	var refused := DialogueApi.choose(_actor, &"ask_debt")
	assert_eq(bool(refused["ok"]), false, "a locked choice cannot be taken")
	assert_eq(String(refused["reason"]), "not_yet_set", "the refusal is the condition's")


## The gate is satisfied on a store where the variable IS present, and only then does
## the choice open.
func test_the_gate_opens_once_its_fact_is_set() -> void:
	DialogueApi.start(_actor, NPC)
	DialogueApi.choose(_actor, &"ask_oath")
	# Raise the gated threshold, standing on the oath node.
	DialogueApi.write_variable(_actor, &"regard", 2)
	var gated := _choice(DialogueApi.current(_actor), &"ask_debt")
	assert_ne(gated, null, "the choice is there")
	assert_eq(bool(gated["locked"]), false, "and now it is open")
	var taken := DialogueApi.choose(_actor, &"ask_debt")
	assert_eq(bool(taken["ok"]), true, "and it can be taken: %s" % str(taken))
	assert_eq(String(taken["node_id"]), &"debt", "moving to the debt node")


## A terminal choice ends the conversation: the row closes and `current` answers
## `not_talking`.
func test_a_terminal_choice_ends_the_conversation() -> void:
	DialogueApi.start(_actor, NPC)
	DialogueApi.choose(_actor, &"ask_oath")
	var ended := DialogueApi.choose(_actor, &"leave")
	assert_eq(bool(ended["ok"]), true, "the terminal choice is taken")
	assert_eq(bool(ended["ended"]), true, "and it reports the end")

	var view := DialogueApi.current(_actor)
	assert_eq(bool(view["ok"]), false, "nothing is current once the conversation ends")
	assert_eq(String(view["reason"]), "not_talking", "and it says so by name")


# --- refusals ---------------------------------------------------------------


## An npc with no conversation refuses by name and opens nothing.
func test_an_unknown_npc_refuses_by_name() -> void:
	var out := DialogueApi.start(_actor, &"nobody_at_all")
	assert_eq(bool(out["ok"]), false, "no conversation, no start")
	assert_eq(String(out["reason"]), "unknown_dialog", "named refusal")
	assert_eq(bool(DialogueApi.current(_actor)["ok"]), false, "and nothing is open")


## Reading before anything is open refuses `not_talking` rather than inventing a node.
func test_current_before_start_refuses() -> void:
	var out := DialogueApi.current(_actor)
	assert_eq(bool(out["ok"]), false, "nothing is open")
	assert_eq(String(out["reason"]), "not_talking", "named refusal")


## A choice the node does not offer refuses `unknown_choice` and moves nothing.
func test_an_unknown_choice_refuses_and_stays() -> void:
	DialogueApi.start(_actor, NPC)
	var out := DialogueApi.choose(_actor, &"not_a_choice")
	assert_eq(bool(out["ok"]), false, "the choice is not offered")
	assert_eq(String(out["reason"]), "unknown_choice", "named refusal")
	assert_eq(String(DialogueApi.current(_actor)["node_id"]), &"intro", "still on intro")


## A null actor refuses everywhere rather than crashing.
func test_a_null_actor_refuses() -> void:
	assert_eq(String(DialogueApi.start(null, NPC)["reason"]), "no_actor", "start")
	assert_eq(String(DialogueApi.current(null)["reason"]), "no_actor", "current")
	assert_eq(String(DialogueApi.choose(null, &"ask_oath")["reason"]), "no_actor", "choose")


# --- persistence and the bus ------------------------------------------------


## The whole row round-trips through `Actor.to_dict`/`from_dict`, so a conversation
## resumes across a load: where the actor stood and what they had been told.
func test_the_row_survives_a_save_round_trip() -> void:
	DialogueApi.start(_actor, NPC)
	DialogueApi.choose(_actor, &"ask_oath")
	var payload := _actor.to_dict()
	var restored := Actor.from_dict(payload)
	DialogueApi.attach(restored)

	var view := DialogueApi.current(restored)
	assert_eq(bool(view["ok"]), true, "the conversation resumed: %s" % str(view))
	assert_eq(String(view["node_id"]), &"oath", "on the same node")
	assert_eq(
		DialogueApi.variables(restored).has(&"asked_about_the_oath"),
		true,
		"and the variable came back"
	)


## `summary` reports the open conversation and the store as primitives.
func test_summary_reports_the_open_conversation() -> void:
	DialogueApi.start(_actor, NPC)
	var sum := DialogueApi.summary(_actor)
	assert_eq(bool(sum["talking"]), true, "summarised as talking")
	assert_eq(String(sum["dialog_id"]), String(DIALOG), "naming the conversation")
	assert_eq(String(sum["node_id"]), &"intro", "and the node")


## Starting announces on the bus; taking a choice announces the move.
func test_the_bus_announces_a_start_and_a_choice() -> void:
	var seen: Array[String] = []
	var on_started := func(_a: String, _n: String, _d: String, _nd: String): seen.append("started")
	var on_taken := func(_a: String, _c: String, _n: String): seen.append("taken")
	var bus := DialogueApi.events()
	bus.dialogue_started.connect(on_started)
	bus.dialogue_choice_taken.connect(on_taken)

	DialogueApi.start(_actor, NPC)
	DialogueApi.choose(_actor, &"ask_oath")
	assert_eq(seen, ["started", "taken"] as Array[String], "both announced in order")

	bus.dialogue_started.disconnect(on_started)
	bus.dialogue_choice_taken.disconnect(on_taken)


# --- helpers ----------------------------------------------------------------


func _choice(view: Dictionary, choice_id: StringName) -> Dictionary:
	for row in view.get("choices", []) as Array:
		if String((row as Dictionary).get("choice_id", "")) == String(choice_id):
			return row as Dictionary
	return {}
