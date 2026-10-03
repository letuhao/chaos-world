extends TestCase

## The shipped loot content: it validates clean, it covers the bands and rarities
## it claims to, and its boss/domain back-references agree with the content audit.

const EMBER_DOMAIN := &"loot_ember_vault_domain"
const EMBER_TIER := 1


func _content() -> LootContent:
	return LootContent.instance()


## Everything the module authors is validation-clean. One failure here names the
## exact table, entry or encounter to fix.
func test_the_shipped_loot_content_validates_clean() -> void:
	assert_eq(str(LootApi.validate()), "[]", "no table problems")
	assert_eq(str(LootApi.validate("tables")), "[]", "no table problems, scoped")
	assert_eq(str(LootApi.validate("encounters")), "[]", "no encounter problems, scoped")


## The tables exist and declare the four separate mechanisms, so the format is
## exercised by the content rather than only by tests.
func test_every_authored_mechanism_appears_in_the_shipped_content() -> void:
	var content := _content()
	var guaranteed := 0
	var independent := 0
	var nested := 0
	var quantities := 0
	var rarity_floors := 0
	var allow_empty := 0
	var ranges := 0
	for table_id in content.table_ids():
		var table := content.table(StringName(table_id))
		assert_ne(table, null, "%s loads" % table_id)
		if table == null:
			continue
		if bool(table.allow_empty):
			allow_empty += 1
		if table.rolls_max > table.rolls:
			ranges += 1
		for entry in table.entries:
			if entry == null:
				continue
			if entry.guaranteed:
				guaranteed += 1
			if entry.is_independent():
				independent += 1
			if entry.is_nested():
				nested += 1
			if entry.quantity_max > entry.quantity:
				quantities += 1
			if entry.rarity_floor != &"":
				rarity_floors += 1
	assert_eq(guaranteed > 0, true, "guaranteed entries are authored")
	assert_eq(independent > 0, true, "independent chance entries are authored")
	assert_eq(nested > 0, true, "nested tables are authored")
	assert_eq(quantities > 0, true, "per-entry quantity ranges are authored")
	assert_eq(rarity_floors > 0, true, "rarity floors are authored")
	assert_eq(allow_empty > 0, true, "an explicit no-drop table is authored")
	assert_eq(ranges > 0, true, "drop-count ranges are authored")


## At least two difficulty bands, and every rarity reachable across them.
func test_the_content_covers_two_bands_and_all_four_rarities() -> void:
	var content := _content()
	var realms: Array = []
	var rarities: Array = []
	var bands := {}
	for encounter_id in content.encounter_ids():
		var encounter := content.encounter_by_id(StringName(encounter_id))
		assert_ne(encounter, null, "%s loads" % encounter_id)
		if encounter == null:
			continue
		assert_eq(encounter.tier_count() >= 2, true, "%s has at least two bands" % encounter_id)
		for tier in encounter.tiers:
			if not realms.has(String(tier.realm)):
				realms.append(String(tier.realm))
			if not rarities.has(String(tier.rarity)):
				rarities.append(String(tier.rarity))
			bands["%s/%s" % [String(tier.realm), String(tier.rarity)]] = true
			for item_id in tier.table_ids():
				var table := content.table(item_id)
				for reachable in table.reachable_item_ids():
					var def := content.definition(reachable)
					if not rarities.has(String(ItemRarity.sanitize(def.rarity))):
						rarities.append(String(ItemRarity.sanitize(def.rarity)))
	assert_eq(bands.size() >= 2, true, "at least two difficulty bands are authored")
	for rarity in ItemRarity.ALL:
		assert_eq(rarities.has(String(rarity)), true, "%s is reachable from loot" % String(rarity))
	for realm_id in realms:
		assert_eq(
			RealmDefaults.ladder().index_of(StringName(realm_id)) >= 0,
			true,
			"%s is a canonical realm id" % realm_id
		)


