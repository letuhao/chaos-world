class_name AnchorWorldLedger
extends RefCounted

## A shared, in-memory anchor ledger (ADR 0132).
##
## An anchor is a world fact: it stands in a place, it outlives the body that raised it, and a
## rival must see it. ADR 0101 settled this shape for a world object and left the persistent
## implementation owed; this is the in-memory seam and `app/` installs the save store.
##
## It is in-memory because it is the SEAM, not the answer. The method names and shape are
## identical to the real store, so a suite that swaps one for the other exercises the same path.

var _ledger: Dictionary = {}


func _init() -> void:
	_ledger = AnchorState.empty()


## The current ledger, normalized on the way out so a caller cannot mutate the world by holding
## on to what it was handed.
##
## Named `read_ledger` rather than `load` because `load` is a global GDScript builtin, and a
## method with that name on a `RefCounted` resolves to the builtin instead — a compile error
## rather than a loud failure, so it is invisible until someone runs it.
func read_ledger() -> Dictionary:
	return AnchorState.normalize(_ledger)


## Replace the ledger. Normalized on the way in, so a caller cannot inject a malformed world by
## writing a field this module does not know about.
func write_ledger(ledger: Dictionary) -> void:
	_ledger = AnchorState.normalize(ledger)


## Whether anything has been written yet, so a caller can tell "no anchors yet" from an
## unwired store. The distinction matters: the first is a new world and the second is a wiring
## fault, and they lead to different answers.
func is_empty() -> bool:
	return (read_ledger().get("raised", {}) as Dictionary).is_empty()
