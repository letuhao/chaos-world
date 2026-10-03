extends TestCase

## BL-0153: which of the two cultivation-only gates actually binds at each of the
## 29 mind boundaries, MEASURED through the production action rather than read off
## the two authored numbers.
##
## ## Why the two numbers cannot be compared directly
##
## `progress_required` and `comprehension_required` are denominated in different
## currencies. Progress accrues one unit per unit of `gain`; comprehension
## accrues `INSIGHT_RATE * INSIGHT_GAIN` per unit of `gain`, and `INSIGHT_GAIN` is
## itself `1.0 + comprehension * 0.01` — a rate that RISES as the floor is
## approached (BL-0165). So `comprehension_required / INSIGHT_RATE` is not the
## work the floor costs; it is only the work it would cost at the bottom of the
## ladder, and the error grows with the floor. Every figure below is produced by
## actually calling `MindTraining.cultivate` and watching which clause flips first.
##
## ## What BL-0153 claimed, and what is measured
##
## The backlog entry measured the comparison with a FLAT `INSIGHT_RATE` and
## concluded "`state.progress` gates nothing". That conclusion does not survive
## BL-0165: once the shared insight rate multiplies the mind path's gain, the
## comprehension curve is no longer linear, and at several boundaries the authored
## `progress_required` is the cheaper of the two clauses. Both gates are live.
## Which of them binds where is a BALANCE decision and is recorded in the backlog
## rather than retuned here, so what this suite asserts is the invariant that
## decision must not break: NEITHER gate is vacuous.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

## The 30 realms make 29 boundaries, and every one is checked.
const BOUNDARIES := 29

## Sittings needed to meet `progress_required`, by construction: each sitting is
## sized to `progress_required / PROGRESS_SITTINGS` of `gain`, so the progress
## clause flips on sitting number PROGRESS_SITTINGS. The comprehension clause is
## then raced against it rather than assumed, so this constant only fixes where
## the two clocks are read from — it does not decide the winner.
const PROGRESS_SITTINGS := 64

## The bound on the wait. It names what failed to converge: a floor this many
## sittings of its own sized work cannot reach is an unreachable gate, and that has
## to surface as an assertion rather than as a hang. The measured worst case is a
## few hundred sittings, so 512 is headroom rather than a budget.
const COMPREHENSION_BOUND := 512

## One race per boundary, cached. The three tests below ask the same question of
## the same 29 boundaries, and a race is thousands of `cultivate` calls; the walk
## is pure and deterministic, so replaying it buys nothing.
static var _races: Dictionary = {}


## One sitting sized so the boundary's whole progress budget is spent in exactly
## `PROGRESS_SITTINGS` of them. Divided by the realm rate because `gain` is
## denominated in realm rate (`amount * RealmRate.factor`), not in `amount` — the
## same correction `Probe.gate_work` makes.
func _sitting(rank_id: StringName, target_seed: MindRealmSeed) -> float:
	var rate := RealmRate.factor(rank_id)
	return target_seed.progress_required / (float(PROGRESS_SITTINGS) * maxf(rate, 0.000001))


## Cultivate until BOTH clauses have flipped, recording the sitting each one
## flipped on. The earlier of the two is the binding gate; a boundary where one
## never flips inside the bound reports it as unmet rather than guessing.
func _race(rank_id: StringName, target_seed: MindRealmSeed) -> Dictionary:
	if _races.has(rank_id):
		return _races[rank_id]
	var actor := Probe.fresh_actor(rank_id)
	var state := actor.path(MindPath.PATH_ID)
	assert_ne(state, null, "a mind path at %s" % rank_id)
	if state == null:
		return {}
	var sitting := _sitting(rank_id, target_seed)
	assert_eq(sitting > 0.0, true, "the sitting is sized to a real budget")
	var to_progress := -1
	var to_comprehension := -1
	var sittings := 0
	while sittings < COMPREHENSION_BOUND and (to_progress < 0 or to_comprehension < 0):
		assert_eq(
			MindTraining.cultivate(actor, sitting), true, "cultivation applied at %s" % rank_id
		)
		sittings += 1
		if to_progress < 0 and state.progress >= target_seed.progress_required:
			to_progress = sittings
		if (
			to_comprehension < 0
			and actor.stats.get_base(Stat.COMPREHENSION) >= target_seed.comprehension_required
		):
			to_comprehension = sittings
	var answer := {
		"to_progress": to_progress,
		"to_comprehension": to_comprehension,
		"bound": _bound_at(to_progress, to_comprehension, target_seed.id),
	}
	_races[rank_id] = answer
	return answer


