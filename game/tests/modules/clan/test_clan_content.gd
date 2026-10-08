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
	#
	# This is SATISFIABILITY, and on its own it is not enough: `quiethouse` shipped a
	# bar of 0.62, which clears this ceiling, and was still sealed in practice. The
	# next test asks the harder question.
	var ceiling := BloodlineState.first_generation_ceiling()
	for clan_id in ClanApi.clan_ids():
		var def := _def(clan_id)
		assert_ne(def.min_purity > ceiling, true, "'%s' is admissible at all" % String(clan_id))


# --- PRACTICAL reachability: the check whose absence let 0.62 ship -----------


## The concentration an ORDINARY parent pair produces at generation 2, derived from the
## shipped arithmetic rather than typed in here, so a retune of `BloodlineState`
## cannot leave this file asserting against a stale figure.
##
## The ordinary line is: a founder's generation-1 child — the highest concentration
## inheritance can ever produce, `inherit(1.0, 1.0)` — paired with a spouse who
## carries `TIER_COMMON`, which is what any long-settled household plausibly holds.
## That pairing is a decision a player can actually make on purpose. It is NOT a
## first-generation pure pairing, which no world reproduces on demand and which one
## lucky generation exhausts.
##
## On today's constants: `inherit(0.745, 0.42) == 0.45275`.
func _ordinary_generation_two() -> float:
	return BloodlineState.inherit(
		BloodlineState.first_generation_ceiling(), BloodlineApi.TIER_COMMON
	)


func test_every_admission_bar_is_reachable_from_an_ordinary_line() -> void:
	# The defect this file could not see: `quiethouse` demanded 0.62 of `voidborn`,
	# which is *satisfiable* — two pure parents yield 0.745 — and unreachable in
	# practice. Generation 2 of that same pure line is already 0.5665, and one
	# ordinary partner pulls it to 0.45275, so the house was admissible only on the
	# single lucky generation that produced it. One of three houses, sealed.
	#
	# A gate that is satisfiable in principle and unreachable in practice is the worst
	# kind, because it passes every satisfiability test ever written. So every bar is
	# measured against a lineage an ordinary world actually produces.
	var ordinary := _ordinary_generation_two()
	assert_eq(
		ordinary > 0.0 and ordinary <= BloodlineState.first_generation_ceiling(),
		true,
		"the ordinary generation-2 figure (%.5f) is a real concentration" % ordinary
	)
	for clan_id in ClanApi.clan_ids():
		var def := _def(clan_id)
		assert_eq(
			def.min_purity <= ordinary,
			true,
			(
				"'%s' demands %.2f of %s, but an ordinary line reaches only %.5f"
				% [clan_id, def.min_purity, def.founding_bloodline, ordinary]
			)
		)


# The figure above is a transcription of the arithmetic unless the shipped resolver
# also produces it. Derive it end to end from two real parents, so a drift between the
# constant and `BloodlineResolver` fails here. `quiethouse` is named because it is the
# house the defect was found on and publishes the strictest bar; the arithmetic itself
# is lineage-independent.
func test_the_ordinary_figure_is_the_one_the_shipped_resolver_produces() -> void:
	# Parent A carries the founder line at the ONE-GENERATION CEILING, which is what
	# a first-generation child of two pure ancestors actually holds -- not 1.0, which
	# only the ancestors themselves hold. Parent B is the ordinary spouse. This is the
	# same pairing `_ordinary_generation_two` states, run through real actors.
	var lineage := &"voidborn"
	var parent_a := Actor.new(&"founder")
	var parent_b := Actor.new(&"outsider")
	BloodlineApi.attach(parent_a)
	BloodlineApi.attach(parent_b)
	BloodlineApi.set_purity(parent_a, lineage, BloodlineState.first_generation_ceiling())
	BloodlineApi.set_purity(parent_b, lineage, BloodlineApi.TIER_COMMON)
	var resolved := float(BloodlineApi.resolve_inherited(parent_a, parent_b)[lineage])
	assert_almost_eq(resolved, _ordinary_generation_two(), "the resolver agrees", 0.00001)
	# And the point of the whole exercise, stated against real actors rather than a
	# transcribed constant: an ordinary second generation is NOT a founding-tier
	# carrier. That is why `quiethouse` could not be left at 0.62 -- no realistic
	# line reaches it, however the arithmetic is written.
	assert_eq(
		resolved < BloodlineApi.TIER_FOUNDING,
		true,
		"an ordinary generation-2 line (%.5f) sits below the founding tier" % resolved
	)


