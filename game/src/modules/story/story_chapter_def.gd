class_name StoryChapterDef
extends Resource

## One chapter of an authored story: a rung on a ladder, and the gate that says the
## rung has been reached (BL-0068).
##
## ## A chapter is a POINTER to gameplay, never a replacement for it
##
## A chapter holds no steps, no beats, no fights, no dialogue text and NO rewards. It
## names the thing that must have happened (`completion`) and, optionally, the
## conversation that plays when it opens (`dialogue_id`). The quest owns its steps AND
## its grants, the dialogue owns its nodes, the event owns its stages.
##
## **Why there is no `grants` field, and why that is load-bearing.** A chapter almost
## always completes on a quest, and that quest already pays through `QuestGrants`. A
## second reward row on the chapter would mean two payers answering one "what did this
## award" question, and paying twice for one action. The repo's answer to that shape is
## always the same: one home per rule. If a chapter ever needs an award its quest does
## not carry, the fix is a grant on the quest, not a grant on the chapter.
##
## ## Both gates are DATA in the one shared requirement language
##
## `requires` and `completion` are read by `StoryGate`, the shape `EventGate`
## established: this module contributes exactly ONE verb ([constant
## StoryGate.VERB_QUEST_DONE]), reuses the three composite verbs, and delegates every
## fate verb to `DestinyApi.gate` verbatim. A new gated chapter is a content edit and
## never a code change (ADR 0065/0066). An empty gate is ungated.
##
## ## This module never writes the ledger (ADR 0113)
##
## A chapter has no `on_enter` beats and records no fact, deliberately. A chapter
## opening is not something the world DID; it is where the player has got to, which is
## narrative state, not a world fact. ADR 0114 already names one director and one
## resolution rule, and a second writer of beats is how "the player did X" ends up with
## two homes. Story READS. Quests, events, combat and npc tallies are what write.
##
## ## Completion is DERIVED, not stored
##
## Nothing here is persisted. Whether a chapter is done is recomputed from these gates
## against state another module already owns, so a story needs no save schema and cannot
## drift from the quest it waits on. The consequence is honest: a chapter whose
## completion gate is a fact the player made true BEFORE the chapter opened reads done
## the instant it opens. That is the correct reading of "the world already remembers it",
## and it is why no `started` stamp exists.

## The stable id, unique inside its own story. It is what `StoryDef.entry_chapter` names
## and what a content guard walks, so a rename is a content break, not a label edit.
@export var chapter_id: StringName = &""

## Player-facing title. An i18n slug (`LOC_STORY_<id>_CHAPTER_<n>_DISPLAY_NAME`), never
## prose: every string the player reads goes through `tools i18n extract`.
@export var display_name: String = ""
@export var description: String = ""

## The gate that OPENS this chapter, in the requirement language. Empty means it opens
## as soon as the ladder reaches it, which is the right shape for chapter one.
@export var requires: Dictionary = {}

## The gate that says this chapter is DONE, in the same language. Almost always
## `{verb: "quest_done", id: <quest_id>}`: the quest is the unit of authored player
## action.
##
## Empty is a content bug rather than an ungated chapter, and [method well_formed] says
## so. A chapter that completes the moment it opens is not a chapter; it is a story that
## is quietly shorter than its author thinks.
@export var completion: Dictionary = {}

## The `DialogueDef.dialog_id` that plays when this chapter opens, or `&""` for a
## chapter with no conversation. A pointer only: story never names a node, so it
## declares no dependency on how the conversation is built.
@export var dialogue_id: StringName = &""

## Whether completing this chapter ends the story. Exactly one chapter of a story SHOULD
## set this, and `StoryDef.problems()` reports the count rather than guessing: a story
## with two endings has no ending, and a story with none never closes.
##
## Named `is_ending` rather than `final` because `final` is reserved-word territory in
## GDScript and a content field that will not parse is the most expensive kind of typo.
@export var is_ending: bool = false


## A chapter must name itself and must name something that can finish it.
func well_formed() -> bool:
	return chapter_id != &"" and not completion.is_empty()


## Whether this chapter's completion gate names `quest_id`. This is the question
## `StoryApi` asks to decide whether a quest completing can move the story at all, and
## it is answered by a walk over the authored gate, never a string match on a
## serialized dictionary.
func completes_on_quest(quest_id: StringName) -> bool:
	for id in _all_quest_ids(completion):
		if id == quest_id:
			return true
	return false


## Every `quest_done` id this chapter names across BOTH gates, in authored order and
## de-duplicated. This is the subscription set: the chapter cannot move on a quest
## outside it.
##
## `requires` is included as well as `completion` because a chapter gated *behind* a
## quest also depends on that quest — if it completes, the chapter may now open, which
## is a story change just as much as a completion is.
##
## One bounded walk over the authored nesting, the shape `QuestDef._collect_gate_ids`
## uses: the depth is what the author wrote, never an unbounded search.
func required_quest_ids() -> Array[StringName]:
	var out: Array[StringName] = _all_quest_ids(requires)
	for id in _all_quest_ids(completion):
		if not out.has(id):
			out.append(id)
	return out


func _all_quest_ids(node) -> Array[StringName]:
	var out: Array[StringName] = []
	_collect_quest_ids(node, out)
	return out


func _collect_quest_ids(node, out: Array[StringName]) -> void:
	if not (node is Dictionary):
		return
	var entry := node as Dictionary
	var verb := StringName(entry.get("verb", ""))
	if StoryGate.COMPOSITE_VERBS.has(verb):
		var children = entry.get("of", [])
		if not (children is Array):
			return
		# `size()` bounds the walk: a composite names exactly its own children.
		for index in range((children as Array).size()):
			_collect_quest_ids((children as Array)[index], out)
		return
	if verb == StoryGate.VERB_QUEST_DONE:
		var id := StringName(entry.get("id", ""))
		if id != &"" and not out.has(id):
			out.append(id)
