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
##
## ## What is payable, and what is merely authored
##
## [method band_bound_tables] is the boundary between the two. A defeat resolves
## exactly one table — the one a band binds for the boss it spawned — so that table's
## closure is every drop a player can receive, and [method unbanded_tables] is the rest
## of the corpus: authored, shipped, and unresolvable. Both domains and tables can be
## authored with no route to them, so both are reported rather than assumed (BL-0338,
## BL-0136).

const TABLE_DIR := "res://data/loot/tables/"
const ENCOUNTER_DIR := "res://data/loot/encounters/"
const BOSS_DIR := "res://data/bosses/"
const DOMAIN_DIR := "res://data/domains/"
## Id prefix for a table produced by the legacy `BossDef.loot` projection.
const LEGACY_PREFIX := "legacy:"
## The boss profile fields `LootContent` reads off a boss record, in the order
## `CombatDamage.resolve_hit` reads them. A named list rather than a
## `BossDef` reference, so this module keeps compiling against no `world` type.
const PROFILE_FIELDS: Array[String] = [
	"crit_chance",
	"crit_damage",
	"penetration",
	"evasion",
	"damage_reduction",
]
## The authored `BossDef.affliction` field, read by the same generic `Object.get` pass as
## the profile and for the same reason: a named string rather than a `BossDef` reference,
## so `loot` still compiles against no `world` type and `tools arch` still sees no edge.
const AFFLICTION_FIELD := "affliction"
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
## Domain ids a caller seeded through [method provide_domain]. Per instance, so a test can
## seed a scratch corpus without touching the shared index.
var _seeded_domains: Array[String] = []


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


## Seed the table index with a table the caller already holds, exactly as
## [method provide] does for an item and [method provide_boss] does for a boss.
##
## [method unbanded_tables] answers "is this table payable?", so proving it can say
## no needs a table the corpus authors and no band binds — and authoring one into
## `res://data/loot/tables/` to find out is exactly the sort of change that must not
## be made to test a claim. Seed on an instance that is not [method instance] when
## the seed is test-only, so the shared index every other caller reads is left alone.
func provide_table(table: LootTableDef) -> void:
	_remember_table(table)


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


## Drop a boss [method provide_boss] added, and answer whether it was there.
##
## The inverse exists because the runner shares one process across every suite: a
## probe seeded into this shared singleton outlives the test that wrote it, and
## test_loot_payable_tables.gd audits the SHIPPED corpus -- so a probe left behind
## lands in its "no authored table is unpayable" answer and reddens a suite that
## has nothing to do with the one that seeded it. A caller that must use the
## singleton (because the read under test goes through it) pairs its `provide`
## with a `forget` in the same test.
##
## Idempotent, like [method provide_boss] refuses a duplicate: removing what is not
## there is not an error.
func forget_boss(boss_id: StringName) -> bool:
	if boss_id == &"":
		return false
	return _bosses.erase(String(boss_id))


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


## `{found, id, domain_id, loot, profile, affliction}` for a boss, read without naming its
## resource type. `loot` is the legacy flat item-id list. `profile` is the boss's authored
## striking profile — the numbers that decide HOW it fights, as opposed to the band vitality
## that decides how hard it is to kill (ADR 0076). `affliction` is the `StatusDef.id` it
## inflicts on the player, `""` for a creature authored to afflict nothing. Read
## generically, because the alternative is a `loot -> world` reference this module
## deliberately does not have.
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


## Every authored domain id under [constant DOMAIN_DIR], sorted.
##
## This is the OTHER side of [method encounter_ids], and the two together are what make an
## orphaned domain detectable at all: `LootApi.domains()` enumerates encounters only, so a
## `DomainDef` with no encounter is one no surface can offer and nothing would otherwise say
## so (BL-0338). One directory level, the same bound [method _tres_files] uses, sorted so
## content order never depends on the filesystem.
func domain_ids() -> Array[String]:
	var out: Array[String] = []
	for path in _tres_files(DOMAIN_DIR):
		var id := _text_field(load(path) as Resource, "id")
		if not id.is_empty() and not out.has(id):
			out.append(id)
	for id in _seeded_domains:
		if not out.has(id):
			out.append(id)
	out.sort()
	return out


