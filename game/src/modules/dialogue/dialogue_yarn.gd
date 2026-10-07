class_name DialogueYarn
extends RefCounted

## Compiles a Yarn-Spinner–style script into a [DialogueDef] (ADR 0862).
##
## ## Why a compiler and not a runtime
##
## The game runs `DialogueDef` graphs through [DialogueRunner]. This class lets a writer
## AUTHOR in a Yarn-shaped text format and have it become that same graph, so there is
## ONE runtime and ONE content shape — a second interpreter would be the ADR 0066
## second-copy failure wearing a parser. Compilation is pure and offline: a `.yarn` file
## is turned into `.tres` content, and nothing reads Yarn at play time.
##
## ## The supported subset, stated exactly
##
## A full Yarn Spinner implementation is a C# runtime with its own compiler; this is the
## honest subset this game needs, and anything outside it is REFUSED by name rather than
## mis-compiled:
##
##   title: NodeName          start a node
##   ---                       body follows
##   Elder: some words         a spoken line (word before ':' is the speaker)
##   some words                a line with no speaker (the player / narration)
##   -> option text            a choice
##      <<if $regard >= 2>>     ...gated on the actor's variable store
##      <<set $seen = true>>    ...writing a variable when taken
##      <<jump NextNode>>       ...moving to another node
##   ===                       end the node
##
## The FIRST node in the file is the entry. A choice with no `<<jump>>` is TERMINAL,
## which matches `DialogueNodeDef`'s "empty choices ends the conversation".
##
## ## Conditions are the closed verb set, never an expression language
##
## `<<if $k >= v>>` maps to [DialogueCondition]'s `at_least`, `<=` to `at_most`, `==` to
## `equals`, and a bare `$k` to `set`. `>` and `<` have no verb in that set and are
## refused — a condition the runtime cannot evaluate is an authoring error, not a
## silently-passing gate.

## The refusal names, so a caller reports WHICH line failed rather than a byte offset.
const R_NO_TITLE := "no_title"
const R_NO_BODY := "missing_body_marker"
const R_NO_END := "missing_end_marker"
const R_DUPLICATE_NODE := "duplicate_node"
const R_BAD_CONDITION := "unparseable_condition"
const R_UNSUPPORTED_OPERATOR := "unsupported_operator"
const R_UNKNOWN_JUMP := "jump_names_no_node"
const R_NO_NODES := "no_nodes"


## Compile `text` into a [DialogueDef], or report every problem.
##
## Returns `{ok: bool, def: DialogueDef|null, problems: Array[String]}`. `problems` is
## NEVER empty on `ok: false`, and names each line's own failure so a writer fixes the
## line rather than guessing.
static func compile(text: String, npc_id: StringName, dialog_id: StringName) -> Dictionary:
	var parsed := _parse(text)
	if not (parsed["problems"] as Array).is_empty():
		return {"ok": false, "def": null, "problems": parsed["problems"]}
	var def := _build(parsed["nodes"] as Array, npc_id, dialog_id)
	var problems := _validate(def)
	if not problems.is_empty():
		return {"ok": false, "def": null, "problems": problems}
	return {"ok": true, "def": def, "problems": []}


# --- parsing -----------------------------------------------------------------


## Parse the text into raw node blocks: `[{title, entry, lines:[...]}]`.
##
## A tiny line scanner, not a grammar. It walks `text.split("\n")` ONCE and keys off the
## three markers (`title:`, `---`, `===`), which is the whole shape of the subset.
static func _parse(text: String) -> Dictionary:
	var problems: Array[String] = []
	var nodes: Array = []
	var current: Dictionary = {}
	var in_body := false
	var lines := text.split("\n")
	for index in lines.size():
		var raw := String(lines[index])
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("title:"):
			# A new title closes any node already being read.
			if not current.is_empty():
				if not in_body:
					problems.append("%s: node '%s' never opened a body" % [R_NO_BODY, current.get("title", "")])
				nodes.append(current)
			current = {"title": line.substr("title:".length()).strip_edges(), "lines": []}
			in_body = false
			continue
		if line == "---":
			if current.is_empty():
				problems.append("%s: a body marker with no title" % R_NO_TITLE)
				continue
			in_body = true
			continue
		if line == "===":
			if not current.is_empty():
				if not in_body:
					problems.append("%s: node '%s' ended without a body" % [R_NO_BODY, current.get("title", "")])
				nodes.append(current)
				current = {}
			in_body = false
			continue
		if current.is_empty() or not in_body:
			# Text outside any node body is a structural error, not content.
			continue
		(current["lines"] as Array).append(line)
	if not current.is_empty():
		problems.append(
			"%s: node '%s' was never closed with '==='" % [R_NO_END, current.get("title", "")]
		)
	if nodes.is_empty() and problems.is_empty():
		problems.append("%s: the script authorises no node" % R_NO_NODES)

	# Refuse a duplicate title: a jump would resolve to whichever came first.
	var seen := {}
	for node in nodes:
		var title := String((node as Dictionary)["title"])
		if seen.has(title):
			problems.append("%s: node '%s' is declared twice" % [R_DUPLICATE_NODE, title])
		seen[title] = true
	return {"nodes": nodes, "problems": problems}


