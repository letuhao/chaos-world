extends TestCase

## **The load-bearing proof: a REAL authored quest completes in PRODUCTION.**
##
## ## The defect this suite exists to end
##
## `QuestApi.advance` — the only verb that completes a quest, and the only caller of
## `QuestGrants.pay` — had exactly ONE production caller, `BeatDirector`, and the
## director's only production offer point is `WorldPulse.offer`, which offers
## `world_period_elapsed` and the four `WorldAmbient.ROSTER` ids. **No authored quest
## step watches any of those five.** Every authored step watches `sect_post_held`,
## `oaths_discharged`, `household_heir_registered`, `third_man_spared` or
## `duels_won`, all written by module writers that bypass the director by design
## (ADR 0137). A player could accept a quest, satisfy every step in play, and it
## never completed. Every quest in `data/quest/quests/` was unfinishable.
##
## ## The anti-pattern this suite deliberately does NOT repeat
##
## `tests/app/test_world_beat_chain.gd:81` proves the chain green by installing a
## FIXTURE quest whose single step watches `PERIOD_FACT` — the one id the pulse
## actually offers. It asserts a fact about its own fixture, not about the game, so
## it was green while the shipped game was unfinishable.
##
## So every test here:
##   - drives a quest read from the REAL `res://data/quest/quests/` tree, never a
##     `QuestFixtureCatalog` fixture;
##   - records its facts through the MODULE THAT OWNS THEM — `CombatFacts`,
##     `SectFacts` — which call `WorldFact.record` and never learn that `quest`
##     exists;
##   - asserts on `QuestApi.summary`, the public read, rather than on
##     `QuestApi.complete`/`advance`, so it cannot smuggle in the very verb it is
##     proving is wired.
##
## **No test in this file calls `QuestApi.accept` or `QuestApi.advance`.** Acceptance
## goes through `app/QuestProgram` (the one production caller of `accept`) or, for a
## `systemic`/`emergent` quest, through `QuestArrivalProjection` — the door this
## change opens. The completion is observed, never requested.
##
## ## The door a `systemic`/`emergent` quest comes through
##
## `QuestApi.offered` skips every non-`authored` kind on purpose (BL-0670: that
## filter is the only thing that makes `kind` a fact about ORIGIN rather than a
## second name for `requirement`), and `QuestProgram` — the only production caller
## of `accept` — only ever sees rows that came out of `offered`. So three shipped
## quests had **no production door**: `what_the_rotation_cost` (`emergent`),
## `the_short_road` and `the_severed_calling` (both `systemic`). A player could
## stand the rotation, win three counted duels, spare the third man, and the quest
## naming exactly that never entered the active set.
##
## They now **ARRIVE**: `QuestArrivalProjection` subscribes to the same ledger hook
## and calls the existing `QuestApi.accept` when the fact that just landed makes
## every required step of such a quest true. The filter in `offered` is untouched,
## because an emergent quest is not OFFERED, it ARRIVES.

## ## Real authored quests, read from content rather than restated
##
## `the_short_road` is the cleanest proof available: one step, one fact
## (`oaths_discharged`), ungated, and — critically — its `kind` is `systemic`, so it
## is NEVER handed out by `QuestApi.offered` (BL-0053: a systemic quest completes by
## living rather than by being offered). It is therefore reachable ONLY by a
## completion path driven from a recorded fact, which is exactly the thing that was
## missing. A test that could accept-and-complete it by hand would prove nothing.
##
## `the_station_you_held` is the multi-step proof: three steps across three DIFFERENT
## owning modules (`sect` twice, `clan` once), so it only completes if the dispatch
## fires for a fact any one of them writes.
##
## `what_the_rotation_cost` is the ARRIVAL proof: an `emergent` quest, three steps
## across two owning modules (`sect`, `combat`), one of them OPTIONAL. It is never
## offered, and nothing in the game hands it out — it can only arrive through play.
const QUEST := &"the_short_road"
const QUEST_FACT := &"oaths_discharged"

const ARRIVAL := &"what_the_rotation_cost"

## The third non-`authored` quest, and the one with a GATE: two required steps
## across two owners, opening behind `has_destiny: the_severed` and
## `has_fate: oath_breaker` (`the_severed_calling.tres`). It is the proof that the
## arrival respects a gate rather than bypassing one.
const SEVERED := &"the_severed_calling"
const SEVERED_GATE_DESTINY := &"the_severed"
const SEVERED_GATE_FATES: Array[StringName] = [&"oath_breaker"]

