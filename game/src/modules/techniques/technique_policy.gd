class_name TechniquePolicy
extends RefCounted

## The vocabulary and the fixed numbers of the technique system, in one place so
## no two files can restate them and drift.
##
## The path markers live here rather than in `PathState` because they are this
## module's vocabulary: a `SHARED` technique and a `"qi+body"` DUAL technique are
## authored rows, not cultivation-path states, and `contracts/` holds only what is
## genuinely shared between modules.

## A technique every path may learn and equip. Takes a UNIVERSAL slot, never a
## path slot, so spending one is a real cost against path depth (ADR 0053).
const SHARED := &"shared"

## Joins two path ids into a DUAL technique's `path` field.
const DUAL_SEPARATOR := "+"

## The fixed per-path slot counts, identical for the whole 30-realm ladder. Only
## the universal pool grows, by one per tier (ADR 0053).
const PATH_SLOTS := {PathState.QI: 3, PathState.BODY: 2, PathState.MIND: 2}

## Universal slots by realm tier: Mortal 0, Spirit 1, Immortal 2, Transcendent 3.
## Read from the actor's realm TIER through `RealmDefaults.ladder().tier_of()`,
## never from a ladder index, so an inserted realm cannot shift every actor below
## it onto the wrong count.
const UNIVERSAL_SLOTS_BY_TIER := {1: 0, 2: 1, 3: 2, 4: 3}

## Tier assumed for an actor whose realm is not on the ladder, and for a fresh
## actor with no path at all. Mortal is the conservative read: it grants the
## smallest slot budget, never a larger one.
const DEFAULT_TIER := 1

## ADR 0054: a passive holds two options maximum. The cap is what keeps a codex
## page a comparison rather than a table of numbers.
const PASSIVE_OPTION_CAP := 2


## Slot budget for a realm tier: `{qi, body, mind, universal, total}`. Totals are
## 7 / 8 / 9 / 10 across the four tiers.
static func slot_budget(tier: int) -> Dictionary:
	var universal := int(UNIVERSAL_SLOTS_BY_TIER.get(tier, 0))
	var out := {"universal": universal, "total": universal}
	for path_id in PathState.ALL:
		var count := int(PATH_SLOTS.get(path_id, 0))
		out[path_id] = count
		out["total"] += count
	return out


## Slot budget for an actor's current realm tier.
static func budget_for_actor(actor: Actor) -> Dictionary:
	if actor == null:
		return slot_budget(DEFAULT_TIER)
	return slot_budget(RealmDefaults.ladder().tier_of(actor.realm()))


## The realm TIER of `realm_id`, or `DEFAULT_TIER` when it is not on the ladder.
static func tier_of(realm_id: StringName) -> int:
	if realm_id == &"":
		return DEFAULT_TIER
	var tier := RealmDefaults.ladder().tier_of(realm_id)
	return tier if tier > 0 else DEFAULT_TIER
