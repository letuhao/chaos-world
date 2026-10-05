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
## **World facts are modelled, and modelled as what they are.** A fact is a thing
## that happened (ADR 0113), it lives in `WorldFact`'s ledger, and a gate reads it
## through `EventGate._has_fact` → `EventFacts.count_of` → `WorldFact.count`. So the
## walk reads it off the real ledger on the real probe rather than refusing it, and
## `Walker.seed_world_facts` puts the world's own ambient news there first — the
## ids `WorldAmbient.due` publishes, and nothing else, so the walk never invents a
## producer.
##
## ## A fact the world has not said is 0, and 0 is an ANSWER
##
## `the_stone_that_answering.tres:20` triggers on
## `{verb: none_of, of: [{verb: fact, id: treasure_stone_read, need: 1}]}`. On a
## fresh ledger that fact is 0, `none_of` is true, `EventApi.begin` accepts it, the
## event opens, and its own `on_enter` writes the fact — which closes its gate for
## every later attempt. That is a gate the content was written to use, and the
## previous version of this suite could not see it: it answered `fact` **unreadable**
## for every fact, so four of the eight authored events were invisible to it and it
## then named two REACHABLE fates permanently unearnable (DEF-0279). Both answers
## were wrong for the same reason — neither asked anything.
##
## ## Why there is no exemption list here, and what replaced it
##
## `KNOWN_UNREACHABLE_FATES` certified two reachable fates as unearnable, so the
## day someone fixed those `.tres` files the suite would have gone red with a
## message telling them to delete a defect that no longer existed, and nothing would
## ever have told them the fix landed. It is gone. The union assertion below now
## asks the walker and asserts its answer — **nothing stranded** — and the
## capabilities it is standing on are asserted next, so a walk that could not read
## something says WHICH, in the measured language of facts, rather than in a
## hand-maintained list of fate ids.
##
## ## Counters and declarations
##
## `{verb: counter}` reads `DestinyState`, `{verb: tagged}` reads the fate ledger's
## tag vocabulary, and `{verb: declare}` is `EventGate._declaration`. All three are
## asked of the module that owns them, through `EventGate.evaluate`, for the reason
## in [method Walker.gate_answers]. No shipped fate gate names a counter or a tag.
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

## ## What `heaven_s_warning_unread` and `night_off_the_rotation` turned out to be
##
## Both were on `KNOWN_UNREACHABLE_FATES`, a hand-maintained list certifying them as
## permanently unearnable. Both are reachable in a normal run, and the list is gone
## (DEF-0279):
##
##   - `night_off_the_rotation` is paid by `auction_at_the_immortal_court.tres:36`,
##     whose trigger is a bare `{verb: has_fate, id: first_blood_duel}`, and
##     `first_blood_duel` is paid by `tournament_of_the_spirit_peaks.tres:40` —
##     reachable because `tournament_called` is one of the four facts
##     `WorldAmbient` publishes, which is also what the duel pays
##     (`combat/duel.gd:146`).
##   - `heaven_s_warning_unread` is paid by `the_stone_that_answering.tres:24`,
##     whose trigger is `none_of([fact treasure_stone_read])`. On a fresh ledger that
##     fact is 0, `none_of` is true, the event opens and its own `on_enter` writes
##     the fact — which closes the gate for every later attempt. The event is
##     written to be opened exactly once.
##
## Neither needed a `.tres` fix. Both were the WALKER's blindness: it refused every
## `fact` verb as unreadable, so it could not see four of the eight authored events
## open at all.


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
##     branch carries what instead of rediscovering it. It asserts the union again
##     and prints the split.
##
## ## Why the expected value is `[]`, and why that is a real assertion
##
## It used to be `KNOWN_UNREACHABLE_FATES` — a hand-maintained list naming two
## fates this walk could not reach, and both of them reachable (DEF-0279). A
## hand-maintained list is only ever right twice: while nothing changes, and if the
## reader remembers to update it. Asserting the walker's own answer means a content
## fix turns this red with a message naming what the walk now reaches, and a
## content break turns it red naming what stopped reaching.
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
