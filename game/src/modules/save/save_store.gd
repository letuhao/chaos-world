class_name SaveStore
extends RefCounted

## The file-backed world store, and the byte-level writer (ADR 0128).
##
## ## What this closes
##
## ADR 0101 settled the SHAPE for a world object — `set_store` with `read_ledger()` and
## `write_ledger(ledger)` — and left the persistent implementation owed (DEF-0147). Four
## modules now want one: `holdings`, `market`, `custody` and the soul. Writing a fourth
## in-memory ledger would have been the wrong move; this is the one real store they share.
##
## ## Per slot, never process-wide
##
## `holdings`, `market` and `custody` all keep their store in a `static var`, so a second save
## that failed to reinstall would read the FIRST save's holdings and every single-slot test
## would pass. `_world` is an instance member and `persist`/`restore` construct a fresh store
## per operation, so a store can only ever hold the slot it was made for.
##
## ## The write is a rename, not a write
##
## **After any failed write exactly one readable file exists, and it is a complete generation.**
## Every ledger is read first and a failure aborts before touching disk; the previous primary
## becomes the backup; the new envelope goes to a temp file; only the rename promotes it. A
## crash mid-write therefore costs the current save, never the previous one. `ItemStateStore`
## opens and writes in place, so a crash there truncates the only save — this exists because
## that was not good enough.

var _world: Dictionary = {}


func _init() -> void:
	_world = {}


## The current ledger, for whichever module asked. This is the whole reason the class exists:
## ADR 0101's contract, satisfied by the file rather than by a dictionary.
##
## Named `read_ledger` rather than `load` because `load` is a global GDScript builtin, and a
## method with that name on a `RefCounted` resolves to the builtin — a compile error rather
## than a loud failure, so it is invisible until someone runs the suite.
func read_ledger() -> Dictionary:
	return _world.duplicate(true)


## Replace the world. Every direction normalizes, so a caller cannot inject a malformed ledger
## by writing a key this module does not know about.
func write_ledger(ledger: Dictionary) -> void:
	_world = ledger.duplicate(true)


## Whether this store has ever held anything, so a caller can tell "no world yet" from an
## unwired store.
func is_empty() -> bool:
	return _world.is_empty()


## Every world key this store carries, so the save writer can snapshot them all.
func world() -> Dictionary:
	return _world.duplicate(true)


## Replace the whole world at once. Used on restore, where every ledger arrives together and
## writing them one at a time would leave a half-restored world visible in between.
func replace_world(world: Dictionary) -> void:
	_world = world.duplicate(true)


# --- Disk -------------------------------------------------------------------


## Write `envelope` as the next generation of `slot`.
##
## Returns `{ok, reason, generation}` where a failure NAMES itself rather than returning an
## empty reason: a swallowed failure here means the player loses an unbounded span and never
## learns, which is the failure this return shape exists to prevent.
##
## `slot` defaults to the primary paths, so every existing caller keeps its behavior. Each
## slot rotates through its OWN files (ADR 0903): the previous primary of THAT slot becomes
## its backup, and a crash mid-write costs that slot's current save, never another journey.
static func persist(
	envelope: Dictionary, generation: int, slot: StringName = &"primary"
) -> Dictionary:
	var paths := SavePaths.for_slot(slot)
	var primary: String = paths["primary"]
	var backup: String = paths["backup"]
	var temp: String = paths["temp"]
	# 1. The directory first, because a write into a missing directory fails on some platforms
	# and succeeds silently losing the file on others.
	if not DirAccess.dir_exists_absolute(SavePaths.DIR):
		var made := DirAccess.make_dir_recursive_absolute(SavePaths.DIR)
		if made != OK and not DirAccess.dir_exists_absolute(SavePaths.DIR):
			return {"ok": false, "reason": "no_directory", "generation": generation}
	# 2. Serialize BEFORE rotating. A file opened and left empty is a destroyed save, which is
	# strictly worse than a save one generation old.
	var text := JSON.stringify(envelope)
	if text.is_empty():
		return {"ok": false, "reason": "unserializable", "generation": generation}
	# 3. Rotate. The previous primary becomes the backup, and the OLD backup is dropped — one
	# deep, which is all the recovery path claims to be.
	if FileAccess.file_exists(primary):
		var rotated := DirAccess.rename_absolute(primary, backup)
		if rotated != OK:
			return {"ok": false, "reason": "rotate_failed", "generation": generation}
	# 4. Write the temp file, closed before the rename. `store_string` without a close leaves the
	# bytes in a buffer, and a rename over an unflushed file promotes an empty save.
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "no_temp", "generation": generation}
	file.store_string(text)
	file.flush()
	file.close()
	# 5. Promote. This is the only step that makes the new generation the live save.
	var promoted := DirAccess.rename_absolute(temp, primary)
	if promoted != OK:
		# No retry, and the temp file is left where it is: a half-recovered write is how one bad
		# write becomes two. The backup still holds a complete generation, and `restore` reads it.
		return {"ok": false, "reason": "rename_failed", "generation": generation}
	return {"ok": true, "reason": "", "generation": generation}


