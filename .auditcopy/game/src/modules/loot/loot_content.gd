class_name LootContent
extends LootContentTables

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
##
## ## The split into two bases, and why this class is still every verb
##
## `max-public-methods` capped this file, and the answer is inheritance rather than
## delegation. The first pass moved the boss and domain RECORDS into
## [LootContentRecords]; the second moved the TABLE / ENCOUNTER / DEFINITION indexer
## into [LootContentTables], which extends that base. So a `LootContent` is a
## [LootContentTables] which is a [LootContentRecords], and this file keeps only what
## is genuinely ABOUT the boss -> table authority.
##
## **Inheritance, not delegation, and that is the whole reason it works.** Every verb
## is called on a `LootContent` instance — `LootContent.instance().table(id)`,
## `LootContent.new().domain_ids()` — so a collaborator plus forwarding methods would
## have left the very signatures the rule counts, one line each, which fixes nothing.
## Inheritance means every one of those names still resolves on a `LootContent`, with
## the same arguments and the same return shape. **No public method was moved off this
## class's surface, renamed, or had its signature changed** — the split is invisible to
## every caller, and `get_script_method_list()` on a `LootContent` reports the whole
## set.
##
## The constants below are all still DECLARED here, with their original values, even
## though most bodies now inherit them: `loot_validator.gd`, `loot_resolver.gd` and
## several suites read them as `LootContent.<NAME>`, and the whole `res://src` tree
## plus `res://tests` compiles against these exact spellings. A base cannot name a
## subclass's constant, so the bases carry their own copies with the same values.
##
## **Nothing was moved OFF `api.gd`.** The facade still answers the same verbs; this
## class is its content index and was before the split.
##
## Every constant this class used to declare now lives on an ancestor —
## `LootContentTables` owns the table/encounter/legacy ids and `LootContentRecords`
## owns the boss/domain dirs and the profile field lists. Redeclaring one here is a
## PARSE ERROR ("already exists in parent class"), not a shadow, which is how a
## split that duplicated the header took the whole module down (INC-0020).

## Shared index: thousands of definitions and one small content tree.
static var shared: LootContent = null


static func instance() -> LootContent:
	if shared == null:
		shared = LootContent.new()
	return shared


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
