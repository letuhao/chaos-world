class_name WorldLedgerStore
extends RefCounted

## The persistent `set_store` implementation the economy ledgers run on (ADR 0165).
##
## ## What this closes
##
## ADR 0101 settled the SHAPE — `read_ledger()` / `write_ledger(ledger)` — and named the
## persistent store as its own debt; ADR 0128 built `SaveStore` for the soul and left the three
## economy ledgers on bare in-memory dictionaries. This is that store, and it is **not a fourth
## persistence mechanism**: it is a per-slot VIEW of the `SaveStore` envelope the game already
## writes, so a claim, a lot and a holder ride the same atomic save as the actor.
##
## ## The key is a CONSTRUCTOR ARGUMENT, and that is the whole independence argument
##
## `holdings`, `market` and `custody` each get their own instance carrying their own key. A
## store can only ever address the one slot it was made for, so writing a holdings ledger
## through the market store lands on the `holdings` key of the market store's world and never
## on the floor. ADR 0101 records the conflation as the silent, total failure it is — a
## `MarketState.normalize` reading a holdings ledger drops every lot — and it is prevented
## structurally here rather than by remembering which normalizer goes with which module.
##
## ## The store holds BYTES; the MODULE owns the shape
##
## There is deliberately **no normalizer in this file**. `WorldLedger` normalizes with
## `HoldingsState`, `MarketWorldLedger` with `MarketState` and `CustodyWorldLedger` with
## `CustodyState`, and a normalizer here would be a fourth answer to "what shape is this
## ledger". The store's whole job is the envelope: which key, which file, and whether what is
## on disk may be read at all.
##
## ## A refusal is a NAMED refusal, and it is remembered
##
## Two conditions stop the read and both are recorded rather than swallowed, because the
## failure this prevents is a world that silently starts EMPTY and loses every claim in it with
## no error anywhere: a ledger stamped with a `SCHEMA_VERSION` from a NEWER build, and a
## truncated or non-JSON file. `read_ledger` answers `{}` in both cases and `last_reason()` then
## names what happened, so a caller distinguishes "nothing is saved yet" from "something is on
## disk and this build may not touch it" — a distinction the whole silent-loss failure rests on.
##
## The reason a FUTURE version is refused rather than read is that reading it is destructive:
## the newer build may have moved a field this one drops, so accepting the ledger and writing it
## back on the next autosave is how a newer run's world is erased by an older build. An OLDER
## version is accepted and re-normalized by the module, which is the whole migration story.

## A ledger written by a build whose `SCHEMA_VERSION` is higher than the reading module's. The
## file is newer than the code, and accepting it would destroy the newer world on the next save.
const REASON_FUTURE_SCHEMA := "future_schema"
## The envelope exists but `SaveStore` could not parse it as a save this build may read — a
## truncated write, a non-JSON body, a foreign format marker.
const REASON_LEDGER_UNREADABLE := "ledger_unreadable"
## There is no readable save at all. Distinct from a refusal: nothing has been rejected.
const REASON_NO_SAVE := "no_readable_save"
## The key this store addresses is not one the envelope carries.
const REASON_UNKNOWN_KEY := "unknown_world_key"

## The one envelope key this view reads and writes. Fixed at construction, never a field a
## caller can repoint — a store that could be re-pointed is a store that can be pointed at
## another module's container.
var key: String = ""
## The `SCHEMA_VERSION` the reading module declares. A ledger stamped higher is refused.
var schema_version: int = 0
## What the last `read_ledger` or `write_ledger` decided, as one of the `REASON_*` constants or
## `""`. Set on every call so a caller that reads the ledger and sees nothing can still ask.
var _last_reason: String = ""


## A store addressing `key` in the shared envelope, reading ledgers authored at
## `schema_version`.
##
## A key the envelope does not carry, or a `schema_version` below 1, is refused by
## `read_ledger` rather than at construction: a store that is merely unused must not take the
## boot down, and a store that is USED with a bad key must say so.
func _init(world_key: String = "", module_schema_version: int = 0) -> void:
	key = String(world_key)
	schema_version = module_schema_version


