extends TestCase

## The `dialogue` module's boot wiring (ADR 0862, DEF-0014). The module shipped with a
## runtime, a compiler and 83 green assertions and **no production caller at all**, so an
## actor never carried a conversation row and `DialogueApi.start` could not be reached
## from the shipped program — the same shape BL-0663 closed for `quest`.
##
## The attach list is read from the SOURCE rather than restated: a peer deleting the line
## fails here instead of shipping the wiring silently away.

const BODY := "res://src/app/item_workbench_body.gd"


## The composition root's attach list names the dialogue phase.
func test_the_composition_root_attaches_the_dialogue_module() -> void:
	var body := FileAccess.get_file_as_string(BODY)
	assert_ne(body, "", "%s ships, so this is not a silent skip" % BODY)
	assert_eq(
		body.contains("DialogueApi.attach("),
		true,
		"the composition root attaches the dialogue module"
	)


## `attach` is what gives the actor its row: without it `summary` reports nothing and
## every verb refuses `not_talking` forever.
func test_attaching_gives_the_actor_a_conversation_row() -> void:
	var actor := Actor.new(&"t_dialogue_boot", {Stat.PHYSIQUE: 10.0})
	DialogueApi.attach(actor)
	var sum := DialogueApi.summary(actor)
	assert_eq(bool(sum["has_actor"]), true, "the row reads back")
	assert_eq(bool(sum["talking"]), false, "and no conversation is open at boot")
	assert_eq(String(sum["dialog_id"]), "", "with no conversation named")


## And the attached actor can actually OPEN the shipped conversation - the end-to-end
## claim, not just the presence of a call.
func test_an_attached_actor_can_open_the_shipped_conversation() -> void:
	var actor := Actor.new(&"t_dialogue_boot_open", {Stat.PHYSIQUE: 10.0})
	DialogueApi.attach(actor)
	var started := DialogueApi.start(actor, &"elder_wei")
	assert_eq(bool(started["ok"]), true, "the shipped conversation opens: %s" % str(started))
	assert_eq(String(started["node_id"]), "intro", "at its entry node")
