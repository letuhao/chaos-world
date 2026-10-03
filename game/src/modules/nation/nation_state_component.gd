class_name NationStateComponent
extends RefCounted

## The `actor.components` slot holding the live nation ledger (ADR 0083).
##
## `Actor.set_component` takes a `RefCounted`, and the ledger itself is a plain
## `Dictionary` — core persists module data verbatim and never names a nation
## type, so the dictionary stays the source of truth and this is only the live
## mirror a caller reads. `SocialState` and `DestinyState` are the same idea in
## the other direction; the difference here is that the payload is normalized on
## every write, so the mirror is always a value `NationState.normalize` would
## produce rather than a half-applied claim.

## The ledger exactly as it persists.
var ledger: Dictionary = {}


func _init(p_ledger: Dictionary = {}) -> void:
	ledger = p_ledger


## The mirror's ledger, re-normalized on the way out so a component written by an
## older build can never be read as more authoritative than the payload.
func read() -> Dictionary:
	return ledger


func write(p_ledger: Dictionary) -> void:
	ledger = p_ledger
