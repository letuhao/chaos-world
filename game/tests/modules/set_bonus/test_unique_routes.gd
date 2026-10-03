extends TestCase

## A unique's boss drop route is declared in exactly one place: the `unique_route:
## <boss>` tag on its own `ItemDef`, which is what `LootRoutes.permits` enforces at
## drop time. `unique_routes.jsonl` used to declare the boss a second time — and a
## slot a third time, in a `slot` column that was a stale copy of the definition's
## `subcategory` for three of its five rows. Two declarations of one fact, kept in
## agreement by luck.
##
## These assert the surviving division of labour: the item owns identity, boss and
## slot; the index owns only the drop tuning a designer knows. A row that restates
## what the item owns fails, and every column the index does keep is checked
## against the shipped content it points at.

const BOSSES_ROOT := "res://data/bosses"
const DOMAINS_ROOT := "res://data/domains"
const ROUTES_PATH := "res://data/sets/unique_routes.jsonl"

## Columns the route index must NOT carry. Each one is a fact the item definition
## already owns and the runtime already enforces, so a copy here is a second
## declaration nothing keeps in agreement.
const OWNED_BY_THE_ITEM := ["boss_id", "slot"]


func _unique_ids() -> Array[StringName]:
	return SetCatalog.instance().unique_ids()


func _definition(item_id: StringName) -> ItemDef:
	var def := SetBonusApi.definition(item_id)
	assert_ne(def, null, "definition %s resolves" % item_id)
	return def


## Every row of the route index, read straight off disk so an orphan row is seen
## even though no catalog lookup would ever return it.
func _route_rows() -> Array:
	var out: Array = []
	if not FileAccess.file_exists(ROUTES_PATH):
		return out
	var json := JSON.new()
	for line in FileAccess.get_file_as_string(ROUTES_PATH).split("\n"):
		if line.strip_edges().is_empty():
			continue
		if json.parse(line) != OK or not json.data is Dictionary:
			out.append({})
			continue
		out.append(json.data)
	return out


## Identity belongs to the item definitions, so the index has exactly one row per
## authored unique: no unique may be invisible because a row is missing, and no
## row may name a unique that no longer exists.
func test_every_authored_unique_has_exactly_one_route_row_and_no_row_is_an_orphan() -> void:
	var ids := _unique_ids()
	assert_eq(ids.size() >= 4, true, "at least four uniques are authored")
	var rows := _route_rows()
	assert_ne(rows.is_empty(), true, "the route index ships")
	var seen := {}
	for row in rows:
		assert_ne(row.is_empty(), true, "every route row parses")
		var unique_id := String(OptionCatalog.text_field(row, "unique_id"))
		assert_ne(unique_id, "", "every route row names a unique")
		assert_eq(seen.has(unique_id), false, "%s has exactly one route row" % unique_id)
		seen[unique_id] = true
		assert_ne(
			SetBonusApi.definition(StringName(unique_id)),
			null,
			"%s: no row is an orphan" % unique_id
		)
		assert_eq(SetBonusApi.is_unique(StringName(unique_id)), true, "%s is a unique" % unique_id)
	for unique_id in ids:
		assert_eq(seen.has(String(unique_id)), true, "%s has a route row" % unique_id)


## The index must never restate a fact the item owns. This is the guard that stops
## the duplication coming back: without it, re-adding `boss_id` would quietly
## reintroduce two declarations that today agree only by construction, and the
## next content edit would silently desynchronise them.
func test_the_route_index_never_restates_the_boss_or_the_slot_the_item_owns() -> void:
	assert_ne(_route_rows().is_empty(), true, "the route index ships")
	for row in _route_rows():
		var unique_id := String(OptionCatalog.text_field(row, "unique_id"))
		for column in OWNED_BY_THE_ITEM:
			assert_eq(
				row.has(column),
				false,
				(
					"%s: the route index must not restate `%s` — the definition owns it"
					% [unique_id, column]
				)
			)
	# And the definition really does answer both, so dropping the copies cost
	# nothing rather than dropping the only declaration.
	for unique_id in _unique_ids():
		var def := _definition(unique_id)
		var route := SetBonusApi.drop_route(unique_id)
		assert_ne(
			UniqueItem.route_boss_id(def), &"", "%s states its boss on the definition" % unique_id
		)
		assert_ne(def.subcategory, &"", "%s states its slot on the definition" % unique_id)
		assert_eq(
			String(route["boss_id"]),
			String(UniqueItem.route_boss_id(def)),
			"%s: the facade reports the definition's boss" % unique_id
		)
		assert_eq(
			String(route["item_subtype"]),
			String(def.subcategory),
			"%s: and its real slot, not a stale column" % unique_id
		)


