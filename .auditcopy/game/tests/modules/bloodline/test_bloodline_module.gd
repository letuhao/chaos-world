extends TestCase

## ADR 0063's inheritance arithmetic as the module actually computes it: the ledger
## round trip, the load-bearing MEAN in `BloodlineState.inherit`, dilution toward the
## floor, the awake boundary, and the gate refusing a requirement it cannot read.
##
## `test_purity_reachability.gd` holds the constants to the published ladder; this suite
## holds them to the CODE, so the two cannot drift apart without a test failing.

const COMMON := &"t_common"
const RARE := &"t_rare"
const FOUNDING := &"t_founding"
const INERT := &"t_inert"


func setup() -> void:
	(
		BloodlineFixtureCatalog
		. install(
			[
				BloodlineFixtureCatalog.common(COMMON),
				BloodlineFixtureCatalog.rare(RARE),
				BloodlineFixtureCatalog.founding(FOUNDING),
				BloodlineFixtureCatalog.inert(INERT),
			]
		)
	)


func teardown() -> void:
	BloodlineFixtureCatalog.teardown()


func _born(actor_id: StringName = &"child") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 5.0})
	BloodlineApi.attach(actor)
	return actor


func _own_sources(actor: Actor) -> Array:
	var out: Array = []
	for modifier in actor.stats._modifiers:
		if BloodlineState.is_own_source(modifier.source):
			out.append(String(modifier.source))
	out.sort()
	return out


func _own_traits(actor: Actor) -> Array:
	var out: Array = []
	for trait_id in actor.traits.to_array():
		# `str()`, not `String()`: this build has no callable `String` constructor for a
		# StringName, so `String(trait_id)` throws. A throw aborts the test mid-function,
		# which the runner reports as "the run above is incomplete" rather than as a
		# failure — the suite would still print a pass count while this never ran.
		var text := str(trait_id)
		if text.begins_with(BloodlineState.TRAIT_PREFIX) or text.begins_with("t_"):
			out.append(text)
	out.sort()
	return out


func _fingerprint(actor: Actor) -> Dictionary:
	return {
		"state": BloodlineApi.state(actor),
		"traits": _own_traits(actor),
		"sources": _own_sources(actor),
		"peak": actor.stats.derived(BloodlineStats.PEAK_PURITY),
	}


# --- The constants are the module's contract ---------------------------------


func test_the_module_constants_are_the_published_ones() -> void:
	# ADR 0063 owns these three numbers. The reachability test owns them independently;
	# this one asserts the CODE reads them rather than the test's own copy.
	assert_almost_eq(BloodlineState.RETENTION, 0.70, "retention")
	assert_almost_eq(BloodlineState.FLOOR, 0.15, "floor")
	assert_almost_eq(BloodlineState.BLEND_CONSTANT, 0.045, "blend constant")
	assert_almost_eq(
		BloodlineState.BLEND_CONSTANT,
		BloodlineState.FLOOR * (1.0 - BloodlineState.RETENTION),
		"the constant is derived from the floor, not picked"
	)
	assert_almost_eq(BloodlineState.first_generation_ceiling(), 0.745, "one-generation ceiling")


func test_the_facade_tiers_sit_inside_the_reachable_band() -> void:
	# Every threshold must be strictly above the floor (or it is granted to everyone
	# forever) and at or below the ceiling (or it is dead content). This is the check
	# whose absence let ADR 0063's first draft ship two unreachable tiers.
	for tier in [BloodlineApi.TIER_COMMON, BloodlineApi.TIER_RARE, BloodlineApi.TIER_FOUNDING]:
		assert_eq(tier > BloodlineState.FLOOR, true, "%f is above the floor" % tier)
		assert_eq(tier <= 0.745, true, "%f is reachable in one generation" % tier)


# --- inherit: the mean is load-bearing ---------------------------------------


func test_inherit_is_the_published_affine_map() -> void:
	assert_almost_eq(BloodlineState.inherit(1.0, 1.0), 0.745, "pure by pure")
	assert_almost_eq(BloodlineState.inherit(1.0, 0.0), 0.395, "carrier and outsider")
	assert_almost_eq(BloodlineState.inherit(0.395, 0.0), 0.183, "and the next generation", 0.0005)
	assert_almost_eq(BloodlineState.inherit(0.6, 0.6), 0.465, "a mixed pairing")


