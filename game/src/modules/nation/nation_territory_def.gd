class_name NationTerritoryDef
extends Resource

## One authored **claim over places**. A territory is never a place.
##
## ADR 0083 is explicit that territory is "a claim over places authored inside
## `sect`", and ADR 0085 is explicit that it "grants no combat bonus": a
## home-ground modifier would make the map a combat *input*, so every territory
## would inherit a balance obligation against every mechanism. Territory decides
## who may fight and where; the shared spine decides who wins.
##
## ## What is deliberately absent
##
## No yield, no upkeep, no qi density, no combat bonus, no defence. Those are
## **tuning** and they live in `NationTuning`, one row per `tier_index`, so a
## rebalance is a `.tres` edit and no test re-pins a literal. If a number about a
## territory can be retuned, it belongs there; if it decides *which places a claim
## covers*, it belongs here.
##
## It is a `.tres` Resource, so it belongs in `modules/`, never in `contracts/`.

@export var id: StringName = &""
@export var display_name: String = ""
## Which tuning row this claim reads. An index, not an amount — the amounts are in
## `NationTuning` and editing one is a balance edit, not a content edit.
@export var tier_index: int = 0
## The places this claim covers. Ids, never `WorldLocationDef` references: the
## nation module declares no `world` dependency, and a `.tres` reference would be a
## `res://` edge the boundary checker reads as one.
@export var location_ids: Array[StringName] = []
## The place a contest for this claim is fought over. Empty means the claim has no
## seat, which is legal content rather than a broken one.
@export var seat_location_id: StringName = &""
## How the seat is held: authored content, e.g. `stone_seat`, `writ_seat`.
@export var seat_kind: StringName = &""
@export var tags: Array[StringName] = []


## Whether the claim covers anywhere at all. A claim over zero places is content
## that exists and holds nothing — the ADR 0083 middle state again, and the reason
## a take on it is refused with a named reason instead of succeeding vacuously.
func covers_land() -> bool:
	return not location_ids.is_empty()


## Whether this claim names the place a contest over it is fought for.
func has_seat() -> bool:
	return seat_location_id != &""
