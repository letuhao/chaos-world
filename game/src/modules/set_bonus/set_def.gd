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
## `count` is distinct equipped members, so it may never exceed
## `max_equippable()` — see that method for why the slot list is the ceiling.
@export var tiers: Array[Dictionary] = []


## How many definitions this set counts toward its thresholds.
func member_count() -> int:
	return pieces.size() + uniques.size()


## The most distinct members of this set a body can ever have equipped at once.
##
## A threshold is satisfied only by what is actually worn, and a body has exactly
## `Equipment.SLOTS` places to wear it, so a tier above this is unreachable
## content rather than a reward. Reading the same slot list the runtime iterates
## (`SetBonusState._distinct_equipped`) is the whole point: a ceiling computed from
## the set's own member count is arithmetic that cannot fail, and it stayed green
## while `void_serpent_coil` shipped a six-member tier no body could reach.
func max_equippable() -> int:
	var declared: int = member_count()
	var slots: int = Equipment.SLOTS.size()
	return declared if declared < slots else slots


## Which authored tiers no body can ever reach, given the members this set
## declares and the slots a body actually has. Empty means the whole ladder is
## winnable, which is what the content suite asserts over the shipped sets.
func unreachable_tier_indices() -> Array[int]:
	var out: Array[int] = []
	var ceiling := max_equippable()
	for index in tiers.size():
		if int(tiers[index].get("count", 0)) > ceiling:
			out.append(index)
	return out


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
