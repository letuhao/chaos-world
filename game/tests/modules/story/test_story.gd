extends TestCase

## BL-0068's central claims, asserted against in-code fixtures.
##
## Story owns NO state, so every assertion here is about a DERIVED reading: the same
## authored ladder answered two different ways by the quest ledger and the fact ledger,
## and the difference between those two answers is the whole module.
##
## ## The assertion that matters most
##
## `test_a_false_gate_hides_and_never_blocks`. BL-0068 says the main story must be
## ignorable and coexist with the sandbox, and the only way that is a fact rather than a
## promise is that an unmet gate produces an empty board, not a refusal. A module with no
## write verbs makes that true by construction, and this file asserts it so a future verb
## that blocks play is caught here rather than in play.

const QUEST_A := &"t_story_quest_a"
const QUEST_B := &"t_story_quest_b"
const FACT_A := &"t_story_fact_a"

## A quest def the story gate can name. `StoryDef.problems()` reads quest existence
## through `QuestApi.catalog()`, so a fixture story naming a quest nobody installs reports
## that quest as missing — which is the behaviour `test_problems_names_an_unknown_quest`
## wants, and the reason the passing tests install these.
const REAL_QUEST := &"the_short_road"


func setup() -> void:
	expect_assertions(1)


func teardown() -> void:
	StoryFixtureCatalog.teardown()
	QuestFixtureCatalog.teardown()


# --- The ladder walks ------------------------------------------------------


## An entry chapter with an empty `requires` opens; the next one waits for its quest.
func test_the_ladder_walks_one_chapter_at_a_time() -> void:
	QuestFixtureCatalog.install([QuestFixtureCatalog.quest(QUEST_A)])
	(
		StoryFixtureCatalog
		. install(
			[
				(
					StoryFixtureCatalog
					. story(
						&"t_walk",
						[
							StoryFixtureCatalog.chapter(
								&"c1", {}, StoryFixtureCatalog.quest_done(QUEST_A)
							),
							StoryFixtureCatalog.chapter(
								&"c2",
								StoryFixtureCatalog.quest_done(QUEST_A),
								StoryFixtureCatalog.quest_done(QUEST_B),
								&"",
								true
							),
						]
					)
				)
			]
		)
	)

	var hero := Actor.new()
	var before := StoryApi.progress(hero, &"t_walk")
	assert_eq(bool(before["known"]), true, "the fixture story is known")
	assert_eq(
		String(before["chapter_id"]), "c1", "an ungated entry chapter is where the player stands"
	)
	assert_eq(bool(before["done"]), false, "and it is not done")

	_complete_quest(hero, QUEST_A)
	var after := StoryApi.progress(hero, &"t_walk")
	assert_eq(
		String(after["chapter_id"]), "c2", "completing the quest moved the player up one rung"
	)
	assert_eq(after["blocked_by"] is Array, true, "blocked_by is always an array")


## A chapter whose completion gate is already true when it opens reads done at once.
##
## This is the honest consequence of deriving rather than storing, and it is asserted so
## nobody "fixes" it by adding a `started` stamp and a second copy of the truth.
func test_a_chapter_already_satisfied_reads_done_immediately() -> void:
	QuestFixtureCatalog.install(
		[QuestFixtureCatalog.quest(QUEST_A), QuestFixtureCatalog.quest(QUEST_B)]
	)
	StoryFixtureCatalog.install(
		[
			StoryFixtureCatalog.story(
				&"t_pre",
				[
					StoryFixtureCatalog.chapter(&"c1", {}, StoryFixtureCatalog.quest_done(QUEST_A)),
					StoryFixtureCatalog.chapter(
						&"c2",
						StoryFixtureCatalog.quest_done(QUEST_A),
						StoryFixtureCatalog.quest_done(QUEST_B),
						&"",
						true
					)
				]
			)
		]
	)

	var hero := Actor.new()
	_complete_quest(hero, QUEST_A)
	_complete_quest(hero, QUEST_B)
	var read := StoryApi.progress(hero, &"t_pre")
	assert_eq(bool(read["done"]), true, "a chapter the world already satisfies is satisfied")
	assert_eq(String(read["chapter_id"]), "c2", "and the walk reaches the ending")


