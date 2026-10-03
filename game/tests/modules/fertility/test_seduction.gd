extends TestCase

## `Seduction` is the producer the lineage stack never had. `FertilityApi.try_conceive`
## and everything behind it — `RaceApi.set_race`, `BloodlineApi.set_purity`,
## `resolve_offspring` — had no caller in `src/` at all, so in a running game no
## pregnancy had ever started (ADR 0108).
##
## These assert the four properties that make it a real producer rather than another
## unwired function: a refusal is a refusal (and writes NOTHING), a success writes
## exactly one status with the partner's lineage SNAPSHOT on it, a second attempt on a
## pregnant actor is refused, and the social floor means conception cannot reach a
## stranger.
##
## This suite lives under `modules/fertility` because the component does: the first test
## in this file is the one that names why it moved, and it is also the test that pins
## the graph that move produced. Read that test before re-pointing either edge.

const PARTNER := &"partner_yun"
const STANDING_CAUSE := &"a_standing_cause"
const SHIPPED_CAUSE := &"bound_in_intimacy"
const REQUIRED := 6.0


## An actor with both modules attached and a ledger to write into. Stats are the
## fertility suite's, so a roll of 0.0 and a roll of 1.0 mean the same thing in both
## places.
func _actor(id: StringName) -> Actor:
	var actor := (
		Actor
		. new(
			id,
			{
				Stat.PHYSIQUE: 10.0,
				Stat.SPIRIT: 10.0,
				Stat.APTITUDE: 10.0,
				Stat.COMPREHENSION: 10.0,
				Stat.WILL: 10.0,
				Stat.FORTUNE: 10.0,
				DualCultivationApi.FERTILITY: 20.0,
				DualCultivationApi.POTENCY: 10.0,
			}
		)
	)
	FertilityApi.attach(actor)
	SocialApi.attach(actor)
	return actor


## Install exactly ONE cause that clears the social floor, and use it to build every
## bond this suite needs.
##
## The catalog is a process-wide singleton with a `reset()` seam, and the shipped set
## is deliberately NOT used to open the gate: an authored cause is data a test owns,
## so this suite keeps passing whatever an author later does to the shipped vocabulary.
func setup() -> void:
	SocialCauseCatalog.instance().reset()
	var cause := SocialCauseDef.new()
	cause.id = STANDING_CAUSE
	cause.standing = REQUIRED
	cause.persistent = true
	SocialCauseCatalog.instance().install([cause])


## Hand the catalog back to the shipped vocabulary. This suite lives inside
## `modules/fertility`, so it now runs against suites that were previously separated
## from it by a directory boundary, and a catalog left holding one suite-private cause
## would leak into whatever ran next.
func teardown() -> void:
	SocialCauseCatalog.instance().install_defaults()


func _bonded(actor: Actor, partner_id: StringName) -> void:
	SocialApi.apply_cause(actor, partner_id, STANDING_CAUSE)


## --- The cycle, and how it was resolved ---------------------------------------


## ## The producer was authored in `dual_cultivation`, and that was a real cycle
##
## `fertility` has declared `dual_cultivation` since ADR 0002, because
## `FertilityProvider` reads `DualCultivationApi.FERTILITY`. A `Seduction` living in
## `dual_cultivation` needed a caller, and every caller of it needs `fertility` — so
## declaring `dual_cultivation -> fertility` closed
## `dual_cultivation -> fertility -> dual_cultivation` and `tools arch` printed
## `module dependency cycle` and exited 1. The cycle was structural, not accidental:
## the coupling was authored long ago (`FertilityApi.conception_chance` multiplies by
## the partner's `DualCultivationApi.POTENCY`) and what was missing was the producer,
## so the two halves of one mechanic each declared the other.
##
## ## What was NOT done, and why
##
## Deleting `fertility -> dual_cultivation` would have made the gate green by
## reporting less: `FertilityProvider.contribute` would still read
## `DualCultivationApi.FERTILITY`, but the gate would no longer know it. A trade of a
## reported structural fact for a hidden one is not a fix. So the reported edge stays,
## the producer moves, and the graph is below.
##
## ## What is asserted here
##
## `fertility` fans out to four modules and nothing points back at it.
## `dual_cultivation` is back to the two edges its own source uses, because the
## producer that needed the other two has left. Read this from the running project
## rather than from a comment: the path is derived from `res://`, so a registry edited
## somewhere else cannot leave this suite asserting a graph that no longer exists.
func test_the_producer_lives_where_the_declared_edges_are_acyclic() -> void:
	var deps := _declared_deps(&"dual_cultivation")
	assert_eq(deps.has(&"fertility"), false, "the producer has left dual_cultivation")
	assert_eq(deps.has(&"social"), false, "and took its social edge with it")
	assert_eq(deps.size(), 2, "so dual_cultivation is contracts and core, and nothing else")

	var mine := _declared_deps(&"fertility")
	# The edge ADR 0002 authored, still reported, and the whole reason the cycle was
	# resolved by moving a file rather than by deleting one.
	assert_eq(
		mine.has(&"dual_cultivation"),
		true,
		"fertility still declares dual_cultivation -- that coupling is a fact, not a bug"
	)
	assert_eq(mine.has(&"social"), true, "and gains the one edge the producer brought")
	assert_eq(
		mine.size(),
		6,
		"and nothing else: bloodline, contracts, core, dual_cultivation, race, social"
	)
	# The fan-out, stated as the acyclicity it is: a module nothing among these four
	# depends on.
	assert_eq(
		_declared_deps(&"social").has(&"fertility"),
		false,
		"social declares contracts and core only, so the new edge cannot close a loop"
	)


