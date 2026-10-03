class_name LootContent
extends RefCounted

## Content index for the loot namespace, plus the **single** place a boss's loot
## table is resolved.
##
## ## One authority, one resolver
##
## [method table_for_boss] is the only function in the game that answers "what
## does this boss drop". It has exactly two inputs and it picks between them once:
##
## 1. An authored binding. A `LootTier.boss_tables` entry names this boss and a
##    table under `res://data/loot/tables/`. When one exists it is authoritative.
## 2. The legacy migration. A boss authored before loot tables carried a flat
##    item-id list on `BossDef.loot`. That list is *projected* into an implicit
##    table by [method project_legacy], deterministically and once, and cached
##    under a `legacy:<boss_id>` id.
##
## There is no runtime path that reads both, and [method LootValidator] rejects
## content where both are populated for the same boss — so the two can never
## disagree. Boss and domain records are read through `Object.get`, so this module
## compiles against no `world` type and declares no dependency on it.

const TABLE_DIR := "res://data/loot/tables/"
const ENCOUNTER_DIR := "res://data/loot/encounters/"
const BOSS_DIR := "res://data/bosses/"
const DOMAIN_DIR := "res://data/domains/"
## Id prefix for a table produced by the legacy `BossDef.loot` projection.
const LEGACY_PREFIX := "legacy:"
## Depth ceiling for nested table references.
const MAX_NESTING_DEPTH := 4

## Shared index: thousands of definitions and one small content tree.
static var shared: LootContent = null

var _tables: Dictionary = {}
var _table_ids: Array[String] = []
var _encounters: Dictionary = {}
var _encounter_ids: Array[String] = []
var _definitions: Dictionary = {}
var _bosses: Dictionary = {}
var _boss_index: Dictionary = {}
var _boss_index_built: bool = false
var _domains: Dictionary = {}


static func instance() -> LootContent:
	if shared == null:
		shared = LootContent.new()
	return shared


# --- Tables -----------------------------------------------------------------


## Load every authored table under [constant TABLE_DIR], keyed and sorted by id.
## Idempotent; a content file named after its id loads directly, anything else is
## found by reading the declared id.
func load_tables() -> void:
	for path in _tres_files(TABLE_DIR):
		var table = load(path)
		if table == null:
			continue
		_remember_table(table)


func _remember_table(table: Resource) -> void:
	if table == null:
		return
	var key := _text_field(table, "id")
	if key.is_empty() or _tables.has(key):
		return
	_tables[key] = table
	_table_ids.append(key)
	_table_ids.sort()


func table(table_id: StringName) -> LootTableDef:
	if table_id == &"":
		return null
	var key := String(table_id)
	if _tables.has(key):
		return _tables[key]
	var direct := "%s%s.tres" % [TABLE_DIR, key]
	if ResourceLoader.exists(direct):
		var loaded = load(direct)
		_remember_table(loaded)
		return _tables.get(key, null) as LootTableDef
	load_tables()
	return _tables.get(key, null) as LootTableDef


func table_ids() -> Array[String]:
	load_tables()
	return _table_ids.duplicate()


# --- Encounters -------------------------------------------------------------


## Load every authored encounter under [constant ENCOUNTER_DIR].
func load_encounters() -> void:
	for path in _tres_files(ENCOUNTER_DIR):
		var encounter = load(path)
		if encounter == null:
			continue
		var key := _text_field(encounter, "id")
		if key.is_empty() or _encounters.has(key):
			continue
		_encounters[key] = encounter
		_encounter_ids.append(key)
		_encounter_ids.sort()


func encounter_by_id(encounter_id: StringName) -> LootEncounterDef:
	if encounter_id == &"":
		return null
	var key := String(encounter_id)
	if not _encounters.has(key):
		load_encounters()
	return _encounters.get(key, null) as LootEncounterDef


## The encounter that hosts `domain_id`, or null.
func encounter_for_domain(domain_id: StringName) -> LootEncounterDef:
	if domain_id == &"":
		return null
	load_encounters()
	for encounter_id in _encounter_ids:
		var encounter := _encounters[encounter_id] as LootEncounterDef
		if encounter != null and encounter.domain_id == domain_id:
			return encounter
	return null


func encounter_ids() -> Array[String]:
	load_encounters()
	return _encounter_ids.duplicate()


# --- Definitions ------------------------------------------------------------


## An `ItemDef` by id, memoized. The lookup itself is the items module's single
## stable-id resolver; this only caches it, because a resolve touches several
## entries per draw and the content tree is walked on a miss.
func definition(item_id: StringName) -> ItemDef:
	if item_id == &"":
		return null
	var key := String(item_id)
	if _definitions.has(key):
		return _definitions[key] as ItemDef
	var def := Crafting.resolve(item_id)
	if def != null:
		_definitions[key] = def
	return def


## Seed the index with a definition the caller already holds — an inventory's live
## reference, or an item realized for a placed drop. Resolution still goes through
## the items module; this only avoids a second content read, and it lets a
## definition that is not in the content tree (an item a caller minted) be dropped
## like any other.
func provide(item_id: StringName, def: ItemDef) -> void:
	if item_id == &"" or def == null:
		return
	_definitions[String(item_id)] = def


