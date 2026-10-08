class_name DialogueDef
extends Resource

## ONE authored conversation: a set of nodes and the node the player enters it at
## (ADR 0862).
##
## ## A conversation is keyed by the NPC it belongs to, not by a name
##
## `npc_id` is the authored identity, so `start` is `(actor, npc_id)` and a settlement
## asks "what can this person say" rather than "which of the forty `.tres` files was
## the author thinking of". `NpcApi.summary` answers who that person is; this class
## never names an `NpcDef` and therefore declares no dependency on `npc/` — the seam
## that DOES reach it is an injected `Callable` (see `DialogueApi.set_npc_reader`).
##
## ## A node id is unique within ONE def, and a repeat is a content error
##
## Two rows sharing an id would make a choice's target resolve to whichever the lookup
## reached first, so a conversation would branch somewhere its author never wrote. The
## catalog therefore keeps the FIRST row and reports the repeat, and
## `tests/modules/dialogue/test_dialogue_graph.gd` asserts the refusal rather than
## leaving it to an audit.

## The stable id, used by content guards and by `DialogueGenerator`'s `dialog_id`
## vocabulary so one dialog id names one conversation.
@export var dialog_id: StringName = &""

## The npc this conversation belongs to. `start` resolves through it.
@export var npc_id: StringName = &""

## The node the player enters at. MUST name a node this def authors; a def whose entry
## names nothing refuses `unknown_node` rather than starting on its first row, because
## "the first node" is a guess and a guess about where a story OPENS is the one an
## author cannot debug.
@export var entry_node: StringName = &""

## Every node, in AUTHORED order — the order a content audit walks and the order the
## read model publishes the node list in.
@export var nodes: Array[DialogueNodeDef] = []


func valid() -> bool:
	return dialog_id != &"" and npc_id != &"" and entry_node != &"" and not nodes.is_empty()


func node(node_id: StringName) -> DialogueNodeDef:
	for row in nodes:
		if row.node_id == node_id:
			return row
	return null


func has_node(node_id: StringName) -> bool:
	return node(node_id) != null


func node_count() -> int:
	return nodes.size()


## The ids this def authors, SORTED by text.
##
## `StringName` compares by an internal pointer-derived id, so an unsorted list would
## publish a different order on a different machine — the finding `NpcState.npc_ids`
## records for the roster, and this list has the identical property.
func node_ids() -> Array[StringName]:
	var texts: Array[String] = []
	for row in nodes:
		texts.append(String(row.node_id))
	texts.sort()
	var out: Array[StringName] = []
	for text in texts:
		out.append(StringName(text))
	return out


## Every choice target this def authors, as `{node_id: true}`. A content guard compares
## it against [method node_ids] so a target naming a node nobody authored is refused at
## authoring time rather than becoming a dead end a player walks into at runtime.
func declared_targets() -> Dictionary:
	var out: Dictionary = {}
	for row in nodes:
		for choice in row.choices:
			if choice.target != &"":
				out[String(choice.target)] = true
	return out


func to_dict() -> Dictionary:
	return {
		"dialog_id": String(dialog_id),
		"npc_id": String(npc_id),
		"entry_node": String(entry_node),
		"node_count": nodes.size(),
	}