## `tools/arch/registry.json` is outside `res://`, so this suite cannot assert on it
## through a resource path — and `res://..` must be simplified before it reaches any
## path comparison, which is the reason `test_arch_rules` says so by name.
func _declared_deps(module_name: StringName) -> Array:
	var root := ProjectSettings.globalize_path("res://..").replace("\\", "/")
	var path := root.simplify_path().path_join("tools/arch/registry.json")
	if not FileAccess.file_exists(path):
		push_error("test_seduction: no module registry at %s" % path)
		return []
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return []
	var modules: Dictionary = (parsed as Dictionary).get("modules", {})
	var entry: Dictionary = modules.get(String(module_name), {}) as Dictionary
	var out: Array = []
	for dep in entry.get("deps", []):
		out.append(StringName(dep))
	return out


## --- Refusals: every one of them writes nothing ------------------------------


## A null partner is the one thing there is no ledger to argue about.
func test_a_null_partner_is_refused_before_anything_is_read() -> void:
	var actor := _actor(&"actor")
	var result := Seduction.attempt(actor, null, 0.0)
	assert_eq(result["ok"], false, "refused")
	assert_eq(result["reason"], Seduction.R_NO_PARTNER, "and it says why")
	assert_eq(actor.has_status(FertilityStats.PREGNANCY), false, "and no status was written")
	assert_eq(Seduction.chance(actor, null), 0.0, "the chance of nothing is zero")


## ## The gate: conception cannot happen to a stranger
##
## `SocialApi.attach` alone creates no bond, so a fresh pair is two people who have
## never met. The roll is 0.0 — a roll that always succeeds against `conception_chance`
## — and it still must not write a status, because the gate is checked BEFORE the roll
## is spent.
func test_two_actors_who_have_never_met_cannot_conceive() -> void:
	var actor := _actor(&"actor")
	var partner := _actor(PARTNER)
	var result := Seduction.attempt(actor, partner, 0.0)
	assert_eq(result["ok"], false, "refused with the best possible roll")
	assert_eq(result["reason"], Seduction.R_NO_BOND, "and the reason is the social gate")
	assert_eq(actor.has_status(FertilityStats.PREGNANCY), false, "no status was written")
	assert_eq(Seduction.chance(actor, partner), 0.0, "and the chance reads zero")
	# The ledger is untouched: a refusal creates no row and no cause.
	assert_eq(SocialApi.social_state(actor).bond_count(), 0, "not even an empty bond was created")


## A bond that exists but sits below the floor is the case that proves the gate is a
## threshold and not merely "have we met".
func test_a_bond_below_the_authored_floor_still_refuses() -> void:
	var actor := _actor(&"actor")
	var partner := _actor(PARTNER)
	SocialCauseCatalog.instance().reset()
	var thin := SocialCauseDef.new()
	thin.id = &"a_thin_cause"
	thin.standing = REQUIRED - 1.0
	SocialCauseCatalog.instance().install([thin])
	SocialApi.apply_cause(actor, PARTNER, &"a_thin_cause")
	assert_eq(Seduction.can_meet(actor, partner), false, "one point short of the floor")
	var result := Seduction.attempt(actor, partner, 0.0)
	assert_eq(result["reason"], Seduction.R_NO_BOND, "so the attempt is refused")
	assert_eq(actor.has_status(FertilityStats.PREGNANCY), false, "and writes no status")