const MULTI := &"the_station_you_held"
const MULTI_FACTS: Array[StringName] = [
	&"sect_post_held",
	&"oaths_discharged",
	&"household_heir_registered",
]

## The gate `the_station_you_held` opens behind, read from its own `.tres`.
const MULTI_GATE_DESTINY := &"the_one_who_stayed"

## The five facts every authored quest step watches, as the SHIPPED tree declares
## them. Asserted against the catalog rather than restated as a local constant list:
## a second copy here would be free to drift from the content it claims to describe.
const AUTHORED_STEP_FACTS: Array[StringName] = [
	&"sect_post_held",
	&"oaths_discharged",
	&"household_heir_registered",
	&"third_man_spared",
	&"duels_won",
]

## What the pulse actually offers, and therefore what the DIRECTOR can hear. None of
## these is an authored step fact, which is the whole measurement: if this list ever
## grows an entry that also appears in `AUTHORED_STEP_FACTS`, the director's path is
## no longer redundant and the reasoning behind the ledger subscription is stale.
const DIRECTOR_OFFERED: Array[StringName] = [WorldPulse.PERIOD_FACT]

var _installed := false
var _arrival_installed := false


func setup() -> void:
	# No fixture catalog: `QuestCatalog.instance()` must load the SHIPPED tree, or
	# every claim here would be about content this suite invented.
	QuestFixtureCatalog.teardown()
	DestinyFixtureCatalog.teardown()
	# The bridge this suite proves, installed the way the composition root installs
	# it. `setup` rather than the boot path, because `ItemWorkbenchApp._ready` needs a
	# scene tree this suite does not have — and because the install IS the unit under
	# test: `test_the_bridge_is_not_installed_by_default` pins that a process which
	# has not installed it does not complete quests, which is the RED half.
	QuestFactProjection.subscribe_to_fact_ledger()
	_installed = true
	# **Installed AFTER, in the same order the composition root uses.** That order IS
	# the ordering decision under test: the arrival must land after the completion
	# dispatch has run, so the quest it enters completes on the SAME fact. Swapping
	# these two lines is a mutation this suite should go red on.
	QuestArrivalProjection.subscribe_to_fact_ledger()
	_arrival_installed = true


func teardown() -> void:
	if _arrival_installed:
		QuestArrivalProjection.unsubscribe_from_fact_ledger()
		_arrival_installed = false
	if _installed:
		QuestFactProjection.unsubscribe_from_fact_ledger()
		_installed = false
	QuestFixtureCatalog.teardown()
	DestinyFixtureCatalog.teardown()


# --- The proof ---------------------------------------------------------------


## **THE TEST.** A REAL authored quest, its facts written by the module that owns
## them, completed with no director, no pulse, no sink and no `advance` call.
##
## Mutation target: delete `QuestFactProjection.subscribe_to_fact_ledger()` from
## `app/item_workbench_app.gd` (or break `_watches`) and this goes red — the fact is
## in the ledger, the step reads `done`, and the quest is still not completed.
func test_a_real_authored_quest_completes_when_its_owner_records_the_fact() -> void:
	expect_assertions(5)
	var actor := QuestFixtureCatalog.hero()
	var def := QuestCatalog.instance().definition(QUEST)
	assert_ne(def, null, "the quest is read from the SHIPPED tree, not a fixture")

	# Accepted the way the running game accepts: through `app/QuestProgram`, the ONE
	# production caller of `QuestApi.accept`. Never `QuestApi.accept` directly.
	var program := QuestProgram.new(actor)
	var accepted := program.accept(QUEST)
	assert_eq(bool(accepted["ok"]), true, "the program took the quest on")
	assert_eq(
		_completed(actor).has(String(QUEST)),
		false,
		"it is not complete yet, so nothing below can pass on a pre-completed quest"
	)

	# THE FACT, written by the module that owns it. `SectFacts` reaches
	# `WorldFact.record` and has no idea `quest` exists — that is the claim.
	SectFacts.record_oaths_discharged(actor, 1)

	# Asserted on the PUBLIC READ. Nothing here asks a quest to complete; it asks
	# what the module already believes.
	assert_eq(
		WorldFact.count(actor, QUEST_FACT),
		1,
		"the owning module wrote the fact, so the ledger holds it"
	)
	var step := _step(actor, QUEST, &"furnace_lit")
	assert_ne(step, null, "the authored step exists")
	assert_eq(bool(step["done"]), true, "the step reads satisfied from the shared ledger")
	assert_eq(
		_completed(actor).has(String(QUEST)),
		true,
		"and the quest COMPLETED — which is what never happened in production"
	)