## Seed the domain index with an id the caller already knows, exactly as [method provide]
## does for an item and [method provide_boss] does for a boss.
##
## `domain_ids()` is a directory walk, so without this a domain that exists only in a live
## world — or in a caller that has already resolved it — would be invisible to
## [method orphan_domains], which is BL-0338's defect one level down. A seeded id is a
## domain the content authors, and [method orphan_domains] then answers the only question
## that matters about it: does any encounter host it?
##
## Seed on an instance that is not [method instance] when the seed is test-only, so the
## shared index every other caller reads is left alone.
func provide_domain(domain_id: StringName) -> void:
	var key := String(domain_id)
	if key.is_empty() or _seeded_domains.has(key):
		return
	_seeded_domains.append(key)
	_seeded_domains.sort()


## Domains a player cannot reach: authored, and with no `LootEncounterDef` to enter.
##
## Reported rather than swallowed, so a domain dropped into the corpus without an encounter
## fails the content gate instead of sitting there invisible.
func orphan_domains() -> Array[String]:
	var hosted := {}
	for encounter_id in encounter_ids():
		var encounter := encounter_by_id(StringName(encounter_id))
		if encounter != null:
			hosted[String(encounter.domain_id)] = true
	var out: Array[String] = []
	for domain_id in domain_ids():
		if not hosted.has(domain_id):
			out.append(domain_id)
	return out


# --- Payable content --------------------------------------------------------


## Table ids an authored band binds DIRECTLY, sorted: what [method table_for_boss]
## hands the resolver for a boss the band spawns.
##
## A band is one authored tier of one encounter, so this walks exactly the bindings
## [method table_for_boss] can read. It does not ask whether the binding's boss is one
## the encounter spawns — that is [method LootValidator]'s business to report, and a
## binding the encounter does not list is a defect in its own right rather than a
## reason to hide the table here.
func bound_table_ids() -> Array[String]:
	load_encounters()
	var out: Array[String] = []
	for encounter_id in _encounter_ids:
		var encounter := _encounters[encounter_id] as LootEncounterDef
		if encounter == null:
			continue
		for tier in encounter.tiers:
			if tier == null:
				continue
			for table_id in tier.table_ids():
				if table_id != &"" and not out.has(String(table_id)):
					out.append(String(table_id))
	out.sort()
	return out


## Every table a defeat can resolve: those a band binds, plus everything nested
## inside them.
##
## This is the whole reachable surface of the table corpus, and the boundary that
## makes [method unbanded_tables] meaningful — a table outside it is authored content
## nothing in the game can pay (BL-0136). The ceiling is [constant
## MAX_NESTING_DEPTH], the same depth [method LootResolver] resolves to: past it a
## chain is already dropped with a `nesting_depth_exceeded` warning, so counting it
## reachable here would overstate what a player can obtain.
func band_bound_tables() -> Array[String]:
	var seen: Dictionary = {}
	for root in bound_table_ids():
		_collect(root, seen, 0)
	var out: Array[String] = []
	for table_id in seen.keys():
		out.append(String(table_id))
	out.sort()
	return out


## Authored tables no authored band can pay, sorted.
##
## ## The defect this reports
##
## A table in this list is content the game ships and nothing can resolve: no tier
## binds it and no table nests it, so `LootContent.table_for_boss` never returns it
## and every item it carries is an item a player can never obtain. That is the
## table-shaped half of [method orphan_domains] — the domain is unreachable content
## with no route to it, and so is a table — and BL-0136 filed it when the corpus held
## eight of them.
##
## Reported rather than swallowed: the count is small enough that a content wave can
## finish the corpus, but nothing about authoring a table warns an author that no band
## will ever pay for it.
func unbanded_tables() -> Array[String]:
	var paid := {}
	for table_id in band_bound_tables():
		paid[table_id] = true
	var out: Array[String] = []
	for table_id in table_ids():
		if not paid.has(table_id):
			out.append(table_id)
	return out


