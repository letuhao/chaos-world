class_name TeardownYield
extends RefCounted

## What one unwanted piece of equipment is worth when it is torn down.
##
## The sink exists because the bag is finite ([constant Inventory.DEFAULT_CAPACITY])
## while the drops are guaranteed, so equipment accrues with nothing to spend it on.
## The yield is AUTHORED MATERIAL, not currency: crafting already consumes
## materials, so this closes a loop that is already built instead of minting a
## second one.
##
## ## The formula, and why it is not a flat refund
##
## `units = GRADE_BASE[grade] * RARITY_REFUND[rarity] * (1 - ROLL_DISCOUNT * rolled)`
## floored at 1 and capped at the grade base.
##
## Three factors, and each one is a decision with a counterpart:
##
##  - **Grade sets the ceiling.** A higher band is made of rarer stuff, so it
##    yields more units. This is the only factor that can raise the yield.
##  - **Rarity DISCOUNTS it.** A legendary refunds a quarter of its grade base, so
##    converting one is a bad deal and keeping it is the better play. This is the
##    counterpart to "a valuable item is hard to earn": a flat refund would pay a
##    lucky roll its full worth and delete the reason to keep hunting for a
##    better one. A discount makes the loot itself the thing worth keeping.
##  - **Each realized option DISCOUNTS it further.** A rolled option is the
##    player's reason to hold the piece, so it costs yield. `ItemRarity.POLICY`
##    caps rolled options at four, so the multiplier bottoms out at 0.68 and can
##    never reach zero and delete the sink.
##
## ## The floor is load-bearing
##
## `MIN_UNITS := 1` means no grade, rarity or roll combination ever yields zero.
## A zero yield would be a SECOND way to throw gear away — the exact defect this
## sink was built to remove. Every refused tier is refused by NAME at the
## transaction instead of silently producing nothing.
##
## ## Keyed by grade id, never by position
##
## `GRADE_BASE` and `MATERIAL_BY_GRADE` are keyed by [ItemGrade]'s stable ids, the
## same rule as `realm_power_table.tres`: inserting a grade must not silently
## rescale every grade below it.
##
## ## The materials are the jade family, and every one is real
##
## One material per grade, each consumed by between 11 and 37 authored recipes, so
## every yield is immediately spendable. `test_teardown_yield.gd` pins that a
## content edit cannot quietly orphan the sink, and `tear_down` refuses with
## `REASON_UNKNOWN_MATERIAL` rather than granting nothing if one ever disappears.

## Units a grade can yield at its best case (common rarity, no realized options).
## The ceiling the rarity and roll discounts work down from.
const GRADE_BASE := {
	ItemGrade.MORTAL: 2,
	ItemGrade.SPIRIT: 3,
	ItemGrade.EARTH: 4,
	ItemGrade.HEAVEN: 5,
	ItemGrade.IMMORTAL: 6,
	ItemGrade.DIVINE: 8,
}

## Fraction of [constant GRADE_BASE] a realized rarity is worth back. Common pays
## in full because it is the piece clogging the bag; legendary pays a quarter, so
## a lucky roll is worth more worn than sold.
const RARITY_REFUND := {
	ItemRarity.COMMON: 1.0,
	ItemRarity.MAGIC: 0.75,
	ItemRarity.RARE: 0.5,
	ItemRarity.LEGENDARY: 0.25,
}

## Each realized rolled option removes this much of the remaining yield. Four
## options (a legendary's full count) leaves 0.68 — a floor, never a zero.
const ROLL_DISCOUNT := 0.08
## Hard ceiling on the discount, derived from the maximum rolled count rather than
## typed in, so a policy that ever allowed more affixes cannot drive the
## multiplier negative and invert the sink into a penalty.
const MAX_ROLL_DISCOUNT := 0.9

## No teardown ever yields nothing. See the class note.
const MIN_UNITS := 1

## The grade-keyed salvage material. Every id resolves under
## `res://data/items/material/` and is an input to authored recipes.
const MATERIAL_BY_GRADE := {
	ItemGrade.MORTAL: &"jade_ore",
	ItemGrade.SPIRIT: &"jade_azure",
	ItemGrade.EARTH: &"jade_moon",
	ItemGrade.HEAVEN: &"jade_star",
	ItemGrade.IMMORTAL: &"jade_immortal",
	ItemGrade.DIVINE: &"jade_divine",
}


## Material this grade's teardown pays out, or `&""` for a grade no row names.
static func material_for(grade: StringName) -> StringName:
	return MATERIAL_BY_GRADE.get(grade, &"")


## Units `instance` tears down into. Pure: reads the definition and the realized
## instance only, touches no actor and no inventory, so the policy is testable on
## its own and a caller can quote a yield before asking for one.
##
## An unknown grade falls back to [constant ItemGrade.MORTAL]'s base rather than
## yielding nothing, because a malformed grade is a content defect and must not
## also become a player-facing dead end.
static func units_for(def: ItemDef, instance: ItemInstance) -> int:
	if def == null:
		return 0
	var grade := def.grade if ItemGrade.ALL.has(def.grade) else ItemGrade.MORTAL
	var base := int(GRADE_BASE.get(grade, GRADE_BASE[ItemGrade.MORTAL]))
	var rarity := ItemRarity.sanitize(instance.rarity if instance != null else def.rarity)
	var discount := 0.0
	if instance != null:
		# `rolled` is a fixed realized array: this reads its length and appends
		# nothing, so there is no loop to bound and no way for it to grow.
		discount = minf(ROLL_DISCOUNT * float(instance.rolled.size()), MAX_ROLL_DISCOUNT)
	var refund := float(RARITY_REFUND.get(rarity, RARITY_REFUND[ItemRarity.COMMON]))
	var units := int(floor(float(base) * refund * (1.0 - discount)))
	return clampi(units, MIN_UNITS, base)


## The whole quote for one instance: what it pays, into what, and the grade that
## decided it. Primitives only, so a panel may render it unchanged.
static func quote(def: ItemDef, instance: ItemInstance) -> Dictionary:
	if def == null:
		return {"ok": false, "material_id": "", "units": 0, "grade": ""}
	var material := material_for(def.grade)
	return {
		"ok": material != &"",
		"material_id": String(material),
		"units": units_for(def, instance),
		"grade": String(def.grade),
		"rarity": String(instance.rarity if instance != null else def.rarity),
		"rolled_options": instance.rolled.size() if instance != null else 0,
	}
