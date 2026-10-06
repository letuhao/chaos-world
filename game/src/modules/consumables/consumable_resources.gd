class_name ConsumableResources
extends RefCounted

## The three AUTHORED consumables a domain run spends, and what each one costs when it
## is empty (ADR 0276). One closed table, declared here rather than scattered.
##
## ## Why a table and not three literals
##
## The resource id, the pool size, the per-room burn and the empty cost are ONE authored
## fact split across four call sites if each of them hard-codes its own copy: `levels`
## sizes the pool, `deplete` spends it, `empty_cost` publishes it and the `.tres` pays it.
## A retune that moved one and not the other is the ADR 0066 duplication failure, and it
## would show up as a pool of ten rooms that drains at two a room with no error anywhere.
## One table, one row per resource, and a test that asserts every field the facade
## publishes still equals this row.
##
## ## Why these three and not a `ResourceDef` content tree
##
## `RESOURCE_HOME_UNITS` in `tools/arch/rules.py` already holds authored `Resource`
## subclasses to the module that owns them, and `EnvironmentField.SUBSTRATES` is the
## precedent for the shape that passes it: a `const` table read as data, with the numbers
## a designer tunes sitting in ONE place. A `.tres` family would add a catalogue walk, an
## id-resolution seam and a load-time gate for three rows.
##
## ## The magnitude is a SHARE, never a health number
##
## ADR 0075 forbids a module subtracting health directly, and `status` pays a DOT as
## `magnitude * def.payload.share_per_pulse`. So [member ROWS]'s `cost_magnitude` is a
## potency — the number `StatusApi.resolve` re-derives onto the live instance — and the
## `.tres` beside it owns the share. Neither file may hold the other's number: this table
## is what a screen publishes, and the def is what the tick path spends.
##
## ## The cadence is published AND paid from the same row
##
## `cost_tick_interval` here is the number `empty_cost` shows a player so they can see
## how fast the bleed comes, and it is asserted equal to the `.tres`'s own `tick_interval`
## by `test_consumables.gd`. They are the same cadence, so they are authored twice and
## checked — not authored once in code and reached for at runtime, because the tick path
## reads the DEF and nothing in `status` may reach into another module's table.
##
## ## Torch costs PERCEPTION and never health, which is why it is not a DOT
##
## ADR 0276 asks for a perception penalty that may cause a false exit read, mirroring
## `EnvironmentField.SUBSTRATE_PERCEPTION_FAULT` — "the body is fine". A health drain
## would be a second starvation wearing a different name, so `darkness` is a
## `stat_modifier` on `insight_gain` and costs the player how clearly they read a room,
## not how much blood they have.

## The three resources, in canonical order. CLOSED: a caller naming anything else is
## refused by name rather than silently given a zero pool that never depletes.
const FOOD := &"food"
const WATER := &"water"
const TORCH := &"torch"
const IDS: Array[StringName] = [FOOD, WATER, TORCH]

## What an EMPTY pool costs, by name. Published on every `empty_cost` answer so a screen
## can label the bar it draws before the cost has ever landed.
const COST_STARVATION := &"starvation"
const COST_DEHYDRATION := &"dehydration"
const COST_DARKNESS := &"darkness"

## ## The pool size, in ROOMS rather than in units
##
## One unit of food is one room entered, so `maximum` is literally "how deep you can go on
## what you are carrying". A ten-room food budget against a `DomainMap` whose `room_count`
## the facade already publishes is the whole survival budget in one comparison, and it is
## why [member ROWS]'s `per_room` is `1.0` for all three rather than three tuned numbers:
## the ATTRITION is authored by the map you chose, and this table only says how much of
## yourself you brought.
##
## Torch is larger than food and water because it is not a daily need — a dark room costs
## a read, not a meal — so the two pressures are deliberately different shapes rather than
## three copies of one dial.
const ROWS: Dictionary = {
	FOOD: {
		"label": "food",
		"maximum": 10.0,
		"per_room": 1.0,
		"empty_status_id": COST_STARVATION,
		"cost_magnitude": 0.35,
		"cost_tick_interval": 2.0,
	},
	WATER: {
		"label": "water",
		"maximum": 10.0,
		"per_room": 1.0,
		"empty_status_id": COST_DEHYDRATION,
		"cost_magnitude": 0.30,
		"cost_tick_interval": 2.0,
	},
	TORCH: {
		"label": "torch",
		"maximum": 12.0,
		"per_room": 1.0,
		"empty_status_id": COST_DARKNESS,
		# A PERCENT potency on a PERCENT stat, so 1.0 is the full authored penalty and a
		# magnitude below it would be a weaker dark rather than a shorter one.
		"cost_magnitude": 1.0,
		"cost_tick_interval": 1.0,
	},
}


## Whether this table carries a row for `resource_id`. The gate every verb tests before
## it touches a pool, so an unknown id is a NAMED refusal rather than a zeroed resource
## that looks like a player who spent everything.
static func has(resource_id: StringName) -> bool:
	return ROWS.has(String(resource_id))


## One row as a plain dictionary, or `{}` for an id this table does not author. A copy
## rather than the row itself: the const must not be writable through a caller's edit.
static func row_of(resource_id: StringName) -> Dictionary:
	if not has(resource_id):
		return {}
	var row: Dictionary = ROWS[String(resource_id)]
	return row.duplicate(true)


## Every authored row, in canonical order, keyed by id. What a test iterates so a retune
## to one row cannot be asserted only on the other two.
static func rows() -> Dictionary:
	var out := {}
	for resource_id in IDS:
		out[String(resource_id)] = row_of(resource_id)
	return out