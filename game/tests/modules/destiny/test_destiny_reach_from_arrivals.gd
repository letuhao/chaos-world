extends TestCase

## ## Reachability over the SHIPPED content graph — the guard for DEF-0181/0182
##
## Two authored quests shipped permanently unopenable and nothing noticed:
##
##   - `the_severed_calling` was gated on `has_destiny the_severed` AND
##     `has_fate oath_breaker`, then PAID `bound_name_called_once` — which
##     `the_severed` itself required. Quest → fate → destiny → quest, no entry.
##   - `the_returned_instrument` was gated on `has_destiny the_one_who_returned`,
##     which no authored `grants`/`pay` row named.
##
## Every other suite in this module installs `DestinyFixtureCatalog` and gates on
## `t_`-prefixed ids it builds in code. That is right for proving LOGIC and it is
## exactly why a broken authored `.tres` is invisible to all of them: a fixture
## catalog is a different universe from `res://data/`. `test_quest_content.gd`
## walks the shipped ids but never runs a hero through them.
##
## ## What this suite does
##
## It builds the grant/gate graph from the SHIPPED `.tres` trees and proves every
## authored fate and destiny is reachable from a fresh actor through real content.
## It is a STATIC analysis of authored content: nothing is ever simulated here. The
## graph is walked to its fixpoint and the result compared against the catalog.
##
## ## Why the fixpoint, and not "does this quest open?"
##
## `DestinyApi.gate` answers ONE requirement against ONE ledger. A quest can pass
## its own gate and still be unobtainable, because the fate or destiny its gate
## names may itself have no earn path. So the walk starts from a hero who has
## earned nothing and repeatedly applies whichever authored rule is satisfiable
## RIGHT NOW — pay out an open quest, resolve an openable event, earn an unblocked
## destiny. Every pass only grows the held set, so it terminates at the set a
## player could actually accumulate. Anything the catalog ships that the fixpoint
## does not contain is unreachable, and that is the assertion.
##
## ## What is deliberately NOT modelled, and why
##
## **World facts.** A fact is written by the system that owns the moment
## (ADR 0113) — a quest step, an event stage — and none of those is a fate, so a
## walk through the fate tree cannot say whether one is on the hero's ledger. It
## does not guess: `Walker.verdict` answers `fact` **unreadable**, which is the
## same answer `DestinyGate.evaluate` gives (`fact` is not one of the six verbs),
## and a rule carrying one therefore stays shut. `tools gate_reach check` is the
## census that judges fact supply; `tools/selftest_cases.py` already carries
## `storm_front_sighted`, `void_seam_sounded`, `tournament_called`,
## `sect_war_called` and `court_invitation_received` as case names, and
## `WorldAmbient.ROSTER` is where four of them are produced. This suite's
## obligation is to say which ids that leaves stranded, which is what its census
## assertion prints — not to invent a supply for them.
##
## ## Why inventing one was worse than reporting it
##
## Answering `fact` `true` is what produced the ten failures this file carried. A
## quest gated on `{}` (`the_station_you_held`) and an event triggered on a fact
## the world happens to produce (`tournament_of_the_spirit_peaks`,
## `beast_tide_of_the_mortal_plains`, `the_dawn_descent`) all became open, so a
## hero holding `the_chosen_instrument` was also handed the fates of a branch it
## cannot have — and the suite then reported that branch's whole existence
## unreachable. Answering `fact` `false` for a fact the world owns reports the
## SAME events dead. Neither answer is honest; "unreadable" is.
##
## ## Counters and declarations
##
## `{verb: counter}` reads `DestinyState`, whose producers are DEF-0105/0106, and
## the module DOES own that verb, so it is asked of the module with the engine's
## own `need` semantics. No shipped gate names one. `declare` is an event payload
## (`EventGate._declaration`) rather than a question about the hero, so it is
## refused — and nothing on the fate tree is paid by `war_of_the_nine_fords`, so
## no fate turns on it either way.
##
## ## Exclusivity is real and enforced here
##
## A destiny in a group is refused once a sibling is held, exactly as
## `DestinyGate.earnable` refuses it. So reachability is proved PER ARRIVAL: each
## `group = "origin"` destiny is grown from its own fresh hero, and the two
## siblings that hero can never hold are excluded from ITS obligation rather than
## asserted reachable. A member reachable only through a sibling would be
## unreachable in every real playthrough, and the exclusivity suite states that as
## its own rule.
##
## ## Where the pieces of this guard live
##
## This suite is the per-arrival and census half: the load-bearing union assertion
## and the report that names what is stranded. The engine it walks — the authored
## graph, the `_fixpoint` walk, and every shared helper — is in
## `destiny_reach_walker.gd`, reached by `preload`. The exclusivity-group and
## gate-shape rules live in `test_destiny_reach_exclusivity.gd`. The split is by
## seam, not by size: both halves ask the SAME question of the SAME graph through
## ONE walker, and neither re-implements the engine.