## The ledger this slot carries, or `{}` when there is none to read. Never a partial world: a
## refusal answers empty AND records the reason, because a fabricated skeleton here is exactly
## the "starts empty and loses every claim" failure.
func read_ledger() -> Dictionary:
	_last_reason = ""
	return _resolve_ledger()


## The read, as one computed value rather than seven exits.
##
## Each refusal that used to `return {}` on its own line now records its reason and clears the
## ledger instead, and only the final line returns. Every branch still runs in the same order
## and `_read_envelope` is still read exactly once per call, so this changes the SHAPE of the
## function and nothing a caller can observe: the returned dictionary, `_last_reason`, and the
## single disk read the comment below is about.
func _resolve_ledger() -> Dictionary:
	var ledger: Dictionary = {}
	# The key is checked before the envelope is opened, exactly as it was: a store made for a
	# slot the envelope does not carry answers without touching the file at all.
	if not _key_is_known():
		_last_reason = REASON_UNKNOWN_KEY
		return {}
	# `_read_envelope` re-reads the file on EVERY call rather than caching. A store installed at
	# boot and read a minute later then sees what was actually written since, which is what makes
	# "claim, save, reload, the claim is still there" true without a reload dance — and it is the
	# same per-operation discipline `SaveStore`'s own docblock states for its `_world`.
	var envelope := _read_envelope()
	# An absent envelope and an unreadable one are two different worlds — a new game and a
	# damaged save — so both refusals are decided from the one `envelope` this call read.
	var absent := envelope.is_empty()
	var readable := bool(envelope.get("readable", false))
	if absent:
		_last_reason = REASON_NO_SAVE
	elif not readable:
		# A save that exists but cannot be read routes to the backup inside `restore`, so
		# reaching here with a refusal means NEITHER slot was readable — the worst case, and the
		# only one a player could not recover from by themselves.
		_last_reason = REASON_LEDGER_UNREADABLE
	if not absent and readable:
		var world = envelope.get("world", {})
		var carried = (world as Dictionary).get(key) if world is Dictionary else null
		if not (world is Dictionary):
			_last_reason = REASON_LEDGER_UNREADABLE
		elif not (carried is Dictionary):
			# A key absent from an otherwise readable envelope is a save from a build that
			# predates the module, not corruption: it reads as an empty ledger with NO refusal,
			# which is how every save written before ADR 0165 keeps loading instead of failing.
			if carried != null:
				_last_reason = REASON_LEDGER_UNREADABLE
		else:
			ledger = carried as Dictionary
	# An OLDER version is accepted here and re-normalized by the module's own `normalize`, which
	# is the migration: the ledger is folded onto the current shape on the way in and written
	# back at the current version on the next save. No version is rewritten in place.
	var future := int(ledger.get("version", 0)) > schema_version
	if future:
		_last_reason = REASON_FUTURE_SCHEMA
		ledger = {}
	return ledger


