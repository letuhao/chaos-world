extends TestCase

## The authored content under `res://data/packs/nation/organizations/` must load, and the module must
## bind to it. This is the suite that would go red first if a `.tres` named a
## script that does not exist, an office id was duplicated, or a polity shipped a
## board with nothing left vacant.

const MARCH := &"march_of_the_nine_provinces"
const COURT := &"court_of_the_star"
## Four territory claims across four tiers, so no tier row is unreachable content.
const TERRITORIES: Array[StringName] = [
	&"river_march", &"ashen_wold", &"nine_province_reach", &"star_court"
]


func _catalog() -> NationCatalog:
	return NationCatalog.instance()


func test_every_authored_nation_loads_with_a_board_of_at_least_four_seats() -> void:
	var ids := _catalog().nation_ids()
	assert_eq(ids.size() >= 2, true, "at least two polities are authored")
	for nation_id in ids:
		var def := _catalog().nation_definition(nation_id)
		assert_ne(def, null, "%s loads" % nation_id)
		assert_ne(def.id, &"", "%s has an id" % nation_id)
		assert_ne(def.display_name, "", "%s is named" % nation_id)
		assert_eq(def.office_ids().size() >= 4, true, "%s authors at least four seats" % nation_id)
		assert_eq(def.board().size(), def.office_ids().size(), "%s seats every seat" % nation_id)


func test_every_nation_leaves_at_least_one_seat_vacant_so_the_state_is_representable() -> void:
	for nation_id in _catalog().nation_ids():
		var def := _catalog().nation_definition(nation_id)
		assert_eq(
			def.vacant_office_ids().size() >= 1,
			true,
			"%s authors an unfilled seat, or vacancy is unrepresentable in content" % nation_id
		)
		# And the vacancies are genuine empty holders, never a zero or a dash.
		for office_id in def.vacant_office_ids():
			assert_eq(
				String(def.board()[String(office_id)]), "", "%s is empty, not zero" % office_id
			)


func test_four_territory_claims_load_one_per_tier() -> void:
	var ids := _catalog().territory_ids()
	assert_eq(ids.size() >= 4, true, "four territory claims are authored")
	for territory_id in TERRITORIES:
		var def := _catalog().territory_definition(territory_id)
		assert_ne(def, null, "%s loads" % territory_id)
		assert_eq(def.covers_land(), true, "%s covers at least one place" % territory_id)
		assert_eq(def.has_seat(), true, "%s names the place it is fought over" % territory_id)
		assert_eq(
			def.tier_index >= 0 and def.tier_index < 4, true, "%s names a real tier" % territory_id
		)


func test_the_tuning_is_loaded_from_its_tres_with_a_row_per_authored_tier() -> void:
	var tuning := _catalog().tuning()
	assert_ne(tuning, null, "the shipped .tres loads")
	assert_eq(tuning.tier_yield.size(), 4, "four yield rows")
	for rows in [
		tuning.tier_upkeep,
		tuning.tier_qi_density,
		tuning.tier_claim_standing_floor,
		tuning.tier_hold_standing_floor
	]:
		assert_eq((rows as Array).size(), 4, "every tier row is authored once")
	assert_eq(tuning.qi_density_cap > 0.0, true, "qi density is capped")
	assert_eq(tuning.war_break > 0.0, true, "exhaustion has a declared break point")
	assert_eq(tuning.yield_for(3) > tuning.yield_for(0), true, "a deeper tier is worth more")
	assert_eq(tuning.qi_density_for(3) <= tuning.qi_density_cap, true, "and no row exceeds the cap")


func test_a_territory_def_carries_no_yield_no_upkeep_and_no_combat_bonus() -> void:
	# ADR 0085: "Territory grants no combat bonus." A home-ground modifier would
	# make the map a combat input, so the shape itself is asserted rather than the
	# value: the tuning resource owns every amount a claim could carry.
	var def := _catalog().territory_definition(&"river_march")
	for field in def.get_property_list():
		var name := String(field.get("name", ""))
		var forbidden := ["damage", "defense", "combat", "yield", "upkeep", "qi_density", "bonus"]
		for word in forbidden:
			assert_eq(
				name.contains(word),
				false,
				"a claim over places carries no %s field (%s)" % [word, name]
			)


