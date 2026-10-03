extends TestCase

## BL-0154 reachability audit: does anything the game itself computes DEPEND on a
## number this module publishes, and is that dependence live?
##
## ## The question, and why the recorded answer was stale
##
## BL-0154 said "filling the Sea of Consciousness changes no stat anything reads"
## and named `MindProvider`'s discarded `mind_power_ratio`. The local is gone. The
## conclusion was measured against a tree where ADR 0071's `MindDamage` did not
## exist, and it DOES: `combat_engine/mind_damage.gd`, bound to a mind actor by
## the composition root (`app/combat_boot.gd:143-151`) and reading six of the seven
## ids this module publishes. So the honest answer is neither "wire it" nor
## "delete it" -- it is that the wiring landed, and the part of it that did NOT
## land is the input those terms share.
##
## ## The enumeration, as a machine-checked fact
##
## Every id this module publishes, and who reads it in `res://src`:
##
## - `mental_attack`       -> `mind_damage.gd:228` (`_mind_stat`, attacker side)
## - `mental_defense`      -> `mind_damage.gd:230` (`_mind_stat`, target side)
## - `illusion_resistance` -> `mind_damage.gd:575` (`_mind_stat`, OBSCURE only)
## - `mind_focus_chance`   -> `mind_damage.gd:550` (`_mind_stat`, spends FOCUS_MULT)
## - `mind_avoidance`      -> `mind_damage.gd:563` (`_mind_stat`, damps coherence)
## - `mind_technique_power`-> `combat_damage.tres:39` `mind_deviation_stat`, read at
##                            `mind_damage.gd:415-418` (`apply_deviation` zeroing it)
## - `spiritual_sense_range`-> NO reader. `ui/panels/stat_presenter.gd:134` only,
##                            which ADR 0124 calls a readout and not a reader.
## - `sea_capacity`        -> NO reader, for the same reason
##                            (`stat_presenter.gd:144`). BL-0142 owns it.
##
## The first half is asserted from `mind_damage.gd`'s own CODE, so deleting a
## reader there goes red here. The second half is asserted as ABSENCE, so the
## day someone wires `spiritual_sense_range` this file fails and the enumeration
## gets updated deliberately rather than rotting into a wrong claim.
##
## ## What a player can observe, proven through the facade only
##
## No test here calls `MindProvider.contribute`. The actor is built and every
## verb is a `MindCultivationApi` call, and the numbers are read off the actor's
## public stat bag and off the mechanism the composition root BOUND -- the seam,
## not the internals.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

const RANK := &"qi_refining"
const MIND_DAMAGE_PATH := "res://src/modules/combat_engine/mind_damage.gd"
const COMBAT_BOOT_PATH := "res://src/app/combat_boot.gd"

## The ids `MindDamage` resolves through `_mind_stat(tuning, "<id>")`. That call
## is the resolution site, not a mention: the id only reaches the actor's stat
## bag because the tuning's prefix is prepended to it there.
const RESOLVED_IDS := [
	MindStats.MENTAL_ATTACK,
	MindStats.MENTAL_DEFENSE,
	MindStats.MIND_FOCUS_CHANCE,
	MindStats.MIND_AVOIDANCE,
	MindStats.ILLUSION_RESISTANCE,
]

## Published, and read by NOTHING that changes an outcome. Pinned as absence so
## a new reader is a deliberate edit here rather than a silent change of claim.
const DISPLAY_ONLY_IDS := [
	MindStats.SPIRITUAL_SENSE_RANGE,
	MindStats.SEA_CAPACITY,
]

## ADR 0071's nine numbers, by field name. A zero here is not a neutral default,
## it is a formula with a term switched off -- which is exactly what the docblock
## in `provider.gd` used to claim the shipped state was.
const ADR_0071_NUMBERS := [
	"mental_defense_cap",
	"illusion_resistance_cap",
	"coherence_damp",
	"focus_mult",
	"turbulence_to_clarity",
	"rupture_threshold",
	"rupture_bleed",
	"rupture_collapse_time",
]

