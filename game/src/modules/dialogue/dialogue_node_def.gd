class_name DialogueNodeDef
extends Resource

## ONE authored beat: who is speaking, what they say, and what the player may answer
## (ADR 0862).
##
## ## LINES ARE ORDERED, AND THE ORDER IS CONTENT
##
## `Array[String]`, not a String. A node is more than one utterance often enough — a
## greeting, a pause, an answer — and joining them into one field would make the author
## choose between a newline convention nobody validates and an array nobody can render
## as a single paragraph. The read model publishes the array as-is so a panel owns the
## joining, exactly as AGENTS.md's "no number formatting in a screen" generalises.
##
## ## SPEAKER IS AN NPC ID, AND IT IS NOT A `StringName` IN THE PAYLOAD
##
## The authored field is a `StringName` because the panel wants one; every payload
## publishes `String(speaker)` so nothing engine-typed reaches a save — the same rule
## `DialogueVariables` states for its keys.

## The stable id `choose` addresses. Unique within one `DialogueDef`.
@export var node_id: StringName = &""

## The npc speaking. An empty id is the PLAYER, which is a real answer and not an
## authoring omission: a node the player speaks is how a conversation states what they
## chose without a mechanic inventing it.
@export var speaker: StringName = &""

## What is said, in order. Empty is legal — a silent beat is a choice-only node.
@export var lines: Array[String] = []

## What the player may answer. Empty means the node is TERMINAL: arriving here ends the
## conversation, so a graph does not need a separate end node type.
@export var choices: Array[DialogueChoiceDef] = []


func valid() -> bool:
	return node_id != &""


func terminal() -> bool:
	return choices.is_empty()


func choice(choice_id: StringName) -> DialogueChoiceDef:
	for row in choices:
		if row.choice_id == choice_id:
			return row
	return null


func has_choice(choice_id: StringName) -> bool:
	return choice(choice_id) != null


## The number of authored choices, INCLUDING locked ones. The read model publishes
## both this and the locked count separately, so a panel can say "two of four open"
## rather than silently rendering a short list that reads as a smaller conversation.
func choice_count() -> int:
	return choices.size()


func to_dict() -> Dictionary:
	return {
		"node_id": String(node_id),
		"speaker": String(speaker),
		"line_count": lines.size(),
		"choice_count": choices.size(),
		"terminal": terminal(),
	}