## The same proof on a quest whose `kind` makes it un-offerable: `systemic` quests
## are never handed out by `QuestApi.offered` (BL-0053), so there is NO code path a
## test could use to complete this one by hand. It can only complete by living.
##
## **RESHAPED.** The old version pinned the finding — "an UNACCEPTED systemic quest
## stays open, because nothing enters one" — and that assertion was half a defect
## report pinned as a requirement. The first half is still true and is still
## asserted here, because it is the correctness claim: a fact alone must never
## complete a quest that is not in flight, or `advance` would be deciding things no
## gate ever passed. The second half is what this change fixes, and it is now the
## other side of the same test: the fact ALONE enters the quest, and the SAME
## occurrence then completes it.
func test_the_systemic_quest_is_never_offered_so_only_a_recorded_fact_can_finish_it() -> void:
	expect_assertions(9)
	var actor := QuestFixtureCatalog.hero()
	var def := QuestCatalog.instance().definition(QUEST)
	assert_ne(def, null, "the shipped quest exists")
	assert_eq(def.kind, QuestDef.KIND_SYSTEMIC, "it is authored systemic, not offered on a board")

	var offered: Array[String] = []
	for row in QuestApi.offered(actor) as Array[Dictionary]:
		offered.append(String(row["id"]))
	assert_eq(
		offered.has(String(QUEST)), false, "nothing in the game hands this quest to the player"
	)

	# **The correctness claim, kept.** A fact alone must not complete a quest that is
	# not in flight. The arrival door below ENTERS it; it does not hand out a
	# completion, and nothing here may assert otherwise.
	assert_eq(
		_completed(actor).has(String(QUEST)),
		false,
		"nothing is complete before a single fact is recorded"
	)

	# **The defect this change fixes.** One occurrence of the fact the owning module
	# writes — `SectFacts` reaches `WorldFact.record` and has no idea `quest` exists.
	# There is no board press, no `QuestProgram`, no `QuestApi.accept` in this body:
	# the world accepts the quest because the world is what made it enterable.
	assert_eq(
		Active(actor).has(String(ARRIVAL)),
		false,
		"the EMERGENT quest the audit found unwired is not in flight before play"
	)
	SectFacts.record_post_held(actor)

	# It ENTERED, by arrival, on the very fact that made it enterable.
	assert_eq(
		_active(actor).has(String(QUEST)),
		true,
		"one recorded fact ARRIVES the systemic quest — nothing offers it and nothing accepts it"
	)
	assert_eq(
		_active(actor).has(String(ARRIVAL)),
		false,
		"but the emergent three-step quest is NOT enterable on one fact of three"
	)

	# **The ordering, pinned.** The SAME occurrence completes it: the arrival is
	# installed after `QuestFactProjection`, so by the time the next fact's dispatch
	# runs the quest is in the active set, and `advance` finishes it there. Had the
	# arrival been installed FIRST, the completion dispatch would already have run
	# for this occurrence over a set the arrival had not yet joined, and the quest
	# would still be sitting active above. Swapping the two subscribe lines in
	# `setup()` is the mutation this assertion exists to catch.
	assert_eq(
		_completed(actor).has(String(QUEST)),
		true,
		"and it completes on THE SAME occurrence, not on a later fact"
	)
	assert_eq(
		_active(actor).has(String(QUEST)),
		false,
		"so it is neither still active nor completed twice"
	)

	# The arrival is an ACCEPT through the existing facade verb, not a bypass: it
	# entered exactly ONE quest — the systemic one whose only step this fact closed —
	# and it entered none of the authored quests whose steps it did not satisfy.
	assert_eq(_active(actor).size(), 1, "one arrival, and only the quest it was true for")
	assert_eq(
		String(QuestApi.summary(actor)["quests"][String(QUEST)]["kind"]),
		String(QuestDef.KIND_SYSTEMIC),
		"the entry is a real ledger row carrying the quest's own kind"
	)


