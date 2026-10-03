class_name NpcTier
extends RefCounted

## The authored tier of an npc (ADR 0077). A tier is DATA: it is compared in `normalize`
## and read by content, never branched on inside a mechanism (ADR 0067).
##
## **Tracked or not is the one question the whole module exists to answer.** A tracked
## npc remembers; an untracked one spawns and is gone. Every other tier distinction is
## content flavour on top of that binary.

## TRACKED. Persists across visits, holds a roster entry and an authored stage.
const MAJOR := &"major"
## TRACKED. As major, and readable by story content that wants a cast member by name.
const STORY := &"story"
## UNTRACKED. A named face in a room. Recurs, but nothing about the relationship persists.
const MINOR := &"minor"
## UNTRACKED. Pure population. May be a different individual next visit.
const TRANSIENT := &"transient"

const ALL: Array[StringName] = [MAJOR, STORY, MINOR, TRANSIENT]
## Validation set only. A mechanism reads the boolean a def author set, never this array,
## so adding a tier can never silently change which existing npcs are remembered.
const TRACKED: Array[StringName] = [MAJOR, STORY]

## What an author gets for free: a named face that neither remembers nor is remembered.
const DEFAULT := MINOR


## The tiers that persist. A validation and documentation aid, never a runtime branch.
static func is_tracked(tier: StringName) -> bool:
	return TRACKED.has(tier)


static func is_known(tier: StringName) -> bool:
	return ALL.has(tier)


static func normalize(tier: StringName) -> StringName:
	return tier if ALL.has(tier) else DEFAULT


static func label(tier: StringName) -> String:
	match tier:
		MAJOR:
			return "Major"
		STORY:
			return "Story"
		MINOR:
			return "Minor"
		TRANSIENT:
			return "Transient"
	return "Minor"