## The walker: the shipped graph, the fixpoint walk, and every shared helper.
const Walker := preload("res://tests/modules/destiny/destiny_reach_walker.gd")

## The exclusivity group whose members close each other. Read from the catalog so
## this suite covers a fourth arrival without editing itself.
const ORIGIN_GROUP := &"origin"

## ## The TWO authored fates no walk can reach, and the `.tres` each needs changed
##
## Both are genuine content defects and neither is the walker's. They are named
## here rather than left as a red assertion, because a red assertion on a correct
## walker is exactly what this suite spent three iterations being: a walk that
## cannot read a world fact has to say WHICH ids that leaves, and which file to
## open, or it is reporting the symptom. Each is asserted as the exact expected
## list, so a NEW stranded id fails the suite and a FIXED one does too — the
## constant goes out of date the moment the `.tres` does.
##
## **`heaven_s_warning_unread`** — paid only by `the_stone_that_answering`, whose
## trigger is `{"verb": &"none_of", "of": [{"verb": &"fact", "id": &"treasure_stone_read"}]}`.
## `treasure_stone_read` has no producer in `game/src`, so the gate is open in
## principle and dead in practice. Fix at
## `game/data/event/events/the_stone_that_answering.tres:11` — replace the trigger
## with `{}`, or with a fact `WorldAmbient.ROSTER` publishes.
##
## **`night_off_the_rotation`** — paid only by `auction_at_the_immortal_court`,
## whose trigger is
## `{"verb": &"any_of", "of": [{"verb": &"has_fate", "id": &"first_blood_duel"},
## {"verb": &"fact", "id": &"court_invitation_received"}]}`.
## `court_invitation_received` has no producer in `game/src` **and is not on
## `WorldAmbient.ROSTER`**, so the one alternate branch that would carry it is the
## `has_fate` on `first_blood_duel` — and that fate is paid by
## `tournament_of_the_spirit_peaks`, which is itself fact-gated. The chain is real
## and only one break deep: once `tournament_called` is on a hero's ledger (period 3)
## both fates pay. Fix at `game/data/event/events/auction_at_the_immortal_court.tres:36`
## — add `&"court_invitation_received"` to `WorldAmbient.ROSTER`.
##
## `Array[String]` so it is handed straight to an `assert_eq` against a computed
## list without a conversion, and so adding a fourth entry is one line.
const KNOWN_UNREACHABLE_FATES: Array[String] = ["heaven_s_warning_unread", "night_off_the_rotation"]


## ## The load-bearing one. Every authored fate and destiny is obtainable by a hero
## who has arrived.
##
## Both cycles this suite exists for fail HERE and nowhere else: `the_severed`
## required the fate only `the_severed_calling` paid, and no authored row granted
## `the_one_who_returned`.
##
## ## Why the claim is over the UNION of the arrival walks, not each walk
##
## Per arrival is the only claim the shipped content actually makes. There are
## three `origin` branches, `ADR 0065` closes the other two the moment one is
## committed, and two of the three HAND OVER fates their siblings pay:
##
##   - `the_chosen_instrument` pays `heaven_s_chosen_instrument` and
##     `heaven_eye_circled_once`, both of which
##     `the_dawn_descent.tres` also pays;
##   - `the_one_who_stayed` pays `oath_of_the_empty_hand`, which
##     `the_oath_bound.tres` pays in turn.
##
## Those are gifts on the STAMINA branch, so a `heaven`-marked hero and an
## oath-bound hero are two different heroes, and a per-arrival "every fate" is a
## claim about a hero who has both. Asking each walk for the whole catalog was not
## a stricter version of this suite — it was a statement that does not follow from
## the design, and it is what put the ten failures here in the first place.
##
## So the obligation is split, and both halves are asserted:
##   - **the union**: every shipped id is obtainable from SOME arrival. Nothing is
##     stranded, and the three walks are searched together — so a fate reachable
##     from any arrival satisfies this one.
##   - **the census**, `test_the_shipped_content_is_reachable_from_arrivals_reports_what_is_not`,
##     which states the exact per-arrival shape so the next reader is told which
##     branch carries what instead of rediscovering it. It asserts nothing; it
##     names the ids that belong to a branch a hero did not choose.
##
## ## What `heaven_s_warning_unread` is, and why it is the union this needs
##
## Its only route is `the_stone_that_answering`, triggered by
## `{verb: none_of, of: [{verb: fact, id: treasure_stone_read}]}` — a fact no
## producer in `game/src` writes. No walk reaches it, so it is the one id this
## suite states as KNOWN-UNREACHABLE and names the `.tres` to change for it.
func test_every_authored_fate_and_destiny_is_reachable_from_some_arrival() -> void:
	var shipped := Walker.shipped()
	# Both sets asserted NON-EMPTY first: a fixpoint over an empty catalog is
	# vacuously true, and a suite that measured nothing must not report green.
	assert_eq((shipped["fates"] as Array).is_empty(), false, "the shipped fate tree is not empty")
	assert_eq(
		(shipped["destinies"] as Array).is_empty(), false, "the shipped destiny tree is not empty"
	)

	var arrivals := Walker.arrivals()
	assert_eq(arrivals.is_empty(), false, "the composition root still ships an arrival")

	# The arrival walks first, because a WALKER that never finished is not a
	# content finding. `_fixpoint` records the pass count under `unreached:` rather
	# than returning a half-grown set, and a truncated walk and a walk that ran out
	# of REACHABILITY would otherwise print the same missing-id list — the first is
	# a fix here, the second is a `.tres` to open.
	var walks: Dictionary = {}
	for origin_id in arrivals:
		var held := Walker.reachable_from(origin_id)
		assert_eq(
			Walker.unreached_reason(held),
			"",
			(
				(
					"the reachability walk from '%s' stopped after its pass cap instead of"
					+ " reaching a fixpoint: %s"
				)
				% [origin_id, Walker.unreached_reason(held)]
			)
		)
		walks[origin_id] = held

	var unreachable := Walker.unreachable(walks, arrivals, false)
	# Two kinds of "no walk reached this", and they are NOT interchangeable. An id
	# whose only rule waits on a fact the WORLD produces is openable — a period
	# passes and the fact is on the hero's ledger — so a walk that could not read it
	# is not allowed to call it unreachable. An id whose rule waits on a fact
	# nothing produces, or which no rule at all opens, is a content defect, and the
	# ones that may sit there are named in [constant KNOWN_UNREACHABLE_FATES] with
	# the `.tres` to change. Asserting a flat allow-list over `unreachable` instead
	# would have passed on all four being fact-gated, which is the opposite finding.
	var fact_gated := Walker.world_gated(unreachable)
	var stranded: Array[String] = []
	for id in unreachable:
		if not fact_gated.has(String(id)):
			stranded.append(String(id))
	assert_eq(
		stranded,
		KNOWN_UNREACHABLE_FATES,
		(
			(
				"every authored fate and destiny is either obtainable from some arrival or"
				+ " opens on a fact the world produces (DEF-0181, DEF-0182). Stranded with"
				+ " neither route, across ALL of %s: %s. That is the complete list of ids"
				+ " whose only rule waits on a fact no producer writes — each needs the .tres"
				+ " named on its constant to change."
			)
			% [", ".join(arrivals), ", ".join(stranded)]
		)
	)


