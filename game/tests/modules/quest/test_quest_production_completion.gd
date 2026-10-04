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
## goes through `app/QuestProgram`, the one production caller of `accept`, and the
## completion is observed, never requested.

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
const QUEST := &"the_short_road"
const QUEST_FACT := &"oaths_discharged"

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


func teardown() -> void:
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


## The same proof on a quest whose `kind` makes it un-offerable, which is the
## strongest form available: `systemic` quests are never handed out by
## `QuestApi.offered` (BL-0053), so there is NO code path a test could use to
## complete this one by hand. It can only complete by living.
func test_the_systemic_quest_is_never_offered_so_only_a_recorded_fact_can_finish_it() -> void:
	var actor := QuestFixtureCatalog.hero()
	var def := QuestCatalog.instance().definition(QUEST)
	assert_ne(def, null, "the shipped quest exists")
	assert_eq(def.kind, QuestDef.KIND_SYSTEMIC, "it is authored systemic, not offered on a board")

	var offered: Array[String] = []
	for row in QuestApi.offered(actor) as Array[Dictionary]:
		offered.append(String(row["id"]))
	assert_eq(
		offered.has(String(QUEST)),
		false,
		"nothing in the game hands this quest to the player"
	)

	# Not accepted either, so only the dispatch could ever finish it.
	assert_eq(
		_completed(actor).has(String(QUEST)),
		false,
		"and it is not even active: the world itself is the only door to it"
	)

	SectFacts.record_oaths_discharged(actor, 1)

	assert_eq(
		_completed(actor).has(String(QUEST)),
		true,
		"a systemic quest completes from a fact its owner recorded, with nothing handed to the player"
	)


## The multi-step case: three steps written by THREE DIFFERENT owning modules
## (`sect`, `sect`, `clan`). It completes only if the dispatch fires for a fact any
## one of them records — the general shape of every remaining authored quest.
func test_a_three_step_authored_quest_completes_across_three_owning_modules() -> void:
	var actor := QuestFixtureCatalog.hero()
	# Its own gate, satisfied through the facade verb the shipped gate names, so the
	# test does not reach around a gate to make the completion easy.
	DestinyApi.earn_destiny(actor, MULTI_GATE_DESTINY, "test:origin")
	var accepted := QuestProgram.new(actor).accept(MULTI)
	assert_eq(bool(accepted["ok"]), true, "the gated quest opens for a hero holding its destiny")

	SectFacts.record_post_held(actor)
	assert_eq(
		_completed(actor).has(String(MULTI)),
		false,
		"one of three steps is not a completion"
	)
	SectFacts.record_oaths_discharged(actor, 3)
	assert_eq(
		_completed(actor).has(String(MULTI)),
		false,
		"two of three steps is still not a completion"
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
func test_the_bridge_is_not_installed_by_default_and_an_unbridged_fact_completes_nothing() -> void:
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


## The symmetric half of the same claim: the install is what changes the answer, and
## it changes it once. Removing it stops completions; reinstalling resumes them, and
## the once-guard is untouched — a fact already spent cannot pay a second grant.
func test_the_install_is_idempotent_and_completion_is_still_decided_once() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestProgram.new(actor).accept(QUEST)

	# A second boot of this composition root must not install a second bridge.
	assert_eq(QuestFactProjection.subscribe_to_fact_ledger(), false, "a duplicate is refused")
	assert_eq(
		WorldFact.subscriber_count(),
		1,
		"so exactly one quest bridge is installed, whichever half installed it"
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
	for fact in WorldAmbient.ROSTER:
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
