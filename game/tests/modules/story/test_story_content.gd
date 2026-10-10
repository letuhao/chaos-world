extends TestCase

## BL-0068's content claim, asserted against the SHIPPED tree.
##
## `test_story.gd` proves the module's behaviour with in-code fixtures. This suite does the
## opposite: it reads `res://data/story/stories/` through the real catalog and asserts the
## authored content is well formed. If shipped content drifts, this file goes red rather than
## a panel discovering it in play.
##
## ## The load-bearing assertion
##
## `test_every_shipped_story_reports_no_problems`. `StoryDef.problems()` is the module's own
## content guard, and it is the reason a gate typo is a build failure instead of a chapter that
## never opens. Running it over real content, not over a fixture built to satisfy it, is what
## makes that guard worth having.
##
## ## Every loop below must assert at least once
##
## These suites iterate shipped content, so an empty tree makes every one of them vacuously
## true. The framework charges a failure to any test that asserts nothing, even one with a
## declared floor, and that is the right call: a content suite passing because there is no
## content reports confidence nobody earned. So the tree is asserted non-empty first, and the
## test that can legitimately find nothing to check states its claim as a property that holds
## either way rather than as a loop.

const REQUIRED_FIELDS := ["id", "display_name", "description", "entry_chapter", "chapters"]
const REQUIRED_CHAPTER_FIELDS := ["chapter_id", "display_name", "requires", "completion"]


func _shipped() -> Array[StoryDef]:
	var out: Array[StoryDef] = []
	var catalog := StoryCatalog.instance()
	for story_id in catalog.story_ids():
		var def := catalog.definition(story_id)
		if def != null:
			out.append(def)
	return out


## The tree must be non-empty, or every assertion in this file is vacuous.
func test_the_authored_tree_loads_at_all() -> void:
	# A `.tres` with a wrong `script_class=`, a mistyped `Array[StoryChapterDef]`, or a
	# dangling ExtResource id does not fail loudly at boot: the catalog's text pre-scan
	# skips it and the story is simply invisible. So the count of files on disk must equal
	# the count the catalog answers for, or content is being silently dropped.
	var files := DirAccess.get_files_at("res://data/story/stories")
	var readable := 0
	for name in files:
		if name.ends_with(".tres"):
			readable += 1
	# `assert_eq(readable == 0, false)`, NOT `assert_ne(readable, false)`.
	# `test_quest_content.gd` records that spelling: `assert_ne(x, false)` demands x be TRUE,
	# so it asserted the authored tree was EMPTY and went red the day the first content
	# landed. The equality alone is not enough either: at 0 == 0 it is vacuously true, so a
	# `.tres` the catalog refuses to load would still look green.
	assert_eq(readable == 0, false, "the authored story tree is not empty")
	assert_eq(
		_shipped().size(),
		readable,
		(
			"every authored story .tres is loaded by the catalog (%d files, %d defs)"
			% [readable, _shipped().size()]
		)
	)


func test_every_shipped_story_reports_no_problems() -> void:
	for def in _shipped():
		var found := def.problems()
		assert_eq(
			found.is_empty(),
			true,
			"%s is well formed; problems: %s" % [String(def.id), ", ".join(found)]
		)


func test_shipped_stories_carry_the_fields_a_reader_needs() -> void:
	for def in _shipped():
		for field in REQUIRED_FIELDS:
			assert_eq(def.get(field) != null, true, "%s carries '%s'" % [def.id, field])
		assert_eq(
			String(def.display_name).begins_with("LOC_"),
			true,
			"%s display_name is an i18n slug, not prose" % def.id
		)
		assert_eq(
			String(def.description).begins_with("LOC_"),
			true,
			"%s description is an i18n slug, not prose" % def.id
		)


func test_shipped_chapters_carry_the_fields_a_gate_walk_needs() -> void:
	for def in _shipped():
		for row in def.chapters:
			for field in REQUIRED_CHAPTER_FIELDS:
				assert_eq(
					row.get(field) != null,
					true,
					"%s/%s carries '%s'" % [def.id, row.chapter_id, field]
				)
			assert_eq(
				row.well_formed(),
				true,
				(
					"%s/%s names a completion gate, so it cannot complete on opening"
					% [def.id, row.chapter_id]
				)
			)


## The rule that keeps a ladder a ladder: one ending, and the entry is a real chapter.
func test_each_shipped_story_opens_and_closes_exactly_once() -> void:
	for def in _shipped():
		var endings := 0
		for row in def.chapters:
			if row.is_ending:
				endings += 1
		assert_eq(endings, 1, "%s has exactly one ending chapter, found %d" % [def.id, endings])
		assert_eq(
			def.chapter(def.entry_chapter) != null,
			true,
			"%s entry_chapter names a chapter it authors" % def.id
		)
		assert_eq(
			def.chapters.size() <= StoryDef.MAX_CHAPTERS,
			true,
			"%s is within the %d-chapter cap" % [def.id, StoryDef.MAX_CHAPTERS]
		)


## Every quest a chapter waits on must exist, or the chapter never opens. This is
## `problems()`'s job too; asserting it separately names the failure as a CONTENT gap
## rather than folding it into a generic "problems: ..." string.
func test_no_shipped_chapter_waits_on_a_quest_that_does_not_ship() -> void:
	var quests := QuestApi.catalog()
	for def in _shipped():
		for row in def.chapters:
			for quest_id in row.required_quest_ids():
				assert_eq(
					quests.has(String(quest_id)),
					true,
					(
						"%s/%s waits on quest '%s', which no catalog defines"
						% [def.id, row.chapter_id, quest_id]
					)
				)


## BL-0068's other half, stated as data: the story must be ignorable. A shipped story with
## `optional == false` is a deliberate exception and this test says so out loud rather than
## letting a panel discover a forced main line.
func test_shipped_stories_default_to_ignorable() -> void:
	for def in _shipped():
		assert_eq(
			def.optional,
			true,
			"%s is optional, so nothing may force its chapters (BL-0068)" % def.id
		)


## A chapter's `dialogue_id`, when set, must name a conversation that exists. Story starts
## nothing itself, but a dangling id is a silent no-op in play.
##
## Accumulated then asserted once, because the framework's rule is absolute: a test that asserts
## nothing is a failure even with a declared floor, and `expect_assertions(0)` does not exempt
## it. A loop that only asserts inside a conditional is therefore a test that fails whenever the
## condition is never true, which is exactly now: no shipped chapter wires a conversation yet.
## Stating the claim as "no dangling dialogue id exists" holds either way and always asserts.
func test_shipped_chapter_dialogue_ids_resolve() -> void:
	var dangling: Array[String] = []
	for def in _shipped():
		for row in def.chapters:
			if row.dialogue_id == &"":
				continue
			if DialogueCatalog.instance().definition(row.dialogue_id) != null:
				continue
			dangling.append("%s/%s -> %s" % [def.id, row.chapter_id, row.dialogue_id])
	assert_eq(
		dangling.is_empty(),
		true,
		"every chapter dialogue_id resolves; dangling: %s" % ", ".join(dangling)
	)
