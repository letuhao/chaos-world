class_name LootTableDef
extends Resource

## An authored weighted loot table. Two counts live here and never mix:
##
##   `rolls..rolls_max`  how many *weighted draws* the table makes. Each draw
##                       picks one candidate from the weighted pool. `rolls_max`
##                       of 0 means exactly `rolls` draws.
##   `quantity`           how many units one hit of an *entry* yields (see
##                       [LootEntry]).
##
## `allow_empty` is the explicit no-drop outcome. `false` means the table has
## declared that it never comes up empty, so a resolve that produced nothing
## forces one item-entry pick. `true` means "nothing here" is a legitimate result
## and the resolver reports it rather than substituting anything.
##
## `realm` and `rarity` are the *default* roll context for drops. A source that
## declares its own rarity (a boss tier) overrides rarity, so a drop from a late
## boss rolls for that boss's rarity rather than the definition's. `realm` is NOT
## overridden: the rung a drop pays is the one its item is authored at, so a band
## never sets a drop's magnitude (ADR 0166). The resolver still resolves and
## reports the realm for the reader; it is a drop's label, not its power.

## Ceiling on one resolve, so a bounded `loot_bonus` count bonus plus a wide
## authored range can never produce an unbounded number of drops.
const MAX_DROPS_PER_RESOLVE := 8

@export var id: StringName = &""
@export var display_name: String = ""
@export var realm: StringName = &""
@export var rarity: StringName = &""
## Weighted draws, minimum. 0 means "no weighted draws at all", which is how a
## pure chance table (or a pure guaranteed table) is authored.
@export var rolls: int = 1
## 0 means exactly `rolls`.
@export var rolls_max: int = 0
@export var allow_empty: bool = false
@export var entries: Array[LootEntry] = []


func roll_cap() -> int:
	return rolls if rolls_max <= rolls else rolls_max


## Draws for one resolve, uniform across the authored range, plus the bounded
## `loot_bonus` count bonus. Always inside `0..MAX_DROPS_PER_RESOLVE`.
func draw_count(extra: int, rng: RandomNumberGenerator) -> int:
	var low := maxi(0, rolls)
	var high := maxi(low, roll_cap())
	var base := high if (high <= low or rng == null) else rng.randi_range(low, high)
	return clampi(base + maxi(0, extra), 0, MAX_DROPS_PER_RESOLVE)


func entry_index(entry_id: StringName) -> int:
	for index in entries.size():
		if entries[index] != null and entries[index].id == entry_id:
			return index
	return -1


## Entries resolved once on every resolve, in authored order.
func guaranteed_entries() -> Array[LootEntry]:
	var out: Array[LootEntry] = []
	for entry in entries:
		if entry != null and entry.guaranteed:
			out.append(entry)
	return out


## Entries the draw range chooses from. Independent and guaranteed entries are
## deliberately excluded: they are not part of the weighted competition.
func weighted_entries() -> Array[LootEntry]:
	var out: Array[LootEntry] = []
	for entry in entries:
		if entry != null and entry.is_weighted():
			out.append(entry)
	return out


## Entries that each roll their own Bernoulli, independently of the draw range.
func independent_entries() -> Array[LootEntry]:
	var out: Array[LootEntry] = []
	for entry in entries:
		if entry != null and entry.is_independent():
			out.append(entry)
	return out


## Every item id this table can produce, nested tables included. Used by the
## validator and by the acquisition report; never by resolution.
func reachable_item_ids(depth: int = 0, chain: Array = []) -> Array[StringName]:
	var out: Array[StringName] = []
	if depth > 8 or chain.has(String(id)):
		return out
	var next_chain := chain.duplicate()
	next_chain.append(String(id))
	for entry in entries:
		if entry == null:
			continue
		if entry.is_nested():
			var child := LootContent.instance().table(entry.table_id)
			if child == null:
				continue
			for nested in child.reachable_item_ids(depth + 1, next_chain):
				if not out.has(nested):
					out.append(nested)
		elif entry.item_id != &"" and not out.has(entry.item_id):
			out.append(entry.item_id)
	return out
