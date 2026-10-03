class_name DestinyProjection
extends RefCounted

## Rebuilds every fate consequence onto an actor from the ledger, and keeps the
## `Actor.traits` mirror in step with it.
##
## **Derived, never stored.** The ledger is the only truth; this class is the
## one place that translates it into stat modifiers and trait ids. That is what
## makes the earn-only invariant safe to ship: a save can be restored, replayed
## or normalized and the projection is simply recomputed, so it can never drift
## from the ledger or double-count.
##
## A second, parallel stat fold is forbidden (ADR 0065). Fate reuses
## `actor.stats.add_modifier` exactly as an authored trait does, because the
## moment a fate gets its own composer, every stat aggregation rule has to be
## taught about it twice.

## The module's signal bus. It lives on the projection rather than the facade
## because a GDScript signal belongs to an instance and a facade is a namespace
## of statics: `DestinyApi` exposes twelve methods already, and a thirteenth for
## a bus would breach the facade cap for no gain. Anything that needs to observe
## fate connects here, and nothing outside the module emits through it.
static var bus: DestinyEvents = null


static func events() -> DestinyEvents:
	if bus == null:
		bus = DestinyEvents.new()
	return bus


## Apply the whole ledger to `actor`. Idempotent by construction: every fate
## contribution is stripped first, then rebuilt. Calling this after no change is
## free of consequence — it produces the same modifier stack.
static func apply(actor: Actor, ledger: Dictionary) -> void:
	if actor == null:
		return
	strip(actor)
	for fate_id in DestinyState.fate_ids(ledger):
		var def := FateCatalog.instance().fate_definition(fate_id)
		if def == null or not def.has_modifiers():
			continue
		for modifier in def.build_modifiers():
			actor.stats.add_modifier(modifier)
	# The trait mirror covers EVERY held fate, including the pure-narrative ones
	# that contribute no numbers: a fate whose whole purpose is to gate story is
	# exactly the one most likely to be tested through `has_trait`, so keying the
	# mirror off `has_modifiers()` would drop the fates that matter most here.
	for fate_id in DestinyState.fate_ids(ledger):
		actor.traits.add(DestinyState.trait_for(fate_id))
	for destiny_id in DestinyState.destiny_ids(ledger):
		actor.traits.add(DestinyState.trait_for(destiny_id))


## Remove every contribution this module owns, from both the stat stack and the
## trait mirror. Used only by `apply`, so a partial projection can never be left
## behind.
static func strip(actor: Actor) -> void:
	if actor == null:
		return
	for fate_id in FateCatalog.instance().fate_ids():
		actor.stats.remove_modifiers_from(DestinyState.source_for(fate_id))
		actor.traits.remove(DestinyState.trait_for(fate_id))
	for destiny_id in FateCatalog.instance().destiny_ids():
		actor.stats.remove_modifiers_from(DestinyState.source_for(destiny_id))
		actor.traits.remove(DestinyState.trait_for(destiny_id))


## What this module contributes to `stat_id`, read from the modifier stack
## rather than recomputed. Reading the stack proves the projection actually
## landed instead of trusting the ledger.
##
## Returned as `{"flat": float, "percent": float}` because a magnitude and a
## rate are different kinds of number: `3.0` flat and `0.3` percent both mean
## something real about a stat, and adding them into one total produces a number
## that means neither (ADR 0065 keeps fate on the single modifier pipeline,
## where `derived = (base + flat) * (1 + percent)` keeps them apart).
static func contribution(actor: Actor, stat_id: StringName) -> Dictionary:
	var out := {"flat": 0.0, "percent": 0.0}
	if actor == null:
		return out
	for modifier in actor.stats._modifiers:
		if modifier.stat != stat_id or not DestinyState.is_own_source(modifier.source):
			continue
		if modifier.op == Stat.Op.PERCENT:
			out["percent"] = float(out["percent"]) + modifier.value
		else:
			out["flat"] = float(out["flat"]) + modifier.value
	return out


## The number of modifiers this module currently holds on `actor`. The
## idempotence check: projecting twice must leave this unchanged.
static func modifier_count(actor: Actor) -> int:
	if actor == null:
		return 0
	var total := 0
	for modifier in actor.stats._modifiers:
		if DestinyState.is_own_source(modifier.source):
			total += 1
	return total