func test_inherit_uses_the_mean_so_a_strong_strong_pairing_beats_a_strong_weak_one() -> void:
	# The property the marriage-and-alliance layer rests on. Blending toward the
	# maximum would make these two pairings identical, and the choice of spouse would
	# stop being a choice at all.
	var strong := 1.0
	var weak := 0.2
	assert_eq(
		BloodlineState.inherit(strong, weak) < BloodlineState.inherit(strong, strong),
		true,
		"a weak partner is a measurable cost"
	)
	# The exact gap, so the cost cannot quietly shrink.
	assert_almost_eq(BloodlineState.inherit(strong, strong), 0.745, "strong by strong")
	assert_almost_eq(BloodlineState.inherit(strong, weak), 0.465, "strong by weak")


func test_inherit_is_order_independent_and_clamped_to_the_unit_interval() -> void:
	assert_almost_eq(
		BloodlineState.inherit(0.3, 0.8), BloodlineState.inherit(0.8, 0.3), "commutative"
	)
	assert_almost_eq(BloodlineState.inherit(1.0, 1.0), 0.745, "never above the ceiling")
	assert_eq(BloodlineState.inherit(-5.0, -5.0) >= 0.0, true, "and never below zero")


func test_inherit_dilutes_toward_the_floor_and_converges_on_it() -> void:
	var purity := 1.0
	for _generation in 80:
		purity = BloodlineState.inherit(purity, purity)
	# Selective breeding cannot compound: the two-sided line has the fixed point the ADR
	# authors as its floor, and every generation above that one only approaches it.
	assert_almost_eq(purity, BloodlineState.FLOOR, "an unbroken line settles at the floor")
	# The one-sided line's own fixed point is LOWER, because half the mean is dropped on
	# the floor instead of doubled. An outsider spouse therefore costs permanently, which
	# is exactly the tension the mean was kept for. The map is `x -> (x/2) * R + C`,
	# which fixes at `C / (2 * (1 - R)) = 0.045 / 0.6 = 0.075`.
	#
	# Asserted ANALYTICALLY, not by iteration: the map contracts by `R/2 = 0.35` per
	# generation, so even 60 generations still sits ~0.006 short of its own fixed point,
	# and an epsilon wide enough to cover that tail would also cover a wrong constant.
	# The closed form is the claim; the loop only shows the iteration heads for it.
	var carrier := 1.0
	for _generation in 60:
		carrier = BloodlineState.inherit(carrier, 0.0)
	var carrier_fixed_point: float = (
		BloodlineState.BLEND_CONSTANT / (2.0 * (1.0 - BloodlineState.RETENTION))
	)
	assert_almost_eq(carrier_fixed_point, 0.075, "the closed form is 0.075")
	assert_eq(carrier < carrier_fixed_point, true, "and the iteration still approaches it")
	assert_eq(carrier_fixed_point < BloodlineState.FLOOR, true, "and always will")


# --- The awake boundary ------------------------------------------------------


func test_is_awake_is_inclusive_at_exactly_the_threshold() -> void:
	var def := BloodlineCatalog.instance().bloodline_definition(RARE)
	assert_almost_eq(def.awaken_threshold, 0.55, "the authored bar")
	assert_eq(def.is_awake(0.55), true, "exactly at it is awake")
	assert_eq(def.is_awake(0.5499), false, "a hair under is not")
	assert_eq(def.is_awake(0.0), false, "and nothing at all is not")
	assert_eq(def.is_awake(1.0), true, "and pure is")


func test_purity_above_the_floor_alone_never_awakens_a_founding_lineage() -> void:
	# The founding bar is above what any second generation can carry, which is the
	# whole reason a founding lineage is worth protecting.
	var second := BloodlineState.inherit(0.745, 0.745)
	# Published to three decimals, as the ADR's chain table is. The exact value is
	# 0.5665, so the epsilon covers the published rounding rather than sitting exactly
	# on the boundary of it.
	assert_almost_eq(second, 0.567, "a second generation", 0.001)
	assert_eq(second >= BloodlineApi.TIER_FOUNDING, false, "which is below the founding bar")
	assert_eq(second >= BloodlineApi.TIER_RARE, true, "but clears the rare bar")


# --- resolve_inherited: the birth system's call -------------------------------


func _seed(actor: Actor, lineage_id: StringName, value: float) -> void:
	BloodlineApi.set_purity(actor, lineage_id, value)


