class_name DialogueRunner
extends RefCounted

## The dialogue state machine: open a conversation, publish the current node, take a
## choice, end (ADR 0862).
##
## ## Stateless, and that is the whole design
##
## Every verb is a `static func` over `(actor, ...)`. The state lives in
## `actor.module_data[DialogueState.MODULE_KEY]`, so a save carries it with no bespoke
## path and a conversation resumes across a load without this class holding anything.
## Two runners cannot disagree about where a conversation is, because there is nothing
## for a second one to hold.
##
## ## The four halves of a node, and which the panel owns
##
## A node publishes `speaker`, `lines` and `choices`. Each choice carries its own
## `locked` and `refusal`, because a gate that could not be met and a gate that was
## never evaluated must not read the same to a player — "she will not tell you that
## yet" is a different sentence from "she never offers it" ([DialogueCondition]).
##
## ## A choice writes BEFORE it moves
##
## [method choose] applies the choice's effect to the variable store and only then
## moves to the target, so a node's own condition reads what the choice that reached it
## wrote. Reversing the two would make a variable unreadable across nodes, which is the
## whole reason a conversation can remember anything.
##
## ## No clock, no `_process`, no `get_tree()`
##
## A conversation advances only when [method start] or [method choose] is called, which
## is the same pull-based rule the `event` and `quest` modules keep (ADR 0085,
## DEF-0111). Nothing here ages on its own.

## The reason a verb returns when the actor carries no dialogue module.
const R_NO_ACTOR := "no_actor"
## The named conversation does not exist in the authored catalog.
const R_UNKNOWN_DIALOG := "unknown_dialog"
## The node an operation addressed is not one the conversation authors.
const R_UNKNOWN_NODE := "unknown_node"
## No conversation is open, so there is nothing to advance or render.
const R_NOT_TALKING := "not_talking"
## The choice id is not one the current node offers.
const R_UNKNOWN_CHOICE := "unknown_choice"


## Open the conversation `npc_id` authors, at its entry node.
##
## Refuses `unknown_dialog` when the npc has no conversation or the def is unplayable,
## and `unknown_node` when the entry names a node the def does not author (the catalog
## reports the same as a problem). Re-opening while already talking to the SAME npc
## restarts at the entry node; talking to a DIFFERENT npc replaces the conversation and
## keeps the variable store, because the store is the actor's memory of everyone.
static func start(actor: Actor, npc_id: StringName) -> Dictionary:
	if actor == null:
		return _refuse(R_NO_ACTOR)
	var def := DialogueCatalog.instance().for_npc(npc_id)
	if def == null or not def.valid():
		return _refuse(R_UNKNOWN_DIALOG, {"npc_id": String(npc_id)})
	if not def.has_node(def.entry_node):
		return _refuse(R_UNKNOWN_NODE, {"node_id": String(def.entry_node)})
	var row := _row(actor)
	DialogueState.open(row, def.dialog_id, def.entry_node)
	_persist(actor, row)
	return _ok(row, {"dialog_id": String(def.dialog_id), "node_id": String(def.entry_node)})


## The current node as primitives, or a `not_talking` refusal.
##
## Each choice is published with its `locked` flag and `refusal` sentence, so a panel
## renders "two of four open" rather than silently short-listing the conversation.
static func current(actor: Actor) -> Dictionary:
	if actor == null:
		return _refuse(R_NO_ACTOR)
	var row := _row(actor)
	if not DialogueState.is_talking(row):
		return _refuse(R_NOT_TALKING)
	var def := DialogueCatalog.instance().definition(DialogueState.dialog_id(row))
	if def == null:
		return _refuse(R_UNKNOWN_DIALOG, {"dialog_id": String(DialogueState.dialog_id(row))})
	var node := def.node(DialogueState.node_id(row))
	if node == null:
		return _refuse(R_UNKNOWN_NODE, {"node_id": String(DialogueState.node_id(row))})
	var store := DialogueState.variables(row)
	return _ok(
		row,
		{
			"dialog_id": String(def.dialog_id),
			"node_id": String(node.node_id),
			"speaker": String(node.speaker),
			"lines": _lines(node),
			"terminal": node.terminal(),
			"choices": _choices(node, store, actor),
		}
	)


## Take `choice_id` on the current node: apply its effect, then move to its target.
##
## Refuses `unknown_choice` when the node does not offer it, and refuses a LOCKED
## choice by its own condition's name (the same refusal `current` published), writing
## nothing — a locked door must not open because a caller skipped the filter.
static func choose(actor: Actor, choice_id: StringName) -> Dictionary:
	if actor == null:
		return _refuse(R_NO_ACTOR)
	var row := _row(actor)
	if not DialogueState.is_talking(row):
		return _refuse(R_NOT_TALKING)
	var def := DialogueCatalog.instance().definition(DialogueState.dialog_id(row))
	if def == null:
		return _refuse(R_UNKNOWN_DIALOG, {"dialog_id": String(DialogueState.dialog_id(row))})
	var node := def.node(DialogueState.node_id(row))
	if node == null:
		return _refuse(R_UNKNOWN_NODE, {"node_id": String(DialogueState.node_id(row))})
	var choice := node.choice(choice_id)
	if choice == null:
		return _refuse(R_UNKNOWN_CHOICE, {"choice_id": String(choice_id)})
	var store := DialogueState.variables(row)
	if choice.authors_condition():
		var verdict := choice.condition.evaluate(store, actor)
		if not bool(verdict["ok"]):
			return _refuse(String(verdict["refusal"]), {"choice_id": String(choice_id)})

	# The effect is applied BEFORE the move, so the target node's own condition reads
	# what this choice wrote.
	var wrote := _apply_effect(store, choice)
	DialogueState.set_variables(row, store)

	if choice.target == &"":
		DialogueState.close(row)
		_persist(actor, row)
		return _ok(
			row,
			{
				"dialog_id": String(def.dialog_id),
				"node_id": "",
				"ended": true,
				"written": wrote,
			}
		)
	var target := def.node(choice.target)
	if target == null:
		# A choice naming a node nobody authored is a content defect. Refuse and STAY,
		# rather than closing the conversation on a dead end the author never wrote.
		_persist(actor, row)
		return _refuse(R_UNKNOWN_NODE, {"node_id": String(choice.target)})
	DialogueState.move_to(row, choice.target)
	_persist(actor, row)
	return _ok(
		row,
		{
			"dialog_id": String(def.dialog_id),
			"node_id": String(choice.target),
			"ended": false,
			"written": wrote,
		}
	)


