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


## Whether `path` is the temp file. A temp file is NEVER a readable slot: it may be a partial
## write, and treating it as one is how a half-written save becomes a lost run.
static func is_temp(path: String) -> bool:
	return path == TEMP
