class_name TechniqueSet
extends Resource

## Authored technique set definition: member techniques and threshold bonuses.
##
## A set bonus triggers when N techniques from the same set are equipped.
## This is the technique-layer counterpart to `SetDef` (which is item-focused):
## `SetDef` derives state from `actor.equipment`, while this derives from
## `TechniqueSlots` — the limited, path-typed binding of equipped techniques.
##
## The `active` flag declares authoring intent: `false` means the bonus is a
## passive stat contribution, `true` means the set is designed for active
## techniques. In BOTH cases the bonus is applied through the stat pipeline as
## `StatModifier`s under a `technique_set:<set_id>:<tier>` source — an active
## technique's benefit IS the cast, so a set bonus on one is includable only as
## a passive contribution that modifies the cast's effectiveness, never as a
## separate action that fires nothing.

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""

## Technique ids that belong to this set. No duplicate ids, ever — a set counts
## distinct equipped members, so a duplicate would let one technique satisfy a
## threshold twice.
@export var members: Array[StringName] = []

## Threshold tiers in ascending piece-count order:
##   `{count: int, label: String, options: [{option_id: &"...", value: float}]}`
## `count` is distinct equipped members, so it may never exceed how many of this
## set's members can actually be equipped at once given the slot budget.
@export var tiers: Array[Dictionary] = []

## Whether this set is designed for active techniques. The bonus is always
## applied through the stat pipeline; this flag is authoring intent for the UI
## and content audit. See the file header for why an active set's bonus is
## applied as a passive contribution rather than a separate cast action.
@export var active: bool = false


## How many techniques this set counts toward its thresholds.
func member_count() -> int:
	return members.size()


## Whether `technique_id` is a member of this set.
func is_member(technique_id: StringName) -> bool:
	return members.has(technique_id)


## Every threshold index this many distinct members reach. Partial thresholds
## come back too: one member of a three-piece set still activates tier 0.
func active_tier_indices(distinct: int) -> Array[int]:
	var out: Array[int] = []
	for index in tiers.size():
		if distinct >= int(tiers[index].get("count", 0)):
			out.append(index)
	return out