func test_resolve_inherited_returns_the_union_of_both_parents_lineages() -> void:
	var a := _born(&"parent_a")
	var b := _born(&"parent_b")
	_seed(a, COMMON, 1.0)
	_seed(a, RARE, 0.6)
	_seed(b, FOUNDING, 0.9)
	var inherited := BloodlineApi.resolve_inherited(a, b)
	assert_eq(inherited.keys().size(), 3, "three lineages in, three out")
	assert_almost_eq(float(inherited[COMMON]), 0.395, "carried by one parent only")
	assert_almost_eq(
		float(inherited[COMMON]), BloodlineApi.inherit_from(a, b, COMMON), "same answer"
	)
	# A line carried by ONE parent only is diluted by a full zero from the other side,
	# which is what makes an outsider spouse a cost the ADR cares about. `inherit` takes
	# the MEAN, so a one-sided line keeps only `purity * 0.5 * RETENTION + BLEND_CONSTANT`:
	# 0.6 -> 0.6 * 0.35 + 0.045 = 0.255, and 0.9 -> 0.9 * 0.35 + 0.045 = 0.36.
	assert_almost_eq(inherited[RARE] as float, 0.255, "the weaker line, one-sided")
	assert_almost_eq(inherited[FOUNDING] as float, 0.36, "and the stronger, from the other side")


func test_resolve_inherited_carries_a_two_sided_lineage_and_omits_an_absent_one() -> void:
	var a := _born(&"a")
	var b := _born(&"b")
	_seed(a, RARE, 0.8)
	_seed(b, RARE, 0.6)
	var inherited := BloodlineApi.resolve_inherited(a, b)
	assert_eq(inherited.keys().size(), 1, "one lineage")
	assert_almost_eq(inherited[RARE] as float, 0.535, "blended from the mean of the two")
	assert_almost_eq(BloodlineState.inherit(0.8, 0.6), 0.535, "which is exactly inherit()")
	assert_eq(inherited.has(COMMON), false, "a lineage neither parent carries is absent, not 0.0")


func test_resolve_inherited_of_two_unblooded_parents_is_empty_and_never_throws() -> void:
	assert_eq(BloodlineApi.resolve_inherited(_born(), _born()), {}, "nothing in, nothing out")
	assert_eq(BloodlineApi.resolve_inherited(null, null), {}, "and nulls are not a crash")


func test_a_child_resolves_weakly_enough_that_a_founding_line_needs_a_near_pure_pairing() -> void:
	# The generator test: a founding lineage is only reachable by breeding true, which
	# is what makes it founding rather than merely rare.
	var a := _born(&"a")
	var b := _born(&"b")
	_seed(a, FOUNDING, 1.0)
	_seed(b, FOUNDING, 1.0)
	var child := BloodlineApi.resolve_inherited(a, b)
	assert_eq(
		(child[FOUNDING] as float) >= BloodlineApi.TIER_FOUNDING, true, "first generation clears it"
	)
	var next_gen: float = child[FOUNDING]
	var grandchild := BloodlineApi.inherit_from(
		_seed_holder(next_gen), _seed_holder(next_gen), FOUNDING
	)
	assert_eq(grandchild >= BloodlineApi.TIER_FOUNDING, false, "the second generation does not")


func _seed_holder(purity: float) -> Actor:
	# A throwaway actor carrying one lineage at `purity`, so the second generation is
	# expressed through the same resolver the birth system calls.
	var actor := Actor.new(&"gen")
	BloodlineApi.attach(actor)
	BloodlineApi.set_purity(actor, FOUNDING, purity)
	return actor


# --- The projection ----------------------------------------------------------


func test_an_awake_lineage_lands_its_percent_modifiers_in_derived() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, COMMON, 0.9)
	assert_eq(_own_sources(actor), ["bloodline:t_common"], "namespaced source")
	assert_almost_eq(BloodlineProjection.contribution(actor, Stat.MAX_HEALTH), 0.1, "on the stack")
	# max_health baseline is 50 + physique * 10 = 150.0; a 10% grant is 165.0.
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), 165.0, "and reached derived()")


func test_an_asleep_lineage_lands_no_modifier_but_still_mirrors_its_trait() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, COMMON, 0.1)
	assert_eq(_own_sources(actor), [], "asleep grants nothing")
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), 150.0, "and the baseline is untouched")
	# The mirror is the point: a dormant lineage is exactly what a lineage screen must
	# be able to show, and `has_trait` is how it is read.
	assert_eq(actor.traits.has(BloodlineState.trait_for(COMMON)), true, "still mirrored")
	assert_eq(BloodlineApi.is_awake(actor, COMMON), false, "but asleep")