## What the index still declares has to agree with the shipped content it points
## at, or it is decoration. The boss comes from the tag, so the row's domain and
## set are checked against the boss and membership that tag actually implies.
func test_every_drop_tuning_row_agrees_with_the_boss_the_tag_names() -> void:
	var ladder := RealmDefaults.ladder()
	for unique_id in _unique_ids():
		var route := SetBonusApi.drop_route(unique_id)
		assert_eq(bool(route["declared"]), true, "%s declares a route" % unique_id)
		var def := _definition(unique_id)
		var boss_id := String(route["boss_id"])
		assert_eq(
			boss_id,
			String(UniqueItem.route_boss_id(def)),
			"%s: the boss comes from the tag" % unique_id
		)
		var boss := load("%s/%s.tres" % [BOSSES_ROOT, boss_id]) as BossDef
		assert_ne(boss, null, "%s: the tagged boss resolves" % unique_id)
		assert_eq(
			String(route["domain_id"]),
			String(boss.domain_id),
			"%s: the row's domain is the tagged boss's own domain" % unique_id
		)
		var route_realm := String(route["route_realm"])
		assert_eq(ladder.index_of(StringName(route_realm)) >= 0, true, "%s route realm" % unique_id)
		assert_eq(
			ladder.tier_of(def.realm) >= _boss_route_tier(boss_id),
			true,
			"%s meets the tagged boss's own realm tier" % unique_id
		)
		assert_eq(
			String(route["set_id"]),
			_set_of(unique_id),
			"%s: the row's set is the set that actually lists it" % unique_id
		)


## The set that lists a unique, or `""` when it belongs to none.
func _set_of(unique_id: StringName) -> String:
	for set_id in SetBonusApi.sets():
		if SetBonusApi.set_definition(set_id).uniques.has(unique_id):
			return String(set_id)
	return ""


## The route index and the set definitions must name the same uniques in both
## directions, or a unique would ship with no set and no route.
func test_the_route_index_and_the_set_definitions_name_the_same_uniques() -> void:
	var from_routes := {}
	for row in _route_rows():
		var unique_id := String(OptionCatalog.text_field(row, "unique_id"))
		if unique_id != "":
			from_routes[unique_id] = true
	var from_sets := {}
	for set_id in SetBonusApi.sets():
		for unique_id in SetBonusApi.set_definition(set_id).uniques:
			from_sets[String(unique_id)] = true
	assert_eq(not from_routes.is_empty(), true, "the route index is not empty")
	assert_eq(from_routes.size() >= 4, true, "at least four uniques are declared")
	for unique_id in from_sets.keys():
		assert_eq(from_routes.has(unique_id), true, "%s is a set member with a route" % unique_id)


## `set_bonus` cannot name `LootRoutes`' constant without breaking the module
## boundary, so the route field name is spelled twice. Renaming either side must
## be loud, because a silent rename would unbind every drop route in the game.
func test_the_route_tag_field_name_is_the_same_on_both_sides_of_the_module_boundary() -> void:
	assert_eq(UniqueItem.ROUTE_TAG_PREFIX, LootRoutes.TAG_PREFIX, "one field name, both modules")
	assert_eq(UniqueItem.TAG, &"unique", "the unique tag is unchanged")


func test_every_authored_unique_declares_a_route_that_resolves_to_a_real_boss() -> void:
	assert_eq(FileAccess.file_exists(ROUTES_PATH), true, "the route index ships")
	var ids := _unique_ids()
	for unique_id in ids:
		var route := SetBonusApi.drop_route(unique_id)
		assert_eq(bool(route["declared"]), true, "%s declares a route" % unique_id)
		var boss_id := String(route["boss_id"])
		assert_ne(boss_id, "", "%s names a boss" % unique_id)
		var boss_path := "%s/%s.tres" % [BOSSES_ROOT, boss_id]
		var domain_id := String(route["domain_id"])
		var domain_path := "%s/%s.tres" % [DOMAINS_ROOT, domain_id]
		assert_eq(ResourceLoader.exists(boss_path), true, "%s resolves to a real boss" % unique_id)
		assert_eq(
			ResourceLoader.exists(domain_path), true, "%s resolves to a real domain" % unique_id
		)
		# Positive reachable path: the boss sits in the domain the route names, and
		# the definition names the same boss in its own tags.
		var boss := load(boss_path) as BossDef
		var domain := load(domain_path) as DomainDef
		assert_eq(
			String(boss.domain_id), domain_id, "%s: boss sits in the named domain" % unique_id
		)
		assert_eq(
			domain.boss_ids.has(StringName(boss_id)),
			true,
			"%s: the domain lists the boss" % unique_id
		)
		var def := _definition(unique_id)
		assert_eq(
			String(UniqueItem.route_boss_id(def)),
			boss_id,
			"%s: the definition names the same route" % unique_id
		)
		assert_eq(
			def.sources.has(StringName("boss:%s" % boss_id)),
			true,
			"%s: the item declares the boss as an acquisition source" % unique_id
		)


