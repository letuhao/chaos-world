class_name MarketWorldLedger
extends RefCounted

## A shared, in-memory market ledger (ADR 0101).
##
## ## Why the floor cannot live in one actor
##
## A dropped item exists **in the location**. If the floor is kept in the dropper's
## `module_data`, the taker reads only their own copy and `take` refuses with
## `no_such_drop` for anything anyone else left — which is not a missing feature, it is the
## floor being invisible. The same defect ADR 0101 records for a resource node's holder,
## found the same way: a single-actor test passes and the multi-actor case silently fails.
##
## ## Not a file-backed store
##
## This is in-memory and is the shape a persistent store copies. A save format for the world
## is its own decision and needs its own ADR rather than arriving inside a feature.

var _ledger: Dictionary = {}


func _init() -> void:
	_ledger = MarketState.empty()


## Named `read_ledger`/`write_ledger`, never `load`/`save`: those are global GDScript
## builtins, and a `RefCounted` method of that name resolves to the builtin — a compile error
## rather than a loud failure.
func read_ledger() -> Dictionary:
	return MarketState.normalize(_ledger)


## Normalized on the way in, so a caller cannot inject a malformed world.
func write_ledger(ledger: Dictionary) -> void:
	_ledger = MarketState.normalize(ledger)


func is_empty() -> bool:
	return (read_ledger()["floor"] as Dictionary).is_empty()
