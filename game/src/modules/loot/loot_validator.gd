class_name LootValidator
extends RefCounted

## Validation for the loot namespace. Everything here is content-shaped: it
## answers "would this table/encounter behave the way it reads?", never "is this
## number fun".
##
## Checked:
##  - every table and encounter id is unique and non-empty;
##  - every referenced item, table, boss and domain id resolves;
##  - no cyclic table references, and no chain past the nesting limit;
##  - weights are finite and positive where they are read, and the weighted pool
##    sums above zero wherever the table needs it;
##  - `chance` stays inside 0.0..1.0 and a guaranteed entry declares none;
##  - quantity and draw ranges are satisfiable (`min <= max`, both non-negative);
##  - a table that declares `allow_empty = false` can actually produce something;
##  - realm ids are canonical ladder ids and rarity ids are known;
##  - every boss of an encounter is bound exactly once per tier, and its band
##    names a table that resolves;
##  - the boss/domain `.tres` back-references agree with the encounter, so the
##    content audit's own boss<->domain consistency holds for this content too;
##  - a boss never has two loot authorities: an authored binding and a populated
##    legacy `BossDef.loot` array at the same time is an error;
##  - a unique-route item is reachable only from the boss it names.

const SCOPE_ALL := ""
const SCOPE_TABLES := "tables"
const SCOPE_ENCOUNTERS := "encounters"
const SCOPE_DOMAINS := "domains"


## Validate the authored content tree. `scope` is "" (everything), `tables` or
## `encounters`. Returns one message per problem; empty means clean.
static func validate(scope: String = SCOPE_ALL) -> Array[String]:
	var problems: Array[String] = []
	if scope == SCOPE_ALL or scope == SCOPE_TABLES:
		var content := LootContent.instance()
		var tables: Array = []
		for table_id in content.table_ids():
			var table := content.table(StringName(table_id))
			if table != null:
				tables.append(table)
		problems.append_array(validate_tables(tables))
	if scope == SCOPE_ALL or scope == SCOPE_ENCOUNTERS:
		problems.append_array(validate_encounters(LootContent.instance()))
	if scope == SCOPE_ALL or scope == SCOPE_DOMAINS:
		problems.append_array(validate_domains(LootContent.instance()))
	return problems


## Every authored domain a player cannot enter, named.
##
## `LootApi.domains()` enumerates encounters, so the set of enterable domains is exactly the
## set of authored encounters and nothing else. A `DomainDef` with no encounter is therefore
## invisible: no surface offers it, and `enter_domain` answers `unknown_domain` — which is a
## lie, because the domain exists. That was true of 128 domains when BL-0338 was filed; they
## all carry encounters now, so this check is here to keep the class of defect loud rather
## than to re-report a fixed one.
static func validate_domains(content: LootContent) -> Array[String]:
	var problems: Array[String] = []
	for domain_id in content.orphan_domains():
		(
			problems
			. append(
				(
					(
						"domain %s: authored with no encounter, so no surface offers it and enter_domain"
						% domain_id
					)
					+ " answers unknown_domain for a domain that exists"
				)
			)
		)
	return problems


## Validate a caller-supplied set of tables, which is what lets a test prove that
## a cyclic table is rejected without authoring a cycle into the content tree.
static func validate_tables(tables: Array) -> Array[String]:
	var problems: Array[String] = []
	var by_id: Dictionary = {}
	for table in tables:
		var table_id := String((table as LootTableDef).id)
		if table_id.is_empty():
			problems.append("table: has no id")
			continue
		if by_id.has(table_id):
			problems.append("table %s: duplicate id" % table_id)
			continue
		by_id[table_id] = table
	for table_id in by_id.keys():
		problems.append_array(_table_problems(by_id[table_id], by_id))
	problems.append_array(_cycles(by_id))
	problems.append_array(_route_problems(by_id))
	return problems


