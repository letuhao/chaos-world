class_name LootEntry
extends Resource

## One authored entry in a loot table. The selection mechanisms are deliberately
## separate so an author can read exactly what a single entry does, and so loot
## probability is never confused with item-option probability (ADR 0033):
##
##   guaranteed    Resolved once on every resolve. Ignores `chance` and `weight`,
##                 and is resolved before any `loot_bonus` count bonus is applied,
##                 so a guaranteed entry is present on every outcome.
##   chance >= 0   An independent Bernoulli roll per resolve, made separately for
##                 each such entry. `weight` is ignored, so this entry never
##                 competes with the weighted pool and several independent entries
##                 can fire in the same resolve.
##   chance < 0    A weighted-choice candidate for the table's draw range. One
##                 draw picks exactly one candidate, with replacement, so the
##                 same entry may legitimately appear twice.
##   kind = table  A nested table. `weight` or `chance` selects it; the child's
##                 own semantics then apply inside and its results are spliced.
##
## Quantity is a separate axis from the draw count: `quantity` is how many units
## one hit yields, and `[quantity, quantity_max]` is a uniform range when
## `quantity_max` is greater than `quantity`.

const KIND_ITEM := &"item"
const KIND_TABLE := &"table"
## Sentinel meaning "not an independent chance roll". A real chance is 0.0..1.0, so
## -1.0 can never collide with an authored probability.
const NO_CHANCE := -1.0

@export var id: StringName = &""
@export var kind: StringName = KIND_ITEM
@export var item_id: StringName = &""
@export var table_id: StringName = &""
## Relative likelihood inside the weighted pool. Only read by a weighted entry.
@export var weight: float = 1.0
## Independent roll probability, or [constant NO_CHANCE] for a weighted entry.
@export var chance: float = NO_CHANCE
@export var guaranteed: bool = false
@export var quantity: int = 1
## 0 means exactly `quantity`.
@export var quantity_max: int = 0
## "" means no floor. Otherwise the drop's rarity context is promoted to at least
## this tier before the `loot_bonus` quality bonus is applied.
@export var rarity_floor: StringName = &""


func is_nested() -> bool:
	return kind == KIND_TABLE


func is_independent() -> bool:
	return not guaranteed and chance >= 0.0


func is_weighted() -> bool:
	return not guaranteed and chance < 0.0


func is_independent_legal() -> bool:
	return chance >= 0.0 and chance <= 1.0


## Highest quantity this entry can produce.
func quantity_cap() -> int:
	return quantity if quantity_max <= quantity else quantity_max


## Units for one hit. Guaranteed entries take their authored floor; every other
## entry draws uniformly across its authored range.
func roll_quantity(rng: RandomNumberGenerator, randomized: bool = true) -> int:
	var low := maxi(1, quantity)
	var high := maxi(low, quantity_cap())
	if not randomized or high <= low or rng == null:
		return low
	return rng.randi_range(low, high)


## Effective independent-roll probability including the actor's bounded
## `loot_bonus` chance bonus. Never leaves 0.0..1.0.
func effective_chance(chance_bonus: float) -> float:
	if not is_independent():
		return 0.0
	return clampf(chance + chance_bonus, 0.0, 1.0)