## A channel climbs CLOSED -> OPEN -> EXPANDED -> STRENGTHENED, so a fresh one
## needs three elixirs. `MeridianState.REFINE_POWER_STEP` does not apply: only
## `get_power_bonus` counts STRENGTHENED, and that is the whole point.
const CHANNEL_STEPS := 3


## A file's CODE, with every whole-line `#` comment removed. Local rather than
## `Probe.module_code` because that helper is hardcoded to this module's own
## directory and the readers under audit live in two other ones.
func _code(path: String) -> String:
	var source := FileAccess.get_file_as_string(path)
	var kept: Array[String] = []
	for line in source.split("\n"):
		if not String(line).strip_edges().begins_with("#"):
			kept.append(String(line))
	return "\n".join(kept)


## A mind actor with the module and the sea attached and nothing earned.
##
## `PERCEPTION` and `MENTAL_CLARITY` are non-zero on purpose: `mental_attack` is
## built from them, so an actor with neither has a `0.0` base, `erosion` is
## `0.0`, and every assertion below would pass against a mechanism that read
## nothing at all. A degenerate fixture is how a reachability guard stops
## discriminating.
func _actor() -> Actor:
	var actor := (
		Actor
		. new(
			&"mind_reach",
			{
				Stat.WILL: 10.0,
				Stat.COMPREHENSION: 10.0,
				MindStats.PERCEPTION: 40.0,
				MindStats.MENTAL_CLARITY: 30.0,
				MindStats.SEA_CAPACITY: 100.0,
			}
		)
	)
	actor.set_path(PathState.new(MindPath.PATH_ID, RANK))
	actor.meridians.unlock_for_realm(RANK)
	MindCultivationApi.attach(actor)
	ItemsApi.attach(actor, 500)
	return actor


## The mechanism the COMPOSITION ROOT bound to this actor, and its own breakdown
## of one strike against itself.
##
## Self-duel on purpose: `AttackContext` takes an `Actor` per side and reads the
## live derived cache off it, so attacker and target being the same actor needs no
## second fixture and no hand-copied stat. `rng` is left null, which ADR 0067
## makes the deterministic answer -- no draw, no roll -- so `mind_focus_chance`
## and `mind_avoidance` are exercised at their READ and not at a dice outcome.
func _bound_parts(actor: Actor) -> Dictionary:
	var report: Dictionary = CombatBoot.bind_mechanisms(actor)
	assert_eq(bool(report.get("bound", false)), true, "the composition root bound a mechanism")
	var mechanism := CombatEngineApi.mechanism_of(actor)
	assert_ne(mechanism, null, "the bound mechanism is readable off the actor")
	if mechanism == null:
		return {}
	return mechanism.breakdown(AttackContext.new(actor, actor))


# --- the enumeration, machine-checked -----------------------------------------


## The headline correction. `MindDamage` exists, and the composition root binds
## it to a mind actor, so the six ids below are read by production code rather
## than described by a docblock that says the mechanism is unbuilt.
func test_the_composition_root_binds_the_mind_mechanism_to_a_mind_actor() -> void:
	var actor := _actor()
	var report: Dictionary = CombatBoot.bind_mechanisms(actor)
	assert_eq(
		String(report.get("mechanism", "")),
		"MindDamage",
		"a mind-only actor binds the mind mechanism"
	)
	assert_eq(CombatEngineApi.has_mechanism(actor), true, "and the binding is really there")
	assert_eq(String(report.get("reason", "x")), "", "a bound actor reports no refusal reason")


## Every id this module publishes that a mechanism resolves, is resolved through
## the ONE call that makes the tuning's prefix reach the actor's stat bag.
## Asserted against `mind_damage.gd`'s code, so a dropped reader fails here.
func test_every_resolved_id_is_named_at_the_mechanisms_resolution_site() -> void:
	var code := _code(MIND_DAMAGE_PATH)
	assert_ne(code, "", "mind_damage.gd is readable")
	for id in RESOLVED_IDS:
		assert_eq(
			code.contains('_mind_stat(tuning, "%s")' % String(id)),
			true,
			"MindDamage resolves %s through _mind_stat" % String(id)
		)


