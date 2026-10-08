class_name ChestDef
extends Resource

## An authored reward bundle — a chest, a cache, a prize box (BL-0053 / DEF-0023).
##
## ## Why a chest is content and not code
##
## A quest, an event or a mod that wants to pay "a bundle of items" should not hardcode
## a list in GDScript: that is the "content as code" failure the repo refuses. A chest is
## a `.tres` naming item ids and weights, and [ItemsApi.open_chest] realizes it. The same
## shape serves a quest reward, a boss cache and a mod's own loot, so nothing has to be
## refactored when a second caller appears.
##
## ## Deterministic, never a live roll
##
## Opening takes a `seed_value`, exactly like [method ItemsApi.generate] and
## `ShopDef.stock_seed`. Two opens with the same seed yield the same bundle, which is what
## makes a reward auditable and a test stable (ADR 0025: no delivery path reads an unseeded
## RNG).
##
## ## Rows and guarantees are different claims
##
## `rows` is a WEIGHTED pool the open draws from; `guaranteed` is a list always delivered.
## A chest that wants "one of three weapons, and always the sigil" authors both. An empty
## pool with guarantees is legal — a fixed bundle — and the two lists are never merged,
## because "you might get this" and "you will get this" are different promises.

## The stable id a caller names. Unique across the chest catalog.
@export var id: StringName = &""

## What the player sees when the chest is named.
@export var display_name: String = ""

## How many rows to DRAW from [member rows]. Zero (with an empty [member rows]) means the
## chest is guarantee-only. Each draw is a separate weighted pick, so a chest may pay the
## same item twice — a stack of two pills is a legitimate bundle.
@export var rolls: int = 1

## The weighted pool, each `{item_id: StringName, weight: int}`. A weight below 1 is a
## typo and is normalized to 1 at open time rather than silently drawing nothing.
@export var rows: Array[Dictionary] = []

## Item ids always delivered, in authored order, ones each. A guaranteed id the catalog
## does not define is refused by name at open, never dropped.
@export var guaranteed: Array[StringName] = []


## Whether this def can be opened at all. A chest with no id, no name, or nothing to pay
## is an authoring error, not an empty prize.
func valid() -> bool:
	if id == &"" or display_name == "":
		return false
	return rolls > 0 and not rows.is_empty() or not guaranteed.is_empty()


## The summed weight of [member rows], with each row floored to weight 1. Zero when the
## pool is empty.
func total_weight() -> int:
	var total := 0
	for row in rows:
		total += maxi(1, int((row as Dictionary).get("weight", 1)))
	return total


## Every item id this chest can pay, pool and guarantees alike, de-duplicated in
## authored order. A content guard resolves each against the item catalog so a typo is a
## build failure rather than a silently empty draw.
func item_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for row in rows:
		var item_id := StringName((row as Dictionary).get("item_id", ""))
		if item_id != &"" and not out.has(item_id):
			out.append(item_id)
	for item_id in guaranteed:
		if item_id != &"" and not out.has(item_id):
			out.append(item_id)
	return out


## Every authoring complaint that must stop this def from reaching play, one line each.
func problems() -> Array[String]:
	var out: Array[String] = []
	if id == &"":
		out.append("chest has no id")
	if display_name == "":
		out.append("%s has no display_name" % String(id))
	if rolls < 0:
		out.append(
			"%s authors %d rolls; a chest cannot draw a negative number" % [String(id), rolls]
		)
	if rolls > 0 and rows.is_empty():
		out.append("%s draws %d rolls from an empty pool" % [String(id), rolls])
	for row in rows:
		if StringName((row as Dictionary).get("item_id", "")) == &"":
			out.append("%s has a pool row naming no item_id" % String(id))
	for item_id in guaranteed:
		if item_id == &"":
			out.append("%s has an empty guaranteed entry" % String(id))
	if not valid():
		out.append("%s pays nothing at all" % String(id))
	return out
