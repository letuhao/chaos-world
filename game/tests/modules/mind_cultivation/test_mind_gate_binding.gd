extends TestCase

## BL-0153: which of the two cultivation-only gates actually prices a mind
## breakthrough, MEASURED through the production action rather than read off the
## two authored numbers.
##
## ## "Binding" means the clause the player WAITS ON
##
## Both clauses are required, so neither is optional and calling the cheaper one
## "not a gate" is the mistake this file exists to avoid. The clause that takes
## MORE sittings to satisfy is the one that sets the price; the one met first is
## free at that boundary. So `bound` here is the LATER of the two crossovers, and
## a clause that is met first at every single boundary is the vacuous one.
##
## ## Why the two numbers cannot be compared directly
##
## `progress_required` and `comprehension_required` are denominated in different
## currencies. Progress accrues one unit per unit of `gain`; comprehension
## accrues `INSIGHT_RATE * INSIGHT_GAIN` per unit of `gain`, and `INSIGHT_GAIN` is
## itself `1.0 + comprehension * 0.01` -- a rate that RISES as the floor is
## approached (BL-0165). So `comprehension_required / INSIGHT_RATE` is not the
## work the floor costs; it is only the work it would cost at the bottom of the
## ladder, and the error grows with the floor. Every figure below comes from
## actually calling `MindTraining.cultivate` and watching which clause flips first.
##
## ## What BL-0153 recorded, and what the fix moved
##
## Measured with the FLAT `INSIGHT_RATE` that shipped before BL-0165, the
## comprehension floor cost 2.2x-3.6x the progress bar at every one of the 29
## boundaries, so comprehension was the price and `progress_required` never priced
## anything. That is the entry's claim and it was correct. Pricing the mind path's
## insight off core's `Stat.INSIGHT_GAIN` bends the comprehension curve
## sub-linear, and the result is that the progress budget now takes the LONGER
## road at most boundaries and is the clause a player waits on. Which of the two
## SHOULD price the ladder is a balance decision and is recorded in the backlog
## rather than retuned here, so what this suite asserts is the invariant that
## decision must not break: NEITHER clause is vacuous.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

## The 30 realms make 29 boundaries, and every one is checked.
const BOUNDARIES := 29

## Sittings needed to meet `progress_required`, by construction: each sitting is
## sized to `progress_required / PROGRESS_SITTINGS` of `gain`, so the progress
## clause flips on sitting number PROGRESS_SITTINGS. The comprehension clause is
## then raced against it rather than assumed, so this constant only fixes where
## the two clocks are read from -- it does not decide the winner.
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
## denominated in realm rate (`amount * RealmRate.factor`), not in `amount` -- the
## same correction `Probe.gate_work` makes.
func _sitting(rank_id: StringName, target_seed: MindRealmSeed) -> float:
	var rate := RealmRate.factor(rank_id)
	return target_seed.progress_required / (float(PROGRESS_SITTINGS) * maxf(rate, 0.000001))


## Cultivate until BOTH clauses have flipped, recording the sitting each one
## flipped on.
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
		"bound": _bound_at(to_progress, to_comprehension),
	}
	_races[rank_id] = answer
	return answer


## The clause that takes the LONGER road, i.e. the one the player waits on. Equal
## sittings cannot happen -- one clause is checked first within a sitting -- so a
## tie would be a measurement artefact and is reported rather than resolved.
func _bound_at(to_progress: int, to_comprehension: int) -> String:
	if to_progress < 0 and to_comprehension < 0:
		return "neither"
	if to_progress < 0:
		return "comprehension"
	if to_comprehension < 0:
		return "progress"
	if to_progress > to_comprehension:
		return "progress"
	if to_comprehension > to_progress:
		return "comprehension"
	return "tie"


## "progress N, comprehension M, neither N, tie N" for every clause, so a failure
## carries the distribution rather than only the boundary that tripped it.
func _distribution() -> String:
	var counts := {"progress": 0, "comprehension": 0, "neither": 0, "tie": 0}
	for boundary in range(BOUNDARIES):
		counts[String(_race_at(boundary).get("bound", "neither"))] += 1
	return (
		"progress %d, comprehension %d, neither %d, tie %d"
		% [counts["progress"], counts["comprehension"], counts["neither"], counts["tie"]]
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
		for clause in ["comprehension", "progress"]:
			assert_ne(
				int(race.get("to_%s" % clause, -1)),
				-1,
				(
					"the %s requirement %s into %s is earned after %s sittings (measured: %s)"
					% [
						clause,
						float(target_seed.get("%s_required" % clause)),
						RealmDefaults.ladder().realms()[boundary + 1].id,
						race.get("to_%s" % clause),
						_distribution(),
					]
				)
			)
		assert_ne(
			String(race.get("bound", "")),
			"neither",
			(
				"exactly one clause prices %s (%s)"
				% [RealmDefaults.ladder().realms()[boundary + 1].id, _distribution()]
			)
		)


## BL-0153's invariant, and the one its own measurement would have kept silently
## broken. Before BL-0165 the comprehension floor priced all 29 boundaries and the
## progress budget priced none of them -- `state.progress` was authored, gated on,
## reported to a screen, and could never be the thing a player waited for. Neither
## clause may go vacuous again: a boundary where one of them is always met first
## is a half-authored gate, whichever side it is. This is the assertion a balance
## change has to confront rather than route around.
func test_neither_cultivation_gate_is_vacuous() -> void:
	for clause in ["progress", "comprehension"]:
		var priced := 0
		for boundary in range(BOUNDARIES):
			if String(_race_at(boundary).get("bound", "")) == clause:
				priced += 1
		assert_ne(
			priced, 0, "%s prices at least one boundary (measured: %s)" % [clause, _distribution()]
		)


## The bound that would have caught a stall. A wait that runs out reports "the
## floor was never earned"; this asserts the wait stays inside the bound it
## declares, so the bound is a real limit and not a formality. Read off the LAST
## boundary, which carries the deepest floor on the ladder.
func test_the_comprehension_wait_stays_inside_its_declared_bound() -> void:
	var waited := int(_race_at(BOUNDARIES - 1).get("to_comprehension", COMPREHENSION_BOUND + 1))
	assert_eq(
		waited < COMPREHENSION_BOUND,
		true,
		(
			"the deepest boundary converges in %d sittings, inside the bound of %d"
			% [waited, COMPREHENSION_BOUND]
		)
	)