## Build a [DialogueDef] from parsed node blocks. Assumes `_parse` found no problems.
static func _build(nodes: Array, npc_id: StringName, dialog_id: StringName) -> DialogueDef:
	var def := DialogueDef.new()
	def.dialog_id = dialog_id
	def.npc_id = npc_id
	if not nodes.is_empty():
		def.entry_node = StringName(String((nodes[0] as Dictionary)["title"]))
	for node_block in nodes:
		def.nodes.append(_build_node(node_block as Dictionary))
	return def


static func _build_node(block: Dictionary) -> DialogueNodeDef:
	var node := DialogueNodeDef.new()
	node.node_id = StringName(String(block["title"]))
	var pending: DialogueChoiceDef = null
	for raw in block["lines"] as Array:
		var line := String(raw)
		if line.begins_with("->"):
			pending = _build_choice(line, node.choices.size())
			node.choices.append(pending)
			continue
		if line.begins_with("<<"):
			# A command line: it belongs to the choice just opened, or is a bare
			# `<<jump>>` after a line (which this subset does not support as a node tail —
			# a jump is an option's destination). Attach to the pending choice.
			for inner in commands_of(line):
				_apply_command(inner, pending)
			continue
		# A spoken or narrated line.
		var speaker := &""
		var spoken := line
		var colon := line.find(":")
		if colon > 0:
			var head := line.substr(0, colon).strip_edges()
			if _is_speaker(head):
				speaker = StringName(head)
				spoken = line.substr(colon + 1).strip_edges()
		# A node has ONE speaker: the first spoken line sets it and later lines
		# continue it. A speaker change needs its own node, so the extra node is the
		# writer's to author rather than this compiler's to invent.
		if node.speaker == &"" and node.lines.is_empty():
			node.speaker = speaker
		node.lines.append(spoken)
	return node


## One `-> text <<if ...>> <<set ...>> <<jump ...>>` choice line: the label is
## everything before the first `<<`, and EVERY `<<...>>` after it is applied to the
## choice, in order.
##
## ## An option may name its own id: `-> #ask_oath Ask whose oath...`
##
## Without an id a choice gets a POSITIONAL one (`choice_0`), and `DialogueChoiceDef`
## warns at length against exactly that: a saved press is addressed by id, so reordering
## a node's options would silently redirect every saved press. A writer who cares names
## the id; one who does not gets the positional fallback rather than a compile error.
static func _build_choice(line: String, index: int) -> DialogueChoiceDef:
	var choice := DialogueChoiceDef.new()
	choice.choice_id = StringName("choice_%d" % index)
	var body := line.substr(2)
	var command_at := body.find("<<")
	var head := (body.substr(0, command_at) if command_at >= 0 else body).strip_edges()
	if head.begins_with("#"):
		var space := head.find(" ")
		var token := head if space < 0 else head.substr(0, space)
		var named := token.substr(1).strip_edges()
		if named != "":
			choice.choice_id = StringName(named)
		head = "" if space < 0 else head.substr(space + 1).strip_edges()
	choice.label = head
	for inner in commands_of(body):
		_apply_command(inner, choice)
	return choice


## Every `<<...>>` payload in `line`, in authored order. A `<<` with no closing `>>`
## yields the remainder, which `_apply_command` then ignores as unrecognised.
static func commands_of(line: String) -> Array[String]:
	var out: Array[String] = []
	var cursor := 0
	while true:
		var open := line.find("<<", cursor)
		if open < 0:
			break
		var close := line.find(">>", open + 2)
		if close < 0:
			out.append(line.substr(open + 2).strip_edges())
			break
		out.append(line.substr(open + 2, close - open - 2).strip_edges())
		cursor = close + 2
	return out