static func _table_problems(table: LootTableDef, by_id: Dictionary) -> Array[String]:
	var table_id := String(table.id)
	var problems: Array[String] = []
	# --- counts
	if table.rolls < 0:
		problems.append("table %s: rolls is negative (%d)" % [table_id, table.rolls])
	if table.rolls_max < 0:
		problems.append("table %s: rolls_max is negative (%d)" % [table_id, table.rolls_max])
	if table.rolls_max > 0 and table.rolls_max < table.rolls:
		problems.append(
			(
				"table %s: draw range is unsatisfiable (rolls %d > rolls_max %d)"
				% [table_id, table.rolls, table.rolls_max]
			)
		)
	# --- context
	if table.realm != &"" and not _is_canonical_realm(table.realm):
		problems.append(
			"table %s: realm '%s' is not on the canonical ladder" % [table_id, String(table.realm)]
		)
	if table.rarity != &"" and not ItemRarity.is_valid(table.rarity):
		problems.append(
			"table %s: rarity '%s' is not a known rarity" % [table_id, String(table.rarity)]
		)
	# --- entries
	if table.entries.is_empty():
		problems.append("table %s: has no entries" % table_id)
	var seen: Dictionary = {}
	var weight_total := 0.0
	var producing := 0
	for index in table.entries.size():
		var entry := table.entries[index]
		if entry == null:
			problems.append("table %s: entry %d is null" % [table_id, index])
			continue
		var entry_id := String(entry.id)
		if entry_id.is_empty():
			problems.append("table %s: entry %d has no id" % [table_id, index])
		elif seen.has(entry_id):
			problems.append("table %s: duplicate entry id '%s'" % [table_id, entry_id])
		else:
			seen[entry_id] = true
		problems.append_array(_entry_problems(table_id, entry, by_id))
		# A nested entry competes in the weighted pool exactly like an item entry,
		# so its weight counts toward what the draw range can actually pick from.
		if entry.is_weighted() and entry.weight > 0.0:
			weight_total += entry.weight
		if entry.is_nested() or entry.item_id == &"":
			continue
		# A route-limited item still counts as producing; the dedicated route
		# check below reports whether its own boss can actually reach it.
		if (
			entry.guaranteed
			or (entry.is_independent() and entry.chance > 0.0)
			or (entry.is_weighted() and entry.weight > 0.0)
		):
			producing += 1
	# --- satisfiability
	# `allow_empty = false` is a promise the resolver has to be able to keep, and
	# it can only keep it from a deterministic source: a guaranteed entry, or a
	# weighted pool to draw from. Independent chance entries can all miss, so a
	# table built only from them would silently come up empty.
	if not table.allow_empty and table.guaranteed_entries().is_empty() and weight_total <= 0.0:
		problems.append(
			(
				(
					"table %s: declares allow_empty = false but has no guaranteed entry and no"
					% table_id
				)
				+ " positive weighted weight to force a pick from"
			)
		)
	if table.rolls > 0 and weight_total <= 0.0:
		problems.append(
			(
				"table %s: draws %d roll(s) but its weighted weights sum to %.4f"
				% [table_id, table.rolls, weight_total]
			)
		)
	return problems


static func _entry_problems(table_id: String, entry: LootEntry, by_id: Dictionary) -> Array[String]:
	var label := "table %s entry '%s'" % [table_id, String(entry.id)]
	var problems: Array[String] = []
	# --- quantity
	if entry.quantity < 1:
		problems.append("%s: quantity %d is below 1" % [label, entry.quantity])
	if entry.quantity_max < 0:
		problems.append("%s: quantity_max %d is negative" % [label, entry.quantity_max])
	if entry.quantity_max > 0 and entry.quantity_max < entry.quantity:
		problems.append(
			(
				"%s: quantity range is unsatisfiable (quantity %d > quantity_max %d)"
				% [label, entry.quantity, entry.quantity_max]
			)
		)
	# --- rarity floor
	if entry.rarity_floor != &"" and not ItemRarity.is_valid(entry.rarity_floor):
		problems.append(
			"%s: rarity_floor '%s' is not a known rarity" % [label, String(entry.rarity_floor)]
		)
	# --- target
	if entry.kind == LootEntry.KIND_TABLE:
		if entry.table_id == &"":
			problems.append("%s: a nested entry has no table_id" % label)
		elif (
			not by_id.has(String(entry.table_id))
			and LootContent.instance().table(entry.table_id) == null
		):
			problems.append("%s: table '%s' does not resolve" % [label, String(entry.table_id)])
		return problems
	if entry.kind != LootEntry.KIND_ITEM:
		problems.append("%s: unknown kind '%s'" % [label, String(entry.kind)])
		return problems
	if entry.item_id == &"":
		problems.append("%s: an item entry has no item_id" % label)
	elif LootContent.instance().definition(entry.item_id) == null:
		problems.append("%s: item '%s' is not a defined item" % [label, String(entry.item_id)])
	# --- probability, kept separate from the weighted pool
	if entry.chance < LootEntry.NO_CHANCE:
		problems.append(
			"%s: chance %.4f is below %.1f" % [label, entry.chance, LootEntry.NO_CHANCE]
		)
	if entry.guaranteed and entry.chance >= 0.0:
		problems.append(
			"%s: a guaranteed entry must not declare a chance (%.4f)" % [label, entry.chance]
		)
	if entry.is_independent() and not entry.is_independent_legal():
		problems.append("%s: chance %.4f is outside 0.0..1.0" % [label, entry.chance])
	if not entry.guaranteed and entry.is_weighted() and not is_finite(entry.weight):
		problems.append("%s: weight %f is not finite" % [label, entry.weight])
	if not entry.guaranteed and entry.is_weighted() and entry.weight < 0.0:
		problems.append("%s: weight %.4f is negative" % [label, entry.weight])
	return problems


