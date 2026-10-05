class_name LootContentTables
extends LootContentRecords

## The TABLE/ENCOUNTER/DEFINITION half of [LootContent]: the authored corpus it
## indexes, the definitions it resolves, and the seeds a caller plants into them.
##
## ## Why this is a BASE CLASS rather than a sibling
##
## [LootContent] tripped `max-public-methods` at 24 instance verbs even after
## [LootContentRecords] took the record half away. Moving the indexer half into a
## plain collaborator would have left every one of those signatures on [LootContent]
## as forwarding methods — the same count the rule reads, one line each, which fixes
## nothing. So this is a BASE: `LootContent extends LootContentTables`, the indexer
## verbs live here, and a `LootContent` IS this class.
##
## ## Why it extends [LootContentRecords] rather than `RefCounted`
##
## GDScript has single inheritance, and [LootContent] already extends
## [LootContentRecords]. The two extracted halves therefore STACK: a [LootContent]
## is a [LootContentTables] which is a [LootContentRecords]. This file inherits the
## record half's verbs and — more importantly — its PRIVATE helpers, so `_text_field`,
## `_string_list` and `_tres_files` stay one copy on the tree and the indexer's own
## content reads below go through exactly the helper they always did.
##
## That is the property that makes the split free at every call site. `LootContent
## .instance().table(id)`, `LootContent.new().encounter_ids()` and `LootContent
## .new().definition(id)` are the calls they were, with the same signatures and the
## same return shapes, because inheritance carries them rather than delegation.
## Nothing in the tree had to change, and `LootContent.instance()` still answers a
## `LootContent`.
##
## ## The split is by SUBJECT, and every cache field lives on exactly one side
##
## This side owns `_tables`, `_table_ids`, `_encounters`, `_encounter_ids` and
## `_definitions`. [LootContentRecords] owns `_bosses`, `_boss_index`,
## `_boss_index_built`, `_domains` and `_seeded_domains`. Neither file reads the
## other's fields, so the two cannot half-see an index.
##
## `project_legacy` stayed on [LootContent] rather than moving here: it is the boss
## authority's own migration path, it is published as one verb, and it needs the boss
## record the record half reads. Only `TABLE_DIR` / `ENCOUNTER_DIR` /
## `LEGACY_PREFIX` — the three paths this half's own walks name — moved, and
## `LEGACY_PREFIX` moved because the body that spells `legacy:<boss_id>` is here.

const TABLE_DIR := "res://data/loot/tables/"
const ENCOUNTER_DIR := "res://data/loot/encounters/"
## Id prefix for a table produced by the legacy `BossDef.loot` projection.
const LEGACY_PREFIX := "legacy:"

var _tables: Dictionary = {}
var _table_ids: Array[String] = []
var _encounters: Dictionary = {}
var _encounter_ids: Array[String] = []
var _definitions: Dictionary = {}

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
## [method LootContent.unbanded_tables] answers "is this table payable?", so proving it can say
## no needs a table the corpus authors and no band binds — and authoring one into
## `res://data/loot/tables/` to find out is exactly the sort of change that must not
## be made to test a claim. Seed on an instance that is not [method LootContent.instance] when
## the seed is test-only, so the shared index every other caller reads is left alone.
func provide_table(table: LootTableDef) -> void:
	_remember_table(table)


# --- Band reachability ------------------------------------------------------
#
# These live HERE, not on [LootContentRecords], and that placement is load-bearing
# rather than stylistic: a base cannot name anything a subclass declares — neither
# a field nor a method — so a base whose body reads `_encounters`, `_encounter_ids`,
# `load_encounters`, `encounter_ids`, `encounter_by_id`, `table` or `table_ids`
# does not parse, and every one of them is declared on THIS side.
#
# Reading them from a base is exactly the `ItemWorkbenchReadout._drill_loop` defect
# one level up, and it cost two rounds here: the six band walks first, then
# `orphan_domains`, because the rule covers METHODS as well as fields. Godot
# reported both only from the first dependant as "Could not resolve class
# LootContentTables" and never printed a line for the file that was actually
# broken, so fixing one half left the error byte-identical.
#
# Every symbol the walks below use is declared above in this same file or inherited
# from [LootContentRecords].


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


## Table ids an authored band binds DIRECTLY, sorted: what [method
## LootContent.table_for_boss] hands the resolver for a boss the band spawns.
##
## A band is one authored tier of one encounter, so this walks exactly the bindings
## [method LootContent.table_for_boss] can read. It does not ask whether the binding's boss
## is one the encounter spawns — that is [method LootValidator]'s business to report, and a
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
## table-shaped half of [method LootContentRecords.orphan_domains] — the domain is
## unreachable content with no route to it, and so is a table — and BL-0136 filed it
## when the corpus held eight of them.
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
## visit per table so a cycle cannot make it recurse without end. `depth` is bounded by
## [constant LootContentRecords.MAX_NESTING_DEPTH], so the walk ends even if `seen`
## were emptied.
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
