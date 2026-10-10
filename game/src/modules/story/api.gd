class_name StoryApi
extends RefCounted

## Public facade for the `story` module. Other modules may reference ONLY this file
## (`api.gd`). Concrete implementations live beside it and are wired in `app/`.
##
## ## Story is a LENS, not a fourth ledger
##
## BL-0053 built the quest, BL-0054 the world event, ADR 0862 the conversation. A story
## sequences those; it owns nothing they own. So this module has **no state of its own**:
## no `MODULE_KEY`, no `attach`, no save schema, no `to_dict`. Whether a chapter is open
## or done is recomputed from the quest ledger and the world fact ledger every time it is
## asked. That is the whole design and it buys three things:
##
##   - a story cannot drift from the quest it waits on, because it stores nothing about it;
##   - a save carries one copy of "the player finished that quest", not two;
##   - a mod that deletes a story cannot corrupt a save, because there is nothing to corrupt.
##
## The cost is equally honest: a chapter whose completion gate is a fact the player made
## true BEFORE the chapter opened reads done the instant it opens. That is the correct
## reading of "the world already remembers it", and it is why there is no `started` stamp.
##
## ## Gates are DATA in the one shared requirement language (ADR 0065/0066)
##
## Every requirement on a chapter is read by `StoryGate`, which contributes exactly ONE
## verb (`quest_done`) and delegates fate verbs to `DestinyApi.gate` and fact reads to
## `WorldFact`. A new gated chapter is a content edit, never a code change.
##
## ## Unmet gates HIDE content; they never block play (BL-0068)
##
## "The player can ignore the main story and it coexists with the sandbox" is a rule about
## what a false gate does. Here it means *this chapter is not on the board*, never *you may
## not do the thing*. Nothing in this module refuses a verb, spends a resource, or withholds
## a system because a chapter is unmet. A story that locked the world behind chapter three
## would not be a story, it would be a wall, and `optional` exists so the data says which
## one it is.
##
## ## This module never writes the ledger (ADR 0113) and never pays (DEF-0107)
##
## `WorldFact.record` has no caller here. ADR 0114 names one director for beats, and a
## second writer of narrative facts is how "the player did X" gets two homes. And no
## chapter carries rewards: the quest a chapter completes already pays through
## `QuestGrants`, so a chapter grant would be a second payer for one action.


## Every authored story id, canonically ordered. `""`-id stories are refused by the
## catalog, so every id here resolves through `definition`.
static func story_ids() -> Array[StringName]:
	return StoryCatalog.instance().story_ids()


## One story, or null. Null rather than a guess: an unknown story id is a content bug and
## inventing a ladder would hide it behind a story that reports itself finished.
static func definition(story_id: StringName) -> StoryDef:
	return StoryCatalog.instance().definition(story_id)


## The chapter `actor` is standing on, as `{story_id, chapter_id, done, open, blocked_by}`.
##
## ## The walk, and why it terminates
##
## The ladder is walked from `entry_chapter` through `next` links, capped at
## `StoryDef.MAX_CHAPTERS`, and a chapter already visited is never entered twice. So the
## bound is the authored chapter count and a cycle in the authored gates is a reported
## content bug rather than a hang. `while` on a container it is growing is the shape the
## arch gate fails, and this is not it: the visited set only ever grows toward a fixed cap
## and the loop stops when it hits it.
##
## `blocked_by` is the unmet rows of the gate that would have opened the NEXT chapter, so a
## panel can say what the story is waiting on without re-deriving the grammar — the same
## reason `QuestApi.gates_for` exists.
static func progress(actor: Actor, story_id: StringName) -> Dictionary:
	var def := StoryCatalog.instance().definition(story_id)
	if def == null:
		return {
			"known": false,
			"story_id": String(story_id),
			"chapter_id": "",
			"done": false,
			"open": false,
			"blocked_by": []
		}
	var current := def.chapter(def.entry_chapter)
	if current == null:
		return {
			"known": true,
			"story_id": String(def.id),
			"chapter_id": "",
			"done": false,
			"open": false,
			"blocked_by": []
		}
	var visited: Dictionary = {}
	var blocked: Array[Dictionary] = []
	# Bounded by the authored cap, and a repeat is a content bug we report by stopping,
	# not a loop we ride.
	for guard in StoryDef.MAX_CHAPTERS:
		var key := String(current.chapter_id)
		if visited.has(key):
			blocked.append(
				{
					"kind": "cycle",
					"id": key,
					"required": true,
					"actual": false,
					"label": "chapter '%s' is reached twice" % key
				}
			)
			break
		visited[key] = true
		var next := _next_of(def, current)
		if next == null:
			break
		var verdict := StoryGate.evaluate(actor, next.requires)
		if not bool(verdict.get("ok", false)):
			# Copied row by row, not cast: `as Array[Dictionary]` on the plain Array a
			# verdict literal carries returns NULL in Godot 4, so a cast would silently
			# empty the very list this is here to publish.
			blocked.clear()
			for entry in verdict.get("unmet", []) as Array:
				if entry is Dictionary:
					blocked.append(entry as Dictionary)
			break
		current = next
	var is_done := (
		current.is_ending and bool(StoryGate.evaluate(actor, current.completion).get("ok", false))
	)
	return {
		"known": true,
		"story_id": String(def.id),
		"chapter_id": String(current.chapter_id),
		"done": is_done,
		"open": not is_done,
		"blocked_by": blocked,
		"chapters_seen": visited.size(),
	}


