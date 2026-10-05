class_name SoulDef
extends Resource

## One authored arrival a soul is re-embodied into (ADR 0127, ADR 0130).
##
## An arrival is EARNED, never chosen: `SoulGate` reads the ledger and answers which one comes
## next, and the player is never offered a choice among them. That is what keeps this inside
## ADR 0065, which forbids a picker over fates and destinies — the ledger is the receipt and
## the gate is the decision.
##
## ## Why these ship with no exclusivity group
##
## `DestinyDef.group` makes destinies in the same group mutually exclusive for good. Rebirth
## arrivals are CONSEQUENCES of dying, not competing claims on the player's identity, and three
## consequences that locked each other out would mean a soul that died twice had fewer options
## than a soul that died once — the wrong direction. So an arrival here names no group at all,
## and every arrival is independently earnable.

## Stable authored id. The gate reads this; a `.tres` deleted between two runs makes its
## arrival unreachable rather than granting an arrival nothing defines.
@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
## One line a player reads when their soul returns into this arrival.
@export var bearing: String = ""
## The body this arrival arrives in. Authored HERE rather than in code because a table of
## origin-to-race mappings in the composition root is content living in the wrong layer, and
## adding an arrival would otherwise mean editing that file.
@export var race_id: StringName = &""
## Order the gate walks. Ties break by id, so two arrivals never depend on directory order.
@export var order: int = 0
## Fates this arrival is owed, named so authored content can gate on it. The soul module
## never grants one itself — that is `destiny`'s ledger, on a body.
@export var marks: Array[StringName] = []


## Whether this def names an arrival at all.
func is_valid_def() -> bool:
	return id != &""


## The `Actor.traits` mirror id this arrival is reflected under.
static func trait_for(arrive_id: StringName) -> StringName:
	return StringName("soul:%s" % arrive_id)
