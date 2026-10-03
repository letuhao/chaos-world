extends TestCase

## BL-0152: `preview.ready` must not promise an action `start` refuses.
##
## `start` refuses on two things — an attempt already in flight, and a body plan
## that closes the mind path (ADR 0109) — and `preview` owes a clause for each.
## Everything below is one rule: **a condition `preview` does not report is a
## button a screen offers that does nothing.** `ready` is the boolean the mind
## screen binds its Breakthrough press to, so every refusal has to be a clause.
##
## The claim under test is an AGREEMENT BETWEEN TWO FUNCTIONS ON ONE ACTOR, so
## every test here reads both sides: `preview` is what the screen reads, and
## `start`/`try_breakthrough` is what the press actually does. Asserting one side
## alone passes on the original code, where `preview` read `ready: true` while
## `start` refused — both halves were true at the same moment, which is the whole
## defect.
##
## Nothing below pastes a threshold, a clause or a roll. The pre-state is prepared
## through the production actions, the expected wording is read off the gate that
## produced it, and the outcome is decided by rolling the module's own published
## chance, so no expectation can drift from the code it describes.
##
## BL-0151 is measured here too, at the bottom: whether a player can be stranded
## holding an attempt is a property of the production entry point, not a matter of
## theory.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

const SOURCE := &"qi_refining"

## Candidates searched for a roll on the far side of the published chance. The
## search is over SEEDS, not over game state, so it cannot be a wait on a
## condition that fails to converge: every candidate either matches or the bound
## is reached.
const ROLL_BOUND := 64


## An actor standing in `SOURCE` with every one of the next realm's entry demands
## met through the production actions, and that realm's pill in hand — so the only
## thing left that can refuse a breakthrough is an attempt already in flight.
## `Probe.prepared` stocks the sea catalyst, channels and cultivation but not the
## pill, so the pill is stocked here from the seed the module itself names.
func _prepared() -> Actor:
	var actor := Probe.prepared(SOURCE)
	var target := RealmDefaults.ladder().next(SOURCE)
	Probe.stock(actor, MindRealmSeed.for_realm(target.id).breakthrough_item)
	return actor


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _conditions(report: Dictionary) -> Array:
	return report.get("conditions", [])


## The two halves of the claim, on one actor, with the pre-state proved first so
## a refusal afterwards is attributable to the attempt and to nothing else.
func test_preview_and_start_agree_while_an_attempt_is_in_flight() -> void:
	var actor := _prepared()
	var seed := MindRealmSeed.for_realm(RealmDefaults.ladder().next(SOURCE).id)
	var pills := ItemsApi.inventory(actor).count(seed.breakthrough_item)
	var rank := actor.path(MindPath.PATH_ID).rank_id

	# THE PRE-STATE. Not decoration: without it, everything below would also pass
	# on an actor that is unready for some unrelated reason, and the test would
	# prove nothing about the attempt.
	var before := MindCultivationApi.preview(actor)
	assert_eq(
		before.get("ready"),
		true,
		"a fully prepared actor is reported ready: %s" % [_conditions(before)]
	)
	assert_eq(_conditions(before).is_empty(), true, "so no clause is outstanding to name")
	assert_eq(String(before.get("attempt")), "", "and nothing is in flight yet")

	# THE STATE UNDER TEST. Only the two-phase lifecycle can hold an attempt open:
	# the facade's sole breakthrough verb resolves in the same call (BL-0151), so
	# this is the one place a test has to step behind the facade, and it steps
	# behind it for setup only — both halves of the claim are read through it.
	var started := MindAdvancement.start(actor, _rng(7))
	assert_ne(started, null, "the attempt commits while the gate is still open")
	assert_eq(
		ItemsApi.inventory(actor).count(seed.breakthrough_item),
		pills - 1,
		"and the commit spent the realm pill exactly once, not twice"
	)

	# `start` spends the realm pill, so the commit leaves a gate shut that has
	# nothing to do with the attempt. Stocking it back through the same production
	# helper the pre-state used leaves the attempt as the ONLY outstanding clause,
	# which is what makes the clause below attributable to it and not to some gate
	# that happens to be shut for an unrelated reason.
	Probe.stock(actor, seed.breakthrough_item)

	# SIDE ONE — what the player is told.
	var after := MindCultivationApi.preview(actor)
	assert_eq(after.get("ready"), false, "an attempt in flight is not reported ready")
	assert_eq(
		_conditions(after).size(),
		1,
		"the attempt is the only thing outstanding: %s" % [_conditions(after)]
	)
	assert_eq(
		String(_conditions(after)[0]),
		MindAdvancement.ATTEMPT_CLAUSE,
		"and it is the module's own published attempt wording"
	)
	assert_eq(
		String(after.get("attempt")),
		String(started.attempt_id),
		"and the record the clause refers to is the one in flight"
	)

	# SIDE TWO — what the press actually does. This is the half that was already
	# true before the fix; it is asserted on every run so the two cannot drift
	# apart again in the other direction.
	assert_eq(MindAdvancement.start(actor, _rng(8)), null, "a second start is refused")
	assert_eq(
		MindCultivationApi.try_breakthrough(actor, _rng(9)),
		false,
		"and the facade's own Breakthrough press refuses, exactly as preview said"
	)

	# A refusal that spends is not a refusal. The two refused presses took nothing
	# from the actor: the pill count is back where the restock left it.
	assert_eq(
		ItemsApi.inventory(actor).count(seed.breakthrough_item),
		pills,
		"neither refused press spent the realm pill"
	)
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, rank, "and the actor did not advance")


