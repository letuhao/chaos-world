extends TestCase

## The conversation screen (ADR 0862, DEF-0014): it renders the `dialogue` facade and
## drives it, and it authors no prose of its own.
##
## Driven with NO scene tree, like every screen contract test: `_bind_nodes` resolves
## nothing, so every case below asserts the read model rather than pixels.

const NPC := &"elder_wei"


func _screen() -> DialogueScreen:
	var screen := DialogueScreen.new()
	var actor := Actor.new(&"t_dialogue_screen", {Stat.PHYSIQUE: 10.0})
	DialogueApi.attach(actor)
	screen.setup(actor)
	return screen


## No actor, no view — the base's rule.
func test_no_actor_summarises_empty() -> void:
	var screen := DialogueScreen.new()
	assert_eq(screen.summary(), {}, "no actor, no view")


## The authored conversation is offered by npc id, read from the facade's catalog.
func test_the_authored_conversation_is_listed() -> void:
	var screen := _screen()
	var view := screen.summary()
	assert_ne(view, {}, "with an actor there is a view")
	assert_eq(bool(view["talking"]), false, "nobody is talking yet")
	var named := false
	for row in view["conversations"] as Array:
		if String((row as Dictionary).get("npc_id", "")) == String(NPC):
			named = true
	assert_eq(named, true, "the elder's conversation is listed")


## Starting one reports the node and the speaker, both authored content.
func test_starting_a_conversation_reports_it() -> void:
	var screen := _screen()
	var outcome := screen.act_start(NPC)
	assert_eq(bool(outcome["ok"]), true, "it opens: %s" % str(outcome))
	var view := screen.summary()
	assert_eq(bool(view["talking"]), true, "the conversation is open")
	assert_eq(String(view["node_id"]), "intro", "at the entry node")
	assert_eq(String(view["speaker"]), String(NPC), "and the elder speaks")


## A terminal choice ends the conversation, and the screen reports it.
func test_a_terminal_choice_ends_the_conversation() -> void:
	var screen := _screen()
	screen.act_start(NPC)
	screen.act_choose(&"ask_oath")
	screen.act_choose(&"leave")
	assert_eq(bool(screen.summary()["talking"]), false, "the conversation ended")


## Walking away from the page is the act of ending the conversation.
func test_leaving_the_page_ends_the_conversation() -> void:
	var screen := _screen()
	screen.act_start(NPC)
	screen.on_screen_hidden()
	assert_eq(bool(screen.summary()["talking"]), false, "walking away ended it")


## A refusal is named, never silent: choosing an option the node does not offer answers
## the module's own reason.
func test_a_refused_choice_names_its_reason() -> void:
	var screen := _screen()
	screen.act_start(NPC)
	var outcome := screen.act_choose(&"not_a_choice")
	assert_eq(bool(outcome["ok"]), false, "the choice is not offered")
	assert_eq(String(outcome["reason"]), "unknown_choice", "named refusal")
