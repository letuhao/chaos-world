class_name DialogueChoiceDef
extends Resource

## ONE authored choice on a node (ADR 0862): a label the player sees, a node it goes
## to, an optional requirement and an optional write.
##
## ## The four halves, and which of them is load-bearing
##
## `label` and `target` are the choice. `condition` is what makes a conversation
## branch rather than fork, and `effect` is what makes it remember. A choice authoring
## neither is an ordinary line of dialogue — which is the common case and is legal,
## because a graph whose every choice carried a gate is not dialogue, it is a puzzle
## wearing a conversation's clothes.
##
## ## A locked choice is PUBLISHED, never dropped
##
## `locked` and `refusal` reach the read model, so a panel can render "not yet" against
## a real sentence. Hiding the row instead would make "she will not tell you that yet"
## and "she never offers it" the same silence — the distinction is the whole reason a
## condition has a NAME (see [DialogueCondition]).

## The stable id a caller presses. NOT an array index: `choose` is addressed by id so a
## node whose choices are reordered does not silently redirect every saved press.
@export var choice_id: StringName = &""

## What the player sees. Authored prose, never a generated summary — the player reads
## this, so it is content and not a projection.
@export var label: String = ""

## The node this choice goes to. An EMPTY id ends the conversation, which is a real
## terminal state rather than a missing target.
@export var target: StringName = &""

## Optional. One requirement; unmet refuses the choice BY NAME and writes nothing.
@export var condition: DialogueCondition = null

## Optional. One variable write, applied when the choice is taken and BEFORE the target
## node is published — so a node's own condition reads what the choice that reached it
## wrote, which is what makes a variable readable across nodes at all.
@export var effect_key: StringName = &""
## The value written by [member effect_key]. Typed by [DialogueVariables] from the
## GDScript value the `.tres` carries.
@export var effect_value: Variant = null


func valid() -> bool:
	return choice_id != &"" and not label.is_empty()


func authors_effect() -> bool:
	return effect_key != &""


func authors_condition() -> bool:
	return condition != null and condition.valid()


## The effect as a one-row array of `{key, value}`, so the store's write verb takes a
## patch rather than this class inventing a second write path.
func effect_rows() -> Array:
	if not authors_effect():
		return [] as Array
	return [{"key": effect_key, "value": effect_value}]


func to_dict() -> Dictionary:
	return {
		"choice_id": String(choice_id),
		"label": label,
		"target": String(target),
		"condition": "" if condition == null else String(condition.verb),
		"effect_key": String(effect_key),
	}
