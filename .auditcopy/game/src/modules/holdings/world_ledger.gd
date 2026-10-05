class_name WorldLedger
extends RefCounted

## A shared, in-memory holdings ledger (ADR 0097).
##
## ## Why this exists at all
##
## A resource node's holder is a WORLD fact, but this repo has no world store: `LootState`
## is `actor.module_data` and dies with the actor, and `DomainApi` erases its map on leave
## keeping only `discovered`. Keeping the holder per actor is not a simplification — it is a
## correctness bug, because two actors then each hold their own copy and a rival reads a
## held node as vacant and overwrites the holder outright. That is exactly the silent
## conquest ADR 0085 forbids.
##
## So the ledger is shared, and this is the seam. `app/` installs a persistent
## implementation with the same two methods; a test installs this one. It is deliberately
## the whole of the fix rather than a file-backed store, because a save format for a world
## is its own decision and this repo's rule is that a new persistence path needs its own
## ADR rather than arriving inside a feature.

var _ledger: Dictionary = {}


func _init() -> void:
	_ledger = HoldingsState.empty()


## The current ledger. Returns a normalized copy so a caller cannot mutate the world by
## holding on to what it was handed.
##
## Named `read_ledger` rather than `load` because `load` is a global GDScript builtin, and a
## method with that name on a `RefCounted` resolves to the builtin instead — which is a
## compile error rather than a loud failure, so it is invisible until someone runs it.
func read_ledger() -> Dictionary:
	return HoldingsState.normalize(_ledger)


## Replace the ledger. Normalized on the way in, so a caller cannot inject a malformed
## world by writing a field the module does not know about.
func write_ledger(ledger: Dictionary) -> void:
	_ledger = HoldingsState.normalize(ledger)


## Whether anything has been written yet, so a caller can tell an empty world from an
## unwired store.
func is_empty() -> bool:
	return (read_ledger()["nodes"] as Dictionary).is_empty()
