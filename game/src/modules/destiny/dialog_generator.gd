class_name DialogGenerator
extends RefCounted

## Assembles NPC dialogue from base text + fate-held modifiers (ADR 0398).
##
## The engine is template + modifiers, not NLP. One dialog_id has one base
## text (authored on `DialogDef`); each held fate may override it through
## `FateDef.dialog_modifiers`. If multiple fates modify the same dialog_id,
## the last one in canonical fate-id order wins (deterministic).
##
## The generator READS the fate ledger. It never writes, and a dialog read
## leaves the ledger byte-identical (ADR 0065 earn-only).


## The assembled dialog, as primitives.
## `{dialog_id, npc_id, base_text, final_text, modifiers_applied}`
## `modifiers_applied` is `[{fate_id, dialog_id, override_text}]`.
static func generate(dialog_id: StringName, actor: Actor) -> Dictionary:
	var empty := {
		"dialog_id": String(dialog_id),
		"npc_id": "",
		"base_text": "",
		"final_text": "",
		"modifiers_applied": [],
	}
	if actor == null:
		return empty
	var def := DialogCatalog.instance().definition(dialog_id)
	if def == null:
		return empty
	var base_text := def.base_text
	var final_text := base_text
	var modifiers_applied: Array[Dictionary] = []
	# Iterate held fates in canonical order so the override is deterministic.
	for fate_id in DestinyState.fate_ids(DestinyApi.state(actor)):
		var fate_def := FateCatalog.instance().fate_definition(fate_id)
		if fate_def == null:
			continue
		if not fate_def.dialog_modifiers.has(String(dialog_id)):
			continue
		var override_text := String(fate_def.dialog_modifiers[String(dialog_id)])
		final_text = override_text
		(
			modifiers_applied
			. append(
				{
					"fate_id": String(fate_id),
					"dialog_id": String(dialog_id),
					"override_text": override_text,
				}
			)
		)
	return {
		"dialog_id": String(dialog_id),
		"npc_id": String(def.npc_id),
		"base_text": base_text,
		"final_text": final_text,
		"modifiers_applied": modifiers_applied,
	}