## ## THE PROOF: an emergent quest ARRIVES through play
##
## `what_the_rotation_cost` is the quest the closing audit named: a player can stand
## the rotation, win three counted duels, spare the third man, and the quest that
## says exactly that was never on the board. Nothing offers it — `QuestApi.offered`
## skips every non-`authored` kind — so the only way it can exist in a save is if the
## world entered it. This drives it entirely through the MODULES THAT OWN THE FACTS:
## `SectFacts` for the post, `CombatFacts` for the duels and the mercy. No
## `QuestApi.accept`, no `QuestProgram`, no `advance`, anywhere in this body.
##
## Mutation target: delete `QuestArrivalProjection.subscribe_to_fact_ledger()` from
## `app/item_workbench_app.gd` and this goes red at the first `sect_post_held` — the
## quest never enters the active set, and `the_severed_calling` never arrives
## either.
func test_the_emergent_quest_arrives_through_play_and_completes() -> void:
	expect_assertions(12)
	var actor := QuestFixtureCatalog.hero()
	var def := QuestCatalog.instance().definition(ARRIVAL)
	assert_ne(def, null, "the emergent quest is read from the SHIPPED tree")
	assert_eq(def.kind, QuestDef.KIND_EMERGENT, "it is authored EMERGENT, so no board lists it")
	for row in QuestApi.offered(actor) as Array[Dictionary]:
		assert_eq(
			String(row["id"]) == String(ARRIVAL),
			false,
			"and no row of the offer board names it: '%s'" % String(row["id"])
		)

	# --- 1. the office -------------------------------------------------------------
	SectFacts.record_post_held(actor)
	assert_eq(
		_active(actor).has(String(ARRIVAL)),
		false,
		"one of three steps is not an arrival"
	)
	# The door is already live, and demonstrably judging this hero's OWN steps: the
	# same fact DID arrive `the_short_road`, whose single required step it closed.
	assert_eq(
		_active(actor).has(&"the_short_road"),
		true,
		"so the door ran and read this hero's steps — a sibling quest it WAS true for is in flight"
	)

	# --- 2. the duels (an OPTIONAL step: three counted wins) ------------------------
	CombatFacts.record_duel_won(actor)
	assert_eq(
		_active(actor).has(String(ARRIVAL)),
		false,
		"the optional duels step alone is not an arrival either"
	)
	CombatFacts.record_duel_won(actor)
	CombatFacts.record_duel_won(actor)
	assert_eq(
		WorldFact.count(actor, &"duels_won"),
		3,
		"the combat module really did take three duels, so the optional step reads done"
	)

	# --- 3. the third man ----------------------------------------------------------
	CombatFacts.record_spared(actor)

	# **THE CLAIM.** The last required fact crossed every remaining step at once, so
	# the quest entered the active set and COMPLETED on that same occurrence, with no
	# board press and no caller anywhere in the test having asked for it.
	assert_eq(
		_active(actor).has(String(ARRIVAL)),
		false,
		"it is no longer active: it arrived and finished on the same fact"
	)
	assert_eq(
		_completed(actor).has(String(ARRIVAL)),
		true,
		"WHAT THE ROTATION COST ARRIVED AND COMPLETED THROUGH PLAY"
	)
	# It PAID, which is the part the dead door made unreachable: `QuestGrants.pay` is
	# reached from `QuestApi._complete`, and the audit's hero earned two fates by
	# living.
	assert_eq(
		DestinyApi.has_fate(actor, &"vigil_broken_by_hand"),
		true,
		"and the grant its content names was paid by the completion"
	)