## The seventh: `mind_technique_power` is not resolved through `_mind_stat` but
## through the tuning's `mind_deviation_stat`, because a collapse zeroes it rather
## than reading it into the formula. Both halves are asserted, so an id renamed
## on one side and not the other fails rather than reading 0.0 forever.
func test_the_collapse_reads_this_modules_published_technique_power() -> void:
	var code := _code(MIND_DAMAGE_PATH)
	assert_eq(
		code.contains("mind_deviation_stat"), true, "apply_deviation reads the tuning's own id"
	)
	assert_eq(
		String(CombatTuning.shipped().mind_deviation_stat),
		String(MindStats.MIND_TECHNIQUE_POWER),
		"the shipped tuning names the id this module publishes"
	)


## The two published ids with NO reader that changes an outcome, asserted as
## absence. `stat_presenter.gd` listing them is a readout (ADR 0124's own
## definition), not a consumer.
func test_the_two_unread_ids_are_unread_and_that_is_pinned() -> void:
	var code := _code(MIND_DAMAGE_PATH)
	for id in DISPLAY_ONLY_IDS:
		assert_eq(
			code.contains('"%s"' % String(id)),
			false,
			"%s has no reader in the mind mechanism, so this claim stays true" % String(id)
		)


## The load-bearing half of the enumeration: the shipped tuning resolves those
## ids to the BARE names, so the ids `MindProvider` publishes are exactly the ids
## combat looks up. A non-empty prefix would leave every term reading 0.0 while
## every assertion above still passed, because the strings would still match.
func test_the_shipped_tuning_resolves_the_bare_ids_and_carries_live_numbers() -> void:
	var tuning := CombatTuning.shipped()
	assert_ne(tuning, null, "the shipped tuning loads")
	if tuning == null:
		return
	assert_eq(
		String(tuning.mind_stat_prefix),
		"",
		"an empty prefix means the mechanism looks up exactly the ids published here"
	)
	assert_eq(
		StringName(tuning.sea_component),
		MindCultivationApi.SEA_COMPONENT,
		"and it finds the sea under the key this module's facade publishes"
	)
	assert_eq(
		StringName(tuning.awareness_pool_id),
		MindCultivationApi.AWARENESS,
		"and the awareness reserve is this module's pool"
	)
	for field in ADR_0071_NUMBERS:
		var value: Variant = tuning.get(field)
		assert_eq(
			float(value) > 0.0,
			true,
			"ADR 0071's %s is live in the shipped tuning, not defaulted to zero" % String(field)
		)


# --- what a player can observe ------------------------------------------------


## The seam, restated as a number: the `mental_defense` the bound mechanism
## computed IS the `mental_defense` this module published, read off the actor's
## public bag. Not `contribute`, not a fixture pin -- the two agree because one
## is the other's reader.
func test_the_bound_mechanism_reads_the_number_this_module_published() -> void:
	var actor := _actor()
	# `cultivate` is what runs `synchronize`, so it is what sizes the sea this
	# mechanism divides by. One sitting is enough; the bound is a canary.
	for _sitting in Probe.FILL_BOUND:
		if actor.stats.derived(MindStats.MENTAL_ATTACK) > 0.0:
			break
		MindCultivationApi.cultivate(actor)
	var parts := _bound_parts(actor)
	assert_ne(parts, {}, "the bound mechanism produced a breakdown")
	if parts.is_empty():
		return
	assert_eq(bool(parts.get("sea_bound", false)), true, "and it found this module's sea")
	assert_almost_eq(
		float(parts.get("mental_attack", -1.0)),
		actor.stats.derived(MindStats.MENTAL_ATTACK),
		"the strike's attack is the attack this module published"
	)
	assert_almost_eq(
		float(parts.get("mental_defense", -1.0)),
		actor.stats.derived(MindStats.MENTAL_DEFENSE),
		"and its defence is the defence this module published"
	)
	assert_eq(
		float(parts.get("erosion", 0.0)) > 0.0,
		true,
		"so a mind strike erodes something: the fixture is not degenerate"
	)


