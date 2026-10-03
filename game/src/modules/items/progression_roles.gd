class_name ProgressionRoles
extends RefCounted

## The authored rule for which items are REQUIRED PROGRESSION INPUTS: an item a
## cultivation path names in its realm seed and the path itself consumes.
##
## The rule is CONTENT, not code, for the same reason `ItemSlots` is: the authored
## data says what an item is FOR, and code only reads it. A breakthrough pill and
## an ordinary healing draught are both `subcategory = pill`, both `consumable`,
## both carrying a `restore_health` option — nothing structural separates them, so
## no structural rule can. What separates them is that a realm seed names the pill
## as the price of an attempt and the path is the only thing allowed to spend it.
## That fact is authored, so it is authored here: one row per item, one JSON file,
## and adding a realm adds a row instead of editing a conditional.
##
## ## Why the inventory's Use verb must refuse these
##
## `ItemsApi.use_item` spends a unit and applies a generic one-shot effect. On a
## progression pill that heals a pool the pill was never for and deletes the only
## copy of the thing the player needs to advance (BL-0110). A button that
## decrements a number is not acquisition. So the refusal is here, at the point
## the item is about to be destroyed, and it carries the role so a caller can say
## WHICH path the item belongs to instead of only "no".
##
## ## Why this is not a hardcoded id list in code
##
## The difference is not cosmetic. A `if def_id == "..."` chain is invisible to
## content tooling, cannot be reviewed as one table, and grows a branch per realm;
## this table is one reviewed file whose every row is cross-checked against the
## realm seeds by `tests/modules/items/test_progression_roles.gd`, in BOTH
## directions — so a progression input can never go unruled, and a role can never
## be invented for an item no seed names.
##
## ## Reading it
##
## The table is authored content and never actor state, so it needs no
## serialization: it is identical before and after a save, which is exactly why a
## restored bag of pills is refused by exactly the same verb that refused it before.

## Authored content. Keyed by item id, never by subtype: `pill` holds both the
## progression pills and the ordinary draughts, so a subtype-keyed rule would
## either gate everything or nothing.
const TABLE_PATH := "res://data/items/progression_roles.json"
## Bumped when the shape changes. A table of another version is refused rather
## than read as an empty rule, which would silently un-rule every progression
## input and reopen BL-0110.
const TABLE_VERSION := 1

static var _table: Dictionary = {}
static var _loaded: bool = false


## The role `def_id` serves, or `&""` when the rule has nothing to say about it.
## An unruled item is an ordinary item the inventory may spend.
static func role_of(def_id: StringName) -> StringName:
	if def_id == &"":
		return &""
	return StringName((_load()["roles"] as Dictionary).get(String(def_id), ""))


## Whether `def_id` is a required progression input, and therefore never spendable
## from the inventory. The whole gate in one question.
static func is_progression_input(def_id: StringName) -> bool:
	return role_of(def_id) != &""


## Every ruled id, sorted. Read by the content suite, which cross-checks the table
## against the realm seeds; never by gameplay, which asks about one id at a time.
static func ruled_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for def_id in (_load()["roles"] as Dictionary).keys():
		out.append(StringName(def_id))
	out.sort()
	return out


## Drop the cached table. A suite that wants to observe a load failure installs a
## missing or malformed table and asks for the answer rather than inheriting a
## table a previous read already accepted.
static func reset() -> void:
	_table = {}
	_loaded = false


static func _load() -> Dictionary:
	if not _loaded:
		_loaded = true
		_table = _read()
	return _table


static func _read() -> Dictionary:
	if not FileAccess.file_exists(TABLE_PATH):
		push_error("ProgressionRoles: progression role table missing at %s" % TABLE_PATH)
		return {"roles": {}}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(TABLE_PATH)) != OK or not json.data is Dictionary:
		push_error(
			"ProgressionRoles: progression role table at %s is not a JSON object" % TABLE_PATH
		)
		return {"roles": {}}
	var data: Dictionary = json.data
	if int(data.get("version", 0)) != TABLE_VERSION:
		push_error(
			(
				"ProgressionRoles: progression role table version %s is not %d"
				% [str(data.get("version", "<none>")), TABLE_VERSION]
			)
		)
		return {"roles": {}}
	var roles := {}
	for def_id in data.get("roles", {}) as Dictionary:
		var role := String((data["roles"] as Dictionary)[def_id])
		if role.is_empty():
			push_error("ProgressionRoles: item '%s' names no role; the row is dead" % def_id)
			continue
		if roles.has(String(def_id)):
			push_error("ProgressionRoles: item '%s' is ruled twice" % def_id)
			continue
		roles[String(def_id)] = role
	return {"roles": roles}
