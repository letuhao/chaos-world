class_name SettlementBridge
extends RefCounted

## The injected view of a settlement for the UI program (ADR 0209). The install seam for
## `DomainSettlement`, which ADR 0163 designed and BL-0847 found never CALLED.
##
## ## Why a second bridge rather than a growing `DomainBridge`
##
## Two reasons, and both are the repo's rules rather than taste:
##
##  - `DomainBridge` is the domain screen's seam and every verb on it takes an `actor`
##    first. A settlement readout is about ONE ROOM of a room the player is LOOKING at,
##    so its verb is keyed on `(actor, room_id)`. Appending a `resident(actor, room_id)`
##    pair to the existing shape would make a second argument convention on one bridge.
##  - A screen must be able to reach the settlement without the bridge the explore
##    screen holds: the settlement panel is a ROOM surface, and the explore screen is
##    the only page that shows rooms today, but binding the seam to the page would make
##    the panel ship-but-dead the moment a second room surface appeared.
##
## ## Why a shared static holder rather than a required injection
##
## The `NpcApi.set_minter` idiom `DomainSpawner.set_minter` already uses: whoever mounts
## the panel adopts the bridge, and a screen bound by a route AND a screen bound by a test
## both get it. An unwired one reads as "not available" rather than as a failure, which
## is what lets the panel DISABLE itself instead of half-answering.
##
## `domain` is not in `rules.UI_MODULES` and `app/` is a private unit, so this file names
## NO domain type at all — not `DomainSettlement`, not `DomainApi`, not `SectApi`. The
## composition root supplies both Callables and this seam stays a plain dictionary door.

## The bridge every screen adopts when nobody handed it one. A `static var`, so the seam
## is available to whoever mounts the panel without every caller remembering to pass it
## down — which is strictly more robust than the alternative, where a screen bound by one
## door and a screen bound by another could end up half-wired.
static var shared_bridge: SettlementBridge = null

## `DomainSettlement.summary(actor, room_id)` -> Dictionary: what the room holds, and
## the named refusal when it names nothing or names something that does not resolve.
## Named `read_settlement` rather than `summary` because a `summary` field beside a
## `summary()` method is a name collision waiting to be read wrong, and the repo's whole
## convention is that `summary()` is the testable surface.
var read_settlement: Callable
## `DomainSettlement.residents(actor, room_id)` -> Dictionary: who stands there, from
## the room's own spawn refs.
var read_residents: Callable


## Return the shared bridge, creating it on first use. Idempotent and null-tolerant, so a
## caller never has to ask whether one exists before adopting it.
static func shared() -> SettlementBridge:
	if shared_bridge == null:
		shared_bridge = SettlementBridge.new()
	return shared_bridge


## Whether a verb is wired. A panel reads this before it offers a readout, so a
## composition root that never installed the seam disables the surface rather than
## half-answering it.
func has(action: StringName) -> bool:
	var callable := _callable_for(action)
	return callable.is_valid()


## Invoke `action`, returning `{}` when the callable is not wired or does not answer a
## dictionary. A panel never null-checks the bridge.
func call_action(action: StringName, args: Array = []) -> Dictionary:
	var callable := _callable_for(action)
	if not callable.is_valid():
		return {}
	var result: Variant = callable.bindv(args).call()
	return result as Dictionary if result is Dictionary else {}


## Everything this bridge can reach, as primitives, so a test can assert the WIRING
## itself rather than inferring it from a readout that quietly showed nothing.
func summary() -> Dictionary:
	var wired: Array = []
	for action in _action_ids():
		if has(StringName(action)):
			wired.append(action)
	return {
		"actions": _action_ids(),
		"wired": wired,
		"ready": wired.size() == _action_ids().size(),
	}


## What the SELECTED room is, as the ONE dictionary the panel takes: the settlement's
## own answer and the room's residents, side by side. `{}` outside a run — the empty
## vocabulary, so a headless test drives the panel through this door like any other caller.
##
## Both verbs are read even when the first refuses: a castle with no sect ref still has
## residents, and `DomainSettlement.residents` says so itself by never consulting the
## institution lookup. Collapsing the two would make "a building nobody has named" look
## like "a building with nobody in it".
##
## The three refusals are passed through UNTOUCHED. `ok: false` with `reason` named is
## the module's vocabulary (ADR 0083) and this seam has no wording of its own to add.
func read_room(actor: Actor, room_id: StringName) -> Dictionary:
	if actor == null or room_id.is_empty():
		return {}
	var about := call_action(&"read_settlement", [actor, room_id])
	if about.is_empty():
		return {}
	var who := call_action(&"read_residents", [actor, room_id])
	about["residents"] = who.get("residents", [])
	about["resident_count"] = int(who.get("count", 0))
	about["residents_truncated"] = bool(who.get("truncated", false))
	return about


func _callable_for(action: StringName) -> Callable:
	return _actions().get(String(action), Callable())


func _action_ids() -> Array:
	return ["read_settlement", "read_residents"]


func _actions() -> Dictionary:
	return {"read_settlement": read_settlement, "read_residents": read_residents}