## A roll that fails writes nothing. The status machine is never reached, so this is
## structural: `try_conceive` is called once, on the only path that was going to write.
func test_a_roll_of_one_writes_no_status() -> void:
	var actor := _actor(&"actor")
	var partner := _actor(PARTNER)
	_bonded(actor, PARTNER)
	var result := Seduction.attempt(actor, partner, 1.0)
	assert_eq(result["ok"], false, "refused")
	assert_eq(result["reason"], Seduction.R_ROLL_FAILED, "the outcome did not occur")
	assert_eq(actor.has_status(FertilityStats.PREGNANCY), false, "no status was written")
	assert_eq(
		SocialApi.bond_entry(actor, PARTNER)["causes"].has(Seduction.CAUSE),
		false,
		"and no cause was recorded: nothing happened, so nothing was logged"
	)


## --- Success: exactly one status, with the lineage captured -------------------


## The whole producer, end to end. ADR 0108's rule is the one that matters: the
## partner's race and purity are SNAPSHOT on the status at conception, so a child born
## later is a function of who conceived it rather than of who is standing nearby.
func test_a_successful_attempt_writes_one_pregnancy_carrying_the_partners_lineage() -> void:
	var actor := _actor(&"actor")
	var partner := _actor(PARTNER)
	RaceApi.attach(actor)
	RaceApi.attach(partner)
	RaceApi.set_race(actor, &"stoneborn")
	RaceApi.set_race(partner, &"tidecaller")
	BloodlineApi.attach(actor)
	BloodlineApi.attach(partner)
	BloodlineApi.set_purity(actor, &"hearthborn", 0.6)
	BloodlineApi.set_purity(partner, &"hearthborn", 0.6)
	_bonded(actor, PARTNER)

	var result := Seduction.attempt(actor, partner, 0.0)
	assert_eq(result["ok"], true, "conceived: %s" % String(result["reason"]))
	assert_eq(result["reason"], "", "with nothing to report")

	var status := FertilityApi.pregnancy(actor)
	assert_ne(status, null, "a pregnancy status exists")
	assert_eq(status.stage, PregnancyStatus.Stage.CONCEIVED, "at the first stage")
	assert_eq(status.partner_id, PARTNER, "naming the partner")
	assert_eq(status.partner_race, &"tidecaller", "with their race captured at conception")
	assert_almost_eq(
		float(status.partner_purity.get("hearthborn", 0.0)),
		0.6,
		"and their purity captured, so birth does not need them alive"
	)
	# Both rolls are stored rather than redrawn, which is what makes birth reproducible.
	assert_almost_eq(status.conception_roll, 0.0, "the conception roll is on the status")
	assert_almost_eq(status.race_roll, 0.0, "and the race roll, defaulted to it")

	var pregnancies := 0
	for entry in actor.statuses:
		if entry.id == FertilityStats.PREGNANCY:
			pregnancies += 1
	assert_eq(pregnancies, 1, "exactly one pregnancy status was written")


## The status is a SNAPSHOT, so mutating the partner afterwards must not reach the
## pregnancy. This is the assertion that would fail if conception read live state.
func test_the_lineage_is_snapshotted_not_read_live() -> void:
	var actor := _actor(&"actor")
	var partner := _actor(PARTNER)
	BloodlineApi.attach(actor)
	BloodlineApi.attach(partner)
	BloodlineApi.set_purity(partner, &"hearthborn", 0.9)
	_bonded(actor, PARTNER)
	Seduction.attempt(actor, partner, 0.0)
	BloodlineApi.set_purity(partner, &"hearthborn", 0.1)
	assert_almost_eq(
		float(FertilityApi.pregnancy(actor).partner_purity.get("hearthborn", 0.0)),
		0.9,
		"the pregnancy carries what the partner held when conception happened"
	)