## THE player-visible consequence, and the answer to BL-0154's real question.
##
## Training a mind channel to STRENGTHENED raises `MeridianNetwork.get_power_bonus`,
## which `MindProvider` multiplies into `mental_defense` and `mind_technique_power`
## (ADR 0016: "Strengthening -- increases mind technique power and mental
## defense"). `MindDamage` reads the first as its mitigation. So the erosion a
## mind strike delivers FALLS, through the facade, from a stat this module owns.
##
## This is the assertion a reader of `provider.gd` should want: it dies the moment
## `meridian_power` stops reaching the published defence, which is the exact
## regression MUTATION-A below reproduces.
func test_training_a_mind_channel_lowers_the_erosion_the_mechanism_resolves() -> void:
	var actor := _actor()
	for _sitting in Probe.FILL_BOUND:
		if actor.stats.derived(MindStats.MENTAL_ATTACK) > 0.0:
			break
		MindCultivationApi.cultivate(actor)
	var before := _bound_parts(actor)
	var defence_before := actor.stats.derived(MindStats.MENTAL_DEFENSE)
	var technique_before := actor.stats.derived(MindStats.MIND_TECHNIQUE_POWER)
	var erosion_before := float(before.get("total", 0.0))
	assert_eq(
		float(actor.meridians.get_power_bonus()) > 0.0,
		false,
		"an untrained network grants no power bonus to begin with"
	)

	# The production verb, once per state, for every channel this realm demands.
	var seed := MindRealmSeed.for_realm(RANK)
	assert_ne(seed, null, "the R1 seed loads")
	if seed == null:
		return
	for meridian_id in seed.required_meridians:
		for _step in CHANNEL_STEPS:
			Probe.stock(actor, seed.training_item)
			MindCultivationApi.train_channel(actor, meridian_id)
	assert_eq(
		float(actor.meridians.get_power_bonus()) > 0.0, true, "strengthened channels now grant one"
	)

	var after := _bound_parts(actor)
	assert_almost_eq(
		float(after.get("mental_defense", -1.0)),
		actor.stats.derived(MindStats.MENTAL_DEFENSE),
		"the mechanism still reads this module's published defence"
	)
	assert_eq(
		float(after.get("mental_defense", 0.0)) > defence_before,
		true,
		"training a channel RAISES the published mental defence"
	)
	assert_eq(
		float(after.get("mitigation", 0.0)) > float(before.get("mitigation", 0.0)),
		true,
		"and so raises the mitigation the mechanism applies"
	)
	assert_eq(
		float(after.get("total", 1.0)) < erosion_before,
		true,
		"so a mind strike erodes strictly less of the sea: the cultivate step has teeth"
	)
	# `total` alone does NOT isolate the defence, and asserting it as if it did is
	# a guard that passes for the wrong reason: `train_channel` also calls
	# `synchronize`, which raises `structural_capacity` through the meridian
	# capacity bonus, and that is ADR 0071's DENOMINATOR. So `erosion` falls on
	# its own and `total` falls with it even if the defence were never touched.
	# `total / erosion` IS `1 - mitigation`, which cancels the denominator exactly
	# and leaves the defence this module published. MUTATION-A (meridian_power
	# pinned to 0.0) kills this line and no other.
	assert_eq(
		_defence_share(after) < _defence_share(before),
		true,
		"and the DEFENCE share of that strike fell once the denominator is cancelled"
	)
	assert_eq(
		actor.stats.derived(MindStats.MIND_TECHNIQUE_POWER) > technique_before,
		true,
		"and the published technique power moved with it"
	)


