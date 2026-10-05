class_name ConflictWorldLedger
extends RefCounted

## A shared, in-memory standoff ledger (ADR 0101, ADR 0245).
##
## ## Why a standoff cannot live in one actor
##
## A standoff has three parties and no owner: the holder, the challenger, and the caller that
## runs the verdict. Kept in one actor's `module_data` it would be copied per actor, so a verdict
## could resolve against a row the other side cannot see — and the whole defeat of the defect is
## that it is silent. ADR 0101 records it twice already: a rival reading held ground as vacant and
## overwriting the holder outright, which is the conquest ADR 0085 forbids outright, and every
## single-actor test passing while it happens.
##
## ## Not a file-backed store
##
## In-memory, and the shape a persistent store copies. A save format for the world is its own
## decision and needs its own ADR rather than arriving inside a feature.

var _ledger: Dictionary = {}


func _init() -> void:
	_ledger = ConflictState.empty()


## The current ledger. Returns a normalized copy so a caller cannot mutate the world by holding
## on to what it was handed.
##
## Named `read_ledger` rather than `load` because `load` is a global GDScript builtin and a
## method with that name on a `RefCounted` resolves to the builtin instead — a compile error
## rather than a loud failure, so it stays invisible until someone runs the suite (ADR 0101).
func read_ledger() -> Dictionary:
	return ConflictState.normalize(_ledger)


## Replace the ledger. Normalized on the way in, so a caller cannot inject a malformed world by
## writing a field the module does not know about.
func write_ledger(ledger: Dictionary) -> void:
	_ledger = ConflictState.normalize(ledger)


## Whether anything has been written yet, so a caller can tell an empty world from an unwired
## store.
func is_empty() -> bool:
	return (read_ledger()["standoffs"] as Dictionary).is_empty()