## Each authored encounter agrees with its domain and boss `.tres` files, which is
## the same back-reference the content audit checks.
func test_encounters_agree_with_the_boss_and_domain_content() -> void:
	var content := _content()
	for encounter_id in content.encounter_ids():
		var encounter := content.encounter_by_id(StringName(encounter_id))
		var domain := content.domain_record(encounter.domain_id)
		assert_eq(bool(domain["found"]), true, "%s has a domain file" % encounter_id)
		assert_eq(String(domain["id"]), String(encounter.domain_id), "and the ids agree")
		for boss_id in encounter.boss_ids:
			assert_eq(
				(domain["boss_ids"] as Array).has(String(boss_id)),
				true,
				"domain %s lists boss %s" % [String(encounter.domain_id), String(boss_id)]
			)
			var boss := content.boss_record(boss_id)
			assert_eq(bool(boss["found"]), true, "boss %s has a file" % String(boss_id))
			assert_eq(
				String(boss["domain_id"]),
				String(encounter.domain_id),
				"boss %s back-references its domain" % String(boss_id)
			)
			assert_eq(
				(boss["loot"] as Array).is_empty(),
				true,
				"boss %s leaves its loot array to the loot module" % String(boss_id)
			)


## Every boss of every authored band is bound to exactly one table that resolves,
## and the whole domain's content is reachable through the facade.
func test_every_bound_boss_resolves_to_a_table() -> void:
	var content := _content()
	var domains := LootApi.domains()
	assert_eq(domains.size(), content.encounter_ids().size(), "the facade lists every encounter")
	for entry in domains:
		var descriptor := entry as Dictionary
		assert_eq(String(descriptor["domain_id"]).is_empty(), false, "a domain id is reported")
		assert_eq((descriptor["tiers"] as Array).is_empty(), false, "with at least one tier")
		for tier in descriptor["tiers"]:
			assert_eq(int((tier as Dictionary)["vitality"]) > 0.0, true, "an authored vitality")
		var encounter := content.encounter_for_domain(StringName(descriptor["domain_id"]))
		for boss_id in encounter.boss_ids:
			for tier_index in [EMBER_TIER, EMBER_TIER + 1]:
				var tier := encounter.tier_at(tier_index)
				if tier == null:
					continue
				assert_eq(tier.table_for(boss_id) != &"", true, "%s is bound" % String(boss_id))
				assert_ne(
					content.table(tier.table_for(boss_id)),
					null,
					"%s resolves" % String(tier.table_for(boss_id))
				)
				assert_eq(
					String(content.table_for_boss(boss_id, tier_index).id),
					String(tier.table_for(boss_id)),
					"and the single authority resolves to it"
				)


## The facade's table projection carries the authored semantics to a reader.
func test_the_facade_projects_a_table_with_its_declared_semantics() -> void:
	var view := LootApi.table(&"loot_ember_warden_t1")
	assert_ne(view.is_empty(), true, "the table projects")
	assert_eq(String(view["id"]), "loot_ember_warden_t1", "with its id")
	assert_eq(String(view["realm"]), "spirit_severing", "its roll realm")
	assert_eq(String(view["rarity"]), "common", "its rarity context")
	assert_eq(int(view["rolls"]), 1, "its draw floor")
	assert_eq(int(view["rolls_max"]), 2, "its draw ceiling")
	assert_eq(bool(view["allow_empty"]), false, "its no-drop declaration")
	var guaranteed := 0
	var weighted := 0
	var independent := 0
	for entry in view["entries"]:
		var row := entry as Dictionary
		if bool(row["guaranteed"]):
			guaranteed += 1
		elif float(row["chance"]) >= 0.0:
			independent += 1
		else:
			weighted += 1
	assert_eq(guaranteed, 1, "one guaranteed entry")
	assert_eq(weighted, 2, "two weighted candidates")
	assert_eq(independent, 1, "one independent chance roll")
	assert_eq((view["item_ids"] as Array).size() > 0, true, "and it reaches real item ids")
	assert_eq(LootApi.table(&"no_such_table").is_empty(), true, "an unknown table projects empty")


