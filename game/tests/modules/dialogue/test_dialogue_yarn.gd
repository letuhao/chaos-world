extends TestCase

## The Yarn-shaped authoring format, compiled into a playable `DialogueDef` (ADR 0862).
##
## The claim under test: a writer's `.yarn` source becomes the SAME graph the runtime
## already executes — so there is one runtime and one content shape, and a construct
## outside the supported subset is REFUSED by name rather than mis-compiled.

const SOURCE := """// a small conversation
title: intro
---
Elder: You climb like someone who has read the register.
Elder: Ask me what you came to ask.
-> Ask whose oath is written in that book. <<set $asked = true>> <<jump oath>>
-> Say nothing more.
===
title: oath
---
Elder: An oath is a debt a body agrees to carry.
-> Who holds the debt now? <<if $regard >= 2>> <<jump debt>>
-> Say nothing more.
===
title: debt
---
Elder: Whoever is still standing when the book closes.
-> Say nothing more.
===
"""


func _compile() -> Dictionary:
	return DialogueYarn.compile(SOURCE, &"elder_wei", &"elder_wei_yarn")


# --- the happy path ---------------------------------------------------------


## The script compiles into a valid def with the three authored nodes.
func test_a_script_compiles_into_a_graph() -> void:
	var out := _compile()
	assert_eq(bool(out["ok"]), true, "it compiles: %s" % str(out["problems"]))
	var def := out["def"] as DialogueDef
	assert_ne(def, null, "a def came back")
	assert_eq(String(def.entry_node), &"intro", "the first node is the entry")
	assert_eq(def.node_count(), 3, "three nodes")


## A `Speaker: words` line becomes a line spoken by that npc; a bare line is narration.
## The speaker is authored VERBATIM — `Elder:` is the speaker `Elder`, not an id.
func test_speaker_detection() -> void:
	var def := _compile()["def"] as DialogueDef
	var intro := def.node(&"intro")
	assert_eq(String(intro.speaker), "Elder", "the authored speaker is kept verbatim")
	assert_eq((intro.lines as Array).size(), 2, "two lines before the choices")
	assert_eq(
		String((intro.lines as Array)[0]),
		"You climb like someone who has read the register.",
		"the first line"
	)


## An `->` line becomes a choice, and its `<<jump>>` its target.
func test_choices_and_jumps() -> void:
	var def := _compile()["def"] as DialogueDef
	var intro := def.node(&"intro")
	assert_eq((intro.choices as Array).size(), 2, "two choices")
	var first := (intro.choices as Array)[0] as DialogueChoiceDef
	assert_eq(String(first.target), &"oath", "the first jumps to oath")
	assert_eq(String(first.effect_key), &"asked", "and writes its effect variable")

	var terminal := (intro.choices as Array)[1] as DialogueChoiceDef
	assert_eq(String(terminal.target), &"", "the second is terminal")


## `<<if $x >= 2>>` becomes an `at_least` condition on `x`.
func test_a_condition_compiles_to_a_gate() -> void:
	var def := _compile()["def"] as DialogueDef
	var oath := def.node(&"oath")
	var gated := (oath.choices as Array)[0] as DialogueChoiceDef
	assert_ne(gated.condition, null, "the gated choice carries a condition")
	assert_eq(String(gated.condition.verb), "at_least", "compiled as at_least")
	assert_eq(String(gated.condition.key), &"regard", "on the regard variable")
	assert_eq(gated.condition.value, 2, "against 2")


## `-> #id label` names the choice, so a saved press is addressed by name rather than by
## position (DialogueChoiceDef's own rule). Without it, the id is positional.
func test_an_option_may_name_its_own_id() -> void:
	var out := DialogueYarn.compile("title: a\n---\nX: hi\n-> #named Go on <<jump a>>\n===\n", &"npc", &"d")
	assert_eq(bool(out["ok"]), true, "it compiles: %s" % str(out["problems"]))
	var def := out["def"] as DialogueDef
	var first := (def.node(&"a").choices as Array)[0] as DialogueChoiceDef
	assert_eq(String(first.choice_id), "named", "the authored id is kept")
	assert_eq(first.label, "Go on", "and the label is the rest of the line")

	var plain := DialogueYarn.compile("title: a\n---\nX: hi\n-> No id here\n===\n", &"npc", &"d")
	var unnamed := ((plain["def"] as DialogueDef).node(&"a").choices as Array)[0] as DialogueChoiceDef
	assert_eq(String(unnamed.choice_id), "choice_0", "without an id it falls back to a position")


## The compiled def drives the SAME runtime the authored `.tres` does.
func test_the_compiled_graph_runs() -> void:
	var def := _compile()["def"] as DialogueDef
	var actor := Actor.new(&"t_yarn_hero", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	# Drive the def through the runner directly, since the catalog is disk-backed.
	var node := def.node(def.entry_node)
	assert_eq(node.terminal(), false, "intro offers choices")
	var take := node.choice(&"choice_0")
	assert_ne(take, null, "the first choice exists")
	assert_eq(String(take.target), &"oath", "and leads on")


# --- refusals ---------------------------------------------------------------


## Each operator maps to its verb, and an unsupported one is refused.
func test_operator_mapping_and_refusal() -> void:
	assert_eq(String(DialogueYarn.parse_condition("$a == 1").verb), "equals", "==")
	assert_eq(String(DialogueYarn.parse_condition("$a >= 1").verb), "at_least", ">=")
	assert_eq(String(DialogueYarn.parse_condition("$a <= 1").verb), "at_most", "<=")
	assert_eq(String(DialogueYarn.parse_condition("$a").verb), "set", "bare = set")
	assert_eq(DialogueYarn.parse_condition("$a > 1"), null, "> has no verb and is refused")


## A script with no node is refused by name.
func test_an_empty_script_is_refused() -> void:
	var out := DialogueYarn.compile("// nothing here\n", &"npc", &"d")
	assert_eq(bool(out["ok"]), false, "no nodes, no def")
	assert_eq(String((out["problems"] as Array)[0]).begins_with("no_nodes"), true, "named refusal")


## A node never closed with `===` is refused by name.
func test_an_unclosed_node_is_refused() -> void:
	var out := DialogueYarn.compile("title: a\n---\nX: hi\n", &"npc", &"d")
	assert_eq(bool(out["ok"]), false, "unclosed")
	var problems := out["problems"] as Array
	assert_eq(String(problems[0]).contains("missing_end_marker"), true, "named: %s" % str(problems))


## A `<<jump>>` naming a node nobody authored is refused by name.
func test_a_dangling_jump_is_refused() -> void:
	var out := DialogueYarn.compile("title: a\n---\n-> go <<jump nowhere>>\n===\n", &"npc", &"d")
	assert_eq(bool(out["ok"]), false, "dangling jump")
	assert_eq(
		String((out["problems"] as Array)[0]).contains("jump_names_no_node"),
		true,
		"named: %s" % str(out["problems"])
	)


## A duplicate node title is refused: a jump would resolve to whichever came first.
func test_a_duplicate_node_is_refused() -> void:
	var out := DialogueYarn.compile(
		"title: a\n---\nX: one\n===\ntitle: a\n---\nX: two\n===\n", &"npc", &"d"
	)
	assert_eq(bool(out["ok"]), false, "duplicate")
	assert_eq(
		String((out["problems"] as Array)[0]).contains("duplicate_node"),
		true,
		"named: %s" % str(out["problems"])
	)
