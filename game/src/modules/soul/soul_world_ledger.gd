class_name SoulWorldLedger
extends RefCounted

## A shared, in-memory soul ledger (ADR 0127).
##
## ## Why this exists at all
##
## A soul outlives its actor, so storing it in `actor.module_data` is not a simplification but
## a correctness bug: the ledger would die with the exact body it exists to outlive, and the
## failure is silent because every single-actor test still passes. ADR 0101 named this shape
## for a world object and left the persistent implementation owed (DEF-0147, now closed by
## ADR 0128); this is that in-memory seam, and `app/` installs the file-backed store.
##
## ## Why it is in-memory
##
## Because it is the SEAM, not the answer. A test installs this one; the composition root
## installs the real store. The method names and the shape are identical either way, so a
## suite that swaps one for the other exercises the same call path.

var _ledger: Dictionary = {}


func _init() -> void:
	_ledger = SoulState.empty()


## The current ledger. Returns a normalized copy so a caller cannot mutate the world by
## holding on to what it was handed.
##
## Named `read_ledger` rather than `load` because `load` is a global GDScript builtin, and a
## method with that name on a `RefCounted` resolves to the builtin instead — which is a
## compile error rather than a loud failure, so it is invisible until someone runs it.
func read_ledger() -> Dictionary:
	return SoulState.normalize(_ledger)


## Replace the ledger. Normalized on the way in, so a caller cannot inject a malformed soul
## by writing a field the module does not know about.
func write_ledger(ledger: Dictionary) -> void:
	_ledger = SoulState.normalize(ledger)


## Whether anything has been written yet, so a caller can tell "no soul yet" from an
## unwired store. The distinction matters: the first is a new game and the second is a
## wiring fault, and they lead to different answers.
func is_empty() -> bool:
	return (
		(read_ledger().get("incarnation", 0) as int) == 0
		and (read_ledger().get("origins", []) as Array).is_empty()
	)
