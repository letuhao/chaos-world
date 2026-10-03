class_name ItemSlots
extends RefCounted

## The authored rule for which wearable slots an equipment subtype may occupy.
##
## The rule is CONTENT, not code: `res://data/items/equipment_slots.json` is the
## one place a subtype's slots are decided, and this class only reads it. It used
## to be a `const` dictionary naming four subtypes, which left the 488 authored
## equipment items whose subtype it did not name with no ruling at all — so a
## pair of greaves fit the weapon slot, and a socket gem could be worn outright.
## Content authors subtypes, so content decides where they go: adding a subtype
## means adding a row, not editing code.
##
## Three states, and they are not interchangeable:
##
##   - **named with slots** — a real constraint. [method for_subtype] returns it
##     and `equip` refuses every other slot.
##   - **named under `unwearable`** — the subtype occupies no wearable slot. It
##     is socket material, not something a body wears, so `equip` refuses it in
##     every slot. `for_subtype` answers `[]`, the same as an unruled subtype, so
##     the two are told apart by [method is_wearable] and not by array shape.
##   - **absent** — the rule has no opinion and the subtype is wearable anywhere.
##     Deliberately permissive, so a newly authored subtype is never accidentally
##     unequippable, but nothing shipped may rely on it: the content suite asserts
##     every authored equipment subtype is ruled one way or the other.

## Authored content. Keyed by subtype, never by slot index or item id, so a
## subtype's ruling is one edit for every item that uses it.
const TABLE_PATH := "res://data/items/equipment_slots.json"
## Bumped when the shape changes. A table of another version is refused rather
## than read as an empty rule, which would silently unrul every subtype.
const TABLE_VERSION := 1

static var _table: Dictionary = {}
static var _loaded: bool = false


## The wearable slots `subtype` may occupy. Empty means the rule has nothing to
## say: either the subtype is unruled or it is authored as unwearable. Ask
## [method is_wearable] to tell those apart.
static func for_subtype(subtype: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for slot in _load().get("by_subtype", {}).get(String(subtype), []):
		out.append(StringName(slot))
	return out


## Whether a body may wear `subtype` at all. False only for a subtype authored
## under `unwearable`; an unruled subtype stays wearable, which is the permissive
## default this rule has always had.
static func is_wearable(subtype: StringName) -> bool:
	return not (_load()["unwearable"] as Dictionary).has(String(subtype))


## Whether the rule says anything at all about `subtype`. False means the
## permissive fallback is doing the work, which no shipped item is allowed to need.
static func is_ruled(subtype: StringName) -> bool:
	var name := String(subtype)
	return (
		(_load()["by_subtype"] as Dictionary).has(name)
		or (_load()["unwearable"] as Dictionary).has(name)
	)


static func _load() -> Dictionary:
	if not _loaded:
		_loaded = true
		_table = _read()
	return _table


static func _read() -> Dictionary:
	if not FileAccess.file_exists(TABLE_PATH):
		push_error("ItemSlots: equipment slot table missing at %s" % TABLE_PATH)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(TABLE_PATH)) != OK or not json.data is Dictionary:
		push_error("ItemSlots: equipment slot table at %s is not a JSON object" % TABLE_PATH)
		return {}
	var data: Dictionary = json.data
	if int(data.get("version", 0)) != TABLE_VERSION:
		push_error(
			(
				"ItemSlots: equipment slot table version %s is not %d"
				% [str(data.get("version", "<none>")), TABLE_VERSION]
			)
		)
		return {}
	var named := {}
	for subtype in data.get("by_subtype", {}) as Dictionary:
		var slots: Array = (data["by_subtype"] as Dictionary)[subtype]
		if slots.is_empty():
			push_error(
				"ItemSlots: subtype '%s' lists no slot; name it under `unwearable`" % subtype
			)
			continue
		named[String(subtype)] = slots
	var denied := {}
	for subtype in data.get("unwearable", []):
		if named.has(String(subtype)):
			push_error("ItemSlots: subtype '%s' is ruled both wearable and unwearable" % subtype)
			continue
		denied[String(subtype)] = true
	return {"by_subtype": named, "unwearable": denied}
