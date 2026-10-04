class_name SaveApi
extends RefCounted

## Public facade for the `save` module (ADR 0128). Other modules may reference ONLY this file
## (`api.gd`).
##
## ## The player chooses nothing
##
## There is no save button, no load button and no slot list. The game autosaves on a period
## boundary the player never sees. A backup exists on disk for crash recovery and **no shipped
## caller names it** — that is a design rule with a guard, not a missing feature, and the guard
## is what keeps it a rule.
##
## ## Why the envelope and not the actor payload
##
## `Actor.to_dict()` IS reached in production: `persist` below is called from the composition
## root's period autosave, so cultivation progress, the dantian, the sea and every module ledger
## ride out under `envelope.actor` whole, with no second item path, because `item_state`
## already rides inside it.
##
## ## The write half ships; the read half does not
##
## `SaveApi.restore()` has no caller anywhere in `res://src` outside this file, so nothing reads
## the slot back at boot and the composition root builds a fresh actor instead. Cultivation
## progress is written every period and never observed on the next session (BL-0061).
##
## Do not read that absence as the design. The envelope is built to round-trip — this docblock
## previously claimed `Actor.to_dict()` had no production caller at all, which stopped being
## true once `persist` was wired, and that stale claim is what DEF-0059 was filed against.
##
## The soul and the world ledgers ride BESIDE the actor, under `envelope.world` — not inside
## it. A soul outlives its body (ADR 0127), so anything stored on the actor dies with it.

## The world store a caller installs into `holdings`, `market`, `custody` and `soul`. Built per
## operation so a store can only ever hold the slot it was made for.
const WORLD_KEYS := SaveSlot.WORLD_KEYS

## The slot every shipped caller names. The backup exists in `SaveStore` and is reachable only
## by its own private recovery path.
const SLOT := &"primary"

## The composition root's clock. Installed rather than created here so the ONE existing frame
## driver schedules saves and this module adds no `_process` of its own — a fourth driver fails
## `tests/app/test_status_clock.gd`.
static var clock: SaveClock = SaveClock.new()

## The stores the composition root installed, keyed by world name. NOT a static the world
## modules read directly: it exists so `publish_world` can reach each one, and an entry with no
## store is skipped rather than fabricated.
static var _stores: Dictionary = {}


## Write the current world as the next generation of the live slot.
##
## Snapshots every ledger FIRST, and aborts before touching disk if any read fails — a partial
## world must never become a file. Returns `{ok, reason, generation}` where `reason` names a
## failure rather than being empty, because a swallowed failure here loses an unbounded span of
## play invisibly.
static func persist(actor: Actor, difficulty_id: String = "") -> Dictionary:
	var world := _snapshot_world()
	var payload := actor.to_dict() if actor != null else {}
	var generation := SaveStore.generation() + 1
	var envelope := SaveSlot.build(payload, world, difficulty_id, generation)
	var outcome := SaveStore.persist(envelope, generation)
	if bool(outcome["ok"]):
		clock.record_saved()
	return outcome


## Read the live slot, falling back to the backup when the primary is unreadable.
##
## `{ok, envelope, recovered, reason}`. **The recovery is silent**: the player has no backup
## choice to make, so a modal reporting an error they cannot act on would be noise. The caller
## still learns — `recovered` is true and `reason` is `primary_unreadable` — and the condition
## is asserted in a test rather than shown in a screen.
static func restore() -> Dictionary:
	return SaveStore.restore()


## Whether a readable live save exists. What a new-game flow asks; there is nothing to choose,
## so there is no slot list to ask for.
static func exists() -> bool:
	return SaveStore.exists()


## Install `store` — any object with `read_ledger()` / `write_ledger(ledger)` — into `key`.
## `app/` calls this for each world module so `holdings`, `market`, `custody` and the soul all
## read one world rather than four copies of it.
##
## The store is written into the facade rather than passed per call, because the modules hold
## theirs in a `static var` and a caller that re-reads the store without reinstalling it gets
## the PREVIOUS slot's world.
static func install_store(key: String, store: RefCounted) -> Dictionary:
	if not WORLD_KEYS.has(key):
		return {"ok": false, "reason": "unknown_world_key", "key": key}
	if store == null or not store.has_method(&"read_ledger"):
		return {"ok": false, "reason": "not_a_store", "key": key}
	_stores[key] = store
	return {"ok": true, "reason": "", "key": key}


## The store registered for `key`, or `null` when none is.
##
## **Published so the composition root's economy boot can install THE SAME instance into a
## module facade** (ADR 0165). One envelope key with two `WorldLedgerStore` instances is not a
## second world — both re-read the file — but it is two objects that can drift, and the boot has
## to decide between a save-backed store and the in-memory seam with ONE rule. Asking here is
## that rule: a key the save owns is installed save-backed, and every other key gets the seam,
## which is why a suite that installs the in-memory ledgers keeps them.
static func store_for(key: String) -> RefCounted:
	return _stores.get(key)


## Restore the persisted world into the installed stores. Called BEFORE any `Actor.from_dict`,
## so a body built from a restored save finds a world already in place rather than an empty one.
##
## A key with no store installed is skipped and named, not invented: writing a world into
## nothing is how a ledger is believed saved and is not.
static func publish_world() -> Dictionary:
	var envelope := _live_envelope()
	if envelope.is_empty():
		return {"ok": false, "reason": "no_readable_save", "restored": []}
	var world := envelope.get("world", {}) as Dictionary
	var restored: Array[String] = []
	for key in WORLD_KEYS:
		var store = _stores.get(key)
		if store == null:
			continue
		var ledger = world.get(key)
		store.call(&"write_ledger", ledger if (ledger is Dictionary) else {})
		restored.append(key)
	return {"ok": true, "reason": "", "restored": restored}


## The persisted world, exactly as the save carries it, so a caller never reaches into a
## module's internals to see what was restored.
static func world_state() -> Dictionary:
	var envelope := _live_envelope()
	if envelope.is_empty():
		return {}
	return (envelope.get("world", {}) as Dictionary).duplicate(true)


## The condition of the save, as primitives, for a status line or a probe:
## `{primary_present, backup_present, generation, envelope_version, recovered}`.
##
## A status line is the whole of the player-facing surface. It reports that saving happened and
## never asks permission — the requirement is that the player does not decide when saving
## happens, and a button that offers them the choice would break it.
static func summary() -> Dictionary:
	var envelope := _live_envelope()
	return {
		"primary_present": SaveStore.exists(),
		# Reported so a probe can assert the backup exists and no shipped caller can read it.
		"backup_present": FileAccess.file_exists(SavePaths.BACKUP),
		"generation": int(envelope.get("generation", 0)),
		"envelope_version": int(envelope.get("envelope_version", 0)),
		"difficulty": String(envelope.get("difficulty", "")),
		"saves": clock.saves(),
	}


## Forget the schedule. A new game starts at zero periods, so it does not inherit a previous
## run's countdown.
static func reset_clock() -> void:
	clock.reset()


# --- Internals -------------------------------------------------------------


## Read every installed store into one world dictionary. The soul is read even when the actor
## is null — a save taken at the moment of death must still carry it, which is the whole reason
## the soul is not on the actor.
static func _snapshot_world() -> Dictionary:
	var world := {}
	for key in WORLD_KEYS:
		var store = _stores.get(key)
		if store == null:
			world[key] = {}
			continue
		world[key] = store.call(&"read_ledger")
	return world


## The live envelope, or `{}` when there is no readable save.
static func _live_envelope() -> Dictionary:
	var restored := SaveStore.restore()
	return restored.get("envelope", {}) as Dictionary
