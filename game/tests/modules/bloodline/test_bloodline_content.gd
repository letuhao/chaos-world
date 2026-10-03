extends TestCase

## ADR 0063's content rules, asserted against the SHIPPED tree rather than a fixture.
## The load-bearing one is reachability: a lineage whose authored threshold is above the
## one-generation ceiling can never be inherited by anyone, however pure the parents, and
## a threshold at or below the floor is granted to everyone forever. That check is the
## whole reason the earlier draft's 0.70 and 0.85 tiers shipped as dead content.
##
## These are deliberately NOT isolated with a fixture catalog: the point is to hold the
## `.tres` files, so the real catalog is what they read.

## The bounds every authored threshold has to sit inside.
const MAX_THRESHOLD := 0.745
const MIN_PERCENT := 0.03
const MAX_PERCENT := 0.15


func _catalog() -> BloodlineCatalog:
	return BloodlineCatalog.instance()


# --- The tree loads at all ----------------------------------------------------


func test_the_authored_tree_loads_and_holds_several_lineages() -> void:
	var ids := _catalog().bloodline_ids()
	assert_eq(ids.size() >= 4, true, "at least four authored lineages, found %d" % ids.size())
	for lineage_id in ids:
		var def := _catalog().bloodline_definition(lineage_id)
		assert_ne(def, null, "'%s' resolves" % String(lineage_id))
		assert_ne(String(def.display_name), "", "'%s' is named" % String(lineage_id))
		assert_ne(String(def.description), "", "'%s' is described" % String(lineage_id))
		assert_eq(
			String(def.source_id()),
			"bloodline:%s" % String(lineage_id),
			"'%s' namespaces its source" % String(lineage_id)
		)


func test_an_unknown_lineage_resolves_to_null_rather_than_a_guess() -> void:
	assert_eq(_catalog().bloodline_definition(&"no_such_lineage"), null, "null, never a fallback")
	assert_eq(_catalog().bloodline_ids().has(&"no_such_lineage"), false, "and it is not listed")


# --- Reachability: no tier may be dead or permanent ---------------------------


func test_no_authored_lineage_is_dead_content() -> void:
	for lineage_id in _catalog().bloodline_ids():
		var def := _catalog().bloodline_definition(lineage_id)
		assert_eq(
			def.awaken_threshold <= MAX_THRESHOLD,
			true,
			"'%s' at %.2f is reachable in one generation" % [lineage_id, def.awaken_threshold]
		)
		# And the parent purity it demands is actually a purity a parent can hold.
		assert_eq(
			(
				(def.awaken_threshold - BloodlineState.BLEND_CONSTANT) / BloodlineState.RETENTION
				<= 1.0
			),
			true,
			"'%s' needs a possible parent" % String(lineage_id)
		)


func test_no_authored_lineage_is_permanently_awake() -> void:
	for lineage_id in _catalog().bloodline_ids():
		var def := _catalog().bloodline_definition(lineage_id)
		assert_eq(
			def.awaken_threshold > BloodlineState.FLOOR,
			true,
			"'%s' sits above the floor" % String(lineage_id)
		)


func test_the_three_published_tiers_are_all_represented_in_authored_content() -> void:
	var tiers: Array[StringName] = []
	for lineage_id in _catalog().bloodline_ids():
		tiers.append(
			BloodlineApi.rank_tier(_catalog().bloodline_definition(lineage_id).awaken_threshold)
		)
	assert_eq(tiers.has(&"common"), true, "a common lineage, tiers %s" % [tiers])
	assert_eq(tiers.has(&"rare"), true, "a rare lineage")
	assert_eq(tiers.has(&"founding"), true, "and a founding one")


func test_a_lineage_authored_at_the_founding_bar_is_genuinely_rare_to_reach() -> void:
	# Not just "under the ceiling" but actually one generation from the top of the
	# ladder: a second generation of any pairing falls below it.
	var founding: Array[StringName] = []
	for lineage_id in _catalog().bloodline_ids():
		if (
			BloodlineApi.rank_tier(_catalog().bloodline_definition(lineage_id).awaken_threshold)
			== &"founding"
		):
			founding.append(lineage_id)
	assert_eq(founding.is_empty(), false, "at least one founding lineage is authored")
	for lineage_id in founding:
		var second := BloodlineState.inherit(MAX_THRESHOLD, MAX_THRESHOLD)
		assert_eq(
			second < _catalog().bloodline_definition(lineage_id).awaken_threshold,
			true,
			"'%s' lapses by the second generation (%.3f)" % [lineage_id, second]
		)


# --- Bounded grants ----------------------------------------------------------


