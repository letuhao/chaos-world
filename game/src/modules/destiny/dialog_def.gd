class_name DialogDef
extends Resource

## One authored dialog line — the BASE text an NPC says before fate modifiers
## are applied (ADR 0398).
##
## Dialog content is data, never code. A dialog line is identified by
## `dialog_id` and belongs to an NPC (`npc_id`). The base text is what the
## NPC says when the player holds no fates that modify this dialog.
##
## Fate-held modifiers are NOT authored here. They live on
## `FateDef.dialog_modifiers`, which maps a dialog_id to a text override.
## The `DialogGenerator` assembles the final text from the base + modifiers.

@export var id: StringName = &""
@export var npc_id: StringName = &""
@export var base_text: String = ""


func is_valid() -> bool:
	return id != &"" and npc_id != &"" and not base_text.is_empty()


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"npc_id": String(npc_id),
		"base_text": base_text,
	}