## The attempt clause is owed by EVERY branch of `preview`, not only the one that
## reaches the realm gates. A fix that appended it just before the final `return`
## would pass the test above and still lie on a refusal path — and the refusal
## paths are the ones a player meets when something has already gone wrong.
##
## The sea is removed rather than the path, because a sea-less actor is a state
## this suite already exercises (`test_mind_persistence.gd` loads one from a v2
## payload) rather than one invented here.
func test_the_attempt_clause_survives_a_refusal_branch_of_preview() -> void:
	var actor := _prepared()
	var started := MindAdvancement.start(actor, _rng(11))
	assert_ne(started, null, "the attempt commits while the gate is still open")

	actor.set_component(MindCultivationApi.SEA_COMPONENT, null)
	assert_eq(MindCultivationApi.sea(actor) == null, true, "the sea component is gone")

	var report := MindCultivationApi.preview(actor)
	assert_eq(report.get("ready"), false, "a preview that cannot even find a sea is not ready")
	assert_eq(
		_conditions(report).has(MindAdvancement.ATTEMPT_CLAUSE),
		true,
		"and the refusal still names the attempt in flight: %s" % [_conditions(report)]
	)
	assert_eq(
		String(report.get("attempt")),
		String(started.attempt_id),
		"a refusal still publishes the record, so 'nothing in flight' is not inferable from one"
	)
	# The reason the branch's own clause is still reported beside it: the clause is
	# ADDED to the report, never substituted for it.
	assert_eq(_conditions(report).size(), 2, "the branch's own reason is reported too")


# --- The second thing `start` refuses on: the ADR 0109 body gate --------------


## `_body_allows` refuses before anything is spent, so `preview` owes it for the
## same reason it owes `ATTEMPT_CLAUSE`: most authored body plans close the mind
## path, and without a clause one of them read READY and its Breakthrough press
## did nothing. Asserted on both sides on one actor, with the realm gate proved
## met BEFORE the body plan is applied so the refusal is attributable to the body
## alone and not to progress, clarity or a missing pill.
func test_preview_and_start_agree_when_the_body_closes_the_mind_path() -> void:
	var actor := _prepared()
	assert_eq(
		MindCultivationApi.preview(actor).get("ready"),
		true,
		"the realm gate alone is satisfied before any body plan applies"
	)

	var body := _a_race_that_closes_mind()
	assert_ne(body, &"", "an authored body plan closes the mind path at all")
	RaceApi.attach(actor)
	assert_eq(RaceApi.set_race(actor, body), true, "the body plan is enrolled")

	# SIDE ONE — the clause is `RaceGate`'s own label, compared whole, so a screen
	# renders core's wording and this test cannot drift from it.
	var report := MindCultivationApi.preview(actor)
	var expected: Array = []
	for entry in RaceGate.path_unmet(actor, PathState.MIND):
		expected.append(String(entry.get("label", "")))
	assert_eq(expected.is_empty(), false, "the enrolled body really does close the path")
	assert_eq(_conditions(report), expected, "preview names the refusal in RaceGate's wording")
	assert_eq(report.get("ready"), false, "so a closed path is not reported ready")
	assert_eq(
		_conditions(report).has(MindAdvancement.ATTEMPT_CLAUSE),
		false,
		"and the attempt is not what it names: %s" % [_conditions(report)]
	)

	# SIDE TWO — what the press does.
	assert_eq(MindAdvancement.start(actor, _rng(5)), null, "the attempt is refused")
	assert_eq(
		MindCultivationApi.try_breakthrough(actor, _rng(6)),
		false,
		"and the facade's press refuses, exactly as preview said"
	)
	assert_eq(String(MindCultivationApi.preview(actor).get("attempt")), "", "nothing was committed")


