class_name NpcPresence
extends RefCounted

## Where a tracked npc is in the world right now (ADR 0077).
##
## **Off-stage is a ledger entry, not a live actor.** A world with 300 authored
## inhabitants and 4 met costs 4 entries and no more: `KNOWN` means "the player has met
## them and knows what stage they were left at", with their last payload stored as
## primitives. No `Actor` is constructed until they are actually needed (ADR 0074).

## Never encountered. Absent from the roster entirely.
const UNKNOWN := &"unknown"
## Met, not currently spawned. The roster entry carries the stage and last payload.
const KNOWN := &"known"
## Live in a room right now; the roster holds the actual `Actor`.
const PRESENT := &"present"
## Story-complete or dead. Never spawns again, and the entry stays as the trace.
const RETIRED := &"retired"

const ALL: Array[StringName] = [UNKNOWN, KNOWN, PRESENT, RETIRED]


static func is_known(presence: StringName) -> bool:
	return ALL.has(presence)


static func normalize(presence: StringName) -> StringName:
	return presence if ALL.has(presence) else UNKNOWN


static func label(presence: StringName) -> String:
	match presence:
		KNOWN:
			return L.t("LOC_NPC_28D7146C1D")
		PRESENT:
			return L.t("LOC_NPC_4E9F7A31EE")
		RETIRED:
			return L.t("LOC_NPC_ELDER_WEI_DISPLAY_NAME_3")
	return L.t("LOC_NPC_BC7819B34F")