## Replace this slot's ledger, leaving every other key in the envelope alone.
##
## Refuses a future-version ledger the same way a read does rather than overwriting it: an older
## build that saved over a newer one would destroy the newer world's fields silently, which is the
## more expensive of the two errors. The refusal is reported by return value so a caller is not
## left believing a write happened.
func write_ledger(ledger: Dictionary) -> Dictionary:
	_last_reason = ""
	if not _key_is_known():
		_last_reason = REASON_UNKNOWN_KEY
		return {"ok": false, "reason": REASON_UNKNOWN_KEY, "key": key}
	if int(ledger.get("version", 0)) > schema_version:
		_last_reason = REASON_FUTURE_SCHEMA
		return {"ok": false, "reason": REASON_FUTURE_SCHEMA, "key": key}
	var envelope := _read_envelope()
	if not bool(envelope.get("readable", false)):
		# A write over an unreadable save is refused rather than allowed to replace a corrupted
		# file with an empty one — losing the whole world to preserve nothing is not a recovery.
		_last_reason = REASON_LEDGER_UNREADABLE if not envelope.is_empty() else REASON_NO_SAVE
		return {"ok": false, "reason": _last_reason, "key": key}
	var world = envelope.get("world", {})
	var safe_world := (world as Dictionary).duplicate(true) if world is Dictionary else {}
	safe_world[key] = ledger.duplicate(true)
	# `readable` and `unreadable` are THIS store's private markers, never part of the envelope:
	# `SaveSlot.build` rebuilds the envelope field by field, so they cannot leak onto disk even
	# though this dictionary carries them.
	var rewritten := envelope.duplicate(true)
	rewritten.erase(&"readable")
	rewritten["world"] = safe_world
	var outcome := _write_envelope(rewritten)
	_last_reason = String(outcome.get("reason", ""))
	return {
		"ok": bool(outcome.get("ok", false)),
		"reason": _last_reason,
		"key": key,
		"generation": int(outcome.get("generation", 0)),
	}


## Why the last read or write decided what it decided: `""`, or one of the `REASON_*`
## constants. **This is the observable half of a refusal** — `read_ledger` answers `{}` either
## way, so without it "no world yet" and "a world this build may not read" are one answer.
func last_reason() -> String:
	return _last_reason


## Whether this store has ever held anything, so a caller can tell an unwired store from a
## world with nothing in it. A REFUSED ledger is not "empty": it is exactly the case where the
## distinction matters, so it answers false and names itself through `last_reason()`.
func is_empty() -> bool:
	if _last_reason != "":
		return false
	return (read_ledger() as Dictionary).is_empty()


# --- Internals -------------------------------------------------------------


func _key_is_known() -> bool:
	return SaveSlot.WORLD_KEYS.has(key) and schema_version >= 1


## The live envelope plus a `readable` verdict, or `{}` when there is nothing to read at all.
## The extra key is what separates "absent" from "present and refused": `SaveStore.restore`
## reports both as `ok: false`, and collapsing them is how a corrupt file reads as a new game.
##
## **A file on disk that will not parse returns `{"unreadable": true}`, not `{}`.** `restore`
## cannot tell a corrupt primary from an empty directory — both are `ok: false` — and answering
## `{}` for the corrupt case would report a damaged save as a NEW GAME, which is the precise
## confusion this file exists to prevent. The existence check is what makes the two answers
## distinct, and it is why `ledger_unreadable` and `no_readable_save` are separate constants
## rather than one word used twice.
func _read_envelope() -> Dictionary:
	var present: bool = (
		FileAccess.file_exists(SavePaths.PRIMARY) or FileAccess.file_exists(SavePaths.BACKUP)
	)
	var restored := SaveStore.restore()
	var envelope = restored.get("envelope", {})
	if not (envelope is Dictionary) or (envelope as Dictionary).is_empty():
		return {"unreadable": true} if present else {}
	var out := (envelope as Dictionary).duplicate(true)
	out["readable"] = bool(restored.get("ok", false))
	return out


## Write `envelope` back through the same `SaveStore` writer the game saves with, so a ledger
## write and an autosave share one rotation, one backup and one temp-and-rename path. Handing
## this to `SaveStore.persist` is the whole reason this is not a fourth persistence mechanism.
func _write_envelope(envelope: Dictionary) -> Dictionary:
	var generation := int(envelope.get("generation", 0)) + 1
	envelope["generation"] = generation
	return SaveStore.persist(
		SaveSlot.build(
			envelope.get("actor", {}) as Dictionary,
			envelope.get("world", {}) as Dictionary,
			String(envelope.get("difficulty", "")),
			generation
		),
		generation
	)