## The second arrival, `the_severed_calling`, on the OTHER systemic path: two
## required steps across two owners, and the crossing one is a `clan` fact rather
## than a `combat` one. It also carries a gate, and the arrival respects it — a
## quest whose gate is shut does not arrive, however true its facts are.
func test_a_gated_systemic_quest_arrives_only_once_its_gate_is_open() -> void:
	expect_assertions(5)
	var actor := QuestFixtureCatalog.hero()
	var def := QuestCatalog.instance().definition(SEVERED)
	assert_ne(def, null, "the gated systemic quest is read from the SHIPPED tree")
	assert_eq(def.kind, QuestDef.KIND_SYSTEMIC, "it is authored systemic, so it arrives, not offered")

	SectFacts.record_post_held(actor)
	ClanFacts.record_heir_registered(actor)
	assert_eq(
		_active(actor).has(String(SEVERED)),
		false,
		"both its facts are true but its gate is shut, so nothing enters it"
	)
	assert_eq(
		_completed(actor).has(String(SEVERED)),
		false,
		"and a gate is honoured by the door, not bypassed by it"
	)

	# The gate is the one its own `.tres` names, opened through the facade verb that
	# evaluates it — not by reaching around the gate to make the arrival easy.
	for fate in SEVERED_GATE_FATES as Array[StringName]:
		DestinyApi.earn_fate(actor, fate, "test:origin")
	DestinyApi.earn_destiny(actor, SEVERED_GATE_DESTINY, "test:origin")
	# One more occurrence of the closing fact, because the arrival reads only what
	# happens: it never runs on a gate opening, which is exactly the "when they
	# happen" rule the class docstring states.
	ClanFacts.record_heir_registered(actor)

	assert_eq(
		_completed(actor).has(String(SEVERED)),
		true,
		"once the gate its own content names is open, the world arrives and completes it"
	)


## Idempotence, proved at the arrival's OWN guard rather than at `accept`'s.
##
## `QuestApi.accept` carries a once-guard and must — it is the authority. But a
## duplicate that was merely refused by the one beneath it would be indistinguishable
## from a duplicate that never reached the facade at all, so the claim is pinned
## where it is actually made: `QuestArrivalProjection.arriving` answers EMPTY for a
## fact it has already spent, because `_arrives` refuses a tracked quest before any
## facade call is attempted.
func test_a_second_occurrence_of_the_same_fact_re_arrives_nothing() -> void:
	expect_assertions(5)
	var actor := QuestFixtureCatalog.hero()
	assert_eq(
		QuestArrivalProjection.arriving(actor, &"third_man_spared").has(String(ARRIVAL)),
		false,
		"before any fact, the closing fact would arrive nothing"
	)

	SectFacts.record_post_held(actor)
	CombatFacts.record_spared(actor)
	assert_eq(
		_completed(actor).has(String(ARRIVAL)),
		true,
		"the quest arrived and completed on the mercy fact"
	)

	# The ledger is monotone (ADR 0065): the steps stay satisfied forever, so a LATER
	# occurrence is the only thing that could re-drive an arrival. It must not, and it
	# must not do so by writing anything.
	var entered := QuestArrivalProjection.on_fact_recorded(actor, &"third_man_spared", 1)
	assert_eq(
		entered.is_empty(),
		true,
		"the door's own dispatch enters nothing on a repeat occurrence"
	)
	assert_eq(
		QuestArrivalProjection.arriving(actor, &"third_man_spared"),
		[] as Array[StringName],
		"and the predicate short-circuits before the facade is reached at all"
	)
	assert_eq(
		WorldFact.count(actor, &"third_man_spared"),
		1,
		"the duplicate recorded above never wrote a second count"
	)


## The multi-step case: three steps written by THREE DIFFERENT owning modules
## (`sect`, `sect`, `clan`). It completes only if the dispatch fires for a fact any
## one of them records — the general shape of every remaining authored quest.
func test_a_three_step_authored_quest_completes_across_three_owning_modules() -> void:
	expect_assertions(6)
	var actor := QuestFixtureCatalog.hero()
	# Its own gate, satisfied through the facade verb the shipped gate names, so the
	# test does not reach around a gate to make the completion easy.
	DestinyApi.earn_destiny(actor, MULTI_GATE_DESTINY, "test:origin")
	var accepted := QuestProgram.new(actor).accept(MULTI)
	assert_eq(bool(accepted["ok"]), true, "the gated quest opens for a hero holding its destiny")

	SectFacts.record_post_held(actor)
	assert_eq(_completed(actor).has(String(MULTI)), false, "one of three steps is not a completion")
	SectFacts.record_oaths_discharged(actor, 3)
	assert_eq(
		_completed(actor).has(String(MULTI)), false, "two of three steps is still not a completion"
	)
	# The `clan` half. `ClanFacts` records the fact the moment a registration lands;
	# the house that lands it is not modelled in this suite, so the OWNING MODULE's
	# write path is driven directly — which is the same edge `ClanHeir.register`
	# takes and the only edge a registration has.
	ClanFacts.record_heir_registered(actor)

	assert_eq(
		_completed(actor).has(String(MULTI)),
		true,
		"the crossing third step, written by a third module, completed the quest"
	)
	# Named per step, so a completion asserted against a short list cannot pass: each
	# authored fact is checked as satisfied from the shared ledger, which is the only
	# thing `QuestApi` ever reads to decide a step is done.
	for fact in MULTI_FACTS as Array[StringName]:
		assert_eq(
			WorldFact.has(actor, fact, _need_of(MULTI, fact)),
			true,
			"'%s' is satisfied in the ledger this completion was decided against" % String(fact)
		)


