class_name StatProvider
extends RefCounted

## Contract: a module contributes derived stats for an actor. Implementations must be
## pure (no scene tree, no mutation) and return {stat_id: float} (ADR 0002).


func contribute(_context: StatContext) -> Dictionary:
	return {}


## Whether a contribution for an id CORE itself computes is an ADDITION to core's
## bucketed value rather than a replacement baseline (ADR 0937).
##
## The re-emit family — a provider that shapes a core-owned stat by emitting a BONUS on
## top of it (`BodyProvider`'s attack/defense/move/poise) — returns true, and
## `ActorStats._ensure_providers` lands the modifier bucket on the bonus exactly once.
## The default false keeps the ADR 0026 shape: a provider value REPLACES the baseline
## for whatever id it emits, which is right for a path's own formula for an id core
## also seeds (the qi provider's absorption, the dantian's capacity). Treating those
## as additions double-counted them — the qi family measured +7 and +100 the moment
## the addition was universal.
func adds_to_core() -> bool:
	return false