## The parsed envelope of `slot` with backup fallback, or `{}` when neither reads.
## The temp file is never read, in any slot.
static func read_envelope(slot: StringName = &"primary") -> Dictionary:
	var paths := SavePaths.for_slot(slot)
	var primary := _read(String(paths["primary"]))
	if not primary.is_empty():
		return primary
	return _read(String(paths["backup"]))


## Read the live slot, falling back to the backup when the primary cannot be read.
##
## **The recovery is silent by design.** The player has no backup choice to make, so a dialog
## reporting an error they cannot act on would be noise; `item_state_store.gd` sets the same
## precedent, that an unreadable file reads as recoverable rather than as an error. The caller
## still learns: `recovered` is true and `reason` names what happened.
static func restore(slot: StringName = &"primary") -> Dictionary:
	var envelope := read_envelope(slot)
	if envelope.is_empty():
		return {
			"ok": false,
			"envelope": {},
			"recovered": false,
			"reason": "no_readable_save",
		}
	var paths := SavePaths.for_slot(slot)
	if _read(String(paths["primary"])).is_empty():
		return {
			"ok": true,
			"envelope": envelope,
			"recovered": true,
			"reason": "primary_unreadable",
		}
	return {"ok": true, "envelope": envelope, "recovered": false, "reason": ""}


## Whether `slot` holds a readable save.
static func exists(slot: StringName = &"primary") -> bool:
	return not read_envelope(slot).is_empty()


## The envelope version currently on disk, or 0 when there is none.
static func envelope_version(slot: StringName = &"primary") -> int:
	return int(read_envelope(slot).get("envelope_version", 0))


## The generation currently on disk, or 0.
static func generation(slot: StringName = &"primary") -> int:
	return int(read_envelope(slot).get("generation", 0))


## Forget a slot: delete its primary, backup and temp files. Returns whether
## anything was removed, so erasing an empty slot reads as a no-op rather
## than as a failure.
static func erase(slot: StringName) -> Dictionary:
	var paths := SavePaths.for_slot(slot)
	var removed := false
	for key in ["primary", "backup", "temp"]:
		var path := String(paths[key])
		if FileAccess.file_exists(path):
			if DirAccess.remove_absolute(path) != OK:
				return {"ok": false, "reason": "erase_failed", "slot": String(slot)}
			removed = true
	return {"ok": true, "reason": "", "slot": String(slot), "erased": removed}


## The parsed envelope at `path`, or `{}` when it is missing or unreadable.
##
## The temp file is never read: it may be a partial write, and a partial write promoted by a
## crash is exactly the state this whole design exists to prevent.
static func _read(path: String) -> Dictionary:
	if SavePaths.is_temp(path):
		return {}
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not SaveSlot.is_readable(parsed):
		return {}
	return parsed as Dictionary