## Close whatever conversation is open, keeping the variable store. Idempotent: closing
## when nobody is talking is a successful no-op, not a refusal.
static func stop(actor: Actor) -> Dictionary:
	if actor == null:
		return _refuse(R_NO_ACTOR)
	var row := _row(actor)
	var was := String(row.get("dialog_id", ""))
	DialogueState.close(row)
	_persist(actor, row)
	return _ok(row, {"closed": was})


## The whole state as primitives: the variables and whether a conversation is open.
static func summary(actor: Actor) -> Dictionary:
	var row := empty_row(actor)
	return {
		"has_actor": actor != null,
		"actor_id": "" if actor == null else String(actor.id),
		"talking": DialogueState.is_talking(row),
		"dialog_id": String(row.get("dialog_id", "")),
		"node_id": String(row.get("node_id", "")),
		"variables": (row.get(DialogueState.STATE_KEY, {}) as Dictionary).duplicate(true),
	}


## The variable store of `actor`, for a caller that wants to read one value. A live
## [DialogueVariables]; write it back through [method write_variable] so the row is
## persisted, rather than mutating a detached copy.
static func variables(actor: Actor) -> DialogueVariables:
	return DialogueState.variables(empty_row(actor))


## Write one variable into the actor's store, persisting the row. The verb a scripted
## caller (a [code]command[/code] in a Yarn node, a quest effect) uses to set
## conversational state without going through a choice.
static func write_variable(actor: Actor, key: StringName, value: Variant) -> Dictionary:
	if actor == null:
		return _refuse(R_NO_ACTOR)
	var row := _row(actor)
	var store := DialogueState.variables(row)
	var wrote := store.set_value(key, value)
	if bool(wrote["ok"]):
		DialogueState.set_variables(row, store)
		_persist(actor, row)
	return wrote


# --- internals ---------------------------------------------------------------


static func empty_row(actor: Actor) -> Dictionary:
	if actor == null:
		return DialogueState.empty()
	return DialogueState.normalize(actor.get_module_data(DialogueState.MODULE_KEY), _known())


static func _row(actor: Actor) -> Dictionary:
	return empty_row(actor)


static func _known() -> Dictionary:
	var out: Dictionary = {}
	for dialog_id in DialogueCatalog.instance().dialog_ids():
		out[String(dialog_id)] = true
	return out


static func _persist(actor: Actor, row: Dictionary) -> void:
	actor.set_module_data(
		DialogueState.MODULE_KEY, DialogueState.normalize(row, _known())
	)


## A node's lines, copied so a caller cannot mutate the authored Resource through the
## payload.
static func _lines(node: DialogueNodeDef) -> Array[String]:
	var out: Array[String] = []
	for line in node.lines:
		out.append(String(line))
	return out


## A node's choices, each with its `locked` flag and `refusal`. Published rather than
## filtered, so a screen can render a locked option and say why.
static func _choices(
	node: DialogueNodeDef, store: DialogueVariables, actor: Actor
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for choice in node.choices:
		if choice == null:
			continue
		var locked := false
		var refusal := ""
		if choice.authors_condition():
			var verdict := choice.condition.evaluate(store, actor)
			locked = not bool(verdict["ok"])
			if locked:
				refusal = String(verdict["refusal"])
		(
			out
			. append(
				{
					"choice_id": String(choice.choice_id),
					"label": choice.label,
					"locked": locked,
					"refusal": refusal,
					"terminal": choice.target == &"",
				}
			)
		)
	return out


## Apply one choice's effect to the store. Returns a one-row report so the caller can
## see what was written (`[]` when the choice authors no effect).
static func _apply_effect(store: DialogueVariables, choice: DialogueChoiceDef) -> Array:
	var out: Array = []
	for row in choice.effect_rows():
		var key := StringName((row as Dictionary).get("key", ""))
		var value: Variant = (row as Dictionary).get("value", null)
		var wrote := store.set_value(key, value)
		out.append({"key": String(key), "ok": bool(wrote["ok"]), "refusal": String(wrote["refusal"])})
	return out


static func _ok(row: Dictionary, detail: Dictionary = {}) -> Dictionary:
	var out := {"ok": true, "reason": "", "talking": DialogueState.is_talking(row)}
	for key in detail.keys():
		out[String(key)] = detail[key]
	return out


static func _refuse(reason: String, detail: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "reason": reason}
	for key in detail.keys():
		out[String(key)] = detail[key]
	return out