## The validator refuses content where a boss would have two loot authorities.
##
## The probe is authored here rather than borrowed from the shipped content, because no
## shipped boss carries a legacy `loot` array any more: the corpus was migrated to
## authored bindings, so the only boss that still has a legacy list is one a caller
## authors. Asserting against a shipped id would pin the test to content drift — which
## is how this assertion came to be wrong in the first place.
func test_the_validator_rejects_two_boss_loot_authorities() -> void:
	var content := _content()
	var legacy := &"probe_legacy_loot_bear"
	content.provide_boss(
		legacy,
		{
			"found": true,
			"id": String(legacy),
			"domain_id": "",
			"boss_ids": [],
			"loot": ["amulet_iron_sage_eye"]
		}
	)
	var record := content.boss_record(legacy)
	assert_eq(bool(record["found"]), true, "the probe boss content resolves")
	assert_eq((record["loot"] as Array).is_empty(), false, "and it carries a legacy loot list")
	# A synthetic encounter that binds a boss which also has a legacy loot list is
	# exactly the conflict the validator exists to catch.
	var encounter := LootEncounterDef.new()
	encounter.id = &"probe_two_authorities"
	encounter.domain_id = &"beast_ironhide_bear_domain"
	encounter.boss_ids = [legacy] as Array[StringName]
	var tier := LootTier.new()
	tier.tier = 1
	tier.realm = &"spirit_severing"
	tier.vitality = 10.0
	tier.boss_tables = (
		[{"boss_id": legacy, "table_id": &"loot_ember_material_pool"}] as Array[Dictionary]
	)
	encounter.tiers = [tier] as Array[LootTier]
	var text := "\n".join(LootValidator._encounter_problems(encounter))
	assert_eq(text.contains("legacy loot entries"), true, "the conflict is reported")
	assert_eq(text.contains("does not bind boss"), false, "the bindings themselves are complete")


## The migration path is a migration path: with the corpus migrated, **no** shipped
## boss carries a legacy `loot` list, so the projection cannot silently become a second
## authority in the content tree. Pinned over the whole shipped corpus, because a single
## surviving `loot` array would put every one of its bosses at risk of two answers to
## "what does this boss drop".
func test_no_shipped_boss_carries_a_legacy_loot_list() -> void:
	var content := _content()
	var legacy: Array = []
	for path in _boss_tres_files():
		var record := content.boss_record(StringName(path.get_file().trim_suffix(".tres")))
		if (record.get("loot", []) as Array).size() > 0:
			legacy.append(String(record.get("id", "")))
	assert_eq(legacy, [], "every shipped boss is bound to an authored table instead")
	assert_eq(
		bool(content.has_authored_table(&"beast_ironhide_bear")),
		true,
		"and the bear the legacy suites once borrowed is now authored"
	)


## Every `.tres` under [constant LootContent.BOSS_DIR], one level deep, so the corpus
## scan above reads the same set the content index does. Bounded by the directory walk
## itself, which `DirAccess` terminates.
func _boss_tres_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(LootContent.BOSS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not file_name.begins_with(".") and file_name.ends_with(".tres"):
			out.append(LootContent.BOSS_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	return out


## The unique-route field name is one constant, so the authoring field can be
## re-pointed without touching resolution.
func test_the_unique_route_field_name_is_a_single_constant() -> void:
	assert_eq(LootRoutes.TAG_PREFIX, "unique_route:", "one owner for the field name")
	var def := ItemDef.new()
	def.tags = (
		["boss_route:someone", "unique_route:boss_a", "unique_route:boss_b"] as Array[StringName]
	)
	assert_eq(str(LootRoutes.routes(def)), '["boss_a", "boss_b"]', "only route tags are read")
	assert_eq(bool(LootRoutes.permits(def, &"boss_a")), true, "a named boss may drop it")
	assert_eq(bool(LootRoutes.permits(def, &"boss_c")), false, "no other boss may")
	assert_eq(
		bool(LootRoutes.permits(ItemDef.new(), &"boss_a")),
		true,
		"an undeclared item is unrestricted"
	)