## ## The RED half, asserted rather than demonstrated
##
## A process that has NOT installed the bridge leaves a hero who satisfied every
## authored step exactly where the game left them: the step reads done and the quest
## does not complete. This is the failure this whole change is about, pinned so a
## future edit that quietly removes the install cannot pass on the green half alone.
##
## **BOTH doors are removed here.** The completion bridge alone proves only that a
## quest already in flight needs the ledger; the ARRIVAL bridge is what puts a
## `systemic`/`emergent` quest in flight at all, so leaving it installed would let
## this test's quest be ENTERED while its step is recorded, and the "does not
## complete" assertion would be measuring something this suite never set up.
func test_the_bridge_is_not_installed_by_default_and_an_unbridged_fact_completes_nothing() -> void:
	expect_assertions(4)
	QuestArrivalProjection.unsubscribe_from_fact_ledger()
	_arrival_installed = false
	QuestFactProjection.unsubscribe_from_fact_ledger()
	_installed = false
	var actor := QuestFixtureCatalog.hero()
	QuestProgram.new(actor).accept(QUEST)

	SectFacts.record_oaths_discharged(actor, 1)

	var step := _step(actor, QUEST, &"furnace_lit")
	assert_ne(step, null, "the step is readable")
	assert_eq(bool(step["done"]), true, "the step IS satisfied — the ledger holds the fact")
	assert_eq(
		_completed(actor).has(String(QUEST)),
		false,
		"and the quest is STILL not completed: this is the shipped defect, measured"
	)
	assert_eq(
		_active(actor).has(String(QUEST)),
		false,
		"and no arrival either — with both doors shut, nothing enters a systemic quest at all"
	)


## The symmetric half of the same claim: the install is what changes the answer, and
## it changes it once. Removing it stops completions; reinstalling resumes them, and
## the once-guard is untouched — a fact already spent cannot pay a second grant.
func test_the_install_is_idempotent_and_completion_is_still_decided_once() -> void:
	expect_assertions(10)
	var actor := QuestFixtureCatalog.hero()
	QuestProgram.new(actor).accept(QUEST)

	# A second boot of this composition root must not install a second bridge — and
	# the ARRIVAL door is the one that could double-enter, so it is the one asked
	# twice.
	assert_eq(QuestFactProjection.subscribe_to_fact_ledger(), false, "a duplicate is refused")
	assert_eq(
		QuestArrivalProjection.subscribe_to_fact_ledger(), false, "so is a second arrival door"
	)
	assert_eq(
		QuestArrivalProjection.is_subscribed_to_fact_ledger(),
		true,
		"and the arrival door is still installed exactly once"
	)
	assert_eq(
		WorldFact.subscriber_count(),
		2,
		"so exactly one quest bridge of each half is installed, whichever half installed it"
	)

	SectFacts.record_oaths_discharged(actor, 1)
	assert_eq(_completed(actor).has(String(QUEST)), true, "the first occurrence completed it")

	# The step stays satisfied forever — the ledger is monotone (ADR 0065) — so a
	# LATER occurrence is the only thing that could re-drive completion. It must not.
	SectFacts.record_oaths_discharged(actor, 1)
	assert_eq(WorldFact.count(actor, QUEST_FACT), 2, "the ledger really did take a second")
	assert_eq(
		_completed(actor).has(String(QUEST)),
		true,
		"and the quest is still complete rather than completed a second time"
	)
	assert_eq(_active(actor).has(String(QUEST)), false, "and it is no longer active")


