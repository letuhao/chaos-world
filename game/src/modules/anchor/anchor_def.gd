class_name AnchorDef
extends Resource

## One authored soul anchor: a place built to hold a damaged soul (ADR 0132).
##
## ## What an anchor IS
##
## **A structure the player raises, which repairs their soul while they are there.** This is
## the "building feature" the rebirth program was asked to wire into, and it is built as its
## own module rather than folded into `holdings` for two reasons: `holdings` is at its
## twelve-method facade cap and has no build verb at all, and an anchor is a thing you RAISE
## rather than a claim over ground that already existed.
##
## ## Why it is keyed by id, never by index
##
## The same rule as `realm_power_table.tres` and `PortraitDef`: an inserted anchor must not
## shift every later one onto the wrong cost.

## Stable authored id. The only key anything resolves by.
@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
## What it costs to raise, as `{items: {def_id: count}, coins: int}`. Authored as a requirement,
## never as a literal in code — the same reason `HoldingsApi.claim_cost` is an obligation line
## rather than an authored amount.
@export var build_cost: Dictionary = {}
## Integrity this anchor restores per whole period, and only while its holder stands in it.
## Fractional, because a per-period repair that cannot land on a whole number is not repair.
@export var repair_per_period: float = 0.0
## The realm floor, if any: an anchor no one can reach yet is content that cannot be used, and
## saying so on the def is better than failing a gate at the moment a player tries it.
@export var realm_floor: StringName = &""
## Whether this anchor heals the soul or only shelters it. A shelter stops a further death from
## costing anything; a hearth repairs what is already lost. Two different verbs, so two ids.
@export var repairs: bool = true
@export var shelters: bool = false


## Whether this def names an anchor at all.
func is_valid_def() -> bool:
	return id != &""


## The `Actor.traits` mirror id this anchor is reflected under.
static func trait_for(anchor_id: StringName) -> StringName:
	return StringName("anchor:%s" % anchor_id)
