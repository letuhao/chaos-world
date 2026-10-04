extends TestCase

## BL-0114 (second wave): the two ids the mind module RENAMED rather than folded
## into core, and the guard that keeps them retired.
##
## `test_mind_stats.gd` already guards the four BL-0163 ids with
## `test_the_deleted_sea_and_rate_ids_stay_deleted`, and it left these two
## unguarded. That gap is the whole reason this file exists: ADR 0071's rename
## made `mind_focus_chance` and `mind_avoidance` the published names, but nothing
## stopped a later wave from re-planting `const CRITICAL_CHANCE := &"critical_chance"`
## beside them, where it reads as a deliberate second dial rather than as the
## duplicate it would be. A re-planted twin is the exact hazard BL-0114 reported,
## so the retirement is asserted rather than remembered.
##
## ## Why a guard and not a note
##
## BL-0114's hazard was never the duplication itself -- it was AMBIGUITY, a second
## id for a concept core already owns, resolvable the wrong way by a future combat
## system with no error. A rename removes the ambiguity; only an assertion keeps it
## removed.
##
## ## The unconditional liveness term, and why it is here
##
## Every check below is either unconditional or runs over a FIXED, non-empty list.
## That is the point of this file's first case. `Probe.module_code_all()` returns
## `""` if the module directory ever moves or stops resolving, and every
## `contains(...) == false` assertion then passes on an empty string -- a guard
## switched off by the absence of what it watches, which this repo has now done
## three times. So the first case proves the scan is reading real, current code
## AND that the rename it guards is still the code's shape, with nothing filtered
## and no loop around it. Emptying `RETIRED` is likewise red rather than silent.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

## The two names ADR 0071 retired. `critical_chance` and `dodge_chance` were
## different StringNames from core's `Stat.CRIT_CHANCE` / `Stat.EVASION`, which is
## what made them a second dial on one idea. Fixed at two on purpose: a shorter
## list is a guard that has quietly stopped guarding.
const RETIRED := [&"critical_chance", &"dodge_chance"]

# --- Liveness: this guard is pointed at something real -------------------------


## The scan reads the module, the retired list is whole, and both replacements are
## still the module's declared ids. No loop, no filter: this is the term that fails
## when the guard is watching nothing.
func test_the_retirement_guard_is_pointed_at_the_renamed_code() -> void:
	var code := Probe.module_code_all()
	assert_ne(code.strip_edges(), "", "the module source scan returned code to check")
	assert_eq(RETIRED.size(), 2, "both renamed ids are still on the retired list")
	assert_eq(
		(
			code.contains(String(MindStats.MIND_FOCUS_CHANCE))
			and code.contains(String(MindStats.MIND_AVOIDANCE))
		),
		true,
		"both replacements are still declared in the module's code"
	)


# --- The retirement itself ----------------------------------------------------


## No file in `mind_cultivation` declares or emits a retired name. SOURCE across
## the whole module rather than the live values, because that is the only check
## that catches a deleted id returning under a second spelling: a numerically
## identical private copy is invisible to every value assertion. Comments are
## stripped by the probe, since the docblocks recording WHY each id was retired
## necessarily spell the ids out.
func test_the_renamed_ids_are_not_re_planted_anywhere_in_the_module() -> void:
	var code := Probe.module_code_all()
	for gone in RETIRED:
		assert_eq(
			code.contains(String(gone)),
			false,
			"no file in mind_cultivation declares or emits %s" % String(gone)
		)


## And nothing derives them at runtime -- the half a source read cannot reach.
func test_the_retired_ids_are_never_derived() -> void:
	for gone in RETIRED:
		var actor := Actor.new(&"renamed_probe", {})
		MindCultivationApi.attach(actor)
		MindCultivationApi.attach_sea(actor)
		actor.mark_stats_dirty()
		assert_eq(
			actor.stats.derived_all().has(gone),
			false,
			"%s is not a derived stat on a mind actor" % String(gone)
		)


## The runtime half, once rather than per id: a mind actor DOES derive both
## replacements. Without this the two cases above also pass on a module that emits
## nothing at all, which is what "the thing I watch disappeared" looks like.
func test_a_mind_actor_derives_the_replacements_the_rename_installed() -> void:
	var actor := Actor.new(
		&"renamed_live",
		{Stat.WILL: 10.0, MindStats.MENTAL_CLARITY: 15.0, MindStats.PERCEPTION: 20.0}
	)
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	actor.mark_stats_dirty()
	var derived := actor.stats.derived_all()
	for current in [MindStats.MIND_FOCUS_CHANCE, MindStats.MIND_AVOIDANCE]:
		assert_eq(derived.has(current), true, "%s is derived" % String(current))