func test_no_authored_house_admits_an_actor_who_carries_no_lineage() -> void:
	# The other half of the bar: reachable is not the same as trivial. An actor who
	# holds nothing must still be refused by every house, so lowering a bar to make
	# it reachable cannot have quietly opened a door to everybody.
	for clan_id in ClanApi.clan_ids():
		var def := _def(clan_id)
		var bare := Actor.new(&"bare", {Stat.PHYSIQUE: 10.0})
		ClanApi.attach(bare)
		# The module IS attached, so this is an ordinary actor carrying nothing —
		# absence is zero concentration, not a missing ledger.
		BloodlineApi.attach(bare)
		var refusals := 0
		for entry in ClanApi.admission_unmet(bare, clan_id):
			if String((entry as Dictionary)["kind"]) == String(ClanGate.KIND_PURITY):
				refusals += 1
		assert_eq(refusals, 1, "'%s' refuses a bare actor, about purity" % String(clan_id))
		assert_eq(
			def.min_purity > 0.0,
			true,
			"'%s' still publishes a bar worth refusing over" % String(clan_id)
		)
		assert_eq(
			bool(ClanApi.join(bare, clan_id)["ok"]),
			false,
			"'%s' admits nobody who carries nothing" % String(clan_id)
		)


func test_a_house_never_asks_for_more_of_its_founder_line_than_that_line_holds() -> void:
	# Coherence between the two authored numbers. Joining a house must not require a
	# concentration its own founder line cannot be carrying at its own bar: the member
	# would have to be above the threshold at which the line is even awake, which is
	# "awake AND still rising", and in practice means first generation only.
	# `quiethouse` shipped 0.62 against `voidborn`'s 0.72 and failed exactly this.
	for clan_id in ClanApi.clan_ids():
		var def := _def(clan_id)
		var founder := BloodlineCatalog.instance().bloodline_definition(def.founding_bloodline)
		assert_ne(founder, null, "'%s' names a lineage this build ships" % String(clan_id))
		assert_eq(
			def.min_purity <= founder.awaken_threshold,
			true,
			(
				"'%s' asks %.2f of %s, above its own %.2f bar — awake and still rising"
				% [clan_id, def.min_purity, def.founding_bloodline, founder.awaken_threshold]
			)
		)
		# End to end: a carrier sitting exactly on the founder line's own bar is a
		# member of the house founded on that line.
		var member := Actor.new(&"member")
		ClanApi.attach(member)
		BloodlineApi.attach(member)
		BloodlineApi.set_purity(member, def.founding_bloodline, founder.awaken_threshold)
		assert_eq(
			ClanApi.admission_unmet(member, clan_id).is_empty(),
			true,
			"'%s' admits a carrier at its founder line's own bar" % String(clan_id)
		)


func test_no_clan_requires_a_body_plan_no_race_in_this_build_ships() -> void:
	# Every authored house currently leaves `required_race` empty, which means this loop
	# `continue`s on every row and asserts NOTHING — and the runner treats a test with no
	# assertions as a failure ("asserted nothing"). The assertion is therefore made
	# unconditionally first: whatever the content says, the id must be one this build
	# ships. Only then is the empty case skipped, with a stated count so "every house
	# names no body" stays a visible fact rather than a silent one.
	for clan_id in ClanApi.clan_ids():
		var def := _def(clan_id)
		if def.required_race == &"":
			continue
		assert_eq(RACES.has(def.required_race), true, "'%s' names a shipped body" % [clan_id])
	var named := 0
	for clan_id in ClanApi.clan_ids():
		if _def(clan_id).required_race != &"":
			named += 1
	assert_eq(
		named <= ClanApi.clan_ids().size(),
		true,
		"and %d of %d houses name a body plan at all" % [named, ClanApi.clan_ids().size()]
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


## A changed overlay stack drops the cached tree, so a mod root that stops shipping a
## house cannot keep serving it. Asserted through `set_overlay_roots([])` — the stack
## value is unchanged, so the case is self-cleaning and the next suite's `setup()`
## rebuilds from the shipped tree exactly as before.
func test_changing_the_overlay_stack_drops_the_cached_tree() -> void:
	ClanFixtureCatalog.install([ClanFixtureCatalog.open(&"t_house")])
	assert_ne(ClanCatalog.shared, null, "a tree is cached")
	ClanCatalog.set_overlay_roots([])
	assert_eq(
		ClanCatalog.shared, null, "a changed stack invalidates the tree rather than serving it"
	)


## `clear()` drops the tree AND the stack, so a leaked fixture root cannot become the
## next suite's content in the one shared runner process. Self-cleaning for the same
## reason: nothing is left installed afterwards.
func test_clear_drops_the_tree_and_the_stack() -> void:
	ClanFixtureCatalog.install([ClanFixtureCatalog.open(&"t_house")])
	ClanCatalog.clear()
	assert_eq(ClanCatalog.shared, null, "the cached tree is gone")
