class_name SetPlacement
extends RefCounted

## How many distinct members of one set a body can actually wear at once, and
## which slot each one goes in.
##
## This is a PLACEMENT question, not a count. `member_count` and
## `Equipment.SLOTS.size()` agree only when every member can be given a slot of
## its own, and a set breaks that the moment it holds two artifacts or three
## weapons: the members are plentiful, the slots are not, and a threshold wide
## enough to need all of them is dead content that still passes a ceiling
## computed from arithmetic. Which is exactly how `void_serpent_coil` shipped a
## six-member tier no body could reach.
##
## A member is placed iff the authored slot rule offers it a slot nothing else
## holds. Both directions matter and neither implies the other: a member with no
## ruling may go anywhere, so it never blocks itself, and a member that can only
## wear one of two taken slots is dropped rather than double-parked.
##
## Deliberately a pure function of its input. It knows nothing about sets, items
## or slots, which is what lets a test hand it the exact member shapes that make
## a threshold unreachable and watch the ceiling drop.

## Ceiling on how deep the reassignment search may go. The search visits each slot
## at most once per attempt and so terminates regardless; the cap is what stops a
## malformed option list from turning that guarantee into a stack-depth gamble.
## It is named after what it bounds, not tuned to the data.
const MAX_REASSIGN_DEPTH := 8


## The slot each member occupies, by member index, or `&""` for a member no body
## can wear alongside the others. Order is the caller's: index `i` is `i` of the
## array passed to the matching call, so a caller can place member `i` into
## `result[i]` without re-deriving anything.
static func assign(member_slots: Array) -> Array[StringName]:
	var by_slot: Dictionary = {}
	for index in member_slots.size():
		_try_place(index, member_slots, by_slot, {}, 0)
	var out: Array[StringName] = []
	for index in member_slots.size():
		out.append(&"")
	for slot in by_slot.keys():
		out[int(by_slot[slot])] = slot
	return out


## How many members [method assign] placed. The real ceiling on a set's thresholds.
static func placed_count(member_slots: Array) -> int:
	var total := 0
	for slot in assign(member_slots):
		if slot != &"":
			total += 1
	return total


## Give `member` a slot, moving whoever holds it if that member can go elsewhere.
## Standard augmenting-path matching: a member that can be re-seated frees the
## slot for one that could not otherwise take it, which is how a later accessory
## still finds its place beside an earlier one.
static func _try_place(
	member: int, member_slots: Array, by_slot: Dictionary, visited: Dictionary, depth: int
) -> bool:
	if depth > MAX_REASSIGN_DEPTH:
		return false
	for slot in member_slots[member] as Array:
		if visited.has(slot):
			continue
		visited[slot] = true
		var holder: int = int(by_slot.get(slot, -1))
		if holder == -1 or _try_place(holder, member_slots, by_slot, visited, depth + 1):
			by_slot[slot] = member
			return true
	return false
