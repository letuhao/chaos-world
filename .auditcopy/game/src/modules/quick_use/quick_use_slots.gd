class_name QuickUseSlots
extends RefCounted

## The quick-use bar: [constant SLOT_COUNT] slots, each holding one item `def_id`.
## Moved out of `app/` per ADR 0056 and DEF-0098, which kept the retired prototype's
## file as the repo's id-persistence model.
##
## ## This is a binding table, not an inventory
##
## The only fact a slot holds is WHICH `def_id` is bound to WHICH index. There is
## deliberately no quantity, no stack and no effect here: how many of that item the
## actor carries, and what spending one does, are both `items`' business and are read
## through `ItemsApi` at the moment they are asked for. A second count of the same
## item is the ADR 0066 failure shape — the two would drift the first time a save
## restored one and not the other — and `tools arch` cannot see a member that does
## not exist, so `test_quick_use_is_not_a_second_inventory.gd` holds the line
## structurally.
##
## ## Why ids and not definitions (ADR 0056)
##
## [method to_ids] persists six bare `StringName`s. Persisting a whole authored
## definition would let a designer retuning a pill silently rewrite every save.
##
## Every method here is reached through [QuickUseApi], which owns the refusal
## vocabulary; this class holds no wording and makes no promise to a caller.

## Published so a panel draws the bar the width the module actually has
## (AGENTS.md: step amounts live in the facade, never in a screen).
const SLOT_COUNT := 6

## One `def_id` per slot, `&""` when the slot is empty. The module's entire state.
var _bound: Array = []


## A bar restored from [code]ids[/code], or a fresh empty one. A payload shorter
## than the bar is padded with empties and a longer one is truncated, so a save
## written at a different bar width restores the slots it can instead of failing.
func _init(ids: Array = []) -> void:
	_bound.resize(SLOT_COUNT)
	for index in SLOT_COUNT:
		_bound[index] = &""
	for index in mini(ids.size(), SLOT_COUNT):
		_bound[index] = StringName(ids[index])


## The id bound to `slot_index`, or `&""` for an index outside the bar. A bad index
## reads as empty rather than raising, so a panel iterating a stale count cannot
## crash the frame it draws.
func bound_at(slot_index: int) -> StringName:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return &""
	return _bound[slot_index]


## Bind `def_id` to `slot_index`, replacing whatever was there. Returns false and
## writes nothing for an index outside the bar.
func bind(slot_index: int, def_id: StringName) -> bool:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return false
	_bound[slot_index] = def_id
	return true


## Release `slot_index` and return the id it held, or `&""` for an index outside the
## bar. Freeing a slot never discards anything: the item is still in the bag, which
## is the whole difference between a bar and an inventory.
func release(slot_index: int) -> StringName:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return &""
	var previous: StringName = _bound[slot_index]
	_bound[slot_index] = &""
	return previous


## The persisted form: six bare ids in slot order, `""` for empty. Strings rather
## than `StringName`s because this is what crosses into a save file.
func to_ids() -> Array:
	var out: Array = []
	for index in SLOT_COUNT:
		out.append(String(_bound[index]))
	return out
