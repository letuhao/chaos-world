class_name SavePaths
extends RefCounted

## Where saves live on disk (ADR 0128).
##
## ## One visible slot, one invisible backup
##
## The player never sees a slot list because there is nothing to choose: the game autosaves on
## its own schedule and reads back the one slot it wrote. The backup exists for crash recovery
## only, and no shipped caller names it.
##
## ## Why the temp path lives beside the primary
##
## Not in a system temp directory: the rename that promotes it must be atomic, and a rename
## across volumes or filesystems is not. Same directory, so the promotion is a metadata
## operation the OS will not interrupt.
##
## ## `user://`, never an absolute path
##
## `user://` resolves per platform and per export. A hardcoded machine path would break every
## other developer's build and every exported one — the rule `AGENTS.md` states as "use
## `res://` paths, never OS-absolute paths".

const DIR := "user://save"
const PRIMARY := "user://save/primary.json"
const BACKUP := "user://save/primary.backup.json"
const TEMP := "user://save/primary.json.tmp"

## Named slots (ADR 0903). The roster is fixed: the legacy primary plus three
## named journeys. A fixed roster means no slot id ever comes from player
## text, so path traversal is impossible by construction rather than by
## validation. A fourth journey is a new ADR, not a constant edit.
const PRIMARY_SLOT := &"primary"
const SLOTS: Array[StringName] = [&"primary", &"first", &"second", &"third"]


## Whether `slot` names a slot. Anything else is refused by name wherever a
## slot enters, so a typo'd id reads as `unknown_slot` rather than a path.
static func is_slot(slot: StringName) -> bool:
	return SLOTS.has(slot)


## The three file paths a slot owns. Primary keeps its exact legacy paths so
## every save ever written still reads; named slots live beside it, each with
## its own backup and temp, so a failed write to one journey can never touch
## another. The temp file is never readable, in every slot.
static func for_slot(slot: StringName) -> Dictionary:
	if slot == &"" or slot == PRIMARY_SLOT:
		return {"primary": PRIMARY, "backup": BACKUP, "temp": TEMP}
	var stem := "user://save/slot_" + String(slot)
	return {
		"primary": stem + ".json",
		"backup": stem + ".backup.json",
		"temp": stem + ".json.tmp",
	}


## Whether `path` is a temp file. A temp file is NEVER a readable slot: it may be a partial
## write, and treating it as one is how a half-written save becomes a lost run. Every slot's
## temp ends in `.tmp`, so one suffix covers the primary and every named slot.
static func is_temp(path: String) -> bool:
	return path == TEMP or path.ends_with(".tmp")
