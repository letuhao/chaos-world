class_name StoryDef
extends Resource

## One authored story: a name, a closed set of chapters, and the chapter it opens on
## (BL-0068).
##
## ## A story is a LADDER over gameplay, not a fourth kind of content
##
## BL-0053 built the quest, BL-0054 the world event, ADR 0862 the conversation. None of
## them is a sequence: a quest is one thing to do, an event is one thing happening in
## the world, a dialogue is one person talking. A story is the thing that says *in what
## order*, and what has to be true before the next one is offered. That is the whole
## job, which is why this class holds ids and gates and nothing else.
##
## ## The main story must stay ignorable (BL-0068)
##
## `optional` is the field that makes the brief's "player can ignore; coexists with
## sandbox" a property of the data rather than a promise about behaviour. When it is
## true, nothing in the game may force a chapter: the ladder only ever *offers* what its
## gates have already unlocked, and a player who never accepts is still playing the same
## world. A story with `optional == false` is the main spine and is allowed to be
## surfaced harder, and it is still never a wall — see `StoryApi` for why an unmet gate
## hides content rather than blocking play.
##
## ## Chapters are ordered by `chapters`, and the ladder is bounded
##
## `chapters` is the authored order a content audit walks, exactly as
## `DialogueDef.nodes` is. It is not the play order: a chapter opens when its `requires`
## passes, so an author may write a branch by giving two chapters the same gate. The
## cap below is what keeps a `.tres` with four thousand sub-resources from being a story
## nobody can read.
##
## ## Entry is an id, never position zero
##
## `entry_chapter` must name a chapter this def authors. Falling back to
## `chapters[0]` would be a guess about where a story OPENS, which is the one guess an
## author cannot debug — the same reasoning `DialogueDef.entry_node` records.

## The hard ceiling on authored chapters. A story is something a player finishes; a
## ladder this long is a content bug, and the number is stated so a test can name it.
const MAX_CHAPTERS := 24

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""

## An i18n slug for the blurb a codex shows, not prose.
@export var synopsis: String = ""

## Whether the player may ignore this story entirely. True for every story the sandbox
## can live without, which is BL-0068's requirement stated as data.
@export var optional: bool = true

## The chapter the story opens on. Must name a chapter this def authors.
@export var entry_chapter: StringName = &""

## Every chapter, in AUTHORED order.
@export var chapters: Array[StoryChapterDef] = []


## The chapter carrying `chapter_id`, or null. Mirrors `EventDef.stage_named`: the
## ladder is looked up by id, never by array position (ADR 0184 §5).
func chapter(chapter_id: StringName) -> StoryChapterDef:
	for row in chapters:
		if row != null and row.chapter_id == chapter_id:
			return row
	return null


## The chapter count as authored, so a screen and a test read one number.
func chapter_count() -> int:
	return chapters.size()


## Every quest id any chapter of this story depends on, in authored order and
## de-duplicated. This is the set `StoryApi` subscribes to: a quest completing outside
## it cannot move this story, so the walk is what makes "story reacts to gameplay" a
## bounded claim rather than a scan of every story on every completion.
func watched_quest_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for row in chapters:
		if row == null:
			continue
		for quest_id in row.required_quest_ids():
			if not out.has(quest_id):
				out.append(quest_id)
	return out


## Whether any chapter of this story is finished by `quest_id`.
func involves_quest(quest_id: StringName) -> bool:
	for row in chapters:
		if row != null and row.completes_on_quest(quest_id):
			return true
	return false


## The ids this def authors, sorted by TEXT. `StringName` compares by an
## interned-pointer id, so an unsorted list publishes a different order on a different
## machine — the finding `DialogueDef.node_ids` records for the same reason.
func chapter_ids() -> Array[StringName]:
	var texts: Array[String] = []
	for row in chapters:
		if row != null:
			texts.append(String(row.chapter_id))
	texts.sort()
	var out: Array[StringName] = []
	for text in texts:
		out.append(StringName(text))
	return out


## Every defect that must stop this story from reaching play, one line each.
##
## Deliberately narrow, following `EventDef.problems()`: it checks SHAPE (ids,
## duplicates, the ladder's length, whether the entry and the gates name things that
## exist) and never whether a gate is satisfied. That is the ledger's question at run
## time, not an authoring error. A content tree with an empty `problems()` list is the
## audited state.
func problems() -> Array[String]:
	var out: Array[String] = []
	if id == &"":
		out.append("story has no id")
	if display_name == "":
		out.append("%s has no display_name" % String(id))
	if chapters.is_empty():
		out.append("%s authors no chapters" % String(id))
	if chapters.size() > MAX_CHAPTERS:
		out.append(
			(
				"%s authors %d chapters; a ladder is bounded at %d"
				% [String(id), chapters.size(), MAX_CHAPTERS]
			)
		)
	if entry_chapter == &"":
		out.append("%s names no entry_chapter" % String(id))
	elif chapter(entry_chapter) == null:
		out.append(
			"%s entry_chapter '%s' is not one of its chapters" % [String(id), String(entry_chapter)]
		)

	var seen: Dictionary = {}
	var endings := 0
	for row in chapters:
		if row == null:
			out.append("%s has an empty chapter slot" % String(id))
			continue
		if row.chapter_id == &"":
			out.append("%s has a chapter with no chapter_id" % String(id))
			continue
		if seen.has(String(row.chapter_id)):
			out.append("%s authors chapter '%s' twice" % [String(id), String(row.chapter_id)])
		seen[String(row.chapter_id)] = true
		if row.is_ending:
			endings += 1
		for problem in _chapter_problems(row):
			out.append("%s chapter '%s' %s" % [String(id), String(row.chapter_id), problem])

	if endings == 0:
		out.append("%s has no chapter marked final; the story never closes" % String(id))
	elif endings > 1:
		out.append("%s marks %d chapters final; a ladder has one ending" % [String(id), endings])
	return out


## One chapter's own shape faults, as fragments the caller prefixes. Kept separate so
## the message reads as one sentence either way.
##
## Quest existence is read through `QuestApi.catalog()` and NOT by naming
## `QuestCatalog`: the facade rule means `api.gd` is the only file another module may
## reference, and a story that reaches the quest catalog directly is a second, undeclared
## edge into a module it already depends on.
func _chapter_problems(row: StoryChapterDef) -> Array[String]:
	var out: Array[String] = []
	if not row.well_formed():
		out.append("names no completion gate; it would finish the instant it opened")
	for gate_name in ["requires", "completion"]:
		var gate: Dictionary = row.requires if gate_name == "requires" else row.completion
		for verb in StoryGate.verbs_in(gate):
			if not StoryGate.KNOWN_VERBS.has(verb):
				out.append(
					(
						"%s gate names verb '%s', which is not one this module reads"
						% [gate_name, String(verb)]
					)
				)
		for quest_id in row.required_quest_ids():
			if not QuestApi.catalog().has(String(quest_id)):
				out.append("names quest '%s', which no catalog defines" % String(quest_id))
	return out
