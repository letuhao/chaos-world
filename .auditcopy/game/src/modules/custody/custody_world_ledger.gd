class_name CustodyWorldLedger
extends RefCounted

## A shared, in-memory custody ledger (ADR 0101, ADR 0104).
##
## ## Why custody cannot live in one actor
##
## A claim is a WORLD fact. If it lives in the holder's `module_data`, the new holder reads
## only their own copy and `transfer` refuses `no_such_claim` for anything anyone else took —
## which is not a missing feature, it is custody being invisible. The same defect ADR 0101
## records for a resource node's holder and for the market floor, found the same way: a
## single-actor test passes and the multi-actor case silently fails.
##
## ## Not a file-backed store
##
## In-memory, and the shape a persistent store copies. A save format for the world is its own
## decision and needs its own ADR rather than arriving inside a feature.

var _ledger: Dictionary = {}


func _init() -> void:
	_ledger = CustodyState.empty()


## Named `read_ledger`/`write_ledger`, never `load`/`save`: those are global GDScript
## builtins, and a `RefCounted` method of that name resolves to the builtin — a compile error
## rather than a loud failure.
func read_ledger() -> Dictionary:
	return CustodyState.normalize(_ledger)


## Normalized on the way in, so a caller cannot inject a malformed world.
func write_ledger(ledger: Dictionary) -> void:
	_ledger = CustodyState.normalize(ledger)


func is_empty() -> bool:
	return (read_ledger()["claims"] as Dictionary).is_empty()