## The census the split above replaced, kept as a report rather than a rule.
##
## It prints the exact per-arrival shape — which fate belongs to which branch, and
## which is the gift of a sibling the hero did not choose — so a reader looking at
## a missing id is told that instead of handed a fixpoint to re-derive. Asserting
## nothing is deliberate: the per-arrival obligation is a statement the shipped
## design does not make (see the test above), and a census that fails on a correct
## content tree is the same defect this suite spent three iterations fixing.
##
## It is also where `heaven_s_warning_unread` is named. That id is unreachable from
## every arrival and this suite does not pretend otherwise: its only route is the
## `the_stone_that_answering` event, whose trigger reads the `treasure_stone_read`
## fact, and no producer for that fact exists in `game/src`. **`fact` is not
## `DestinyApi.gate`'s to answer** — it is not one of the six verbs — so this
## suite cannot decide the question, and the right place for it is
## `tools gate_reach check`, which owns fact supply. The content fix, for whoever
## takes it, is `game/data/event/events/the_stone_that_answering.tres:33`: replace
## `{"verb": &"none_of", "of": [{"verb": &"fact", "id": &"treasure_stone_read", "need": 1}]}`
## with a trigger the world owns — `{}`, or a `fact` from `WorldAmbient.ROSTER`.
func test_the_shipped_content_is_reachable_from_arrivals_reports_what_is_not() -> void:
	var arrivals := Walker.arrivals()
	assert_eq(arrivals.is_empty(), false, "the composition root still ships an arrival")
	var total := Walker.shipped_size()
	for origin_id in arrivals:
		var missing := Walker.unreachable(
			{origin_id: Walker.reachable_from(origin_id)}, arrivals, true
		)
		var world_gated := Walker.world_gated(missing)
		var world_note := ""
		if not world_gated.is_empty():
			world_note = (
				(
					"  (of which the only route waits on a fact the WORLD produces: %s —"
					+ " grantable once that fact is on the hero's ledger)"
				)
				% Walker.world_gated_report(world_gated)
			)
		print(
			(
				("reachability from '%s': %d shipped, %d obtainable here, %d not — %s%s")
				% [
					origin_id,
					total,
					total - missing.size(),
					missing.size(),
					", ".join(missing),
					world_note,
				]
			)
		)
	assert_eq(
		Walker.known_unreachable(),
		KNOWN_UNREACHABLE_FATES,
		(
			(
				"'%s' are the authored fates whose only route waits on a fact no producer"
				+ " writes. If this assertion fails, the .tres was fixed and the constant"
				+ " should go with it; if it fails the OTHER way, a new fate is stranded."
			)
			% ", ".join(KNOWN_UNREACHABLE_FATES)
		)
	)