func test_an_awakening_lineage_also_adds_its_authored_traits_and_a_strip_takes_both_back() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, INERT, 0.9)
	assert_eq(actor.traits.has(&"t_fixture_grant"), true, "the authored trait is granted")
	assert_eq(actor.traits.has(BloodlineState.trait_for(INERT)), true, "alongside the mirror")
	BloodlineProjection.strip(actor)
	assert_eq(actor.traits.has(&"t_fixture_grant"), false, "strip takes the authored trait back")
	assert_eq(actor.traits.has(BloodlineState.trait_for(INERT)), false, "and the mirror")
	# Stripping is a projection reset, not a transformation. Purity itself survives.
	assert_almost_eq(BloodlineApi.purity_of(actor, INERT), 0.9, "the ledger is unchanged")


func test_attaching_twice_produces_the_same_actor_the_first_time_produced() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, COMMON, 0.9)
	BloodlineApi.set_purity(actor, RARE, 0.6)
	var once := _fingerprint(actor)
	BloodlineApi.attach(actor)
	BloodlineApi.attach(actor)
	BloodlineApi.attach(actor)
	assert_eq(_fingerprint(actor), once, "attach is idempotent")
	assert_eq(actor.stats.provider_count(), 1, "and registers the provider exactly once")


func test_dropping_purity_below_the_bar_removes_the_modifier_and_keeps_the_mirror() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, COMMON, 0.9)
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), 165.0, "awake")
	BloodlineApi.set_purity(actor, COMMON, 0.2)
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), 150.0, "the grant is taken back")
	assert_eq(
		actor.traits.has(BloodlineState.trait_for(COMMON)), true, "and the line is still held"
	)
	assert_almost_eq(BloodlineApi.purity_of(actor, COMMON), 0.2, "at the new concentration")


func test_an_unknown_lineage_is_refused_and_changes_nothing() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, COMMON, 0.9)
	var before := _fingerprint(actor)
	assert_eq(BloodlineApi.set_purity(actor, &"t_no_such_line", 1.0), false, "refused")
	assert_eq(_fingerprint(actor), before, "and nothing moved")
	assert_eq(BloodlineApi.set_purity(null, COMMON, 1.0), false, "a null actor is refused too")


func test_an_unblooded_actor_attaches_clean_and_harmlessly() -> void:
	var actor := _born()
	assert_eq(BloodlineApi.awake(actor), [], "nothing awake")
	assert_almost_eq(BloodlineApi.purity_of(actor, COMMON), 0.0, "and nothing carried")
	assert_eq(_own_sources(actor), [], "nothing projected")
	assert_almost_eq(
		actor.stats.derived(BloodlineStats.PEAK_PURITY), 0.0, "the provider reads zero"
	)
	BloodlineApi.attach(null)
	assert_eq(BloodlineApi.awake(null), [], "and a null actor reads nothing")


# --- The gate ----------------------------------------------------------------


func test_the_verdicts_carry_only_ok_reason_and_unmet() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, RARE, 0.9)
	for requirement in [
		{},
		{"verb": &"is_awake", "id": String(RARE)},
		{"verb": &"purity_at_least", "id": String(RARE), "at": 0.95},
		{"verb": &"has_trait", "id": String(BloodlineState.trait_for(RARE))},
		{"verb": &"teleported"},
	]:
		var verdict := BloodlineApi.unmet(actor, requirement)
		assert_eq(verdict.keys().size(), 3, "exactly three keys for %s" % [requirement])
		assert_eq(BloodlineApi.unmet(actor, requirement), verdict, "the facade adds nothing")
		assert_eq((verdict["unmet"] as Array).is_empty(), bool(verdict["ok"]), "ok and unmet agree")


func test_an_unknown_verb_refuses_closed_and_names_itself() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, RARE, 0.9)
	var verdict := BloodlineApi.unmet(actor, {"verb": &"teleported"})
	assert_eq(bool(verdict["ok"]), false, "refused")
	assert_eq(String(verdict["reason"]), "unknown_verb", "as a refusal, not an unmet")
	var entry := (verdict["unmet"] as Array)[0] as Dictionary
	assert_eq(String(entry["kind"]), "gate", "it names the kind")
	assert_ne(String(entry["label"]), "", "with a renderable label")
	assert_ne(String(entry["label"]).contains("teleported"), false, "that names the verb")


