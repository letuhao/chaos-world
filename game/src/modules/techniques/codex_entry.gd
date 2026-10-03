class_name CodexEntry
extends RefCounted

## The permanent record of one learned technique (ADR 0053).
##
## This is the second of three states with three owners of truth. An `ItemDef`
## delivers a technique and is consumed; a `CodexEntry` says the actor knows it
## forever; a `TechniqueSlots` binding says whether it is equipped right now.
## Collapsing them would make a single mis-click unequip a real investment and a
## slot limit silently delete something the player paid for.
##
## **Nothing deletes an entry.** Unequipping and slot overflow return the entry to
## the codex, which is the only place it lives; the codex is unbounded. The
## equipped set is 7-10 entries against an unbounded known set, and that gap is
## the whole design space.
##
## An entry stores realized (rolled) data only when learning realized any. Passives
## carry authored `passive_options` on the def, so their entry is id plus rung.

## The def id. The only identity persisted: a save stores a `StringName` id and
## rehydrates, never the authored definition (ADR 0056), so a designer retuning a
## technique cannot silently rewrite every existing save.
var technique_id: StringName = &""

## Realized effects, stored exactly as they were realized and never rerolled. Empty
## for a technique that realized nothing.
var realized: Array[Dictionary] = []

## Mastery rung, 0 at rung 0. Accumulated through use and persisted alongside the
## id, because an id alone cannot express it.
var mastery_rung: int = 0


func _init(
	p_technique_id: StringName = &"", p_realized: Array[Dictionary] = [], p_rung: int = 0
) -> void:
	technique_id = p_technique_id
	for effect in p_realized:
		realized.append(effect.duplicate(true))
	mastery_rung = p_rung


## Every effect this technique contributes, realized data first and authored
## `passive_options` after. Realized data wins on a duplicate option id: it is the
## same option at the rolled value, so keeping both would double it.
func effects_for(def: TechniqueDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var claimed := {}
	for effect in realized:
		var key := String(effect.get("option_id", ""))
		if key.is_empty() or claimed.has(key):
			continue
		claimed[key] = true
		out.append(effect)
	if def == null:
		return out
	for effect in def.effects():
		if claimed.has(String(effect.get("option_id", ""))):
			continue
		out.append(effect)
	return out


## Raise this entry's rung to `rung`. Returns true only when the rung actually
## moved, so a caller never pays for a study that taught nothing.
func raise_to(rung: int) -> bool:
	var target := maxi(0, rung)
	if target <= mastery_rung:
		return false
	mastery_rung = target
	return true


func to_dict() -> Dictionary:
	return {"id": String(technique_id), "rung": mastery_rung, "realized": realized.duplicate(true)}


static func from_dict(data: Dictionary) -> CodexEntry:
	var realized: Array[Dictionary] = []
	for effect in data.get("realized", []):
		if effect is Dictionary:
			realized.append((effect as Dictionary).duplicate(true))
	return CodexEntry.new(StringName(data.get("id", "")), realized, int(data.get("rung", 0)))