## Counted from the SCRIPT TEXT, not by reflection, exactly as
## `test_domain_api.gd` does it: `tools arch` counts `static func` declarations the
## same way, so this is the number the gate enforces. Reflection is unavailable
## here — `get_method_list()` is an instance method and every facade verb is static.
func _published_facade_methods() -> Array[String]:
	var script := load("res://src/modules/nation/api.gd") as GDScript
	var out: Array[String] = []
	for line in String(script.source_code).split("\n"):
		var trimmed := String(line).strip_edges()
		if not trimmed.begins_with("static func "):
			continue
		var name := trimmed.trim_prefix("static func ").split("(")[0].strip_edges()
		if not name.begins_with("_"):
			out.append(name)
	return out


func test_the_nation_carries_no_facade_method_that_grants_power() -> void:
	# ADR 0084's structural guard, copied from `test_destiny_earning`: `tools arch`
	# cannot see a method that does not exist, so the invariant is pinned by reading
	# the published method list.
	var published := _published_facade_methods()
	for banned in [
		"grant_stat",
		"grant_attribute",
		"set_base",
		"add_base",
		"power_up",
		"buff",
		"apply_modifier",
		"tick",
		"advance",
	]:
		assert_eq(published.has(banned), false, "the facade exposes no %s" % banned)


func test_the_facade_stays_at_or_below_the_twelve_method_cap() -> void:
	var published := _published_facade_methods()
	assert_eq(published.size() > 0, true, "and the count is real, not an artefact of the parse")
	assert_eq(published.size() <= 12, true, "%d public methods, cap is 12" % published.size())


func test_founding_a_polity_seats_its_board_including_the_vacancies() -> void:
	var actor := Actor.new(&"probe", {Stat.PHYSIQUE: 10.0})
	NationApi.attach(actor)
	NationApi.found(actor, MARCH, "probe")
	var summary := NationApi.summary(actor)
	assert_eq(summary["founded"], true, "the actor lives under it")
	assert_eq(String(summary["nation_id"]), String(MARCH), "and under the right one")
	var offices: Dictionary = summary["offices"]
	assert_eq(
		offices.size(),
		_catalog().nation_definition(MARCH).office_ids().size(),
		"every seat is a row"
	)
	assert_eq(int(summary["vacant_offices"]) >= 1, true, "and the vacancy is counted, not hidden")
	# Standing comes from the authored claim, which is the institution's own earned
	# number and never the actor's.
	var def := _catalog().nation_definition(MARCH)
	assert_eq(int(summary["standing"]), def.own_claim().standing, "the polity's authored standing")
	assert_eq(int(summary["standing_cap"]), def.own_claim().standing_cap, "and its cap")


## A changed overlay stack drops the cached tree, so a mod root that stops shipping
## a nation cannot keep serving it. Asserted through `set_overlay_roots([])` — the
## stack value is unchanged, so the case is self-cleaning and the next suite reads
## the shipped tree exactly as before.
func test_changing_the_overlay_stack_drops_the_cached_tree() -> void:
	assert_ne(NationCatalog.shared, null, "a tree is cached")
	NationCatalog.set_overlay_roots([])
	assert_eq(
		NationCatalog.shared, null, "a changed stack invalidates the tree rather than serving it"
	)
	assert_ne(NationCatalog.instance().nation_ids().size(), 0, "and the shipped tree rebuilds")


## `clear()` drops the tree AND the stack, so a leaked fixture root cannot become
## the next suite's content in the one shared runner process. Self-cleaning for the
## same reason: nothing is left installed afterwards.
func test_clear_drops_the_tree_and_the_stack() -> void:
	NationCatalog.clear()
	assert_eq(NationCatalog.shared, null, "the cached tree is gone")
	assert_ne(NationCatalog.instance().nation_ids().size(), 0, "and the shipped tree rebuilds")