## `1 - mitigation`, read off a breakdown as `total / erosion`.
##
## `MindDamage` publishes both halves (`mind_damage.gd:250,253`), and their
## quotient is exactly the multiplier S5 applied -- so this reconstructs the
## defence contribution without restating the formula, which is ADR 0124's rule
## about a readout never becoming a second copy of the arithmetic.
func _defence_share(parts: Dictionary) -> float:
	var erosion := float(parts.get("erosion", 0.0))
	if erosion <= 0.0:
		return -1.0
	return float(parts.get("total", 0.0)) / erosion


## The seventh id's consequence: a collapsing sea disarms its loser for a minute
## by flat-zeroing `mind_technique_power` (`apply_deviation`). So that id is read
## by production code and the read changes an outcome.
func test_a_collapsing_sea_disarms_the_loser_through_the_published_stat() -> void:
	var actor := _actor()
	for _sitting in Probe.FILL_BOUND:
		if actor.stats.derived(MindStats.MENTAL_ATTACK) > 0.0:
			break
		MindCultivationApi.cultivate(actor)
	var before := actor.stats.derived(MindStats.MIND_TECHNIQUE_POWER)
	assert_eq(before > 0.0, true, "the fixture publishes a real technique power")
	var applied: StringName = MindDamage.apply_deviation(actor)
	assert_ne(applied, &"", "a collapse applies the deviation status")
	actor.mark_stats_dirty()
	assert_almost_eq(
		actor.stats.derived(MindStats.MIND_TECHNIQUE_POWER),
		0.0,
		"and the published technique power is zeroed, so the loser is disarmed"
	)


## ## The one term that is NOT live, stated rather than left to rot
##
## `mind_focus_chance` and `mind_avoidance` each carry an `awareness_ratio` term,
## and ADR 0071's `coherence` is built from the same reserve. Nothing in
## `res://src` ever WRITES the `awareness` pool: `attach` creates it
## (`api.gd:209`), `MindDamage` drains it as a reported delta, and no verb, item
## or technique grants it. So `awareness_ratio` is a constant `0.0`, ADR 0071's
## `COHERENCE_DAMP` is inert, and the erosion Kind `ATTEND` drains nothing.
##
## That is a real unwired gap and it is NOT this module's to close -- the writer
## belongs to `training.gd`, and what should fund awareness (ADR 0013 calls it
## "perceptual acuity, affects detection/crit/dodge"; ADR 0071 calls it "the
## depleting AWARENESS reserve") is a design question needing its own ADR. This
## assertion exists so the gap is a FACT the build knows about rather than a
## silence, and so the day a writer appears it goes red and someone checks
## whether ADR 0071's "1.0 -> 0.5 at full awareness" now holds.
func test_the_awareness_terms_are_inert_and_that_is_pinned() -> void:
	var actor := _actor()
	MindCultivationApi.cultivate(actor)
	var pool: Variant = actor.resource(MindCultivationApi.AWARENESS)
	assert_ne(pool, null, "the awareness reserve exists")
	if pool == null:
		return
	assert_almost_eq(float(pool.get("current")), 0.0, "and nothing in src ever grants any")
	# The reserve is SCALED and empty, not unscaled. That distinction matters:
	# an absent pool would make every awareness term read 0.0 through the
	# degradation branch instead, and the two are different failures -- one is a
	# reserve nobody funds, the other is a reserve that does not exist.
	assert_eq(
		float(pool.get("maximum")) > 0.0,
		true,
		"the reserve has a scale, so the zero above is an empty reserve not an absent one"
	)
	var parts := _bound_parts(actor)
	assert_almost_eq(
		float(parts.get("awareness_ratio", -1.0)),
		0.0,
		"every awareness-derived term therefore reads zero"
	)
	assert_almost_eq(
		float(parts.get("coherence", 0.0)),
		1.0,
		"so ADR 0071's COHERENCE_DAMP is currently a no-op, at any coherence build"
	)