## The first authored body plan that closes the mind path, found rather than named:
## the claim is that a body plan CAN close the path, which holds for whichever one
## does, so pinning a race id here would only make the test drift when the roster
## changes.
func _a_race_that_closes_mind() -> StringName:
	for race_id: StringName in RaceApi.race_ids():
		var def := RaceCatalog.instance().race_definition(race_id)
		if def != null and def.closed_paths.has(PathState.MIND):
			return race_id
	return &""


# --- Why the abandon verb has no production caller --------------------------


## BL-0151 asks whether a player can be stranded holding an attempt. That is a
## property of the PRODUCTION entry point, not a matter of theory, so it is
## measured here rather than argued: the facade's breakthrough verb commits AND
## resolves in one call, so nothing can survive it and `cancel` is unreachable
## rather than merely unused. A strand would surface as a non-empty `attempt` on
## the facade's own report — the same value the mind screen reads.
##
## BOTH resolve paths are walked, because the concern is a path where `resolve`
## returns without ending the attempt. Rolling the module's published chance
## decides which path is taken deterministically, so neither outcome is waited
## for and neither can be missed.
func test_no_facade_breakthrough_can_leave_an_attempt_in_flight() -> void:
	assert_eq(
		_press_lands(false), true, "a granted breakthrough through the facade strands nothing"
	)
	assert_eq(_press_lands(true), false, "and a deviated one strands nothing either")


## One facade press, and the answer read back off the facade's own report.
## `rolls_above_the_chance` chooses which resolve path to take.
func _press_lands(rolls_above_the_chance: bool) -> bool:
	var actor := _prepared()
	var chance := float(MindCultivationApi.preview(actor).get("chance", -1.0))
	assert_eq(chance >= 0.0, true, "the module publishes a chance to roll against")
	var chosen := _seed_at_or_above(chance) if rolls_above_the_chance else _seed_below(chance)
	assert_ne(chosen, 0, "a roll on the requested side of the published chance exists")
	var rng := RandomNumberGenerator.new()
	rng.seed = chosen
	var landed := MindCultivationApi.try_breakthrough(actor, rng)
	assert_eq(
		String(MindCultivationApi.preview(actor).get("attempt")),
		"",
		"the press left nothing in flight (landed=%s)" % landed
	)
	return landed


## The first seed whose FIRST draw lands below the chance `preview` published,
## searched rather than hoped for: `resolve_attempt` draws exactly once, so the
## seed follows from the module's own number rather than a value copied out of a
## previous run.
##
## It returns the SEED and never the generator it tested with. `resolve_attempt`
## draws from whatever generator it is handed, so handing back one whose first
## roll had already been consumed would roll the SECOND value and quietly test
## something other than what the search matched.
func _seed_below(chance: float) -> int:
	for candidate in range(1, ROLL_BOUND + 1):
		var probe := RandomNumberGenerator.new()
		probe.seed = candidate
		if probe.randf() < chance:
			return candidate
	return 0


## And the first seed that lands at or above it, so the refusing resolve path is
## reached deterministically instead of by a roll that happens to fail.
func _seed_at_or_above(chance: float) -> int:
	for candidate in range(1, ROLL_BOUND + 1):
		var probe := RandomNumberGenerator.new()
		probe.seed = candidate
		if probe.randf() >= chance:
			return candidate
	return 0