# --- Gates are data --------------------------------------------------------


## The one verb this module adds, and the ones it delegates, all read the same shape.
func test_the_gate_vocabulary_is_one_language() -> void:
	var quest_gate := StoryFixtureCatalog.quest_done(QUEST_A)
	assert_eq(
		bool(StoryGate.evaluate(null, quest_gate).get("ok", false)),
		false,
		"a null actor reads unmet rather than raising"
	)
	assert_eq(
		String(StoryGate.evaluate(null, quest_gate).get("reason", "")),
		"no_ledger",
		"and says which"
	)

	# An unknown verb REFUSES and names itself; it is never an unmet, because a typo
	# that reads as progression is invisible content.
	var typo := {"verb": &"has_vibes", "id": &"good"}
	var verdict := StoryGate.evaluate(Actor.new(), typo)
	assert_eq(bool(verdict.get("ok", false)), false, "an unknown verb does not pass")
	assert_eq(String(verdict.get("reason", "")), "unknown_verb", "and refuses with the cause named")
	assert_eq(
		StoryGate.KNOWN_VERBS.has(&"quest_done"), true, "quest_done is this module's own verb"
	)
	assert_eq(StoryGate.KNOWN_VERBS.has(&"fact"), true, "fact is read through the shared ledger")
	assert_eq(
		StoryGate.KNOWN_VERBS.has(&"has_fate"), true, "fate verbs are delegated, not re-implemented"
	)


## `all_of` / `any_of` / `none_of` are reused verbatim, not re-derived.
func test_composites_compose_the_same_verbs() -> void:
	QuestFixtureCatalog.install(
		[QuestFixtureCatalog.quest(QUEST_A), QuestFixtureCatalog.quest(QUEST_B)]
	)
	var hero := Actor.new()
	_complete_quest(hero, QUEST_A)

	var all_of := {
		"verb": &"all_of",
		"of": [StoryFixtureCatalog.quest_done(QUEST_A), StoryFixtureCatalog.quest_done(QUEST_B)]
	}
	var any_of := {
		"verb": &"any_of",
		"of": [StoryFixtureCatalog.quest_done(QUEST_A), StoryFixtureCatalog.quest_done(QUEST_B)]
	}
	var none_of := {"verb": &"none_of", "of": [StoryFixtureCatalog.quest_done(QUEST_B)]}
	assert_eq(bool(StoryGate.evaluate(hero, all_of).get("ok", false)), false, "all_of needs both")
	assert_eq(bool(StoryGate.evaluate(hero, any_of).get("ok", false)), true, "any_of needs one")
	assert_eq(
		bool(StoryGate.evaluate(hero, none_of).get("ok", false)), true, "none_of needs neither"
	)


## A fact gate reads the ONE ledger, so a chapter can be satisfied by anything the world
## remembers, not only by a quest the player was handed.
func test_a_fact_gate_reads_the_shared_ledger() -> void:
	(
		StoryFixtureCatalog
		. install(
			[
				(
					StoryFixtureCatalog
					. story(
						&"t_fact",
						# `is_ending` is load-bearing, not decoration: `progress().done` means "the ladder
						# reached its ending AND that ending's gate passes", so a non-ending chapter reads
						# `done: false` forever however its completion gate is answered. Asserting a
						# completion crossing needs an ending.
						[
							StoryFixtureCatalog.chapter(
								&"c1", {}, StoryFixtureCatalog.fact(FACT_A, 2), &"", true
							)
						]
					)
				)
			]
		)
	)
	var hero := Actor.new()
	assert_eq(bool(StoryApi.progress(hero, &"t_fact")["done"]), false, "no fact yet")
	StoryFixtureCatalog.record_fact(hero, FACT_A, 1)
	assert_eq(bool(StoryApi.progress(hero, &"t_fact")["done"]), false, "one of two is not two")
	StoryFixtureCatalog.record_fact(hero, FACT_A, 1)
	assert_eq(bool(StoryApi.progress(hero, &"t_fact")["done"]), true, "the crossing completes it")