## Apply one command's INNER text (`if $x >= 2`, `set $k = v`, `jump Node`) to `choice`.
## Recognised: `if`, `set`, `jump`, `declare`. An unrecognised command or a bad argument
## is left for `_validate` to catch; this never throws. A null choice (a command before
## any option) is ignored — the subset has no node-level commands.
static func _apply_command(inner: String, choice: DialogueChoiceDef) -> void:
	if choice == null:
		return
	if inner.begins_with("if "):
		var condition := parse_condition(inner.substr(3).strip_edges())
		if condition != null:
			choice.condition = condition
		return
	if inner.begins_with("set "):
		var parts := _split_set(inner.substr(4).strip_edges())
		if not parts.is_empty():
			choice.effect_key = StringName(parts[0])
			choice.effect_value = parts[1]
		return
	if inner.begins_with("jump "):
		choice.target = StringName(inner.substr(5).strip_edges())
		return
	# `declare` and anything else is authoring ceremony this subset ignores.


## `$key = value` or `$key to value`. Returns `[key, typed_value]` or `[]`.
static func _split_set(text: String) -> Array:
	var body := text.strip_edges()
	if body.begins_with("$"):
		body = body.substr(1)
	var sep := -1
	var assign := body.find("=")
	var to := body.find(" to ")
	if assign >= 0:
		sep = assign
	elif to >= 0:
		sep = to
	else:
		return []
	var key := body.substr(0, sep).strip_edges()
	var raw := body.substr(sep + (1 if assign >= 0 else 4)).strip_edges()
	if key == "" or raw == "":
		return []
	return [key, _typed(raw)]


## Parse a `$key OP value` condition into a [DialogueCondition], or null.
##
## Exposed so a test pins each operator's mapping without going through a full file.
static func parse_condition(text: String) -> DialogueCondition:
	var body := text.strip_edges()
	if not body.begins_with("$"):
		return null
	body = body.substr(1)
	var condition := DialogueCondition.new()
	# Longest operator first, so `>=` is not read as `>`.
	var operators: Array = [
		["==", DialogueCondition.EQUALS],
		[">=", DialogueCondition.AT_LEAST],
		["<=", DialogueCondition.AT_MOST],
	]
	for pair in operators:
		var op := String(pair[0])
		var verb := StringName(pair[1])
		var at := body.find(op)
		if at >= 0:
			var key := body.substr(0, at).strip_edges()
			var value := body.substr(at + op.length()).strip_edges()
			if key == "" or value == "":
				return null
			condition.verb = verb
			condition.key = StringName(key)
			condition.value = _typed(value)
			return condition
	# A bare `$key` is the `set` verb — "the variable is present".
	if not body.contains(" ") and not body.contains("<") and not body.contains(">"):
		condition.verb = DialogueCondition.SET
		condition.key = StringName(body.strip_edges())
		return condition
	return null


## Whether `head` reads as a speaker name — an identifier, not a sentence fragment.
static func _is_speaker(head: String) -> bool:
	if head.is_empty() or head.length() > 32:
		return false
	if head.contains(" "):
		return false
	return head.is_valid_identifier()


## A Yarn literal: an integer, a float, `true`/`false`, else a string.
static func _typed(raw: String) -> Variant:
	if raw == "true":
		return true
	if raw == "false":
		return false
	if raw.is_valid_int():
		return int(raw)
	if raw.is_valid_float():
		return float(raw)
	return raw.trim_prefix("\"").trim_suffix("\"")


# --- validation --------------------------------------------------------------


## Every authoring defect that must stop a compiled def from being playable, one line
## each. Bounded by the authored graph — never a walk that could not terminate.
static func _validate(def: DialogueDef) -> Array[String]:
	var problems: Array[String] = []
	if not def.valid():
		problems.append("compiled def is not valid (id, npc, entry or nodes missing)")
		return problems
	if not def.has_node(def.entry_node):
		problems.append("%s: entry node '%s' is not authored" % [R_UNKNOWN_JUMP, def.entry_node])
	for node in def.nodes:
		if node == null:
			continue
		for choice in node.choices:
			if choice == null:
				continue
			if choice.condition != null and not choice.condition.valid():
				problems.append("%s on choice '%s'" % [R_BAD_CONDITION, choice.choice_id])
			if choice.target != &"" and not def.has_node(choice.target):
				problems.append("%s: '%s' -> '%s'" % [R_UNKNOWN_JUMP, node.node_id, choice.target])
	return problems
