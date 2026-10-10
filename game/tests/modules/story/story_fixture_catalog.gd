class_name StoryFixtureCatalog
extends RefCounted

## A test-local stand-in for `StoryCatalog`, holding `StoryDef` resources built in code.
## The module reads content through the catalog singleton, so the logic tests install
## their own catalog for the span of one test rather than depending on which `.tres`
## files happen to exist today.
##
## `test_story_content.gd` does the opposite: it reads the real tree and asserts shipped
## content is well formed. Between them a fixture can never quietly become the only thing
## that works.
##
## Fixtures use a reserved `t_` id prefix so they can never collide with a real authored
## story, and `teardown()` restores whatever catalog the process held beforehand.
##
## ## The typed-array trap, inherited and avoided
##
## `QuestFixtureCatalog` records that assigning an untyped `Array` to a typed
## `Array[Dictionary]` export is a RUNTIME type error which aborts the builder before its
## `return`, so the caller installs a `null` definition and every assertion answers
## `unknown_quest`. A fixture that silently returns null looks exactly like a module with
## no catalog. `chapter()` therefore builds `Array[Dictionary]` explicitly.


## Replace the module's catalog singleton for the span of one test.
static func install(defs: Array) -> void:
	var catalog := StoryCatalog.new()
	for def in defs:
		if def is StoryDef:
			catalog._defs[String(def.id)] = def
	catalog._loaded = true
	StoryCatalog.shared = catalog


## Undo `install`. The real catalog is what the singleton lazily rebuilds when
## `shared` is null, so a restored test that needs shipped content simply has none
## installed. This is `QuestFixtureCatalog.teardown`'s shape, deliberately.
static func teardown() -> void:
	StoryCatalog.shared = null


## Record `amount` of `fact` on `actor`, through core's own ledger verb.
##
## `WorldFact.record` is the write side of the read `StoryGate` delegates to, so a test
## that needs a fact gate satisfied makes one true the same way the world does. Story
## exposes no write verb of its own, which is the property the suite is checking.
static func record_fact(actor: Actor, fact: StringName, amount: int = 1) -> void:
	WorldFact.record(actor, fact, amount)


## Completing a quest is done in the test file, not here: `_complete_quest` stamps the
## `quest_state` ledger directly, which is what `QuestApi.complete` ends up persisting.
## `StoryApi` has no write verb at all, so a chapter can only ever be opened by something
## outside this module — which is the BL-0068 claim under test.


## One chapter. `requires` and `completion` are gate dictionaries in the shared
## requirement language; `quest_done(quest_id)` is the shorthand this module's own verb.
static func chapter(
	chapter_id: StringName,
	requires: Dictionary = {},
	completion: Dictionary = {},
	dialogue_id: StringName = &"",
	is_ending: bool = false
) -> StoryChapterDef:
	var row := StoryChapterDef.new()
	row.chapter_id = chapter_id
	row.display_name = String(chapter_id).capitalize()
	row.description = "Fixture chapter %s." % chapter_id
	row.requires = requires
	row.completion = completion
	row.dialogue_id = dialogue_id
	row.is_ending = is_ending
	return row


## `{verb: "quest_done", id: quest_id}` — the shape almost every chapter completes on.
static func quest_done(quest_id: StringName) -> Dictionary:
	return {"verb": StoryGate.VERB_QUEST_DONE, "id": quest_id}


## `{verb: "fact", id: fact_id, need: need}` — the shared ledger read.
static func fact(fact_id: StringName, need: int = 1) -> Dictionary:
	return {"verb": StoryGate.VERB_FACT, "id": fact_id, "need": need}


## A story whose chapters are the array, in authored order, opening on the first.
static func story(story_id: StringName, chapters: Array, optional: bool = true) -> StoryDef:
	var def := StoryDef.new()
	def.id = story_id
	def.display_name = String(story_id).capitalize()
	def.description = "Fixture story %s." % story_id
	def.optional = optional
	def.entry_chapter = &"" if chapters.is_empty() else (chapters[0] as StoryChapterDef).chapter_id
	for row in chapters:
		if row is StoryChapterDef:
			def.chapters.append(row)
	return def