## Seed the boss index with a record the caller already holds, exactly as
## [method provide] does for an item.
##
## The legacy `BossDef.loot` projection is a migration path with **no live content**:
## every shipped boss carries an empty `loot` array and is bound to an authored table
## instead, so there is no shipped boss whose projection could be observed. Without a
## seam the only honest way to prove the projection would be to reintroduce a second
## loot authority into the content tree — which is precisely the hazard the validator
## exists to refuse. So a caller authors the probe the projection needs.
func provide_boss(boss_id: StringName, record: Dictionary) -> void:
	if boss_id == &"" or not bool(record.get("found", false)):
		return
	_bosses[String(boss_id)] = record


# --- The single boss -> table authority -------------------------------------


## The table `boss_id` drops from at `tier_index`. Prefers an authored binding and
## otherwise projects the legacy `BossDef.loot` list. See the class docs.
func table_for_boss(boss_id: StringName, tier_index: int = 0) -> LootTableDef:
	if boss_id == &"":
		return null
	load_encounters()
	for encounter_id in _encounter_ids:
		var encounter := _encounters[encounter_id] as LootEncounterDef
		if encounter == null:
			continue
		var tier := encounter.tier_at(tier_index)
		if tier == null:
			continue
		var table_id := tier.table_for(boss_id)
		if table_id == &"":
			continue
		var authored := table(table_id)
		if authored != null:
			return authored
	var legacy := project_legacy(boss_id, boss_record(boss_id).get("loot", []))
	_tables[String(legacy.id)] = legacy
	if not _table_ids.has(String(legacy.id)):
		_table_ids.append(String(legacy.id))
		_table_ids.sort()
	return legacy


## The implicit table a legacy `BossDef.loot` item list projects into: one
## uniform-weight item entry per id, a single draw, and `allow_empty = true` so a
## boss whose authored list is empty genuinely drops nothing.
func project_legacy(boss_id: StringName, item_ids: Array) -> LootTableDef:
	var table := LootTableDef.new()
	table.id = StringName(LEGACY_PREFIX + String(boss_id))
	table.display_name = "Legacy projection of %s" % String(boss_id)
	table.rolls = 1
	table.rolls_max = 1
	table.allow_empty = true
	var seen: Dictionary = {}
	for raw in item_ids:
		var item_id := StringName(raw)
		if item_id == &"" or seen.has(String(item_id)):
			continue
		seen[String(item_id)] = true
		var entry := LootEntry.new()
		entry.id = StringName("legacy_%s_%d" % [String(boss_id), table.entries.size()])
		entry.kind = LootEntry.KIND_ITEM
		entry.item_id = item_id
		entry.weight = 1.0
		table.entries.append(entry)
	return table


## Whether an authored binding exists for `boss_id` at any tier. Used by the
## validator to detect the two-authority conflict.
func has_authored_table(boss_id: StringName) -> bool:
	load_encounters()
	for encounter_id in _encounter_ids:
		var encounter := _encounters[encounter_id] as LootEncounterDef
		if encounter == null:
			continue
		for tier in encounter.tiers:
			if tier != null and tier.table_for(boss_id) != &"":
				return true
	return false


# --- Boss / domain content records ------------------------------------------


## `{found, id, domain_id, loot}` for a boss, read without naming its resource
## type. `loot` is the legacy flat item-id list.
func boss_record(boss_id: StringName) -> Dictionary:
	var key := String(boss_id)
	if _bosses.has(key):
		return _bosses[key]
	var record := _read_record(BOSS_DIR, key)
	if not bool(record.get("found", false)):
		_build_boss_index()
		var path: String = _boss_index.get(key, "")
		if not path.is_empty():
			record = _read_record("", path)
	_bosses[key] = record
	return record


## `{found, id, boss_ids}` for a domain, read without naming its resource type.
func domain_record(domain_id: StringName) -> Dictionary:
	var key := String(domain_id)
	if _domains.has(key):
		return _domains[key]
	var direct := "%s%s.tres" % [DOMAIN_DIR, key]
	var record := (
		_read_record(DOMAIN_DIR, key) if ResourceLoader.exists(direct) else {"found": false}
	)
	_domains[key] = record
	return record


func _read_record(directory: String, key: String) -> Dictionary:
	var path := key
	if not directory.is_empty():
		path = "%s%s.tres" % [directory, key]
	var missing := {"found": false, "id": key, "domain_id": "", "boss_ids": [], "loot": []}
	if not ResourceLoader.exists(path):
		return missing
	var resource = load(path)
	if resource == null:
		return missing
	return {
		"found": true,
		"id": _text_field(resource, "id", key),
		"domain_id": _text_field(resource, "domain_id"),
		"boss_ids": _string_list(resource.get("boss_ids")),
		"loot": _string_list(resource.get("loot")),
	}


func _build_boss_index() -> void:
	if _boss_index_built:
		return
	_boss_index_built = true
	for path in _tres_files(BOSS_DIR):
		var record := _read_record("", path)
		if bool(record.get("found", false)):
			_boss_index[String(record["id"])] = path


# --- Shared helpers ---------------------------------------------------------


## A string-ish field read off a content resource without naming its type. A
## `StringName` and a `String` both read cleanly, and a field the resource does not
## declare reads as empty rather than as the string "Null".
static func _text_field(resource: Resource, field: String, fallback: String = "") -> String:
	if resource == null:
		return fallback
	var value = resource.get(field)
	if value == null:
		return fallback
	return String(value)


static func _string_list(value) -> Array[String]:
	var out: Array[String] = []
	if not value is Array:
		return out
	for entry in value:
		out.append(String(entry))
	return out


## Every `.tres` directly inside `directory`, sorted, so content loading order
## never depends on the filesystem.
static func _tres_files(directory: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(".tres"):
			out.append(directory + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