## Every nested reference is visited once; a reference back onto the path being
## walked is a cycle and is reported with the path that closed it.
static func _cycles(by_id: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var state: Dictionary = {}
	for table_id in by_id.keys():
		if int(state.get(table_id, 0)) == 0:
			var found := _visit(by_id, String(table_id), state, [])
			if found != "":
				problems.append(found)
	return problems


static func _visit(by_id: Dictionary, table_id: String, state: Dictionary, path: Array) -> String:
	state[table_id] = 1
	var table := by_id.get(table_id) as LootTableDef
	if table == null:
		state[table_id] = 2
		return ""
	var next_path := path.duplicate()
	next_path.append(table_id)
	if next_path.size() > LootContent.MAX_NESTING_DEPTH:
		state[table_id] = 2
		return (
			"table cycle: %s exceeds the nesting limit of %d"
			% [
				" -> ".join(next_path),
				LootContent.MAX_NESTING_DEPTH,
			]
		)
	for entry in table.entries:
		if entry == null or not entry.is_nested() or entry.table_id == &"":
			continue
		var child_id := String(entry.table_id)
		if next_path.has(child_id):
			return "table cycle: %s -> %s" % [" -> ".join(next_path), child_id]
		if not by_id.has(child_id):
			continue
		var marked := int(state.get(child_id, 0))
		if marked == 1:
			return "table cycle: %s -> %s" % [" -> ".join(next_path), child_id]
		if marked == 0:
			var found := _visit(by_id, child_id, state, next_path)
			if found != "":
				state[table_id] = 2
				return found
	state[table_id] = 2
	return ""


## A unique-route item must be listed by the table of the boss it names, and no
## other source may list it in a way that could actually fire.
static func _route_problems(by_id: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	for table_id in by_id.keys():
		var table := by_id[table_id] as LootTableDef
		for item_id in _reachable(table, by_id, []):
			var def := LootContent.instance().definition(item_id)
			for boss_id in LootRoutes.routes(def):
				if not _bound_boss_drops(boss_id, item_id, by_id):
					(
						problems
						. append(
							(
								"table %s: item '%s' declares unique_route:%s but no table bound to that boss lists it"
								% [table_id, String(item_id), boss_id]
							)
						)
					)
	return problems


static func _reachable(table: LootTableDef, by_id: Dictionary, chain: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	if table == null or chain.has(String(table.id)):
		return out
	var next_chain := chain.duplicate()
	next_chain.append(String(table.id))
	for entry in table.entries:
		if entry == null:
			continue
		if entry.is_nested():
			for nested in _reachable(
				by_id.get(String(entry.table_id)) as LootTableDef, by_id, next_chain
			):
				if not out.has(nested):
					out.append(nested)
		elif entry.item_id != &"" and not out.has(entry.item_id):
			out.append(entry.item_id)
	return out


static func _bound_boss_drops(boss_id: String, item_id: StringName, by_id: Dictionary) -> bool:
	var content := LootContent.instance()
	for encounter_id in content.encounter_ids():
		var encounter := content.encounter_by_id(StringName(encounter_id))
		if encounter == null:
			continue
		for tier in encounter.tiers:
			if tier == null or tier.table_for(StringName(boss_id)) == &"":
				continue
			var table := by_id.get(String(tier.table_for(StringName(boss_id)))) as LootTableDef
			if table == null:
				table = content.table(tier.table_for(StringName(boss_id)))
			if table != null and _reachable(table, by_id, []).has(item_id):
				return true
	return false


# --- Encounters -------------------------------------------------------------


static func validate_encounters(content: LootContent) -> Array[String]:
	var problems: Array[String] = []
	var domain_ids: Dictionary = {}
	for encounter_id in content.encounter_ids():
		var encounter := content.encounter_by_id(StringName(encounter_id))
		if encounter == null:
			continue
		var label := String(encounter.id)
		if encounter.domain_id == &"":
			problems.append("encounter %s: has no domain_id" % label)
		elif domain_ids.has(String(encounter.domain_id)):
			problems.append(
				(
					"encounter %s: domain '%s' already has an encounter"
					% [label, String(encounter.domain_id)]
				)
			)
		else:
			domain_ids[String(encounter.domain_id)] = label
		problems.append_array(_encounter_problems(encounter))
	return problems


static func _encounter_problems(encounter: LootEncounterDef) -> Array[String]:
	var label := String(encounter.id)
	var content := LootContent.instance()
	var problems: Array[String] = []
	if encounter.boss_ids.is_empty():
		problems.append("encounter %s: has no bosses" % label)
	if encounter.tiers.is_empty():
		problems.append("encounter %s: has no tiers" % label)
	# --- boss <-> domain back-references, the same pair the content audit checks
	var domain := content.domain_record(encounter.domain_id)
	if not bool(domain.get("found", false)):
		problems.append(
			(
				"encounter %s: domain '%s' has no .tres under %s"
				% [label, String(encounter.domain_id), LootContent.DOMAIN_DIR]
			)
		)
	elif String(domain.get("id", "")) != String(encounter.domain_id):
		problems.append(
			(
				"encounter %s: domain file '%s' declares id '%s'"
				% [label, String(encounter.domain_id), String(domain.get("id", ""))]
			)
		)
	else:
		var listed: Array = domain.get("boss_ids", [])
		for boss_id in encounter.boss_ids:
			if not listed.has(String(boss_id)):
				problems.append(
					(
						"encounter %s: domain '%s' does not list boss '%s'"
						% [label, String(encounter.domain_id), String(boss_id)]
					)
				)
	for boss_id in encounter.boss_ids:
		var boss := content.boss_record(boss_id)
		if not bool(boss.get("found", false)):
			problems.append("encounter %s: boss '%s' has no .tres" % [label, String(boss_id)])
		elif String(boss.get("domain_id", "")) != String(encounter.domain_id):
			problems.append(
				(
					"encounter %s: boss '%s' declares domain_id '%s'"
					% [label, String(boss_id), String(boss.get("domain_id", ""))]
				)
			)
		# One authority: a boss bound to an authored table here *and* carrying a
		# populated legacy loot array would be two independent answers to "what does
		# this boss drop". The conflict is decided per encounter, from this
		# encounter's own bindings rather than from a global index.
		var legacy: Array = boss.get("loot", [])
		if not legacy.is_empty() and _bound_here(encounter, boss_id):
			problems.append(
				(
					(
						"encounter %s: boss '%s' has both an authored loot table and %d legacy"
						% [label, String(boss_id), legacy.size()]
					)
					+ " loot entries"
				)
			)
	# --- tiers
	var tier_ids: Dictionary = {}
	for tier in encounter.tiers:
		if tier == null:
			problems.append("encounter %s: has a null tier" % label)
			continue
		var tier_label := "encounter %s tier %d" % [label, tier.tier]
		if tier_ids.has(tier.tier):
			problems.append("%s: duplicate tier" % tier_label)
		tier_ids[tier.tier] = true
		if tier.realm == &"" or not _is_canonical_realm(tier.realm):
			problems.append(
				"%s: realm '%s' is not a canonical ladder id" % [tier_label, String(tier.realm)]
			)
		if tier.rarity != &"" and not ItemRarity.is_valid(tier.rarity):
			problems.append(
				"%s: rarity '%s' is not a known rarity" % [tier_label, String(tier.rarity)]
			)
		if tier.vitality <= 0.0:
			problems.append(
				"%s: vitality %.2f leaves the boss undefeatable" % [tier_label, tier.vitality]
			)
		var bound := tier.boss_ids()
		for boss_id in encounter.boss_ids:
			if not bound.has(boss_id):
				problems.append("%s: does not bind boss '%s'" % [tier_label, String(boss_id)])
		for boss_id in bound:
			if not encounter.boss_ids.has(boss_id):
				problems.append(
					(
						"%s: binds boss '%s' which the encounter does not list"
						% [tier_label, String(boss_id)]
					)
				)
			if content.table(tier.table_for(boss_id)) == null:
				problems.append(
					(
						"%s: boss '%s' names table '%s', which does not resolve"
						% [tier_label, String(boss_id), String(tier.table_for(boss_id))]
					)
				)
		for binding in tier.boss_tables:
			if float(binding.get("vitality", 0.0)) < 0.0:
				problems.append(
					(
						"%s: boss '%s' has a negative vitality override"
						% [tier_label, String(binding.get("boss_id", ""))]
					)
				)
	return problems


## Whether this encounter binds `boss_id` to a table at any of its tiers.
static func _bound_here(encounter: LootEncounterDef, boss_id: StringName) -> bool:
	for tier in encounter.tiers:
		if tier != null and tier.table_for(boss_id) != &"":
			return true
	return false


static func _is_canonical_realm(realm_id: StringName) -> bool:
	return RealmDefaults.ladder().index_of(realm_id) >= 0
