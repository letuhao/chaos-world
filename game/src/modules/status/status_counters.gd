class_name StatusCounters
extends RefCounted

## One actor-scoped counter store with TWO key spaces (ADR 0902, P6=C): grant-keyed
## (`<grant>|<scope>`, the Keepverse `RecordCounterHit` shape) and per-instance (the
## handle `StatusRegistry` mints — identity fixed by the stacking semantics, so two
## `coexist` instances of one id count independently).
##
## ## The semantics are Keepverse's, measured
##
## `n += hits`; the call answers `true` when `n >= every_hits` crossing, and
## - with `reset_on_burst` set, the RESIDUAL is kept (`n % every_hits`), because a
##   coalesced record must not eat progress toward the next burst;
## - otherwise the running total is kept, so a latch that has crossed its threshold
##   answers `true` on every later hit until it is cleared.
## `hits` is the coalesced count: N merged blows advance by N, ONE burst per call.
##
## ## Why this is NOT `Actor.module_data`
##
## The same reason `StatusRuntime` is not: `Actor.to_dict` serializes `module_data`
## verbatim, and counters are combat-runtime state (ADR 0902 decision 8, T13 — they
## are expected TRANSIENT). A static table keyed by actor instance id keeps them out
## of every save, and the weak handle keeps a discarded actor from pinning its counts.

const GRANT_SEPARATOR := "|"
const SPACE_GRANT := "grant"
const SPACE_INSTANCE := "instance"

static var _by_actor: Dictionary = {}


## The grant key space's ONE spelling: `<grant>|<scope>`, both trimmed, so a caller
## that passes padded ids reaches the same record as one that does not.
static func grant_key(grant_id: StringName, scope_key: StringName) -> String:
	return (
		"%s%s%s"
		% [
			String(grant_id).strip_edges(),
			GRANT_SEPARATOR,
			String(scope_key).strip_edges(),
		]
	)


## Advance one counter by `hits` COUNTED units (ADR 0902, P6=C) — the hit-count
## source. Delegates to [method advance], the ONE accumulator both sources share.
static func record(
	actor: Actor, key: Variant, every_hits: int, reset_on_burst: bool, hits: int = 1
) -> bool:
	return advance(actor, key, float(every_hits), reset_on_burst, float(hits))


## Advance one accumulator by an AMOUNT — the value-event source (ADR 0902, P7), and
## the one implementation both sources call. Answers whether the threshold was reached
## on THIS call: `reset_on_burst` keeps the residual (`n` modulo `every`), otherwise
## the running total is kept and every later call past the threshold answers true.
static func advance(
	actor: Actor, key: Variant, every: float, reset_on_burst: bool, amount: float
) -> bool:
	if actor == null or every <= 0.0 or amount <= 0.0:
		return false
	var space: Variant = _space_for(actor, key)
	if not (space is Dictionary):
		return false
	var stored := space as Dictionary
	var n := float(stored.get(key, 0)) + amount
	if n >= every:
		stored[key] = fmod(n, every) if reset_on_burst else n
		return true
	stored[key] = n
	return false


static func value(actor: Actor, key: Variant) -> int:
	var space: Variant = _space_for(actor, key)
	return 0 if not (space is Dictionary) else int((space as Dictionary).get(key, 0))


## Both key spaces as copies: `{grant: {key: n}, instance: {id: n}}`. Primitives
## only, so a screen and a test read the same shape (ADR 0902, P6/P13 readback).
static func snapshot(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var spaces := _store(actor)
	return {
		SPACE_GRANT: (spaces[SPACE_GRANT] as Dictionary).duplicate(),
		SPACE_INSTANCE: (spaces[SPACE_INSTANCE] as Dictionary).duplicate(),
	}


## Drop the instance-space counters of instances that left the actor. Called from
## the module's own prune, so an expired or replaced instance cannot leave a count
## behind for its successor to inherit.
static func drop_instances(actor: Actor, gone: Array) -> void:
	if actor == null or gone.is_empty():
		return
	var spaces: Variant = _existing_spaces(actor)
	if not (spaces is Dictionary):
		return
	var space := (spaces as Dictionary)[SPACE_INSTANCE] as Dictionary
	# The `for` is over the CALLER's snapshot array and the body only erases:
	# the bound cannot grow under the loop (INC-0002's shape is impossible here).
	for instance_id in gone:
		space.erase(int(instance_id))


## Drop every grant-space counter a grant wrote — the Keepverse `ClearGrant`'s
## prefix sweep (`<grant>|`), so clearing one grant can never
## reach a sibling grant whose id shares a prefix only in appearance.
static func clear_grant(actor: Actor, grant_id: StringName) -> void:
	if actor == null or grant_id == &"":
		return
	var spaces: Variant = _existing_spaces(actor)
	if not (spaces is Dictionary):
		return
	var space := (spaces as Dictionary)[SPACE_GRANT] as Dictionary
	var prefix := String(grant_id).strip_edges() + GRANT_SEPARATOR
	# Prefix sweep over a snapshot of the keys; the body only erases.
	for key in space.keys():
		if String(key).begins_with(prefix):
			space.erase(key)


## Drop one actor's counters. `StatusApi.withdraw` calls this when the host leaves.
static func forget(actor: Actor) -> void:
	if actor != null:
		_by_actor.erase(actor.get_instance_id())


## The store `actor` owns, created on first use. The payload holds only keys and
## counts, and the actor is held as a `WeakRef`, exactly as `StatusRuntime` does it.
static func _store(actor: Actor) -> Dictionary:
	var key := actor.get_instance_id()
	var existing: Variant = _by_actor.get(key)
	if existing is Dictionary:
		var spaces: Variant = (existing as Dictionary).get("spaces")
		if spaces is Dictionary:
			return spaces as Dictionary
	var fresh := {SPACE_GRANT: {}, SPACE_INSTANCE: {}}
	_by_actor[key] = {"actor": weakref(actor), "spaces": fresh}
	return fresh


## The store `actor` ALREADY owns, or null — the read and sweep paths peek through
## this so a prune or a clear for an actor that never counted allocates nothing.
static func _existing_spaces(actor: Actor) -> Variant:
	if actor == null:
		return null
	var existing: Variant = _by_actor.get(actor.get_instance_id())
	if not (existing is Dictionary):
		return null
	var spaces: Variant = (existing as Dictionary).get("spaces")
	return spaces if spaces is Dictionary else null


## The key space `key` addresses, or null for an empty or unaddressable key.
static func _space_for(actor: Actor, key: Variant) -> Variant:
	if actor == null:
		return null
	var spaces := _store(actor)
	if key is String or key is StringName:
		if String(key).strip_edges().is_empty():
			return null
		return spaces[SPACE_GRANT]
	if key is int:
		return spaces[SPACE_INSTANCE]
	return null
