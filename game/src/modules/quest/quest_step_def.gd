class_name QuestStepDef
extends Resource

## One thing that must have happened, named as a **fact in the shared world ledger**
## (ADR 0113). A step never counts anything itself: it names a fact id and asks
## the one ledger how many of that fact exist. That is the whole point of the
## ledger — a quest step, an npc tally, a combat kill and an event trigger all
## write the same row, so "the player did X" has exactly one home.
##
## Because the ledger is monotone, `optional` is the only way a step can be
## skipped, and it is authored here rather than inferred: an optional step is
## flavour the player may never do, and a required one is the quest.

@export var step_id: StringName = &""
## The bare fact id in the ledger's one flat namespace. Never `quest:`-prefixed —
## ADR 0113 refuses a namespaced fact for the same reason ADR 0065 refuses a
## namespaced fate id.
@export var fact: StringName = &""
## How many of that fact the world must hold. 0 or less is normalized to 1, so
## a step can never be satisfied by a ledger that has never heard of its fact.
@export var need: int = 1
@export var display_name: String = ""
## An optional step never blocks completion and is never listed as outstanding.
@export var optional: bool = false


## The count this step asks for, always at least 1.
func required_count() -> int:
	return maxi(1, need)


## A step with no fact names nothing and could never complete, so it is a content
## bug. Exposed so a content test can say so rather than discovering it in play.
func well_formed() -> bool:
	return step_id != &"" and fact != &"" and required_count() >= 1