# --- The generalisation: no mind id is a core id -------------------------------


## Core still owns the two concepts, under names the mind module must not take.
## Unconditional, and asserted against the literal strings: disjointness that
## passes because core renamed its own ids out of the way is not disjointness.
func test_core_still_owns_the_two_concepts_under_its_own_names() -> void:
	assert_eq(String(Stat.CRIT_CHANCE), "crit_chance", "core's crit chance id")
	assert_eq(String(Stat.EVASION), "evasion", "core's evasion id")
	assert_eq(
		RETIRED.has(Stat.CRIT_CHANCE) or RETIRED.has(Stat.EVASION),
		false,
		"neither retired mind id is a core id under a different spelling"
	)


## No id the mind module publishes may BE a core stat id. Weaker than BL-0114's own
## concern -- the twins differed in name -- but it is the one part of the rule that
## generalises to ids nobody has thought of yet, and it costs one pass over a list
## core owns and the module therefore cannot drift from.
##
## ## Why this compares `BASE_ATTRIBUTES` and not `BASE_ATTRIBUTES + RATE_STATS`
##
## It used to compare against both, and inferring ownership from `RATE_STATS` was wrong
## twice over. Membership there is a claim about an id's SHAPE, not about who owns it:
## BL-0675 registered `mind_focus_chance`, `mind_avoidance` and `illusion_resistance`
## there because a FLAT on a fraction must be refused and that array is the only list
## both content gates read. An id being listed there says nothing about who derives it,
## so the comparison below would have failed on ids that are perfectly the module's own.
##
## Ownership is therefore PROBED, which is what `test_combat_stats_shape.gd:116` had to
## do for the same reason and after the same class of false green (BL-0362: the old
## combat guard compared `Stat.BASE_ATTRIBUTES + Stat.RATE_STATS`, core's derived ids are
## in NEITHER list, and the collision passed). A list can only ever report what someone
## remembered to put in it; an `ActorStats` read reports what the engine derives.
func test_no_mind_stat_id_is_also_a_core_stat_id() -> void:
	var mine := [
		MindStats.PERCEPTION,
		MindStats.MENTAL_CLARITY,
		MindStats.MENTAL_ATTACK,
		MindStats.MENTAL_DEFENSE,
		MindStats.SPIRITUAL_SENSE_RANGE,
		MindStats.MIND_FOCUS_CHANCE,
		MindStats.MIND_AVOIDANCE,
		MindStats.MIND_TECHNIQUE_POWER,
		MindStats.ILLUSION_RESISTANCE,
	]
	# Both sides asserted non-empty before the loop: an empty `mine` would make
	# every membership test below trivially true, which is the vacuous guard again.
	assert_eq(mine.size() >= 8, true, "the mind stat surface this checks is not empty")
	assert_eq(
		Stat.BASE_ATTRIBUTES.size() >= 7,
		true,
		"core's base attribute list this compares against is not empty"
	)
	for stat_id in mine:
		assert_eq(
			Stat.BASE_ATTRIBUTES.has(stat_id),
			false,
			"%s is not one of core's declared base attributes" % String(stat_id)
		)
	# The probe. Every base attribute is set generously and no provider is attached, so a
	# core-derived id reads non-zero and a module-owned one reads exactly 0.0 (backed at
	# `0.0` by `core/actor_stats.gd:187-189`). If core ever starts deriving one of these
	# strings, this fails; a list comparison could not tell.
	var generous := {}
	for stat_id in Stat.BASE_ATTRIBUTES:
		generous[stat_id] = 100.0
	var probe := Actor.new(&"probe", generous)
	for stat_id in mine:
		assert_almost_eq(
			probe.stats.derived(stat_id),
			0.0,
			(
				(
					"%s is derived by nothing, so no other owner can reach it -- a non-zero "
					% String(stat_id)
				)
				+ "here means core or another provider already owns this string"
			)
		)
	# The negative control, so the probe is falsifiable rather than vacuous: the same actor
	# DOES derive a non-zero for a core id that names a real derived stat, which is
	# precisely what the loop above is comparing against.
	assert_ne(
		probe.stats.derived(Stat.CRIT_CHANCE),
		0.0,
		"core's own CRIT_CHANCE is non-zero on this probe"
	)