## Which clause flips first. Equal sittings cannot happen — one clause is checked
## first within a sitting, so a tie would be a measurement artefact, and it is
## reported rather than silently resolved.
func _bound_at(to_progress: int, to_comprehension: int, target_id: StringName) -> String:
	if to_progress < 0 and to_comprehension < 0:
		return "neither"
	if to_progress < 0:
		return "comprehension"
	if to_comprehension < 0:
		return "progress"
	if to_progress < to_comprehension:
		return "progress"
	if to_comprehension < to_progress:
		return "comprehension"
	return "tie"


## "name:count" for every clause, so a failure carries the distribution rather than
## only the boundary that happened to trip it.
func _distribution() -> String:
	var counts := {"progress": 0, "comprehension": 0, "neither": 0, "tie": 0}
	for boundary in range(BOUNDARIES):
		var race := _race_at(boundary)
		var bound := String(race.get("bound", "neither"))
		counts[bound] = int(counts.get(bound, 0)) + 1
	return (
		"progress %d, comprehension %d, neither %d, tie %d"
		% [
			counts["progress"],
			counts["comprehension"],
			counts["neither"],
			counts["tie"],
		]
	)


## The race for the boundary STARTING at ladder index `boundary`, whose target is
## the next realm up.
func _race_at(boundary: int) -> Dictionary:
	var realms := RealmDefaults.ladder().realms()
	if boundary < 0 or boundary + 1 >= realms.size():
		return {}
	var target_seed := MindRealmSeed.for_realm(realms[boundary + 1].id)
	assert_ne(target_seed, null, "target seed for %s" % realms[boundary + 1].id)
	if target_seed == null:
		return {}
	return _race(realms[boundary].id, target_seed)


## The contract: every boundary is decidable, and every one of them is earnable
## inside a bounded number of sittings through the production action. A boundary
## that reported `neither` is an unreachable gate, which is a failure and not a
## measurement.
func test_every_boundary_names_exactly_one_binding_gate() -> void:
	for boundary in range(BOUNDARIES):
		var race := _race_at(boundary)
		var target_seed := MindRealmSeed.for_realm(RealmDefaults.ladder().realms()[boundary + 1].id)
		assert_ne(
			int(race.get("to_comprehension", -1)),
			-1,
			(
				"the comprehension floor %s into %s is earned (reached after %s sittings; %s)"
				% [
					target_seed.comprehension_required,
					RealmDefaults.ladder().realms()[boundary + 1].id,
					race.get("to_comprehension"),
					_distribution(),
				]
			)
		)
		assert_ne(
			int(race.get("to_progress", -1)),
			-1,
			(
				"the progress budget %s into %s is earned (%s)"
				% [
					target_seed.progress_required,
					RealmDefaults.ladder().realms()[boundary + 1].id,
					_distribution(),
				]
			)
		)
		assert_ne(
			String(race.get("bound", "")),
			"neither",
			(
				"exactly one clause binds into %s (%s)"
				% [RealmDefaults.ladder().realms()[boundary + 1].id, _distribution()]
			)
		)


## BL-0153's premise, inverted. The entry recorded that `progress_required` never
## binds, which is what "vacuous gate" means; the measurement says otherwise on a
## non-empty set of boundaries, and it says so because BL-0165 made the insight
## rate rise with comprehension. Neither clause may go vacuous again: a boundary
## where only one of them ever binds is the defect this file exists to keep closed,
## whichever side it happens to be.
func test_neither_cultivation_gate_is_vacuous() -> void:
	for bound in ["progress", "comprehension"]:
		var bound_count := 0
		for boundary in range(BOUNDARIES):
			if String(_race_at(boundary).get("bound", "")) == bound:
				bound_count += 1
		assert_ne(
			bound_count,
			0,
			"%s binds at at least one boundary (measured: %s)" % [bound, _distribution()]
		)


## The bound that would have caught a stall. A wait that runs out reports "the
## floor was never earned"; this asserts the wait stays inside the bound it
## declares, so the bound is a real limit and not a formality. Read off the LAST
## boundary, which is the deepest floor on the ladder.
func test_the_comprehension_wait_stays_inside_its_declared_bound() -> void:
	var race := _race_at(BOUNDARIES - 1)
	var waited := int(race.get("to_comprehension", COMPREHENSION_BOUND + 1))
	assert_eq(
		waited < COMPREHENSION_BOUND,
		true,
		(
			"the deepest boundary converges in %d sittings, inside the bound of %d"
			% [
				waited,
				COMPREHENSION_BOUND,
			]
		)
	)