## Whether `actor` has taken `story_id` to its ending chapter. Derived, never stored, so a
## story cannot claim to be finished on evidence it does not own.
static func is_finished(actor: Actor, story_id: StringName) -> bool:
	return bool(progress(actor, story_id).get("done", false))


## Every chapter now open for `actor` across every story, as primitive rows
## `{story_id, chapter_id, dialogue_id, display_name}`.
##
## A chapter is OPEN when its `requires` passes and its `completion` does not. That is the
## only definition this module uses, and `offered` is what a codex or a notification reads.
## An `optional` story's chapters appear here and nowhere else may they be pushed.
static func offered(actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for story_id in StoryCatalog.instance().story_ids():
		var def := StoryCatalog.instance().definition(story_id)
		if def == null:
			continue
		for row in def.chapters:
			if row == null:
				continue
			if not bool(StoryGate.evaluate(actor, row.requires).get("ok", false)):
				continue
			if bool(StoryGate.evaluate(actor, row.completion).get("ok", false)):
				continue
			(
				out
				. append(
					{
						"story_id": String(def.id),
						"chapter_id": String(row.chapter_id),
						"dialogue_id": String(row.dialogue_id),
						"display_name": row.display_name,
					}
				)
			)
	return out


## The story ids whose ladder names `quest_id` anywhere, in catalog order.
##
## This is the subscription filter and the reason the module is cheap to wire: a quest
## completing outside every authored story answers `[]` here, so the caller reaches no
## gate at all. It is a walk over authored content, bounded by the authored chapter count.
static func stories_for_quest(quest_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for story_id in StoryCatalog.instance().story_ids():
		var def := StoryCatalog.instance().definition(story_id)
		if def != null and def.involves_quest(quest_id):
			out.append(story_id)
	return out


## Primitives-only read model for a codex screen. No `Resource` and no `Actor` crosses
## this boundary, the ADR 0114 payload rule.
static func summary(actor: Actor) -> Dictionary:
	var stories: Array[Dictionary] = []
	for story_id in StoryCatalog.instance().story_ids():
		var def := StoryCatalog.instance().definition(story_id)
		if def == null:
			continue
		(
			stories
			. append(
				{
					"id": String(def.id),
					"display_name": def.display_name,
					"optional": def.optional,
					"chapter_count": def.chapter_count(),
					"progress": progress(actor, story_id),
				}
			)
		)
	return {
		"has_actor": actor != null,
		"stories": stories,
		"problems": StoryCatalog.instance().problems()
	}


## Every authoring complaint in the tree, as stable strings. `tools data audit` and a
## content test read this; a non-empty list means shipped content that cannot be played.
static func problems() -> Array[String]:
	return StoryCatalog.instance().problems()


# --- Internals -------------------------------------------------------------


## The chapter that follows `row` in authored order, or null at the end of the ladder.
##
## Order is the authored array, NOT a gate: a chapter's `requires` decides whether the
## player may stand on it, and the array decides what comes next. Splitting those two is
## what lets an author write a branch (two chapters gated on the same predecessor) without
## the walk needing to know a branch happened.
static func _next_of(def: StoryDef, row: StoryChapterDef) -> StoryChapterDef:
	var index := -1
	for i in def.chapters.size():
		if def.chapters[i] == row:
			index = i
			break
	if index < 0 or index + 1 >= def.chapters.size():
		return null
	return def.chapters[index + 1]