func test_a_gate_naming_no_verb_or_an_unreadable_argument_is_refused() -> void:
	var actor := _born()
	for requirement in [
		{"id": String(RARE)},
		{"verb": &"is_awake"},
		{"verb": &"purity_at_least", "id": String(RARE)},
		{"verb": &"has_trait"},
		{"verb": &"all_of", "of": []},
		{"verb": &"is_awake", "id": String(&"t_never_authored")},
	]:
		var verdict := BloodlineApi.unmet(actor, requirement)
		assert_eq(bool(verdict["ok"]), false, "refused for %s" % [requirement])
		assert_ne(String(verdict["reason"]), "unmet", "and it is a refusal for %s" % [requirement])


func test_is_awake_passes_only_for_a_lineage_that_has_crossed_its_bar() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, RARE, 0.9)
	assert_eq(
		bool(BloodlineApi.unmet(actor, {"verb": &"is_awake", "id": String(RARE)})["ok"]),
		true,
		"held"
	)
	assert_eq(BloodlineApi.awake(actor), [RARE], "and listed by the facade")
	var missed := BloodlineApi.unmet(actor, {"verb": &"is_awake", "id": String(FOUNDING)})
	assert_eq(bool(missed["ok"]), false, "a line it is not")
	var entry := (missed["unmet"] as Array)[0] as Dictionary
	assert_eq(String(entry["kind"]), "awake", "as an awake complaint")
	assert_almost_eq(float(entry["required"]), 0.72, "required is the authored bar")
	assert_almost_eq(float(entry["actual"]), 0.0, "and actual is what it carries")


func test_purity_at_least_is_the_continuous_form_of_the_same_gate() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, RARE, 0.6)
	assert_eq(
		bool(
			(
				BloodlineApi
				. unmet(actor, {"verb": &"purity_at_least", "id": String(RARE), "at": 0.6})["ok"]
			)
		),
		true,
		"exactly at the bar passes"
	)
	var missed := BloodlineApi.unmet(
		actor, {"verb": &"purity_at_least", "id": String(RARE), "at": 0.61}
	)
	assert_eq(bool(missed["ok"]), false, "a hair over does not")
	assert_eq(String((missed["unmet"] as Array)[0]["kind"]), "purity", "as a purity complaint")


func test_has_trait_reads_the_mirror_and_nothing_else() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, RARE, 0.1)
	assert_eq(
		bool(
			(
				BloodlineApi
				. unmet(actor, {"verb": &"has_trait", "id": String(BloodlineState.trait_for(RARE))})["ok"]
			)
		),
		true,
		"a dormant line still answers a trait gate"
	)
	assert_eq(
		bool(BloodlineApi.unmet(actor, {"verb": &"has_trait", "id": String(RARE)})["ok"]),
		false,
		"a bare lineage id is not a trait id"
	)
	assert_eq(
		bool(
			BloodlineApi.unmet(actor, {"verb": &"has_trait", "id": String(&"race:stoneborn")})["ok"]
		),
		false,
		"and a sibling's namespace is not ours to answer"
	)


func test_the_composites_nest_and_report_every_unmet_child() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, RARE, 0.9)
	var nested := {
		"verb": &"all_of",
		"of":
		[
			{"verb": &"is_awake", "id": String(RARE)},
			{
				"verb": &"any_of",
				"of":
				[
					{"verb": &"is_awake", "id": String(FOUNDING)},
					{"verb": &"purity_at_least", "id": String(RARE), "at": 0.5},
				]
			},
		]
	}
	assert_eq(bool(BloodlineApi.unmet(actor, nested)["ok"]), true, "the deep branch passes")
	# `any_of` is still satisfied by the other branch, so the root keeps passing; the
	# appended leaf is what an `all_of` would have caught.
	nested["of"][1]["of"].append({"verb": &"is_awake", "id": String(COMMON)})
	assert_eq(bool(BloodlineApi.unmet(actor, nested)["ok"]), true, "still passes, on any_of")
	assert_eq(
		bool(
			(
				BloodlineApi
				. unmet(
					actor, {"verb": &"none_of", "of": [{"verb": &"is_awake", "id": String(COMMON)}]}
				)["ok"]
			)
		),
		true,
		"an unmet child satisfies none_of"
	)
	var all := {
		"verb": &"all_of",
		"of":
		[{"verb": &"is_awake", "id": String(FOUNDING)}, {"verb": &"is_awake", "id": String(COMMON)}]
	}
	var refused := BloodlineApi.unmet(actor, all)
	assert_eq((refused["unmet"] as Array).size(), 2, "both unmet leaves are reported")


