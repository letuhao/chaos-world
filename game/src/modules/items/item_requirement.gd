class_name ItemRequirement
extends Resource

## Optional requirement profile for one item (ADR 0052, adapted from Keepverse
## `equipment-requirement-maintenance.md`).
##
## Requirements exist so an exceptional item cannot simply be worn by a weak actor
## for free. They are strictly OPTIONAL: an item with an empty profile has no
## restriction, and rarity does not imply demand — an ordinary common item should
## never carry a requirement it did not ask for.
##
## Two rules are load-bearing and are enforced by `Equipment`:
##
## 1. **Gear never enables its own requirement.** Every check reads the actor's BASE
##    attributes and base resources, never a derived stat and never anything an
##    equipped item supplied. Reading `stats.get_base` rather than `stats.derived`
##    is what makes this structural instead of a rule to remember.
## 2. **Upkeep is an ongoing obligation, not an equip gate.** An item whose upkeep
##    cannot be paid stays EQUIPPED and contributes NOTHING; it is not unequipped and
##    it is not a barrier to equipping. Combat spending therefore cannot cause an
##    equip cascade, while a strong item still carries a running price.
##
## The four profiles are independent and may combine:
##   realm   — a minimum realm ordinal, so a R30 relic needs a R30 actor
##   fixed   — minimum base value for named attributes
##   ratio   — minimum SHARE of the actor's base allocation, so the item favours a build
##   upkeep  — a resource drained per interval while equipped

## Profile kinds. An item declares at most one of each.
const REALM := &"realm"
const FIXED := &"fixed"
const RATIO := &"ratio"
const UPKEEP := &"upkeep"

## Minimum realm ORDINAL the actor must have reached: 0 at Qi Refining, 29 at
## Primordial Origin, read off the shared 30-realm ladder. A realm ordinal is the
## natural unit of "this item demands a practitioner" - the actor is at a realm, not
## at a number - so the floor is compared straight across without any conversion.
## Breakthroughs inside a realm do not move it: a floor names a realm, and the
## ordinal is what an item can honestly be said to require.
@export var min_realm_index: int = 0

## Minimum BASE attribute value, keyed by Stat id.
@export var fixed_minimums: Dictionary = {}

## Minimum share of the actor's BASE allocation, keyed by Stat id. A share is the
## stat's base value over the total of every stat named here, so the ratio means
## "this build leans on X" rather than "this build has a big number".
@export var ratio_minimums: Dictionary = {}

## Upkeep: resource id -> amount drained per `upkeep_interval` seconds while the
## item is equipped and not suspended.
@export var upkeep: Dictionary = {}
@export var upkeep_interval: float = 60.0

## How far below the required amount a resource may fall before payment is refused.
## Without a reserve, upkeep would chip an actor to zero and suspend on the last tick.
@export var upkeep_reserve: Dictionary = {}


func is_empty() -> bool:
	return (
		min_realm_index <= 0
		and fixed_minimums.is_empty()
		and ratio_minimums.is_empty()
		and upkeep.is_empty()
	)


## Every unmet requirement, for a panel to render. Empty means the item is wearable.
func unmet(actor: Actor) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []
	if actor == null:
		return problems
	if min_realm_index > 0:
		var best := _actor_realm_index(actor)
		if best < min_realm_index:
			(
				problems
				. append(
					{
						"kind": REALM,
						"id": &"realm",
						"required": min_realm_index,
						"actual": best,
						"label": "Requires realm %d (you are at %d)" % [min_realm_index, best],
					}
				)
			)
	for stat_id in fixed_minimums:
		var required := float(fixed_minimums[stat_id])
		var actual := actor.stats.get_base(stat_id)
		if actual < required:
			(
				problems
				. append(
					{
						"kind": FIXED,
						"id": stat_id,
						"required": required,
						"actual": actual,
						"label": "Requires %s %s" % [stat_id, required],
					}
				)
			)
	for stat_id in ratio_minimums:
		var required := float(ratio_minimums[stat_id])
		var actual := _share_of(actor, stat_id)
		if actual < required:
			(
				problems
				. append(
					{
						"kind": RATIO,
						"id": stat_id,
						"required": required,
						"actual": actual,
						"label": "Requires a %s lean of %.0f%%" % [stat_id, required * 100.0],
					}
				)
			)
	return problems


func satisfied_by(actor: Actor) -> bool:
	return unmet(actor).is_empty()


## This stat's share of the BASE allocation across every stat named in `ratio_minimums`.
## Base only, so an item cannot satisfy a ratio by granting the stat it demands.
func _share_of(actor: Actor, stat_id: StringName) -> float:
	var total := 0.0
	for other in ratio_minimums:
		total += actor.stats.get_base(other)
	if total <= 0.0:
		return 0.0
	return actor.stats.get_base(stat_id) / total


## The actor's highest realm ordinal across every cultivation path it has, so an
## item never demands one specific path. `PathState.ALL` keeps this from naming a
## module, and `RealmDefaults.ladder()` is the shared ladder every system already
## reads, so the ordinal needs no private conversion.
func _actor_realm_index(actor: Actor) -> int:
	var best := 0
	for path_id in PathState.ALL:
		var state := actor.path(path_id)
		if state == null:
			continue
		best = maxi(best, RealmDefaults.ladder().index_of(state.rank_id))
	return best
