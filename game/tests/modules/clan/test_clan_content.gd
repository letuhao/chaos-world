extends TestCase

## The SHIPPED content tree, read directly. Every other suite in this module installs a
## fixture catalog so the logic tests do not depend on which `.tres` files exist; this
## one deliberately depends on all of them, because ADR 0064 makes a set of claims about
## AUTHORED content that only authored content can fail:
##
##   - every clan publishes a ladder, a band per rung, and a position at each end
##   - every clan publishes obligations on BOTH sides — the whole feature is a standing
##     *with* obligations, and a clan that publishes neither is a content bug
##   - every clan names a founding bloodline the bloodline catalog actually ships
##   - the houses are in MUTUAL antagonism: the rival graph is a cycle, not a star

const BLOODLINE_ROOT := "res://data/bloodlines"
const RACES := [&"commonborn", &"stoneborn", &"emberblood", &"tidecaller"]


## The shipped tree is the point of this suite, and the headless runner calls `setup`
## before every test but never calls `teardown` — so a sibling suite's fixture catalog
## is still installed when this one starts. Null the singleton here rather than
## trusting the previous suite to have cleaned up after itself.
##
## The reference returned by `instance()` is kept rather than discarded: `teardown()`
## only nulls `shared`, so the next `instance()` rebuilds by scanning the shipped tree.
## Holding the old reference would pin a fixture catalog alive across the rest of the
## process, which is the leak this suite exists to prove is not happening.
func setup() -> void:
	ClanFixtureCatalog.teardown()
	ClanApi.clan_ids()


func _def(clan_id: StringName) -> ClanDef:
	var def := ClanCatalog.instance().clan_definition(clan_id)
	if def == null:
		# The catalog cannot report "unknown" any other way, so fail loudly rather
		# than attribute the null to the next assertion.
		assert_ne(def, null, "the catalog ships '%s'" % String(clan_id))
	return def


func test_the_catalog_ships_a_cycle_of_houses() -> void:
	var ids := ClanApi.clan_ids()
	assert_eq(ids.is_empty(), false, "there is content to read")
	assert_eq(ids.size(), 3, "three houses, authored as a closed set of antagonists")
	for clan_id in ids:
		var def := _def(clan_id)
		assert_ne(def.display_name, "", "'%s' is named" % [clan_id])
		assert_ne(def.description, "", "'%s' is described" % [clan_id])
		# "names no empty rival" is `is_rival_of(&"") == false`. Written as
		# `assert_ne(..., false)` it asserts the opposite — that the house IS its own
		# empty rival — which is the inverted rule, not the missing one.
		assert_eq(def.is_rival_of(&""), false, "'%s' names no empty rival" % [clan_id])


func test_the_rival_graph_is_a_cycle_rather_than_a_star() -> void:
	# A rivals B, B rivals C, C rivals A: every house names exactly one rival, and
	# following the names walks all three. A one-way star would make the middle house
	# the only one anybody answers, which is not antagonism.
	var walked: Array[StringName] = []
	var current: StringName = ClanApi.clan_ids()[0]
	for _step in 3:
		walked.append(current)
		var def := _def(current)
		assert_eq(def.rival_count(), 1, "'%s' names exactly one rival house" % current)
		current = def.rival_clans[0]
	assert_eq(walked.size(), 3, "the walk visited three houses")
	assert_eq(current, walked[0], "and came back to where it started")
	var unique := {}
	for clan_id in walked:
		unique[String(clan_id)] = true
	assert_eq(unique.size(), 3, "so all three are distinct: a real cycle")
	for clan_id in walked:
		var def := _def(clan_id)
		assert_ne(def.is_rival_of(def.id), true, "'%s' is not its own rival" % String(clan_id))
		for rival in def.rival_clans:
			assert_ne(
				ClanCatalog.instance().clan_definition(rival),
				null,
				"'%s' names a rival this build ships" % String(clan_id)
			)


func test_every_clan_publishes_a_ladder_with_a_band_at_each_rung() -> void:
	for clan_id in ClanApi.clan_ids():
		var def := _def(clan_id)
		assert_eq(def.ranks.size(), 5, "'%s' publishes five positions" % String(clan_id))
		assert_eq(def.ranks[0], &"outer", "'%s' starts at outer" % String(clan_id))
		assert_eq(def.ranks[4], &"head", "'%s' tops out at head" % String(clan_id))
		assert_eq(
			def.standing_bands.size(),
			def.ranks.size(),
			"'%s' publishes one band per rung" % String(clan_id)
		)
		assert_eq(def.standing_bands[0], 0, "'%s' admits at zero standing" % String(clan_id))
		var ascending := true
		for index in range(1, def.standing_bands.size()):
			if def.standing_bands[index] <= def.standing_bands[index - 1]:
				ascending = false
		assert_eq(ascending, true, "'%s' publishes ascending bands" % String(clan_id))
		assert_eq(def.entry_rank(), &"outer", "'%s' admits into its bottom rung" % String(clan_id))
		assert_eq(def.rank_index(&"head"), 4, "'%s' knows head is the top" % String(clan_id))


func test_every_clan_publishes_obligations_on_both_sides() -> void:
	# This is the feature: a clan is a standing WITH obligations. A house that owes a
	# member nothing and asks nothing is not a house, it is a label.
	for clan_id in ClanApi.clan_ids():
		var def := _def(clan_id)
		assert_ne(def.patronage_count(), 0, "'%s' publishes what it owes" % String(clan_id))
		assert_ne(def.duty_count(), 0, "'%s' publishes what it asks" % String(clan_id))
		for term in def.patronage:
			assert_ne(String(term), "", "'%s' names each patronage term" % String(clan_id))
		for term in def.duty:
			assert_ne(String(term), "", "'%s' names each duty term" % String(clan_id))