func test_every_route_is_realm_and_rarity_compatible_with_its_unique() -> void:
	var ladder := RealmDefaults.ladder()
	for unique_id in _unique_ids():
		var route := SetBonusApi.drop_route(unique_id)
		var def := _definition(unique_id)
		var route_realm := String(route["route_realm"])
		assert_eq(ladder.index_of(StringName(route_realm)) >= 0, true, "%s route realm" % unique_id)
		assert_eq(
			ladder.index_of(def.realm) >= ladder.index_of(StringName(route_realm)),
			true,
			"%s is at least as high on the ladder as the boss that drops it" % unique_id
		)
		assert_eq(
			ladder.tier_of(def.realm) >= _boss_route_tier(String(route["boss_id"])),
			true,
			"%s meets the boss's own realm tier" % unique_id
		)
		var min_rarity := String(route["min_rarity"])
		assert_eq(
			ItemRarity.is_valid(StringName(min_rarity)),
			true,
			"%s min rarity is a rarity" % unique_id
		)
		assert_eq(
			ItemRarity.tier(def.rarity) >= ItemRarity.tier(StringName(min_rarity)),
			true,
			"%s is at least the rarity the route gates on" % unique_id
		)
		assert_eq(
			int(def.roll_spec.get("count", 0)),
			ItemRarity.affix_count(def.rarity),
			"%s roll count matches its rarity" % unique_id
		)
		assert_ne(float(route["drop_weight"]), 0.0, "%s has a positive drop weight" % unique_id)


## A boss's own tier, read from the canonical realm id its domain and loot ids
## name. The route has to sit at or below the unique, so the tier is derived from
## the shipped boss/domain content rather than trusted from the route row.
func _boss_route_tier(boss_id: String) -> int:
	var ladder := RealmDefaults.ladder()
	var boss := load("%s/%s.tres" % [BOSSES_ROOT, boss_id]) as BossDef
	var domain := load("%s/%s.tres" % [DOMAINS_ROOT, String(boss.domain_id)]) as DomainDef
	var tokens: Array = [String(boss.domain_id)]
	tokens.append_array(boss.loot)
	tokens.append_array(domain.boss_ids)
	var best := ""
	for token in tokens:
		for entry in ladder.realms():
			if String(entry.id) in String(token) and len(String(entry.id)) > len(best):
				best = String(entry.id)
	assert_ne(best, "", "boss %s names a canonical realm" % boss_id)
	return ladder.tier_of(StringName(best))


func test_a_unique_without_a_route_reports_no_route_rather_than_an_empty_one() -> void:
	var route := SetBonusApi.drop_route(&"set_ironhide_vigil_band")
	assert_eq(bool(route["declared"]), false, "a piece declares no unique route")
	assert_eq(String(route["boss_id"]), "", "and reports no boss")


func test_at_least_one_unique_carries_a_set_membership() -> void:
	var with_set := 0
	for unique_id in _unique_ids():
		var membership := SetBonusApi.membership(unique_id)
		if String(membership["set_id"]) != "":
			with_set += 1
			assert_eq(String(membership["kind"]), "unique", "%s is a unique member" % unique_id)
			assert_eq(bool(membership["is_unique"]), true, "%s is flagged unique" % unique_id)
	assert_eq(with_set >= 1, true, "at least one unique belongs to a set")


func test_membership_reports_nothing_for_an_item_outside_every_set() -> void:
	var membership := SetBonusApi.membership(&"armor_iron_helm")
	assert_eq(String(membership["set_id"]), "", "an unrelated item is in no set")
	assert_eq(bool(membership["is_unique"]), false, "and is not a unique")
