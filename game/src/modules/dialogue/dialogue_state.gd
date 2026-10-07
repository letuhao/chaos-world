class_name DialogueState
extends RefCounted

## Where a conversation IS, and the variables it has written (ADR 0862).
##
## ## One row, and it is not the graph
##
## The authored graph is [DialogueDef]'s. This class persists only the two things a
## save must carry: WHICH conversation an actor is inside and WHICH node of it they
## stand on, plus the typed variable store [DialogueVariables] owns. Nothing here
## duplicates a node's lines or choices — a save that carried the graph would go
## stale the moment content was re-authored, which is the ADR 0066 second-copy
## failure with a Resource instead of a dictionary.
##
## ## The variables live INSIDE this row, under `STATE_KEY`
##
## [DialogueVariables.from_dict] reads `data.get("variables", {})`, so the store
## round-trips through `module_data[DialogueState.MODULE_KEY]` with no second
## top-level key and no bespoke save path — `Actor.to_dict` carries it because it
## carries `module_data`.
##
## ## An unknown `dialog_id` is DROPPED, never kept
##
## A save written against content that no longer ships would otherwise resume into a
## conversation the catalog cannot resolve, and the runner would answer `unknown_node`
## forever with no way to leave. [method normalize] takes the catalog's known ids and
## clears a conversation the current tree does not define, which is the same rule
## `QuestState.normalize` applies to a retired quest id.

## The `actor.module_data` key the versioned row persists under (ADR 0027).
const MODULE_KEY := &"dialogue_state"
## The nested key the variable store lives under, matching `DialogueVariables.STATE_KEY`.
const STATE_KEY := DialogueVariables.STATE_KEY
const SCHEMA_VERSION := 1

## No conversation is open. A real state, not an error: most of the time nobody is
## talking.
const NOBODY := &""


static func empty() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"dialog_id": "",
		"node_id": "",
		STATE_KEY: {},
	}


## Whether a conversation is open.
static func is_talking(row: Dictionary) -> bool:
	return String(row.get("dialog_id", "")) != ""


## The conversation an actor is inside, or `&""`.
static func dialog_id(row: Dictionary) -> StringName:
	return StringName(row.get("dialog_id", ""))


## The node the actor stands on, or `&""`.
static func node_id(row: Dictionary) -> StringName:
	return StringName(row.get("node_id", ""))


## Open `dialog_id` at `node_id`. Writes nothing else; the caller owns the transition.
static func open(row: Dictionary, dialog_id_value: StringName, node_id_value: StringName) -> void:
	row["dialog_id"] = String(dialog_id_value)
	row["node_id"] = String(node_id_value)


## Move to `node_id_value` within the open conversation. An empty id CLOSES the row —
## reaching a node with no choices ends the conversation, which is a real terminal
## state rather than a dangling pointer.
static func move_to(row: Dictionary, node_id_value: StringName) -> void:
	if node_id_value == NOBODY:
		row["node_id"] = ""
		row["dialog_id"] = ""
		return
	row["node_id"] = String(node_id_value)


## Close the conversation, keeping the variable store.
static func close(row: Dictionary) -> void:
	row["dialog_id"] = ""
	row["node_id"] = ""


## The variable store this row carries, as a live [DialogueVariables].
static func variables(row: Dictionary) -> DialogueVariables:
	return DialogueVariables.from_dict({STATE_KEY: row.get(STATE_KEY, {})})


## Write the store back into the row. The store owns its own shape, so this copies
## `to_dict()` rather than reaching into it.
static func set_variables(row: Dictionary, store: DialogueVariables) -> void:
	row[STATE_KEY] = {} if store == null else store.to_dict()


## Normalize a raw `module_data` payload into a valid row.
##
## `known` is the catalog's `{id: true}`. A `dialog_id` the tree no longer defines is
## cleared, and a `node_id` with no conversation is meaningless, so both either survive
## together or are dropped together. A malformed nested store is dropped rather than
## read as a partial dict — a half-read variable store is a door that opens or refuses
## at random.
static func normalize(raw, known: Dictionary = {}) -> Dictionary:
	var row := empty()
	if not (raw is Dictionary):
		return row
	var source := raw as Dictionary
	var dialog := String(source.get("dialog_id", ""))
	var node := String(source.get("node_id", ""))
	if dialog != "" and (known.is_empty() or known.has(dialog)):
		row["dialog_id"] = dialog
		row["node_id"] = node
	var store: Variant = source.get(STATE_KEY, {})
	if store is Dictionary:
		row[STATE_KEY] = (store as Dictionary).duplicate(true)
	return row