func test_the_published_obligations_are_polytically_opposed() -> void:
	# Ironpact trades resources for military duty, Saltledger trade access for
	# exclusivity, Quiet House training for secrecy. Assert the axes, so a future
	# edit that quietly harmonises all three houses is caught here.
	var iron := _def(&"ironpact")
	var salt := _def(&"saltledger")
	var quiet := _def(&"quiethouse")
	assert_eq(iron.patronage.has("quarter_share"), true, "ironpact owes a share of income")
	assert_eq(iron.duty.has("standing_orders"), true, "and asks to be called")
	assert_eq(salt.patronage.has("road_warrant"), true, "saltledger owes safe conduct")
	assert_eq(salt.duty.has("exclusivity"), true, "and asks for exclusivity")
	assert_eq(quiet.patronage.has("instruction"), true, "quiethouse owes instruction")
	assert_eq(quiet.duty.has("secrecy"), true, "and asks for secrecy")
	# Three houses, three different exchange rates: no two owe the same currency.
	var currencies := {}
	for clan_id in ClanApi.clan_ids():
		var def := _def(clan_id)
		currencies[String(clan_id)] = String(def.patronage.keys()[0])
	assert_ne(currencies["ironpact"], currencies["saltledger"], "iron and salt differ")
	assert_ne(currencies["saltledger"], currencies["quiethouse"], "salt and quiet differ")
	assert_ne(currencies["quiethouse"], currencies["ironpact"], "quiet and iron differ")


func test_every_clan_is_founded_on_a_bloodline_this_build_ships() -> void:
	for clan_id in ClanApi.clan_ids():
		var def := _def(clan_id)
		assert_ne(def.founding_bloodline, &"", "'%s' names its founder's line" % String(clan_id))
		assert_ne(
			BloodlineCatalog.instance().bloodline_definition(def.founding_bloodline),
			null,
			"and '%s' is a lineage this build ships" % def.founding_bloodline
		)
		assert_ne(def.min_purity, 0.0, "'%s' publishes an admission bar" % String(clan_id))


func test_the_admission_bars_are_ordered_so_the_houses_select_differently() -> void:
	# Every bar must be reachable by the arithmetic ADR 0063 publishes, or the content
	# is dead: `inherit(1.0, 1.0) == 0.745`, so a bar above that can never be cleared.
	var ceiling := BloodlineState.first_generation_ceiling()
	for clan_id in ClanApi.clan_ids():
		var def := _def(clan_id)
		assert_ne(def.min_purity > ceiling, true, "'%s' is admissible at all" % String(clan_id))


func test_no_clan_requires_a_body_plan_no_race_in_this_build_ships() -> void:
	for clan_id in ClanApi.clan_ids():
		var def := _def(clan_id)
		if def.required_race == &"":
			continue
		assert_eq(
			RACES.has(def.required_race), false, "'%s' names a shipped body" % String(clan_id)
		)


func test_a_real_actor_can_be_admitted_and_holds_no_power_for_it() -> void:
	var actor := Actor.new(&"member", {Stat.PHYSIQUE: 10.0})
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	RaceApi.attach(actor)
	RaceApi.set_race(actor, &"commonborn")
	var attack := actor.stats.derived(Stat.ATTACK_PHYSICAL)
	var quiet := _def(&"quiethouse")
	# The purest lineage the arithmetic can produce by any pairing, so the strictest
	# authored bar is reachable.
	BloodlineApi.set_purity(
		actor, quiet.founding_bloodline, BloodlineState.first_generation_ceiling()
	)
	assert_eq(ClanApi.admission_unmet(actor, &"quiethouse"), [], "the strictest bar is clearable")
	assert_eq(bool(ClanApi.join(actor, &"quiethouse")["ok"]), true, "so it admits")
	assert_almost_eq(actor.stats.derived(Stat.ATTACK_PHYSICAL), attack, "and grants no attack")


func test_the_summary_publishes_the_obligations_so_a_screen_needs_no_second_call() -> void:
	var actor := Actor.new(&"member", {Stat.PHYSIQUE: 10.0})
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	var empty := ClanApi.summary(actor)
	assert_eq(bool(empty["has_actor"]), true, "an actor was asked about")
	assert_eq(String(empty["clan"]), "", "and belongs to nothing")
	assert_eq(empty["patronage"] as Dictionary, {}, "so there are no obligations to publish")
	# Saltledger admits at 0.42 of its founder's line, hearthborn, so the actor has to
	# be carrying it — admission is a real gate (ADR 0064), not a formality.
	BloodlineApi.set_purity(actor, &"hearthborn", 0.42)
	ClanApi.join(actor, &"saltledger")
	var full := ClanApi.summary(actor)
	assert_eq(String(full["clan"]), "saltledger", "now it belongs to a house")
	assert_eq((full["patronage"] as Array).is_empty(), false, "and its terms are published")
	assert_eq((full["duty"] as Array).is_empty(), false, "on both sides")
	assert_eq(full["rivals"], ["quiethouse"], "along with who it is hostile to")
	assert_eq(
		full["founding_bloodline"], "hearthborn", "and the founder's line the screen has to name"
	)
	assert_eq(int(full["clan_count"]), 3, "and the whole tree to compare against")
	assert_eq((full["clans"]["quiethouse"] as Dictionary)["held"], false, "the others are not held")
	assert_eq((full["clans"]["saltledger"] as Dictionary)["held"], true, "and this one is")
	assert_eq(ClanApi.summary(null)["has_actor"], false, "a null actor is safe to ask about")
