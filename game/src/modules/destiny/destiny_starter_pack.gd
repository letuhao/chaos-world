class_name DestinyStarterPack
extends RefCounted

## One authored starter pack: the rows a body is handed at the moment it exists,
## before anything has been earned.
##
## ## Why this is DATA and not a grant
##
## A pack names `item_id`s. It does not mint them, resolve them against the item
## catalog, or touch an inventory — every one of those is `items`' rule and this
## module declares no dependency on it. That separation is what lets the DEFAULT
## kit and a destiny's OWN kit be described in the same shape: the pack is the
## authored answer to "what does this body begin holding", and the composition
## root turns rows into real instances through `ItemsApi.generate`.
##
## The alternative — destiny calling `ItemsApi` itself — would have needed an
## `items` edge in `registry.json` for a module whose whole subject is a
## narrative identity, and it would have made a boot-time grant reachable from
## inside the codex with no composition root in the path.
##
## ## Why `role` is authored and `as_instance` is NOT
##
## [member role] is the authored SHAPE of a kit — a weapon, armor, a consumable
## and a token — and it is what makes "the default is gone" a statement about
## four things rather than about four opaque ids.
##
## Whether a row lands as an `ItemInstance` or an `ItemStack` is **not** a field
## here. `ItemDef.stackable` already answers it and `ItemsApi.generate` already
## routes on it; a second `as_instance` flag here would be a second source of
## truth for a question the definition owns, and the two could disagree.
##
## ## Construction validates ONCE, and a refused pack does not exist
##
## [method make] is the only way to build one. A malformed row is refused by
## name rather than stored, because a pack is boot content: a row that silently
## vanished at boot is a player who opens an empty bag with nothing to select,
## which is the exact failure this type exists to close.

## The four authored roles. A pack is one of each at most, so a kit has a
## readable shape instead of a pile of ids.
const ROLE_WEAPON := &"weapon"
const ROLE_ARMOR := &"armor"
const ROLE_CONSUMABLE := &"consumable"
const ROLE_TOKEN := &"token"

const ROLES: Array[StringName] = [ROLE_WEAPON, ROLE_ARMOR, ROLE_CONSUMABLE, ROLE_TOKEN]

## Refusal reasons, named so a caller can report WHY and not just that it failed.
const REASON_NO_ID := "no_pack_id"
const REASON_NO_SOURCE := "no_source"
const REASON_NO_ROWS := "no_rows"
const REASON_BAD_ITEM := "bad_item_id"
const REASON_BAD_COUNT := "bad_count"
const REASON_BAD_ROLE := "bad_role"
const REASON_DUPLICATE_ROLE := "duplicate_role"
const REASON_DUPLICATE_ITEM := "duplicate_item_id"

## Stable identity of this pack. The default's is
## [constant DestinyStarterPacks.DEFAULT_PACK_ID]; a registered pack carries the
## destiny id it was registered under, so a read can always say WHICH kit it
## answered with.
var pack_id: StringName = &""
## What put this pack in the registry: `&"default"`, or the destiny id that
## registered it. Never empty — a pack with no source cannot be reported.
var source: StringName = &""
## The rows, one per [member role], in [constant ROLES] order so two packs read
## the same way round.
var entries: Array[Dictionary] = []


## Build a validated pack, or report why it could not be built.
##
## Returns `{ok: true, pack: DestinyStarterPack}` or `{ok: false, reason: String}`
## — the refusal carries the offending id so a content author is told which row
## to fix rather than being handed a bare `false`.
##
## Every loop below is a `for` over an array the CALLER supplied or over
## [constant ROLES], so each is bounded by its input and terminates; there is no
## `while` anywhere in this type, and `tests/arch_rules/test_no_unbounded_wait.gd`
## is the guard that keeps it that way.
static func make(pack_id: StringName, source: StringName, rows: Array) -> Dictionary:
	if pack_id == &"":
		return {"ok": false, "reason": REASON_NO_ID}
	if source == &"":
		return {"ok": false, "reason": REASON_NO_SOURCE}
	if rows.is_empty():
		return {"ok": false, "reason": REASON_NO_ROWS}
	var pack := DestinyStarterPack.new()
	pack.pack_id = pack_id
	pack.source = source
	# One pass per authored role, so the row order a caller passed cannot decide
	# the order a reader sees, and a missing role is simply absent rather than
	# sorted somewhere arbitrary.
	for role in ROLES:
		var found := -1
		for index in range(rows.size()):
			if StringName((rows[index] as Dictionary).get("role", &"")) != role:
				continue
			if found >= 0:
				return {"ok": false, "reason": REASON_DUPLICATE_ROLE, "role": String(role)}
			found = index
		if found < 0:
			continue
		var row := rows[found] as Dictionary
		var item_id := StringName(row.get("item_id", &""))
		if item_id == &"":
			return {"ok": false, "reason": REASON_BAD_ITEM, "role": String(role)}
		var count := int(row.get("count", 0))
		if count < 1:
			return {"ok": false, "reason": REASON_BAD_COUNT, "role": String(role)}
		for existing in pack.entries:
			if StringName((existing as Dictionary)["item_id"]) == item_id:
				return {"ok": false, "reason": REASON_DUPLICATE_ITEM, "item_id": String(item_id)}
		pack.entries.append({"role": String(role), "item_id": String(item_id), "count": count})
	if pack.entries.is_empty():
		return {"ok": false, "reason": REASON_NO_ROWS}
	return {"ok": true, "pack": pack}


## The `item_id` filed under `role`, or `""` when this pack carries no such row.
func item_for_role(role: StringName) -> String:
	for row in entries:
		if StringName((row as Dictionary)["role"]) == role:
			return String((row as Dictionary)["item_id"])
	return ""


## Every `item_id` in [constant ROLES] order. The shape a consumer iterates when
## it is about to mint rows.
func item_ids() -> Array[String]:
	var out: Array[String] = []
	for row in entries:
		out.append(String((row as Dictionary)["item_id"]))
	return out


## The primitives-only view. Every key is a `String` and every value is a
## primitive or an `Array` of them, so this is what a `summary()`-shaped caller
## publishes without re-deriving anything.
func to_dict() -> Dictionary:
	var rows: Array = []
	for row in entries:
		(
			rows
			. append(
				{
					"role": String((row as Dictionary)["role"]),
					"item_id": String((row as Dictionary)["item_id"]),
					"count": int((row as Dictionary)["count"]),
				}
			)
		)
	return {
		"pack_id": String(pack_id),
		"source": String(source),
		"entry_count": entries.size(),
		"entries": rows,
	}