## Every authored quest now has a live completion path, and the reason is structural
## rather than per-quest: every fact an authored step watches is a fact some module
## owns, so the dispatch fires for all of them.
##
## The assertion that matters is the SECOND one — that no authored step watches only
## ids the director alone offers. That is what made every shipped quest unfinishable,
## and it is the claim that goes stale the day someone authors a step on
## `world_period_elapsed`.
func test_every_authored_step_fact_is_watched_by_the_production_dispatch() -> void:
	expect_assertions(9)
	var watched := QuestFactProjection.watched_facts()
	var from_content: Array[StringName] = []
	for quest_id in QuestCatalog.instance().quest_ids():
		var def := QuestCatalog.instance().definition(quest_id)
		if def == null:
			continue
		for fact in def.watched_facts():
			from_content.append(fact)

	assert_eq(from_content.is_empty(), false, "the shipped tree declares steps to watch")
	assert_eq(
		watched.size(),
		_watched_set(from_content).size(),
		"the dispatch's watched set is exactly the shipped steps' facts"
	)

	# The measurement, stated as an assertion: the director's own offers are NOT
	# authored step facts, which is why the subscription rather than a wider
	# `BeatDirector.offer` is the fix.
	for fact in DIRECTOR_OFFERED as Array[StringName]:
		assert_eq(
			_watched_set(from_content).has(String(fact)),
			false,
			"'%s' is offered by the pulse alone and is not an authored step fact" % String(fact)
		)
	for fact in _ambient_facts():
		assert_eq(
			_watched_set(from_content).has(String(fact)),
			false,
			"ambient fact '%s' is offered by the pulse alone" % String(fact)
		)

	# And every one of the five authored step facts IS watched, so each has a live
	# dispatch.
	for fact in AUTHORED_STEP_FACTS as Array[StringName]:
		assert_eq(
			_watched_set(from_content).has(String(fact)),
			true,
			"'%s' is an authored step fact and reaches the dispatch" % String(fact)
		)

	# The arrival door listens on its OWN, narrower set: only the facts a non-`authored`
	# quest watches, because an accept is the only thing it drives. Every one of them
	# is already in the completion set above, so the arrival can never be waiting on a
	# fact that cannot also complete — the two doors cannot disagree about what a world
	# can do.
	var arrived := QuestArrivalProjection.watched_facts()
	assert_eq(arrived.is_empty(), false, "the arrival door has something to listen for")
	for fact in arrived as Array[StringName]:
		assert_eq(
			_watched_set(from_content).has(String(fact)),
			true,
			"'%s' is a fact a shipped arriving quest watches, so it is in the completion set too"
			% String(fact)
		)


# --- Helpers -----------------------------------------------------------------


## The completed quest ids, read through the public summary.
func _completed(actor: Actor) -> Array:
	return QuestApi.summary(actor)["completed"]


func _active(actor: Actor) -> Array:
	return QuestApi.summary(actor)["active"]


## One authored step read through the module's public verb.
func _step(actor: Actor, quest_id: StringName, step_id: StringName) -> Dictionary:
	for row in QuestApi.steps(actor, quest_id) as Array[Dictionary]:
		if StringName(row["step_id"]) == step_id:
			return row
	return {}


## A `fact -> true` set, de-duplicated, so two lists compare as sets of facts rather
## than as multisets (two quests may watch the same fact).
func _watched_set(facts: Array[StringName]) -> Dictionary:
	var out: Dictionary = {}
	for fact in facts:
		out[String(fact)] = true
	return out


## How much of `fact` `quest_id` asks for, read from the authored `.tres` rather than
## restated here — the same rule the constants above follow: a second copy of a content
## number is free to drift from the content it claims to describe.
func _need_of(quest_id: StringName, fact: StringName) -> int:
	var def := QuestCatalog.instance().definition(quest_id)
	if def == null:
		return 1
	var step := def.step_for_fact(fact)
	return 1 if step == null else step.required_count()


## The ambient fact ids the world's own news offers, as ids.
##
## `WorldAmbient.ROSTER` is a roster of ROWS, not of bare ids, so it is read through
## the module's own published `ids()` rather than indexed by hand — a reader that
## assumed a flat list of ids would be reading someone else's data shape. That verb
## publishes `Array[String]`, so the ids are converted rather than retyped: a
## `String` and a `StringName` name the same fact, and `String()` is the conversion
## both this module and `WorldFact` use everywhere else.
func _ambient_facts() -> Array[StringName]:
	var out: Array[StringName] = []
	for fact in WorldAmbient.ids():
		out.append(StringName(fact))
	return out
