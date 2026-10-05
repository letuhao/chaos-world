class_name SetDef
extends Resource

## Authored set definition (ADR 0025/0033): the members that make it up and the
## threshold bonuses each number of equipped members unlocks.
##
## A set owns no effect of its own. Every member is an ordinary `ItemDef` that
## resolves through the master option catalog, and every threshold is a list of
## master option ids with authored values — so a set never restates an effect
## implementation, and a member's own effects are unaffected by membership.

## The only counting policy: a set counts *distinct definitions*. Two copies of
## one member in two accessory slots are one member, never two, so a threshold
## can never be reached by duplicating a single piece.
const COUNT_DISTINCT_DEFINITION := &"distinct_definition"

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
## The canonical realm this set's threshold values are authored for. Threshold
## magnitudes are validated inside this realm's window, so a set never hands out
## a bonus scaled for a different band.
@export var realm: StringName = &""
## The representative rarity band of the set; pairs with `realm` to bound the
## authored threshold values.
@export var rarity: StringName = &"common"
## Counting policy, declared rather than implied so the rule is data, not code.
@export var counting: StringName = COUNT_DISTINCT_DEFINITION
## Ordinary members, by definition id. No duplicate ids, ever.
@export var pieces: Array[StringName] = []
## Unique members. A unique counts toward the thresholds exactly like a piece.
@export var uniques: Array[StringName] = []
## Threshold tiers in ascending piece-count order:
##   `{count: int, label: String, options: [{option_id: &"...", value: float}]}`
## `count` is distinct equipped members, so it may never exceed how many this set's
## members can actually be placed in a body's slots — a *placement*, not a count.
## [method member_count] cannot answer that: it is arithmetic over the set's own
## declarations and cannot see two artifacts contending for one slot. The number
## that governs a threshold lives in [SetCatalog], which resolves the members and
## asks [SetPlacement].
@export var tiers: Array[Dictionary] = []


## How many definitions this set counts toward its thresholds.
func member_count() -> int:
	return pieces.size() + uniques.size()


## Every counted member id, pieces first.
func member_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for piece_id in pieces:
		out.append(piece_id)
	for unique_id in uniques:
		out.append(unique_id)
	return out


func is_member(item_id: StringName) -> bool:
	return pieces.has(item_id) or uniques.has(item_id)


func is_unique_member(item_id: StringName) -> bool:
	return uniques.has(item_id)


## Which authored tier a member id belongs to for presentation (`piece` /
## `unique` / `""`).
func member_kind(item_id: StringName) -> StringName:
	if pieces.has(item_id):
		return &"piece"
	if uniques.has(item_id):
		return &"unique"
	return &""


## Every threshold index this many distinct members reach. Partial thresholds
## come back too: one member of a three-piece set still activates tier 0.
func active_tier_indices(distinct: int) -> Array[int]:
	var out: Array[int] = []
	for index in tiers.size():
		if distinct >= int(tiers[index].get("count", 0)):
			out.append(index)
	return out