# --- The sandbox rule (BL-0068) -------------------------------------------


## A false gate HIDES. It never blocks, because story has no write verb to block with.
func test_a_false_gate_hides_and_never_blocks() -> void:
	QuestFixtureCatalog.install([QuestFixtureCatalog.quest(QUEST_A)])
	(
		StoryFixtureCatalog
		. install(
			[
				(
					StoryFixtureCatalog
					. story(
						&"t_hide",
						[
							StoryFixtureCatalog.chapter(
								&"c1", {}, StoryFixtureCatalog.quest_done(QUEST_A)
							),
							StoryFixtureCatalog.chapter(
								&"c2",
								StoryFixtureCatalog.quest_done(QUEST_A),
								StoryFixtureCatalog.quest_done(QUEST_B),
								&"",
								true
							),
						]
					)
				)
			]
		)
	)

	var hero := Actor.new()
	var offered := StoryApi.offered(hero)
	assert_eq(offered.size(), 1, "only the chapter whose gate passes is on the board")
	assert_eq(String((offered[0] as Dictionary)["chapter_id"]), "c1", "and it is the entry chapter")
	# The whole of BL-0068's "player can ignore" in one assertion: nothing was refused,
	# nothing was spent, the board simply held one fewer row.
	assert_eq(StoryApi.problems().size(), 0, "and hiding content is not an error")


## `stories_for_quest` is the subscription filter, and it is bounded by authored content.
func test_stories_for_quest_is_the_subscription_filter() -> void:
	QuestFixtureCatalog.install(
		[QuestFixtureCatalog.quest(QUEST_A), QuestFixtureCatalog.quest(QUEST_B)]
	)
	(
		StoryFixtureCatalog
		. install(
			[
				StoryFixtureCatalog.story(
					&"t_one",
					[
						StoryFixtureCatalog.chapter(
							&"c1", {}, StoryFixtureCatalog.quest_done(QUEST_A)
						)
					]
				),
				StoryFixtureCatalog.story(
					&"t_two",
					[
						StoryFixtureCatalog.chapter(
							&"c1", {}, StoryFixtureCatalog.quest_done(QUEST_B)
						)
					]
				),
			]
		)
	)
	assert_eq(StoryApi.stories_for_quest(QUEST_A).size(), 1, "one story watches quest A")
	assert_eq(String(StoryApi.stories_for_quest(QUEST_A)[0]), "t_one", "and it is named")
	assert_eq(
		StoryApi.stories_for_quest(&"t_nobody").size(),
		0,
		"a quest no story names reaches no gate at all"
	)


# --- Authoring refusals ----------------------------------------------------


## A chapter with no completion gate would finish the instant it opened, so it is a
## content bug and reported as one.
func test_problems_refuse_an_unfinishable_chapter() -> void:
	var broken := StoryFixtureCatalog.story(
		&"t_broken", [StoryFixtureCatalog.chapter(&"c1", {}, {})]
	)
	var found := broken.problems()
	assert_ne(found.size(), 0, "a chapter with no completion gate is reported")
	assert_eq(_any_contains(found, "completion"), true, "and the reason names the gate")


## A story whose entry chapter names nothing is unstartable, and guessing `chapters[0]`
## would hide it.
func test_problems_refuse_an_entry_that_names_nothing() -> void:
	var def := StoryFixtureCatalog.story(
		&"t_entry",
		[StoryFixtureCatalog.chapter(&"c1", {}, StoryFixtureCatalog.quest_done(REAL_QUEST))]
	)
	def.entry_chapter = &"c_missing"
	assert_eq(_any_contains(def.problems(), "entry_chapter"), true, "a dangling entry is named")