## The attempt is recorded on the bond afterwards — that is what gives the world a
## readable answer to "what is the history of these two" (ADR 0091), and it is why the
## cause has to exist in the shipped vocabulary.
##
## This is the ONE test in the suite that installs the SHIPPED catalog, because
## `attempt` names the authored id and the catalog refuses an id it does not hold. Every
## other test opens the gate with its own cause so nothing here depends on an authored
## magnitude — and a test that quietly relied on `install_defaults()` throughout would
## pass against a catalog that had lost the cause entirely.
##
## The bond is therefore built out of two SHIPPED causes rather than the suite's own:
## one of them would not clear the floor, and two different ones is the shape
## `SocialBondClass` requires of a friendship anyway (ADR 0076).
func test_a_successful_attempt_records_the_authored_cause_on_the_bond() -> void:
	SocialCauseCatalog.instance().install_defaults()
	var actor := _actor(&"actor")
	var partner := _actor(PARTNER)
	SocialApi.apply_cause(actor, PARTNER, &"shared_brotherhood")
	SocialApi.apply_cause(actor, PARTNER, &"helped_in_combat")
	assert_eq(Seduction.can_meet(actor, partner), true, "two shipped acts clear the floor")
	assert_eq(Seduction.attempt(actor, partner, 0.0)["ok"], true, "conceived")
	var entry := SocialApi.bond_entry(actor, PARTNER)
	assert_eq(
		entry["last_cause"], String(SHIPPED_CAUSE), "the authored cause is the last one written"
	)
	assert_eq(entry["causes"].has(SHIPPED_CAUSE), true, "and it is in the ledger")
	# The cause lands at the floor the gate itself demands, so a pair that conceived once
	# keeps its standing through `SocialBond`'s persistent floor rather than drifting back.
	assert_eq(
		Seduction.can_meet(actor, partner),
		true,
		"the recorded act is also what keeps the pair above the social floor"
	)
	# One-sided, deliberately: `apply_cause` writes one bond and the mirror is the
	# calling module's transaction.
	assert_eq(
		SocialApi.bond_entry(partner, &"actor")["present"],
		false,
		"the mirror bond was not written from one call"
	)


## A body already carrying a pregnancy is refused before the roll is read, and a second
## attempt adds no second status.
func test_a_second_attempt_on_a_pregnant_actor_is_refused() -> void:
	var actor := _actor(&"actor")
	var partner := _actor(PARTNER)
	_bonded(actor, PARTNER)
	assert_eq(Seduction.attempt(actor, partner, 0.0)["ok"], true, "conceived once")
	var result := Seduction.attempt(actor, partner, 0.0)
	assert_eq(result["ok"], false, "refused")
	assert_eq(result["reason"], Seduction.R_ALREADY_PREGNANT, "and it names the state")
	assert_eq(Seduction.chance(actor, partner), 0.0, "the chance reads zero while pregnant")
	var pregnancies := 0
	for entry in actor.statuses:
		if entry.id == FertilityStats.PREGNANCY:
			pregnancies += 1
	assert_eq(pregnancies, 1, "still exactly one")


## --- The roll is always the caller's -----------------------------------------


## `chance` is a pure read and the roll is always a parameter, so the same pair answers
## the same way twice and a caller that owns the rng compares its own number against
## this one. No `randf` anywhere in the component is what makes that a guarantee rather
## than an observation.
func test_chance_is_a_pure_read_of_the_threshold_the_roll_is_compared_against() -> void:
	var actor := _actor(&"actor")
	var partner := _actor(PARTNER)
	_bonded(actor, PARTNER)
	var first := Seduction.chance(actor, partner)
	assert_almost_eq(first, FertilityApi.conception_chance(actor, partner), "the authored roll")
	assert_almost_eq(Seduction.chance(actor, partner), first, "reading it twice answers the same")
	assert_eq(first > 0.0, true, "an established pair has a real chance")
	assert_eq(first < 1.0, true, "and it is never certain")
	# The partner's potency is already inside `conception_chance` (ADR 0002), which is
	# the coupling that made `fertility` -- not `dual_cultivation` -- the natural home for
	# this component. The base is written through `set_base` and the actor marked dirty,
	# because `derived` caches -- a stat changed behind the cache would make this assert
	# against a stale number.
	var potent := _actor(&"potent_partner")
	potent.stats.set_base(DualCultivationApi.POTENCY, 40.0)
	potent.mark_stats_dirty()
	_bonded(actor, &"potent_partner")
	assert_eq(
		Seduction.chance(actor, potent) > first,
		true,
		"a partner with more potency raises the threshold's roll"
	)


func test_the_component_draws_no_random_number_of_its_own() -> void:
	var script := load("res://src/modules/fertility/seduction.gd") as GDScript
	var code: String = script.source_code
	var lines := ""
	for line in code.split("\n"):
		var stripped := String(line).strip_edges()
		if not stripped.begins_with("#"):
			lines += stripped + "\n"
	for forbidden in ["randf", "randi", "RandomNumberGenerator", "rand_range", "seed("]:
		assert_eq(
			lines.contains(forbidden),
			false,
			"the roll is always the caller's -- seduction.gd must not contain %s" % forbidden
		)
