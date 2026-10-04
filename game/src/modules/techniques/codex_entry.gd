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
##
## ## A passive's values scale with its rung, and only its values
##
## ADR 0140 decides this. `power` (`POWER_STEP = 1.15`, compounding) is the one
## multiplier of the three that means "this technique is stronger", so it is the
## one that reaches a passive — a rung-4 `cult_bone_density` of 4.0 contributes
## 6.996, not 4.0, and that is the whole of what mastery does to a passive.
##
## The other two are REFUSED for a passive, and it is worth naming why, because
## both look available:
##
## - `qi_cost` (`0.94^n`) and `cooldown` (`0.96^n`) discount what an ACTIVATION
##   pays. A passive has no cost block at all: `TechniqueCasting.activate` refuses
##   it with `not_active`, and `test_a_passive_has_no_cost_block_and_an_active_has_one`
##   pins `qi_cost == stamina_cost == cooldown == 0.0` on every shipped passive. So
##   there is nothing to discount, and a "discount" column applied to a zero is a
##   number that reads as a benefit and pays nothing.
##
## ## Why the stat channel scales and the resource-capacity channel does not
##
## A stat-channel option (`cult_bone_density`, `cult_mental_defense`, ...) is a
## body change that composes with everything else on the actor: more of it is
## strictly more, it is bounded by the option's own `bounds` (`clamp_to_bounds`
##   is re-applied through `OptionCatalog.fixed_effect` at authoring time), and
##   two sources never collide because the source tag is `technique:<id>` and a
##   rebuild replaces the whole contribution atomically (ADR 0054). So it scales.
##
## A RESOURCE-CAPACITY option (`core_max_qi`, `core_max_stamina`) resizes a
## `ResourcePool`'s maximum, and `Actor._sync_core_resources` re-derives that
## maximum from the derived stat on every `mark_stats_dirty`. Scaling it would put
## the passive on top of the realm ladder's own capacity growth — `RealmScaling`
##   already MULTs `MAX_QI` and `MAX_STAMINA` by the realm's `power`, which runs
##   1.0x to 551.46x, and `QiTraining.synchronize` re-seals the qi pool from the
##   NEXT realm's authored `dantian_capacity`. A passive that multiplied its own
##   capacity contribution by 1.749 would be a fourth multiplier on a number that
##   already has three, and the one that is least authored. So it does not scale.
##
## The split is legible from the option record alone: `target_type` is `stat` or
## `resource`, so the rule is a data read rather than a curated list, and a
## passive that gains a third option needs no new decision.
func effects_for(def: TechniqueDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# A def that authored fewer than five rungs can never leave a higher rung's
	# power on the actor, so the clamp reads the def's OWN `mastery_rungs` rather
	# than ADR 0055's ceiling. An effect with no def behind it (a realized row
	# whose definition the catalog can no longer resolve) falls back to the ceiling,
	# which is the honest read: the row's provenance is gone and the conservative
	# clamp would be a guess about content nobody can see.
	var rungs := TechniqueScales.MAX_RUNGS if def == null else def.mastery_rungs
	var power := float(
		(
			TechniqueScales
			. multipliers_at(TechniqueScales.rung_for(mastery_rung, rungs), rungs)["power"]
		)
	)
	var claimed := {}
	for effect in realized:
		var key := String(effect.get("option_id", ""))
		if key.is_empty() or claimed.has(key):
			continue
		claimed[key] = true
		out.append(_scaled(effect, power))
	if def == null:
		return out
	for effect in def.effects():
		if claimed.has(String(effect.get("option_id", ""))):
			continue
		out.append(_scaled(effect, power))
	return out


## One effect at this entry's rung. A copy — never the input dictionary — because
## `def.effects()` rebuilds its entries from the catalog on every call, and a rung
## that wrote through to one of them would scale a number twice over a rebuild.
##
## A pool CAPACITY is returned UNSCALED, and the reason is the file header's: it
## resizes a pool maximum that the realm ladder and the authored dantian capacity
## already govern.
func _scaled(effect: Dictionary, power: float) -> Dictionary:
	if power <= 1.0:
		return effect.duplicate(true)
	var out := effect.duplicate(true)
	# Capacity is exempt by its TARGET ID, not by its target type. Every option in
	# `master_option_pool.jsonl` typed `resource` is a one-shot restoration
	# (`scope: current`: restore_health, restore_qi, …), and none of them is a
	# capacity — the capacity options (`core_max_qi`, `core_max_stamina`) are typed
	# `stat` with a `max_*` id. So a `target_type` test never fires and the
	# exemption silently scales `max_qi` by 1.749 at rung 4, which is exactly the
	# double-count ADR 0140 refuses: `RealmScaling` already MULTs `MAX_QI` by the
	# realm's own power (1.0x to 551.46x) and the authored dantian capacity governs
	# the pool on top. Read the id, which is what actually carries the meaning.
	if _is_capacity(out.get("target_id", &"")):
		return out
	out["value"] = float(out.get("value", 0.0)) * power
	return out


## Whether an effect resizes a pool MAXIMUM, which the realm ladder and the
## authored capacity already govern.
##
## ## The twin of `TechniqueMarginalia.is_capacity_effect`
##
## Two refusals on one quantity from opposite directions — a rung may not scale a
## capacity, and a copy's margin may not band one — and they are written twice
## because they answer different questions at different moments. That is a tie, so
## `test_technique_marginalia.gd` walks every `cult_*` option in the shipped
## catalog and asserts the pair agree: a comment is not a tie, a test is.
##
## Keyed on the word `capacity`, because that is the corpus's word for it — and on
## the `max_` family, which is the OTHER word. A suffix test on `_maximum` alone
## caught `max_qi` and `max_stamina` and let three real capacities through:
## `dantian_capacity` (re-sealed every `synchronize` by `qi_cultivation/training.gd`
## from the next realm's authored value), `essence_capacity`, and
## `carry_capacity`. Each would scale by 1.749 at rung 4 — the exact double-count
## ADR 0160 refuses. Matching the concept is the only rule that survives content the
## predicate has never seen; a name list is a list that is out of date the moment
## someone adds a pool.
static func _is_capacity(target_id) -> bool:
	return TechniqueMarginalia.is_capacity_effect(target_id)


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
