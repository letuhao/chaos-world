class_name SaveMigrate
extends RefCounted

## Every migration step the envelope owns, and the one rule they all follow
## (ADR 0037's precedent, extended to the world slot).
##
## ## Why a `save/` migration and not a `core/` one
##
## `Actor._restore_versioned` migrates the ACTOR payload, and it is the only thing that
## does: a dictionary literal cannot express "this key may be absent", so the shape of
## "old save, new slot" is decided where the envelope is assembled. `core/` may not name
## `modules/save`, so the direction is one-way and the migration cannot be a cycle.
##
## ## Every step is ADDITIVE and TOTAL
##
## A step never removes a key it does not understand, never rewrites a field it does not
## own, and never refuses an envelope it can read. The three properties that makes the
## migration story hold in BOTH directions:
##
## 1. **An old save loads.** A save written before the world polity slot existed has no
##    `polity` key, and reads as an empty ledger — which is the truth: that save never had
##    a polity. It is NOT given `{}` stamped at the current version, which would assert a
##    world it never had.
## 2. **A new save loads on the old path.** The envelope gains ONE key inside `world`,
##    which `SaveSlot.build` already reconstructs field by field — a build from before
##    this change reads only the keys it knows and writes them back, so the `polity` slot
##    is DROPPED rather than corrupted. Nothing else about the envelope changed, and
##    `envelope_version` did NOT move: ADR 0128 pins the two ladders independent, and an
##    envelope key appearing is not an envelope change (ADR 0165 says so for the economy
##    keys, and this is the same shape).
## 3. **A FUTURE ledger version is refused by name**, never read. Reading a newer ledger
##    and writing it back on the next autosave is how a newer build's world is erased by
##    an older one. `WorldLedgerStore` owns that refusal; this file owns the one thing it
##    cannot — the save's own claim about which version wrote it.

## The reason an envelope was refused. Kept as constants rather than inline strings so a
## caller compares against a name rather than a spelling.
const R_NO_READABLE_SAVE := "no_readable_save"
const R_FUTURE_ACTOR_SCHEMA := "future_actor_schema"


## The envelope this build can work with, or `{}` when it must not touch it.
##
## ## The actor version gate is EXPLICIT and is the whole of "version-gated"
##
## A payload stamped with an `Actor.SCHEMA_VERSION` this build does not know is refused
## BY NAME rather than half-read: the newer build may have moved a field this one drops,
## so accepting it and writing it back is how a newer run's save is erased by an older
## build — the identical argument `WorldLedgerStore.REASON_FUTURE_SCHEMA` makes for a
## ledger, and the reason ADR 0165 refuses a future ledger rather than normalizing it.
##
## An OLDER actor version is **accepted**: that is the migration path, and
## `Actor._restore_versioned` is what dispatches on it. This file never rewrites one,
## because a migration is a guess about a payload this module did not author — `SaveSlot`
## states that rule and it is why the ladder lives in `core/actor.gd` and not here.
static func prepare(envelope: Dictionary) -> Dictionary:
	if envelope.is_empty():
		return {}
	var actor_payload = envelope.get("actor", {})
	var stamped := (
		int((actor_payload as Dictionary).get("version", 0)) if (actor_payload is Dictionary) else 0
	)
	if stamped > Actor.SCHEMA_VERSION:
		return {}
	var world = envelope.get("world", {}) if (envelope.get("world", {}) is Dictionary) else {}
	# The world is normalized here rather than trusted, so a save whose `polity` slot
	# arrived malformed cannot reach `publish_world` and be written back whole. An ABSENT
	# key is left ABSENT rather than filled, for the reason in the class docblock: a
	# fabricated skeleton is how "no world yet" becomes "a world that started empty and
	# lost everything in it".
	var carried = world.get(WorldPolityLedger.WORLD_KEY)
	var safe_world := (world as Dictionary).duplicate(true)
	if carried is Dictionary and not (carried as Dictionary).is_empty():
		safe_world[WorldPolityLedger.WORLD_KEY] = WorldPolityLedger.normalize_payload(
			carried as Dictionary
		)
	var out := (envelope as Dictionary).duplicate(true)
	out["world"] = safe_world
	return out


## Why [method prepare] answered `{}`, so a caller can tell "there was nothing to
## migrate" from "there was something this build may not touch". `""` means the envelope
## was migrated, or that none was offered.
static func refusal(envelope: Dictionary) -> String:
	if envelope.is_empty():
		return R_NO_READABLE_SAVE
	var actor_payload = envelope.get("actor", {})
	var stamped := (
		int((actor_payload as Dictionary).get("version", 0)) if (actor_payload is Dictionary) else 0
	)
	return R_FUTURE_ACTOR_SCHEMA if stamped > Actor.SCHEMA_VERSION else ""