## Every item id a defeat can deliver: the union over the band-bound closure.
##
## Keyed by id and accumulated through a table-visited set, so the walk is bounded by
## the table count rather than by the path count — the same reason [method _collect]
## carries one.
func band_reachable_item_ids() -> Array[StringName]:
	var out: Dictionary = {}
	for table_id in band_bound_tables():
		_collect_items(StringName(table_id), out, 0, {})
	var ids: Array[StringName] = []
	for item_id in out.keys():
		ids.append(StringName(item_id))
	ids.sort()
	return ids


## The walk behind [method band_bound_tables]: depth-first, `seen` keeping it to one
## visit per table so a cycle cannot make it recurse without end.
func _collect(table_id: String, seen: Dictionary, depth: int) -> void:
	if depth > MAX_NESTING_DEPTH or seen.has(table_id):
		return
	var found := table(StringName(table_id))
	if found == null:
		return
	seen[table_id] = true
	for entry in found.entries:
		if entry != null and entry.is_nested() and entry.table_id != &"":
			_collect(String(entry.table_id), seen, depth + 1)


## [method band_reachable_item_ids]'s walk. `chain` is the path being walked, so a
## reference back onto it stops rather than descending; `depth` is the second ceiling
## for a chain that is long rather than cyclic.
func _collect_items(table_id: StringName, out: Dictionary, depth: int, chain: Dictionary) -> void:
	var key := String(table_id)
	if depth > MAX_NESTING_DEPTH or chain.has(key):
		return
	var found := table(table_id)
	if found == null:
		return
	var next_chain := chain.duplicate()
	next_chain[key] = true
	for entry in found.entries:
		if entry == null:
			continue
		if entry.is_nested():
			if entry.table_id != &"":
				_collect_items(entry.table_id, out, depth + 1, next_chain)
		elif entry.item_id != &"" and not out.has(String(entry.item_id)):
			out[String(entry.item_id)] = true


func _read_record(directory: String, key: String) -> Dictionary:
	var path := key
	if not directory.is_empty():
		path = "%s%s.tres" % [directory, key]
	var missing := {
		"found": false,
		"id": key,
		"domain_id": "",
		"boss_ids": [],
		"loot": [],
		"profile": {},
		"affliction": "",
	}
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
		# A field the resource does not declare reads as `null` here, so an older
		# `BossDef` without a profile yields an empty one rather than a zeroed one full of
		# keys that were never authored. `LootState` decides what an empty profile means.
		"profile": _boss_profile(resource),
		# Same shape for the affliction: a record that declares none reads as `""`, which
		# is the whole corpus as it stood before this field existed, so adding it changed
		# no boss's behaviour until a `.tres` named an id.
		"affliction": _boss_affliction(resource),
	}


## The `StatusDef.id` a boss record inflicts on the player, or `""` when it names none.
##
## An `Object.get` read for the reason [method _boss_profile] is one, and the same
## `Variant` discipline applies: `StringName` and `String` both read cleanly, and a
## resource with no such field answers `null` rather than the string "Null". Nothing is
## validated here — whether the id names a real def is `LootAffliction`'s question, and
## refusing it there keeps this module free of any `status` vocabulary it would then have
## to keep in step with.
static func _boss_affliction(resource: Resource) -> String:
	if resource == null:
		return ""
	return _text_field(resource, AFFLICTION_FIELD)


## The authored striking profile of a boss record, or `{}` when the record declares none.
##
## Read field by field with [method _float_field] rather than by calling the resource's
## own projection, so this stays a `Object.get` read and `loot` still names no `world`
## type. Every authored value is clamped into the range `CombatDamage` works in, so a
## hand-edited `.tres` cannot hand the combat model a number it does not already bound.
static func _boss_profile(resource: Resource) -> Dictionary:
	if resource == null:
		return {}
	var declared := false
	var profile: Dictionary = {}
	for field in PROFILE_FIELDS:
		var value = resource.get(field)
		if value == null:
			continue
		declared = true
		var number := float(value)
		match String(field):
			"crit_chance", "evasion":
				profile[field] = clampf(number, 0.0, 1.0)
			"damage_reduction":
				profile[field] = clampf(number, 0.0, 1.0)
			"crit_damage":
				profile[field] = maxf(0.0, number)
			_:
				profile[field] = maxf(0.0, number)
	if not declared:
		return {}
	return profile


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