func test_every_authored_grant_is_a_bounded_percent_and_none_is_flat() -> void:
	for lineage_id in _catalog().bloodline_ids():
		var def := _catalog().bloodline_definition(lineage_id)
		assert_eq(
			def.percent_modifiers.is_empty(), false, "'%s' grants something" % String(lineage_id)
		)
		for key in def.percent_modifiers.keys():
			var value := float(def.percent_modifiers[key])
			assert_eq(
				value >= MIN_PERCENT and value <= MAX_PERCENT,
				true,
				(
					"'%s' grants %s at %.2f, inside [%.2f, %.2f]"
					% [lineage_id, key, value, MIN_PERCENT, MAX_PERCENT]
				)
			)
			# PERCENT is what `build_modifiers` emits; assert the shape rather than
			# trusting the export annotation to have been read.
			var tagged := false
			for modifier in def.build_modifiers():
				if modifier.stat == StringName(key):
					tagged = modifier.op == Stat.Op.PERCENT and modifier.source == def.source_id()
			assert_eq(tagged, true, "'%s' grants %s as a tagged PERCENT" % [lineage_id, key])


func test_no_authored_grant_chains_into_a_multiplier() -> void:
	# A percent modifier rides the actor's own growth and cannot compound. Two lineages
	# at the authored maximum therefore cannot produce anything close to a double.
	var worst := 0.0
	for lineage_id in _catalog().bloodline_ids():
		var def := _catalog().bloodline_definition(lineage_id)
		for key in def.percent_modifiers.keys():
			worst += float(def.percent_modifiers[key])
	assert_eq(worst <= 1.0, true, "even every authored grant at once is %.2f" % worst)


# --- Data hygiene ------------------------------------------------------------


func test_every_authored_lineage_is_beside_the_bloodline_projection_and_nothing_else() -> void:
	# A lineage is named by its race, never gated by it: the module's own premise is
	# that ancestry and body plan are separate systems, and a lineage that required a
	# race would couple them through content.
	for lineage_id in _catalog().bloodline_ids():
		var def := _catalog().bloodline_definition(lineage_id)
		if def.race_id != &"":
			assert_ne(
				RaceCatalog.instance().race_definition(def.race_id),
				null,
				"'%s' names a race that ships" % String(lineage_id)
			)
	assert_eq(
		_categorised_race_ids().has(&""), true, "and at least one lineage crosses races outright"
	)


## The distinct `race_id` values authored, so a build cannot quietly lose its
## cross-race lineage.
func _categorised_race_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for lineage_id in _catalog().bloodline_ids():
		var race_id := _catalog().bloodline_definition(lineage_id).race_id
		if not out.has(race_id):
			out.append(race_id)
	return out


func test_the_authored_prose_carries_no_marker_of_the_thing_this_repo_forbids() -> void:
	# AGENTS.md forbids sexual content outright, and these lineages feed the birth
	# system. The copy must describe structure and inheritance, never anything else.
	# Cheap and blunt on purpose: a keyword ban is a canary, not a style review.
	var banned := ["seduct", "arous", "orgasm", "climax", "lust", "erotic", "naked", "breast"]
	for lineage_id in _catalog().bloodline_ids():
		var def := _catalog().bloodline_definition(lineage_id)
		var prose := (def.display_name + " " + def.description).to_lower()
		for word in banned:
			assert_eq(prose.contains(word), false, "'%s' avoids '%s'" % [lineage_id, word])


func test_the_shipped_tree_can_actually_awaken_and_lapse_on_a_real_actor() -> void:
	# End to end through the shipped content: a founder-pure lineage grants while it is
	# pure, and the very next generation does not.
	var ids := _catalog().bloodline_ids()
	var parent_a := Actor.new(&"a")
	var parent_b := Actor.new(&"b")
	BloodlineApi.attach(parent_a)
	BloodlineApi.attach(parent_b)
	for lineage_id in ids:
		BloodlineApi.set_purity(parent_a, lineage_id, 1.0)
		BloodlineApi.set_purity(parent_b, lineage_id, 1.0)
	var child_purity := BloodlineApi.resolve_inherited(parent_a, parent_b)
	var child := Actor.new(&"child")
	BloodlineApi.attach(child)
	var awakened := 0
	for lineage_id in ids:
		BloodlineApi.set_purity(child, lineage_id, float(child_purity[lineage_id]))
		if BloodlineApi.is_awake(child, lineage_id):
			awakened += 1
	assert_eq(awakened > 0, true, "a first generation of pure parents awakens something")
	var founding := BloodlineApi.TIER_FOUNDING
	# A founding bar is authored at or just under the one-generation ceiling, so two
	# pure parents DO produce an awake founding lineage — that is what "one more
	# generation than the tier below" means. It lapses the generation after, so the
	# check has to inherit once more rather than re-assert on the same child.
	var lapsed := 0
	for lineage_id in ids:
		var def := _catalog().bloodline_definition(lineage_id)
		if def.awaken_threshold < founding:
			continue
		var grandchild := BloodlineState.inherit(float(child_purity[lineage_id]), 0.0)
		if grandchild < def.awaken_threshold:
			lapsed += 1
	assert_eq(lapsed > 0, true, "but a founding lineage lapses in the next generation")