## Two endings is no ending; zero endings is a story that never closes.
func test_problems_count_endings() -> void:
	var two := (
		StoryFixtureCatalog
		. story(
			&"t_two_endings",
			[
				StoryFixtureCatalog.chapter(
					&"c1", {}, StoryFixtureCatalog.quest_done(REAL_QUEST), &"", true
				),
				StoryFixtureCatalog.chapter(
					&"c2", {}, StoryFixtureCatalog.quest_done(REAL_QUEST), &"", true
				),
			]
		)
	)
	assert_eq(_any_contains(two.problems(), "2 chapters final"), true, "two endings are reported")

	var none := StoryFixtureCatalog.story(
		&"t_no_end",
		[StoryFixtureCatalog.chapter(&"c1", {}, StoryFixtureCatalog.quest_done(REAL_QUEST))]
	)
	assert_eq(_any_contains(none.problems(), "no chapter marked final"), true, "and so is none")


## A gate naming a verb this module does not read is a typo, not progression.
func test_problems_name_an_unknown_gate_verb() -> void:
	var def := StoryFixtureCatalog.story(
		&"t_typo",
		[StoryFixtureCatalog.chapter(&"c1", {}, {"verb": &"quest_finished", "id": REAL_QUEST})]
	)
	assert_eq(_any_contains(def.problems(), "quest_finished"), true, "the near-miss verb is named")


## A chapter naming a quest that does not exist is caught at authoring time.
func test_problems_names_an_unknown_quest() -> void:
	QuestFixtureCatalog.install([])
	var def := StoryFixtureCatalog.story(
		&"t_ghost",
		[StoryFixtureCatalog.chapter(&"c1", {}, StoryFixtureCatalog.quest_done(&"t_ghost_quest"))]
	)
	assert_eq(
		_any_contains(def.problems(), "t_ghost_quest"),
		true,
		"a quest no catalog defines is reported"
	)


## A well-formed fixture story reports nothing, so the refusals above are the rule and
## not a guard that always fires.
func test_a_well_formed_story_reports_nothing() -> void:
	QuestFixtureCatalog.install([QuestFixtureCatalog.quest(REAL_QUEST)])
	var def := (
		StoryFixtureCatalog
		. story(
			&"t_clean",
			[
				StoryFixtureCatalog.chapter(&"c1", {}, StoryFixtureCatalog.quest_done(REAL_QUEST)),
				StoryFixtureCatalog.chapter(
					&"c2",
					StoryFixtureCatalog.quest_done(REAL_QUEST),
					StoryFixtureCatalog.quest_done(REAL_QUEST),
					&"",
					true
				),
			]
		)
	)
	assert_eq(
		def.problems().size(), 0, "a clean ladder has nothing to report: %s" % str(def.problems())
	)


# --- Internals -------------------------------------------------------------


## Mark `QUEST` completed on `hero`, exactly as `QuestState.finish` does.
##
## Story has no write verb and this module never calls `QuestApi.complete` (that would
## pay grants and needs a fate catalog), so the test writes the ledger row the same way
## `QuestFixtureCatalog` writes a fact: directly, as the system that owns it would.
func _complete_quest(hero: Actor, quest_id: StringName) -> void:
	var ledger: Dictionary = hero.get_module_data(&"quest_state")
	if ledger.is_empty():
		ledger = {"version": 1, "active": {}, "offered": []}
	(ledger["active"] as Dictionary)[String(quest_id)] = {
		"started": 0, "completed": true, "failed": false
	}
	hero.set_module_data(&"quest_state", ledger)


func _any_contains(lines: Array[String], needle: String) -> bool:
	for line in lines:
		if line.contains(needle):
			return true
	return false