func test_a_malformed_child_poisons_its_whole_composite() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, RARE, 0.9)
	var verdict := BloodlineApi.unmet(
		actor,
		{
			"verb": &"all_of",
			"of": [{"verb": &"is_awake", "id": String(RARE)}, {"verb": &"teleported"}]
		}
	)
	assert_eq(String(verdict["reason"]), "unknown_verb", "refuse-with-cause, not an unmet")


func test_the_gate_reads_the_ledger_and_not_a_stat_so_an_item_cannot_grant_a_lineage() -> void:
	# A stat can be raised by an item; a bloodline power must not be. A pure modifier
	# on a bloodline stat must therefore leave the gate shut.
	var actor := _born()
	BloodlineApi.set_purity(actor, RARE, 0.1)
	actor.stats.add_modifier(
		StatModifier.new(BloodlineStats.AWAKENED_COUNT, Stat.Op.FLAT, 5.0, &"item:granted_grant")
	)
	assert_almost_eq(actor.stats.derived(BloodlineStats.AWAKENED_COUNT), 5.0, "the stat moved")
	assert_eq(
		bool(BloodlineApi.unmet(actor, {"verb": &"is_awake", "id": String(RARE)})["ok"]),
		false,
		"and the gate did not"
	)


# --- The provider ------------------------------------------------------------


func test_the_provider_reports_the_ledger_through_the_attached_summary() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, COMMON, 0.9)
	BloodlineApi.set_purity(actor, RARE, 0.2)
	assert_almost_eq(actor.stats.derived(BloodlineStats.LINEAGE_COUNT), 2.0, "two carried")
	assert_almost_eq(actor.stats.derived(BloodlineStats.AWAKENED_COUNT), 1.0, "one awake")
	assert_almost_eq(actor.stats.derived(BloodlineStats.PEAK_PURITY), 0.9, "the strongest")
	assert_almost_eq(actor.stats.derived(BloodlineStats.MEAN_PURITY), 0.55, "the mean")
	assert_almost_eq(
		actor.stats.derived(BloodlineStats.BLOODLINE_POWER), 0.03, "a common line's worth"
	)


func test_a_purity_change_moves_the_providers_readout_without_a_second_attach() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, COMMON, 0.1)
	assert_almost_eq(actor.stats.derived(BloodlineStats.AWAKENED_COUNT), 0.0, "asleep")
	BloodlineApi.set_purity(actor, COMMON, 0.9)
	assert_almost_eq(
		actor.stats.derived(BloodlineStats.AWAKENED_COUNT), 1.0, "awake, with no re-attach"
	)


func test_a_stranger_casting_the_provider_alone_reads_the_same_component() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, FOUNDING, 1.0)
	var values := BloodlineProvider.new().contribute(_context(actor))
	assert_almost_eq(float(values[BloodlineStats.AWAKENED_COUNT]), 1.0, "the awake set is readable")
	assert_almost_eq(float(values[BloodlineStats.PEAK_PURITY]), 1.0, "and the concentration")
	# A founding line's 0.15 grant is weighted 1.0 by the tier read, capped at 1.0.
	assert_almost_eq(float(values[BloodlineStats.BLOODLINE_POWER]), 0.15, "and the power aggregate")


func test_the_provider_contributes_nothing_before_the_module_is_attached() -> void:
	var actor := Actor.new(&"bare")
	assert_almost_eq(actor.stats.derived(BloodlineStats.LINEAGE_COUNT), 0.0, "no summary, no stats")
	var values := BloodlineProvider.new().contribute(_context(actor))
	assert_eq(values.is_empty(), true, "and the provider contributes nothing at all")


## The context `Actor` builds internally, so the provider can be cast outside a module
## attach exactly as `test_race_attach.gd` does. Six arguments: `StatContext._init` takes
## the six dictionaries plus an optional untyped meridian reference.
func _context(actor: Actor) -> StatContext:
	return StatContext.new(
		actor.stats.base_ref(),
		actor.resources,
		actor.traits,
		actor.affinities,
		actor.paths,
		actor.components
	)
